-- Arena: the tournament hall. A walled room with duel tables; each table has its own
-- game set (felt top, a rack of 3D letter tiles showing the live word, a duel clock,
-- a letter bag and a brass bell). Built from plain parts, no custom assets.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Arena = {}

local folder = Instance.new("Folder")
folder.Name = "WordDuelArena"
folder.Parent = workspace

local MONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local BUILDER = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function surfaceText(p, face, text, props)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = props.pps or 50
	sg.LightInfluence = props.light or 0.4
	sg.Parent = p
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.FontFace = props.font or MONT
	l.TextScaled = true
	l.TextColor3 = props.color or Color3.fromRGB(28, 26, 34)
	l.Text = text
	l.Parent = sg
	if props.pad then
		local u = Instance.new("UIPadding")
		u.PaddingTop = UDim.new(props.pad, 0)
		u.PaddingBottom = UDim.new(props.pad, 0)
		u.PaddingLeft = UDim.new(props.pad, 0)
		u.PaddingRight = UDim.new(props.pad, 0)
		u.Parent = l
	end
	return l, sg
end

---------------------------------------------------------------- mood
do
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 16.8
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(92, 80, 88)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 112, 116)
	Lighting.ExposureCompensation = 0.35
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	for _, ch in ipairs(Lighting:GetChildren()) do
		if ch:IsA("Atmosphere") or ch:IsA("PostEffect") then
			ch:Destroy()
		end
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.24
	atmo.Offset = 0.1
	atmo.Color = Color3.fromRGB(220, 190, 160)
	atmo.Decay = Color3.fromRGB(150, 120, 120)
	atmo.Glare = 0.2
	atmo.Haze = 1.6
	atmo.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.08
	cc.Saturation = 0.06
	cc.TintColor = Color3.fromRGB(255, 244, 232)
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end

---------------------------------------------------------------- the hall
-- interior: x -62..62, z -80..46
local HALL_MIN, HALL_MAX = Vector3.new(-62, 0, -80), Vector3.new(62, 0, 46)
local center = (HALL_MIN + HALL_MAX) / 2
local sizeX, sizeZ = HALL_MAX.X - HALL_MIN.X, HALL_MAX.Z - HALL_MIN.Z

part({ Name = "Floor", Size = Vector3.new(sizeX + 8, 1, sizeZ + 8), Position = Vector3.new(center.X, -0.5, center.Z), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(132, 94, 66), Parent = folder })
part({ Name = "Rug", Size = Vector3.new(118, 0.1, 64), Position = Vector3.new(0, 0.05, 8), Material = Enum.Material.Fabric, Color = Color3.fromRGB(122, 40, 46), CanCollide = false, Parent = folder })
part({ Name = "RugBorder", Size = Vector3.new(121, 0.08, 67), Position = Vector3.new(0, 0.04, 8), Material = Enum.Material.Fabric, Color = Color3.fromRGB(196, 150, 70), CanCollide = false, Parent = folder })

local WALL_H = 28
local function wall(name, size, pos)
	-- dark wood wainscot below, warm plaster above, a brass rail between
	part({ Name = name .. "Upper", Size = Vector3.new(size.X, WALL_H, size.Z), Position = pos + Vector3.new(0, WALL_H / 2, 0), Material = Enum.Material.Plaster, Color = Color3.fromRGB(150, 120, 104), Parent = folder })
	local inset = (size.X > size.Z) and Vector3.new(0, 0, 0.3) or Vector3.new(0.3, 0, 0)
	part({ Name = name .. "Panel", Size = Vector3.new(size.X + 0.6, 7, size.Z + 0.6), Position = pos + Vector3.new(0, 3.5, 0), Material = Enum.Material.Wood, Color = Color3.fromRGB(70, 44, 30), Parent = folder })
	part({ Name = name .. "Rail", Size = Vector3.new(size.X + 0.9, 0.35, size.Z + 0.9), Position = pos + Vector3.new(0, 7.1, 0), Material = Enum.Material.Metal, Color = Color3.fromRGB(196, 150, 70), Parent = folder })
	return inset
end
wall("WallN", Vector3.new(sizeX + 4, 0, 2), Vector3.new(center.X, 0, HALL_MAX.Z + 1))
wall("WallS", Vector3.new(sizeX + 4, 0, 2), Vector3.new(center.X, 0, HALL_MIN.Z - 1))
wall("WallE", Vector3.new(2, 0, sizeZ + 4), Vector3.new(HALL_MAX.X + 1, 0, center.Z))
wall("WallW", Vector3.new(2, 0, sizeZ + 4), Vector3.new(HALL_MIN.X - 1, 0, center.Z))
-- invisible lid so nobody climbs out
part({ Name = "Lid", Size = Vector3.new(sizeX + 4, 1, sizeZ + 4), Position = Vector3.new(center.X, WALL_H + 0.5, center.Z), Transparency = 1, Parent = folder })

-- columns with sconces
for _, x in ipairs({ HALL_MIN.X + 1.5, HALL_MAX.X - 1.5 }) do
	for z = HALL_MIN.Z + 14, HALL_MAX.Z - 6, 22 do
		part({ Name = "Column", Size = Vector3.new(3, WALL_H, 3), Position = Vector3.new(x, WALL_H / 2, z), Material = Enum.Material.Wood, Color = Color3.fromRGB(58, 36, 24), Parent = folder })
		local lamp = part({ Name = "Sconce", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), Position = Vector3.new(x + (x < 0 and 1.8 or -1.8), 12, z), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 200, 140), CanCollide = false, Parent = folder })
		local l = Instance.new("PointLight")
		l.Range = 18
		l.Brightness = 1.4
		l.Color = Color3.fromRGB(255, 200, 150)
		l.Parent = lamp
	end
end

-- big title banner on the far wall, made of letter tiles
do
	local word = "WORD DUEL"
	local tileSize, gap = 5.2, 0.8
	local width = #word * (tileSize + gap)
	local x0 = -width / 2 + tileSize / 2
	for i = 1, #word do
		local ch = word:sub(i, i)
		if ch ~= " " then
			local amber = i > 5
			local t = part({
				Name = "BannerTile",
				Size = Vector3.new(tileSize, tileSize, 0.6),
				Position = Vector3.new(x0 + (i - 1) * (tileSize + gap), 15 + ((i % 2 == 0) and 0.4 or -0.4), HALL_MAX.Z - 0.4),
				Color = amber and Color3.fromRGB(255, 186, 74) or Color3.fromRGB(247, 238, 216),
				Material = Enum.Material.SmoothPlastic,
				Parent = folder,
			})
			t.Orientation = Vector3.new(0, 180, (i % 3 - 1) * 3)
			surfaceText(t, Enum.NormalId.Front, ch, { pad = 0.12, light = 0.2 })
		end
	end
	local sub = part({ Name = "BannerSub", Size = Vector3.new(40, 2, 0.2), Position = Vector3.new(0, 10.2, HALL_MAX.Z - 0.3), Transparency = 1, CanCollide = false, Parent = folder })
	sub.Orientation = Vector3.new(0, 180, 0)
	surfaceText(sub, Enum.NormalId.Front, "KEEP A LETTER IN PLACE.  BEAT THE CLOCK.", { font = BUILDER, color = Color3.fromRGB(255, 236, 210), light = 0 })
end

local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(10, 0.2, 10)
spawn.CFrame = CFrame.lookAt(Vector3.new(0, 0.1, -60), Vector3.new(0, 0.1, 0))
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Neutral = true
spawn.Duration = 0
spawn.Parent = folder
for _, d in ipairs(spawn:GetChildren()) do
	if d:IsA("Decal") then
		d:Destroy()
	end
end
Arena.LobbyCFrame = CFrame.lookAt(Vector3.new(0, 4, -55), Vector3.new(0, 4, 0))

---------------------------------------------------------------- duel tables
Arena.Tables = {}
local MAX_TILES = 10
local TILE = 0.95
local TABLE_TOP = 3.4

local function buildTable(index, origin)
	local model = Instance.new("Model")
	model.Name = "Table" .. index
	model.Parent = folder

	local wood = Color3.fromRGB(64, 38, 24)
	local brass = Color3.fromRGB(196, 150, 70)
	-- pedestal + round top with brass rim and green felt
	part({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.6, 3.6), Position = origin + Vector3.new(0, 0.2, 0), Orientation = Vector3.new(0, 0, 90), Color = wood, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Leg", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.1, 1.1), Position = origin + Vector3.new(0, 1.7, 0), Orientation = Vector3.new(0, 0, 90), Color = wood, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 8.6, 8.6), Position = origin + Vector3.new(0, TABLE_TOP - 0.25, 0), Orientation = Vector3.new(0, 0, 90), Color = brass, Material = Enum.Material.Metal, Parent = model })
	part({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 8.2, 8.2), Position = origin + Vector3.new(0, TABLE_TOP - 0.2, 0), Orientation = Vector3.new(0, 0, 90), Color = wood, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Felt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 7, 7), Position = origin + Vector3.new(0, TABLE_TOP + 0.02, 0), Orientation = Vector3.new(0, 0, 90), Color = Color3.fromRGB(24, 74, 56), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })

	-- word rack across the middle, tiles stand in it (letters on both faces)
	local rackLen = 7.4 -- fits the table; tiles shrink for long words
	part({ Name = "Rack", Size = Vector3.new(rackLen, 0.35, 0.9), Position = origin + Vector3.new(0, TABLE_TOP + 0.2, 0), Color = Color3.fromRGB(92, 58, 34), Material = Enum.Material.Wood, Parent = model })
	part({ Name = "RackLip", Size = Vector3.new(rackLen, 0.12, 0.95), Position = origin + Vector3.new(0, TABLE_TOP + 0.4, 0), Color = brass, Material = Enum.Material.Metal, Parent = model })
	local tiles = {}
	for i = 1, MAX_TILES do
		local x = (i - (MAX_TILES + 1) / 2) * (TILE + 0.12)
		local t = part({
			Name = "Tile" .. i,
			Size = Vector3.new(TILE, TILE, 0.24),
			Position = origin + Vector3.new(x, TABLE_TOP + 0.95, 0),
			Color = Color3.fromRGB(247, 238, 216),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Transparency = 1,
			Parent = model,
		})
		local front, sgF = surfaceText(t, Enum.NormalId.Front, "", { pad = 0.1 })
		local back, sgB = surfaceText(t, Enum.NormalId.Back, "", { pad = 0.1 })
		sgF.Enabled = false
		sgB.Enabled = false
		tiles[i] = { part = t, labels = { front, back }, guis = { sgF, sgB }, home = t.CFrame, letter = nil }
	end

	-- duel clock: a wooden box with a lit display on each side and two plunger buttons
	local clock = part({ Name = "Clock", Size = Vector3.new(1.8, 0.9, 0.9), Position = origin + Vector3.new(2.6, TABLE_TOP + 0.45, 0), Color = Color3.fromRGB(40, 26, 18), Material = Enum.Material.Wood, Parent = model })
	local screen = part({ Name = "ClockScreen", Size = Vector3.new(1.3, 0.55, 0.95), Position = clock.Position + Vector3.new(0, 0.05, 0), Color = Color3.fromRGB(16, 18, 24), Material = Enum.Material.SmoothPlastic, Parent = model })
	local clockLabels = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local l = surfaceText(screen, face, "--", { color = Color3.fromRGB(255, 186, 74), light = 0, pad = 0.08 })
		table.insert(clockLabels, l)
	end
	local btnA = part({ Name = "ButtonA", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.45, 0.45), Position = clock.Position + Vector3.new(0, 0.6, -0.25), Orientation = Vector3.new(0, 0, 90), Color = Color3.fromRGB(60, 60, 60), Parent = model })
	local btnB = part({ Name = "ButtonB", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.45, 0.45), Position = clock.Position + Vector3.new(0, 0.6, 0.25), Orientation = Vector3.new(0, 0, 90), Color = Color3.fromRGB(60, 60, 60), Parent = model })

	-- letter bag + brass bell + score pads
	part({ Name = "LetterBag", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), Position = origin + Vector3.new(-2.6, TABLE_TOP + 0.55, 0.9), Color = Color3.fromRGB(96, 40, 110), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	part({ Name = "BagTie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.5, 0.5), Position = origin + Vector3.new(-2.6, TABLE_TOP + 1.15, 0.9), Orientation = Vector3.new(0, 0, 90), Color = brass, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	part({ Name = "SpillTile", Size = Vector3.new(0.6, 0.12, 0.6), Position = origin + Vector3.new(-1.9, TABLE_TOP + 0.08, 1.5), Orientation = Vector3.new(0, 25, 0), Color = Color3.fromRGB(247, 238, 216), CanCollide = false, Parent = model })
	part({ Name = "BellBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.7, 0.7), Position = origin + Vector3.new(-2.6, TABLE_TOP + 0.08, -1.1), Orientation = Vector3.new(0, 0, 90), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	part({ Name = "Bell", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Position = origin + Vector3.new(-2.6, TABLE_TOP + 0.3, -1.1), Color = brass, Material = Enum.Material.Metal, Reflectance = 0.15, CanCollide = false, Parent = model })
	for _, z in ipairs({ -2.7, 2.7 }) do
		local pad = part({ Name = "ScorePad", Size = Vector3.new(1.6, 0.05, 1.1), Position = origin + Vector3.new(1.2, TABLE_TOP + 0.05, z), Orientation = Vector3.new(0, z < 0 and 8 or -172, 0), Color = Color3.fromRGB(240, 232, 214), CanCollide = false, Parent = model })
		surfaceText(pad, Enum.NormalId.Top, "WORD DUEL", { font = MONT, color = Color3.fromRGB(196, 122, 26), light = 0.6, pad = 0.25 })
	end

	-- hanging lamp: warm pool of light on each table
	part({ Name = "LampCord", Size = Vector3.new(0.1, 6, 0.1), Position = origin + Vector3.new(0, 18, 0), Color = Color3.fromRGB(20, 20, 20), CanCollide = false, Parent = model })
	part({ Name = "LampShade", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3, 3), Position = origin + Vector3.new(0, 14.8, 0), Orientation = Vector3.new(0, 0, 90), Color = Color3.fromRGB(28, 60, 44), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	local bulb = part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Position = origin + Vector3.new(0, 14.2, 0), Color = Color3.fromRGB(255, 214, 160), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 80
	light.Range = 22
	light.Brightness = 4
	light.Color = Color3.fromRGB(255, 210, 160)
	light.Shadows = true
	light.Parent = bulb

	-- seats face each other along Z
	-- Premium luxury duel chairs: midnight obsidian leather, polished gold/brass accents, dark walnut wood
	-- Completely distinct and high contrast against oak wood floor and burgundy rug
	local chairWood = Color3.fromRGB(36, 22, 14)
	local chairLeather = Color3.fromRGB(24, 28, 40)
	local chairBrass = Color3.fromRGB(218, 165, 32)

	local function makeChair(name, pos, lookTarget)
		local cf = CFrame.lookAt(pos, lookTarget)
		-- 4 walnut legs with brass ferrules
		for _, dx in ipairs({ -0.95, 0.95 }) do
			for _, dz in ipairs({ -0.95, 0.95 }) do
				part({
					Name = name .. "Leg",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.4, 0.22, 0.22),
					CFrame = cf * CFrame.new(dx, -1.05, dz) * CFrame.Angles(0, 0, math.pi / 2),
					Color = chairWood,
					Material = Enum.Material.Wood,
					Parent = model,
				})
			end
		end
		-- Walnut frame base under seat
		part({
			Name = name .. "Base",
			Size = Vector3.new(2.6, 0.2, 2.6),
			CFrame = cf * CFrame.new(0, -0.3, 0),
			Color = chairWood,
			Material = Enum.Material.Wood,
			Parent = model,
		})
		-- Polished brass accent ring below cushion
		part({
			Name = name .. "Trim",
			Size = Vector3.new(2.5, 0.1, 2.5),
			CFrame = cf * CFrame.new(0, -0.15, 0),
			Color = chairBrass,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		-- Padded luxury midnight obsidian leather Seat
		local seat = Instance.new("Seat")
		seat.Name = name
		seat.Anchored = true
		seat.Size = Vector3.new(2.4, 0.6, 2.4)
		seat.CFrame = cf
		seat.Color = chairLeather
		seat.Material = Enum.Material.Leather
		seat.Parent = model
		return seat
	end

	local seatA = makeChair("SeatA", origin + Vector3.new(0, 1.8, -5), origin + Vector3.new(0, 1.8, 0))
	local seatB = makeChair("SeatB", origin + Vector3.new(0, 1.8, 5), origin + Vector3.new(0, 1.8, 0))

	-- small floating names for spectators
	local anchor = part({ Name = "Display", Size = Vector3.new(1, 1, 1), Position = origin + Vector3.new(0, 8.2, 0), Transparency = 1, CanCollide = false, Parent = model })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(11, 1.4)
	bb.LightInfluence = 0
	bb.MaxDistance = 70
	bb.Parent = anchor
	local namesLabel = Instance.new("TextLabel")
	namesLabel.Name = "Names"
	namesLabel.Size = UDim2.fromScale(1, 1)
	namesLabel.BackgroundTransparency = 1
	namesLabel.FontFace = BUILDER
	namesLabel.TextScaled = true
	namesLabel.TextColor3 = Color3.fromRGB(255, 236, 210)
	namesLabel.TextStrokeTransparency = 0.5
	namesLabel.Text = ""
	namesLabel.Parent = bb

	local t = {
		index = index,
		model = model,
		seats = { seatA, seatB },
		buttons = { btnA, btnB },
		tiles = tiles,
		clockLabels = clockLabels,
		namesLabel = namesLabel,
		busy = false,
		origin = origin,
		assigned = {},
		rigs = {},
		seatTokens = { 0, 0 },
		deadline = nil,
		rackCenter = CFrame.new(origin + Vector3.new(0, TABLE_TOP + 0.95, 0)),
		shownLen = 0,
	}
	-- only the two assigned duelists (players or NPC rigs) may sit here
	for side, seat in ipairs(t.seats) do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = seat.Occupant
			if not hum then
				return
			end
			local who = Players:GetPlayerFromCharacter(hum.Parent) or hum.Parent
			if who ~= t.assigned[side] then
				task.defer(function()
					if seat.Occupant == hum then
						local curWho = Players:GetPlayerFromCharacter(hum.Parent) or hum.Parent
						if curWho ~= t.assigned[side] then
							hum.Sit = false
						end
					end
				end)
			end
		end)
	end
	table.insert(Arena.Tables, t)
	return t
end

do
	local cols = 4
	for i = 1, 8 do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		buildTable(i, Vector3.new((col - 1.5) * 26, 0, row * 26 - 5))
	end
end

---------------------------------------------------------------- API
function Arena.FreeTable()
	for _, t in ipairs(Arena.Tables) do
		if not t.busy then
			return t
		end
	end
	return nil
end

-- show `word` centered on the table's tile rack; tiles whose letter changed hop up briefly
function Arena.SetDisplay(t, word, names)
	t.namesLabel.Text = names or ""
	local len = word and #word or 0
	local relayout = len ~= t.shownLen
	t.shownLen = len
	for i, tile in ipairs(t.tiles) do
		local show = i <= len
		tile.part.Transparency = show and 0 or 1
		for _, g in ipairs(tile.guis) do
			g.Enabled = show
		end
		if show then
			local w = math.min(TILE, 7.0 / len - 0.1)
			local home = t.rackCenter * CFrame.new((i - (len + 1) / 2) * (w + 0.1), (w - TILE) / 2, 0)
			local up = string.upper(word:sub(i, i))
			if relayout then
				tile.home = home
				tile.part.Size = Vector3.new(w, w, 0.24)
				tile.part.CFrame = home
			elseif tile.letter and tile.letter ~= up then
				TweenService:Create(tile.part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { CFrame = tile.home * CFrame.new(0, 0.45, 0) }):Play()
			end
			-- tiles run along +X; seat A (front faces) sees +X on its LEFT, so the front faces
			-- carry the mirrored position's letter and the back faces read normally for seat B
			tile.labels[1].Text = string.upper(word:sub(len + 1 - i, len + 1 - i))
			tile.labels[2].Text = up
			tile.letter = up
		else
			tile.letter = nil
		end
	end
end

-- side = 1 or 2: whose clock is running (0 = none)
function Arena.SetClock(t, side)
	for i, b in ipairs(t.buttons) do
		b.Color = side == i and Color3.fromRGB(230, 70, 60) or Color3.fromRGB(60, 60, 60)
		b.Material = side == i and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
end

function Arena.SetTimer(t, deadline)
	t.deadline = deadline
	if not deadline then
		for _, l in ipairs(t.clockLabels) do
			l.Text = "--"
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local now = workspace:GetServerTimeNow()
		for _, t in ipairs(Arena.Tables) do
			if t.deadline then
				local txt = tostring(math.max(0, math.ceil(t.deadline - now)))
				for _, l in ipairs(t.clockLabels) do
					if l.Text ~= txt then
						l.Text = txt
					end
				end
			end
		end
	end
end)

local function humanoidOf(player)
	local char = player and player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function resetSeat(t, side, seat)
	local sign = (side == 1) and -1 or 1
	seat.Anchored = true
	seat.CFrame = CFrame.lookAt(t.origin + Vector3.new(0, 1.8, sign * 5), t.origin + Vector3.new(0, 1.8, 0))
end

local function clearSeatOccupant(t, side, seat, keepHum)
	if t.rigs[side] then
		if t.rigs[side].Parent then
			t.rigs[side]:Destroy()
		end
		t.rigs[side] = nil
	end
	local occ = seat.Occupant
	if occ and occ ~= keepHum then
		if not Players:GetPlayerFromCharacter(occ.Parent) then
			if occ.Parent then
				occ.Parent:Destroy()
			end
		else
			occ.Sit = false
		end
	end
	local weld = seat:FindFirstChild("SeatWeld")
	if weld and (not keepHum or seat.Occupant ~= keepHum) then
		weld:Destroy()
	end
end

function Arena.Seat(t, side, player)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	t.seatTokens[side] = (t.seatTokens[side] or 0) + 1
	local token = t.seatTokens[side]
	local seat = t.seats[side]
	t.assigned[side] = player
	hum.UseJumpPower = true
	hum.JumpPower = 0
	if player.Character then
		player.Character.Archivable = true -- lets the opponent's HUD render this avatar
	end

	-- Fast path: player is already cleanly seated in their assigned chair
	if seat.Occupant == hum and hum.SeatPart == seat and seat:FindFirstChild("SeatWeld") then
		if t.rigs[side] then
			if t.rigs[side].Parent then
				t.rigs[side]:Destroy()
			end
			t.rigs[side] = nil
		end
		seat.Anchored = true
		return
	end

	clearSeatOccupant(t, side, seat, hum)
	resetSeat(t, side, seat)

	if hum.SeatPart and hum.SeatPart ~= seat then
		local oldWeld = hum.SeatPart:FindFirstChild("SeatWeld")
		if oldWeld then
			oldWeld:Destroy()
		end
		hum.Sit = false
	end
	local root = hum.RootPart
	if root then
		for _, w in ipairs(root:GetChildren()) do
			if w:IsA("Weld") or w.Name == "SeatWeld" then
				w:Destroy()
			end
		end
	end

	local function trySit(curHum)
		local char = player.Character
		local r = curHum.RootPart
		if char then
			if r then
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end
			char:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
		end
		seat:Sit(curHum)
	end

	if not hum.Sit and not seat.Occupant then
		trySit(hum)
	end

	task.spawn(function()
		for _ = 1, 25 do
			task.wait(0.08)
			if t.seatTokens[side] ~= token or t.assigned[side] ~= player or not player.Parent then
				return
			end
			local curHum = humanoidOf(player)
			if not curHum or curHum.Health <= 0 then
				return
			end
			if seat.Occupant == curHum and curHum.SeatPart == seat then
				return
			end
			if curHum.Sit and curHum.SeatPart ~= seat then
				local oldWeld = curHum.SeatPart and curHum.SeatPart:FindFirstChild("SeatWeld")
				if oldWeld then
					oldWeld:Destroy()
				end
				curHum.Sit = false
			else
				clearSeatOccupant(t, side, seat, curHum)
				resetSeat(t, side, seat)
				trySit(curHum)
			end
		end
	end)
end

-- seat an NPC rig (bot opponent or ambient duelist)
function Arena.SeatRig(t, side, rig)
	local seat = t.seats[side]
	local hum = rig:FindFirstChildOfClass("Humanoid")
	t.seatTokens[side] = (t.seatTokens[side] or 0) + 1
	local token = t.seatTokens[side]
	if t.rigs[side] and t.rigs[side] ~= rig then
		if t.rigs[side].Parent then
			t.rigs[side]:Destroy()
		end
		t.rigs[side] = nil
	end
	clearSeatOccupant(t, side, seat, hum)
	resetSeat(t, side, seat)
	t.assigned[side] = rig
	t.rigs[side] = rig
	rig:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
	rig.Parent = folder
	if hum then
		task.spawn(function()
			for _ = 1, 30 do
				if t.seatTokens[side] ~= token or t.assigned[side] ~= rig or not rig.Parent then
					return
				end
				if seat.Occupant == hum then
					return
				end
				if not seat.Occupant then
					resetSeat(t, side, seat)
					rig:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
					seat:Sit(hum)
				end
				task.wait(0.05)
			end
		end)
	end
end

function Arena.ClearSeats(t, keep)
	for side, seat in ipairs(t.seats) do
		t.seatTokens[side] = (t.seatTokens[side] or 0) + 1
		local keepPlayer = keep and keep[side]
		local keepHum = keepPlayer and humanoidOf(keepPlayer)
		if keepPlayer and keepHum and seat.Occupant == keepHum and keepHum.SeatPart == seat and seat:FindFirstChild("SeatWeld") then
			if t.rigs[side] then
				if t.rigs[side].Parent then
					t.rigs[side]:Destroy()
				end
				t.rigs[side] = nil
			end
			t.assigned[side] = keepPlayer
			seat.Anchored = true
		else
			t.assigned[side] = nil
			clearSeatOccupant(t, side, seat)
			resetSeat(t, side, seat)
		end
	end
end

function Arena.Unseat(player)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	hum.Sit = false
	hum.JumpPower = 50
	local root = hum.RootPart
	if root then
		for _, w in ipairs(root:GetChildren()) do
			if w:IsA("Weld") or w.Name == "SeatWeld" then
				w:Destroy()
			end
		end
	end
	for _, t in ipairs(Arena.Tables) do
		for side, seat in ipairs(t.seats) do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld and (seat.Occupant == hum or t.assigned[side] == player) then
				weld:Destroy()
			end
			if t.assigned[side] == player then
				t.seatTokens[side] = (t.seatTokens[side] or 0) + 1
				t.assigned[side] = nil
			end
			-- Always ensure seat is anchored and at its correct table position
			resetSeat(t, side, seat)
		end
	end
	if root then
		task.defer(function()
			if root.Parent then
				root.CFrame = Arena.LobbyCFrame + Vector3.new(math.random(-6, 6), 0, math.random(-3, 3))
			end
		end)
	end
end

local function orientCharacter(player, char)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if root then
		task.defer(function()
			if root.Parent then
				for _, t in ipairs(Arena.Tables) do
					if t.assigned[1] == player or t.assigned[2] == player then
						return
					end
				end
				root.CFrame = Arena.LobbyCFrame + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2))
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		orientCharacter(player, char)
	end)
	if player.Character then
		orientCharacter(player, player.Character)
	end
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function(char)
		orientCharacter(player, char)
	end)
	if player.Character then
		orientCharacter(player, player.Character)
	end
end

return Arena
