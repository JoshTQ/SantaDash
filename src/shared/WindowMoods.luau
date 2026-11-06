--[[
	Life behind the windows (Josh, 6 Nov 2026: "outside should be more
	dynamic, not just blank windows"). HouseBuilder gives every window pane a
	Mood attribute; client/WindowMoods changes the panes over time with these
	pure rules, so the street flickers and twinkles without a server part.

	TV      the pane flickers through TV colours
	Dark    an empty room: now and then someone switches the light on
	Lamp    a warm lamp, breathing very slightly
	Candle, Curtains, Cat, Tree, Star: dressing only, the pane stays warm
]]

local WindowMoods = {}

WindowMoods.Warm = Color3.fromRGB(255, 217, 138)
WindowMoods.Off = Color3.fromRGB(43, 53, 80)
WindowMoods.TVColours = {
	Color3.fromRGB(143, 208, 255),
	Color3.fromRGB(190, 160, 255),
	Color3.fromRGB(120, 230, 200),
	Color3.fromRGB(255, 200, 230),
	Color3.fromRGB(170, 220, 255),
}
WindowMoods.Range = 260 -- studs from the camera; further panes are left alone
WindowMoods.Rate = 8 -- updates a second

-- A stable 0-1 number per pane, from its position (same on every client).
function WindowMoods.seed(position: Vector3): number
	local h = math.sin(position.X * 12.9898 + position.Y * 78.233 + position.Z * 37.719) * 43758.5453
	return h - math.floor(h)
end

-- The TV's colour at time t: a new picture every 0.3-0.7 s.
function WindowMoods.tv(t: number, seed: number): Color3
	local step = math.floor(t / (0.3 + seed * 0.4) + seed * 10)
	local list = WindowMoods.TVColours
	return list[(step * 7 + math.floor(seed * 13)) % #list + 1]
end

-- Is the empty room's light on at time t? On for 6 s in every 20-40 s.
function WindowMoods.darkLit(t: number, seed: number): boolean
	local period = 20 + seed * 20
	local phase = (t + seed * period) % period
	return phase < 6
end

-- The lamp's gentle breathing: 0.95-1.0 of its colour.
function WindowMoods.lamp(t: number, seed: number): number
	return 0.975 + 0.025 * math.sin(t * (0.6 + seed) + seed * 6.28)
end

-- What a pane with this mood should look like at time t: colour and whether it glows.
function WindowMoods.look(mood: string, t: number, seed: number): (Color3?, boolean?)
	if mood == "TV" then
		return WindowMoods.tv(t, seed), true
	elseif mood == "Dark" then
		local lit = WindowMoods.darkLit(t, seed)
		return if lit then WindowMoods.Warm else WindowMoods.Off, lit
	elseif mood == "Lamp" then
		local k = WindowMoods.lamp(t, seed)
		local w = WindowMoods.Warm
		return Color3.new(w.R * k, w.G * k, w.B * k), true
	end
	return nil, nil
end

return WindowMoods
