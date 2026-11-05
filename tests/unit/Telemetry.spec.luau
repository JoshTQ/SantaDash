--[[
	Crash and error analytics (server/Telemetry.luau) and Util.retry.
	Telemetry runs in a headless world so ScriptContext, LogService and the
	ClientError remote behave as in a real server.
]]

local function setup()
	local world = headless()
	local engine = world.engine
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Telemetry = world.load("ServerScriptService.Server.Telemetry")
	local Config = world.load("ReplicatedStorage.Shared.Config")
	local logged = {}
	engine:service("AnalyticsService").LogCustomEvent = function(_, player, event, value, fields)
		table.insert(logged, { player = player, event = event, value = value, fields = fields })
	end
	return world, engine, Telemetry, Config, logged
end

local function findLog(logged, event: string)
	for _, entry in logged do
		if entry.event == event then
			return entry
		end
	end
	return nil
end

describe("Telemetry signatures", function()
	it("strips player names, numbers, ids and quoted text", function()
		local _, _, Telemetry = setup()
		expect(Telemetry.signature("Players.Ann123.PlayerScripts.Hud:42: attempt to index nil with 'Text'")).toBe(
			"Hud:#: attempt to index nil with <s>"
		)
		expect(Telemetry.signature('ServerScriptService.Server.Run:310: bad 12.5 "Ann"')).toBe(
			"Run:#: bad # <s>"
		)
		expect(Telemetry.signature("[Matchmaker] crew 0123abcd-1234-4abc-8def-0123456789ab failed")).toBe(
			"[Matchmaker] crew <id> failed"
		)
		expect(Telemetry.signature("first line\nstack trace line")).toBe("first line")
		expect(Telemetry.signature("   ")).toBe("(empty)")
	end)

	it("keeps signatures short", function()
		local _, _, Telemetry, Config = setup()
		local long = string.rep("x", 500)
		expect(#Telemetry.signature(long)).toBe(Config.Telemetry.SignatureLength)
	end)
end)

describe("Telemetry counting and flushing", function()
	it("counts events by detail and folds too many distinct details into Other", function()
		local _, _, Telemetry, Config = setup()
		local max = Config.Telemetry.MaxSignaturesPerFlush
		for i = 1, max + 5 do
			Telemetry.count("Thing", "d" .. i)
		end
		Telemetry.count("Thing", "d1", 4)
		local pending = Telemetry.pending().Thing
		expect(pending.d1).toBe(5)
		expect(pending.Other).toBe(5)
		expect(Telemetry.totals().Thing).toBe(max + 5 + 4)
	end)

	it("waits for a player before sending, then sends each bucket once with its place", function()
		local world, engine, Telemetry, _, logged = setup()
		world.run(function()
			Telemetry.start("Run")
			Telemetry.count("TeleportFailed", "GameFull", 2)
			expect(Telemetry.flush()).toBe(0) -- nobody to attach the events to
			expect(Telemetry.pending().TeleportFailed.GameFull).toBe(2)
			local ann = engine:addPlayer("Ann")
			expect(Telemetry.flush()).toBe(1)
			local entry = findLog(logged, "TeleportFailed")
			expect(entry.player).toBe(ann)
			expect(entry.value).toBe(2)
			expect(entry.fields.CustomField01).toBe("GameFull")
			expect(entry.fields.CustomField02).toBe("Run")
			expect(next(Telemetry.pending())).toBeNil()
			expect(Telemetry.flush()).toBe(0) -- nothing new
		end)
	end)

	it("flushes on its own every FlushSeconds", function()
		local world, engine, Telemetry, Config, logged = setup()
		world.run(function()
			Telemetry.start("Lobby")
			engine:addPlayer("Ann")
			Telemetry.count("MatchCrewFormed", "Public 6")
			world.wait(Config.Telemetry.FlushSeconds + 1)
			expect(findLog(logged, "MatchCrewFormed")).never.toBeNil()
		end)
	end)

	it("counts a failed send as dropped without warning about it", function()
		local world, engine, Telemetry = setup()
		engine:service("AnalyticsService").LogCustomEvent = function()
			error("analytics is down")
		end
		world.run(function()
			Telemetry.start("Lobby")
			engine:addPlayer("Ann")
			Telemetry.count("Thing")
			expect(Telemetry.flush()).toBe(0)
			world.wait(0.5)
		end)
		expect(Telemetry.totals().TelemetryDropped).toBe(1)
		expect(#engine.warnings).toBe(0)
		expect(Telemetry.totals().Warning).toBeNil()
	end)
end)

describe("Telemetry hooks", function()
	it("counts server script errors and warnings", function()
		local world, engine, Telemetry = setup()
		world.run(function()
			Telemetry.start("Lobby")
			engine:spawn(function()
				error("boom 42")
			end)
			-- (The spec's own warn is Lune's; game code's warn goes to LogService.)
			engine
				:service("LogService").MessageOut
				:Fire("[Lobby] tick failed: oops 7", Enum.MessageType.MessageWarning)
			engine:service("LogService").MessageOut:Fire("just output", Enum.MessageType.MessageOutput)
			world.wait(0.5)
		end, { allowErrors = true })
		local pending = Telemetry.pending()
		expect(Telemetry.totals().ServerError).toBe(1)
		local signature = next(pending.ServerError)
		expect(string.find(signature, "boom #", 1, true)).never.toBeNil()
		expect(pending.Warning["[Lobby] tick failed: oops #"]).toBe(1)
		expect(Telemetry.totals().Warning).toBe(1) -- plain output isn't a warning
	end)

	it("accepts client error reports, ignores junk and caps each player", function()
		local world, engine, Telemetry, Config = setup()
		local Remotes = world.load("ReplicatedStorage.Shared.Remotes")
		world.run(function()
			Telemetry.start("Lobby", Remotes.get("ClientError"))
			local ann = engine:addPlayer("Ann")
			local remote = Remotes.get("ClientError")
			remote.OnServerEvent:Fire(ann, { junk = true })
			remote.OnServerEvent:Fire(ann, 12)
			for i = 1, Config.Telemetry.ClientErrorsPerPlayer + 10 do
				remote.OnServerEvent:Fire(ann, "Players.Ann.PlayerScripts.Hud:" .. i .. ": oops")
			end
			world.wait(0.2)
		end)
		local pending = Telemetry.pending().ClientError
		expect(pending["Hud:#: oops"]).toBe(Config.Telemetry.ClientErrorsPerPlayer)
	end)

	it("is started by Main in both places, with the ClientError remote", function()
		local world, engine = setup()
		world.run(function()
			world.runScript("ServerScriptService.Server.Main")
			world.wait(0.5)
		end)
		local remotes = engine:service("ReplicatedStorage"):FindFirstChild("Remotes")
		expect(remotes:FindFirstChild("ClientError")).never.toBeNil()
		local Telemetry = world.load("ServerScriptService.Server.Telemetry")
		world.run(function()
			engine:spawn(function()
				error("after start")
			end)
			world.wait(0.2)
		end, { allowErrors = true })
		expect(Telemetry.totals().ServerError).toBe(1)
	end)
end)

describe("Util.retry", function()
	it("returns the first success and stops trying", function()
		local world = headless()
		local Util = world.load("ReplicatedStorage.Shared.Util")
		local tries, ok, value = 0, nil, nil
		world.run(function()
			ok, value = Util.retry(3, 1, function(a, b)
				tries += 1
				if tries < 2 then
					error("hiccup")
				end
				return a + b
			end, 2, 3)
		end)
		expect(ok).toBe(true)
		expect(value).toBe(5)
		expect(tries).toBe(2)
	end)

	it("waits longer between each try and returns the last error", function()
		local world = headless()
		local engine = world.engine
		local Util = world.load("ReplicatedStorage.Shared.Util")
		local at, ok, err = {}, nil, nil
		world.run(function()
			ok, err = Util.retry(3, 1, function()
				table.insert(at, engine.now)
				error("down " .. #at)
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "down 3", 1, true)).never.toBeNil()
		expect(#at).toBe(3)
		expect(at[2] - at[1]).toBeNear(1, 0.15)
		expect(at[3] - at[2]).toBeNear(2, 0.15)
	end)
end)
