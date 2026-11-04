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

return Parts
