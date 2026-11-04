--[[
	Anchored smooth plastic parts for the greybox builders (MapBuilder,
	LobbyMap). Event-free, so tests can build with it.
]]

local Parts = {}

function Parts.new(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	className: string?
): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Biggest dimension (studs) of a part that is too small to cast a shadow
-- anyone notices.
Parts.TinyShadow = 2

-- Render and physics clean-up for a finished build (Frozen Canal Town is
-- ~7,600 parts, a third of them light bulbs; phones feel every one):
-- - Non-colliding dressing can't be touched or ray-hit, so the physics
--   engine never tests it for contacts (a part tagged with the attribute
--   Trigger, like a boost hoop, keeps Touched).
-- - Neon and tiny parts don't cast shadows.
-- Returns how many parts it changed.
function Parts.settle(root: Instance): number
	local changed = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local touched = false
			if not d.CanCollide and not d:GetAttribute("Trigger") and (d.CanTouch or d.CanQuery) then
				d.CanTouch = false
				d.CanQuery = false
				touched = true
			end
			local size = d.Size
			if
				d.CastShadow
				and (d.Material == Enum.Material.Neon or math.max(size.X, size.Y, size.Z) <= Parts.TinyShadow)
			then
				d.CastShadow = false
				touched = true
			end
			if touched then
				changed += 1
			end
		end
	end
	return changed
end

return Parts
