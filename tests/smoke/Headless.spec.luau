-- The headless engine itself: clock, signals, players, walking, welds.
describe("headless engine", function()
	it("runs task.wait on virtual time", function()
		local world = headless()
		local t0 = world.engine.now
		world.run(function()
			world.wait(30)
		end)
		expect(world.engine.now - t0).toBeGreaterThanOrEqual(30)
	end)

	it("walks a humanoid to its MoveTo goal at WalkSpeed", function()
		local world = headless()
		local engine = world.engine
		local player = engine:addPlayer("Walker")
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		world.run(function()
			humanoid:MoveTo(Vector3.new(32, 3, 0))
			world.wait(1)
			expect(engine.rootOf(player).Position.X).toBeNear(16, 2)
			world.wait(2)
			expect(engine.rootOf(player).Position.X).toBeNear(32, 0.01)
		end)
	end)

	it("fires Touched when a character walks onto a part", function()
		local world = headless()
		local engine = world.engine
		local pad = engine.Instance.new("Part")
		pad.Size = Vector3.new(10, 1, 10)
		pad.CFrame = CFrame.new(50, 0, 0)
		pad.Parent = engine.workspace
		local touched = 0
		pad.Touched:Connect(function()
			touched += 1
		end)
		local player = engine:addPlayer("Toucher")
		world.run(function()
			engine:teleport(player, Vector3.new(50, 2, 0))
			world.wait(0.5)
		end)
		expect(touched).toBe(1)
	end)

	it("loads game modules into the world", function()
		local world = headless()
		local Config = world.load("ReplicatedStorage.Shared.Config")
		expect(Config.Run.StopSeconds).toBe(120)
	end)
end)
