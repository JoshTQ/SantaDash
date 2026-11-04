--[[
	Copies src/ to build/engine-src/ for the test place (test.project.json).

	  lune run tools/prepare-engine              plain copy
	  lune run tools/prepare-engine --coverage   every module gets coverage probes
	                                             (tools/luau-cov) that count into
	                                             ReplicatedStorage.CoverageProbes
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local OUT = "build/engine-src"
local TOOL = "tools/luau-cov/target/release/luau-cov" .. (if process.os == "windows" then ".exe" else "")
local PRELUDE =
	'local __cl, __cf = require(game:GetService("ReplicatedStorage"):WaitForChild("CoverageProbes"))("{file}");'

local coverage = table.find(process.args, "--coverage") ~= nil
if coverage and not fs.isFile(TOOL) then
	print("Coverage needs the instrumenter: cargo build --release --manifest-path tools/luau-cov/Cargo.toml")
	process.exit(1)
end

local function copy(from: string, to: string)
	fs.writeDir(to)
	for _, name in fs.readDir(from) do
		local source, target = from .. "/" .. name, to .. "/" .. name
		if fs.isDir(source) then
			copy(source, target)
		elseif coverage and string.find(name, "%.luau$") then
			local result = process.exec(TOOL, { "--prelude", PRELUDE, source })
			if not result.ok then
				error("luau-cov failed on " .. source .. ":\n" .. result.stderr)
			end
			fs.writeFile(target, serde.decode("json", result.stdout).source)
		else
			fs.writeFile(target, fs.readFile(source))
		end
	end
end

if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
copy("src", OUT)
print("Wrote " .. OUT .. (if coverage then " (with coverage probes)" else ""))
