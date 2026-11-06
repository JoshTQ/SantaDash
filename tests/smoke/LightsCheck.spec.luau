--[[
	"Who's there?!" checks (Josh, 6 Nov 2026: lights on needed a consequence).
	Plays a fast Stop 1 headless and stands a Santa in the first lit house.
]]

local function startStop1(world)
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 40
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 30
	Config.Noise.Alarm.Enabled = false -- keep the dogs out of this test
	Config.ElfBots.MaxCrewForBots = 0 -- and the elves, who fill sacks for solo Santas
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local a = engine:addPlayer("A")
	local run = Run.new(1, { a }, function() end)
	run:start()
	while run.stopIndex < 1 or run.phase ~= "Sneak" do
		world.wait(0.1)
	end
	local stop = run.route.stops[1]
	local house = stop.lights[1].Parent.Parent
	local box, size = house:GetBoundingBox()
	local inside = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2 + 3, box.Position.Z)
	return run, engine, a, stop, house, inside, Config
end

local function hasSign(house, enabled: boolean): boolean
	for _, d in house:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "WhosThere" and d.Enabled == enabled then
			return true
		end
	end
	return false
end

local function droppedPresents(run): number
	local n = 0
	for _, d in run.route.model:GetDescendants() do
		if d:IsA("Model") and d.Name == "DroppedPresent" then
			n += 1
		end
	end
	return n
end

describe("Who's there?! checks", function()
	it("warns, then spots a Santa in a lit house: drops a present, adds noise, bonks them out", function()
		local world = headless()
		world.run(function()
			local run, engine, a, _, house, inside, Config = startStop1(world)
			local LightsCheck = world.load("ServerScriptService.Server.LightsCheck")
			while run.phase ~= "LightsOn" do
				world.wait(0.1)
			end
			local st = run.players[a]
			st.sackCount, st.sackValue = 2, 100
			local root = a.Character.HumanoidRootPart
			root.CFrame = inside
			root.Anchored = true -- stand still in the hallway
			local noise = run.noise

			local deadline = engine.now + Config.LightsCheck.FirstDelay + Config.LightsCheck.WarnSeconds + 2
			local warned = false
			while st.sackCount == 2 and engine.now < deadline do
				warned = warned or hasSign(house, true)
				world.wait(0.1)
			end
			expect(warned).toBeTruthy()
			expect(st.sackCount).toBe(1)
			expect(st.sackValue).toBe(50)
			expect(run.noise >= noise + Config.LightsCheck.Noise * 0.99).toBeTruthy()
			expect(droppedPresents(run)).toBe(1)
			local box, size = house:GetBoundingBox()
			expect(LightsCheck.inside(box, size, root.Position)).toBeFalsy()
			expect(#engine:hudMessages(a, "Banner") > 0).toBeTruthy()
			run.ended = true
		end, { maxSeconds = 120 })
	end)

	it("a Santa hiding in the wardrobe isn't spotted", function()
		local world = headless()
		world.run(function()
			local run, engine, a, stop, house, inside, Config = startStop1(world)
			local spot
			for _, s in stop.hideSpots do
				if s.inside and house:GetBoundingBox() then
					local box, size = house:GetBoundingBox()
					local LightsCheck = world.load("ServerScriptService.Server.LightsCheck")
					if LightsCheck.inside(box, size, s.inside.Position) then
						spot = s
						break
					end
				end
			end
			while run.phase ~= "LightsOn" do
				world.wait(0.1)
			end
			local st = run.players[a]
			st.sackCount, st.sackValue = 2, 100
			a.Character.HumanoidRootPart.CFrame = inside
			if spot then
				run:_hide(a, spot)
			else
				st.hidden = { inside = inside, exit = inside } -- this house type has no wardrobe
			end
			local noise = run.noise
			world.wait(Config.LightsCheck.FirstDelay + Config.LightsCheck.WarnSeconds + 1.5)
			expect(st.sackCount).toBe(2)
			expect(droppedPresents(run)).toBe(0)
			expect(run.noise < noise + Config.LightsCheck.Noise).toBeTruthy()
			run.ended = true
		end, { maxSeconds = 120 })
	end)

	it("nothing checks before the lights come on, and the signs go when the sleigh leaves", function()
		local world = headless()
		world.run(function()
			local run, engine, a, _, house, inside = startStop1(world)
			local st = run.players[a]
			st.sackCount, st.sackValue = 2, 100
			local root = a.Character.HumanoidRootPart
			root.CFrame = inside
			root.Anchored = true
			while run.phase == "Sneak" do
				world.wait(0.1)
			end
			expect(st.sackCount).toBe(2) -- the sneak phase is safe
			root.Anchored = false
			root.CFrame = run.route.stops[1].deckCFrame * CFrame.new(0, 3, 60)
			while run.stopIndex == 1 and not run.ended do
				world.wait(0.2)
			end
			expect(hasSign(house, true)).toBeFalsy()
			expect(hasSign(house, false)).toBeFalsy() -- destroyed, not just hidden
			run.ended = true
		end, { maxSeconds = 200 })
	end)
end)
