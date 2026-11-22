-- DailyLadder: one shared solo puzzle per day. Turn START into TARGET by changing one
-- letter at a time; every step must be a real word. Par = the shortest possible chain.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WordRules = require(Shared.WordRules)

local Dictionary = require(script.Parent.Dictionary)
local PlayerData = require(script.Parent.PlayerData)

local DailyLadder = {}
DailyLadder.Send = nil -- function(player, action, payload)

local LEN = 4
local EPOCH_DAY = 20774 -- puzzle #1 = 2026-11-18 (UTC)

local function today()
	return math.floor(os.time() / 86400)
end

-- breadth-first distances from `from` over one-letter moves (whole dictionary)
local function distances(from)
	local dist = { [from] = 0 }
	local queue, head = { from }, 1
	while head <= #queue do
		local w = queue[head]
		head += 1
		for _, n in ipairs(Dictionary.Moves(w, 1, nil, nil)) do
			if dist[n] == nil then
				dist[n] = dist[w] + 1
				table.insert(queue, n)
			end
		end
	end
	return dist
end

local cache = {} -- [day] = puzzle

function DailyLadder.ForDay(day)
	if cache[day] then
		return cache[day]
	end
	local rng = Random.new(day * 7919 + 13)
	local list = Dictionary.StartList(LEN)
	local puzzle
	for _ = 1, 40 do
		local start = list[rng:NextInteger(1, #list)]
		if Dictionary.IsAllowed(start) then
			local dist = distances(start)
			local candidates = {}
			for _, w in ipairs(list) do
				local d = dist[w]
				if d and d >= Config.LadderMinPar and d <= Config.LadderMaxPar and Dictionary.IsAllowed(w) then
					table.insert(candidates, w)
				end
			end
			if #candidates > 0 then
				table.sort(candidates)
				local target = candidates[rng:NextInteger(1, #candidates)]
				puzzle = { day = day, number = day - EPOCH_DAY, start = start, target = target, par = dist[target] }
				break
			end
		end
	end
	puzzle = puzzle or { day = day, number = day - EPOCH_DAY, start = "cold", target = "warm", par = 4 }
	puzzle.toTarget = distances(puzzle.target) -- for hints
	cache[day] = puzzle
	return puzzle
end

function DailyLadder.Today()
	return DailyLadder.ForDay(today())
end

---------------------------------------------------------------- per-player session
local sessions = {} -- [player] = { day, chain = {...}, startedAt, solved, steps, time }

local function send(player, action, payload)
	if DailyLadder.Send then
		DailyLadder.Send(player, action, payload)
	end
end

local function session(player)
	local pz = DailyLadder.Today()
	local s = sessions[player]
	if not s or s.day ~= pz.day then
		local prof = PlayerData.Get(player)
		local done = prof and prof.ladderDay == pz.day
		s = {
			day = pz.day,
			chain = { pz.start },
			startedAt = os.clock(),
			solved = done,
			steps = done and prof.ladderSteps or nil,
		}
		sessions[player] = s
	end
	return s, pz
end

local function state(player, extra)
	local s, pz = session(player)
	local prof = PlayerData.Get(player)
	local out = {
		number = pz.number,
		start = pz.start,
		target = pz.target,
		par = pz.par,
		chain = s.chain,
		solved = s.solved,
		steps = s.steps,
		elapsed = math.floor(os.clock() - s.startedAt),
		streak = prof and prof.ladderStreak or 0,
		helps = prof and (prof.inventory.Help or 0) or 0,
	}
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

function DailyLadder.Open(player)
	send(player, "Ladder", state(player))
end

-- returns nil on success, or a reason string
function DailyLadder.Move(player, raw)
	local s, pz = session(player)
	if s.solved and #s.chain == 1 then
		-- already solved today: replaying is allowed for fun, no rewards
		s.replay = true
	end
	local cur = s.chain[#s.chain]
	local w = WordRules.Normalize(raw)
	local reason
	if not w or #w ~= LEN then
		reason = "Type a " .. LEN .. "-letter word."
	elseif w == cur then
		reason = "Change one letter."
	elseif (WordRules.Diff(cur, w)) ~= 1 then
		reason = "Change exactly ONE letter."
	elseif table.find(s.chain, w) then
		reason = string.upper(w) .. " is already in your ladder."
	elseif not Dictionary.IsWord(w) then
		reason = string.upper(w) .. " is not in the dictionary."
	elseif not Dictionary.IsAllowed(w, player.UserId) then
		reason = "That word is not allowed."
	end
	if reason then
		send(player, "Ladder", state(player, { invalid = reason }))
		return reason
	end
	table.insert(s.chain, w)
	if w == pz.target then
		local steps = #s.chain - 1
		local secs = math.floor(os.clock() - s.startedAt)
		local reward
		local prof = PlayerData.Get(player)
		if prof and prof.ladderDay ~= pz.day and not s.replay then
			prof.ladderStreak = (prof.ladderDay == pz.day - 1) and (prof.ladderStreak + 1) or 1
			prof.ladderDay = pz.day
			prof.ladderSteps = steps
			prof.ladderSolves += 1
			local coins = Config.LadderReward.coins + (steps <= pz.par and Config.LadderReward.parBonus or 0) + Config.LadderReward.perStreak * math.min(prof.ladderStreak, 10)
			prof.coins += coins
			PlayerData.AddXP(player, Config.LadderReward.xp)
			PlayerData.CheckAchievements(player)
			PlayerData.Changed(player)
			reward = { coins = coins, xp = Config.LadderReward.xp }
		end
		s.solved = true
		s.steps = steps
		send(player, "Ladder", state(player, { justSolved = true, time = secs, reward = reward }))
		return nil
	end
	send(player, "Ladder", state(player))
	return nil
end

function DailyLadder.Undo(player)
	local s = session(player)
	if #s.chain > 1 and not (s.solved and s.chain[#s.chain] == DailyLadder.Today().target) then
		table.remove(s.chain)
	end
	send(player, "Ladder", state(player))
end

function DailyLadder.Restart(player)
	local s, pz = session(player)
	s.chain = { pz.start }
	s.startedAt = os.clock()
	if s.solved then
		s.replay = true
	end
	send(player, "Ladder", state(player))
end

-- spend one Help: reveal the next word on a shortest path from where you are
function DailyLadder.Hint(player)
	local s, pz = session(player)
	local prof = PlayerData.Get(player)
	local cur = s.chain[#s.chain]
	if cur == pz.target then
		return "solved"
	end
	if not prof or (prof.inventory.Help or 0) < 1 then
		send(player, "Ladder", state(player, { invalid = "You need a Hint power-up (Shop)." }))
		return "no help"
	end
	local d = pz.toTarget[cur]
	local best
	if d then
		for _, n in ipairs(Dictionary.Moves(cur, 1, nil, nil)) do
			-- a neighbour one step closer = on a shortest path; prefer everyday words
			if pz.toTarget[n] == d - 1 and not table.find(s.chain, n) and Dictionary.IsAllowed(n) then
				if not best or (Dictionary.IsCommon(n) and not Dictionary.IsCommon(best)) then
					best = n
				end
			end
		end
	end
	if not best then
		send(player, "Ladder", state(player, { invalid = "You've wandered off - press UNDO a few times and try again." }))
		return "no path"
	end
	prof.inventory.Help -= 1
	PlayerData.Changed(player)
	send(player, "Ladder", state(player, { hint = best }))
	return best
end

function DailyLadder.PlayerLeft(player)
	sessions[player] = nil
end

return DailyLadder
