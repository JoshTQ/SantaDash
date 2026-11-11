--[[
	Pure rules for the HUD's feedback ("juice"), so they run in tests:

	  pops(before, after)     the little "+12" numbers that float off the
	                          stats panel when you grab, bank, spill or spend
	  sackFull(data)          the sack label turns red and says FULL
	  timerUrgency(phase, s)  how hard the stop timer pulses near the horn
	  keyHint(action, device) "TAP!" on phones, "TAP! (Space)" on keyboards
	  confirmLeave(...)       Back to hub needs a second tap within a few
	                          seconds, so a stray thumb never quits a run

	Hud.client does the drawing; nothing here touches the game.
]]

local HudFeedback = {}

export type Pop = { kind: string, text: string }
export type PlayerData = {
	jingle: number,
	sackCount: number,
	sackValue: number,
	banked: number,
	sackCapacity: number?,
}

-- What changed between two Player updates, as floating numbers. Banking
-- empties the sack into the sleigh, so it is one big pop, not a spill.
function HudFeedback.pops(before: PlayerData?, after: PlayerData): { Pop }
	local out = {}
	if not before then
		return out
	end
	local banked = after.banked - before.banked
	if banked > 0 then
		table.insert(out, { kind = "bank", text = "+" .. banked })
	elseif after.sackCount < before.sackCount then
		-- Presents, not value: "-1" in red beside the sack count.
		table.insert(out, { kind = "spill", text = "-" .. (before.sackCount - after.sackCount) })
	elseif after.sackValue > before.sackValue then
		table.insert(out, { kind = "sack", text = "+" .. (after.sackValue - before.sackValue) })
	end
	local jingle = after.jingle - before.jingle
	if jingle > 0 then
		table.insert(out, { kind = "jingle", text = "+" .. jingle })
	elseif jingle < 0 then
		table.insert(out, { kind = "spend", text = tostring(jingle) })
	end
	return out
end

function HudFeedback.sackFull(data: PlayerData, defaultCapacity: number): boolean
	return data.sackCount >= (data.sackCapacity or defaultCapacity)
end

HudFeedback.UrgentSeconds = 10 -- the horn's last seconds pulse the timer

-- 0 = calm, otherwise how many pixels of extra text size the pulse peaks at.
function HudFeedback.timerUrgency(phase: string?, secondsLeft: number): number
	if phase ~= "Horn" or secondsLeft <= 0 then
		return 0
	end
	if secondsLeft <= 5 then
		return 12
	elseif secondsLeft <= HudFeedback.UrgentSeconds then
		return 6
	end
	return 0
end

-- Device = "Touch" | "Gamepad" | "Keyboard". Phones never see keyboard keys.
local KEYS = {
	Tap = { word = "TAP!", Keyboard = "Space", Gamepad = "A" },
	Throw = { word = "THROW", Keyboard = "F", Gamepad = "R2" },
}

function HudFeedback.keyHint(action: string, device: string): string
	local k = KEYS[action]
	if not k then
		return action
	end
	local key = k[device]
	return if key then k.word .. " (" .. key .. ")" else k.word
end

-- Which device to label for, from the last input Roblox saw.
function HudFeedback.deviceFor(inputTypeName: string?, touchEnabled: boolean): string
	if inputTypeName == "Touch" then
		return "Touch"
	elseif inputTypeName and string.sub(inputTypeName, 1, 7) == "Gamepad" then
		return "Gamepad"
	elseif inputTypeName and (inputTypeName == "Keyboard" or string.sub(inputTypeName, 1, 5) == "Mouse") then
		return "Keyboard"
	end
	return if touchEnabled then "Touch" else "Keyboard"
end

-- Results: your Coal counts up from 0, fast then settling (ease-out).
HudFeedback.CountUpSeconds = 1.2

function HudFeedback.countUp(total: number, elapsed: number, duration: number?): number
	local d = duration or HudFeedback.CountUpSeconds
	if elapsed >= d or d <= 0 then
		return total
	end
	local t = math.max(0, elapsed) / d
	return math.floor(total * (1 - (1 - t) ^ 3))
end

-- Results: one line about your own run, plus where Coal goes on a first heist.
function HudFeedback.summary(row: { grabs: number?, escaped: boolean }, firstHeist: boolean): string
	local grabs = row.grabs or 0
	local line = string.format(
		"You grabbed %d %s · %s",
		grabs,
		if grabs == 1 then "present" else "presents",
		if row.escaped then "escaped x2!" else "missed the sleigh"
	)
	if firstHeist then
		line ..= "\nFirst heist! Spend Coal in the Shop."
	end
	return line
end

-- Krampus off screen: an arrow on the screen's edge pointing at him.
-- point = Camera:WorldToScreenPoint (x, y in GUI px, z = depth; negative
-- = behind the camera), size = the GUI's size in the same px. Returns nil
-- while he is on screen, else where the arrow goes and its rotation in
-- degrees (0 = pointing right, clockwise, like GuiObject.Rotation).
HudFeedback.ArrowRange = 100 -- studs: only while he is this close
HudFeedback.ArrowMargin = 48 -- px kept clear of the screen edge

function HudFeedback.edgeArrow(
	point: Vector3,
	onScreen: boolean,
	size: Vector2,
	margin: number?
): { x: number, y: number, rotation: number }?
	if onScreen and point.Z > 0 then
		return nil
	end
	local m = margin or HudFeedback.ArrowMargin
	local cx, cy = size.X / 2, size.Y / 2
	local dx, dy = point.X - cx, point.Y - cy
	if point.Z <= 0 then
		-- Behind the camera the projection is mirrored.
		dx, dy = -dx, -dy
	end
	if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then
		dy = 1 -- straight behind: point down
	end
	-- Push out to the inner rectangle's edge.
	local hx, hy = math.max(1, cx - m), math.max(1, cy - m)
	local scale = math.min(hx / math.max(math.abs(dx), 1e-6), hy / math.max(math.abs(dy), 1e-6))
	return {
		x = cx + dx * scale,
		y = cy + dy * scale,
		rotation = math.deg(math.atan2(dy, dx)),
	}
end

HudFeedback.ConfirmSeconds = 3

-- First tap arms Back to hub; a second tap before `armedUntil` leaves.
-- Returns (leave now?, new armedUntil).
function HudFeedback.confirmLeave(now: number, armedUntil: number): (boolean, number)
	if now < armedUntil then
		return true, 0
	end
	return false, now + HudFeedback.ConfirmSeconds
end

return HudFeedback
