--[[
	Indoor camera (Josh, 11 Nov 2026: "the camera is janky" inside houses).
]]

local IndoorCamera = load("ReplicatedStorage.Shared.IndoorCamera")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

test("inside means a roof above and walls close on two or more sides", function()
	expect(IndoorCamera.inside(6, { 5, 9, nil, nil })).toBe(true)
	expect(IndoorCamera.inside(nil, { 5, 9, 4, 3 })).toBe(false) -- open sky
	expect(IndoorCamera.inside(6, { 5, nil, nil, nil })).toBe(false) -- under a market awning by one wall
	expect(IndoorCamera.inside(IndoorCamera.CeilingRange + 1, { 5, 5, 5, 5 })).toBe(false)
	expect(IndoorCamera.inside(6, { IndoorCamera.WallRange + 1, IndoorCamera.WallRange + 1, nil, nil })).toBe(
		false
	)
end)

test("the zoom limit settles in and out, so a doorway doesn't flicker it", function()
	local s = IndoorCamera.newState()
	expect(IndoorCamera.step(s, true, 0)).toBe(false)
	expect(IndoorCamera.step(s, true, IndoorCamera.EnterSeconds / 2)).toBe(false)
	expect(IndoorCamera.step(s, true, IndoorCamera.EnterSeconds)).toBe(true)
	-- A blink outside (stepping through the doorway) doesn't lift it.
	local t = IndoorCamera.EnterSeconds
	expect(IndoorCamera.step(s, false, t + 0.1)).toBe(true)
	expect(IndoorCamera.step(s, true, t + 0.2)).toBe(true)
	expect(IndoorCamera.step(s, false, t + 0.3)).toBe(true)
	expect(IndoorCamera.step(s, false, t + 0.3 + IndoorCamera.LeaveSeconds)).toBe(false)
end)

test("inside the camera stays over your shoulder; outside it's yours again", function()
	expect(IndoorCamera.maxZoom(true, 128)).toBe(IndoorCamera.MaxZoomInside)
	expect(IndoorCamera.maxZoom(false, 128)).toBe(128)
	expect(IndoorCamera.maxZoom(true, 8)).toBe(8)
	expect(IndoorCamera.MaxZoomInside >= 10 and IndoorCamera.MaxZoomInside <= 16).toBeTruthy()
end)

test("walls between the camera and your Santa fade out (Invisicam) in both places' project files", function()
	for _, path in { "default.project.json", "deploy.project.json" } do
		local project = serde.decode("json", fs.readFile(path))
		local props = project.tree.StarterPlayer["$properties"]
		expect(props ~= nil).toBeTruthy()
		expect(props.DevCameraOcclusionMode).toBe("Invisicam")
	end
end)
