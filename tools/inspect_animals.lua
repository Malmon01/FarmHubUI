-- ตรวจโครงสร้างสัตว์ที่ออกจากไข่ (สำหรับพัฒนาแท็บหาตัว) พิมพ์ผลลง console/log
local function p(...) print("[FHInspect]", ...) end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v) end
	return table.concat(t, ", ")
end

-- สัตว์ที่วางอยู่บนพื้น
local pickups = workspace:FindFirstChild("AnimalPickups")
if pickups then
	for i, m in ipairs(pickups:GetChildren()) do
		if i > 3 then break end
		p("=== animal", m:GetFullName(), m.ClassName, "|", attrs(m))
		for _, c in ipairs(m:GetDescendants()) do
			if c:IsA("TextLabel") and c.Text ~= "" then p("  text", c:GetFullName(), "=", c.Text) end
			if c:IsA("ValueBase") then p("  value", c:GetFullName(), "=", tostring(c.Value)) end
			local a = attrs(c)
			if a ~= "" and not c:IsA("ParticleEmitter") then p("  attr", c:GetFullName(), c.ClassName, a) end
			if c:IsA("BillboardGui") then p("  billboard", c:GetFullName(), "Adornee=", tostring(c.Adornee)) end
		end
	end
end

-- จุดกด Steal
for _, d in ipairs(workspace:GetChildren()) do
	if d.Name == "PromptAnchor" then
		p("=== PromptAnchor", d.ClassName, attrs(d), "pos", tostring(d.Position))
		for _, c in ipairs(d:GetDescendants()) do
			p("  ", c:GetFullName(), c.ClassName, attrs(c),
				c:IsA("ProximityPrompt") and ("Action=" .. c.ActionText .. " Object=" .. c.ObjectText) or "")
		end
	end
end

-- BillboardGui ที่มีข้อความ /s (เงินต่อวินาที) ใน PlayerGui
local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
if pg then
	local n = 0
	for _, c in ipairs(pg:GetDescendants()) do
		if c:IsA("TextLabel") and c.Text:find("/s") and n < 10 then
			n += 1
			local bb = c:FindFirstAncestorWhichIsA("BillboardGui")
			p("  money text", c:GetFullName(), "=", c.Text, "| adornee", bb and tostring(bb.Adornee) or "-")
		end
	end
end
p("done")
