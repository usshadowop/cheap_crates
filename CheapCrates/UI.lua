--[[
	Cheap Crates - the window.

	  [Scan]  status                      [x] Use bag items  [ ] Best fill only  [x] Scroll = BUY
	  [Crates] [Shopping list]                                        Merchant's Favor: 123
	  Crate             Fill with         Crate    Fill    Total  Favor  Per Favor
	  ...rows (Buy button on each)...
	  Favor needed: [ 200 ] [Plan]   summary of the cheapest plan
	  [ BUY 20 Silverleaf ] [Skip] [Cancel]   current step
]]

local _, ns = ...
local S = ns.S

local W = 740
local ROW_H = 18
local ROWS = 14
local ROW_Y = -98
local H = 432

local COLS = {
	{ key = "name", x = 10, w = 184, align = "LEFT" },
	{ key = "fill", x = 198, w = 150, align = "LEFT" },
	{ key = "crate", x = 352, w = 62, align = "RIGHT" },
	{ key = "fillc", x = 418, w = 62, align = "RIGHT" },
	{ key = "total", x = 484, w = 68, align = "RIGHT" },
	{ key = "favor", x = 556, w = 44, align = "RIGHT" },
	{ key = "per", x = 604, w = 64, align = "RIGHT" },
}
local HEADERS = {
	crates = { name = "Crate", fill = "Fill with (any one)", crate = "Crate", fillc = "Fill", total = "Total", favor = "Favor", per = "Per Favor" },
	shop = { name = "Item", fill = "Buy", crate = "Owned", fillc = "", total = "Planned", favor = "Status", per = "Paid" },
	bags = { name = "Crate", fill = "Fill materials (bags + bank)", crate = "Crates", fillc = "Bundles", total = "Can fill", favor = "Favor", per = "Missing" },
}
local SORTABLE = { name = "name", total = "total", favor = "favor", per = "per" }

local function Tip(widget, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Age(t)
	if not t then return "never" end
	local d = math.max(0, time() - t)
	if d < 90 then return d .. "s" end
	if d < 5400 then return math.floor(d / 60 + 0.5) .. "m" end
	if d < 129600 then return math.floor(d / 3600 + 0.5) .. "h" end
	return math.floor(d / 86400 + 0.5) .. "d"
end
ns.Age = Age

-- "45 in bags, 12 in bank"
local function OwnedText(bags, bank)
	if bags > 0 and bank > 0 then return ("%d in bags, %d in bank"):format(bags, bank) end
	if bank > 0 then return ("%d in bank"):format(bank) end
	return ("%d in bags"):format(bags)
end
ns.OwnedText = OwnedText

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "CheapCratesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
ns.frame = frame
frame:SetSize(W, H)
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:Hide()
if frame.SetBackdrop then
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.88)
end
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	ns.db.pos = { point, relPoint, x, y }
end)
if UISpecialFrames then table.insert(UISpecialFrames, "CheapCratesFrame") end -- Escape closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Cheap Crates")

local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
subtitle:SetText("Waylaid Crates by cost per Merchant's Favor")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

-- toolbar ------------------------------------------------------------------------------------

local scanBtn = CreateFrame("Button", "CheapCratesScanButton", frame, "UIPanelButtonTemplate")
scanBtn:SetSize(76, 22)
scanBtn:SetPoint("TOPLEFT", 10, -30)
scanBtn:SetText("Scan")
scanBtn:SetScript("OnClick", function()
	if S.scan then ns.StopScan() else ns.StartScan(IsShiftKeyDown() and "full" or "quick") end
end)
Tip(scanBtn, function()
	if not S.ahOpen then return "Open the auction house to scan." end
	return "Click: quick scan, a few seconds. The lowest price of all 126 crates and materials in two requests, then exact prices for the items that decide the top 10.\n\nShift-click: full scan, every listing of every item (about a minute: the server allows ~100 requests a minute).\n\nClick again to stop."
end)

local scanText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scanText:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
scanText:SetWidth(230)
scanText:SetJustifyH("LEFT")

local function Check(name, label, x, tip, onClick)
	local cb = CreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	cb:SetPoint("TOPLEFT", x, -30)
	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 0, 0)
	fs:SetText(label)
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	Tip(cb, tip)
	cb.label = fs
	return cb
end

local bagsCheck = Check("CheapCratesBagsCheck", "Use bags + bank", 352,
	"Count crates and fill materials you already own, in your bags and your bank. What you own is used first and costs nothing, so a bundle you already hold makes that crate only cost the crate, and the planner buys only what you are missing (the shopping list says what to take out of the bank). /crates bank off counts your bags only.",
	function(on) ns.db.useBags = on; ns.UpdateUI(true) end)
local bestCheck = Check("CheapCratesBestCheck", "Best fill only", 472,
	"Show only the cheapest bundle for each crate instead of every crate + bundle combination.",
	function(on) ns.db.bestOnly = on; ns.UpdateUI(true) end)
local wheelCheck = Check("CheapCratesWheelCheck", "Scroll = BUY", 588,
	"While a shopping list is active at the auction house, every mouse wheel tick presses BUY (over the game world, this window, or anything that does not scroll). One tick = one purchase. The wheel never accepts a price that rose above the plan: that needs a click. The wheel goes back to normal when the list is done or the auction house closes.",
	function(on) ns.SetWheel(on) end)

-- tabs ---------------------------------------------------------------------------------------

local function Tab(text, view, x, width)
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetPoint("TOPLEFT", x, -58)
	b:SetText(text)
	b:SetScript("OnClick", function() ns.db.view = view; ns.offset = 0; ns.UpdateUI(true) end)
	return b
end
local cratesTab = Tab("Crates", "crates", 10, 80)
local shopTab = Tab("Shopping list", "shop", 92, 116)
local bagsTab = Tab("Bags & bank", "bags", 210, 112)
Tip(bagsTab, "How many crates you can fill with the crates and fill materials in your bags and bank (and how many right now: filling needs the items in your bags).")

local favorText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
favorText:SetPoint("TOPRIGHT", -14, -62)
favorText:SetJustifyH("RIGHT")

local viewHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
viewHint:SetPoint("LEFT", bagsTab, "RIGHT", 10, 0)
viewHint:SetWidth(214)
viewHint:SetJustifyH("LEFT")

-- column headers -----------------------------------------------------------------------------

local headers = {}
for _, col in ipairs(COLS) do
	local h = CreateFrame("Button", nil, frame)
	h:SetSize(col.w, 16)
	h:SetPoint("TOPLEFT", col.x + 8 - 8, -82)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	h.text:SetAllPoints()
	h.text:SetJustifyH(col.align)
	h.key = col.key
	h:SetScript("OnClick", function(self)
		if ns.db.view ~= "crates" or not SORTABLE[self.key] then return end
		local k = SORTABLE[self.key]
		if ns.db.sortKey == k then ns.db.sortDesc = not ns.db.sortDesc else ns.db.sortKey, ns.db.sortDesc = k, false end
		ns.UpdateUI(true)
	end)
	headers[col.key] = h
end

-- rows ---------------------------------------------------------------------------------------

local rows = {}
ns.rows = rows

local function RowTooltip(row)
	local d = row.data
	if not d then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if d.kind == "combo" then
		local c = d.combo.crate
		GameTooltip:AddLine(c.name)
		GameTooltip:AddDoubleLine("Type", ("%s %s (%s goods)"):format(c.tier, c.cat, c.kind == "crafted" and "crafted" or "raw"), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Merchant's Favor", tostring(d.combo.favor) .. (d.combo.favorEst and " (estimated)" or ""), 0.8, 0.8, 0.8, 1, 1, 1)
		local lr, lg = 1, 1
		if ns.PlayerLevel() < c.level then lr, lg = 1, 0.3 end
		GameTooltip:AddDoubleLine("Requires level", tostring(c.level), 0.8, 0.8, 0.8, lr, lg, lg)
		local cl = d.combo.crateLadder
		local b = ns.db.book[c.id]
		local crateLine
		local cBags, cBank = ns.ItemCounts(c.id)
		if cl.have > 0 then crateLine = OwnedText(cBags, cBank)
		elseif d.combo.crateCost then crateLine = ns.CoinsFull(d.combo.crateCost) .. ((b and b.listed) and ("  (%d listed)"):format(b.listed) or "")
		elseif d.combo.crateMissing == "unscanned" then crateLine = "not scanned"
		else crateLine = "|cffff4444none listed|r" end
		GameTooltip:AddDoubleLine("Crate", crateLine, 0.8, 0.8, 0.8, 1, 1, 1)
		if d.combo.ownedBundles > 0 then
			GameTooltip:AddDoubleLine("Your materials fill", ("%d of these (%d from your bags alone)"):format(d.combo.ownedBundles, d.combo.bagBundles),
				0.8, 0.8, 0.8, 0.3, 1, 0.3)
		end
		if cBags + cBank > 0 and cl.have == 0 then
			GameTooltip:AddDoubleLine("Crates you own", OwnedText(cBags, cBank), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Fill with any one of:", 1, 0.82, 0)
		for _, r in ipairs(ns.lastCombos or {}) do
			if r.crate == c then
				local fb = ns.db.book[r.fill.item]
				local left = ("%d %s"):format(r.fill.qty, ns.ItemName(r.fill.item))
				local right
				if r.fillLadder.have >= r.fill.qty then right = "|cff00ff00owned|r"
				elseif r.fillCost then right = ns.CoinsFull(r.fillCost)
				elseif r.fillMissing == "unscanned" then right = "not scanned"
				elseif r.fillMissing == "short" then right = ("only %d listed"):format(fb and fb.listed or 0)
				else right = "none listed" end
				local fBags, fBank = ns.ItemCounts(r.fill.item)
				if fBags + fBank > 0 then left = left .. "  |cffaaaaaa(" .. OwnedText(fBags, fBank) .. ")|r" end
				if r.stackBlocked then left = left .. (" |cffff4444stacks to %d|r"):format(r.stack or 0) end
				local cr, cg, cb = 1, 1, 1
				if r == d.combo then cr, cg, cb = 0.3, 1, 0.3 end
				GameTooltip:AddDoubleLine(left, right, cr, cg, cb, 1, 1, 1)
			end
		end
		if d.combo.stackBlocked then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("%s stacks to %d, fewer than the %d this bundle needs. Crates are reported to need the whole bundle in one stack, so this bundle is left out of plans (/crates stackcheck off to allow it)."):format(ns.ItemName(d.combo.fill.item), d.combo.stack or 0, d.combo.fill.qty), 1, 0.4, 0.4, true)
		end
		if d.combo.levelBlocked then
			GameTooltip:AddLine(("You need level %d for this crate, so plans leave it out (/crates levels off to include it)."):format(c.level), 1, 0.4, 0.4, true)
		end
		if d.combo.est then
			GameTooltip:AddLine("~ = at least this much: the lowest listed price times the bundle size. Some of the bundle may sit on dearer listings. Buy and Plan read the exact price first.", 0.7, 0.7, 0.7, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click Buy to put this crate and bundle on the shopping list.", 0.7, 0.7, 0.7, true)
	elseif d.kind == "step" then
		local st = d.step
		GameTooltip:AddLine(ns.ItemName(st.itemID))
		GameTooltip:AddDoubleLine("To buy", tostring(st.qty), 0.8, 0.8, 0.8, 1, 1, 1)
		if (st.have or 0) > 0 then
			local sb, sk = ns.ItemCounts(st.itemID)
			GameTooltip:AddDoubleLine("Already own", ("%d  (%s)"):format(st.have, OwnedText(sb, sk)), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Planned", ns.CoinsFull(st.planned), 0.8, 0.8, 0.8, 1, 1, 1)
		if st.budget ~= st.planned then GameTooltip:AddDoubleLine("Accepted", ns.CoinsFull(st.budget), 0.8, 0.8, 0.8, 1, 1, 1) end
		if st.got > 0 then GameTooltip:AddDoubleLine("Bought", ("%d for %s"):format(st.got, ns.CoinsFull(st.paid)), 0.8, 0.8, 0.8, 1, 1, 1) end
		if st.note then GameTooltip:AddLine(st.note, 1, 0.82, 0, true) end
	elseif d.kind == "group" then
		local g = d.group
		GameTooltip:AddLine(("%d x %s"):format(g.count, g.crate.name))
		GameTooltip:AddLine(("Filled with %d %s each"):format(g.fill.qty, ns.ItemName(g.fill.item)), 1, 1, 1)
		GameTooltip:AddDoubleLine("Favor", tostring(g.favor), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Cost", ns.CoinsFull(g.cost), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Per Favor", ns.CoinsFull(g.cost / math.max(1, g.favor)), 0.8, 0.8, 0.8, 1, 1, 1)
	elseif d.kind == "bag" then
		local b = d.bag
		local c = b.crate
		GameTooltip:AddLine(c.name)
		GameTooltip:AddDoubleLine("Empty crates", b.crates > 0 and OwnedText(b.crates - b.cratesBank, b.cratesBank) or "none", 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Fill materials:", 1, 0.82, 0)
		if #b.parts == 0 then GameTooltip:AddLine("none", 0.6, 0.6, 0.6) end
		for _, p in ipairs(b.parts) do
			local right
			if p.blocked then right = "|cffff4444bundle is bigger than a stack|r"
			elseif p.n > 0 then right = ("%d bundle%s"):format(p.n, p.n == 1 and "" or "s") .. ((p.have % p.fill.qty > 0) and (" + %d spare"):format(p.have % p.fill.qty) or "")
			else right = ("%d more for a bundle"):format(p.fill.qty - p.have) end
			GameTooltip:AddDoubleLine(("%d %s (bundle of %d)  |cffaaaaaa%s|r"):format(p.have, ns.ItemName(p.fill.item), p.fill.qty, OwnedText(p.bags, p.bank)), right, 1, 1, 1, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Can fill (bags + bank)", ("%d (%d Favor)"):format(b.can, b.favor), 0.8, 0.8, 0.8, 0.3, 1, 0.3)
		GameTooltip:AddDoubleLine("Right now, from your bags", tostring(b.canNow), 0.8, 0.8, 0.8, 1, 1, 1)
		if b.can > b.canNow then GameTooltip:AddLine("Take the rest out of your bank to fill them: filling needs the items in your bags.", 0.4, 0.8, 1, true) end
		if b.levelBlocked then GameTooltip:AddLine(("Needs level %d."):format(c.level), 1, 0.4, 0.4) end
		if b.spareBundles > 0 then
			GameTooltip:AddLine(("%d bundle%s without a crate: Buy gets the crate%s."):format(b.spareBundles, b.spareBundles == 1 and "" or "s", b.spareBundles == 1 and "" or "s"), 0.7, 0.7, 0.7, true)
		elseif b.spareCrates > 0 then
			GameTooltip:AddLine(("%d crate%s without a bundle: Buy gets the cheapest bundle for each."):format(b.spareCrates, b.spareCrates == 1 and "" or "s"), 0.7, 0.7, 0.7, true)
		end
	else
		GameTooltip:Hide()
		return
	end
	GameTooltip:Show()
end

local function GetRow(i)
	local row = rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, frame)
	row:SetSize(W - 34, ROW_H)
	row:SetPoint("TOPLEFT", 8, ROW_Y - (i - 1) * ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.cols = {}
	for _, col in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", col.x - 8, 0)
		fs:SetWidth(col.w)
		fs:SetJustifyH(col.align)
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		row.cols[col.key] = fs
	end
	row.buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.buy:SetSize(40, 16)
	row.buy:SetPoint("RIGHT", -2, 0)
	row.buy:SetText("Buy")
	row.buy:SetScript("OnClick", function(self)
		local d = self:GetParent().data
		if d and d.kind == "combo" then ns.BuyCombo(d.combo)
		elseif d and d.kind == "bag" then ns.BuyMissing(d.bag) end
	end)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = row
	return row
end
for i = 1, ROWS do GetRow(i) end

-- scroll bar ---------------------------------------------------------------------------------

ns.offset = 0
local slider = CreateFrame("Slider", "CheapCratesSlider", frame)
slider:SetOrientation("VERTICAL")
slider:SetWidth(14)
slider:SetPoint("TOPRIGHT", -8, ROW_Y)
slider:SetHeight(ROWS * ROW_H)
slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
if slider.GetThumbTexture and slider:GetThumbTexture() then slider:GetThumbTexture():SetSize(14, 22) end
local sliderBg = slider:CreateTexture(nil, "BACKGROUND")
sliderBg:SetAllPoints()
sliderBg:SetColorTexture(1, 1, 1, 0.08)
slider:SetMinMaxValues(0, 0)
slider:SetValueStep(1)
if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
slider:SetValue(0)
local syncing = false
slider:SetScript("OnValueChanged", function(self, value)
	if syncing then return end
	local v = math.floor((value or 0) + 0.5)
	if v ~= ns.offset then ns.offset = v; ns.UpdateUI(true) end
end)

frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(self, delta)
	if ns.WheelActive() then ns.Press("wheel"); return end
	ns.offset = math.max(0, ns.offset - (delta or 0) * 3)
	ns.UpdateUI(true)
end)

-- goal row -----------------------------------------------------------------------------------

local goalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
goalLabel:SetPoint("TOPLEFT", 12, -364)
goalLabel:SetText("Favor needed:")

local goalEdit = CreateFrame("EditBox", "CheapCratesGoalEdit", frame, "InputBoxTemplate")
goalEdit:SetSize(56, 20)
goalEdit:SetPoint("TOPLEFT", 104, -359)
goalEdit:SetAutoFocus(false)
goalEdit:SetNumeric(true)
goalEdit:SetMaxLetters(6)
goalEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ns.PlanGoal(tonumber(self:GetText())) end)
goalEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
Tip(goalEdit, "How much Merchant's Favor you need. Plan finds the cheapest mix of crates and bundles that adds up to at least this much, using what is in your bags first when \"Use bag items\" is ticked, and turns it into a shopping list.")

local planBtn = CreateFrame("Button", "CheapCratesPlanButton", frame, "UIPanelButtonTemplate")
planBtn:SetSize(56, 22)
planBtn:SetPoint("LEFT", goalEdit, "RIGHT", 6, 0)
planBtn:SetText("Plan")
planBtn:SetScript("OnClick", function() goalEdit:ClearFocus(); ns.PlanGoal(tonumber(goalEdit:GetText())) end)

local planText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
planText:SetPoint("LEFT", planBtn, "RIGHT", 10, 0)
planText:SetWidth(W - 250)
planText:SetJustifyH("LEFT")

-- buy bar ------------------------------------------------------------------------------------

local buyBtn = CreateFrame("Button", "CheapCratesBuyButton", frame, "UIPanelButtonTemplate")
buyBtn:SetSize(240, 28)
buyBtn:SetPoint("TOPLEFT", 10, -392)
buyBtn:SetText("BUY")
buyBtn:SetScript("OnClick", function() ns.Press("click") end)
Tip(buyBtn, "Buys the next item on the shopping list. One click, key press (Key Bindings > AddOns > Cheap Crates) or wheel tick per purchase. If the price rose above the plan by more than your tolerance (" .. "/crates tolerance" .. "), the first click shows the new price and the next click accepts it.")

local skipBtn = CreateFrame("Button", "CheapCratesSkipButton", frame, "UIPanelButtonTemplate")
skipBtn:SetSize(56, 22)
skipBtn:SetPoint("LEFT", buyBtn, "RIGHT", 6, 0)
skipBtn:SetText("Skip")
skipBtn:SetScript("OnClick", function() ns.SkipStep() end)
Tip(skipBtn, "Skip this item and go to the next one. Skipping a crate also drops the fill materials that were meant for it.")

local cancelBtn = CreateFrame("Button", "CheapCratesCancelButton", frame, "UIPanelButtonTemplate")
cancelBtn:SetSize(64, 22)
cancelBtn:SetPoint("LEFT", skipBtn, "RIGHT", 4, 0)
cancelBtn:SetText("Cancel")
cancelBtn:SetScript("OnClick", function() ns.CancelQueue() end)

local stepText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stepText:SetPoint("LEFT", cancelBtn, "RIGHT", 10, 0)
stepText:SetWidth(W - 400)
stepText:SetJustifyH("LEFT")

local glow = frame:CreateTexture(nil, "BACKGROUND")
glow:SetPoint("TOPLEFT", buyBtn, "TOPLEFT", -4, 4)
glow:SetPoint("BOTTOMRIGHT", buyBtn, "BOTTOMRIGHT", 4, -4)
glow:SetColorTexture(0, 0.8, 0, 0.35)
glow:Hide()

-------------------------------------------------------------------------------
-- Scroll wheel = BUY
-------------------------------------------------------------------------------

-- A wheel tick is a hardware event, so it may run the restricted purchase calls. While a
-- shopping list is active at the auction house, MOUSEWHEELUP/DOWN are override-bound to click
-- this (invisible) button; frames that scroll (lists, chat) still take the wheel first.
local wheelBtn = CreateFrame("Button", "CheapCratesWheelButton", UIParent)
wheelBtn:SetSize(1, 1)
wheelBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
wheelBtn:EnableMouse(false)
wheelBtn:SetScript("OnClick", function() ns.Press("wheel") end)

local bindOwner = CreateFrame("Frame")

-- only while the window is open: a hidden shopping list never buys on a stray scroll
function ns.WheelActive()
	return ns.db and ns.db.wheel and S.ahOpen and frame:IsShown() and S.queue ~= nil and not S.queue.finished
end

function ns.ApplyWheelBinding()
	if not SetOverrideBindingClick or not ClearOverrideBindings then return end
	if InCombatLockdown and InCombatLockdown() then return end
	ClearOverrideBindings(bindOwner)
	if ns.WheelActive() then
		SetOverrideBindingClick(bindOwner, true, "MOUSEWHEELDOWN", "CheapCratesWheelButton")
		SetOverrideBindingClick(bindOwner, true, "MOUSEWHEELUP", "CheapCratesWheelButton")
	end
end

function ns.SetWheel(on)
	ns.db.wheel = on and true or false
	wheelCheck:SetChecked(ns.db.wheel)
	ns.ApplyWheelBinding()
	ns.Print("Scroll = BUY %s.", ns.db.wheel and "on: while a shopping list is active at the auction house, each wheel tick buys the next item" or "off")
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function SortCombos(list)
	local key, desc = ns.db.sortKey or "per", ns.db.sortDesc
	local function val(r)
		if key == "name" then return r.crate.name .. ":" .. ns.ItemName(r.fill.item) end
		if key == "favor" then return r.favor end
		return r[key]
	end
	table.sort(list, function(a, b)
		-- usable rows first, then priced but blocked, then unpriced
		local ra = a.eligible and 0 or (a.total and 1 or 2)
		local rb = b.eligible and 0 or (b.total and 1 or 2)
		if ra ~= rb then return ra < rb end
		local va, vb = val(a), val(b)
		if va == nil or vb == nil then
			if va ~= vb then return va ~= nil end
			return a.crate.name < b.crate.name
		end
		if va ~= vb then
			if desc then return va > vb end
			return va < vb
		end
		return (a.total or 0) < (b.total or 0)
	end)
end

local function CostCell(cost, ladder, need, missing, itemID)
	-- covered by what you own: say where it is
	if ladder.have >= need then
		if ns.BagCount(itemID) >= need then return "|cff00ff00bags|r" end
		return "|cff66ccffbank|r"
	end
	-- a key-pass price is exact for one unit and a floor for more
	if cost then
		local s = ns.Coins(cost)
		if ladder.est and need - ladder.have > 1 then s = "~" .. s end
		return s
	end
	if missing == "unscanned" then return "|cff888888?|r" end
	if missing == "short" then return "|cffff8800short|r" end
	return "|cffff4444none|r"
end

local function BuildData()
	local data = {}
	if ns.db.view == "crates" then
		local list = ns.Combos()
		ns.lastCombos = list
		local shown = {}
		for _, r in ipairs(list) do
			if not ns.db.bestOnly or r.bestOfCrate then shown[#shown + 1] = r end
		end
		SortCombos(shown)
		for _, r in ipairs(shown) do data[#data + 1] = { kind = "combo", combo = r } end
	elseif ns.db.view == "bags" then
		local rows, sum = ns.BagFill()
		local text
		if #rows == 0 then
			text = "|cff888888No Waylaid Crates or fill materials in your bags or bank.|r"
		else
			text = ("|cffffd100Can fill:|r |cff00ff00%d crate%s|r (%d Favor), %d from your bags right now"):format(sum.can, sum.can == 1 and "" or "s", sum.favor, sum.canNow)
			if sum.spareBundles > 0 then text = text .. ("   |cffaaaaaa%d bundle%s need a crate|r"):format(sum.spareBundles, sum.spareBundles == 1 and "" or "s") end
			if sum.spareCrates > 0 then text = text .. ("   |cffaaaaaa%d crate%s need a bundle|r"):format(sum.spareCrates, sum.spareCrates == 1 and "" or "s") end
		end
		data[1] = { kind = "text", text = text }
		for _, r in ipairs(rows) do data[#data + 1] = { kind = "bag", bag = r } end
		if #rows > 0 then data[#data + 1] = { kind = "text", text = "|cff66ccff* some in your bank|r  |cff888888(take them out to fill: filling needs the items in your bags)|r" } end
	else
		local q = S.queue
		if not q then
			data[1] = { kind = "text", text = "|cff888888No shopping list. Press Buy on a crate in the Crates tab, or enter the Favor you need below and press Plan.|r" }
		else
			if q.plan and #q.plan.groups > 0 then
				data[#data + 1] = { kind = "text", text = ("|cffffd100Crates to fill|r  (%d crate%s, %d Favor)"):format(#q.plan.units, #q.plan.units == 1 and "" or "s", q.plan.favor) }
				for _, g in ipairs(q.plan.groups) do data[#data + 1] = { kind = "group", group = g } end
			end
			if q.plan and q.plan.fromBank and #q.plan.fromBank > 0 then
				data[#data + 1] = { kind = "text", text = "|cffffd100Take from your bank|r  (already yours, so not bought)" }
				for _, f in ipairs(q.plan.fromBank) do
					data[#data + 1] = { kind = "text", text = ("    |cff66ccff%d x %s|r"):format(f.qty, ns.ItemName(f.itemID)) }
				end
			end
			data[#data + 1] = { kind = "text", text = #q.steps > 0 and "|cffffd100To buy|r  (one BUY press each)" or "|cff00ff00Nothing to buy: you already have everything in your bags.|r" }
			for i, st in ipairs(q.steps) do data[#data + 1] = { kind = "step", step = st, index = i, current = (i == q.idx and not q.finished) } end
		end
	end
	return data
end

local STATUS = {
	pending = "|cff888888waiting|r", checking = "|cffccccccchecking|r", ready = "|cff00ff00ready|r",
	price = "|cffffff00price!|r", buying = "|cffffffffbuying|r", done = "|cff00ff00done|r",
	skipped = "|cff888888skipped|r", failed = "|cffff4444failed|r",
}

local function DrawRow(row, d)
	row.data = d
	local c = row.cols
	for _, col in ipairs(COLS) do c[col.key]:SetText(""); c[col.key]:SetWidth(col.w) end
	row.bg:SetColorTexture(0, 0, 0, 0)
	row.buy:Hide()
	if d.kind == "combo" then
		local r = d.combo
		local nameColor = r.levelBlocked and "|cff888888" or (r.cheapest and "|cff00ff00" or "|cffffffff")
		-- (N): how many of this crate the fill materials in your bags and bank can fill
		c.name:SetText(nameColor .. r.crate.short .. "|r" .. (r.ownedBundles > 0 and (" |cff00ff00(%d)|r"):format(r.ownedBundles) or ""))
		local fillName = ("%d %s"):format(r.fill.qty, ns.ItemName(r.fill.item))
		if r.stackBlocked then fillName = "|cffff4444" .. fillName .. "|r" end
		c.fill:SetText(fillName)
		c.crate:SetText(CostCell(r.crateCost, r.crateLadder, 1, r.crateMissing, r.crate.id))
		c.fillc:SetText(CostCell(r.fillCost, r.fillLadder, r.fill.qty, r.fillMissing, r.fill.item))
		c.total:SetText(r.total and ((r.est and "~" or "") .. ns.Coins(r.total)) or "-")
		c.favor:SetText(tostring(r.favor) .. (r.favorEst and "|cff888888*|r" or ""))
		c.per:SetText(r.per and ns.Coins(r.per) or "-")
		row.buy:SetShown(true)
		row.buy:SetEnabled(r.total ~= nil)
		if r.cheapest then row.bg:SetColorTexture(0, 0.6, 0, 0.18)
		elseif r.bestOfCrate and not ns.db.bestOnly and r.eligible then row.bg:SetColorTexture(1, 1, 1, 0.04) end
	elseif d.kind == "group" then
		local g = d.group
		c.name:SetWidth(470)
		c.name:SetText(("  %dx %s  |cffaaaaaawith %d %s each|r"):format(g.count, g.crate.short, g.fill.qty, ns.ItemName(g.fill.item)))
		c.total:SetText(ns.Coins(g.cost))
		c.favor:SetText("+" .. g.favor)
		c.per:SetText("")
	elseif d.kind == "bag" then
		local b = d.bag
		local color = b.levelBlocked and "|cff888888" or (b.can > 0 and "|cff00ff00" or "|cffffffff")
		c.name:SetText(color .. b.crate.short .. "|r")
		local parts = {}
		for _, p in ipairs(b.parts) do
			local name = ns.ItemName(p.fill.item)
			if p.blocked then parts[#parts + 1] = "|cffff4444" .. name .. "|r"
			elseif p.n > 0 then
				local fromBank = p.n - p.nBags
				parts[#parts + 1] = ("%dx %s"):format(p.n, name) .. (fromBank > 0 and (" |cff66ccff(%d bank)|r"):format(fromBank) or "")
			else parts[#parts + 1] = ("|cff888888%d/%d %s|r"):format(p.have, p.fill.qty, name) end
		end
		c.fill:SetText(#parts > 0 and table.concat(parts, ", ") or "|cff888888none|r")
		c.crate:SetText(tostring(b.crates) .. (b.cratesBank > 0 and "|cff66ccff*|r" or ""))
		c.fillc:SetText(tostring(b.bundles) .. (b.bundlesBank > 0 and "|cff66ccff*|r" or ""))
		c.total:SetText(b.can > 0 and ("|cff00ff00%d|r"):format(b.can) or "0")
		c.favor:SetText(b.favor > 0 and tostring(b.favor) or "")
		if b.spareBundles > 0 then
			c.per:SetText(("+%d crate%s"):format(b.spareBundles, b.spareBundles == 1 and "" or "s"))
		elseif b.spareCrates > 0 then
			c.per:SetText(("+%d bundle%s"):format(b.spareCrates, b.spareCrates == 1 and "" or "s"))
		end
		row.buy:SetShown(true)
		row.buy:SetEnabled(not b.levelBlocked and (b.spareBundles > 0 or b.spareCrates > 0))
		if b.can > 0 then row.bg:SetColorTexture(0, 0.6, 0, 0.12) end
	elseif d.kind == "step" then
		local st = d.step
		local crate = ns.CRATE_BY_ID[st.itemID]
		c.name:SetText((crate and "Crate: " .. crate.short) or ns.ItemName(st.itemID))
		c.fill:SetText(tostring(st.qty) .. ((st.got > 0 and st.got < st.qty) and (" (%d bought)"):format(st.got) or ""))
		c.crate:SetText((st.have or 0) > 0 and tostring(st.have) or "")
		c.total:SetText(ns.Coins(st.budget))
		c.favor:SetText(STATUS[st.status] or st.status)
		c.per:SetText(st.paid > 0 and ns.Coins(st.paid) or "")
		if d.current then row.bg:SetColorTexture(1, 0.82, 0, 0.15) end
	else
		c.name:SetWidth(W - 60)
		c.name:SetText(d.text or "")
	end
end

local lastDraw, dirty = 0, false

local function Draw()
	lastDraw, dirty = GetTime(), false
	local db = ns.db
	if not db then return end
	local view = db.view or "crates"

	bagsCheck:SetChecked(db.useBags)
	bestCheck:SetChecked(db.bestOnly)
	wheelCheck:SetChecked(db.wheel)
	cratesTab:SetEnabled(view ~= "crates")
	shopTab:SetEnabled(view ~= "shop")
	bagsTab:SetEnabled(view ~= "bags")
	local _, bagSum = ns.BagFill()
	bagsTab:SetText(bagSum.can > 0 and ("Bags & bank (%d)"):format(bagSum.can) or "Bags & bank")
	bagsCheck.label:SetText(db.useBank == false and "Use bag items" or "Use bags + bank")
	local q = S.queue
	shopTab:SetText((q and not q.finished) and ("Shopping list (%d)"):format(#q.steps - q.idx + 1) or "Shopping list")

	-- scan status
	scanBtn:SetText(S.scan and "Stop" or "Scan")
	scanBtn:SetEnabled(S.ahOpen and not (q and not q.finished) or S.scan ~= nil)
	local progress = ns.ScanProgress()
	if progress then
		scanText:SetText("|cffffff00" .. progress .. "|r")
	elseif db.lastScan then
		scanText:SetText(("Prices from %s ago"):format(Age(db.lastScan)) .. (S.ahOpen and "" or "  |cff888888(AH closed)|r"))
	else
		scanText:SetText(S.ahOpen and "Not scanned yet: press Scan" or "|cff888888Open the auction house and press Scan|r")
	end

	local favor = ns.CurrentFavor()
	favorText:SetText(favor and ("Merchant's Favor: |cffffffff%d|r"):format(favor) or "")

	if view == "crates" then
		viewHint:SetText(ns.db.bestOnly and "Cheapest bundle per crate" or "Every crate + bundle, cheapest per Favor first")
	elseif view == "bags" then
		viewHint:SetText("Buy gets what is missing to pair them up")
	else
		viewHint:SetText(q and q.title or "")
	end

	for _, col in ipairs(COLS) do
		local text = HEADERS[view][col.key] or ""
		if view == "crates" and SORTABLE[col.key] == (db.sortKey or "per") then
			text = text .. (db.sortDesc and " v" or " ^")
		end
		headers[col.key].text:SetText(text)
	end

	-- rows
	local data = BuildData()
	local maxOffset = math.max(0, #data - ROWS)
	if ns.offset > maxOffset then ns.offset = maxOffset end
	if view == "shop" and q and not q.finished and ns.followedIdx ~= q.idx then
		-- bring the current step into view when the list moves on (scrolling stays free otherwise)
		ns.followedIdx = q.idx
		for i, d in ipairs(data) do
			if d.current then
				if i <= ns.offset then ns.offset = math.max(0, i - 2)
				elseif i > ns.offset + ROWS then ns.offset = math.min(maxOffset, i - ROWS + 1) end
				break
			end
		end
	end
	for i = 1, ROWS do
		local row = rows[i]
		local d = data[ns.offset + i]
		if d then DrawRow(row, d); row:Show() else row.data = nil; row:Hide() end
	end
	syncing = true
	slider:SetMinMaxValues(0, maxOffset)
	slider:SetValue(ns.offset)
	syncing = false
	slider:SetShown(maxOffset > 0)

	-- plan summary
	if q and q.plan and q.plan.target then
		local p = q.plan
		if p.short then
			planText:SetText(("|cffff4444Only %d Favor can be bought right now|r (%d crates, %s)."):format(p.favor, #p.units, ns.Coins(p.cost)))
		else
			planText:SetText(("%d Favor from %d crate%s for %s  (%s per Favor)"):format(p.favor, #p.units, #p.units == 1 and "" or "s",
				ns.Coins(p.cost), ns.Coins(p.cost / math.max(1, p.favor))))
		end
	elseif q and q.plan then
		planText:SetText(("Shopping list: %s"):format(q.title or ""))
	else
		planText:SetText("|cff888888Type the Favor you need and press Plan for the cheapest way to get it.|r")
	end

	-- buy bar
	local st = ns.CurrentStep()
	buyBtn:SetText(ns.BuyButtonText())
	buyBtn:SetEnabled(st ~= nil and S.ahOpen and (st.status == "ready" or st.status == "price"))
	skipBtn:SetEnabled(st ~= nil and st.status ~= "buying")
	cancelBtn:SetEnabled(q ~= nil)
	if st then
		local stepNo = ("|cff888888%d/%d|r  "):format(q.idx, #q.steps)
		stepText:SetText(stepNo .. ns.StepText(st) .. (S.ahOpen and "" or "  |cff888888(open the auction house)|r"))
	elseif q and q.finished then
		stepText:SetText(("|cff00ff00Done.|r Spent %s."):format(ns.Coins(q.spent)))
	else
		stepText:SetText("")
	end
	glow:SetShown(st ~= nil and S.ahOpen and st.status == "ready")
end

-- force = draw now; otherwise at most ~6 times a second
function ns.UpdateUI(force)
	if not frame:IsShown() then dirty = true; return end
	if force or GetTime() - lastDraw > 0.15 then Draw() else dirty = true end
end

function ns.DrawIfDirty()
	if dirty and frame:IsShown() and GetTime() - lastDraw > 0.15 then Draw() end
end

frame:SetScript("OnShow", function() ns.followedIdx = nil; Draw(); ns.ApplyWheelBinding() end)
frame:SetScript("OnHide", function() ns.ApplyWheelBinding() end)

function ns.Show()
	frame:ClearAllPoints()
	if ns.db.pos then
		frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
	elseif AuctionHouseFrame and S.ahOpen then
		frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
	end
	frame:Show()
	Draw()
end

function ns.Hide() frame:Hide() end

function ns.Toggle()
	if frame:IsShown() then frame:Hide() else ns.Show() end
end
function CheapCrates_Toggle() if ns.db then ns.Toggle() end end
