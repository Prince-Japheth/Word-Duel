-- Word Duel: shared tuning values. Edit numbers here, not in game code.
local Config = {}

---------------------------------------------------------------- clock
-- The clock speeds up every move like Piano Tiles, but the speed-up itself eases off:
-- big steps early, smaller and smaller steps later, and it never goes below the floor.
Config.StartTurnTime = 12        -- level 1: seconds for the first turn of a match
Config.StartTurnTimeMin = 8      -- the fastest any match ever STARTS (high levels)
Config.StartSpeedupPerLevel = 0.1 -- each level starts 0.1s faster, down to StartTurnTimeMin
Config.ClockEase = 18            -- bigger = gentler speed-up (moves to cover ~63% of the way to the floor)
Config.MinTurnTime = 3.5         -- hard floor so it never becomes impossible
Config.KingMomentumBonus = 2     -- after a win, the next challenger starts this much slower than your winning pace
Config.DeadlockBuffer = 2      -- bonus seconds when the server forces a multi-letter escape
Config.TimeBoostSeconds = 5    -- "More Time" item
Config.ContinueChoiceSeconds = 5 -- after a ranked win: seconds to Leave Table before the next challenger

---------------------------------------------------------------- helps
Config.HelpMaxPerMatch = 2
Config.HelpCooldownTurns = 2   -- Help cannot be used on two of your own turns in a row
Config.ShardsPerHelp = 5       -- Brilliant Move shards that convert into 1 Help

---------------------------------------------------------------- matchmaking
Config.BaseBracket = 5         -- +/- levels
Config.BracketWiden = 5        -- extra levels allowed ...
Config.BracketWidenEvery = 10  -- ... per this many seconds waiting
Config.BotOfferAfter = 12      -- seconds in queue before "Practice vs Bot" is offered
-- nobody waits: if no human is found, a human-like bot fills the seat after a few seconds
Config.BotFillMin = 3
Config.BotFillMax = 7
Config.KingFillMin = 6         -- a King waiting this long gets a challenger anyway
Config.KingFillMax = 12
Config.TableCount = 8

---------------------------------------------------------------- rewards
Config.RareLetters = { q = true, z = true, x = true, j = true }
Config.Reward = {
	WordXP = 2,
	WordCoins = 1,
	BrilliantXP = 25,
	BrilliantShards = 1,
	WinXP = 40,
	WinStreakXP = 10,  -- per current King streak
	WinCoins = 20,
	LossXP = 15,
	LossCoins = 5,
	BotWinXP = 10,
	BotWinCoins = 5,
}
-- points (letters kept in place) pay a bonus at the end of every match
Config.ScoreCoinRate = 1
Config.ScoreCoinCap = 1000 -- uncapped direct scaling: every point equals 1 coin
-- Letter locks: at high level, once a rally is fast, 1-2 letters are sometimes banned for a
-- few turns in a row (different letters each turn), then they go away for a while
Config.LetterLockLevel = 15      -- average level of the two players
Config.LetterLockVolley = 12     -- the rally must already be this many moves in
Config.LetterLockChance = 0.3    -- chance per turn that a lock spell starts
Config.LetterLockRun = { 2, 4 }  -- a spell lasts this many turns
Config.LetterLockCooldown = { 4, 8 } -- quiet turns before another spell can start
Config.LetterLockMinMoves = 15   -- never lock so hard that fewer legal words remain

-- a "long word" for records and awards
Config.LongWordLength = 7
Config.EloK = 32
Config.StartElo = 1000

-- King-of-the-Table win streak milestones (free lifelines for free players)
Config.StreakMilestones = {
	[5] = { Help = 1 },
	[10] = { Help = 1, Time = 1 },
	[25] = { Help = 2, DoubleShift = 1 },
}

-- Daily Ladder: one shared solo puzzle a day (4-letter start -> target)
Config.LadderMinPar = 4
Config.LadderMaxPar = 6
Config.LadderReward = { coins = 40, parBonus = 40, perStreak = 5, xp = 20 } -- first solve each day

-- first-time tutorial: a relaxed match against a coach
Config.TutorialTurnTime = 45
Config.TutorialMoves = 4
Config.TutorialReward = { coins = 100, Help = 1 }

Config.ReferralLevel = 3
Config.ReferralBundle = { Help = 3, Time = 3 }

---------------------------------------------------------------- items
Config.ItemOrder = { "Help", "Skip", "Time", "DoubleShift" }
Config.Items = {
	-- keys stay the same (saves + Robux products); names are what players see
	Help = { name = "Hint", desc = "Shows you a word that scores. Max 2 per match, not two turns in a row." },
	Skip = { name = "Pass", desc = "Hand the same word back to your rival." },
	Time = { name = "Time Boost", desc = "+5 seconds on your clock." },
	DoubleShift = { name = "Double Points", desc = "Your next word scores double." },
}
-- Natural (non-Robux) way to get items: coins earned from playing.
Config.CoinPrices = { Help = 250, Skip = 350, Time = 200, DoubleShift = 600 }
Config.SlotCoinPrices = { [2] = 1500, [3] = 5000, [4] = 15000 }
Config.StartingInventory = { Help = 3, Skip = 1, Time = 2, DoubleShift = 0 }

-- Loadout belt: how many boost uses you can bring into ONE match.
Config.MaxSlots = 4
-- Absolute hard cap on belt slots: players cannot have more than 9 slots under any circumstances.
Config.AbsoluteMaxSlots = 9
-- Fast-game slots: 2 extra belt slots that only open mid-match when the clock gets this short
Config.FastSlotClocks = { 7, 5 }
-- a used boost's slot refills from what you own after this many of your turns
Config.ItemRefillTurns = 3
Config.SlotLevels = { [2] = 20, [3] = 50, [4] = 100 } -- free unlock by level

---------------------------------------------------------------- Robux products
-- Create each Developer Product on the Creator Dashboard, then paste its id here.
-- id = 0 means "not created yet". In Studio, id 0 grants for free so you can test.
Config.Products = {
	-- Coin packs (top up currency)
	{ key = "Coins1000", id = 0, robux = 49, label = "1,000 Coins", grant = { coins = 1000 }, isCoins = true },
	{ key = "Coins5000", id = 0, robux = 199, label = "5,000 Coins", grant = { coins = 5000 }, isCoins = true },
	{ key = "Coins15000", id = 0, robux = 499, label = "15,000 Coins", grant = { coins = 15000 }, isCoins = true },
	{ key = "Coins50000", id = 0, robux = 1299, label = "50,000 Coins", grant = { coins = 50000 }, isCoins = true },

	-- Boost packs
	{ key = "Help3", id = 0, robux = 49, label = "3 Hints", grant = { Help = 3 } },
	{ key = "Help10", id = 0, robux = 129, label = "10 Hints", grant = { Help = 10 } },
	{ key = "Skip3", id = 0, robux = 49, label = "3 Passes", grant = { Skip = 3 } },
	{ key = "Time5", id = 0, robux = 49, label = "5 Time Boosts", grant = { Time = 5 } },
	{ key = "Double1", id = 0, robux = 79, label = "1 Double Points", grant = { DoubleShift = 1 } },
	{ key = "Double5", id = 0, robux = 299, label = "5 Double Points", grant = { DoubleShift = 5 } },
	{ key = "Slot2", id = 0, robux = 399, label = "Boost Slot 2", slot = 2 },
	{ key = "Slot3", id = 0, robux = 899, label = "Boost Slot 3", slot = 3 },
	{ key = "Slot4", id = 0, robux = 1499, label = "Boost Slot 4", slot = 4 },
}

---------------------------------------------------------------- ranks (by Elo)
Config.Ranks = {
	{ name = "Bronze", min = 0, color = Color3.fromRGB(176, 120, 72) },
	{ name = "Silver", min = 1100, color = Color3.fromRGB(190, 196, 204) },
	{ name = "Gold", min = 1250, color = Color3.fromRGB(240, 196, 60) },
	{ name = "Platinum", min = 1400, color = Color3.fromRGB(110, 220, 210) },
	{ name = "Diamond", min = 1600, color = Color3.fromRGB(120, 160, 255) },
	{ name = "Grandmaster", min = 1800, color = Color3.fromRGB(235, 80, 90) },
}

---------------------------------------------------------------- achievements (permanent milestones)
-- stat = profile field path, goal = value, reward = coins/items granted once.
Config.Achievements = {
	-- Wins
	{ id = "first_win", name = "First Blood", desc = "Win a ranked match.", stat = "wins", goal = 1, reward = { coins = 100 } },
	{ id = "wins_10", name = "Getting Started", desc = "Win 10 ranked matches.", stat = "wins", goal = 10, reward = { coins = 150 } },
	{ id = "wins_25", name = "Table Regular", desc = "Win 25 ranked matches.", stat = "wins", goal = 25, reward = { coins = 300, Help = 1 } },
	{ id = "wins_50", name = "Contender", desc = "Win 50 ranked matches.", stat = "wins", goal = 50, reward = { coins = 500, Help = 1 } },
	{ id = "wins_100", name = "Clock Slammer", desc = "Win 100 ranked matches.", stat = "wins", goal = 100, reward = { coins = 1000, DoubleShift = 1 } },
	{ id = "wins_250", name = "Word Legend", desc = "Win 250 ranked matches.", stat = "wins", goal = 250, reward = { coins = 2000, DoubleShift = 2 } },

	-- King Streaks
	{ id = "streak_3", name = "Triple Threat", desc = "Hold the table for 3 wins in a row.", stat = "bestStreak", goal = 3, reward = { coins = 100 } },
	{ id = "streak_5", name = "Hot Seat", desc = "Hold the table for 5 wins in a row.", stat = "bestStreak", goal = 5, reward = { coins = 200 } },
	{ id = "streak_10", name = "Untouchable", desc = "Hold the table for 10 wins in a row.", stat = "bestStreak", goal = 10, reward = { coins = 500, Help = 1 } },
	{ id = "streak_15", name = "15-Win Blitz Streak", desc = "Hold the table for 15 wins in a row.", stat = "bestStreak", goal = 15, reward = { coins = 1000, DoubleShift = 1 } },
	{ id = "streak_25", name = "Legendary King", desc = "Hold the table for 25 wins in a row.", stat = "bestStreak", goal = 25, reward = { coins = 2000, DoubleShift = 2 } },

	-- Words Played
	{ id = "words_100", name = "Wordsmith", desc = "Play 100 words.", stat = "wordsPlayed", goal = 100, reward = { coins = 150 } },
	{ id = "words_500", name = "Vocabulary Builder", desc = "Play 500 words.", stat = "wordsPlayed", goal = 500, reward = { coins = 400, Help = 1 } },
	{ id = "words_1000", name = "Lexicon", desc = "Play 1000 words.", stat = "wordsPlayed", goal = 1000, reward = { coins = 800, Help = 2 } },

	-- Rare Letters (Q, Z, X, J)
	{ id = "rare_10", name = "Grandmaster Vocabulary", desc = "Play 10 words with Q, Z, X or J.", stat = "rareWords", goal = 10, reward = { coins = 400, Help = 1 } },
	{ id = "rare_25", name = "Rare Letter Hunter", desc = "Play 25 words with Q, Z, X or J.", stat = "rareWords", goal = 25, reward = { coins = 800 } },
	{ id = "rare_50", name = "Scrabble Shark", desc = "Play 50 words with Q, Z, X or J.", stat = "rareWords", goal = 50, reward = { coins = 1500, DoubleShift = 1 } },

	-- Levels (earned from wins!)
	{ id = "level_5", name = "Beginner", desc = "Reach level 5.", stat = "level", goal = 5, reward = { coins = 100 } },
	{ id = "level_10", name = "Apprentice", desc = "Reach level 10.", stat = "level", goal = 10, reward = { coins = 250 } },
	{ id = "level_20", name = "Skilled", desc = "Reach level 20.", stat = "level", goal = 20, reward = { coins = 500, Help = 1 } },
	{ id = "level_30", name = "Veteran", desc = "Reach level 30.", stat = "level", goal = 30, reward = { coins = 1000, Help = 2 } },
	{ id = "level_50", name = "Expert", desc = "Reach level 50.", stat = "level", goal = 50, reward = { coins = 1500, DoubleShift = 1 } },

	-- Word Length milestones (career records)
	{ id = "word_8", name = "Impressive Word", desc = "Play a word of 8+ letters.", stat = "bestWordLen", goal = 8, reward = { coins = 250 } },
	{ id = "word_9", name = "Mega Word", desc = "Play a word of 9+ letters.", stat = "bestWordLen", goal = 9, reward = { coins = 400, Help = 1 } },
	{ id = "word_10", name = "Maximum Word", desc = "Play a 10-letter word.", stat = "bestWordLen", goal = 10, reward = { coins = 800, DoubleShift = 1 } },

	-- Long Word Streaks & Totals
	{ id = "longrun_3", name = "Long Chain", desc = "Play 3 long words (7+) in a row in one match.", stat = "longStreakBest", goal = 3, reward = { coins = 300 } },
	{ id = "longrun_5", name = "Endless Vocabulary", desc = "Play 5 long words in a row in one match.", stat = "longStreakBest", goal = 5, reward = { coins = 800, Help = 2 } },
	{ id = "long_25", name = "Long-Word Collector", desc = "Play 25 long words (7+ letters).", stat = "longWords", goal = 25, reward = { coins = 250 } },
	{ id = "long_50", name = "Eloquent", desc = "Play 50 long words (7+ letters).", stat = "longWords", goal = 50, reward = { coins = 500 } },
	{ id = "long_100", name = "Dictionary Diver", desc = "Play 100 long words.", stat = "longWords", goal = 100, reward = { coins = 1000, Help = 2 } },

	-- Match High Scores
	{ id = "score_30", name = "High Scorer", desc = "Score 30 points in one match.", stat = "bestScore", goal = 30, reward = { coins = 200 } },
	{ id = "score_50", name = "Point Master", desc = "Score 50 points in one match.", stat = "bestScore", goal = 50, reward = { coins = 400 } },
	{ id = "score_75", name = "Score Machine", desc = "Score 75 points in one match.", stat = "bestScore", goal = 75, reward = { coins = 700, Help = 1 } },
	{ id = "score_100", name = "Century", desc = "Score 100 points in one match.", stat = "bestScore", goal = 100, reward = { coins = 1500, DoubleShift = 1 } },

	-- Career Total Score
	{ id = "total_500", name = "Point Hoarder", desc = "Score 500 total points across matches.", stat = "totalScore", goal = 500, reward = { coins = 300 } },
	{ id = "total_2000", name = "Point Machine", desc = "Score 2000 total points across matches.", stat = "totalScore", goal = 2000, reward = { coins = 1000, DoubleShift = 1 } },

	-- Speed Plays (>50% clock remaining)
	{ id = "fast_25", name = "Quick Thinker", desc = "Make 25 fast plays with >50% clock remaining.", stat = "fastPlays", goal = 25, reward = { coins = 200 } },
	{ id = "fast_100", name = "Speed Demon", desc = "Make 100 fast plays with >50% clock remaining.", stat = "fastPlays", goal = 100, reward = { coins = 800, Help = 2 } },

	-- Daily Login Streaks
	{ id = "daily_3", name = "Routine", desc = "Log in 3 days in a row.", stat = "dailyStreak", goal = 3, reward = { coins = 100 } },
	{ id = "daily_7", name = "Habit", desc = "Log in 7 days in a row.", stat = "dailyStreak", goal = 7, reward = { coins = 300, Time = 2 } },
	{ id = "daily_14", name = "Dedicated", desc = "Log in 14 days in a row.", stat = "dailyStreak", goal = 14, reward = { coins = 500, Help = 2 } },
	{ id = "daily_30", name = "Obsessed", desc = "Log in 30 days in a row.", stat = "dailyStreak", goal = 30, reward = { coins = 1500, DoubleShift = 2 } },
}

---------------------------------------------------------------- helpers
-- starting clock for a match between players of this (average) level
function Config.StartClockForLevel(level)
	return math.max(Config.StartTurnTimeMin, Config.StartTurnTime - (math.max(1, level) - 1) * Config.StartSpeedupPerLevel)
end

-- clock for move number `volley` of a match that started at `start` seconds
function Config.TurnTime(volley, start)
	start = start or Config.StartTurnTime
	return Config.MinTurnTime + (start - Config.MinTurnTime) * math.exp(-volley / Config.ClockEase)
end

-- after a win you keep your momentum: the next challenger starts near your winning pace
function Config.KingStartClock(finalClock, level)
	return math.clamp((finalClock or Config.StartTurnTime) + Config.KingMomentumBonus, Config.MinTurnTime + 1.5, Config.StartClockForLevel(level))
end

-- level 1-4: 3 letters, 5-14: 4, 15-29: 5, 30+: 6
function Config.LengthForLevel(level)
	if level < 5 then
		return 3
	elseif level < 15 then
		return 4
	elseif level < 30 then
		return 5
	end
	return 6
end

function Config.XPToNext(level)
	return 100 + (level - 1) * 25
end

function Config.RankFor(elo)
	local best = Config.Ranks[1]
	for _, r in ipairs(Config.Ranks) do
		if elo >= r.min then
			best = r
		end
	end
	return best
end

function Config.SlotsFor(level, slotsBought)
	local earned = 1
	for slot = 2, Config.MaxSlots do
		if level >= Config.SlotLevels[slot] then
			earned = slot
		end
	end
	local base = math.min(Config.MaxSlots, math.max(earned, 1 + (slotsBought or 0)))
	local maxBase = (Config.AbsoluteMaxSlots or 9) - #Config.FastSlotClocks
	return math.min(maxBase, base)
end

function Config.ProductByKey(key)
	for _, p in ipairs(Config.Products) do
		if p.key == key then
			return p
		end
	end
	return nil
end

function Config.ProductById(id)
	for _, p in ipairs(Config.Products) do
		if p.id ~= 0 and p.id == id then
			return p
		end
	end
	return nil
end

Config.BiblicalWords = {
	jesus = true, christ = true, god = true, lord = true,
	faith = true, grace = true, cross = true, holy = true,
	bible = true, pray = true, prayer = true, amen = true,
	savior = true, mercy = true, glory = true, heaven = true,
	angel = true, gospel = true, psalm = true, pastor = true,
	prophet = true, zion = true, trinity = true, redeem = true,
	shiloh = true, messiah = true, judah = true, eden = true,
	noah = true, moses = true, elijah = true, isaiah = true,
	daniel = true, blessed = true, blessing = true, hallelujah = true,
}

function Config.IsBiblical(word)
	return word ~= nil and Config.BiblicalWords[string.lower(word)] == true
end

return Config
