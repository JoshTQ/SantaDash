--[[
	Room Mix houses (Josh, 6 Nov 2026): 5-7 rooms over 1-2 floors, every room
	reachable from the front door, secret rooms where Loot rolls one, and
	window moods on the outside.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local HouseBuilder = load("ServerScriptService.Server.HouseBuilder")

local function reachable(plan)
	-- Walk the doorways (and open plan within a room) from the hall / landing.
	for l = 0, plan.floors - 1 do
		local seen, queue = { [plan.hallCol .. ",1"] = true }, { { plan.hallCol, 1 } }
		while #queue > 0 do
			local c, r = table.unpack(table.remove(queue, 1))
			for _, s in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nc, nr = c + s[1], r + s[2]
				if nc >= 0 and nc < plan.cols and nr >= 0 and nr <= 1 and not seen[nc .. "," .. nr] then
					local g = plan.grid[l + 1]
					local same = g[r + 1][c + 1] == g[nr + 1][nc + 1]
					if same or plan.doors[HouseBuilder.edgeKey(l, c, r, nc, nr)] then
						seen[nc .. "," .. nr] = true
						table.insert(queue, { nc, nr })
					end
				end
			end
		end
		for r = 0, 1 do
			for c = 0, plan.cols - 1 do
				if not seen[c .. "," .. r] then
					return false
				end
			end
		end
	end
	return true
end

test("plans have 5-7 rooms over 1-2 floors, all reachable from the hall", function()
	local floors = {}
	for seed = 1, 200 do
		local plan = HouseBuilder.roomPlan(HouseBuilder.mulberry(seed), seed % 2 == 0, 1, seed % 3 == 0)
		local rooms = 0
		for _, room in plan.rooms do
			rooms += if room.type == "Landing" then 0 else 1
		end
		expect(rooms >= 5 and rooms <= 7).toBeTruthy()
		expect(plan.grid[1][2][plan.hallCol + 1].type).toBe("Hall")
		expect(reachable(plan)).toBeTruthy()
		floors[plan.floors] = true
	end
	expect(floors[1] and floors[2]).toBeTruthy()
end)

test("secret rooms: bookcases downstairs clear of the fireplace, attics only under Alpine roofs", function()
	local kinds = {}
	for seed = 1, 300 do
		local alpine = seed % 2 == 0
		local cs = if seed % 3 == 0 then -1 else 1
		local plan = HouseBuilder.roomPlan(HouseBuilder.mulberry(seed), true, cs, alpine)
		local s = plan.secret
		expect(s ~= nil).toBeTruthy()
		kinds[s.kind] = true
		local room = plan.grid[s.level + 1][s.row + 1][s.col + 1]
		expect(room.type ~= "Hall" and room.type ~= "Landing" and room.type ~= "Bathroom").toBeTruthy()
		if s.kind == "Bookcase" then
			expect(s.level).toBe(0)
			expect(s.row).toBe(0)
			expect(s.col).never.toBe(if cs < 0 then 0 else plan.cols - 1)
		elseif s.kind == "Attic" then
			expect(alpine).toBe(true)
			expect(s.level).toBe(plan.floors - 1)
		else
			expect(s.level).toBe(0)
			expect(room.type).never.toBe("Kitchen")
		end
	end
	expect(kinds.Bookcase and kinds.Cellar and kinds.Attic).toBeTruthy()
end)

test("a secret room is built sealed, with its trigger, Big present spot and dark glow", function()
	local seen = {}
	for seed = 1, 120 do
		local style = if seed % 2 == 0 then "alpine" else "candy"
		local house = HouseBuilder.build(seed, style, "Room Mix", { secret = true })
		local secret = house:FindFirstChild("Secret")
		expect(secret ~= nil).toBeTruthy()
		local kind = secret:GetAttribute("Kind")
		seen[kind] = true
		expect(house:GetAttribute("Secret")).toBe(kind)
		local trigger = secret:FindFirstChild("SecretTrigger")
		expect(trigger:IsA("BasePart")).toBeTruthy()
		expect(typeof(trigger:GetAttribute("Open"))).toBe("CFrame")
		expect(house:FindFirstChild("SecretSpawn", true) ~= nil).toBeTruthy()
		if kind == "Bookcase" then
			expect(trigger.CanCollide).toBe(true) -- the bookcase blocks the gap until it swings
		else
			expect(house:FindFirstChild("SecretInside", true) ~= nil).toBeTruthy()
			expect(house:FindFirstChild("SecretOutside", true) ~= nil).toBeTruthy()
		end
		for _, d in secret:GetDescendants() do
			if d.Name == "SecretGlow" or d.Name == "SecretReveal" then
				expect(d.Transparency).toBe(1)
			elseif d:IsA("PointLight") then
				expect(d.Enabled).toBe(false)
				expect(d.Shadows).toBe(false)
			end
		end
	end
	expect(seen.Bookcase and seen.Cellar and seen.Attic).toBeTruthy()
	-- No secret asked for, none built.
	expect(HouseBuilder.build(5, "candy", "Room Mix"):FindFirstChild("Secret")).toBeNil()
end)

test("windows have moods: curtains, candles, TVs, dark rooms and more", function()
	local moods = {}
	for seed = 1, 20 do
		for _, d in HouseBuilder.build(seed, "candy", "Room Mix"):GetDescendants() do
			if d.Name == "Window" then
				local mood = d:GetAttribute("Mood")
				expect(mood ~= nil).toBeTruthy()
				moods[mood] = true
			end
		end
	end
	for _, mood in HouseBuilder.WindowMoods do
		expect(moods[mood[1]] and mood[1]).toBe(mood[1])
	end
end)

test("Loot: secrets in about half the robbable houses, never the landing house, vault or Lair", function()
	local rng = Random.new(4)
	local houses, secrets = 0, 0
	for _ = 1, 200 do
		for stop = 1, #Config.Run.StopKinds do
			for _, house in Loot.planStop(rng, stop).houses do
				local count = 0
				for _, present in house.presents do
					if present.secret then
						count += 1
						expect(present.size).toBe(Config.Houses.Secret.PresentSize)
					end
				end
				expect(count).toBe(if house.secret then 1 else 0)
				if house.isLanding or house.locked or house.typeName == "Lair" then
					expect(house.secret).toBe(false)
				else
					houses += 1
					secrets += if house.secret then 1 else 0
				end
			end
		end
	end
	local share = secrets / houses
	expect(share > 0.4 and share < 0.6).toBeTruthy() -- Josh: 2-3 houses in every 5
end)
