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
	FlightArcHeight = 60, -- cruise height; SleighFlight does the ground run, climb and glide
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
	-- Roblox's cloud calls fail now and then (throttling, flood limits):
	-- MemoryStore, MessagingService and teleports are tried this many times,
	-- waiting RetryBackoffSeconds, then twice that, between tries.
	Attempts = 3,
	RetryBackoffSeconds = 1,
}

-- Crash and error analytics (server/Telemetry.luau): script errors (server
-- and client), warnings and matchmaking events are counted per server and
-- sent to Roblox's Custom Events (Creator Dashboard > Analytics) every
-- FlushSeconds. No names or chat text are ever sent.
Config.Telemetry = {
	FlushSeconds = 60,
	SignatureLength = 90, -- characters kept from an error message
	MaxSignaturesPerFlush = 25, -- the rest are counted as "Other"
	ClientErrorsPerPlayer = 20, -- reports accepted per player per server
}

Config.Player = {
	WalkSpeed = 16,
}

-- Hazard bumps (security dogs): a LinearVelocity push for a moment, so it
-- works on client-owned Santas (server/Knockback.luau).
Config.Knockback = {
	Lift = 18, -- studs/s upward: a little hop off the ground
	Seconds = 0.2, -- how long the push holds before physics takes over
	MaxForce = 100000, -- beats Humanoid ground friction, not the map
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
	-- He stands still this long when he arrives: the KrampusArrives cutscene
	-- (4 s) plus Config.Cutscenes.KrampusGrace. Without cutscenes, a 3 s warning.
	WarningSeconds = 3,
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
			-- Lighting has an Atmosphere (Main.server), and Roblox ignores FogEnd
			-- while one exists, so the blizzard thickens the Atmosphere instead.
			AtmosphereDensity = 0.55,
			AtmosphereHaze = 3,
			SnowRatePhone = 200, -- snowflake particles/s on touch screens (600 elsewhere)
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

-- Short slapstick cutscenes (src/shared/Cutscenes.luau). Josh, 2 Nov 2026:
-- all five, one version each that plays every time; any player can skip.
Config.Cutscenes = {
	Enabled = true,
	MaxSeconds = 5, -- no scene runs longer than this
	KrampusGrace = 2, -- seconds Krampus still waits after his intro ends
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

-- Saved player data (server/PlayerData.luau): one DataStore for both places.
Config.PlayerData = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
	LockSeconds = 180, -- a session lock older than this (crashed server) is taken over
	LoadAttempts = 6, -- a teleport can arrive before the old server lets go
	RetrySeconds = 2,
	SaveInStudio = false, -- Studio plays use fresh defaults and save nothing
}

-- Results: loot becomes Coal, saved in PlayerData.
Config.Coal = {
	PerLootValue = 1,
}

-- Store and holiday monetisation (game-design.md "Monetisation";
-- server/Store.luau, shared/StoreRules.luau). Rules that never bend:
--   * Jingle, Mythic and Secret are never sold or boosted for Robux.
--   * No purchase prompt in a player's first 3 minutes of play (all items).
--   * Paid random boosts show their odds and are hidden from players
--     PolicyService restricts (ArePaidRandomItemsRestricted).
-- assetId 0 = not created on the Creator Dashboard yet: listed but never prompted.
-- ready = false: the thing it powers isn't built yet (or its art isn't
-- approved), so it stays hidden. from / to: UTC dates it is on sale
-- ("YYYY-MM-DD", to is the last day).
Config.Store = {
	NoPromptSeconds = 180,
	FastSneakBonus = 3, -- walk speed added during the sneak phase (16 -> 19; Peppermint Rush is 22)
	HolidayFrom = "2026-12-06", -- first holiday bundle (Grow a Garden started Dec 6 last year)
	HolidayAllBy = "2026-12-20", -- every holiday item live before the gifted-Robux spike
	HolidayTo = "2027-01-05", -- holiday shop's last day
	-- Staging only: show dated items any day, so they can be tested now.
	IgnoreDates = false,
	Items = {
		{
			id = "StarterSack",
			kind = "Product",
			assetId = 0,
			price = 25,
			once = true,
			name = "Starter Sack",
			blurb = "1,000 Coal and 2 Instant Break-outs. One per player.",
			grants = { coal = 1000, inventory = { InstantBreakout = 2 } },
			ready = true,
		},
		{
			id = "TwoXLoot",
			kind = "Pass",
			assetId = 0,
			price = 149,
			name = "2X Loot",
			blurb = "Double the Coal from every run you finish.",
			grants = { perk = "TwoXLoot" },
			ready = true,
		},
		{
			id = "BiggerSack2",
			kind = "Pass",
			assetId = 0,
			price = 79,
			name = "Bigger Sack 2X",
			blurb = "Carry twice as many presents per stop.",
			grants = { perk = "BiggerSack2" },
			ready = true,
		},
		{
			id = "BiggerSack3",
			kind = "Pass",
			assetId = 0,
			price = 179,
			name = "Bigger Sack 3X",
			blurb = "Carry three times as many presents per stop.",
			grants = { perk = "BiggerSack3" },
			ready = true,
		},
		{
			id = "BiggerSack5",
			kind = "Pass",
			assetId = 0,
			price = 449,
			name = "Bigger Sack 5X",
			blurb = "Carry five times as many presents per stop.",
			grants = { perk = "BiggerSack5" },
			ready = true,
		},
		{
			id = "FastSneak",
			kind = "Pass",
			assetId = 0,
			price = 99,
			name = "Fast Sneak",
			blurb = "Tiptoe faster while the house is asleep.",
			grants = { perk = "FastSneak" },
			ready = true,
		},
		{
			id = "InstantBreakout",
			kind = "Product",
			assetId = 0,
			price = 15,
			name = "Instant Break-out",
			blurb = "Pop out of Krampus's basket right away.",
			grants = { inventory = { InstantBreakout = 1 } },
			ready = true,
		},
		{
			id = "SantasBlessing",
			kind = "Product",
			assetId = 0,
			price = 99,
			name = "Santa's Blessing",
			blurb = "2X loot for everyone on this server for 10 minutes. Your name goes up in lights!",
			grants = { blessing = true },
			runServerOnly = true, -- it boosts the runs on this server
			ready = true,
		},
		{
			id = "LuckySack",
			kind = "Product",
			assetId = 0,
			price = 29,
			name = "Lucky Sack",
			blurb = "x3 luck for Rare, Epic and Legendary presents in your next run.",
			grants = { inventory = { LuckySack = 1 } },
			paidRandom = true, -- changes the odds of a random reward
			luck = 3,
			ready = false, -- needs present rarities (Grotto unwrap)
		},
		{
			id = "NaughtyPass",
			kind = "Pass",
			assetId = 0,
			price = 399,
			name = "Naughty Pass",
			blurb = "The paid track of this season's 25 tiers.",
			grants = { perk = "NaughtyPass" },
			ready = false, -- pass tiers not built
		},
		{
			id = "VIPGrotto",
			kind = "Pass",
			assetId = 0,
			price = 299,
			name = "VIP Grotto",
			blurb = "Gold sleigh, VIP name tag and an extra shelf.",
			grants = { perk = "VIPGrotto" },
			ready = false, -- Grotto not built; gold sleigh needs art approval
		},
		{
			id = "HolidayBundle",
			kind = "Product",
			assetId = 0,
			price = 199,
			once = true,
			name = "Holiday Bundle",
			blurb = "A Christmas suit, 2,500 Coal and a Santa's Blessing.",
			grants = { coal = 2500, blessing = true, cosmetic = "HolidaySuit" },
			from = "2026-12-06",
			to = "2027-01-05",
			ready = false, -- suit art approved (Ugly Jumper); waits for the Meshy import
		},
		{
			id = "ChristmasEveSuit",
			kind = "Product",
			assetId = 0,
			price = 149,
			once = true,
			name = "Christmas Eve Suit",
			blurb = "Only on sale over Christmas. Becomes a Legacy suit in January.",
			grants = { cosmetic = "ChristmasEveSuit" },
			from = "2026-12-20",
			to = "2027-01-05",
			ready = false, -- art approved (Midnight Frost); waits for the Meshy import
		},
		{
			id = "SharkySuit",
			kind = "Product",
			assetId = 0,
			price = 149,
			once = true,
			name = "Sharky Claus",
			blurb = "Santa in a shark costume. Leaves bubbles behind; his Cheer goes chomp-chomp.",
			grants = { cosmetic = "SharkySuit" },
			ready = false, -- art approved; waits for the Meshy import
		},
		{
			id = "ChromeSuit",
			kind = "Product",
			assetId = 0,
			price = 149,
			once = true,
			name = "Chrome Puffer",
			blurb = "A shiny silver puffer that glints as you run; his Cheer pops a rainbow.",
			grants = { cosmetic = "ChromeSuit" },
			ready = false, -- art approved; waits for the Meshy import
		},
	},
}

--[[
	Santa suits (skins). The id is the key in PlayerData's owned table, so a
	store item's grants.cosmetic unlocks it; "free" suits everyone has.
	model: the ServerStorage.Assets model whose "Body" mesh replaces the
	classic Santa's (same rig, so every clip still plays). nil = classic.
	Effects are cosmetic only: a trail while moving and a burst on Cheer,
	trimmed on phones (client/SkinEffects.client.luau).
]]
Config.Skins = {
	Default = "Classic",
	List = {
		{ id = "Classic", name = "Classic Santa", free = true },
		{
			id = "HolidaySuit",
			name = "Ugly Jumper",
			model = "SantaJumper",
			howTo = "In the Holiday Bundle (Dec 6 to Jan 5)",
			trail = { Color3.fromRGB(220, 40, 50), Color3.fromRGB(40, 150, 80) },
			cheer = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 40, 50) }, count = 24 },
		},
		{
			id = "ChristmasEveSuit",
			name = "Midnight Frost",
			model = "SantaFrost",
			howTo = "On sale Dec 20 to Jan 5",
			trail = { Color3.fromRGB(190, 230, 255), Color3.fromRGB(120, 160, 255) },
			cheer = { colors = { Color3.fromRGB(124, 245, 208), Color3.fromRGB(176, 124, 255) }, count = 30 },
		},
		{
			id = "SharkySuit",
			name = "Sharky Claus",
			model = "SantaShark",
			howTo = "Sharky Claus in the shop",
			trail = { Color3.fromRGB(170, 220, 255), Color3.fromRGB(58, 123, 213) },
			cheer = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 220, 255) }, count = 20 },
		},
		{
			id = "ChromeSuit",
			name = "Chrome Puffer",
			model = "SantaChrome",
			howTo = "Chrome Puffer in the shop",
			trail = { Color3.fromRGB(230, 235, 250), Color3.fromRGB(255, 78, 138) },
			cheer = {
				colors = {
					Color3.fromRGB(255, 78, 138),
					Color3.fromRGB(255, 184, 74),
					Color3.fromRGB(74, 184, 255),
				},
				count = 28,
			},
		},
	},
	PhoneEffectScale = 0.5, -- phones get half the particles and a shorter trail
}

-- Boots (Josh, 6 Nov 2026): bought once with Coal and kept for good; they
-- make you faster on ice and play the Skate clip there. Worn over any suit
-- (shared/GearAttach.luau). Robux boot styles come later: cosmetic only,
-- and they need the Coal boots for the speed (style = true, base = id).
-- ready = false: the model isn't approved and imported yet, so it's hidden.
Config.Boots = {
	List = {
		{
			id = "SkateBoots",
			name = "Blade Skates",
			model = "SkateBoots", -- ServerStorage.Assets: LeftBoot + RightBoot on the foot bones
			coal = 1500, -- about 2-3 finished runs; the Starter Sack's 1,000 gets you most of the way
			skateSpeed = 30, -- WalkSpeed on ice (Config.Canal.SkateSpeed without boots)
			hoopSpeed = 46, -- WalkSpeed after a boost hoop (Config.Canal.HoopSpeed without)
			blurb = "Faster on the ice, and you skate instead of shuffle. Yours for good.",
			trail = Color3.fromRGB(255, 217, 102), -- the gold scratch line
			ready = false, -- 3D preview awaiting Josh's approval, then Meshy + import
		},
	},
}

-- Gear worn on top of any suit (shared/GearAttach.luau): boots, and the
-- Lair's warm clothes. Built once, fits every suit (Josh, 6 Nov 2026).
Config.Gear = {
	-- Other names a bone may have in an imported rig (canonical name first
	-- in GearAttach.boneNames). Matched case-insensitively.
	BoneNames = {
		LeftFoot = { "LeftAnkle", "mixamorig:LeftFoot", "L_Foot" },
		RightFoot = { "RightAnkle", "mixamorig:RightFoot", "R_Foot" },
		LeftHand = { "LeftWrist", "mixamorig:LeftHand", "L_Hand" },
		RightHand = { "RightWrist", "mixamorig:RightHand", "R_Hand" },
		Head = { "mixamorig:Head" },
		Neck = { "neck", "mixamorig:Neck" },
		Spine = { "Spine01", "Spine02", "Chest", "mixamorig:Spine" },
		Hips = { "Pelvis", "mixamorig:Hips" },
	},
	-- Per-suit nudges (suit id -> bone -> CFrame in bone space) for bulky
	-- suits. Empty until a Studio check shows one is needed (docs/PLAYTEST.md).
	SuitNudge = {} :: { [string]: { [string]: CFrame } },
	FollowDistance = 150, -- clients only move gear on Santas this close
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

-- Frozen Canal Town (Maps/FrozenCanal, server/CanalTown). Josh's picks, 1 Nov
-- 2026: Christmas Market with security dogs, skate lanes with boost hoops,
-- Ice Rink Square, floe hop at the Lair.
Config.Canal = {
	SkateSpeed = 24, -- WalkSpeed on Ice (a boost, not custom physics)
	HoopSpeed = 40, -- WalkSpeed for a moment after flying through a boost hoop
	HoopBoostSeconds = 1.5,
	Width = 44, -- the main canal between stops (runs along the on-foot path)
	SegmentLength = 100, -- canal ice is split so Thin Ice can break one piece
	StopEndClear = 30, -- canal ice this close to a stop is never CrackZone
	IceTop = 0.25, -- top of canal and lake ice
	FloeTop = 0.9, -- floes sit proud of the water so the hop reads
	FloeCell = 11, -- floe grid pitch; floes are 7-8 studs with ~3-4 stud gaps
	Promenade = 6, -- pavement width either side of a street canal
	Dogs = {
		Count = 4, -- Stop 1 market, mixed Corgi Patrol and Tin Sausage Dog
		Speed = 9, -- slower than a walking Santa (16), so you can dodge them
		HitRadius = 4,
		Knockback = 40,
		CorgiCooldown = 5, -- seconds before the same corgi can ram you again
		TinWindDown = 3, -- a tin dog stops for this long after a bonk
		WarnRadius = 14, -- a dog growls (corgi) or whirrs (tin) at Santas this close
	},
	Polisher = { AngularSpeed = 0.35, HitRadius = 5 }, -- Ice Rink Square, Stop 2
	-- Dogs and the polisher only bump Santas near their own level (studs of
	-- root height under / over the hazard's ground point), not on roofs above.
	Hazards = { Below = 2, Above = 7 },
	-- A root no more than this over its standing height above the water (and
	-- not over a floe) means SPLOOSH; higher is a hop. Floes sit FloeTop -
	-- IceTop (0.65) proud, so a Santa on a floe never counts.
	SplashSlack = 0.4,
	FloeEdgeGrace = 0.75, -- root this far past a floe's edge still has a foot on it
	StompDelay = 8, -- Lair: seconds after landing before Krampus stomps the lake into floes
	-- Forest and snowy hills around the town (Josh, 2 Nov: "not just totally flat").
	Woodland = {
		Band = 260, -- studs of forest either side of each street (stops are 700 apart)
		Inner = 90, -- forest starts this far from the street's centre line
		Edge = 160, -- forest depth around the outside of the town
		TreeSpacing = 30,
		TreeChance = 0.55,
		TreeHeight = { 16, 30 },
		LitChance = 0.15, -- trees wrapped in Christmas lights
		HillArea = 9000, -- one hill per this many square studs of forest
		HillRadius = { 26, 60 },
		HillHeight = { 10, 22 }, -- rounder bumps keep the sunk balls small
	},
	LightColours = { -- Christmas bulbs: red, gold, green, blue, pink
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 205, 80),
		Color3.fromRGB(90, 230, 120),
		Color3.fromRGB(90, 160, 255),
		Color3.fromRGB(255, 120, 210),
	},
}

-- Sound mix (Sounds.luau has the catalogue). Phone speakers clip easily, so
-- groups stay below 1 and music sits well under the effects.
Config.Audio = {
	Enabled = true,
	MusicEnabled = true,
	Groups = { Sfx = 0.8, Ui = 0.7, Music = 0.35, Ambience = 0.4 },
	FolderName = "SoundAssets", -- ReplicatedStorage.SoundAssets: Sounds named by key override the ids
	MusicFade = 1.2, -- seconds to cross-fade between music loops
}

return Config
