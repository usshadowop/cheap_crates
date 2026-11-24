--[[
	Cheap Crates - auction house scan (modern C_AuctionHouse API, as on the Forever client).

	Same request pattern as the Item Sniper addon, which was checked against
	Blizzard's UI source for Forever 1.60.1:

	1. Key pass. SearchForItemKeys takes up to 100 item keys per request and answers with each
	   item's lowest price and total quantity. Its answer also names the item key the server
	   files the listings under: Forever files commodities under a key that carries the item's
	   level, and a level-0 key built from the ID alone is a separate, empty key. The scan adopts
	   the server's key for every item that is listed.
	   All 126 items take two requests, about a second.
	2. Detail reads. One SendSearchQuery (or Refresh*, for a key the client already holds) per
	   item gives every listing: unit price and quantity for commodities, auction ID and buyout
	   for other items. The key pass cannot say how many units sit at the lowest price, so a
	   bundle of 20 needs this read to be priced exactly. The default scan reads only the items
	   that decide the top of the list (see "Scan driver" below); a full scan reads them all.

	Every request waits for C_AuctionHouse.IsThrottledMessageSystemReady() (about 100 requests a
	minute), which is why reading every item one by one takes about a minute.
]]

local _, ns = ...
local S, RT = ns.S, ns.RT
local IsSecret = ns.IsSecret

local BATCH_SIZE = 100
local BATCH_TIMEOUT = 5
local DETAIL_TIMEOUT = 4
local MAX_ROWS = 200

local function C_AH() return C_AuctionHouse end

local sorts
local function Sorts()
	if not sorts then
		local order = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
		sorts = { { sortOrder = order, reverseSort = false } }
	end
	return sorts
end
ns.Sorts = Sorts

function ns.ThrottleReady()
	local ah = C_AH()
	return S.ahOpen and ah and ah.IsThrottledMessageSystemReady and ah.IsThrottledMessageSystemReady()
end

-- best guess at an item's key before the server has named it
function ns.KeyFor(id)
	local r = RT(id)
	if r.key then return r.key end
	local ah = C_AH()
	local info = ah.GetItemKeyInfo and ah.GetItemKeyInfo(ah.MakeItemKey(id))
	if info then r.isCommodity = info.isCommodity and true or false end
	-- materials are commodities: their listings sit under a key with the item's level. A crate is
	-- only given that key once the client says it stacks; otherwise the plain key, which is what
	-- other (non-stackable) items use. Either way the key pass replaces this with the server's key.
	local isMaterial = not ns.CRATE_BY_ID[id]
	if r.isCommodity == true or (r.isCommodity == nil and isMaterial) then
		local _, _, _, lvl = ns.ItemInfo(id)
		if type(lvl) == "number" and not IsSecret(lvl) and lvl > 0 then
			return ah.MakeItemKey(id, lvl)
		end
	end
	if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	return ah.MakeItemKey(id)
end

local function AdoptKey(id, key)
	if type(key) ~= "table" then return end
	local copy = {}
	for k, v in pairs(key) do
		if IsSecret(v) then return end
		copy[k] = v
	end
	local r = RT(id)
	r.key = copy
	r.keyConfirmed = true
end

-------------------------------------------------------------------------------
-- Reading results into the price book
-------------------------------------------------------------------------------

local function SortRows(rows)
	table.sort(rows, function(a, b) return a.unit < b.unit end)
	while #rows > MAX_ROWS do table.remove(rows) end
end

function ns.ReadCommodity(id)
	local ah = C_AH()
	local n = ah.GetNumCommoditySearchResults(id) or 0
	local rows, listed = {}, 0
	for i = 1, n do
		local res = ah.GetCommoditySearchResultInfo(id, i)
		if not res then break end
		if IsSecret(res.unitPrice) or IsSecret(res.quantity) then return false end
		-- a price tier can mix your own units with other sellers'; the server skips yours
		local avail = (res.quantity or 0) - (res.containsOwnerItem and (res.numOwnerItems or 0) or 0)
		if avail > 0 and (res.unitPrice or 0) > 0 then
			rows[#rows + 1] = { unit = res.unitPrice, qty = avail }
			listed = listed + avail
		end
	end
	SortRows(rows)
	ns.db.book[id] = { t = time(), commodity = true, rows = rows, listed = listed }
	local r = RT(id)
	r.isCommodity = true
	r.freshAt = GetTime()
	return true
end

function ns.ReadItems(key)
	local ah = C_AH()
	local id = key.itemID
	local n = ah.GetNumItemSearchResults(key) or 0
	local rows, listed = {}, 0
	for i = 1, n do
		local res = ah.GetItemSearchResultInfo(key, i)
		if res and res.buyoutAmount and not IsSecret(res.buyoutAmount) and res.buyoutAmount > 0
			and not res.containsOwnerItem and not S.boughtAuctions[res.auctionID] then
			local qty = (res.quantity and res.quantity > 0) and res.quantity or 1
			rows[#rows + 1] = { unit = res.buyoutAmount / qty, qty = qty, buyout = res.buyoutAmount, auctionID = res.auctionID }
			listed = listed + qty
		end
	end
	SortRows(rows)
	ns.db.book[id] = { t = time(), commodity = false, rows = rows, listed = listed }
	local r = RT(id)
	r.isCommodity = false
	r.freshAt = GetTime()
	if not r.key then r.key = key end
	return true
end

-- one detailed request for an item (scan detail pass and the purchase "check price" step)
function ns.SendDetail(id)
	local ah = C_AH()
	local r = RT(id)
	local key = r.key or ns.KeyFor(id)
	if r.isCommodity == nil and ah.GetItemKeyInfo then
		local info = ah.GetItemKeyInfo(key)
		if info then r.isCommodity = info.isCommodity and true or false end
	end
	-- the first request for a key is a search; later ones must be a refresh to reach the server again
	if r.isCommodity ~= nil and ah.HasSearchResults and ah.HasSearchResults(key) then
		if r.isCommodity then ah.RefreshCommoditySearchResults(id) else ah.RefreshItemSearchResults(key) end
	else
		ah.SendSearchQuery(key, Sorts(), false)
	end
	r.awaiting = GetTime()
	r.sentKey = key
	S.lastSend = GetTime()
end

-- results events land here (any source: our scan, a purchase check, or the Blizzard UI)
function ns.OnCommodityResults(id)
	if not ns.IsTracked(id) then return end
	local r = RT(id)
	if r.lastFrame == GetTime() and not r.awaiting then return end
	r.lastFrame = GetTime()
	if not ns.ReadCommodity(id) then return end
	r.awaiting = nil
	ns.ResultsArrived(id)
end

function ns.OnItemResults(key)
	if not key or not ns.IsTracked(key.itemID) then return end
	local id = key.itemID
	local r = RT(id)
	-- read with the key we searched with when the event's key is the generic one
	local readKey = (r.sentKey and r.sentKey.itemID == id) and r.sentKey or key
	if r.lastFrame == GetTime() and not r.awaiting then return end
	r.lastFrame = GetTime()
	ns.ReadItems(readKey)
	r.awaiting = nil
	ns.ResultsArrived(id)
end

local tracked
function ns.IsTracked(id)
	if not tracked then
		tracked = {}
		for _, x in ipairs(ns.ALL_ITEMS) do tracked[x] = true end
	end
	return tracked[id] or false
end

function ns.ResultsArrived(id)
	local sc = S.scan
	if sc and sc.inflight and sc.inflight.id == id then
		sc.inflight = nil
		sc.done = sc.done + 1
		if sc.phase == "detail" then sc.qi = sc.qi + 1 end
	end
	if ns.OnBuyResults then ns.OnBuyResults(id) end
	ns.UpdateUI()
end

-------------------------------------------------------------------------------
-- Scan driver
--
-- quick (default): the key pass prices all 126 items in two requests: each item's lowest
--   price and how many are listed. That alone is exact for one unit (a crate) but only a
--   floor for a bundle of 20 (some of it may sit on dearer listings), so those show as "~".
--   The refine phase then reads full listings only where it matters: it keeps taking the
--   cheapest crate + bundle per Favor that still has an estimated bundle and reads that item,
--   until the top REFINE_TOP are all exact. Every estimate is a floor, so nothing below them
--   can be cheaper. Usually 10-20 requests instead of 126.
-- full (shift-click Scan, /crates scan full): reads every listed item, about a minute.
-- plan (ns.StartRefine): reads just the items a Plan or a Buy is about to use.
-------------------------------------------------------------------------------

ns.REFINE_TOP = 10

local function NewScan(mode, ids)
	return {
		mode = mode, t = GetTime(), started = time(), phase = "keys", ids = ids or {}, bi = 1,
		quick = {}, queue = {}, qi = 1, done = 0, refined = {}, inflight = nil,
	}
end

function ns.StartScan(mode)
	mode = mode or "quick"
	if not S.ahOpen then
		ns.Print("Open the auction house first, then press Scan.")
		return false
	end
	if S.queue and not S.queue.finished then
		ns.Print("Finish or cancel the shopping list before scanning again (it uses the same request budget).")
		return false
	end
	if S.scan then return false end
	local ids = {}
	for _, id in ipairs(ns.ALL_ITEMS) do ids[#ids + 1] = id end
	S.scan = NewScan(mode, ids)
	if mode == "full" then
		ns.Print("Full scan: every listing of all %d items (about a minute)...", #ids)
	end
	ns.ScanPump()
	ns.UpdateUI(true)
	return true
end

-- reads the full listings of just these items, then calls onDone (Plan and Buy use this)
function ns.StartRefine(ids, onDone)
	local sc = NewScan("plan")
	sc.phase = "detail"
	sc.queue = ids
	sc.onDone = onDone
	S.scan = sc
	ns.ScanPump()
	ns.UpdateUI(true)
end

function ns.StopScan(quiet)
	if not S.scan then return end
	S.scan = nil
	if not quiet then ns.Print("Scan stopped.") end
	ns.UpdateUI(true)
end

-- full scan: every crate, then every listed fill item
local function BuildDetailQueue(sc)
	local q = {}
	for _, c in ipairs(ns.CRATES) do q[#q + 1] = c.id end
	local fills = {}
	for _, id in ipairs(sc.ids) do
		if not ns.CRATE_BY_ID[id] then
			local qk = sc.quick[id]
			if qk and qk.listed > 0 then
				fills[#fills + 1] = { id = id, score = qk.min or math.huge }
			elseif not sc.keyPassFailed then
				ns.db.book[id] = { t = time(), commodity = true, rows = {}, listed = 0 }
			else
				fills[#fills + 1] = { id = id, score = math.huge }
			end
		end
	end
	table.sort(fills, function(a, b) return a.score < b.score end)
	for _, f in ipairs(fills) do q[#q + 1] = f.id end
	sc.queue = q
	sc.qi = 1
end

local function AfterKeyPass(sc)
	if sc.mode == "full" or sc.keyPassFailed then
		sc.phase = "detail"
		BuildDetailQueue(sc)
		return
	end
	-- an item the key pass did not list is not on the auction house
	for _, id in ipairs(sc.ids) do
		local qk = sc.quick[id]
		if qk and qk.listed == 0 then
			ns.db.book[id] = { t = time(), commodity = RT(id).isCommodity, rows = {}, listed = 0 }
		end
	end
	sc.phase = "refine"
end

-- next item whose full listings decide the top of the list, or nil when the top is exact
function ns.NextToRefine(skip)
	local ok = {}
	for _, r in ipairs(ns.Combos()) do
		if r.eligible then ok[#ok + 1] = r end
	end
	table.sort(ok, function(a, b) return a.per < b.per end)
	local exact = 0
	for _, r in ipairs(ok) do
		if r.est and not skip[r.fill.item] then return r.fill.item end
		exact = exact + 1
		if exact >= ns.REFINE_TOP then return nil end
	end
	return nil
end

local function FinishScan(sc)
	S.scan = nil
	if sc.onDone then
		sc.onDone()
		ns.UpdateUI(true)
		return
	end
	ns.db.lastScan = time()
	local listedCrates = 0
	for _, c in ipairs(ns.CRATES) do
		local b = ns.db.book[c.id]
		if b and (b.listed or 0) > 0 then listedCrates = listedCrates + 1 end
	end
	ns.Print("Scan done in %ds: %d items priced (%d read in full), %d of %d crates listed.",
		math.floor(GetTime() - sc.t + 0.5), #sc.ids, sc.done, listedCrates, #ns.CRATES)
	local combos = {}
	for _, r in ipairs(ns.Combos()) do if r.eligible then combos[#combos + 1] = r end end
	table.sort(combos, function(a, b) return a.per < b.per end)
	for i = 1, 3 do
		local r = combos[i]
		if r then
			ns.Print("  %d. %s + %d %s: %s (%s per Favor)", i, r.crate.short, r.fill.qty, ns.ItemName(r.fill.item),
				ns.CoinsFull(r.total), ns.CoinsFull(r.per))
		end
	end
	ns.UpdateUI(true)
	if sc.afterScan then sc.afterScan() end
end

-- answer to a key-pass request (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED)
function ns.OnBrowseResults()
	local sc = S.scan
	if not (sc and sc.batch and sc.batch.sent) then return end
	local ah = C_AH()
	local results = ah.GetBrowseResults and ah.GetBrowseResults() or {}
	local wanted = {}
	for _, id in ipairs(sc.batch.ids) do wanted[id] = true end
	local byItem, ours, allZero = {}, 0, true
	for _, res in ipairs(results) do
		local id = res.itemKey and res.itemKey.itemID
		if id and wanted[id] then
			ours = ours + 1
			local a = byItem[id] or { listed = 0 }
			byItem[id] = a
			local q, p = res.totalQuantity, res.minPrice
			if q and not IsSecret(q) and q > 0 then
				allZero = false
				a.listed = a.listed + q
				-- the key holding the listings (an answer can also carry an empty "None available" key)
				if not a.keyQty or q > a.keyQty then a.key, a.keyQty = res.itemKey, q end
			end
			if p and not IsSecret(p) and p > 0 and (not a.min or p < a.min) then a.min = p end
		end
	end
	if #results > 0 and ours == 0 then return end -- someone else's browse answer (the Blizzard UI)
	if ours > 0 and allZero and (sc.batch.zeroRetries or 0) < 2 then
		-- Forever quirk reported by other authors: the first answer can carry zero quantities; ask again
		sc.batch.zeroRetries = (sc.batch.zeroRetries or 0) + 1
		sc.batch.sent = false
		return
	end
	if ah.HasFullBrowseResults and not ah.HasFullBrowseResults() and (sc.batch.pages or 0) < 5 then
		sc.batch.more = true -- the rest of the answer comes in pages; ScanPump asks for the next one
		return
	end
	for _, id in ipairs(sc.batch.ids) do
		local a = byItem[id]
		if a and a.key then AdoptKey(id, a.key) end
		sc.quick[id] = { listed = a and a.listed or 0, min = a and a.min }
		-- lowest price x everything listed: exact for one unit, a floor for more
		local b = ns.db.book[id]
		if a and a.min and a.listed > 0 and (not b or (b.t or 0) < sc.started or b.est) then
			ns.db.book[id] = { t = time(), est = true, rows = { { unit = a.min, qty = a.listed } }, listed = a.listed }
		end
	end
	sc.bi = sc.bi + #sc.batch.ids
	sc.batch = nil
	if sc.bi > #sc.ids then AfterKeyPass(sc) end
	ns.UpdateUI(true)
end

function ns.ScanPump()
	local sc = S.scan
	if not sc then return end
	if not S.ahOpen then return end
	if S.pendingCommodity or S.pendingItem then return end -- a purchase owns the gate
	local now = GetTime()
	local ah = C_AH()

	if sc.phase == "keys" then
		if not ah.SearchForItemKeys then
			sc.keyPassFailed = true
			AfterKeyPass(sc)
			return
		end
		if sc.batch and sc.batch.more then
			if not ns.ThrottleReady() then return end
			sc.batch.more = false
			sc.batch.pages = (sc.batch.pages or 0) + 1
			sc.batch.t = now
			S.lastSend = now
			ah.RequestMoreBrowseResults()
			return
		end
		if sc.batch and sc.batch.sent then
			if now - sc.batch.t < BATCH_TIMEOUT then return end
			sc.batch.tries = (sc.batch.tries or 0) + 1
			if sc.batch.tries >= 2 then
				-- no answer: price these items one by one instead
				sc.keyPassFailed = true
				sc.bi = sc.bi + #sc.batch.ids
				sc.batch = nil
				if sc.bi > #sc.ids then AfterKeyPass(sc) end
				return
			end
			sc.batch.sent = false
		end
		if not ns.ThrottleReady() then return end
		if not sc.batch then
			local ids = {}
			for i = sc.bi, math.min(#sc.ids, sc.bi + BATCH_SIZE - 1) do ids[#ids + 1] = sc.ids[i] end
			sc.batch = { ids = ids }
		end
		local keys = {}
		for _, id in ipairs(sc.batch.ids) do keys[#keys + 1] = ns.KeyFor(id) end
		sc.batch.sent = true
		sc.batch.t = now
		S.lastSend = now
		ah.SearchForItemKeys(keys, Sorts())
		return
	end

	-- detail / refine: one item at a time
	if sc.inflight then
		if now - sc.inflight.t < DETAIL_TIMEOUT then return end
		if sc.inflight.tries < 1 then
			if not ns.ThrottleReady() then return end
			sc.inflight.tries = sc.inflight.tries + 1
			sc.inflight.t = now
			ns.SendDetail(sc.inflight.id) -- ask once more
			return
		end
		ns.Print("No answer for %s; skipped.", ns.ItemName(sc.inflight.id))
		RT(sc.inflight.id).awaiting = nil
		sc.inflight = nil
		if sc.phase == "detail" then sc.qi = sc.qi + 1 end
	end
	local id
	if sc.phase == "refine" then
		id = ns.NextToRefine(sc.refined)
	else
		id = sc.queue[sc.qi]
	end
	if not id then
		FinishScan(sc)
		return
	end
	if not ns.ThrottleReady() then return end
	sc.refined[id] = true
	sc.inflight = { id = id, t = now, tries = 0 }
	ns.SendDetail(id)
end

-- one line for the window's status text, or nil when idle
function ns.ScanProgress()
	local sc = S.scan
	if not sc then return nil end
	if sc.mode == "plan" then
		return ("Reading exact prices %d/%d..."):format(sc.qi - 1, #sc.queue)
	end
	if sc.phase == "keys" then
		return ("Scanning: lowest prices of %d items..."):format(#sc.ids)
	end
	if sc.phase == "refine" then
		return ("Scanning: exact prices for the top %d (%d read)..."):format(ns.REFINE_TOP, sc.done)
	end
	return ("Full scan: %d/%d..."):format(sc.qi - 1, #sc.queue)
end
