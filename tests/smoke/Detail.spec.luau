--[[
	Detail.client running against the real server in a headless world: the
	hub's dressing leaves the scene when the camera goes far away and comes
	back in one frame when it jumps home.
]]

local function boot()
	local world = headless()
	local engine = world.engine
	local me = engine:addPlayer("Me")
	engine:setLocalPlayer(me)
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.runScript("StarterPlayer.StarterPlayerScripts.Client.Detail")
		world.wait(0.5)
	end)
	return world
end

local function hubParts(hub)
	local n = 0
	for _, d in hub:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

test("far dressing leaves the scene and a jump home brings it straight back", function()
	local world = boot()
	local hub = world.engine.workspace:FindFirstChild("SleighStationLobby")
	expect(hub).never.toBeNil()
	expect(hub:GetAttribute("DetailRoot")).toBe(true)
	local camera = world.engine.workspace.CurrentCamera
	local home = camera.CFrame
	local all = hubParts(hub)
	world.run(function()
		world.wait(1)
	end)
	expect(hubParts(hub)).toBe(all)

	-- Far away (a run's route is 1,600+ studs off): dressing goes, a bit per step.
	camera.CFrame = CFrame.new(0, 20, 5000)
	world.run(function()
		world.wait(3)
	end)
	local far = hubParts(hub)
	expect(far).toBeLessThan(all)

	-- Jump home (a respawn): back in the very next frame, no waiting for steps.
	camera.CFrame = home
	world.run(function()
		world.wait(0.05)
	end)
	expect(hubParts(hub)).toBe(all)
end)

test("the DetailOff workspace attribute puts everything back", function()
	local world = boot()
	local hub = world.engine.workspace:FindFirstChild("SleighStationLobby")
	local camera = world.engine.workspace.CurrentCamera
	local all = hubParts(hub)
	camera.CFrame = CFrame.new(0, 20, 5000)
	world.run(function()
		world.wait(3)
	end)
	expect(hubParts(hub)).toBeLessThan(all)
	world.engine.workspace:SetAttribute("DetailOff", true)
	world.run(function()
		world.wait(0.5)
	end)
	expect(hubParts(hub)).toBe(all)
end)
