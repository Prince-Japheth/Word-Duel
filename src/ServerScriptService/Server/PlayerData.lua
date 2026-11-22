-- PlayerData: loads/saves profiles, XP/levels, inventory, achievements, daily streak.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local PlayerData = {}
PlayerData.OnChanged = nil -- function(player, profile) set by Main
PlayerData.OnToast = nil -- function(player, text) set by Main
PlayerData.OnLevelUp = nil -- function(player, profile) set by Main
PlayerData.OnReward = nil -- function(player, payload) set by Main: the big reward popup

local STORE_NAME = "WordDuel_Profiles_v1"
local store
do
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = res
	else
		warn("[WordDuel] DataStore unavailable, progress will not save:", res)
	end
end

local profiles = {} -- [player] = profile
local canSave = {} -- [player] = bool (false if load failed, so we never overwrite real data)

local function template()
	local inv = {}
	for k, v in pairs(Config.StartingInventory) do
		inv[k] = v
	end
	return {
		xp = 15, -- Endowed Progress Effect: head start towards Level 2
		level = 1,
		elo = Config.StartElo,
		coins = 0,
		shards = 0,
		wins = 0,
		losses = 0,
		matches = 0,
		curStreak = 0,
		bestStreak = 0,
		wordsPlayed = 0,
		rareWords = 0,
		inventory = inv,
		belt = { "Help", "Time", "Skip" },
		slotsBought = 0,
		achievements = {},
		dailyDay = 0,
		dailyStreak = 0,
		referredBy = 0,
		referralPaid = false,
		tutorialDone = false,
		bestWordLen = 0,
		bestWord = "",
		longWords = 0,
		longStreakBest = 0,
		bestScore = 0,
		totalScore = 0,
		fastPlays = 0,
		ladderDay = 0,
		ladderStreak = 0,
		ladderSteps = 0,
		ladderSolves = 0,
		receipts = {},
	}
end

local function reconcile(data, tmpl)
	for k, v in pairs(tmpl) do
		if data[k] == nil then
			data[k] = v
		elseif type(v) == "table" and type(data[k]) == "table" and k == "inventory" then
			reconcile(data[k], v)
		end
	end
	return data
end

local function key(player)
	return "u_" .. player.UserId
end

function PlayerData.Load(player)
	local data, ok = nil, false
	if store then
		for attempt = 1, 3 do
			local success, res = pcall(function()
				return store:GetAsync(key(player))
			end)
			if success then
				data, ok = res, true
				break
			end
			warn("[WordDuel] load failed", attempt, res)
			task.wait(1.5 * attempt)
		end
	end
	if not player.Parent then
		return nil
	end
	local profile = reconcile(type(data) == "table" and data or template(), template())
	if profile.belt and #profile.belt < 3 then
		profile.belt[2] = profile.belt[2] or "Time"
		profile.belt[3] = profile.belt[3] or "Skip"
	end
	if RunService:IsStudio() then
		profile.tutorialDone = false
		profile.dailyDay = 0
	end
	profiles[player] = profile
	canSave[player] = ok
	if store and not ok then
		PlayerData.Toast(player, "Could not load your save. Progress this session will NOT be saved.")
	end
	return profile
end

-- Returns true when the profile is safely stored. In an unpublished Studio place there is
-- no DataStore at all; that counts as success so purchases can be tested.
function PlayerData.Save(player)
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not store then
		return RunService:IsStudio()
	end
	if not canSave[player] then
		return false
	end
	local success, err
	for attempt = 1, 3 do
		success, err = pcall(function()
			store:UpdateAsync(key(player), function()
				return profile
			end)
		end)
		if success then
			return true
		end
		task.wait(attempt)
	end
	warn("[WordDuel] save failed for", player.Name, err)
	return false
end

-- Studio-only test hook: swap in a fake store (table with GetAsync/UpdateAsync) to test saving.
function PlayerData._UseStoreForTesting(fake)
	if RunService:IsStudio() then
		store = fake
	end
end

function PlayerData.Release(player)
	PlayerData.Save(player)
	profiles[player] = nil
	canSave[player] = nil
end

function PlayerData.Get(player)
	return profiles[player]
end

function PlayerData.Toast(player, text)
	if PlayerData.OnToast then
		PlayerData.OnToast(player, text)
	end
end

function PlayerData.Changed(player)
	local p = profiles[player]
	if p and PlayerData.OnChanged then
		PlayerData.OnChanged(player, p)
	end
end

function PlayerData.Slots(profile)
	return Config.SlotsFor(profile.level, profile.slotsBought)
end

-- grant = { coins = n, Help = n, ... }
function PlayerData.Grant(player, grant, silent)
	local p = profiles[player]
	if not p or not grant then
		return
	end
	local parts = {}
	for k, v in pairs(grant) do
		if k == "coins" then
			p.coins += v
			table.insert(parts, "+" .. v .. " coins")
		elseif Config.Items[k] then
			p.inventory[k] = (p.inventory[k] or 0) + v
			table.insert(parts, "+" .. v .. " " .. Config.Items[k].name)
		end
	end
	if not silent and #parts > 0 and PlayerData.OnReward then
		PlayerData.OnReward(player, { kind = "bonus", title = table.concat(parts, "  "), sub = "Added to your stash", items = parts, grant = grant })
	end
	PlayerData.Changed(player)
	return parts
end

-- Give something AND make it noticed: a big popup with sound on the player's screen.
-- kind: "daily" | "award" | "level" | "record" | "streak" | "shards" | "bonus"
function PlayerData.Reward(player, kind, title, sub, grant)
	local items = grant and PlayerData.Grant(player, grant, true) or {}
	if PlayerData.OnReward then
		PlayerData.OnReward(player, { kind = kind, title = title, sub = sub, items = items, grant = grant })
	end
end

local function statValue(p, stat)
	return p[stat] or 0
end

function PlayerData.CheckAchievements(player)
	local p = profiles[player]
	if not p then
		return
	end
	for _, a in ipairs(Config.Achievements) do
		if not p.achievements[a.id] and statValue(p, a.stat) >= a.goal then
			p.achievements[a.id] = os.time()
			PlayerData.Reward(player, "award", a.name, a.desc, a.reward)
		end
	end
end

function PlayerData.AddXP(player, amount, allowLevelUp)
	if allowLevelUp ~= true then
		allowLevelUp = false
	end
	local p = profiles[player]
	if not p or amount <= 0 then
		return
	end
	if not allowLevelUp then
		local needed = Config.XPToNext(p.level)
		if p.xp + amount >= needed then
			p.xp = math.max(p.xp, needed - 1)
		else
			p.xp += amount
		end
		PlayerData.Changed(player)
		return
	end
	p.xp += amount
	local leveled = false
	local oldSlots = PlayerData.Slots(p)
	while p.xp >= Config.XPToNext(p.level) do
		p.xp -= Config.XPToNext(p.level)
		p.level += 1
		leveled = true
	end
	if leveled then
		local sub = "You're getting stronger"
		if PlayerData.Slots(p) > oldSlots then
			sub = "New boost slot on your belt"
		end
		PlayerData.Reward(player, "level", "LEVEL " .. p.level, sub)
		PlayerData.CheckAchievements(player)
		if PlayerData.OnLevelUp then
			PlayerData.OnLevelUp(player, p)
		end
	end
	PlayerData.Changed(player)
end

-- personal records -------------------------------------------------------------
-- (silent the very first time a stat is set, so a new player isn't spammed)
local function record(player, title, sub)
	PlayerData.Reward(player, "record", title, sub, nil)
end

function PlayerData.CheckScoreRecord(player, score)
	local p = profiles[player]
	if not p or not score or score <= p.bestScore then
		return
	end
	local had = p.bestScore > 0
	p.bestScore = score
	if had then
		record(player, score .. " POINTS", "Best score in one match")
	end
	PlayerData.CheckAchievements(player)
end

-- called for every word a player plays; longRun = their long words in a row this match
function PlayerData.WordPlayed(player, word, longRun)
	local p = profiles[player]
	if not p then
		return
	end
	local len = #word
	if len >= Config.LongWordLength then
		p.longWords += 1
	end
	if len > p.bestWordLen then
		local had = p.bestWordLen >= 3
		p.bestWordLen = len
		p.bestWord = word
		if had then
			record(player, string.upper(word), "Longest word - " .. len .. " letters")
		end
	end
	if longRun > p.longStreakBest then
		p.longStreakBest = longRun
		if longRun >= 2 then
			record(player, longRun .. " IN A ROW", "Long words in a row")
		end
	end
end

-- 5 Brilliant shards -> 1 Help
function PlayerData.AddShards(player, n)
	local p = profiles[player]
	if not p then
		return
	end
	p.shards += n
	while p.shards >= Config.ShardsPerHelp do
		p.shards -= Config.ShardsPerHelp
		p.inventory.Help += 1
		if PlayerData.OnReward then
			PlayerData.OnReward(player, { kind = "shards", title = "+1 HINT", sub = Config.ShardsPerHelp .. " shards combined", items = { "+1 Hint" }, grant = { Help = 1 } })
		end
	end
	PlayerData.Changed(player)
end

-- Daily login streak chest
function PlayerData.Daily(player)
	local p = profiles[player]
	if not p then
		return
	end
	local today = math.floor(os.time() / 86400)
	if p.dailyDay == today then
		return
	end
	if p.dailyDay == today - 1 then
		p.dailyStreak += 1
	else
		p.dailyStreak = 1
	end
	p.dailyDay = today
	local grant = { coins = 40 + 10 * math.min(p.dailyStreak, 10) }
	if p.dailyStreak % 14 == 0 then
		grant.DoubleShift = 1
	elseif p.dailyStreak % 7 == 0 then
		grant.Help = 1
	end
	PlayerData.Reward(player, "daily", "DAY " .. p.dailyStreak, "Come back tomorrow for more", grant)
	PlayerData.CheckAchievements(player)
end

-- autosave loop
task.spawn(function()
	while true do
		task.wait(120)
		for _, plr in ipairs(Players:GetPlayers()) do
			task.spawn(PlayerData.Save, plr)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerData.Save, plr)
	end
	task.wait(3)
end)

return PlayerData
