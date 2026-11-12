--[[
	Pure rules for the lobby's weekly leaderboards (no services, so the
	Lune tests can pin them):

	  Top Crews   one entry per crew (the same set of real Santas), scored
	              by the crew's best single-run haul this week.
	  Most Wanted one entry per Santa, scored by all the loot they got away
	              with this week.

	Weeks start Monday 00:00 UTC, and every week gets fresh store names,
	so the boards reset by themselves with no clean-up job.

	A crew's key holds its members' UserIds (sorted, 7 base-62 characters
	each), so the lobby can show the names without a second DataStore. Six
	Santas make 42 characters, inside the 50 a DataStore key allows.
]]

local Leaderboard = {}

local WEEK = 7 * 24 * 3600
-- 1 Jan 1970 was a Thursday: shifting by 3 days makes weeks start on Monday.
local MONDAY_OFFSET = 3 * 24 * 3600

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local WIDTH = 7 -- 62^7 is about 3.5 trillion, far past today's UserIds

-- The Monday a week starts on, e.g. "2026-11-09".
function Leaderboard.weekKey(t: number): string
	local start = math.floor((t + MONDAY_OFFSET) / WEEK) * WEEK - MONDAY_OFFSET
	-- Roblox's os.date only takes "*t" / "!*t"
	local d = os.date("!*t", start) :: any
	return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

-- Seconds until the boards reset.
function Leaderboard.secondsLeft(t: number): number
	local start = math.floor((t + MONDAY_OFFSET) / WEEK) * WEEK - MONDAY_OFFSET
	return start + WEEK - t
end

local function encodeId(id: number): string
	local out = {}
	local n = math.floor(id)
	for _ = 1, WIDTH do
		local d = n % 62
		table.insert(out, 1, string.sub(DIGITS, d + 1, d + 1))
		n = (n - d) // 62
	end
	return table.concat(out)
end

local function decodeId(s: string): number?
	local n = 0
	for i = 1, #s do
		local d = string.find(DIGITS, string.sub(s, i, i), 1, true)
		if not d then
			return nil
		end
		n = n * 62 + (d - 1)
	end
	return n
end

-- One key per crew, whatever order the Santas are in. Nil for no Santas.
function Leaderboard.crewKey(userIds: { number }): string?
	local ids = {}
	for _, id in userIds do
		if type(id) == "number" and id > 0 and not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return nil
	end
	table.sort(ids)
	local parts = {}
	for _, id in ids do
		table.insert(parts, encodeId(id))
	end
	return table.concat(parts)
end

-- The UserIds in a crew key (empty for a key that isn't one).
function Leaderboard.crewIds(key: string): { number }
	local ids = {}
	if type(key) ~= "string" or #key == 0 or #key % WIDTH ~= 0 then
		return ids
	end
	for i = 1, #key, WIDTH do
		local id = decodeId(string.sub(key, i, i + WIDTH - 1))
		if not id then
			return {}
		end
		table.insert(ids, id)
	end
	return ids
end

-- The crew's score after a run: their best single haul.
function Leaderboard.bestHaul(old: any, haul: number): number
	local prev = if type(old) == "number" then old else 0
	return math.max(prev, math.floor(haul))
end

-- 950 -> "950", 12345 -> "12.3K", 2500000 -> "2.5M"
function Leaderboard.short(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local value, suffix = n / 1000, "K"
	if n >= 1e6 then
		value, suffix = n / 1e6, "M"
	end
	local text = if value >= 100 then string.format("%d", value) else string.format("%.1f", value)
	text = string.gsub(text, "%.0$", "")
	return text .. suffix
end

-- "Bob, Ann & Cy"; long crews are cut to "Bob, Ann +4".
function Leaderboard.crewNames(names: { string }, maxNames: number?): string
	local limit = maxNames or 3
	if #names == 0 then
		return "?"
	end
	if #names > limit then
		local shown = table.move(names, 1, limit - 1, 1, {})
		return table.concat(shown, ", ") .. " +" .. (#names - #shown)
	end
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " & " .. names[#names]
end

-- "Resets in 3d 4h" / "Resets in 5h" / "Resets in 12m"
function Leaderboard.resetText(seconds: number): string
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	if d >= 1 then
		return string.format("Resets in %dd %dh", d, h)
	end
	if h >= 1 then
		return string.format("Resets in %dh", h)
	end
	return string.format("Resets in %dm", math.max(1, math.ceil(seconds / 60)))
end

-- A Roblox headshot for a Wanted poster.
function Leaderboard.headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

return Leaderboard
