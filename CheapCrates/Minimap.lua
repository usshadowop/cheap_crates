--[[
	Cheap Crates - minimap button.

	Uses the same icon as the addon list (the .toc's IconTexture). Left-click opens or closes
	the window, right-click opens it on the In bags tab, drag moves it around the minimap.
	/crates minimap off hides it.
]]

local ADDON_NAME, ns = ...
local S = ns.S

local DEFAULT_ICON = "Interface\\Icons\\INV_Crate_02" -- keep in step with ## IconTexture in the .toc
local DEFAULT_ANGLE = 210

-- the icon the addon list shows, read from the .toc when the client exposes it
local function AddonIcon()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if get then
		local ok, icon = pcall(get, ADDON_NAME, "IconTexture")
		if ok and type(icon) == "string" and icon:lower():find("^interface[\\/]") then return icon end
	end
	return DEFAULT_ICON
end

local button = CreateFrame("Button", "CheapCratesMinimapButton", Minimap or UIParent)
ns.minimapButton = button
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(24, 24)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("CENTER")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(18, 18)
icon:SetPoint("CENTER")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- trim the icon's own border inside the round frame
button.icon = icon

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(50, 50)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

-- round minimaps keep the button on the circle; square ones (some UI addons) on the square's edge
local function Place()
	if not Minimap then return end
	local angle = math.rad(ns.db.minimap.angle or DEFAULT_ANGLE)
	local x, y = math.cos(angle), math.sin(angle)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		x = math.max(-1, math.min(1, x * 1.4142))
		y = math.max(-1, math.min(1, y * 1.4142))
	end
	local w = (Minimap:GetWidth() or 140) / 2 + 5
	local h = (Minimap:GetHeight() or 140) / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function Dragging()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale() or 1
	if not (mx and my and px and py) then return end
	px, py = px / scale, py / scale
	ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
	Place()
end

button:SetScript("OnDragStart", function(self)
	if not Minimap then return end
	self:LockHighlight()
	self:SetScript("OnUpdate", Dragging)
	GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
	self:UnlockHighlight()
end)

button:SetScript("OnClick", function(_, mouseButton)
	if not ns.db then return end
	if mouseButton == "RightButton" then
		if ns.frame:IsShown() and ns.db.view == "bags" then
			ns.Hide()
		else
			ns.db.view = "bags"
			ns.offset = 0
			ns.Show()
		end
	else
		ns.Toggle()
	end
end)

button:SetScript("OnEnter", function(self)
	if not ns.db then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Cheap Crates")
	local favor = ns.CurrentFavor()
	if favor then GameTooltip:AddDoubleLine("Merchant's Favor", tostring(favor), 0.8, 0.8, 0.8, 1, 1, 1) end
	local _, sum = ns.BagFill()
	if sum.can > 0 then
		GameTooltip:AddDoubleLine("Ready to fill from bags", ("%d crate%s (%d Favor)"):format(sum.can, sum.can == 1 and "" or "s", sum.favor), 0.8, 0.8, 0.8, 0.3, 1, 0.3)
	end
	local q = S.queue
	if q and not q.finished then
		local left = #q.steps - q.idx + 1
		GameTooltip:AddDoubleLine("Shopping list", ("%d item%s left"):format(left, left == 1 and "" or "s"), 0.8, 0.8, 0.8, 1, 0.82, 0)
	end
	GameTooltip:AddDoubleLine("Prices", ns.db.lastScan and (ns.Age(ns.db.lastScan) .. " old") or "not scanned yet", 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffffffClick|r  open / close", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffffffRight-click|r  what your bags can fill", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffffffDrag|r  move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.MinimapInit()
	icon:SetTexture(AddonIcon())
	if ns.db.minimap.angle == nil then ns.db.minimap.angle = DEFAULT_ANGLE end
	Place()
	button:SetShown(not ns.db.minimap.hide)
end

function ns.SetMinimapShown(show)
	ns.db.minimap.hide = not show
	button:SetShown(show and true or false)
	if show then
		Place()
		ns.Print("Minimap button shown.")
	else
		ns.Print("Minimap button hidden. /crates minimap on brings it back; /crates opens the window.")
	end
end
