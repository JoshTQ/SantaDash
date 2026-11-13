--[[
	PromptSight.client in a headless world (Josh, 13 Nov 2026: "you can
	interact with gifts through walls, outside of the house"): a gift behind
	a wall can't be grabbed from outside, and comes back once you walk round.
]]

local function setup()
	local world = headless()
	local engine = world.engine
	engine.raycasts = true
	local me = engine:addPlayer("Me")
	engine:setLocalPlayer(me)
	local ws = engine.workspace
	local Instance = engine.Instance
	local house = Instance.new("Model")
	house.Name = "House"
	house.Parent = ws
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.Size = Vector3.new(20, 12, 1)
	wall.CFrame = CFrame.new(0, 6, 0)
	wall.Parent = house
	local present = Instance.new("Model")
	present.Name = "Present"
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Anchored = true
	box.Size = Vector3.new(2, 2, 2)
	box.CFrame = CFrame.new(0, 1, 3)
	box.Parent = present
	local ribbon = Instance.new("Part")
	ribbon.Name = "Ribbon"
	ribbon.Anchored = true
	ribbon.Size = Vector3.new(2.2, 2.2, 0.3)
	ribbon.CFrame = box.CFrame
	ribbon.Parent = present
	present.PrimaryPart = box
	present.Parent = house
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.MaxActivationDistance = 10
	prompt.Parent = box
	local door = Instance.new("ProximityPrompt")
	door.ActionText = "Close"
	door.MaxActivationDistance = 10
	door.Parent = wall
	local character = Instance.new("Model")
	character.Name = "Me"
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.Size = Vector3.new(1, 1, 1)
	head.Parent = character
	character.Parent = ws
	me.Character = character
	return world, head, prompt, door
end

test("a gift behind a wall can't be grabbed from outside, and can from inside", function()
	local world, head, prompt, door = setup()
	head.CFrame = CFrame.new(0, 4.5, -4) -- outside, 7 studs away through the wall
	world.run(function()
		world.runScript("StarterPlayer.StarterPlayerScripts.Client.PromptSight")
		world.wait(0.5)
	end)
	expect(prompt.MaxActivationDistance).toBe(0)
	expect(door.MaxActivationDistance).toBe(10) -- doors are left alone

	head.CFrame = CFrame.new(0, 4.5, 8) -- inside, same distance, nothing in the way
	world.run(function()
		world.wait(0.5)
	end)
	expect(prompt.MaxActivationDistance).toBe(10)
end)

test("the server refuses a grab through a wall, and allows it round the door", function()
	local world, head, prompt = setup()
	local PromptSight = world.load("ReplicatedStorage.Shared.PromptSight")
	local character = head.Parent
	world.run(function()
		head.CFrame = CFrame.new(0, 4.5, -4) -- outside, wall between
		expect(PromptSight.serverAllows(character, prompt)).toBe(false)
		head.CFrame = CFrame.new(0, 4.5, 8) -- inside
		expect(PromptSight.serverAllows(character, prompt)).toBe(true)
		-- Lag: the server sees you just round the end of the wall.
		-- Lag: the server has you just short of the wall's end; a nudge sees round it.
		head.CFrame = CFrame.new(11, 4.5, -0.6)
		expect(PromptSight.sees(head.Position, prompt.Parent, character)).toBe(false)
		expect(PromptSight.serverAllows(character, prompt)).toBe(true)
	end)
end)
