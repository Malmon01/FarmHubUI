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
	GemRadius  = 60,               -- เก็บเพชรเฉพาะที่อยู่ใกล้ตัวในรัศมีนี้ (studs)
	GemStay    = 0.6,              -- ยืนบนเพชรรอให้เก็บติดนานสุดกี่วินาที
	TeleportRetries = 3,           -- วาร์ปซ้ำกี่ครั้งถ้าเกมดึงตัวกลับ
	TeleportVia = { [13] = 12 },   -- โซนที่ไกลเกินวาร์ปตรง: วาร์ปไปโซนนี้ก่อน แล้ว Tween ต่อ
	SwingPressGap = 0.8,           -- กดปุ่ม Auto Swing แล้วรออย่างน้อยกี่วินาทีก่อนกดซ้ำ (รอปุ่มเปลี่ยนสี)
	TweenSpeed = 300,              -- ความเร็ว Tween (studs/วินาที)
	LiftWait   = 12,               -- รอสัตว์ออกจากไข่แล้วกด Steal นานสุดกี่วินาที
	LiftRadius = 60,               -- หาปุ่ม Steal ในรัศมีนี้รอบไข่ที่ตีแตก
	LiftPromptWords = { "steal", "pick", "carry", "grab", "lift" },
	ToolKeyword = "Pickaxe",       -- ชื่อที่ขุด (Elite Pickaxe ฯลฯ)
	GuardTimeout = 30,             -- รอผู้พิทักษ์ตีนานสุดกี่วินาที
	KnockbackDist = 12,            -- ถูกดันออกไกลเกินนี้ = โดนตีแล้ว
	ZoneOrder  = {},
	ZoneModels = {},               -- "โซนที่ N" -> workspace.Build.ZoneBuilds.ZoneN
}
local VERSION = "2026-11-10 r22"   -- เช็กใน F9 ว่าได้เวอร์ชันล่าสุด
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
	local list, found, seen = {}, {}, {}
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
	Eggs        = {},              -- ชนิดไข่ที่เลือก (ว่าง = ทุกชนิด)
	AutoFarm    = false,
	CollectGems = false,
	Debug       = false,
	FarmRun     = 0,
	ReadyZone   = nil,
	SwingWant   = false,           -- ต้องการให้ Auto Swing เปิดอยู่ไหม
	GemRun      = 0,
	Priority    = "ใกล้สุดก่อน",
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

local function log(...)
	if State.Debug then print("[FarmHub]", ...) end
end

-- ถือที่ขุด: หา Tool ที่ชื่อมี CONFIG.ToolKeyword (เช่น "Elite Pickaxe") แล้วถือ
local function getTool()
	local char, _, hum = getChar()
	if not char then return end
	local kw = CONFIG.ToolKeyword:lower()
	local held = char:FindFirstChildOfClass("Tool")
	if held and held.Name:lower():find(kw, 1, true) then return held end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t.Name:lower():find(kw, 1, true) then
				log("ถือ:", t.Name)
				hum:EquipTool(t)
				return t
			end
		end
	end
	log("ไม่พบ Tool ที่ชื่อมี '" .. CONFIG.ToolKeyword .. "' ในกระเป๋า")
end

-- หา GUI ปุ่มที่มองเห็นอยู่บนจอ จากข้อความ/ชื่อ (เช่น "Auto Swing", "Drop")
local function isShown(gui)
	local g = gui
	while g and not g:IsA("LayerCollector") do
		if g:IsA("GuiObject") and not g.Visible then return false end
		g = g.Parent
	end
	return g ~= nil and g.Enabled
end

local function squash(s) return (s:lower():gsub("%s", "")) end

-- exact = true: ข้อความ/ชื่อต้องตรงทั้งคำ (กันไปเจอปุ่มอื่นที่มีคำนี้อยู่ข้างใน)
local function findGuiButton(text, exact)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local want = squash(text)
	local function match(s)
		s = squash(s)
		if exact then return s == want end
		return s:find(want, 1, true) ~= nil
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") and not d:IsDescendantOf(pg:FindFirstChild("FarmHubUI") or d) then
			local label = (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text or ""
			if match(label) or match(d.Name) then
				local btn = d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton")
				if btn and isShown(btn) then return btn end
			end
		end
	end
end

-- กดปุ่ม GUI ของเกม (ใช้ getconnections ถ้ามี ไม่งั้นจำลองการคลิกเมาส์)
local function pressButton(btn)
	if getconnections then
		for _, sig in ipairs({ btn.Activated, btn.MouseButton1Click, btn.MouseButton1Down }) do
			local conns = getconnections(sig)
			if #conns > 0 then
				for _, c in ipairs(conns) do pcall(function() c:Fire() end) end
				return
			end
		end
	end
	local vim = game:GetService("VirtualInputManager")
	local sg = btn:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = (sg and sg.IgnoreGuiInset) and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
	local p = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
	vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
	task.wait(0.05)
	vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
end

-- ปุ่ม Auto Swing ของเกม: PlayerGui.MainGUI.AutoSwing
-- สีแดง = เปิดอยู่, สีเขียว = ปิดอยู่ (เกมไม่มีค่าอื่นบอกสถานะ เลยดูจากสี)
local autoSwingBtn
local function getAutoSwingBtn()
	if autoSwingBtn and autoSwingBtn.Parent then return autoSwingBtn end
	local pg = player:FindFirstChild("PlayerGui")
	local main = pg and pg:FindFirstChild("MainGUI")
	autoSwingBtn = main and main:FindFirstChild("AutoSwing") or findGuiButton("Auto Swing")
	return autoSwingBtn
end

-- สถานะ Auto Swing: เขียว = เปิด, แดง = ปิด
-- 1) ถ้าปุ่มใช้รูปจาก ReplicatedStorage.Assets.AutoSwingState ดูจากชื่อรูป (On/Off ฯลฯ)
-- 2) ไม่งั้นดูจากสี (เขียวมากกว่า = เปิด)
-- คืนค่า true = เปิด, false = ปิด, nil = ดูไม่ออก
local function swingStateImages()
	local map = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("AutoSwingState")
	if not folder then return map end
	for _, d in ipairs(folder:GetDescendants()) do
		local id = (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image
			or (d:IsA("Decal") or d:IsA("Texture")) and d.Texture
			or d:IsA("StringValue") and d.Value
		if id and id ~= "" then
			local n = d.Name:lower()
			if n:find("off") or n:find("disable") or n:find("inactive") or n:find("red") then
				map[id] = false
			elseif n:find("on") or n:find("enable") or n:find("active") or n:find("green") then
				map[id] = true
			end
		end
	end
	return map
end

local function autoSwingIsOn(btn)
	-- เกมเก็บสถานะใน AutoSwingColorAlpha: 0 = ปิด (แดง), มากกว่า 0 = เปิด (เขียว / กำลังกะพริบ)
	local alpha = btn:FindFirstChild("AutoSwingColorAlpha")
	if alpha and alpha:IsA("NumberValue") then
		return alpha.Value > 0.05
	end
	local list = btn:GetDescendants()
	table.insert(list, btn)
	local images = swingStateImages()
	for _, d in ipairs(list) do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Visible and images[d.Image] ~= nil then
			return images[d.Image]
		end
	end
	local reds, greens = 0, 0
	local function judge(c)
		if c.R - c.G > 0.25 then reds += 1 elseif c.G - c.R > 0.25 then greens += 1 end
	end
	for _, d in ipairs(list) do
		if d:IsA("GuiObject") and d.Visible then
			if d.BackgroundTransparency < 1 then judge(d.BackgroundColor3) end
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.ImageTransparency < 1 then judge(d.ImageColor3) end
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.TextTransparency < 1 then judge(d.TextColor3) end
		elseif d:IsA("UIGradient") and d.Enabled then
			for _, k in ipairs(d.Color.Keypoints) do judge(k.Value) end
		elseif d:IsA("UIStroke") and d.Enabled then
			judge(d.Color)
		end
	end
	if greens > reds then return true end
	if reds > greens then return false end
	return nil
end

-- บันทึกโครงสร้างปุ่ม Auto Swing ลงไฟล์ FarmHub_autoswing.txt (ไว้ตรวจว่าเกมแสดงสถานะยังไง)
local function dumpAutoSwing(btn)
	if not writefile then return end
	local out = { "VERSION " .. VERSION, "isOn = " .. tostring(autoSwingIsOn(btn)) }
	local function c3(c) return string.format("(%.2f,%.2f,%.2f)", c.R, c.G, c.B) end
	local list = btn:GetDescendants()
	table.insert(list, 1, btn)
	for _, d in ipairs(list) do
		local s = d:GetFullName() .. " [" .. d.ClassName .. "]"
		if d:IsA("GuiObject") then s ..= " vis=" .. tostring(d.Visible) .. " bg=" .. c3(d.BackgroundColor3) .. " bgT=" .. d.BackgroundTransparency end
		if d:IsA("ImageLabel") or d:IsA("ImageButton") then s ..= " img=" .. d.Image .. " imgC=" .. c3(d.ImageColor3) end
		if d:IsA("TextLabel") or d:IsA("TextButton") then s ..= " tc=" .. c3(d.TextColor3) end
		if d:IsA("UIGradient") then
			local k = {} for _, p in ipairs(d.Color.Keypoints) do k[#k + 1] = c3(p.Value) end
			s ..= " grad=" .. table.concat(k, ",")
		end
		if d:IsA("UIStroke") then s ..= " stroke=" .. c3(d.Color) end
		if d:IsA("ValueBase") then s ..= " value=" .. tostring(d.Value) end
		table.insert(out, s)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("AutoSwingState")
	table.insert(out, "--- AutoSwingState")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			local s = d:GetFullName() .. " [" .. d.ClassName .. "]"
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then s ..= " img=" .. d.Image end
			if d:IsA("Decal") or d:IsA("Texture") then s ..= " tex=" .. d.Texture end
			if d:IsA("ValueBase") then s ..= " value=" .. tostring(d.Value) end
			table.insert(out, s)
		end
	end
	pcall(appendfile or writefile, "FarmHub_autoswing.txt", table.concat(out, "\n") .. "\n\n")
end

-- คุม Auto Swing ของเกมให้ตรงกับที่ต้องการ (State.SwingWant)
--   เปิด = ยืนติดไข่ที่กำลังจะตีแล้ว, ปิด = ระหว่างเดินทาง / หลังไข่แตก
-- กดทันทีเมื่อสถานะไม่ตรงกับที่ต้องการ (อ่านจาก AutoSwingColorAlpha ซึ่งแม่น)
local lastObserved, dumps = "init", 0
local lastSwingPress = 0
local function syncAutoSwing()
	local btn = getAutoSwingBtn()
	if not btn or not isShown(btn) then return end
	local on = autoSwingIsOn(btn)
	if on ~= lastObserved and dumps < 12 then   -- สถานะเปลี่ยน: บันทึกลงไฟล์ไว้ตรวจ
		lastObserved, dumps = on, dumps + 1
		dumpAutoSwing(btn)
	end
	if on == nil or on == State.SwingWant then return end
	-- กดแล้วปุ่มต้องใช้เวลาเปลี่ยนสี (ค่า alpha ค่อย ๆ ขยับ) รอก่อนค่อยกดซ้ำ
	if os.clock() - lastSwingPress < CONFIG.SwingPressGap then return end
	lastSwingPress = os.clock()
	log(State.SwingWant and "เปิด Auto Swing" or "ปิด Auto Swing")
	pressButton(btn)
end

-- ตั้งสถานะที่ต้องการ แล้วกดทันที (ไม่ต้องรอ) ถ้าไม่ตรง
local function setSwing(on)
	if State.SwingWant ~= on then lastSwingPress = 0 end
	State.SwingWant = on
	syncAutoSwing()
end

-- กำลังยกสัตว์อยู่ไหม (ตอนยก เกมจะโชว์ปุ่ม Drop) จำปุ่มไว้ ไม่ต้องสแกนทุกครั้ง
local dropBtn, dropScanAt = nil, 0
local function isCarrying()
	if dropBtn and dropBtn.Parent then return isShown(dropBtn) end
	if os.clock() < dropScanAt then return false end
	dropScanAt = os.clock() + 0.3
	dropBtn = findGuiButton("Drop", true)
	return dropBtn ~= nil
end

local function eggAlive(part)
	return part and part.Parent ~= nil
		and part:GetAttribute("Broken") ~= true
		and (part:GetAttribute("Health") or 1) > 0
end

-- ความหายากของไข่ (EggInfoRarity) เรียงจากธรรมดา -> หายากสุด
local RARITY_ORDER = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic",
	"Secret", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal",
}
local RARITY_RANK = {}
for i, r in ipairs(RARITY_ORDER) do RARITY_RANK[r] = i end

local PRIORITY_NEAR, PRIORITY_RARE, PRIORITY_LUCK = "ใกล้สุดก่อน", "หายากสุดก่อน", "Luck สูงสุดก่อน"

local function eggRarity(part) return part:GetAttribute("EggInfoRarity") or "?" end
local function eggLuck(part) return part:GetAttribute("HatchLuck") or part:GetAttribute("Luck") or 0 end

-- ผ่านตัวกรองชนิดไข่ไหม (ไม่ได้เลือกเลย = ทุกชนิด)
local function eggSelected(part)
	if next(State.Eggs) == nil then return true end
	return State.Eggs[part:GetAttribute("EggType")] == true
end

-- จำตำแหน่งกลางโซน (เฉลี่ยตำแหน่งไข่ที่เคยเห็น) และบันทึกลงไฟล์ ใช้วาร์ปไปโซนที่อยู่ไกลจนไข่ยังไม่โหลด
local HttpService = game:GetService("HttpService")
local ZONE_FILE = "FarmHub_zones.json"
local ZonePos = {}
pcall(function()
	if isfile and isfile(ZONE_FILE) then
		for name, v in pairs(HttpService:JSONDecode(readfile(ZONE_FILE))) do
			ZonePos[name] = Vector3.new(v[1], v[2], v[3])
		end
	end
end)
local zoneSaveAt = 0
local function rememberZone(zoneName, pos)
	ZonePos[zoneName] = pos
	if writefile and os.clock() > zoneSaveAt then
		zoneSaveAt = os.clock() + 20
		local data = {}
		for n, p in pairs(ZonePos) do data[n] = { p.X, p.Y, p.Z } end
		pcall(writefile, ZONE_FILE, HttpService:JSONEncode(data))
	end
end

-- หาไข่ในโซน
--   filter   = ชื่อชนิดไข่ หรือ ALL_EGGS
--   usePrefs = true: ใช้ชนิดไข่ที่เลือก + ลำดับการตีที่ตั้งไว้ (ใช้ตอนฟาร์ม)
-- คืนค่า (ไข่, ระยะ)
local function findEgg(zoneName, filter, usePrefs)
	local zone = CONFIG.ZoneModels[zoneName]
	local folder = zone and zone:FindFirstChild("Eggs")
	local _, root = getChar()
	if not folder or not root then return end
	local priority = usePrefs and State.Priority or PRIORITY_NEAR
	local best, bestDist, bestScore
	local sum, count = Vector3.zero, 0
	for _, m in ipairs(folder:GetChildren()) do
		local part = m:FindFirstChild("Egg")
		if part and part:IsA("BasePart") then sum += part.Position count += 1 end
		if part and part:IsA("BasePart") and eggAlive(part)
			and (filter == ALL_EGGS or part:GetAttribute("EggType") == filter)
			and (not usePrefs or eggSelected(part)) then
			local d = (part.Position - root.Position).Magnitude
			local score = 0
			if priority == PRIORITY_RARE then
				score = RARITY_RANK[eggRarity(part)] or 0
			elseif priority == PRIORITY_LUCK then
				score = eggLuck(part)
			end
			-- คะแนนสูงกว่าชนะ ถ้าเท่ากันเอาใบที่ใกล้กว่า
			if not best or score > bestScore or (score == bestScore and d < bestDist) then
				best, bestDist, bestScore = part, d, score
			end
		end
	end
	if count > 0 then rememberZone(zoneName, sum / count) end
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

-- วางตัวละครให้ยืนบนพื้นจริง (ยิงเลเซอร์ลงหาพื้น) ไม่ลอยกลางอากาศ
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function onGround(cf, ignore)
	local char = player.Character
	local list = { char }
	if ignore then table.insert(list, ignore) end
	local gems = workspace:FindFirstChild("EggGemDrops")
	if gems then table.insert(list, gems) end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), groundParams)
	if not hit then return cf end
	local _, root, hum = getChar()
	local height = 3
	if hum and root then
		height = root.Size.Y / 2 + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight)
	end
	return cf + Vector3.new(0, hit.Position.Y + height - cf.Position.Y, 0)
end

local function eggCFrame(egg, root)
	local cf = besideCFrame(egg.Position, root, math.max(egg.Size.X, egg.Size.Z) / 2 + 2.5)
	-- ไม่นับไข่และรังเป็นพื้น (ข้ามทั้งโฟลเดอร์ Eggs ของโซน)
	local eggsFolder = egg.Parent and egg.Parent.Parent
	return onGround(cf, eggsFolder)
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
	-- Noclip ระหว่าง Tween: ทะลุกำแพง/สิ่งกีดขวาง
	local char = root.Parent
	local noclip = RunService.Stepped:Connect(function()
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end)
	local tween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
	local done = false
	local c = tween.Completed:Connect(function() done = true end)
	tween:Play()
	while not done and not (shouldStop and shouldStop()) and root.Parent do task.wait() end
	if not done then tween:Cancel() end
	c:Disconnect()
	hold:Disconnect()
	noclip:Disconnect()
	return done
end

local grabNearbyGems   -- กำหนดในส่วนเก็บเพชรด้านล่าง

-- Tween ไปข้างไข่ แล้วตีจนแตก
local function breakEgg(egg, shouldStop, skipGems)
	local _, root = getChar()
	getTool()          -- ถือที่ขุดไว้ (ปุ่ม Auto Swing จะโผล่)
	setSwing(false)    -- ระหว่างเดินทางไปไข่: ปิด
	if not root or not tweenTo(eggCFrame(egg, root), shouldStop) then return false end
	setSwing(true)     -- ถึงไข่เป้าหมายแล้ว: เปิด
	log("ตีไข่:", egg:GetAttribute("EggType"), "HP", egg:GetAttribute("Health"))
	local started, lastActivate = os.clock(), 0
	while eggAlive(egg) and not shouldStop() and os.clock() - started < CONFIG.EggTimeout do
		local _, r = getChar()
		if r then
			r.CFrame = eggCFrame(egg, r)
			r.AssemblyLinearVelocity = Vector3.zero
		end
		syncAutoSwing()
		if os.clock() - lastActivate > CONFIG.HitDelay then
			lastActivate = os.clock()
			local tool = getTool()
			if tool then tool:Activate() end   -- สำรอง เผื่อ Auto Swing ไม่ทำงาน
		end
		task.wait()   -- เช็กทุกเฟรม: ไข่แตกปุ๊บ ไปต่อทันที
	end
	setSwing(false)        -- ไข่เป้าหมายแตก (หรือหยุด): ปิดทันที กันตีโดนไข่ใบอื่น
	-- เพชรตกตอนไข่แตก: เก็บตอนนี้ (Auto Swing ปิดแล้ว)
	if not skipGems and State.CollectGems and grabNearbyGems then grabNearbyGems(shouldStop) end
	return not eggAlive(egg)
end

-- ยกสัตว์: ไข่แตกแล้วจะมีสัตว์ออกมาพร้อมปุ่ม "E Steal" (ProximityPrompt)
-- สคริปต์จะหา Prompt ที่เพิ่งเกิดใกล้ไข่ที่ตีแตก แล้ว Tween ไปกดให้
local function promptPos(p)
	local par = p.Parent
	if not par then return end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Model") then return par:GetPivot().Position end
end

local function isLiftPrompt(p)
	local text = (p.ActionText .. " " .. p.ObjectText .. " " .. p.Name):lower()
	for _, word in ipairs(CONFIG.LiftPromptWords) do
		if text:find(word, 1, true) then return true end
	end
	return false
end

local function triggerPrompt(p)
	p.HoldDuration = 0   -- ไม่ต้องกดค้าง (ฝั่งเรา)
	if fireproximityprompt then
		fireproximityprompt(p)
		return
	end
	-- ไม่มี fireproximityprompt: กดปุ่มคีย์บอร์ดของ Prompt แทน
	local vim = game:GetService("VirtualInputManager")
	vim:SendKeyEvent(true, p.KeyboardKeyCode, false, game)
	task.wait(0.05)
	vim:SendKeyEvent(false, p.KeyboardKeyCode, false, game)
end

-- เริ่มจด Prompt ที่เกิดใหม่ในแมพ (เรียกก่อนตีไข่) คืนค่า (รายการ, ฟังก์ชันหยุดจด)
local function watchNewPrompts()
	local list = {}
	local conn = workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then table.insert(list, d) end
	end)
	return list, function() conn:Disconnect() end
end

-- ขั้นตอนสำคัญจะพิมพ์ลง F9 เสมอ (ไม่ต้องเปิดโหมดดีบัก)
local statusLabel   -- ช่องสถานะบนหน้าฟาร์ม (สร้างตอนทำ UI)
local function say(...)
	print("[FarmHub]", ...)
	if statusLabel then
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		statusLabel.Text = "สถานะ: " .. table.concat(parts, " ")
	end
end

local function bestLiftPrompt(list, eggPos)
	local best, bestDist
	for _, p in ipairs(list) do
		if p.Parent and p.Enabled and isLiftPrompt(p) then
			local pos = promptPos(p)
			local d = pos and (pos - eggPos).Magnitude
			if d and d < CONFIG.LiftRadius and (not bestDist or d < bestDist) then
				best, bestDist = p, d
			end
		end
	end
	return best
end

-- ยกสัตว์ให้ไวที่สุด: เช็กทุกเฟรม, วาร์ปไปติดตัวสัตว์ (ระยะสั้น) แล้วกด Steal ทันที
local function liftAnimal(eggPos, newPrompts, shouldStop)
	local started, tried = os.clock(), 0
	local slowScanAt = os.clock() + 1.5   -- ถ้า 1.5 วิยังไม่เจอ ค่อยสแกนทั้งแมพ (ช้า)
	while os.clock() - started < CONFIG.LiftWait and not shouldStop() do
		local best = bestLiftPrompt(newPrompts, eggPos)
		if not best then
			local pickups = workspace:FindFirstChild("AnimalPickups")
			if pickups then
				local list = {}
				for _, p in ipairs(pickups:GetDescendants()) do
					if p:IsA("ProximityPrompt") then table.insert(list, p) end
				end
				best = bestLiftPrompt(list, eggPos)
			end
		end
		if not best and os.clock() > slowScanAt then
			slowScanAt = os.clock() + 1
			local list = {}
			for _, p in ipairs(workspace:GetDescendants()) do
				if p:IsA("ProximityPrompt") then table.insert(list, p) end
			end
			best = bestLiftPrompt(list, eggPos)
		end

		if best then
			if tried == 0 then say("ยกสัตว์: กด", best.ActionText, "ที่", best:GetFullName()) end
			local _, root = getChar()
			local pos = promptPos(best)
			if root and pos then
				root.CFrame = besideCFrame(pos, root, 1.5)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			triggerPrompt(best)
			tried += 1
			-- เช็กผลทุกเฟรม ไม่เกิน 0.3 วิ แล้วค่อยกดซ้ำ
			local t = os.clock()
			while os.clock() - t < 0.3 do
				if not best.Parent or not best.Enabled or isCarrying() then
					say(string.format("ยกสัตว์แล้ว (%.2f วิ, กด %d ครั้ง)", os.clock() - started, tried))
					return true
				end
				task.wait()
			end
		else
			task.wait()
		end
	end
	say(tried > 0 and "กด Steal แล้วแต่ยังยกไม่ได้" or "ไม่เจอปุ่ม Steal ใกล้ไข่ที่ตีแตก")
	return false
end

-- Tween ไปหาผู้พิทักษ์ แล้วยืนติดตัวจนกว่าจะโดนตี
local function waitForGuardHit(guard, shouldStop)
	local _, root, hum = getChar()
	if not root then return false end
	local hit, conns = false, {}
	-- ถ้ายกสัตว์อยู่: "โดนตีแล้ว" = ผู้พิทักษ์แย่งสัตว์ไป (ปุ่ม Drop หาย) แม่นที่สุด
	-- ถ้าไม่ได้ยก: ใช้เลือดลด / ตาย / CatchFlingRemote / กระเด็น แทน
	local carrying = isCarrying()
	local lastHealth = hum.Health
	table.insert(conns, hum.HealthChanged:Connect(function(h)
		if h < lastHealth then log("เลือดลด:", lastHealth, "->", h) hit = not carrying end
		lastHealth = h
	end))
	table.insert(conns, hum.Died:Connect(function() hit = true end))
	local fling = ReplicatedStorage:FindFirstChild("CatchFlingRemote")
	if fling and fling:IsA("RemoteEvent") then
		table.insert(conns, fling.OnClientEvent:Connect(function(...)
			log("<- CatchFlingRemote", ...)
			hit = not carrying
		end))
	end
	table.insert(conns, guard:GetAttributeChangedSignal("ChaseState"):Connect(function()
		log("ผู้พิทักษ์ ChaseState =", guard:GetAttribute("ChaseState"))
	end))

	local stop = function() return hit or shouldStop() end
	tweenTo(onGround(besideCFrame(guard:GetPivot().Position, root, 3), guard), stop)

	local started = os.clock()
	while not stop() and guard.Parent and os.clock() - started < CONFIG.GuardTimeout do
		local _, r = getChar()
		if not r then hit = true break end
		local target = onGround(besideCFrame(guard:GetPivot().Position, r, 3), guard)
		r.CFrame = target
		r.AssemblyLinearVelocity = Vector3.zero
		task.wait()   -- เช็กทุกเฟรม
		if carrying and not isCarrying() then
			log("ผู้พิทักษ์แย่งสัตว์ไปแล้ว")
			hit = true
		end
		-- ถูกตีจนกระเด็น / ถูกย้ายตำแหน่ง (ใช้เฉพาะตอนไม่ได้ยกสัตว์)
		if not carrying and r.Parent and (r.Position - target.Position).Magnitude > CONFIG.KnockbackDist then
			log("ถูกกระเด็นออกจากจุดที่ยืน")
			hit = true
		end
	end
	for _, c in ipairs(conns) do c:Disconnect() end
	return hit
end

-- ขั้นเตรียม: ขุดไข่โซนที่ใกล้ที่สุด -> ยกสัตว์ที่ออกจากไข่ (Steal) -> พุ่งไปหาผู้พิทักษ์ให้ตี
local function warmUp(shouldStop)
	local egg, zoneName = nearestZoneEgg()
	if not egg then say("ไม่พบไข่ใกล้ ๆ ข้ามขั้นผู้พิทักษ์") return end

	say("ขั้นที่ 1: ขุดไข่ใน", zoneName)
	local eggPos = egg.Position
	local newPrompts, stopWatching = watchNewPrompts()
	breakEgg(egg, shouldStop, true)   -- ขั้นเตรียม: ไม่เก็บเพชร รีบยกสัตว์
	if not shouldStop() then
		say("ขั้นที่ 2: ยกสัตว์")
		liftAnimal(eggPos, newPrompts, shouldStop)
	end
	stopWatching()
	if shouldStop() then return end

	local guard = getGuard(zoneName)
	if not guard then say("ไม่พบผู้พิทักษ์ใน", zoneName) return zoneName end
	say("ขั้นที่ 3: พุ่งไปหาผู้พิทักษ์", guard.Name)
	local hit = waitForGuardHit(guard, shouldStop)
	say(hit and "ผู้พิทักษ์ตีแล้ว" or "หมดเวลารอผู้พิทักษ์")
	if not getChar() then player.CharacterAdded:Wait() task.wait(1) end   -- ถ้าตาย รอเกิดใหม่

	return zoneName
end

-- ตำแหน่งปลายทางในโซน: ข้างไข่ (ถ้าเห็นไข่แล้ว) หรือกลางโซน
local function zoneTarget(zoneName, root)
	local egg = findEgg(zoneName, ALL_EGGS, true) or findEgg(zoneName, ALL_EGGS)
	if egg then return eggCFrame(egg, root) end
	-- ไข่ยังไม่โหลด: ใช้ตำแหน่งกลางโซนที่จำไว้ ถ้ายังไม่เคยเห็น ใช้กึ่งกลางกรอบของโมเดลโซน
	if ZonePos[zoneName] then
		return onGround(CFrame.new(ZonePos[zoneName] + Vector3.new(0, 5, 0)))
	end
	-- ลอง ZoneHitboxes ก่อน (กล่องขอบเขตโซน) แล้วค่อยใช้กรอบของโมเดลโซน
	local num = zoneName:match("(%d+)")
	local build = workspace:FindFirstChild("Build")
	local hitboxes = build and build:FindFirstChild("ZoneHitboxes")
	local hb = hitboxes and num and (hitboxes:FindFirstChild("Zone" .. num) or hitboxes:FindFirstChild(num))
	if hb then
		local pos = hb:IsA("BasePart") and hb.Position or (hb:IsA("Model") and hb:GetBoundingBox().Position)
		if pos then return onGround(CFrame.new(pos + Vector3.new(0, 5, 0))) end
	end
	local zone = CONFIG.ZoneModels[zoneName]
	if not zone then return end
	local ok, box = pcall(zone.GetBoundingBox, zone)
	local cf = ok and box or zone:GetPivot()
	say("ยังไม่รู้ตำแหน่ง", zoneName, "ใช้กึ่งกลางโมเดลโซน")
	return onGround(CFrame.new(cf.Position + Vector3.new(0, 5, 0)))
end

-- วาร์ปทันทีไปโซน (ถ้าเกมดึงตัวกลับ จะวาร์ปซ้ำ สูงสุด CONFIG.TeleportRetries ครั้ง)
local function teleportInto(zoneName)
	for attempt = 1, CONFIG.TeleportRetries do
		local _, root = getChar()
		if not root then return false end
		local target = zoneTarget(zoneName, root)
		if not target then return false end
		root.CFrame = target
		root.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.4)
		if root.Parent and (root.Position - target.Position).Magnitude < 40 then return true end
		say("เกมดึงตัวกลับหลังวาร์ป ลองใหม่ (ครั้งที่ " .. attempt .. ")")
	end
	return false
end

-- ไปโซนที่เลือก: ถ้าโซนนั้นไกลเกินวาร์ปตรง (CONFIG.TeleportVia) วาร์ปไปโซนก่อนหน้าก่อน แล้ว Tween ต่อ
local function goToZone(zoneName, shouldStop)
	local num = tonumber(zoneName:match("(%d+)"))
	local viaNum = num and CONFIG.TeleportVia[num]
	if viaNum then
		local via = "โซนที่ " .. viaNum
		say("วาร์ปไป", via, "ก่อน")
		teleportInto(via)
		local _, root = getChar()
		local target = root and zoneTarget(zoneName, root)
		if target then
			say("Tween ต่อไป", zoneName)
			tweenTo(target, shouldStop)
		end
	else
		say("วาร์ปไป", zoneName)
		teleportInto(zoneName)
	end
	task.wait(0.3)   -- รอไข่ในโซนโหลด
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
-- โดนผู้พิทักษ์ตีแล้ววาร์ปทันทีไปโซนที่เลือก จากนั้น Tween ไปตีไข่ที่ใกล้ที่สุดไปเรื่อย ๆ
function Callbacks.AutoFarm(on)
	State.AutoFarm = on
	State.FarmRun += 1
	State.ReadyZone = nil
	if not on then return end
	local run = State.FarmRun
	local function stopped() return not State.AutoFarm or State.FarmRun ~= run end
	-- ตาย/เกิดใหม่ระหว่างฟาร์ม: เริ่มขั้นเตรียม + วาร์ปใหม่ ไม่ Tween ข้ามแมพจากจุดเกิด
	local respawnConn = player.CharacterAdded:Connect(function()
		if not stopped() then say("ตัวละครเกิดใหม่ เริ่มรอบใหม่") State.ReadyZone = nil end
	end)
	local waiting = true
	-- คุม Auto Swing ตลอดที่ฟาร์ม (ระหว่าง Tween ด้วย) หยุดฟาร์มแล้วปิดให้
	task.spawn(function()
		while not stopped() do syncAutoSwing() task.wait(0.1) end
		State.SwingWant = false
		local t = os.clock()
		while os.clock() - t < 3 and not State.AutoFarm do syncAutoSwing() task.wait(0.1) end
	end)

	while not stopped() do
		if not getChar() then
			task.wait(0.5)
		elseif State.ReadyZone ~= State.Zone then
			local target = State.Zone
			local warmZone = warmUp(stopped)
			if stopped() then break end
			State.ReadyZone = target
			if warmZone == target then
				say("ขั้นที่ 4: อยู่ใน", target, "แล้ว เริ่มฟาร์มเลย")
			else
				say("ขั้นที่ 4: ไปฟาร์มที่", target)
				goToZone(target, stopped)   -- วาร์ป (โซนไกลวาร์ปผ่านโซนก่อนหน้า) แล้วเริ่มฟาร์ม
			end
		else
			local egg = findEgg(State.Zone, ALL_EGGS, true)
			if egg then
				if waiting then say("ตีไข่:", egg:GetAttribute("EggType"), egg:GetAttribute("EggInfoRarity")) waiting = false end
				breakEgg(egg, function() return stopped() or State.ReadyZone ~= State.Zone end)
			else
				if not waiting then say("ไม่มีไข่ตามตัวกรองใน", State.Zone, "รอไข่เกิด") waiting = true end
				task.wait(0.5)   -- ไม่มีไข่ รอเกิดใหม่
			end
		end
		task.wait()
	end
	respawnConn:Disconnect()
end

-- เก็บเพชร: เพชรที่ตกจากไข่อยู่ใน workspace.EggGemDrops (เช่น EggGemDrops.Gem)
-- วิธีเก็บ: วาร์ปตัวละครไปแตะเพชรที่อยู่ใกล้ตัว (ในรัศมี CONFIG.GemRadius) แล้วกลับที่เดิม
local gemLogged = false

local function gemPart(g)
	if g:IsA("BasePart") then return g end
	return g:FindFirstChildWhichIsA("BasePart", true)
end

-- พิมพ์โครงสร้างเพชรเม็ดแรกลง F9 (ไว้ดูว่าเกมเก็บเพชรแบบไหน)
local function describeGem(g)
	local attrs, inside = {}, {}
	for k, v in pairs(g:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
	for _, d in ipairs(g:GetDescendants()) do table.insert(inside, d.Name .. "[" .. d.ClassName .. "]") end
	say("เพชร:", g:GetFullName(), g.ClassName,
		"| attrs:", table.concat(attrs, ", "),
		"| ข้างใน:", table.concat(inside, ", "))
end

local function nearbyGems(root)
	local folder = workspace:FindFirstChild("EggGemDrops")
	local list = {}
	if not folder then return list end
	for _, g in ipairs(folder:GetChildren()) do
		local part = gemPart(g)
		if part and (part.Position - root.Position).Magnitude <= CONFIG.GemRadius then
			table.insert(list, g)
		end
	end
	return list
end

-- เก็บเพชรแบบสคริปต์รุ่นก่อน: Tween (Noclip) ไปหาเพชรที่ตกใกล้ตัวทีละเม็ด จนหมด
local gemSkip = setmetatable({}, { __mode = "k" })   -- เพชรที่เก็บไม่ติด -> ข้ามไปก่อนจนถึงเวลานี้
grabNearbyGems = function(shouldStop)
	local got = 0
	while not (shouldStop and shouldStop()) do
		local _, root = getChar()
		if not root then break end
		-- เพชรเม็ดที่ใกล้ที่สุด (ข้ามเม็ดที่เพิ่งเก็บไม่ติด)
		local best, bestDist
		for _, g in ipairs(nearbyGems(root)) do
			local part = gemPart(g)
			if part and not (gemSkip[g] and os.clock() < gemSkip[g]) then
				local d = (part.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = g, d end
			end
		end
		if not best then break end

		local part = gemPart(best)
		if not gemLogged then gemLogged = true describeGem(best) end
		if got == 0 then say("เก็บเพชร: ไปหาเพชรที่ตก") end
		tweenTo(onGround(CFrame.new(part.Position)), shouldStop)
		root.AssemblyLinearVelocity = Vector3.zero
		if firetouchinterest and part.Parent then
			firetouchinterest(root, part, 0)
			firetouchinterest(root, part, 1)
		end
		local prompt = best:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then triggerPrompt(prompt) end
		-- ยืนบนเพชรจนเพชรหาย (ไม่เกิน GemStay วิ)
		local t = os.clock()
		while best.Parent and os.clock() - t < CONFIG.GemStay do
			if part.Parent then root.CFrame = onGround(CFrame.new(part.Position)) end
			task.wait()
		end
		if best.Parent then
			gemSkip[best] = os.clock() + 3
		else
			got += 1
		end
	end
	if got > 0 then say("เก็บเพชรได้", got, "เม็ด") end
end

-- ตอนเปิดฟาร์ม ระบบฟาร์มจะเรียกเก็บเพชรเองระหว่างตีไข่
-- ตอนไม่ได้ฟาร์ม สวิตช์นี้จะวนเก็บเพชรใกล้ตัวเอง
function Callbacks.CollectGems(on)
	State.CollectGems = on
	State.GemRun += 1
	if not on then return end
	local run = State.GemRun
	say("เปิดเก็บเพชร (รัศมี " .. CONFIG.GemRadius .. " studs)")
	while State.CollectGems and State.GemRun == run do
		if not State.AutoFarm then grabNearbyGems(function() return not State.CollectGems or State.AutoFarm end) end
		task.wait(0.2)
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
label(side, "v " .. VERSION, {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -8),
	Size = UDim2.new(1, -28, 0, 16), TextSize = 11, TextColor3 = C.SubText,
})
print("[FarmHub] โหลดเวอร์ชัน", VERSION)

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

-- เลือกได้หลายตัว (selected = ตาราง { [ชื่อ] = true }) ไม่เลือกเลย = ทั้งหมด
local function makeMultiSelect(page, text, options, selected, callback, clearText)
	local ROW_H, ITEM_H, GAP = 40, 28, 4
	local CLEAR = clearText or "ล้าง (ทั้งหมด)"
	local row = makeRow(page, ROW_H)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 0, ROW_H) })

	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.new(0.55, -8, 0, ROW_H - 12), BackgroundColor3 = C.Input,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(btn, 6)
	local valueLabel = label(btn, "", {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
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

	local isOpen, opts, items = false, {}, {}

	local function refreshText()
		local names = {}
		for _, o in ipairs(opts) do if selected[o] then table.insert(names, o) end end
		for o in pairs(selected) do if not table.find(names, o) then table.insert(names, o) end end
		valueLabel.Text = #names == 0 and "ทั้งหมด" or table.concat(names, ", ")
		for o, item in pairs(items) do
			local on = selected[o] == true
			item.BackgroundColor3 = on and C.Accent or C.Input
			item.TextColor3 = on and C.Knob or C.Text
		end
	end

	local function setOpen(v)
		isOpen = v
		local h = v and (ROW_H + (#opts + 1) * (ITEM_H + GAP) + 4) or ROW_H
		tween(row, { Size = UDim2.new(1, 0, 0, h) })
		arrow.Text = v and "^" or "v"
	end

	local function changed()
		refreshText()
		if callback then task.spawn(callback, selected) end
	end

	local function setOptions(newOpts)
		opts = newOpts or {}
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		items = {}
		list.Size = UDim2.new(0.55, -8, 0, (#opts + 1) * (ITEM_H + GAP))
		local clear = create("TextButton", {
			Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = 0, BackgroundColor3 = C.Row,
			AutoButtonColor = true, Font = FONT, Text = CLEAR, TextSize = 14,
			TextColor3 = C.SubText, Parent = list,
		})
		corner(clear, 6)
		clear.MouseButton1Click:Connect(function()
			for k in pairs(selected) do selected[k] = nil end
			changed()
		end)
		for i, o in ipairs(opts) do
			local item = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = i,
				BackgroundColor3 = C.Input, AutoButtonColor = true,
				Font = FONT, Text = o, TextSize = 14, TextColor3 = C.Text, Parent = list,
			})
			corner(item, 6)
			items[o] = item
			item.MouseButton1Click:Connect(function()
				selected[o] = (not selected[o]) or nil
				changed()
			end)
		end
		refreshText()
		if isOpen then setOpen(true) end
	end

	btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	setOptions(options)
	return { SetOptions = setOptions }
end

---------------------------------------------------------------------
-- Build pages
---------------------------------------------------------------------
-- 1) ฟาร์ม
local farmPage = addTab("ฟาร์ม")
local eggPicker, lastEggList

-- อัปเดตรายชื่อไข่ของโซนที่เลือก (เรียกตอนเปลี่ยนโซน และวนเช็กเองทุก 1.5 วิ)
local function refreshEggList()
	if not eggPicker then return end
	local list = eggTypesOf(State.Zone)
	local key = table.concat(list, "|")
	if key ~= lastEggList then
		lastEggList = key
		eggPicker.SetOptions(list)
	end
end

makeDropdown(farmPage, "เลือกโซน", CONFIG.ZoneOrder, State.Zone, function(zone)
	State.Zone = zone
	for k in pairs(State.Eggs) do State.Eggs[k] = nil end   -- ไข่ของโซนเก่าใช้ไม่ได้แล้ว
	lastEggList = nil
	refreshEggList()
	Callbacks.ZoneChanged(zone)
end)

-- เปิด/ปิดเริ่มฟาร์ม = เปิด/ปิดเก็บเพชรด้วย (ปิดเก็บเพชรแยกได้ ฟาร์มยังทำงานต่อ)
local gemToggle
makeToggle(farmPage, "เริ่มฟาร์ม", false, function(on)
	if gemToggle then gemToggle.Set(on) end
	Callbacks.AutoFarm(on)
end)
gemToggle = makeToggle(farmPage, "เก็บเพชร", false, Callbacks.CollectGems)

eggPicker = makeMultiSelect(farmPage, "เลือกไข่", {}, State.Eggs, function()
	say("เลือกไข่:", next(State.Eggs) and "ตั้งแล้ว" or "ทุกชนิด")
end, "ล้าง (ทุกชนิด)")
refreshEggList()
task.spawn(function()
	while gui.Parent do
		refreshEggList()
		task.wait(1.5)
	end
end)
makeDropdown(farmPage, "ลำดับการตี", { PRIORITY_NEAR, PRIORITY_RARE, PRIORITY_LUCK }, State.Priority, function(p)
	State.Priority = p
	say("ลำดับการตี:", p)
end)
makeNote(farmPage, "* รายชื่อไข่อัปเดตเองตามโซนที่เลือก (เลือกได้หลายชนิด)")
statusLabel = label(farmPage, "สถานะ: พร้อม", {
	Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nextOrder(),
	TextSize = 13, TextColor3 = C.Accent, TextTruncate = Enum.TextTruncate.AtEnd,
})
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
