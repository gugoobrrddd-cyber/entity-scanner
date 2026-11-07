--[[
	Thermal  /  entity scope (Client Version - Mobile Safe)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ContentProvider = game:GetService("ContentProvider")

----------------------------------------------------------------------
-- Access gate (Dilewati agar bisa berjalan bebas di client)
----------------------------------------------------------------------
local localPlayer = Players.LocalPlayer
if not localPlayer then
	warn("[Thermal] Must run in a LocalScript.")
	return
end

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local CONFIG = {
	PanelKey = Enum.KeyCode.RightControl,
	EspKey = Enum.KeyCode.RightAlt,
	MinRange = 25,
	MaxRange = 2000,
	DefaultRange = 400,
	MaxListRows = 60,
	MaxHighlights = 31, -- engine renders at most 31 Highlights
	MaxOverlay = 31, -- tracers + arrows, nearest first
	MaxBlips = 80,
	ToastLimit = 4,
	SweepSeconds = 2.4, -- one radar revolution
}

local SOUNDS = {
	Click = { Id = "rbxassetid://10128760939", Volume = 0.3 },
	Toggle = { Id = "rbxassetid://9117027976", Volume = 0.25 },
	Open = { Id = "rbxassetid://6698736600", Volume = 0.2 },
	Close = { Id = "rbxassetid://6698737249", Volume = 0.2 },
	Alert = { Id = "rbxassetid://5120879183", Volume = 0.35 },
	Scan = { Id = "rbxassetid://71083768704443", Volume = 0.3 },
}

local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

----------------------------------------------------------------------
-- Design tokens
----------------------------------------------------------------------
local C = {
	Housing = Color3.fromHex("#1D1F23"),
	Raised = Color3.fromHex("#24272C"),
	Hover = Color3.fromHex("#2B2E34"),
	Inset = Color3.fromHex("#16171A"),
	Bed = Color3.fromHex("#15120E"),
	Ring = Color3.fromHex("#3A332B"),
	Line = Color3.fromHex("#33363C"),
	LineSoft = Color3.fromHex("#2A2C31"),
	Text = Color3.fromHex("#ECE6DA"),
	Muted = Color3.fromHex("#8F8B83"),
	Accent = Color3.fromHex("#F28C28"),
	AccentInk = Color3.fromHex("#1A1206"),
	Ember = Color3.fromHex("#E8512F"),
	Shadow = Color3.fromHex("#0E0D0C"),
	Player = Color3.fromHex("#ECE6DA"),
	Npc = Color3.fromHex("#F28C28"),
}

local RAMP = {
	{ 0, Color3.fromHex("#7A57D1") },
	{ 0.3, Color3.fromHex("#C2408A") },
	{ 0.55, Color3.fromHex("#E8512F") },
	{ 0.8, Color3.fromHex("#F7A531") },
	{ 1, Color3.fromHex("#FFF3D1") },
}

local S = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
local R = { sm = 4, md = 6, lg = 12 }
local T = if TOUCH
	then { caption = 12, small = 13, body = 15, label = 16, title = 18, hero = 22 }
	else { caption = 11, small = 12, body = 14, label = 15, title = 17, hero = 20 }

local Z = {
	Row = if TOUCH then 48 else 38,
	RowHint = if TOUCH then 58 else 50,
	ListRow = if TOUCH then 42 else 30,
	Segment = if TOUCH then 36 else 28,
	SegmentW = if TOUCH then 72 else 64,
	Icon = if TOUCH then 36 else 28,
	Action = if TOUCH then 40 else 30,
	Search = if TOUCH then 38 else 32,
	SliderRow = if TOUCH then 62 else 54,
	SliderHit = if TOUCH then 40 else 26,
	BlipHit = if TOUCH then 26 else 16,
	Knob = if TOUCH then 16 else 12,
}
local M = { fast = 0.15, base = 0.2, panel = 0.3 }

local function fontFamily(enumName, fallback)
	local ok, family = pcall(function()
		return Font.fromEnum(Enum.Font[enumName]).Family
	end)
	if ok and family then
		return family
	end
	return Font.fromEnum(fallback).Family
end

local BODY_FAMILY = fontFamily("TitilliumWeb", Enum.Font.Gotham)
local DISPLAY_FAMILY = fontFamily("Michroma", Enum.Font.GothamBold)

local F = {
	Body = Font.new(BODY_FAMILY, Enum.FontWeight.Regular),
	Medium = Font.new(BODY_FAMILY, Enum.FontWeight.SemiBold),
	Bold = Font.new(BODY_FAMILY, Enum.FontWeight.Bold),
	Display = Font.new(DISPLAY_FAMILY, Enum.FontWeight.Regular),
}

local state = {
	Esp = true,
	Highlights = true,
	Names = true,
	Distance = true,
	Health = true,
	Tracers = false,
	Arrows = true,
	Players = true,
	Npcs = true,
	HideTeam = false,
	ColorMode = "Thermal",
	Fill = 0.25,
	Range = CONFIG.DefaultRange,
	Alerts = false,
	AlertRadius = 40,
	Sounds = true,
	Sweep = true,
	Rate = "Normal",
	Filter = "",
	Sort = "Distance",
	RadarMode = "Heading",
}

local RATES = { Fast = 0.1, Normal = 0.25, Eco = 0.5 }

local bindings = {}
local updateAccumulator = math.huge

local function requestUpdate()
	updateAccumulator = math.huge
end

local function bind(key, fn)
	bindings[key] = bindings[key] or {}
	table.insert(bindings[key], fn)
end

local function setState(key, value)
	state[key] = value
	local list = bindings[key]
	if list then
		for _, fn in list do
			fn(value)
		end
	end
	requestUpdate()
end

local motionReduced = false
local function readReducedMotion()
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	motionReduced = ok and value == true
end
readReducedMotion()

local function create(className, props, children)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	local value = if typeof(radius) == "UDim" then radius else UDim.new(0, radius)
	return create("UICorner", { CornerRadius = value, Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function pad(parent, left, right, top, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
		Parent = parent,
	})
end

local function text(props)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or F.Body
	props.TextSize = props.TextSize or T.body
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Text = props.Text or ""
	return create("TextLabel", props)
end

local function textStroke(label)
	return create("UIStroke", {
		Color = C.Shadow,
		Thickness = 1.5,
		Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
end

local function hairline(parent, props)
	props.BackgroundColor3 = props.BackgroundColor3 or C.LineSoft
	props.Parent = parent
	return create("Frame", props)
end

local function tween(inst, duration, goal, style, direction)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(
			if motionReduced then 0 else duration,
			style or Enum.EasingStyle.Quint,
			direction or Enum.EasingDirection.Out
		),
		goal
	)
	t:Play()
	return t
end

local function ironbow(t)
	t = math.clamp(t, 0, 1)
	for i = 1, #RAMP - 1 do
		local a, b = RAMP[i], RAMP[i + 1]
		if t <= b[1] then
			return a[2]:Lerp(b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return RAMP[#RAMP][2]
end

local function rampSequence()
	local points = {}
	for _, k in RAMP do
		table.insert(points, ColorSequenceKeypoint.new(k[1], k[2]))
	end
	return ColorSequence.new(points)
end

local function formatNumber(n)
	if n ~= n then
		return "?"
	end
	if n == math.huge then
		return "inf"
	end
	if n == -math.huge then
		return "-inf"
	end
	return tostring(math.floor(n + 0.5))
end

local function escapeRich(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local MUTED_HEX = "#" .. C.Muted:ToHex()

local selectionRing = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
})
corner(selectionRing, R.md)
create("UIStroke", {
	Color = C.Accent,
	Thickness = 2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = selectionRing,
})

local function onHover(gui, enter, leave)
	if TOUCH then
		return
	end
	gui.MouseEnter:Connect(enter)
	gui.MouseLeave:Connect(leave)
end

local function pressable(button)
	local scale = create("UIScale", { Parent = button })
	button.SelectionImageObject = selectionRing
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.96 }, Enum.EasingStyle.Quad)
	end)
	local function release()
		tween(scale, M.fast, { Scale = 1 })
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	return button
end

local function plural(n, word, wordPlural)
	return tostring(n) .. " " .. (if n == 1 then word else (wordPlural or word .. "s"))
end

local function keyName(keyCode)
	local name = keyCode.Name:gsub("Control", "Ctrl")
	name = name:gsub("(%l)(%u)", "%1 %2")
	return name
end

local function getRoot(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function isPointerDown(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isPointerMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local toast, playSound, openInspector, closeInspector, refreshInspector, selectTab
local spectating = nil

local function stopSpectate()
	if not spectating then
		return
	end
	spectating = nil
	local camera = workspace.CurrentCamera
	local myChar = localPlayer.Character
	local myHumanoid = if myChar then myChar:FindFirstChildOfClass("Humanoid") else nil
	if camera and myHumanoid then
		camera.CameraSubject = myHumanoid
	end
end

local function startSpectate(data)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	spectating = data
	camera.CameraSubject = data.Humanoid
end

localPlayer.CharacterAdded:Connect(function()
	spectating = nil
end)

local tracked = {}
local inspected = nil

local function untrack(model)
	local data = tracked[model]
	if not data then
		return
	end
	tracked[model] = nil
	for _, conn in data.Conns do
		conn:Disconnect()
	end
	if data.Highlight then
		data.Highlight:Destroy()
	end
	if data.Tag then
		data.Tag:Destroy()
	end
	if spectating == data then
		stopSpectate()
	end
	requestUpdate()
end

local function track(humanoid)
	local model = humanoid.Parent
	if not model or not model:IsA("Model") or tracked[model] then
		return
	end

	local data = {
		Model = model,
		Humanoid = humanoid,
		Conns = {},
		Pinned = false,
		InAlert = false,
		PingUntil = nil,
	}
	tracked[model] = data

	table.insert(data.Conns, humanoid.AncestryChanged:Connect(function()
		if humanoid.Parent ~= model then
			untrack(model)
		end
	end))
	table.insert(data.Conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end))

	requestUpdate()
end

local function fullScan()
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("Humanoid") then
			track(inst)
		end
	end
	local count = 0
	for model in tracked do
		if model ~= localPlayer.Character then
			count += 1
		end
	end
	return count
end

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Humanoid") then
		track(inst)
	end
end)

local function buildTag(data, root)
	local tag = create("BillboardGui", {
		Name = "ThermalTag",
		Adornee = root,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(240, 34),
		StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0),
		Enabled = false,
	})

	local plate = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Housing,
		BackgroundTransparency = 0.12,
		Parent = tag,
	})
	corner(plate, R.sm)
	data.PlateStroke = stroke(plate, C.Line, 1, 0.3)
	pad(plate, 7, 8, 0, 0)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = plate,
	})

	data.HeatTick = create("Frame", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(3, 12),
		BackgroundColor3 = C.Accent,
		Parent = plate,
	})
	corner(data.HeatTick, 1)

	data.NameLabel = text({
		LayoutOrder = 2,
		FontFace = F.Medium,
		TextSize = T.small + 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = plate,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(150, math.huge), Parent = data.NameLabel })

	data.InfoLabel = text({
		LayoutOrder = 3,
		TextSize = T.small,
		TextColor3 = C.Muted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = plate,
	})

	data.Plate = plate

	data.HpBack = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(44, 3),
		BackgroundColor3 = C.Shadow,
		BackgroundTransparency = 0.3,
		Parent = tag,
	})
	corner(data.HpBack, 2)

	data.HpFill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Text,
		Parent = data.HpBack,
	})
	corner(data.HpFill, 2)

	data.Tag = tag
	tag.Parent = root
end

local function ensureVisuals(data, root)
	if not data.Highlight or data.Highlight.Parent ~= data.Model then
		if data.Highlight then
			data.Highlight:Destroy()
		end
		data.Highlight = create("Highlight", {
			Name = "ThermalHighlight",
			Adornee = data.Model,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			FillTransparency = 1 - state.Fill,
			OutlineTransparency = 0,
			Enabled = false,
			Parent = data.Model,
		})
	end
	if not data.Tag or data.Tag.Parent ~= root then
		if data.Tag then
			data.Tag:Destroy()
		end
		buildTag(data, root)
	end
end

local function ping(data)
	if tracked[data.Model] ~= data then
		return
	end
	data.PingUntil = os.clock() + 1.6
	if data.Highlight then
		data.Highlight.FillTransparency = 0.05
		tween(data.Highlight, 1.6, { FillTransparency = 1 - state.Fill }, Enum.EasingStyle.Quad)
	end
	requestUpdate()
end

local playerGui = localPlayer:WaitForChild("PlayerGui")
for _, guiName in { "ThermalPanel", "ThermalOverlay" } do
	local old = playerGui:FindFirstChild(guiName)
	if old then
		old:Destroy()
	end
end

local overlayGui = create("ScreenGui", {
	Name = "ThermalOverlay",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 40,
	Parent = playerGui,
})

local panelGui = create("ScreenGui", {
	Name = "ThermalPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = playerGui,
})

local soundBank = {}
do
	local folder = create("Folder", { Name = "ThermalSounds", Parent = panelGui })
	local list = {}
	for name, def in SOUNDS do
		if def.Id ~= "" then
			local sound = create("Sound", { Name = name, SoundId = def.Id, Volume = def.Volume, Parent = folder })
			soundBank[name] = sound
			table.insert(list, sound)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

playSound = function(name)
	if not state.Sounds then
		return
	end
	local sound = soundBank[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local toastStack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, if TOUCH then 12 else 72),
	Size = UDim2.fromOffset(320, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = overlayGui,
})
create("UIListLayout", {
	Padding = UDim.new(0, S.sm - 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Parent = toastStack,
})

local toasts = {}
local toastOrder = 0

toast = function(message, color)
	toastOrder += 1
	local card = create("Frame", {
		LayoutOrder = toastOrder,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = C.Housing,
		BackgroundTransparency = 1,
		Parent = toastStack,
	})
	corner(card, R.md)
	local cardStroke = stroke(card, C.Line, 1, 1)
	local bar = create("Frame", {
		Position = UDim2.fromOffset(S.sm, 9),
		Size = UDim2.new(0, 3, 1, -18),
		BackgroundColor3 = color or C.Accent,
		BackgroundTransparency = 1,
		Parent = card,
	})
	corner(bar, 2)
	local timer = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, R.md, 1, 0),
		Size = UDim2.new(1, -R.md * 2, 0, 1),
		BackgroundColor3 = color or C.Accent,
		BackgroundTransparency = 0.5,
		Parent = card,
	})
	tween(timer, 3.2, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear)
	local label = text({
		Text = message,
		FontFace = F.Medium,
		TextSize = T.body,
		TextTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Parent = card,
	})

	table.insert(toasts, card)
	while #toasts > CONFIG.ToastLimit do
		table.remove(toasts, 1):Destroy()
	end

	tween(card, M.base, { BackgroundTransparency = 0.04 })
	tween(cardStroke, M.base, { Transparency = 0 })
	tween(bar, M.base, { BackgroundTransparency = 0 })
	tween(label, M.base, { TextTransparency = 0 })

	task.delay(3.2, function()
		if card.Parent == nil then
			return
		end
		tween(cardStroke, M.panel, { Transparency = 1 })
		tween(bar, M.panel, { BackgroundTransparency = 1 })
		timer.Visible = false
		tween(label, M.panel, { TextTransparency = 1 })
		tween(card, M.panel, { BackgroundTransparency = 1 })
		task.wait(M.panel)
		local index = table.find(toasts, card)
		if index then
			table.remove(toasts, index)
		end
		card:Destroy()
	end)
end

local tracerLayer = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = overlayGui })
local arrowLayer = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = overlayGui })
local tracers, arrows = {}, {}

local function getTracer(index)
	local line = tracers[index]
	if not line then
		line = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.35,
			Visible = false,
			Parent = tracerLayer,
		})
		tracers[index] = line
	end
	return line
end

local function getArrow(index)
	local arrow = arrows[index]
	if arrow then
		return arrow
	end
	local holder = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = arrowLayer,
	})
	local shaft = create("Frame", {
		Position = UDim2.fromOffset(1, 8),
		Size = UDim2.fromOffset(10, 2),
		BackgroundColor3 = C.Text,
		Parent = holder,
	})
	local tip = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		BackgroundColor3 = C.Text,
		Parent = holder,
	})
	local label = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(48, 14),
		FontFace = F.Bold,
		TextSize = T.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = arrowLayer,
	})
	textStroke(label)
	arrow = { Holder = holder, Shaft = shaft, Tip = tip, Label = label }
	arrows[index] = arrow
	return arrow
end

local W = if TOUCH then 300 else 360
local SCOPE_D = if TOUCH then 176 else 220
local BEZEL_TOP = if TOUCH then 6 else S.sm
local HEADER_H = if TOUCH then 44 else 46
local SCOPE_H = BEZEL_TOP + SCOPE_D + 24 + (if TOUCH then 24 else 26)
local READOUT_H, PAGE_H, FOOTER_H = 46, 252, 30
local TABS_H = if TOUCH then 44 else 38
local FULL_H = HEADER_H + SCOPE_H + READOUT_H + TABS_H + PAGE_H + FOOTER_H
local COLLAPSED_H = HEADER_H + SCOPE_H + READOUT_H
local BLIP_R = SCOPE_D / 2 - 8
local BEZEL_BAND = 12
local BEZEL_D = SCOPE_D + BEZEL_BAND * 2

local root = create("Frame", {
	Name = "Root",
	-- DIGESER AGAR MUNCUL AMAN DI TENGAH-BAWAH LAYAR MOBILE (TIDAK TERTUTUP NOTCH)
	Position = UDim2.new(0.5, -W / 2, 0.55, -COLLAPSED_H / 2),
	Size = UDim2.fromOffset(W, if TOUCH then COLLAPSED_H else FULL_H),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = panelGui,
})
local uiScale = create("UIScale", { Parent = root })

local function makeHousing(container, name)
	for _, layer in { { 2, 1, 0.78 }, { 5, 3, 0.86 }, { 10, 6, 0.91 }, { 18, 10, 0.95 } } do
		local spread, drop, transparency = layer[1], layer[2], layer[3]
		local shadow = create("Frame", {
			Position = UDim2.fromOffset(-spread, -spread + drop),
			Size = UDim2.new(1, spread * 2, 1, spread * 2),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = transparency,
			Parent = container,
		})
		corner(shadow, R.lg + spread)
	end

	local panel = create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Active = true,
		Parent = container,
	})
	corner(panel, R.lg)
	stroke(panel, C.Line, 1)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("#212328"), Color3.fromHex("#1B1D20")),
		Rotation = 90,
		Parent = panel,
	})
	create("Frame", {
		Position = UDim2.fromOffset(R.lg, 0),
		Size = UDim2.new(1, -R.lg * 2, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.93,
		Parent = panel,
	})
	return panel
end

local main = makeHousing(root, "Main")

local SHEET_W = 320
local sheetRoot = create("Frame", {
	Name = "Sheet",
	Size = UDim2.fromOffset(SHEET_W, COLLAPSED_H),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = root,
})
local sheet = makeHousing(sheetRoot, "SheetPanel")

local header = create("Frame", {
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundTransparency = 1,
	Active = true,
	Parent = main,
})

local titleGroup = create("Frame", {
	Position = UDim2.fromOffset(S.lg, 0),
	Size = UDim2.new(1, -100, 1, 0),
	BackgroundTransparency = 1,
	Parent = header,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, S.sm + 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = titleGroup,
})
text({
	LayoutOrder = 1,
	Text = "Thermal",
	FontFace = F.Display,
	TextSize = T.label,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 20),
	Parent = titleGroup,
})
text({
	LayoutOrder = 2,
	Text = "Entity scope",
	TextColor3 = C.Muted,
	TextSize = T.small,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 20),
	Visible = not TOUCH,
	Parent = titleGroup,
})

local function iconButton(symbol, xOffset, hint)
	local button = create("TextButton", {
		Text = symbol,
		FontFace = F.Medium,
		TextSize = 18,
		TextColor3 = C.Muted,
		AutoButtonColor = false,
		BackgroundColor3 = C.Hover,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, xOffset, 0.5, 0),
		Size = UDim2.fromOffset(Z.Icon, Z.Icon),
		Parent = header,
	})
	corner(button, R.md)
	pressable(button)

	local tip = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, xOffset, 0, HEADER_H - 4),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Raised,
		Visible = false,
		ZIndex = 20,
		Parent = main,
	})
	corner(tip, R.sm)
	stroke(tip, C.Line, 1)
	pad(tip, 8, 8, 0, 0)
	local tipLabel = text({
		Text = hint,
		TextSize = T.small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 20,
		Parent = tip,
	})

	local hoverToken = 0
	onHover(button, function()
		hoverToken += 1
		local token = hoverToken
		tween(button, M.fast, { BackgroundTransparency = 0, TextColor3 = C.Text })
		task.delay(0.35, function()
			if token == hoverToken then
				tip.Visible = true
			end
		end)
	end, function()
		hoverToken += 1
		tip.Visible = false
		tween(button, M.fast, { BackgroundTransparency = 1, TextColor3 = C.Muted })
	end)
	button.Activated:Connect(function()
		hoverToken += 1
		tip.Visible = false
	end)
	return button, tipLabel
end

local closeButton = iconButton("×", -10, "Close")
local collapseButton, collapseTip = iconButton("–", -10 - Z.Icon - 4, "Collapse to radar")
collapseButton.Visible = not TOUCH

hairline(main, {
	Position = UDim2.fromOffset(0, HEADER_H - 1),
	Size = UDim2.new(1, 0, 0, 1),
})

local scopeBlock = create("Frame", {
	Position = UDim2.fromOffset(0, HEADER_H),
	Size = UDim2.new(1, 0, 0, SCOPE_H),
	BackgroundTransparency = 1,
	Parent = main,
})

local bezel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, BEZEL_TOP),
	Size = UDim2.fromOffset(BEZEL_D, BEZEL_D),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = scopeBlock,
})
corner(bezel, UDim.new(0.5, 0))
stroke(bezel, C.Line, 1)
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromHex("#30333A"), Color3.fromHex("#1A1C20")),
	Rotation = 90,
	Parent = bezel,
})

local compassCard = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = bezel,
})
for i = 0, 35 do
	if i % 9 ~= 0 then
		local major = i % 3 == 0
		local pivot = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Rotation = i * 10,
			Parent = compassCard,
		})
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, if major then 2 else 3),
			Size = UDim2.fromOffset(1, if major then 7 else 4),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = if major then 0.45 else 0.7,
			Parent = pivot,
		})
	end
end

local compassLetters = {}
for k, letter in { "N", "E", "S", "W" } do
	compassLetters[k] = text({
		Text = letter,
		FontFace = F.Bold,
		TextSize = 10,
		TextColor3 = if letter == "N" then C.Accent else C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		ZIndex = 2,
		Parent = bezel,
	})
end

local LETTER_RADIUS = BEZEL_D / 2 - BEZEL_BAND / 2
local function placeCompass(northAngle)
	compassCard.Rotation = northAngle + 90
	for k, label in compassLetters do
		local a = math.rad(northAngle + (k - 1) * 90)
		label.Position = UDim2.new(0.5, math.cos(a) * LETTER_RADIUS, 0.5, math.sin(a) * LETTER_RADIUS)
	end
end
placeCompass(-90)

local scope = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(SCOPE_D, SCOPE_D),
	BackgroundColor3 = C.Bed,
	Active = true,
	ZIndex = 3,
	Parent = bezel,
})
corner(scope, UDim.new(0.5, 0))
stroke(scope, Color3.fromHex("#0B0A09"), 1)

for _, layer in { { 1, 0.5 }, { 3, 0.72 }, { 6, 0.86 } } do
	local shade = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -layer[1] * 2, 1, -layer[1] * 2),
		BackgroundTransparency = 1,
		Parent = scope,
	})
	corner(shade, UDim.new(0.5, 0))
	stroke(shade, Color3.new(0, 0, 0), 2, layer[2])
end

local function ring(fraction, transparency)
	local frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BLIP_R * 2 * fraction, BLIP_R * 2 * fraction),
		BackgroundTransparency = 1,
		Parent = scope,
	})
	corner(frame, UDim.new(0.5, 0))
	stroke(frame, C.Ring, 1, transparency)
end
ring(1 / 3, 0.25)
ring(2 / 3, 0.25)
ring(1, 0.55)

create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -16, 0, 1),
	BackgroundColor3 = C.Ring,
	BackgroundTransparency = 0.45,
	Parent = scope,
})
create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 1, 1, -16),
	BackgroundColor3 = C.Ring,
	BackgroundTransparency = 0.45,
	Parent = scope,
})

local ringLabels = {}
for index, fraction in { 1 / 3, 2 / 3, 1 } do
	local angle = math.rad(-38)
	local reach = fraction * BLIP_R - 11
	local label = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.cos(angle) * reach, 0.5, math.sin(angle) * reach),
		Size = UDim2.fromOffset(28, 12),
		TextSize = T.caption,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = scope,
	})
	ringLabels[index] = { Label = label, Fraction = fraction }
end

local function refreshRangeLabels()
	for _, item in ringLabels do
		item.Label.Text = formatNumber(state.Range * item.Fraction * item.Fraction)
	end
end
refreshRangeLabels()
bind("Range", refreshRangeLabels)

local sweepAngle = -90
local sweepBoostUntil = 0
local sweepPivots = {}
for i = 1, 6 do
	local pivot = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = scope,
	})
	local arm = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.5, -4, 0, if i == 1 then 2 else 1),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = if i == 1 then 0 else 0.45 + i * 0.09,
		ZIndex = 2,
		Parent = pivot,
	})
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = arm,
	})
	sweepPivots[i] = pivot
end

local blipLayer = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = scope,
})

create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6),
	BackgroundColor3 = C.Text,
	ZIndex = 4,
	Parent = scope,
}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local headingPivot = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1,
	ZIndex = 4,
	Parent = scope,
})
create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(2, 8),
	BackgroundColor3 = C.Text,
	BackgroundTransparency = 0.2,
	ZIndex = 4,
	Parent = headingPivot,
})

local blipTip = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.fromOffset(0, 20),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = C.Housing,
	BackgroundTransparency = 0.04,
	Visible = false,
	ZIndex = 7,
	Parent = scope,
})
corner(blipTip, R.sm)
stroke(blipTip, C.Line, 1)
pad(blipTip, 6, 6, 0, 0)
local blipTipLabel = text({
	FontFace = F.Medium,
	TextSize = T.small,
	RichText = true,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	ZIndex = 7,
	Parent = blipTip,
})

local blips = {}
local hoveredBlip = nil
local function getBlip(index)
	local blip = blips[index]
	if blip then
		return blip
	end
	local holder = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Z.BlipHit, Z.BlipHit),
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ZIndex = 5,
		Visible = false,
		Parent = blipLayer,
	})
	local dot = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C.Text,
		ZIndex = 5,
		Parent = holder,
	})
	local shape = corner(dot, UDim.new(0.5, 0))
	local ringStroke = create("UIStroke", {
		Color = C.Text,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
		Parent = dot,
	})
	blip = { Holder = holder, Frame = dot, Shape = shape, Ring = ringStroke, Entry = nil }
	holder.MouseEnter:Connect(function()
		hoveredBlip = blip
	end)
	holder.MouseLeave:Connect(function()
		if hoveredBlip == blip then
			hoveredBlip = nil
		end
	end)
	holder.Activated:Connect(function()
		if blip.Entry then
			selectTab(1, true)
			openInspector(blip.Entry.Data)
		end
	end)
	blips[index] = blip
	return blip
end

local zoomLabel = text({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(120, 14),
	FontFace = F.Medium,
	TextSize = T.small,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextTransparency = 1,
	ZIndex = 6,
	Parent = scope,
})
local zoomToken = 0
local function flashZoom()
	zoomToken += 1
	local token = zoomToken
	zoomLabel.Text = formatNumber(state.Range) .. " studs"
	zoomLabel.TextTransparency = 0
	task.delay(0.9, function()
		if token == zoomToken then
			tween(zoomLabel, M.panel, { TextTransparency = 1 })
		end
	end)
end
scope.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local factor = if input.Position.Z > 0 then 0.85 else 1 / 0.85
		local value = math.clamp(math.floor(state.Range * factor / 5 + 0.5) * 5, CONFIG.MinRange, CONFIG.MaxRange)
		if value ~= state.Range then
			setState("Range", value)
		end
		flashZoom()
	end
end)

local glassCover = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Bed,
	BackgroundTransparency = 1,
	ZIndex = 8,
	Parent = scope,
})
corner(glassCover, UDim.new(0.5, 0))
local function powerOn()
	sweepBoostUntil = os.clock() + 0.6
	if motionReduced then
		return
	end
	glassCover.BackgroundTransparency = 0
	tween(glassCover, 0.55, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

local function setSwatch(frame, shape, isPlayer, color)
	if isPlayer then
		shape.CornerRadius = UDim.new(0.5, 0)
		frame.Rotation = 0
	else
		shape.CornerRadius = UDim.new(0, 1)
		frame.Rotation = 45
	end
	frame.BackgroundColor3 = color
end

local legendY = BEZEL_TOP + BEZEL_D + 6
local function legendItem(x, isPlayer)
	local swatch = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + 4, legendY + 7),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C.Text,
		Parent = scopeBlock,
	})
	local shape = corner(swatch, UDim.new(0.5, 0))
	setSwatch(swatch, shape, isPlayer, C.Text)
	return text({
		Position = UDim2.fromOffset(x + 14, legendY),
		Size = UDim2.fromOffset(80, 14),
		TextSize = T.small,
		TextColor3 = C.Muted,
		Parent = scopeBlock,
	})
end
local playerLegend = legendItem(S.lg, true)
local npcLegend = legendItem(S.lg + 82, false)

local rampLegend = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -S.lg, 0, legendY),
	Size = UDim2.fromOffset(110, 14),
	BackgroundTransparency = 1,
	Parent = scopeBlock,
})
text({ Text = "Far", TextSize = T.small, TextColor3 = C.Muted, Size = UDim2.fromOffset(24, 14), Parent = rampLegend })
local rampBar = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 26, 0.5, 0),
	Size = UDim2.fromOffset(48, 4),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = rampLegend,
})
corner(rampBar, 2)
create("UIGradient", { Color = rampSequence(), Parent = rampBar })
text({
	Text = "Near",
	TextSize = T.small,
	TextColor3 = C.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(32, 14),
	Parent = rampLegend,
})
bind("ColorMode", function(mode)
	rampLegend.Visible = mode == "Thermal"
end)

local readout = create("Frame", {
	Position = UDim2.fromOffset(0, HEADER_H + SCOPE_H),
	Size = UDim2.new(1, 0, 0, READOUT_H),
	BackgroundTransparency = 1,
	Parent = main,
})
local readGroup = create("Frame", {
	Position = UDim2.fromOffset(S.lg, 0),
	Size = UDim2.new(1, -120, 1, 0),
	BackgroundTransparency = 1,
	Parent = readout,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = readGroup,
})
local countLabel = text({
	LayoutOrder = 1,
	Text = "0",
	FontFace = F.Bold,
	TextSize = T.hero,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 26),
	Parent = readGroup,
})
local countCaption = text({
	LayoutOrder = 2,
	Text = "in range",
	TextColor3 = C.Muted,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 20),
	Parent = readGroup,
})

local rescanButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -S.lg, 0.5, 0),
	Size = UDim2.fromOffset(if TOUCH then 88 else 80, if TOUCH then 40 else 30),
	Text = "Rescan",
	FontFace = F.Medium,
	TextSize = T.body,
	TextColor3 = C.Text,
	AutoButtonColor = false,
	BackgroundColor3 = C.Raised,
	Parent = readout,
})
corner(rescanButton, R.md)
pressable(rescanButton)
local rescanStroke = stroke(rescanButton, C.Line, 1)
onHover(rescanButton, function()
	tween(rescanStroke, M.fast, { Color = C.Accent })
end, function()
	tween(rescanStroke, M.fast, { Color = C.Line })
end)

local tabsY = if TOUCH then 0 else HEADER_H + SCOPE_H + READOUT_H
local tabsBar = create("Frame", {
	Position = UDim2.fromOffset(0, tabsY),
	Size = UDim2.new(1, 0, 0, TABS_H),
	BackgroundTransparency = 1,
	Parent = if TOUCH then sheet else main,
})
hairline(tabsBar, {
	Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
})
local underline = create("Frame", {
	Position = UDim2.new(0, S.lg, 1, -2),
	Size = UDim2.fromOffset(48, 2),
	BackgroundColor3 = C.Accent,
	ZIndex = 2,
	Parent = tabsBar,
})

local pagesHolder = create("Frame", {
	Position = UDim2.fromOffset(0, tabsY + TABS_H),
	Size = if TOUCH then UDim2.new(1, 0, 1, -TABS_H) else UDim2.new(1, 0, 0, PAGE_H),
	BackgroundTransparency = 1,
	Parent = if TOUCH then sheet else main,
})

local sheetClose = nil
if TOUCH then
	sheetClose = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, -1),
		Size = UDim2.fromOffset(Z.Icon, Z.Icon),
		Text = "×",
		FontFace = F.Medium,
		TextSize = 18,
		TextColor3 = C.Muted,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ZIndex = 2,
		Parent = tabsBar,
	})
	corner(sheetClose, R.md)
	pressable(sheetClose)
end
pad(pagesHolder, S.lg, S.lg, S.md, S.sm)

local TAB_NAMES = { "Entities", "Visuals", "Settings" }
local tabButtons, pages = {}, {}
local activeTab = 1

local function placeUnderline(animate)
	local button = tabButtons[activeTab]
	local width = math.max(button.TextBounds.X, 24)
	local goal = {
		Position = UDim2.new(0, button.Position.X.Offset, 1, -2),
		Size = UDim2.fromOffset(width, 2),
	}
	if animate then
		tween(underline, M.base, goal)
	else
		underline.Position = goal.Position
		underline.Size = goal.Size
	end
end

selectTab = function(index, animate)
	activeTab = index
	for i, button in tabButtons do
		button.TextColor3 = if i == index then C.Text else C.Muted
		pages[i].Visible = i == index
	end
	placeUnderline(animate)
end

for i, name in TAB_NAMES do
	local button = create("TextButton", {
		Position = UDim2.new(0, S.lg + (i - 1) * 86, 0, 0),
		Size = UDim2.new(0, 78, 1, -2),
		Text = name,
		FontFace = F.Medium,
		TextSize = T.body,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Parent = tabsBar,
	})
	button.SelectionImageObject = selectionRing
	button.Activated:Connect(function()
		if activeTab ~= i then
			playSound("Click")
			selectTab(i, true)
		end
	end)
	button:GetPropertyChangedSignal("TextBounds"):Connect(function()
		if activeTab == i then
			placeUnderline(false)
		end
	end)
	tabButtons[i] = button

	pages[i] = create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = pagesHolder,
	})
end

local footer = create("Frame", {
	Position = UDim2.fromOffset(0, FULL_H - FOOTER_H),
	Size = UDim2.new(1, 0, 0, FOOTER_H),
	BackgroundTransparency = 1,
	Visible = not TOUCH,
	Parent = main,
})
hairline(footer, { Size = UDim2.new(1, 0, 0, 1) })
text({
	Text = keyName(CONFIG.PanelKey) .. " hides the panel. " .. keyName(CONFIG.EspKey) .. " switches ESP.",
	TextSize = T.caption,
	TextColor3 = C.Muted,
	Position = UDim2.fromOffset(S.lg, 1),
	Size = UDim2.new(1, -S.lg * 2, 1, -1),
	Parent = footer,
})

local reopenChip = create("TextButton", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, S.lg, 1, -S.lg),
	Size = UDim2.fromOffset(124, 34),
	Text = "Open Thermal",
	FontFace = F.Medium,
	TextSize = T.body,
	TextColor3 = C.Text,
	BackgroundColor3 = C.Housing,
	AutoButtonColor = false,
	Visible = false,
	Parent = panelGui,
})
corner(reopenChip, R.md)
pressable(reopenChip)
stroke(reopenChip, C.Line, 1)

local MINI_D = 124
local miniHud, miniSlot, miniCount, miniTap, espQuick, scrim = nil, nil, nil, nil, nil, nil
local bezelScale = create("UIScale", { Parent = bezel })

if TOUCH then
	scrim = create("TextButton", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 1,
		Parent = panelGui,
	})

	miniHud = create("Frame", {
		Name = "MiniRadar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(MINI_D, MINI_D + 32),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
		Parent = panelGui,
	})
	miniSlot = create("Frame", {
		Size = UDim2.fromOffset(MINI_D, MINI_D),
		BackgroundTransparency = 1,
		Parent = miniHud,
	})
	local chip = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, MINI_D + 6),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Housing,
		BackgroundTransparency = 0.12,
		Parent = miniHud,
	})
	corner(chip, R.sm)
	stroke(chip, C.Line, 1, 0.3)
	pad(chip, 8, 8, 0, 0)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chip,
	})
	miniCount = text({
		LayoutOrder = 1,
		Text = "0",
		FontFace = F.Medium,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = chip,
	})
	text({
		LayoutOrder = 2,
		Text = "in range",
		TextSize = T.small,
		TextColor3 = C.Muted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = chip,
	})
	miniTap = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ZIndex = 10,
		Parent = miniHud,
	})
	miniTap.SelectionImageObject = selectionRing

	espQuick = create("TextButton", {
		Name = "EspQuick",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6 + MINI_D + 32 + 8),
		Size = UDim2.fromOffset(96, 40),
		Text = "",
		BackgroundColor3 = C.Housing,
		BackgroundTransparency = 0.06,
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 1,
		Parent = panelGui,
	})
	corner(espQuick, R.md)
	stroke(espQuick, C.Line, 1)
	pressable(espQuick)
	text({
		Text = "ESP",
		FontFace = F.Medium,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0, 36, 1, 0),
		Parent = espQuick,
	})
	local quickTrack = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(36, 20),
		BackgroundColor3 = C.Line,
		Parent = espQuick,
	})
	corner(quickTrack, UDim.new(0.5, 0))
	local quickKnob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.Muted,
		Parent = quickTrack,
	})
	corner(quickKnob, UDim.new(0.5, 0))
	local function renderQuick(animate)
		local on = state.Esp
		local trackGoal = { BackgroundColor3 = if on then C.Accent else C.Line }
		local knobGoal = {
			Position = if on then UDim2.new(1, -18, 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
			BackgroundColor3 = if on then C.AccentInk else C.Muted,
		}
		if animate then
			tween(quickTrack, M.fast, trackGoal)
			tween(quickKnob, M.base, knobGoal)
		else
			quickTrack.BackgroundColor3 = trackGoal.BackgroundColor3
			quickKnob.Position = knobGoal.Position
			quickKnob.BackgroundColor3 = knobGoal.BackgroundColor3
		end
	end
	bind("Esp", function()
		renderQuick(true)
	end)
	renderQuick(false)
	espQuick.Activated:Connect(function()
		playSound("Toggle")
		setState("Esp", not state.Esp)
	end)
end

local function placeBezel(inMini)
	if inMini and miniSlot then
		bezel.Parent = miniSlot
		bezel.Position = UDim2.fromScale(0.5, 0)
		bezelScale.Scale = MINI_D / BEZEL_D
	else
		bezel.Parent = scopeBlock
		bezel.Position = UDim2.new(0.5, 0, 0, BEZEL_TOP)
		bezelScale.Scale = 1
	end
end

local activeSlider = nil

local function scrollPage(page)
	local scroller = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = C.Line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = page,
	})
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })
	pad(scroller, 0, 6, 0, S.sm)
	return scroller
end

local function rowDivider(row)
	hairline(row, { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1) })
end

local function sectionLabel(parent, order, label)
	local frame = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	text({
		Text = label,
		FontFace = F.Medium,
		TextSize = T.small,
		TextColor3 = C.Muted,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Size = UDim2.new(1, 0, 1, -4),
		Parent = frame,
	})
end

local function toggleRow(parent, order, label, key, hint)
	local height = if hint then Z.RowHint else Z.Row
	local labelY = if hint then math.floor((height - 38) / 2) else 0
	local row = create("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Parent = parent,
	})
	text({
		Text = label,
		FontFace = F.Medium,
		Position = UDim2.fromOffset(0, labelY),
		Size = UDim2.new(1, -56, 0, if hint then 20 else height),
		Parent = row,
	})
	if hint then
		text({
			Text = hint,
			TextSize = T.small,
			TextColor3 = C.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(0, labelY + 20),
			Size = UDim2.new(1, -52, 0, 16),
			Parent = row,
		})
	end

	local track = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(if TOUCH then 36 else 30, Z.Knob + 4),
		BackgroundColor3 = C.Line,
		Parent = row,
	})
	corner(track, UDim.new(0.5, 0))
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(Z.Knob, Z.Knob),
		BackgroundColor3 = C.Muted,
		Parent = track,
	})
	corner(knob, UDim.new(0.5, 0))
	rowDivider(row)

	local function render(animate)
		local on = state[key] == true
		local trackGoal = { BackgroundColor3 = if on then C.Accent else C.Line }
		local knobGoal = {
			Position = if on then UDim2.new(1, -(Z.Knob + 2), 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
			BackgroundColor3 = if on then C.AccentInk else C.Muted,
		}
		if animate then
			tween(track, M.fast, trackGoal)
			tween(knob, M.base, knobGoal)
		else
			track.BackgroundColor3 = trackGoal.BackgroundColor3
			knob.Position = knobGoal.Position
			knob.BackgroundColor3 = knobGoal.BackgroundColor3
		end
	end

	bind(key, function()
		render(true)
	end)
	row.SelectionImageObject = selectionRing
	row.Activated:Connect(function()
		playSound("Toggle")
		setState(key, not state[key])
	end)
	render(false)
end

local function segmentedRow(parent, order, label, key, options)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, Z.Segment + 16),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	text({ Text = label, FontFace = F.Medium, Size = UDim2.new(1, -(Z.SegmentW * #options + 8), 1, 0), Parent = row })
	rowDivider(row)

	local count = #options
	local control = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(Z.SegmentW * count, Z.Segment),
		BackgroundColor3 = C.Inset,
		Parent = row,
	})
	corner(control, R.md)
	stroke(control, C.LineSoft, 1)

	local indicator = create("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1 / count, -4, 1, -4),
		BackgroundColor3 = C.Raised,
		Parent = control,
	})
	corner(indicator, R.sm)
	stroke(indicator, C.Line, 1)

	local buttons = {}
	local function render(animate)
		for i, option in options do
			local selected = state[key] == option.Value
			buttons[i].TextColor3 = if selected then C.Text else C.Muted
			if selected then
				local goal = { Position = UDim2.new((i - 1) / count, 2, 0, 2) }
				if animate then
					tween(indicator, M.base, goal)
				else
					indicator.Position = goal.Position
				end
			end
		end
	end

	for i, option in options do
		local button = create("TextButton", {
			Position = UDim2.fromScale((i - 1) / count, 0),
			Size = UDim2.fromScale(1 / count, 1),
			Text = option.Label,
			FontFace = F.Medium,
			TextSize = T.small,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 2,
			Parent = control,
		})
		button.SelectionImageObject = selectionRing
		button.Activated:Connect(function()
			if state[key] ~= option.Value then
				playSound("Click")
				setState(key, option.Value)
			end
		end)
		buttons[i] = button
	end

	bind(key, function()
		render(true)
	end)
	render(false)
end

local function sliderRow(parent, order, label, opts)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, Z.SliderRow),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	text({ Text = label, FontFace = F.Medium, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, -100, 0, 18), Parent = row })
	local valueLabel = text({
		FontFace = F.Medium,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.fromOffset(100, 18),
		Parent = row,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 6, 0, Z.SliderRow - 18),
		Size = UDim2.new(1, -12, 0, 4),
		BackgroundColor3 = C.Line,
		Parent = row,
	})
	corner(track, 2)
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track })
	corner(fill, 2)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(Z.Knob, Z.Knob),
		BackgroundColor3 = C.Text,
		ZIndex = 2,
		Parent = track,
	})
	corner(knob, UDim.new(0.5, 0))
	local hitbox = create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.new(1, 12, 0, Z.SliderHit),
		Text = "",
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = track,
	})
	rowDivider(row)

	local curve = opts.Curve or 1
	local slider = {}

	function slider.Render()
		local alpha = math.clamp((state[opts.Key] - opts.Min) / (opts.Max - opts.Min), 0, 1) ^ (1 / curve)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = opts.Format(state[opts.Key])
	end

	function slider.SetFromX(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local value = opts.Min + (opts.Max - opts.Min) * alpha ^ curve
		value = math.clamp(math.floor(value / opts.Step + 0.5) * opts.Step, opts.Min, opts.Max)
		if value ~= state[opts.Key] then
			setState(opts.Key, value)
		end
	end

	hitbox.InputBegan:Connect(function(input)
		if isPointerDown(input) then
			activeSlider = slider
			slider.SetFromX(input.Position.X)
		end
	end)

	bind(opts.Key, slider.Render)
	slider.Render()
end

local function infoRow(parent, order, label, value)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, if TOUCH then 42 else 34),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	text({ Text = label, Size = UDim2.new(0.55, 0, 1, 0), Parent = row })
	local valueLabel = text({
		Text = value,
		FontFace = F.Medium,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Parent = row,
	})
	rowDivider(row)
	return valueLabel
end

local function actionButton(parent, order, label, onActivate)
	local button = create("TextButton", {
		LayoutOrder = order,
		Text = label,
		FontFace = F.Medium,
		TextSize = T.body,
		TextColor3 = C.Text,
		BackgroundColor3 = C.Raised,
		AutoButtonColor = false,
		Parent = parent,
	})
	corner(button, R.md)
	pressable(button)
	local buttonStroke = stroke(button, C.LineSoft, 1)
	onHover(button, function()
		tween(button, M.fast, { BackgroundColor3 = C.Hover })
	end, function()
		tween(button, M.fast, { BackgroundColor3 = C.Raised })
	end)
	button.Activated:Connect(onActivate)
	return button, buttonStroke
end

local entitiesPage = pages[1]
local listView = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = entitiesPage })

local searchWell = create("Frame", {
	Size = UDim2.new(1, 0, 0, Z.Search),
	BackgroundColor3 = C.Inset,
	Parent = listView,
})
corner(searchWell, R.md)
local searchStroke = stroke(searchWell, C.LineSoft, 1)

local searchBox = create("TextBox", {
	Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -40, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	PlaceholderText = "Search by name",
	PlaceholderColor3 = C.Muted,
	TextColor3 = C.Text,
	FontFace = F.Body,
	TextSize = T.body,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Parent = searchWell,
})
local clearSearch = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -4, 0.5, 0),
	Size = UDim2.fromOffset(24, 24),
	Text = "×",
	FontFace = F.Medium,
	TextSize = 16,
	TextColor3 = C.Muted,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Visible = false,
	Parent = searchWell,
})

searchBox.Focused:Connect(function()
	tween(searchStroke, M.fast, { Color = C.Accent })
end)
searchBox.FocusLost:Connect(function()
	tween(searchStroke, M.fast, { Color = C.LineSoft })
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local trimmed = string.match(string.lower(searchBox.Text), "^%s*(.-)%s*$") or ""
	clearSearch.Visible = searchBox.Text ~= ""
	setState("Filter", trimmed)
end)
clearSearch.Activated:Connect(function()
	searchBox.Text = ""
end)

local headerRow = create("Frame", {
	Position = UDim2.fromOffset(0, Z.Search + 8),
	Size = UDim2.new(1, -4, 0, 22),
	BackgroundTransparency = 1,
	Parent = listView,
})
local sortHeaders = {}
local function sortHeader(sortKey, label, props)
	props.Text = label
	props.FontFace = F.Medium
	props.TextSize = T.small
	props.TextColor3 = C.Muted
	props.BackgroundTransparency = 1
	props.AutoButtonColor = false
	props.Parent = headerRow
	local button = create("TextButton", props)
	button.Activated:Connect(function()
		if state.Sort ~= sortKey then
			playSound("Click")
			setState("Sort", sortKey)
		end
	end)
	sortHeaders[sortKey] = button
end
sortHeader("Name", "Name", {
	Position = UDim2.fromOffset(22, 0),
	Size = UDim2.new(0, 60, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})
sortHeader("Health", "Health", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -64, 0, 0),
	Size = UDim2.new(0, 62, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})
sortHeader("Distance", "Studs", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 0),
	Size = UDim2.new(0, 48, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local function renderSortHeaders()
	for key, button in sortHeaders do
		button.TextColor3 = if key == state.Sort then C.Accent else C.Muted
	end
end
renderSortHeaders()
bind("Sort", renderSortHeaders)

local listFrame = create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, Z.Search + 32),
	Size = UDim2.new(1, 0, 1, -(Z.Search + 32)),
	BackgroundTransparency = 1,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = C.Line,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = listView,
})
create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listFrame })

local emptyLabel = text({
	LayoutOrder = 0,
	TextColor3 = C.Muted,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Size = UDim2.new(1, -8, 0, 44),
	Position = UDim2.fromOffset(4, 0),
	Parent = listFrame,
})

local rows = {}
local function getRow(index)
	local row = rows[index]
	if row then
		return row
	end

	local button = create("TextButton", {
		LayoutOrder = index,
		Size = UDim2.new(1, -4, 0, Z.ListRow),
		Text = "",
		BackgroundColor3 = C.Raised,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Parent = listFrame,
	})
	corner(button, R.md)

	local pin = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(2, 14),
		BackgroundColor3 = C.Accent,
		Visible = false,
		Parent = button,
	})
	local swatch = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C.Text,
		Parent = button,
	})
	local swatchShape = corner(swatch, UDim.new(0.5, 0))
	local nameLabel = text({
		FontFace = F.Medium,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -150, 1, 0),
		Parent = button,
	})
	local health = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -64, 0.5, 0),
		Size = UDim2.fromOffset(62, 16),
		BackgroundTransparency = 1,
		Parent = button,
	})
	local hpBack = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(28, 3),
		BackgroundColor3 = C.Line,
		Parent = health,
	})
	corner(hpBack, 2)
	local hpFill = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Text, Parent = hpBack })
	corner(hpFill, 2)
	local hpText = text({
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.fromOffset(28, 16),
		TextSize = T.small,
		TextColor3 = C.Muted,
		Parent = health,
	})
	local distLabel = text({
		FontFace = F.Medium,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(48, 16),
		Parent = button,
	})

	row = {
		Button = button,
		Pin = pin,
		Swatch = swatch,
		SwatchShape = swatchShape,
		Name = nameLabel,
		HpFill = hpFill,
		HpText = hpText,
		Dist = distLabel,
		Target = nil,
	}

	onHover(button, function()
		tween(button, M.fast, { BackgroundTransparency = 0 })
	end, function()
		tween(button, M.fast, { BackgroundTransparency = 1 })
	end)
	button.SelectionImageObject = selectionRing
	button.Activated:Connect(function()
		if row.Target then
			openInspector(row.Target)
		end
	end)

	rows[index] = row
	return row
end

local inspectorView = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = entitiesPage,
})

local backButton = create("TextButton", {
	Size = UDim2.fromOffset(if TOUCH then 60 else 50, if TOUCH then 36 else 28),
	Text = "Back",
	FontFace = F.Medium,
	TextSize = T.body,
	TextColor3 = C.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Parent = inspectorView,
})
onHover(backButton, function()
	backButton.TextColor3 = C.Text
end, function()
	backButton.TextColor3 = C.Muted
end)

local inspectName = text({
	FontFace = F.Bold,
	TextSize = T.label,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(54, 0),
	Size = UDim2.new(1, -164, 0, 28),
	Parent = inspectorView,
})
local inspectKind = text({
	TextSize = T.small,
	TextColor3 = C.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(108, 28),
	Parent = inspectorView,
})

local propsFrame = create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, if TOUCH then 40 else 34),
	Size = UDim2.new(1, 0, 1, -(if TOUCH then 40 else 34) - (Z.Action * 2 + 12)),
	BackgroundTransparency = 1,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = C.Line,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = inspectorView,
})
create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = propsFrame })

local props = {}
local function propRow(order, key, label, tall)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, if tall then 40 else 24),
		BackgroundTransparency = 1,
		Parent = propsFrame,
	})
	text({ Text = label, TextSize = T.small, TextColor3 = C.Muted, Size = UDim2.new(0, 92, 0, 24), Parent = row })
	props[key] = text({
		FontFace = F.Medium,
		TextSize = T.small + 1,
		TextWrapped = tall == true,
		TextTruncate = if tall then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		TextYAlignment = if tall then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(96, if tall then 5 else 0),
		Size = UDim2.new(1, -96, 1, if tall then -5 else 0),
		Parent = row,
	})
end
propRow(1, "Health", "Health")
propRow(2, "Distance", "Distance")
propRow(3, "WalkSpeed", "Walk speed")
propRow(4, "Jump", "Jump")
propRow(5, "State", "State")
propRow(6, "Rig", "Rig")
propRow(7, "Position", "Position")
propRow(8, "Path", "Path", true)

local actionsGrid = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, Z.Action * 2 + 6),
	BackgroundTransparency = 1,
	Parent = inspectorView,
})
create("UIGridLayout", {
	CellSize = UDim2.new(1 / 3, -6, 0, Z.Action),
	CellPadding = UDim2.fromOffset(9, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = actionsGrid,
})

local pinButton, pinStroke, watchButton, watchStroke

actionButton(actionsGrid, 1, "Ping", function()
	if inspected then
		playSound("Click")
		ping(inspected)
	end
end)

pinButton, pinStroke = actionButton(actionsGrid, 2, "Pin", function()
	if inspected then
		playSound("Click")
		inspected.Pinned = not inspected.Pinned
		refreshInspector()
		requestUpdate()
	end
end)

watchButton, watchStroke = actionButton(actionsGrid, 3, "Watch", function()
	if not inspected then
		return
	end
	playSound("Click")
	if spectating == inspected then
		stopSpectate()
	else
		startSpectate(inspected)
	end
	refreshInspector()
end)

actionButton(actionsGrid, 4, "Go to", function()
	if not inspected then
		return
	end
	local myChar = localPlayer.Character
	local root = getRoot(inspected.Model)
	if myChar and root then
		playSound("Click")
		myChar:PivotTo(root.CFrame * CFrame.new(0, 0, 6))
		toast("Moved next to " .. inspectName.Text)
	else
		toast("Can't move: your character isn't loaded", C.Ember)
	end
end)

actionButton(actionsGrid, 5, "Print path", function()
	if inspected then
		playSound("Click")
		print("[Thermal] " .. inspected.Model:GetFullName())
		toast("Path printed to Output")
	end
end)

local function setActionActive(button, buttonStroke, active)
	button.TextColor3 = if active then C.Accent else C.Text
	buttonStroke.Color = if active then C.Accent else C.LineSoft
end

refreshInspector = function()
	local data = inspected
	if not data then
		return
	end
	if tracked[data.Model] ~= data then
		local name = inspectName.Text
		closeInspector()
		toast(name .. " left the workspace", C.Ember)
		return
	end

	local model = data.Model
	local humanoid = data.Humanoid
	local root = getRoot(model)
	local plr = Players:GetPlayerFromCharacter(model)

	inspectName.Text = if plr then plr.DisplayName else model.Name
	inspectKind.Text = if plr then "Player @" .. plr.Name else "NPC"

	props.Health.Text = formatNumber(humanoid.Health) .. " of " .. formatNumber(humanoid.MaxHealth)
	props.WalkSpeed.Text = formatNumber(humanoid.WalkSpeed)
	props.Jump.Text = if humanoid.UseJumpPower
		then formatNumber(humanoid.JumpPower) .. " power"
		else string.format("%.1f height", humanoid.JumpHeight)
	props.State.Text = humanoid:GetState().Name
	props.Rig.Text = humanoid.RigType.Name
	props.Path.Text = model:GetFullName()

	if root then
		local p = root.Position
		local myChar = localPlayer.Character
		local myRoot = if myChar then getRoot(myChar) else nil
		local camera = workspace.CurrentCamera
		local origin = if myRoot then myRoot.Position elseif camera then camera.CFrame.Position else Vector3.zero
		props.Position.Text = string.format("%.0f, %.0f, %.0f", p.X, p.Y, p.Z)
		props.Distance.Text = formatNumber((p - origin).Magnitude) .. " studs"
	else
		props.Position.Text = "No parts yet"
		props.Distance.Text = "Unknown"
	end

	pinButton.Text = if data.Pinned then "Unpin" else "Pin"
	setActionActive(pinButton, pinStroke, data.Pinned)
	watchButton.Text = if spectating == data then "Stop watching" else "Watch"
	setActionActive(watchButton, watchStroke, spectating == data)
end

openInspector = function(data)
	inspected = data
	playSound("Click")
	listView.Visible = false
	inspectorView.Visible = true
	refreshInspector()
end

closeInspector = function()
	inspected = nil
	inspectorView.Visible = false
	listView.Visible = true
end

backButton.Activated:Connect(function()
	playSound("Click")
	closeInspector()
end)

do
	local list = scrollPage(pages[2])
	local o = 0
	local function n()
		o += 1
		return o
	end

	sectionLabel(list, n(), "Draw")
	toggleRow(list, n(), "ESP", "Esp", if TOUCH then "The ESP button switches this anywhere" else keyName(CONFIG.EspKey) .. " switches this from anywhere")
	toggleRow(list, n(), "Highlight bodies", "Highlights")
	toggleRow(list, n(), "Name tags", "Names")
	toggleRow(list, n(), "Distance in tag", "Distance")
	toggleRow(list, n(), "Health bars", "Health")
	toggleRow(list, n(), "Tracers", "Tracers", "Lines from the bottom of the screen")
	toggleRow(list, n(), "Off-screen arrows", "Arrows", "Points at things you can't see")

	sectionLabel(list, n(), "Show")
	toggleRow(list, n(), "Players", "Players")
	toggleRow(list, n(), "NPCs", "Npcs")
	toggleRow(list, n(), "Hide my team", "HideTeam")
	sliderRow(list, n(), "Range", {
		Key = "Range",
		Min = CONFIG.MinRange,
		Max = CONFIG.MaxRange,
		Step = 5,
		Curve = 2,
		Format = function(v)
			return formatNumber(v) .. " studs"
		end,
	})

	sectionLabel(list, n(), "Color")
	segmentedRow(list, n(), "Color by", "ColorMode", {
		{ Label = "Distance", Value = "Thermal" },
		{ Label = "Type", Value = "Type" },
		{ Label = "Team", Value = "Team" },
	})
	sliderRow(list, n(), "Highlight fill", {
		Key = "Fill",
		Min = 0,
		Max = 0.6,
		Step = 0.05,
		Format = function(v)
			return formatNumber(v * 100) .. "%"
		end,
	})
end

local trackedInfo, scanInfo
do
	local list = scrollPage(pages[3])
	local o = 0
	local function n()
		o += 1
		return o
	end

	sectionLabel(list, n(), "Alerts")
	toggleRow(list, n(), "Proximity alerts", "Alerts", "Notify when something enters the radius")
	sliderRow(list, n(), "Alert radius", {
		Key = "AlertRadius",
		Min = 10,
		Max = 200,
		Step = 5,
		Format = function(v)
			return formatNumber(v) .. " studs"
		end,
	})

	sectionLabel(list, n(), "Panel")
	toggleRow(list, n(), "Sounds", "Sounds")
	toggleRow(list, n(), "Radar sweep", "Sweep", "Off automatically with reduced motion")
	segmentedRow(list, n(), "Radar top", "RadarMode", {
		{ Label = "Camera", Value = "Heading" },
		{ Label = "North", Value = "North" },
	})
	segmentedRow(list, n(), "Refresh", "Rate", {
		{ Label = "Fast", Value = "Fast" },
		{ Label = "Normal", Value = "Normal" },
		{ Label = "Eco", Value = "Eco" },
	})

	if not TOUCH then
		sectionLabel(list, n(), "Keys")
		infoRow(list, n(), "Show or hide panel", keyName(CONFIG.PanelKey))
		infoRow(list, n(), "Switch ESP", keyName(CONFIG.EspKey))
	end

	sectionLabel(list, n(), "Diagnostics")
	trackedInfo = infoRow(list, n(), "Tracked", "0")
	scanInfo = infoRow(list, n(), "Last scan", "0 ms")
end

local alertPrimed = false
bind("Alerts", function(on)
	alertPrimed = false
	if not on then
		for _, data in tracked do
			data.InAlert = false
		end
	end
end)

bind("Fill", function()
	local now = os.clock()
	for _, data in tracked do
		local pinging = data.PingUntil ~= nil and now < data.PingUntil
		if data.Highlight and not pinging then
			data.Highlight.FillTransparency = 1 - state.Fill
		end
	end
end)

local visibleSorted = {}

local function entityColor(entry)
	if state.ColorMode == "Thermal" then
		return ironbow(1 - math.sqrt(math.clamp(entry.Dist / state.Range, 0, 1)))
	end
	if state.ColorMode == "Team" and entry.Player and entry.Player.Team then
		return entry.Player.TeamColor.Color
	end
	return if entry.Player then C.Player else C.Npc
end

local function updateAll()
	local started = os.clock()
	readReducedMotion()

	local camera = workspace.CurrentCamera
	local myChar = localPlayer.Character
	local myRoot = if myChar then getRoot(myChar) else nil
	local origin = if myRoot then myRoot.Position elseif camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	local range = state.Range

	local visible = {}
	local nPlayers, nNpcs = 0, 0
	local newAlerts = {}

	for model, data in tracked do
		if data.Highlight then
			data.Highlight.Enabled = false
		end
		if data.Tag then
			data.Tag.Enabled = false
		end

		if model ~= myChar then
			local root = getRoot(model)
			if root then
				local plr = Players:GetPlayerFromCharacter(model)
				if plr then
					nPlayers += 1
				else
					nNpcs += 1
				end

				local typeOk = if plr then state.Players else state.Npcs
				local teamHidden = plr ~= nil
					and state.HideTeam
					and localPlayer.Team ~= nil
					and plr.Team == localPlayer.Team
				local name = if plr then plr.DisplayName else model.Name
				local filterOk = state.Filter == ""
					or string.find(string.lower(name), state.Filter, 1, true) ~= nil
					or (plr ~= nil and string.find(string.lower(plr.Name), state.Filter, 1, true) ~= nil)
				local eligible = typeOk and not teamHidden and filterOk
				local dist = (root.Position - origin).Magnitude

				if state.Alerts and eligible then
					if dist <= state.AlertRadius then
						if not data.InAlert then
							data.InAlert = true
							if alertPrimed then
								table.insert(newAlerts, { Name = name, Dist = dist })
							end
						end
					elseif dist > state.AlertRadius * 1.15 then
						data.InAlert = false
					end
				end

				if eligible and (dist <= range or data.Pinned) then
					ensureVisuals(data, root)
					local humanoid = data.Humanoid
					local hp, maxHp = humanoid.Health, humanoid.MaxHealth
					local ratio = 1
					if maxHp > 0 and maxHp < math.huge then
						ratio = math.clamp(hp / maxHp, 0, 1)
					end
					if ratio ~= ratio then
						ratio = 0
					end
					table.insert(visible, {
						Data = data,
						Root = root,
						Player = plr,
						Name = name,
						Context = if plr
							then "@" .. plr.Name
							elseif model.Parent and model.Parent ~= workspace then model.Parent.Name
							else nil,
						Dist = dist,
						Hp = hp,
						MaxHp = maxHp,
						Ratio = ratio,
					})
				end
			end
		end
	end

	if state.Alerts then
		alertPrimed = true
	end

	table.sort(visible, function(a, b)
		return a.Dist < b.Dist
	end)
	for _, entry in visible do
		entry.Color = entityColor(entry)
	end

	local highlightsUsed = 0
	local showTag = state.Esp and (state.Names or state.Distance or state.Health)
	for _, entry in visible do
		local data = entry.Data
		local pinging = data.PingUntil ~= nil and now < data.PingUntil
		local highlight = data.Highlight
		if ((state.Esp and state.Highlights) or pinging) and highlightsUsed < CONFIG.MaxHighlights then
			highlightsUsed += 1
			highlight.FillColor = entry.Color
			highlight.OutlineColor = entry.Color
			if not pinging then
				highlight.FillTransparency = 1 - state.Fill
			end
			highlight.Enabled = true
		end

		data.Tag.Enabled = showTag
		if showTag then
			local focused = data.Pinned or data == inspected or pinging
			local fade = if focused then 0 else math.clamp((entry.Dist / range - 0.55) / 0.45, 0, 1) * 0.55
			data.Plate.Visible = state.Names or state.Distance
			data.Plate.BackgroundTransparency = 0.12 + fade * 0.6
			data.PlateStroke.Transparency = 0.3 + fade * 0.6
			data.PlateStroke.Color = if focused then C.Accent else C.Line
			data.HeatTick.BackgroundColor3 = entry.Color
			data.HeatTick.BackgroundTransparency = fade
			data.NameLabel.Visible = state.Names
			data.NameLabel.Text = entry.Name
			data.NameLabel.TextTransparency = fade
			data.InfoLabel.Visible = state.Distance
			data.InfoLabel.Text = formatNumber(entry.Dist)
			data.InfoLabel.TextTransparency = fade
			data.HpBack.Visible = state.Health
			data.HpBack.BackgroundTransparency = 0.3 + fade * 0.5
			data.HpFill.Size = UDim2.fromScale(entry.Ratio, 1)
			data.HpFill.BackgroundColor3 = C.Ember:Lerp(C.Text, entry.Ratio)
			data.HpFill.BackgroundTransparency = fade
		end
	end

	visibleSorted = visible

	countLabel.Text = tostring(#visible)
	if miniCount then
		miniCount.Text = tostring(#visible)
	end
	countCaption.Text = "in range of " .. tostring(nPlayers + nNpcs)
	playerLegend.Text = plural(nPlayers, "player")
	npcLegend.Text = plural(nNpcs, "NPC")
	trackedInfo.Text = plural(nPlayers + nNpcs, "entity", "entities")

	local listOrder = table.clone(visible)
	local sortKey = state.Sort
	table.sort(listOrder, function(a, b)
		local pa, pb = a.Data.Pinned == true, b.Data.Pinned == true
		if pa ~= pb then
			return pa
		end
		if sortKey == "Health" and a.Ratio ~= b.Ratio then
			return a.Ratio < b.Ratio
		elseif sortKey == "Name" then
			local na, nb = string.lower(a.Name), string.lower(b.Name)
			if na ~= nb then
				return na < nb
			end
		end
		return a.Dist < b.Dist
	end)

	local shown = math.min(#listOrder, CONFIG.MaxListRows)
	for i = 1, shown do
		local entry = listOrder[i]
		local row = getRow(i)
		row.Target = entry.Data
		row.Button.Visible = true
		row.Pin.Visible = entry.Data.Pinned == true
		setSwatch(row.Swatch, row.SwatchShape, entry.Player ~= nil, entry.Color)
		row.Name.Text = if entry.Context
			then escapeRich(entry.Name) .. '  <font color="' .. MUTED_HEX .. '">' .. escapeRich(entry.Context) .. "</font>"
			else escapeRich(entry.Name)
		row.HpFill.Size = UDim2.fromScale(entry.Ratio, 1)
		row.HpFill.BackgroundColor3 = C.Ember:Lerp(C.Text, entry.Ratio)
		row.HpText.Text = if entry.Hp == math.huge or entry.MaxHp == math.huge
			then "inf"
			else formatNumber(entry.Ratio * 100) .. "%"
		row.Dist.Text = formatNumber(entry.Dist)
	end
	for i = shown + 1, #rows do
		rows[i].Button.Visible = false
		rows[i].Target = nil
	end

	emptyLabel.Visible = shown == 0
	if shown == 0 then
		if state.Filter ~= "" then
			emptyLabel.Text = 'Nothing matches "' .. state.Filter .. '". Clear the search to see everything in range.'
		else
			emptyLabel.Text = "Nothing within " .. formatNumber(range) .. " studs. Raise the range in Visuals or rescan."
		end
	end

	refreshInspector()

	if #newAlerts > 0 then
		table.sort(newAlerts, function(a, b)
			return a.Dist < b.Dist
		end)
		for i = 1, math.min(#newAlerts, 2) do
			local alert = newAlerts[i]
			toast(alert.Name .. " is " .. formatNumber(alert.Dist) .. " studs away", C.Ember)
		end
		if #newAlerts > 2 then
			toast("And " .. plural(#newAlerts - 2, "more", "more") .. " nearby", C.Ember)
		end
		playSound("Alert")
	end

	scanInfo.Text = string.format("%.2f ms", (os.clock() - started) * 1000)
end

local function renderRadar(camera, sweepOn)
	local myChar = localPlayer.Character
	local myRoot = if myChar then getRoot(myChar) else nil
	local origin = if myRoot then myRoot.Position else camera.CFrame.Position

	local look = camera.CFrame.LookVector
	local northUp = state.RadarMode == "North"

	local viewFrame = CFrame.new()
	if not northUp and Vector2.new(look.X, look.Z).Magnitude > 1e-3 then
		viewFrame = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	end

	local north = viewFrame:VectorToObjectSpace(Vector3.new(0, 0, -1))
	placeCompass(math.deg(math.atan2(north.Z, north.X)))
	if northUp and Vector2.new(look.X, look.Z).Magnitude > 1e-3 then
		headingPivot.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
	else
		headingPivot.Rotation = 0
	end

	local radius = BLIP_R
	local range = state.Range
	local count = 0

	for _, entry in visibleSorted do
		if count >= CONFIG.MaxBlips then
			break
		end
		local root = entry.Root
		if root.Parent then
			count += 1
			local rel = viewFrame:VectorToObjectSpace(root.Position - origin)
			local planar = Vector2.new(rel.X, rel.Z)
			local dist = planar.Magnitude
			local r = math.min(math.sqrt(dist / range), 1) * radius
			local dir = if dist > 1e-3 then planar / dist else Vector2.zero
			local x, y = dir.X * r, dir.Y * r

			local blip = getBlip(count)
			blip.Entry = entry
			blip.Holder.Visible = true
			blip.Holder.Position = UDim2.new(0.5, x, 0.5, y)
			setSwatch(blip.Frame, blip.Shape, entry.Player ~= nil, entry.Color)

			local fade = 0
			if sweepOn then
				local delta = (sweepAngle - math.deg(math.atan2(y, x))) % 360
				fade = 0.1 + 0.65 * (delta / 360)
			end
			local focused = entry.Data == inspected or entry.Data.Pinned == true or blip == hoveredBlip
			blip.Frame.BackgroundTransparency = if focused then 0 else fade
			blip.Ring.Enabled = focused
		end
	end

	for i = count + 1, #blips do
		blips[i].Holder.Visible = false
		blips[i].Entry = nil
	end

	local hovered = hoveredBlip
	if hovered and hovered.Holder.Visible and hovered.Entry then
		local entry = hovered.Entry
		blipTipLabel.Text = escapeRich(entry.Name)
			.. ' <font color="'
			.. MUTED_HEX
			.. '">'
			.. formatNumber(entry.Dist)
			.. "</font>"
		local pos = hovered.Holder.Position
		blipTip.Position = UDim2.new(0.5, pos.X.Offset, 0.5, pos.Y.Offset - 10)
		blipTip.Visible = true
	else
		blipTip.Visible = false
	end
end

local function renderOverlay(camera)
	local wantTracers = state.Esp and state.Tracers
	local wantArrows = state.Esp and state.Arrows
	local tracerCount, arrowCount = 0, 0

	if wantTracers or wantArrows then
		local viewport = camera.ViewportSize
		local cx, cy = viewport.X / 2, viewport.Y / 2
		local margin = 40
		local used = 0

		for _, entry in visibleSorted do
			if used >= CONFIG.MaxOverlay then
				break
			end
			local root = entry.Root
			if root.Parent then
				used += 1
				local point = camera:WorldToViewportPoint(root.Position)
				local inFront = point.Z > 0
				local onScreen = inFront
					and point.X >= 0
					and point.X <= viewport.X
					and point.Y >= 0
					and point.Y <= viewport.Y

				if onScreen then
					if wantTracers then
						tracerCount += 1
						local line = getTracer(tracerCount)
						local ox, oy = cx, viewport.Y - 6
						local dx, dy = point.X - ox, point.Y - oy
						line.Position = UDim2.fromOffset(ox + dx / 2, oy + dy / 2)
						line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1)
						line.Rotation = math.deg(math.atan2(dy, dx))
						line.BackgroundColor3 = entry.Color
						line.Visible = true
					end
				elseif wantArrows then
					arrowCount += 1
					local dx, dy = point.X - cx, point.Y - cy
					if not inFront then
						dx, dy = -dx, -dy
					end
					if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then
						dy = 1
					end
					local scale = math.min(
						(cx - margin) / math.max(math.abs(dx), 1e-3),
						(cy - margin) / math.max(math.abs(dy), 1e-3)
					)
					local ax, ay = cx + dx * scale, cy + dy * scale
					local length = math.sqrt(dx * dx + dy * dy)
					local ux, uy = dx / length, dy / length

					local arrow = getArrow(arrowCount)
					arrow.Holder.Position = UDim2.fromOffset(ax, ay)
					arrow.Holder.Rotation = math.deg(math.atan2(dy, dx))
					arrow.Shaft.BackgroundColor3 = entry.Color
					arrow.Tip.BackgroundColor3 = entry.Color
					arrow.Holder.Visible = true
					arrow.Label.Position = UDim2.fromOffset(ax - ux * 24, ay - uy * 24)
					arrow.Label.Text = formatNumber(entry.Dist)
					arrow.Label.TextColor3 = entry.Color
					arrow.Label.Visible = true
				end
			end
		end
	end

	for i = tracerCount + 1, #tracers do
		tracers[i].Visible = false
	end
	for i = arrowCount + 1, #arrows do
		arrows[i].Holder.Visible = false
		arrows[i].Label.Visible = false
	end
end

local function renderFrame(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local panelShown = root.Visible or (miniHud ~= nil and miniHud.Visible)
	local sweepOn = state.Sweep and not motionReduced

	if panelShown and sweepOn then
		local speed = 360 / CONFIG.SweepSeconds
		if os.clock() < sweepBoostUntil then
			speed *= 4
		end
		sweepAngle = (sweepAngle + speed * dt) % 360
		for i, pivot in sweepPivots do
			pivot.Rotation = sweepAngle - (i - 1) * 4
			pivot.Visible = true
		end
	else
		for _, pivot in sweepPivots do
			pivot.Visible = false
		end
	end

	if panelShown then
		renderRadar(camera, sweepOn)
	end
	renderOverlay(camera)
end

local baseScale = 1
local isOpen = true
local collapsed = false
local animToken = 0
local dragging = false
local dragStart = Vector3.zero
local startPosition = root.Position

local function refreshScale()
	local size = panelGui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	if TOUCH then
		local portrait = size.X < size.Y
		local sheetX = if portrait then (W - SHEET_W) / 2 else W + 12
		local sheetY = if portrait then COLLAPSED_H + 12 else 0
		sheetRoot.Position = UDim2.fromOffset(sheetX, sheetY)
		local left, right = math.min(0, sheetX), math.max(W, sheetX + SHEET_W)
		local groupW, groupH = right - left, sheetY + COLLAPSED_H
		baseScale = math.clamp(math.min((size.X - 24) / groupW, (size.Y - 16) / groupH), 0.5, 1)
		root.Position = UDim2.new(0.5, -(groupW / 2 + left) * baseScale, 0.55, -(groupH / 2) * baseScale)
	else
		baseScale = math.clamp((size.Y - 24) / FULL_H, 0.5, 1)
	end
	if isOpen then
		uiScale.Scale = baseScale
	end
end
panelGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshScale)
refreshScale()

local function showOpenState()
	if TOUCH then
		miniHud.Visible = false
		espQuick.Visible = false
		placeBezel(false)
		scrim.Visible = true
	else
		reopenChip.Visible = false
	end
	root.Visible = true
end

local function showClosedState()
	root.Visible = false
	if TOUCH then
		scrim.Visible = false
		placeBezel(true)
		miniHud.Visible = true
		espQuick.Visible = true
	else
		reopenChip.Visible = true
	end
end

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	animToken += 1
	local token = animToken

	if open then
		playSound("Open")
		showOpenState()
		powerOn()
		if motionReduced then
			uiScale.Scale = baseScale
		else
			uiScale.Scale = baseScale * 0.96
			tween(uiScale, M.panel, { Scale = baseScale })
		end
	else
		playSound("Close")
		dragging = false
		activeSlider = nil
		if motionReduced then
			showClosedState()
		else
			local closing = tween(uiScale, M.fast, { Scale = baseScale * 0.96 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			closing.Completed:Connect(function()
				if token == animToken then
					showClosedState()
				end
			end)
		end
	end
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)
reopenChip.Activated:Connect(function()
	setOpen(true)
end)
if TOUCH then
	miniTap.Activated:Connect(function()
		setOpen(true)
	end)
	scrim.Activated:Connect(function()
		setOpen(false)
	end)
	sheetClose.Activated:Connect(function()
		setOpen(false)
	end)
end

collapseButton.Activated:Connect(function()
	playSound("Click")
	collapsed = not collapsed
	collapseButton.Text = if collapsed then "+" else "–"
	collapseTip.Text = if collapsed then "Expand panel" else "Collapse to radar"
	tween(root, M.panel, { Size = UDim2.fromOffset(W, if collapsed then COLLAPSED_H else FULL_H) })
end)

local scanning = false
rescanButton.Activated:Connect(function()
	if scanning then
		return
	end
	scanning = true
	rescanButton.Text = "Scanning"
	playSound("Scan")
	sweepBoostUntil = os.clock() + 0.9
	local found = fullScan()
	requestUpdate()
	task.delay(0.9, function()
		scanning = false
		rescanButton.Text = "Rescan"
		toast("Rescanned: " .. plural(found, "entity", "entities") .. " tracked")
	end)
end)

header.InputBegan:Connect(function(input)
	if not TOUCH and isPointerDown(input) then
		dragging = true
		dragStart = input.Position
		startPosition = root.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isPointerMove(input) then
		return
	end
	if dragging then
		local delta = input.Position - dragStart
		root.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
	if activeSlider then
		activeSlider.SetFromX(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if isPointerDown(input) then
		dragging = false
		activeSlider = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.PanelKey then
		setOpen(not isOpen)
	elseif input.KeyCode == CONFIG.EspKey then
		playSound("Toggle")
		setState("Esp", not state.Esp)
		toast(if state.Esp then "ESP on" else "ESP off")
	end
end)

selectTab(1, false)
task.defer(placeUnderline, false)
rampLegend.Visible = state.ColorMode == "Thermal"
fullScan()
if TOUCH then
	isOpen = false
	sheetRoot.Visible = true
	showClosedState()
	refreshScale()
else
	powerOn()
end

RunService.RenderStepped:Connect(renderFrame)
RunService.Heartbeat:Connect(function(dt)
	updateAccumulator += dt
	if updateAccumulator >= RATES[state.Rate] then
		updateAccumulator = 0
		updateAll()
	end
end)
