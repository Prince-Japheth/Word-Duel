-- TestHooks: Studio-only automated test entry point. Does nothing in a live game.
-- Creates ServerStorage.WordDuelTest (BindableFunction); call :Invoke(command, arg) from the
-- Studio command bar or an MCP tool. Runs inside the game's own module instances, so it sees
-- real matches, profiles and the queue.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local TestHooks = {}

function TestHooks.Start(deps)
	if not RunService:IsStudio() then
		return
	end
	local Match, Lobby, Dictionary, PlayerData, Config = deps.Match, deps.Lobby, deps.Dictionary, deps.PlayerData, deps.Config
	local Players = game:GetService("Players")

	local sent = {} -- every message the server sends: { to, action, payload }
	local realMatchSend, realLobbySend = Match.Send, Lobby.Send
	local function capture(real)
		return function(p, a, payload)
			table.insert(sent, { to = p, a = a, p = payload })
			if typeof(p) == "Instance" then
				return real(p, a, payload)
			end
		end
	end
	Match.Send = capture(realMatchSend)
	Lobby.Send = capture(realLobbySend)

	local function realPlayer()
		return Players:GetPlayers()[1]
	end

	local fake -- stand-in second player for ranked / friend-table tests
	local function getFake()
		if not fake then
			fake = { UserId = -777, DisplayName = "TestRival", Name = "TestRival", Parent = workspace, Character = nil, __fake = true }
			PlayerData.Load(fake)
		end
		return fake
	end

	local function since(n, kind, who)
		for i = n + 1, #sent do
			local s = sent[i]
			if s.a == kind and (who == nil or s.to == who) then
				return s.p
			end
		end
		return nil
	end

	local function entOf(m, p)
		return m.ents[1].player == p and m.ents[1] or m.ents[2]
	end

	local cmds = {}

	cmds.state = function(who)
		local p = who == "fake" and getFake() or realPlayer()
		local m = Match.ByPlayer[p]
		local prof = PlayerData.Get(p)
		local r = { inMatch = m ~= nil, busy = Lobby.IsBusy(p) }
		if prof then
			r.elo, r.wins, r.losses, r.curStreak, r.bestStreak, r.coins, r.level, r.xp = prof.elo, prof.wins, prof.losses, prof.curStreak, prof.bestStreak, prof.coins, prof.level, prof.xp
			r.inv = prof.inventory
		end
		if m then
			local e = entOf(m, p)
			r.word, r.myTurn, r.ranked, r.private, r.volley = m.word, m.ents[m.turn] == e, m.ranked, m.private, m.volley
			r.left = m.deadline and (m.deadline - workspace:GetServerTimeNow()) or nil
			local names = {}
			for _, sl in ipairs(e.slots or {}) do
				table.insert(names, sl.kind .. ":" .. sl.state)
			end
			r.items = table.concat(names, ",")
			r.score, r.rivalScore = e.score, m:other(e).score
		end
		return r
	end

	cmds.setup = function()
		local prof = PlayerData.Get(realPlayer())
		prof.inventory = { Help = 5, Skip = 5, Time = 5, DoubleShift = 5 }
		prof.slotsBought = 3
		prof.belt = { "Help", "Time", "DoubleShift", "Skip" }
		PlayerData.Changed(realPlayer())
		return "ok"
	end

	cmds.playbot = function()
		Lobby.PlayBot(realPlayer())
		return Match.ByPlayer[realPlayer()] and "started" or "no match"
	end

	local function submitAs(p, word)
		local m = Match.ByPlayer[p]
		if not m then
			return "no match"
		end
		local n = #sent
		m:submit(p, word)
		return since(n, "Invalid", p) or ("accepted -> " .. m.word)
	end

	cmds.submit = function(word)
		return submitAs(realPlayer(), word)
	end

	cmds.goodMove = function(who)
		local p = (type(who) == "table" and who) or (who == "fake" and getFake()) or realPlayer()
		local m = Match.ByPlayer[p]
		if not m then
			return "no match"
		end
		local w = m:bestMove()
		if not w then
			return "no moves"
		end
		return submitAs(p, w)
	end

	cmds.useItem = function(kind)
		local p = realPlayer()
		local m = Match.ByPlayer[p]
		if not m then
			return "no match"
		end
		local e = entOf(m, p)
		local n = #sent
		local d0, t0 = m.deadline, m.turn
		m:useItem(p, kind)
		local inv = since(n, "Invalid", p)
		if inv then
			return "rejected: " .. inv
		end
		local hint = since(n, "Hint", p)
		return string.format("ok hint=%s dt=%.1f double=%s turnPassed=%s helpUsed=%d left=%s", hint and hint.word or "-", (m.deadline or 0) - (d0 or 0), tostring(e.doublePoints), tostring(m.turn ~= t0), e.helpUsed, (function()
			local names = {}
			for _, sl in ipairs(e.slots or {}) do
				table.insert(names, sl.kind .. ":" .. sl.state)
			end
			return table.concat(names, ",")
		end)())
	end

	-- ranked: queue the real player and the fake together
	cmds.ranked = function()
		local f = getFake()
		Lobby.Queue(realPlayer())
		Lobby.Queue(f)
		return "queued both"
	end

	-- fake plays a move whenever it is its turn (or stalls so it loses on time)
	local fakeMode = "off"
	cmds.fakeMode = function(mode)
		fakeMode = mode
		return mode
	end
	task.spawn(function()
		while true do
			task.wait(0.6)
			if fake and fakeMode == "play" then
				local m = Match.ByPlayer[fake]
				if m and m.active and m.ents[m.turn].player == fake then
					pcall(cmds.goodMove, "fake")
				end
			end
		end
	end)

	cmds.lastResult = function(who)
		local p = who == "fake" and getFake() or realPlayer()
		for i = #sent, 1, -1 do
			if sent[i].a == "BoutEnd" and sent[i].to == p then
				return sent[i].p
			end
		end
		return nil
	end

	cmds.lastSent = function(kind)
		for i = #sent, 1, -1 do
			if sent[i].a == kind then
				return { to = typeof(sent[i].to) == "Instance" and sent[i].to.Name or "fake", payload = sent[i].p }
			end
		end
		return nil
	end

	cmds.choice = function(arg)
		local who, choice = arg[1], arg[2]
		local p = who == "fake" and getFake() or realPlayer()
		Lobby.Choice(p, choice)
		return "ok"
	end

	cmds.kingCashOut = function(who)
		local p = who == "fake" and getFake() or realPlayer()
		Lobby.KingCashOut(p)
		return "ok"
	end

	-- friend table: fake hosts, real player joins with the code
	cmds.friend = function()
		local f = getFake()
		local code = Lobby.CreatePrivate(f)
		local n = #sent
		Lobby.JoinPrivate(realPlayer(), code .. " ") -- trailing space: join should still work
		local m = Match.ByPlayer[realPlayer()]
		return string.format("code=%s match=%s private=%s ranked=%s toast=%s", tostring(code), tostring(m ~= nil), tostring(m and m.private), tostring(m and m.ranked), tostring(since(n, "Toast")))
	end

	cmds.queueWhileHosting = function()
		local p = realPlayer()
		local code = Lobby.CreatePrivate(p)
		Lobby.Queue(p)
		local still = Lobby.HostCode(p)
		Lobby.CancelQueue(p)
		return string.format("code=%s stillHostingAfterQueue=%s", tostring(code), tostring(still ~= nil))
	end

	cmds.forfeit = function(who)
		local p = who == "fake" and getFake() or realPlayer()
		local m = Match.ByPlayer[p]
		if m then
			m:forfeit(p)
		end
		return "ok"
	end

	-- saving: round-trip the real profile through an in-memory store
	cmds.saveTest = function()
		local p = realPlayer()
		local mem = {}
		local fail = false
		local mock = {
			GetAsync = function(_, k)
				return mem[k]
			end,
			UpdateAsync = function(_, k, fn)
				if fail then
					error("simulated DataStore outage")
				end
				mem[k] = fn(mem[k])
				return mem[k]
			end,
		}
		PlayerData._UseStoreForTesting(mock)
		local prof = PlayerData.Load(p) -- reload through the store so saving is enabled
		prof.coins = 4321
		prof.inventory.Help = 17
		prof.achievements.first_win = 123
		local savedOk = PlayerData.Save(p)
		-- load into a stand-in with the same UserId
		local twin = { UserId = p.UserId, Parent = workspace, Name = "Twin", DisplayName = "Twin" }
		local loaded = PlayerData.Load(twin)
		local roundTrip = loaded and loaded.coins == 4321 and loaded.inventory.Help == 17 and loaded.achievements.first_win == 123
		PlayerData.Release(twin)
		-- receipts: product grant only confirmed when the save works
		local product
		for _, pr in ipairs(Config.Products) do
			if pr.key == "Help3" then
				product = pr
			end
		end
		local oldId = product.id
		product.id = 987654
		local helpBefore = prof.inventory.Help
		local r1 = deps.Shop.ProcessReceipt({ PlayerId = p.UserId, ProductId = 987654, PurchaseId = "test-1" })
		local helpAfter1 = prof.inventory.Help
		local r2 = deps.Shop.ProcessReceipt({ PlayerId = p.UserId, ProductId = 987654, PurchaseId = "test-1" })
		local helpAfter2 = prof.inventory.Help
		fail = true
		local r3 = deps.Shop.ProcessReceipt({ PlayerId = p.UserId, ProductId = 987654, PurchaseId = "test-2" })
		fail = false
		product.id = oldId
		PlayerData._UseStoreForTesting(nil)
		PlayerData.Load(p) -- give the Studio player a clean profile again
		PlayerData.Changed(p)
		return string.format(
			"save=%s roundTrip=%s | receipt1=%s help %d->%d | duplicate=%s help=%d | saveFails=%s",
			tostring(savedOk), tostring(roundTrip), tostring(r1), helpBefore, helpAfter1, tostring(r2), helpAfter2, tostring(r3)
		)
	end

	cmds.studioBuy = function(key)
		local Shop = deps.Shop
		local p = realPlayer()
		local prof = PlayerData.Get(p)
		local before = prof.slotsBought
		Shop.Buy(p, key)
		return "slotsBought " .. before .. " -> " .. prof.slotsBought .. " slots=" .. PlayerData.Slots(prof)
	end

	-- force a letter lock on the real player's next turn (to look at the lock UI)
	cmds.forceLock = function()
		local p = realPlayer()
		local m = Match.ByPlayer[p]
		if not m then
			return "no match"
		end
		local e = entOf(m, p)
		m.ents[1].level, m.ents[2].level = 40, 40
		m.volley = math.max(m.volley, Config.LetterLockVolley + 1)
		local old = Config.LetterLockChance
		Config.LetterLockChance = 1
		m.lockRun, m.lockCooldown = 0, 0
		m.turn = e.side
		m:startTurn()
		Config.LetterLockChance = old
		return "locked " .. table.concat(m.lockLetters or {}, ",") .. " on " .. m.word
	end

	cmds.cleanup = function()
		if fake then
			Lobby.PlayerLeft(fake)
			fakeMode = "off"
		end
		local m = Match.ByPlayer[realPlayer()]
		if m then
			m:forfeit(realPlayer())
		end
		return "ok"
	end

	-- ONE call, compact answer: logic + simulated matches + tutorial + backfill + saving.
	-- Returns "PASS n/n" or "FAIL k/n" plus the failing checks. Takes about 10 seconds.
	cmds.runAll = function()
		local WordRules = require(game:GetService("ReplicatedStorage").Shared.WordRules)
		local Ambient = deps.Ambient
		local Arena = deps.Arena
		local results, fails = 0, {}
		local function check(name, cond, detail)
			results += 1
			if not cond then
				table.insert(fails, name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
			end
		end
		local function newFake(id, name)
			local f = { UserId = id, DisplayName = name, Name = name, Parent = workspace, Character = nil, __fake = true }
			PlayerData.Load(f)
			return f
		end

		-- words + rules
		check("normalize", WordRules.Normalize("  CaT ") == "cat")
		check("diff", (WordRules.Diff("cat", "bat")) == 1)
		check("CAT->CATER = 5", select(2, WordRules.Points("cat", "cater")) == 5)
		check("CATER->CAT = 3", select(2, WordRules.Points("cater", "cat")) == 3)
		check("TREAD->STEAL = 2", select(2, WordRules.Points("tread", "steal")) == 2)
		check("plural/past banned", WordRules.IsInflection("cat", "cats") and WordRules.IsInflection("box", "boxes") and WordRules.IsInflection("bake", "baked") and WordRules.IsInflection("jump", "jumped") and WordRules.IsInflection("try", "tries") and WordRules.IsInflection("try", "tried") and WordRules.IsInflection("stop", "stopped"))
		check("real changes allowed", not WordRules.IsInflection("cat", "cater") and not WordRules.IsInflection("cats", "rats") and not WordRules.IsInflection("cat", "cast"))
		check("long words", Dictionary.IsWord("elephant") and Dictionary.IsWord("submarine"))
		check("word box", Dictionary.IsWord("box"))
		check("non-word xum", not Dictionary.IsWord("xum"))
		check("blocked word", not Dictionary.IsWord("ass") and not Dictionary.IsWord("shit"))
		local badStart
		for len = 3, 6 do
			for _ = 1, 25 do
				local w = Dictionary.StartWord(len)
				if #w ~= len or not Dictionary.IsCommon(w) then
					badStart = w
				end
			end
		end
		check("start words common", badStart == nil, badStart)
		check("bot picks common", Dictionary.IsCommon(Dictionary.PickMove("cat", 1, { cat = true }, nil) or ""))
		check("clock starts at StartTurnTime", Config.TurnTime(0) == Config.StartTurnTime)
		local T = Config.TurnTime
		check("clock speed-up eases off", (T(0) - T(1)) > (T(20) - T(21)) and (T(20) - T(21)) > (T(60) - T(61)) and (T(60) - T(61)) > 0)
		check("clock never below floor", T(500) >= Config.MinTurnTime and T(500) < Config.MinTurnTime + 0.01)
		check("higher level starts faster", Config.StartClockForLevel(30) < Config.StartClockForLevel(1) and Config.StartClockForLevel(500) == Config.StartTurnTimeMin)
		check("King keeps momentum", math.abs(Config.KingStartClock(5, 1) - (5 + Config.KingMomentumBonus)) < 0.01 and Config.KingStartClock(3.6, 1) >= Config.MinTurnTime + 1.5)
		local ambientCount = 0
		for _, t in ipairs(Arena.Tables) do
			if Ambient.IsRunning(t) then
				ambientCount += 1
			end
		end
		check("hall has NPC duels", ambientCount >= 3, ambientCount)

		-- fast simulated ranked match between two fake players (the TREAD -> STEAL -> CREED example)
		local fa, fb = newFake(-9001, "TesterA"), newFake(-9002, "TesterB")
		local tbl = Arena.FreeTable()
		Ambient.Stop(tbl)
		local ended
		local function onEnd(_, w, l, why)
			ended = { winner = w, loser = l, reason = why }
		end
		local m = Match.new(tbl, Match.PlayerEntity(fa), Match.PlayerEntity(fb), { ranked = true, word = "tread", onEnd = onEnd })
		m.turn = 1 -- test script: TesterA opens (real games: lower level first)
		check("ranked people", m.ranked == true)
		check("early move blocked", submitAs(fa, "steal"):find("Get ready") ~= nil)
		task.wait(1.6)
		check("A plays STEAL", submitAs(fa, "steal") == "accepted -> steal")
		check("STEAL scores 2", m.ents[1].score == 2, m.ents[1].score)
		check("not your turn", submitAs(fa, "creed"):find("Not your turn") ~= nil)
		check("repeat blocked", submitAs(fb, "tread"):find("already played") ~= nil)
		check("needs a kept letter", submitAs(fb, "abhor"):find("same spot") ~= nil)
		check("too short", submitAs(fb, "st"):find("3 to 10") ~= nil)
		check("dictionary", submitAs(fb, "stxxx"):find("dictionary") ~= nil)
		check("B plays CREED", submitAs(fb, "creed"):find("accepted") ~= nil)
		check("CREED scores 1", m.ents[2].score == 1, m.ents[2].score)
		check("clock speeds up", m.turnTime == Config.TurnTime(2) and Config.TurnTime(2) < Config.TurnTime(0), m.turnTime)
		check("state has scores", m:stateFor(m.ents[1]).myScore == 2 and m:stateFor(m.ents[1]).rivalScore == 1)
		check("state has used list", #m:stateFor(m.ents[1]).used == 3)
		local bw = m:bestMove()
		check("hint keeps letters", bw and Match.kept(m.word, bw) >= 1, bw)
		-- Double Points item
		local pa = PlayerData.Get(fa)
		pa.inventory.DoubleShift = 1
		m.ents[1].slots = { { kind = "DoubleShift", state = "ready", readyIn = 0 } }
		m:useItem(fa, "DoubleShift")
		local before = m.ents[1].score
		local dw = m:bestMove()
		submitAs(fa, dw)
		check("double points", m.ents[1].score - before == 2 * select(2, WordRules.Points("creed", dw)), m.ents[1].score - before)
		m:forfeit(fb)
		check("forfeit ends match", ended and ended.reason == "left" and ended.winner.player == fa, ended and ended.reason)
		tbl.busy = false

		-- any length: CAT -> CATER scores 5, plurals/past tense refused
		local tblC = Arena.FreeTable()
		Ambient.Stop(tblC)
		ended = nil
		local mc = Match.new(tblC, Match.PlayerEntity(fa), Match.PlayerEntity(fb), { ranked = false, word = "cat", onEnd = onEnd })
		mc.turn = 1
		task.wait(1.6)
		check("CATS refused", submitAs(fa, "cats"):find("plurals") ~= nil)
		check("CATER accepted", submitAs(fa, "cater") == "accepted -> cater")
		check("CATER scores 5", mc.ents[1].score == 5, mc.ents[1].score)
		check("CATERED refused", submitAs(fb, "catered"):find("past tense") ~= nil)
		check("shorter word ok", submitAs(fb, "care"):find("accepted") ~= nil and mc.ents[2].score == 3, mc.ents[2].score)
		local bwc = mc:bestMove()
		check("hint is legal", bwc and Match.kept("care", bwc) >= 1 and not WordRules.IsInflection("care", bwc), bwc)
		mc:forfeit(fb)
		tblC.busy = false

		-- letter locks: only at high level once the rally is fast
		local tblL = Arena.FreeTable()
		Ambient.Stop(tblL)
		local ml = Match.new(tblL, Match.PlayerEntity(fa), Match.PlayerEntity(fb), { ranked = false, word = "planter", onEnd = function() end })
		ml.turn = 1
		task.wait(1.6)
		ml.volley = 2
		check("no locks early/low level", not ml:locksAllowed())
		ml.ents[1].level, ml.ents[2].level = 40, 40
		ml.volley = Config.LetterLockVolley + 5
		check("locks allowed when fast + high level", ml:locksAllowed())
		local oldChance = Config.LetterLockChance
		Config.LetterLockChance = 1
		ml.lockRun, ml.lockCooldown = 0, 0
		ml:updateLocks()
		local L = ml.lockLetters
		check("lock picks 1-2 letters from the word", L and #L >= 1 and #L <= 2 and string.find("planter", L[1], 1, true) ~= nil, L and table.concat(L, ","))
		check("lock leaves enough moves", L and #ml:candidates() >= Config.LetterLockMinMoves)
		local lockedMoveOk = true
		for _, c in ipairs(ml:candidates()) do
			if ml:hitsLock(c.w) then
				lockedMoveOk = false
			end
		end
		check("bots/Help never use locked letters", lockedMoveOk and (ml:bestMove() == nil or not ml:hitsLock(ml:bestMove())))
		if L then
			-- find a real word that uses a locked letter and otherwise would be legal
			local bad
			for _, c in ipairs((function()
				local saved = ml.lockLetters
				ml.lockLetters = nil
				local all = ml:candidates()
				ml.lockLetters = saved
				return all
			end)()) do
				if ml:hitsLock(c.w) then
					bad = c.w
					break
				end
			end
			ml.turn = 1
			check("locked letter refused", bad and submitAs(fa, bad):find("locked") ~= nil, bad)
		end
		-- a spell lasts a few turns, then cools down
		local runs = 0
		for _ = 1, 12 do
			ml:updateLocks()
			if ml.lockLetters then
				runs += 1
			end
		end
		check("locks come and go", runs > 0 and runs < 12, runs)
		Config.LetterLockChance = oldChance
		ml:forfeit(fa)
		tblL.busy = false

		-- power-up slots: fast-game slots open when the clock gets short; used slots refill
		-- slowly, and only from what you own
		local tblP = Arena.FreeTable()
		Ambient.Stop(tblP)
		local mp = Match.new(tblP, Match.PlayerEntity(fa), Match.PlayerEntity(fb), { ranked = false, word = "stone", onEnd = function() end })
		mp.turn = 1
		task.wait(1.6)
		local pe = mp.ents[1]
		local prof = PlayerData.Get(fa)
		prof.inventory.Time = 1
		pe.slots = { { kind = "Time", state = "empty", readyIn = 0 }, { kind = "Time", state = "locked", fastAt = 7, readyIn = 0 } }
		mp.turnTime = 12
		mp:refreshSlots(pe, true)
		check("open slot fills from what you own", pe.slots[1].state == "ready" and pe.slots[2].state == "locked")
		mp.turnTime = 6.5
		mp:refreshSlots(pe, true)
		check("fast slot opens but stays empty if you own too few", pe.slots[2].state == "empty", pe.slots[2].state)
		prof.inventory.Time = 2
		mp:refreshSlots(pe, false)
		check("owning more fills the slot", pe.slots[2].state == "ready")
		mp.turn = 1
		mp:useItem(fa, "Time")
		check("using a power-up starts its refill", pe.slots[1].state == "cooldown" and pe.slots[1].readyIn == Config.ItemRefillTurns and prof.inventory.Time == 1)
		for _ = 1, Config.ItemRefillTurns - 1 do
			mp:refreshSlots(pe, true)
		end
		check("refill takes a few turns", pe.slots[1].state == "cooldown")
		mp:refreshSlots(pe, true)
		check("refills only from what you own", pe.slots[1].state == "empty" and pe.slots[2].state == "ready", pe.slots[1].state)
		prof.inventory.Time = 3
		mp:refreshSlots(pe, false)
		check("refills when you have more", pe.slots[1].state == "ready")
		mp:forfeit(fa)
		tblP.busy = false

		-- clock timeout still eliminates
		ended = nil
		local tblT = Arena.FreeTable()
		Ambient.Stop(tblT)
		ended = nil
		local mt = Match.new(tblT, Match.PlayerEntity(fa), Match.PlayerEntity(fb), { ranked = true, word = "pin", onEnd = onEnd })
		mt.turn = 1
		task.wait(1.6)
		mt.deadline = workspace:GetServerTimeNow() + 0.15
		mt:armTimer(mt.token)
		task.wait(0.5)
		check("timeout ends match", ended and ended.reason == "timeout" and ended.winner.player == fb, ended and ended.reason)
		tblT.busy = false

		-- hidden bot: looks like a player, has a seated avatar
		local fc = newFake(-9003, "TesterC")
		local tbl2 = Arena.FreeTable()
		Ambient.Stop(tbl2)
		local n0 = #sent
		local bot = Match.BotEntity(3, { disguised = true, elo = 1100 })
		local m2 = Match.new(tbl2, Match.PlayerEntity(fc), bot, { ranked = true, onEnd = function() end })
		local start = since(n0, "MatchStart", fc)
		check("bot hidden", start and start.opp.isBot == false)
		check("bot name human", not bot.name:find("Bot") and not bot.name:find("Practice"), bot.name)
		check("bot has avatar", bot.rig ~= nil and bot.rig.Parent ~= nil)
		check("bot match ranked", m2.ranked == true)
		local bm = m2:botMove(m2.ents[2])
		check("bot plays legal words", bm and Match.kept(m2.word, bm) >= 1 and Dictionary.IsWord(bm), bm)
		m2:forfeit(fc)
		tbl2.busy = false

		-- bots answer inside their clock (both at the start and at the 3.5s floor)
		local lateBot, slowest = nil, 0
		for _, t in ipairs({ Config.StartTurnTime, Config.MinTurnTime }) do
			for _, skill in ipairs({ 0.05, 0.5, 0.95 }) do
				local fakeMatch = setmetatable({ turnTime = t, volley = 0 }, Match)
				for _ = 1, 200 do
					local d = fakeMatch:botDelay({ skill = skill, disguised = true })
					slowest = math.max(slowest, d / t)
					if d > t - 0.5 or d < 0.5 then
						lateBot = string.format("t=%.1f skill=%.2f d=%.2f", t, skill, d)
					end
				end
			end
		end
		check("bots answer in time", lateBot == nil, lateBot)
		local slipMatch = setmetatable({ turnTime = 12, volley = 10 }, Match)
		check("bots rarely freeze", slipMatch:botSlipChance({ skill = 0.5, disguised = true }) < 0.1)

		-- tutorial, queue backfill and the automatic King run in parallel (each takes a few seconds)
		local learner, waiter = newFake(-9004, "Learner"), newFake(-9005, "Waiter")
		local kingA, kingB = newFake(-9006, "KingA"), newFake(-9007, "KingB")
		local tutDone, fillMatch, kingResult
		task.spawn(function()
			-- two people queue -> ranked match; one times out; the winner stays on as King
			-- automatically and a challenger sits down on the same word without any button
			Lobby.Queue(kingA)
			Lobby.Queue(kingB)
			local km
			for _ = 1, 40 do
				km = Match.ByPlayer[kingA]
				if km then
					break
				end
				task.wait(0.1)
			end
			if not km then
				kingResult = "no ranked match"
				return
			end
			task.wait(1.6)
			km.deadline = workspace:GetServerTimeNow() + 0.1
			km:armTimer(km.token)
			task.wait(0.4)
			local loserSide = km.turn
			local winnerP = km.ents[3 - loserSide].player
			local lastWord = km.word
			for _ = 1, 60 do
				local nm = Match.ByPlayer[winnerP]
				if nm and nm ~= km then
					kingResult = (nm.word == lastWord and nm.ranked) and "ok" or ("wrong match " .. tostring(nm.word))
					nm:forfeit(winnerP)
					return
				end
				task.wait(0.1)
			end
			kingResult = "no challenger"
		end)
		task.spawn(function()
			Lobby.StartTutorial(learner)
			local tm = Match.ByPlayer[learner]
			if not tm then
				return
			end
			for _ = 1, 120 do
				if not tm.active then
					break
				end
				if tm.ents[tm.turn].player == learner and tm.deadline then
					pcall(cmds.goodMove, learner)
				end
				task.wait(0.15)
			end
			tutDone = PlayerData.Get(learner).tutorialDone
		end)
		task.spawn(function()
			PlayerData.Get(waiter).level = 40 -- far from the King testers so the two tests never pair up
			Lobby.Queue(waiter)
			for _ = 1, 100 do
				local qm = Match.ByPlayer[waiter]
				if qm then
					fillMatch = qm
					break
				end
				task.wait(0.1)
			end
		end)
		for _ = 1, 140 do
			if tutDone ~= nil and fillMatch and kingResult then
				break
			end
			task.wait(0.1)
		end
		check("King continues automatically", kingResult == "ok", kingResult)
		check("tutorial completes", tutDone == true)
		check("tutorial reward", PlayerData.Get(learner).coins >= Config.TutorialReward.coins)
		check("queue backfilled", fillMatch ~= nil)
		check("backfill ranked + hidden", fillMatch and fillMatch.ranked and fillMatch.ents[2].disguised)
		if fillMatch then
			fillMatch:forfeit(waiter)
		end

		-- records + awards for long words and scores, each announced with a reward popup
		local popups = {}
		local realOnReward = PlayerData.OnReward
		PlayerData.OnReward = function(plr, payload)
			if plr == fa then
				table.insert(popups, payload)
			end
			if realOnReward then
				realOnReward(plr, payload)
			end
		end
		local pr = PlayerData.Get(fa)
		pr.bestWordLen, pr.longWords, pr.longStreakBest, pr.bestScore, pr.achievements = 4, 0, 0, 10, {}
		PlayerData.WordPlayed(fa, "elephant", 1)
		PlayerData.WordPlayed(fa, "triangle", 2)
		PlayerData.CheckAchievements(fa)
		PlayerData.CheckScoreRecord(fa, 31)
		PlayerData.OnReward = realOnReward
		check("longest word record", pr.bestWordLen == 8 and pr.bestWord == "elephant")
		check("long words counted", pr.longWords == 2 and pr.longStreakBest == 2)
		check("best score record", pr.bestScore == 31)
		check("long-word awards", pr.achievements.word_8 ~= nil and pr.achievements.score_30 ~= nil)
		local kinds = {}
		for _, r in ipairs(popups) do
			kinds[r.kind] = (kinds[r.kind] or 0) + 1
		end
		check("reward popups sent", (kinds.record or 0) >= 3 and (kinds.award or 0) >= 2, game:GetService("HttpService"):JSONEncode(kinds))

		-- saving and receipts
		local save = cmds.saveTest()
		check("save + receipts", save:find("save=true roundTrip=true") and save:find("duplicate=Enum.ProductPurchaseDecision.PurchaseGranted help=20") and save:find("saveFails=Enum.ProductPurchaseDecision.NotProcessedYet"), save)

		for _, f in ipairs({ fa, fb, fc, learner, waiter, kingA, kingB }) do
			Lobby.PlayerLeft(f)
			PlayerData.Release(f)
		end
		local passed = results - #fails
		return (#fails == 0 and "PASS " or "FAIL ") .. passed .. "/" .. results .. (#fails > 0 and (": " .. table.concat(fails, "; ")) or "")
	end

	local bf = ServerStorage:FindFirstChild("WordDuelTest") or Instance.new("BindableFunction")
	bf.Name = "WordDuelTest"
	bf.OnInvoke = function(cmd, arg)
		local f = cmds[cmd]
		if not f then
			return "unknown command " .. tostring(cmd)
		end
		local ok, res = pcall(f, arg)
		if not ok then
			return "ERROR " .. tostring(res)
		end
		return res
	end
	bf.Parent = ServerStorage
	print("[WordDuel] Studio test hooks ready (ServerStorage.WordDuelTest)")
end

return TestHooks
