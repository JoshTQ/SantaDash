--[[
	First-time player tips (server/Onboarding + client/Tips) against the real
	server in one headless world: the lobby trail to a sleigh, the run's tips,
	"First heist!" tag, the X button, and veterans who never see a tip.
]]

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 120)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function boot(names: { string }?)
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
	local me = engine:addPlayer("Me")
	engine:setLocalPlayer(me)
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.runScript("StarterPlayer.StarterPlayerScripts.Client.Tips")
		world.wait(0.5)
	end)
	return world, engine, me, Config
end

local function tipIds(engine, player): { [string]: number }
	local ids = {}
	for _, m in engine:hudMessages(player, "Tip") do
		ids[m.data.id] = (ids[m.data.id] or 0) + 1
	end
	return ids
end

local function seated(player): boolean
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function boardPublic(world, player)
	local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
	waitUntil(world, function()
		local p = StationClock.phaseAt("Public", 1, world.engine.now)
		return p.name == "Boarding" and p.endsAt - world.engine.now >= 4
	end, 120, "Public boarding")
	local zone = world.engine.workspace:FindFirstChild("PublicZone", true)
	world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
	waitUntil(world, function()
		return seated(player)
	end, 5, "sitting on the sleigh")
end

local function tag(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root:FindFirstChild("FirstHeistTag")
end

local function marker(engine)
	return engine.workspace:FindFirstChild("TipMarker")
end

describe("first-time player tips", function()
	it("guides a new player from the workshop onto a sleigh, then clears the trail", function()
		local world, engine, me = boot()
		world.run(function()
			waitUntil(world, function()
				return engine:guiShows("Follow the trail to a sleigh!")
			end, 15, "the Board tip")
			expect(marker(engine)).never.toBeNil()
			expect(tag(me)).never.toBeNil()
			expect(me:GetAttribute("FirstHeist")).toBe(true)
			boardPublic(world, me)
			world.wait(0.5)
			expect(#engine:hudMessages(me, "TipDone")).toBeGreaterThanOrEqual(1)
			expect(marker(engine)).toBeNil()
		end)
	end)

	it("teaches the run in order: sneak, grab, carry, lights, horn, Lair, Krampus, done", function()
		local world, engine, me = boot()
		world.run(function()
			boardPublic(world, me)
			waitUntil(world, function()
				return tipIds(engine, me).Sneak ~= nil
			end, 60, "the Sneak tip")
			expect(tipIds(engine, me).Grab).toBe(1)
			-- Grab a present: the Grab tip is learnt, Carry comes next.
			local present
			for _, d in engine.workspace:GetDescendants() do
				if d:IsA("ProximityPrompt") and d.ActionText == "Grab" then
					present = d
					break
				end
			end
			expect(present).never.toBeNil()
			engine.trigger(present, me)
			world.wait(0.5)
			local done = {}
			for _, m in engine:hudMessages(me, "TipDone") do
				done[m.data.id] = true
			end
			expect(done.Grab).toBe(true)
			expect(tipIds(engine, me).Carry).toBe(1)
			waitUntil(world, function()
				return engine:guiShows("Best thief: Me") or #engine:hudMessages(me, "Results") > 0
			end, 300, "the results")
			local ids = tipIds(engine, me)
			for _, id in { "LightsOn", "Horn", "Bank", "Lair", "Krampus", "Done" } do
				expect(ids[id]).toBe(1)
			end
			-- Every core lesson learnt: no longer new, tag gone.
			expect(me:GetAttribute("FirstHeist")).toBe(false)
			expect(tag(me)).toBeNil()
		end)
	end)

	it("shows each tip only once across runs", function()
		local world, engine, me = boot()
		world.run(function()
			boardPublic(world, me)
			waitUntil(world, function()
				return #engine:hudMessages(me, "Results") > 0
			end, 300, "the first run")
			waitUntil(world, function()
				return #engine:hudMessages(me, "Results") > 1
			end, 400, "the second run")
			for id, count in tipIds(engine, me) do
				if id ~= "Grab" and id ~= "Board" then -- action tips may repeat until done
					expect(count).toBe(1)
				end
			end
		end)
	end)

	it("the X switches tips off for good", function()
		local world, engine, me = boot()
		world.run(function()
			waitUntil(world, function()
				return engine:guiShows("Follow the trail")
			end, 15, "the Board tip")
			engine:guiButton("X").Activated:Fire()
			world.wait(0.5)
			expect(engine:guiShows("Follow the trail")).toBe(false)
			expect(marker(engine)).toBeNil()
			expect(me:GetAttribute("FirstHeist")).toBe(false)
			local before = #engine:hudMessages(me, "Tip")
			boardPublic(world, me)
			waitUntil(world, function()
				return #engine:hudMessages(me, "Results") > 0
			end, 300, "the run")
			expect(#engine:hudMessages(me, "Tip")).toBe(before)
		end)
	end)
end)

describe("Onboarding with saved progress", function()
	it("never shows a veteran a tip, and treats a failed load as new", function()
		local world = headless()
		local engine = world.engine
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local Onboarding = world.load("ServerScriptService.Server.Onboarding")
		local Tutorial = world.load("ReplicatedStorage.Shared.Tutorial")
		local vet = engine:addPlayer("Vet")
		local newbie = engine:addPlayer("Newbie")
		local saves = {}
		local store = {
			waitFor = function(player)
				if player == newbie then
					error("DataStore down")
				end
				local done = {}
				for _, l in Tutorial.Lessons do
					done[l.id] = true
				end
				return { tutorial = { done = done } }
			end,
			update = function(player, fn)
				local data = {}
				fn(data)
				saves[player.Name] = data.tutorial
			end,
		}
		world.run(function()
			Onboarding._reset(store)
			Onboarding._setHud(world.load("ReplicatedStorage.Shared.Remotes").get("Hud"))
			Onboarding.load(vet)
			Onboarding.load(newbie)
			expect(Onboarding.teach(vet, "Sneak")).toBe(false)
			expect(Onboarding.isNew(vet)).toBe(false)
			expect(Onboarding.teach(newbie, "Sneak")).toBe(true)
			expect(Onboarding.isNew(newbie)).toBe(true)
			-- Saved as plain data the store can write.
			expect(saves.Newbie.done.Sneak).toBe(true)
			expect(saves.Newbie.tipsOff).toBe(false)
			-- Action tips come back after RepeatSeconds, not before.
			expect(Onboarding.teach(newbie, "Grab")).toBe(true)
			expect(Onboarding.teach(newbie, "Grab")).toBe(false)
			world.wait(Onboarding.RepeatSeconds + 1)
			expect(Onboarding.teach(newbie, "Grab")).toBe(true)
			Onboarding.complete(newbie, "Grab")
			expect(saves.Newbie.done.Grab).toBe(true)
			-- Unknown players and lessons are ignored.
			Onboarding.unload(newbie)
			expect(Onboarding.teach(newbie, "Horn")).toBe(false)
		end)
		expect(#engine:hudMessages(vet, "Tip")).toBe(0)
	end)
end)
