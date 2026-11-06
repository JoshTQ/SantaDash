--[[
	Body heat in Krampus's Lair (Josh's playtest, 6 Nov 2026). Pure maths,
	shared by the server (which owns the number) and the HUD (which shows it).

	Heat runs 0..1. It drains only while a Santa swims, at a rate their warm
	gear slows down, and refills on land (fast by the island's fires). At 0
	they freeze into an ice cube; see server/Swimming.
]]

local Config = require(script.Parent.Config)

local BodyHeat = {}

BodyHeat.ATTRIBUTE = "BodyHeat" -- player attribute, 0..1 (Config.BodyHeat.SendStep steps)
BodyHeat.FROZEN_ATTRIBUTE = "Frozen" -- player attribute while stuck in the ice cube

export type Where = "Swimming" | "Land" | "Fire"

-- Seconds of swimming from full heat to frozen with `warmth` (0 = no gear).
function BodyHeat.swimSeconds(warmth: number): number
	return Config.BodyHeat.SwimSeconds * (1 + math.max(0, warmth))
end

-- Heat after `dt` seconds spent `where`.
function BodyHeat.step(heat: number, dt: number, where: Where, warmth: number): number
	local H = Config.BodyHeat
	if where == "Swimming" then
		heat -= dt / BodyHeat.swimSeconds(warmth)
	elseif where == "Fire" then
		heat += dt / H.FireRecoverSeconds
	else
		heat += dt / H.RecoverSeconds
	end
	return math.clamp(heat, 0, 1)
end

-- The value sent to the HUD: rounded to SendStep so attributes don't spam.
function BodyHeat.quantise(heat: number): number
	local step = Config.BodyHeat.SendStep
	return math.clamp(math.floor(heat / step + 0.5) * step, 0, 1)
end

-- What the HUD meter says.
function BodyHeat.label(heat: number, frozen: boolean): string
	if frozen then
		return "FROZEN SOLID!"
	elseif heat < 0.3 then
		return "BRRR! Get out of the water!"
	end
	return "BODY HEAT"
end

-- The meter shows while you're losing heat or still warming back up.
function BodyHeat.visible(heat: number, frozen: boolean): boolean
	return frozen or heat < 0.999
end

return BodyHeat
