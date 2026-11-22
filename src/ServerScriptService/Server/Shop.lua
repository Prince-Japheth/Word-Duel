-- Shop: Robux Developer Products (unlimited stock in inventory) + coin purchases,
-- Loadout Belt validation, and friend referral rewards.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Shop = {}

local function applyProduct(player, product)
	local p = PlayerData.Get(player)
	if not p then
		return false
	end
	if product.slot then
		p.slotsBought = math.max(p.slotsBought, product.slot - 1)
		PlayerData.Changed(player)
		if PlayerData.OnReward then
			PlayerData.OnReward(player, { kind = "level", title = "BOOST SLOT " .. product.slot, sub = "Bring one more boost into every match" })
		end
	else
		PlayerData.Grant(player, product.grant)
	end
	return true
end

function Shop.Buy(player, key)
	local product = Config.ProductByKey(key)
	if not product then
		return
	end
	local p = PlayerData.Get(player)
	if not p then
		return
	end
	if product.slot then
		local slots = PlayerData.Slots(p)
		if slots >= product.slot then
			return PlayerData.Toast(player, "You already have that slot.")
		end
		if slots < product.slot - 1 then
			return PlayerData.Toast(player, "Unlock Belt Slot " .. (product.slot - 1) .. " first.")
		end
	end
	if product.id == 0 then
		if RunService:IsStudio() then
			PlayerData.Toast(player, "[Studio test] Free grant: " .. product.label)
			applyProduct(player, product)
		else
			PlayerData.Toast(player, "This product is not set up yet.")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end

function Shop.BuyWithCoins(player, kind)
	local price = Config.CoinPrices[kind]
	local p = PlayerData.Get(player)
	if not price or not p then
		return
	end
	if p.coins < price then
		return PlayerData.Toast(player, "Not enough coins! You have " .. p.coins .. " / " .. price .. " needed. Play duels or top up!")
	end
	p.coins -= price
	PlayerData.Grant(player, { [kind] = 1 })
end

function Shop.BuySlotWithCoins(player, slot)
	local p = PlayerData.Get(player)
	if not p or not slot then
		return
	end
	local price = Config.SlotCoinPrices[slot]
	if not price then
		return PlayerData.Toast(player, "Invalid belt slot.")
	end
	if (slot + #Config.FastSlotClocks) > (Config.AbsoluteMaxSlots or 9) then
		return PlayerData.Toast(player, "Max 9 belt slots reached.")
	end
	local slots = PlayerData.Slots(p)
	if slots >= slot then
		return PlayerData.Toast(player, "You already unlocked Slot " .. slot .. ".")
	end
	if slots < slot - 1 then
		return PlayerData.Toast(player, "Unlock Slot " .. (slot - 1) .. " first.")
	end
	if p.coins < price then
		return PlayerData.Toast(player, "Need " .. price .. " coins (you have " .. p.coins .. "). Play duels or top up!")
	end
	p.coins -= price
	p.slotsBought = math.max(p.slotsBought, slot - 1)
	PlayerData.Changed(player)
	if PlayerData.OnReward then
		PlayerData.OnReward(player, { kind = "level", title = "BELT SLOT " .. slot .. " UNLOCKED!", sub = "Belt permanently upgraded with coins!" })
	end
	PlayerData.Toast(player, "Unlocked Belt Slot " .. slot .. "!")
end

function Shop.SetBelt(player, list)
	local p = PlayerData.Get(player)
	if not p or type(list) ~= "table" then
		return
	end
	local slots = PlayerData.Slots(p) + #Config.FastSlotClocks -- fast-game slots can be set up too
	local belt = {}
	for i = 1, slots do
		local kind = list[i]
		if type(kind) == "string" and Config.Items[kind] then
			belt[i] = kind
		else
			belt[i] = nil
		end
	end
	p.belt = belt
	PlayerData.Changed(player)
end

function Shop.ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = Config.ProductById(info.ProductId)
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = PlayerData.Get(player)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- duplicate receipt guard
	for _, id in ipairs(p.receipts) do
		if id == info.PurchaseId then
			-- already granted this session; confirm only once it is actually saved
			if PlayerData.Save(player) then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	if not applyProduct(player, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(p.receipts, info.PurchaseId)
	while #p.receipts > 50 do
		table.remove(p.receipts, 1)
	end
	-- Only confirm the purchase once it is saved. If the save fails, Roblox retries the receipt
	-- later; the receipt id above stops a double grant if the retry lands in this same session.
	if not PlayerData.Save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = Shop.ProcessReceipt

---------------------------------------------------------------- referrals
-- Invite launch data = "ref=<inviterUserId>;code=<privateCode>"
-- Both players get Config.ReferralBundle once the invited friend reaches level 3 (blocks alt farming).
local pendingStore
pcall(function()
	pendingStore = DataStoreService:GetDataStore("WordDuel_Referrals_v1")
end)

function Shop.ParseLaunchData(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local raw = ok and joinData and joinData.LaunchData
	if type(raw) ~= "string" then
		return nil, nil
	end
	local ref = tonumber(raw:match("ref=(%d+)"))
	local code = raw:match("code=(%w+)")
	return ref, code
end

function Shop.RegisterReferral(player, refId)
	local p = PlayerData.Get(player)
	if not p or not refId or refId == player.UserId then
		return
	end
	if p.referredBy == 0 and p.matches == 0 and p.level < Config.ReferralLevel then
		p.referredBy = refId
		PlayerData.Toast(player, "Invited by a friend! Reach level " .. Config.ReferralLevel .. " and you both get a bonus.")
	end
end

function Shop.CheckReferralPayout(player)
	local p = PlayerData.Get(player)
	if not p or p.referredBy == 0 or p.referralPaid or p.level < Config.ReferralLevel then
		return
	end
	p.referralPaid = true
	PlayerData.Reward(player, "bonus", "FRIEND BONUS", "You and your friend both get this", Config.ReferralBundle)
	local inviter = Players:GetPlayerByUserId(p.referredBy)
	if inviter and PlayerData.Get(inviter) then
		PlayerData.Reward(inviter, "bonus", "FRIEND BONUS", player.DisplayName .. " reached level " .. Config.ReferralLevel, Config.ReferralBundle)
	elseif pendingStore then
		local refKey = "r_" .. p.referredBy
		task.spawn(function()
			pcall(function()
				pendingStore:UpdateAsync(refKey, function(old)
					return (old or 0) + 1
				end)
			end)
		end)
	end
	PlayerData.Save(player)
end

function Shop.ClaimPendingReferrals(player)
	if not pendingStore then
		return
	end
	local claimed = 0
	local ok = pcall(function()
		pendingStore:UpdateAsync("r_" .. player.UserId, function(old)
			claimed = old or 0
			if claimed == 0 then
				return nil -- no write
			end
			return 0
		end)
	end)
	if ok and claimed > 0 then
		local grant = {}
		for k, v in pairs(Config.ReferralBundle) do
			grant[k] = v * claimed
		end
		PlayerData.Reward(player, "bonus", "FRIEND BONUS", claimed .. " friend(s) you invited levelled up", grant)
	end
end

return Shop
