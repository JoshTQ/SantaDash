--[[
	The always-on gold guide line to the sleigh (Josh's first playtest, 6 Nov
	2026: "If a player misses the sleigh, it's very hard for them to find where
	it landed in the next stop. Like the tutorial, have the yellow line showing
	to them at all times to the sleigh.").

	Pure rules here (tested in Lune); client/SleighGuide.client.luau draws it.
	The server sends the sleigh's deck position with every "Stop" HUD message
	(sleighAt, nil while it flies).
]]

local Config = require(script.Parent.Config)

local SleighGuide = {}

-- Closer than this (flat studs from the deck) you are basically aboard: the
-- line would just be a stub at your feet, so it hides.
SleighGuide.HIDE_WITHIN = Config.Map.SleighStopRadius - 2

export type State = { stop: number, phase: string, sleighAt: Vector3? }

-- Whether to draw the line for this HUD state and Santa position.
function SleighGuide.shows(state: State?, at: Vector3?, cutscene: boolean): boolean
	if not state or not at or cutscene then
		return false
	end
	if state.stop == 0 or state.phase == "Flight" or not state.sleighAt then
		return false
	end
	local flat = (state.sleighAt - at) * Vector3.new(1, 0, 1)
	return flat.Magnitude > SleighGuide.HIDE_WITHIN
end

-- How the line looks at this distance: further = a wider line with a taller
-- arc (it reads over the trees), and gold turns red-gold after the horn.
function SleighGuide.style(distance: number, horn: boolean): { width: number, curve: number, color: Color3 }
	local t = math.clamp(distance / 400, 0, 1)
	return {
		width = 0.5 + t * 1.5,
		curve = 4 + t * 36,
		color = if horn then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 205, 60),
	}
end

-- The sleigh marker's text: "SLEIGH 230" (studs, rounded to tens past 100).
function SleighGuide.label(distance: number): string
	local d = math.floor(distance + 0.5)
	if d >= 100 then
		d = math.floor(d / 10 + 0.5) * 10
	end
	return "SLEIGH  " .. d
end

return SleighGuide
