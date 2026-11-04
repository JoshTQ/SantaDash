--[[
	Hit counters for coverage builds of the test place. `tools/prepare-engine.luau
	--coverage` starts every module with
	  local __cl, __cf = require(ReplicatedStorage.CoverageProbes)("src/...");
	and RunTests returns hits() so tools/ocale.luau can merge them into the
	coverage report. Keys are strings so HttpService can JSON-encode them.
]]

local hits: { [string]: { l: { [string]: number }, f: { [string]: number } } } = {}

local CoverageProbes = {}

function CoverageProbes.hits()
	return hits
end

return setmetatable(CoverageProbes, {
	__call = function(_, file: string)
		local entry = hits[file] or { l = {}, f = {} }
		hits[file] = entry
		local lines, functions = entry.l, entry.f
		local function line(n: number)
			local key = tostring(n)
			lines[key] = (lines[key] or 0) + 1
		end
		local function fn(index: number)
			local key = tostring(index)
			functions[key] = (functions[key] or 0) + 1
		end
		return line, fn
	end,
})
