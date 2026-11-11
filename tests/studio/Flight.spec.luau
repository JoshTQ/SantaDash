--[[
	STUDIO ONLY (needs physics, see Physics.spec): after the sleigh lands and
	lets a rider go, real gravity keeps them standing on the sleigh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(ServerStorage.Server.MapBuilder)
local Run = require(ServerStorage.Server.Run)
local Rig = require(ReplicatedStorage.EngineTests.Rig)

describe("sleigh landing under gravity", function()
	it("a rider let go after landing stays standing on the sleigh", function()
		Remotes.init()
		local run = Run.new(8, {}, function() end)
		local from = run.route.startDeck
		local to = run.route.stops[1].deckCFrame
		local santa = Rig.santa(run.route.model, (from * CFrame.new(0, 2, 0)).Position)
		run:_ride(
			{ Rig.player(santa, "Rider") },
			{ path = "flight", base = from, to = to, peak = Config.Run.FlightArcHeight, seconds = 3 }
		)
		task.wait(1.5)
		expect(MapBuilder.isAboard(to, santa.root.Position)).toBe(true)
		expect(santa.root.Position.Y).toBeGreaterThan(to.Position.Y - 1)
		expect(santa.root.CFrame.UpVector.Y).toBeGreaterThan(0.7)
		run:_finish()
	end, 90000)
end)
