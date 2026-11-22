-- NPC: builds avatar rigs for bot opponents and ambient table duels, plus Roblox-style
-- display names. Names are generated, never taken from real accounts.
local Players = game:GetService("Players")

local NPC = {}

local FIRST = {
	"Pixel", "Lunar", "Mango", "Frosty", "Turbo", "Cosmic", "Sunny", "Shadow", "Minty", "Ziggy",
	"Nova", "Echo", "Blaze", "Coral", "Maple", "Velvet", "Rusty", "Jade", "Ruby", "Storm",
	"Cocoa", "Peachy", "Toasty", "Misty", "Clever", "Lucky", "Sneaky", "Bouncy", "Sleepy", "Zesty",
	"Silent", "Golden", "Crimson", "Hyper", "Chill", "Fuzzy", "Witty", "Brave", "Spicy", "Icy",
}
local SECOND = {
	"Fox", "Panda", "Otter", "Wizard", "Ninja", "Comet", "Bean", "Tiger", "Koala", "Falcon",
	"Pickle", "Noodle", "Penguin", "Rocket", "Llama", "Dragon", "Waffle", "Mochi", "Badger", "Owl",
	"Phoenix", "Raven", "Puffin", "Gecko", "Muffin", "Biscuit", "Taco", "Bunny", "Wolf", "Shark",
	"Scribe", "Speller", "Reader", "Quill", "Ink", "Pages", "Lexi", "Writer", "Riddle", "Puzzler",
}

local used = {}
function NPC.RandomName()
	for _ = 1, 20 do
		local a = FIRST[math.random(#FIRST)]
		local b = SECOND[math.random(#SECOND)]
		local style = math.random(6)
		local name
		if style == 1 then
			name = a .. b .. math.random(2, 999)
		elseif style == 2 then
			name = a .. "_" .. b
		elseif style == 3 then
			name = string.lower(a) .. b .. math.random(1, 99)
		elseif style == 4 then
			name = a .. b
		elseif style == 5 then
			name = b .. "_" .. math.random(10, 9999)
		else
			name = string.lower(a) .. string.lower(b)
		end
		if not used[name] then
			used[name] = true
			return name
		end
	end
	return "Player" .. math.random(1000, 99999)
end

local SKIN = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 102, 70), Color3.fromRGB(116, 72, 48), Color3.fromRGB(86, 56, 40),
	Color3.fromRGB(245, 205, 48), Color3.fromRGB(255, 235, 210),
}
local SHIRT = {
	Color3.fromRGB(30, 30, 36), Color3.fromRGB(220, 220, 225), Color3.fromRGB(196, 40, 52), Color3.fromRGB(36, 92, 196),
	Color3.fromRGB(40, 140, 90), Color3.fromRGB(240, 170, 40), Color3.fromRGB(120, 60, 170), Color3.fromRGB(240, 120, 160),
	Color3.fromRGB(70, 170, 200), Color3.fromRGB(90, 70, 50), Color3.fromRGB(250, 250, 250), Color3.fromRGB(255, 90, 40),
}
local PANTS = {
	Color3.fromRGB(28, 30, 40), Color3.fromRGB(40, 52, 90), Color3.fromRGB(70, 70, 76), Color3.fromRGB(110, 84, 60),
	Color3.fromRGB(20, 20, 22), Color3.fromRGB(60, 90, 140), Color3.fromRGB(200, 200, 205),
}

local function pick(t)
	return t[math.random(#t)]
end

-- Returns a seated-ready R15 Model, or nil if avatar creation is unavailable.
function NPC.Build(name)
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(SKIN)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = pick(SHIRT)
	local legs = pick(PANTS)
	desc.LeftLegColor = legs
	desc.RightLegColor = legs
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = name
	model.Archivable = true
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model:SetAttribute("WordDuelNPC", true)
	return model
end

return NPC
