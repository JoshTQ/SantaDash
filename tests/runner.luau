--[[
	Test runner for Lune (https://lune-org.github.io/docs): `lune run tests/runner`.

	Loads the game's ModuleScripts straight from src/ with a fake `game`,
	`script` and `require` that resolve Roblox instance paths to files, and
	Lune's Roblox datatypes (Vector3, CFrame, Instance, ...). Modules that need
	the live engine (events, physics, pathfinding) are tested in Studio instead.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

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
	assert(folder and #parts == 3, "can't resolve require path " .. table.concat(parts, "."))
	for _, suffix in { ".luau", ".server.luau", ".client.luau" } do
		local file = folder .. "/" .. parts[3] .. suffix
		if fs.isFile(file) then
			return file
		end
	end
	error("no file for " .. table.concat(parts, "."))
end

local workspaceInstance = roblox.Instance.new("Model")
workspaceInstance.Name = "Workspace"

local fakeGame = {
	GetService = function(_, name: string)
		return path({ name })
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
		local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
		cache[file] = chunk()
	end
	return cache[file]
end

----------------------------------------------------------------------------
-- Tiny test API: test(name, fn), expect(value).toBe / toEqual / toBeNear ...
----------------------------------------------------------------------------

local results = { passed = 0, failed = {} }
local currentFile = ""

local function fmt(v): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error("expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error("expected a truthy value, got " .. fmt(actual), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error("expected a falsy value, got " .. fmt(actual), 2)
		end
	end
	function e.toBeNear(expected: number, tolerance: number?)
		if math.abs(actual - expected) > (tolerance or 1e-6) then
			error("expected about " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeLessThan(limit: number)
		if not (actual < limit) then
			error("expected < " .. fmt(limit) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeGreaterThan(limit: number)
		if not (actual > limit) then
			error("expected > " .. fmt(limit) .. ", got " .. fmt(actual), 2)
		end
	end
	return e
end

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		table.insert(results.failed, currentFile .. " > " .. name .. "\n    " .. tostring(err))
	end
end

-- Loads a module by its Roblox path, e.g. load("ServerScriptService.Server.Loot").
local function load(dotted: string)
	return loadModule(string.split(dotted, "."))
end

local helpers = {
	test = test,
	expect = expect,
	load = load,
	Random = Random,
	roblox = roblox,
	newFolder = function()
		return roblox.Instance.new("Folder")
	end,
}

local filter = process.args[1]
local files = {}
for _, dir in { "tests/unit", "tests/integration" } do
	for _, name in fs.readDir(dir) do
		if string.find(name, "%.spec%.luau$") and (not filter or string.find(name, filter, 1, true)) then
			table.insert(files, dir .. "/" .. name)
		end
	end
end
table.sort(files)

for _, file in files do
	currentFile = file
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
process.exit(if #results.failed == 0 then 0 else 1)
