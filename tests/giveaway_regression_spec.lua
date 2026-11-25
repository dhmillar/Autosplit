-- Deterministic regression coverage; run from the addon root with Lua 5.1.
-- Exercises the actual giveaway controller and engine, without WoW or real trades.
local tests = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function world(stacks, quantity, options)
    options = options or {}
    local w = {now = 0, tasks = {}, tickers = {}, messages = {}, inventory = {},
        outgoing = {}, splitCalls = 0, clickCalls = 0, pickupCalls = 0, open = false,
        npc = "Player-Raider", combat = false, night = "2026-10-26"}
    local guid = 0
    local function item(count, id)
        guid = guid + 1
        return {itemID = id or 42, hyperlink = "item:" .. (id or 42), stackCount = count,
            guid = "Item-" .. guid, isLocked = false, isBound = false}
    end
    for slot, count in ipairs(stacks) do w.inventory[slot] = item(count) end
    if options.full then for slot = #stacks + 1, 8 do w.inventory[slot] = item(1, 99) end end
    local function later(fn) w.tasks[#w.tasks + 1] = {at = w.now + 0.1, fn = fn} end
    w.item, w.later = item, later
    function w:advance(seconds)
        local target = self.now + seconds
        for iteration = 1, 10000 do
            local nextAt, taskIndex, ticker = target + 1
            for index, task in ipairs(self.tasks) do
                if task.at < nextAt then nextAt, taskIndex, ticker = task.at, index, nil end
            end
            for _, candidate in ipairs(self.tickers) do
                if not candidate.cancelled and candidate.at < nextAt then
                    nextAt, taskIndex, ticker = candidate.at, nil, candidate
                end
            end
            if nextAt > target then self.now = target; return end
            self.now = nextAt
            if ticker then ticker.at = ticker.at + ticker.period; ticker.fn()
            else local task = table.remove(self.tasks, taskIndex); task.fn() end
        end
        error("Unbounded mock event loop")
    end
    local frames = {}
    CreateFrame = function()
        local f = {events = {}}
        function f:RegisterEvent(event) self.events[event] = true end
        function f:SetScript(_, fn) self.handler = fn end
        frames[#frames + 1] = f
        return f
    end
    function w:fire(event, ...)
        for _, f in ipairs(frames) do if f.events[event] then f.handler(f, event, ...) end end
    end
    C_Timer = {NewTicker = function(period, fn)
        local t = {period = period, fn = fn, at = w.now + period}
        function t:Cancel() self.cancelled = true end
        w.tickers[#w.tickers + 1] = t
        return t
    end}
    NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS = 4, 1
    GetTime = function() return w.now end
    time = function() return 1793055600 + math.floor(w.now) end
    date = function() return w.night end
    InCombatLockdown = function() return w.combat end
    IsInRaid = function() return true end
    GetNumGroupMembers = function() return 2 end
    UnitGUID = function(unit)
        if unit == "NPC" then return w.npc end
        return unit == "raid2" and "Player-Raider" or "Player-Self"
    end
    GetUnitName = function(unit)
        if unit == "NPC" and options.missingNpcName then return nil end
        if unit == "NPC" and not w.npc then return end
        return (unit == "NPC" or unit == "raid2") and "Raider-Realm" or "Self-Realm"
    end
    UnitIsUnit = function(a, b) return UnitGUID(a) == UnitGUID(b) end
    ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot) return {bag = bag, slot = slot} end}
    C_Item = {GetItemGUID = function(location)
        local entry = location.bag == 0 and w.inventory[location.slot]
        return entry and entry.guid
    end}
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
        GetContainerNumFreeSlots = function() return 0, 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and w.inventory[slot] or nil end,
        SplitContainerItem = function(bag, slot, count)
            eq(bag, 0); assert(not w.held); w.splitCalls = w.splitCalls + 1
            local source = w.inventory[slot]
            assert(count < source.stackCount)
            if options.noSplitAck then return end
            later(function()
                if options.wholeSplit then
                    w.held = source; w.inventory[slot] = nil
                else
                    local actual = options.splitAmount or count
                    source.stackCount = source.stackCount - actual
                    w.held = item(actual, source.itemID)
                end
            end)
        end,
        PickupContainerItem = function(bag, slot)
            eq(bag, 0); w.pickupCalls = w.pickupCalls + 1
            if w.held then
                assert(not w.inventory[slot], "A staging move must never swap items")
                local held = w.held; w.held = nil
                if options.stageRefused then w.held = held; return end
                later(function()
                    assert(not w.inventory[slot]); w.inventory[slot] = held
                    if options.stageHook then options.stageHook(w, slot) end
                end)
            else
                assert(w.inventory[slot])
                if options.delayedPickup then
                    later(function() w.held, w.inventory[slot] = w.inventory[slot], nil end)
                    return
                end
                w.held, w.inventory[slot] = w.inventory[slot], nil
            end
        end,
    }
    GetCursorInfo = function()
        if w.held then return "item", w.held.itemID, w.held.hyperlink end
    end
    GetTradePlayerItemInfo = function(slot)
        local entry = w.outgoing[slot]
        if entry then return "Item", 1, entry.stackCount, 1, "", nil, false, not options.missingItemID and entry.itemID or nil end
    end
    GetTradePlayerItemLink = function(slot) return w.outgoing[slot] and w.outgoing[slot].hyperlink end
    GetPlayerTradeMoney = function() return 0 end
    TradeFrame = {IsShown = function() return w.open end}
    ClickTradeButton = function(slot)
        w.clickCalls = w.clickCalls + 1
        assert(w.held and not w.outgoing[slot])
        local held = w.held; w.held = nil
        if options.noTradeAck then return end
        later(function()
            if options.wrongTradeCount then held.stackCount = options.wrongTradeCount end
            w.outgoing[slot] = held
            w:fire("TRADE_PLAYER_ITEM_CHANGED", slot)
        end)
    end
    CloseTrade = function()
        w.open = false; w:fire("TRADE_CLOSED"); w.outgoing = {}; w.npc = nil
    end
    LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE = 100, "Trade complete."
    LE_GAME_ERR_TRADE_CANCELLED, ERR_TRADE_CANCELLED = 101, "Trade cancelled."
    AutosplitCharDB = {}
    local addon = {SplitEngine = {}, Message = function(message) w.messages[#w.messages + 1] = message end}
    assert(loadfile("RaidEngine.lua"))("Autosplit", addon)
    assert(loadfile("RaidGiveaway.lua"))("Autosplit", addon)
    w:fire("PLAYER_LOGIN")
    w.controller = addon.Giveaway
    w.controller:SelectBag(0, 1)
    assert(w.controller:SetQuantity(quantity or 1))
    function w:openTrade()
        self.npc, self.open = "Player-Raider", true
        self:fire("TRADE_SHOW")
    end
    function w:accept(a, b) self:fire("TRADE_ACCEPT_UPDATE", a, b) end
    function w:complete(afterClose)
        self:accept(1, 0); self:accept(0, 1)
        if afterClose then CloseTrade() end
        self:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
        if not afterClose then CloseTrade() end
        self:advance(0.5)
    end
    return w
end

local function test(name, fn) fn(); tests = tests + 1; print("PASS " .. name) end
test("one from twenty is acknowledged in a bag before one enters trade", function()
    local w = world({20}); w:openTrade()
    eq(w.clickCalls, 0); eq(w.controller.engine.active.phase, "placing")
    w:advance(0.08); eq(w.clickCalls, 0)
    w:advance(1); eq(w.inventory[1].stackCount, 19)
    eq(w.outgoing[1].stackCount, 1); eq(w.splitCalls, 1); eq(w.clickCalls, 1)
    eq(w.controller.engine.active.phase, "offered")
end)
test("missing split acknowledgement never retries or offers the source stack", function()
    local w = world({20}, 1, {noSplitAck = true}); w:openTrade(); w:advance(6)
    eq(w.splitCalls, 1); eq(w.clickCalls, 0); eq(w.inventory[1].stackCount, 20)
end)
test("a split returning the entire stack is never added to trade", function()
    local w = world({20}, 1, {wholeSplit = true}); w:openTrade(); w:advance(6)
    eq(w.clickCalls, 0); eq(w.outgoing[1], nil)
end)
test("a full general bag refuses a partial-stack giveaway before any movement", function()
    local w = world({20}, 1, {full = true}); w:openTrade(); w:advance(1)
    eq(w.splitCalls, 0); eq(w.pickupCalls, 0); eq(w.clickCalls, 0)
end)
test("an exact existing single needs no empty general slot", function()
    local w = world({1}, 1, {full = true}); w:openTrade(); w:advance(1)
    eq(w.splitCalls, 0); eq(w.outgoing[1].stackCount, 1)
end)
test("multi-stack quantity waits for each trade slot and offers exactly five", function()
    local w = world({4, 3}, 5); w:openTrade(); w:advance(2)
    eq(w.outgoing[1].stackCount, 3); eq(w.outgoing[2].stackCount, 2)
    eq(w.inventory[1].stackCount, 1); eq(w.inventory[2].stackCount, 1); eq(w.clickCalls, 2)
end)
test("never picks up an exact-size pre-existing multi-item stack", function()
    local w = world({5}, 5); w:openTrade(); w:advance(2)
    eq(w.pickupCalls, 0); eq(w.clickCalls, 0); eq(w.inventory[1].stackCount, 5)
end)
test("an asynchronous pickup cannot submit an unverified cursor stack", function()
    local w = world({20}, 1, {delayedPickup=true}); w:openTrade(); w:advance(2)
    eq(w.clickCalls, 0); eq(w.outgoing[1], nil)
end)
test("successful trade gets the name from the matching raid GUID if the trade unit name is unavailable", function()
    local w = world({20}, 1, {missingNpcName=true}); w:openTrade(); w:advance(1)
    w:accept(true, true); CloseTrade()
    w:fire("UI_ERROR_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE); w:advance(1)
    eq(w.controller.engine:History()[1].name, "Raider-Realm")
end)
test("changing partner during a delayed split stops every later trade click", function()
    local w = world({20}); w:openTrade(); w:advance(0.08)
    w.npc = "Player-Other"; w:advance(6); eq(w.clickCalls, 0)
end)
test("combat during preparation stops every later trade click", function()
    local w = world({20}); w:openTrade(); w:advance(0.08)
    w.combat = true; w:advance(6); eq(w.clickCalls, 0)
end)
test("unexpected confirmed outgoing quantity closes the trade", function()
    local w = world({20}, 1, {wrongTradeCount = 20}); w:openTrade(); w:advance(2)
    eq(w.open, false); eq(#w.controller.engine:History(), 0)
end)
test("separate acceptance events plus success after close record the frozen recipient", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:complete(true)
    local h = w.controller.engine:History()
    eq(#h, 1); eq(h[1].name, "Raider-Realm"); eq(h[1].guid, "Player-Raider"); eq(h[1].quantity, 1)
    eq(w.npc, nil)
end)
test("both accepted and inventory loss without a success message never record served", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1, 1)
    CloseTrade(); w:advance(6)
    eq(#w.controller.engine:History(), 0)
    eq(w.controller.engine:Recipient("Player-Raider").state, "uncertain")
end)
test("same-item incoming inventory does not erase a confirmed outgoing gift", function()
    local w = world({20}); w:openTrade(); w:advance(1); w.inventory[1].stackCount = 20
    w:complete(true); eq(w.controller.engine:History()[1].quantity, 1)
end)
test("a confirmed manual quantity mismatch records the actual amount and requested amount", function()
    local w = world({20}); w:openTrade(); w:advance(1)
    w.outgoing[1].stackCount = 20
    w:fire("TRADE_PLAYER_ITEM_CHANGED", 1); w:complete(true)
    local record = w.controller.engine:History()[1]
    eq(record.quantity, 20); eq(record.requestedQuantity, 1); eq(record.quantityMismatch, true)
end)
test("repeated completion and close events produce one durable history record", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:complete(true)
    w:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
    w:fire("TRADE_CLOSED"); w:advance(1)
    local addon = {}
    assert(loadfile("RaidEngine.lua"))("Autosplit", addon)
    local reloaded = addon.CreateRaidEngine({night = function() return "2026-10-26" end}, AutosplitCharDB, function() end)
    eq(#reloaded:History(), 1); eq(reloaded:History()[1].name, "Raider-Realm")
end)
test("a new trade session cannot supply completion evidence for the prior recipient", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1, 0); CloseTrade()
    w:openTrade()
    w:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
    w:advance(6); eq(#w.controller.engine:History(), 0)
end)

test("missing outgoing acknowledgement never retries placement or touches the next source", function()
    local w = world({4,3}, 5, {noTradeAck = true}); w:openTrade(); w:advance(6)
    eq(w.clickCalls, 1); eq(w.splitCalls, 1); eq(w.inventory[2].stackCount, 3)
    eq(w.open, false); eq(#w.controller.engine:History(), 0)
end)
test("incorrect split amount is never picked up for a trade", function()
    local w = world({20}, 1, {splitAmount = 2}); w:openTrade(); w:advance(6)
    eq(w.clickCalls, 0); eq(w.splitCalls, 1)
end)
test("an occupied staging destination is never swapped into", function()
    local w = world({20}); w:openTrade(); w:advance(0.08)
    w.inventory[2] = w.item(1, 99); w:advance(6)
    eq(w.clickCalls, 0); eq(w.inventory[2].itemID, 99); assert(w.held)
end)
test("refused staging placement never trades the cursor or retries the split", function()
    local w = world({20}, 1, {stageRefused = true}); w:openTrade(); w:advance(6)
    eq(w.clickCalls, 0); eq(w.splitCalls, 1); assert(w.held)
end)
test("staging locks must clear before pickup", function()
    local w = world({20}, 1, {stageHook = function(env, slot) env.inventory[slot].isLocked = true end})
    w:openTrade(); w:advance(0.6); eq(w.clickCalls, 0)
    for _, entry in pairs(w.inventory) do entry.isLocked = false end
    w:advance(1); eq(w.outgoing[1].stackCount, 1)
end)
test("bound state changing during staging blocks the giveaway", function()
    local w = world({20}, 1, {stageHook = function(env, slot) env.inventory[slot].isBound = true end})
    w:openTrade(); w:advance(6); eq(w.clickCalls, 0)
end)
test("missing isolated GUID never permits a pickup for trade", function()
    local w = world({20}, 1, {stageHook = function(env, slot) env.inventory[slot].guid = nil end})
    w:openTrade(); w:advance(6); eq(w.clickCalls, 0)
end)
test("missing outgoing item metadata cancels the same trade", function()
    local w = world({20}, 1, {missingItemID = true}); w:openTrade(); w:advance(2)
    eq(w.open, false); eq(#w.controller.engine:History(), 0)
end)
test("closing during a delayed split never performs a later trade click", function()
    local w = world({20}); w:openTrade(); w:advance(0.08); CloseTrade(); w:advance(6)
    eq(w.clickCalls, 0); eq(w.splitCalls, 1)
end)
test("a foreign cursor during preparation is never cleared or sent", function()
    local w = world({20}); w:openTrade(); w.held = w.item(1, 99); w:advance(6)
    eq(w.clickCalls, 0); eq(w.splitCalls, 0); eq(w.held.itemID, 99)
end)
test("success arriving before teardown waits for the same trade to close", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1,0)
    w:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
    eq(#w.controller.engine:History(), 0)
    CloseTrade(); w:advance(1); eq(#w.controller.engine:History(), 1)
end)
test("authoritative cancellation after acceptance never records a gift", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1,1)
    w.inventory[1].stackCount = 20
    w:fire("UI_ERROR_MESSAGE", LE_GAME_ERR_TRADE_CANCELLED, ERR_TRADE_CANCELLED)
    CloseTrade(); w:advance(6)
    eq(#w.controller.engine:History(), 0); eq(w.controller.engine:Recipient("Player-Raider"), nil)
end)
test("failure after acceptance plus inventory loss remains unconfirmed", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1,1)
    w:fire("UI_ERROR_MESSAGE", 999, "Trade failed."); CloseTrade(); w:advance(6)
    eq(#w.controller.engine:History(), 0)
    eq(w.controller.engine:Recipient("Player-Raider").state, "uncertain")
end)
test("success without an accepted item snapshot is visible only as unconfirmed", function()
    local w = world({20}); w:openTrade(); w:advance(1)
    w.inventory[1].stackCount = 20 -- no independent evidence that a gift left the bags
    w:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
    CloseTrade(); w:advance(6)
    eq(#w.controller.engine:History(), 0); eq(#w.controller.engine:Attempts(), 1)
    eq(w.controller.engine:Attempts()[1].name, "Raider-Realm")
end)
test("night changes during closing preserve the original saved raid night", function()
    local w = world({20}); w:openTrade(); w:advance(1); w:accept(1,0); CloseTrade()
    w.night = "2026-10-27"
    w:fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE)
    eq(#w.controller.engine:History(), 0)
    eq(AutosplitCharDB.nights["2026-10-26"]["Player-Raider"].state, "served")
end)
test("reload with an unresolved reservation cannot offer another copy", function()
    local w = world({20}); w:openTrade(); w:advance(1); CloseTrade(); w:advance(6)
    local old = AutosplitCharDB.nights["2026-10-26"]["Player-Raider"]
    local addon = {}; assert(loadfile("RaidEngine.lua"))("Autosplit", addon)
    local reload = addon.CreateRaidEngine({night = function() return "2026-10-26" end,
        combat = function() return false end, member = function() return true end}, AutosplitCharDB, function() end)
    eq(reload:Begin({guid="Player-Raider",name="Raider-Realm"}), nil)
    eq(reload:Attempts()[1].guid, "Player-Raider"); eq(old.state, "uncertain")
end)

print(("Giveaway regressions: %d tests passed"):format(tests))
