-- ตรวจโครงสร้างสัตว์ที่ออกจากไข่ (สำหรับพัฒนาแท็บหาตัว) พิมพ์ผลลง console/log
local function p(...) print("[FHInspect]", ...) end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v) end
	return table.concat(t, ", ")
end
local seen, count = {}, 0
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("ProximityPrompt") and d.ActionText:lower():find("steal") and count < 6 then
		local holder = d:FindFirstAncestorWhichIsA("Model") or d.Parent
		if holder and not seen[holder] then
			seen[holder] = true
			count += 1
			p("=== prompt", d:GetFullName(), "| Action:", d.ActionText, "| Object:", d.ObjectText, "| Hold:", d.HoldDuration)
			p("holder", holder:GetFullName(), holder.ClassName, "| attrs:", attrs(holder))
			local parentModel = holder.Parent
			if parentModel then p("holder.Parent", parentModel:GetFullName(), parentModel.ClassName, "| attrs:", attrs(parentModel)) end
			for _, c in ipairs(holder:GetDescendants()) do
				local a = attrs(c)
				if a ~= "" then p("  attr", c:GetFullName(), c.ClassName, a) end
				if c:IsA("TextLabel") and c.Text ~= "" then p("  text", c:GetFullName(), c.Text) end
				if c:IsA("ValueBase") then p("  value", c:GetFullName(), tostring(c.Value)) end
			end
		end
	end
end
for _, name in ipairs({ "AnimalPickups", "CarriedAnimals" }) do
	local f = workspace:FindFirstChild(name)
	if f then
		p("=== folder", name, "children", #f:GetChildren())
		for i, c in ipairs(f:GetChildren()) do
			if i > 5 then break end
			p("  ", c:GetFullName(), c.ClassName, attrs(c))
		end
	end
end
local rs = game:GetService("ReplicatedStorage")
local mut = rs:FindFirstChild("Mutation", true)
if mut then
	local n = {}
	for _, c in ipairs(mut:GetChildren()) do n[#n + 1] = c.Name end
	p("=== Mutation folder", mut:GetFullName(), table.concat(n, ", "))
end
p("done")
