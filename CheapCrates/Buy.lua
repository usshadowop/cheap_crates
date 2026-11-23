--[[
	Cheap Crates - shopping list and purchasing.

	A shopping list has one step per item to buy: crates first, then fill materials. Each step
	runs:  pending -> checking (one fresh search, automatic) -> ready -> buying -> done.

	Buying needs a hardware event. C_AuctionHouse.StartCommoditiesPurchase and PlaceBid are
	HasRestrictions in Blizzard's API documentation for this client, so each purchase happens
	on a BUY press: the BUY button, the key binding, or (with "Scroll = BUY") a mouse wheel tick.
	ConfirmCommoditiesPurchase is not restricted, so the commodity price quote is confirmed
	automatically when it arrives, but only if it is within the plan's price (plus the
	tolerance, 5% by default). If the price rose, nothing is bought: the step shows the new
	price and waits for you to click BUY to accept it, or Skip. A wheel tick never accepts a
	higher price.

	If a crate cannot be bought, the fill materials for it are taken off the list before the
	fill steps start, so you never pay for materials with no crate to put them in.
]]

local _, ns = ...
local S = ns.S
local IsSecret = ns.IsSecret

local CHECK_TIMEOUT = 4
local BUY_TIMEOUT = 10
local FRESH_FOR = 1.5 -- seconds a result counts as fresh for a step's price check

local function C_AH() return C_AuctionHouse end

local function Tol()
	return 1 + math.max(0, ns.db.tolerance or 5) / 100
end

local function Cur()
	local q = S.queue
	if not q or q.finished then return nil end
	return q.steps[q.idx], q
end
ns.CurrentStep = Cur

-------------------------------------------------------------------------------
-- Building a list
-------------------------------------------------------------------------------

function ns.StartQueue(plan, title)
	if S.pendingCommodity or S.pendingItem then
		ns.Print("A purchase is still being processed; try again in a moment.")
		return false
	end
	if S.scan then ns.StopScan(true) end
	local steps, firstFill = {}, nil
	for _, b in ipairs(plan.buys) do
		steps[#steps + 1] = { itemID = b.itemID, qty = b.qty, budget = b.budget, planned = b.budget, got = 0, paid = 0, isCrate = b.isCrate, have = b.have, status = "pending", tries = 0 }
		if not b.isCrate and not firstFill then firstFill = #steps end
	end
	S.queue = { plan = plan, title = title, steps = steps, idx = 1, firstFill = firstFill or (#steps + 1), spent = 0, started = time() }
	ns.db.view = "shop"
	if #steps == 0 then
		S.queue.finished = true
		ns.Print("Nothing to buy: your bags already hold everything for this.")
	else
		local planned = 0
		for _, st in ipairs(steps) do planned = planned + st.budget end
		ns.Print("Shopping list: %d item%s for about %s. Press BUY (or scroll) at the auction house to buy each one.",
			#steps, #steps == 1 and "" or "s", ns.CoinsFull(planned))
	end
	ns.ApplyWheelBinding()
	ns.UpdateUI(true)
	return true
end

function ns.CancelQueue()
	if not S.queue then return end
	if S.pendingCommodity and C_AH() and C_AH().CancelCommoditiesPurchase then C_AH().CancelCommoditiesPurchase() end
	S.pendingCommodity, S.pendingItem = nil, nil
	S.queue = nil
	ns.Print("Shopping list cancelled.")
	ns.ApplyWheelBinding()
	ns.UpdateUI(true)
end

-- after the crate steps: drop fill materials for crates that could not be bought
local function RebuildFills(q)
	local plan = q.plan
	local avail = {}
	for _, st in ipairs(q.steps) do
		if st.isCrate then avail[st.itemID] = (st.have or 0) + st.got end
	end
	local need, dropped = {}, 0
	for _, u in ipairs(plan.units) do
		local cid = u.crate.id
		local a = avail[cid]
		if a == nil then a = plan.have[cid] or 0 end
		if a > 0 then
			avail[cid] = a - 1
			need[u.fill.item] = (need[u.fill.item] or 0) + u.fill.qty
		else
			avail[cid] = 0
			dropped = dropped + 1
		end
	end
	if dropped == 0 then return end
	for i = q.firstFill, #q.steps do
		local st = q.steps[i]
		local buy = math.max(0, (need[st.itemID] or 0) - (st.have or 0))
		if buy < st.qty then
			if buy == 0 then
				st.status, st.note = "skipped", "no crate for it"
			else
				local l = ns.NewLadder(st.itemID, st.have or 0)
				st.qty = buy
				st.budget = l:Cost(l.have, l.have + buy) or st.budget
			end
		end
	end
	ns.Print("%d crate%s could not be bought, so the fill materials for %s were taken off the list.",
		dropped, dropped == 1 and "" or "s", dropped == 1 and "it" or "them")
end

local function Finish(q)
	q.finished = true
	local planned, bought, missed = 0, 0, 0
	for _, st in ipairs(q.steps) do
		planned = planned + (st.planned or 0)
		if st.status == "done" then bought = bought + 1 elseif st.status ~= "skipped" or st.note ~= "no crate for it" then missed = missed + 1 end
	end
	ns.Print("|cff00ff00Shopping list finished.|r Spent %s (planned %s).%s", ns.CoinsFull(q.spent), ns.CoinsFull(planned),
		missed > 0 and (" %d item%s not bought (skipped or unavailable)."):format(missed, missed == 1 and " was" or "s were") or " Everything bought.")
	if q.plan and q.plan.target then
		ns.Print("Fill the crates (right-click a crate with the bundle in your bags) and hand them in for Merchant's Favor.")
	end
	ns.ApplyWheelBinding()
end

local function Advance(q)
	while q.idx <= #q.steps do
		local st = q.steps[q.idx]
		if st.status ~= "done" and st.status ~= "skipped" and st.status ~= "failed" then break end
		q.idx = q.idx + 1
		if q.idx == q.firstFill and not q.rebuilt then
			q.rebuilt = true
			RebuildFills(q)
		end
	end
	if q.idx > #q.steps then Finish(q) end
	ns.UpdateUI(true)
end

function ns.SkipStep()
	local st, q = Cur()
	if not st then return end
	if st.status == "buying" then
		ns.Print("Wait for the current purchase to finish before skipping.")
		return
	end
	st.status = "skipped"
	st.note = st.got > 0 and ("got %d of %d"):format(st.got, st.qty) or "skipped"
	Advance(q)
end

-------------------------------------------------------------------------------
-- Checking a step's price against fresh results
-------------------------------------------------------------------------------

-- cheapest way to get `need` units from the book: cost, units available, lots to buy (non-commodities)
local function Quote(id, need)
	local b = ns.db.book[id]
	if not b or b.est then return nil, 0 end -- only a detailed answer can be bought from
	if b.commodity then
		local cost, got = 0, 0
		for _, r in ipairs(b.rows) do
			local take = math.min(need - got, r.qty)
			cost = cost + take * r.unit
			got = got + take
			if got >= need then break end
		end
		return cost, got
	end
	local cost, got, lots = 0, 0, {}
	for _, r in ipairs(b.rows) do
		if got >= need then break end
		if not S.boughtAuctions[r.auctionID] then
			lots[#lots + 1] = { auctionID = r.auctionID, buyout = r.buyout, qty = r.qty }
			cost = cost + r.buyout
			got = got + r.qty
		end
	end
	return cost, got, lots
end

local function Evaluate(st)
	local need = st.qty - st.got
	local cost, avail, lots = Quote(st.itemID, need)
	local b = ns.db.book[st.itemID]
	st.commodity = b and b.commodity
	if not cost or avail <= 0 then
		st.status, st.note = "failed", "none listed"
		ns.Print("%s: none listed on the auction house; skipped.", ns.ItemName(st.itemID))
		Advance(S.queue)
		return
	end
	local remaining = st.budget - st.paid
	if avail < need then
		st.status = "price"
		st.offer = { qty = math.min(avail, need), cost = cost, lots = lots, short = true }
		st.note = ("only %d listed"):format(avail)
	elseif cost <= remaining * Tol() + 0.5 then
		st.status = "ready"
		st.offer = { qty = need, cost = cost, lots = lots, next = 1 }
		st.note = nil
	else
		st.status = "price"
		st.offer = { qty = need, cost = cost, lots = lots, next = 1 }
		st.note = ("now %s"):format(ns.CoinsPlain(cost))
	end
	if st.offer and st.offer.lots then st.offer.next = 1 end
	ns.UpdateUI(true)
end

-- results for an item arrived (from any request)
function ns.OnBuyResults(id)
	local st = Cur()
	if st and st.itemID == id and st.status == "checking" then Evaluate(st) end
end

function ns.BuyPump()
	local st, q = Cur()
	if not st or not S.ahOpen then return end
	local now = GetTime()
	if st.status == "pending" then
		local r = ns.RT(st.itemID)
		if r.freshAt and now - r.freshAt <= FRESH_FOR and (r.freshAt > (st.lastBuyAt or 0)) then
			st.status = "checking"
			Evaluate(st)
			return
		end
		if not ns.ThrottleReady() or S.pendingCommodity or S.pendingItem then return end
		st.status = "checking"
		st.checkAt = now
		ns.SendDetail(st.itemID)
		ns.UpdateUI(true)
	elseif st.status == "checking" then
		if now - (st.checkAt or now) > CHECK_TIMEOUT then
			st.tries = st.tries + 1
			if st.tries >= 3 then
				st.status, st.note = "failed", "no answer"
				ns.Print("%s: the auction house did not answer; skipped.", ns.ItemName(st.itemID))
				Advance(q)
			else
				st.status = "pending"
			end
		end
	elseif st.status == "buying" then
		if now - (st.buyAt or now) > BUY_TIMEOUT then
			-- no word from the server: look again (a bought auction is gone from the fresh results)
			S.pendingCommodity, S.pendingItem = nil, nil
			st.status = "pending"
			st.lastBuyAt = now
		end
	end
end

-------------------------------------------------------------------------------
-- BUY press (hardware event: button click, key binding, or wheel tick)
-------------------------------------------------------------------------------

local function HasMoney(amount)
	local m = GetMoney and GetMoney()
	if type(m) ~= "number" or IsSecret(m) then return true end
	return m >= amount
end

function ns.Press(source)
	local st, q = Cur()
	if not st then
		if source ~= "wheel" then
			if S.queue and S.queue.finished then
				ns.Print("The shopping list is finished. Pick a crate or plan a Favor goal for a new one.")
			else
				ns.Print("Nothing to buy. Press Buy on a crate row, or enter the Favor you need and press Plan.")
			end
		end
		return
	end
	if not S.ahOpen then
		if source ~= "wheel" then ns.Print("Open the auction house to buy.") end
		return
	end
	if S.pendingCommodity or S.pendingItem then return end -- one purchase at a time
	if (st.status == "ready" or st.status == "price") and not ns.ThrottleReady() then
		-- every auction house message shares one gate; a purchase sent while it is shut may be dropped
		if source ~= "wheel" then ns.Print("The auction house is still answering the last request; press again.") end
		return
	end

	if st.status == "price" then
		if source == "wheel" then
			if not st.wheelWarned then
				st.wheelWarned = true
				ns.Print("|cffffff00%s costs more than planned (%s, planned %s).|r Click BUY to accept the new price, or Skip. The scroll wheel will not accept it.",
					ns.ItemName(st.itemID), ns.CoinsFull(st.offer.cost), ns.CoinsFull(st.budget - st.paid))
			end
			return
		end
		-- accept the new price (and a smaller quantity, if that is all there is)
		st.budget = st.paid + st.offer.cost
		if st.offer.short then st.qty = st.got + st.offer.qty end
		st.offer.short = nil
		st.status = "ready"
		st.note = "price accepted"
	end
	if st.status ~= "ready" then return end

	local ah = C_AH()
	local o = st.offer
	if st.commodity then
		if not HasMoney(o.cost) then ns.Print("Not enough gold for %d x %s (%s).", o.qty, ns.ItemName(st.itemID), ns.CoinsFull(o.cost)); return end
		S.pendingCommodity = { step = st, qty = o.qty, limit = (st.budget - st.paid) * Tol() + 0.5 }
		st.status, st.buyAt = "buying", GetTime()
		-- HasRestrictions: allowed because this runs inside the press
		ah.StartCommoditiesPurchase(st.itemID, o.qty)
	else
		local lot = o.lots and o.lots[o.next or 1]
		if not lot then st.status = "pending"; return end
		if not HasMoney(lot.buyout) then ns.Print("Not enough gold for %s (%s).", ns.ItemName(st.itemID), ns.CoinsFull(lot.buyout)); return end
		S.pendingItem = { step = st, auctionID = lot.auctionID, buyout = lot.buyout, qty = lot.qty }
		S.boughtAuctions[lot.auctionID] = true
		st.status, st.buyAt = "buying", GetTime()
		-- HasRestrictions: allowed because this runs inside the press
		ah.PlaceBid(lot.auctionID, lot.buyout)
	end
	ns.UpdateUI(true)
end

-- key binding entry point (Bindings.xml)
function CheapCrates_BuyPressed()
	if ns.db then ns.Press("key") end
end

-------------------------------------------------------------------------------
-- Purchase events
-------------------------------------------------------------------------------

local function Record(st, qty, price)
	local h = ns.db.history
	table.insert(h, 1, { time = time(), itemID = st.itemID, qty = qty, price = price })
	while #h > 200 do table.remove(h) end
end

local function Bought(st, qty, price)
	local q = S.queue
	st.got = st.got + qty
	st.paid = st.paid + (price or 0)
	if q then q.spent = q.spent + (price or 0) end
	st.lastBuyAt = GetTime()
	Record(st, qty, price)
	ns.Print("|cff00ff00Bought|r %d x %s for %s.", qty, ns.ItemName(st.itemID), ns.CoinsFull(price))
end

function ns.OnPriceQuote(unitPrice, totalPrice)
	local p = S.pendingCommodity
	if not p then return end
	local ah = C_AH()
	if IsSecret(totalPrice) or totalPrice <= p.limit then
		p.quoted = totalPrice
		-- not restricted: confirmed here, inside the event, with no further press
		ah.ConfirmCommoditiesPurchase(p.step.itemID, p.qty)
	else
		ah.CancelCommoditiesPurchase()
		S.pendingCommodity = nil
		local st = p.step
		st.status = "price"
		st.offer = { qty = p.qty, cost = totalPrice }
		st.note = ("now %s"):format(ns.CoinsPlain(totalPrice))
		st.wheelWarned = false
		ns.Print("|cffffff00Not bought:|r the server quoted %d x %s at %s, over the planned %s. Click BUY to accept, or Skip.",
			p.qty, ns.ItemName(st.itemID), ns.CoinsFull(totalPrice), ns.CoinsFull(st.budget - st.paid))
		ns.UpdateUI(true)
	end
end

function ns.OnPriceUnavailable()
	local p = S.pendingCommodity
	if not p then return end
	S.pendingCommodity = nil
	p.step.status = "pending"
	p.step.lastBuyAt = GetTime()
	ns.Print("%s: those units are gone (someone else bought them). Checking the price again.", ns.ItemName(p.step.itemID))
	ns.UpdateUI(true)
end

function ns.OnCommodityBought()
	local p = S.pendingCommodity
	if not p then return end
	S.pendingCommodity = nil
	local st = p.step
	Bought(st, p.qty, p.quoted)
	if st.got >= st.qty then st.status = "done" else st.status = "pending" end
	if S.queue then Advance(S.queue) end
end

function ns.OnCommodityFailed()
	local p = S.pendingCommodity
	if not p then return end
	S.pendingCommodity = nil
	local st = p.step
	st.tries = st.tries + 1
	st.lastBuyAt = GetTime()
	if st.tries >= 3 then
		st.status, st.note = "failed", "purchase failed"
		ns.Print("|cffff4444Could not buy %s|r after %d tries; skipped.", ns.ItemName(st.itemID), st.tries)
		if S.queue then Advance(S.queue) end
	else
		st.status = "pending"
		ns.Print("Purchase of %s failed; checking again.", ns.ItemName(st.itemID))
	end
	ns.UpdateUI(true)
end

function ns.OnItemBought(auctionID)
	local p = S.pendingItem
	if not p or p.auctionID ~= auctionID then return end
	S.pendingItem = nil
	local st = p.step
	Bought(st, p.qty, p.buyout)
	if st.got >= st.qty then
		st.status = "done"
		if S.queue then Advance(S.queue) end
	else
		local o = st.offer
		o.next = (o.next or 1) + 1
		st.status = (o.lots and o.lots[o.next]) and "ready" or "pending"
		ns.UpdateUI(true)
	end
end

function ns.OnAuctionError(err)
	local p = S.pendingItem or S.pendingCommodity
	if not p then return end
	local names = {}
	if Enum and Enum.AuctionHouseError then
		for name, value in pairs(Enum.AuctionHouseError) do names[value] = name end
	end
	local st = p.step
	ns.Print("|cffff4444Auction house error|r on %s: %s. Checking again.", ns.ItemName(st.itemID), names[err] or tostring(err))
	if S.pendingCommodity and C_AH().CancelCommoditiesPurchase then C_AH().CancelCommoditiesPurchase() end
	S.pendingItem, S.pendingCommodity = nil, nil
	st.tries = st.tries + 1
	st.lastBuyAt = GetTime()
	st.status = st.tries >= 3 and "failed" or "pending"
	if st.status == "failed" then st.note = "error" ; if S.queue then Advance(S.queue) end end
	ns.UpdateUI(true)
end

-------------------------------------------------------------------------------
-- Text for the UI
-------------------------------------------------------------------------------

function ns.StepText(st)
	if not st then return "" end
	local name = ns.ItemName(st.itemID)
	local need = st.qty - st.got
	if st.status == "pending" or st.status == "checking" then
		return ("Checking the price of %d x %s..."):format(need, name)
	elseif st.status == "ready" then
		local o = st.offer
		if st.commodity then
			return ("Ready: %d x %s for %s"):format(o.qty, name, ns.CoinsFull(o.cost))
		end
		local lot = o.lots[o.next or 1]
		return ("Ready: %s%s for %s"):format(lot.qty > 1 and (lot.qty .. " x ") or "", name, ns.CoinsFull(lot.buyout))
	elseif st.status == "price" then
		if st.offer.short then
			return ("|cffffff00Only %d %s listed|r (%s). Click BUY to take them, or Skip."):format(st.offer.qty, name, ns.CoinsFull(st.offer.cost))
		end
		return ("|cffffff00Price rose:|r %d x %s now %s (planned %s). Click BUY to accept, or Skip."):format(need, name, ns.CoinsFull(st.offer.cost), ns.CoinsFull(st.budget - st.paid))
	elseif st.status == "buying" then
		return ("Buying %s..."):format(name)
	end
	return name
end

function ns.BuyButtonText()
	local st, q = Cur()
	if not st then
		if S.queue and S.queue.finished then return "Done" end
		return "BUY"
	end
	if not S.ahOpen then return "Open the AH" end
	if st.status == "ready" then
		local o = st.offer
		if st.commodity then return ("BUY %d %s"):format(o.qty, ns.ItemName(st.itemID)) end
		return ("BUY %s"):format(ns.ItemName(st.itemID))
	elseif st.status == "price" then
		return "Accept " .. ns.CoinsPlain(st.offer.cost)
	elseif st.status == "buying" then
		return "Buying..."
	end
	return "Checking..."
end
