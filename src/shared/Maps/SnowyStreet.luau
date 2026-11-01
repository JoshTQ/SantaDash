-- The original greybox street. Leaves every layout number at its Config
-- default, so it doubles as the reference for what a map can override.
return {
	id = "SnowyStreet",
	name = "Snowy Street",
	palette = {}, -- Ground / Road / Path = { Color3, Enum.Material }
	layout = {}, -- Slots, SideOffset, RoadWidth, StreetStart, StreetOverrun, StopSpacing, FootPathZ, CocoaMachine
	features = {}, -- { kind = "<MapFeatures key>", ... }, built at every stop
	dressing = nil, -- name of an approved Model in ServerStorage.Maps
}
