-- Exercise the actual addon UI glue against a minimal WoW frame/event simulation.
local frames, tickers, messages = {}, {}, {}
local ctrl, combat, now, held = false, false, 0, nil
local inventory = {[0] = {}, [1] = {}, [5] = {}}
local bagSizes = {[0] = 25, [1] = 4, [5] = 4}
local reagent = false
local scans = 0
local itemSerial = 0
local function item(count, id)
    itemSerial = itemSerial + 1
    return {itemID = id or 42, hyperlink = "item:" .. (id or 42),
        stackCount = count, guid = "Item-" .. itemSerial, iconFileID = 123}
end
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local Frame = {}
Frame.__index = Frame
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:GetScript(event) return self.scripts[event] end
function Frame:HookScript(event, fn)
    local old = self.scripts[event]
    self.scripts[event] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Frame:Fire(event, ...) if self.scripts[event] then self.scripts[event](self, ...) end end
function Frame:Show()
    if not self.shown then self.shown = true; self:Fire("OnShow") end
end
function Frame:Hide()
    if self.shown then self.shown = false; self:Fire("OnHide") end
end
function Frame:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:SetText(text) self.text = text; self:Fire("OnTextChanged") end
function Frame:GetText() return self.text or "" end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:SetFocus() self.focus = true end
function Frame:ClearFocus() self.focus = false end
function Frame:HasFocus() return not not self.focus end
function Frame:GetID() return self.id or 0 end
function Frame:GetBagID() return self.bag end
function Frame:GetFrameLevel() return self.level or 10 end
function Frame:SetFrameLevel(level) self.level = level end
for _, method in ipairs({"SetSize", "SetPoint", "SetFrameStrata", "SetClampedToScreen",
    "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetWidth",
    "SetJustifyH", "SetJustifyV", "SetAutoFocus", "SetMaxLetters", "HighlightText",
    "SetTextColor", "SetTexture", "SetAllPoints", "RegisterForClicks", "SetOwner",
    "SetBagItem", "AddLine"}) do Frame[method] = function() end end
local function MakeFrame(name, parent)
    local frame = setmetatable({scripts = {}, shown = true, parent = parent, enabled = true}, Frame)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function Frame:CreateTexture() return MakeFrame(nil, self) end
function Frame:CreateFontString() return MakeFrame(nil, self) end
function CreateFrame(_, name, parent, template)
    local frame = MakeFrame(name, parent)
    if template == "BasicFrameTemplateWithInset" then frame.TitleText = MakeFrame(nil, frame) end
    return frame
end
UIParent = MakeFrame()
GameTooltip = MakeFrame()
DEFAULT_CHAT_FRAME = {AddMessage = function(_, text) messages[#messages + 1] = text end}
NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_CONTAINER_FRAMES = 4, 1, 6
Enum = {BagIndex = {ReagentBag = 5}}
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
bit = {band = function(a, b) return a == b and a or 0 end}
GetTime = function() return now end
InCombatLockdown = function() return combat end
IsControlKeyDown = function() return ctrl end
SpellIsTargeting = function() return false end
GetCursorInfo = function() if held then return "item", held.itemID end end
ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot) return {bag = bag, slot = slot} end}
C_Item = {
    GetItemGUID = function(location)
        local info = inventory[location.bag] and inventory[location.bag][location.slot]
        return info and info.guid
    end,
    GetItemInfo = function() return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,reagent end,
    GetItemFamily = function() return 0 end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bagSizes[bag] or 0 end,
    GetContainerNumFreeSlots = function(bag) return 4, bag == 1 and 32 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        scans = scans + 1
        return inventory[bag] and inventory[bag][slot]
    end,
    SplitContainerItem = function(bag, slot, count)
        eq(count, 1); assert(not held)
        inventory[bag][slot].stackCount = inventory[bag][slot].stackCount - 1
        held = item(1)
    end,
    PickupContainerItem = function(bag, slot)
        assert(not inventory[bag][slot]); inventory[bag][slot] = held; held = nil
    end,
}
C_Timer = {NewTicker = function(_, fn)
    local ticker = {fn = fn, Cancel = function(self) self.cancelled = true end}
    tickers[#tickers + 1] = ticker
    return ticker
end}
function Frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
local function Event(event)
    for _, frame in ipairs(frames) do
        if frame.events and frame.events[event] then frame:Fire("OnEvent", event) end
    end
end
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        original(...)
        callback(...)
    end
end
local normalClicks = 0
local bagFrame = MakeFrame("ContainerFrame1", UIParent)
bagFrame.Items = {}
function bagFrame:UpdateItemSlots() end
local sourceButton = MakeFrame(nil, bagFrame)
sourceButton.bag, sourceButton.id = 0, 1
sourceButton:SetScript("OnClick", function() normalClicks = normalClicks + 1 end)
bagFrame.Items[1] = sourceButton
local baganatorButton = MakeFrame(nil, UIParent)
baganatorButton.bag, baganatorButton.id = 0, 1
local listener
Baganator = {API = {Skins = {
    RegisterListener = function(fn) listener = fn end,
    GetAllFrames = function() return {{regionType = "ItemButton", region = baganatorButton}} end,
}}}
inventory[0][1] = item(20)
local addon = {}
assert(loadfile("Engine.lua"))("Autosplit", addon)
assert(loadfile("Autosplit.lua"))("Autosplit", addon)
Event("PLAYER_LOGIN")
local function Shield(button)
    for _, frame in ipairs(frames) do
        if frame.parent == button and frame:GetScript("OnClick") then return frame end
    end
    error("missing shield")
end
local function Drain()
    for _ = 1, 5000 do
        local active = false
        for _, ticker in ipairs(tickers) do
            if not ticker.cancelled then active = true; now = now + 0.1; ticker.fn() end
        end
        if not active then return end
    end
    error("ticker did not stop")
end
local tests = 0
local function test(name, fn) fn(); tests = tests + 1; print("PASS " .. name) end

test("normal bag clicks are untouched and Ctrl shields start hidden", function()
    eq(Shield(sourceButton):IsShown(), false)
    sourceButton:Fire("OnClick", "RightButton"); eq(normalClicks, 1)
end)
test("Ctrl-left-click opens popup defaulted to the full stack", function()
    ctrl = true; Event("MODIFIER_STATE_CHANGED")
    assert(Shield(sourceButton):IsShown())
    Shield(sourceButton):Fire("OnClick", "LeftButton")
    assert(AutosplitQuantityDialog:IsShown())
    eq(AutosplitQuantityDialog.quantity:GetText(), "20")
    eq(AutosplitQuantityDialog.split:GetText(), "Split")
    eq(normalClicks, 1)
end)
test("invalid popup input disables Split", function()
    for _, text in ipairs({"", "0", "21", "-1", "1.5", "2e1", "abc"}) do
        AutosplitQuantityDialog.quantity:SetText(text)
        eq(AutosplitQuantityDialog.split.enabled, false)
    end
end)
test("Split button produces two singles and leaves eighteen", function()
    AutosplitQuantityDialog.quantity:SetText("2")
    assert(AutosplitQuantityDialog.split.enabled)
    AutosplitQuantityDialog.split:Fire("OnClick")
    Drain()
    eq(inventory[0][1].stackCount, 18)
    eq(inventory[0][2].stackCount, 1); eq(inventory[0][3].stackCount, 1)
    eq(next(inventory[1]), nil); eq(next(inventory[5]), nil)
    eq(AutosplitQuantityDialog.split.enabled, false)
end)
test("Ctrl-right-click resets default to the current stack count", function()
    Event("BAG_UPDATE_DELAYED")
    Shield(sourceButton):Fire("OnClick", "RightButton")
    eq(AutosplitQuantityDialog.quantity:GetText(), "18")
end)
test("Baganator live buttons use the same popup", function()
    assert(listener)
    assert(Shield(baganatorButton):IsShown())
    Shield(baganatorButton):Fire("OnClick", "LeftButton")
    eq(AutosplitQuantityDialog.quantity:GetText(), "18")
end)
test("new pooled bag buttons acquire Ctrl support", function()
    local new = MakeFrame(nil, bagFrame); new.bag, new.id = 0, 1
    bagFrame.Items[2] = new; bagFrame:UpdateItemSlots()
    assert(Shield(new):IsShown())
end)
test("reagent bag space is used only for crafting reagents", function()
    reagent = true
    Shield(sourceButton):Fire("OnClick", "LeftButton")
    AutosplitQuantityDialog.quantity:SetText("1")
    AutosplitQuantityDialog.quantity:Fire("OnEnterPressed"); Drain()
    eq(inventory[5][1].stackCount, 1); eq(inventory[0][1].stackCount, 17)
    reagent = false
end)
test("popup close stops an active split", function()
    Shield(sourceButton):Fire("OnClick", "LeftButton")
    AutosplitQuantityDialog.split:Fire("OnClick")
    local countAfterFirst = inventory[0][1].stackCount
    AutosplitQuantityDialog:Hide(); Drain()
    eq(inventory[0][1].stackCount, countAfterFirst)
end)
test("combat rejects popup without running normal item click", function()
    combat = true
    Shield(sourceButton):Fire("OnClick", "RightButton")
    eq(AutosplitQuantityDialog:IsShown(), false); eq(normalClicks, 1)
    assert(messages[#messages]:find("combat")); combat = false
end)
test("Ctrl release hides shields", function()
    ctrl = false; Event("MODIFIER_STATE_CHANGED")
    eq(Shield(sourceButton):IsShown(), false)
end)
test("idle bag events perform no inventory scans or active polling", function()
    local before = scans
    Event("BAG_UPDATE_DELAYED"); eq(scans, before)
    for _, ticker in ipairs(tickers) do eq(ticker.cancelled, true) end
end)
print(("UI integration: %d tests passed"):format(tests))

-- Load the giveaway controller and menu in the same environment as the real splitter.
for _, method in ipairs({"SetColorTexture", "SetTexCoord", "SetHighlightTexture", "SetPushedTexture",
    "SetDesaturated", "SetHeight", "ClearAllPoints", "SetScrollChild", "SetHyperlink",
    "SetWordWrap", "SetVerticalScroll"}) do
    Frame[method] = function() end
end
function Frame:SetNormalTexture(texture) self.normalTexture = texture end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:GetWidth() return self.width or 140 end
function Frame:GetCenter() return 100, 100 end
function Frame:GetEffectiveScale() return 1 end
Minimap = MakeFrame("Minimap", UIParent)
TradeFrame = MakeFrame("TradeFrame", UIParent); TradeFrame:Hide()
local raid, extraRaider = true, false
local npcGUID, npcName = "Player-Raider", "Raider-Realm"
local outgoing, gold = {}, 0
local epoch = os.time({year = 2026, month = 10, day = 26, hour = 23, min = 0, sec = 0})
date = function(format, timestamp) return os.date(format, timestamp) end
time = function() return epoch end
IsInRaid = function() return raid end
GetNumGroupMembers = function() return extraRaider and 3 or 2 end
UnitGUID = function(unit)
    if unit == "player" or unit == "raid1" then return "Player-Self" end
    if unit == "raid2" then return "Player-Raider" end
    if unit == "raid3" and extraRaider then return "Player-New" end
    if unit == "NPC" then return npcGUID end
end
GetUnitName = function(unit) return unit == "NPC" and npcName or unit == "raid2" and "Raider-Realm" or unit == "raid3" and "New-Realm" or "Self-Realm" end
UnitIsUnit = function(a, b) return UnitGUID(a) == UnitGUID(b) end
C_Container.GetBagName = function(bag) return "Bag " .. bag end
C_Item.GetItemIconByID = function() return 123 end
local fullAcceptCalls = 0
AcceptTrade = function() fullAcceptCalls = fullAcceptCalls + 1; error("Acceptance must use Blizzard's protected UI") end
C_SecureTransfer = {AcceptTrade = AcceptTrade}
GetTradePlayerItemInfo = function(slot)
    local info = outgoing[slot]
    if info then return "Item", 123, info.stackCount, 1, "", nil, false, info.itemID end
end
GetTradePlayerItemLink = function(slot) return outgoing[slot] and outgoing[slot].hyperlink end
GetPlayerTradeMoney = function() return gold end
ClickTradeButton = function(slot) assert(held); assert(not outgoing[slot]); outgoing[slot] = held; held = nil end
ClearCursor = function() held = nil end
GetCursorInfo = function() if held then return "item", held.itemID, held.hyperlink end end
C_Container.PickupContainerItem = function(bag, slot)
    if held then
        assert(not inventory[bag][slot]); inventory[bag][slot] = held; held = nil
    else held = inventory[bag][slot]; inventory[bag][slot] = nil end
end
local raidSplitAmounts = {}
C_Container.SplitContainerItem = function(bag, slot, quantity)
    assert(not held); assert(quantity >= 1 and quantity < inventory[bag][slot].stackCount)
    raidSplitAmounts[#raidSplitAmounts + 1] = quantity
    inventory[bag][slot].stackCount = inventory[bag][slot].stackCount - quantity
    held = item(quantity, inventory[bag][slot].itemID)
end
assert(loadfile("RaidEngine.lua"))("Autosplit", addon)
assert(loadfile("RaidGiveaway.lua"))("Autosplit", addon)
assert(loadfile("RaidWindow.lua"))("Autosplit", addon)
Event("PLAYER_LOGIN")
local raidTests = 0
local function raidTest(name, fn) fn(); raidTests = raidTests + 1; print("PASS " .. name) end
LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE = 100, "Trade complete."
LE_GAME_ERR_TRADE_CANCELLED, ERR_TRADE_CANCELLED = 101, "Trade cancelled."
local function FireTradeInfo(id, message)
    for _, frame in ipairs(frames) do
        if frame.events and frame.events.UI_INFO_MESSAGE then frame:Fire("OnEvent", "UI_INFO_MESSAGE", id, message) end
    end
end
local function OpenTrade()
    outgoing = {}; gold = 0; TradeFrame:Show(); Event("TRADE_SHOW")
    for _ = 1, 100 do
        local active = addon.Giveaway.engine.active
        if not active or active.phase ~= "placing" then return end
        now = now + 0.05
        for _, ticker in ipairs(tickers) do if not ticker.cancelled then ticker.fn() end end
    end
    error("Placement did not settle")
end
local function CloseTrade(completed)
    if not completed then FireTradeInfo(LE_GAME_ERR_TRADE_CANCELLED, ERR_TRADE_CANCELLED) end
    TradeFrame:Hide(); outgoing = {}; Event("TRADE_CLOSED")
    if completed then FireTradeInfo(LE_GAME_ERR_TRADE_COMPLETE, ERR_TRADE_COMPLETE) end
end
_G.CloseTrade = function() CloseTrade(false) end

raidTest("minimap button uses the stable NE artwork path", function()
    assert(AutosplitMinimapButton)
    eq(AutosplitMinimapButton.normalTexture, "Interface\\AddOns\\Autosplit\\Icon")
end)
raidTest("/as opens the menu with inventory and selection slot", function()
    eq(SLASH_AUTOSPLIT1, "/autosplit")
    eq(SLASH_AUTOSPLIT2, "/as")
    eq(SLASH_AUTOSPLIT3, "/netools")
    SlashCmdList.AUTOSPLIT("")
    assert(AutosplitMainWindow:IsShown())
    assert(AutosplitMainWindow.selection:GetScript("OnReceiveDrag"))
    assert(#AutosplitMainWindow.bagButtons > 0)
    eq(AutosplitMainWindow.bagButtons[1].entry.bag, 0)
    eq(AutosplitMainWindow.quantity:GetText(), "1")
end)
raidTest("/as defaults to remaining players with an explicit no-item state", function()
    eq(AutosplitMainWindow.listMode, "remaining")
    eq(AutosplitMainWindow.remainingTab:GetText(), "Remaining players")
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 0")
    eq(AutosplitMainWindow.remainingEmpty:GetText(), "Choose a giveaway item first.")
    eq(AutosplitMainWindow.remainingEmpty:IsShown(), true)
end)
raidTest("minimap click toggles the same window", function()
    AutosplitMinimapButton:Fire("OnClick"); eq(AutosplitMainWindow:IsShown(), false)
    AutosplitMinimapButton:Fire("OnClick"); eq(AutosplitMainWindow:IsShown(), true)
end)
raidTest("General separates display settings without scanning Autosplit bags", function()
    local window = AutosplitMainWindow
    eq(window.TitleText:GetText(), "NE Tools")
    eq(window.generalTab:GetText(), "General")
    eq(window.autosplitTab:GetText(), "Autosplit")
    eq(window.autosplitPanel:IsShown(), true)
    eq(window.generalPanel:IsShown(), false)
    window.attemptsTab:Fire("OnClick")
    eq(window.historyContent:IsShown(), true)
    eq(window.historyEmpty:IsShown(), true)
    window.quantity:SetFocus()
    local before = scans
    window.generalTab:Fire("OnClick")
    eq(window.generalPanel:IsShown(), true)
    eq(window.autosplitPanel:IsShown(), false)
    eq(window.quantity:IsShown(), false)
    eq(window.quantity:HasFocus(), false)
    eq(window.selection:IsShown(), false)
    eq(window.historyScroll:IsShown(), false)
    eq(window.historyContent:IsShown(), false)
    eq(window.historyEmpty:IsShown(), false)
    Event("BAG_UPDATE_DELAYED")
    addon.RefreshWindow(true)
    eq(scans, before)
    window.autosplitTab:Fire("OnClick")
    eq(window.generalPanel:IsShown(), false)
    eq(window.selection:IsShown(), true)
    assert(scans > before)
    eq(window.historyContent:IsShown(), true)
    window.remainingTab:Fire("OnClick")
end)
raidTest("General can hide, restore, and reset the minimap launcher without changing raid options", function()
    local window = AutosplitMainWindow
    local db = addon.Giveaway.db
    local enabled, item, quantity = db.enabled, db.item, db.quantity
    window.generalTab:Fire("OnClick")
    eq(window.minimapVisibility:GetText(), "Hide minimap button")
    window.minimapVisibility:Fire("OnClick")
    eq(db.minimapHidden, true)
    eq(AutosplitMinimapButton:IsShown(), false)
    eq(window.minimapVisibility:GetText(), "Show minimap button")
    db.minimapAngle = 47
    window.minimapReset:Fire("OnClick")
    eq(db.minimapAngle, 220)
    SlashCmdList.AUTOSPLIT(""); eq(window:IsShown(), false)
    SlashCmdList.AUTOSPLIT(""); eq(window:IsShown(), true)
    eq(window.generalPanel:IsShown(), true)
    window.minimapVisibility:Fire("OnClick")
    eq(db.minimapHidden, false)
    eq(AutosplitMinimapButton:IsShown(), true)
    eq(db.enabled, enabled); eq(db.item, item); eq(db.quantity, quantity)
    window.autosplitTab:Fire("OnClick")
end)
raidTest("bag view selects an item without moving or consuming it", function()
    local before = addon.Giveaway:Count({itemID = 42})
    AutosplitMainWindow.bagButtons[1]:Fire("OnClick", "LeftButton")
    eq(addon.Giveaway.db.item.itemID, 42); eq(addon.Giveaway.db.enabled, true)
    eq(addon.Giveaway:Count({itemID = 42}), before)
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 1")
    eq(AutosplitMainWindow.rosterLabels[1]:GetText(), "Raider-Realm")
end)
raidTest("dropping an item onto the selection slot returns it to the bags", function()
    local before = addon.Giveaway:Count({itemID = 42})
    held = item(1)
    AutosplitMainWindow.selection:Fire("OnReceiveDrag")
    eq(held, nil); eq(addon.Giveaway.db.item.itemID, 42)
    eq(addon.Giveaway:Count({itemID = 42}), before)
end)
raidTest("incoming raid trade stages exactly one item and never auto-accepts", function()
    OpenTrade()
    eq(outgoing[1].stackCount, 1); eq(outgoing[1].itemID, 42)
    eq(outgoing[2], nil); eq(gold, 0); eq(fullAcceptCalls, 0)
    eq(addon.TradeBusy, true)
end)
raidTest("splitter and giveaway item changes are blocked during trade", function()
    local chosen = addon.Giveaway.db.item
    addon.OpenQuantity(0, 1); eq(AutosplitQuantityDialog:IsShown(), false)
    addon.Giveaway:Select(nil); eq(addon.Giveaway.db.item, chosen)
end)
raidTest("trade completion records delivered and stops settlement timer", function()
    for _, frame in ipairs(frames) do
        if frame.events and frame.events.TRADE_ACCEPT_UPDATE then frame:Fire("OnEvent", "TRADE_ACCEPT_UPDATE", 1, 1) end
    end
    CloseTrade(true); Drain()
    eq(addon.Giveaway.engine:Recipient(npcGUID).state, "served")
    eq(addon.TradeBusy, false)
    eq(AutosplitMainWindow.toggle.enabled, true)
end)
raidTest("confirmed recipient disappears from the remaining list but stays in the saved ledger", function()
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 0")
    eq(AutosplitMainWindow.rosterLabels[1]:IsShown(), false)
    eq(AutosplitMainWindow.remainingEmpty:GetText(), "No eligible players remaining.")
    eq(addon.Giveaway.engine:History()[1].name, "Raider-Realm")
end)
raidTest("joining and leaving updates only eligible players in the current raid", function()
    extraRaider = true; Event("GROUP_ROSTER_UPDATE")
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 1")
    eq(AutosplitMainWindow.rosterLabels[1]:GetText(), "New-Realm")
    extraRaider = false; Event("GROUP_ROSTER_UPDATE")
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 0")
    eq(AutosplitMainWindow.rosterLabels[1]:IsShown(), false)
    raid = false; Event("GROUP_ROSTER_UPDATE")
    eq(AutosplitMainWindow.remainingEmpty:GetText(), "Join a raid to see remaining players.")
    raid = true; Event("GROUP_ROSTER_UPDATE")
end)
raidTest("remaining and unconfirmed tabs are distinct", function()
    AutosplitMainWindow.attemptsTab:Fire("OnClick")
    eq(AutosplitMainWindow.historyScroll:IsShown(), true)
    eq(AutosplitMainWindow.rosterScroll:IsShown(), false)
    AutosplitMainWindow.remainingTab:Fire("OnClick")
    eq(AutosplitMainWindow.historyScroll:IsShown(), false)
    eq(AutosplitMainWindow.rosterScroll:IsShown(), true)
end)
raidTest("repeat trade from the same raid member adds nothing", function()
    OpenTrade(); eq(outgoing[1], nil); CloseTrade(); Drain()
end)
raidTest("non-raid trade adds nothing", function()
    npcGUID = "Player-Outsider"; npcName = "Other-Realm"
    OpenTrade(); eq(outgoing[1], nil); CloseTrade(); Drain()
end)
raidTest("pause and clear retain recipient history", function()
    addon.Giveaway:ToggleEnabled(); eq(addon.Giveaway.db.enabled, false)
    addon.Giveaway:Select(nil)
    eq(addon.Giveaway.engine:Recipient("Player-Raider").state, "served")
end)
raidTest("night lasts across midnight and rolls over at six local", function()
    epoch = os.time({year = 2026, month = 10, day = 27, hour = 1, min = 0, sec = 0})
    eq(addon.Giveaway:Night(), "2026-10-26")
    epoch = os.time({year = 2026, month = 10, day = 27, hour = 6, min = 0, sec = 0})
    eq(addon.Giveaway:Night(), "2026-10-27")
end)
raidTest("a new raid night makes a previously served raider eligible again", function()
    addon.Giveaway:Select({itemID=42, link="item:42"})
    addon.RefreshWindow()
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 1")
    eq(AutosplitMainWindow.rosterLabels[1]:GetText(), "Raider-Realm")
end)
raidTest("a partial stack is verified in the free general bag slot before trade", function()
    inventory = {[0] = {[1] = item(20)}, [1] = {}, [5] = {}}
    for slot = 2, 24 do inventory[0][slot] = item(1, 99) end
    for slot = 1, 4 do inventory[1][slot] = item(1, 99); inventory[5][slot] = item(1, 99) end
    npcGUID, npcName = "Player-Raider", "Raider-Realm"
    addon.Giveaway:SelectBag(0, 1)
    OpenTrade()
    eq(inventory[0][1].stackCount, 19); eq(outgoing[1].stackCount, 1)
end)
raidTest("cancelled giveaway returns stock and releases recipient reservation", function()
    local returned = outgoing[1]
    CloseTrade()
    inventory[0][1].stackCount = inventory[0][1].stackCount + returned.stackCount
    Drain()
    eq(inventory[0][1].stackCount, 20)
    eq(addon.Giveaway.engine:Recipient(npcGUID), nil)
end)
raidTest("bound and locked copies are skipped without touching inventory", function()
    inventory[0][1].isBound = true
    OpenTrade(); eq(outgoing[1], nil); CloseTrade(); Drain()
    inventory[0][1].isBound = false; inventory[0][1].isLocked = true
    OpenTrade(); eq(outgoing[1], nil); CloseTrade(); Drain()
    eq(inventory[0][1].stackCount, 20); inventory[0][1].isLocked = false
end)
raidTest("party mode and manual outgoing gold disable raid automation", function()
    raid = false
    OpenTrade(); eq(outgoing[1], nil); CloseTrade(); Drain(); raid = true
    outgoing = {}; gold = 10000; TradeFrame:Show(); Event("TRADE_SHOW")
    eq(outgoing[1], nil); eq(gold, 10000); CloseTrade(); Drain(); gold = 0
end)
local function PrepareQuantity(stacks, quantity)
    epoch = epoch + 86400
    inventory = {[0] = {}, [1] = {}, [5] = {}}
    for slot, count in ipairs(stacks) do inventory[0][slot] = item(count) end
    raidSplitAmounts = {}
    addon.Giveaway:SelectBag(0, 1)
    AutosplitMainWindow.quantity:SetText(tostring(quantity))
end
local function ReturnOfferAndCancel()
    local count = 0
    for _, info in pairs(outgoing) do count = count + info.stackCount end
    CloseTrade()
    if count > 0 then
        if inventory[0][1] then inventory[0][1].stackCount = inventory[0][1].stackCount + count
        else inventory[0][1] = item(count) end
    end
    Drain()
end
raidTest("quantity one splits exactly one from a twenty stack", function()
    PrepareQuantity({20}, 1); OpenTrade()
    eq(outgoing[1].stackCount, 1); eq(inventory[0][1].stackCount, 19)
    eq(raidSplitAmounts[1], 1); eq(fullAcceptCalls, 0)
    ReturnOfferAndCancel()
end)
raidTest("edited quantity splits three from a twenty stack", function()
    PrepareQuantity({20}, 3); OpenTrade()
    eq(outgoing[1].stackCount, 3); eq(inventory[0][1].stackCount, 17)
    eq(raidSplitAmounts[1], 3); eq(addon.Giveaway.engine.active.quantity, 3)
    ReturnOfferAndCancel()
end)
raidTest("an exact-size source is left intact and the quantity is split from a larger stack", function()
    PrepareQuantity({5, 20}, 5); OpenTrade()
    eq(outgoing[1].stackCount, 5); eq(inventory[0][1].stackCount, 5)
    eq(inventory[0][2].stackCount, 15); eq(raidSplitAmounts[1], 5)
    ReturnOfferAndCancel()
end)
raidTest("quantity spanning stacks offers the exact total and records that quantity", function()
    PrepareQuantity({4, 3}, 5); OpenTrade()
    eq(outgoing[1].stackCount, 3); eq(outgoing[2].stackCount, 2)
    eq(inventory[0][1].stackCount, 1); eq(inventory[0][2].stackCount, 1); eq(raidSplitAmounts[1], 3)
    for _, frame in ipairs(frames) do
        if frame.events and frame.events.TRADE_ACCEPT_UPDATE then frame:Fire("OnEvent", "TRADE_ACCEPT_UPDATE", 1, 1) end
    end
    CloseTrade(true); Drain()
    eq(addon.Giveaway.engine:History()[1].quantity, 5)
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 0")
    eq(fullAcceptCalls, 0)
end)
raidTest("insufficient stock makes no partial outgoing offer", function()
    PrepareQuantity({4}, 5); OpenTrade()
    eq(outgoing[1], nil); eq(inventory[0][1].stackCount, 4)
    eq(addon.Giveaway.engine:Recipient(npcGUID), nil)
    ReturnOfferAndCancel()
end)
raidTest("more than six required trade slots is refused before pickup", function()
    PrepareQuantity({1,1,1,1,1,1,1}, 7); OpenTrade()
    eq(outgoing[1], nil); eq(#raidSplitAmounts, 0)
    eq(addon.Giveaway:Count({itemID = 42}), 7)
    ReturnOfferAndCancel()
end)
raidTest("six-stack quantity fits the six tradable slots", function()
    PrepareQuantity({1,1,1,1,1,1}, 6); OpenTrade()
    for slot = 1, 6 do eq(outgoing[slot].stackCount, 1) end
    eq(outgoing[7], nil); eq(#raidSplitAmounts, 0)
    ReturnOfferAndCancel()
end)
raidTest("invalid quantity text blocks the trade until corrected", function()
    PrepareQuantity({20}, 1)
    for _, value in ipairs({"", "0", "-1", "1.5", "2e1", "abc"}) do
        AutosplitMainWindow.quantity:SetFocus()
        AutosplitMainWindow.quantity:SetText(value)
        OpenTrade(); eq(outgoing[1], nil); eq(inventory[0][1].stackCount, 20)
        ReturnOfferAndCancel()
    end
    AutosplitMainWindow.quantity:SetText("2"); OpenTrade()
    eq(outgoing[1].stackCount, 2); ReturnOfferAndCancel()
end)
raidTest("quantity changes are blocked during an open trade", function()
    PrepareQuantity({20}, 3); OpenTrade()
    eq(AutosplitMainWindow.quantity.mouseEnabled, false)
    eq(addon.Giveaway:SetQuantity("8"), nil); eq(addon.Giveaway.db.quantity, 3)
    eq(outgoing[1].stackCount, 3); ReturnOfferAndCancel()
end)
raidTest("new item selection resets even a focused quantity editor to one", function()
    PrepareQuantity({20}, 8); inventory[0][2] = item(5, 99)
    AutosplitMainWindow.quantity:SetFocus()
    addon.Giveaway:SelectBag(0, 2)
    eq(addon.Giveaway.db.quantity, 1); eq(AutosplitMainWindow.quantity:GetText(), "1")
    eq(AutosplitMainWindow.quantity:HasFocus(), false)
end)
raidTest("same-item reselection keeps the chosen quantity", function()
    PrepareQuantity({20}, 4); addon.Giveaway:SelectBag(0, 1)
    eq(addon.Giveaway.db.quantity, 4); eq(AutosplitMainWindow.quantity:GetText(), "4")
end)
raidTest("minimap drag registers updates only during drag", function()
    GetCursorPosition = function() return 200, 200 end
    AutosplitMinimapButton:Fire("OnDragStart")
    assert(AutosplitMinimapButton:GetScript("OnUpdate"))
    AutosplitMinimapButton:Fire("OnUpdate")
    assert(addon.Giveaway.db.minimapAngle)
    AutosplitMinimapButton:Fire("OnDragStop")
    eq(AutosplitMinimapButton:GetScript("OnUpdate"), nil)
end)
raidTest("unconfirmed tab shows a reserved recipient without claiming delivery", function()
    local ledger = addon.Giveaway.engine:Ledger()
    ledger["Player-Unconfirmed"] = {state="uncertain", name="Unconfirmed-Realm", itemID=42,
        link="item:42", quantity=1, requestedQuantity=1, timestamp=epoch}
    AutosplitMainWindow.attemptsTab:Fire("OnClick")
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Unconfirmed attempts: 1")
    assert(AutosplitMainWindow.historyRows[1].name:GetText():find("Unconfirmed-Realm",1,true))
    assert(AutosplitMainWindow.historyRows[1].item:GetText():find("Unconfirmed; requested 1",1,true))
    eq(#addon.Giveaway.engine:History(), 0)
    ledger["Player-Unconfirmed"] = nil
end)
raidTest("unconfirmed aliases are kept out of remaining players until verified", function()
    addon.Giveaway:Select({itemID=42, link="item:42"})
    local ledger = addon.Giveaway.engine:Ledger()
    ledger["Player-Alias"] = {state="uncertain", name="Raider-Realm", itemID=42,
        link="item:42", quantity=1, requestedQuantity=1, timestamp=epoch}
    AutosplitMainWindow.remainingTab:Fire("OnClick")
    eq(AutosplitMainWindow.rosterTitle:GetText(), "Remaining players: 0")
    eq(AutosplitMainWindow.remainingEmpty:GetText(), "No eligible players. Check Unconfirmed.")
    ledger["Player-Alias"] = nil
end)
raidTest("hidden giveaway window and idle bags do not scan inventory", function()
    AutosplitMainWindow:Hide()
    local before = scans; Event("BAG_UPDATE_DELAYED"); eq(scans, before)
    for _, ticker in ipairs(tickers) do eq(ticker.cancelled, true) end
end)
raidTest("a saved hidden minimap preference applies when WoW loads the launcher", function()
    local db = addon.Giveaway.db
    db.minimapHidden = true
    local previous = AutosplitMinimapButton
    assert(loadfile("RaidWindow.lua"))("Autosplit", addon)
    Event("PLAYER_LOGIN")
    assert(AutosplitMinimapButton ~= previous)
    eq(AutosplitMinimapButton:IsShown(), false)
    SlashCmdList.AUTOSPLIT("")
    eq(AutosplitMainWindow:IsShown(), true)
    AutosplitMainWindow.generalTab:Fire("OnClick")
    eq(AutosplitMainWindow.minimapVisibility:GetText(), "Show minimap button")
end)
print(("Raid UI integration: %d tests passed"):format(raidTests))
