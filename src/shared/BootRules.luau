--[[
	Boots: who owns and wears which, buying with Coal, and how fast a pair
	makes you on ice. Pure (saved-data tables in, answers out), so the
	server (server/Boots.luau) and the tests share it.

	Owning boots is data.owned[id] = true (the same table suits and passes
	use); the pair being worn is data.boots ("" for none).
]]

local Config = require(script.Parent.Config)

local BootRules = {}

export type Boot = {
	id: string,
	name: string,
	model: string,
	coal: number?,
	skateSpeed: number?,
	hoopSpeed: number?,
	blurb: string?,
	trail: Color3?,
	style: boolean?,
	base: string?,
	ready: boolean?,
}

function BootRules.get(id: any): Boot?
	if type(id) ~= "string" then
		return nil
	end
	for _, boot in Config.Boots.List do
		if boot.id == id then
			return boot :: any
		end
	end
	return nil
end

-- On sale and wearable: its model is approved and imported.
function BootRules.ready(boot: Boot?): boolean
	return boot ~= nil and boot.ready ~= false
end

function BootRules.owns(data: { [string]: any }?, id: string): boolean
	return data ~= nil and data.owned ~= nil and data.owned[id] == true
end

-- Buys boots with Coal. Returns ok, or false and why: "unknown", "notReady",
-- "owned", "notForCoal" (a Robux style) or "coal" (not enough).
function BootRules.buy(data: { [string]: any }, id: any): (boolean, string?)
	local boot = BootRules.get(id)
	if not boot then
		return false, "unknown"
	elseif not BootRules.ready(boot) then
		return false, "notReady"
	elseif BootRules.owns(data, boot.id) then
		return false, "owned"
	elseif boot.style or not boot.coal then
		return false, "notForCoal"
	elseif (data.coal or 0) < boot.coal then
		return false, "coal"
	end
	data.coal -= boot.coal
	data.owned[boot.id] = true
	if data.boots == nil or data.boots == "" then
		data.boots = boot.id -- put on your first pair straight away
	end
	return true, nil
end

-- Puts on owned boots, or takes them off with "" / nil.
function BootRules.equip(data: { [string]: any }, id: any): (boolean, string?)
	if id == nil or id == "" then
		data.boots = ""
		return true, nil
	end
	local boot = BootRules.get(id)
	if not boot then
		return false, "unknown"
	elseif not BootRules.owns(data, boot.id) then
		return false, "locked"
	end
	data.boots = boot.id
	return true, nil
end

-- The boots worn, or nil (none, refunded, unknown or not imported yet).
function BootRules.current(data: { [string]: any }?): Boot?
	local id = data and data.boots
	local boot = BootRules.get(id)
	if not boot or not BootRules.owns(data, boot.id) or not BootRules.ready(boot) then
		return nil
	end
	return boot
end

-- The pair whose stats count: a style rides on its base boots, and gives
-- nothing unless you own them too (styles are cosmetic only).
function BootRules.statsOf(data: { [string]: any }?, boot: Boot?): Boot?
	if not boot then
		return nil
	end
	if boot.style then
		local base = BootRules.get(boot.base)
		if base and BootRules.owns(data, base.id) then
			return base
		end
		return nil
	end
	return boot
end

-- WalkSpeed on ice and after a hoop for the boots worn (nil = Config.Canal's).
function BootRules.speeds(data: { [string]: any }?): (number?, number?)
	local stats = BootRules.statsOf(data, BootRules.current(data))
	if not stats then
		return nil, nil
	end
	return stats.skateSpeed, stats.hoopSpeed
end

-- Shop rows: every ready pair, with owned / wearing / price.
function BootRules.list(data: { [string]: any }?): { any }
	local rows = {}
	local worn = BootRules.current(data)
	for _, boot in Config.Boots.List do
		if BootRules.ready(boot :: any) then
			table.insert(rows, {
				id = boot.id,
				name = boot.name,
				blurb = boot.blurb,
				coal = if boot.style then nil else boot.coal,
				owned = BootRules.owns(data, boot.id),
				wearing = worn ~= nil and worn.id == boot.id,
				canAfford = data ~= nil and boot.coal ~= nil and (data.coal or 0) >= boot.coal,
			})
		end
	end
	return rows
end

return BootRules
