--[[
	Line and function coverage for the Lune test runner.

	`lune run tests/runner --coverage` instruments every module under src/ with
	tools/luau-cov (probes are added on the same line, so line numbers in errors
	stay the same), runs the specs, then writes:

	  coverage/lcov.info    lcov, for genhtml, Codecov, editors (Coverage Gutters)
	  coverage/index.html   per-file table; each file links to its source with
	                        covered lines in green and missed lines in red
	  coverage/summary.md   the same table in Markdown (CI posts it to the job summary)

	Files listed in ENGINE_ONLY need the live engine (events, physics, remotes),
	so Lune can't run them. They're still reported, but kept out of the
	"Lune-testable" total that the coverage floor checks.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Coverage = {}

-- Covered by the in-engine tier (tests/engine, Jest Roblox) instead.
Coverage.ENGINE_ONLY = {
	["src/server/Main.server.luau"] = true,
	["src/server/Run.luau"] = true,
	["src/server/Lobby.luau"] = true,
	["src/server/RunHost.luau"] = true,
	["src/server/Krampus.luau"] = true,
	["src/server/ElfBot.luau"] = true,
	["src/server/Mover.luau"] = true,
	["src/shared/Remotes.luau"] = true,
	["src/client/Hud.client.luau"] = true,
}

-- Advisory floor for the Lune-testable total (warns, never fails, before launch).
Coverage.FLOOR = 0.8

local TOOL = "tools/luau-cov/target/release/luau-cov" .. (if process.os == "windows" then ".exe" else "")

type FileData = {
	lines: { number },
	functions: { { name: string, line: number } },
	lineHits: { [number]: number },
	fnHits: { [number]: number },
}

local files: { [string]: FileData } = {}

local function instrumentFile(file: string): (string, FileData)
	local result = process.exec(TOOL, { file })
	if not result.ok then
		error("luau-cov failed on " .. file .. ":\n" .. result.stderr)
	end
	local data = serde.decode("json", result.stdout)
	local entry = files[file]
	if not entry then
		entry = { lines = data.lines, functions = data.functions, lineHits = {}, fnHits = {} }
		files[file] = entry
	end
	return data.source, entry
end

function Coverage.available(): boolean
	return fs.isFile(TOOL)
end

-- Returns instrumented source and adds the probe functions to `env`.
function Coverage.instrument(file: string, env: { [string]: any }): string
	local source, entry = instrumentFile(file)
	local lineHits, fnHits = entry.lineHits, entry.fnHits
	env.__cl = function(line: number)
		lineHits[line] = (lineHits[line] or 0) + 1
	end
	env.__cf = function(index: number)
		fnHits[index] = (fnHits[index] or 0) + 1
	end
	return source
end

-- Raw hit counts as JSON, so another run (the in-engine tier) can merge in.
function Coverage.saveHits(path: string)
	local out = {}
	for file, entry in files do
		local l, f = {}, {}
		for line, n in entry.lineHits do
			l[tostring(line)] = n
		end
		for index, n in entry.fnHits do
			f[tostring(index)] = n
		end
		out[file] = { l = l, f = f }
	end
	fs.writeFile(path, serde.encode("json", out))
end

-- Adds hit counts in the saveHits shape ({ [file] = { l = {}, f = {} } }).
function Coverage.addHits(data: { [string]: { l: { [string]: number }?, f: { [string]: number }? } })
	for file, hits in data do
		if fs.isFile(file) then
			local _, entry = instrumentFile(file)
			for line, n in hits.l or {} do
				local key = tonumber(line) :: number
				entry.lineHits[key] = (entry.lineHits[key] or 0) + n
			end
			for index, n in hits.f or {} do
				local key = tonumber(index) :: number
				entry.fnHits[key] = (entry.fnHits[key] or 0) + n
			end
		end
	end
end

-- Registers files no spec loaded, so they show up at 0% instead of vanishing.
local function addUnloaded(dir: string)
	for _, name in fs.readDir(dir) do
		local file = dir .. "/" .. name
		if fs.isDir(file) then
			addUnloaded(file)
		elseif string.find(name, "%.luau$") and not files[file] then
			instrumentFile(file)
		end
	end
end

local function escape(s: string): string
	return (string.gsub(s, '[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function pct(hit: number, total: number): string
	if total == 0 then
		return "-"
	end
	return string.format("%.1f%%", 100 * hit / total)
end

local function stats(entry: FileData)
	local hitLines = 0
	for _, line in entry.lines do
		if (entry.lineHits[line] or 0) > 0 then
			hitLines += 1
		end
	end
	local hitFns = 0
	for i = 1, #entry.functions do
		if (entry.fnHits[i - 1] or 0) > 0 then
			hitFns += 1
		end
	end
	return hitLines, #entry.lines, hitFns, #entry.functions
end

local CSS = [[
:root{--bg:#fff;--fg:#1f2328;--muted:#656d76;--line:#d0d7de;--hit:#dafbe1;--miss:#ffebe9;--hitbar:#1a7f37;--missbar:#cf222e}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--line:#30363d;--hit:#12261e;--miss:#2d1214;--hitbar:#3fb950;--missbar:#f85149}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif}
h1{font-size:20px;margin:0 0 4px}p{color:var(--muted);margin:0 0 16px}a{color:inherit}
table{border-collapse:collapse;width:100%;max-width:960px}th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:left}
td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.bar{display:inline-block;width:90px;height:8px;background:var(--missbar);border-radius:4px;overflow:hidden;vertical-align:middle;margin-right:8px}
.bar i{display:block;height:100%;background:var(--hitbar)}
.tag{font-size:12px;color:var(--muted)}
pre{margin:0;font:13px/1.5 ui-monospace,monospace;overflow-x:auto;tab-size:4}
.src{border:1px solid var(--line);border-radius:6px;overflow:hidden}
.src div{display:flex;white-space:pre}.src .h{background:var(--hit)}.src .m{background:var(--miss)}
.src b{display:inline-block;min-width:44px;padding:0 8px;text-align:right;color:var(--muted);font-weight:normal;user-select:none}
.src em{display:inline-block;min-width:36px;padding-right:8px;text-align:right;color:var(--muted);font-style:normal;user-select:none}
]]

local function page(title: string, body: string): string
	return '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
		.. "<title>"
		.. escape(title)
		.. "</title><style>"
		.. CSS
		.. "</style></head><body>"
		.. body
		.. "</body></html>"
end

local function htmlName(file: string): string
	return (string.gsub(file, "[/\\]", "_")) .. ".html"
end

local function sourcePage(file: string, entry: FileData): string
	local executable = {}
	for _, line in entry.lines do
		executable[line] = true
	end
	local out =
		{ "<h1>" .. escape(file) .. '</h1><p><a href="index.html">All files</a></p><div class="src"><pre>' }
	local n = 0
	for text in string.gmatch(fs.readFile(file) .. "\n", "([^\n]*)\n") do
		n += 1
		local hits = entry.lineHits[n] or 0
		local class = if not executable[n] then "" elseif hits > 0 then "h" else "m"
		local count = if executable[n] then (if hits > 0 then tostring(hits) .. "x" else "0") else ""
		table.insert(
			out,
			string.format('<div class="%s"><b>%d</b><em>%s</em>%s</div>', class, n, count, escape(text))
		)
	end
	table.insert(out, "</pre></div>")
	return page(file, table.concat(out))
end

-- Writes the reports and returns the Lune-testable line ratio.
function Coverage.report(outDir: string): number
	addUnloaded("src")
	if fs.isDir(outDir) then
		fs.removeDir(outDir)
	end
	fs.writeDir(outDir)

	local names = {}
	for file in files do
		table.insert(names, file)
	end
	table.sort(names)

	local lcov = {}
	local rows, mdRows = {}, {}
	local totals = { all = { 0, 0 }, lune = { 0, 0 } }
	for _, file in names do
		local entry = files[file]
		local hitLines, lines, hitFns, fns = stats(entry)
		local engine = Coverage.ENGINE_ONLY[file] == true

		totals.all[1] += hitLines
		totals.all[2] += lines
		if not engine then
			totals.lune[1] += hitLines
			totals.lune[2] += lines
		end

		table.insert(lcov, "SF:" .. file)
		for i, fn in entry.functions do
			table.insert(lcov, string.format("FN:%d,%s", fn.line, fn.name))
			table.insert(lcov, string.format("FNDA:%d,%s", entry.fnHits[i - 1] or 0, fn.name))
		end
		table.insert(lcov, string.format("FNF:%d\nFNH:%d", fns, hitFns))
		for _, line in entry.lines do
			table.insert(lcov, string.format("DA:%d,%d", line, entry.lineHits[line] or 0))
		end
		table.insert(lcov, string.format("LF:%d\nLH:%d\nend_of_record", lines, hitLines))

		local ratio = if lines > 0 then hitLines / lines else 1
		local tag = if engine then ' <span class="tag">engine tier</span>' else ""
		table.insert(
			rows,
			string.format(
				'<tr><td><a href="%s">%s</a>%s</td><td class="n"><span class="bar"><i style="width:%.0f%%"></i></span>%s</td><td class="n">%d / %d</td><td class="n">%s</td></tr>',
				htmlName(file),
				escape(file),
				tag,
				100 * ratio,
				pct(hitLines, lines),
				hitLines,
				lines,
				pct(hitFns, fns)
			)
		)
		table.insert(
			mdRows,
			string.format(
				"| `%s`%s | %s | %d / %d | %s |",
				file,
				if engine then " (engine)" else "",
				pct(hitLines, lines),
				hitLines,
				lines,
				pct(hitFns, fns)
			)
		)
		fs.writeFile(outDir .. "/" .. htmlName(file), sourcePage(file, entry))
	end

	fs.writeFile(outDir .. "/lcov.info", table.concat(lcov, "\n") .. "\n")

	local headline = string.format(
		"Lune-testable code: %s of lines (%d / %d). All code: %s (%d / %d).",
		pct(totals.lune[1], totals.lune[2]),
		totals.lune[1],
		totals.lune[2],
		pct(totals.all[1], totals.all[2]),
		totals.all[1],
		totals.all[2]
	)
	fs.writeFile(
		outDir .. "/index.html",
		page(
			"Coverage",
			"<h1>Test coverage</h1><p>"
				.. escape(headline)
				.. " Files tagged engine tier need the live engine and are tested in Studio or Open Cloud.</p>"
				.. "<table><tr><th>File</th><th>Lines</th><th></th><th>Functions</th></tr>"
				.. table.concat(rows)
				.. "</table>"
		)
	)
	fs.writeFile(
		outDir .. "/summary.md",
		"### Test coverage\n\n"
			.. headline
			.. "\n\n| File | Lines | Hit / total | Functions |\n|---|---|---|---|\n"
			.. table.concat(mdRows, "\n")
			.. "\n"
	)

	print(headline)
	print("Report: " .. outDir .. "/index.html")
	return if totals.lune[2] > 0 then totals.lune[1] / totals.lune[2] else 1
end

return Coverage
