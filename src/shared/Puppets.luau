--[[
	Scripted motion that the server and every client compute the same way.

	The server moves the sleigh (every flight and the Getaway) and Krampus
	(his KrampusArrives intro and his Getaway belly-flop) along fixed paths. A
	server PivotTo only reaches clients at the network rate, so a cutscene
	camera that follows those models judders, and the sleigh and its riders
	step instead of glide. Instead, the server sends each path once (a "Puppets"
	Hud message) and every client poses the same models itself each frame
	(client/PuppetPlayer), from the same pure functions the server uses here.
	The server still moves everything, so gameplay never depends on a client.

	A puppet is plain data:
		target   the Model (PivotTo) or BasePart (CFrame) to pose
		path     "flight" | "getawaySleigh" | "krampusIntro" | "krampusFlop"
		base     the path's origin (flight: from deck; getaway: landed deck;
		         intro: Krampus's spawn; flop: where he was standing)
		to       flight only: the deck it lands on
		peak     flight only: the arc height
		deck     flop only: the deck position he leaps for
		offset   optional, applied after the path (a rider's seat on the deck)
		seconds  how long the path runs; it holds its end pose after that
]]

local Cutscenes = require(script.Parent.Cutscenes)
local SleighFlight = require(script.Parent.SleighFlight)

local Puppets = {}

export type Path = "flight" | "getawaySleigh" | "krampusIntro" | "krampusFlop"
export type Puppet = {
	target: Instance?,
	path: Path,
	base: CFrame,
	to: CFrame?,
	peak: number?,
	deck: Vector3?,
	offset: CFrame?,
	seconds: number,
}

Puppets.Paths = { "flight", "getawaySleigh", "krampusIntro", "krampusFlop" }

-- Where the path puts its target at time t (clamped to [0, seconds]).
function Puppets.poseAt(puppet: Puppet, t: number): CFrame
	t = math.clamp(t, 0, puppet.seconds)
	local path = puppet.path
	local pose
	if path == "flight" then
		pose = SleighFlight.deckAt(puppet.base, puppet.to :: CFrame, t, puppet.seconds, puppet.peak or 0)
	elseif path == "getawaySleigh" then
		pose = puppet.base * Cutscenes.getawaySleigh(t)
	elseif path == "krampusIntro" then
		pose = puppet.base * Cutscenes.krampusIntro(t)
	elseif path == "krampusFlop" then
		pose = Cutscenes.krampusFlop(t, puppet.base, puppet.deck :: Vector3)
	else
		error("unknown puppet path " .. tostring(path))
	end
	return if puppet.offset then pose * puppet.offset else pose
end

-- Why a puppet can't be played, or nil when it is fine. Clients drop bad ones
-- instead of erroring every frame.
function Puppets.problem(puppet: Puppet): string?
	if typeof(puppet) ~= "table" then
		return "not a table"
	end
	if not table.find(Puppets.Paths, puppet.path) then
		return "unknown path " .. tostring(puppet.path)
	end
	if typeof(puppet.base) ~= "CFrame" then
		return puppet.path .. " has no base CFrame"
	end
	if type(puppet.seconds) ~= "number" or puppet.seconds <= 0 or puppet.seconds ~= puppet.seconds then
		return puppet.path .. " has no length"
	end
	if puppet.path == "flight" and typeof(puppet.to) ~= "CFrame" then
		return "flight has nowhere to land"
	end
	if puppet.path == "krampusFlop" and typeof(puppet.deck) ~= "Vector3" then
		return "krampusFlop has no deck to leap for"
	end
	if puppet.offset ~= nil and typeof(puppet.offset) ~= "CFrame" then
		return puppet.path .. " offset is not a CFrame"
	end
	return nil
end

-- Has the path reached its end pose?
function Puppets.done(puppet: Puppet, t: number): boolean
	return t >= puppet.seconds
end

return Puppets
