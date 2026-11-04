--[[
	Builds Sleigh Heist for one experience and publishes it to both of its
	places (Lobby and Run) through Roblox Open Cloud.

	  lune run tools/deploy <environment> [--dry-run] [--no-smoke] [--restart]

	  <environment>   a label for logs and BuildInfo: staging or production
	  --dry-run       build and check only; nothing is uploaded
	  --no-smoke      skip the pre-publish smoke test in a real Roblox server
	  --restart       after publishing, ask Roblox to restart the
	                  experience's servers so nobody stays on the old build

	Steps:
	1. Copies src/ to build/deploy-src/ and stamps this experience's place ids
	   into Config.Places (the repo keeps 0 = single-server/Studio mode), plus a
	   Shared.BuildInfo module (commit, environment, time).
	2. Builds build/SleighHeist-<environment>.rbxl from deploy.project.json
	   (approved models come from assets/models/*.rbxm into ServerStorage.Assets).
	3. Refuses instances Open Cloud can't publish (SurfaceAppearance, unions,
	   Editable*, BaseWrap): those places must be published from Studio.
	4. Smoke test: saves the file as an unpublished version of the Lobby place
	   and, in a real Roblox server, requires every server and shared module and
	   checks the stamped place ids. Players never see this version.
	5. Publishes the Run place first, then the Lobby place, so new lobbies only
	   ever teleport crews into the new run build.

	Environment:
	  ROBLOX_API_KEY   Open Cloud key: universe-places (Write) and
	                   luau-execution-sessions (Write) on this experience;
	                   universe (Write) too for --restart
	  UNIVERSE_ID      the experience's universe id
	  LOBBY_PLACE_ID   its start place (the Sleigh Station lobby)
	  RUN_PLACE_ID     its run place
	  GITHUB_SHA, GITHUB_STEP_SUMMARY   filled in by GitHub Actions
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local API = process.env.ROBLOX_API_BASE or "https://apis.roblox.com" -- override only for tests
local SRC = "src"
local OUT_SRC = "build/deploy-src"
local POLL_SECONDS = 3
local GIVE_UP_SECONDS = 6 * 60 -- Luau execution tasks time out at 5 minutes

-- Open Cloud refuses places that contain these (they must be published from
-- Studio). Import Meshy models with a colour texture only, no PBR, to avoid
-- SurfaceAppearance.
local UNPUBLISHABLE = {
	"SurfaceAppearance",
	"PartOperation",
	"UnionOperation",
	"NegateOperation",
	"IntersectOperation",
	"EditableImage",
	"EditableMesh",
	"BaseWrap",
	"WrapLayer",
	"WrapTarget",
}

local args = process.args
local environment = args[1]
local dryRun = table.find(args, "--dry-run") ~= nil
local smoke = table.find(args, "--no-smoke") == nil
local restart = table.find(args, "--restart") ~= nil

if not environment or string.sub(environment, 1, 2) == "--" then
	print("usage: lune run tools/deploy <staging|production> [--dry-run] [--no-smoke] [--restart]")
	process.exit(1)
end

local env = process.env
local key = env.ROBLOX_API_KEY
local summaryLines: { string } = {}

local function fail(message: string): never
	print("::error::" .. message)
	process.exit(1)
	error(message) -- unreachable; keeps the type checker happy
end

local function id(name: string): string
	local value = env[name]
	if dryRun and (value == nil or value == "") then
		return "0"
	end
	if value == nil or not string.match(value, "^%d+$") or value == "0" then
		fail(name .. " must be set to a numeric id (see docs/DEPLOY.md)")
	end
	return value :: string
end

local universe = id("UNIVERSE_ID")
local lobby = id("LOBBY_PLACE_ID")
local run = id("RUN_PLACE_ID")
if not dryRun and (key == nil or key == "") then
	fail("ROBLOX_API_KEY is not set (see docs/DEPLOY.md)")
end
if not dryRun and lobby == run then
	fail("LOBBY_PLACE_ID and RUN_PLACE_ID must be two different places")
end

local commit = env.GITHUB_SHA or "local"
local shortCommit = string.sub(commit, 1, 7)

-- 1. Copy src/ and stamp the place ids ------------------------------------

local function copy(from: string, to: string)
	fs.writeDir(to)
	for _, name in fs.readDir(from) do
		local source, target = from .. "/" .. name, to .. "/" .. name
		if fs.isDir(source) then
			copy(source, target)
		else
			fs.writeFile(target, fs.readFile(source))
		end
	end
end

-- Replaces the numbers in `Config.Places = { Lobby = 0, Run = 0, ... }`
-- and fails loudly if that block ever changes shape.
local function stampPlaces(source: string, lobbyId: string, runId: string): string
	local first, last = string.find(source, "Config%.Places%s*=%s*%b{}")
	if not first then
		fail("Couldn't find `Config.Places = { ... }` in src/shared/Config.luau")
	end
	local block = string.sub(source, first :: number, last :: number)
	local lobbyCount, runCount
	block, lobbyCount = string.gsub(block, "(\n%s*Lobby%s*=%s*)%d+", "%1" .. lobbyId, 1)
	block, runCount = string.gsub(block, "(\n%s*Run%s*=%s*)%d+", "%1" .. runId, 1)
	if lobbyCount ~= 1 or runCount ~= 1 then
		fail("Config.Places needs numeric `Lobby = ...` and `Run = ...` fields")
	end
	return string.sub(source, 1, (first :: number) - 1) .. block .. string.sub(source, (last :: number) + 1)
end

if fs.isDir(OUT_SRC) then
	fs.removeDir(OUT_SRC)
end
copy(SRC, OUT_SRC)

local configPath = OUT_SRC .. "/shared/Config.luau"
fs.writeFile(configPath, stampPlaces(fs.readFile(configPath), lobby, run))

local builtAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
fs.writeFile(
	OUT_SRC .. "/shared/BuildInfo.luau",
	string.format(
		"-- Generated by tools/deploy.luau; not in the repo.\nreturn table.freeze({\n"
			.. "\tCommit = %q,\n\tEnvironment = %q,\n\tBuiltAt = %q,\n\tLobbyPlaceId = %s,\n\tRunPlaceId = %s,\n})\n",
		commit,
		environment,
		builtAt,
		lobby,
		run
	)
)
print(
	string.format(
		"Stamped Config.Places: Lobby = %s, Run = %s (%s, %s)",
		lobby,
		run,
		environment,
		shortCommit
	)
)

-- 2. Build ------------------------------------------------------------------

local placeFile = string.format("build/SleighHeist-%s.rbxl", environment)
local built = process.exec("rojo", { "build", "deploy.project.json", "-o", placeFile }, { stdio = "inherit" })
if not built.ok then
	fail("rojo build failed")
end
local placeBytes = fs.readFile(placeFile)
print(string.format("Built %s (%.1f KB)", placeFile, #placeBytes / 1024))

-- 3. Check for instances Open Cloud can't publish ----------------------------

local game = roblox.deserializePlace(placeBytes)
local blocked: { [string]: number } = {}
local assetCount = 0
local assets = game:GetService("ServerStorage"):FindFirstChild("Assets")
if assets then
	assetCount = #assets:GetChildren()
end
for _, instance in game:GetDescendants() do
	for _, className in UNPUBLISHABLE do
		if instance:IsA(className) then
			blocked[instance:GetFullName()] = (blocked[instance:GetFullName()] or 0) + 1
			break
		end
	end
end
if next(blocked) then
	for path in blocked do
		print("  can't publish through Open Cloud: " .. path)
	end
	fail(
		"The place contains instances Open Cloud can't publish (see above). Re-export those models "
			.. "without SurfaceAppearance/unions; docs/DEPLOY.md explains how."
	)
end
print(string.format("Publishable: %d approved models in ServerStorage.Assets", assetCount))

if dryRun then
	print("Dry run: nothing uploaded.")
	process.exit(0)
end

-- Open Cloud ----------------------------------------------------------------

local function call(method: string, url: string, body: string?, contentType: string?): any
	local response = net.request({
		url = url,
		method = method :: any,
		headers = {
			["x-api-key"] = key :: string,
			["content-type"] = contentType or "application/json",
		},
		body = body,
	})
	if not response.ok then
		local hint = ""
		if response.statusCode == 401 or response.statusCode == 403 then
			hint = "\nCheck the API key's permissions and that it's allowed on universe "
				.. universe
				.. " (docs/DEPLOY.md step 3)."
		end
		error(string.format("%s %s -> %d\n%s%s", method, url, response.statusCode, response.body, hint))
	end
	if response.body == "" then
		return {}
	end
	return serde.decode("json", response.body)
end

local function saveVersion(placeId: string, versionType: string): number
	local result = call(
		"POST",
		string.format(
			"%s/universes/v1/%s/places/%s/versions?versionType=%s",
			API,
			universe,
			placeId,
			versionType
		),
		placeBytes,
		"application/octet-stream"
	)
	return result.versionNumber
end

-- 4. Smoke test in a real Roblox server --------------------------------------

local SMOKE_SCRIPT = [==[
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local report = { failed = {}, slow = {}, loaded = 0 }
local function tryRequire(module)
	local done = false
	task.spawn(function()
		local ok, err = pcall(require, module)
		if ok then
			report.loaded += 1
		else
			table.insert(report.failed, module:GetFullName() .. ": " .. tostring(err))
		end
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < 5 do
		task.wait()
	end
	if not done then
		table.insert(report.slow, module:GetFullName())
	end
end

for _, root in { ReplicatedStorage:WaitForChild("Shared", 10), ServerScriptService:WaitForChild("Server", 10) } do
	for _, module in root:GetDescendants() do
		if module:IsA("ModuleScript") then
			tryRequire(module)
		end
	end
end

local Config = require(ReplicatedStorage.Shared.Config)
local BuildInfo = require(ReplicatedStorage.Shared.BuildInfo)
report.placeId = game.PlaceId
report.lobby = Config.Places.Lobby
report.run = Config.Places.Run
report.commit = BuildInfo.Commit
return HttpService:JSONEncode(report)
]==]

local function runTask(placeId: string, version: number, script: string): any
	local created = call(
		"POST",
		string.format(
			"%s/cloud/v2/universes/%s/places/%s/versions/%d/luau-execution-session-tasks",
			API,
			universe,
			placeId,
			version
		),
		serde.encode("json", { script = script, timeout = "120s" })
	)
	local started = os.clock()
	local result = created
	while result.state == nil or result.state == "QUEUED" or result.state == "PROCESSING" do
		if os.clock() - started > GIVE_UP_SECONDS then
			fail("Gave up waiting for smoke task " .. tostring(created.path))
		end
		task.wait(POLL_SECONDS)
		result = call("GET", API .. "/cloud/v2/" .. created.path)
	end
	local ok, logs = pcall(call, "GET", API .. "/cloud/v2/" .. created.path .. "/logs?maxPageSize=10000")
	if ok then
		for _, page in logs.luauExecutionSessionTaskLogs or {} do
			for _, message in page.messages or {} do
				print("  [server] " .. message)
			end
		end
	end
	if result.state ~= "COMPLETE" then
		fail(
			"Smoke task ended " .. tostring(result.state) .. ": " .. serde.encode("json", result.error or {})
		)
	end
	return serde.decode("json", result.output.results[1])
end

if smoke then
	local version = saveVersion(lobby, "Saved")
	print(string.format("Smoke test: saved Lobby place version %d (not published)", version))
	local report = runTask(lobby, version, SMOKE_SCRIPT)
	for _, name in report.slow do
		print("::warning::Smoke test: " .. name .. " was still loading after 5 s")
	end
	if #report.failed > 0 then
		for _, line in report.failed do
			print("  failed to load: " .. line)
		end
		fail(string.format("Smoke test: %d module(s) failed to load in a Roblox server", #report.failed))
	end
	if
		tostring(report.lobby) ~= lobby
		or tostring(report.run) ~= run
		or tostring(report.placeId) ~= lobby
	then
		fail("Smoke test: place ids don't match: " .. serde.encode("json", report))
	end
	print(string.format("Smoke test passed: %d modules loaded, place ids match", report.loaded))
	table.insert(
		summaryLines,
		string.format("| Smoke test | %d modules loaded in a Roblox server |", report.loaded)
	)
end

-- 5. Publish: Run first, then Lobby ------------------------------------------

local runVersion = saveVersion(run, "Published")
print(string.format("Published Run place %s as version %d", run, runVersion))
local lobbyVersion = saveVersion(lobby, "Published")
print(string.format("Published Lobby place %s as version %d", lobby, lobbyVersion))
table.insert(summaryLines, string.format("| Run place `%s` | version %d |", run, runVersion))
table.insert(summaryLines, string.format("| Lobby place `%s` | version %d |", lobby, lobbyVersion))

if restart then
	-- Same as "Restart servers for updates" in the Creator Dashboard. Players
	-- mid-run are disconnected, so this is opt-in. A failure here is only a
	-- warning: the new version is live for every new server either way.
	local ok, err =
		pcall(call, "POST", string.format("%s/cloud/v2/universes/%s:restartServers", API, universe), "{}")
	if ok then
		print("Asked Roblox to restart the experience's servers")
		table.insert(summaryLines, "| Servers | restart requested |")
	else
		print("::warning::Couldn't restart servers (needs universe Write on the key): " .. tostring(err))
	end
end

if env.GITHUB_STEP_SUMMARY and env.GITHUB_STEP_SUMMARY ~= "" then
	local summary = string.format(
		"### Deployed to %s (`%s`)\n\n| | |\n| --- | --- |\n%s\n\n",
		environment,
		shortCommit,
		table.concat(summaryLines, "\n")
	)
	local existing = if fs.isFile(env.GITHUB_STEP_SUMMARY) then fs.readFile(env.GITHUB_STEP_SUMMARY) else ""
	fs.writeFile(env.GITHUB_STEP_SUMMARY, existing .. summary)
end
print(string.format("Deployed %s to %s.", shortCommit, environment))
