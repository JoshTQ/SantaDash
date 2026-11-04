--[[
	Helpers for the in-engine physics specs: a test pad far from everything,
	and a stand-in Santa (an R15-style Humanoid rig) the server simulates.

	Open Cloud runs a server with no clients, so real Players can't join;
	these rigs get the same physics a Santa gets, owned by the server.
]]

local Rig = {}

local PAD_HEIGHT = 2000 -- well above any map and route

local nextPad = 0

-- An anchored floor (material optional) in its own folder, away from the
-- other specs. Returns the folder and the floor's top-centre position.
function Rig.pad(size: Vector3?, material: Enum.Material?): (Folder, Vector3)
	nextPad += 1
	local folder = Instance.new("Folder")
	folder.Name = "EngineTestPad" .. nextPad
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = size or Vector3.new(200, 2, 200)
	floor.CFrame = CFrame.new(nextPad * 400, PAD_HEIGHT, 0)
	floor.Material = material or Enum.Material.Snow
	floor.Parent = folder
	folder.Parent = workspace
	return folder, floor.CFrame.Position + Vector3.new(0, floor.Size.Y / 2, 0)
end

-- A Humanoid rig standing on whatever is under `at` (its feet at `at`).
-- R15-style: a 2x2x1 root with HipHeight 2, like a default Santa.
export type Body = { model: Model, humanoid: Humanoid, root: BasePart }

function Rig.santa(parent: Instance, at: Vector3): Body
	local model = Instance.new("Model")
	model.Name = "TestSanta"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(at + Vector3.new(0, 3, 0))
	root.Parent = model
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = root.CFrame
	torso.CanCollide = false
	torso.Massless = true
	torso.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = torso
	weld.Parent = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return { model = model, humanoid = humanoid, root = root }
end

-- Something shaped like a Player for code that only reads Character,
-- DisplayName, Name and CharacterAdded (Run's seat and ride code).
function Rig.player(body: Body, name: string?): any
	local added = Instance.new("BindableEvent")
	return {
		Name = name or "TestSanta",
		DisplayName = name or "TestSanta",
		UserId = 0,
		Character = body.model,
		CharacterAdded = added.Event,
		Parent = nil, -- not in Players: Run sends it no remotes
	}
end

-- Waits until check() or `seconds` pass; returns check()'s last value.
function Rig.waitFor(check: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.05)
	end
	return check()
end

-- Lets a body land and come to rest on its floor.
function Rig.settle(body: Body)
	Rig.waitFor(function()
		return body.humanoid.FloorMaterial ~= Enum.Material.Air
			and body.root.AssemblyLinearVelocity.Magnitude < 0.5
	end, 4)
end

function Rig.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

return Rig
