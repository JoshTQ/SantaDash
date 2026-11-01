--[[
	Sleigh Heist tuning numbers.

	Every balance number lives here so tuning never touches systems code.
	Source of truth: game-design.md ("The game cycle", "Distance from the sleigh",
	"Random events"). Anything marked GREYBOX is a stand-in until the real system
	(Krampus, threats, elf bots, saving) is built.
]]

local Config = {}

-- One run = 4 stops (3 houses + finale), 2:00 a stop, about 8 minutes.
Config.Run = {
	Stops = 4,
	StopSeconds = 120,
	LightsOnAt = 45, -- 0:00-0:45 sneak phase, then lights come on and Heat rises
	HornAt = 90, -- horn blasts at 1:30: 30 s to get back on
	FlightSeconds = 5, -- sleigh hop between roofs (take-off is 0:00-0:05)
	FlightArcHeight = 60,
	ResultsSeconds = 10,
	RequeueSeconds = 5, -- "Next run in 5..." auto-requeue
	FinaleEscapeMultiplier = 2, -- escaping Stop 4 doubles all loot
	LeaveEarlyWhenAllAboard = true, -- after the horn, leave as soon as the whole crew is on
}

-- Sleigh Station hub and matchmaking.
Config.Lobby = {
	CrewMax = 6,
	QuickJoinSeconds = 10, -- a public sleigh departs within 10 s of its first rider
	MaxRunsPerServer = 4, -- concurrent routes built in one server
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

-- House Cards. Threat AI is not in the greybox yet, but the threat count still
-- drives the +25% loot per threat and the extra noise in Risky houses.
Config.Houses = {
	Types = {
		Cosy = { Threats = 0, Label = "COSY", RoofColor = Color3.fromRGB(150, 215, 255) },
		Normal = { Threats = 1, Label = "NORMAL", RoofColor = Color3.fromRGB(255, 205, 70) },
		Risky = { Threats = 2, Label = "RISKY", RoofColor = Color3.fromRGB(230, 60, 60) },
	},
	-- Escalation: Stop 1 is mostly Cosy with no Risky houses; Stop 2+ use the street mix.
	StopWeights = {
		[1] = { Cosy = 70, Normal = 30, Risky = 0 },
		Default = { Cosy = 40, Normal = 40, Risky = 20 },
	},
	MinCosyPerStreet = 1, -- always at least one Cosy house on every street
	ThreatLootBonus = 0.25,
	PresentsPerHouse = { Near = 5, Mid = 4, Far = 4 },
	RiskyExtraPresents = 1,
}

-- Present value follows the size-squared rule: value = BaseValue * size^2.
Config.Presents = {
	BaseValue = 10,
	Sizes = {
		{ Size = 1, Weight = 60 },
		{ Size = 1.5, Weight = 30 },
		{ Size = 2, Weight = 10 },
	},
	GrabHoldSeconds = 0.4,
	JinglePerGrab = 50, -- multiplied by the ring's loot multiplier
	VaultPresents = 3,
	VaultPresentSize = 2.5,
	OnFootPresents = 3, -- hidden loot on the walk between stops (TranZit)
	OnFootMultiplier = 2.5,
	NaughtyListValue = 250, -- the finale's prize in Krampus's Lair
}

Config.Sack = {
	Capacity = 15,
	-- GREYBOX assumption: your sack is banked into the sleigh each time you
	-- leave a stop on board, so the sack limit is per stop.
	BankOnBoard = true,
}

-- Jingle: in-run only, gone at the end, NEVER sold for Robux.
Config.Jingle = {
	Start = 500,
}

Config.Buys = {
	VaultDoor = { Cost = 1000 }, -- locked Far-ring room, opens for the whole crew
	PeppermintRush = { Cost = 1500, WalkSpeed = 22 }, -- cocoa machine, Near ring
}

-- Shared street noise meter, reset every stop.
Config.Noise = {
	Max = 100,
	PerGrab = 4,
	PerBuy = 2,
	LightsOnPerSecond = 0.3, -- Heat after the lights come on
	PerThreatMultiplier = 0.25, -- each threat in the house adds 25% to grab noise
	StopMultiplier = { 1, 1.25, 1.5, 1.75 }, -- noise fills faster each stop
	-- GREYBOX: Krampus isn't built (model awaiting approval). Until he is, a full
	-- meter blows the horn early and the sleigh leaves in EarlyHornSeconds.
	OnFull = "EarlyHorn",
	EarlyHornSeconds = 15,
}

-- Krampus. UNDECIDED: game-design.md says he arrives from Stop 2 in "The game
-- cycle" and "Krampus is coming", but from Stop 3 in "Escalation by stop".
-- Change FirstStop here once Josh picks; no systems code needs to change.
Config.Krampus = {
	FirstStop = 2,
	Enabled = false, -- GREYBOX: no Krampus AI until his model is approved
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
	LairSize = Vector3.new(48, 18, 48),
	SideOffset = 34, -- house centre distance from the road centre line
	RoadWidth = 24,
}

return Config
