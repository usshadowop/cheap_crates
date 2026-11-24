local HARNESS, ADDON = ...
local W = assert(loadfile(HARNESS .. "/wow_stub.lua"))()

-- load the addon the way the game does: the files in .toc order, each chunk gets (addonName, namespace)
local ns = {}
local files = {}
for line in io.lines(ADDON .. "/CheapCrates.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:match("^#") then files[#files + 1] = line end
end
for _, f in ipairs(files) do assert(loadfile(ADDON .. "/" .. f))("CheapCrates", ns) end

local failures = 0
local function check(cond, msg)
	if cond then print("  ok   " .. msg) else failures = failures + 1; print("  FAIL " .. msg) end
end
local function lastChat(pat)
	for i = #W.chat, 1, -1 do if W.chat[i]:find(pat) then return W.chat[i] end end
end
local function countCalls(name)
	local n = 0
	for _, c in ipairs(W.calls) do if c == name then n = n + 1 end end
	return n
end
local function click(btn) btn:GetScript("OnClick")(btn, "LeftButton") end
local function press(btn) W.press(function() click(btn) end) end
local function findCombo(list, crateID, fillID)
	for _, r in ipairs(list) do if r.crate.id == crateID and r.fill.item == fillID then return r end end
end

-- every crate and fill item exists in the fake client
for _, c in ipairs(ns.CRATES) do W.items[c.id] = { name = c.name, ilvl = 10 } end
for id, name in pairs(ns.ITEM_NAMES) do
	if not ns.CRATE_BY_ID[id] then W.items[id] = { name = name, commodity = true, ilvl = 5 } end
end
W.items[2589].stack = 20      -- Linen Cloth stacks to 20, so the 40-Linen bundle cannot be filled
W.items[765].infoLevel = 1    -- Silverleaf: the client's item level differs from the key the server files it under

-- crate IDs used below
local HERBS, FABRICS, TEXTILES, JHERBS, EHERBS = 248682, 248702, 248684, 248686, 248690
local SILVERLEAF, BRIAR, PEACE, MAGE = 765, 2450, 2447, 785
local HIDE, BOLT, LINEN, LLEATHER, BRUISE, FADE = 4231, 2996, 2589, 2318, 2453, 3818

local function Listings()
	W.ah.listings = {}
	ns.S.boughtAuctions = {} -- the fixture reuses auction IDs; on a real server every listing has a new one
	W.ah.setItems(HERBS, { { auctionID = 1001, buyout = 4000, quantity = 1 }, { auctionID = 1002, buyout = 6000, quantity = 1 } })
	W.ah.setCommodity(SILVERLEAF, { { unitPrice = 20, quantity = 15 }, { unitPrice = 30, quantity = 100 } })
	W.ah.setCommodity(BRIAR, { { unitPrice = 40, quantity = 10 } })
	W.ah.setCommodity(PEACE, { { unitPrice = 50, quantity = 200 } })
	W.ah.setCommodity(MAGE, { { unitPrice = 100, quantity = 50 } })
	W.ah.setItems(FABRICS, { { auctionID = 2001, buyout = 5000, quantity = 1 }, { auctionID = 2002, buyout = 5500, quantity = 1 }, { auctionID = 2003, buyout = 9000, quantity = 1 } })
	W.ah.setCommodity(HIDE, { { unitPrice = 1000, quantity = 3 }, { unitPrice = 2000, quantity = 10 } })
	W.ah.setCommodity(BOLT, { { unitPrice = 200, quantity = 100 } })
	W.ah.setItems(TEXTILES, { { auctionID = 3001, buyout = 1000, quantity = 1 } })
	W.ah.setCommodity(LINEN, { { unitPrice = 10, quantity = 500 } })
	W.ah.setCommodity(LLEATHER, { { unitPrice = 100, quantity = 40 } })
	W.ah.setCommodity(BRUISE, { { unitPrice = 30, quantity = 100 } })     -- Journeyman Herbs: no crate listed
	W.ah.setItems(EHERBS, { { auctionID = 4001, buyout = 100, quantity = 1 } }) -- level 20 crate
	W.ah.setCommodity(FADE, { { unitPrice = 1, quantity = 100 } })
end
W.level = 15

-- runs a scan to the end; returns the game time it took
local function Rescan(mode)
	W.shift = (mode == "full")
	click(CheapCratesScanButton)
	W.shift = false
	local t0 = W.now
	for _ = 1, 2400 do
		W.tick(0.05)
		if not ns.S.scan then break end
	end
	return W.now - t0
end
local function DetailCalls()
	return countCalls("SendSearchQuery") + countCalls("RefreshCommoditySearchResults") + countCalls("RefreshItemSearchResults")
end
local function RunUntil(cond, seconds)
	for _ = 1, math.floor((seconds or 10) / 0.05) do
		if cond() then return true end
		W.tick(0.05)
	end
	return cond()
end

print("== load")
W.fire("ADDON_LOADED", "CheapCrates")
W.fire("PLAYER_LOGIN")
check(CheapCratesDB and CheapCratesDB.useBags == true and CheapCratesDB.tolerance == 5 and CheapCratesDB.wheel == true, "saved variables initialised with defaults")
check(#ns.CRATES == 30, "30 crates in the database")
local fills = 0
for _, c in ipairs(ns.CRATES) do fills = fills + #c.fills end
check(fills == 96 and #ns.ALL_ITEMS == 126, "96 fill bundles, 126 distinct items to price")
ns.Show()
check(CheapCratesFrame:IsShown(), "window opens before any scan without errors")

print("== scan needs the auction house")
W.chat = {}
W.slash("scan")
check(lastChat("Open the auction house first") ~= nil and ns.S.scan == nil, "scan refused while the auction house is closed")

print("== scan")
Listings()
W.fire("AUCTION_HOUSE_SHOW")
check(CheapCratesFrame:IsShown(), "window shown with the auction house")
W.calls = {}
local took = Rescan()
check(ns.S.scan == nil and CheapCratesDB.lastScan ~= nil, "quick scan finished")
check(countCalls("SearchForItemKeys") == 2, "key pass: two batch requests price all 126 items")
check(DetailCalls() == 7, "then exact listings for just the 7 bundles that decide the top of the list (" .. DetailCalls() .. " reads)")
check(took < 6, ("quick scan took %.1f s of game time"):format(took))
check(not W.throttleViolations, "never sent while the throttle was closed")
check(#W.violations == 0, "no restricted calls during the scan")
local b = CheapCratesDB.book
check(b[HERBS] and b[HERBS].est and b[HERBS].rows[1].unit == 4000, "crate priced from the key pass (its lowest price is exact for one crate)")
check(b[SILVERLEAF] and b[SILVERLEAF].commodity and not b[SILVERLEAF].est and #b[SILVERLEAF].rows == 2 and b[SILVERLEAF].listed == 115, "Silverleaf read in full (server key adopted from the key pass)")
check(ns.R[SILVERLEAF].key.itemLevel == 5, "Silverleaf searched under the server's key, not the client's item level")
check(b[LINEN] and b[LINEN].est, "a bundle that cannot be used (stack-blocked) is not read in full")
check(b[2449] and b[2449].listed == 0, "unlisted fill item recorded as none listed")
check(b[JHERBS] and b[JHERBS].listed == 0, "crate the key pass did not list is recorded as none listed")
check(lastChat("Scan done") ~= nil, "scan summary printed")
local top = {}
for _, r in ipairs(ns.Combos()) do if r.eligible then top[#top + 1] = r end end
local anyEst = false
for _, r in ipairs(top) do if r.est then anyEst = true end end
check(not anyEst, "every usable crate + bundle priced exactly")

print("== full scan (shift-click Scan)")
W.calls = {}
took = Rescan("full")
check(DetailCalls() >= 30 + 10, "reads every crate and every listed material (" .. DetailCalls() .. " reads)")
check(not b[HERBS].est and #b[HERBS].rows == 2 and b[HERBS].rows[1].auctionID == 1001, "crate auctions read with auction IDs")
check(not b[LINEN].est, "even unusable bundles read in full")
check(took > 15, ("full scan takes longer (%.1f s)"):format(took))

print("== prices per Favor")
CheapCratesDB.useBags = false
local list = ns.Combos()
local herbsBriar = findCombo(list, HERBS, BRIAR)
check(herbsBriar.total == 4400 and herbsBriar.per == 880, "Apprentice Herbs + 10 Briarthorn = 4400 (880 per Favor)")
local herbsSilver = findCombo(list, HERBS, SILVERLEAF)
check(herbsSilver.fillCost == 15 * 20 + 5 * 30, "20 Silverleaf walks up the price ladder (15 at 20c, 5 at 30c)")
local fabHide = findCombo(list, FABRICS, HIDE)
check(fabHide.total == 7000 and fabHide.per == 700 and fabHide.favor == 10, "Apprentice Fabrics + 2 Cured Light Hide = 7000 for 10 Favor")
local texLeather = findCombo(list, TEXTILES, LLEATHER)
check(texLeather.per == 600 and texLeather.cheapest, "Apprentice Textiles + 20 Light Leather is the cheapest per Favor")
local texLinen = findCombo(list, TEXTILES, LINEN)
check(texLinen.stackBlocked and not texLinen.eligible and texLinen.per == 280, "40 Linen Cloth flagged: stacks to 20 (priced but left out)")
local eHerbs = findCombo(list, EHERBS, FADE)
check(eHerbs.levelBlocked and not eHerbs.eligible, "level 20 crate left out at level 15")
local jHerbs = findCombo(list, JHERBS, BRUISE)
check(jHerbs.total == nil and jHerbs.crateMissing == "none", "crate with nothing listed cannot be priced")
check(herbsBriar.bestOfCrate and not herbsSilver.bestOfCrate, "cheapest bundle of each crate marked")

print("== crates view")
CheapCratesDB.view = "crates"
ns.UpdateUI(true)
check(ns.rows[1].data and ns.rows[1].data.combo.fill.item == LLEATHER, "list sorted: cheapest per Favor first")
check(ns.rows[1].cols.per:GetText() == ns.Coins(600), "per-Favor column shows 6 silver")
CheapCratesBestCheck:SetChecked(true); click(CheapCratesBestCheck)
local shownCrates, dup = {}, false
for i = 1, 14 do
	local d = ns.rows[i].data
	if d and d.kind == "combo" then
		if shownCrates[d.combo.crate.id] then dup = true end
		shownCrates[d.combo.crate.id] = true
	end
end
check(CheapCratesDB.bestOnly and not dup, "best fill only: one row per crate")
CheapCratesBestCheck:SetChecked(false); click(CheapCratesBestCheck)
-- header click sorts by total
local totalHeader
for _, f in ipairs(W.frames) do if f.key == "total" and f._parent == CheapCratesFrame then totalHeader = f end end
click(totalHeader)
check(CheapCratesDB.sortKey == "total" and ns.rows[1].data.combo.total == 3000, "clicking the Total header sorts by total")
CheapCratesDB.sortKey = "per"

print("== bag inventory tick box")
W.bagCount[BRIAR] = 10
W.bagCount[TEXTILES] = 1
CheapCratesBagsCheck:SetChecked(true); click(CheapCratesBagsCheck)
check(CheapCratesDB.useBags == true, "tick box turns bag counting on")
list = ns.Combos()
check(findCombo(list, HERBS, BRIAR).total == 4000, "10 Briarthorn in bags: Apprentice Herbs only costs the crate (4000)")
check(findCombo(list, TEXTILES, LLEATHER).total == 2000, "crate in bags: Textiles only costs the leather")
W.bagCount[BRIAR] = 6
check(findCombo(ns.Combos(), HERBS, BRIAR).total == 4000 + 4 * 40, "6 of 10 Briarthorn in bags: buy the missing 4")
CheapCratesBagsCheck:SetChecked(false); click(CheapCratesBagsCheck)
check(findCombo(ns.Combos(), HERBS, BRIAR).total == 4400, "tick box off: full price again")
W.bagCount = {}

print("== buy one crate + bundle from its row")
CheapCratesDB.view = "crates"
ns.UpdateUI(true)
local fabRow
for i = 1, 14 do
	local d = ns.rows[i].data
	if d and d.kind == "combo" and d.combo.crate.id == FABRICS and d.combo.fill.item == HIDE then fabRow = ns.rows[i] end
end
check(fabRow ~= nil, "Apprentice Fabrics + Cured Light Hide row visible")
W.chat = {}
click(fabRow.buy)
local q = ns.S.queue
check(q and #q.steps == 2 and q.steps[1].itemID == FABRICS and q.steps[1].budget == 5000 and q.steps[2].itemID == HIDE and q.steps[2].qty == 2 and q.steps[2].budget == 2000,
	"shopping list: the crate (5000), then 2 hides (2000)")
check(CheapCratesDB.view == "shop", "switched to the shopping list")
check(W.overrides.MOUSEWHEELDOWN == "CheapCratesWheelButton", "scroll wheel bound to BUY while the list is active")
W.run(1)
check(q.steps[1].status == "ready", "crate price checked and ready")
check(CheapCratesBuyButton:IsEnabled(), "BUY button enabled")
W.calls = {}
press(CheapCratesBuyButton)
check(countCalls("PlaceBid") == 1, "one press, one PlaceBid")
W.run(1)
check(q.steps[1].status == "done" and q.steps[1].paid == 5000, "crate bought for 5000")
check(q.steps[2].status == "ready", "hides checked and ready")
-- a wheel tick buys the next item
W.press(function() click(CheapCratesWheelButton) end)
W.run(1)
check(q.steps[2].status == "done" and q.steps[2].paid == 2000, "wheel tick bought the 2 hides for 2000 (quote auto-confirmed)")
check(q.finished and q.spent == 7000, "list finished, spent 7000")
check(W.overrides.MOUSEWHEELDOWN == nil, "wheel released when the list is done")
check(#W.violations == 0, "every purchase ran inside a hardware event")

print("== a key press with nothing to buy does nothing")
W.calls = {}
W.press(function() CheapCrates_BuyPressed() end)
check(countCalls("PlaceBid") == 0 and countCalls("StartCommoditiesPurchase") == 0, "no purchase")

print("== price rises between the check and the press")
Listings(); Rescan()
CheapCratesDB.useBags = false
local herbsSilverCombo = findCombo(ns.Combos(), HERBS, SILVERLEAF)
ns.BuyCombo(herbsSilverCombo)
q = ns.S.queue
W.run(1)
press(CheapCratesBuyButton) -- crate
W.run(1)
check(q.steps[1].status == "done" and q.steps[2].status == "ready" and q.steps[2].budget == 450, "crate bought, 20 Silverleaf ready at 450")
W.ah.setCommodity(SILVERLEAF, { { unitPrice = 40, quantity = 100 } }) -- someone bought the cheap ones
W.chat = {}
press(CheapCratesBuyButton)
W.run(1)
check(countCalls("CancelCommoditiesPurchase") >= 1 and q.steps[2].status == "price" and q.steps[2].got == 0, "quote of 800 is over 450 + 5%: cancelled, nothing bought")
check(lastChat("Not bought") ~= nil, "told why")
W.calls = {}
W.press(function() click(CheapCratesWheelButton) end)
W.run(1)
check(countCalls("StartCommoditiesPurchase") == 0 and q.steps[2].status == "price", "a wheel tick does not accept a higher price")
check(lastChat("will not accept") ~= nil, "wheel tick explains it needs a click")
check(CheapCratesBuyButton:GetText():find("Accept") ~= nil, "button offers to accept the new price")
press(CheapCratesBuyButton)
W.run(1)
check(q.steps[2].status == "done" and q.steps[2].paid == 800 and q.finished, "a click accepts the new price and buys")

print("== price already higher when the step is checked")
Listings(); Rescan()
ns.BuyCombo(findCombo(ns.Combos(), FABRICS, HIDE))
q = ns.S.queue
W.ah.setItems(FABRICS, { { auctionID = 2005, buyout = 9000, quantity = 1 } })
W.run(1)
check(q.steps[1].status == "price" and q.steps[1].offer.cost == 9000, "crate now 9000 against 5000 planned: waits for approval")
check(not CheapCratesBuyButton:GetText():find("BUY") and CheapCratesBuyButton:IsEnabled(), "button reads Accept")
click(CheapCratesSkipButton)
check(q.steps[1].status == "skipped", "Skip")
check(q.steps[2].status == "skipped" and q.steps[2].note == "no crate for it" and q.finished, "skipping the crate also drops its hides")
check(lastChat("taken off the list") ~= nil, "told the fill materials were dropped")

print("== auction gone at the press: next lot instead")
Listings(); Rescan()
CheapCratesDB.tolerance = 20
ns.BuyCombo(findCombo(ns.Combos(), FABRICS, HIDE))
q = ns.S.queue
W.run(1)
check(q.steps[1].status == "ready" and q.steps[1].offer.lots[1].auctionID == 2001, "ready to buy auction 2001")
table.remove(W.ah.listings[FABRICS], 1) -- someone else bought 2001
W.chat = {}
press(CheapCratesBuyButton)
W.run(1.5)
check(lastChat("Auction house error") ~= nil, "server error reported")
check(q.steps[1].status == "ready" and q.steps[1].offer.lots[1].auctionID == 2002, "re-checked: auction 2002 (5500, within 20%) is ready")
press(CheapCratesBuyButton)
W.run(1)
press(CheapCratesBuyButton)
W.run(1)
check(q.finished and q.steps[1].paid == 5500 and q.steps[2].status == "done", "bought the next auction and the hides")
CheapCratesDB.tolerance = 5

print("== Favor goal planner")
Listings(); Rescan("full") -- the planner itself, on full listings
CheapCratesDB.useBags = false
local plan = ns.PlanFavor(25, false)
check(plan.favor == 25 and plan.cost == 18500 and not plan.short, "25 Favor: cheapest mix costs 18500")
local g1, g2 = plan.groups[1], plan.groups[2]
check(#plan.groups == 2 and g1.crate.id == TEXTILES and g1.count == 1 and g2.crate.id == FABRICS and g2.count == 2 and g2.fill.item == HIDE,
	"1x Textiles with Light Leather + 2x Fabrics with Cured Light Hide")
plan = ns.PlanFavor(7, false)
check(plan.cost == 7000 and plan.favor == 10 and #plan.units == 1 and plan.units[1].crate.id == FABRICS,
	"7 Favor: one 10-Favor crate (7000) beats two 5-Favor crates (7400)")
plan = ns.PlanFavor(5, false)
check(plan.cost == 3000 and plan.favor == 5, "5 Favor: the single cheapest crate")
plan = ns.PlanFavor(1000, false)
check(plan.short and plan.favor == 5 + 10 + 30 and plan.favor < 1000, "unreachable goal: plans the most Favor available (all listed crates)")
local greedy = ns.GreedyPlan(25, false)
check(greedy.favor >= 25 and greedy.cost >= 18500, "greedy fallback reaches the goal, never cheaper than the exact plan")
CheapCratesDB.useBags = true
W.bagCount[HIDE] = 4
W.bagCount[FABRICS] = 1
plan = ns.PlanFavor(25, true)
check(plan.cost < 18500, "with bag items the same goal costs less (" .. plan.cost .. ")")
local buysHide = false
for _, bu in ipairs(plan.buys) do if bu.itemID == HIDE then buysHide = true end end
check(not buysHide, "4 hides already in bags: none bought")
W.bagCount = {}
CheapCratesDB.useBags = false

print("== goal box -> shopping list -> buy everything with the scroll wheel")
CheapCratesGoalEdit:SetText("25")
click(CheapCratesPlanButton)
RunUntil(function() return ns.S.queue ~= nil and ns.S.queue.plan.target == 25 end, 5)
q = ns.S.queue
check(q and q.plan.target == 25 and #q.steps == 4, "Plan builds a 4-item shopping list")
check(q.steps[1].itemID == TEXTILES and q.steps[2].itemID == FABRICS and q.steps[2].qty == 2 and q.steps[2].budget == 10500
	and q.steps[3].itemID == LLEATHER and q.steps[4].itemID == HIDE and q.steps[4].qty == 4 and q.steps[4].budget == 5000,
	"crates first (Textiles, 2 Fabrics for 10500), then 20 Light Leather and 4 hides (5000)")
ns.UpdateUI(true)
local sawGroup, sawStep = false, false
for i = 1, 14 do
	local d = ns.rows[i].data
	if d and d.kind == "group" then sawGroup = true end
	if d and d.kind == "step" then sawStep = true end
end
check(sawGroup and sawStep, "shopping list shows the crates to fill and the items to buy")
W.calls = {}
for _ = 1, 30 do
	W.press(function() CheapCratesFrame:GetScript("OnMouseWheel")(CheapCratesFrame, -1) end)
	W.run(0.5)
	if q.finished then break end
end
check(q.finished and q.spent == 18500, "scrolling bought everything for exactly the planned 18500")
check(countCalls("PlaceBid") == 3 and countCalls("StartCommoditiesPurchase") == 2, "3 crate auctions + 2 commodity purchases, no extras")
check(#W.violations == 0, "all inside hardware events")
check(lastChat("Fill the crates") ~= nil, "reminds you to fill and hand in")

print("== a crate sells out mid-list: its fill materials shrink")
Listings(); Rescan()
ns.S.queue = nil -- the previous list (also 25 Favor) is finished
ns.PlanGoal(25)
RunUntil(function() return ns.S.queue ~= nil and ns.S.queue.plan.target == 25 end, 5)
q = ns.S.queue
W.run(2)
check(q.steps[1].status == "ready", "Textiles crate ready")
W.ah.setItems(FABRICS, { { auctionID = 2001, buyout = 5000, quantity = 1 } }) -- the other Fabrics crates are gone
press(CheapCratesBuyButton)
W.run(1.5)
check(q.steps[2].status == "price" and q.steps[2].offer.short and q.steps[2].offer.qty == 1, "only 1 of 2 Fabrics crates left: asks")
press(CheapCratesBuyButton) -- take the one that is there
W.run(1.5)
check(q.steps[2].status == "done" and q.steps[2].got == 1, "took the 1 crate")
check(q.steps[4].qty == 2 and q.steps[4].budget == 2000 and q.steps[3].qty == 20, "hides cut from 4 to 2 (one crate's worth); leather unchanged")
for _ = 1, 4 do press(CheapCratesBuyButton); W.run(1) end
check(q.finished and q.steps[4].got == 2, "finished with 2 hides")

print("== the auction house closes mid-list")
Listings(); Rescan()
ns.BuyCombo(findCombo(ns.Combos(), FABRICS, HIDE))
q = ns.S.queue
W.run(1)
W.fire("AUCTION_HOUSE_CLOSED")
check(q.steps[1].status == "pending" and W.overrides.MOUSEWHEELDOWN == nil, "step parked and wheel released")
W.calls = {}
W.press(function() CheapCrates_BuyPressed() end)
check(countCalls("PlaceBid") == 0, "no purchase with the auction house closed")
W.fire("AUCTION_HOUSE_SHOW")
W.run(1)
check(q.steps[1].status == "ready" and W.overrides.MOUSEWHEELDOWN == "CheapCratesWheelButton", "resumes when it opens again")
click(CheapCratesCancelButton)
check(ns.S.queue == nil and W.overrides.MOUSEWHEELDOWN == nil, "Cancel drops the list")

print("== presses respect the shared request gate")
Listings(); Rescan()
W.run(0.5) -- let the gate open after the scan's last read
ns.BuyCombo(findCombo(ns.Combos(), FABRICS, HIDE))
q = ns.S.queue
W.run(0.3) -- the price check answered, but the gate (0.4 s) is still shut
check(q.steps[1].status == "ready" and not C_AuctionHouse.IsThrottledMessageSystemReady(), "step ready while the gate is still shut")
W.calls = {}; W.chat = {}
press(CheapCratesBuyButton)
check(countCalls("PlaceBid") == 0 and lastChat("press again") ~= nil, "press with the gate shut: nothing sent, asked to press again")
W.run(0.3)
press(CheapCratesBuyButton)
check(countCalls("PlaceBid") == 1, "next press goes through")
W.run(1)
check(q.steps[2].status == "ready", "hides ready")
press(CheapCratesBuyButton)
W.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") -- the server threw the purchase request away
check(q.steps[2].status == "ready" and ns.S.pendingCommodity == nil, "dropped purchase request: back to ready")
W.run(1) -- the stale quote for the dropped request is ignored
check(q.steps[2].got == 0 and countCalls("ConfirmCommoditiesPurchase") == 0, "nothing confirmed for the dropped request")
press(CheapCratesBuyButton)
W.run(1)
check(q.finished and q.steps[2].got == 2, "the next press buys the hides")

print("== quick scan with a short top list: Buy and Plan read the exact prices they need")
ns.REFINE_TOP = 2
Listings(); W.calls = {}; Rescan()
check(DetailCalls() == 2, "top 2 only: 2 full reads (" .. DetailCalls() .. ")")
check(b[SILVERLEAF].est and b[HIDE] and not b[HIDE].est, "Silverleaf left as an estimate, Cured Light Hide read")
check(findCombo(ns.Combos(), HERBS, SILVERLEAF).est, "its row is marked ~")
ns.UpdateUI(true)
W.chat = {}
ns.S.queue = nil -- the previous list is finished
ns.BuyCombo(findCombo(ns.Combos(), HERBS, SILVERLEAF))
check(ns.S.queue == nil and ns.S.scan and ns.S.scan.mode == "plan", "Buy first reads the estimated item")
RunUntil(function() return ns.S.queue ~= nil end, 5)
q = ns.S.queue
check(q and q.steps[2].itemID == SILVERLEAF and q.steps[2].budget == 450, "then lists 20 Silverleaf at the exact 450, not the 400 floor")
ns.CancelQueue()
W.chat = {}
ns.PlanGoal(40)
check(lastChat("Reading exact prices for the plan") ~= nil, "Plan reads exact prices for what it would buy")
RunUntil(function() return ns.S.queue ~= nil end, 15)
q = ns.S.queue
local stillEst = false
for _, st in ipairs(q.steps) do
	local bk = CheapCratesDB.book[st.itemID]
	if bk.est and st.qty > 1 then stillEst = true end
end
check(not stillEst, "every multi-unit item in the plan was read in full")
check(ns.PlanFavor(40, false).cost == q.plan.cost, "the list matches a plan made from the exact prices (" .. q.plan.cost .. ")")
ns.CancelQueue()
ns.REFINE_TOP = 10

print("== Plan pressed while a scan runs waits for it")
Listings()
click(CheapCratesScanButton)
W.run(0.3)
W.chat = {}
ns.PlanGoal(25)
check(ns.S.queue == nil and lastChat("as soon as the scan finishes") ~= nil, "waits for the scan")
RunUntil(function() return ns.S.queue ~= nil end, 20)
check(ns.S.queue and ns.S.queue.plan.target == 25 and ns.S.queue.plan.cost == 18500, "then plans 25 Favor for 18500")
ns.CancelQueue()

print("== In bags tab")
Listings(); Rescan()
W.bagCount = { [HERBS] = 1, [SILVERLEAF] = 45, [BRIAR] = 10, [MAGE] = 4, [FABRICS] = 2, [LINEN] = 60, [EHERBS] = 1, [FADE] = 10 }
local rows, sum = ns.BagFill()
local function bagRow(id) for _, r in ipairs(rows) do if r.crate.id == id then return r end end end
local hr = bagRow(HERBS)
check(hr and hr.crates == 1 and hr.bundles == 3 and hr.can == 1 and hr.favor == 5 and hr.spareBundles == 2,
	"Apprentice Herbs: 1 crate, 3 bundles (2x Silverleaf, 1x Briarthorn) -> can fill 1, 2 bundles need a crate")
local mage
for _, part in ipairs(hr.parts) do if part.fill.item == MAGE then mage = part end end
check(mage and mage.have == 4 and mage.n == 0, "4/10 Mageroyal shown as not yet a bundle")
local fr = bagRow(FABRICS)
check(fr and fr.crates == 2 and fr.bundles == 0 and fr.can == 0 and fr.spareCrates == 2, "Apprentice Fabrics: 2 crates, no bundle")
local tr = bagRow(TEXTILES)
check(tr and tr.bundles == 0 and tr.parts[1].blocked, "60 Linen Cloth is no bundle: 40 do not fit in one stack of 20")
local er = bagRow(EHERBS)
check(er and er.levelBlocked and er.can == 0, "level 20 crate: cannot fill it at level 15")
check(sum.can == 1 and sum.favor == 5 and sum.spareBundles == 2 and sum.spareCrates == 2, "total: 1 crate ready to fill (5 Favor)")
check(bagRow(JHERBS) == nil, "crates with nothing in bags are not listed")
CheapCratesDB.view = "crates"
ns.UpdateUI(true)
local bagsTab
for _, f in ipairs(W.frames) do if f._parent == CheapCratesFrame and f._kind == "Button" and type(f._text) == "string" and f._text:find("^In bags") then bagsTab = f end end
check(bagsTab and bagsTab:GetText() == "In bags (1)", "tab shows how many crates you can fill")
click(bagsTab)
check(CheapCratesDB.view == "bags", "tab opens the bags view")
check(ns.rows[1].data.kind == "text" and ns.rows[1].data.text:find("Ready to fill now") and ns.rows[1].data.text:find("1 crate"), "summary line: ready to fill now")
check(ns.rows[2].data.kind == "bag" and ns.rows[2].data.bag.crate.id == HERBS, "crates you can fill listed first")
check(ns.rows[2].cols.total:GetText():find("1") and ns.rows[2].cols.per:GetText() == "+2 crates", "row shows can fill 1, missing +2 crates")
-- Buy on that row: the 2 crates the spare bundles need, nothing else
click(ns.rows[2].buy)
RunUntil(function() return ns.S.queue ~= nil end, 5)
q = ns.S.queue
check(q and #q.steps == 1 and q.steps[1].itemID == HERBS and q.steps[1].qty == 2 and q.steps[1].budget == 10000,
	"Buy gets just the 2 missing crates (4000 + 6000)")
ns.CancelQueue()
CheapCratesDB.view = "bags"; ns.UpdateUI(true)
local fabRowUI
for i = 1, 14 do local d = ns.rows[i].data; if d and d.kind == "bag" and d.bag.crate.id == FABRICS then fabRowUI = ns.rows[i] end end
click(fabRowUI.buy)
RunUntil(function() return ns.S.queue ~= nil end, 5)
q = ns.S.queue
check(q and #q.steps == 1 and q.steps[1].itemID == HIDE and q.steps[1].qty == 4 and q.steps[1].budget == 5000,
	"2 empty Fabrics crates: Buy gets the cheapest bundle for each (4 Cured Light Hide)")
ns.CancelQueue()
local erUI
CheapCratesDB.view = "bags"; ns.UpdateUI(true)
for i = 1, 14 do local d = ns.rows[i].data; if d and d.kind == "bag" and d.bag.crate.id == EHERBS then erUI = ns.rows[i] end end
check(erUI and not erUI.buy:IsEnabled(), "nothing to buy for a crate above your level")
W.bagCount = {}
ns.UpdateUI(true)
check(bagsTab:GetText() == "In bags" and ns.rows[1].data.text:find("No Waylaid Crates"), "empty bags: says so")
CheapCratesDB.view = "crates"

print("== settings and commands")
W.chat = {}
W.slash("favor artisan crafted 45")
check(ns.FavorFor(ns.CRATE_BY_ID[248711]) == 45 and not ns.FavorIsEstimate(ns.CRATE_BY_ID[248711]), "/crates favor sets a crate's Favor")
W.slash("favor reset")
check(ns.FavorFor(ns.CRATE_BY_ID[248711]) == 40 and ns.FavorIsEstimate(ns.CRATE_BY_ID[248711]), "/crates favor reset")
W.slash("tolerance 12")
check(CheapCratesDB.tolerance == 12, "/crates tolerance")
W.slash("tolerance 5")
W.chat = {}
W.slash("top 3")
check(lastChat("1%. Apprentice Textiles") ~= nil and lastChat("3%. ") ~= nil, "/crates top lists the cheapest crates")
W.slash("wheel off")
check(CheapCratesDB.wheel == false, "/crates wheel off")
W.slash("wheel on")
W.slash("levels off")
check(findCombo(ns.Combos(), EHERBS, FADE).eligible, "/crates levels off includes higher-level crates")
W.slash("levels on")
W.slash("key F10")
check(W.bindings.F10 == "CHEAPCRATES_BUY", "/crates key binds BUY")
W.chat = {}
W.slash("help")
check(#W.chat > 5, "/crates help")
W.slash("goal 10")
RunUntil(function() return ns.S.queue ~= nil end, 5)
check(ns.S.queue and ns.S.queue.plan.target == 10, "/crates goal plans from chat")
ns.CancelQueue()

print("== scan stops when the auction house closes")
click(CheapCratesScanButton)
W.run(0.5)
W.fire("AUCTION_HOUSE_CLOSED")
check(ns.S.scan == nil, "scan stopped")
check(not W.throttleViolations, "throttle respected throughout")
check(#W.violations == 0, "no restricted call outside a hardware event, all run")

print()
if failures > 0 then
	print(failures .. " TEST(S) FAILED")
	return true
end
print("ALL TESTS PASSED")
return false
