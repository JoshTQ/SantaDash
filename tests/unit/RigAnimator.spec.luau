-- Stand-ins and unrigged models have no Animations: the animator is a no-op.
local RigAnimator = load("ServerScriptService.Server.RigAnimator")

describe("RigAnimator", function()
	it("is a safe no-op on a model without animations", function()
		local model = Instance.new("Model")
		Instance.new("Humanoid").Parent = model
		local anim = RigAnimator.new(model)
		expect(anim:has("Idle")).toBe(false)
		anim:play("Idle")
		anim:oneShot("Snatch", 2)
		anim:play(nil)
		anim:stopAll()
		expect(anim.current).toBeNil()
	end)
end)
