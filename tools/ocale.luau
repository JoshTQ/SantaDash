--[[
	Runs the in-engine tier (tests/engine, Jest Roblox) in a real Roblox server
	through Open Cloud Luau Execution, and prints the results.

	  lune run tools/ocale <place.rbxl> [--coverage]

	1. Saves the place file as a new version of the test place (not published
	   to players).
	2. Starts a Luau execution task on that version that runs
	   ReplicatedStorage.RunTests, polls until it finishes, prints its logs.
	3. Exits 1 if any engine spec failed. With --coverage, merges the engine hit
	   counts into coverage/hits.json (from `lune run tests/runner --coverage`)
	   and rewrites the coverage report for both tiers together.

	Environment:
	  ROBLOX_API_KEY      Open Cloud key with universe-places:write and
	                      luau-execution-sessions:write on the test universe
	  ROBLOX_UNIVERSE_ID  the private test universe
	  ROBLOX_PLACE_ID     the test place in it
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Coverage = require("../tests/coverage")

local API = "https://apis.roblox.com"
local SCRIPT = 'return require(game:GetService("ReplicatedStorage"):WaitForChild("RunTests"))()'
local POLL_SECONDS = 3
local GIVE_UP_SECONDS = 6 * 60 -- tasks time out at 5 minutes

local placeFile = process.args[1]
local coverage = table.find(process.args, "--coverage") ~= nil
local key = process.env.ROBLOX_API_KEY
local universe = process.env.ROBLOX_UNIVERSE_ID
local place = process.env.ROBLOX_PLACE_ID

if not (placeFile and fs.isFile(placeFile)) then
	print("usage: lune run tools/ocale <place.rbxl> [--coverage]")
	process.exit(1)
end
if not (key and universe and place) then
	print(
		"Set ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID (see the README's in-engine tests section)."
	)
	process.exit(1)
end

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
		error(string.format("%s %s -> %d\n%s", method, url, response.statusCode, response.body))
	end
	return serde.decode("json", response.body)
end

-- 1. Save the place as a new version.
local saved = call(
	"POST",
	string.format("%s/universes/v1/%s/places/%s/versions?versionType=Saved", API, universe, place),
	fs.readFile(placeFile),
	"application/octet-stream"
)
print("Saved test place version " .. tostring(saved.versionNumber))

-- 2. Run the engine specs on that version.
local created = call(
	"POST",
	string.format(
		"%s/cloud/v2/universes/%s/places/%s/versions/%s/luau-execution-session-tasks",
		API,
		universe,
		place,
		tostring(saved.versionNumber)
	),
	serde.encode("json", { script = SCRIPT, timeout = "300s" })
)

local started = os.clock()
local result = created
while result.state == nil or result.state == "QUEUED" or result.state == "PROCESSING" do
	if os.clock() - started > GIVE_UP_SECONDS then
		print("Gave up waiting for task " .. tostring(created.path))
		process.exit(1)
	end
	task.wait(POLL_SECONDS)
	result = call("GET", API .. "/cloud/v2/" .. created.path)
end

local ok, logs = pcall(call, "GET", API .. "/cloud/v2/" .. created.path .. "/logs?maxPageSize=10000")
if ok then
	for _, page in logs.luauExecutionSessionTaskLogs or {} do
		for _, message in page.messages or {} do
			print(message)
		end
	end
end

if result.state ~= "COMPLETE" then
	print("Task ended " .. tostring(result.state) .. ": " .. serde.encode("json", result.error or {}))
	process.exit(1)
end

-- 3. Read what RunTests returned.
local summary = serde.decode("json", result.output.results[1])
print(
	string.format(
		"Engine tests: %s passed, %s failed, %s total",
		tostring(summary.passed),
		tostring(summary.failed),
		tostring(summary.total)
	)
)
if summary.error then
	print("Jest error: " .. summary.error)
end

if coverage then
	if fs.isFile("coverage/hits.json") then
		Coverage.addHits(serde.decode("json", fs.readFile("coverage/hits.json")))
	end
	Coverage.addHits(summary.coverage or {})
	Coverage.report("coverage")
	Coverage.saveHits("coverage/hits.json")
end

process.exit(if summary.success then 0 else 1)
