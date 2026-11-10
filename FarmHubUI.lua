--[[
	Farm Hub UI  (Roblox Lua / Luau)
	- เมนูซ้าย: ฟาร์ม / หาตัว / สวน / เพิ่ม FPS
	- หน้าฟาร์ม: เลือกโซน, เริ่มฟาร์ม, เก็บเพชร, เลือกไข่ (ดึงจากเกมจริง)
	- กดโลโก้เพื่อย่อหน้าต่าง, กด RightControl เพื่อซ่อน/แสดง

	โครงสร้างเกมที่ใช้:
	  workspace.Build.ZoneBuilds.ZoneN.Eggs["<tier>: <ชื่อไข่>"].Egg
	    Attributes: EggType, Health, MaxHealth, Broken, ZoneIndex
]]

local Players           = game:GetService("Players")
local UIS               = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local CONFIG = {
	Title      = "FARM HUB",
	LogoImage  = "",               -- เช่น "rbxassetid://1234567890" (ว่าง = แสดงคำว่า Logo)
	ToggleKey  = Enum.KeyCode.RightControl,
	HitDelay   = 0.15,             -- เวลาระหว่างการตีแต่ละครั้ง (วินาที)
	EggTimeout = 20,               -- ตีไข่ใบเดียวนานสุดกี่วินาที แล้วข้ามไปใบอื่น
	TweenSpeed = 300,              -- ความเร็ว Tween (studs/วินาที)
	LiftDelay  = 0.6,              -- รอหลังไข่แตกก่อนยกไข่ (วินาที)
	GuardTimeout = 30,             -- รอผู้พิทักษ์ตีนานสุดกี่วินาที
	KnockbackDist = 12,            -- ถูกดันออกไกลเกินนี้ = โดนตีแล้ว
	ZoneOrder  = {},
	ZoneModels = {},               -- "โซนที่ N" -> workspace.Build.ZoneBuilds.ZoneN
}
local ALL_EGGS = "ทั้งหมด"

-- ดึงรายชื่อโซนจริงจาก workspace.Build.ZoneBuilds (Zone1, Zone2, ...)
do
	local build = workspace:FindFirstChild("Build")
	local zoneBuilds = build and build:FindFirstChild("ZoneBuilds")
	local nums = {}
	if zoneBuilds then
		for _, z in ipairs(zoneBuilds:GetChildren()) do
			local n = tonumber(z.Name:match("^Zone(%d+)$"))
			if n then table.insert(nums, n) end
		end
	end
	table.sort(nums)   -- เรียง 1,2,3,...,13
	for _, n in ipairs(nums) do
		local name = "โซนที่ " .. n
		table.insert(CONFIG.ZoneOrder, name)
		CONFIG.ZoneModels[name] = zoneBuilds:FindFirstChild("Zone" .. n)
	end
	if #CONFIG.ZoneOrder == 0 then
		CONFIG.ZoneOrder = { "ไม่พบโซน" }
		warn("[FarmHub] ไม่พบ workspace.Build.ZoneBuilds")
	end
end

-- รายชื่อชนิดไข่ในโซน (อ่านจากชื่อโมเดล "1: Forest Egg", "2: Rock Egg", ...)
local function eggTypesOf(zoneName)
	local list, found, seen = { ALL_EGGS }, {}, {}
	local zone = CONFIG.ZoneModels[zoneName]
	local folder = zone and zone:FindFirstChild("Eggs")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local tier, name = m.Name:match("^(%d+):%s*(.+)$")
			if name and not seen[name] then
				seen[name] = true
				table.insert(found, { tonumber(tier), name })
			end
		end
	end
	table.sort(found, function(a, b) return a[1] < b[1] end)
	for _, f in ipairs(found) do table.insert(list, f[2]) end
	return list
end

local State = {
	Zone        = CONFIG.ZoneOrder[1],
	Egg         = ALL_EGGS,
	AutoFarm    = false,
	CollectGems = false,
	Debug       = false,
	FarmRun     = 0,
	ReadyZone   = nil,
}

---------------------------------------------------------------------
-- Game helpers
---------------------------------------------------------------------
local function getChar()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then return char, root, hum end
end

-- ถืออาวุธ (ใช้ชิ้นที่ถืออยู่ ถ้าไม่ได้ถือจะหยิบชิ้นแรกในกระเป๋า)
local function getTool()
	local char, _, hum = getChar()
	if not char then return end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then return tool end
	local backpack = player:FindFirstChild("Backpack")
	tool = backpack and backpack:FindFirstChildOfClass("Tool")
	if tool then hum:EquipTool(tool) end
	return tool
end

local function eggAlive(part)
	return part and part.Parent ~= nil
		and part:GetAttribute("Broken") ~= true
		and (part:GetAttribute("Health") or 1) > 0
end

local function log(...)
	if State.Debug then print("[FarmHub]", ...) end
end

-- หาไข่ที่ใกล้ที่สุดในโซน (filter = ชื่อชนิดไข่ หรือ ALL_EGGS) คืนค่า (ไข่, ระยะ)
local function findEgg(zoneName, filter)
	local zone = CONFIG.ZoneModels[zoneName]
	local folder = zone and zone:FindFirstChild("Eggs")
	local _, root = getChar()
	if not folder or not root then return end
	local best, bestDist
	for _, m in ipairs(folder:GetChildren()) do
		local part = m:FindFirstChild("Egg")
		if part and part:IsA("BasePart") and eggAlive(part) then
			if filter == ALL_EGGS or part:GetAttribute("EggType") == filter then
				local d = (part.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = part, d end
			end
		end
	end
	return best, bestDist
end

-- ไข่ที่ใกล้ที่สุดจากทุกโซน = โซนที่ใกล้ที่สุด คืนค่า (ไข่, ชื่อโซน)
local function nearestZoneEgg()
	local bestEgg, bestZone, bestDist
	for zoneName in pairs(CONFIG.ZoneModels) do
		local egg, d = findEgg(zoneName, ALL_EGGS)
		if egg and (not bestDist or d < bestDist) then
			bestEgg, bestZone, bestDist = egg, zoneName, d
		end
	end
	return bestEgg, bestZone
end

-- ผู้พิทักษ์ของโซน = โมเดลในโซนที่มี Attribute "ChaseState" (เช่น Zone1.Chicken)
local function getGuard(zoneName)
	local zone = CONFIG.ZoneModels[zoneName]
	if not zone then return end
	for _, c in ipairs(zone:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("ChaseState") ~= nil then return c end
	end
end

-- ตำแหน่งยืนข้างเป้าหมาย หันหน้าเข้าหา
local function besideCFrame(targetPos, root, gap)
	local flat = Vector3.new(root.Position.X - targetPos.X, 0, root.Position.Z - targetPos.Z)
	local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local pos = targetPos + dir * gap
	return CFrame.lookAt(pos, Vector3.new(targetPos.X, pos.Y, targetPos.Z))
end

local function eggCFrame(egg, root)
	return besideCFrame(egg.Position, root, math.max(egg.Size.X, egg.Size.Z) / 2 + 2.5)
end

-- เคลื่อนที่แบบ Tween ด้วยความเร็ว CONFIG.TweenSpeed (studs/วินาที)
local function tweenTo(cf, shouldStop)
	local _, root = getChar()
	if not root then return false end
	local t = (root.Position - cf.Position).Magnitude / CONFIG.TweenSpeed
	if t < 0.05 then root.CFrame = cf return true end
	local hold = RunService.Heartbeat:Connect(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	local tween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
	local done = false
	local c = tween.Completed:Connect(function() done = true end)
	tween:Play()
	while not done and not (shouldStop and shouldStop()) and root.Parent do task.wait() end
	if not done then tween:Cancel() end
	c:Disconnect()
	hold:Disconnect()
	return done
end

-- Tween ไปข้างไข่ แล้วตีจนแตก
local function breakEgg(egg, shouldStop)
	local _, root = getChar()
	if not root or not tweenTo(eggCFrame(egg, root), shouldStop) then return false end
	log("ตีไข่:", egg:GetAttribute("EggType"), "HP", egg:GetAttribute("Health"))
	local started = os.clock()
	while eggAlive(egg) and not shouldStop() and os.clock() - started < CONFIG.EggTimeout do
		local _, r = getChar()
		local tool = getTool()
		if r then
			r.CFrame = eggCFrame(egg, r)
			r.AssemblyLinearVelocity = Vector3.zero
		end
		if tool then tool:Activate() end
		task.wait(CONFIG.HitDelay)
	end
	return not eggAlive(egg)
end

-- ยกไข่: ถ้ามี ProximityPrompt ใกล้ตัว (ในไข่ที่แตก หรือใน AnimalPickups) จะกดให้
local function liftEgg(eggModel)
	task.wait(CONFIG.LiftDelay)
	local _, root = getChar()
	if not root then return end
	if not fireproximityprompt then
		log("ตัวรันนี้ไม่มี fireproximityprompt (ถ้ายกไข่อัตโนมัติอยู่แล้วก็ไม่เป็นไร)")
		return
	end
	for _, scope in ipairs({ eggModel, workspace:FindFirstChild("AnimalPickups") }) do
		if scope then
			for _, p in ipairs(scope:GetDescendants()) do
				local part = p:IsA("ProximityPrompt") and p.Enabled and p.Parent
				if part and part:IsA("BasePart") and (part.Position - root.Position).Magnitude < 20 then
					log("กด Prompt:", p:GetFullName(), p.ActionText)
					fireproximityprompt(p)
				end
			end
		end
	end
end

-- Tween ไปหาผู้พิทักษ์ แล้วยืนติดตัวจนกว่าจะโดนตี
local function waitForGuardHit(guard, shouldStop)
	local _, root, hum = getChar()
	if not root then return false end
	local hit, conns = false, {}
	local lastHealth = hum.Health
	table.insert(conns, hum.HealthChanged:Connect(function(h)
		if h < lastHealth then log("เลือดลด:", lastHealth, "->", h) hit = true end
		lastHealth = h
	end))
	table.insert(conns, hum.Died:Connect(function() hit = true end))
	local fling = ReplicatedStorage:FindFirstChild("CatchFlingRemote")
	if fling and fling:IsA("RemoteEvent") then
		table.insert(conns, fling.OnClientEvent:Connect(function(...)
			log("<- CatchFlingRemote", ...)
			hit = true
		end))
	end
	table.insert(conns, guard:GetAttributeChangedSignal("ChaseState"):Connect(function()
		log("ผู้พิทักษ์ ChaseState =", guard:GetAttribute("ChaseState"))
	end))

	local stop = function() return hit or shouldStop() end
	tweenTo(besideCFrame(guard:GetPivot().Position, root, 3), stop)

	local started = os.clock()
	while not stop() and guard.Parent and os.clock() - started < CONFIG.GuardTimeout do
		local _, r = getChar()
		if not r then hit = true break end
		local target = besideCFrame(guard:GetPivot().Position, r, 3)
		r.CFrame = target
		r.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.1)
		-- ถูกตีจนกระเด็น / ถูกย้ายตำแหน่ง
		if r.Parent and (r.Position - target.Position).Magnitude > CONFIG.KnockbackDist then
			log("ถูกกระเด็นออกจากจุดที่ยืน")
			hit = true
		end
	end
	for _, c in ipairs(conns) do c:Disconnect() end
	return hit
end

-- ขั้นเตรียม: ขุดไข่โซนที่ใกล้ที่สุด -> ยกไข่ -> พุ่งไปหาผู้พิทักษ์ให้ตี
local function warmUp(shouldStop)
	local egg, zoneName = nearestZoneEgg()
	if not egg then log("ไม่พบไข่ใกล้ ๆ ข้ามขั้นผู้พิทักษ์") return end

	log("ขั้นที่ 1: ขุดไข่ใน", zoneName)
	local char = getChar()
	local carryConn = State.Debug and char and char.ChildAdded:Connect(function(c)
		log("ตัวละครได้ของ:", c.Name, c.ClassName)
	end)
	local eggModel = egg.Parent
	breakEgg(egg, shouldStop)
	if not shouldStop() then
		log("ขั้นที่ 2: ยกไข่")
		liftEgg(eggModel)
	end
	if carryConn then carryConn:Disconnect() end
	if shouldStop() then return end

	local guard = getGuard(zoneName)
	if not guard then log("ไม่พบผู้พิทักษ์ใน", zoneName) return end
	log("ขั้นที่ 3: พุ่งไปหาผู้พิทักษ์", guard.Name)
	local hit = waitForGuardHit(guard, shouldStop)
	log(hit and "ผู้พิทักษ์ตีแล้ว" or "หมดเวลารอผู้พิทักษ์")
	task.wait(1)
	if not getChar() then player.CharacterAdded:Wait() task.wait(1) end   -- ถ้าตาย รอเกิดใหม่
end

---------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------
local Callbacks = {}

function Callbacks.ZoneChanged(zone)
	log("เลือกโซน:", zone)
end

function Callbacks.EggChanged(egg)
	log("เลือกไข่:", egg)
end

-- ฟาร์ม: ทุกครั้งที่เริ่ม/เปลี่ยนโซน จะทำขั้นเตรียม (warmUp) ก่อน
-- แล้วค่อย Tween ไปโซนที่เลือก ตีไข่ที่ใกล้ที่สุดไปเรื่อย ๆ
function Callbacks.AutoFarm(on)
	State.AutoFarm = on
	State.FarmRun += 1
	State.ReadyZone = nil
	if not on then return end
	local run = State.FarmRun
	local function stopped() return not State.AutoFarm or State.FarmRun ~= run end

	while not stopped() do
		if not getChar() then
			task.wait(0.5)
		elseif State.ReadyZone ~= State.Zone then
			local target = State.Zone
			warmUp(stopped)
			State.ReadyZone = target
			log("ขั้นที่ 4: ไปฟาร์มที่", target)
		else
			local egg = findEgg(State.Zone, State.Egg)
			if egg then
				breakEgg(egg, function() return stopped() or State.ReadyZone ~= State.Zone end)
			else
				task.wait(0.5)   -- ไม่มีไข่ รอเกิดใหม่
			end
		end
		task.wait()
	end
end

-- เก็บเพชร: แตะชิ้นส่วนที่ชื่อมี Gem/Diamond ที่เกิดขึ้นในแมพ (ต้องมี firetouchinterest)
local gemConn
local function isGem(inst)
	if not inst:IsA("BasePart") then return false end
	local n = inst.Name:lower()
	return n:find("gem") ~= nil or n:find("diamond") ~= nil
end

local function touchGem(part)
	local _, root = getChar()
	if not root or not part.Parent then return end
	if firetouchinterest then
		firetouchinterest(root, part, 0)
		task.wait()
		firetouchinterest(root, part, 1)
	end
end

function Callbacks.CollectGems(on)
	State.CollectGems = on
	if on then
		if not firetouchinterest then warn("[FarmHub] ตัวรันนี้ไม่มี firetouchinterest เก็บเพชรอัตโนมัติไม่ได้") end
		gemConn = gemConn or workspace.DescendantAdded:Connect(function(inst)
			if State.CollectGems and isGem(inst) then
				if State.Debug then print("[FarmHub] เจอเพชร:", inst:GetFullName()) end
				task.delay(0.2, touchGem, inst)
			end
		end)
	elseif gemConn then
		gemConn:Disconnect()
		gemConn = nil
	end
end

-- โหมดดีบัก: พิมพ์ข้อมูล Remote ที่เกี่ยวกับการตีไข่/เพชร ลงช่อง F9
local debugHooked = false
function Callbacks.Debug(on)
	State.Debug = on
	if not on or debugHooked then return end
	debugHooked = true
	for _, name in ipairs({ "EggGemDropRemote", "EggHitConfirmed", "EggHitRejected", "EggHitLanded" }) do
		local r = ReplicatedStorage:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(function(...)
				if State.Debug then print("[FarmHub] <-", name, ...) end
			end)
		end
	end
	if hookmetamethod and getnamecallmethod then
		local watch = { EggHitRequest = true, BatHitRequest = true, MasteryPickaxeSwing = true }
		local old
		old = hookmetamethod(game, "__namecall", function(self, ...)
			if State.Debug and getnamecallmethod() == "FireServer"
				and typeof(self) == "Instance" and watch[self.Name] then
				print("[FarmHub] ->", self.Name, ...)
			end
			return old(self, ...)
		end)
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
	State.AutoFarm, State.Debug = false, false
	Callbacks.CollectGems(false)
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
	eggDropdown.SetOptions(eggTypesOf(zone))   -- เปลี่ยนไข่ตามโซนที่เลือก
	eggDropdown.Set(ALL_EGGS)
	Callbacks.ZoneChanged(zone)
end)

makeToggle(farmPage, "เริ่มฟาร์ม", false, Callbacks.AutoFarm)
makeToggle(farmPage, "เก็บเพชร", false, Callbacks.CollectGems)

eggDropdown = makeDropdown(farmPage, "เลือกไข่", eggTypesOf(State.Zone), State.Egg, function(egg)
	State.Egg = egg
	Callbacks.EggChanged(egg)
end)
makeButton(farmPage, "รีเฟรชรายชื่อไข่", function()
	eggDropdown.SetOptions(eggTypesOf(State.Zone))
end)
makeNote(farmPage, "* รายการไข่จะเปลี่ยนตามโซนที่เลือก")
makeToggle(farmPage, "โหมดดีบัก (ดูผลใน F9)", false, Callbacks.Debug)

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
