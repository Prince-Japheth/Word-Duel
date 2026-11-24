-- Word Duel client: every screen is built here from native UI objects (no image uploads needed).
-- Look: cream letter tiles with a 3D lip, pressable "key" buttons, ink panels, one amber accent.
-- Layout is designed at 1180x700 and scaled to the screen (UIScale), inside Roblox's safe area.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WordRules = require(Shared.WordRules)
local MAX_WORD = 10
local Net = ReplicatedStorage:WaitForChild("Net")

local IS_STUDIO = RunService:IsStudio()

-- touch layout = custom letter keyboard instead of a text box (attribute ForceTouch overrides, for testing)
local function touchMode()
	local forced = player:GetAttribute("ForceTouch")
	if forced ~= nil then
		return forced == true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local setSearching, showLobby, alignMatchCamera, stopMatchCam, alignLobbyCamera
local queueCancelBtn, queueBotBtn

pcall(function()
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function fire(action, payload)
	Net:FireServer(action, payload)
end

---------------------------------------------------------------- theme
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local C = {
	white = rgb(255, 255, 255),
	ink = rgb(14, 15, 22),
	s0 = rgb(10, 11, 17),
	s1 = rgb(22, 24, 36),
	s2 = rgb(31, 34, 50),
	s3 = rgb(45, 49, 70),
	text = rgb(245, 242, 235),
	dim = rgb(160, 164, 186),
	faint = rgb(104, 109, 136),
	amber = rgb(255, 186, 74),
	amberLip = rgb(196, 122, 26),
	cream = rgb(247, 238, 216),
	creamLip = rgb(204, 182, 140),
	teal = rgb(58, 214, 168),
	tealLip = rgb(26, 148, 112),
	red = rgb(255, 94, 100),
	redLip = rgb(176, 46, 58),
	blue = rgb(110, 146, 255),
	blueLip = rgb(62, 90, 196),
}

local F = {
	display = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
	heavy = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold),
	bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	medium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	tile = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
}

local CENTER = Enum.TextXAlignment.Center
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local H = Enum.FillDirection.Horizontal
local V = Enum.FillDirection.Vertical

---------------------------------------------------------------- helpers
local function make(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 12) })
end

local function round()
	return make("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(color, transparency, thickness)
	return make("UIStroke", {
		Color = color or C.white,
		Transparency = transparency or 0.9,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function pad(l, r, t, b)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or l),
		PaddingBottom = UDim.new(0, b or t or l),
	})
end

local function list(dir, padding, halign, valign)
	return make("UIListLayout", {
		FillDirection = dir or V,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- multiplies the background: white at top, slightly darker at the bottom (a soft sheen)
local function sheen(amount)
	local d = math.floor(255 * (1 - (amount or 0.12)))
	return make("UIGradient", { Color = ColorSequence.new(C.white, rgb(d, d, d)), Rotation = 90 })
end

local function text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.FontFace = props.FontFace or F.bold
	props.TextColor3 = props.TextColor3 or C.text
	props.TextSize = props.TextSize or 18
	props.TextXAlignment = props.TextXAlignment or LEFT
	return make("TextLabel", props)
end

local function tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function shake(inst)
	if not inst then return end
	local base = inst.Position
	task.spawn(function()
		for _, dx in ipairs({ -12, 10, -7, 5, -2, 0 }) do
			tween(inst, 0.04, { Position = base + UDim2.fromOffset(dx, 0) }, Enum.EasingStyle.Linear)
			task.wait(0.04)
		end
		inst.Position = base
	end)
end

local function lighten(c, a)
	return c:Lerp(C.white, a)
end

local function clearChildren(inst, keepClass)
	for _, ch in ipairs(inst:GetChildren()) do
		if not (keepClass and ch:IsA(keepClass)) then
			ch:Destroy()
		end
	end
end

local function rankColor(name)
	for _, r in ipairs(Config.Ranks) do
		if r.name == name then
			return r.color
		end
	end
	return C.text
end

---------------------------------------------------------------- sound
local musicWanted, musicMuted, setMusic, sfx, sounds
do
-- Roblox-made UI sounds from the Creator Store (public, so they play in any game).
local SFX = {
	click = { 15675059323, 0.35 },
	key = { 15675032796, 0.3 },
	good = { 15675055424, 0.5 },
	bad = { 15675075163, 0.45 },
	whoosh = { 15674975792, 0.35 },
	win = { 15675043410, 0.6 },
	lose = { 15675062723, 0.5 },
	tick = { 15675085146, 0.35 },
	brilliant = { 15675016548, 0.6 },
	turn = { 15675046931, 0.8 }, -- "your move" cue
}
local soundFolder = make("Folder", { Name = "WordDuelSounds", Parent = playerGui })
sounds = {}
for name, s in pairs(SFX) do
	sounds[name] = make("Sound", { Name = name, SoundId = "rbxassetid://" .. s[1], Volume = s[2], Parent = soundFolder })
end
local MUSIC_VOLUME = 0.1
local music = make("Sound", { Name = "Music", SoundId = "rbxassetid://15675069601", Volume = 0, Looped = true, Parent = soundFolder })
musicMuted = false
musicWanted = false

sfx = function(name)
	local s = sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

setMusic = function(on)
	musicWanted = on
	local play = on and not musicMuted
	if play and not music.IsPlaying then
		music:Play()
	end
	tween(music, 1, { Volume = play and MUSIC_VOLUME or 0 }, Enum.EasingStyle.Linear)
end

end -- scope
---------------------------------------------------------------- root + scaling
local root
do
local gui = make("ScreenGui", {
	Name = "WordDuel",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	Parent = playerGui,
})
root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Parent = gui })
local uiScale = make("UIScale", { Parent = root })
local DESIGN = Vector2.new(1180, 700)

local function relayout()
	local abs = gui.AbsoluteSize
	if abs.X <= 0 or abs.Y <= 0 then
		return
	end
	local s = math.clamp(math.min(abs.X / DESIGN.X, abs.Y / DESIGN.Y), 0.4, 1.4)
	uiScale.Scale = s
	root.Size = UDim2.fromOffset(abs.X / s, abs.Y / s)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

end -- scope
---------------------------------------------------------------- building blocks
-- Pressable key: colored face sitting on a darker lip; sinks when pressed.
local STYLES = {
	primary = { face = C.amber, lip = C.amberLip, text = C.ink },
	secondary = { face = C.s3, lip = C.s0, text = C.text },
	success = { face = C.teal, lip = C.tealLip, text = C.ink },
	danger = { face = C.red, lip = C.redLip, text = C.white },
	blue = { face = C.blue, lip = C.blueLip, text = C.white },
	cream = { face = C.cream, lip = C.creamLip, text = C.ink },
	disabled = { face = C.s2, lip = C.s0, text = C.faint },
}
local LIP = 5

local Key = {}
Key.__index = Key

function Key:setStyle(style)
	self.style = style
	local st = STYLES[style]
	self.face.BackgroundColor3 = st.face
	self.lip.BackgroundColor3 = st.lip
	self.title.TextColor3 = st.text
	if self.sub then
		self.sub.TextColor3 = st.text
	end
end

function Key:setEnabled(on)
	self.enabled = on
	self:setStyle(on and self.baseStyle or "disabled")
end

function Key:setText(t, sub)
	self.title.Text = t
	if sub and self.sub then
		self.sub.Text = sub
	end
end

-- opts: text, sub, style, size, position, anchor, order, parent, textSize, radius, onClick, icon, sound
local function newKey(opts)
	local style = opts.style or "secondary"
	local st = STYLES[style]
	local radius = opts.radius or 14
	local holder = make("Frame", {
		Name = opts.name or "Key",
		BackgroundTransparency = 1,
		Size = opts.size,
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		LayoutOrder = opts.order or 0,
		Parent = opts.parent,
	})
	local lip = make("Frame", {
		BackgroundColor3 = st.lip,
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.new(1, 0, 1, -LIP),
		Parent = holder,
	}, { corner(radius) })
	local face = make("TextButton", {
		Name = "Face",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = st.face,
		Size = UDim2.new(1, 0, 1, -LIP),
		Parent = holder,
	}, { corner(radius), sheen(0.14) })
	local title = text({
		Name = "Title",
		Text = opts.text or "",
		FontFace = F.heavy,
		TextSize = opts.textSize or 18,
		TextColor3 = st.text,
		TextXAlignment = CENTER,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	local sub
	if opts.sub then
		title.Size = UDim2.new(1, 0, 0.58, 0)
		title.TextYAlignment = Enum.TextYAlignment.Bottom
		sub = text({
			Name = "Sub",
			Text = opts.sub,
			FontFace = F.bold,
			TextSize = opts.subSize or 14,
			TextColor3 = st.text,
			TextTransparency = 0.3,
			TextXAlignment = CENTER,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromScale(0, 0.6),
			Size = UDim2.new(1, 0, 0.4, 0),
			Parent = face,
		})
	end
	if opts.icon then
		-- small letter tile above the label (dock buttons)
		local size = opts.iconSize or 30
		local ic = make("Frame", { BackgroundColor3 = C.cream, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(size, size), Parent = face }, { corner(7), sheen(0.12) })
		text({ Text = opts.icon, FontFace = F.tile, TextSize = math.floor(size * 0.55), TextColor3 = C.ink, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = ic })
		title.Size = UDim2.new(1, 0, 0, 20)
		title.Position = UDim2.new(0, 0, 1, -28)
	end
	local k = setmetatable({ holder = holder, face = face, lip = lip, title = title, sub = sub, style = style, baseStyle = style, enabled = true, onClick = opts.onClick }, Key)
	face.MouseEnter:Connect(function()
		if k.enabled then
			tween(face, 0.12, { BackgroundColor3 = lighten(STYLES[k.style].face, 0.08) })
		end
	end)
	face.MouseLeave:Connect(function()
		tween(face, 0.12, { BackgroundColor3 = STYLES[k.style].face, Position = UDim2.new() })
	end)
	face.MouseButton1Down:Connect(function()
		if k.enabled then
			tween(face, 0.05, { Position = UDim2.fromOffset(0, LIP - 1) })
		end
	end)
	face.MouseButton1Up:Connect(function()
		tween(face, 0.12, { Position = UDim2.new() })
	end)
	face.Activated:Connect(function()
		if not k.enabled then
			return
		end
		sfx(opts.sound or "click")
		if k.onClick then
			k.onClick()
		end
	end)
	return k
end

-- Letter tile: cream face on a lip. opts: face, lip, ink, rotation, order, position
local function newTile(parent, letter, size, opts)
	opts = opts or {}
	local lipH = math.max(3, math.floor(size * 0.075))
	local r = math.floor(size * 0.17)
	local holder = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + lipH),
		Position = opts.position or UDim2.new(),
		Rotation = opts.rotation or 0,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	})
	local lip = make("Frame", { BackgroundColor3 = opts.lip or C.creamLip, Position = UDim2.fromOffset(0, lipH), Size = UDim2.fromOffset(size, size), Parent = holder }, { corner(r) })
	local face = make("Frame", { BackgroundColor3 = opts.face or C.cream, Size = UDim2.fromOffset(size, size), Parent = holder }, { corner(r), sheen(0.1) })
	local label = text({
		Text = string.upper(letter),
		FontFace = F.tile,
		TextSize = math.floor(size * (#letter > 1 and 0.42 or 0.6)),
		TextColor3 = opts.ink or C.ink,
		TextXAlignment = CENTER,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	return { holder = holder, face = face, lip = lip, label = label, lipH = lipH }
end

local function tileWord(parent, word, size, gap, opts)
	opts = opts or {}
	local row = make("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	}, { list(H, gap or 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	for i = 1, #word do
		newTile(row, word:sub(i, i), size, { order = i, face = opts.face, lip = opts.lip, ink = opts.ink, rotation = opts.rotations and opts.rotations[i] or 0 })
	end
	return row
end

local function coinIcon(parent, size, position)
	local c = make("Frame", { BackgroundColor3 = C.white, Size = UDim2.fromOffset(size, size), Position = position or UDim2.new(), Parent = parent }, {
		round(),
		make("UIGradient", { Color = ColorSequence.new(lighten(C.amber, 0.35), C.amber), Rotation = 90 }),
		stroke(C.amberLip, 0, 2),
	})
	make("Frame", { BackgroundColor3 = C.amberLip, BackgroundTransparency = 0.35, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.4, 0.4), Parent = c }, { round() })
	return c
end

local function gemIcon(parent, size, position)
	local holder = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Position = position or UDim2.new(), Parent = parent })
	make("Frame", {
		BackgroundColor3 = C.white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		Rotation = 45,
		Parent = holder,
	}, { corner(4), make("UIGradient", { Color = ColorSequence.new(lighten(C.teal, 0.4), C.teal), Rotation = 45 }), stroke(C.tealLip, 0, 2) })
	return holder
end

---------------------------------------------------------------- icon set
local Icon, avatar, chip, panel, scrim
do
-- One icon per kind of reward, drawn from shapes so they're crisp and always the same.
-- Players meet them in the icon guide (after the tutorial, and under Rules).
Icon = {}
local GOLD, GOLD_DK = rgb(255, 196, 64), rgb(190, 122, 22)
local ICON_GLYPH = { Help = "?", Skip = ">>", Time = "+5", DoubleShift = "2X" }

local function shape(parent, props, children)
	props.Parent = parent
	props.BorderSizePixel = 0
	return make("Frame", props, children)
end

local function holderOf(parent, size, position)
	return shape(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Position = position or UDim2.new() })
end

local function goldFill(top, bottom)
	return make("UIGradient", { Color = ColorSequence.new(top or lighten(GOLD, 0.4), bottom or GOLD), Rotation = 90 })
end

-- medal on two ribbons; dark when not earned yet
function Icon.medal(parent, size, position, earned)
	local h = holderOf(parent, size, position)
	shape(h, { BackgroundColor3 = earned and C.red or C.s3, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.37, 0), Size = UDim2.fromScale(0.2, 0.5), Rotation = -16 })
	shape(h, { BackgroundColor3 = earned and C.blue or C.s3, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.63, 0), Size = UDim2.fromScale(0.2, 0.5), Rotation = 16 })
	local disc = shape(h, { BackgroundColor3 = C.white, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.7, 0.7) }, {
		round(),
		earned and goldFill() or goldFill(C.s3, C.s2),
		stroke(earned and GOLD_DK or C.s0, 0, math.max(2, math.floor(size * 0.05))),
	})
	shape(disc, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.58, 0.58) }, { round(), stroke(earned and GOLD_DK or C.s0, 0.35, math.max(1, math.floor(size * 0.035))) })
	return h
end

-- trophy cup: personal records
function Icon.trophy(parent, size, position)
	local h = holderOf(parent, size, position)
	for _, x in ipairs({ 0.2, 0.8 }) do
		shape(h, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0.1), Size = UDim2.fromScale(0.26, 0.3) }, { round(), stroke(GOLD_DK, 0, math.max(2, math.floor(size * 0.06))) })
	end
	shape(h, { BackgroundColor3 = C.white, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromScale(0.56, 0.48) }, { corner(math.floor(size * 0.2)), goldFill(), stroke(GOLD_DK, 0, math.max(1, math.floor(size * 0.04))) })
	shape(h, { BackgroundColor3 = GOLD_DK, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.13, 0.2) })
	shape(h, { BackgroundColor3 = rgb(92, 58, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(0.56, 0.2) }, { corner(math.floor(size * 0.05)) })
	shape(h, { BackgroundColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.76), Size = UDim2.fromScale(0.3, 0.07) }, { round() })
	return h
end

-- treasure chest: the daily chest
function Icon.chest(parent, size, position)
	local h = holderOf(parent, size, position)
	shape(h, { BackgroundColor3 = rgb(150, 90, 46), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.92), Size = UDim2.fromScale(0.86, 0.46) }, { corner(math.floor(size * 0.07)) })
	shape(h, { BackgroundColor3 = rgb(118, 68, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.14), Size = UDim2.fromScale(0.9, 0.34) }, { corner(math.floor(size * 0.12)) })
	for _, x in ipairs({ 0.28, 0.72 }) do
		shape(h, { BackgroundColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0.14), Size = UDim2.fromScale(0.09, 0.78) })
	end
	shape(h, { BackgroundColor3 = C.white, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.2, 0.22) }, { corner(math.floor(size * 0.04)), goldFill(), stroke(GOLD_DK, 0, 1) })
	return h
end

-- crown: King of the Table
function Icon.crown(parent, size, position)
	local h = holderOf(parent, size, position)
	for i, x in ipairs({ 0.2, 0.5, 0.8 }) do
		shape(h, { BackgroundColor3 = C.white, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, i == 2 and 0.3 or 0.38), Size = UDim2.fromScale(0.3, 0.3), Rotation = 45 }, { corner(math.floor(size * 0.03)), goldFill() })
	end
	shape(h, { BackgroundColor3 = C.white, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.84, 0.36) }, { corner(math.floor(size * 0.06)), goldFill(), stroke(GOLD_DK, 0, math.max(1, math.floor(size * 0.04))) })
	for _, x in ipairs({ 0.3, 0.5, 0.7 }) do
		shape(h, { BackgroundColor3 = C.red, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.68), Size = UDim2.fromScale(0.11, 0.11) }, { round() })
	end
	return h
end

-- blue level badge with the number
function Icon.level(parent, size, position, n)
	local h = holderOf(parent, size, position)
	newTile(h, tostring(n or ""), math.floor(size * 0.9), { position = UDim2.fromScale(0.05, 0), face = C.blue, lip = C.blueLip, ink = C.white })
	text({ Text = "LV", FontFace = F.heavy, TextSize = math.max(9, math.floor(size * 0.18)), TextColor3 = C.white, TextXAlignment = CENTER, Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.2), ZIndex = 3, Parent = h })
	return h
end

-- an item as its letter tile (Help ?, Skip >>, More Time +5, Double Points 2X)
function Icon.item(parent, size, position, kind)
	return newTile(parent, ICON_GLYPH[kind] or "+", size, { position = position }).holder
end

-- small rounded label chip
chip = function(parent, str, color, order)
	local f = make("Frame", {
		BackgroundColor3 = color or C.s3,
		BackgroundTransparency = 0.82,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = order or 0,
		Parent = parent,
	}, { round(), pad(12, 12, 0, 0), stroke(color or C.white, 0.6) })
	local t = text({ Text = str, FontFace = F.heavy, TextSize = 12, TextColor3 = color or C.dim, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Parent = f })
	return f, t
end

-- avatar circle: headshot for real players, a letter for bots
local thumbCache = {}
avatar = function(parent, size, position)
	local f = make("Frame", { BackgroundColor3 = C.s3, Size = UDim2.fromOffset(size, size), Position = position or UDim2.new(), Parent = parent }, { round(), stroke(C.white, 0.85, 2) })
	local img = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "", Parent = f }, { round() })
	local letter = text({ Text = "", FontFace = F.display, TextSize = math.floor(size * 0.45), TextColor3 = C.dim, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = f })
	local function set(userId, name)
		img.Image = ""
		letter.Text = string.upper((name or "?"):sub(1, 1))
		if userId and userId > 0 then
			if thumbCache[userId] then
				img.Image = thumbCache[userId]
				letter.Text = ""
				return
			end
			task.spawn(function()
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end)
				if ok and url then
					thumbCache[userId] = url
					img.Image = url
					letter.Text = ""
				end
			end)
		end
	end
	-- render a character model's head (works for players and NPC rigs alike)
	local function setRig(model)
		for _, ch in ipairs(f:GetChildren()) do
			if ch:IsA("ViewportFrame") then
				ch:Destroy()
			end
		end
		if not model then
			return false
		end
		local ok, clone = pcall(function()
			model.Archivable = true
			return model:Clone()
		end)
		if not ok or not clone then
			return false
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
		local head = clone:FindFirstChild("Head")
		if not head then
			clone:Destroy()
			return false
		end
		local vp = make("ViewportFrame", { BackgroundColor3 = C.s3, Size = UDim2.fromScale(1, 1), Ambient = rgb(170, 160, 150), LightColor = C.white, LightDirection = Vector3.new(-0.4, -0.6, -1), ZIndex = 2, Parent = f }, { round() })
		clone.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 26
		local look = head.CFrame.LookVector
		cam.CFrame = CFrame.lookAt(head.Position + look * 3.4 + Vector3.new(0, 0.15, 0), head.Position)
		cam.Parent = vp
		vp.CurrentCamera = cam
		letter.Text = ""
		img.Image = ""
		return true
	end
	return f, set, setRig
end

-- full-screen dim layer (extends past the safe area so it covers the notch/top bar)
scrim = function(parent, transparency, z)
	return make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.s0,
		BackgroundTransparency = transparency or 0.35,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-600, -600),
		Size = UDim2.new(1, 1200, 1, 1200),
		ZIndex = z or 1,
		Parent = parent,
	})
end

panel = function(props)
	local radius = props.radius or 18
	props.radius = nil
	props.BackgroundColor3 = props.BackgroundColor3 or C.s1
	local f = make("Frame", props)
	corner(radius).Parent = f
	stroke(C.white, 0.9).Parent = f
	return f
end

end -- scope
---------------------------------------------------------------- state
local profile = nil
local lastLevel = nil
local match = nil -- { me, opp, ranked, state }
local leaderboard = { elo = {}, streak = {} }
local lbTab = "elo"
local privateCode = nil
local hint = nil
local searching = false
local quickCombo = 0
local longRunCombo = 0
local submitLeftFrac = 0

---------------------------------------------------------------- toasts + flash
local showFlash, toast
do
local toastHolder = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 104),
	Size = UDim2.fromOffset(600, 300),
	ZIndex = 50,
	Parent = root,
}, { list(V, 8, Enum.HorizontalAlignment.Center) })
local toastOrder = 0

toast = function(msg, accent)
	toastOrder += 1
	sfx("key") -- every message gets a soft click so it's noticed
	local t = make("Frame", {
		BackgroundColor3 = C.s1,
		BackgroundTransparency = 0.04,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	}, { round(), stroke(accent or C.white, accent and 0.55 or 0.88), pad(18, 20, 11, 11), list(H, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local dot = make("Frame", { BackgroundColor3 = accent or C.amber, Size = UDim2.fromOffset(8, 8), LayoutOrder = 1, Parent = t }, { round() })
	local label = text({ Text = msg, FontFace = F.bold, TextSize = 16, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), LayoutOrder = 2, Parent = t })
	task.delay(5.5, function()
		if not t.Parent then
			return
		end
		tween(t, 0.35, { BackgroundTransparency = 1 })
		tween(label, 0.35, { TextTransparency = 1 })
		tween(dot, 0.35, { BackgroundTransparency = 1 })
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then
			tween(s, 0.35, { Transparency = 1 })
		end
		task.wait(0.4)
		t:Destroy()
	end)
	-- keep at most 4 on screen
	local items = {}
	for _, ch in ipairs(toastHolder:GetChildren()) do
		if ch:IsA("Frame") then
			table.insert(items, ch)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #items - 4 do
		items[i]:Destroy()
	end
end

-- big call-outs are outlined text only (no backing bar); during a match they sit away
-- from the board so they never cover the word
local flash = text({
	Text = "",
	FontFace = F.display,
	TextSize = 52,
	TextXAlignment = CENTER,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromOffset(900, 64),
	TextStrokeColor3 = C.s0,
	TextStrokeTransparency = 0.1,
	Visible = false,
	ZIndex = 45,
	Parent = root,
})
local flashScale = make("UIScale", { Parent = flash })
local flashToken = 0
showFlash = function(msg, color, seconds, pos, size)
	flashToken += 1
	local my = flashToken
	flash.Text = msg
	flash.TextColor3 = color or C.amber
	flash.TextSize = size or 52
	flash.Position = pos or UDim2.fromScale(0.5, 0.42)
	flash.TextTransparency = 0
	flash.TextStrokeTransparency = 0.1
	flash.Visible = true
	flashScale.Scale = 0.6
	tween(flashScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(seconds or 1.6, function()
		if flashToken == my then
			tween(flash, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.wait(0.3)
			if flashToken == my then
				flash.Visible = false
			end
		end
	end)
end

end -- scope
---------------------------------------------------------------- top-right currency
local coinText, shardText, topRight
do
topRight = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(480, 46),
	ZIndex = 5,
	Parent = root,
}, { list(H, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })

local function topPill(order, width)
	return make("Frame", { BackgroundColor3 = C.s1, BackgroundTransparency = 0.06, Size = UDim2.fromOffset(width, 46), LayoutOrder = order, Parent = topRight }, { round(), stroke(C.white, 0.88) })
end
local shardPill = topPill(1, 104)
gemIcon(shardPill, 26, UDim2.fromOffset(10, 10))
shardText = text({ Text = "0/5", FontFace = F.heavy, TextSize = 17, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -52, 1, 0), Parent = shardPill })
local coinPill = topPill(2, 140)
coinIcon(coinPill, 26, UDim2.fromOffset(10, 10))
coinText = text({ Text = "0", FontFace = F.heavy, TextSize = 18, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -54, 1, 0), Parent = coinPill })
local muteBtn = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.s1, BackgroundTransparency = 0.06, Size = UDim2.fromOffset(96, 46), LayoutOrder = 3, Parent = topRight }, { round(), stroke(C.amber, 0.5, 1.5) })
local muteStroke = muteBtn:FindFirstChildOfClass("UIStroke")
local muteNote = text({ Text = "♪", FontFace = F.display, TextSize = 20, TextColor3 = C.amber, TextXAlignment = CENTER, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(26, 46), Parent = muteBtn })
local muteLabel = text({ Text = "MUSIC", FontFace = F.heavy, TextSize = 12, TextColor3 = C.text, Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -34, 1, 0), Parent = muteBtn })
local muteSlash = make("Frame", { BackgroundColor3 = C.red, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 19, 0.5, 0), Size = UDim2.fromOffset(24, 3), Rotation = -40, Visible = false, Parent = muteBtn }, { round() })
muteBtn.Activated:Connect(function()
	musicMuted = not musicMuted
	muteSlash.Visible = musicMuted
	muteNote.TextColor3 = musicMuted and C.red or C.amber
	muteLabel.Text = musicMuted and "MUTED" or "MUSIC"
	muteLabel.TextColor3 = musicMuted and C.faint or C.text
	if muteStroke then
		muteStroke.Color = musicMuted and C.red or C.amber
		muteStroke.Transparency = musicMuted and 0.7 or 0.5
	end
	setMusic(musicWanted)
	sfx("click")
end)

end -- scope
---------------------------------------------------------------- lobby
local lobby, lobbyCol, openModal, playKey, profLevel, profXP, rankChip, rankChipText, wlText, xpFill
do
-- (declared above) local openModal -- forward

lobby = make("Frame", { Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
make("Frame", {
	BackgroundColor3 = C.s0,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(-600, -600),
	Size = UDim2.new(0, 1700, 1, 1200),
	Parent = lobby,
}, {
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.04),
			NumberSequenceKeypoint.new(0.58, 0.12),
			NumberSequenceKeypoint.new(0.8, 0.62),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

lobbyCol = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(0, 430, 1, 0), Parent = lobby })
local col = lobbyCol

-- logo: WORD on cream tiles, DUEL on amber tiles, slightly tumbled
tileWord(col, "WORD", 58, 8, { position = UDim2.fromOffset(0, 40), rotations = { -4, 2, -2, 3 } })
tileWord(col, "DUEL", 58, 8, { position = UDim2.fromOffset(34, 108), rotations = { 3, -3, 2, -2 }, face = C.amber, lip = C.amberLip })
text({ Text = "Keep a letter in place. Beat the clock.", FontFace = F.medium, TextSize = 18, TextColor3 = C.dim, Position = UDim2.fromOffset(2, 186), Size = UDim2.fromOffset(430, 24), Parent = col })

-- profile card
local profileCard = panel({ BackgroundTransparency = 0.08, Position = UDim2.fromOffset(0, 226), Size = UDim2.fromOffset(430, 108), Parent = col })
local _, setMyAvatar = avatar(profileCard, 70, UDim2.fromOffset(18, 19))
setMyAvatar(player.UserId, player.DisplayName)
text({ Text = player.DisplayName, FontFace = F.heavy, TextSize = 22, Position = UDim2.fromOffset(104, 16), Size = UDim2.fromOffset(210, 28), TextTruncate = Enum.TextTruncate.AtEnd, Parent = profileCard })
profLevel = text({ Text = "LV 1", FontFace = F.display, TextSize = 22, TextColor3 = C.amber, TextXAlignment = RIGHT, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 14), Size = UDim2.fromOffset(100, 28), Parent = profileCard })
profXP = text({ Text = "0 / 100 XP", FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, TextXAlignment = RIGHT, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 44), Size = UDim2.fromOffset(110, 18), Parent = profileCard })
local profRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(104, 46), Size = UDim2.fromOffset(220, 26), Parent = profileCard }, { list(H, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
rankChip, rankChipText = chip(profRow, "BRONZE 1000", C.amber, 1)
_, wlText = chip(profRow, "0W  0L", C.dim, 2)
local xpBack = make("Frame", { BackgroundColor3 = C.s3, Position = UDim2.fromOffset(104, 84), Size = UDim2.new(1, -122, 0, 8), Parent = profileCard }, { round() })
xpFill = make("Frame", { BackgroundColor3 = C.white, Size = UDim2.fromScale(0, 1), Parent = xpBack }, { round(), make("UIGradient", { Color = ColorSequence.new(lighten(C.amber, 0.3), C.amber) }) })

-- main actions
playKey = newKey({
	text = "PLAY RANKED",
	sub = "Matched by level  -  Elo on the line",
	style = "primary",
	textSize = 26,
	size = UDim2.fromOffset(430, 86),
	position = UDim2.fromOffset(0, 356),
	parent = col,
	onClick = function()
		if not searching then
			fire("Queue")
			setSearching(true, { bracket = Config.BaseBracket, waited = 0 })
		end
	end,
})
newKey({
	text = "PRACTICE",
	sub = "vs a bot",
	style = "secondary",
	textSize = 19,
	size = UDim2.fromOffset(211, 66),
	position = UDim2.fromOffset(0, 456),
	parent = col,
	onClick = function()
		fire("PlayBot")
	end,
})
newKey({
	text = "FRIENDS",
	sub = "private table",
	style = "blue",
	textSize = 19,
	size = UDim2.fromOffset(211, 66),
	position = UDim2.fromOffset(219, 456),
	parent = col,
	onClick = function()
		openModal("friend")
	end,
})

-- dock
local dock = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 540), Size = UDim2.fromOffset(430, 88), Parent = col }, { list(H, 10) })
local dockItems = {
	{ "B", "BOOSTS", "belt" },
	{ "S", "SHOP", "shop" },
	{ "A", "AWARDS", "achievements" },
	{ "R", "RANKS", "leaderboard" },
	{ "?", "RULES", "howto" },
}
for i, d in ipairs(dockItems) do
	newKey({
		text = d[2],
		icon = d[1],
		style = "secondary",
		textSize = 12,
		size = UDim2.fromOffset(78, 86),
		order = i,
		parent = dock,
		onClick = function()
			if d[3] == "leaderboard" then
				fire("GetLeaderboard")
			end
			openModal(d[3])
		end,
	})
end

end -- scope
---------------------------------------------------------------- queue card
local queueCard = panel({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 16),
	Size = UDim2.fromOffset(560, 78),
	Visible = false,
	ZIndex = 50,
	Parent = root,
})
local spinTile = newTile(queueCard, "?", 44, { position = UDim2.fromOffset(18, 15) })
local queueTitle = text({ Text = "FINDING OPPONENT", FontFace = F.heavy, TextSize = 17, Position = UDim2.fromOffset(78, 16), Size = UDim2.fromOffset(240, 24), Parent = queueCard })
local queueSub = text({ Text = "", FontFace = F.bold, TextSize = 14, TextColor3 = C.faint, Position = UDim2.fromOffset(78, 42), Size = UDim2.fromOffset(240, 20), Parent = queueCard })
local queueBotKey = newKey({
	text = "VS BOT",
	style = "blue",
	textSize = 15,
	size = UDim2.fromOffset(104, 50),
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -134, 0, 13),
	parent = queueCard,
	onClick = function()
		fire("PlayBot")
	end,
})
queueBotKey.holder.Visible = false
newKey({
	text = "CANCEL",
	style = "secondary",
	textSize = 15,
	size = UDim2.fromOffset(104, 50),
	anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -18, 0, 13),
	parent = queueCard,
	onClick = function()
		fire("CancelQueue")
		setSearching(false)
	end,
})
task.spawn(function()
	local letters = "ABCDEFGHIJKLMNOPRSTUW"
	while true do
		task.wait(0.14)
		if queueCard.Visible then
			local i = math.random(#letters)
			spinTile.label.Text = letters:sub(i, i)
		end
	end
end)

---------------------------------------------------------------- modal sheet
local ITEM_GLYPH, closeModal, refreshModal, checkNextModal, welcomeLayer, welcomeShown, welcomePending
welcomeShown = false
welcomePending = false
do
local modalLayer = make("Frame", { Name = "Modal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = root })
local modalScrim = scrim(modalLayer, 0.3)
local sheet = panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromOffset(680, 560),
	BackgroundColor3 = C.s1,
	radius = 22,
	Parent = modalLayer,
})
local sheetScale = make("UIScale", { Parent = sheet })
local modalTitle = text({ Text = "", FontFace = F.display, TextSize = 30, Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -120, 0, 36), Parent = sheet })
local modalSub = text({ Text = "", FontFace = F.medium, TextSize = 15, TextColor3 = C.faint, Position = UDim2.fromOffset(28, 58), Size = UDim2.new(1, -120, 0, 20), Parent = sheet })
local closeBtn = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.s3, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 22), Size = UDim2.fromOffset(42, 42), Parent = sheet }, { round() })
for _, rot in ipairs({ 45, -45 }) do
	make("Frame", { BackgroundColor3 = C.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 3), Rotation = rot, Parent = closeBtn }, { round() })
end
make("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.92, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 1), Parent = sheet })
local modalBody = make("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(24, 108),
	Size = UDim2.new(1, -36, 1, -124),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = C.faint,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = sheet,
})
local currentModal = nil
local beltDraft = nil
local renderers = {}

closeModal = function()
	modalLayer.Visible = false
	currentModal = nil
	beltDraft = nil
	if checkNextModal then
		checkNextModal()
	end
end
closeBtn.Activated:Connect(function()
	sfx("click")
	closeModal()
end)
modalScrim.Activated:Connect(closeModal)

local function clearBody()
	clearChildren(modalBody)
	list(V, 14).Parent = modalBody
	pad(16, 16, 12, 16).Parent = modalBody
end

local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

local function section(str)
	text({ Text = string.upper(str), FontFace = F.heavy, TextSize = 13, TextColor3 = C.faint, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder(), Parent = modalBody })
end

local function para(str, color)
	return text({
		Text = str,
		FontFace = F.medium,
		TextSize = 16,
		TextColor3 = color or C.dim,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = nextOrder(),
		Parent = modalBody,
	})
end

local function card(height, parent)
	return make("Frame", { BackgroundColor3 = C.s2, Size = UDim2.new(1, 0, 0, height), LayoutOrder = nextOrder(), Parent = parent or modalBody }, { corner(14), stroke(C.white, 0.93) })
end

local function grid(cellW, cellH)
	cellW = cellW or 290
	local g = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nextOrder(), Parent = modalBody })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cellW, cellH), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = g })
	return g
end

ITEM_GLYPH = { Help = "?", Skip = ">>", Time = "+5", DoubleShift = "2X" }

local function progressBar(parent, frac, position, size, color)
	local back = make("Frame", { BackgroundColor3 = C.s3, Position = position, Size = size, Parent = parent }, { round() })
	local actualFrac = math.clamp(frac or 0, 0, 1)
	local endowedFrac = actualFrac >= 1 and 1 or math.clamp(0.15 + 0.85 * actualFrac, 0.15, 1)
	make("Frame", { BackgroundColor3 = color or C.amber, Size = UDim2.fromScale(endowedFrac, 1), Parent = back }, { round() })
	return back
end

-- SHOP ------------------------------------------------------------------------
renderers.shop = function()
	modalTitle.Text = "Shop"
	modalSub.Text = "Stock up on boosts, expand your belt, or top up your coins."
	local inv = profile and profile.inventory or {}

	section("Your stash")
	local invRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = nextOrder(), Parent = modalBody }, { list(H, 10) })
	for i, k in ipairs(Config.ItemOrder) do
		local c = make("Frame", { BackgroundColor3 = C.s2, Size = UDim2.fromOffset(146, 52), LayoutOrder = i, Parent = invRow }, { corner(12), stroke(C.white, 0.93) })
		newTile(c, ITEM_GLYPH[k], 32, { position = UDim2.fromOffset(10, 8) })
		text({ Text = "x" .. (inv[k] or 0), FontFace = F.display, TextSize = 20, Position = UDim2.fromOffset(52, 6), Size = UDim2.fromOffset(84, 24), Parent = c })
		text({ Text = string.upper(Config.Items[k].name), FontFace = F.heavy, TextSize = 10, TextColor3 = C.faint, Position = UDim2.fromOffset(52, 29), Size = UDim2.fromOffset(90, 14), Parent = c })
	end

	-- TOP UP COINS (ROBUX)
	section("Top Up Coins (Robux)")
	local cg = grid(290, 96)
	local coinOrder = 0
	for _, p in ipairs(Config.Products) do
		if p.isCoins then
			coinOrder += 1
			local c = make("Frame", { BackgroundColor3 = C.s2, LayoutOrder = coinOrder, Parent = cg }, { corner(16), stroke(C.amber, 0.5, 1.5) })
			local ic = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 20), Size = UDim2.fromOffset(46, 46), Parent = c })
			coinIcon(ic, 46)
			text({ Text = p.label, FontFace = F.display, TextSize = 18, Position = UDim2.fromOffset(74, 20), Size = UDim2.fromOffset(148, 24), Parent = c })
			text({ Text = "Instant coin top-up", FontFace = F.bold, TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(74, 46), Size = UDim2.fromOffset(148, 16), Parent = c })
			local ready = p.id ~= 0 or IS_STUDIO
			local key = newKey({
				text = ready and ("R$ " .. p.robux) or "SOON",
				style = "success",
				textSize = 15,
				size = UDim2.fromOffset(98, 48),
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -12, 0.5, 0),
				parent = c,
				onClick = function()
					fire("BuyProduct", p.key)
				end,
			})
			if not ready then
				key:setEnabled(false)
			end
		end
	end

	-- BUY BOOSTS WITH COINS
	section("Buy Boosts (In-Game Coins)")
	local g = grid(290, 132)
	for i, k in ipairs(Config.ItemOrder) do
		local c = make("Frame", { BackgroundColor3 = C.s2, LayoutOrder = i, Parent = g }, { corner(16), stroke(C.white, 0.93) })
		newTile(c, ITEM_GLYPH[k], 46, { position = UDim2.fromOffset(16, 16) })
		text({ Text = Config.Items[k].name, FontFace = F.heavy, TextSize = 18, Position = UDim2.fromOffset(74, 18), Size = UDim2.fromOffset(110, 22), Parent = c })
		text({ Text = "Owned " .. (inv[k] or 0), FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, Position = UDim2.fromOffset(74, 42), Size = UDim2.fromOffset(110, 18), Parent = c })
		text({ Text = Config.Items[k].desc, FontFace = F.medium, TextSize = 13, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 44), Parent = c })
		local price = Config.CoinPrices[k]
		local affordable = profile and profile.coins >= price
		local key = newKey({
			text = Config.FormatNumber(price),
			style = affordable and "primary" or "secondary",
			textSize = 15,
			size = UDim2.fromOffset(116, 46),
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -14, 0, 14),
			parent = c,
			onClick = function()
				if affordable then
					fire("BuyCoins", k)
				else
					sfx("bad")
					toast("Need " .. Config.FormatNumber(price) .. " coins! Play duels or top up above.")
				end
			end,
		})
		key.title.Position = UDim2.fromOffset(12, 0)
		coinIcon(key.face, 18, UDim2.new(0, 10, 0.5, -9))
	end

	-- BELT UPGRADES (COINS OR ROBUX)
	if profile and profile.slots < Config.MaxSlots then
		local nextSlot = profile.slots + 1
		local coinPrice = Config.SlotCoinPrices[nextSlot]
		local levelReq = Config.SlotLevels[nextSlot]
		local robuxProduct = nil
		for _, p in ipairs(Config.Products) do
			if p.slot == nextSlot then
				robuxProduct = p
				break
			end
		end

		section("Belt Expansion: Slot " .. nextSlot)
		local slotCard = panel({ Size = UDim2.new(1, 0, 0, 84), LayoutOrder = nextOrder(), Parent = modalBody })
		newTile(slotCard, tostring(nextSlot), 50, { position = UDim2.fromOffset(16, 17), face = C.amber, lip = C.amberLip })
		text({ Text = "Unlock Boost Slot " .. nextSlot, FontFace = F.heavy, TextSize = 18, Position = UDim2.fromOffset(80, 16), Size = UDim2.new(0.4, 0, 0, 24), Parent = slotCard })
		text({ Text = "Free at LV " .. (levelReq or 20) .. "  •  Or unlock now:", FontFace = F.bold, TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(80, 42), Size = UDim2.new(0.4, 0, 0, 20), Parent = slotCard })

		local btnRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(264, 48), Parent = slotCard }, { list(H, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
		if coinPrice then
			local affordable = profile.coins >= coinPrice
			local coinBtn = newKey({
				text = Config.FormatNumber(coinPrice),
				style = affordable and "primary" or "secondary",
				textSize = 14,
				size = UDim2.fromOffset(128, 48),
				parent = btnRow,
				onClick = function()
					if affordable then
						fire("BuySlotCoins", nextSlot)
					else
						sfx("bad")
						toast("Need " .. Config.FormatNumber(coinPrice) .. " coins! Play duels or top up above.")
					end
				end,
			})
			coinBtn.title.Position = UDim2.fromOffset(12, 0)
			coinIcon(coinBtn.face, 18, UDim2.new(0, 8, 0.5, -9))
		end
		if robuxProduct then
			local ready = robuxProduct.id ~= 0 or IS_STUDIO
			newKey({
				text = ready and ("R$ " .. robuxProduct.robux) or "SOON",
				style = "success",
				textSize = 15,
				size = UDim2.fromOffset(104, 48),
				parent = btnRow,
				onClick = function()
					fire("BuyProduct", robuxProduct.key)
				end,
			})
		end
	end

	-- ROBUX ITEM PACKS
	section("Item Packs (Robux)")
	local rg = grid(290, 92)
	local o = 0
	for _, p in ipairs(Config.Products) do
		if not p.isCoins and not p.slot then
			o += 1
			local c = make("Frame", { BackgroundColor3 = C.s2, LayoutOrder = o, Parent = rg }, { corner(16), stroke(C.white, 0.93) })
			local glyph = ITEM_GLYPH[next(p.grant or {})] or "+"
			newTile(c, glyph, 46, { position = UDim2.fromOffset(16, 20), face = C.cream, lip = C.creamLip })
			text({ Text = p.label, FontFace = F.heavy, TextSize = 17, Position = UDim2.fromOffset(74, 24), Size = UDim2.fromOffset(110, 22), TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
			text({ Text = "Item pack", FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, Position = UDim2.fromOffset(74, 48), Size = UDim2.fromOffset(110, 18), Parent = c })
			local ready = p.id ~= 0 or IS_STUDIO
			local key = newKey({
				text = ready and ("R$ " .. p.robux) or "SOON",
				style = "success",
				textSize = 16,
				size = UDim2.fromOffset(104, 50),
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -14, 0.5, -2),
				parent = c,
				onClick = function()
					fire("BuyProduct", p.key)
				end,
			})
			if not ready then
				key:setEnabled(false)
			end
		end
	end
end

-- BELT ------------------------------------------------------------------------
local activeBeltSlot = nil

renderers.belt = function()
	modalTitle.Text = "Boost Belt Loadout"
	modalSub.Text = "Choose power-ups to take into duels. You can activate them on your turn to win the match."
	if not profile then
		return
	end
	beltDraft = beltDraft or table.clone(profile.belt or {})

	-- How it works helper card
	local banner = make("Frame", {
		BackgroundColor3 = C.s2,
		Size = UDim2.new(1, 0, 0, 70),
		LayoutOrder = nextOrder(),
		Parent = modalBody,
	}, { corner(14), stroke(C.amber, 0.4, 1.5), pad(14, 14, 10, 10) })
	text({ Text = "HOW YOUR BELT WORKS IN DUELS", FontFace = F.heavy, TextSize = 12, TextColor3 = C.amber, Size = UDim2.new(1, 0, 0, 16), Parent = banner })
	text({
		Text = "• BASE SLOTS: Ready on Move 1 of every match.\n• CLUTCH SLOTS (Gold): Emergency slots that unlock mid-match when your clock drops below 7s / 5s!",
		FontFace = F.bold,
		TextSize = 12,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = banner,
	})

	-- If user is selecting a boost for a specific slot: show intuitive boost selector
	if activeBeltSlot then
		section("Select Boost for Slot " .. activeBeltSlot)
		text({
			Text = "Tap a boost below to equip it into Slot " .. activeBeltSlot .. ":",
			FontFace = F.bold,
			TextSize = 13,
			TextColor3 = C.text,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = nextOrder(),
			Parent = modalBody,
		})

		for _, k in ipairs(Config.ItemOrder) do
			local item = Config.Items[k]
			local count = (profile.inventory and profile.inventory[k]) or 0
			local row = panel({
				Size = UDim2.new(1, 0, 0, 68),
				LayoutOrder = nextOrder(),
				Parent = modalBody,
			})
			newTile(row, ITEM_GLYPH[k] or "?", 48, { position = UDim2.fromOffset(12, 10) })
			text({ Text = item.name, FontFace = F.heavy, TextSize = 16, Position = UDim2.fromOffset(72, 12), Size = UDim2.new(0.5, 0, 0, 20), Parent = row })
			text({ Text = item.desc, FontFace = F.bold, TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(72, 34), Size = UDim2.new(0.55, 0, 0, 24), Parent = row })
			text({ Text = "Own: " .. count, FontFace = F.heavy, TextSize = 13, TextColor3 = count > 0 and C.teal or C.faint, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -125, 0, 24), Size = UDim2.fromOffset(70, 20), Parent = row })

			newKey({
				text = "EQUIP",
				style = "primary",
				textSize = 14,
				size = UDim2.fromOffset(105, 46),
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -12, 0.5, 0),
				parent = row,
				onClick = function()
					beltDraft[activeBeltSlot] = k
					activeBeltSlot = nil
					sfx("click")
					openModal("belt", true)
				end,
			})
		end

		-- Clear slot option & cancel
		local cancelRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = nextOrder(), Parent = modalBody }, { list(H, 12) })
		newKey({
			text = "REMOVE ITEM",
			style = "secondary",
			textSize = 14,
			size = UDim2.fromOffset(160, 44),
			parent = cancelRow,
			onClick = function()
				beltDraft[activeBeltSlot] = nil
				activeBeltSlot = nil
				sfx("bad")
				openModal("belt", true)
			end,
		})
		newKey({
			text = "CANCEL",
			style = "secondary",
			textSize = 14,
			size = UDim2.fromOffset(120, 44),
			parent = cancelRow,
			onClick = function()
				activeBeltSlot = nil
				openModal("belt", true)
			end,
		})
		return
	end

	section("Belt Slots")
	local g = grid(188, 216)
	for slot = 1, Config.MaxSlots + #Config.FastSlotClocks do
		local fastAt = (slot > profile.slots) and Config.FastSlotClocks[slot - profile.slots] or nil
		local unlocked = slot <= profile.slots or fastAt ~= nil
		local c = make("Frame", {
			BackgroundColor3 = unlocked and C.s2 or C.s1,
			LayoutOrder = slot,
			Parent = g,
		}, { corner(16), stroke(fastAt and C.amber or (unlocked and C.teal or C.white), fastAt and 0.6 or (unlocked and 0.8 or 0.95), fastAt and 1.5 or 1) })

		local tagText = fastAt and ("CLUTCH <" .. fastAt .. "s") or ("SLOT " .. slot .. " • START")
		text({
			Text = tagText,
			FontFace = F.heavy,
			TextSize = 10,
			TextColor3 = fastAt and C.amber or (unlocked and C.teal or C.faint),
			TextXAlignment = CENTER,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = c,
		})

		if unlocked then
			local current = beltDraft[slot]
			if not current or current == "None" or not Config.Items[current] then
				-- Empty socket
				local socket = make("Frame", { BackgroundColor3 = C.s1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 36), Size = UDim2.fromOffset(56, 56), Parent = c }, { corner(12), stroke(C.white, 0.8, 1.5) })
				text({ Text = "+", FontFace = F.display, TextSize = 26, TextColor3 = C.faint, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = socket })
				text({ Text = "Empty", FontFace = F.heavy, TextSize = 15, TextColor3 = C.dim, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 18), Parent = c })
				text({ Text = "Tap to choose", FontFace = F.bold, TextSize = 11, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 14), Parent = c })
				newKey({
					text = "EQUIP",
					style = "primary",
					textSize = 14,
					size = UDim2.fromOffset(122, 44),
					anchor = Vector2.new(0.5, 0),
					position = UDim2.new(0.5, 0, 0, 154),
					parent = c,
					onClick = function()
						activeBeltSlot = slot
						openModal("belt", true)
					end,
				})
			else
				-- Equipped item
				newTile(c, ITEM_GLYPH[current] or "?", 56, { position = UDim2.new(0.5, -28, 0, 34) })
				text({ Text = Config.Items[current].name, FontFace = F.heavy, TextSize = 15, TextColor3 = C.text, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 18), Parent = c })
				local count = (profile.inventory and profile.inventory[current]) or 0
				text({ Text = count .. " in bag", FontFace = F.bold, TextSize = 11, TextColor3 = count > 0 and C.teal or C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 14), Parent = c })
				newKey({
					text = "CHANGE",
					style = "secondary",
					textSize = 13,
					size = UDim2.fromOffset(122, 44),
					anchor = Vector2.new(0.5, 0),
					position = UDim2.new(0.5, 0, 0, 154),
					parent = c,
					onClick = function()
						activeBeltSlot = slot
						openModal("belt", true)
					end,
				})
			end
		else
			-- Locked
			local lockT = newTile(c, "LV", 56, { position = UDim2.new(0.5, -28, 0, 34), face = C.s3, lip = C.s0 })
			lockT.label.TextColor3 = C.faint
			lockT.label.TextSize = 18
			text({ Text = "Locked Slot", FontFace = F.heavy, TextSize = 14, TextColor3 = C.dim, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 18), Parent = c })
			local coinP = Config.SlotCoinPrices[slot]
			local subP = coinP and (Config.FormatNumber(coinP) .. "c or LV " .. (Config.SlotLevels[slot] or 20)) or ("LV " .. (Config.SlotLevels[slot] or 20))
			text({ Text = subP, FontFace = F.bold, TextSize = 11, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 16), Parent = c })
			if slot == profile.slots + 1 then
				newKey({
					text = "UNLOCK",
					style = "success",
					textSize = 12,
					size = UDim2.fromOffset(122, 40),
					anchor = Vector2.new(0.5, 0),
					position = UDim2.new(0.5, 0, 0, 154),
					parent = c,
					onClick = function()
						openModal("shop", true)
					end,
				})
			end
		end
	end

	-- Directory of boosts
	section("Boost Directory & Inventory")
	for _, k in ipairs(Config.ItemOrder) do
		local item = Config.Items[k]
		local count = (profile.inventory and profile.inventory[k]) or 0
		local card = panel({ Size = UDim2.new(1, 0, 0, 64), LayoutOrder = nextOrder(), Parent = modalBody })
		newTile(card, ITEM_GLYPH[k] or "?", 46, { position = UDim2.fromOffset(12, 9) })
		text({ Text = item.name, FontFace = F.heavy, TextSize = 15, Position = UDim2.fromOffset(68, 12), Size = UDim2.new(0.5, 0, 0, 18), Parent = card })
		text({ Text = item.desc, FontFace = F.bold, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(68, 32), Size = UDim2.new(0.65, 0, 0, 24), Parent = card })
		text({ Text = "Owned: " .. count, FontFace = F.heavy, TextSize = 13, TextColor3 = count > 0 and C.teal or C.faint, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(80, 20), Parent = card })
	end

	-- Save button
	local save = newKey({
		text = "SAVE BELT LOADOUT",
		style = "primary",
		textSize = 18,
		size = UDim2.new(1, 0, 0, 58),
		order = nextOrder(),
		parent = modalBody,
		onClick = function()
			fire("SetBelt", beltDraft)
			closeModal()
			toast("Belt loadout saved!", C.teal)
		end,
	})
	save.holder.LayoutOrder = nextOrder()
end

-- ACHIEVEMENTS ----------------------------------------------------------------
renderers.achievements = function()
	modalTitle.Text = "Awards & Records"
	modalSub.Text = "Your personal bests, and every medal you can win."
	if not profile then
		return
	end
	section("Records")
	local recGrid = grid(139, 114)
	local recs = {
		{ "LONGEST WORD", (profile.bestWordLen or 0) > 0 and string.upper(profile.bestWord or "") or "-", (profile.bestWordLen or 0) .. " letters" },
		{ "IN A ROW", tostring(profile.longStreakBest or 0), "long words" },
		{ "LONG WORDS", tostring(profile.longWords or 0), "7+ letters" },
		{ "BEST SCORE", tostring(profile.bestScore or 0), "one match" },
	}
	for i, r in ipairs(recs) do
		local c = make("Frame", { BackgroundColor3 = C.s2, LayoutOrder = i, Parent = recGrid }, { corner(16), stroke(C.amber, 0.75) })
		Icon.trophy(c, 36, UDim2.new(0.5, -18, 0, 8))
		text({ Text = r[2], FontFace = F.display, TextSize = 18, TextColor3 = C.amber, TextXAlignment = CENTER, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 48), Size = UDim2.new(1, -12, 0, 24), Parent = c })
		text({ Text = r[1], FontFace = F.heavy, TextSize = 10, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 14), Parent = c })
		text({ Text = r[3], FontFace = F.bold, TextSize = 11, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 14), Parent = c })
	end
	local earned = 0
	for _, a in ipairs(Config.Achievements) do
		if profile.achievements[a.id] then
			earned += 1
		end
	end
	section("Medals   " .. earned .. " / " .. #Config.Achievements)
	local g = grid(290, 104)
	for i, a in ipairs(Config.Achievements) do
		local done = profile.achievements[a.id] ~= nil
		local value = math.min(profile[a.stat] or 0, a.goal)
		local c = make("Frame", { BackgroundColor3 = done and C.s2 or C.s1, LayoutOrder = i, Parent = g }, { corner(16), stroke(done and C.amber or C.white, done and 0.55 or 0.93) })
		Icon.medal(c, 56, UDim2.fromOffset(12, 16), done)
		text({ Text = a.name, FontFace = F.heavy, TextSize = 15, TextColor3 = done and C.amber or C.text, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(80, 12), Size = UDim2.new(1, -92, 0, 20), Parent = c })
		text({ Text = a.desc, FontFace = F.medium, TextSize = 12, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(80, 33), Size = UDim2.new(1, -92, 0, 30), Parent = c })
		local actualFrac = math.clamp(value / a.goal, 0, 1)
		local endowedFrac = done and 1 or math.clamp(0.15 + 0.85 * actualFrac, 0.15, 1)
		local bar = make("Frame", { BackgroundColor3 = C.s0, Position = UDim2.fromOffset(80, 70), Size = UDim2.new(1, -92, 0, 18), Parent = c }, { round() })
		make("Frame", { BackgroundColor3 = done and C.amber or C.blue, Size = UDim2.fromScale(endowedFrac, 1), Parent = bar }, { round() })
		text({ Text = done and "WON" or (value .. " / " .. a.goal), FontFace = F.heavy, TextSize = 11, TextColor3 = C.white, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = bar })
	end
end

-- LEADERBOARD -----------------------------------------------------------------
renderers.leaderboard = function()
	modalTitle.Text = "Rankings"
	modalSub.Text = "Global, across every server."
	local tabs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = nextOrder(), Parent = modalBody }, { list(H, 10) })
	for i, t in ipairs({ { "elo", "ELO" }, { "streak", "KING RUN" }, { "longest", "LONGEST" }, { "longrun", "IN A ROW" }, { "longwords", "LONG WORDS" }, { "score", "BEST SCORE" } }) do
		local k = newKey({
			text = t[2],
			style = lbTab == t[1] and "primary" or "secondary",
			textSize = 11,
			size = UDim2.fromOffset(96, 44),
			order = i,
			parent = tabs,
			onClick = function()
				lbTab = t[1]
				openModal("leaderboard", true)
			end,
		})
		k.holder.LayoutOrder = i
	end
	local entries = leaderboard[lbTab] or {}
	if #entries == 0 then
		local c = card(90)
		text({ Text = "No entries yet", FontFace = F.heavy, TextSize = 18, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 24), Parent = c })
		text({ Text = "Rankings fill in once the game is published and people play ranked.", FontFace = F.medium, TextSize = 14, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 20), Parent = c })
	end
	local medal = { C.amber, rgb(200, 206, 216), rgb(205, 140, 90) }
	for _, e in ipairs(entries) do
		local c = card(56)
		local badge = make("Frame", { BackgroundColor3 = medal[e.rank] or C.s3, Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(34, 34), Parent = c }, { round() })
		text({ Text = tostring(e.rank), FontFace = F.display, TextSize = 15, TextColor3 = medal[e.rank] and C.ink or C.dim, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = badge })
		text({ Text = e.name, FontFace = F.heavy, TextSize = 17, Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -200, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
		text({ Text = tostring(e.value), FontFace = F.display, TextSize = 19, TextColor3 = C.amber, TextXAlignment = RIGHT, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 0), Size = UDim2.fromOffset(120, 56), Parent = c })
	end
end

-- FRIEND TABLE ----------------------------------------------------------------
local codeBox
renderers.friend = function()
	modalTitle.Text = "Friend Table"
	modalSub.Text = "Unranked. Invite a friend and you both get a bonus when they reach level " .. Config.ReferralLevel .. "."
	section("Host")
	if privateCode then
		local c = card(150)
		text({ Text = "YOUR TABLE CODE", FontFace = F.heavy, TextSize = 12, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 16), Parent = c })
		tileWord(c, privateCode, 54, 8, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 38), face = C.amber, lip = C.amberLip })
		text({ Text = "Waiting for your friend to join...", FontFace = F.medium, TextSize = 14, TextColor3 = C.dim, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 18), Parent = c })
		newKey({ text = "CLOSE TABLE", style = "danger", textSize = 16, size = UDim2.new(1, 0, 0, 52), order = nextOrder(), parent = modalBody, onClick = function()
			fire("CancelPrivate")
		end }).holder.LayoutOrder = nextOrder()
	else
		newKey({ text = "OPEN A TABLE", sub = "get a 5-letter code to share", style = "primary", textSize = 18, size = UDim2.new(1, 0, 0, 68), parent = modalBody, onClick = function()
			fire("CreatePrivate")
		end }).holder.LayoutOrder = nextOrder()
	end
	newKey({ text = "INVITE ROBLOX FRIENDS", style = "blue", textSize = 16, size = UDim2.new(1, 0, 0, 54), parent = modalBody, onClick = function()
		fire("GetInviteData")
	end }).holder.LayoutOrder = nextOrder()

	section("Join")
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = nextOrder(), Parent = modalBody })
	codeBox = make("TextBox", {
		PlaceholderText = "ENTER CODE",
		Text = "",
		FontFace = F.display,
		TextSize = 24,
		TextColor3 = C.text,
		PlaceholderColor3 = C.faint,
		BackgroundColor3 = C.s0,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -150, 0, 56),
		Parent = row,
	}, { corner(14), stroke(C.white, 0.85) })
	newKey({ text = "JOIN", style = "success", textSize = 18, size = UDim2.fromOffset(138, 61), anchor = Vector2.new(1, 0), position = UDim2.new(1, 0, 0, 0), parent = row, onClick = function()
		fire("JoinPrivate", codeBox.Text)
	end })
end

-- HOW TO PLAY -----------------------------------------------------------------
renderers.howto = function()
	modalTitle.Text = "How to Play"
	modalSub.Text = "Fast to learn. Hard to master."
	newKey({ text = "PLAY THE TUTORIAL", sub = "a relaxed practice game with a coach", style = "primary", textSize = 18, size = UDim2.new(1, 0, 0, 66), parent = modalBody, onClick = function()
		closeModal()
		fire("StartTutorial")
	end }).holder.LayoutOrder = nextOrder()
	newKey({ text = "WHAT THE ICONS MEAN", sub = "coins, items, medals, records, King", style = "secondary", textSize = 16, size = UDim2.new(1, 0, 0, 62), parent = modalBody, onClick = function()
		openModal("guide")
	end }).holder.LayoutOrder = nextOrder()
	local ex = card(96)
	local exRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), Parent = ex }, { list(H, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local chain = { "TREAD", "STEAL", "CREED" }
	for i, w in ipairs(chain) do
		tileWord(exRow, w, 30, 3, { order = i * 2 })
		if i < #chain then
			text({ Text = ">", FontFace = F.display, TextSize = 22, TextColor3 = C.amber, TextXAlignment = CENTER, Size = UDim2.fromOffset(16, 40), LayoutOrder = i * 2 + 1, Parent = exRow })
		end
	end
	local steps = {
		{ "Keep a letter, score points", "Play any real word (3 to 8 letters) that keeps at least one letter in the same spot as the last word. Every kept letter and every letter you add is a point: TREAD -> STEAL = 2, CAT -> CATER = 5." },
		{ "No cheap moves", "No lazy suffix tricks: plurals, past tense, -ing, -er, -ly, -ness and similar. DANCE→DANCER, HAND→HANDY, CATS→CAT - all blocked. Words can only be played once per match." },
		{ "Faster and faster", "Your clock starts at 12s (faster at higher levels) and shrinks every move - quickly at first, then more gently - but never below 3.5s. Run out and you lose." },
		{ "Letter locks", "At level " .. Config.LetterLockLevel .. "+, once a rally is fast, 1-2 letters are sometimes locked for a few turns - different ones each turn. You can't play a word that uses them." },
		{ "Brilliant moves", "Words with Q, Z, X or J earn bonus XP and shards. " .. Config.ShardsPerHelp .. " shards make 1 Hint." },
		{ "Elo & Ranked Duels", "Ranked matches put your Elo rating on the line. Beat rivals to gain Elo and climb from Bronze (1000) to Silver, Gold, Platinum, Diamond, and Master. Casual Practice against bots never affects your Elo." },
		{ "King of the Table", "Win a ranked duel and you keep the table: a new challenger sits down automatically and starts from your last word. Every defense grows your streak and bonuses. Tap LEAVE TABLE any time - you keep everything." },
		{ "Boosts", "Hint shows a word that scores (max 2 per match, not twice in a row). Pass hands the word back. Time Boost adds 5 seconds. Double Points doubles your next word. Your belt decides how many you bring; faster games open 2 extra slots, and used slots refill after a few turns." },
		{ "Grow", "Level up for longer words: 3 letters at first, up to 6 at level 30." },
	}
	for i, s in ipairs(steps) do
		local c = make("Frame", { BackgroundColor3 = C.s2, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nextOrder(), Parent = modalBody }, { corner(14), stroke(C.white, 0.93), pad(66, 16, 14, 14) })
		local n = make("Frame", { BackgroundColor3 = C.amber, Position = UDim2.fromOffset(-50, 0), Size = UDim2.fromOffset(34, 34), Parent = c }, { round() })
		text({ Text = tostring(i), FontFace = F.display, TextSize = 16, TextColor3 = C.ink, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = n })
		local inner = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), Parent = c }, { list(V, 2) })
		text({ Text = s[1], FontFace = F.heavy, TextSize = 17, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 1, Parent = inner })
		text({ Text = s[2], FontFace = F.medium, TextSize = 15, TextColor3 = C.dim, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = inner })
	end
end

-- ICON GUIDE ------------------------------------------------------------------
renderers.guide = function()
	modalTitle.Text = "What the icons mean"
	modalSub.Text = "You'll see these whenever you earn something."
	local rows = {
		{ function(p) coinIcon(p, 46) end, "Coins", "Earned every word and every match. Spend them in the Shop." },
		{ function(p) Icon.item(p, 46, nil, "Help") end, "Hint", "Boost: shows a word that scores right now." },
		{ function(p) Icon.item(p, 46, nil, "Skip") end, "Pass", "Boost: hands the same word back to your rival." },
		{ function(p) Icon.item(p, 46, nil, "Time") end, "Time Boost", "Boost: +5 seconds on your clock." },
		{ function(p) Icon.item(p, 46, nil, "DoubleShift") end, "Double Points", "Boost: your next word scores double." },
		{ function(p) newTile(p, "+", 46, { face = C.amber, lip = C.amberLip }) end, "Boost Belt", "You bring as many boosts as your belt has slots. Under 7s and 5s on the clock, 2 extra slots open. Used ones refill after 3 of your turns, from what you own." },
		{ function(p) gemIcon(p, 46) end, "Shards", "From Q, Z, X or J words. " .. Config.ShardsPerHelp .. " shards make a Hint." },
		{ function(p) Icon.chest(p, 46) end, "Daily chest", "Play every day - the chest grows with your streak." },
		{ function(p) Icon.medal(p, 46, nil, true) end, "Medal", "A permanent award. Each one pays out once." },
		{ function(p) Icon.trophy(p, 46) end, "Record", "You beat your own personal best." },
		{ function(p) newTile(p, "R", 46, { face = C.teal, lip = C.tealLip }) end, "Elo & Rank", "Your competitive skill rating in Ranked duels (starts at 1000). Win matches to gain Elo and rank up from Bronze to Master!" },
		{ function(p) Icon.crown(p, 46) end, "King of the Table", "Win ranked and you keep the table: a new challenger sits down automatically. Leave any time - you keep everything." },
		{ function(p) Icon.level(p, 46, nil, 5) end, "Level", "Levels unlock belt slots and longer start words." },
	}
	for _, r in ipairs(rows) do
		local c = card(74)
		local ic = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(46, 46), Parent = c })
		r[1](ic)
		text({ Text = r[2], FontFace = F.heavy, TextSize = 17, Position = UDim2.fromOffset(76, 12), Size = UDim2.new(1, -90, 0, 22), Parent = c })
		text({ Text = r[3], FontFace = F.medium, TextSize = 14, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(76, 35), Size = UDim2.new(1, -90, 0, 34), Parent = c })
	end
end

openModal = function(name, keepPosition)
	local wasOpen = modalLayer.Visible and currentModal == name
	if name ~= "belt" then
		beltDraft = nil
	end
	currentModal = name
	local scroll = modalBody.CanvasPosition
	orderCounter = 0
	clearBody()
	renderers[name]()
	modalLayer.Visible = true
	if keepPosition and wasOpen then
		task.defer(function()
			modalBody.CanvasPosition = scroll
		end)
	else
		modalBody.CanvasPosition = Vector2.zero
		sheetScale.Scale = 0.94
		tween(sheetScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		sfx("whoosh")
	end
end

refreshModal = function()
	if modalLayer.Visible and currentModal and currentModal ~= "belt" then
		openModal(currentModal, true)
	end
end

end -- scope
---------------------------------------------------------------- match HUD
local cancelSearchKey, chainCount, chainList, chainPanel, chipsRow, currentGuess, deskInput, feedback, hud, itemsCol, matchFlashPos, modeTag, myPlate, oppPlate, scorePop, searchBotKey, searchControls, stage, statusLabel, submitKey, tilesRow, timerFill, timerText, touchInput, typeHintStroke, typeHintText, updatePreview, vs
do
hud = make("Frame", { Name = "Match", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
make("Frame", {
	BackgroundColor3 = C.s0,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(-600, -600),
	Size = UDim2.new(1, 1200, 1, 1200),
	Parent = hud,
}, {
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.45, 0.3),
			NumberSequenceKeypoint.new(0.75, 0.62),
			NumberSequenceKeypoint.new(1, 0.4),
		}),
	}),
})

local function plate(side)
	local right = side == "right"
	local f = panel({
		AnchorPoint = Vector2.new(right and 1 or 0, 0),
		Position = UDim2.new(right and 1 or 0, right and -16 or 16, 0, 14),
		Size = UDim2.fromOffset(340, 84),
		BackgroundTransparency = 0.04,
		Parent = hud,
	})
	local s = f:FindFirstChildOfClass("UIStroke")
	local _, setAv, setRig = avatar(f, 56, UDim2.new(right and 1 or 0, right and -70 or 14, 0, 14))
	local name = text({ Text = "", FontFace = F.heavy, TextSize = 20, TextXAlignment = right and RIGHT or LEFT, Position = UDim2.fromOffset(right and 14 or 84, 16), Size = UDim2.new(1, -98, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
	local info = text({ Text = "", FontFace = F.bold, TextSize = 14, TextXAlignment = right and RIGHT or LEFT, Position = UDim2.fromOffset(right and 14 or 84, 44), Size = UDim2.new(1, -98, 0, 20), Parent = f })
	local bar = make("Frame", { BackgroundColor3 = C.amber, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -36, 0, 4), Visible = false, Parent = f }, { round() })
	local tgtRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = UDim2.new(right and 1 or 0, right and -14 or 14, 0, 80), Size = UDim2.fromOffset(312, 30), Parent = f }, { list(H, 6, right and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	-- mine = amber tiles, rival = red tiles; dist = steps from the current word
	local function setTarget(word, dist, mine)
		clearChildren(tgtRow, "UIListLayout")
		if not word then
			f.Size = UDim2.fromOffset(340, 84)
			return
		end
		f.Size = UDim2.fromOffset(340, 120)
		text({ Text = mine and "YOUR WORD" or "THEIR WORD", FontFace = F.heavy, TextSize = 11, TextColor3 = C.faint, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 0, Parent = tgtRow })
		tileWord(tgtRow, word, 25, 3, { order = 1, face = mine and C.amber or C.red, lip = mine and C.amberLip or C.redLip, ink = mine and C.ink or C.white })
		local label = dist == nil and "FAR" or (dist == 1 and "1 STEP" or (dist .. " STEPS"))
		chip(tgtRow, label, mine and C.amber or C.red, 2)
	end
	local function setScore(score, double)
		clearChildren(tgtRow, "UIListLayout")
		f.Size = UDim2.fromOffset(340, 120)
		text({ Text = "SCORE", FontFace = F.heavy, TextSize = 11, TextColor3 = C.faint, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 0, Parent = tgtRow })
		text({ Text = tostring(score or 0), FontFace = F.display, TextSize = 24, TextColor3 = C.amber, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 1, Parent = tgtRow })
		if double then
			chip(tgtRow, "2X NEXT WORD", C.blue, 2)
		end
	end
	return { frame = f, stroke = s, setAvatar = setAv, setRig = setRig, name = name, info = info, bar = bar, setTarget = setTarget, setScore = setScore }
end
myPlate = plate("left")
oppPlate = plate("right")

-- "+2" pops next to that player's score instead of over the board
scorePop = function(mine, msg, color)
	local l = text({
		Text = msg,
		FontFace = F.display,
		TextSize = 26,
		TextColor3 = color,
		TextStrokeColor3 = C.s0,
		TextStrokeTransparency = 0.2,
		TextXAlignment = mine and LEFT or RIGHT,
		AnchorPoint = Vector2.new(mine and 0 or 1, 0.5),
		Position = UDim2.new(mine and 0 or 1, mine and 364 or -364, 0, 112),
		Size = UDim2.fromOffset(320, 32),
		ZIndex = 44,
		Parent = hud,
	})
	local sc = make("UIScale", { Scale = 0.5, Parent = l })
	tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(l, 1.1, { Position = l.Position - UDim2.fromOffset(0, 24) }, Enum.EasingStyle.Quad)
	task.delay(0.9, function()
		tween(l, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.35)
		l:Destroy()
	end)
end

-- where in-match call-outs go: under the input on PC, above the board on phones
matchFlashPos = function()
	return touchMode() and UDim2.new(0.5, 0, 0, 112) or UDim2.new(0.5, 0, 0, 600)
end
vs = make("Frame", { BackgroundColor3 = C.s1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(58, 58), Parent = hud }, { round(), stroke(C.white, 0.85, 2) })
text({ Text = "VS", FontFace = F.display, TextSize = 18, TextColor3 = C.dim, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = vs })
modeTag = text({ Text = "", FontFace = F.heavy, TextSize = 11, TextColor3 = C.amber, TextXAlignment = CENTER, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.fromOffset(160, 16), Parent = hud })

queueCancelBtn = make("TextButton", {
	Name = "QueueCancelBtn",
	Text = "CANCEL SEARCH",
	FontFace = F.heavy,
	TextSize = 11,
	TextColor3 = C.dim,
	BackgroundColor3 = C.s2,
	BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 108),
	Size = UDim2.fromOffset(130, 26),
	Visible = false,
	ZIndex = 10,
	Parent = hud,
}, { corner(13), stroke(C.white, 0.88, 1) })
queueCancelBtn.Activated:Connect(function()
	sfx("click")
	fire("CancelQueue")
	setSearching(false)
end)

queueBotBtn = make("TextButton", {
	Name = "QueueBotBtn",
	Text = "VS BOT (START NOW)",
	FontFace = F.heavy,
	TextSize = 11,
	TextColor3 = C.blue,
	BackgroundColor3 = C.s2,
	BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 138),
	Size = UDim2.fromOffset(150, 26),
	Visible = false,
	ZIndex = 10,
	Parent = hud,
}, { corner(13), stroke(C.blue, 0.6, 1) })
queueBotBtn.Activated:Connect(function()
	sfx("click")
	fire("PlayBot")
end)

-- left column: belt items
itemsCol = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 150), Size = UDim2.fromOffset(224, 540), Parent = hud }, { list(V, 8) })
-- right column: chain
chainPanel = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 152), Size = UDim2.fromOffset(200, 330), BackgroundTransparency = 0.1, Parent = hud })
text({ Text = "CHAIN", FontFace = F.heavy, TextSize = 12, TextColor3 = C.faint, Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(100, 16), Parent = chainPanel })
chainCount = text({ Text = "", FontFace = F.heavy, TextSize = 12, TextColor3 = C.faint, TextXAlignment = RIGHT, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 14), Size = UDim2.fromOffset(80, 16), Parent = chainPanel })
chainList = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 1, -52), ClipsDescendants = true, Parent = chainPanel }, { list(V, 6) })

-- stage (center)
stage = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(720, 560), Parent = hud })
statusLabel = text({ Text = "", FontFace = F.display, TextSize = 28, TextXAlignment = CENTER, Size = UDim2.new(1, 0, 0, 34), Parent = stage })
chipsRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 26), Parent = stage }, { list(H, 22, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
tilesRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 100), Parent = stage }, { list(H, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
timerText = text({ Text = "", FontFace = F.display, TextSize = 28, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 174), Size = UDim2.new(1, 0, 0, 28), Parent = stage })
local timerBack = make("Frame", { BackgroundColor3 = C.s2, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 204), Size = UDim2.fromOffset(600, 8), Parent = stage }, { round() })
timerFill = make("Frame", { BackgroundColor3 = C.teal, Size = UDim2.fromScale(1, 1), Parent = timerBack }, { round() })
local inputArea = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 262), Size = UDim2.new(1, 0, 0, 260), Parent = stage })
feedback = make("TextLabel", {
	Name = "Feedback",
	Text = "",
	FontFace = F.heavy,
	TextSize = 13,
	TextColor3 = C.text,
	TextXAlignment = CENTER,
	BackgroundColor3 = C.s1,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 232),
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 28),
	Visible = false,
	ZIndex = 15,
	Parent = stage,
}, { corner(14), stroke(C.red, 1, 1.5), pad(18, 18, 5, 5) })
local feedbackStroke = feedback:FindFirstChildOfClass("UIStroke")
local feedbackClearToken = 0
feedback:GetPropertyChangedSignal("Text"):Connect(function()
	local t = feedback.Text
	if not t or t == "" then
		feedback.BackgroundTransparency = 1
		feedback.Visible = false
		if feedbackStroke then feedbackStroke.Transparency = 1 end
		if not touchMode() then
			local myTurn = match and match.state and match.state.myTurn
			typeHintText.Text = myTurn and "TYPE ON YOUR KEYBOARD  -  ENTER TO PLAY" or "WAIT FOR YOUR TURN"
			typeHintText.TextColor3 = myTurn and C.amber or C.dim
			if typeHintStroke then
				typeHintStroke.Color = C.white
				typeHintStroke.Transparency = myTurn and 0.4 or 0.85
			end
		end
		return
	end
	local isError = feedback.TextColor3 == C.red or string.find(t, "!") or string.find(t, "No") or string.find(t, "Too") or string.find(t, "Keep") or string.find(t, "locked") or string.find(t, "already") or string.find(t, "different") or string.find(t, "Type") or string.find(t, "BLOCKED") or string.find(t, "ROOT") or string.find(t, "PLURALS") or string.find(t, "NEED") or string.find(t, "LENGTH") or string.find(t, "SAME ROOT") or string.find(t, "Tense") or string.find(t, "plural") or string.find(t, "Derivative")
	local color = isError and C.red or (string.find(t, "+") and C.teal or (string.find(t, "WORTH") and C.teal or (string.find(t, "DIVINE") and rgb(255, 215, 0) or C.amber)))
	feedback.BackgroundColor3 = isError and rgb(48, 16, 22) or (string.find(t, "+") and rgb(16, 38, 28) or C.s1)
	feedback.BackgroundTransparency = 0.15
	if feedbackStroke then
		feedbackStroke.Color = color
		feedbackStroke.Transparency = 0.4
	end
	feedback.TextColor3 = isError and lighten(C.red, 0.4) or (string.find(t, "DIVINE") and rgb(255, 215, 0) or (string.find(t, "+") and C.teal or (string.find(t, "WORTH") and C.teal or C.text)))
	-- On desktop, feedback text is displayed directly inside typeHint (the deskInput bar) with matching border glow.
	-- The separate floating pill is only visible in touchMode so it never covers the countdown or floats awkwardly below the input bar!
	feedback.Visible = touchMode()
	if not touchMode() then
		typeHintText.Text = t
		typeHintText.TextColor3 = feedback.TextColor3
		if typeHintStroke then
			typeHintStroke.Color = color
			typeHintStroke.Transparency = isError and 0.2 or 0.4
		end
		if isError then
			shake(deskInput)
		end
	end
	if isError then
		if touchMode() then shake(feedback) end
		feedbackClearToken += 1
		local tok = feedbackClearToken
		task.delay(2.8, function()
			if feedbackClearToken == tok and feedback.Parent then
				-- If player still has letters typed, re-evaluate preview so an invalid guess STAYS explained!
				if currentGuess and updatePreview and match and match.state and match.state.myTurn and #currentGuess() >= 3 then
					updatePreview()
				else
					feedback.Text = ""
				end
			end
		end)
	end
end)

-- desktop input: you type straight onto the tiles; this row is just the hint + PLAY
deskInput = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(600, 70), Parent = inputArea })
local typeHint = make("Frame", { BackgroundColor3 = C.s0, BackgroundTransparency = 0.25, Size = UDim2.new(1, -168, 0, 64), Parent = deskInput }, { corner(16), stroke(C.white, 0.85, 2) })
typeHintStroke = typeHint:FindFirstChildOfClass("UIStroke")
typeHintText = text({ Text = "", FontFace = F.heavy, TextSize = 16, TextColor3 = C.dim, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = typeHint })
submitKey = newKey({ text = "PLAY", style = "primary", textSize = 22, size = UDim2.fromOffset(156, 69), anchor = Vector2.new(1, 0), position = UDim2.new(1, 0, 0, 0), parent = deskInput })

-- touch input: letter keyboard + PLAY
touchInput = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(640, 250), Visible = false, Parent = inputArea })

-- search controls: shown while searching in the Play UI
searchControls = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(600, 70), Visible = false, Parent = inputArea })
cancelSearchKey = newKey({
	text = "CANCEL SEARCH",
	sub = "Return to lobby",
	style = "secondary",
	textSize = 18,
	size = UDim2.fromOffset(220, 64),
	anchor = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 0),
	parent = searchControls,
	onClick = function()
		fire("CancelQueue")
		setSearching(false)
	end,
})
searchBotKey = newKey({
	text = "PLAY VS BOT",
	sub = "Start immediately",
	style = "blue",
	textSize = 18,
	size = UDim2.fromOffset(200, 64),
	anchor = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 115, 0, 0),
	parent = searchControls,
	onClick = function()
		fire("PlayBot")
	end,
})
searchBotKey.holder.Visible = false

end -- scope
---------------------------------------------------------------- match logic
local coachCard, lastTick, layoutInput, popIndex, renderMatch, renderTiles, resetPending, selectedSlot, setControls, setTypingKeys, renderItems, keysLink
do
local pending = nil -- touch mode: array of letters being composed
local selectedIndex = nil
local typed = "" -- desktop: letters typed so far
lastTick = nil
popIndex = nil -- tile that just changed (animates in)
-- (declared above) local renderTiles, updatePreview -- forward
local renderCoach -- forward

currentGuess = function()
	if not (match and match.state) then
		return ""
	end
	return typed
end

resetPending = function()
	pending = nil
	selectedIndex = nil
	typed = ""
end

local function submit()
	if not (match and match.state and match.state.myTurn) then
		return
	end
	local s = match.state
	local word = s.word
	local guess = currentGuess()
	if #guess < 3 then
		feedback.TextColor3 = C.red
		feedback.Text = "WORD LENGTH  •  Use 3 to 10 letters"
		sfx("bad")
		shake(deskInput)
		return
	end
	if guess == word then
		feedback.TextColor3 = C.red
		feedback.Text = "DIFFERENT WORD  •  Play a new word"
		sfx("bad")
		shake(deskInput)
		return
	end
	local usedSet = {}
	for _, w in ipairs(s.used or {}) do usedSet[w] = true end
	if usedSet[guess] then
		feedback.TextColor3 = C.red
		feedback.Text = "ALREADY PLAYED  •  " .. string.upper(guess) .. " was used"
		sfx("bad")
		shake(deskInput)
		return
	end
	local keptN, _ = WordRules.Points(word, guess)
	if keptN == 0 then
		feedback.TextColor3 = C.red
		feedback.Text = "KEEP 1+ LETTER  •  Must keep a letter from " .. string.upper(word)
		sfx("bad")
		shake(deskInput)
		return
	end
	if WordRules.IsInflection(word, guess) then
		feedback.TextColor3 = C.red
		feedback.Text = "NO PLURALS / PAST TENSE  •  Not a form of " .. string.upper(word)
		sfx("bad")
		shake(deskInput)
		return
	end
	if match.state.deadline and match.state.turnTime and match.state.turnTime > 0 then
		submitLeftFrac = (match.state.deadline - workspace:GetServerTimeNow()) / match.state.turnTime
	end
	fire("Submit", guess)
end
submitKey.onClick = submit

-- physical keyboard: letters fill the tiles, Backspace fixes, Enter plays
setControls = function(on)
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = pm:GetControls()
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

-- Typing claims A-Z, Backspace, Enter, Up/Down slot navigation, Shift use, and 1-9 shortcuts
-- at top priority during a match, so Roblox's default bindings cannot swallow them.
local ContextActionService = game:GetService("ContextActionService")
selectedSlot = 1

local SLOT_NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.Two] = 2, [Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.Eight] = 8, [Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.Nine] = 9, [Enum.KeyCode.KeypadNine] = 9,
}

local function useSelectedSlot()
	if not (match and match.state) then
		return
	end
	local s = match.state
	local slots = s.slots or {}
	local sl = slots[selectedSlot]
	if not sl or sl.kind == "Empty" or not Config.Items[sl.kind] then
		showFlash("SLOT IS EMPTY", C.dim, 1.0, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if not s.myTurn then
		showFlash("BOOSTS ONLY ON YOUR TURN", C.dim, 1.0, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.state == "locked" then
		showFlash(string.upper(Config.Items[sl.kind].name) .. " OPENS UNDER " .. (sl.fastAt or 0) .. "s", C.amber, 1.2, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.state == "cooldown" then
		showFlash("REFILLING IN " .. sl.readyIn .. (sl.readyIn == 1 and " TURN" or " TURNS"), C.dim, 1.2, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.state == "empty" then
		showFlash("NONE LEFT IN STASH", C.red, 1.2, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.kind == "Help" and s.helpLeft and s.helpLeft <= 0 then
		showFlash("MAX HINTS USED", C.red, 1.2, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.kind == "Help" and s.helpCooldown and s.helpCooldown > 0 then
		showFlash("HINT COOLDOWN - NEXT TURN", C.red, 1.2, matchFlashPos(), 28)
		sfx("bad")
		return
	end
	if sl.state == "ready" then
		fire("UseItem", sl.kind)
		sfx("click")
	end
end

local TYPE_KEYS = {
	Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.Backspace,
	Enum.KeyCode.Up, Enum.KeyCode.Down,
	Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
}
for kc in pairs(SLOT_NUMBER_KEYS) do
	table.insert(TYPE_KEYS, kc)
end
for c = string.byte("A"), string.byte("Z") do
	table.insert(TYPE_KEYS, Enum.KeyCode[string.char(c)])
end

local function typingActive()
	return not touchMode() and hud.Visible and not UserInputService:GetFocusedTextBox()
end

local function handleKey(kc)
	if not (match and match.state) then
		return
	end
	local s = match.state
	local totalSlots = s.slots and #s.slots or 0

	-- Slot navigation with Up / Down arrows
	if kc == Enum.KeyCode.Up then
		if totalSlots > 0 then
			selectedSlot = selectedSlot - 1
			if selectedSlot < 1 then selectedSlot = totalSlots end
			sfx("click")
			renderItems(s)
		end
		return
	elseif kc == Enum.KeyCode.Down then
		if totalSlots > 0 then
			selectedSlot = selectedSlot + 1
			if selectedSlot > totalSlots then selectedSlot = 1 end
			sfx("click")
			renderItems(s)
		end
		return
	elseif kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		useSelectedSlot()
		return
	elseif SLOT_NUMBER_KEYS[kc] then
		local num = SLOT_NUMBER_KEYS[kc]
		if totalSlots > 0 and num <= totalSlots then
			selectedSlot = num
			sfx("click")
			renderItems(s)
		end
		return
	end

	-- Word typing: letters, backspace, and submit
	if not s.myTurn then
		return
	end
	if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
		submit()
	elseif kc == Enum.KeyCode.Backspace then
		if #typed > 0 then
			typed = typed:sub(1, -2)
			sfx("key")
			renderTiles(s)
			updatePreview()
		end
	elseif #typed >= MAX_WORD then
		feedback.TextColor3 = C.red
		feedback.Text = "Words can be up to " .. MAX_WORD .. " letters"
	else
		typed ..= string.lower(kc.Name)
		sfx("key")
		renderTiles(s)
		updatePreview()
	end
end

-- what the ContextActionService path already handled (so the fallback never double-types)
local casHandled = setmetatable({}, { __mode = "k" })
local lastCasKey, lastCasTime = nil, 0

local function onTypeKey(_, inputState, io)
	if not typingActive() then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		casHandled[io] = true
		lastCasKey, lastCasTime = io.KeyCode, os.clock()
		handleKey(io.KeyCode)
	end
	return Enum.ContextActionResult.Sink
end

local TYPE_KEY_SET = {}
for _, kc in ipairs(TYPE_KEYS) do
	TYPE_KEY_SET[kc] = true
end

-- Fallback: if anything swallows a key before ContextActionService sees it (reported for
-- I and O), the raw UserInputService event still types it. In Studio every key is logged
-- so a missing letter can be traced.
UserInputService.InputBegan:Connect(function(io, processed)
	if io.UserInputType ~= Enum.UserInputType.Keyboard or not hud.Visible then
		return
	end
	local kc = io.KeyCode
	task.defer(function()
		local viaCas = casHandled[io] == true or (lastCasKey == kc and os.clock() - lastCasTime < 0.1)
		if IS_STUDIO and TYPE_KEY_SET[kc] then
			print(string.format("[WordDuel keys] %s processed=%s handledByTyping=%s myTurn=%s", kc.Name, tostring(processed), tostring(viaCas), tostring(match and match.state and match.state.myTurn)))
		end
		if not viaCas and TYPE_KEY_SET[kc] and typingActive() then
			handleKey(kc)
		end
	end)
end)

setTypingKeys = function(on)
	ContextActionService:UnbindAction("WordDuelTyping")
	if on then
		ContextActionService:BindActionAtPriority("WordDuelTyping", onTypeKey, false, 3000, table.unpack(TYPE_KEYS))
	end
end

local function typeLetter(letter)
	if not (match and match.state and match.state.myTurn) then
		return
	end
	if #typed < MAX_WORD then
		typed ..= letter
		sfx("key")
		renderTiles(match.state)
		updatePreview()
	end
end

local function backspace()
	if not (match and match.state) or #typed == 0 then
		return
	end
	typed = typed:sub(1, -2)
	sfx("key")
	renderTiles(match.state)
	updatePreview()
end

local letterKeys = {} -- on-screen keys by letter (greyed out while locked)

local function lockedSet(state)
	local set = {}
	for _, ch in ipairs(state and state.lockLetters or {}) do
		set[ch] = true
	end
	return set
end

-- build the on-screen keyboard
do
	local rows = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
	local keyW, keyH, gap = 60, 60, 6
	for r, letters in ipairs(rows) do
		local rowF = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, (r - 1) * (keyH + gap)), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, keyH), Parent = touchInput }, { list(H, gap, Enum.HorizontalAlignment.Center) })
		if r == 3 then
			newKey({ text = "CLEAR", textSize = 13, size = UDim2.fromOffset(84, keyH), order = 0, parent = rowF, onClick = function()
				typed = ""
				if match and match.state then
					renderTiles(match.state)
				end
			end }).holder.LayoutOrder = 0
		end
		for i = 1, #letters do
			local ch = letters:sub(i, i)
			local k = newKey({ text = string.upper(ch), style = "cream", textSize = 22, radius = 10, size = UDim2.fromOffset(keyW, keyH), parent = rowF, sound = "key", onClick = function()
				typeLetter(ch)
			end })
			k.holder.LayoutOrder = i
			letterKeys[ch] = k
		end
		if r == 3 then
			newKey({ text = "DEL", textSize = 13, size = UDim2.fromOffset(84, keyH), parent = rowF, onClick = backspace }).holder.LayoutOrder = 99
		end
	end
	local touchPlay = newKey({ text = "PLAY", style = "primary", textSize = 22, size = UDim2.fromOffset(300, 62), anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 3 * (keyH + gap) + 4), parent = touchInput, onClick = submit })
	touchPlay.holder.Name = "TouchPlay"
end

keysLink = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(320, 22), Parent = stage })
keysLink.Activated:Connect(function()
	sfx("click")
	player:SetAttribute("ForceTouch", not touchMode())
end)

layoutInput = function()
	if searching then
		deskInput.Visible = false
		touchInput.Visible = false
		searchControls.Visible = true
		keysLink.Visible = false
		feedback.Visible = false
		return
	end
	searchControls.Visible = false
	local touch = touchMode()
	deskInput.Visible = not touch
	touchInput.Visible = touch
	feedback.Visible = touch
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Position = UDim2.fromOffset(360, 518)
	-- PC players can switch to clickable on-screen keys (and back)
	keysLink.Visible = UserInputService.KeyboardEnabled
	keysLink.Text = touch and "Use my physical keyboard" or "Keys not typing? Use on-screen keys"
	keysLink.Position = UDim2.new(0.5, 0, 0, touch and 556 or 336)
end
layoutInput()
player:GetAttributeChangedSignal("ForceTouch"):Connect(layoutInput)


-- While typing: your letters fill the tiles; a letter in the same spot as the current word
-- glows teal (that's a point), a new letter is amber, untyped spots show the current word faded.
-- Not typing: the current word, with letters kept from the previous word on a teal edge.
renderTiles = function(state)
	clearChildren(tilesRow, "UIListLayout")
	local word = state.word
	local typing = state.myTurn and #typed > 0
	local n = typing and math.max(#word, #typed) or #word
	local size = math.min(88, math.floor((700 - (n - 1) * 10) / math.max(n, 5)))
	for i = 1, n do
		local orig = word:sub(i, i)
		local shown, face, lip, ink = orig, C.cream, C.creamLip, C.ink
		local isUntypedGhost = false
		if typing then
			if i <= #typed then
				shown = typed:sub(i, i)
				if lockedSet(state)[shown] then
					face, lip, ink = C.red, C.redLip, C.white -- locked letter: this word won't be accepted
				elseif i > #word then
					face, lip, ink = C.blue, C.blueLip, C.white -- added on the end: scores
				elseif shown == orig then
					face, lip = C.teal, C.tealLip -- kept in the same spot: scores
				else
					face, lip = C.amber, C.amberLip
				end
			elseif orig == "" then
				shown = ""
			else
				-- Untyped spot: keep original letter visible as a faded guide/watermark of the word behind
				shown = orig
				ink = C.faint
				isUntypedGhost = true
			end
		elseif state.prev and state.prev:sub(i, i) == orig then
			lip = C.tealLip
		end
		local t = newTile(tilesRow, shown, size, { order = i, face = face, lip = lip, ink = ink })
		if isUntypedGhost then
			t.face.BackgroundTransparency = 0.25
			t.lip.BackgroundTransparency = 0.4
			t.label.TextTransparency = 0.35
		end
		if popIndex == i then
			local sc = make("UIScale", { Scale = 0.55, Parent = t.holder })
			tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

updatePreview = function()
	if not (match and match.state and match.state.myTurn) then
		return
	end
	local s = match.state
	local guess = currentGuess()
	local word = s.word
	feedback.Text = ""
	if #guess == 0 and hint and hint.word then
		feedback.TextColor3 = C.teal
		feedback.Text = string.format("%s %s  (+%d)", hint.coach and "Try:" or "Hint:", string.upper(hint.word), hint.points or 0)
		submitKey:setEnabled(false)
		return
	end
	if #guess < 3 then
		submitKey:setEnabled(false)
		return
	end
	local keptN, pts0 = WordRules.Points(word, guess)
	local usedSet = {}
	for _, w in ipairs(s.used or {}) do
		usedSet[w] = true
	end
	feedback.TextColor3 = C.red
	if guess == word then
		feedback.Text = "DIFFERENT WORD  •  Play a new word"
		submitKey:setEnabled(false)
	elseif usedSet[guess] then
		feedback.Text = "ALREADY PLAYED  •  " .. string.upper(guess) .. " was used"
		submitKey:setEnabled(false)
	elseif (function()
		for ch in pairs(lockedSet(s)) do
			if string.find(guess, ch, 1, true) then
				return true
			end
		end
		return false
	end)() then
		local shown = {}
		for _, ch in ipairs(s.lockLetters) do
			table.insert(shown, string.upper(ch))
		end
		feedback.Text = "LOCKED LETTER  •  No words with " .. table.concat(shown, "/")
		submitKey:setEnabled(false)
	elseif keptN == 0 then
		feedback.Text = "KEEP 1+ LETTER  •  Must keep a letter from " .. string.upper(word)
		submitKey:setEnabled(false)
	elseif WordRules.IsInflection(word, guess) then
		feedback.Text = "NO PLURALS / PAST TENSE  •  Not a form of " .. string.upper(word)
		submitKey:setEnabled(false)
	else
		local pts = pts0 * (s.doublePoints and 2 or 1)
		local isBiblical = Config.IsBiblical(guess)
		feedback.TextColor3 = isBiblical and rgb(255, 215, 0) or C.teal
		local bibTag = isBiblical and "  •  ✝ DIVINE WORD (+25 BONUS XP)" or ""
		feedback.Text = string.format("WORTH %d %s  •  PRESS ENTER TO PLAY%s%s", pts, pts == 1 and "PT" or "PTS", s.doublePoints and " (2X BOOST)" or "", bibTag)
		submitKey:setEnabled(true)
	end
end

-- the belt during a match: every slot shows what it is and when it's usable
renderItems = function(state)
	clearChildren(itemsCol, "UIListLayout")
	local slots = state.slots or {}
	local listLayout = itemsCol:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.Padding = UDim.new(0, #slots > 6 and 5 or 8)
	end
	local cardH = #slots > 6 and 48 or 54
	local header = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = itemsCol })
	text({ Text = "BOOSTS", FontFace = F.heavy, TextSize = 11, TextColor3 = C.dim, TextXAlignment = LEFT, Size = UDim2.new(0.4, 0, 1, 0), Parent = header })
	text({ Text = "↑↓ / 1-9  •  SHIFT", FontFace = F.bold, TextSize = 10, TextColor3 = C.faint, TextXAlignment = RIGHT, Position = UDim2.fromScale(0.4, 0), Size = UDim2.new(0.6, 0, 1, 0), Parent = header })
	if #slots == 0 then
		local c = panel({ BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 1, Parent = itemsCol })
		text({ Text = "No boosts on your belt", FontFace = F.bold, TextSize = 14, TextColor3 = C.faint, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = c })
		return
	end
	if selectedSlot > #slots then
		selectedSlot = 1
	end
	-- tutorial: the coach points at one power-up per step
	local want = state.tutorial and ({ [1] = "Help", [2] = "DoubleShift", [3] = "Time" })[state.myWords or 0] or nil
	for i, sl in ipairs(slots) do
		local isSelected = (i == selectedSlot)
		local kind = sl.kind
		if kind == "Empty" or not Config.Items[kind] then
			local emptyCard = make("Frame", {
				BackgroundColor3 = isSelected and C.s2 or C.s1,
				BackgroundTransparency = 0.35,
				Size = UDim2.new(1, 0, 0, cardH),
				LayoutOrder = i,
				Parent = itemsCol,
			}, { corner(12), stroke(isSelected and C.amber or (sl.fastAt and C.amber or C.white), isSelected and 0.2 or (sl.fastAt and 0.65 or 0.92), isSelected and 2 or 1) })
			local socket = make("Frame", { BackgroundColor3 = C.s0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(30, 30), Parent = emptyCard }, { corner(8), stroke(C.white, 0.9, 1) })
			text({ Text = "+", FontFace = F.display, TextSize = 16, TextColor3 = C.faint, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = socket })
			local tag = sl.fastAt and ("CLUTCH <" .. sl.fastAt .. "s") or ("SLOT " .. (sl.slot or i))
			text({ Text = tag, FontFace = F.heavy, TextSize = 12, TextColor3 = sl.fastAt and C.amber or C.dim, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(48, cardH == 48 and 6 or 9), Size = UDim2.new(1, -86, 0, 16), Parent = emptyCard })
			text({ Text = "Empty slot", FontFace = F.medium, TextSize = 10, TextColor3 = C.faint, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(48, cardH == 48 and 23 or 26), Size = UDim2.new(1, -86, 0, 14), Parent = emptyCard })
			local numBadge = make("Frame", {
				BackgroundColor3 = isSelected and C.amber or C.s0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(22, 22),
				Parent = emptyCard,
			}, { corner(6), stroke(isSelected and C.amberLip or C.white, isSelected and 0.2 or 0.88, 1) })
			text({
				Text = tostring(i),
				FontFace = F.heavy,
				TextSize = 11,
				TextColor3 = isSelected and C.ink or C.dim,
				TextXAlignment = CENTER,
				Size = UDim2.fromScale(1, 1),
				Parent = numBadge,
			})
		else
			local usable = state.myTurn and sl.state == "ready"
			local status = "TAP TO USE"
			if sl.state == "locked" then
				status = "OPENS UNDER " .. sl.fastAt .. "s"
			elseif sl.state == "cooldown" then
				status = "REFILLS IN " .. sl.readyIn .. (sl.readyIn == 1 and " TURN" or " TURNS")
			elseif sl.state == "empty" then
				status = "NONE LEFT - SHOP"
			elseif kind == "Help" and state.helpLeft and state.helpLeft <= 0 then
				status, usable = "MAX USED", false
			elseif kind == "Help" and state.helpCooldown and state.helpCooldown > 0 then
				status, usable = "NEXT TURN", false
			elseif not state.myTurn then
				status = sl.fastAt and ("CLUTCH <" .. sl.fastAt .. "s") or "YOUR TURN ONLY"
			end
			local spotlight = want == kind and usable
			if usable then
				if spotlight then
					status = isSelected and "TRY ME!  •  SHIFT" or "TRY ME!"
				elseif sl.fastAt and isSelected then
					status = "CLUTCH  •  SHIFT"
				elseif sl.fastAt then
					status = "CLUTCH READY"
				elseif isSelected then
					status = "SHIFT TO USE"
				else
					status = "TAP TO USE"
				end
			end
			local isPrimary = spotlight or (isSelected and usable)
			local k = newKey({
				text = string.upper(Config.Items[kind].name),
				sub = status,
				subSize = 10,
				style = isPrimary and "primary" or "secondary",
				textSize = 13,
				size = UDim2.new(1, 0, 0, cardH),
				parent = itemsCol,
				onClick = function()
					selectedSlot = i
					fire("UseItem", kind)
				end,
			})
			k.holder.LayoutOrder = i
			k.title.TextXAlignment = LEFT
			k.title.TextTruncate = Enum.TextTruncate.AtEnd
			k.title.TextSize = 13
			k.title.Position = UDim2.fromOffset(48, 0)
			k.title.Size = UDim2.new(1, -86, 0.56, 0)
			k.sub.TextXAlignment = LEFT
			k.sub.TextTruncate = Enum.TextTruncate.AtEnd
			k.sub.TextSize = 10
			k.sub.Position = UDim2.new(0, 48, 0.56, 0)
			k.sub.Size = UDim2.new(1, -86, 0.44, 0)
			newTile(k.face, ITEM_GLYPH[kind], 30, { position = UDim2.new(0, 10, 0.5, -16) })
			if not usable then
				k:setEnabled(false)
			end
			if isPrimary then
				k.sub.TextColor3 = C.ink
				k.sub.TextTransparency = 0.2
			elseif sl.fastAt and usable then
				k.sub.TextColor3 = C.amber
				k.sub.TextTransparency = 0.05
			elseif sl.fastAt and sl.state == "locked" then
				k.sub.TextColor3 = C.amber
				k.sub.TextTransparency = 0.35
			end
			if isPrimary or isSelected or usable then
				corner(14).Parent = k.holder
				if isPrimary then
					stroke(C.white, 0.45, 1.5).Parent = k.holder
				elseif isSelected then
					stroke(C.amber, 0.25, 2).Parent = k.holder
				elseif sl.fastAt and usable then
					stroke(C.amber, 0.35, 1.5).Parent = k.holder
				elseif usable then
					stroke(C.white, 0.88, 1).Parent = k.holder
				end
			end
			local badgeBg, badgeBgTrans, badgeTxt, badgeStrokeCol, badgeStrokeTrans
			if isPrimary then
				badgeBg, badgeBgTrans, badgeTxt, badgeStrokeCol, badgeStrokeTrans = C.ink, 0.12, C.amber, C.ink, 0.5
			elseif isSelected then
				badgeBg, badgeBgTrans, badgeTxt, badgeStrokeCol, badgeStrokeTrans = C.amber, 0, C.ink, C.amberLip, 0.2
			elseif sl.fastAt and usable then
				badgeBg, badgeBgTrans, badgeTxt, badgeStrokeCol, badgeStrokeTrans = C.s1, 0, C.amber, C.amber, 0.45
			else
				badgeBg, badgeBgTrans, badgeTxt, badgeStrokeCol, badgeStrokeTrans = C.s1, 0, C.dim, C.white, 0.85
			end
			local numBadge = make("Frame", {
				BackgroundColor3 = badgeBg,
				BackgroundTransparency = badgeBgTrans,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(22, 22),
				Parent = k.face,
			}, { corner(6), stroke(badgeStrokeCol, badgeStrokeTrans, 1) })
			text({
				Text = tostring(i),
				FontFace = F.heavy,
				TextSize = 11,
				TextColor3 = badgeTxt,
				TextXAlignment = CENTER,
				Size = UDim2.fromScale(1, 1),
				Parent = numBadge,
			})
			if sl.fastAt and usable then
				local sc = k.holder:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = k.holder })
				sc.Scale = 1.08
				tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			if sl.state == "locked" then
				k.face.BackgroundTransparency = 0.5
			end
		end
	end
end

local function renderChain(state)
	clearChildren(chainList, "UIListLayout")
	local hist = state.history or {}
	chainCount.Text = (#hist - 1) .. " MOVES"
	for i = #hist, 1, -1 do
		local newest = i == #hist
		local row = make("Frame", { BackgroundColor3 = newest and C.amber or C.s2, BackgroundTransparency = newest and 0.85 or 0.2, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = #hist - i, Parent = chainList }, { corner(9) })
		if newest then
			stroke(C.amber, 0.5).Parent = row
		end
		local w, prev = string.upper(hist[i]), hist[i - 1] and string.upper(hist[i - 1]) or nil
		local rich = w
		if prev then
			-- green = kept in the same spot, blue = added on the end (both scored)
			local parts = {}
			for k = 1, #w do
				local ch = w:sub(k, k)
				if k > #prev then
					table.insert(parts, '<font color="#6E92FF">' .. ch .. "</font>")
				elseif ch == prev:sub(k, k) then
					table.insert(parts, '<font color="#3AD6A8">' .. ch .. "</font>")
				else
					table.insert(parts, ch)
				end
			end
			rich = table.concat(parts)
		end
		text({ Text = rich, RichText = true, FontFace = F.display, TextSize = 16, TextColor3 = newest and C.text or C.dim, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Parent = row })
	end
end

-- tutorial coach: a speech card on the right (replaces the chain panel while learning)
coachCard = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 152), Size = UDim2.fromOffset(250, 250), BackgroundColor3 = C.s1, Visible = false, ZIndex = 3, Parent = hud })
stroke(C.amber, 0.4, 2).Parent = coachCard
local coachAvatar = newTile(coachCard, "T", 40, { position = UDim2.fromOffset(18, 18), face = C.amber, lip = C.amberLip })
text({ Text = "COACH TILLY", FontFace = F.heavy, TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(70, 22), Size = UDim2.fromOffset(160, 16), Parent = coachCard })
local coachStep = text({ Text = "", FontFace = F.bold, TextSize = 12, TextColor3 = C.faint, Position = UDim2.fromOffset(70, 40), Size = UDim2.fromOffset(160, 16), Parent = coachCard })
local coachText = text({ Text = "", FontFace = F.medium, TextSize = 17, TextColor3 = C.text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 76), Size = UDim2.new(1, -36, 1, -92), Parent = coachCard })
local _ = coachAvatar

renderCoach = function(s)
	local on = s.tutorial == true
	coachCard.Visible = on
	chainPanel.Visible = not on
	if not on then
		return
	end
	local n = s.myWords or 0
	coachStep.Text = "WORD " .. math.min((s.myWords or 0) + 1, Config.TutorialMoves) .. " OF " .. Config.TutorialMoves
	local how = touchMode() and "Tap the letters, then PLAY." or "Just type it and press Enter."
	if not s.myTurn then
		coachText.Text = "Nice! Now your rival changes one letter. Watch the tiles - the letter that changed lights up in the chain."
	elseif n == 0 then
		coachText.Text = "Play ANY real word - longer or shorter is fine - but keep at least one letter in the same spot. Kept letters and added letters are points (CAT -> CATER = 5)! My tip is below the tiles. " .. how
	elseif n == 1 then
		coachText.Text = "Boost time! Tap HINT (glowing, on the left) - it shows a word that scores. Then play that word."
	elseif n == 2 then
		coachText.Text = "Tap DOUBLE POINTS, then play any word - it scores twice. Used boosts refill after a few turns."
	else
		coachText.Text = "Last one! TIME BOOST gives you +5 seconds; PASS hands the word back. In Ranked matches, wins earn Elo to climb from Bronze to Master!"
	end
end

local function infoLine(info)
	return string.format("LV %d  -  %s %d%s", info.level, string.upper(info.rank), info.elo, info.isBot and "  -  BOT" or "")
end

renderMatch = function()
	if not match or not match.state then
		return
	end
	local s = match.state
	myPlate.name.Text = match.me.name
	myPlate.info.Text = infoLine(match.me)
	myPlate.info.TextColor3 = rankColor(match.me.rank)
	oppPlate.name.Text = match.opp.name
	oppPlate.info.Text = infoLine(match.opp)
	oppPlate.info.TextColor3 = rankColor(match.opp.rank)
	myPlate.setScore(s.myScore, s.doublePoints)
	oppPlate.setScore(s.rivalScore)
	myPlate.bar.Visible = s.myTurn
	oppPlate.bar.Visible = not s.myTurn
	myPlate.stroke.Color = s.myTurn and C.amber or C.white
	myPlate.stroke.Transparency = s.myTurn and 0.2 or 0.9
	oppPlate.stroke.Color = s.myTurn and C.white or C.amber
	oppPlate.stroke.Transparency = s.myTurn and 0.9 or 0.2

	statusLabel.Text = s.myTurn and "YOUR MOVE" or (string.upper(match.opp.name) .. " IS THINKING")
	statusLabel.TextColor3 = s.myTurn and C.amber or C.dim

	clearChildren(chipsRow, "UIListLayout")
	local locked = lockedSet(s)
	if s.lockLetters and #s.lockLetters > 0 then
		local shown = {}
		for _, ch in ipairs(s.lockLetters) do
			table.insert(shown, string.upper(ch))
		end
		chip(chipsRow, "LOCKED:  " .. table.concat(shown, "  "), C.red, 0)
	end
	for ch, k in pairs(letterKeys) do
		k:setEnabled(not locked[ch])
	end
	chip(chipsRow, "ANY WORD - KEEP 1+ LETTER IN ITS SPOT", C.dim, 1)
	if s.doublePoints then
		chip(chipsRow, "DOUBLE POINTS", C.blue, 2)
	end
	chip(chipsRow, "MOVE " .. (s.volley + 1), C.dim, 3)

	renderTiles(s)
	renderChain(s)
	renderItems(s)

	typeHintStroke.Color = s.myTurn and C.amber or C.white
	typeHintStroke.Transparency = s.myTurn and 0.4 or 0.85
	typeHintText.Text = s.myTurn and "TYPE ON YOUR KEYBOARD  -  ENTER TO PLAY" or "WAIT FOR YOUR TURN"
	typeHintText.TextColor3 = s.myTurn and C.amber or C.faint
	submitKey:setEnabled(s.myTurn)
	if s.myTurn then
		feedback.Text = ""
		updatePreview()
	end
	renderCoach(s)
end

RunService.RenderStepped:Connect(function()
	if hud.Visible and match and match.state and match.state.deadline then
		local s = match.state
		local left = math.max(0, s.deadline - workspace:GetServerTimeNow())
		local frac = s.turnTime > 0 and math.clamp(left / s.turnTime, 0, 1) or 0
		timerFill.Size = UDim2.fromScale(frac, 1)
		local color = frac > 0.5 and C.teal or (frac > 0.25 and C.amber or C.red)
		timerFill.BackgroundColor3 = color
		timerText.Text = string.format("%.1f", left)
		timerText.TextColor3 = left < 3 and C.red or C.text
		local whole = math.ceil(left)
		if s.myTurn and left > 0 and left < 3.05 and whole ~= lastTick then
			lastTick = whole
			sfx("tick")
		end

		-- Dynamic clutch slot unlocking as clock ticks down during turn
		if s.myTurn and s.slots then
			local unlockedAny = false
			for _, sl in ipairs(s.slots) do
				if sl.kind and sl.kind ~= "Empty" and sl.state == "locked" and sl.fastAt and left <= sl.fastAt then
					local count = profile and profile.inventory and profile.inventory[sl.kind] or 0
					sl.state = count > 0 and "ready" or "empty"
					unlockedAny = true
				end
			end
			if unlockedAny then
				sfx("whoosh")
				renderItems(s)
			end
		end
	end
	if queueCard.Visible then
		spinTile.holder.Rotation = math.sin(os.clock() * 4) * 8
	end
end)

end -- scope
---------------------------------------------------------------- result overlay
local cashKey, countdownBanner, countdownFill, countdownSub, countdownTitle, earnedLabel, earnedRow, kingBanner, kingBannerText, kingKey, okKey, resultButtons, resultCard, resultLayer, resultScale, resultTitle, resultWhy, statCoins, statElo, statScore, statXP, statsLine, statsPill, leaveLink
do
-- (declared above) local earnedRow -- set below (used by the rewards section)
resultLayer = make("Frame", { Name = "Result", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = root })
scrim(resultLayer, 0.35)
resultCard = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(660, 440), radius = 24, Parent = resultLayer })
resultScale = make("UIScale", { Parent = resultCard })
resultTitle = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 68), Position = UDim2.fromOffset(0, 24), Parent = resultCard })
resultWhy = text({ Text = "", FontFace = F.medium, TextSize = 16, TextColor3 = C.dim, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 22), Parent = resultCard })
local statsRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 92), Visible = false, Parent = resultCard }, { list(H, 12, Enum.HorizontalAlignment.Center) })
local function statBox(order, label)
	local b = make("Frame", { BackgroundColor3 = C.s2, Size = UDim2.fromOffset(116, 88), LayoutOrder = order, Parent = statsRow }, { corner(16), stroke(C.white, 0.92) })
	local v = text({ Text = "", FontFace = F.display, TextSize = 30, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 38), Parent = b })
	text({ Text = label, FontFace = F.heavy, TextSize = 12, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 16), Parent = b })
	return v
end
statScore = statBox(0, "SCORE")
statXP = statBox(1, "XP")
statCoins = statBox(2, "COINS")
statElo = statBox(3, "ELO")
statsPill = make("Frame", {
	BackgroundColor3 = rgb(24, 28, 42),
	BackgroundTransparency = 0.05,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 134),
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Visible = false,
	Parent = resultCard,
}, { corner(18), stroke(C.amber, 0.45, 1.5), pad(24, 24, 9, 9) })
statsLine = text({
	Text = "",
	RichText = true,
	FontFace = F.heavy,
	TextSize = 15,
	TextColor3 = C.text,
	TextXAlignment = CENTER,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Parent = statsPill,
})
earnedLabel = text({ Text = "EARNED THIS MATCH", FontFace = F.heavy, TextSize = 12, TextColor3 = C.faint, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, 0, 0, 16), Visible = false, Parent = resultCard })
earnedRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 198), Size = UDim2.new(1, -40, 0, 64), Visible = false, Parent = resultCard }, { list(H, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

-- Countdown banner: prominent, impossible to miss
countdownBanner = make("Frame", {
	BackgroundColor3 = rgb(34, 28, 16),
	BackgroundTransparency = 0.05,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 252),
	Size = UDim2.new(1, -52, 0, 64),
	Visible = false,
	Parent = resultCard,
}, { corner(14), stroke(C.amber, 0.45, 1.5) })
local countdownProgressBack = make("Frame", {
	BackgroundColor3 = C.s0,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 5),
	Parent = countdownBanner,
}, { corner(2) })
countdownFill = make("Frame", {
	BackgroundColor3 = C.amber,
	Size = UDim2.fromScale(1, 1),
	Parent = countdownProgressBack,
}, { corner(2) })
countdownTitle = text({
	Text = "NEXT OPPONENT IN 5s",
	FontFace = F.display,
	TextSize = 20,
	TextColor3 = C.amber,
	TextXAlignment = CENTER,
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 24),
	Parent = countdownBanner,
})
countdownSub = text({
	Text = "Auto-starting next duel  -  or tap PLAY NOW to skip waiting",
	FontFace = F.bold,
	TextSize = 13,
	TextColor3 = C.dim,
	TextXAlignment = CENTER,
	Position = UDim2.fromOffset(0, 32),
	Size = UDim2.new(1, 0, 0, 18),
	Parent = countdownBanner,
})

kingBanner = make("Frame", { BackgroundColor3 = C.amber, BackgroundTransparency = 0.86, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 340), Size = UDim2.new(1, -52, 0, 52), Visible = false, Parent = resultCard }, { corner(14), stroke(C.amber, 0.4, 2) })
Icon.crown(kingBanner, 36, UDim2.fromOffset(12, 8))
kingBannerText = text({ Text = "", FontFace = F.heavy, TextSize = 15, TextColor3 = C.amber, Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -70, 1, 0), Parent = kingBanner })

resultButtons = make("Frame", { Name = "ResultButtons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 340), Size = UDim2.new(1, -52, 0, 72), Parent = resultCard })

-- Two big buttons side by side during King streak
kingKey = newKey({
	text = "PLAY NOW",
	sub = "Skip waiting → start instantly",
	style = "primary",
	textSize = 21,
	subSize = 12,
	size = UDim2.new(0.5, -8, 0, 72),
	position = UDim2.new(0, 0, 0, 0),
	parent = resultButtons,
	onClick = function()
		fire("Choice", "king")
		resultLayer.Visible = false
	end,
})
cashKey = newKey({
	text = "LEAVE TABLE",
	sub = "Keep all rewards & exit",
	style = "secondary",
	textSize = 19,
	subSize = 12,
	size = UDim2.new(0.5, -8, 0, 72),
	position = UDim2.new(0.5, 8, 0, 0),
	parent = resultButtons,
	onClick = function()
		resultLayer.Visible = false
		fire("Choice", "cashout")
		fire("LeaveTable")
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Sit = false end
		showLobby(true)
		if checkNextModal then checkNextModal() end
	end,
})
cashKey.holder.Visible = false

leaveLink = make("TextButton", { Text = "Staying until countdown ends auto-starts the next match", FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 416), Size = UDim2.fromOffset(450, 18), Visible = false, Parent = resultCard })
leaveLink.Active = false

okKey = newKey({
	text = "CONTINUE",
	sub = "Back to lobby",
	style = "primary",
	textSize = 22,
	subSize = 13,
	size = UDim2.fromOffset(320, 70),
	anchor = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 0),
	parent = resultButtons,
	onClick = function()
		resultLayer.Visible = false
		fire("Choice", "cashout")
		fire("LeaveTable")
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Sit = false end
		showLobby(true)
		if checkNextModal then checkNextModal() end
	end,
})

end -- scope
---------------------------------------------------------------- king panel
local kingPanel = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(640, 170), Visible = false, ZIndex = 6, Parent = root })
text({ Text = "KING OF THE TABLE", FontFace = F.heavy, TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(24, 18), Size = UDim2.fromOffset(300, 16), Parent = kingPanel })
local kingWordHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 42), Size = UDim2.fromOffset(300, 50), Parent = kingPanel })
local kingText = text({ Text = "", FontFace = F.medium, TextSize = 15, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(330, 42), Size = UDim2.fromOffset(290, 50), Parent = kingPanel })
newKey({ text = "LEAVE TABLE", style = "secondary", textSize = 16, size = UDim2.new(1, -48, 0, 60), position = UDim2.new(0, 24, 1, -82), parent = kingPanel, onClick = function()
	fire("KingCashOut")
end })

---------------------------------------------------------------- rewards
local earnedEntry, flushEarned, guideAfterLobby, pendingEarned, queueReward, parkCelebrations, celebrateQueue, celebrating, celebrateLayer, showNextCelebration
do
-- In the lobby a reward gets a real moment: big icon, short text, and you dismiss it.
-- During a match nothing pops over the board; rewards are collected and shown on the
-- result screen under "EARNED THIS MATCH".
local EYEBROW = { daily = "DAILY CHEST", award = "MEDAL WON", level = "LEVEL UP", record = "NEW RECORD", streak = "KING STREAK", shards = "SHARDS COMBINED", bonus = "YOU GOT" }
local REWARD_COLOR = { daily = C.teal, award = C.amber, level = C.blue, record = C.amber, streak = C.amber, shards = C.teal, bonus = C.amber }
local REWARD_SOUND = { daily = "brilliant", award = "win", level = "win", record = "brilliant", streak = "win", shards = "good", bonus = "win" }

local function rewardIcon(r, parent, size)
	local k = r.kind
	if k == "daily" then
		return Icon.chest(parent, size)
	elseif k == "award" then
		return Icon.medal(parent, size, nil, true)
	elseif k == "level" then
		return Icon.level(parent, size, nil, tonumber((r.title or ""):match("%d+")))
	elseif k == "record" then
		return Icon.trophy(parent, size)
	elseif k == "streak" then
		return Icon.crown(parent, size)
	elseif k == "shards" then
		return gemIcon(parent, size)
	end
	return coinIcon(parent, size)
end

-- the actual things you got, as icons with amounts
local function grantRow(parent, grant, iconSize)
	if not grant then
		return
	end
	local order = 0
	local function entry(drawIcon, amount)
		order += 1
		local f = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, iconSize), LayoutOrder = order, Parent = parent }, { list(H, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		local ic = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(iconSize, iconSize), LayoutOrder = 1, Parent = f })
		drawIcon(ic)
		text({ Text = "+" .. amount, FontFace = F.display, TextSize = math.floor(iconSize * 0.7), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, iconSize), LayoutOrder = 2, Parent = f })
	end
	if grant.coins then
		entry(function(p)
			coinIcon(p, iconSize)
		end, grant.coins)
	end
	for _, k in ipairs({ "Help", "Skip", "Time", "DoubleShift" }) do
		if grant[k] then
			entry(function(p)
				Icon.item(p, iconSize, nil, k)
			end, grant[k])
		end
	end
end

pendingEarned = {}
celebrateQueue, celebrating = {}, false
local celebratingReward = nil
guideAfterLobby = false

celebrateLayer = make("Frame", { Name = "Celebrate", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 46, Parent = root })
scrim(celebrateLayer, 0.3)
local celCard = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 430), radius = 26, ZIndex = 2, Parent = celebrateLayer })
local celScale = make("UIScale", { Parent = celCard })
local celRays = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(250, 250), Parent = celCard })
for i = 1, 12 do
	make("Frame", { BackgroundColor3 = C.amber, BackgroundTransparency = 0.9, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 10, 1, 0), Rotation = i * 15, Parent = celRays }, { round() })
end
local celIcon = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(120, 120), Parent = celCard })
local celEyebrow = text({ Text = "", FontFace = F.heavy, TextSize = 14, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 0, 18), Parent = celCard })
local celTitle = text({ Text = "", FontFace = F.display, TextSize = 34, TextXAlignment = CENTER, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(20, 212), Size = UDim2.new(1, -40, 0, 42), Parent = celCard })
local celSub = text({ Text = "", FontFace = F.medium, TextSize = 17, TextColor3 = C.dim, TextXAlignment = CENTER, TextWrapped = true, Position = UDim2.fromOffset(30, 256), Size = UDim2.new(1, -60, 0, 44), Parent = celCard })
local celGrant = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 300), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), Parent = celCard }, { list(H, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
newKey({ text = "NICE!", style = "primary", textSize = 20, size = UDim2.fromOffset(240, 62), anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -22), parent = celCard, onClick = function()
	celebrateLayer.Visible = false
	celebrating = false
	if #celebrateQueue > 0 then
		showNextCelebration()
	elseif checkNextModal then
		checkNextModal()
	end
end })
RunService.RenderStepped:Connect(function(dt)
	if celebrateLayer.Visible then
		celRays.Rotation += dt * 18
	end
end)

showNextCelebration = function()
	if celebrating or #celebrateQueue == 0 then
		return
	end
	if modalLayer and modalLayer.Visible then
		return
	end
	if welcomeLayer and welcomeLayer.Visible then
		return
	end
	if welcomePending then
		return
	end
	celebrating = true
	local r = table.remove(celebrateQueue, 1)
	celebratingReward = r
	local color = REWARD_COLOR[r.kind] or C.amber
	clearChildren(celIcon)
	rewardIcon(r, celIcon, 120)
	celEyebrow.Text = EYEBROW[r.kind] or "REWARD"
	celEyebrow.TextColor3 = color
	celTitle.Text = string.upper(r.title or "")
	celSub.Text = r.sub or ""
	clearChildren(celGrant, "UIListLayout")
	grantRow(celGrant, r.grant, 32)
	for _, ray in ipairs(celRays:GetChildren()) do
		ray.BackgroundColor3 = color
	end
	celebrateLayer.Visible = true
	celScale.Scale = 0.7
	tween(celScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	sfx(REWARD_SOUND[r.kind] or "win")
end

queueReward = function(r)
	if match ~= nil and r.kind ~= "daily" then
		table.insert(pendingEarned, r)
	else
		table.insert(celebrateQueue, r)
		if checkNextModal then
			checkNextModal()
		else
			showNextCelebration()
		end
	end
end

-- a match is starting: dismiss any open celebration; lobby rewards stay in queue for return
parkCelebrations = function()
	celebrating = false
	celebratingReward = nil
	celebrateLayer.Visible = false
end

-- match-earned rewards are already summarized on the Victory/Defeat screen.
-- we clear pendingEarned here so players aren't fatigued by 5x "NICE!" fullscreen modals!
flushEarned = function()
	pendingEarned = {}
	if checkNextModal then
		checkNextModal()
	end
end

-- one tile in the result screen's "EARNED THIS MATCH" row
earnedEntry = function(r, order, cardWidth)
	cardWidth = cardWidth or 220
	local color = REWARD_COLOR[r.kind] or C.amber
	local f = make("Frame", {
		BackgroundColor3 = C.s2,
		Size = UDim2.fromOffset(cardWidth, 60),
		LayoutOrder = order,
		Parent = earnedRow,
	}, { corner(12), stroke(color, 0.5, 1.5) })
	local ic = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(40, 40), Parent = f })
	rewardIcon(r, ic, 40)
	text({ Text = EYEBROW[r.kind] or "REWARD", FontFace = F.heavy, TextSize = 10, TextColor3 = color, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -62, 0, 13), Parent = f })
	text({ Text = string.upper(r.title or ""), FontFace = F.display, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(56, 21), Size = UDim2.new(1, -62, 0, 18), Parent = f })
	text({ Text = r.sub or "", FontFace = F.medium, TextSize = 11, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(56, 38), Size = UDim2.new(1, -62, 0, 16), Parent = f })
end

end -- scope
---------------------------------------------------------------- welcome (first time)
welcomeLayer = make("Frame", { Name = "Welcome", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 40, Parent = root })
scrim(welcomeLayer, 0.25)
local welcomeCard = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 380), radius = 24, ZIndex = 2, Parent = welcomeLayer })
tileWord(welcomeCard, "HELLO", 56, 8, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 34), face = C.amber, lip = C.amberLip, rotations = { -3, 2, -2, 3, -1 } })
text({ Text = "New to Word Duel?", FontFace = F.display, TextSize = 28, TextXAlignment = CENTER, Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 34), Parent = welcomeCard })
text({ Text = "Learn it in under a minute with Coach Tilly.\nFinish the tutorial for " .. (Config.TutorialReward.coins or 150) .. " coins and a free Hint.", FontFace = F.medium, TextSize = 17, TextColor3 = C.dim, TextXAlignment = CENTER, TextWrapped = true, Position = UDim2.fromOffset(30, 164), Size = UDim2.new(1, -60, 0, 50), Parent = welcomeCard })
newKey({ text = "START TUTORIAL", style = "primary", textSize = 20, size = UDim2.new(1, -60, 0, 66), position = UDim2.fromOffset(30, 232), parent = welcomeCard, onClick = function()
	welcomeLayer.Visible = false
	welcomeShown = true
	welcomePending = false
	fire("StartTutorial")
	if checkNextModal then
		checkNextModal()
	end
end })
local skipBtn = make("TextButton", { Text = "I know how to play - skip", FontFace = F.bold, TextSize = 15, TextColor3 = C.faint, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 316), Size = UDim2.fromOffset(300, 30), ZIndex = 3, Parent = welcomeCard })
skipBtn.Activated:Connect(function()
	sfx("click")
	if profile then profile.tutorialDone = true end
	welcomeShown = true
	welcomePending = false
	welcomeLayer.Visible = false
	fire("SkipTutorial")
	if checkNextModal then
		checkNextModal()
	end
end)

checkNextModal = function()
	if match or (hud and hud.Visible) or (resultLayer and resultLayer.Visible) then
		return
	end
	if modalLayer and modalLayer.Visible then
		return
	end
	if welcomeLayer and welcomeLayer.Visible then
		return
	end
	if celebrating or (celebrateLayer and celebrateLayer.Visible) then
		return
	end
	-- First-time player onboarding: Tutorial Welcome modal comes FIRST
	if welcomePending and not welcomeShown then
		welcomeShown = true
		welcomePending = false
		welcomeLayer.Visible = true
		return
	end
	-- After tutorial is done/skipped (or for returning players): Show queued celebrations (e.g. Daily Chest)
	if #celebrateQueue > 0 then
		showNextCelebration()
		return
	end
end

---------------------------------------------------------------- screens
-- 3D table signs are for spectators; hide them locally while you're seated in a duel
local function setTableSigns(on)
	local arena = workspace:FindFirstChild("WordDuelArena")
	if not arena then
		return
	end
	for _, bb in ipairs(arena:GetDescendants()) do
		if bb:IsA("Humanoid") then
			-- overhead names (NPCs at other tables, your opponent) would draw through the HUD
			bb.DisplayDistanceType = on and Enum.HumanoidDisplayDistanceType.Viewer or Enum.HumanoidDisplayDistanceType.None
		elseif bb:IsA("BillboardGui") then
			bb.Enabled = on
		end
	end
end

local matchCamConn = nil

stopMatchCam = function()
	if matchCamConn then
		matchCamConn:Disconnect()
		matchCamConn = nil
	end
end

alignMatchCamera = function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local seat = hum and hum.SeatPart
	if not seat then
		local arena = workspace:FindFirstChild("WordDuelArena")
		if arena then
			for _, d in ipairs(arena:GetDescendants()) do
				if d:IsA("Seat") and d.Occupant == hum then
					seat = d
					break
				end
			end
		end
	end
	-- Still searching (not seated): frame the nearest free table from a seat, same angle as a match
	if not seat and searching then
		local arena = workspace:FindFirstChild("WordDuelArena")
		local best, bestD = nil, math.huge
		if arena then
			for _, d in ipairs(arena:GetDescendants()) do
				if d:IsA("Seat") and d.Name == "SeatA" and not d.Occupant then
					local other = d.Parent and d.Parent:FindFirstChild("SeatB")
					if not (other and other:IsA("Seat") and other.Occupant) then
						local dist = (d.Position - root.Position).Magnitude
						if dist < bestD then
							best, bestD = d, dist
						end
					end
				end
			end
		end
		seat = best
	end
	-- If not seated yet and still at the lobby spawn area (Z <= -45), wait until character reaches table
	if not seat and root.Position.Z <= -45 then
		return false
	end
	local refCFrame = seat and seat.CFrame or root.CFrame
	local pos = seat and (seat.Position + Vector3.new(0, 0.5, 0)) or root.Position
	local look = refCFrame.LookVector
	local eye = pos - look * 6 + Vector3.new(0, 7, 0)
	local target = pos + look * 5 + Vector3.new(0, 1, 0)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, target)
	return true
end

local function startMatchCam()
	stopMatchCam()
	alignMatchCamera()
	matchCamConn = RunService.RenderStepped:Connect(function()
		if not (hud and hud.Visible) and not match and not searching then
			stopMatchCam()
			return
		end
		alignMatchCamera()
	end)
end

alignLobbyCamera = function()
	stopMatchCam()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	if hum then
		workspace.CurrentCamera.CameraSubject = hum
	end
	if root then
		local look = root.CFrame.LookVector
		workspace.CurrentCamera.CFrame = CFrame.lookAt(root.Position - look * 12 + Vector3.new(0, 4, 0), root.Position + Vector3.new(0, 1.5, 0))
	end
end

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if hum then
		hum.Seated:Connect(function(active, seatPart)
			if (match or searching) and active and seatPart then
				alignMatchCamera()
			end
		end)
	end
	if lobby.Visible and not match and not searching then
		alignLobbyCamera()
	end
end)

showLobby = function(v)
	lobby.Visible = v
	lobbyCol.Visible = true
	topRight.Visible = v
	setTableSigns(v)
	if not v then
		closeModal()
	else
		alignLobbyCamera()
	end
	setMusic(v)
end

setSearching = function(on, q)
	searching = on
	q = q or {}
	queueCard.Visible = false
	vs.Visible = true
	if queueCancelBtn then
		queueCancelBtn.Visible = on
	end
	if queueBotBtn then
		queueBotBtn.Visible = on and (q.botOffer == true)
	end
	setControls(not on)
	if on then
		playKey:setText("SEARCHING...", "finding someone your level")
		playKey:setEnabled(false)

		-- Instantly open the Play UI without starting words
		showLobby(false)
		hud.Visible = true
		kingPanel.Visible = false
		resultLayer.Visible = false
		welcomeLayer.Visible = false
		feedback.Text = ""

		-- My plate: populated with current player
		myPlate.setAvatar(player.UserId, player.Name)
		myPlate.name.Text = player.DisplayName
		local lvl = profile and profile.level or 1
		local rk = profile and profile.rank or "BRONZE"
		myPlate.info.Text = string.format("LV %d  -  %s", lvl, string.upper(rk))
		myPlate.info.TextColor3 = rankColor(rk)
		myPlate.setScore(0, false)
		myPlate.bar.Visible = false
		myPlate.stroke.Color = C.amber
		myPlate.stroke.Transparency = 0.5

		-- Opponent plate: loading UI
		oppPlate.setAvatar(0, "?")
		oppPlate.name.Text = "FINDING OPPONENT..."
		local bracket = q.bracket or Config.BaseBracket
		local waited = q.waited or 0
		oppPlate.info.Text = string.format("Within %d levels  -  %ds", bracket, waited)
		oppPlate.info.TextColor3 = C.dim
		oppPlate.setScore(0, false)
		oppPlate.bar.Visible = false
		oppPlate.stroke.Color = C.white
		oppPlate.stroke.Transparency = 0.85

		-- Headers
		modeTag.Text = "RANKED MATCHMAKING"
		statusLabel.Text = "GET READY"
		statusLabel.TextColor3 = C.amber

		-- Clean matchmaking chips with full game rules readable
		clearChildren(chipsRow, "UIListLayout")
		chip(chipsRow, "ANY WORD - KEEP 1+ LETTER IN ITS SPOT", C.amber, 1)
		chip(chipsRow, "NO PLURALS / PAST TENSE", C.dim, 2)
		chip(chipsRow, "MOVE 1", C.dim, 3)

		-- Real 3D letter tile placeholders (cream tiles with ? and 3D lips)
		clearChildren(tilesRow, "UIListLayout")
		local len = profile and profile.wordLength or 3
		local size = math.min(88, math.floor((700 - (len - 1) * 10) / math.max(len, 5)))
		for i = 1, len do
			newTile(tilesRow, "?", size, { order = i, face = C.cream, lip = C.creamLip, ink = C.dim })
		end

		-- Timer: 10.0s full bar
		timerText.Text = "10.0"
		timerText.TextColor3 = C.text
		timerFill.Size = UDim2.fromScale(1, 1)
		timerFill.BackgroundColor3 = C.teal

		-- Boosts belt column on left: render player's equipped boosts so they can read them
		local beltSlots = {}
		local belt = profile and profile.belt or {}
		local inv = profile and profile.inventory or {}
		local baseSlots = profile and profile.slots or 1
		local totalSlots = baseSlots + #Config.FastSlotClocks
		for i = 1, totalSlots do
			local fastAt = (i > baseSlots) and Config.FastSlotClocks[i - baseSlots] or nil
			local kind = belt[i]
			if kind and Config.Items[kind] then
				local count = inv[kind] or 0
				table.insert(beltSlots, {
					kind = kind,
					state = fastAt and "locked" or (count > 0 and "ready" or "empty"),
					readyIn = 0,
					fastAt = fastAt,
					slot = i,
				})
			else
				table.insert(beltSlots, {
					kind = "Empty",
					state = "empty",
					readyIn = 0,
					fastAt = fastAt,
					slot = i,
				})
			end
		end
		renderItems({ slots = beltSlots, myTurn = false })

		-- Chain panel column on right: readable placeholder
		coachCard.Visible = false
		chainPanel.Visible = true
		chainCount.Text = "0 MOVES"
		clearChildren(chainList, "UIListLayout")
		local chainPlaceholder = make("Frame", { BackgroundColor3 = C.s2, BackgroundTransparency = 0.35, Size = UDim2.new(1, 0, 0, 36), Parent = chainList }, { corner(9) })
		text({ Text = "First word starts chain", FontFace = F.bold, TextSize = 13, TextColor3 = C.faint, TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Parent = chainPlaceholder })

		-- Input area: desk input visible with waiting hint, exactly like in-game
		deskInput.Visible = not touchMode()
		touchInput.Visible = touchMode()
		searchControls.Visible = false
		typeHintText.Text = "WAITING FOR OPPONENT..."
		typeHintText.TextColor3 = C.dim
		typeHintStroke.Color = C.white
		typeHintStroke.Transparency = 0.85
		submitKey:setEnabled(false)
		keysLink.Visible = UserInputService.KeyboardEnabled
		keysLink.Text = touchMode() and "Use my physical keyboard" or "Keys not typing? Use on-screen keys"
		keysLink.Position = UDim2.new(0.5, 0, 0, touchMode() and 556 or 336)

		-- Matchmaking camera angle: continuously track table seat
		startMatchCam()
	else
		stopMatchCam()
		quickCombo = 0
		longRunCombo = 0
		submitLeftFrac = 0
		queueCard.Visible = false
		vs.Visible = true
		if queueCancelBtn then
			queueCancelBtn.Visible = false
		end
		if queueBotBtn then
			queueBotBtn.Visible = false
		end
		playKey:setText("PLAY RANKED", "Matched by level  -  Elo on the line")
		playKey:setEnabled(true)
		if not match then
			hud.Visible = false
			showLobby(true)
			alignLobbyCamera()
		end
		layoutInput()
	end
end

---------------------------------------------------------------- profile render
local function renderProfile()
	if not profile then
		return
	end
	profLevel.Text = "LV " .. profile.level
	profXP.Text = profile.xp .. " / " .. profile.xpNext .. " XP"
	local actualFrac = math.clamp(profile.xp / profile.xpNext, 0, 1)
	local endowedFrac = actualFrac >= 1 and 1 or math.clamp(0.15 + 0.85 * actualFrac, 0.15, 1)
	tween(xpFill, 0.5, { Size = UDim2.fromScale(endowedFrac, 1) })
	local rc = rankColor(profile.rank)
	rankChipText.Text = string.upper(profile.rank) .. "  " .. profile.elo
	rankChipText.TextColor3 = rc
	rankChip:FindFirstChildOfClass("UIStroke").Color = rc
	rankChip.BackgroundColor3 = rc
	wlText.Text = string.format("%dW  %dL  -  %d-LETTER", profile.wins, profile.losses, profile.wordLength)
	coinText.Text = Config.FormatNumber(profile.coins)
	shardText.Text = profile.shards .. "/" .. Config.ShardsPerHelp
	lastLevel = profile.level
	refreshModal()
end

---------------------------------------------------------------- network
local handlers = {}

handlers.Profile = function(p)
	profile = p
	renderProfile()
	if not p.tutorialDone and not match then
		welcomePending = true
		welcomeShown = false
		if checkNextModal then
			checkNextModal()
		end
	end
end

handlers.Toast = function(msg)
	toast(msg)
end

handlers.Leaderboard = function(lb)
	leaderboard = lb or leaderboard
	refreshModal()
end

handlers.QueueState = function(q)
	setSearching(q.searching == true, q)
end

handlers.PrivateCode = function(d)
	privateCode = d and d.code
	refreshModal()
	if privateCode then
		toast("Table open  -  code " .. privateCode, C.amber)
	end
end

handlers.InviteData = function(d)
	local ok, err = pcall(function()
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = "Duel me in Word Duel!"
		opts.LaunchData = d.launchData
		if SocialService:CanSendGameInviteAsync(player) then
			SocialService:PromptGameInvite(player, opts)
		else
			toast("Invites aren't available for your account here.")
		end
	end)
	if not ok then
		toast("Invite failed: " .. tostring(err), C.red)
	end
end

handlers.MatchStart = function(d)
	parkCelebrations()
	pendingEarned = {}
	welcomeLayer.Visible = false
	quickCombo = 0
	longRunCombo = 0
	match = { me = d.me, opp = d.opp, ranked = d.ranked, state = nil }
	hint = nil
	lastTick = nil
	selectedSlot = 1
	resetPending()
	setSearching(false, {})
	kingPanel.Visible = false
	resultLayer.Visible = false
	showLobby(false)
	hud.Visible = true
	feedback.Text = ""
	statusLabel.Text = "GET READY"
	statusLabel.TextColor3 = C.dim
	clearChildren(tilesRow, "UIListLayout")
	myPlate.setAvatar(d.me.userId, d.me.name)
	oppPlate.setAvatar(d.opp.userId, d.opp.name)
	-- show the opponent's actual seated avatar (same treatment for people and bots)
	task.spawn(function()
		for _ = 1, 20 do
			if d.opp.rig and d.opp.rig.Parent and d.opp.rig:FindFirstChild("Head") then
				oppPlate.setRig(d.opp.rig)
				return
			end
			task.wait(0.15)
		end
	end)
	setControls(false)
	setTypingKeys(true)
	popIndex = nil
	startMatchCam()
	myPlate.name.Text = d.me.name
	oppPlate.name.Text = d.opp.name
	modeTag.Text = d.tutorial and "TUTORIAL" or (d.private and "FRIEND TABLE" or (d.ranked and "RANKED" or "PRACTICE"))
	layoutInput()
	sfx("whoosh")
	if d.king then
		showFlash("DEFEND YOUR TABLE", C.amber, 1.5)
		modeTag.Text = "KING OF THE TABLE" .. ((d.kingStreak or 0) > 0 and ("  -  " .. d.kingStreak .. " WINS") or "")
	elseif d.challenger then
		showFlash("CHALLENGE THE KING", C.amber, 1.5)
		modeTag.Text = "CHALLENGING THE KING"
	else
		showFlash("VS " .. string.upper(d.opp.name), C.amber, 1.3)
	end
end

handlers.MatchState = function(s)
	if not match then
		return
	end
	popIndex = nil
	if match.state and match.state.word ~= s.word then
		local old = match.state.word
		if #old == #s.word then
			for i = 1, #old do
				if old:sub(i, i) ~= s.word:sub(i, i) then
					popIndex = i
					break
				end
			end
		end
		hint = nil
		resetPending()
	end
	if match.state and match.state.myTurn ~= s.myTurn then
		lastTick = nil
	end
	local becameMine = s.myTurn and not (match.state and match.state.myTurn)
	match.state = s
	selectedSlot = math.clamp(selectedSlot, 1, math.max(1, #(s.slots or {})))
	renderMatch()
	if becameMine then
		-- clear cue that it's your move: sound + a pop on the status line
		sfx("turn")
		local sc = statusLabel:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = statusLabel })
		sc.Scale = 1.35
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		if s.lockLetters and #s.lockLetters > 0 then
			local shown = {}
			for _, ch in ipairs(s.lockLetters) do
				table.insert(shown, string.upper(ch))
			end
			showFlash("LOCKED:  " .. table.concat(shown, "  "), C.red, 1.1, matchFlashPos(), 38)
			sfx("bad")
		end
	end
end

handlers.Invalid = function(reason)
	feedback.TextColor3 = C.red
	feedback.Text = reason
	sfx("bad")
	shake(tilesRow)
end

handlers.Hint = function(h)
	hint = h
	feedback.TextColor3 = C.teal
	feedback.Text = string.format("%s %s  (+%d)", h.coach and "Try:" or "Hint:", string.upper(h.word or ""), h.points or 0)
	if match and match.state then
		renderTiles(match.state)
	end
end

handlers.Deadlock = function(d)
	showFlash("DEADLOCK  -  CHANGE " .. d.diff, C.red, 1.8)
	sfx("bad")
end

handlers.Brilliant = function(d)
	showFlash("BRILLIANT  " .. string.upper(d.word), C.amber, 1.4, matchFlashPos(), 38)
	sfx("brilliant")
end

handlers.Blessed = function(d)
	showFlash("✝ BLESSED WORD: " .. string.upper(d.word) .. "  (+25 BONUS XP)", rgb(255, 215, 0), 2.2, matchFlashPos(), 38)
	sfx("brilliant")
end

-- fast-paced cues: quick answers build a combo (pitch climbs), long words and rally
-- milestones get their own call-outs
local STRIKE_RANKS = {
	[1] = { name = "QUICK MOVE!", color = C.teal, size = 36 },
	[2] = { name = "DOUBLE STRIKE!", color = C.teal, size = 38 },
	[3] = { name = "TRIPLE STRIKE!", color = C.amber, size = 42 },
	[4] = { name = "FURY STRIKE!", color = C.amber, size = 44 },
	[5] = { name = "FRENZY!", color = C.red, size = 48 },
	[6] = { name = "RAMPAGE!", color = C.red, size = 50 },
	[7] = { name = "DOMINATION!", color = rgb(255, 80, 200), size = 52 },
	[8] = { name = "UNSTOPPABLE!", color = rgb(255, 215, 0), size = 56 },
}

handlers.FirstBigWord = function(d)
	local mine = match and d.by == match.me.name
	local msg = mine and ("FIRST BIG WORD!  " .. string.upper(d.word) .. "  (+100 COINS)") or (string.upper(d.by) .. " PLAYED FIRST BIG WORD! (" .. d.len .. " LETTERS)")
	showFlash(msg, rgb(255, 215, 0), 2.2, matchFlashPos(), 38)
	sfx("brilliant")
end

handlers.Played = function(d)
	local mine = match and d.by == match.me.name
	local label = "+" .. (d.points or 0)
	if mine then
		local isFast = d.isFast or submitLeftFrac >= 0.5
		if isFast then
			quickCombo += 1
		else
			quickCombo = 0
		end
		if quickCombo >= 2 then
			local rank = STRIKE_RANKS[math.min(quickCombo, #STRIKE_RANKS)]
			label ..= "   " .. rank.name .. " x" .. quickCombo
			showFlash(rank.name .. "  (x" .. quickCombo .. ")", rank.color, 1.2, matchFlashPos(), rank.size)
		end
		if d.long then
			longRunCombo += 1
			if longRunCombo == 2 then
				label ..= "   CHAIN x2!"
				showFlash("WORD CHAIN!  (2 in a row)", C.teal, 1.1, matchFlashPos(), 38)
			elseif longRunCombo == 3 then
				label ..= "   MASTER x3!"
				showFlash("VOCABULARY MASTER!  (3 in a row)", C.amber, 1.2, matchFlashPos(), 42)
			elseif longRunCombo >= 4 then
				label ..= "   DEMON x" .. longRunCombo .. "!"
				showFlash("DICTIONARY DEMON!  (" .. longRunCombo .. " in a row)", C.red, 1.4, matchFlashPos(), 46)
			else
				label ..= "   LONG WORD!"
			end
		else
			longRunCombo = 0
		end
		if (d.points or 0) >= 10 then
			showFlash("LEGENDARY MOVE!  +" .. d.points .. " PTS", rgb(255, 215, 0), 1.4, matchFlashPos(), 48)
		elseif (d.points or 0) >= 7 then
			showFlash("MASSIVE PLAY!  +" .. d.points .. " PTS", C.amber, 1.2, matchFlashPos(), 40)
		end
		local s = sounds.good
		if s then
			s.PlaybackSpeed = 1 + 0.08 * math.min(quickCombo, 8)
		end
		if quickCombo >= 5 or (d.points or 0) >= 10 or longRunCombo >= 4 then
			sfx("brilliant")
		else
			sfx("good")
		end
	else
		sfx("key")
	end
	scorePop(mine, label, mine and C.teal or C.red)
	if d.volley and d.volley % 10 == 0 then
		task.delay(0.4, function()
			if hud.Visible then
				local rText = "RALLY " .. d.volley .. "  -  FASTER!"
				local rColor = C.blue
				if d.volley == 10 then
					rText = "RALLY 10  -  HEATING UP!"
					rColor = C.teal
				elseif d.volley == 20 then
					rText = "RALLY 20  -  ON FIRE!"
					rColor = C.amber
				elseif d.volley == 30 then
					rText = "RALLY 30  -  BLITZ SPEED!"
					rColor = C.red
				elseif d.volley >= 40 then
					rText = "RALLY " .. d.volley .. "  -  UNSTOPPABLE!"
					rColor = rgb(255, 215, 0)
				end
				showFlash(rText, rColor, 1.3, matchFlashPos(), 42)
				sfx("whoosh")
			end
		end)
	end
end

handlers.TimeShieldEarned = function(d)
	local mine = match and d.by == match.me.name
	if mine then
		showFlash("TIME SHIELD! (+2.0s FOR 5+ PT WORD)", rgb(255, 215, 0), 1.6, matchFlashPos(), 36)
		sfx("brilliant")
	else
		showFlash(string.upper(d.by) .. " EARNED TIME SHIELD! (+2s)", C.blue, 1.3, matchFlashPos(), 32)
	end
end

handlers.TimeShieldActive = function(d)
	local mine = match and d.by == match.me.name
	if mine then
		showFlash("TIME SHIELD ACTIVATED (+2.0s CLOCK)", C.teal, 1.4, matchFlashPos(), 36)
		sfx("whoosh")
	end
end

handlers.SlotOpened = function(d)
	-- Clutch slot unlocked mid-match: subtle cue only, never distract from typing
	sfx("whoosh")
end

handlers.Reward = function(r)
	queueReward(r)
end

handlers.BoutEnd = function(r)
	hud.Visible = false
	match = nil
	coachCard.Visible = false
	quickCombo = 0
	longRunCombo = 0
	submitLeftFrac = 0
	clearChildren(resultTitle)
	local word = r.won and "VICTORY" or "DEFEAT"
	if r.tutorial then
		word = r.won and "READY" or "AGAIN"
	end
	tileWord(resultTitle, word, 50, 6, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		face = r.won and C.amber or C.red,
		lip = r.won and C.amberLip or C.redLip,
		ink = r.won and C.ink or C.white,
	})
	local why
	if r.reason == "tutorial" then
		why = "Tutorial complete - you're ready to duel for Elo in Ranked!"
	elseif r.reason == "target" then
		why = r.won and ("You reached " .. string.upper(r.word or "") .. " first") or ("Your rival reached " .. string.upper(r.word or "") .. " first")
	elseif r.reason == "timeout" then
		why = r.won and "Their clock ran out" or "Your clock ran out"
	else
		why = r.won and "Your opponent left" or "You left the table"
	end
	if r.reason == "tutorial" then
		resultWhy.Position = UDim2.fromOffset(0, 100)
		resultWhy.Size = UDim2.new(1, 0, 0, 22)
		resultWhy.TextSize = 16
		resultWhy.Text = why
		resultWhy.TextColor3 = C.dim
	elseif r.eloProtected then
		resultWhy.Position = UDim2.fromOffset(0, 92)
		resultWhy.Size = UDim2.new(1, 0, 0, 36)
		resultWhy.TextSize = 14
		resultWhy.Text = string.format("VALIANT EFFORT! %s on %s (score %d vs %d)\nELO LOSS CUT IN HALF FOR OUTSCORING RIVAL!", why, string.upper(r.word or ""), r.score or 0, r.rivalScore or 0)
		resultWhy.TextColor3 = C.amber
	else
		resultWhy.Position = UDim2.fromOffset(0, 100)
		resultWhy.Size = UDim2.new(1, 0, 0, 22)
		resultWhy.TextSize = 16
		resultWhy.Text = string.format("%s on %s  -  score %d vs %d", why, string.upper(r.word or ""), r.score or 0, r.rivalScore or 0)
		resultWhy.TextColor3 = C.dim
	end
	statScore.Text = tostring(r.score or 0)
	statScore.TextColor3 = C.amber
	statXP.Text = "+" .. (r.xp or 0)
	statCoins.Text = "+" .. (r.coins or 0)
	statElo.Text = (r.eloDelta and r.eloDelta ~= 0) and string.format("%+d", r.eloDelta) or "-"
	statElo.TextColor3 = (r.eloDelta or 0) > 0 and C.teal or ((r.eloDelta or 0) < 0 and C.red or C.dim)
	local eloPart = ""
	if r.eloDelta and r.eloDelta ~= 0 then
		eloPart = string.format('   •   <font color="%s">%+d ELO</font>', r.eloDelta > 0 and "#3AD6A8" or "#FF5E64", r.eloDelta)
	end
	local ptsPart = string.format('<font color="#FFBA4A"><b>%d PTS</b></font> (+%d COINS)', r.score or 0, r.scoreCoins or r.score or 0)
	statsLine.Text = string.format('%s   •   +%d XP   •   +%d TOTAL COINS%s', ptsPart, r.xp or 0, r.coins or 0, eloPart)
	statsPill.Visible = true

	if r.luckyDrop then
		task.delay(0.2, function()
			showFlash("LUCKY DROP! +1 " .. string.upper(r.luckyDrop.name), rgb(255, 215, 0), 2.2, matchFlashPos(), 38)
			sfx("brilliant")
		end)
	end

	-- everything earned during the match, shown here instead of over the board
	clearChildren(earnedRow, "UIListLayout")
	local hasEarned = #pendingEarned > 0
	earnedLabel.Visible = hasEarned
	earnedRow.Visible = hasEarned
	if hasEarned then
		local count = #pendingEarned
		if count == 1 then
			earnedEntry(pendingEarned[1], 1, 280)
		elseif count == 2 then
			earnedEntry(pendingEarned[1], 1, 250)
			earnedEntry(pendingEarned[2], 2, 250)
		elseif count == 3 then
			earnedEntry(pendingEarned[1], 1, 180)
			earnedEntry(pendingEarned[2], 2, 180)
			earnedEntry(pendingEarned[3], 3, 180)
		else
			earnedEntry(pendingEarned[1], 1, 160)
			earnedEntry(pendingEarned[2], 2, 160)
			earnedEntry(pendingEarned[3], 3, 160)
			local moreCard = make("Frame", {
				BackgroundColor3 = C.s2,
				Size = UDim2.fromOffset(80, 60),
				LayoutOrder = 99,
				Parent = earnedRow,
			}, { corner(12), stroke(C.white, 0.82, 1.5) })
			text({
				Text = "+" .. (count - 3) .. "\nMORE",
				FontFace = F.heavy,
				TextSize = 13,
				TextColor3 = C.amber,
				TextXAlignment = CENTER,
				Size = UDim2.fromScale(1, 1),
				Parent = moreCard,
			})
		end
	end
	-- ranked win: you stay at the table as King automatically; Leave Table is optional
	local choice = r.won and r.canKing
	kingKey.holder.Visible = choice
	cashKey.holder.Visible = choice
	countdownBanner.Visible = choice
	leaveLink.Visible = choice
	okKey.holder.Visible = not choice
	kingBanner.Visible = false

	-- Dynamic vertical layout for resultCard so elements NEVER collide
	local y = 172
	if hasEarned then
		earnedLabel.Position = UDim2.fromOffset(0, y)
		y += 20
		earnedRow.Position = UDim2.new(0.5, 0, 0, y)
		y += 66
	end
	if choice then
		countdownBanner.Position = UDim2.new(0.5, 0, 0, y)
		y += 70
	end
	y += 8
	resultButtons.Position = UDim2.new(0.5, 0, 0, y)
	y += 76
	if choice then
		leaveLink.Position = UDim2.new(0.5, 0, 0, y)
		y += 22
	end
	y += 18
	resultCard.Size = UDim2.fromOffset(660, math.max(280, y))

	-- keep pendingEarned intact so flushEarned in lobby gives the full celebration modal
	if r.tutorial and r.won then
		guideAfterLobby = true
	end
	resultLayer.Visible = true
	resultScale.Scale = 0.85
	tween(resultScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	sfx(r.won and "win" or "lose")
	if choice then
		task.spawn(function()
			countdownFill.Size = UDim2.fromScale(1, 1)
			for i = Config.ContinueChoiceSeconds, 1, -1 do
				if not resultLayer.Visible then
					return
				end
				countdownTitle.Text = string.format("NEXT OPPONENT IN %ds", i)
				countdownSub.Text = string.format("You're King%s! Auto-starting in %ds, or tap PLAY NOW", (r.streak and r.streak > 1) and (" (" .. r.streak .. " wins)") or "", i)
				tween(countdownFill, 1, { Size = UDim2.fromScale((i - 1) / Config.ContinueChoiceSeconds, 1) }, Enum.EasingStyle.Linear)
				task.wait(1)
			end
		end)
	end
end

handlers.KingWaiting = function(d)
	kingPanel.Visible = true
	clearChildren(kingWordHolder)
	tileWord(kingWordHolder, d.word, 42, 5)
	kingText.Text = "You hold the table. A challenger is on the way - they inherit this word on a 10s clock."
end

handlers.LobbyReturn = function()
	task.defer(function()
		flushEarned()
		if guideAfterLobby then
			guideAfterLobby = false
			openModal("guide")
		end
	end)
	setControls(true)
	setTypingKeys(false)
	coachCard.Visible = false
	hud.Visible = false
	kingPanel.Visible = false
	match = nil
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hum then hum.Sit = false end
	if root then
		for _, w in ipairs(root:GetChildren()) do
			if w:IsA("Weld") or w.Name == "SeatWeld" then
				w:Destroy()
			end
		end
		if root.Position.Z > -45 then
			root.CFrame = CFrame.lookAt(Vector3.new(0, 4, -55), Vector3.new(0, 4, 0))
		end
	end
	showLobby(true)
end

Net.OnClientEvent:Connect(function(action, payload)
	local h = handlers[action]
	if h then
		local ok, err = pcall(h, payload)
		if not ok then
			warn("[WordDuel] client handler", action, "failed:", err)
		end
	end
end)

player.Chatted:Connect(function(msg)
	if msg == "/reset" or msg == "/first" then
		fire("ResetFirstTime")
	end
end)

fire("ClientReady")
showLobby(true)
