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

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local MapEventBrain = require(script.Parent.MapEventBrain)

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

		-- GREYBOX piles: white blocks until a snowball pile model is approved.
		for _, offset in ctx.entry.piles or cfg.Piles do
			local pile = Instance.new("Part")
			pile.Name = "SnowPile"
			pile.Anchored = true
			pile.Size = Vector3.new(6, 3, 6)
			pile.CFrame = stop.origin * CFrame.new(offset + Vector3.new(0, 1.5, 0))
			pile.Color = Color3.fromRGB(245, 248, 255)
			pile.Material = Enum.Material.Snow
			pile.Parent = folder
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Grab snowballs"
			prompt.ObjectText = "Snow pile"
			prompt.HoldDuration = 0.3
			prompt.Parent = pile
			prompt.Triggered:Connect(function(player)
				if run.players[player] then
					snowballs[player] = MapEventBrain.takeSnowballs(snowballs[player] or 0)
					sendSnowballs(player)
				end
			end)
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
			local ball = Instance.new("Part")
			ball.Name = "Snowball"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * 1.2
			ball.Color = Color3.new(1, 1, 1)
			ball.Material = Enum.Material.Snow
			ball.CanCollide = false
			ball.CFrame = CFrame.new(root.Position + look * 3 + Vector3.yAxis * 1.5)
			ball.AssemblyLinearVelocity = (look + Vector3.yAxis * 0.15).Unit * cfg.ThrowSpeed
			ball.Parent = folder
			ball:SetNetworkOwner(nil)
			ball.Touched:Connect(function(hit)
				if not ball.Parent or hit:IsDescendantOf(player.Character or folder) then
					return
				end
				local victim = playerFromPart(hit)
				-- Crewmates: a cosmetic splat only, never a stun (no griefing).
				if victim and run.players[victim] then
					run:_send(victim, "Splat", { seconds = cfg.SplatSeconds, by = player.DisplayName })
					run:_banner(player, "SPLAT! You got " .. victim.DisplayName .. "!", 1.5)
					splats[player.DisplayName] = (splats[player.DisplayName] or 0) + 1
				end
				ball:Destroy()
			end)
			task.delay(cfg.SnowballLife, function()
				if ball.Parent then
					ball:Destroy()
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
