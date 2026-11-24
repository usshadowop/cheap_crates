-- Minimal WoW client stub for exercising CheapCrates headlessly under Lua 5.1.
-- Adapted from the Item Sniper addon's harness; adds bag counts, stack sizes,
-- the Merchant's Favor currency and player level.
-- Fakes: frames/events/scripts, a throttled auction house with commodity + item search,
-- commodity quotes, PlaceBid, and the hardware-event rule for restricted functions.

local W = {}
_G.WOWSTUB = W

W.now = 0
W.frames = {}
W.chat = {}
W.hw = false            -- true while simulating a key press / click
W.violations = {}       -- restricted calls made outside a hardware event
W.calls = {}            -- log of auction house calls

function GetTime() return W.now end
function time() return 1700000000 + math.floor(W.now) end
function date(fmt, t) return "d" end
function GetMoney() return W.money or 100000000 end
function InCombatLockdown() return false end
function GetCursorInfo() return W.cursor and W.cursor.kind, W.cursor and W.cursor.id, W.cursor and W.cursor.link end
function ClearCursor() W.cursor = nil end
function PlaySound() W.sounds = (W.sounds or 0) + 1 end
function FlashClientIcon() W.flashes = (W.flashes or 0) + 1 end
function GetMoneyString(c) return string.format("%dg%ds%dc", math.floor(c / 10000), math.floor(c / 100) % 100, c % 100) end
W.bindings = {}
function GetBindingKey(action) for k, a in pairs(W.bindings) do if a == action then return k end end end
function SetBinding(key, action) if action then W.bindings[key] = action else W.bindings[key] = nil end return true end
function GetBuildInfo() return "1.60.1", "70862", "Nov 7 2026", 16001 end
W.meta = {}
C_AddOns = { GetAddOnMetadata = function(_, field) return W.meta[field] or "0.1.0" end }
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
SOUNDKIT = { ALARM_CLOCK_WARNING_3 = 12889, RAID_WARNING = 8959 }
function hooksecurefunc() end
W.whispers = {}
function SendChatMessage(msg, chatType, lang, target)
	restricted_chat = true
	W.calls[#W.calls + 1] = "SendChatMessage"
	if not W.hw then W.violations[#W.violations + 1] = "SendChatMessage" end
	W.whispers[#W.whispers + 1] = { msg = msg, chatType = chatType, target = target }
end
function GetRealmName() return "Forever-Normal" end
function UnitName() return "Tester" end
ChatFontNormal = {}
function IsShiftKeyDown() return W.shift or false end
W.overrides = {}
function SetOverrideBindingClick(owner, prio, key, button) W.overrides[key] = button end
function ClearOverrideBindings(owner) W.overrides = {} end
ChatFontSmall = {}
Enum = {
	AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
	AuctionHouseError = { NotEnoughMoney = 0, HigherBid = 1, ItemNotFound = 4 },
}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) W.chat[#W.chat + 1] = msg; if W.verbose then print("  [chat] " .. msg) end end }
GameTooltip = setmetatable({}, { __index = function() return function() end end })

-- frames ---------------------------------------------------------------------
local Frame = {}
Frame.__index = function(t, k)
	if Frame[k] then return Frame[k] end
	-- widget methods are PascalCase; anything else (entry, icon, _text ...) is a plain field
	if type(k) == "string" and k:match("^%u") then return function() end end
	return nil
end
local function NewRegion()
	return setmetatable({ _text = "" }, {
		__index = function(t, k)
			if k == "SetText" then return function(self, s) self._text = s end end
			if k == "GetText" then return function(self) return self._text end end
			if k == "SetTexture" then return function(self, t) self._texture = t end end
			if k == "GetTexture" then return function(self) return self._texture end end
			return function() end
		end })
end
function CreateFrame(kind, name, parent, template)
	local f = setmetatable({ _scripts = {}, _events = {}, _shown = true, _kind = kind, _name = name, _parent = parent, _text = "" }, Frame)
	if name then _G[name] = f end
	W.frames[#W.frames + 1] = f
	return f
end
function Frame:SetScript(h, fn) self._scripts[h] = fn end
function Frame:GetScript(h) return self._scripts[h] end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
-- like the client: OnShow / OnHide run when the frame actually changes state
function Frame:Show()
	if self._shown then return end
	self._shown = true
	if self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Frame:Hide()
	if not self._shown then return end
	self._shown = false
	if self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Frame:SetShown(b) if b then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:CreateTexture() return NewRegion() end
function Frame:CreateFontString() return NewRegion() end
function Frame:SetText(s) self._text = s end
function Frame:GetText() return self._text end
function Frame:SetChecked(b) self._checked = b end
function Frame:SetEnabled(b) self._enabled = b and true or false end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Frame:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Frame:SetValue(v) self._value = v end
function Frame:GetValue() return self._value or 0 end
function Frame:GetThumbTexture() return nil end
function Frame:GetChecked() return self._checked end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:SetPoint(...) self._point = { ... } end
function Frame:GetWidth() return self._w or 140 end
function Frame:GetHeight() return self._h or 140 end
function Frame:GetCenter() return self._cx or 500, self._cy or 500 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetParent() return self._parent end
function Frame:HasFocus() return false end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
W.cursorX, W.cursorY = 0, 0
function GetCursorPosition() return W.cursorX, W.cursorY end

function W.fire(event, ...)
	for _, f in ipairs(W.frames) do
		if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
	end
end
function W.tick(dt)
	W.now = W.now + (dt or 0.016)
	W.ah.step()
	for _, f in ipairs(W.frames) do
		if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, dt) end
	end
end
function W.run(seconds, dt)
	dt = dt or 0.05
	local n = math.floor(seconds / dt + 0.5)
	for _ = 1, n do W.tick(dt) end
end
function W.press(fn) -- simulate a hardware event
	W.hw = true
	fn()
	W.hw = false
end
function W.slash(msg) SlashCmdList.CHEAPCRATES(msg) end

-- items ---------------------------------------------------------------------
W.items = {
	-- ilvl: the item level the server files listings under. Forever lists commodities under item keys that
	-- carry it (Wool Cloth 15, Silk Cloth 30, seen in game); a level-0 key is a different, empty key.
	-- infoLevel overrides what GetItemInfo reports (default: ilvl).
	[2589] = { name = "Linen Cloth", commodity = true, ilvl = 5 },
	[2592] = { name = "Wool Cloth", commodity = true, sellPrice = 40, ilvl = 15 }, -- live value differs from the built-in 33
	[14131] = { name = "Ritual Belt", equipment = true, ilvl = 25 },
	[4306] = { name = "Silk Cloth", commodity = true, ilvl = 30 },
	[2996] = { name = "WRONG NAME FOR 2996", commodity = true, ilvl = 10 }, -- simulates a stale built-in ID
	[7073] = { name = "Broken Fang" },
	[6948] = { name = "Hearthstone" },
}
W.bags = { [0] = { 6948, 2589 } }
W.bagCount = {}          -- itemID -> units in bags (C_Item.GetItemCount)
W.bankCount = {}         -- itemID -> units in the bank
W.favor = 0
W.level = 60
function UnitLevel() return W.level end
C_CurrencyInfo = { GetCurrencyInfo = function(id) if id == 3402 then return { name = "Merchant's Favor", quantity = W.favor } end end }
UISpecialFrames = {} -- bag 0 holds a Hearthstone and Linen Cloth
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot, itemID = W.bags[bag] and W.bags[bag][slot] } end }
function StaticPopup_Hide(which) W.hiddenPopups = (W.hiddenPopups or 0) + 1 end
C_Container = {
	GetContainerNumSlots = function(bag) return W.bags[bag] and #W.bags[bag] or 0 end,
	GetContainerItemID = function(bag, slot) return W.bags[bag] and W.bags[bag][slot] end,
}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
C_Item = {
	GetItemInfoInstant = function(x) return tonumber(x) end, -- Forever: name lookups return nothing
	GetItemInfo = function(id) local it = W.items[id]; if it then return it.name, "|cffffffff|Hitem:" .. id .. "::::::::::|h[" .. it.name .. "]|h|r", 1, it.infoLevel or it.ilvl or 1, 1, "Trade Goods", "Trade Goods", it.stack or 200, "", 1, it.sellPrice end end,
	-- (item, includeBank, ...): bags, plus the bank when asked
	GetItemCount = function(id, bank) return (W.bagCount[id] or 0) + (bank and W.bankCount[id] or 0) end,
	GetItemIconByID = function() return 1 end,
	RequestLoadItemDataByID = function() end,
}

-- auction house -------------------------------------------------------------
local ah = { listings = {}, results = {}, pending = {}, lastSend = -10, quote = nil, resultsDelay = 0.15, throttle = 0.4 }
W.ah = ah
ah.hasResults = {}

local function restricted(name)
	W.calls[#W.calls + 1] = name
	if not W.hw then W.violations[#W.violations + 1] = name end
end
local function log(name) W.calls[#W.calls + 1] = name end

-- the key the server files an item's listings under; a commodity search for any other key finds nothing
local function serverKey(id)
	local it = W.items[id]
	return { itemID = id, itemLevel = it and it.ilvl or 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end
W.serverKey = serverKey
local function keyStr(k) return k.itemID .. ":" .. (k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0) end
local function commoditySearchHits(key)
	local it = W.items[key.itemID]
	if not (it and it.commodity) then return true end
	return (key.itemLevel or 0) == (it.ilvl or 0) and (key.itemSuffix or 0) == 0
end
ah.searchKey = {} -- itemID -> the key the client last searched with (Refresh* reuses it)

-- listings: commodity -> list of {unitPrice, quantity, owner}; item -> list of {auctionID, buyout, quantity}
function ah.setCommodity(itemID, rows) ah.listings[itemID] = rows end
function ah.setItems(itemID, rows) ah.listings[itemID] = rows end

local function sortedCommodity(itemID, live)
	local rows = {}
	for _, r in ipairs((live and ah.listings[itemID]) or ah.results[itemID] or {}) do rows[#rows + 1] = r end
	table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
	return rows
end
local function sortedItems(itemID)
	local rows = {}
	for _, r in ipairs(ah.results[itemID] or {}) do rows[#rows + 1] = r end
	table.sort(rows, function(a, b) return (a.buyout or 1e12) < (b.buyout or 1e12) end)
	return rows
end

local function enqueueResults(itemID, key)
	key = key or ah.searchKey[itemID] or { itemID = itemID, itemLevel = 0, itemSuffix = 0 }
	ah.pending[#ah.pending + 1] = { at = W.now + ah.resultsDelay, itemID = itemID, hk = keyStr(key), hits = commoditySearchHits(key) }
end

function ah.step()
	local i = 1
	while i <= #ah.pending do
		local p = ah.pending[i]
		if W.now >= p.at then
			table.remove(ah.pending, i)
			if not p.kind then
				-- the client keeps a snapshot of the results until the next refresh answers
				ah.hasResults[p.hk] = true
				local snap = {}
				for _, r in ipairs(p.hits and ah.listings[p.itemID] or {}) do
					local c = {}; for k, v in pairs(r) do c[k] = v end; snap[#snap + 1] = c
				end
				ah.results[p.itemID] = snap
			end
			if p.kind == "browsepage" then
				W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			elseif p.kind == "created" then
				W.fire("AUCTION_HOUSE_AUCTION_CREATED", p.auctionID)
			elseif p.kind == "browse" then
				ah.browse = p.results
				W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			elseif p.kind == "quote" then
				W.fire("COMMODITY_PRICE_UPDATED", p.unitPrice, p.totalPrice)
			elseif p.kind == "quote_unavailable" then
				W.fire("COMMODITY_PRICE_UNAVAILABLE")
			elseif p.kind == "confirm" then
				W.fire("COMMODITY_PURCHASE_SUCCEEDED")
				W.fire("COMMODITY_PURCHASED", p.itemID, p.qty)
			elseif p.kind == "bid" then
				W.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", p.auctionID)
			elseif p.kind == "biderror" then
				W.fire("AUCTION_HOUSE_SHOW_ERROR", Enum.AuctionHouseError.ItemNotFound)
			elseif W.items[p.itemID].commodity then
				W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", p.itemID)
			else
				W.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = p.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
			end
			W.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
		else
			i = i + 1
		end
	end
	if not ah.readyFired and W.now - ah.lastSend >= ah.throttle then
		ah.readyFired = true
		W.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	end
end

local function throttledSend(name, itemID, key)
	log(name)
	if W.now - ah.lastSend < ah.throttle then
		W.throttleViolations = (W.throttleViolations or 0) + 1
		W.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
		return
	end
	ah.lastSend = W.now
	ah.readyFired = false
	ah.sends = (ah.sends or 0) + 1
	ah.sendLog = ah.sendLog or {}
	ah.sendLog[#ah.sendLog + 1] = { t = W.now, itemID = itemID, name = name, key = key }
	if key then ah.searchKey[itemID] = key end
	enqueueResults(itemID, key)
end

ah.browse = nil
C_AuctionHouse = {
	SendBrowseQuery = function(q)
		log("SendBrowseQuery")
		assert(type(q.searchString) == "string" and type(q.sorts) == "table")
		if W.now - ah.lastSend < ah.throttle then W.throttleViolations = (W.throttleViolations or 0) + 1; return end
		ah.lastSend = W.now; ah.readyFired = false
		local found = {}
		if q.searchString == "" then
			-- whole house: one row per item with its total quantity and lowest price, delivered in pages of 2
			local ids = {}
			for id in pairs(ah.listings) do ids[#ids + 1] = id end
			table.sort(ids)
			for _, id in ipairs(ids) do
				local total, low = 0, nil
				for _, r in ipairs(ah.listings[id]) do
					total = total + (r.quantity or 1)
					local p = r.unitPrice or (r.buyout and r.buyout / (r.quantity or 1))
					if p and (not low or p < low) then low = p end
				end
				if total > 0 then found[#found + 1] = { itemKey = serverKey(id), totalQuantity = total, minPrice = low or 0, containsOwnerItem = false } end
			end
			ah.browseAll = found
			ah.browse = {}
			for i = 1, math.min(2, #found) do ah.browse[#ah.browse + 1] = found[i] end
			ah.browseFull = #ah.browse >= #found
			ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "browsepage" }
			return
		end
		for id, it in pairs(W.items) do
			if it.name:lower():find(q.searchString:lower(), 1, true) then
				found[#found + 1] = { itemKey = serverKey(id), totalQuantity = 1, minPrice = 1, containsOwnerItem = false }
			end
		end
		ah.browseFull = true
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "browse", results = found }
	end,
	SearchForItemKeys = function(keys, sorts)
		log("SearchForItemKeys")
		assert(type(keys) == "table" and #keys >= 1 and type(sorts) == "table")
		if W.now - ah.lastSend < ah.throttle then W.throttleViolations = (W.throttleViolations or 0) + 1; W.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"); return end
		ah.lastSend = W.now; ah.readyFired = false
		ah.sends = (ah.sends or 0) + 1
		ah.sendLog = ah.sendLog or {}
		ah.sendLog[#ah.sendLog + 1] = { t = W.now, itemID = 0, name = "SearchForItemKeys", keys = #keys }
		local found = {}
		for _, k in ipairs(keys) do
			local total, low, own = 0, nil, false
			for _, r in ipairs(ah.listings[k.itemID] or {}) do
				total = total + (r.quantity or 1)
				local p = r.unitPrice or (r.buyout and r.buyout / (r.quantity or 1))
				if p and (not low or p < low) then low = p end
				if r.own then own = true end
			end
			if total > 0 then found[#found + 1] = { itemKey = serverKey(k.itemID), totalQuantity = total, minPrice = low or 0, containsOwnerItem = own } end
			-- as seen in game: a requested commodity key that differs from the server's comes back as an
			-- extra empty "None available" row
			local it = W.items[k.itemID]
			if it and it.commodity and not commoditySearchHits(k) then
				found[#found + 1] = { itemKey = { itemID = k.itemID, itemLevel = k.itemLevel or 0, itemSuffix = k.itemSuffix or 0, battlePetSpeciesID = 0 }, totalQuantity = 0, minPrice = 0, containsOwnerItem = false }
			end
		end
		ah.lastKeys = keys
		ah.browseFull = true
		ah.pending[#ah.pending + 1] = { at = W.now + 0.15, kind = "browse", results = found }
	end,
	RequestMoreBrowseResults = function()
		log("RequestMoreBrowseResults")
		if W.now - ah.lastSend < ah.throttle then W.throttleViolations = (W.throttleViolations or 0) + 1; return end
		ah.lastSend = W.now; ah.readyFired = false
		local have = #ah.browse
		for i = have + 1, math.min(have + 2, #ah.browseAll) do ah.browse[#ah.browse + 1] = ah.browseAll[i] end
		ah.browseFull = #ah.browse >= #ah.browseAll
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "browsepage" }
	end,
	GetBrowseResults = function() return ah.browse or {} end,
	HasFullBrowseResults = function() return ah.browseFull ~= false end,
	MakeItemKey = function(id, lvl, suf, pet) return { itemID = id, itemLevel = lvl or 0, itemSuffix = suf or 0, battlePetSpeciesID = pet or 0 } end,
	GetItemKeyInfo = function(key)
		local it = W.items[key.itemID]
		if not it or it.uncached then return nil end
		return { itemID = key.itemID, itemName = it.name, isCommodity = it.commodity or false, isEquipment = it.equipment or false, isPet = false, quality = 1, iconFileID = 1, battlePetSpeciesID = 0 }
	end,
	IsThrottledMessageSystemReady = function() return W.now - ah.lastSend >= ah.throttle end,
	HasSearchResults = function(key) return ah.hasResults[keyStr(key)] or false end,
	SendSearchQuery = function(key, sorts, sep) assert(sorts[1].sortOrder == 0); throttledSend("SendSearchQuery", key.itemID, key) end,
	SendSellSearchQuery = function(key, sorts, sep) assert(key.itemLevel == 0 and key.itemSuffix == 0, "gear sell search needs the cleared key"); throttledSend("SendSellSearchQuery", key.itemID, key) end,
	RefreshCommoditySearchResults = function(itemID) throttledSend("RefreshCommoditySearchResults", itemID) end,
	RefreshItemSearchResults = function(key) throttledSend("RefreshItemSearchResults", key.itemID, key) end,
	GetNumCommoditySearchResults = function(itemID) return #(ah.results[itemID] or {}) end,
	GetCommoditySearchResultsQuantity = function(itemID) local t = 0; for _, r in ipairs(ah.results[itemID] or {}) do t = t + (r.quantity or 1) end return t end,
	GetItemSearchResultsQuantity = function(key) local t = 0; for _, r in ipairs(ah.results[key.itemID] or {}) do t = t + (r.quantity or 1) end return t end,
	GetCommoditySearchResultInfo = function(itemID, i)
		local r = sortedCommodity(itemID)[i]
		if not r then return nil end
		return { itemID = itemID, quantity = r.quantity, unitPrice = r.unitPrice, auctionID = r.auctionID or i, owners = r.owner and { r.owner } or {}, totalNumberOfOwners = 1, numOwnerItems = 0, containsOwnerItem = r.own or false, containsAccountItem = false }
	end,
	GetNumItemSearchResults = function(key) return #(ah.results[key.itemID] or {}) end,
	GetItemSearchResultInfo = function(key, i)
		local r = sortedItems(key.itemID)[i]
		if not r then return nil end
		return { itemKey = key, owners = r.owner and { r.owner } or {}, totalNumberOfOwners = 1, timeLeft = 3, auctionID = r.auctionID, quantity = r.quantity or 1, itemLink = "|Hitem:" .. key.itemID .. "|h[x]|h", containsOwnerItem = r.own or false, containsAccountItem = false, containsSocketedItem = false, buyoutAmount = r.buyout, minBid = r.bid or 1 }
	end,
	StartCommoditiesPurchase = function(itemID, qty)
		restricted("StartCommoditiesPurchase")
		ah.quote = { itemID = itemID, qty = qty }
		-- price the order cheapest-first from current listings
		local rows, left, total, maxUnit = sortedCommodity(itemID, true), qty, 0, 0
		for _, r in ipairs(rows) do
			if left <= 0 then break end
			local take = math.min(left, r.quantity)
			total = total + take * r.unitPrice
			maxUnit = math.max(maxUnit, r.unitPrice)
			left = left - take
		end
		if left > 0 then
			ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "quote_unavailable", itemID = itemID }
		else
			ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "quote", itemID = itemID, unitPrice = maxUnit, totalPrice = total }
		end
	end,
	ConfirmCommoditiesPurchase = function(itemID, qty)
		log("ConfirmCommoditiesPurchase")
		assert(ah.quote and ah.quote.itemID == itemID and ah.quote.qty == qty, "confirm without matching quote")
		-- remove the units from the book
		local rows, left = sortedCommodity(itemID, true), qty
		for _, r in ipairs(rows) do
			if left <= 0 then break end
			local take = math.min(left, r.quantity)
			r.quantity = r.quantity - take
			left = left - take
		end
		local keep = {}
		for _, r in ipairs(ah.listings[itemID]) do if r.quantity > 0 then keep[#keep + 1] = r end end
		ah.listings[itemID] = keep
		ah.bought = ah.bought or {}
		ah.bought[#ah.bought + 1] = { itemID = itemID, qty = qty }
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "confirm", itemID = itemID, qty = qty }
		ah.quote = nil
	end,
	CancelCommoditiesPurchase = function() log("CancelCommoditiesPurchase"); ah.quote = nil end,
	-- posting: throttled, restricted, asks for confirmation below 5c
	PostCommodity = function(location, duration, quantity, unitPrice)
		restricted("PostCommodity")
		assert(location and location.itemID, "no item location")
		ah.lastSend = W.now; ah.readyFired = false
		if unitPrice < 5 then return true end
		ah.posts = ah.posts or {}
		ah.posts[#ah.posts + 1] = { itemID = location.itemID, duration = duration, quantity = quantity, unitPrice = unitPrice }
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "created", auctionID = 5000 + #ah.posts }
		return false
	end,
	ConfirmPostCommodity = function(location, duration, quantity, unitPrice)
		restricted("ConfirmPostCommodity")
		ah.lastSend = W.now; ah.readyFired = false
		ah.posts = ah.posts or {}
		ah.posts[#ah.posts + 1] = { itemID = location.itemID, duration = duration, quantity = quantity, unitPrice = unitPrice, confirmed = true }
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "created", auctionID = 5000 + #ah.posts }
	end,
	PostItem = function(location, duration, quantity, bid, buyout) restricted("PostItem"); return false end,
	ConfirmPostItem = function() restricted("ConfirmPostItem") end,
	PlaceBid = function(auctionID, amount)
		restricted("PlaceBid")
		for itemID, rows in pairs(ah.listings) do
			for i, r in ipairs(rows) do
				if r.auctionID == auctionID then
					assert(amount == r.buyout, "wrong buyout amount")
					table.remove(rows, i)
					ah.bought = ah.bought or {}
					ah.bought[#ah.bought + 1] = { itemID = itemID, auctionID = auctionID, price = amount }
					ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "bid", itemID = itemID, auctionID = auctionID }
					return
				end
			end
		end
		ah.pending[#ah.pending + 1] = { at = W.now + 0.2, kind = "biderror" }
	end,
}

return W
