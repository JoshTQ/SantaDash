--[[
	Pop-in houses through a real Run (Josh, 11 Nov 2026: "most houses on the
	map are closed with no entry"): walk up to a filler townhouse and its door
	swings open on a room; grab its gift; walk away and it packs up again.
]]

local function boot()
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 90
	Config.Run.LightsOnAt = 80
	Config.Run.HornAt = 85
	Config.MapEvents.Chance = 0
	Config.PopIn.GiftChance = 1 -- every room has a gift
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local Util = world.load("ReplicatedStorage.Shared.Util")
	return world, engine, Config, Run, Util, { engine:addPlayer("A") }
end

it("a Santa at the door opens the room, grabs its gift, and it packs away after they leave", function()
	local world, engine, Config, Run, Util, players = boot()
	local santa = players[1]
	world.run(function()
		local run = Run.new(1, players, function() end)
		run:start()
		local deadline = engine.now + 200
		while not (run.stopIndex == 1 and run.phase ~= "Flight") do
			assert(engine.now < deadline, "never reached stop 1")
			world.wait(0.1)
		end
		world.wait(0.5)
		local stop = run.route.stops[1]
		expect(#stop.popIns > 10).toBeTruthy()
		local entry = stop.popIns[1]
		expect(entry.room).toBeNil()
		local presentsBefore = #stop.presents

		-- Walk up to the door (just outside it).
		local doorAt = entry.door.CFrame.Position
		Util.teleport(santa, CFrame.new(doorAt + entry.frame.LookVector * 4 + Vector3.new(0, 3, 0)))
		world.wait(Config.PopIn.TickSeconds * 3)
		expect(entry.room ~= nil).toBeTruthy()
		expect(entry.block.CanCollide).toBe(false)
		local present = entry.present
		expect(present ~= nil).toBeTruthy()
		expect(#stop.presents).toBe(presentsBefore + 1)
		-- No other house opened.
		for i = 2, #stop.popIns do
			local other = stop.popIns[i]
			if (other.door.CFrame.Position - doorAt).Magnitude > Config.PopIn.OpenRadius + 6 then
				expect(other.room).toBeNil()
			end
		end

		-- Grab it: one more in the sack and a token of Jingle.
		local st = run.players[santa]
		local count, jingle = st.sackCount, st.jingle
		engine.trigger(present.prompt, santa)
		world.wait(0.5)
		expect(st.sackCount).toBe(count + 1)
		expect(st.jingle).toBe(jingle + Config.PopIn.Jingle)

		-- Back to the sleigh: the room packs away a few seconds later.
		Util.teleport(santa, stop.deckCFrame + Vector3.new(0, 3, 0))
		world.wait(Config.PopIn.CloseSeconds + 1)
		expect(entry.room).toBeNil()
		expect(entry.block.CanCollide).toBe(true)
		expect(#stop.presents).toBe(presentsBefore)

		-- Back again: the door opens, the gift's gone (cookies instead).
		Util.teleport(santa, CFrame.new(doorAt + entry.frame.LookVector * 4 + Vector3.new(0, 3, 0)))
		world.wait(Config.PopIn.TickSeconds * 3)
		expect(entry.room ~= nil).toBeTruthy()
		expect(entry.present).toBeNil()
		expect(entry.room:FindFirstChild("Cookies") ~= nil).toBeTruthy()
		run.ended = true
	end)
end)

it("rooms all pack away when the sleigh leaves the stop", function()
	local world, engine, Config, Run, Util, players = boot()
	local santa = players[1]
	world.run(function()
		local run = Run.new(1, players, function() end)
		run:start()
		local deadline = engine.now + 200
		while not (run.stopIndex == 1 and run.phase ~= "Flight") do
			assert(engine.now < deadline, "never reached stop 1")
			world.wait(0.1)
		end
		world.wait(0.5)
		local stop = run.route.stops[1]
		local entry = stop.popIns[2]
		Util.teleport(
			santa,
			CFrame.new(entry.door.CFrame.Position + entry.frame.LookVector * 3 + Vector3.new(0, 3, 0))
		)
		world.wait(1)
		expect(entry.room ~= nil).toBeTruthy()
		while run.stopIndex == 1 do
			assert(engine.now < deadline + 300, "stop 1 never ended")
			world.wait(0.5)
		end
		expect(entry.room).toBeNil()
		expect(entry.block.Transparency).toBe(0)
		run.ended = true
	end)
end)
