local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Util = require(ReplicatedStorage.Shared.Util)

describe("Util.now", function()
	it("is the server-synchronised clock", function()
		expect(Util.now()).toBeCloseTo(workspace:GetServerTimeNow(), 0)
	end)
end)
