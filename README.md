# Cheap Crates (World of Warcraft: Forever)

Finds the cheapest way to earn **Merchant's Favor** from Waylaid Crates, and buys it for you.

- Knows every Waylaid Crate in the game (30 of them) and every bundle that fills each one
  (96 bundles in all).
- **Scan** prices every crate and every fill material on the auction house in a few seconds.
- Lists every crate + bundle combination with its total cost and **cost per Merchant's
  Favor**, since crates pay different amounts of Favor (5 to 40).
- **Use bag items** tick box: crates and materials you already carry are used first and cost
  nothing, so a stack of Silverleaf in your bags takes the Silverleaf off the bill.
- **In bags** tab: how many crates you can fill right now with what you carry, and a Buy
  button for whatever is missing to pair them up.
- **Buy** on any row puts that crate and its bundle on a shopping list.
- **Favor needed**: type how much Favor you need, press **Plan**, and it works out the
  cheapest mix of crates and bundles that adds up to at least that much. The total cost is
  shown and every item goes on the shopping list.
- Buy the list one item per **BUY** press. That can be the button, a key binding, or a
  **scroll wheel tick**, so scrolling buys everything at the planned price.

Targets the live Forever client (interface `16001`, patch 1.60.1) and its modern auction house,
where materials sell as commodities. The auction house calls follow the Item Sniper addon,
which was checked against Blizzard's UI source for this build.

## Install

1. Copy the `CheapCrates` folder into
   `World of Warcraft\_forever_\Interface\AddOns\CheapCrates`.
   The folder must be named `CheapCrates`, the same as the `.toc` file.
2. Restart the game or `/reload`.
3. Optional: bind a BUY key under Options > Keybindings > AddOns > "Cheap Crates: BUY next
   item", or type `/crates key F10`.

## Use

Click the crate button on the minimap (the same icon as in the addon list) or type `/crates`.
The window opens next to the auction house when that is open. It does not open by itself
(`/crates autoshow on` if you want it to). Right-click the minimap button to jump straight to
the In bags tab. Drag the button to move it around the minimap. Its tooltip shows your
Merchant's Favor, how many crates your bags can fill, and any shopping list in progress.

1. Press **Scan**. It prices 126 items: the 30 crates plus every fill material. That takes a
   few seconds (details under "Why the scan is quick" below). Prices marked `~` are floors:
   the real price can only be the same or higher. Shift-click **Scan** (or `/crates scan full`)
   for a full scan that reads every listing of every item, about a minute.
2. The **Crates** tab lists every crate + bundle, cheapest per Favor first. The cheapest
   overall is green. Columns: crate price, fill price (for the whole bundle, walking up the
   listings: if the cheapest 15 Silverleaf are 20c and the rest 30c, 20 Silverleaf costs
   15×20c + 5×30c), total, Favor, and cost per Favor. Click a header to sort. Hover a row to see
   every bundle for that crate, how many are listed, and what you have in your bags.
   - `bags` means you already have it, so it costs nothing (with **Use bag items** ticked).
   - `none` means nothing is listed. `?` means the item has not been scanned yet.
   - Grey crate names are above your level and are left out of plans.
   - A red bundle needs more than one stack holds. Crates are reported to need the whole
     bundle in a single stack, so those bundles are left out of plans too. The addon reads each
     item's real stack size from the game.
   - Tick **Best fill only** to show one row per crate, with its cheapest bundle.
3. To buy one crate and its bundle, press **Buy** on its row.
   To reach a Favor total, type it into **Favor needed** and press **Plan** (or `/crates goal 200`).
4. The **Shopping list** tab shows the crates to fill and the items to buy: crates first,
   then materials, each with its planned price. Press **BUY** once per item, using the button,
   your key, or the **scroll wheel**.
5. The **In bags** tab shows what you can fill right now. The tab reads "In bags (3)" when you
   carry 3 crates that have a full bundle each. Per crate it lists empty crates, complete
   bundles (and partial ones like `12/20 Silverleaf`), how many you can fill, the Favor that
   is worth, and what is missing ("+2 crates" or "+1 bundle"). **Buy** on a row gets just
   that: crates for spare bundles, or the cheapest bundle for each spare crate. A bundle
   bigger than one stack does not count, and neither does a crate above your level.

### Why the scan is quick

The auction house takes up to 100 items per request (`SearchForItemKeys`), so all 126 items
cost two requests, about a second. That answer gives each item's lowest price and how many are
listed. It does not say how many units sit at that lowest price, though. "Silverleaf: 2c, 500
listed" could be 1 unit at 2c and 499 at 50c, which is a very different price for a bundle of
20. That needs one more request per item, and the server allows only about 100 requests a
minute. Reading every item that way is what a full scan does, and why it takes a minute.

The quick scan reads the full listings only where they decide the answer. It takes the
cheapest crate + bundle per Favor that still has a `~` price, reads that one material, and
repeats until the top 10 are all exact. A `~` price is a floor, so nothing further down can be
cheaper than those 10. That is usually 10 to 20 requests. A crate's own price is exact straight
away, since one crate is one listing. **Buy** and **Plan** read the exact price of anything they
are about to buy more than one of before building the list. Each item's price is checked again
right before its purchase anyway.

### Buying, and what protects your gold

- **One press = one purchase.** The game only allows auction house purchases from a key press
  or mouse click, so the addon cannot buy on its own. It checks each item's current price
  automatically, then your press buys it. For materials it confirms the server's price quote
  itself, so one press is the whole purchase.
- **At the planned price.** Each item has a budget from the plan. If the price rose by more
  than the tolerance (5% by default, `/crates tolerance <percent>`), nothing is bought. The
  BUY button then reads **Accept &lt;new price&gt;**: click it to pay the new price, or press
  **Skip**. A scroll wheel tick never accepts a higher price, so scrolling cannot overpay.
- **Crates first.** If a crate sells out before you buy it, the materials meant for it come off
  the list, so you never pay for materials with no crate to put them in.
- **Sold out.** If someone buys the auction you were about to buy, the addon finds the next
  one within your tolerance. If fewer units are listed than you need, it asks first.
- **Scroll = BUY** (on by default) works only while a shopping list is active at the auction
  house and the Cheap Crates window is open. Closing the window gives the wheel straight back.
  If you open the auction house with a list still waiting, you get a chat reminder rather than
  a window that buys on a stray scroll. Wheel ticks over the game world or this window buy the
  next item. Scrolling lists and chat still scroll. The wheel goes back to normal when the list
  is done, the window closes, or the auction house closes.

When the list is done, fill each crate: use the crate with the bundle in your bags. Hand the
sealed crates in for Merchant's Favor. Alliance: Marcy Baker, Azeroth Commerce Authority, Three
Corners (Redridge Mountains). Horde: Dokimi, Durotar Supply and Logistics, west of the
Crossroads (the Barrens). If an item you bought is not in your bags, collect it from the mailbox.

## How the Favor goal planner works

For each crate it builds a cost curve: the cost of 1, 2, 3... of that crate, each filled with
the cheapest remaining bundle across all of its options. It reads further down the auction
listings as it goes, so the 10th Apprentice Herbs crate costs more than the 1st. A knapsack
over those curves then finds how many of each crate reach the goal for the least gold.

- Favor past the goal is worth nothing. For a 7-Favor goal, one 10-Favor crate beats two
  5-Favor crates when it is cheaper, even though it "wastes" 3 Favor.
- Large goals spread across crate types on their own, as the cheapest listings run out.
- With **Use bag items**, what you carry is used first and only the missing units are bought.
- If the goal cannot be reached from what is listed, the plan buys the most Favor available
  and says so.

## Commands

| Command | What it does |
|---|---|
| `/crates` | open or close the window |
| `/crates scan` | quick scan: all 126 items, exact prices for the top 10 (a few seconds) |
| `/crates scan full` | read every listing of every item (about a minute; also shift-click Scan) |
| `/crates goal <favor>` | cheapest way to that much Favor, as a shopping list |
| `/crates top [n]` | the n cheapest crates per Favor, in chat |
| `/crates buy` / `skip` / `cancel` | BUY press / skip the current item / drop the list |
| `/crates bags on\|off` | count items already in your bags (also a tick box) |
| `/crates wheel on\|off` | scroll wheel presses BUY (also a tick box) |
| `/crates tolerance <percent>` | how far a price may rise above the plan before BUY asks (default 5) |
| `/crates favor <tier> <raw\|crafted> <n>` | set the Favor a crate pays (`/crates favor reset` restores the defaults) |
| `/crates levels on\|off` | leave out crates above your level (default on) |
| `/crates stackcheck on\|off` | leave out bundles bigger than one stack (default on) |
| `/crates key <KEY>` | bind the BUY key |
| `/crates minimap on\|off` | show or hide the minimap button (`/crates minimap` toggles) |
| `/crates autoshow on\|off` | open the window when the auction house opens (default off) |
| `/crates reset` | put the window back next to the auction house |

## Crate data

All from WoW Forever sources: Method's Forever crate guide (item IDs and bundles), checked by
name on Wowhead's Forever database, plus outof.games, wowforever.gg, ForeverChanges and The
Forever Guides. The data is in `CheapCrates/Data.lua`.

| Tier | Level | Raw goods (Herbs, Ore, Textiles, Curiosities) | Crafted goods (Fabrics, Ingots, Parts) |
|---|---|---|---|
| Apprentice | 10 | 5 Favor | 10 Favor |
| Journeyman | 10 | 10 Favor | 20 Favor |
| Expert | 20 | 15 Favor | 30 Favor |
| Artisan | 35 | 20 Favor (estimated) | 40 Favor (estimated) |

Not confirmed by players yet, so check them in game:

- **Artisan Favor.** No source had reported it yet. The window marks it with `*`. If a sealed
  Artisan crate pays something else, set it with `/crates favor artisan crafted 45` (for
  example), and every price per Favor and every plan uses the new value.
- **Journeyman Textiles.** Listed as 20 Medium Leather. One guide saw the crate take 40.
- **Journeyman Parts.** Every source lists "45 Gold Power Core". That looks odd, but no source
  says otherwise. The stack check catches it if 45 does not fit in one stack.
- **Crates on the auction house.** If crates turn out to stack (sold as commodities), the
  addon handles that too. It reads how the auction house lists each item.

## Development

`tests/` holds a headless harness (adapted from Item Sniper's). It fakes the game client and a
throttled auction house, including commodity quotes and the rule that purchases need a key
press. The tests drive the addon through: scan, prices per Favor, bag counts, buying a single
crate, price rises at the check and at the quote, a sold-out auction, the Favor planner
(including the "one 10-Favor crate beats two 5-Favor crates" case), a crate selling out
mid-list, the scroll wheel, the request gate, quick vs full scans, the In bags tab, and slash
commands. Run them with Lua 5.1, the
game's Lua version:

```bash
python3 tests/run.py
```

It needs `lua5.1` on PATH or `pip install lupa`.

## Things to verify in game

- Stack sizes and item names come from the client's item cache. The addon asks for all 126
  items at login, but a bundle is only stack-checked once its item has loaded.
- Some materials (Linen, Silk, Mageweave, Runecloth) have 40-unit bundles. If they stack to 20
  on Forever, those bundles show in red and stay out of plans. If the crates do accept two
  stacks, `/crates stackcheck off` lets the planner use them.
- If Item Sniper's scroll = BUY is also on, the two addons share the wheel. Turn one off while
  using the other.
