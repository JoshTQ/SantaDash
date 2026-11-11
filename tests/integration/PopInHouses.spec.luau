--[[
	Pop-in houses (Josh, 11 Nov 2026: "most houses on the map are closed with
	no entry, feels wrong"): every filler townhouse has a real front door, and
	opening it swaps the solid block for a roomy one-room interior that packs
	away again. Built with Lune's Roblox library (no events).
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local Maps = load("ReplicatedStorage.Shared.Maps")
local PopInHouses = load("ServerScriptService.Server.PopInHouses")
local P = Config.PopIn

local function build(seed)
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	return MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
end

local route = build(11)

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function allEntries()
	local list = {}
	for _, stop in route.stops do
		for _, entry in stop.popIns do
			table.insert(list, { stop = stop, entry = entry })
		end
	end
	return list
end

-- Does a box (cf, size) overlap a part's box? (axis-aligned in the box's frame, good enough for these upright parts)
local function overlaps(cf: CFrame, size: Vector3, part: BasePart): boolean
	local corners = {}
	local half = part.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(corners, cf:PointToObjectSpace(part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
			end
		end
	end
	local lo, hi = corners[1], corners[1]
	for _, c in corners do
		lo, hi = lo:Min(c), hi:Max(c)
	end
	local h = size / 2
	return lo.X < h.X and hi.X > -h.X and lo.Y < h.Y and hi.Y > -h.Y and lo.Z < h.Z and hi.Z > -h.Z
end

test("nearly every filler townhouse has a real front door now", function()
	local blocks = 0
	for _, d in route.model:GetDescendants() do
		if d.Name == "Townhouse" then
			blocks += 1
		end
	end
	local entries = allEntries()
	expect(blocks > 30).toBeTruthy()
	expect(#entries).toBe(blocks)
	for _, e in entries do
		expect(e.entry.door.Name).toBe("PopInDoor")
		expect(e.entry.door.Size.Z).toBe(P.DoorWidth)
		expect(e.entry.door.CanCollide).toBe(true)
		-- On the street face of the block, at the bottom.
		local d = e.entry.frame:PointToObjectSpace(e.entry.door.CFrame.Position)
		expect(math.abs(d.Z + e.entry.size.X / 2) < 1).toBeTruthy()
		expect(math.abs(d.X) < 0.01).toBeTruthy()
	end
end)

test("no lit window sits over a front door", function()
	for _, e in allEntries() do
		local door = e.entry.door
		for _, d in route.model:GetDescendants() do
			if d.Name == "Window" and overlaps(door.CFrame, door.Size + Vector3.new(2, 0, 0), d) then
				error("a window covers the door at " .. tostring(door.CFrame.Position))
			end
		end
	end
end)

test("opening swaps the block for a roomy room, and closing puts it all back", function()
	local e = allEntries()[1]
	local entry, stop = e.entry, e.stop
	local block, door = entry.block, entry.door
	local doorBefore, wreathBefore = door.CFrame, entry.wreath[1].CFrame
	local partsBefore = countParts(route.model)

	local present = PopInHouses.open(entry, stop.buildPresent)
	expect(entry.room ~= nil).toBeTruthy()
	expect(block.Transparency).toBe(1)
	expect(block.CanCollide).toBe(false)
	expect(block.CanQuery).toBe(false)
	expect(door.CanCollide).toBe(false)
	-- The door swings out towards the street, and its wreath goes with it.
	local moved = door.CFrame.Position - doorBefore.Position
	expect(moved:Dot(entry.frame.LookVector) > 0).toBeTruthy()
	expect((entry.wreath[1].CFrame.Position - wreathBefore.Position).Magnitude > 1).toBeTruthy()
	-- Opening twice is harmless.
	expect(PopInHouses.open(entry, stop.buildPresent) == present).toBeTruthy()

	local roomParts = countParts(entry.room)
	expect(roomParts <= 24).toBeTruthy()
	expect(countParts(route.model)).toBe(partsBefore + roomParts)

	-- The doorway is clear: a corridor DoorWidth-1 wide and 9 tall from outside the door to the middle.
	local W, D = PopInHouses.roomSize(entry)
	local corridor = entry.frame * CFrame.new(0, 5, -D / 4)
	for _, p in entry.room:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide and p.Name ~= "Floor" then
			if overlaps(corridor, Vector3.new(P.DoorWidth - 1, 9, D / 2 + 2), p) then
				error(p.Name .. " blocks the doorway")
			end
		end
	end
	-- And the room is spacious: at least a 14 x 12 stud clear patch to walk and turn the camera in.
	local middle = entry.frame * CFrame.new(0, 5, -2)
	for _, p in entry.room:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide and p.Name ~= "Floor" then
			if overlaps(middle, Vector3.new(14, 8, 12), p) then
				error(p.Name .. " crowds the middle of the room")
			end
		end
	end
	expect(W >= 30).toBeTruthy()
	expect(D >= 20).toBeTruthy()

	PopInHouses.close(entry)
	expect(entry.room).toBeNil()
	expect(block.Transparency).toBe(0)
	expect(block.CanCollide).toBe(true)
	expect(door.CFrame == doorBefore).toBe(true)
	expect(entry.wreath[1].CFrame == wreathBefore).toBe(true)
	expect(countParts(route.model)).toBe(partsBefore)
	if present then
		expect(present.taken).toBe(true) -- the stale copy can't be grabbed
	end
end)

test("about two in three rooms have a small gift; the rest have cookies", function()
	local gifts, cookies = 0, 0
	for _, e in allEntries() do
		local entry = e.entry
		entry.gift = nil
		local present = PopInHouses.open(entry, e.stop.buildPresent)
		if present then
			gifts += 1
			expect(present.plan.size).toBe(1)
			expect(present.plan.popIn).toBe(true)
			expect(present.plan.jingle).toBe(P.Jingle)
			expect(present.model:IsDescendantOf(entry.room)).toBeTruthy()
			expect(present.prompt.Enabled).toBe(true)
		else
			cookies += 1
			expect(entry.room:FindFirstChild("Cookies") ~= nil).toBeTruthy()
		end
		PopInHouses.close(entry)
	end
	local share = gifts / (gifts + cookies)
	expect(share > 0.4 and share < 0.9).toBeTruthy()
end)

test("an untaken gift is still there next visit; a taken one isn't", function()
	local entry, stop
	for _, e in allEntries() do
		e.entry.gift = nil
		if PopInHouses.giftFor(e.entry) then
			entry, stop = e.entry, e.stop
			break
		end
	end
	local first = PopInHouses.open(entry, stop.buildPresent)
	PopInHouses.close(entry)
	local second = PopInHouses.open(entry, stop.buildPresent)
	expect(second ~= nil and second ~= first).toBeTruthy()
	second.taken = true
	PopInHouses.close(entry)
	expect(PopInHouses.open(entry, stop.buildPresent)).toBeNil()
	PopInHouses.close(entry)
end)

test("a pop-in gift is worth a Near present and only a token of Jingle", function()
	local plan = Loot.planPopIn()
	local st = Loot.newPlayerState()
	local jingle = st.jingle
	expect(Loot.grab(st, plan)).toBe(true)
	expect(st.jingle).toBe(jingle + P.Jingle)
	expect(st.sackValue).toBe(Loot.presentValue(1, Config.Rings.Near.LootMultiplier, 0))
	expect(P.Jingle < Loot.jingleForGrab(1)).toBeTruthy()
end)

test("the route stays inside the phone budget with MaxOpen rooms open on a stop", function()
	local stop = route.stops[1]
	for i = 1, P.MaxOpen do
		PopInHouses.open(stop.popIns[i], stop.buildPresent)
	end
	local n = countParts(route.model)
	print(string.format("  [budget] route with %d pop-in rooms open: %d parts", P.MaxOpen, n))
	expect(n < 9000).toBeTruthy()
	local lights = 0
	for _, d in route.model:GetDescendants() do
		if d:IsA("Light") then
			lights += 1
		end
	end
	expect(lights < 200).toBeTruthy()
	for i = 1, P.MaxOpen do
		PopInHouses.close(stop.popIns[i])
	end
end)

test("pop-in rooms are kept out of Detail's culling and nothing in them casts a shadow it shouldn't", function()
	local e = allEntries()[2]
	PopInHouses.open(e.entry, e.stop.buildPresent)
	expect(e.entry.room:GetAttribute("KeepDetail")).toBe(true)
	expect(e.entry.block:GetAttribute("KeepDetail")).toBe(true)
	expect(e.entry.door:GetAttribute("KeepDetail")).toBe(true)
	for _, p in e.entry.room:GetDescendants() do
		if p:IsA("BasePart") then
			expect(p.Anchored).toBe(true)
			if p.Material == Enum.Material.Neon then
				expect(p.CastShadow).toBe(false)
			end
		elseif p:IsA("Light") then
			expect(p.Shadows).toBe(false)
		end
	end
	PopInHouses.close(e.entry)
end)
