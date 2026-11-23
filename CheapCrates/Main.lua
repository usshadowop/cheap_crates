--[[
	Cheap Crates - events, the per-frame driver, Buy / Plan entry points and slash commands.
]]

local ADDON_NAME, ns = ...
local S = ns.S

-------------------------------------------------------------------------------
-- Buy one combo / plan a Favor goal
-------------------------------------------------------------------------------

local function QueueBusy()
	if S.pendingCommodity or S.pendingItem then
		ns.Print("A purchase is still being processed; try again in a moment.")
		return true
	end
	return false
end

function ns.BuyCombo(combo)
	if QueueBusy() then return end
	local plan = ns.PlanUnits({ { crate = combo.crate, fill = combo.fill } }, ns.db.useBags)
	if S.queue and not S.queue.finished then ns.Print("Replaced the previous shopping list.") end
	local title = ("%s + %d %s"):format(combo.crate.short, combo.fill.qty, ns.ItemName(combo.fill.item))
	if plan.short then
		ns.Print("|cffffff00Not enough listed for %s at the last scan.|r The list will buy what is there; scan again for fresh prices.", title)
	end
	ns.StartQueue(plan, title)
	if ns.frame:IsShown() then ns.offset = 0 end
end

function ns.PlanGoal(n)
	if not n or n <= 0 then
		ns.Print("Enter how much Merchant's Favor you need, e.g. /crates goal 200")
		return
	end
	n = math.floor(n)
	if QueueBusy() then return end
	if not ns.db.lastScan and not next(ns.db.book) then
		ns.Print("No prices yet: open the auction house and press Scan first.")
		return
	end
	ns.db.goal = n
	local plan = ns.PlanFavor(n, ns.db.useBags)
	if #plan.units == 0 then
		ns.Print("No crate can be filled from the current prices (none listed, or all above your level). Scan again later.")
		return
	end
	if plan.short then
		ns.Print("|cffff4444Only %d of %d Favor can be bought|r from what is listed (%d crates for %s).", plan.favor, n, #plan.units, ns.CoinsFull(plan.cost))
	else
		ns.Print("Cheapest way to %d Favor: %d crate%s worth %d Favor for %s (%s per Favor):", n, #plan.units,
			#plan.units == 1 and "" or "s", plan.favor, ns.CoinsFull(plan.cost), ns.CoinsFull(plan.cost / math.max(1, plan.favor)))
	end
	for _, g in ipairs(plan.groups) do
		ns.Print("  %dx %s with %d %s each: %s", g.count, g.crate.short, g.fill.qty, ns.ItemName(g.fill.item), ns.CoinsFull(g.cost))
	end
	ns.StartQueue(plan, ("Goal: %d Favor"):format(n))
	ns.offset = 0
end

-------------------------------------------------------------------------------
-- Driver
-------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	if not ns.db then return end
	if S.ahOpen then
		ns.BuyPump()
		ns.ScanPump()
	end
	ns.DrawIfDirty()
end)

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	CheapCratesDB = CheapCratesDB or {}
	local db = CheapCratesDB
	for k, v in pairs(ns.DEFAULTS) do
		if db[k] == nil then
			if type(v) == "table" then db[k] = {} else db[k] = v end
		end
	end
	ns.db = db
	ns.UpdateUI(true)
end

function handlers.PLAYER_LOGIN()
	-- warm the item cache: names, stack sizes and item levels (for auction keys)
	if C_Item and C_Item.RequestLoadItemDataByID then
		for _, id in ipairs(ns.ALL_ITEMS) do C_Item.RequestLoadItemDataByID(id) end
	end
end

function handlers.AUCTION_HOUSE_SHOW()
	S.ahOpen = true
	S.boughtAuctions = {}
	for _, r in pairs(ns.R) do r.freshAt = nil; r.awaiting = nil end
	if S.queue and not S.queue.finished then
		local st = ns.CurrentStep()
		if st and st.status ~= "done" then st.status = "pending" end
	end
	if ns.db.autoShow then ns.Show() end
	ns.ApplyWheelBinding()
	ns.UpdateUI(true)
end

function handlers.AUCTION_HOUSE_CLOSED()
	S.ahOpen = false
	if S.scan then
		ns.Print("Auction house closed: scan stopped (%d items priced).", S.scan.done)
		S.scan = nil
	end
	S.pendingCommodity, S.pendingItem = nil, nil
	local st = ns.CurrentStep()
	if st and (st.status == "checking" or st.status == "buying" or st.status == "ready") then st.status = "pending" end
	ns.ApplyWheelBinding()
	ns.UpdateUI(true)
end

function handlers.PLAYER_REGEN_ENABLED() ns.ApplyWheelBinding() end
function handlers.BAG_UPDATE_DELAYED() ns.UpdateUI() end
function handlers.CURRENCY_DISPLAY_UPDATE() ns.UpdateUI() end
function handlers.PLAYER_LEVEL_UP() ns.UpdateUI() end
function handlers.GET_ITEM_INFO_RECEIVED() ns.UpdateUI() end
function handlers.ITEM_KEY_ITEM_INFO_RECEIVED() ns.UpdateUI() end

-- search results
function handlers.COMMODITY_SEARCH_RESULTS_UPDATED(itemID) ns.OnCommodityResults(itemID) end
function handlers.COMMODITY_SEARCH_RESULTS_ADDED(itemID) ns.OnCommodityResults(itemID) end
function handlers.ITEM_SEARCH_RESULTS_UPDATED(itemKey) ns.OnItemResults(itemKey) end
function handlers.ITEM_SEARCH_RESULTS_ADDED(itemKey) ns.OnItemResults(itemKey) end
function handlers.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED() ns.OnBrowseResults() end
function handlers.AUCTION_HOUSE_BROWSE_RESULTS_ADDED() ns.OnBrowseResults() end

-- throttle: send the next request the moment the gate opens
function handlers.AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
	ns.BuyPump()
	ns.ScanPump()
end
function handlers.AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED()
	-- the request was thrown away: ask again
	local sc = S.scan
	if sc then
		if sc.batch then sc.batch.sent = false end
		if sc.inflight then sc.inflight.t = -math.huge end
	end
	local st = ns.CurrentStep()
	if st and st.status == "checking" then st.status = "pending" end
	-- a dropped purchase request: nothing was bought, the next press can try again
	if st and st.status == "buying" and (S.pendingCommodity or S.pendingItem) and GetTime() - (st.buyAt or 0) < 1 then
		if S.pendingItem then S.boughtAuctions[S.pendingItem.auctionID] = nil end
		S.pendingCommodity, S.pendingItem = nil, nil
		st.status = "ready"
		ns.Print("The auction house dropped that purchase request (too many requests); press BUY again.")
	end
	ns.UpdateUI(true)
end

-- purchases
function handlers.COMMODITY_PRICE_UPDATED(unitPrice, totalPrice) ns.OnPriceQuote(unitPrice, totalPrice) end
function handlers.COMMODITY_PRICE_UNAVAILABLE() ns.OnPriceUnavailable() end
function handlers.COMMODITY_PURCHASE_SUCCEEDED() ns.OnCommodityBought() end
function handlers.COMMODITY_PURCHASE_FAILED() ns.OnCommodityFailed() end
function handlers.AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID) ns.OnItemBought(auctionID) end
function handlers.AUCTION_HOUSE_SHOW_ERROR(err) ns.OnAuctionError(err) end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if h then h(...) end
end)
for event in pairs(handlers) do
	-- an event this client does not know must not stop the addon from loading
	pcall(ev.RegisterEvent, ev, event)
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function OnOff(v) return v == "on" or v == "1" or v == "true" or v == "yes" end

local function Help()
	ns.Print("Commands (/crates or /cheapcrates):")
	ns.Print("  /crates  open or close the window")
	ns.Print("  /crates scan  price every crate and fill material (auction house open)")
	ns.Print("  /crates goal <favor>  cheapest way to that much Merchant's Favor, as a shopping list")
	ns.Print("  /crates top [n]  the n cheapest crates per Favor in chat")
	ns.Print("  /crates buy  press BUY (same as the button / key binding)")
	ns.Print("  /crates skip | cancel  skip the current item / drop the shopping list")
	ns.Print("  /crates bags on|off  count items already in your bags")
	ns.Print("  /crates wheel on|off  mouse wheel presses BUY while a shopping list is active")
	ns.Print("  /crates tolerance <percent>  how far a price may rise above the plan before it asks (now %d%%)", ns.db.tolerance or 5)
	ns.Print("  /crates favor <tier> <raw|crafted> <n> | favor reset  set the Favor a crate pays")
	ns.Print("  /crates levels on|off  leave out crates above your level (now %s)", ns.db.respectLevel and "on" or "off")
	ns.Print("  /crates stackcheck on|off  leave out bundles bigger than one stack (now %s)", ns.db.stackCheck and "on" or "off")
	ns.Print("  /crates key <KEY>  bind the BUY key, e.g. /crates key F10")
	ns.Print("  /crates reset  put the window back next to the auction house")
end

local function Top(n)
	local list = ns.Combos()
	local best = {}
	for _, r in ipairs(list) do if r.eligible and r.bestOfCrate then best[#best + 1] = r end end
	table.sort(best, function(a, b) return a.per < b.per end)
	if #best == 0 then ns.Print("No prices yet: press Scan at the auction house."); return end
	ns.Print("Cheapest crates per Merchant's Favor (prices from %s ago):", ns.Age(ns.db.lastScan))
	for i = 1, math.min(n, #best) do
		local r = best[i]
		ns.Print("  %d. %s + %d %s: %s for %d Favor = %s each", i, r.crate.short, r.fill.qty, ns.ItemName(r.fill.item),
			ns.CoinsFull(r.total), r.favor, ns.CoinsFull(r.per))
	end
end

local TIER_ALIASES = { apprentice = "Apprentice", journeyman = "Journeyman", expert = "Expert", artisan = "Artisan" }
local KIND_ALIASES = { raw = "gathered", gathered = "gathered", crafted = "crafted" }

SLASH_CHEAPCRATES1 = "/crates"
SLASH_CHEAPCRATES2 = "/cheapcrates"
SlashCmdList.CHEAPCRATES = function(msg)
	if not ns.db then return end
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	local db = ns.db
	if cmd == "" or cmd == "show" or cmd == "toggle" then
		if cmd == "show" then ns.Show() else ns.Toggle() end
	elseif cmd == "hide" then
		ns.Hide()
	elseif cmd == "help" or cmd == "?" then
		Help()
	elseif cmd == "scan" then
		if S.scan then ns.StopScan() else ns.StartScan() end
	elseif cmd == "stop" then
		ns.StopScan()
	elseif cmd == "goal" or cmd == "plan" then
		ns.PlanGoal(tonumber(rest))
		if CheapCratesGoalEdit and tonumber(rest) then CheapCratesGoalEdit:SetText(tostring(math.floor(tonumber(rest)))) end
	elseif cmd == "top" then
		Top(tonumber(rest) or 5)
	elseif cmd == "buy" then
		ns.Press("key")
	elseif cmd == "skip" then
		ns.SkipStep()
	elseif cmd == "cancel" then
		ns.CancelQueue()
	elseif cmd == "bags" then
		db.useBags = OnOff(rest:lower())
		ns.Print("Use bag items %s.", db.useBags and "on" or "off")
		ns.UpdateUI(true)
	elseif cmd == "wheel" then
		ns.SetWheel(OnOff(rest:lower()))
	elseif cmd == "tolerance" or cmd == "tol" then
		local p = tonumber((rest:gsub("%%", "")))
		if not p or p < 0 or p > 100 then ns.Print("Usage: /crates tolerance <0-100>  (now %d%%)", db.tolerance or 5); return end
		db.tolerance = p
		ns.Print("A price may now rise %d%% above the plan before BUY stops and asks.", p)
	elseif cmd == "favor" then
		local a, b, c = rest:match("^(%S+)%s*(%S*)%s*(%S*)$")
		if a and a:lower() == "reset" then
			db.favor = {}
			ns.Print("Favor values reset to the defaults.")
		else
			local tier = a and TIER_ALIASES[a:lower()]
			local kind = b and KIND_ALIASES[b:lower()]
			local n = tonumber(c)
			if not (tier and kind and n and n >= 0) then
				ns.Print("Usage: /crates favor <apprentice|journeyman|expert|artisan> <raw|crafted> <amount>   or   /crates favor reset")
				for _, t in ipairs({ "Apprentice", "Journeyman", "Expert", "Artisan" }) do
					local g = ns.FavorFor({ tier = t, kind = "gathered" })
					local cr = ns.FavorFor({ tier = t, kind = "crafted" })
					ns.Print("  %s: raw %d, crafted %d%s", t, g, cr, ns.FAVOR_ESTIMATED[t] and not db.favor[t .. ":gathered"] and " (estimated)" or "")
				end
				return
			end
			db.favor[tier .. ":" .. kind] = n
			ns.Print("%s %s crates now count as %d Favor.", tier, kind == "gathered" and "raw" or "crafted", n)
		end
		ns.UpdateUI(true)
	elseif cmd == "levels" then
		db.respectLevel = OnOff(rest:lower())
		ns.Print("Crates above your level are %s.", db.respectLevel and "left out of plans" or "included")
		ns.UpdateUI(true)
	elseif cmd == "stackcheck" then
		db.stackCheck = OnOff(rest:lower())
		ns.Print("Bundles bigger than one stack are %s.", db.stackCheck and "left out of plans" or "allowed")
		ns.UpdateUI(true)
	elseif cmd == "key" then
		local key = rest:upper()
		if key == "" then ns.Print("Usage: /crates key F10"); return end
		if InCombatLockdown and InCombatLockdown() then ns.Print("Not in combat."); return end
		if SetBinding(key, "CHEAPCRATES_BUY") then
			if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
			ns.Print("%s now presses BUY.", key)
		else
			ns.Print("Could not bind %s.", key)
		end
	elseif cmd == "reset" then
		db.pos = nil
		ns.Show()
	else
		Help()
	end
end

BINDING_HEADER_CHEAPCRATES = "Cheap Crates"
BINDING_NAME_CHEAPCRATES_BUY = "Cheap Crates: BUY next item on the shopping list"
BINDING_NAME_CHEAPCRATES_TOGGLE = "Cheap Crates: open / close the window"
