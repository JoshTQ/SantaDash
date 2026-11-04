--[[
	Approved models live in ServerStorage.Assets (imported from Meshy). Each
	system asks for its model by name and falls back to its greybox stand-in
	when it isn't there yet. Names and required parts:

	Krampus   Humanoid, HumanoidRootPart, part "Basket"
	ElfA/ElfD Humanoid, HumanoidRootPart
	Sleigh    PrimaryPart "Body", Seat1-Seat6, "Horn", "Lantern", "Hitch"
	Reindeer  PrimaryPart "Body", Head, LegFL/LegFR/LegBL/LegBR on Motor6Ds
	          (two per sleigh, placed in front of the sleigh's Hitch)
	House, KrampusLair, VaultDoor  see HouseKit.luau
	CocoaMachine  PrimaryPart "Body", "BuyPrompt" Attachment (+ Sign, TopMug,
	          Dispenser, PricePlate); placed standing on the street
	SnowPile  Blizzard pile (Sparkle Drift): PrimaryPart "Drift", Ball1-Ball5
	          (hidden per grab, regrow), "Glow" (pulses), "Sparkles" Attachment,
	          ProximityPrompt; 6x3x6 studs, pivot at its centre
	Snowball  about 1.2 studs, PrimaryPart + Trail; thrown during a Blizzard
	SnowSplat decal Model left where a snowball lands, fades out
	The Sleigh's Seats are disabled: Run carries riders at each Seat's spot.

	Map set dressing lives in ServerStorage.Maps.<dressing> (see shared/Maps):
	a Model with StopDressing and/or RouteDressing children.
]]

local ServerStorage = game:GetService("ServerStorage")

local Assets = {}

function Assets.get(name: string): Model?
	local folder = ServerStorage:FindFirstChild("Assets")
	local model = folder and folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function Assets.folder(): Folder?
	return ServerStorage:FindFirstChild("Assets") :: Folder?
end

function Assets.mapDressing(name: string?): Model?
	local folder = name and ServerStorage:FindFirstChild("Maps")
	local model = folder and folder:FindFirstChild(name :: string)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- A clone of the named model if it has every listed descendant, else nil (with a warning).
function Assets.clone(name: string, required: { string }): Model?
	local template = Assets.get(name)
	if not template then
		return nil
	end
	for _, partName in required do
		if not template:FindFirstChild(partName, true) then
			warn(("[Assets] %s is missing %q; using the greybox stand-in"):format(name, partName))
			return nil
		end
	end
	return template:Clone()
end

return Assets
