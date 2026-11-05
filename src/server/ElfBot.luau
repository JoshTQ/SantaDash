--[[
	One elf bot in a solo run: follows its Santa, fetches nearby presents into
	the Santa's sack, and hops to the Santa after chimneys and sleigh rides.
	Decisions live in ElfBrain. Body: the approved model (ServerStorage.Assets,
	named after its variant) or the coloured stand-in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local ElfBrain = require(script.Parent.ElfBrain)
local RigAnimator = require(script.Parent.RigAnimator)
local MapBuilder = require(script.Parent.MapBuilder)
local Mover = require(script.Parent.Mover)

local E = Config.ElfBots
local TICK = 0.25
local REACH = 4

local ElfBot = {}
ElfBot.__index = ElfBot

local function buildBody(parent: Instance, variant: string, cframe: CFrame): MapBuilder.ElfBody
	local model = Assets.clone(variant, { "Humanoid", "HumanoidRootPart" })
	if model then
		model:PivotTo(cframe)
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = E.WalkSpeed
		model.Parent = parent
		return {
			model = model,
			humanoid = humanoid,
			root = model:FindFirstChild("HumanoidRootPart", true) :: BasePart,
		}
	end
	return MapBuilder.buildElf(parent, cframe, variant)
end

function ElfBot.new(run, owner: Player, variant: string, index: number, cframe: CFrame)
	local self = setmetatable({}, ElfBot)
	self.run = run
	self.owner = owner
	self.variant = variant
	self.offset = ElfBrain.followOffset(index)
	self.body = buildBody(run.route.model, variant, cframe)
	self.anim = RigAnimator.new(self.body.model) -- no-op on the stand-in
	pcall(function()
		self.body.root:SetNetworkOwner(nil)
	end)
	self.mover = Mover.new(
		self.body.humanoid,
		self.body.root,
		{ AgentRadius = 1.5, AgentHeight = E.Height, AgentCanJump = true },
		E.RepathSeconds
	)
	self.target = nil
	self.nextGrabAt = 0
	self.alive = true
	task.spawn(function()
		while self.alive do
			local ok, err = pcall(self._think, self)
			if not ok then
				warn("[ElfBot] " .. tostring(err))
			end
			task.wait(TICK)
		end
	end)
	return self
end

function ElfBot:destroy()
	self.alive = false
	self.body.model:Destroy()
end

function ElfBot:_think()
	local run = self.run
	local ownerRoot = Util.rootOf(self.owner)
	if not ownerRoot or run.ended then
		self.mover:stop()
		return
	end
	local root = self.body.root
	local behindOwner = (ownerRoot.CFrame * CFrame.new(self.offset)).Position

	-- Left behind by a chimney or the sleigh: hop over.
	if (root.Position - ownerRoot.Position).Magnitude > E.CatchUpDistance then
		self.target = nil
		self.mover:teleport(CFrame.new(behindOwner + Vector3.new(0, 2, 0)))
		return
	end

	if self.target and self.target.present.taken then
		self.target = nil
	end
	local t = Util.now()
	if not self.target and t >= self.nextGrabAt and run:canElfGrab(self.owner) then
		self.target = ElfBrain.pickPresent(ownerRoot.Position, run:presentCandidates())
	end

	local target = self.target
	if target then
		if (root.Position - target.position).Magnitude <= REACH then
			self.target = nil
			self.anim:oneShot("Grab", 3)
			self.nextGrabAt = t + E.GrabEverySeconds
			run:elfCollect(self.owner, target.present, root.Position)
		else
			self.mover:moveTo(target.position)
			self.anim:play("Follow")
		end
	elseif (root.Position - behindOwner).Magnitude > E.FollowDistance then
		self.mover:moveTo(behindOwner)
		self.anim:play("Follow")
	else
		self.mover:stop()
		self.anim:play("Idle")
	end
end

return ElfBot
