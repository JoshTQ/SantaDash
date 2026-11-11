--[[
	Poses the server's scripted movers (the sleigh and its riders in flight,
	Krampus in his intro and belly-flop) on this client every frame, from the
	same pure paths the server uses (shared/Puppets). The server moves them too,
	but its updates only arrive at the network rate, so without this the sleigh
	steps and a cutscene camera following Krampus judders.

	Local only: changes to server-owned anchored parts never replicate back, and
	this runs before the camera each frame, so the server's stepped updates
	never show. Each path ends on exactly the pose the server leaves it in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Puppets = require(ReplicatedStorage.Shared.Puppets)
local Util = require(ReplicatedStorage.Shared.Util)

local BIND = "SleighHeistPuppets"

local PuppetPlayer = {}

type Active = { puppet: Puppets.Puppet, startedAt: number }
local active: { [Instance]: Active } = {} -- one path per target; a newer one replaces it
local bound = false

local function pose(target: Instance, cframe: CFrame)
	if target:IsA("Model") then
		target:PivotTo(cframe)
	elseif target:IsA("BasePart") then
		target.CFrame = cframe
	end
end

local function step()
	local t = Util.now()
	for target, entry in active do
		if not target.Parent then
			active[target] = nil
			continue
		end
		local at = t - entry.startedAt
		local ok, err = pcall(function()
			pose(target, Puppets.poseAt(entry.puppet, at))
		end)
		if not ok then
			warn("[PuppetPlayer] " .. tostring(err))
			active[target] = nil
		elseif Puppets.done(entry.puppet, at) then
			active[target] = nil -- left on its end pose, where the server leaves it too
		end
	end
	if next(active) == nil then
		RunService:UnbindFromRenderStep(BIND)
		bound = false
	end
end

-- data: { startedAt, puppets = { Puppet } }
function PuppetPlayer.play(data)
	if type(data) ~= "table" or type(data.startedAt) ~= "number" or type(data.puppets) ~= "table" then
		return
	end
	for _, puppet in data.puppets do
		local target = typeof(puppet) == "table" and puppet.target
		if typeof(target) == "Instance" and Puppets.problem(puppet) == nil then
			if Util.now() - data.startedAt < puppet.seconds then
				active[target] = { puppet = puppet, startedAt = data.startedAt }
			end
		end
	end
	if next(active) ~= nil and not bound then
		bound = true
		-- Before the camera (default or cutscene), so both see this frame's pose.
		RunService:BindToRenderStep(BIND, Enum.RenderPriority.First.Value, step)
	end
end

-- The pose this client is giving `target` right now, if it is puppeted.
function PuppetPlayer.poseOf(target: Instance?): CFrame?
	local entry = target and active[target]
	if not entry then
		return nil
	end
	local ok, cframe = pcall(Puppets.poseAt, entry.puppet, Util.now() - entry.startedAt)
	return if ok then cframe else nil
end

-- Leaving a run: drop everything (the server moves them from here on).
function PuppetPlayer.clear()
	table.clear(active)
	if bound then
		RunService:UnbindFromRenderStep(BIND)
		bound = false
	end
end

return PuppetPlayer
