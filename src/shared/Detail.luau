--[[
	Client-side level of detail for the parts-built maps (phones).

	Workspace.StreamingEnabled stays off (the server sends model refs to
	clients), so every part of a route is on every client all the time. A
	route is ~8,650 parts, and the run place also holds the Sleigh Station
	hub. Most of that is dressing nobody can touch: Christmas bulbs, garlands,
	hedge tops, window frames, roof trim. This module lets each client drop
	far-away dressing out of its own scene and put it back as the camera
	comes closer. It only ever moves parts on the local client, so the server
	and the other players see nothing change.

	Three tiers, by what a part is (Detail.tierOf):
	- Fine: small untouchable bits (mostly the Christmas bulbs). Go first.
	- Dressing: bigger parts that Parts.settle made non-colliding.
	- Solid: anchored colliding scenery (forest pines, bollards, house
	  shells). Phones only, and only far past the next stop: a stop is 700
	  studs from the next, and the Atmosphere hides that far anyway. When the
	  camera jumps (a respawn or a carry), everything near it comes back that
	  same frame, so nobody lands on a floor that isn't there.
	Never hidden: very big parts (ground, roads, canal ice), anything with a prompt, label or Trigger attribute,
	unanchored or invisible parts, and anything inside a model that moves or
	plays (the sleigh, presents, doors, the Lair's clockwork, characters...).

	Parts are grouped into grid cells and each cell is shown or hidden as
	one, with a gap between the hide and show distances so a cell on the
	edge doesn't flicker.

	The server marks the roots to scan with the DetailRoot attribute
	(MapBuilder.buildRoute, LobbyMap.build). Detail.client wires it up.
]]

local Detail = {}

-- Studs per grid cell side.
Detail.CellSize = 48

-- Parts whose biggest side is at most this (studs) are Fine; the rest are
-- Dressing. Matches Parts.TinyShadow.
Detail.FineSize = 2

-- Hide beyond `hide` studs, show again inside `show` (camera to cell box).
export type Band = { hide: number, show: number }
export type Profile = { name: string, Fine: Band, Dressing: Band, Solid: Band }

local NEVER = { hide = math.huge, show = math.huge }

-- The Atmosphere (Density 0.28, Haze 1.2) hides most detail past ~300 studs
-- at night anyway; these keep the street you're on, and the next one along,
-- fully dressed.
Detail.Profiles = {
	Phone = {
		name = "Phone",
		Fine = { hide = 170, show = 150 },
		Dressing = { hide = 420, show = 380 },
		Solid = { hide = 600, show = 520 },
	} :: Profile,
	Desktop = {
		name = "Desktop",
		Fine = { hide = 320, show = 290 },
		Dressing = { hide = 900, show = 850 },
		Solid = NEVER,
	} :: Profile,
}

-- Parts with a side at least this long (ground, roads, the canal ice, big
-- hills) always stay: few parts, and they hold the skyline together.
Detail.KeepSize = 100

-- Most parts moved in one step, so crossing a band never hitches a frame.
Detail.MaxMovesPerStep = 600

-- Seconds between steps.
Detail.StepSeconds = 0.25

-- A camera move this big in one frame is a jump (respawn, snatch, cutscene
-- cut): show everything near the new spot at once, ignoring the budget.
Detail.JumpStuds = 120

-- Models that move, animate or play: nothing inside them is ever hidden.
Detail.KeepModels = {
	Sleigh = true,
	Present = true,
	NaughtyList = true,
	DroppedPresent = true,
	IcePolisher = true,
	LairHouse = true, -- LairAnimator moves the clockwork every frame
	KrampusStandIn = true,
	CocoaMachine = true,
	SnowPile = true,
	Snowball = true,
	FrontDoor = true,
	InnerDoorway = true,
}

-- Phones get the short bands. A touch screen with no keyboard is a phone or
-- tablet; a low graphics quality (1-4 of 10, set by hand) also gets them.
-- quality: Enum.SavedQualitySetting value, 0 = Automatic.
function Detail.profile(touch: boolean, keyboard: boolean, quality: number?): Profile
	if touch and not keyboard then
		return Detail.Profiles.Phone
	end
	if quality and quality > 0 and quality <= 4 then
		return Detail.Profiles.Phone
	end
	return Detail.Profiles.Desktop
end

-- Distance from p to the box [lo, hi] (0 inside).
function Detail.distanceToBox(p: Vector3, lo: Vector3, hi: Vector3): number
	local dx = math.max(lo.X - p.X, 0, p.X - hi.X)
	local dy = math.max(lo.Y - p.Y, 0, p.Y - hi.Y)
	local dz = math.max(lo.Z - p.Z, 0, p.Z - hi.Z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Whether a cell should be shown next, given whether it is shown now.
function Detail.wantShown(shown: boolean, distance: number, band: Band): boolean
	if shown then
		return distance <= band.hide
	end
	return distance <= band.show
end

local function hasKeeper(part: Instance): boolean
	for _, d in part:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("ClickDetector") then
			return true
		end
	end
	return false
end

-- "Fine", "Dressing", "Solid", or nil (never hidden). root: the DetailRoot it sits in.
function Detail.tierOf(part: Instance, root: Instance): string?
	if not part:IsA("BasePart") then
		return nil
	end
	local p = part :: BasePart
	if not p.Anchored or p.Transparency >= 1 then
		return nil
	end
	local solid = p.CanCollide
	if not solid and (p.CanTouch or p.CanQuery) then
		return nil
	end
	if p:GetAttribute("Trigger") or p:GetAttribute("KeepDetail") then
		return nil
	end
	local node = p.Parent
	while node and node ~= root do
		if
			Detail.KeepModels[node.Name]
			or node:FindFirstChildOfClass("Humanoid")
			or node:GetAttribute("KeepDetail")
		then
			return nil
		end
		node = node.Parent
	end
	if node ~= root or hasKeeper(p) then
		return nil
	end
	local s = p.Size
	if math.max(s.X, s.Y, s.Z) >= Detail.KeepSize then
		return nil
	end
	if solid then
		return "Solid"
	end
	return if math.max(s.X, s.Y, s.Z) <= Detail.FineSize then "Fine" else "Dressing"
end

----------------------------------------------------------------------------
-- Culler: owns the cells for any number of roots
----------------------------------------------------------------------------

type Cell = {
	tier: string,
	lo: Vector3,
	hi: Vector3,
	parts: { BasePart },
	homes: { Instance },
	shown: boolean,
	root: Instance,
}

export type Culler = {
	profile: Profile,
	cells: { [string]: Cell },
	nextRoot: number,
	known: { [Instance]: boolean },
	roots: { [Instance]: number },
	hidden: number,
	add: (self: Culler, root: Instance) -> number,
	_rootId: (self: Culler, root: Instance) -> number,
	addPart: (self: Culler, part: Instance, root: Instance) -> boolean,
	drop: (self: Culler, root: Instance) -> (),
	step: (self: Culler, from: Vector3, budget: number?, showOnly: boolean?) -> number,
	showAll: (self: Culler) -> (),
	counts: (self: Culler) -> { cells: number, parts: number, hidden: number },
}

local Culler = {}
Culler.__index = Culler

function Detail.new(profile: Profile): Culler
	return setmetatable({
		profile = profile,
		cells = {},
		roots = {},
		hidden = 0,
		nextRoot = 0,
		known = setmetatable({}, { __mode = "k" }),
	}, Culler) :: any
end

local function keyOf(rootId: number, tier: string, pos: Vector3): string
	local s = Detail.CellSize
	return string.format(
		"%d|%s|%d|%d|%d",
		rootId,
		tier,
		math.floor(pos.X / s),
		math.floor(pos.Y / s),
		math.floor(pos.Z / s)
	)
end

function Culler._rootId(self: Culler, root: Instance): number
	local id = self.roots[root]
	if not id then
		self.nextRoot += 1
		id = self.nextRoot
		self.roots[root] = id
	end
	return id
end

-- Takes one part into a cell if it is dressing. Returns whether it did. A
-- part it already holds (our own re-parenting fires DescendantAdded) is
-- skipped.
function Culler.addPart(self: Culler, part: Instance, root: Instance): boolean
	if self.known[part] then
		return false
	end
	local tier = Detail.tierOf(part, root)
	if not tier then
		return false
	end
	local p = part :: BasePart
	local pos = p.CFrame.Position
	local key = keyOf(self:_rootId(root), tier, pos)
	local cell = self.cells[key]
	local half = p.Size / 2
	if not cell then
		cell = {
			tier = tier,
			lo = pos - half,
			hi = pos + half,
			parts = {},
			homes = {},
			shown = true,
			root = root,
		}
		self.cells[key] = cell
	else
		cell.lo = cell.lo:Min(pos - half)
		cell.hi = cell.hi:Max(pos + half)
	end
	self.known[p] = true
	table.insert(cell.parts, p)
	table.insert(cell.homes, p.Parent :: Instance)
	if not cell.shown then
		-- Joined a hidden cell: hide it with the rest.
		p.Parent = nil
		self.hidden += 1
	end
	return true
end

-- Scans a root. Returns how many parts it took.
function Culler.add(self: Culler, root: Instance): number
	self:_rootId(root)
	local taken = 0
	for _, d in root:GetDescendants() do
		if self:addPart(d, root) then
			taken += 1
		end
	end
	return taken
end

-- Forgets a root (it was destroyed or is about to be): hidden parts are let
-- go with it.
function Culler.drop(self: Culler, root: Instance)
	self.roots[root] = nil
	for key, cell in self.cells do
		if cell.root == root then
			if not cell.shown then
				self.hidden -= #cell.parts
			end
			for _, part in cell.parts do
				self.known[part] = nil
			end
			self.cells[key] = nil
		end
	end
end

local function setShown(self: Culler, cell: Cell, shown: boolean)
	cell.shown = shown
	for i, part in cell.parts do
		if shown then
			local home = cell.homes[i]
			-- A home the server has since removed stays removed.
			-- pcall: the server may have destroyed it while hidden (broken ice).
			if home.Parent ~= nil or home == cell.root then
				pcall(function()
					part.Parent = home
				end)
			end
		else
			pcall(function()
				part.Parent = nil
			end)
		end
	end
	self.hidden += if shown then -#cell.parts else #cell.parts
end

-- One pass from the camera position: shows near cells first, then hides far
-- ones, moving at most `budget` parts. showOnly skips the hiding (a jump).
-- Returns how many it moved.
function Culler.step(self: Culler, from: Vector3, budget: number?, showOnly: boolean?): number
	local left = budget or Detail.MaxMovesPerStep
	local toShow, toHide = {}, {}
	for _, cell in self.cells do
		local band = (self.profile :: any)[cell.tier] :: Band
		local d = Detail.distanceToBox(from, cell.lo, cell.hi)
		local want = Detail.wantShown(cell.shown, d, band)
		if want ~= cell.shown and (want or not showOnly) then
			table.insert(if want then toShow else toHide, { cell = cell, d = d })
		end
	end
	table.sort(toShow, function(a, b)
		return a.d < b.d
	end)
	table.sort(toHide, function(a, b)
		return a.d > b.d
	end)
	local moved = 0
	for _, list in { { toShow, true }, { toHide, false } } do
		for _, entry in list[1] do
			local n = #entry.cell.parts
			-- Always do at least one cell, so a huge cell can't stall forever.
			if moved > 0 and n > left then
				return moved
			end
			setShown(self, entry.cell, list[2])
			moved += n
			left -= n
		end
	end
	return moved
end

-- Puts every hidden part back (cutscenes that sweep the whole map, or turning
-- the culler off).
function Culler.showAll(self: Culler)
	for _, cell in self.cells do
		if not cell.shown then
			setShown(self, cell, true)
		end
	end
end

function Culler.counts(self: Culler)
	local cells, parts = 0, 0
	for _, cell in self.cells do
		cells += 1
		parts += #cell.parts
	end
	return { cells = cells, parts = parts, hidden = self.hidden }
end

return Detail
