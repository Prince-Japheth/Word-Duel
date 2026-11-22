-- Lobby: ranked queue (level brackets), bots, King of the Table, private friend tables,
-- and match results (Elo, XP, coins, streaks, leaderboards).
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local PlayerData = require(script.Parent.PlayerData)
local Arena = require(script.Parent.Arena)
local Match = require(script.Parent.Match)
local Leaderboards = require(script.Parent.Leaderboards)
local Ambient = require(script.Parent.Ambient)

local Lobby = {}
Lobby.Send = nil -- function(player, action, payload)

local queue = {} -- { {player=, since=, offered=bool} }
local kings = {} -- { {player=, table=, word=, since=} }
local privates = {} -- [code] = { host = player, since = }
local pendingChoice = {} -- [player] = { table=, word=, token= }

local function send(player, action, payload)
	if Lobby.Send and player and player.Parent then
		Lobby.Send(player, action, payload)
	end
end

local function removeFrom(list, player)
	for i = #list, 1, -1 do
		if list[i].player == player then
			if list[i].reservedTable then
				Arena.ClearSeats(list[i].reservedTable)
				releaseTable(list[i].reservedTable)
			end
			table.remove(list, i)
		end
	end
end

local function inQueue(player)
	for _, q in ipairs(queue) do
		if q.player == player then
			return true
		end
	end
	return false
end

local function levelOf(player)
	local p = PlayerData.Get(player)
	return p and p.level or 1
end

local function bracket(waitSeconds)
	return Config.BaseBracket + math.floor(waitSeconds / Config.BracketWidenEvery) * Config.BracketWiden
end

local function isKing(player)
	for _, k in ipairs(kings) do
		if k.player == player then
			return true
		end
	end
	return false
end

function Lobby.IsBusy(player)
	return Match.ByPlayer[player] ~= nil or pendingChoice[player] ~= nil or inQueue(player) or isKing(player)
end

local function releaseTable(tbl)
	tbl.busy = false
	Arena.ClearSeats(tbl)
	Arena.SetDisplay(tbl, nil, nil)
	Arena.SetClock(tbl, 0)
	Arena.SetTimer(tbl, nil)
	-- hand the table back to an ambient NPC duel after a short pause
	task.delay(4, function()
		if not tbl.busy then
			Ambient.Start(tbl)
		end
	end)
end

local function toLobby(player)
	Arena.Unseat(player)
	send(player, "LobbyReturn", {})
end

---------------------------------------------------------------- results
local function elo(a, b, aWon)
	local expected = 1 / (1 + 10 ^ ((b - a) / 400))
	local score = aWon and 1 or 0
	return math.floor(Config.EloK * (score - expected) + 0.5)
end

local onEnd -- forward declaration

local function startMatch(tbl, a, b, opts)
	Ambient.Stop(tbl)
	opts.onEnd = onEnd
	return Match.new(tbl, a, b, opts)
end

onEnd = function(match, winner, loser, reason)
	local tbl = match.table
	local ranked = match.ranked
	-- practice/tutorial opponents are labelled bots; matchmaking bots count like people
	local vsBot = (winner.kind == "bot" and not winner.disguised) or (loser.kind == "bot" and not loser.disguised)
	local results = {}

	if match.tutorial then
		local learner = winner.player and winner or loser
		local plr = learner.player
		local p = plr and PlayerData.Get(plr)
		local res = { won = winner == learner, reason = reason, word = match.word, words = learner.words, eloDelta = 0, xp = 0, coins = 0, tutorial = true }
		if p and winner == learner and not p.tutorialDone then
			p.tutorialDone = true
			res.coins = Config.TutorialReward.coins or 0
			res.xp = 20
			PlayerData.Grant(plr, Config.TutorialReward, true)
			PlayerData.AddXP(plr, res.xp, true)
			PlayerData.Changed(plr)
		end
		if plr then
			send(plr, "BoutEnd", res)
			task.delay(2.5, function()
				if plr.Parent and not Match.ByPlayer[plr] then
					toLobby(plr)
				end
				releaseTable(tbl)
			end)
		else
			releaseTable(tbl)
		end
		return
	end

	local delta = 0
	if ranked then
		delta = elo(winner.elo, loser.elo, true)
	end

	-- loser
	if loser.player then
		local p = PlayerData.Get(loser.player)
		local res = { won = false, reason = reason, word = match.word, words = loser.words, eloDelta = 0, xp = 0, coins = 0, score = loser.score, rivalScore = winner.score }
		if p then
			if ranked then
				-- Elo Protection: If player timed out but outscored the winner, Elo loss is cut in half!
				local protected = (loser.score or 0) > (winner.score or 0)
				local eloLost = delta
				if protected then
					eloLost = math.floor(delta * 0.5)
					res.eloProtected = true
				end
				p.elo = math.max(0, p.elo - eloLost)
				p.losses += 1
				res.eloDelta = -eloLost
			end
			p.matches += 1
			p.curStreak = 0
			p.totalScore = (p.totalScore or 0) + (res.score or 0)
			if reason ~= "left" then
				res.xp = vsBot and 5 or Config.Reward.LossXP
				res.coins = vsBot and 0 or Config.Reward.LossCoins
				local scoreCoins = math.min(Config.ScoreCoinCap, math.floor((res.score or 0) * Config.ScoreCoinRate))
				res.scoreCoins = scoreCoins
				res.coins += scoreCoins
				p.coins += res.coins
				PlayerData.AddXP(loser.player, res.xp, false)
			end
			PlayerData.CheckAchievements(loser.player)
			PlayerData.Changed(loser.player)
			PlayerData.CheckScoreRecord(loser.player, loser.score)
			Leaderboards.Submit(loser.player, p)
		end
		results[loser.player] = res
	end

	-- winner
	if winner.player then
		local p = PlayerData.Get(winner.player)
		local res = { won = true, reason = reason, word = match.word, words = winner.words, eloDelta = 0, xp = 0, coins = 0, score = winner.score, rivalScore = loser.score }
		if p then
			p.matches += 1
			p.totalScore = (p.totalScore or 0) + (res.score or 0)
			if ranked then
				p.elo += delta
				p.wins += 1
				p.curStreak += 1
				p.bestStreak = math.max(p.bestStreak, p.curStreak)
				res.eloDelta = delta
				res.xp = Config.Reward.WinXP + Config.Reward.WinStreakXP * math.min(p.curStreak - 1, 10)
				res.coins = Config.Reward.WinCoins
				local milestone = Config.StreakMilestones[p.curStreak]
				if milestone then
					PlayerData.Reward(winner.player, "streak", p.curStreak .. " WINS", "King of the Table streak bonus", milestone)
				end
			else
				res.xp = Config.Reward.BotWinXP
				res.coins = Config.Reward.BotWinCoins
			end
			res.streak = p.curStreak
			local scoreCoins = math.min(Config.ScoreCoinCap, math.floor((res.score or 0) * Config.ScoreCoinRate))
			res.scoreCoins = scoreCoins
			res.coins += scoreCoins
			p.coins += res.coins
			PlayerData.AddXP(winner.player, res.xp, true)
			PlayerData.CheckAchievements(winner.player)
			PlayerData.Changed(winner.player)
			PlayerData.CheckScoreRecord(winner.player, winner.score)
			Leaderboards.Submit(winner.player, p)

			-- Subway Surfers-style rare item drop on ranked victory!
			if ranked then
				local dropRoll = math.random()
				local dropChance = (winner.score and winner.score >= 30) and 0.07 or 0.04
				if dropRoll < dropChance then
					local dropPool = { "Time", "Time", "Time", "Time", "Help", "Help", "Help", "Skip", "Skip", "DoubleShift" }
					local droppedItem = dropPool[math.random(#dropPool)]
					local itemName = Config.Items[droppedItem].name
					res.luckyDrop = { item = droppedItem, name = itemName }
					PlayerData.Reward(winner.player, "bonus", "LUCKY DROP!", "+1 " .. itemName .. " found after the match!", { [droppedItem] = 1 })
				end
			end
		end
		res.canKing = ranked and not match.private and reason ~= "left_server"
		results[winner.player] = res
	end

	-- Award for biggest word in that entire match
	if match.biggestWord and match.biggestWordLen >= 6 and match.biggestWordPlayer then
		PlayerData.Reward(match.biggestWordPlayer, "award", "BIGGEST WORD", string.upper(match.biggestWord) .. " (" .. match.biggestWordLen .. " letters • Match Best)", { coins = 40 })
	end

	for plr, res in pairs(results) do
		send(plr, "BoutEnd", res)
	end

	-- loser leaves the table
	if loser.player then
		task.delay(2.5, function()
			if loser.player.Parent and not Match.ByPlayer[loser.player] then
				toLobby(loser.player)
			end
		end)
	end

	-- private, practice, or bot-won: table closes
	if not winner.player or match.private or not ranked then
		task.delay(2.5, function()
			if winner.player and winner.player.Parent then
				toLobby(winner.player)
			end
			releaseTable(tbl)
		end)
		return
	end

	-- winner chooses: Cash Out or King of the Table
	local token = {}
	pendingChoice[winner.player] = { table = tbl, word = match.word, token = token, finalClock = match.turnTime, side = winner.side or 1 }
	-- staying on as King is the default; the winner only acts to Cash Out
	task.delay(Config.ContinueChoiceSeconds, function()
		local pc = pendingChoice[winner.player]
		if pc and pc.token == token then
			Lobby.Choice(winner.player, "king")
		end
	end)
end

---------------------------------------------------------------- public API
function Lobby.Queue(player)
	if Lobby.IsBusy(player) then
		return
	end
	-- hosting a friend table and queueing at once could seat you in two matches
	if Lobby.HostCode(player) then
		Lobby.CancelPrivate(player)
	end
	local tbl = Arena.FreeTable()
	if tbl then
		Ambient.Stop(tbl)
		tbl.busy = true
		Arena.Seat(tbl, 1, player)
		Arena.SetDisplay(tbl, "", string.format("%s (Lv %d)  vs  FINDING OPPONENT...", player.Name, levelOf(player)))
	end
	local fill = Config.BotFillMin + math.random() * (Config.BotFillMax - Config.BotFillMin)
	table.insert(queue, { player = player, since = os.clock(), offered = false, fillAt = os.clock() + fill, reservedTable = tbl })
	send(player, "QueueState", { searching = true, bracket = Config.BaseBracket, seated = tbl ~= nil })
end

function Lobby.CancelQueue(player)
	removeFrom(queue, player)
	toLobby(player)
	send(player, "QueueState", { searching = false })
end

function Lobby.PlayBot(player)
	if Match.ByPlayer[player] or pendingChoice[player] then
		return
	end
	removeFrom(queue, player)
	local tbl = Arena.FreeTable()
	if not tbl then
		return send(player, "Toast", "All tables are busy. Try again in a moment.")
	end
	send(player, "QueueState", { searching = false })
	startMatch(tbl, Match.PlayerEntity(player), Match.BotEntity(levelOf(player)), { ranked = false })
end

local function eloOf(player)
	local p = PlayerData.Get(player)
	return p and p.elo or Config.StartElo
end

-- a human-like bot with a skill close to the player's
-- a human-like bot with a skill close to the player's; `finalClock` (the pace you just won
-- at) makes the next King challenger tougher the faster you were going
local function disguisedFor(player, finalClock)
	local pace = 0
	if finalClock then
		pace = math.max(0, Config.StartClockForLevel(levelOf(player)) - finalClock) * 30
	end
	local p = PlayerData.Get(player)
	return Match.BotEntity(levelOf(player), { disguised = true, elo = math.max(0, eloOf(player) + pace + math.random(-60, 60)), xp = p and p.xp or 0 })
end

-- first-time tutorial: a relaxed match against a coach on an easy word
function Lobby.StartTutorial(player)
	if Lobby.IsBusy(player) then
		return
	end
	removeFrom(queue, player)
	local tbl = Arena.FreeTable()
	if not tbl then
		return send(player, "Toast", "All tables are busy. Try again in a moment.")
	end
	local starts = { "cat", "hot", "pin", "map", "bed", "cup" }
	startMatch(tbl, Match.PlayerEntity(player), Match.BotEntity(1, { tutorial = true }), {
		ranked = false,
		tutorial = true,
		word = starts[math.random(#starts)],
	})
end

function Lobby.SkipTutorial(player)
	local p = PlayerData.Get(player)
	if p and not p.tutorialDone then
		p.tutorialDone = true
		PlayerData.Changed(player)
	end
end

function Lobby.Choice(player, choice)
	local pc = pendingChoice[player]
	if not pc then
		return
	end
	pendingChoice[player] = nil
	if choice == "king" and player.Parent then
		-- a challenger sits down right away: a waiting human in range first, otherwise a bot
		table.insert(kings, { player = player, table = pc.table, word = pc.word, since = os.clock(), fillAt = os.clock(), finalClock = pc.finalClock, side = pc.side or 1 })
		Arena.SetDisplay(pc.table, pc.word, player.DisplayName .. " is King of the Table")
		if Lobby._tick then
			task.spawn(Lobby._tick)
		end
	else
		-- cashing out ends your King run
		local p = PlayerData.Get(player)
		if p then
			p.curStreak = 0
			PlayerData.Changed(player)
		end
		releaseTable(pc.table)
		if player.Parent then
			toLobby(player)
		end
	end
end

function Lobby.LeaveTable(player)
	for i, k in ipairs(kings) do
		if k.player == player then
			table.remove(kings, i)
			local p = PlayerData.Get(player)
			if p then
				p.curStreak = 0
				PlayerData.Changed(player)
			end
			releaseTable(k.table)
			toLobby(player)
			return
		end
	end
	local pc = pendingChoice[player]
	if pc then
		pendingChoice[player] = nil
		local p = PlayerData.Get(player)
		if p then
			p.curStreak = 0
			PlayerData.Changed(player)
		end
		releaseTable(pc.table)
		toLobby(player)
		return
	end
	for _, tbl in ipairs(Arena.Tables) do
		if tbl.assigned[1] == player or tbl.assigned[2] == player then
			releaseTable(tbl)
			break
		end
	end
	toLobby(player)
end

local function orderKingSides(kingSide, kingEnt, challengerEnt)
	if kingSide == 2 then
		return challengerEnt, kingEnt
	end
	return kingEnt, challengerEnt
end

function Lobby.KingBot(player)
	for i, k in ipairs(kings) do
		if k.player == player then
			table.remove(kings, i)
			local a, b = orderKingSides(k.side, Match.PlayerEntity(player), Match.BotEntity(levelOf(player)))
			startMatch(k.table, a, b, {
				word = k.word,
				startClock = Config.KingStartClock(k.finalClock, levelOf(player)),
				firstTurn = (k.side == 2) and 1 or 2,
				ranked = false,
			})
			return
		end
	end
end

function Lobby.KingCashOut(player)
	for i, k in ipairs(kings) do
		if k.player == player then
			table.remove(kings, i)
			local p = PlayerData.Get(player)
			if p then
				p.curStreak = 0
				PlayerData.Changed(player)
			end
			releaseTable(k.table)
			toLobby(player)
			return
		end
	end
end

-- private friend tables -----------------------------------------------------------
local function newCode()
	local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	local s = ""
	for _ = 1, 5 do
		local i = math.random(#chars)
		s ..= chars:sub(i, i)
	end
	return s
end

function Lobby.CreatePrivate(player)
	if Lobby.IsBusy(player) then
		return
	end
	for code, pv in pairs(privates) do
		if pv.host == player then
			return send(player, "PrivateCode", { code = code })
		end
	end
	local code = newCode()
	while privates[code] do
		code = newCode()
	end
	privates[code] = { host = player, since = os.clock() }
	send(player, "PrivateCode", { code = code })
	return code
end

function Lobby.CancelPrivate(player)
	for code, pv in pairs(privates) do
		if pv.host == player then
			privates[code] = nil
		end
	end
	send(player, "PrivateCode", { code = nil })
end

function Lobby.HostCode(player)
	for code, pv in pairs(privates) do
		if pv.host == player then
			return code
		end
	end
	return nil
end

function Lobby.JoinPrivate(player, code)
	if type(code) ~= "string" then
		return
	end
	code = string.upper(code):gsub("%s", "")
	local pv = privates[code]
	if not pv or not pv.host.Parent then
		return send(player, "Toast", "No open table with code " .. code .. " in this server.")
	end
	if pv.host == player then
		return
	end
	if Lobby.IsBusy(player) or Lobby.IsBusy(pv.host) then
		return send(player, "Toast", "That player is busy right now.")
	end
	local tbl = Arena.FreeTable()
	if not tbl then
		return send(player, "Toast", "All tables are busy. Try again in a moment.")
	end
	privates[code] = nil
	send(pv.host, "PrivateCode", { code = nil })
	startMatch(tbl, Match.PlayerEntity(pv.host), Match.PlayerEntity(player), { private = true, ranked = false })
end

---------------------------------------------------------------- leaving
function Lobby.PlayerLeft(player)
	removeFrom(queue, player)
	local m = Match.ByPlayer[player]
	if m then
		m:forfeit(player)
	end
	local pc = pendingChoice[player]
	if pc then
		pendingChoice[player] = nil
		releaseTable(pc.table)
	end
	for i = #kings, 1, -1 do
		if kings[i].player == player then
			releaseTable(kings[i].table)
			table.remove(kings, i)
		end
	end
	Lobby.CancelPrivate(player)
end

---------------------------------------------------------------- matchmaking loop
local function tick()
	local t = os.clock()

	-- 1) Kings get challengers first: newcomer inherits the exact word, clock resets to 10s
	for ki = #kings, 1, -1 do
		local k = kings[ki]
		local kLevel = levelOf(k.player)
		for qi, q in ipairs(queue) do
			local range = bracket(t - q.since)
			if math.abs(levelOf(q.player) - kLevel) <= range then
				if q.reservedTable then
					Arena.ClearSeats(q.reservedTable)
					releaseTable(q.reservedTable)
					q.reservedTable = nil
				end
				table.remove(kings, ki)
				table.remove(queue, qi)
				send(q.player, "QueueState", { searching = false })
				local a, b = orderKingSides(k.side, Match.PlayerEntity(k.player), Match.PlayerEntity(q.player))
				startMatch(k.table, a, b, {
					word = k.word,
					startClock = Config.KingStartClock(k.finalClock, levelOf(k.player)),
					ranked = true,
					kingFor = k.player,
				})
				break
			end
		end
	end

	-- 2) pair queued players within level brackets
	local i = 1
	while i <= #queue do
		local a = queue[i]
		local matched = false
		for j = i + 1, #queue do
			local b = queue[j]
			local range = bracket(t - math.min(a.since, b.since))
			if math.abs(levelOf(a.player) - levelOf(b.player)) <= range then
				local tbl = a.reservedTable or b.reservedTable or Arena.FreeTable()
				if not tbl then
					break
				end
				if a.reservedTable and a.reservedTable ~= tbl then
					releaseTable(a.reservedTable)
				end
				if b.reservedTable and b.reservedTable ~= tbl then
					releaseTable(b.reservedTable)
				end
				a.reservedTable = nil
				b.reservedTable = nil
				table.remove(queue, j)
				table.remove(queue, i)
				send(a.player, "QueueState", { searching = false })
				send(b.player, "QueueState", { searching = false })
				startMatch(tbl, Match.PlayerEntity(a.player), Match.PlayerEntity(b.player), { ranked = true })
				matched = true
				break
			end
		end
		if not matched then
			i += 1
		end
	end

	-- 3) nobody waits long: unmatched players get a human-like bot, kings get a challenger
	for qi = #queue, 1, -1 do
		local q = queue[qi]
		if t >= q.fillAt then
			local tbl = q.reservedTable or Arena.FreeTable()
			if tbl then
				q.reservedTable = nil
				table.remove(queue, qi)
				send(q.player, "QueueState", { searching = false })
				startMatch(tbl, Match.PlayerEntity(q.player), disguisedFor(q.player), { ranked = true })
			end
		end
	end
	for ki = #kings, 1, -1 do
		local k = kings[ki]
		if t >= k.fillAt and k.player.Parent then
			table.remove(kings, ki)
			local a, b = orderKingSides(k.side, Match.PlayerEntity(k.player), disguisedFor(k.player, k.finalClock))
			startMatch(k.table, a, b, {
				word = k.word,
				startClock = Config.KingStartClock(k.finalClock, levelOf(k.player)),
				ranked = true,
				kingFor = k.player,
			})
		end
	end

	-- 4) status for people still waiting
	for _, q in ipairs(queue) do
		local waited = t - q.since
		send(q.player, "QueueState", { searching = true, bracket = bracket(waited), waited = math.floor(waited), seated = q.reservedTable ~= nil })
	end
end

Lobby._tick = tick
Ambient.FillAll()

task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(tick)
		if not ok then
			warn("[WordDuel] matchmaking error:", err)
		end
	end
end)

return Lobby
