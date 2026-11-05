--[[
	Plays an approved model's animations (ServerStorage.Assets.<Name>.Animations,
	Animation instances named by game state, from the Meshy pipeline) on its
	Humanoid's Animator. Models without them (stand-ins, unrigged imports) get a
	no-op animator, so callers never need to check.

	  local anim = RigAnimator.new(model)
	  anim:play("Tiptoe")          -- looping state; no-op if already playing
	  anim:oneShot("Snatch", 2.5)  -- plays once over the loop, at a speed

	Server-side tracks replicate to every client.
]]

local RigAnimator = {}
RigAnimator.__index = RigAnimator

export type RigAnimator = typeof(setmetatable(
	{} :: { tracks: { [string]: any }, current: string?, names: { [string]: boolean } },
	RigAnimator
))

local FADE = 0.25

function RigAnimator.new(model: Instance): RigAnimator
	local self = setmetatable({ tracks = {}, current = nil, names = {} }, RigAnimator)
	local folder = model:FindFirstChild("Animations")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (folder and animator) then
		return self
	end
	for _, animation in folder:GetChildren() do
		if animation:IsA("Animation") then
			local ok, track = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if ok and track then
				track.Looped = animation:GetAttribute("Loop") == true
				self.tracks[animation.Name] = track
				self.names[animation.Name] = true
			else
				warn("[RigAnimator] couldn't load " .. animation:GetFullName() .. ": " .. tostring(track))
			end
		end
	end
	return self
end

function RigAnimator.has(self: RigAnimator, name: string): boolean
	return self.names[name] == true
end

-- Switches the looping state animation (fades between them).
function RigAnimator.play(self: RigAnimator, name: string?)
	if name == self.current then
		return
	end
	local old = self.current and self.tracks[self.current]
	if old then
		old:Stop(FADE)
	end
	self.current = name
	local track = name and self.tracks[name]
	if track then
		track:Play(FADE)
	end
end

function RigAnimator.oneShot(self: RigAnimator, name: string, speed: number?)
	local track = self.tracks[name]
	if track then
		track:Play(0.1, 1, speed or 1)
	end
end

function RigAnimator.stopAll(self: RigAnimator)
	for _, track in self.tracks do
		track:Stop(0)
	end
	self.current = nil
end

return RigAnimator
