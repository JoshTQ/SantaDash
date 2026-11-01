--[[
	Random map events: what each event does while it plays. Which event plays,
	when, and at which stop is decided by MapEventBrain (pure, tested).

	A map lists the events it can roll as { kind = "<key>", weight = n } in its
	`events` (shared/Maps). Each kind here has a Config.MapEvents.Events entry
	with its off switch and numbers.

	start(ctx) runs when the event begins and returns a cleanup that Run calls
	when it ends (before the horn), when the sleigh leaves, or when the run ends.
	Disconnect and destroy everything there. Run sends the warning banner and
	the HUD chip; start does the event itself and its cleanup says it's over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local MapEventBrain = require(script.Parent.MapEventBrain)

-- Required parts of the approved Sparkle Drift snow pile (Assets "SnowPile").
local PILE_PARTS = { "Drift", "Ball1", "Ball2", "Ball3", "Ball4", "Ball5" }

export type StartContext = {
	run: any, -- Run: players, noiseScale, eventInput, _banner, _send ...
	stop: any, -- MapBuilder.Stop
	entry: { [string]: any }, -- the map's events entry
	endsAt: number, -- Util.now() time it ends
}

export type MapEvent = {
	start: (ctx: StartContext) -> () -> (),
}

local MapEvents: { [string]: MapEvent } = {}

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

----------------------------------------------------------------------------
-- Blizzard: fog and snow (client), muffled noise, snow piles, snowball fights.
----------------------------------------------------------------------------

MapEvents.Blizzard = {
	start = function(ctx: StartContext)
		local cfg = Config.MapEvents.Events.Blizzard
		local run, stop = ctx.run, ctx.stop
		local folder = Instance.new("Folder")
		folder.Name = "Blizzard"
		folder.Parent = run.route.model

		local snowballs: { [Player]: number } = {}
		local lastThrow: { [Player]: number } = {}
		local splats: { [string]: number } = {}

		local function sendSnowballs(player: Player)
			run:_send(player, "Snowballs", { count = snowballs[player] or 0 })
		end

		run.noiseScale = cfg.NoiseMultiplier

		-- Snow piles: the approved Sparkle Drift (Assets "SnowPile"), else a
		-- white block. Each grab hides one of its balls; they regrow.
		for _, offset in ctx.entry.piles or cfg.Piles do
			local at = stop.origin * CFrame.new(offset + Vector3.new(0, 1.5, 0))
			local pile: Instance? = Assets.clone("SnowPile", PILE_PARTS)
			local promptParent: Instance
			if pile then
				local model = pile :: Model
				model:PivotTo(at)
				promptParent = model.PrimaryPart or model:FindFirstChild("Drift") :: Instance
				local glow = model:FindFirstChild("Glow", true)
				if glow and glow:IsA("BasePart") then
					local base = glow.Transparency
					TweenService:Create(
						glow,
						TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Transparency = math.min(1, base + 0.4) }
					):Play()
				end
			else
				local block = Instance.new("Part")
				block.Name = "SnowPile"
				block.Anchored = true
				block.Size = Vector3.new(6, 3, 6)
				block.CFrame = at
				block.Color = Color3.fromRGB(245, 248, 255)
				block.Material = Enum.Material.Snow
				pile, promptParent = block, block
			end
			local pileModel = pile :: Instance
			pileModel.Parent = folder

			local prompt = pileModel:FindFirstChildWhichIsA("ProximityPrompt", true)
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Parent = promptParent
			end
			local p = prompt :: ProximityPrompt
			p.ActionText = "Grab snowballs"
			p.ObjectText = "Snow pile"
			p.HoldDuration = 0.3

			local nextBall = 0
			p.Triggered:Connect(function(player)
				if not run.players[player] then
					return
				end
				snowballs[player] = MapEventBrain.takeSnowballs(snowballs[player] or 0)
				sendSnowballs(player)
				nextBall = nextBall % 5 + 1
				local ballPart = pileModel:FindFirstChild("Ball" .. nextBall, true)
				if ballPart and ballPart:IsA("BasePart") and ballPart.Transparency < 1 then
					local was = ballPart.Transparency
					ballPart.Transparency = 1
					task.delay(cfg.PileRegrowSeconds, function()
						if ballPart.Parent then
							ballPart.Transparency = was
						end
					end)
				end
			end)
		end

		-- A blue splat decal where a snowball lands (Assets "SnowSplat"), fading out.
		local function splatAt(position: Vector3)
			local mark = Assets.clone("SnowSplat", {})
			if not mark then
				return
			end
			for _, d in mark:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			mark:PivotTo(CFrame.new(position))
			mark.Parent = folder
			for _, d in mark:GetDescendants() do
				if d:IsA("Decal") then
					TweenService:Create(d, TweenInfo.new(cfg.SplatMarkSeconds), { Transparency = 1 }):Play()
				end
			end
			task.delay(cfg.SplatMarkSeconds, function()
				mark:Destroy()
			end)
		end

		local function newSnowball(): (Instance, BasePart)
			local model = Assets.clone("Snowball", {})
			local primary = model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
			if model and primary then
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = false
						d.CanCollide = false
					end
				end
				return model, primary :: BasePart
			end
			local ball = Instance.new("Part")
			ball.Name = "Snowball"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * 1.2
			ball.Color = Color3.new(1, 1, 1)
			ball.Material = Enum.Material.Snow
			ball.CanCollide = false
			return ball, ball
		end

		local function throw(player: Player)
			local root = Util.rootOf(player)
			local t = Util.now()
			if
				not root
				or not MapEventBrain.canThrow(snowballs[player] or 0, lastThrow[player] or -math.huge, t)
			then
				return
			end
			lastThrow[player] = t
			snowballs[player] -= 1
			sendSnowballs(player)

			local look = root.CFrame.LookVector
			local projectile, ball = newSnowball()
			local from = CFrame.new(root.Position + look * 3 + Vector3.yAxis * 1.5)
			if projectile:IsA("Model") then
				projectile:PivotTo(from)
			else
				ball.CFrame = from
			end
			projectile.Parent = folder
			ball.AssemblyLinearVelocity = (look + Vector3.yAxis * 0.15).Unit * cfg.ThrowSpeed
			ball:SetNetworkOwner(nil)
			ball.Touched:Connect(function(hit)
				if
					not projectile.Parent
					or hit:IsDescendantOf(projectile)
					or hit:IsDescendantOf(player.Character or projectile)
				then
					return
				end
				local victim = playerFromPart(hit)
				-- Crewmates: a cosmetic splat only, never a stun (no griefing).
				if victim and run.players[victim] then
					run:_send(victim, "Splat", { seconds = cfg.SplatSeconds, by = player.DisplayName })
					run:_banner(player, "SPLAT! You got " .. victim.DisplayName .. "!", 1.5)
					splats[player.DisplayName] = (splats[player.DisplayName] or 0) + 1
				end
				splatAt(ball.Position)
				projectile:Destroy()
			end)
			task.delay(cfg.SnowballLife, function()
				if projectile.Parent then
					projectile:Destroy()
				end
			end)
		end

		run.eventInput = function(player: Player, action: string)
			if action == "Throw" then
				throw(player)
			end
		end

		run:_send(nil, "Weather", {
			kind = "Blizzard",
			fogEnd = cfg.FogEnd,
			fogColor = cfg.FogColor,
		})

		return function()
			run.noiseScale = 1
			run.eventInput = nil
			folder:Destroy()
			for player in snowballs do
				snowballs[player] = 0
				sendSnowballs(player)
			end
			run:_send(nil, "Weather", {})
			local mvp, count = MapEventBrain.mvp(splats)
			run:_banner(
				nil,
				cfg.Ended .. (if mvp then string.format("  Snowball MVP: %s (%d splats)", mvp, count) else ""),
				3
			)
		end
	end,
}

return MapEvents
