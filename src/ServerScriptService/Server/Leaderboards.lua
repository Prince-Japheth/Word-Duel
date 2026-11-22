-- Leaderboards: global Elo and Longest Streak via OrderedDataStore, cached top 10.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Leaderboards = {}

local boards = {}
do
	local ok = pcall(function()
		boards.elo = DataStoreService:GetOrderedDataStore("WordDuel_Elo_v1")
		boards.streak = DataStoreService:GetOrderedDataStore("WordDuel_Streak_v1")
		boards.longest = DataStoreService:GetOrderedDataStore("WordDuel_LongestWord_v1")
		boards.longrun = DataStoreService:GetOrderedDataStore("WordDuel_LongRun_v1")
		boards.longwords = DataStoreService:GetOrderedDataStore("WordDuel_LongWords_v1")
		boards.score = DataStoreService:GetOrderedDataStore("WordDuel_BestScore_v1")
	end)
	if not ok then
		boards = {}
	end
end

local cache = { elo = {}, streak = {}, longest = {}, longrun = {}, longwords = {}, score = {} }
-- which profile field feeds each board
local FIELD = { elo = "elo", streak = "bestStreak", longest = "bestWordLen", longrun = "longStreakBest", longwords = "longWords", score = "bestScore" }
local nameCache = {}
local lastSubmit = {} -- [userId] = os.clock()

local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("User " .. userId)
	return nameCache[userId]
end

function Leaderboards.Submit(player, profile, force)
	if not boards.elo then
		return
	end
	local uid = player.UserId
	if uid <= 0 then
		return -- Studio test players
	end
	-- throttle writes per player (forced on leave so the final value lands)
	if not force and lastSubmit[uid] and os.clock() - lastSubmit[uid] < 20 then
		return
	end
	lastSubmit[uid] = os.clock()
	task.spawn(function()
		pcall(function()
			for key, store in pairs(boards) do
				store:SetAsync(tostring(uid), math.floor(profile[FIELD[key]] or 0))
			end
		end)
	end)
end

local function refresh()
	for key, store in pairs(boards) do
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if ok then
			local list = {}
			for rank, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(entry.key)
				table.insert(list, { rank = rank, name = uid and nameOf(uid) or entry.key, value = entry.value })
			end
			cache[key] = list
		end
	end
end

function Leaderboards.Get()
	return cache
end

task.spawn(function()
	while true do
		pcall(refresh)
		task.wait(60)
	end
end)

return Leaderboards
