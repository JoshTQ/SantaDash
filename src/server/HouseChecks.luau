--[[
	"Who's there?!" checks (Config.LightsCheck, Josh 6 Nov 2026: the lights
	coming on needed a consequence). Started by Run when the lights come on;
	the returned cleanup runs when the sleigh leaves.

	Each lit house, in turn:
	  warning  WarnSeconds of orange flicker, a grumble, "WHO'S THERE?!" over
	           the roof, and a banner for any Santa inside: hide or get out
	  flash    a bright white flash. Every Santa inside who isn't in the
	           wardrobe is SPOTTED: one present falls out of their sack onto
	           the floor (anyone can grab it back), the noise meter jumps,
	           and they're bonked out of the front door.
	The rules (timing, who's inside, where you land) are in LightsCheck.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local DogBump = require(script.Parent.DogBump)
local Knockback = require(script.Parent.Knockback)
local LightsCheck = require(script.Parent.LightsCheck)
local Loot = require(script.Parent.Loot)

local L = Config.LightsCheck
local TICK = 0.1
local FLICKER = 0.15

local HouseChecks = {}

export type House = {
	model: Model,
	light: PointLight,
	box: CFrame,
	size: Vector3,
	exit: CFrame,
	checkAt: number,
	warned: boolean,
	sign: BillboardGui,
	restore: { color: Color3, brightness: number, range: number }?,
}

-- Which way is out of the front of a house: towards the middle of the street
-- (stop.origin's +Z runs down it), for houses with no front door to use.
local function frontOf(stop, centre: Vector3): Vector3
	local origin: CFrame = stop.origin or CFrame.new()
	local x = origin:PointToObjectSpace(centre).X
	return origin:VectorToWorldSpace(Vector3.new(if x > 0 then -1 else 1, 0, 0))
end

local function doorOf(stop, model: Model): Vector3?
	for _, door in stop.doors or {} do
		if door.door:IsDescendantOf(model) then
			return door.closed.Position
		end
	end
	local vault = stop.vaultDoor
	if vault and vault:IsDescendantOf(model) then
		return vault.Position
	end
	return nil
end

local function makeSign(lamp: BasePart, above: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "WhosThere"
	gui.Size = UDim2.fromScale(14, 3.5)
	gui.StudsOffset = Vector3.new(0, above, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "WHO'S THERE?!"
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
	gui.Parent = lamp
	return gui
end

-- The lit houses of this stop, each with its first check scheduled.
function HouseChecks.houses(stop, lightsAt: number): { House }
	local houses = {}
	for _, light in stop.lights do
		local lamp = light.Parent
		local model = lamp and lamp.Parent
		if lamp and lamp:IsA("BasePart") and model and model:IsA("Model") then
			local box, size = model:GetBoundingBox()
			local floorY = box.Position.Y - size.Y / 2
			local low = Vector3.new(box.Position.X, floorY + 3, box.Position.Z)
			local roof = box.Position.Y + size.Y / 2
			table.insert(houses, {
				model = model,
				light = light,
				box = box,
				size = size,
				exit = LightsCheck.exitCFrame(box, size, doorOf(stop, model), frontOf(stop, low)),
				checkAt = 0,
				warned = false,
				sign = makeSign(lamp, roof - lamp.Position.Y + 3),
			})
		end
	end
	for i, house in houses do
		house.checkAt = LightsCheck.firstCheckAt(lightsAt, i, #houses)
	end
	return houses
end

local function santasOf(run): { LightsCheck.Santa }
	local list = {}
	for player, st in run.players do
		local root = Util.rootOf(player)
		if root then
			table.insert(list, {
				player = player,
				position = root.Position,
				hidden = st.hidden ~= nil,
				captive = st.captive == true,
			})
		end
	end
	return list
end

local function warnHouse(run, house: House)
	house.warned = true
	local light = house.light
	house.restore = { color = light.Color, brightness = light.Brightness, range = light.Range }
	house.sign.Enabled = true
	SoundPlayer.at("ParentWake", house.light.Parent)
	for _, player in LightsCheck.spotted(house.box, house.size, santasOf(run)) do
		run:_banner(player, "WHO'S THERE?! Someone's coming. Hide in the wardrobe or get out!", L.WarnSeconds)
	end
end

local function restore(house: House)
	local r = house.restore
	if r then
		house.light.Color = r.color
		house.light.Brightness = r.brightness
		house.light.Range = r.range
		house.restore = nil
	end
	house.sign.Enabled = false
end

-- Drops one present, adds noise and bonks `player` out of the front door.
function HouseChecks.spot(run, house: House, player: Player, dropper: DogBump.Dropper)
	local root = Util.rootOf(player)
	local st = run.players[player]
	if not root or not st then
		return
	end
	local value = Loot.dropOne(st)
	if value then
		dropper.drop(root.Position - Vector3.new(0, 2.5, 0), value)
		run:_sendPlayer(player)
	end
	run:_addNoise(L.Noise)
	Util.teleport(player, house.exit)
	Knockback.apply(root, house.exit.LookVector * L.Bonk + Vector3.new(0, Config.Knockback.Lift, 0))
	SoundPlayer.at("CutsceneBonk", house.exit.Position)
	run:_banner(
		player,
		if value
			then "SPOTTED! You dropped a present and got shooed out. Grab it back!"
			else "SPOTTED! You got shooed out of the house!",
		2.5
	)
end

local function flash(run, house: House, dropper: DogBump.Dropper)
	local light = house.light
	light.Color = L.FlashColor
	light.Brightness = L.FlashBrightness
	light.Range = (house.restore and house.restore.range or light.Range) * 1.3
	house.sign.Enabled = false
	SoundPlayer.at("LightsOn", house.light.Parent)
	for _, player in LightsCheck.spotted(house.box, house.size, santasOf(run)) do
		HouseChecks.spot(run, house, player, dropper)
	end
end

-- Runs the checks until the returned cleanup is called.
function HouseChecks.start(run, stop, rng: Random?): () -> ()
	local random = rng or Random.new()
	local lightsAt = Util.now()
	local houses = HouseChecks.houses(stop, lightsAt)
	local dropper = DogBump.dropper(run, run.route and run.route.model or workspace)
	local alive = true
	local flashEnds: { [House]: number } = {}

	task.spawn(function()
		while alive do
			task.wait(TICK)
			if not alive or run.ended then
				break
			end
			local t = Util.now()
			for _, house in houses do
				local ends = flashEnds[house]
				if ends then
					if t >= ends then
						flashEnds[house] = nil
						restore(house)
					end
				elseif t >= house.checkAt then
					if not house.warned then
						warnHouse(run, house) -- a long frame skipped the warning: still warn first
						house.checkAt = t + L.WarnSeconds
					else
						flash(run, house, dropper)
						flashEnds[house] = t + L.FlashSeconds
						house.warned = false
						house.checkAt = LightsCheck.nextCheckAt(house.checkAt, random:NextNumber())
					end
				elseif LightsCheck.warning(t, house.checkAt) then
					if not house.warned then
						warnHouse(run, house)
					end
					-- Orange flicker while someone stomps downstairs.
					local on = math.floor(t / FLICKER) % 2 == 0
					house.light.Color = L.WarnColor
					local base = house.restore and house.restore.brightness or 2
					house.light.Brightness = if on then base * 1.2 else base * 0.25
				end
			end
		end
	end)

	return function()
		alive = false
		for _, house in houses do
			restore(house)
			house.sign:Destroy()
		end
		dropper.cleanup()
	end
end

return HouseChecks
