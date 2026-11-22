-- Word Duel server entry point: remotes, player lifecycle, request routing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = Instance.new("RemoteEvent")
Net.Name = "Net"
Net.Parent = ReplicatedStorage

local Dictionary = require(script.Parent.Dictionary)
local PlayerData = require(script.Parent.PlayerData)
local Arena = require(script.Parent.Arena)
local Match = require(script.Parent.Match)
local Leaderboards = require(script.Parent.Leaderboards)
local Lobby = require(script.Parent.Lobby)
local Shop = require(script.Parent.Shop)
local DailyLadder = require(script.Parent.DailyLadder)

print(("[WordDuel] dictionary loaded: %d words, %d tables"):format(Dictionary.Count(), #Arena.Tables))

local function send(player, action, payload)
	if typeof(player) == "Instance" and player.Parent then
		Net:FireClient(player, action, payload)
	end
end
Match.Send = send
Lobby.Send = send
DailyLadder.Send = send

-- profile snapshot sent to the owning client
local function snapshot(p)
	local rank = Config.RankFor(p.elo)
	return {
		xp = p.xp,
		xpNext = Config.XPToNext(p.level),
		level = p.level,
		elo = p.elo,
		rank = rank.name,
		coins = p.coins,
		shards = p.shards,
		wins = p.wins,
		losses = p.losses,
		curStreak = p.curStreak,
		bestStreak = p.bestStreak,
		wordsPlayed = p.wordsPlayed,
		rareWords = p.rareWords,
		dailyStreak = p.dailyStreak,
		inventory = p.inventory,
		belt = p.belt,
		slots = PlayerData.Slots(p),
		achievements = p.achievements,
		wordLength = Config.LengthForLevel(p.level),
		tutorialDone = p.tutorialDone == true,
		ladderSolves = p.ladderSolves,
		bestWordLen = p.bestWordLen,
		bestWord = p.bestWord,
		longWords = p.longWords,
		longStreakBest = p.longStreakBest,
		bestScore = p.bestScore,
	}
end

PlayerData.OnChanged = function(player, p)
	send(player, "Profile", snapshot(p))
end
PlayerData.OnReward = function(player, payload)
	send(player, "Reward", payload)
end
PlayerData.OnToast = function(player, text)
	send(player, "Toast", text)
end
PlayerData.OnLevelUp = function(player)
	Shop.CheckReferralPayout(player)
end

-- per-player request rate limit
local budget = {}
local function allow(player)
	local b = budget[player]
	local t = os.clock()
	if not b or t - b.t > 1 then
		budget[player] = { t = t, n = 1 }
		return true
	end
	b.n += 1
	return b.n <= 12
end

local handlers = {
	Queue = function(plr)
		Lobby.Queue(plr)
	end,
	CancelQueue = function(plr)
		Lobby.CancelQueue(plr)
	end,
	PlayBot = function(plr)
		Lobby.PlayBot(plr)
	end,
	Submit = function(plr, word)
		local m = Match.ByPlayer[plr]
		if m then
			m:submit(plr, word)
		end
	end,
	UseItem = function(plr, kind)
		local m = Match.ByPlayer[plr]
		if m and type(kind) == "string" then
			m:useItem(plr, kind)
		end
	end,
	Choice = function(plr, choice)
		Lobby.Choice(plr, choice)
	end,
	KingBot = function(plr)
		Lobby.KingBot(plr)
	end,
	KingCashOut = function(plr)
		Lobby.KingCashOut(plr)
	end,
	CreatePrivate = function(plr)
		Lobby.CreatePrivate(plr)
	end,
	CancelPrivate = function(plr)
		Lobby.CancelPrivate(plr)
	end,
	JoinPrivate = function(plr, code)
		Lobby.JoinPrivate(plr, code)
	end,
	SetBelt = function(plr, list)
		if not Lobby.IsBusy(plr) then
			Shop.SetBelt(plr, list)
		else
			send(plr, "Toast", "Change your belt in the lobby, not mid-match.")
		end
	end,
	BuyProduct = function(plr, key)
		Shop.Buy(plr, key)
	end,
	BuyCoins = function(plr, kind)
		Shop.BuyWithCoins(plr, kind)
	end,
	BuySlotCoins = function(plr, slot)
		Shop.BuySlotWithCoins(plr, slot)
	end,
	LadderOpen = function(plr)
		DailyLadder.Open(plr)
	end,
	LadderMove = function(plr, word)
		if type(word) == "string" then
			DailyLadder.Move(plr, word)
		end
	end,
	LadderUndo = function(plr)
		DailyLadder.Undo(plr)
	end,
	LadderRestart = function(plr)
		DailyLadder.Restart(plr)
	end,
	LadderHint = function(plr)
		DailyLadder.Hint(plr)
	end,
	StartTutorial = function(plr)
		Lobby.StartTutorial(plr)
	end,
	SkipTutorial = function(plr)
		Lobby.SkipTutorial(plr)
	end,
	LeaveTable = function(plr)
		Lobby.LeaveTable(plr)
	end,
	GetLeaderboard = function(plr)
		send(plr, "Leaderboard", Leaderboards.Get())
	end,
	GetInviteData = function(plr)
		local code = Lobby.HostCode(plr) or Lobby.CreatePrivate(plr)
		send(plr, "InviteData", { launchData = "ref=" .. plr.UserId .. (code and (";code=" .. code) or "") })
	end,
	ClientReady = function(plr)
		task.spawn(function()
			local p = PlayerData.Get(plr)
			local t0 = os.clock()
			while not p and plr.Parent and (os.clock() - t0 < 5) do
				task.wait(0.05)
				p = PlayerData.Get(plr)
			end
			if not p or not plr.Parent then
				return
			end
			PlayerData.CheckAchievements(plr)
			PlayerData.Daily(plr)
			PlayerData.Changed(plr)
			send(plr, "Leaderboard", Leaderboards.Get())
		end)
	end,
	ResetFirstTime = function(plr)
		local p = PlayerData.Get(plr)
		if p then
			p.matches = 0
			p.tutorialDone = false
			p.dailyDay = 0
			p.dailyStreak = 0
			p.coins = 0
			p.xp = 0
			p.level = 1
			p.elo = Config.StartElo
			PlayerData.Save(plr)
			PlayerData.Daily(plr)
			PlayerData.Changed(plr)
			send(plr, "Toast", "Reset to First-Time Player!")
		end
	end,
}

Net.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or not allow(player) then
		return
	end
	local h = handlers[action]
	if h and (action == "ClientReady" or PlayerData.Get(player)) then
		local ok, err = pcall(h, player, payload)
		if not ok then
			warn("[WordDuel] handler", action, "failed:", err)
		end
	end
end)

local function onPlayerAdded(player)
	local profile = PlayerData.Load(player)
	if not profile then
		return
	end
	local ref, code = Shop.ParseLaunchData(player)
	Shop.RegisterReferral(player, ref)
	Shop.ClaimPendingReferrals(player)
	PlayerData.Changed(player)
	send(player, "Leaderboard", Leaderboards.Get())
	-- joined through a friend's invite: sit at their private table automatically
	if code then
		task.delay(4, function()
			if player.Parent then
				Lobby.JoinPrivate(player, code)
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, plr)
end

Players.PlayerRemoving:Connect(function(player)
	Lobby.PlayerLeft(player)
	DailyLadder.PlayerLeft(player)
	local p = PlayerData.Get(player)
	if p then
		Leaderboards.Submit(player, p, true)
	end
	PlayerData.Release(player)
	budget[player] = nil
end)

-- Studio-only automated test hooks (no-op in a live game)
require(script.Parent.TestHooks).Start({
	Match = Match,
	Lobby = Lobby,
	Dictionary = Dictionary,
	PlayerData = PlayerData,
	Shop = Shop,
	Config = Config,
	Arena = Arena,
	Ambient = require(script.Parent.Ambient),
	DailyLadder = DailyLadder,
})

-- server shutdown: save everyone before the server closes
game:BindToClose(function()
	local pending = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			PlayerData.Save(plr)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

-- periodically claim referral payouts for friends who levelled up while the inviter was offline
task.spawn(function()
	while true do
		task.wait(90)
		for _, plr in ipairs(Players:GetPlayers()) do
			task.spawn(Shop.ClaimPendingReferrals, plr)
		end
	end
end)
