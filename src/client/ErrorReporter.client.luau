--[[
	Tells the server when one of this player's scripts errors, so client
	crashes show up in the analytics (server/Telemetry.luau). Each distinct
	error is sent once, and at most MAX_REPORTS a session.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MAX_REPORTS = 20

local remote = Remotes.get("ClientError")
local seen: { [string]: boolean } = {}
local sent = 0

ScriptContext.Error:Connect(function(message: string)
	local text = string.sub(tostring(message), 1, 300)
	if sent >= MAX_REPORTS or seen[text] then
		return
	end
	seen[text] = true
	sent += 1
	remote:FireServer(text)
end)
