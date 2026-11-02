-- Smoke test of a whole run in a real server: build, take-off flight, end,
-- clean-up. A crew with no players ends after the first flight.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Run = require(ServerStorage.Server.Run)

describe("Run", function()
	it("builds a route, flies, ends and cleans up after itself", function()
		Remotes.init()
		local finished, survivors = false, nil
		local run = Run.new(7, {}, function(_, s)
			finished = true
			survivors = s
		end)

		local routeModel = run.route.model
		expect(routeModel:IsDescendantOf(workspace)).toBe(true)
		expect(#run.route.stops).toBe(#Config.Run.StopKinds)

		run:start()
		local deadline = os.clock() + Config.Run.FlightSeconds + 20
		while not finished and os.clock() < deadline do
			task.wait(0.25)
		end

		expect(finished).toBe(true)
		expect(#survivors).toBe(0)
		expect(run.ended).toBe(true)
		expect(routeModel.Parent).toBeNil()
	end, 60000)
end)
