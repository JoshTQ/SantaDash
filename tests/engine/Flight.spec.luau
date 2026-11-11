--[[
	The sleigh ride in a real server: a rider is carried in their seat along
	the whole flight and is let go aboard the landed sleigh. (Open Cloud
	servers don't simulate physics, so standing on it afterwards under gravity
	is checked in tests/studio.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(ServerStorage.Server.MapBuilder)
local Run = require(ServerStorage.Server.Run)
local Rig = require(script.Parent.Rig)

describe("sleigh flight", function()
	it("carries a rider seat-to-seat and lets them go aboard", function()
		Remotes.init()
		local run = Run.new(8, {}, function() end)
		local from = run.route.startDeck
		local to = run.route.stops[1].deckCFrame
		local santa = Rig.santa(run.route.model, (from * CFrame.new(0, 2, 0)).Position)
		local rider = Rig.player(santa, "Rider")
		local seconds = 3

		local worst = 0
		local sampling = true
		task.spawn(function()
			while sampling do
				if santa.root.Anchored then
					local seat = run.route.seatOffsets[1]
					worst = math.max(worst, (santa.root.Position - (run.deck * seat).Position).Magnitude)
				end
				task.wait()
			end
		end)
		run:_ride(
			{ rider },
			{ path = "flight", base = from, to = to, peak = Config.Run.FlightArcHeight, seconds = seconds }
		)
		sampling = false

		expect(worst).toBeLessThan(0.5) -- glued to the seat the whole way
		expect(run.deck).toEqual(to)
		expect(santa.root.Anchored).toBe(false)
		expect(MapBuilder.isAboard(to, santa.root.Position)).toBe(true)

		run:_finish()
	end, 90000)
end)
