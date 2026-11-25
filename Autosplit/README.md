# Autosplit 1.2.1

Hold **Ctrl** and **left-click or right-click** a stack in your bags. Autosplit opens a quantity window filled with the number of items currently in that stack. Change the number if desired, then click **Split** (or press Enter).

The quantity is the number of individual items to separate, not the size of each new stack:

| Original stack | Quantity entered | Result | Empty slots needed |
| --- | --- | --- | --- |
| 20 | 20 | Twenty stacks of one | 19 |
| 20 | 2 | Two stacks of one, with 18 left in the original | 2 |
| 20 | 1 | One stack of one, with 19 left in the original | 1 |

For a full split, the final item stays in the original slot. The default quantity is the selected stack's current count, even when the item's maximum allowed stack size is higher.

## Install

Target: **WoW Retail 12.1.5**, interface **120105**. Supports Blizzard's combined and individual bags and Baganator's live inventory buttons. Classic and other inventory replacements are not qualified.

Extract `dist/Autosplit-1.2.1.zip` into your WoW Retail `Interface/AddOns` folder. The result must be:

```text
World of Warcraft/_retail_/Interface/AddOns/Autosplit/Autosplit.toc
World of Warcraft/_retail_/Interface/AddOns/Autosplit/Autosplit.lua
World of Warcraft/_retail_/Interface/AddOns/Autosplit/Engine.lua
World of Warcraft/_retail_/Interface/AddOns/Autosplit/RaidEngine.lua
World of Warcraft/_retail_/Interface/AddOns/Autosplit/RaidGiveaway.lua
World of Warcraft/_retail_/Interface/AddOns/Autosplit/RaidWindow.lua
World of Warcraft/_retail_/Interface/AddOns/Autosplit/Icon.tga
```

Start WoW and enable **Autosplit** in the AddOns list. If WoW was already running when you added the new folder, restart the game to discover the addon.

## Minimap button and raid giveaway

Click the circular **AS** minimap button, or type **`/as`** (also **`/autosplit`**), to open the bag and giveaway menu. Drag the minimap button to reposition it.

The menu shows your backpack and equipped bags, including empty slots and stack counts. Click an item in this view, or drag an item from your bags into the giveaway selection slot. Dropping selects a template and returns the actual item to your bags. Selection enables the giveaway. Use **Pause giveaway** or **Clear item** to stop it; these controls retain recipient history. Ctrl-clicking a stack in the bag view opens the original quantity dialog.

The **Quantity** field beside the selected item defaults to **1**. Change it to a positive whole number to give that many per eligible raid member. Valid edits are saved automatically and survive reloads; choosing a different item resets the quantity to 1. Invalid or blank input pauses automatic offers until corrected. Quantity cannot be changed during a trade.

When a member of your **current raid** opens trade, Autosplit offers **exactly the configured quantity** of unlocked, unbound items. With Quantity 1 and a stack of 20, it splits one directly into the trade and leaves 19 in your bags. With Quantity 3, it offers three and leaves 17. A partial-stack giveaway now requires one free slot in a general bag. Autosplit first materializes the requested quantity there, waits for the original remainder and exact isolated count/GUID/unlocked state, and only then picks up that isolated stack for trade. It never trades the unverified split cursor or falls back to the original larger stack. An existing exact-size stack can still be offered with full bags. It prefers an exact-size stack, otherwise uses larger stacks, splitting only the amount needed. Quantities can span up to six trade slots; if more slots would be required, combine stacks in your bags first. Insufficient available stock or too many required trade slots is refused before any item is picked up.

It never initiates trades, gives money, offers more than the requested quantity, or adds items to a trade that already contains outgoing items or gold. Other players do not need the addon. Every outgoing trade slot must acknowledge its exact count before the next source is touched. Missing acknowledgement times out without a retry; an incorrect outgoing quantity cancels that same trade. If preparation is interrupted, check the trade, cursor, and any isolated stack before continuing. Foreign cursors are never cleared automatically.

**Finish the trade using Blizzard's Trade button and any confirmation Blizzard displays.** Current Retail uses a restricted trade acceptance API and secure confirmation UI; Autosplit automates item placement and recipient tracking, and does not call or bypass the protected acceptance step. See the [secure transfer API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecureTransferDocumentation.lua) and [Blizzard confirmation UI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SecureTransferUI/Blizzard_SecureTransferUI.lua).

Each recipient's character GUID is tracked **once per local raid night**, shared across all giveaway item selections, quantities, and raid roster changes for your distributing character. A night resets at **6 a.m. local computer time**, so crossing midnight does not permit repeats. Joining another raid the same night also preserves the no-repeat record. The selected item, quantity, enabled state, minimap position, and recipient ledger are retained through normal reloads and relogs through `AutosplitCharDB` (per character), at WoW's normal save boundaries. This is not crash-proof disk persistence. Seven recent nights are retained.

The menu defaults to **Traded tonight**, a scrollable list showing each confirmed recipient's name, the quantity and item, and the local trade time, newest first. This list includes recipients who left the raid and survives reloads and item selection changes. Pending, uncertain, and cancelled trades are not displayed as completed gifts. It switches to the new night's list at the 6 a.m. rollover. Existing records from earlier versions display quantity 1. A server-confirmed trade with a captured accepted outgoing snapshot records the actual amount, including a visible requested/actual discrepancy. Its result does not depend on the net bag decrease, so receiving the same item does not hide it.

The **Raid roster** tab shows **Ready**, **Given**, or **Pending** for current members. The **Unconfirmed** tab separately shows pending or uncertain attempts, including the captured recipient and requested amount, without claiming delivery. Completed history requires an accepted outgoing-item snapshot, server trade-complete information, and closure of the same trade session. Acceptance or a bag decrease alone never establishes success. A reported cancellation can release its reservation after settlement when no item was lost (up to five seconds); otherwise missing or conflicting evidence remains unconfirmed and blocks repeats that night. No old uncertain record is retroactively marked delivered. Bound items, including temporarily tradable bound raid loot, are excluded from this giveaway feature.

Trading and stack splitting share a cursor guard so they cannot run simultaneously. Automation is paused during combat. Closing the bag menu does not pause an enabled giveaway.

## Behavior

- Loads automatically; there is no always-visible window or setup requirement.
- Uses only carried inventory, including compatible reagent/specialty bags. It does not split bank, warbank, guild bank, mail, or cached inventories of other characters.
- Checks all needed empty slots before starting. It never deliberately fills existing stacks, swaps items, or makes room by moving unrelated items.
- Waits for each move to be confirmed before separating the next item. Avoid sorting or moving inventory until it finishes.
- Splitting is unavailable during combat and stops if combat starts, the original stack changes, or a destination changes. Closing the popup or pressing Escape stops the queue. Items already separated remain where they are.
- If WoW refuses a move, an item can remain on your cursor. Place it safely into your bags before trying again.
- `/as` or `/autosplit` opens the bag/giveaway menu. `/autosplit stop` cancels an active split queue.
- Ctrl-clicking a stack takes priority over the usual Ctrl-click action for supported inventory buttons. Other clicks retain their original handlers.

There are no external runtime dependencies or continuously running update loops. Timers run only during stack splitting, verified giveaway preparation, brief trade settlement, or minimap dragging. The bag grid is refreshed only while visible; a hidden, idle menu performs no inventory scans.

## Validation

156 deterministic scenarios pass under Lua 5.1: 28 original splitting tests, 49 adapted raid-engine tests, 48 original/adapted UI tests, and 31 asynchronous giveaway regressions. The new regressions cover delayed/missing split and trade acknowledgements, incorrect amounts, full bags, staging locks and races, metadata/GUID changes, cancellation after acceptance, event ordering, simultaneous same-item inventory, actual-quantity discrepancies, identity/night persistence, duplicate events and interrupted reloads. The old 120-test result belongs to release 1.2.0; the current tests were actually executed for this release using a direct windowless Pythonw runner.

These are simulated tests; actual WoW interaction and taint behavior still need an in-game check. Suggested check: try 2 of 20, then a full split; repeat with both mouse buttons and confirm ordinary clicks. For any owner-performed giveaway check, first leave a free general-bag slot, select a cheap tradable stack of 20 and verify Quantity 1 offers one and leaves 19. Cancel and retry with Quantity 3 to verify three are offered and 17 remain. Complete a trade, verify its quantity in the history, and reopen trade to check no repeat is added. Also check a cancelled trade becomes eligible again after settlement.

For developers, run `tests/run_tests.py` with Python and the `lupa` package (its Lua 5.1 runtime), or execute each `tests/*_spec.lua` from the addon root using Lua 5.1. `python build.py` recreates the installable ZIP.

API and bag-button behavior were checked against the [WoW UI source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua), [container API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua), and [trade UI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/TradeFrame.lua). Baganator integration was checked against its locally installed API and button templates.
