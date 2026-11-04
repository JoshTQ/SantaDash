--[[
	Soak test: whole runs with crews that do random things, checked against
	rules that must always hold. It finds crashes, stuck runs and leaks that
	scripted tests miss.

	Each run uses its own seed (the world's math.random and the players'
	choices), so a failure names the seed that reproduces it:
	  SOAK_SEED=17 lune run tests/runner Soak
	SOAK_RUNS=200 runs more seeds (default 12).
]]

local process = require("@lune/process")

local RUNS = tonumber(process.env.SOAK_RUNS) or 12
local ONLY = tonumber(process.env.SOAK_SEED)

local INPUTS = { "Tap", "Tap", "Tap", "Unhide", "Throw", "Jump", "", "Tap" }

local function fastRuns(Config)
	Config.Run.StopSeconds = 40
	Config.Run.LightsOnAt = 10
	Config.Run.HornAt = 25
	Config.Run.ResultsSeconds = 2
end

-- Every ProximityPrompt in the route that is enabled right now.
local function prompts(run)
	local out = {}
	for _, d in run.route.model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Enabled then
			table.insert(out, d)
		end
	end
	return out
end

local function promptPosition(prompt): Vector3?
	local node = prompt.Parent
	while node do
		if node:IsA("BasePart") then
			return node.Position
		elseif node:IsA("Attachment") then
			return node.WorldPosition
		elseif node:IsA("Model") then
			return node:GetPivot().Position
		end
		node = node.Parent
	end
	return nil
end

local function soak(seed: number)
	local rng = Random.new(seed)
	local world = headless({ seed = seed })
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	fastRuns(Config)
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local Players = engine.Players

	local crew = {}
	for i = 1, rng:NextInteger(1, Config.Lobby.CrewMax) do
		crew[i] = engine:addPlayer("S" .. i)
	end
	local log = {} -- what the players did, for the failure message
	local problems = {}
	local function problem(text: string)
		if #problems < 10 then
			table.insert(problems, string.format("t=%.1f %s", engine.now, text))
		end
	end

	local finished, survivors = false, nil
	local run
	world.run(function()
		run = Run.new(1, crew, function(_, list)
			finished = true
			survivors = list
		end)
		run:start()

		while not finished do
			world.wait(0.5)
			if finished then
				break
			end
			for _, player in table.clone(crew) do
				if player.Parent ~= Players or not run.players[player] then
					continue
				end
				local roll = rng:NextNumber()
				if roll < 0.3 then
					local list = prompts(run)
					local prompt = list[rng:NextInteger(1, math.max(#list, 1))]
					local at = prompt and promptPosition(prompt)
					if at then
						table.insert(log, player.Name .. " uses " .. prompt.Parent.Name)
						engine:teleport(player, at + Vector3.new(0, 3, 0))
						prompt.Triggered:Fire(player)
					end
				elseif roll < 0.34 then
					table.insert(log, player.Name .. " boards")
					engine:teleport(player, (run.deck * CFrame.new(0, 3, 0)).Position)
				elseif roll < 0.5 then
					run:onInput(player, INPUTS[rng:NextInteger(1, #INPUTS)])
				elseif roll < 0.52 then
					table.insert(log, player.Name .. " respawns")
					player:LoadCharacter()
				elseif roll < 0.523 and #crew > 1 then
					table.insert(log, player.Name .. " leaves the game")
					run:removePlayer(player)
					engine:removePlayer(player)
				end
			end

			-- Rules that hold at every moment.
			for player, st in run.players do
				if st.captive and st.hidden then
					problem(player.Name .. " is snatched and hidden at once")
				end
				if st.sackCount > Config.Sack.Capacity then
					problem(player.Name .. " has " .. st.sackCount .. " presents in the sack")
				end
				if st.jingle < 0 then
					problem(player.Name .. " has negative Jingle " .. st.jingle)
				end
				if st.hidden and st.hidden.occupant ~= player then
					problem(player.Name .. " is hidden in a wardrobe that lists someone else")
				end
			end
			if engine.now > 1500 then
				problem("the run never finished")
				break
			end
		end
	end, { maxSeconds = 1800, allowErrors = true })

	for _, err in engine.errors do
		problem("game thread error: " .. string.sub(err, 1, 300))
	end
	for _, w in engine.warnings do
		problem("warning: " .. string.sub(w, 1, 200))
	end
	if finished then
		for _, player in survivors do
			if player.Parent ~= Players then
				problem(player.Name .. " left the game but is listed as a survivor")
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Anchored then
				problem(player.Name .. " is still anchored after the run")
			end
			local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.WalkSpeed ~= Config.Player.WalkSpeed then
				problem(player.Name .. " still has WalkSpeed " .. humanoid.WalkSpeed .. " after the run")
			end
		end
		if run.route.model.Parent ~= nil then
			problem("the route model was not destroyed")
		end
		if run.krampus then
			problem("Krampus is still around after the run")
		end
		if #run.elves > 0 then
			problem(#run.elves .. " elf bots are still around after the run")
		end
		-- Nothing from the run left in the workspace except characters.
		for _, child in engine.workspace:GetChildren() do
			local isCharacter = Players:GetPlayerFromCharacter(child) ~= nil
			if not isCharacter and child.Name ~= "Camera" then
				problem("left in the workspace after the run: " .. child.Name)
			end
		end
	else
		problem("onFinished was never called")
	end

	if process.env.SOAK_DEBUG then
		print(seed, "now", engine.now, "stop", run.stopIndex, "actions", #log, "finished", finished)
	end
	if #problems > 0 then
		local recent = {}
		for i = math.max(1, #log - 8), #log do
			table.insert(recent, log[i])
		end
		error(
			string.format(
				"seed %d (%d Santas): %s\n      last actions: %s",
				seed,
				#crew,
				table.concat(problems, "\n      "),
				table.concat(recent, "; ")
			),
			0
		)
	end
end

describe("soak: random crews doing random things", function()
	for seed = 1, if ONLY then 1 else RUNS do
		local s = ONLY or seed
		it("seed " .. s, function()
			soak(s)
		end)
	end
end)
