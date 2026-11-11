--[[
	The two real shops at every Sleigh Stop, built from parts as "Sleigh-Cart
	Pop-ups": the naughty Santas' own one-night shops, parked on gold sleigh
	runners (Josh, 11 Nov 2026: "only keep genuine ones that sell stuff.
	Improve them so they look better too"; he picked option C).

	  cocoa: a blue cart with a bubbling copper cocoa pot on the counter and
	         a giant gold mug on the awning (Peppermint Rush). Model
	         "CocoaMachine", prompt on its Counter.
	  wardrobe: a green cart with a hanging rail of warm gear and a giant
	         mitten on the awning; server/Wardrobe hangs the gear on the rail
	         (one prompt per hanger). Model "WardrobeStall".

	The roof toppers and the lantern are there so a cart reads as a shop
	from across the street on a phone (the red-team worry with this look).

	`at` is a ground CFrame at the cart's centre; its front (counter, sign,
	prompts) faces -Z. Event-free so Lune can build it.

	  ShopStalls.cocoa(parent, at, priceText) -> (Model, counter: BasePart)
	  ShopStalls.wardrobe(parent, at) -> (Model, Rail)
]]

local Parts = require(script.Parent.Parts)

local ShopStalls = {}

local CREAM = Color3.fromRGB(250, 246, 236)
local RED = Color3.fromRGB(226, 52, 62)
local BLUE = Color3.fromRGB(58, 111, 224)
local GREEN = Color3.fromRGB(47, 122, 74)
local GOLD = Color3.fromRGB(255, 200, 61)
local WOOD = Color3.fromRGB(201, 138, 84)
local DARK = Color3.fromRGB(58, 33, 20)
local BOARD = Color3.fromRGB(32, 38, 58)
local COPPER = Color3.fromRGB(201, 119, 46)
local COCOA = Color3.fromRGB(106, 58, 34)
local MUG = Color3.fromRGB(70, 200, 120)
local MITTEN = Color3.fromRGB(58, 111, 224)
local GLOW = Color3.fromRGB(255, 214, 140)

-- Cart sizes in studs (tests read these).
ShopStalls.Cart = {
	width = 12, -- along X
	depth = 6, -- along Z
	bodyBottom = 0.9, -- runners underneath
	counterTop = 4.9,
	awning = 10.4, -- canopy height
}

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X

local function cylinder(parent, name, radius, height, at: CFrame, color, material): BasePart
	local p =
		Parts.new(parent, name, Vector3.new(height, radius * 2, radius * 2), at * UPRIGHT, color, material)
	p.Shape = Enum.PartType.Cylinder
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

-- The shared cart: runners, body, counter, posts, striped awning, lantern
-- and a chalkboard. Returns the model and its counter.
local function cart(
	name: string,
	at: CFrame,
	colour: Color3,
	stripe: Color3,
	board: string
): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	local C = ShopStalls.Cart
	local w, d = C.width, C.depth

	-- Gold sleigh runners with curled ends.
	for i, z in { -d / 2 + 0.6, d / 2 - 0.6 } do
		dressing(
			Parts.new(
				m,
				"Runner" .. i,
				Vector3.new(w + 1, 0.4, 0.5),
				at * CFrame.new(0, 0.2, z),
				GOLD,
				Enum.Material.Metal
			)
		)
		local curl = Parts.new(
			m,
			"Curl" .. i,
			Vector3.new(0.5, 1.6, 1.6),
			at * CFrame.new(w / 2 + 0.6, 0.9, z) * CFrame.Angles(0, math.pi / 2, 0),
			GOLD,
			Enum.Material.Metal
		)
		curl.Shape = Enum.PartType.Cylinder
		dressing(curl)
	end
	local bodyH = C.counterTop - 0.4 - C.bodyBottom
	local body = Parts.new(
		m,
		"Body",
		Vector3.new(w, bodyH, d),
		at * CFrame.new(0, C.bodyBottom + bodyH / 2, 0),
		colour,
		Enum.Material.Wood
	)
	dressing(
		Parts.new(
			m,
			"Trim",
			Vector3.new(w + 0.1, 0.4, d + 0.1),
			at * CFrame.new(0, C.counterTop - 1, 0),
			GOLD
		)
	)
	local counter = Parts.new(
		m,
		"Counter",
		Vector3.new(w + 0.6, 0.4, d + 0.6),
		at * CFrame.new(0, C.counterTop - 0.2, 0),
		WOOD,
		Enum.Material.Wood
	)

	-- Posts and a candy-striped awning with a scalloped front valance.
	local postH = C.awning - C.counterTop
	for i, corner in
		{ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }
	do
		dressing(
			Parts.new(
				m,
				"Post" .. i,
				Vector3.new(0.5, postH, 0.5),
				at * CFrame.new(corner.X * (w / 2 - 0.3), C.counterTop + postH / 2, corner.Z * (d / 2 - 0.3)),
				CREAM
			)
		)
	end
	local stripes = 4
	local sw = (w + 1) / stripes
	for i = 1, stripes do
		local x = -(w + 1) / 2 + (i - 0.5) * sw
		dressing(
			Parts.new(
				m,
				"Awning" .. i,
				Vector3.new(sw, 0.5, d + 1.4),
				at * CFrame.new(x, C.awning + 0.25, 0) * CFrame.Angles(-0.12, 0, 0),
				if i % 2 == 1 then stripe else CREAM
			)
		)
		dressing(
			Parts.new(
				m,
				"Valance" .. i,
				Vector3.new(sw, 1.1, 0.2),
				at * CFrame.new(x, C.awning - 0.45, -d / 2 - 0.65),
				if i % 2 == 1 then CREAM else stripe
			)
		)
	end

	-- Lantern on a pole at the back corner: a warm light that reads from afar.
	dressing(
		Parts.new(
			m,
			"LanternPole",
			Vector3.new(0.3, 3.4, 0.3),
			at * CFrame.new(w / 2 + 0.2, C.awning + 1.7, d / 2),
			DARK
		)
	)
	local lantern = dressing(
		Parts.new(
			m,
			"Lantern",
			Vector3.new(1, 1.3, 1),
			at * CFrame.new(w / 2 + 0.2, C.awning + 3.6, d / 2),
			GLOW,
			Enum.Material.Neon
		)
	)
	warmLight(lantern)

	-- Chalkboard on the front of the body.
	local chalk = dressing(
		Parts.new(
			m,
			"Chalkboard",
			Vector3.new(w - 3, bodyH - 1.4, 0.2),
			at * CFrame.new(0, C.bodyBottom + bodyH / 2 - 0.3, -d / 2 - 0.1),
			BOARD
		)
	)
	ShopStalls.text(chalk, board, BOARD, CREAM)

	m.PrimaryPart = body
	return m, counter
end

function ShopStalls.cocoa(parent: Instance, at: CFrame, priceText: string): (Model, BasePart)
	local m, counter = cart("CocoaMachine", at, BLUE, RED, "PEPPERMINT RUSH\n" .. priceText .. " Jingle")
	local top = ShopStalls.Cart.counterTop

	-- A bubbling copper pot with a ladle, steam rising off it.
	local pot = cylinder(m, "Pot", 2.2, 2.2, at * CFrame.new(0, top + 1.1, 0.3), COPPER, Enum.Material.Metal)
	local cocoa = dressing(cylinder(m, "PotCocoa", 1.9, 0.2, at * CFrame.new(0, top + 2.15, 0.3), COCOA))
	dressing(
		Parts.new(
			m,
			"Ladle",
			Vector3.new(0.3, 3.4, 0.3),
			at * CFrame.new(1.1, top + 2.6, 0.6) * CFrame.Angles(0, 0, -0.5),
			Color3.fromRGB(140, 143, 166),
			Enum.Material.Metal
		)
	)
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Steam"
	steam.Color = ColorSequence.new(Color3.fromRGB(244, 246, 255))
	steam.Transparency = NumberSequence.new(0.35)
	steam.Rate = 3
	steam.Lifetime = NumberRange.new(1.5, 2.5)
	steam.Speed = NumberRange.new(1.5, 2.5)
	steam.Size = NumberSequence.new(1.2)
	steam.Parent = cocoa
	pot.CanCollide = false

	-- The giant gold-rimmed mug on the awning: "cocoa here" from anywhere.
	local roof = ShopStalls.Cart.awning + 0.5
	dressing(cylinder(m, "TopMug", 1.8, 3, at * CFrame.new(-2, roof + 1.5, 0), MUG))
	dressing(cylinder(m, "TopMugCocoa", 1.6, 0.2, at * CFrame.new(-2, roof + 3.05, 0), COCOA))
	dressing(cylinder(m, "TopMugBand", 1.85, 0.7, at * CFrame.new(-2, roof + 1.5, 0), CREAM))
	dressing(
		cylinder(m, "TopMugRim", 1.95, 0.35, at * CFrame.new(-2, roof + 2.95, 0), GOLD, Enum.Material.Metal)
	)
	dressing(
		Parts.new(m, "TopMugHandle", Vector3.new(1.2, 2, 0.6), at * CFrame.new(-2 + 2.2, roof + 1.5, 0), MUG)
	)

	m.Parent = parent
	return m, counter
end

-- Where server/Wardrobe hangs the gear (cart space).
export type Rail = { y: number, z: number, shelfY: number, frontZ: number, width: number }

function ShopStalls.wardrobe(parent: Instance, at: CFrame): (Model, Rail)
	local m = cart("WardrobeStall", at, GREEN, GREEN, "WARDROBE\nwarm gear")
	local C = ShopStalls.Cart

	-- Hanging rail across the front posts, under the awning.
	local railZ = -C.depth / 2 + 0.3
	dressing(
		Parts.new(
			m,
			"Rail",
			Vector3.new(C.width - 0.6, 0.3, 0.3),
			at * CFrame.new(0, C.awning - 1.4, railZ),
			WOOD
		)
	)

	-- A giant blue mitten on the awning.
	local roof = C.awning + 0.5
	dressing(
		Parts.new(
			m,
			"TopMitten",
			Vector3.new(2.4, 2.8, 1),
			at * CFrame.new(2, roof + 2.2, 0),
			MITTEN,
			Enum.Material.Fabric
		)
	)
	dressing(
		Parts.new(
			m,
			"TopMittenThumb",
			Vector3.new(0.9, 1.4, 0.9),
			at * CFrame.new(2 - 1.5, roof + 2.4, 0),
			MITTEN,
			Enum.Material.Fabric
		)
	)
	dressing(
		Parts.new(
			m,
			"TopMittenCuff",
			Vector3.new(2.7, 0.9, 1.2),
			at * CFrame.new(2, roof + 0.45, 0),
			CREAM,
			Enum.Material.Fabric
		)
	)

	m.Parent = parent
	return m,
		{
			y = C.awning - 1.4,
			z = railZ,
			shelfY = C.counterTop,
			frontZ = -C.depth / 2 - 0.3,
			width = C.width - 2,
		}
end

return ShopStalls
