--[[
	Cheap Crates - settings, helpers and the pricing engine.

	Pricing model. Every item (crate or fill material) has a "ladder": the units you already
	carry (when "Use bag items" is ticked) come first at no cost, then the auction house
	listings from cheapest to dearest. Buying N units costs the next N rungs of the ladder.
	Commodities (stackable goods) are bought by the unit, so a partial row costs only the units
	taken; non-stackable auctions are whole lots, so touching a lot costs its full buyout.

	A "combo" is one crate plus one of its fill bundles. Its cost is the crate's first rung plus
	the bundle's first N rungs; cost per Favor = cost / Favor the sealed crate pays.

	The Favor goal planner (ns.PlanFavor) finds the cheapest mix of crates and bundles worth at
	least the goal: a cost curve per crate (n crates filled with the n cheapest bundles across
	its options), then a knapsack over the crates. Buying deeper into a price ladder makes that
	crate dearer, so big goals spread across crate types on their own.
]]

local ADDON_NAME, ns = ...

local CC = {}
ns.CC = CC
_G.CheapCrates = CC
CC.ns = ns

ns.ADDON_NAME = ADDON_NAME

ns.DEFAULTS = {
	book = {},           -- itemID -> { t, commodity, est, listed, rows = { {unit, qty, buyout?, auctionID?} } }
	lastScan = nil,      -- time() of the last completed scan
	useBags = true,      -- count items already in your bags
	bestOnly = false,    -- crates view: only the cheapest bundle of each crate
	wheel = true,        -- mouse wheel presses BUY while a shopping list is active at the auction house
	tolerance = 5,       -- % a price may rise above the plan before a purchase stops and asks
	favor = {},          -- overrides: ["Artisan:crafted"] = 40
	respectLevel = true, -- leave out crates above your level
	stackCheck = true,   -- leave out bundles bigger than the item's stack size
	sortKey = "per",
	sortDesc = false,
	goal = nil,
	history = {},
	pos = nil,
	autoShow = false,    -- open by itself when the auction house opens (/crates autoshow on)
	minimap = {},        -- minimap button: { hide = bool, angle = degrees }
	view = "crates",
}

ns.S = {
	ahOpen = false,
	scan = nil,          -- scan in progress (Scan.lua)
	queue = nil,         -- shopping list (Buy.lua)
	pendingCommodity = nil,
	pendingItem = nil,
	boughtAuctions = {},
	lastSend = 0,
}
ns.R = {} -- per-item runtime: { key, keyConfirmed, isCommodity, freshAt, awaiting }

function ns.RT(itemID)
	local r = ns.R[itemID]
	if not r then
		r = {}
		ns.R[itemID] = r
	end
	return r
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	local cf = DEFAULT_CHAT_FRAME or ChatFrame1
	if cf then cf:AddMessage("|cff33ff99CheapCrates|r: " .. msg) end
end

function ns.IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end
local IsSecret = ns.IsSecret

local GOLD, SILVER, COPPER = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

-- compact coins: "12g 34s", "5s 20c", "45c" (copper is dropped above 1 gold)
function ns.Coins(c)
	if c == nil then return "-" end
	if IsSecret(c) then return "?" end
	c = math.floor(c + 0.5)
	local neg = c < 0
	if neg then c = -c end
	local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local out
	if g > 0 then
		out = s > 0 and ("%d%s %d%s"):format(g, GOLD, s, SILVER) or (g .. GOLD)
	elseif s > 0 then
		out = cu > 0 and ("%d%s %d%s"):format(s, SILVER, cu, COPPER) or (s .. SILVER)
	else
		out = cu .. COPPER
	end
	return neg and ("-" .. out) or out
end

-- full precision, for tooltips and chat
function ns.CoinsFull(c)
	if c == nil then return "-" end
	if IsSecret(c) then return "?" end
	c = math.floor(c + 0.5)
	local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. GOLD end
	if s > 0 or g > 0 then parts[#parts + 1] = s .. SILVER end
	parts[#parts + 1] = cu .. COPPER
	return table.concat(parts, " ")
end

-- plain text (no colour codes), for status lines that get long
function ns.CoinsPlain(c)
	if c == nil then return "-" end
	if IsSecret(c) then return "?" end
	c = math.floor(c + 0.5)
	local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then return ("%dg %ds %dc"):format(g, s, cu) end
	if s > 0 then return ("%ds %dc"):format(s, cu) end
	return cu .. "c"
end

local function ItemInfo(id)
	if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
	if GetItemInfo then return GetItemInfo(id) end
end
ns.ItemInfo = ItemInfo

function ns.ItemName(id)
	local name = ItemInfo(id)
	if type(name) == "string" and name ~= "" and not IsSecret(name) then return name end
	return ns.ITEM_NAMES[id] or ("item " .. tostring(id))
end

-- max stack size from the live client, or nil while the item is not cached
function ns.StackSize(id)
	local _, _, _, _, _, _, _, stack = ItemInfo(id)
	if type(stack) == "number" and not IsSecret(stack) and stack > 0 then return stack end
	return nil
end

-- units of an item in your bags (bank not included)
function ns.BagCount(id)
	local n
	if C_Item and C_Item.GetItemCount then
		n = C_Item.GetItemCount(id, false)
	elseif GetItemCount then
		n = GetItemCount(id, false)
	end
	if type(n) ~= "number" or IsSecret(n) then return 0 end
	return n
end

function ns.PlayerLevel()
	local lvl = UnitLevel and UnitLevel("player")
	if type(lvl) ~= "number" or IsSecret(lvl) then return 999 end
	return lvl
end

function ns.CurrentFavor()
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local info = C_CurrencyInfo.GetCurrencyInfo(ns.CURRENCY_ID)
		if info and type(info.quantity) == "number" and not IsSecret(info.quantity) then return info.quantity end
	end
	return nil
end

function ns.FavorFor(crate)
	local db = ns.db
	local key = crate.tier .. ":" .. crate.kind
	local v = db and db.favor and db.favor[key]
	if type(v) == "number" then return v end
	return ns.DEFAULT_FAVOR[crate.tier][crate.kind]
end

function ns.FavorIsEstimate(crate)
	local db = ns.db
	if db and db.favor and db.favor[crate.tier .. ":" .. crate.kind] then return false end
	return ns.FAVOR_ESTIMATED[crate.tier] or false
end

function ns.LevelBlocked(crate)
	return ns.db.respectLevel and ns.PlayerLevel() < (crate.level or 0)
end

function ns.StackBlocked(fill)
	if not ns.db.stackCheck then return false end
	local stack = ns.StackSize(fill.item)
	return stack ~= nil and stack < fill.qty, stack
end

-------------------------------------------------------------------------------
-- Ladders
-------------------------------------------------------------------------------

local Ladder = {}
Ladder.__index = Ladder

-- have = free units (from bags) that come before the auction house listings
function ns.NewLadder(itemID, have)
	local b = ns.db.book[itemID]
	local rows = b and b.rows or {}
	local l = setmetatable({
		itemID = itemID,
		have = have or 0,
		rows = rows,
		lot = b ~= nil and b.commodity == false,
		est = b ~= nil and b.est or false,
		scanned = b ~= nil,
		pos = 0,
		starts = {},
	}, Ladder)
	local s = l.have
	for i, r in ipairs(rows) do
		l.starts[i] = s
		s = s + (r.qty or 1)
	end
	l.supply = s
	return l
end

-- cost of rungs (a, b]; nil when the ladder does not reach b
function Ladder:Cost(a, b)
	if b <= a then return 0 end
	if b > self.supply then return nil end
	local cost = 0
	for i, r in ipairs(self.rows) do
		local s = self.starts[i]
		if s >= b then break end
		if self.lot then
			-- a lot is paid in full when its first unit is taken
			if s >= a then cost = cost + (r.buyout or r.unit * r.qty) end
		else
			local e = s + r.qty
			local lo, hi = math.max(a, s), math.min(b, e)
			if hi > lo then cost = cost + (hi - lo) * r.unit end
		end
	end
	return cost
end

function Ladder:Peek(q) return self:Cost(self.pos, self.pos + q) end

-- units the auction house must supply to reach position pos
function Ladder:ToBuy(pos)
	return math.max(0, (pos or self.pos) - self.have)
end

-------------------------------------------------------------------------------
-- Combos (crates view)
-------------------------------------------------------------------------------

-- why a combo cannot be priced: "unscanned" | "none" (none listed) | "short" (not enough listed)
local function Missing(l, q)
	if l.supply >= q then return nil end
	if not l.scanned then return "unscanned" end
	if l.supply - l.have <= 0 then return "none" end
	return "short"
end

function ns.Combos()
	local db = ns.db
	local list = {}
	for _, c in ipairs(ns.CRATES) do
		local favor = ns.FavorFor(c)
		local cl = ns.NewLadder(c.id, db.useBags and ns.BagCount(c.id) or 0)
		local cc = cl:Cost(0, 1)
		local best
		for _, o in ipairs(c.fills) do
			local fl = ns.NewLadder(o.item, db.useBags and ns.BagCount(o.item) or 0)
			local fc = fl:Cost(0, o.qty)
			local stackBad, stack = ns.StackBlocked(o)
			local row = {
				crate = c, fill = o, favor = favor,
				crateCost = cc, fillCost = fc,
				total = (cc and fc) and (cc + fc) or nil,
				crateLadder = cl, fillLadder = fl,
				crateMissing = Missing(cl, 1), fillMissing = Missing(fl, o.qty),
				-- a key-pass price is exact for one unit (the crate) but only a floor for a bundle
				est = fl.est and (o.qty - fl.have) > 1,
				levelBlocked = ns.LevelBlocked(c),
				stackBlocked = stackBad, stack = stack,
				favorEst = ns.FavorIsEstimate(c),
			}
			row.per = (row.total and favor > 0) and (row.total / favor) or nil
			row.eligible = row.per ~= nil and not row.levelBlocked and not row.stackBlocked
			list[#list + 1] = row
			if row.eligible and (not best or row.total < best.total) then best = row end
		end
		if best then best.bestOfCrate = true end
		-- no eligible bundle: still mark the cheapest priced one so "best only" shows the crate
		if not best then
			for _, row in ipairs(list) do
				if row.crate == c and row.total and (not best or row.total < best.total) then best = row end
			end
			if best then best.bestOfCrate = true end
			if not best then
				for _, row in ipairs(list) do
					if row.crate == c then row.bestOfCrate = true; break end
				end
			end
		end
	end
	local cheapest
	for _, row in ipairs(list) do
		if row.eligible and (not cheapest or row.per < cheapest.per) then cheapest = row end
	end
	if cheapest then cheapest.cheapest = true end
	return list
end

-------------------------------------------------------------------------------
-- What your bags can fill right now (In bags tab)
-------------------------------------------------------------------------------

-- rows: one per crate you hold a crate or any fill material for
--   { crate, crates, bundles, can, favor, parts = { {fill, have, n, blocked} }, spareCrates, spareBundles }
-- sum: { can, favor, spareCrates, spareBundles }
function ns.BagFill()
	local rows = {}
	local sum = { can = 0, favor = 0, spareCrates = 0, spareBundles = 0 }
	for _, c in ipairs(ns.CRATES) do
		local crates = ns.BagCount(c.id)
		local bundles, parts = 0, {}
		for _, o in ipairs(c.fills) do
			local have = ns.BagCount(o.item)
			if have > 0 then
				-- a bundle bigger than one stack cannot go in (reported crate quirk)
				local blocked = ns.StackBlocked(o)
				local n = blocked and 0 or math.floor(have / o.qty)
				bundles = bundles + n
				parts[#parts + 1] = { fill = o, have = have, n = n, blocked = blocked }
			end
		end
		if crates > 0 or #parts > 0 then
			local levelBlocked = ns.LevelBlocked(c)
			local can = levelBlocked and 0 or math.min(crates, bundles)
			local row = {
				crate = c, crates = crates, bundles = bundles, can = can, favor = can * ns.FavorFor(c), parts = parts,
				spareCrates = math.max(0, crates - bundles), spareBundles = math.max(0, bundles - crates),
				levelBlocked = levelBlocked,
			}
			rows[#rows + 1] = row
			sum.can = sum.can + can
			sum.favor = sum.favor + row.favor
			sum.spareCrates = sum.spareCrates + row.spareCrates
			sum.spareBundles = sum.spareBundles + row.spareBundles
		end
	end
	table.sort(rows, function(a, b)
		if a.can ~= b.can then return a.can > b.can end
		if (a.crates + a.bundles) ~= (b.crates + b.bundles) then return (a.crates + a.bundles) > (b.crates + b.bundles) end
		return a.crate.name < b.crate.name
	end)
	return rows, sum
end

-------------------------------------------------------------------------------
-- Plans
-------------------------------------------------------------------------------

-- every combo the planner may use
local function Candidates()
	local out = {}
	for _, c in ipairs(ns.CRATES) do
		local favor = ns.FavorFor(c)
		if favor > 0 and not ns.LevelBlocked(c) then
			for _, o in ipairs(c.fills) do
				if not ns.StackBlocked(o) then
					out[#out + 1] = { crate = c, fill = o, favor = favor }
				end
			end
		end
	end
	return out
end

local function NewLadderSet(useBags)
	local set, have = {}, {}
	local function L(id)
		local l = set[id]
		if not l then
			have[id] = useBags and ns.BagCount(id) or 0
			l = ns.NewLadder(id, have[id])
			set[id] = l
		end
		return l
	end
	return L, set, have
end

-- replays the chosen units on fresh ladders: per-unit cost, groups, totals and purchase list
local function FinishPlan(units, useBags, target, short)
	local L, set, have = NewLadderSet(useBags)
	local plan = { units = units, groups = {}, favor = 0, cost = 0, target = target, short = short, useBags = useBags, have = have, ladders = set }
	local byKey = {}
	for _, u in ipairs(units) do
		local cl, fl = L(u.crate.id), L(u.fill.item)
		local cc = cl:Cost(cl.pos, cl.pos + 1) or 0
		local fc = fl:Cost(fl.pos, fl.pos + u.fill.qty) or 0
		cl.pos = cl.pos + 1
		fl.pos = fl.pos + u.fill.qty
		u.cost = cc + fc
		plan.favor = plan.favor + u.favor
		plan.cost = plan.cost + u.cost
		local k = u.crate.id .. ":" .. u.fill.item
		local g = byKey[k]
		if not g then
			g = { crate = u.crate, fill = u.fill, count = 0, favor = 0, cost = 0 }
			byKey[k] = g
			plan.groups[#plan.groups + 1] = g
		end
		g.count = g.count + 1
		g.favor = g.favor + u.favor
		g.cost = g.cost + u.cost
	end
	-- purchases: crates first (they are the scarce part), then fill materials
	plan.buys = {}
	local seen = {}
	local function add(id, isCrate)
		if seen[id] then return end
		seen[id] = true
		local l = set[id]
		local n = l:ToBuy()
		plan.usedFromBags = plan.usedFromBags or {}
		plan.usedFromBags[id] = math.min(l.pos, l.have)
		if n > 0 then
			plan.buys[#plan.buys + 1] = { itemID = id, qty = n, budget = l:Cost(l.have, l.pos) or 0, isCrate = isCrate, have = l.have }
		end
	end
	for _, g in ipairs(plan.groups) do add(g.crate.id, true) end
	for _, g in ipairs(plan.groups) do add(g.fill.item, false) end
	return plan
end
ns.FinishPlan = FinishPlan

-- one or more explicit combos (the Buy button on a crate row): units = { {crate, fill}, ... }
function ns.PlanUnits(list, useBags)
	local units = {}
	for _, u in ipairs(list) do
		for _ = 1, (u.count or 1) do
			units[#units + 1] = { crate = u.crate, fill = u.fill, favor = ns.FavorFor(u.crate) }
		end
	end
	local plan = FinishPlan(units, useBags, nil, false)
	-- an explicit combo the auction house cannot supply
	for _, u in ipairs(list) do
		local cl, fl = plan.ladders[u.crate.id], plan.ladders[u.fill.item]
		if cl.pos > cl.supply or fl.pos > fl.supply then plan.short = true end
	end
	return plan
end

-- Greedy fallback (only for goals too large for the exact planner below): adds the combo with
-- the lowest cost per useful Favor at the ladders' current depth, then drops surplus crates.
local function GreedyPlan(target, useBags)
	local L = NewLadderSet(useBags)
	local cands = Candidates()
	local units, favor, remaining = {}, 0, target
	local guard = 0
	while remaining > 0 and guard < 4000 do
		guard = guard + 1
		local best, bestScore, bestTotal
		for _, k in ipairs(cands) do
			local cl = L(k.crate.id)
			local cc = cl:Peek(1)
			if cc then
				local fl = L(k.fill.item)
				local fc = fl:Peek(k.fill.qty)
				if fc then
					local total = cc + fc
					local score = total / math.min(k.favor, remaining)
					if not best or score < bestScore - 1e-9
						or (math.abs(score - bestScore) <= 1e-9 and total < bestTotal) then
						best, bestScore, bestTotal = k, score, total
					end
				end
			end
		end
		if not best then break end
		local cl, fl = L(best.crate.id), L(best.fill.item)
		cl.pos = cl.pos + 1
		fl.pos = fl.pos + best.fill.qty
		units[#units + 1] = { crate = best.crate, fill = best.fill, favor = best.favor }
		favor = favor + best.favor
		remaining = remaining - best.favor
	end
	local short = remaining > 0

	-- drop crates the goal no longer needs, dearest first (the top rung of each ladder)
	local surplus = favor - target
	while surplus > 0 do
		local bestIdx, bestSave
		local tried = {}
		for i = #units, 1, -1 do
			local u = units[i]
			local k = u.crate.id .. ":" .. u.fill.item
			if not tried[k] and u.favor <= surplus then
				tried[k] = true
				local cl, fl = L(u.crate.id), L(u.fill.item)
				local save = (cl:Cost(cl.pos - 1, cl.pos) or 0) + (fl:Cost(fl.pos - u.fill.qty, fl.pos) or 0)
				if not bestSave or save > bestSave then bestIdx, bestSave = i, save end
			end
		end
		if not bestIdx then break end
		local u = table.remove(units, bestIdx)
		local cl, fl = L(u.crate.id), L(u.fill.item)
		cl.pos = cl.pos - 1
		fl.pos = fl.pos - u.fill.qty
		surplus = surplus - u.favor
	end

	return FinishPlan(units, useBags, target, short)
end
ns.GreedyPlan = GreedyPlan

local function gcd(a, b)
	while b ~= 0 do a, b = b, a % b end
	return a
end

-- The cheapest set of crates worth at least `target` Favor. Exact under the ladder model:
--  1. For each crate, the cost of n of them: the crate's first n rungs plus the n cheapest
--     bundles across its fill options (cheapest next bundle each time; every option's ladder
--     only gets dearer, so this is the cheapest way to fill n crates of that kind).
--  2. A knapsack over the crates: how many of each, to reach the goal for the least gold.
--     Favor is counted in steps of the common divisor of the crate values (5), so a goal of
--     500 Favor is 100 steps. Favor past the goal is worth nothing, so a single 10-Favor crate
--     beats two 5-Favor ones for a 7-Favor goal when it is cheaper.
-- If the goal cannot be reached from what is listed, the plan buys the most Favor available.
local DP_WORK_LIMIT = 4e6

function ns.PlanFavor(target, useBags)
	local groups, byCrate = {}, {}
	for _, k in ipairs(Candidates()) do
		local g = byCrate[k.crate.id]
		if not g then
			g = { crate = k.crate, favor = k.favor, fills = {} }
			byCrate[k.crate.id] = g
			groups[#groups + 1] = g
		end
		g.fills[#g.fills + 1] = k.fill
	end
	if #groups == 0 then return FinishPlan({}, useBags, target, true) end

	local step = 0
	for _, g in ipairs(groups) do step = gcd(step, g.favor) end
	local T = math.ceil(target / step)

	-- 1. cost curves
	local L = NewLadderSet(useBags)
	local work = 0
	for _, g in ipairs(groups) do
		g.f = g.favor / step
		g.cost, g.choice = { [0] = 0 }, {}
		local cl = L(g.crate.id)
		local total = 0
		for n = 1, math.ceil(T / g.f) do
			local cc = cl:Cost(n - 1, n)
			if not cc then break end
			local bestFill, bestCost
			for _, o in ipairs(g.fills) do
				local fc = L(o.item):Peek(o.qty)
				if fc and (not bestCost or fc < bestCost) then bestFill, bestCost = o, fc end
			end
			if not bestFill then break end
			local fl = L(bestFill.item)
			fl.pos = fl.pos + bestFill.qty
			total = total + cc + bestCost
			g.cost[n], g.choice[n] = total, bestFill
		end
		g.maxN = #g.choice
		work = work + g.maxN * (T + 1)
	end
	if work > DP_WORK_LIMIT then return GreedyPlan(target, useBags) end

	-- 2. knapsack: best[s] = least gold for s Favor steps (s = T means "T or more")
	local INF = math.huge
	local best = { [0] = 0 }
	for s = 1, T do best[s] = INF end
	local picks = {}
	for gi, g in ipairs(groups) do
		local new, pick = {}, {}
		for s = 0, T do new[s] = best[s] end
		for s = 0, T do
			local b = best[s]
			if b < INF then
				for n = 1, g.maxN do
					local s2 = s + n * g.f
					if s2 > T then s2 = T end
					local c = b + g.cost[n]
					if c < new[s2] then
						new[s2] = c
						pick[s2] = { n = n, from = s }
					end
					if s2 == T then break end -- more crates only cost more
				end
			end
		end
		best, picks[gi] = new, pick
	end

	local final, short = T, false
	if best[T] == INF then
		short = true
		final = 0
		for s = T - 1, 1, -1 do
			if best[s] < INF then final = s; break end
		end
	end

	-- walk back through the choices: how many of each crate
	local counts, s = {}, final
	for gi = #groups, 1, -1 do
		local p = picks[gi][s]
		if p then counts[gi], s = p.n, p.from else counts[gi] = 0 end
	end

	-- units, cheapest crate kinds first (if a crate later cannot be bought, the dearest go first)
	local order = {}
	for gi, g in ipairs(groups) do
		local n = counts[gi]
		if n > 0 then order[#order + 1] = { g = g, n = n, per = g.cost[n] / (n * g.favor) } end
	end
	table.sort(order, function(a, b) return a.per < b.per end)
	local units = {}
	for _, o in ipairs(order) do
		for k = 1, o.n do
			units[#units + 1] = { crate = o.g.crate, fill = o.g.choice[k], favor = o.g.favor }
		end
	end
	return FinishPlan(units, useBags, target, short)
end
