--[[
	Stop gate rules (Josh, 13 Nov 2026: "You can just run to the next stop,
	and steal everything before they spawn in").
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Maps = load("ReplicatedStorage.Shared.Maps")
local StopGate = load("ServerScriptService.Server.StopGate")
local G = Config.StopGate

test("only the stop the sleigh is parked at is live", function()
	expect(StopGate.stopLive(1, 1, "Sneak")).toBe(true)
	expect(StopGate.stopLive(1, 1, "LightsOn")).toBe(true)
	expect(StopGate.stopLive(1, 1, "Horn")).toBe(true)
	expect(StopGate.stopLive(2, 1, "Sneak")).toBe(false) -- running ahead
	expect(StopGate.stopLive(3, 1, "Horn")).toBe(false) -- the Lair from Stop 1
	expect(StopGate.stopLive(1, 2, "Sneak")).toBe(false) -- the sleigh has left
	expect(StopGate.stopLive(1, 0, "Takeoff")).toBe(false)
	expect(StopGate.stopLive(1, 1, "Flight")).toBe(false) -- flying away
	expect(StopGate.stopLive(3, 3, "Results")).toBe(false)
end)

test("an on-foot gap opens when the sleigh reaches its first stop and stays open", function()
	expect(StopGate.gapLive(1, 0)).toBe(false) -- take-off
	expect(StopGate.gapLive(1, 1)).toBe(true)
	expect(StopGate.gapLive(2, 1)).toBe(false) -- the path past Stop 2
	expect(StopGate.gapLive(1, 2)).toBe(true) -- Santas who missed the sleigh
	expect(StopGate.gapLive(2, 2)).toBe(true)
end)

test("presents follow their stop or gap; untagged regrabs need the sleigh parked", function()
	expect(StopGate.presentLive({ stopIndex = 3 }, 1, "Sneak")).toBe(false)
	expect(StopGate.presentLive({ stopIndex = 1 }, 1, "Sneak")).toBe(true)
	expect(StopGate.presentLive({ footGap = 2 }, 1, "Sneak")).toBe(false)
	expect(StopGate.presentLive({ footGap = 1 }, 1, "Flight")).toBe(true)
	expect(StopGate.presentLive({}, 2, "Horn")).toBe(true)
	expect(StopGate.presentLive({}, 2, "Flight")).toBe(false)
end)

test("Enabled = false turns every lock off", function()
	G.Enabled = false
	expect(StopGate.stopLive(3, 1, "Sneak")).toBe(true)
	expect(StopGate.gapLive(2, 0)).toBe(true)
	expect(StopGate.warded(3, 1, "Sneak")).toBe(false)
	G.Enabled = true
end)

test("only streets the sleigh hasn't reached are warded, and only while it's parked", function()
	expect(StopGate.warded(2, 1, "Sneak")).toBe(true)
	expect(StopGate.warded(3, 1, "Horn")).toBe(true)
	expect(StopGate.warded(1, 1, "Sneak")).toBe(false)
	expect(StopGate.warded(1, 2, "Sneak")).toBe(false) -- missed it: walk back is fine
	expect(StopGate.warded(2, 1, "Flight")).toBe(false) -- riders fly into Stop 2
	expect(StopGate.warded(1, 0, "Takeoff")).toBe(false)
end)

test("every map's ward covers its street, landing and Lair but not the path", function()
	for _, id in Maps.ids() do
		local map = Maps.get(id)
		local layout = map.layout
		local footZ = layout.FootPathZ
		for i = 1, #Config.Run.StopKinds do
			local origin = Maps.stopOrigin(layout, i)
			local landing = (layout.LandingAt and layout.LandingAt[i]) or Config.Map.LandingAt
			expect(StopGate.depth(origin, footZ, (origin * landing).Position) ~= nil).toBe(true)
			local far = Config.Rings.Far.Distance
			expect(StopGate.depth(origin, footZ, (origin * CFrame.new(0, 0, far)).Position) ~= nil).toBe(true)
			local kind = Config.Run.StopKinds[i]
			local endAt = layout.EndHouseAt and layout.EndHouseAt[kind]
			if endAt then
				expect(StopGate.depth(origin, footZ, (origin * endAt).Position) ~= nil).toBe(true)
			end
			-- The path (and the Frozen Canal's 44-wide main canal) stays open.
			local halfPath = if id == "FrozenCanal" then Config.Canal.Width / 2 else 5
			for x = -300, 300, 50 do
				local edge = (origin * CFrame.new(x, 0, footZ + halfPath)).Position
				expect(StopGate.depth(origin, footZ, edge)).toBe(nil)
			end
			-- Neighbouring stops' wards never overlap, so the live street is never warded.
			local nextOrigin = Maps.stopOrigin(layout, i + 1)
			for _, x in { -G.HalfWidth, G.HalfWidth } do
				for z = 0, G.Length, 100 do
					local p = (origin * CFrame.new(x, 0, footZ + G.PathClearance + z)).Position
					expect(StopGate.depth(nextOrigin, footZ, p)).toBe(nil)
				end
			end
		end
	end
end)

test("the ward pushes out of its nearest edge, and the safe spot is on the path", function()
	local origin = CFrame.new(700, 0, 1600)
	-- Just up the street from the main canal: straight back to it.
	local v = StopGate.pushVelocity(origin, -40, Vector3.new(700, 0, 1600 + 20))
	expect(v.Z < 0).toBe(true)
	expect(math.abs(v.X) < 1e-6).toBe(true)
	expect(v.Y).toBe(Config.Knockback.Lift)
	-- Skating in along the back lane (z 600) from the stop before: back along
	-- the lane, never down the street.
	local lane = StopGate.pushVelocity(origin, -40, Vector3.new(700 - G.HalfWidth + 10, 0, 1600 + 600))
	expect(lane.X < 0).toBe(true)
	expect(math.abs(lane.Z) < 1e-6).toBe(true)
	expect(StopGate.depth(origin, -40, Vector3.new(700 - G.HalfWidth + 10, 0, 2200))).toBe(10)
	local spot = StopGate.safeSpot(origin, -40, Vector3.new(720, 0, 1900))
	expect(spot.X).toBe(720)
	expect(spot.Z).toBe(1560)
	expect(StopGate.depth(origin, -40, spot)).toBe(nil)
end)

test("tag marks every stop's presents and splits on-foot presents by gap", function()
	local route = {
		stops = { { presents = { {}, {} } }, { presents = { {} } }, { presents = { {} } } },
		onFootPresents = { {}, {}, {}, {} },
	}
	StopGate.tag(route, { 2, 2 })
	expect(route.stops[1].presents[2].stopIndex).toBe(1)
	expect(route.stops[3].presents[1].stopIndex).toBe(3)
	expect(route.onFootPresents[2].footGap).toBe(1)
	expect(route.onFootPresents[3].footGap).toBe(2)
end)

test("locked banners say too early ahead, gone behind", function()
	expect(string.find(StopGate.lockedText(3, 1), "Too early", 1, true) ~= nil).toBe(true)
	expect(string.find(StopGate.lockedText(1, 2), "left this street", 1, true) ~= nil).toBe(true)
end)
