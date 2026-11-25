local addon = {}
assert(loadfile("Engine.lua"))("Autosplit", addon)
local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local function world(count, slots)
    local w = {now = 0, inventory = {}, events = {}, calls = 0, inCombat = false}
    local function item(n, id, guid)
        return {itemID = id or 42, hyperlink = "item:" .. (id or 42),
            stackCount = n, isLocked = false, guid = guid or "original"}
    end
    w.item = item
    w.inventory[1] = item(count)
    w.api = {
        info = function(_, slot) return w.inventory[slot] end,
        guid = function(_, slot) return w.inventory[slot] and w.inventory[slot].guid end,
        time = function() return w.now end,
        combat = function() return w.inCombat end,
        cursor = function() if w.cursor then return "item", w.cursor.itemID end end,
        accepts = function() return not w.rejectBag end,
        destinations = function()
            local result = {}
            for slot = 2, slots + 1 do
                if not w.inventory[slot] then result[#result + 1] = {bag = 0, slot = slot} end
            end
            return result
        end,
        split = function(_, slot, quantity)
            eq(quantity, 1)
            assert(not w.cursor)
            w.calls = w.calls + 1
            if w.failSplit then return end
            w.inventory[slot].stackCount = w.inventory[slot].stackCount - 1
            w.cursor = item(1)
            if w.fillDuringSplit then w.inventory[2] = item(1, 99) end
        end,
        pickup = function(_, slot)
            assert(not w.inventory[slot], "must never merge or swap")
            if w.failPlace then return end
            if w.delay then
                w.queued = {slot = slot, item = w.cursor}
                w.inventory[1].isLocked = true
            else w.inventory[slot] = w.cursor end
            w.cursor = nil
        end,
    }
    w.engine = addon.CreateEngine(w.api, function(state, message, completed, quantity, success)
        w.events[#w.events + 1] = {state = state, message = message, success = success}
        if state == "finished" then w.success = success end
    end)
    w.source = assert(w.engine:Snapshot(0, 1))
    function w:drain()
        for _ = 1, 2500 do
            if not self.engine.job then return end
            self.now = self.now + 0.1
            self.engine:Step()
        end
        error("queue never finished")
    end
    function w:total()
        local sum = w.cursor and w.cursor.stackCount or 0
        for _, info in pairs(w.inventory) do sum = sum + info.stackCount end
        return sum
    end
    return w
end

test("20 of 20 creates 20 singles with 19 empty slots", function()
    local w = world(20, 19)
    assert(w.engine:Start(w.source, 20)); w:drain()
    eq(w.calls, 19); eq(w:total(), 20); eq(w.success, true)
    for slot = 1, 20 do eq(w.inventory[slot].stackCount, 1) end
end)
test("2 of 20 leaves 18 and two singles", function()
    local w = world(20, 2)
    assert(w.engine:Start(w.source, 2)); w:drain()
    eq(w.inventory[1].stackCount, 18)
    eq(w.inventory[2].stackCount, 1); eq(w.inventory[3].stackCount, 1)
    eq(w:total(), 20); eq(w.success, true)
end)
test("one item can be separated", function()
    local w = world(20, 1)
    assert(w.engine:Start(w.source, 1)); w:drain()
    eq(w.inventory[1].stackCount, 19); eq(w.calls, 1); eq(w.success, true)
end)
test("two-item full split needs just one slot", function()
    local w = world(2, 1)
    assert(w.engine:Start(w.source, 2)); w:drain()
    eq(w:total(), 2); eq(w.success, true)
end)
test("not enough space refuses before moving anything", function()
    local w = world(20, 18)
    local ok, error = w.engine:Start(w.source, 20)
    eq(ok, nil); assert(error:find("19")); eq(w.calls, 0)
end)
test("partial split needs quantity empty slots", function()
    local w = world(20, 1)
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 0)
end)
test("invalid quantities never touch inventory", function()
    for _, value in ipairs({0, -1, 21, 1.5, "2", math.huge, 0/0}) do
        local w = world(20, 30)
        eq(w.engine:Start(w.source, value), nil); eq(w.calls, 0)
    end
    local w = world(20, 20)
    eq(w.engine:Start(w.source, nil), nil)
end)
test("combat blocks start", function()
    local w = world(20, 20); w.inCombat = true
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 0)
end)
test("occupied cursor blocks start without changing it", function()
    local w = world(20, 20); w.cursor = w.item(3, 99)
    eq(w.engine:Start(w.source, 2), nil); eq(w.cursor.itemID, 99); eq(w.calls, 0)
end)
test("stale popup count is rejected", function()
    local w = world(20, 20); w.inventory[1].stackCount = 19
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 0)
end)
test("same item with a different GUID is rejected", function()
    local w = world(20, 20); w.inventory[1].guid = "replacement"
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 0)
end)
test("locked source blocks start", function()
    local w = world(20, 20); w.inventory[1].isLocked = true
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 0)
    eq(w.engine:Snapshot(0, 1), nil)
end)
test("one-item stacks are not selectable", function()
    local w = world(20, 1); w.inventory[1].stackCount = 1
    eq(w.engine:Snapshot(0, 1), nil)
end)
test("server acknowledgement is required before next split", function()
    local w = world(20, 20); w.delay = true
    assert(w.engine:Start(w.source, 2))
    for _ = 1, 15 do w.now = w.now + 0.1; w.engine:Step() end
    eq(w.calls, 1)
    w.inventory[w.queued.slot] = w.queued.item
    w.inventory[1].isLocked = false; w.delay = false
    w:drain(); eq(w.calls, 2); eq(w.success, true); eq(w:total(), 20)
end)
test("missing acknowledgement times out without repeating split", function()
    local w = world(20, 20); w.delay = true
    assert(w.engine:Start(w.source, 2)); w:drain()
    eq(w.calls, 1); eq(w.success, false)
end)
test("combat interrupts active queue", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.inCombat = true; w:drain()
    eq(w.calls, 1); eq(w.success, false); eq(w:total(), 20)
end)
test("cancel preserves completed moves", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.engine:Cancel(); w.engine:Step()
    eq(w.calls, 1); eq(w.success, false); eq(w:total(), 20)
end)
test("concurrent start is rejected", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20))
    eq(w.engine:Start(w.source, 2), nil); eq(w.calls, 1)
end)
test("destination occupied mid-queue never receives a swap", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.engine:Step()
    w.inventory[3] = w.item(1, 99); w:drain()
    eq(w.calls, 1); eq(w.inventory[3].itemID, 99); eq(w.success, false)
end)
test("changed bag compatibility stops the next move", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.engine:Step(); w.rejectBag = true; w:drain()
    eq(w.calls, 1); eq(w.success, false)
end)
test("source moved mid-queue stops splitting", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.engine:Step(); w.inventory[1] = nil; w:drain()
    eq(w.calls, 1); eq(w.success, false)
end)
test("split failure stops immediately", function()
    local w = world(20, 20); w.failSplit = true
    assert(w.engine:Start(w.source, 20)); eq(w.engine.job, nil)
    eq(w.calls, 1); eq(w:total(), 20); eq(w.success, false)
end)
test("placement failure preserves cursor item for manual recovery", function()
    local w = world(20, 20); w.failPlace = true
    assert(w.engine:Start(w.source, 20)); eq(w.engine.job, nil)
    eq(w.cursor.stackCount, 1); eq(w:total(), 20); eq(w.success, false)
end)
test("destination race after pickup leaves the cursor item safe", function()
    local w = world(20, 20); w.fillDuringSplit = true
    assert(w.engine:Start(w.source, 20)); eq(w.engine.job, nil)
    eq(w.cursor.stackCount, 1); eq(w.inventory[2].itemID, 99); eq(w.success, false)
end)
test("foreign cursor during queue is never cleared", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 20)); w.cursor = w.item(3, 99); w:drain()
    eq(w.calls, 1); eq(w.cursor.itemID, 99); eq(w.success, false)
end)
test("locked source between moves waits then resumes", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 2)); w.engine:Step()
    w.inventory[1].isLocked = true
    w.now = 1; w.engine:Step(); eq(w.calls, 1)
    w.inventory[1].isLocked = false; w:drain(); eq(w.success, true)
end)
test("permanent lock between moves times out", function()
    local w = world(20, 20)
    assert(w.engine:Start(w.source, 2)); w.engine:Step()
    w.inventory[1].isLocked = true; w:drain(); eq(w.success, false); eq(w.calls, 1)
end)
test("maximum-size stack uses a bounded queue", function()
    local w = world(1000, 999)
    assert(w.engine:Start(w.source, 1000)); w:drain()
    eq(w.calls, 999); eq(w:total(), 1000); eq(w.success, true)
end)
print(("Engine: %d tests passed"):format(tests))
