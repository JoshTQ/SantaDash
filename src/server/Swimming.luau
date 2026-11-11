--[[
	Swimming and body heat in Krampus's Lair (Josh's playtest, 6 Nov 2026).

	The lake gets real terrain water under its ice, so when Krampus stomps
	the ice away Santas swim (Roblox's own Swimming state) instead of being
	snapped back onto a floe. Swimming drains body heat (shared/BodyHeat),
	warm gear from the Wardrobe slows that down, and land refills it, fast on
	the island by the fires. At 0 a Santa freezes into an ice cube for a
	moment, then washes up on the nearest shore, soggy and slow. No loot is
	lost. Krampus never swims (KrampusBrain ignores Santas in the water).

	  Swimming.fillWater(lake) -> undo      terrain water under the lake ice
	  Swimming.start(run, swim) -> stop     the 0.1 s heat loop for this stop
	  Swimming.shorePoint(swim, at)          where a frozen Santa washes up
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BodyHeat = require(ReplicatedStorage.Shared.BodyHeat)
local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local Wardrobe = require(ReplicatedStorage.Shared.Wardrobe)

local H = Config.BodyHeat
local Swimming = {}

-- What FloeLake.build records about the lake (world space).
export type Swim = {
	island: Vector3,
	islandRadius: number,
	warmRadius: number, -- flat distance from the island's centre that counts as by the fire
	bridgeFrom: Vector3,
	bridgeTo: Vector3,
}

local function terrain(): any
	local ok, t = pcall(function()
		return workspace:FindFirstChildOfClass("Terrain")
	end)
	return if ok then t else nil
end

-- The block of water under a lake ice part (its CFrame and size).
function Swimming.waterBlock(lake: BasePart): (CFrame, Vector3)
	local top = -lake.Size.Y / 2 + H.WaterTop
	return lake.CFrame * CFrame.new(0, top - H.WaterDepth / 2, 0),
		Vector3.new(lake.Size.X, H.WaterDepth, lake.Size.Z)
end

-- Fills terrain water under the lake ice; returns a function that empties it.
-- A no-op where there is no Terrain (the Lune test world).
function Swimming.fillWater(lake: BasePart): () -> ()
	local t = terrain()
	if not t or not H.Enabled then
		return function() end
	end
	local cframe, size = Swimming.waterBlock(lake)
	local ok, err = pcall(t.FillBlock, t, cframe, size, Enum.Material.Water)
	if not ok then
		warn("[Swimming] couldn't fill the lake: " .. tostring(err))
		return function() end
	end
	return function()
		pcall(t.FillBlock, t, cframe, size, Enum.Material.Air)
	end
end

-- Where on the lake a Santa is, for body heat.
function Swimming.where(swim: Swim, at: Vector3, swimming: boolean): BodyHeat.Where
	if swimming then
		return "Swimming"
	end
	local flat = Vector3.new(at.X - swim.island.X, 0, at.Z - swim.island.Z).Magnitude
	return if flat < swim.warmRadius then "Fire" else "Land"
end

-- The nearest dry place to `at`: on the bell bridge or the island's edge.
function Swimming.shorePoint(swim: Swim, at: Vector3): Vector3
	local a, b = swim.bridgeFrom, swim.bridgeTo
	local ab = b - a
	local t = math.clamp((at - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	local onBridge = a + ab * t
	local flat = Vector3.new(at.X - swim.island.X, 0, at.Z - swim.island.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local onIsland = swim.island + dir * (swim.islandRadius - 4)
	local function d(p: Vector3)
		return Vector3.new(p.X - at.X, 0, p.Z - at.Z).Magnitude
	end
	local best = if d(onBridge) <= d(onIsland) then onBridge else onIsland
	return best + Vector3.new(0, 4, 0)
end

-- An ice cube round a Santa (also Krampus's Frost Zap, server/KrampusMagic).
function Swimming.iceCube(root: BasePart, name: string?): BasePart
	local cube = Instance.new("Part")
	cube.Name = name or "FrozenSanta"
	cube.Anchored = true
	cube.CanCollide = false
	cube.CanQuery = false
	cube.CanTouch = false
	cube.Size = Vector3.new(6, 7, 6)
	cube.CFrame = CFrame.new(root.CFrame.Position)
	cube.Color = Color3.fromRGB(190, 235, 255)
	cube.Material = Enum.Material.Ice
	cube.Transparency = 0.35
	cube.Parent = workspace
	return cube
end

function Swimming.start(run, swim: Swim?): () -> ()
	if not swim or not H.Enabled then
		return function() end
	end
	local heat: { [Player]: number } = {}
	local cubes: { [Player]: BasePart } = {}
	local alive = true

	local function send(player: Player)
		local value = BodyHeat.quantise(heat[player] or 1)
		if player:GetAttribute(BodyHeat.ATTRIBUTE) ~= value then
			player:SetAttribute(BodyHeat.ATTRIBUTE, value)
		end
	end

	local function thaw(player: Player)
		local cube = cubes[player]
		cubes[player] = nil
		if cube then
			cube:Destroy()
		end
		local st = run.players[player]
		player:SetAttribute(BodyHeat.FROZEN_ATTRIBUTE, nil)
		if not st then
			return
		end
		st.frozen = false
		st.swimming = false
		local root = Util.rootOf(player)
		if root then
			root.Anchored = false
			if alive then
				Util.teleport(player, CFrame.new(Swimming.shorePoint(swim, root.CFrame.Position)))
			end
		end
		if alive then
			heat[player] = H.ThawHeat
			st.soggyUntil = Util.now() + H.SoggySeconds
			send(player)
			run:_banner(player, "Phew! Soggy and slow for a moment.", 2)
		end
		run:_applyPerks(player)
	end

	local function freeze(player: Player, st)
		local root = Util.rootOf(player)
		if not root then
			return
		end
		st.frozen = true
		st.swimming = false
		root.Anchored = true
		cubes[player] = Swimming.iceCube(root)
		player:SetAttribute(BodyHeat.FROZEN_ATTRIBUTE, true)
		SoundPlayer.at("IceCrack", root.CFrame.Position)
		run:_banner(player, "FROZEN SOLID! Bobbing back to shore...", H.FrozenSeconds)
		run:_banner(nil, player.DisplayName .. " turned into a Santa ice lolly!", 2)
		task.delay(H.FrozenSeconds, function()
			if cubes[player] then
				thaw(player)
			end
		end)
	end

	local acc = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		local step = acc
		acc = 0
		for player, st in run.players do
			if st.frozen then
				continue
			end
			local humanoid = Util.humanoidOf(player)
			local root = humanoid and humanoid.RootPart
			if not humanoid or not root or st.captive or st.hidden or run.ended then
				st.swimming = false
				heat[player] = BodyHeat.step(heat[player] or 1, step, "Land", 0)
			else
				local swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
				if swimming ~= (st.swimming == true) then
					st.swimming = swimming
					run:_applyPerks(player) -- the Duckie Ring's swim speed
				end
				local where = Swimming.where(swim, root.CFrame.Position, swimming)
				heat[player] = BodyHeat.step(heat[player] or 1, step, where, Wardrobe.warmth(st.wardrobe))
				if heat[player] <= 0 then
					freeze(player, st)
				end
			end
			send(player)
		end
	end)

	return function()
		alive = false
		connection:Disconnect()
		for player in cubes do
			thaw(player)
		end
		for player, st in run.players do
			st.swimming = false
			st.frozen = false
			player:SetAttribute(BodyHeat.ATTRIBUTE, nil)
			player:SetAttribute(BodyHeat.FROZEN_ATTRIBUTE, nil)
		end
	end
end

return Swimming
