--[[
	Farm Hub UI  (Roblox Lua / Luau)
	- เมนูซ้าย: ฟาร์ม / หาตัว / สวน / เพิ่ม FPS
	- หน้าฟาร์ม: เลือกโซน, เริ่มฟาร์ม, เก็บเพชร, เลือกไข่ (รายการไข่เปลี่ยนตามโซนที่เลือก)
	- ลากหน้าต่างได้, กด RightControl เพื่อซ่อน/แสดง
	ใส่โค้ดการทำงานจริงตรงจุดที่เขียนว่า TODO ในส่วน "Callbacks"
]]

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local player       = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG  (แก้ชื่อโซน / ไข่ / โลโก้ ตรงนี้)
---------------------------------------------------------------------
local CONFIG = {
	Title      = "FARM HUB",
	LogoImage  = "",               -- เช่น "rbxassetid://1234567890" (ว่าง = แสดงคำว่า Logo)
	ToggleKey  = Enum.KeyCode.RightControl,
	ZoneOrder  = { "โซนที่ 12", "โซนที่ 13" },
	Zones = {
		["โซนที่ 12"] = { "ไข่ธรรมดา", "ไข่ทอง", "ไข่เพชร" },
		["โซนที่ 13"] = { "ไข่ไฟ", "ไข่น้ำแข็ง", "ไข่มังกร" },
	},
}

local State = {
	Zone        = CONFIG.ZoneOrder[1],
	Egg         = nil,
	AutoFarm    = false,
	CollectGems = false,
}
State.Egg = CONFIG.Zones[State.Zone][1]

---------------------------------------------------------------------
-- Callbacks  (ใส่ logic ของเกมตรงนี้)
---------------------------------------------------------------------
local Callbacks = {}

function Callbacks.ZoneChanged(zone)
	print("[FarmHub] เลือกโซน:", zone)
end

function Callbacks.EggChanged(egg)
	print("[FarmHub] เลือกไข่:", egg)
end

function Callbacks.AutoFarm(on)
	State.AutoFarm = on
	while State.AutoFarm do
		-- TODO: โค้ดฟาร์มในโซน State.Zone
		task.wait(0.5)
	end
end

function Callbacks.CollectGems(on)
	State.CollectGems = on
	while State.CollectGems do
		-- TODO: โค้ดเก็บเพชร
		task.wait(0.5)
	end
end

function Callbacks.FpsBoost()
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 9e9
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
			d.Enabled = false
		elseif d:IsA("BasePart") then
			d.Material = Enum.Material.SmoothPlastic
			d.Reflectance = 0
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		end
	end
end

function Callbacks.UnlockFps(on)
	if setfpscap then
		setfpscap(on and 999 or 60)
	else
		warn("[FarmHub] setfpscap ไม่รองรับในตัวรันนี้")
	end
end

---------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------
local C = {
	Bg      = Color3.fromRGB(24, 24, 28),
	Side    = Color3.fromRGB(18, 18, 22),
	Row     = Color3.fromRGB(34, 34, 40),
	Input   = Color3.fromRGB(46, 46, 54),
	Accent  = Color3.fromRGB(166, 226, 46),   -- เขียวมะนาวตามภาพร่าง
	Off     = Color3.fromRGB(70, 70, 80),
	Knob    = Color3.fromRGB(15, 15, 15),
	Text    = Color3.fromRGB(235, 235, 235),
	SubText = Color3.fromRGB(150, 150, 160),
}
local FONT = Enum.Font.GothamMedium

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function create(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function corner(inst, r)
	create("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
end

local function tween(inst, goal, t)
	TweenService:Create(inst, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad), goal):Play()
end

local function label(parent, text, props)
	local p = {
		BackgroundTransparency = 1,
		Font = FONT, Text = text, TextSize = 16,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}
	for k, v in pairs(props or {}) do p[k] = v end
	return create("TextLabel", p)
end

---------------------------------------------------------------------
-- Root
---------------------------------------------------------------------
local guiParent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local old = guiParent:FindFirstChild("FarmHubUI")
if old then old:Destroy() end

local gui = create("ScreenGui", {
	Name = "FarmHubUI", ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = guiParent,
})

local main = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(580, 360),
	BackgroundColor3 = C.Bg, Active = true,
	Parent = gui,
})
corner(main, 12)
create("UIStroke", { Color = C.Input, Thickness = 1, Parent = main })

-- Sidebar --------------------------------------------------------------
local side = create("Frame", {
	Size = UDim2.new(0, 150, 1, 0),
	BackgroundColor3 = C.Side, Parent = main,
})
corner(side, 12)

label(side, CONFIG.Title, {
	Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 30),
	TextSize = 18, Font = Enum.Font.GothamBold, TextColor3 = C.Accent,
})

local tabHolder = create("Frame", {
	Position = UDim2.fromOffset(10, 52), Size = UDim2.new(1, -20, 1, -62),
	BackgroundTransparency = 1, Parent = side,
})
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabHolder })

-- Content --------------------------------------------------------------
local content = create("Frame", {
	Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -150, 1, 0),
	BackgroundTransparency = 1, Parent = main,
})

local pageTitle = label(content, "", {
	Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -120, 0, 28),
	TextSize = 20, Font = Enum.Font.GothamBold,
})

-- Logo (วงกลม) = แสดงโลโก้ + เป็นปุ่ม
local function makeLogo(parent, size, props)
	local p = {
		Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Row,
		Image = CONFIG.LogoImage, AutoButtonColor = false, Parent = parent,
	}
	for k, v in pairs(props or {}) do p[k] = v end
	local b = create("ImageButton", p)
	corner(b, size / 2)
	local stroke = create("UIStroke", { Color = C.Accent, Thickness = 2, Parent = b })
	if CONFIG.LogoImage == "" then
		label(b, "Logo", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14 })
	end
	b.MouseEnter:Connect(function() tween(stroke, { Thickness = 3 }) end)
	b.MouseLeave:Connect(function() tween(stroke, { Thickness = 2 }) end)
	return b
end

-- โลโก้มุมขวาบนในหน้าต่าง: กดเพื่อย่อหน้าต่าง
local logo = makeLogo(content, 56, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 10),
})

-- โลโก้ลอย (โชว์ตอนย่อ): กดเพื่อเปิดหน้าต่างกลับ, ลากย้ายได้
local floatLogo = makeLogo(gui, 60, {
	Position = UDim2.new(0, 20, 0.5, -30), Visible = false,
})

local function setMinimized(min)
	main.Visible = not min
	floatLogo.Visible = min
end

-- ปุ่มปิด
local closeBtn = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.Row,
	Font = Enum.Font.GothamBold, Text = "X", TextSize = 14, TextColor3 = C.SubText,
	AutoButtonColor = true, Parent = content,
})
corner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function()
	State.AutoFarm, State.CollectGems = false, false
	gui:Destroy()
end)

local pagesHolder = create("Frame", {
	Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 1, -88),
	BackgroundTransparency = 1, Parent = content,
})

---------------------------------------------------------------------
-- Tabs / Pages
---------------------------------------------------------------------
local tabs = {}

local function selectTab(tab)
	for _, t in ipairs(tabs) do
		local on = (t == tab)
		t.page.Visible = on
		tween(t.button, { BackgroundColor3 = on and C.Accent or C.Row })
		t.button.TextColor3 = on and C.Knob or C.Text
	end
	pageTitle.Text = tab.name
end

local function addTab(name)
	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 36), LayoutOrder = #tabs + 1,
		BackgroundColor3 = C.Row, AutoButtonColor = false,
		Font = FONT, Text = name, TextSize = 16, TextColor3 = C.Text,
		Parent = tabHolder,
	})
	corner(button, 8)

	local page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Accent,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false, Parent = pagesHolder,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	create("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = page })

	local tab = { name = name, button = button, page = page }
	table.insert(tabs, tab)
	button.MouseButton1Click:Connect(function() selectTab(tab) end)
	return page
end

---------------------------------------------------------------------
-- Components
---------------------------------------------------------------------
local order = 0
local function nextOrder() order += 1; return order end

local function makeRow(page, height)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 40), LayoutOrder = nextOrder(),
		BackgroundColor3 = C.Row, ClipsDescendants = true, Parent = page,
	})
	corner(row, 8)
	return row
end

local function makeToggle(page, text, default, callback)
	local row = makeRow(page)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 0, 40) })

	local track = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(48, 24), BackgroundColor3 = C.Off,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(track, 12)
	local knob = create("Frame", {
		Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 3, 0.5, -9),
		BackgroundColor3 = C.Text, Parent = track,
	})
	corner(knob, 9)

	local state = false
	local function set(v, silent)
		state = v
		tween(track, { BackgroundColor3 = v and C.Accent or C.Off })
		tween(knob, {
			Position = v and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
			BackgroundColor3 = v and C.Knob or C.Text,
		})
		if not silent and callback then task.spawn(callback, v) end
	end
	track.MouseButton1Click:Connect(function() set(not state) end)
	set(default or false, true)
	return { Set = set, Get = function() return state end }
end

local function makeButton(page, text, callback)
	local row = makeRow(page)
	local b = create("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = FONT, Text = text, TextSize = 16, TextColor3 = C.Accent, Parent = row,
	})
	b.MouseButton1Click:Connect(function()
		tween(row, { BackgroundColor3 = C.Input }, 0.08)
		task.delay(0.1, function() tween(row, { BackgroundColor3 = C.Row }) end)
		if callback then task.spawn(callback) end
	end)
end

local function makeNote(page, text)
	label(page, text, {
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(),
		TextSize = 13, TextColor3 = C.SubText,
	})
end

local function makeDropdown(page, text, options, default, callback)
	local ROW_H, ITEM_H, GAP = 40, 28, 4
	local row = makeRow(page, ROW_H)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 0, ROW_H) })

	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.new(0.55, -8, 0, ROW_H - 12), BackgroundColor3 = C.Input,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(btn, 6)
	local valueLabel = label(btn, "", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), TextSize = 15 })
	local arrow = label(btn, "v", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 16, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Accent, Font = Enum.Font.GothamBold,
	})

	local list = create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, ROW_H),
		Size = UDim2.new(0.55, -8, 0, 0), BackgroundTransparency = 1, Parent = row,
	})
	create("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local isOpen, current, opts = false, nil, {}

	local function setOpen(v)
		isOpen = v
		local h = v and (ROW_H + #opts * (ITEM_H + GAP) + 4) or ROW_H
		tween(row, { Size = UDim2.new(1, 0, 0, h) })
		arrow.Text = v and "^" or "v"
	end

	local function set(v, silent)
		current = v
		valueLabel.Text = v or "-- เลือก --"
		if not silent and callback then task.spawn(callback, v) end
	end

	local function setOptions(newOpts)
		opts = newOpts or {}
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		list.Size = UDim2.new(0.55, -8, 0, #opts * (ITEM_H + GAP))
		for i, o in ipairs(opts) do
			local item = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = i,
				BackgroundColor3 = C.Input, AutoButtonColor = true,
				Font = FONT, Text = o, TextSize = 14, TextColor3 = C.Text, Parent = list,
			})
			corner(item, 6)
			item.MouseButton1Click:Connect(function()
				set(o)
				setOpen(false)
			end)
		end
		if isOpen then setOpen(true) end
	end

	btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	setOptions(options)
	set(default, true)
	return { Set = set, Get = function() return current end, SetOptions = setOptions }
end

---------------------------------------------------------------------
-- Build pages
---------------------------------------------------------------------
-- 1) ฟาร์ม
local farmPage = addTab("ฟาร์ม")
local eggDropdown

makeDropdown(farmPage, "เลือกโซน", CONFIG.ZoneOrder, State.Zone, function(zone)
	State.Zone = zone
	local eggs = CONFIG.Zones[zone] or {}
	eggDropdown.SetOptions(eggs)
	eggDropdown.Set(eggs[1])          -- เปลี่ยนไข่ตามโซนที่เลือก
	Callbacks.ZoneChanged(zone)
end)

makeToggle(farmPage, "เริ่มฟาร์ม", false, Callbacks.AutoFarm)
makeToggle(farmPage, "เก็บเพชร", false, Callbacks.CollectGems)

eggDropdown = makeDropdown(farmPage, "เลือกไข่", CONFIG.Zones[State.Zone], State.Egg, function(egg)
	State.Egg = egg
	Callbacks.EggChanged(egg)
end)
makeNote(farmPage, "* รายการไข่จะเปลี่ยนตามโซนที่เลือก")

-- 2) หาตัว
local findPage = addTab("หาตัว")
makeToggle(findPage, "ตัวอย่าง: ออโต้หาตัว", false, function(on)
	print("[FarmHub] หาตัว:", on) -- TODO
end)

-- 3) สวน
local gardenPage = addTab("สวน")
makeToggle(gardenPage, "ตัวอย่าง: ออโต้รดน้ำ", false, function(on)
	print("[FarmHub] สวน:", on) -- TODO
end)

-- 4) เพิ่ม FPS
local fpsPage = addTab("เพิ่ม FPS")
makeButton(fpsPage, "ลดกราฟิก (เพิ่ม FPS)", Callbacks.FpsBoost)
makeToggle(fpsPage, "ปลดล็อก FPS", false, Callbacks.UnlockFps)
makeNote(fpsPage, "* ลดกราฟิกแล้วต้องรีจอยเพื่อคืนค่า")

selectTab(tabs[1])

---------------------------------------------------------------------
-- Drag + hotkey
---------------------------------------------------------------------
-- ทำให้ลากได้ คืนค่าฟังก์ชันเช็กว่าเพิ่งลากไปหรือเปล่า (กันกดติดตอนลากเสร็จ)
local function makeDraggable(frame)
	local dragging, dragStart, startPos, moved
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos, moved = true, input.Position, frame.Position, false
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 4 then moved = true end
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	return function() return moved end
end

makeDraggable(main)
local floatMoved = makeDraggable(floatLogo)

logo.MouseButton1Click:Connect(function() setMinimized(true) end)
floatLogo.MouseButton1Click:Connect(function()
	if not floatMoved() then setMinimized(false) end
end)

UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == CONFIG.ToggleKey then
		setMinimized(main.Visible)
	end
end)
