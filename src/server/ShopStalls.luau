--[[
	The two real shops at every Sleigh Stop, built from parts in the "Giant
	Goods" look: the stall is a giant version of what it sells (Josh, 11 Nov
	2026: "only keep genuine ones that sell stuff. Improve them so they look
	better too").

	  cocoa: a giant candy-banded mug with marshmallows and steam, served
	         through a lit hatch (Peppermint Rush). Model "CocoaMachine",
	         prompt on its Counter.
	  wardrobe: a giant knitted bobble hat with a lit window and a counter
	         rail in front; server/Wardrobe hangs the warm gear on the rail
	         (one prompt per hanger). Model "WardrobeStall".

	`at` is a ground CFrame at the stall's centre; the stall's front (hatch,
	window, prompts) faces its -Z. Event-free so Lune can build it.

	  ShopStalls.cocoa(parent, at, priceText) -> (Model, counter: BasePart)
	  ShopStalls.wardrobe(parent, at, width) -> (Model, railY: number, railZ: number)
]]

local Parts = require(script.Parent.Parts)

local ShopStalls = {}

local MUG = Color3.fromRGB(47, 168, 102)
local MUG_DARK = Color3.fromRGB(29, 122, 72)
local MUG_LIGHT = Color3.fromRGB(91, 208, 138)
local BAND = Color3.fromRGB(248, 248, 248)
local COCOA = Color3.fromRGB(106, 58, 34)
local PINK = Color3.fromRGB(255, 227, 236)
local HATCH = Color3.fromRGB(58, 33, 20)
local GLOW = Color3.fromRGB(255, 214, 140)
local RED = Color3.fromRGB(226, 52, 62)
local HAT = Color3.fromRGB(214, 44, 54)
local WOOL = Color3.fromRGB(247, 247, 247)
local WINDOW = Color3.fromRGB(90, 26, 32)
local BLUE = Color3.fromRGB(58, 111, 224)
local GOLD = Color3.fromRGB(255, 200, 61)
local WOOD = Color3.fromRGB(201, 138, 84)
local DARK = Color3.fromRGB(58, 33, 20)

-- Stall sizes in studs (tests read these).
ShopStalls.Mug = { radius = 5, height = 11 }
ShopStalls.Hat = { brimRadius = 7, domeRadius = 6.6 }

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X

local function cylinder(parent, name, radius, height, at: CFrame, color, material): BasePart
	local p =
		Parts.new(parent, name, Vector3.new(height, radius * 2, radius * 2), at * UPRIGHT, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, name, diameter, at: CFrame, color, material): BasePart
	local p = Parts.new(parent, name, Vector3.one * diameter, at, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function dressing(p: BasePart): BasePart
	p.CanCollide = false
	return p
end

-- 1500 -> "1,500".
function ShopStalls.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- Text on a part's front (-Z) face.
function ShopStalls.text(p: BasePart, value: string, bg: Color3, fg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.BorderSizePixel = 0
	label.Text = value
	label.TextColor3 = fg
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
end

local function warmLight(p: BasePart)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Brightness = 1.6
	light.Range = 18
	light.Shadows = false
	light.Parent = p
end

function ShopStalls.cocoa(parent: Instance, at: CFrame, priceText: string): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "CocoaMachine"
	local R, H = ShopStalls.Mug.radius, ShopStalls.Mug.height
	local top = 0.6 + H

	cylinder(m, "Base", R + 0.3, 0.8, at * CFrame.new(0, 0.4, 0), MUG_DARK)
	local body = cylinder(m, "Body", R, H, at * CFrame.new(0, 0.6 + H / 2, 0), MUG)
	for i, y in { 2.4, 6.4, 10.2 } do
		dressing(cylinder(m, "Band" .. i, R + 0.08, 1, at * CFrame.new(0, y, 0), BAND))
	end
	dressing(cylinder(m, "Rim", R + 0.3, 0.7, at * CFrame.new(0, top, 0), MUG_LIGHT))
	dressing(cylinder(m, "Cocoa", R - 0.2, 0.4, at * CFrame.new(0, top + 0.2, 0), COCOA, Enum.Material.Sand))
	for i, spot in { Vector3.new(-1.7, 0, 0.6), Vector3.new(0.5, 0, -1.4), Vector3.new(1.8, 0, 1.1) } do
		dressing(
			ball(
				m,
				"Marshmallow" .. i,
				2,
				at * CFrame.new(spot + Vector3.new(0, top + 0.6, 0)),
				if i == 2 then PINK else BAND
			)
		)
	end

	-- Handle on the back (+Z), out of the pavement and clear of the hatch.
	for i, y in { 9.4, 3.6 } do
		dressing(Parts.new(m, "Handle" .. i, Vector3.new(1.5, 1.5, 3), at * CFrame.new(0, y, R + 1.2), MUG))
	end
	dressing(Parts.new(m, "Handle3", Vector3.new(1.5, 7.3, 1.5), at * CFrame.new(0, 6.5, R + 2.6), MUG))

	-- Serving hatch on the front: frame, warm glow, red counter, sign.
	Parts.new(m, "HatchFrame", Vector3.new(6.6, 5, 2.4), at * CFrame.new(0, 6.8, -R + 0.9), HATCH)
	local glow = dressing(
		Parts.new(
			m,
			"HatchGlow",
			Vector3.new(5.6, 4, 0.2),
			at * CFrame.new(0, 6.8, -R - 0.32),
			GLOW,
			Enum.Material.Neon
		)
	)
	warmLight(glow)
	local counter =
		Parts.new(m, "Counter", Vector3.new(7.6, 0.6, 2.2), at * CFrame.new(0, 4.5, -R - 0.9), RED)
	local sign =
		dressing(Parts.new(m, "Sign", Vector3.new(7, 1.4, 0.4), at * CFrame.new(0, 10.2, -R - 0.1), RED))
	ShopStalls.text(sign, "PEPPERMINT RUSH", RED, Color3.new(1, 1, 1))
	local plate = dressing(
		Parts.new(m, "PricePlate", Vector3.new(3, 1, 0.2), at * CFrame.new(-2.2, 3.3, -R - 0.15), GOLD)
	)
	ShopStalls.text(plate, priceText, GOLD, DARK)

	-- Steam off the top (particles, not parts).
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Steam"
	steam.Color = ColorSequence.new(Color3.fromRGB(244, 246, 255))
	steam.Transparency = NumberSequence.new(0.35)
	steam.Rate = 3
	steam.Lifetime = NumberRange.new(2, 3)
	steam.Speed = NumberRange.new(1.5, 2.5)
	steam.Size = NumberSequence.new(1.6)
	steam.Parent = sign

	m.PrimaryPart = body
	m.Parent = parent
	return m, counter
end

-- width: room on the rail for the hangers. Returns the rail's height and its
-- distance in front (-Z) of the hat's centre, for the hangers.
function ShopStalls.wardrobe(parent: Instance, at: CFrame, width: number): (Model, number, number)
	local m = Instance.new("Model")
	m.Name = "WardrobeStall"
	local brim, dome = ShopStalls.Hat.brimRadius, ShopStalls.Hat.domeRadius

	local brimPart = cylinder(m, "Brim", brim, 3.2, at * CFrame.new(0, 1.6, 0), WOOL, Enum.Material.Fabric)
	ball(m, "Dome", dome * 2, at * CFrame.new(0, 3.2, 0), HAT, Enum.Material.Fabric)
	dressing(ball(m, "Pompom", 4.4, at * CFrame.new(0, 3.2 + dome + 1.6, 0), WOOL, Enum.Material.Fabric))

	Parts.new(m, "WindowFrame", Vector3.new(8.4, 4, 2.4), at * CFrame.new(0, 5.8, -5.4), WINDOW)
	local glow = dressing(
		Parts.new(
			m,
			"WindowGlow",
			Vector3.new(7.4, 3, 0.2),
			at * CFrame.new(0, 5.8, -6.62),
			GLOW,
			Enum.Material.Neon
		)
	)
	warmLight(glow)
	local sign = dressing(
		Parts.new(
			m,
			"Sign",
			Vector3.new(8, 1.4, 0.4),
			at * CFrame.new(0, 8.7, -4.6) * CFrame.Angles(-0.45, 0, 0),
			BLUE
		)
	)
	ShopStalls.text(sign, "WARDROBE", BLUE, Color3.new(1, 1, 1))

	-- Counter and hanging rail in front of the window.
	local railZ = -brim - 2
	local half = math.max(width, 8) / 2
	Parts.new(m, "Counter", Vector3.new(half * 2, 0.6, 2.4), at * CFrame.new(0, 3.4, -brim - 1.2), BLUE)
	for i, side in { -1, 1 } do
		Parts.new(
			m,
			"RailPost" .. i,
			Vector3.new(0.5, 6.4, 0.5),
			at * CFrame.new(side * (half + 0.3), 3.2, railZ),
			WOOD
		)
	end
	dressing(Parts.new(m, "Rail", Vector3.new(half * 2 + 1, 0.4, 0.4), at * CFrame.new(0, 6.3, railZ), WOOD))

	m.PrimaryPart = brimPart
	m.Parent = parent
	return m, 6.3, railZ
end

return ShopStalls
