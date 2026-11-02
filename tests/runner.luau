--[[
	Test runner for Lune (https://lune-org.github.io/docs): `lune run tests/runner`.

	Loads the game's ModuleScripts straight from src/ with a fake `game`,
	`script` and `require` that resolve Roblox instance paths to files, and
	Lune's Roblox datatypes (Vector3, CFrame, Instance, ...). Modules that need
	the live engine (events, physics, pathfinding) run in a headless world:
	`local world = headless()` (see tests/headless/Engine.luau).

	  lune run tests/runner                 all specs
	  lune run tests/runner Loot            only spec files whose name contains "Loot"
	  lune run tests/runner --coverage      also write coverage/ (see tests/coverage.luau)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Coverage = require("./coverage")

local coverageOn = false
local filter: string? = nil
for _, arg in process.args do
	if arg == "--coverage" then
		coverageOn = true
	else
		filter = arg
	end
end
if coverageOn and not Coverage.available() then
	print("Coverage needs the instrumenter: cargo build --release --manifest-path tools/luau-cov/Cargo.toml")
	process.exit(1)
end

-- Instance path -> folder on disk (mirrors default.project.json).
local ROOTS = {
	ReplicatedStorage = { Shared = "src/shared" },
	ServerScriptService = { Server = "src/server" },
}

-- Deterministic stand-in for Roblox's Random.
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	return setmetatable({ state = (seed or 12345) % 2147483647 }, Random)
end
function Random:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function Random:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min then
		return min + (max - min) * r
	end
	return r
end
function Random:NextInteger(min: number, max: number): number
	return math.min(max, min + math.floor(self:_next() * (max - min + 1)))
end

local loadModule

-- A fake Instance path: indexing builds child paths; require() resolves them.
local PathMeta = {}
local function path(parts: { string })
	return setmetatable({ __parts = parts }, PathMeta)
end
PathMeta.__index = function(self, key)
	local parts = table.clone(rawget(self, "__parts"))
	if key == "Parent" then
		table.remove(parts)
	else
		table.insert(parts, key)
	end
	return path(parts)
end

local function fileFor(parts: { string }): string
	local folder = ROOTS[parts[1]] and ROOTS[parts[1]][parts[2]]
	assert(folder and #parts >= 3, "can't resolve require path " .. table.concat(parts, "."))
	-- Deeper paths are subfolders; a folder module is its init.luau (as in Rojo).
	local base = folder .. "/" .. table.concat(parts, "/", 3)
	for _, suffix in { ".luau", ".server.luau", ".client.luau", "/init.luau" } do
		local file = base .. suffix
		if fs.isFile(file) then
			return file
		end
	end
	error("no file for " .. table.concat(parts, "."))
end

local workspaceInstance = roblox.Instance.new("Model")
workspaceInstance.Name = "Workspace"

-- Services backed by src/ folders resolve to require paths. Any other service
-- (ServerStorage, ...) is a real, empty Lune Instance that specs can fill
-- through the `services` helper; it is emptied before each spec file.
local services: { [string]: any } = {}
local function resetServices()
	for _, service in services do
		service:ClearAllChildren()
	end
end

local fakeGame = {
	GetService = function(_, name: string)
		if ROOTS[name] then
			return path({ name })
		end
		if not services[name] then
			local service = roblox.Instance.new("Folder")
			service.Name = name
			services[name] = service
		end
		return services[name]
	end,
}

local builtins = {
	math = math,
	string = string,
	table = table,
	buffer = buffer,
	bit32 = bit32,
	utf8 = utf8,
	coroutine = coroutine,
	os = os,
	assert = assert,
	error = error,
	ipairs = ipairs,
	pairs = pairs,
	next = next,
	pcall = pcall,
	xpcall = xpcall,
	print = print,
	warn = function(...)
		print("[warn]", ...)
	end,
	select = select,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	typeof = typeof,
	rawget = rawget,
	rawset = rawset,
	rawequal = rawequal,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	unpack = table.unpack,
	task = task,
	Random = Random,
	game = fakeGame,
	workspace = workspaceInstance,
}
for _, name in
	{
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim",
		"UDim2",
		"Instance",
		"Enum",
	}
do
	builtins[name] = (roblox :: any)[name]
end

local cache = {}

function loadModule(parts: { string })
	local file = fileFor(parts)
	if cache[file] == nil then
		-- Globals are copied in (not __index): Luau resolves imports with raw lookups.
		local env = table.clone(builtins)
		env.script = path(parts)
		env.require = function(target)
			return loadModule(rawget(target, "__parts"))
		end
		local source = if coverageOn then Coverage.instrument(file, env) else fs.readFile(file)
		local chunk = luau.load(source, { debugName = file, environment = env })
		cache[file] = chunk()
	end
	return cache[file]
end

----------------------------------------------------------------------------
-- Headless worlds: the game's modules on tests/headless/Engine.luau, so code
-- that needs the live engine (Run, Krampus, Lobby, Hud...) runs here too.
-- Each world has its own clock, Instances, players and module cache.
----------------------------------------------------------------------------

local Engine = require("./headless/Engine")

-- Rojo's mapping from default.project.json: Instance path -> folder.
local MOUNTS = {
	{ service = "ReplicatedStorage", name = "Shared", dir = "src/shared" },
	{ service = "ServerScriptService", name = "Server", dir = "src/server" },
	{ service = "StarterPlayer", name = "Client", dir = "src/client", under = "StarterPlayerScripts" },
}

local sourceCache: { [string]: string } = {}

local function headless()
	local engine = Engine.new()
	local world = { engine = engine, Engine = Engine }
	local moduleCache = {}

	-- Lune's fs and process calls yield, which would suspend game threads, so
	-- every source is read (and instrumented) before the world runs.
	local function preload(file: string)
		if not sourceCache[file] then
			sourceCache[file] = fs.readFile(file)
		end
		if coverageOn then
			Coverage.prepare(file)
		end
	end

	-- Rojo's rules: init.luau makes its folder a ModuleScript, *.server.luau a
	-- Script, *.client.luau a LocalScript, any other .luau a ModuleScript.
	local function mount(parent, name: string, dir: string)
		local initFile = dir .. "/init.luau"
		local node = engine.Instance.new(if fs.isFile(initFile) then "ModuleScript" else "Folder")
		node.Name = name
		if fs.isFile(initFile) then
			rawset(node, "_file", initFile)
			preload(initFile)
		end
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local file = dir .. "/" .. entry
			if fs.isDir(file) then
				mount(node, entry, file)
			elseif entry ~= "init.luau" then
				local base, kind = string.match(entry, "^(.-)%.(%a+)%.luau$")
				local className = if kind == "server"
					then "Script"
					elseif kind == "client" then "LocalScript"
					else nil
				if not className then
					base = string.match(entry, "^(.-)%.luau$")
					className = "ModuleScript"
				end
				if base then
					local script = engine.Instance.new(className)
					script.Name = base
					rawset(script, "_file", file)
					script.Parent = node
					preload(file)
				end
			end
		end
		node.Parent = parent
		return node
	end
	for _, m in MOUNTS do
		local parent = engine:service(m.service)
		if m.under then
			local holder = parent:FindFirstChild(m.under) or engine.Instance.new("Folder")
			holder.Name = m.under
			holder.Parent = parent
			parent = holder
		end
		mount(parent, m.name, m.dir)
	end

	local env0 = table.clone(builtins)
	env0.game = engine.DataModel
	env0.workspace = engine.workspace
	env0.Instance = engine.Instance
	env0.task = engine.task
	env0.os = engine.os
	env0.typeof = Engine.typeof
	-- math.random (Krampus's wander) is seeded per world, so runs repeat exactly.
	local worldRandom = Random.new(1)
	env0.math = table.clone(math)
	env0.math.random = function(a: number?, b: number?)
		if a == nil then
			return worldRandom:NextNumber()
		elseif b == nil then
			return worldRandom:NextInteger(1, a)
		end
		return worldRandom:NextInteger(a, b :: number)
	end
	env0.math.randomseed = function() end
	env0.warn = function(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		table.insert(engine.warnings, table.concat(parts, " "))
	end
	env0.print = function() end -- keep test output quiet

	local function chunkFor(script)
		local file = rawget(script, "_file")
		assert(file, "not a script from src/: " .. tostring(script))
		local env = table.clone(env0)
		env.script = script
		env.require = world.require
		local source = if coverageOn then Coverage.instrument(file, env) else sourceCache[file]
		return luau.load(source, { debugName = file, environment = env })
	end

	function world.require(script)
		if moduleCache[script] == nil then
			moduleCache[script] = chunkFor(script)()
		end
		return moduleCache[script]
	end

	-- Instance path from the DataModel, e.g. "ServerScriptService.Server.Run".
	function world.find(dotted: string)
		local parts = string.split(dotted, ".")
		local node = engine:service(parts[1])
		for i = 2, #parts do
			node = node:FindFirstChild(parts[i])
			assert(node, "no " .. dotted .. " in the headless world")
		end
		return node
	end

	function world.load(dotted: string)
		return world.require(world.find(dotted))
	end

	-- Runs a Script or LocalScript (e.g. Main.server, Hud.client) in a game thread.
	function world.runScript(dotted: string)
		local chunk = chunkFor(world.find(dotted))
		engine:spawn(chunk)
	end

	function world.run(fn, options)
		engine:run(fn, options)
	end

	-- Inside world.run: let the game run for `seconds` of virtual time.
	-- (The spec's own `task` is Lune's, so use this, not task.wait.)
	function world.wait(seconds: number?)
		return engine:wait(seconds or 0)
	end

	return world
end

----------------------------------------------------------------------------
-- Test API, a Jest-compatible subset so specs can move to Jest Roblox
-- unchanged: describe / it (or test) / beforeEach / afterEach, and expect()
-- with toBe, toEqual, toBeTruthy, toBeFalsy, toBeNil, toBeNear,
-- toBeLessThan, toBeGreaterThan, toBeGreaterThanOrEqual, toContain,
-- toHaveLength, toThrow, each negatable with expect(x).never.
----------------------------------------------------------------------------

local results = { passed = 0, failed = {} }
local currentFile = ""

local function fmt(v): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

local function deepEqual(a, b): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function makeMatchers(actual, negate: boolean)
	local e = {}
	local function check(pass: boolean, message: string)
		if pass == negate then
			error((if negate then "not: " else "") .. message, 3)
		end
	end
	function e.toBe(expected)
		check(actual == expected, "expected " .. fmt(expected) .. ", got " .. fmt(actual))
	end
	function e.toEqual(expected)
		check(deepEqual(actual, expected), "expected tables to be deeply equal")
	end
	function e.toBeTruthy()
		check(not not actual, "expected a truthy value, got " .. fmt(actual))
	end
	function e.toBeFalsy()
		check(not actual, "expected a falsy value, got " .. fmt(actual))
	end
	function e.toBeNil()
		check(actual == nil, "expected nil, got " .. fmt(actual))
	end
	function e.toBeNear(expected: number, tolerance: number?)
		check(
			math.abs(actual - expected) <= (tolerance or 1e-6),
			"expected about " .. fmt(expected) .. ", got " .. fmt(actual)
		)
	end
	function e.toBeLessThan(limit: number)
		check(actual < limit, "expected < " .. fmt(limit) .. ", got " .. fmt(actual))
	end
	function e.toBeGreaterThan(limit: number)
		check(actual > limit, "expected > " .. fmt(limit) .. ", got " .. fmt(actual))
	end
	function e.toBeGreaterThanOrEqual(limit: number)
		check(actual >= limit, "expected >= " .. fmt(limit) .. ", got " .. fmt(actual))
	end
	function e.toBeLessThanOrEqual(limit: number)
		check(actual <= limit, "expected <= " .. fmt(limit) .. ", got " .. fmt(actual))
	end
	function e.toContain(item)
		local found = false
		if type(actual) == "string" then
			found = string.find(actual, item, 1, true) ~= nil
		else
			for _, v in actual do
				if v == item then
					found = true
					break
				end
			end
		end
		check(found, "expected to contain " .. fmt(item))
	end
	function e.toHaveLength(n: number)
		check(#actual == n, "expected length " .. n .. ", got " .. #actual)
	end
	function e.toThrow(pattern: string?)
		local ok, err = pcall(actual)
		local pass = not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil)
		check(
			pass,
			"expected to throw" .. (if pattern then " " .. fmt(pattern) else "") .. ", got " .. fmt(err)
		)
	end
	return e
end

local function expect(actual)
	local e = makeMatchers(actual, false)
	e.never = makeMatchers(actual, true)
	return e
end

-- describe() scopes: names and before/after hooks nest.
local scopes = { { name = nil, before = {}, after = {} } }

local function runHooks(kind: string, reverse: boolean)
	local from, to, step = 1, #scopes, 1
	if reverse then
		from, to, step = #scopes, 1, -1
	end
	for i = from, to, step do
		for _, hook in scopes[i][kind] do
			hook()
		end
	end
end

local function fullName(name: string): string
	local parts = {}
	for _, scope in scopes do
		if scope.name then
			table.insert(parts, scope.name)
		end
	end
	table.insert(parts, name)
	return table.concat(parts, " > ")
end

local function test(name: string, fn: () -> ())
	local ok, err = pcall(function()
		runHooks("before", false)
		local passed, testErr = pcall(fn)
		runHooks("after", true)
		if not passed then
			error(testErr, 0)
		end
	end)
	if ok then
		results.passed += 1
	else
		table.insert(results.failed, currentFile .. " > " .. fullName(name) .. "\n    " .. tostring(err))
	end
end

local function describe(name: string, fn: () -> ())
	table.insert(scopes, { name = name, before = {}, after = {} })
	local ok, err = pcall(fn)
	table.remove(scopes)
	if not ok then
		table.insert(
			results.failed,
			currentFile .. " > " .. fullName(name) .. " (describe)\n    " .. tostring(err)
		)
	end
end

local function beforeEach(fn: () -> ())
	table.insert(scopes[#scopes].before, fn)
end

local function afterEach(fn: () -> ())
	table.insert(scopes[#scopes].after, fn)
end

-- Loads a module by its Roblox path, e.g. load("ServerScriptService.Server.Loot").
local function load(dotted: string)
	return loadModule(string.split(dotted, "."))
end

local helpers = {
	test = test,
	it = test,
	describe = describe,
	beforeEach = beforeEach,
	afterEach = afterEach,
	expect = expect,
	load = load,
	Random = Random,
	roblox = roblox,
	-- services.ServerStorage etc.: the same Instances modules get from game:GetService.
	services = setmetatable({}, {
		__index = function(_, name)
			return fakeGame:GetService(name)
		end,
	}),
	headless = headless,
	newFolder = function()
		return roblox.Instance.new("Folder")
	end,
}

local files = {}
for _, dir in { "tests/unit", "tests/integration", "tests/regression", "tests/smoke" } do
	for _, name in fs.readDir(dir) do
		if string.find(name, "%.spec%.luau$") and (not filter or string.find(name, filter, 1, true)) then
			table.insert(files, dir .. "/" .. name)
		end
	end
end
table.sort(files)

for _, file in files do
	currentFile = file
	resetServices()
	local env = table.clone(builtins)
	for k, v in helpers do
		env[k] = v
	end
	local ok, err = pcall(function()
		luau.load(fs.readFile(file), { debugName = file, environment = env })()
	end)
	if not ok then
		table.insert(results.failed, file .. " (failed to load)\n    " .. tostring(err))
	end
end

print(string.format("%d passed, %d failed (%d files)", results.passed, #results.failed, #files))
for _, failure in results.failed do
	print("FAIL " .. failure)
end

if coverageOn then
	local ratio = Coverage.report("coverage")
	if ratio < Coverage.FLOOR then
		print(string.format("warning: line coverage is below the %d%% floor", Coverage.FLOOR * 100))
	end
end

process.exit(if #results.failed == 0 then 0 else 1)
