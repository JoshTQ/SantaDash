--[[
	Entry point for the in-engine tier. tools/ocale.luau runs
	  return require(game:GetService("ReplicatedStorage").RunTests)()
	in a fresh Open Cloud server and reads the JSON this returns. It also works
	from Studio's command bar to run the engine specs locally.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(): string
	local Jest = require(ReplicatedStorage.DevPackages.Jest)
	local root = ReplicatedStorage.EngineTests

	local status, result = Jest.runCLI(root, { verbose = true, ci = true }, { root }):awaitStatus()

	local out: { [string]: any } = { status = status, success = false }
	if status == "Resolved" then
		local results = result.results
		out.success = results.success
		out.passed = results.numPassedTests
		out.failed = results.numFailedTests
		out.total = results.numTotalTests
	else
		out.error = tostring(result)
	end
	out.coverage = require(ReplicatedStorage.CoverageProbes).hits()
	return HttpService:JSONEncode(out)
end
