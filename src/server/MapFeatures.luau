--[[
	Map features: map-specific pieces for every stop of a map (see
	shared/Maps). A map lists them as { kind = "<key>", ...args }.

	Each entry is { build = fn(BuildContext)?, start = fn(StartContext)? }.

	build: adds Instances under ctx.model while the route is built, in stop
	space (ctx.origin; +Z runs down the street from the landing house, houses
	sit at x = +/- SideOffset). It must not connect events, so the Lune
	integration tests can build every map.

	start: runtime behaviour (e.g. skating on Ice zones). Run calls it when the
	stop begins and calls the function it returns (if any) when the sleigh
	leaves that stop or the run ends. Disconnect everything there.
]]

export type BuildContext = {
	model: Model,
	origin: CFrame,
	feature: { [string]: any },
	rng: Random,
	stop: any, -- MapBuilder.Stop
	newPart: (...any) -> BasePart,
	map: any, -- Maps.Map: the whole definition (layout, features)
	landing: CFrame, -- this stop's Sleigh Stop, in stop space
}

export type StartContext = {
	run: any, -- Run: players, phase, _banner, _send ...
	stop: any, -- MapBuilder.Stop (its Instances are under the route model)
	feature: { [string]: any },
}

export type Feature = {
	build: ((ctx: BuildContext) -> ())?,
	start: ((ctx: StartContext) -> (() -> ())?)?,
}

-- Frozen Canal Town: CanalStreet, SkateCanal, ChristmasMarket, IceRink, FloeLake.
local MapFeatures: { [string]: Feature } = table.clone(require(script.Parent.CanalTown).features)

return MapFeatures
