local WindowMoods = load("ReplicatedStorage.Shared.WindowMoods")

test("a pane's seed is stable and between 0 and 1", function()
	local p = Vector3.new(12.5, 8, -40)
	local a = WindowMoods.seed(p)
	expect(a).toBe(WindowMoods.seed(p))
	expect(a >= 0 and a < 1).toBeTruthy()
	expect(WindowMoods.seed(Vector3.new(13, 8, -40))).never.toBe(a)
end)

test("TVs change picture within a second or so", function()
	local seen = {}
	for i = 0, 40 do
		seen[tostring(WindowMoods.tv(i * 0.1, 0.3))] = true
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	expect(n).toBeGreaterThan(2)
end)

test("an empty room lights up for a few seconds now and then", function()
	local lit, total = 0, 0
	for i = 0, 3999 do
		total += 1
		lit += if WindowMoods.darkLit(i * 0.1, 0.5) then 1 else 0
	end
	expect(lit).toBeGreaterThan(0)
	expect(lit / total).toBeLessThan(0.4)
	local colour, glow = WindowMoods.look("Dark", 0, 0)
	expect(glow ~= nil).toBeTruthy()
	expect(colour ~= nil).toBeTruthy()
end)

test("dressing-only moods leave the pane alone", function()
	for _, mood in { "Curtains", "Candle", "Cat", "Tree", "Star" } do
		expect(WindowMoods.look(mood, 1, 0.5)).toBeNil()
	end
	local colour = WindowMoods.look("Lamp", 1, 0.5)
	expect(colour.R > 0.9).toBeTruthy()
end)
