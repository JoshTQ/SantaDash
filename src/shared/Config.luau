--[[
	Sleigh Heist tuning numbers.

	Every balance and layout number lives here so tuning never touches systems
	code. Source of truth: game-design.md ("The game cycle", "Distance from the
	sleigh", "Random events", "Krampus is coming"). Anything marked GREYBOX is a
	stand-in until the real system or approved model exists.
]]

local Config = {}

-- 15 Nov launch slice: two house stops + Krampus's Lair, 2:00 a stop, about
-- 6 minutes. The full route (3 streets + finale) follows in late November.
Config.Run = {
	StopKinds = { "Street", "Street", "Finale" },
	StopSeconds = 120,
	LightsOnAt = 45, -- 0:00-0:45 sneak phase, then lights come on and Heat rises
	HornAt = 90, -- horn blasts at 1:30: 30 s to get back on
	FlightSeconds = 5, -- sleigh hop between roofs (take-off is 0:00-0:05)
	FlightArcHeight = 60,
	ResultsSeconds = 10,
	RequeueSeconds = 5, -- "Next run in 5..." auto-requeue
}

-- What each kind of stop contains. Slots index Config.Street.Slots.
Config.StopKinds = {
	Street = {
		-- Launch slice: Near and Far rings only. Add 2, 3, 4 for the Mid ring later.
		Slots = { 1, 5, 6 },
		EndHouse = "Vault",
		Banner = "Stop %d: sneak in, grab presents. Further = better loot!",
	},
	Finale = {
		Slots = { 1 },
		ForceType = "Risky", -- every house but the landing house
		EndHouse = "Lair",
		Banner = "KRAMPUS'S LAIR! Steal the Naughty List and escape to double your loot!",
		EscapeMultiplier = 2, -- escaping the finale doubles all loot
	},
}

-- Sleigh Station hub and matchmaking.
Config.Lobby = {
	CrewMax = 6,
	QuickJoinSeconds = 10, -- a public sleigh departs within 10 s of its first rider
	MaxRunsPerServer = 4, -- concurrent routes built in one server
}

-- Cross-server matchmaking (Josh, 1 Nov 2026): the lobby place queues crews
-- and teleports each into its own reserved server of the run place. 0 = not
-- published yet; then everything runs in one place (Studio, offline tests).
Config.Places = {
	Lobby = 0,
	Run = 0,
	ArrivalTimeoutSeconds = 15, -- the run starts with whoever arrived by then
}

-- Lobby-side matchmaking (cross-server). Public riders and Party groups go into
-- one MemoryStore queue shared by every lobby server; any lobby server packs
-- them into crews, reserves a run server and tells the riders' servers to
-- teleport them. Private sleighs never touch the shared queue.
Config.Matchmaking = {
	QueueName = "SleighHeist_PublicCrews_v1",
	Topic = "SleighHeist_CrewReady_v1",
	CancelledMapName = "SleighHeist_HoppedOff_v1", -- riders who got off after queueing
	PackEverySeconds = 2, -- how often each lobby server tries to form crews
	ReadBatch = 50, -- tickets read per pack (MemoryStore max is 100)
	InvisibleSeconds = 30, -- a read batch is hidden from other servers while one server packs it
	TicketTTLSeconds = 120, -- a ticket nobody packed in this long is dropped
	PublicWaitSeconds = 12, -- a crew leaves part-full once its oldest rider waited this long (bots fill)
	PartyFillSeconds = 8, -- a Party group waits this long for randoms to top it up
	LocalFallbackSeconds = 25, -- no crew by then (MemoryStore down): leave with whoever is on this server
}

Config.Player = {
	WalkSpeed = 16,
}

-- Distance rings around the sleigh: further = better loot, longer run back.
-- Distance is studs down the street from the landing house (16 studs/s walk).
Config.Rings = {
	Near = { Distance = 0, LootMultiplier = 1 },
	Mid = { Distance = 200, LootMultiplier = 1.5 },
	Far = { Distance = 440, LootMultiplier = 2.5 },
}

-- Street layout. Side: -1 left of the road, 1 right. Extra: studs past the ring.
Config.Street = {
	Slots = {
		{ Ring = "Near", Side = -1, Extra = 0 }, -- the landing house
		{ Ring = "Mid", Side = 1, Extra = 0 },
		{ Ring = "Mid", Side = -1, Extra = 0 },
		{ Ring = "Mid", Side = 1, Extra = 50 },
		{ Ring = "Far", Side = -1, Extra = 0 },
		{ Ring = "Far", Side = 1, Extra = 0 },
	},
}

-- House Cards. Threat AI (residents, pets, gadgets) is not in the greybox yet,
-- but the threat count still drives +25% loot per threat and extra grab noise.
Config.Houses = {
	Types = {
		Cosy = { Threats = 0, Label = "COSY", RoofColor = Color3.fromRGB(150, 215, 255) },
		Normal = { Threats = 1, Label = "NORMAL", RoofColor = Color3.fromRGB(255, 205, 70) },
		Risky = { Threats = 2, Label = "RISKY", RoofColor = Color3.fromRGB(230, 60, 60), ExtraPresents = 1 },
		-- End-of-street houses: always Far ring, fixed contents.
		Vault = {
			Threats = 0,
			Label = "VAULT",
			RoofColor = Color3.fromRGB(255, 200, 60),
			Presents = 3,
			PresentSize = 2.5,
			Locked = true, -- opens for the whole crew for Config.Buys.VaultDoor.Cost
			NoChimney = true,
			Extra = 60,
		},
		Lair = {
			Threats = 2,
			Label = "KRAMPUS'S LAIR",
			RoofColor = Color3.fromRGB(90, 40, 120),
			Presents = 8,
			Size = Vector3.new(48, 18, 48),
			HideSpots = 2,
			NaughtyList = true,
			Extra = 30,
		},
	},
	-- Escalation: Stop 1 is mostly Cosy with no Risky houses; later stops use the street mix.
	StopWeights = {
		[1] = { Cosy = 70, Normal = 30, Risky = 0 },
		Default = { Cosy = 40, Normal = 40, Risky = 20 },
	},
	MinCosyPerStreet = 1, -- always at least one Cosy house on every street
	ThreatLootBonus = 0.25,
	PresentsPerHouse = { Near = 5, Mid = 4, Far = 4 },
	HideSpots = 1, -- wardrobes per house, unless the type says otherwise
}

-- Present value follows the size-squared rule: value = BaseValue * size^2.
Config.Presents = {
	BaseValue = 10,
	Sizes = { { 1, 60 }, { 1.5, 30 }, { 2, 10 } }, -- { size, weight }
	GrabHoldSeconds = 0.4,
	JinglePerGrab = 50, -- multiplied by the ring's loot multiplier
	OnFootPresents = 3, -- hidden loot on each walk between stops (TranZit)
	OnFootMultiplier = 2.5,
	NaughtyListValue = 250, -- the finale's prize in Krampus's Lair
}

-- GREYBOX assumption: your sack is banked into the sleigh each time you leave
-- a stop on board, so the sack limit is per stop.
Config.Sack = {
	Capacity = 15,
	-- Missing the final sleigh: you keep this share of your unbanked sack
	-- (Josh, 1 Nov 2026: lose 50%). Banked loot is always kept.
	MissedFinalKeep = 0.5,
}

-- Jingle: in-run only, gone at the end, NEVER sold for Robux.
Config.Jingle = {
	Start = 500,
}

Config.Buys = {
	VaultDoor = { Cost = 1000 }, -- locked Far-ring room, opens for the whole crew
	PeppermintRush = { Cost = 1500, WalkSpeed = 22 }, -- cocoa machine, Near ring
}

-- Shared street noise meter, reset every stop. A full meter brings Krampus.
Config.Noise = {
	Max = 100,
	PerGrab = 4,
	PerBuy = 2,
	LightsOnPerSecond = 0.3, -- Heat after the lights come on
	PerThreatMultiplier = 0.25, -- each threat in the house adds 25% to grab noise
	StopMultiplier = { 1, 1.25, 1.5, 1.75 }, -- noise fills faster each stop
	Gasp = 10, -- running out of breath in a hiding spot
}

-- Krampus (game-design.md "The danger: Krampus is coming"). He arrives from
-- FirstStop (Josh, 1 Nov 2026: Stop 3, the Lair in the launch slice), when the
-- noise meter fills or automatically after ArriveAt.
-- Proposed, awaiting Josh: a no-chase tease from TeaseFrom (distant bells).
-- GREYBOX: block stand-in in the approved Shaggy Goat Grump colours until the
-- Meshy mesh exists; a Model named "Krampus" in ServerStorage.Assets replaces it.
Config.Krampus = {
	FirstStop = 3,
	NoiseArrivalFrom = 3,
	TeaseEnabled = false,
	TeaseFrom = 1,
	TeaseAt = 30, -- seconds into a stop
	ArriveAt = 45, -- seconds into an automatic stop (with the lights)
	WarningSeconds = 3, -- "KRAMPUS IS COMING" before he appears
	WalkSpeed = 14, -- slower than a Santa (16), so running works
	CarrySpeed = 10,
	SenseRange = 70, -- sees and sniffs players this close, unless hidden
	CatchRange = 6,
	RepathSeconds = 0.75,
	-- Rescue: ring the hand bells behind him and he spins and drops the basket.
	BellRange = 10,
	StunSeconds = 3,
	BellCooldown = 6,
	ReleaseGrace = 4, -- seconds a dropped Santa can't be re-snatched
	-- Wiggle free: taps needed, the same solo or in a crew (Josh, 1 Nov 2026).
	WiggleTaps = 15,
	-- Hiding: breath drains while he is near; tapping refills it.
	BreathRange = 25,
	BreathSeconds = 5, -- full to empty with no taps
	BreathPerTap = 0.08,
	MaxTapsPerSecond = 8,
	Height = 11, -- about 2.2x a Santa
}

-- Random map events (game-design.md "Random map events"). One roll per run;
-- a hit plays one event from the map's own pool at one stop. Rules: one big
-- moment per stop, never in a Krampus stop, never blocks the way back to the
-- sleigh, always ends before the horn, always has an upside.
-- Josh, 1 Nov 2026: launch = this system + Blizzard; crew snowballs stay harmless.
Config.MapEvents = {
	Chance = 0.6, -- per run
	Stops = { 2 }, -- launch slice: Stop 2 only (Stop 1 = easy, Stop 3 = Lair)
	WarningSeconds = 8, -- banner + sound before it starts
	StartAt = 30, -- seconds into the stop
	MaxSeconds = 55, -- and it always ends before Config.Run.HornAt
	Events = {
		-- Heavy snow: fog closes in, snow muffles noise, free snowballs.
		Blizzard = {
			Enabled = true, -- off switch
			Label = "BLIZZARD",
			Forecast = "Forecast: heavy snow later...",
			Warning = "BLIZZARD IN %d! Snow muffles your noise. Grab snowballs!",
			Ended = "The blizzard has passed.",
			NoiseMultiplier = 0.6, -- all street noise while it snows
			FogEnd = 180, -- studs; keep >= 150 so the sleigh / Lair beams stay readable
			FogColor = Color3.fromRGB(225, 232, 245),
			-- Snow piles in stop space (+Z down the street): the approved Sparkle
			-- Drift (Assets "SnowPile"), or a white block if it isn't imported yet.
			Piles = {
				Vector3.new(-9, 0, 40),
				Vector3.new(9, 0, 140),
				Vector3.new(-9, 0, 260),
				Vector3.new(9, 0, 380),
			},
			PileSnowballs = 6, -- per grab; piles never run out
			PileRegrowSeconds = 6, -- a grabbed ball on the pile model grows back
			MaxSnowballs = 12,
			ThrowSpeed = 110, -- studs/s
			ThrowCooldown = 0.4,
			SnowballLife = 3, -- seconds before a miss melts
			-- Crewmates only get a cosmetic splat (no stun): no griefing strangers.
			SplatSeconds = 1.5,
			SplatMarkSeconds = 2, -- the blue splat decal where a snowball lands
		},
	},
}

-- Elf bots fill in for missing friends in solo runs (game-design.md "Solo").
-- Josh, 1 Nov 2026: bots are a random mix of elf designs A and D. Each
-- variant name is also the Model name to put in ServerStorage.Assets once
-- approved; until then MapBuilder builds a coloured stand-in.
Config.ElfBots = {
	MaxCrewForBots = 1, -- bots join crews this small
	Count = 2,
	Variants = { "ElfA", "ElfD" },
	SoloLootMultiplier = 0.8, -- solo runs pay 80%, so friends are better
	WalkSpeed = 18,
	Height = 4,
	FollowDistance = 8,
	GrabRange = 25, -- presents within this distance of their Santa
	GrabEverySeconds = 3,
	CatchUpDistance = 120, -- further than this (chimney, sleigh) and they hop to their Santa
	RepathSeconds = 0.5,
	StandIn = {
		ElfA = { Body = Color3.fromRGB(60, 170, 80), Hat = Color3.fromRGB(220, 40, 50) },
		ElfD = { Body = Color3.fromRGB(220, 40, 50), Hat = Color3.fromRGB(60, 170, 80) },
	},
}

-- Results: loot becomes Coal. Not saved yet (DataStore comes with the Grotto).
Config.Coal = {
	PerLootValue = 1,
}

Config.Map = {
	StopSpacing = 700, -- studs between stops along the route (about 40 s on foot)
	RouteSpacing = 1600, -- studs between concurrent routes
	RouteOriginZ = 1600, -- first route sits this far from the hub
	HouseSize = Vector3.new(28, 14, 28),
	DoorSize = Vector3.new(8, 12, 0), -- tall enough for Krampus
	SideOffset = 34, -- house centre distance from the road centre line
	RoadWidth = 24,
	StreetStart = -40, -- road starts this far behind the landing house
	StreetOverrun = 120, -- road continues this far past the Far ring
	FootPathZ = -40, -- the on-foot path between stops
	CocoaMachine = Vector3.new(-14, 3.5, 22),
	TakeoffOffset = Vector3.new(-150, 60, 0), -- where the sleigh starts, before Stop 1
	-- The sleigh lands on the ground at each stop's Sleigh Stop (Josh, 1 Nov
	-- 2026): a clearing; you're aboard if you're inside it when it leaves.
	LandingAt = CFrame.new(0, 0, 0), -- stop space: on the road in front of the landing house
	SleighStopRadius = 17, -- also a safe zone: Krampus ignores anyone inside (Josh, 1 Nov)
	DeckHeight = 1.6, -- deck centre above the ground, so the runners clear it
	DeckSize = Vector3.new(10, 1, 14),
	-- Inside the Naughty Workshop on the spawn ring, facing the yard (+Z).
	HubSpawn = CFrame.lookAt(Vector3.new(0, 4.5, -42), Vector3.new(0, 4.5, 0)),
}

-- Sleigh Station lobby layout, matching the interactive 3D preview Josh iterated on (1 Nov).
-- +Z runs from the workshop, through the show-off yard, to the station.
Config.LobbyMap = {
	FloorHeight = 1.5, -- workshop floor and station platform
	Workshop = { X0 = -40, X1 = 40, Z0 = -64, Z1 = -22, Height = 20 },
	Yard = { X0 = -70, X1 = 70, Z0 = -22, Z1 = 92 },
	Platform = { X0 = -40, X1 = 40, Z0 = 46, Z1 = 58 },
	GateZ = 51,
	GateGap = 8, -- studs between the gate barriers
	BoardZone = { Z0 = 52, Z1 = 57.5, HalfWidth = 6 }, -- step in here to sit on the sleigh
	SleighZ = 65,
	Podium = Vector3.new(-38, 0, 8),
	Trophy = Vector3.new(16, 0, 14),
	Wanted = Vector3.new(56, 0, 18),
	Fork = Vector3.new(-2, 0, 33),
	Path = { -- main path from the workshop doors to the fork
		Vector3.new(0, 0, -21),
		Vector3.new(-4, 0, -8),
		Vector3.new(-16, 0, 6),
		Vector3.new(-13, 0, 22),
		Vector3.new(-2, 0, 33),
	},
	-- Bays left to right as you walk up: Public, Party, Private.
	Bays = {
		{ Kind = "Public", Number = 1, X = 26, Colour = Color3.fromRGB(47, 191, 91), Sleigh = "Red" },
		{ Kind = "Party", Number = 2, X = 0, Colour = Color3.fromRGB(61, 123, 255), Sleigh = "Blue" },
		{ Kind = "Private", Number = 3, X = -26, Colour = Color3.fromRGB(138, 92, 255), Sleigh = "Purple" },
	},
	ArriveSeconds = 3, -- sleigh flies in
	BoardSeconds = { Public = 12, Party = 20, Private = 20 }, -- gate open, BOARDING NOW! lit
	DepartSeconds = 5, -- sleigh takes off
	GapSeconds = 3, -- empty bay before the next sleigh
}

return Config
