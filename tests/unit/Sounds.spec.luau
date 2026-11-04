local Config = load("ReplicatedStorage.Shared.Config")
local Sounds = load("ReplicatedStorage.Shared.Sounds")

local groups = {}
for _, name in Sounds.Groups do
	groups[name] = true
end

test("every sound has a valid group, volume, pitch, range and search text", function()
	for key, def in Sounds.Defs do
		expect(groups[def.group] and key).toBe(key)
		expect(Config.Audio.Groups[def.group] ~= nil).toBeTruthy()
		expect(def.volume).toBeGreaterThan(0)
		expect(def.volume).toBeLessThan(1.01) -- phone speakers clip; never boost
		expect(type(def.id)).toBe("number")
		expect(#def.find).toBeGreaterThan(3)
		if def.pitch then
			expect(def.pitch[1] <= def.pitch[2] and key).toBe(key)
			expect(def.pitch[1]).toBeGreaterThan(0.5)
			expect(def.pitch[2]).toBeLessThan(2)
		end
		if def.range then
			expect(def.range[1] < def.range[2] and key).toBe(key)
			-- Concurrent routes are RouteSpacing apart: a crew never hears another crew.
			expect(def.range[2]).toBeLessThan(Config.Map.RouteSpacing / 2)
		end
	end
end)

test("2D groups are 2D and world sounds are 3D", function()
	for key, def in Sounds.Defs do
		if def.group == "Ui" or def.group == "Music" or def.group == "Ambience" then
			expect(def.range == nil and key).toBe(key)
		end
	end
end)

test("music sits under the effects for mobile", function()
	local G = Config.Audio.Groups
	expect(G.Music).toBeLessThan(G.Sfx)
	expect(G.Ambience).toBeLessThan(G.Sfx)
	for _, v in G do
		expect(v).toBeLessThan(1.01)
	end
end)

test("unknown keys fail loudly", function()
	expect(pcall(Sounds.get, "NoSuchSound")).toBe(false)
end)

-- Regression: a typo in a sound key is silent in game, so check every key in the code.
test("every sound key used in src exists in the catalogue", function()
	local files = {}
	local function walk(dir)
		for _, name in listDir(dir) do
			local file = dir .. "/" .. name
			if string.find(name, "%.luau$") then
				table.insert(files, file)
			elseif not string.find(name, "%.") then
				walk(file)
			end
		end
	end
	walk("src")
	local used = 0
	local patterns = {
		'SoundPlayer%.at%(%s*"(%w+)"',
		'SoundPlayer%.loop%(%s*"(%w+)"',
		'SoundPlayer%.ui%(%s*"(%w+)"',
		'_sfx%([^,]+,%s*"(%w+)"',
		'SoundPlayer%.at, "(%w+)"', -- task.delay(t, SoundPlayer.at, "Key", ...)
	}
	for _, file in files do
		local source = readSource(file)
		for _, pattern in patterns do
			for key in string.gmatch(source, pattern) do
				used += 1
				expect(Sounds.Defs[key] ~= nil and key).toBe(key)
			end
		end
		-- Keys picked with if/else inside a sound call: every quoted word on the line.
		for line in string.gmatch(source, "[^\n]+") do
			if string.find(line, "SoundPlayer%.%a+%(if ") then
				for key in string.gmatch(line, '"(%w+)"') do
					used += 1
					expect(Sounds.Defs[key] ~= nil and key).toBe(key)
				end
			end
		end
	end
	expect(used).toBeGreaterThan(25)
end)

test("the sleigh leave warning: last-call honk at 10 s, ticks 5 to 1, each once", function()
	local played = {}
	local last = nil
	for left = 30, 0, -1 do
		for _ = 1, 3 do -- the client checks ten times a second; repeats must not re-cue
			local cue = Sounds.leaveCue(left, last)
			if cue then
				table.insert(played, left .. cue)
			end
			last = left
		end
	end
	expect(table.concat(played, ",")).toBe(
		"10LastCall,5CountdownTick,4CountdownTick,3CountdownTick,2CountdownTick,1CountdownTick"
	)
end)

test("countdown ticks rise in pitch", function()
	expect(Sounds.tickPitch(5)).toBeNear(1)
	expect(Sounds.tickPitch(1)).toBeNear(1.4)
	expect(Sounds.tickPitch(3)).toBeLessThan(Sounds.tickPitch(2))
	expect(Sounds.tickPitch(99)).toBeNear(1) -- clamped
end)

test("the noise meter squeaks once at 75% and alarms once when full", function()
	local max = Config.Noise.Max
	expect(Sounds.noiseCue(0, max * 0.5, max)).toBe(nil)
	expect(Sounds.noiseCue(max * 0.5, max * 0.8, max)).toBe("NoiseWarn")
	expect(Sounds.noiseCue(max * 0.8, max * 0.9, max)).toBe(nil)
	expect(Sounds.noiseCue(max * 0.9, max, max)).toBe("NoiseFull")
	expect(Sounds.noiseCue(max, max, max)).toBe(nil)
	expect(Sounds.noiseCue(0, max, max)).toBe("NoiseFull") -- one jump: the alarm wins
end)

test("loot cues: Jingle and corgi spills; banking is cued by the server", function()
	local base = { jingle = 100, banked = 0, sackCount = 3 }
	expect(#Sounds.lootCues(nil, base)).toBe(0)
	expect(Sounds.lootCues(base, { jingle = 150, banked = 0, sackCount = 4 })[1]).toBe("JingleGain")
	expect(Sounds.lootCues(base, { jingle = 100, banked = 0, sackCount = 2 })[1]).toBe("SackSpill")
	expect(#Sounds.lootCues(base, { jingle = 100, banked = 500, sackCount = 0 })).toBe(0)
	expect(#Sounds.lootCues(base, { jingle = 60, banked = 0, sackCount = 3 })).toBe(0) -- spending is silent
end)

test("Krampus heartbeat only when he is close, louder and faster as he nears", function()
	expect(Sounds.krampusMix(nil).heartbeat).toBe(0)
	expect(Sounds.krampusMix(Sounds.HeartbeatFar).heartbeat).toBe(0)
	local mid = Sounds.krampusMix(50)
	local near = Sounds.krampusMix(Sounds.HeartbeatNear)
	expect(mid.heartbeat).toBeGreaterThan(0)
	expect(near.heartbeat).toBeGreaterThan(mid.heartbeat)
	expect(near.speed).toBeGreaterThan(mid.speed)
	expect(Sounds.krampusMix(1).heartbeat).toBeNear(1)
end)

test("music follows the run", function()
	expect(Sounds.musicFor(false, nil, false)).toBe("LobbyMusic")
	expect(Sounds.musicFor(true, "Sneak", false)).toBe("SneakMusic")
	expect(Sounds.musicFor(true, "Horn", false)).toBe("HurryMusic")
	expect(Sounds.musicFor(true, "Horn", true)).toBe("KrampusMusic")
	expect(Sounds.musicFor(true, "Flight", false)).toBe(nil)
end)

test("dogs warn before they bump", function()
	local D = Config.Canal.Dogs
	expect(D.WarnRadius).toBeGreaterThan(D.HitRadius * 2)
	expect(Sounds.dogWarns(D.HitRadius - 1, D.HitRadius, D.WarnRadius)).toBeFalsy()
	expect(Sounds.dogWarns(D.HitRadius + 1, D.HitRadius, D.WarnRadius)).toBeTruthy()
	expect(Sounds.dogWarns(D.WarnRadius, D.HitRadius, D.WarnRadius)).toBeFalsy()
end)

test("cooldowns and pitch variation", function()
	expect(Sounds.ready("KrampusSniff", nil, 0)).toBeTruthy()
	expect(Sounds.ready("KrampusSniff", 0, 1)).toBeFalsy()
	expect(Sounds.ready("KrampusSniff", 0, Sounds.get("KrampusSniff").cooldown)).toBeTruthy()
	expect(Sounds.ready("SleighHorn", 0, 0)).toBeTruthy() -- no cooldown
	local rng = Random.new(7)
	for _ = 1, 20 do
		local p = Sounds.pitchFor("PresentGrab", rng)
		expect(p >= 0.9 and p <= 1.15).toBeTruthy()
	end
	expect(Sounds.pitchFor("SleighHorn", rng)).toBe(1)
end)
