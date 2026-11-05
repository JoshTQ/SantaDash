local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Remotes = require(ReplicatedStorage.Shared.Remotes)

describe("Remotes", function()
	it("creates every RemoteEvent on the server, once", function()
		Remotes.init()
		Remotes.init()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		expect(folder).never.toBeNil()
		for _, name in { "Hud", "LeaveCrew", "Input", "Store", "ClientError" } do
			local remote = Remotes.get(name)
			expect(remote:IsA("RemoteEvent")).toBe(true)
			expect(remote.Parent).toBe(folder)
		end
		expect(#folder:GetChildren()).toBe(4)
	end)

	it("fails loudly for a remote that doesn't exist", function()
		Remotes.init()
		expect(function()
			Remotes.get("NoSuchRemote")
		end).toThrow("Unknown remote")
	end)
end)
