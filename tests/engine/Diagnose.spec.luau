-- TEMPORARY probe: what the Open Cloud test server simulates.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local it, expect = JestGlobals.it, JestGlobals.expect

it("probe", function()
	local facts = {}
	local function note(k, v)
		table.insert(facts, k .. "=" .. tostring(v))
	end
	note("IsRunning", RunService:IsRunning())
	note("IsRunMode", RunService:IsRunMode())
	note("IsServer", RunService:IsServer())
	note("IsStudio", RunService:IsStudio())
	local ball = Instance.new("Part")
	ball.Size = Vector3.one
	ball.CFrame = CFrame.new(0, 3000, 0)
	ball.Parent = workspace
	local y0 = ball.Position.Y
	local t0 = os.clock()
	local beats = 0
	local c = RunService.Heartbeat:Connect(function()
		beats += 1
	end)
	local stepped = 0
	local c2 = RunService.Stepped:Connect(function()
		stepped += 1
	end)
	task.wait(1)
	c:Disconnect()
	c2:Disconnect()
	note("fell", y0 - ball.Position.Y)
	note("heartbeats", beats)
	note("stepped", stepped)
	note("elapsed", os.clock() - t0)
	note("gravity", workspace.Gravity)
	local ok, err = pcall(function()
		workspace:StepPhysics(1 / 60, { ball })
	end)
	note("StepPhysics", if ok then "ok" else err)
	note("afterStep", y0 - ball.Position.Y)
	local ok2, err2 = pcall(function()
		RunService:Run()
	end)
	note("Run", if ok2 then "ok" else err2)
	task.wait(0.5)
	note("fellAfterRun", y0 - ball.Position.Y)
	note("IsRunningAfter", RunService:IsRunning())
	ball:Destroy()
	expect(table.concat(facts, " | ")).toBe("")
end, 20000)
