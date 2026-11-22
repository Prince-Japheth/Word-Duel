-- Match: one 1v1 bout at a table. Infinite rally on a clock that keeps speeding up.
-- Rules:
--   * play any real word (3-10 letters) that keeps AT LEAST ONE letter in the same spot as
--     the previous word; no plural/past tense of the previous word; no repeats in a match
--   * points = letters kept in place + letters added (CAT -> CATER = 5, TREAD -> STEAL = 2)
--   * clock: starts by level (or King momentum), speeds up every move with easing, never below the floor
--   * run out of time and you lose; points are your score (bonus coins/XP), survival decides the win
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WordRules = require(Shared.WordRules)

local Dictionary = require(script.Parent.Dictionary)
local PlayerData = require(script.Parent.PlayerData)
local Arena = require(script.Parent.Arena)
local NPC = require(script.Parent.NPC)

local Match = {}
Match.__index = Match
Match.ByPlayer = {} -- [player] = match
Match.Send = nil -- function(player, action, payload), set by Main

local function now()
	return workspace:GetServerTimeNow()
end

local function send(e, action, payload)
	if e.player and Match.Send then
		Match.Send(e.player, action, payload)
	end
end

local MIN_LEN, MAX_LEN = 3, 10

-- letters kept in the same position (a move needs at least one)
local function kept(prev, w)
	return (WordRules.Points(prev, w))
end
Match.kept = kept

local function points(prev, w)
	local _, pts = WordRules.Points(prev, w)
	return pts
end

-- entity helpers ------------------------------------------------------------
function Match.PlayerEntity(player)
	local p = PlayerData.Get(player)
	-- belt slots: the first `base` are open from the start; the next ones are fast-game
	-- slots that open when the clock gets short. Each slot pulls from what you own.
	local slots = {}
	if p then
		local base = PlayerData.Slots(p)
		local maxAllowed = math.min(Config.AbsoluteMaxSlots or 9, base + #Config.FastSlotClocks)
		for i = 1, maxAllowed do
			local kind = p.belt[i]
			local fastAt = i > base and Config.FastSlotClocks[i - base] or nil
			if kind and Config.Items[kind] then
				table.insert(slots, { kind = kind, state = fastAt and "locked" or "empty", fastAt = fastAt, readyIn = 0, slot = i })
			else
				table.insert(slots, { kind = "Empty", state = fastAt and "locked" or "unassigned", fastAt = fastAt, readyIn = 0, slot = i })
			end
		end
	end
	return {
		kind = "player",
		player = player,
		userId = player.UserId,
		name = player.DisplayName,
		level = p and p.level or 1,
		xp = p and p.xp or 0,
		elo = p and p.elo or Config.StartElo,
		slots = slots,
	}
end

local PRACTICE_NAMES = { "Practice Rook", "Practice Bishop", "Practice Knight", "Practice Pawn", "Practice Queen" }

-- opts.disguised: a matchmaking bot that plays like a person (generated name, skill near `elo`)
-- opts.tutorial: the friendly coach used in the first-time tutorial
function Match.BotEntity(level, opts)
	opts = opts or {}
	level = math.max(1, level + math.random(-2, 2))
	local name
	if opts.tutorial then
		name = "Coach Tilly"
	elseif opts.disguised then
		name = NPC.RandomName()
	else
		name = PRACTICE_NAMES[math.random(#PRACTICE_NAMES)]
	end
	local elo = opts.elo or Config.StartElo
	return {
		kind = "bot",
		disguised = opts.disguised == true,
		tutorial = opts.tutorial == true,
		userId = 0,
		name = name,
		level = level,
		xp = opts.xp or 0,
		elo = elo,
		slots = {},
		-- 0..1: how strong this bot plays (stronger = faster, higher scores, slips less)
		skill = math.clamp((elo - 800) / 1000 + (math.random() - 0.5) * 0.2, 0.05, 0.95),
	}
end

local function resetEntity(e, side)
	e.side = side
	e.helpUsed = 0
	e.lastHelpTurn = -99
	e.ownTurns = 0
	e.words = 0
	e.score = 0
	e.doublePoints = false
	e.longRun = 0
end

local function publicInfo(e)
	local rank = Config.RankFor(e.elo)
	-- matchmaking bots look exactly like players; only practice/tutorial opponents are labelled
	return { name = e.name, level = e.level, elo = e.elo, rank = rank.name, userId = e.userId, isBot = e.kind == "bot" and not e.disguised, rig = e.rig }
end

-- power-up slots ------------------------------------------------------------------
-- you can fill a slot only while you own more of that power-up than are already loaded
function Match:canFill(e, kind)
	if self.tutorial then
		return true
	end
	if not kind or kind == "Empty" then
		return false
	end
	local p = e.player and PlayerData.Get(e.player)
	if not p then
		return false
	end
	local loaded = 0
	for _, s in ipairs(e.slots) do
		if s.kind == kind and s.state == "ready" then
			loaded += 1
		end
	end
	return loaded < (p.inventory[kind] or 0)
end

-- fast slots open when the clock gets short; used slots count down and refill; empty
-- slots fill as soon as you own one (e.g. bought mid-game)
function Match:refreshSlots(e, ownTurn)
	local timeLeft = self.deadline and math.max(0, self.deadline - now()) or self.turnTime or 0
	for _, s in ipairs(e.slots or {}) do
		if s.kind and s.kind ~= "Empty" then
			if s.state == "locked" and s.fastAt and (timeLeft <= s.fastAt or (self.turnTime and self.turnTime <= s.fastAt)) then
				s.state = "empty"
				send(e, "SlotOpened", { kind = s.kind, clock = s.fastAt })
			end
			if s.state == "cooldown" and ownTurn then
				s.readyIn -= 1
				if s.readyIn <= 0 then
					s.state = "empty"
				end
			end
			if s.state == "empty" and self:canFill(e, s.kind) then
				s.state = "ready"
			end
		end
	end
end

-- moves ------------------------------------------------------------------------
-- every legal move: unused, keeps a letter in place, not a plural/past tense of the
-- current word. Lengths near the current word (people rarely jump far). { {w=, pts=}, ... }
function Match:candidates()
	local out = {}
	local prev = self.word
	for len = math.max(MIN_LEN, #prev - 2), math.min(MAX_LEN, #prev + 2) do
		for _, w in ipairs(Dictionary.AllWords(len)) do
			if not self.used[w] and kept(prev, w) >= 1 and not WordRules.IsInflection(prev, w) and not WordRules.IsSuffixManipulation(prev, w) and not self:hitsLock(w) then
				table.insert(out, { w = w, pts = points(prev, w) })
			end
		end
	end
	return out
end

-- letter locks ---------------------------------------------------------------------
-- At high levels, once a rally is already fast, a lock sometimes appears: for a few turns
-- in a row, 1-2 letters (taken from the current word) can't be used, different ones each
-- turn. Then it goes away for a while. Always leaves enough legal words to play.
function Match:hitsLock(w, letters)
	if type(letters) ~= "table" then
		letters = self.lockLetters
	end
	if not letters then
		return false
	end
	for _, ch in ipairs(letters) do
		if string.find(w, ch, 1, true) then
			return true
		end
	end
	return false
end

function Match:locksAllowed()
	if self.tutorial or self.volley < Config.LetterLockVolley then
		return false
	end
	local a, b = self.ents[1], self.ents[2]
	return (a.level + b.level) / 2 >= Config.LetterLockLevel
end

function Match:pickLockLetters()
	local letters, seen = {}, {}
	for i = 1, #self.word do
		local ch = self.word:sub(i, i)
		if not seen[ch] then
			seen[ch] = true
			table.insert(letters, ch)
		end
	end
	for i = #letters, 2, -1 do
		local j = math.random(i)
		letters[i], letters[j] = letters[j], letters[i]
	end
	local want = math.random(1, 2)
	for n = want, 1, -1 do
		local pick = { table.unpack(letters, 1, n) }
		self.lockLetters = pick
		local enough = #self:candidates() >= Config.LetterLockMinMoves
		self.lockLetters = nil
		if enough then
			return pick
		end
	end
	return nil
end

function Match:updateLocks()
	self.lockLetters = nil
	if not self:locksAllowed() then
		return
	end
	if (self.lockRun or 0) > 0 then
		self.lockRun -= 1
	elseif (self.lockCooldown or 0) > 0 then
		self.lockCooldown -= 1
		return
	elseif math.random() < Config.LetterLockChance then
		self.lockRun = math.random(Config.LetterLockRun[1], Config.LetterLockRun[2]) - 1
	else
		return
	end
	if self.lockRun == 0 then
		self.lockCooldown = math.random(Config.LetterLockCooldown[1], Config.LetterLockCooldown[2])
	end
	self.lockLetters = self:pickLockLetters()
end

-- a strong everyday move: as many letters kept as possible (used by Help and the tutorial)
function Match:bestMove()
	local best, bestScore
	for _, c in ipairs(self:candidates()) do
		-- everyday words first (a hint nobody knows is useless), then points, then a little
		-- preference for staying near the current length
		local s = (Dictionary.IsCommon(c.w) and 100 or 0) + c.pts * 10 - math.abs(#c.w - #self.word) * 6 + math.random()
		if (not bestScore or s > bestScore) and Dictionary.IsAllowed(c.w) then
			best, bestScore = c, s
		end
	end
	return best and best.w, best and best.pts
end

-- construction --------------------------------------------------------------
-- opts: word, volley, ranked, private, tutorial, firstTurn, onEnd(match, winner, loser, reason)
function Match.new(tbl, a, b, opts)
	local self = setmetatable({}, Match)
	self.table = tbl
	tbl.busy = true
	self.ents = { a, b }
	local function real(e)
		return e.kind == "player" or e.disguised
	end
	self.ranked = opts.ranked and real(a) and real(b)
	self.tutorial = opts.tutorial
	self.private = opts.private
	self.onEnd = opts.onEnd
	self.volley = opts.volley or 0
	-- starting clock: from the players' level, or (King) from the pace the last match was won at
	self.startClock = opts.startClock or Config.StartClockForLevel(math.floor((a.level + b.level) / 2))

	-- Determine turn order:
	-- When playing online (ranked, online, or no explicit firstTurn forced),
	-- the player on the lower level always starts first.
	-- If both are on the exact same level and xp, then have it at random.
	local firstTurn = opts.firstTurn
	if opts.tutorial then
		firstTurn = 1
	elseif not firstTurn or self.ranked or opts.online then
		local aLvl = a.level or 1
		local bLvl = b.level or 1
		local aXp = a.xp or 0
		local bXp = b.xp or 0
		if aLvl < bLvl then
			firstTurn = 1
		elseif bLvl < aLvl then
			firstTurn = 2
		elseif aXp < bXp then
			firstTurn = 1
		elseif bXp < aXp then
			firstTurn = 2
		else
			firstTurn = (math.random(1, 2) == 1) and 1 or 2
		end
	end
	self.turn = firstTurn or 1
	self.firstBigWordDone = false
	self.biggestWord = nil
	self.biggestWordLen = 0
	self.biggestWordPlayer = nil
	self.biggestWordPlayerName = nil
	self.token = 0
	self.active = true

	local len = #(opts.word or "")
	if len == 0 then
		len = Config.LengthForLevel(math.floor((a.level + b.level) / 2))
	end
	self.word = opts.word or Dictionary.StartWord(len)
	self.used = { [self.word] = true }
	self.history = { self.word }
	if self.tutorial then
		for _, e in ipairs(self.ents) do
			if e.kind == "player" then
				e.slots = {}
				for _, kind in ipairs({ "Help", "DoubleShift", "Time", "Skip" }) do
					table.insert(e.slots, { kind = kind, state = "ready", readyIn = 0 })
				end
			end
		end
	end

	Arena.ClearSeats(tbl, { [1] = a.player, [2] = b.player })
	for i, e in ipairs(self.ents) do
		resetEntity(e, i)
		if e.player then
			Match.ByPlayer[e.player] = self
			Arena.Seat(tbl, i, e.player)
			e.rig = e.player.Character
		elseif e.kind == "bot" then
			e.rig = NPC.Build(e.name)
			if e.rig then
				Arena.SeatRig(tbl, i, e.rig)
			end
		end
	end
	Arena.SetDisplay(tbl, self.word, string.format("%s (Lv %d)  vs  %s (Lv %d)", a.name, a.level, b.name, b.level))

	for _, e in ipairs(self.ents) do
		local opp = self.ents[3 - e.side]
		local isKing = opts.kingFor ~= nil and e.player == opts.kingFor
		local kp = isKing and PlayerData.Get(e.player)
		send(e, "MatchStart", { me = publicInfo(e), opp = publicInfo(opp), ranked = self.ranked, private = self.private, tutorial = self.tutorial, king = isKing, kingStreak = kp and kp.curStreak or nil, challenger = opts.kingFor ~= nil and not isKing })
	end
	task.delay(1.5, function()
		self:startTurn()
	end)
	return self
end

function Match:other(e)
	return self.ents[3 - e.side]
end

function Match:broadcast(action, payload)
	for _, e in ipairs(self.ents) do
		send(e, action, payload)
	end
end

function Match:stateFor(e)
	local hist = {}
	for i = math.max(1, #self.history - 11), #self.history do
		table.insert(hist, self.history[i])
	end
	local used = {}
	for w in pairs(self.used) do
		table.insert(used, w)
	end
	local helpCooldown = (e.lastHelpTurn + Config.HelpCooldownTurns) - (e.ownTurns + (self.ents[self.turn] == e and 0 or 1))
	local other = self:other(e)
	return {
		word = self.word,
		prev = self.history[#self.history - 1],
		myTurn = self.ents[self.turn] == e,
		deadline = self.deadline,
		turnTime = self.turnTime,
		history = hist,
		used = used,
		volley = self.volley,
		slots = e.slots,
		helpLeft = Config.HelpMaxPerMatch - e.helpUsed,
		helpCooldown = math.max(0, helpCooldown),
		myScore = e.score,
		rivalScore = other.score,
		doublePoints = e.doublePoints,
		tutorial = self.tutorial,
		myWords = e.words,
		lockLetters = self.lockLetters,
	}
end

function Match:pushState()
	for _, e in ipairs(self.ents) do
		send(e, "MatchState", self:stateFor(e))
	end
end

-- turn flow -----------------------------------------------------------------
function Match:armTimer(token)
	local remaining = self.deadline - now()
	task.delay(math.max(0, remaining), function()
		if not self.active or self.token ~= token then
			return
		end
		if now() < self.deadline - 0.05 then
			self:armTimer(token) -- clock was extended (More Time)
			return
		end
		self:finish(3 - self.turn, "timeout")
	end)
end

function Match:armClutchTimers(token)
	local e = self.ents[self.turn]
	if not e or not self.deadline then
		return
	end
	for _, s in ipairs(e.slots or {}) do
		if s.kind and s.kind ~= "Empty" and s.state == "locked" and s.fastAt then
			local delaySec = (self.deadline - s.fastAt) - now()
			if delaySec > 0 then
				task.delay(delaySec, function()
					if not self.active or self.token ~= token then
						return
					end
					if s.state == "locked" and self.ents[self.turn] == e then
						s.state = "empty"
						if self:canFill(e, s.kind) then
							s.state = "ready"
						end
						send(e, "SlotOpened", { kind = s.kind, clock = s.fastAt })
						self:pushState()
					end
				end)
			else
				s.state = "empty"
				if self:canFill(e, s.kind) then
					s.state = "ready"
				end
				send(e, "SlotOpened", { kind = s.kind, clock = s.fastAt })
			end
		end
	end
end

function Match:startTurn()
	if not self.active then
		return
	end
	self.token += 1
	local token = self.token
	local e = self.ents[self.turn]
	e.ownTurns += 1

	self:updateLocks()
	-- practically never happens: nothing at all keeps a letter in place -> deal a fresh word
	if #self:candidates() == 0 then
		self.lockLetters = nil
		local fresh
		for _ = 1, 20 do
			fresh = Dictionary.StartWord(#self.word)
			if not self.used[fresh] then
				break
			end
		end
		self.word = fresh
		self.used[fresh] = true
		table.insert(self.history, fresh)
		self:broadcast("Toast", "No words left - fresh word: " .. string.upper(fresh))
	end

	self.turnTime = self.tutorial and Config.TutorialTurnTime or Config.TurnTime(self.volley, self.startClock)
	if e.timeShield and e.timeShield > 0 then
		local bonus = e.timeShield
		e.timeShield = 0
		self.turnTime += bonus
		self:broadcast("TimeShieldActive", { by = e.name, added = bonus })
	end
	for _, ent in ipairs(self.ents) do
		self:refreshSlots(ent, ent == e)
	end
	self.deadline = now() + self.turnTime
	Arena.SetClock(self.table, self.turn)
	Arena.SetTimer(self.table, self.deadline)
	Arena.SetDisplay(self.table, self.word, self.table.namesLabel.Text)
	self:pushState()

	self:armTimer(token)
	self:armClutchTimers(token)
	if e.kind == "bot" then
		self:botThink(token)
	elseif self.tutorial and e.words ~= 1 then
		-- tutorial: suggest a good word every turn (except when teaching the Hint power-up)
		local w, pts = self:bestMove()
		if w then
			send(e, "Hint", { word = w, points = pts, coach = true })
		end
	end
end

function Match:reject(e, reason)
	send(e, "Invalid", reason)
end

function Match:applyMove(e, w)
	local old = self.word
	local pts = points(old, w)
	if e.doublePoints then
		pts *= 2
		e.doublePoints = false
	end
	self.word = w
	self.used[w] = true
	table.insert(self.history, w)
	self.volley += 1
	e.words += 1
	e.score += pts

	-- Score Time Shield: scoring a 5+ pt word banks +2.0s buffer for your next turn
	if pts >= 5 then
		e.timeShield = math.min(4.0, (e.timeShield or 0) + 2.0)
		self:broadcast("TimeShieldEarned", { by = e.name, added = 2.0, pts = pts, total = e.timeShield })
	end

	local remaining = self.deadline and math.max(0, self.deadline - now()) or 0
	local clockFrac = (self.turnTime and self.turnTime > 0) and (remaining / self.turnTime) or 0
	local isFast = clockFrac >= 0.5

	local rare = Dictionary.IsRare(w)
	local biblical = Config.IsBiblical(w)
	if e.player then
		local p = PlayerData.Get(e.player)
		if p then
			p.wordsPlayed += 1
			p.coins += Config.Reward.WordCoins + (biblical and 10 or 0)
			if isFast then
				p.fastPlays = (p.fastPlays or 0) + 1
			end
			e.longRun = (#w >= Config.LongWordLength) and (e.longRun + 1) or 0
			PlayerData.WordPlayed(e.player, w, e.longRun)
			if rare then
				p.rareWords += 1
			end
			local bonusXP = (rare and Config.Reward.BrilliantXP or 0) + (biblical and 25 or 0)
			PlayerData.AddXP(e.player, Config.Reward.WordXP + bonusXP, false)
			if rare then
				PlayerData.AddShards(e.player, Config.Reward.BrilliantShards)
			end
			PlayerData.CheckAchievements(e.player)
			PlayerData.Changed(e.player)
		end
	end

	local wLen = #w
	if wLen >= Config.LongWordLength and not self.firstBigWordDone then
		self.firstBigWordDone = true
		if e.player then
			PlayerData.Reward(e.player, "award", "FIRST BIG WORD", string.upper(w) .. " (" .. wLen .. " letters • First in match)", { coins = 25 })
		end
		self:broadcast("FirstBigWord", { by = e.name, word = w, len = wLen })
	end

	if wLen > self.biggestWordLen then
		self.biggestWordLen = wLen
		self.biggestWord = w
		self.biggestWordPlayer = e.player
		self.biggestWordPlayerName = e.name
	end
	if biblical then
		self:broadcast("Blessed", { word = w, by = e.name })
	elseif rare then
		self:broadcast("Brilliant", { word = w, by = e.name })
	end
	self:broadcast("Played", { word = w, by = e.name, from = old, points = pts, long = #w >= Config.LongWordLength, volley = self.volley, clockFrac = clockFrac, isFast = isFast })

	if self.tutorial and e.kind == "player" and e.words >= Config.TutorialMoves then
		self:pushState()
		self:finish(e.side, "tutorial")
		return
	end
	self.turn = 3 - self.turn
	self:startTurn()
end

function Match:submit(player, raw)
	local e = self.ents[self.turn]
	if not self.active then
		return
	end
	if e.player ~= player then
		local me = self.ents[1].player == player and self.ents[1] or self.ents[2]
		return self:reject(me, "Not your turn.")
	end
	if not self.deadline then
		return self:reject(e, "Get ready - the clock hasn't started.")
	end
	if self.checking then
		return
	end
	local w = WordRules.Normalize(raw)
	if not w or #w < MIN_LEN or #w > MAX_LEN then
		return self:reject(e, "Use a word of " .. MIN_LEN .. " to " .. MAX_LEN .. " letters.")
	end
	if w == self.word then
		return self:reject(e, "Play a different word.")
	end
	if self.used[w] then
		return self:reject(e, string.upper(w) .. " was already played this match.")
	end
	if kept(self.word, w) < 1 then
		return self:reject(e, "Keep at least one letter in the same spot as " .. string.upper(self.word) .. ".")
	end
	if self:hitsLock(w) then
		local shown = {}
		for _, ch in ipairs(self.lockLetters) do
			table.insert(shown, string.upper(ch))
		end
		return self:reject(e, table.concat(shown, " and ") .. (#shown == 1 and " is" or " are") .. " locked this turn - no words with " .. (#shown == 1 and "it" or "them") .. ".")
	end
	if WordRules.IsInflection(self.word, w) then
		return self:reject(e, "Tense or plural of " .. string.upper(self.word) .. " is not allowed.")
	end
	if WordRules.IsSuffixManipulation(self.word, w) then
		return self:reject(e, "Derivative form of " .. string.upper(self.word) .. " is not allowed.")
	end
	if not Dictionary.IsWord(w) then
		return self:reject(e, string.upper(w) .. " is not in the dictionary.")
	end
	self.checking = true
	local token = self.token
	local allowed = Dictionary.IsAllowed(w, player.UserId)
	self.checking = false
	if not self.active or self.token ~= token then
		return
	end
	if not allowed then
		return self:reject(e, "That word is not allowed.")
	end
	if now() > self.deadline + 0.25 then
		return -- too late; timer resolves it
	end
	self:applyMove(e, w)
end

function Match:useItem(player, kind)
	if not self.active then
		return
	end
	local e = self.ents[self.turn]
	local me = self.ents[1].player == player and self.ents[1] or self.ents[2]
	if e ~= me then
		return self:reject(me, "Boosts can only be used on your turn.")
	end
	if not self.deadline then
		return self:reject(me, "Get ready - the clock hasn't started.")
	end
	local slot
	local timeLeft = self.deadline and math.max(0, self.deadline - now()) or 0
	for _, s in ipairs(e.slots) do
		if s.kind == kind then
			if s.state == "locked" and s.fastAt and (timeLeft <= s.fastAt + 0.5 or (self.turnTime and self.turnTime <= s.fastAt)) then
				s.state = "empty"
				if self:canFill(e, s.kind) then
					s.state = "ready"
				end
			end
			if s.state == "ready" then
				slot = s
				break
			end
		end
	end
	if not slot then
		return self:reject(e, "That boost isn't ready yet.")
	end
	local p = PlayerData.Get(player)
	if not self.tutorial and (not p or (p.inventory[kind] or 0) < 1) then
		return self:reject(e, "You don't have any " .. Config.Items[kind].name .. " left.")
	end

	if kind == "Help" then
		if e.helpUsed >= Config.HelpMaxPerMatch then
			return self:reject(e, "Max " .. Config.HelpMaxPerMatch .. " Hints per match.")
		end
		if e.ownTurns - e.lastHelpTurn < Config.HelpCooldownTurns then
			return self:reject(e, "Hint can't be used two turns in a row.")
		end
		local w, pts = self:bestMove()
		if not w then
			return self:reject(e, "No hint available.")
		end
		send(e, "Hint", { word = w, points = pts })
		e.helpUsed += 1
		e.lastHelpTurn = e.ownTurns
	elseif kind == "Time" then
		self.deadline += Config.TimeBoostSeconds
		self.turnTime += Config.TimeBoostSeconds
		Arena.SetTimer(self.table, self.deadline)
	elseif kind == "DoubleShift" then
		if e.doublePoints then
			return self:reject(e, "Double Points is already active.")
		end
		e.doublePoints = true
	elseif kind ~= "Skip" then
		return
	end

	-- consume: the slot starts refilling (free in the tutorial)
	slot.state = "cooldown"
	slot.readyIn = self.tutorial and 1 or Config.ItemRefillTurns
	if not self.tutorial then
		p.inventory[kind] -= 1
		PlayerData.Changed(player)
	end
	self:broadcast("Toast", e.name .. " used " .. Config.Items[kind].name .. "!")

	if kind == "Skip" then
		self.volley += 1
		self.turn = 3 - self.turn
		self:startTurn()
	else
		self:pushState()
	end
end

-- bots ------------------------------------------------------------------------
-- Bots think like people: quick early, slower and more error-prone as the clock shrinks.
-- Stronger bots answer faster, keep more letters (higher scores) and slip less.
-- how long a bot "thinks": a slice of its clock (weaker bots use more of it), always
-- finishing at least 0.6s before its time runs out
function Match:botDelay(e)
	if e.tutorial then
		return 1.4 + math.random() * 0.8
	end
	local t = self.turnTime
	local frac = 0.12 + math.random() ^ 1.6 * (0.4 - 0.25 * e.skill)
	local d = math.max(0.8, t * frac + math.random() * 0.5)
	return math.min(d, t - 0.6)
end

-- chance a bot blanks this turn (how you beat it): grows slowly as the rally speeds up
function Match:botSlipChance(e)
	if e.tutorial then
		return 0
	end
	local slip = math.clamp(0.01 + self.volley * 0.004 - e.skill * 0.02, 0.005, 0.25)
	if not e.disguised then
		slip *= 0.6 -- practice bots are a bit kinder
	end
	return slip
end

function Match:botThink(token)
	local e = self.ents[self.turn]
	if math.random() < self:botSlipChance(e) then
		return -- freezes; the clock decides
	end
	local delay = self:botDelay(e)
	task.delay(delay, function()
		if not self.active or self.token ~= token then
			return
		end
		local w = self:botMove(e)
		if w and self.active and self.token == token then
			self:applyMove(e, w)
		end
	end)
end

function Match:botMove(e)
	local cands = self:candidates()
	if #cands == 0 then
		return nil
	end
	-- people mostly play everyday words; strong players squeeze out more kept letters
	local common = {}
	for _, c in ipairs(cands) do
		if Dictionary.IsCommon(c.w) then
			table.insert(common, c)
		end
	end
	local pool = #common > 0 and common or cands
	-- people mostly stay near the current length (grow or shrink by at most one letter)
	local near = {}
	for _, c in ipairs(pool) do
		if math.abs(#c.w - #self.word) <= 1 then
			table.insert(near, c)
		end
	end
	if #near > 0 then
		pool = near
	end
	local want = 1
	if not e.tutorial then
		local maxPts = 0
		for _, c in ipairs(pool) do
			maxPts = math.max(maxPts, c.pts)
		end
		if math.random() < 0.3 + 0.6 * e.skill then
			want = maxPts
		else
			want = math.random(1, math.max(1, maxPts))
		end
	end
	local pick = {}
	for _, c in ipairs(pool) do
		if c.pts >= want then
			table.insert(pick, c)
		end
	end
	if #pick == 0 then
		pick = pool
	end
	for _ = 1, 8 do
		local c = pick[math.random(#pick)]
		if Dictionary.IsAllowed(c.w) then
			return c.w
		end
	end
	return nil
end

-- ending ------------------------------------------------------------------------
function Match:finish(winnerSide, reason)
	if not self.active then
		return
	end
	self.active = false
	self.token += 1
	local winner, loser = self.ents[winnerSide], self.ents[3 - winnerSide]
	for _, e in ipairs(self.ents) do
		if e.player and Match.ByPlayer[e.player] == self then
			Match.ByPlayer[e.player] = nil
		end
	end
	Arena.SetClock(self.table, 0)
	Arena.SetTimer(self.table, nil)
	-- bot avatars leave with the loser/table reset
	for _, e in ipairs(self.ents) do
		if e.kind == "bot" and e.rig then
			local rig = e.rig
			task.delay(2.6, function()
				if rig.Parent then
					rig:Destroy()
				end
			end)
		end
	end
	if self.onEnd then
		self.onEnd(self, winner, loser, reason)
	end
end

function Match:forfeit(player)
	for _, e in ipairs(self.ents) do
		if e.player == player then
			self:finish(3 - e.side, "left")
			return
		end
	end
end

return Match
