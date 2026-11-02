--[[
	Frozen Canal Town (Josh picked concept C, 1 Nov 2026: "more fun and
	elaborate"). Each street is a frozen canal with pavements, front gardens,
	hedges and picket fences; a main canal with boost hoops joins the stops
	(it is also the on-foot route if you miss the sleigh).

	Stop space (+Z runs down the street from the landing house):
	  street canal  x -14..14 (the Road, in Ice), pavements out to x +/-20
	  houses        x +/-46, fronts and doors facing the canal
	  Sleigh Stop   a plaza on the right bank across from the landing house
	  main canal    along z = -40 to the next stop
	  Stop 1        Christmas Market + security dogs (z 50..400)
	  Stop 2        Ice Rink Square at z 230 + the ice polisher
	  Stop 3        the street opens onto a lake; the Lair sits on an island,
	                reached by the bell bridge. Krampus stomps, the lake
	                breaks into floes (floe hop).
	The geometry is built by server/CanalTown; numbers live in Config.Canal.
]]

local LANDING = CFrame.new(38, 0, 6) -- the plaza on the right bank
local ISLAND = Vector3.new(0, 0, 470) -- the Lair's island in the lake

return {
	id = "FrozenCanal",
	name = "Frozen Canal Town",
	palette = {
		Ground = { Color3.fromRGB(236, 242, 252), Enum.Material.Snow },
		Road = { Color3.fromRGB(175, 220, 245), Enum.Material.Ice }, -- the street canals
		Path = { Color3.fromRGB(175, 220, 245), Enum.Material.Ice }, -- under the main canal
	},
	layout = {
		SideOffset = 46,
		RoadWidth = 28,
		StreetStart = -20, -- the street canal meets the main canal
		FootPathZ = -40, -- the main canal runs along the on-foot path
		CocoaMachine = Vector3.new(24, 3.5, 32), -- by the Sleigh Stop plaza
		LandingAt = { LANDING, LANDING, LANDING },
		EndHouseAt = {
			Finale = CFrame.lookAt(ISLAND, Vector3.zero), -- Lair island
		},
	},
	features = {
		{ kind = "CanalStreet" }, -- pavements, gardens, hedges, fences, canal barriers
		{ kind = "Woodland" }, -- pine forest and snowy hills around the town
		{ kind = "SkateCanal" }, -- main canal, boost hoops, skating, Thin Ice segments
		{ kind = "ChristmasMarket", stops = { 1 } }, -- stalls + security dogs
		{ kind = "IceRink", stops = { 2 }, centre = Vector3.new(0, 0, 230), radius = 46 },
		{
			kind = "FloeLake",
			stops = { 3 },
			from = 300, -- lake starts this far down the street
			to = 640,
			halfWidth = 150,
			island = ISLAND,
			islandRadius = 58, -- room for the Lair (48 wide), its fence, lanterns and trees
		},
	},
	-- Random map events (MapEvents, from the events work): Blizzard at launch.
	events = { { kind = "Blizzard", weight = 1 } },
	dressing = nil,
}
