-- Ambient: NPC duels at tables nobody is using, so the hall never looks empty.
-- A real match always takes priority: Lobby calls Ambient.Stop(table) before using it.
local Players = game:GetService("Players")
local Arena = require(script.Parent.Arena)
local Dictionary = require(script.Parent.Dictionary)
local NPC = require(script.Parent.NPC)

local Ambient = {}
local running = {} -- [table] = { rigs = {}, alive = true }

function Ambient.Stop(tbl)
	local run = running[tbl]
	if not run then
		return
	end
	running[tbl] = nil
	run.alive = false
	for _, rig in ipairs(run.rigs) do
		rig:Destroy()
	end
	Arena.ClearSeats(tbl)
	Arena.SetTimer(tbl, nil)
	Arena.SetClock(tbl, 0)
	Arena.SetDisplay(tbl, nil, nil)
end

function Ambient.IsRunning(tbl)
	return running[tbl] ~= nil
end

function Ambient.Start(tbl)
	if running[tbl] or tbl.busy then
		return
	end
	-- Real player safety check: never spawn NPCs if a player is at or assigned to this table
	for side = 1, 2 do
		if tbl.assigned and tbl.assigned[side] then
			local a = tbl.assigned[side]
			if typeof(a) == "Instance" and a:IsA("Player") then
				return
			end
		end
		local seat = tbl.seats and tbl.seats[side]
		if seat and seat.Occupant then
			local plr = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
			if plr then
				return
			end
		end
	end
	local run = { rigs = {}, alive = true }
	running[tbl] = run
	task.spawn(function()
		local names = { NPC.RandomName(), NPC.RandomName() }
		for side = 1, 2 do
			local rig = NPC.Build(names[side])
			if not run.alive then
				if rig then
					rig:Destroy()
				end
				return
			end
			if rig then
				table.insert(run.rigs, rig)
				Arena.SeatRig(tbl, side, rig)
			end
		end
		while run.alive do
			-- one ambient "game": a short rally on a fresh word
			local word = Dictionary.StartWord(math.random(3, 5))
			local used = { [word] = true }
			local side = math.random(2)
			Arena.SetDisplay(tbl, word, names[1] .. "  vs  " .. names[2])
			local rally = math.random(6, 18)
			for _ = 1, rally do
				if not run.alive then
					return
				end
				local think = 1.5 + math.random() * 4
				Arena.SetClock(tbl, side)
				Arena.SetTimer(tbl, workspace:GetServerTimeNow() + think + math.random() * 5)
				task.wait(think)
				if not run.alive then
					return
				end
				local w = Dictionary.PickMove(word, 1, used, nil)
				if not w then
					break
				end
				used[w] = true
				word = w
				Arena.SetDisplay(tbl, word, names[1] .. "  vs  " .. names[2])
				side = 3 - side
			end
			Arena.SetTimer(tbl, nil)
			Arena.SetClock(tbl, 0)
			task.wait(3 + math.random() * 3)
		end
	end)
end

-- fill every free table, staggered so they don't all change in lockstep
function Ambient.FillAll()
	for i, tbl in ipairs(Arena.Tables) do
		task.delay(i * 0.7, function()
			if not tbl.busy then
				Ambient.Start(tbl)
			end
		end)
	end
end

return Ambient
