local _, Autosplit = ...
local maxBag = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1)
local controller = {status = "Choose an item from your bags to start a raid giveaway."}
Autosplit.Giveaway = controller

local function ReadableText(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "string" and value ~= "" then return value end
end

local function ReadableGUID(unit)
    return ReadableText(UnitGUID(unit))
end

local function Matches(info, item)
    return info and info.itemID == item.itemID and (not item.link or info.hyperlink == item.link)
end

function controller:Night()
    -- Local 06:00 rollover keeps a late-night raid on one ledger across midnight.
    return date("%Y-%m-%d", time() - 6 * 60 * 60)
end

function controller:Inventory()
    local result = {}
    for bag = 0, maxBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            result[#result + 1] = {bag = bag, slot = slot, info = C_Container.GetContainerItemInfo(bag, slot)}
        end
    end
    return result
end

function controller:Count(item)
    if not item then return 0 end
    local count = 0
    for bag = 0, maxBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if Matches(info, item) then count = count + info.stackCount end
        end
    end
    return count
end

function controller:Roster()
    local roster = {}
    if not IsInRaid() then return roster end
    for index = 1, GetNumGroupMembers() do
        local unit = "raid" .. index
        local guid = ReadableGUID(unit)
        if guid and not UnitIsUnit(unit, "player") then
            roster[#roster + 1] = {guid = guid, name = ReadableText(GetUnitName(unit, true)) or "Unknown"}
        end
    end
    table.sort(roster, function(a, b) return a.name < b.name end)
    return roster
end

function controller:IsMember(guid)
    if not guid or not IsInRaid() or guid == ReadableGUID("player") then return false end
    for index = 1, GetNumGroupMembers() do
        if ReadableGUID("raid" .. index) == guid then return true end
    end
    return false
end

local function Outgoing()
    local offer = {}
    for slot = 1, 7 do
        local name, _, count, _, enchantment, _, _, itemID = GetTradePlayerItemInfo(slot)
        if name then
            offer[#offer + 1] = {
                slot = slot, itemID = itemID, count = count,
                link = GetTradePlayerItemLink(slot), enchantment = enchantment,
            }
        end
    end
    return offer
end

local function EmptyOffer()
    return #Outgoing() == 0 and (GetPlayerTradeMoney() or 0) == 0
end

local function SnapshotOffer(item)
    local offer = Outgoing()
    if #offer == 0 or (GetPlayerTradeMoney() or 0) ~= 0 then return end
    local total = 0
    for _, entry in ipairs(offer) do
        if entry.slot > 6 or entry.itemID ~= item.itemID or (item.link and entry.link ~= item.link)
            or type(entry.count) ~= "number" or entry.count < 1 or entry.count % 1 ~= 0
            or (entry.enchantment and entry.enchantment ~= "") then return end
        total = total + entry.count
    end
    return {itemID = item.itemID, link = item.link, quantity = total}
end

local function ValidOffer(item, quantity)
    local snapshot = SnapshotOffer(item)
    return snapshot ~= nil and snapshot.quantity == quantity
end

local function FindItem(item, quantity)
    quantity = quantity or 1
    local candidates = {}
    for bag = 0, maxBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if Matches(info, item) and not info.isLocked and not info.isBound then
                local source = {
                    bag = bag, slot = slot, count = info.stackCount, link = info.hyperlink,
                    itemID = info.itemID, guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)),
                }
                candidates[#candidates + 1] = source
            end
        end
    end
    -- A multi-item source must retain at least one item. The only direct
    -- pickup allowed is a verified singleton; never dump a bag stack.
    table.sort(candidates, function(a, b)
        local ac, bc = math.max(1, a.count - 1), math.max(1, b.count - 1)
        if (a.count == 1 and quantity == 1) ~= (b.count == 1 and quantity == 1) then
            return a.count == 1
        end
        if ac ~= bc then return ac > bc end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    local plan, remaining = {}, quantity
    for _, source in ipairs(candidates) do
        source.amount = math.min(math.max(1, source.count - 1), remaining)
        plan[#plan + 1] = source
        remaining = remaining - source.amount
        if remaining == 0 then break end
    end
    if remaining > 0 then
        return nil, ("Need %d safely separable items; only %d available without moving a full bag stack."):format(quantity, quantity - remaining)
    end
    if #plan > 6 then return nil, "That quantity needs more than 6 trade slots. Combine stacks in your bags first." end
    return plan
end

local function SourceUnchanged(source)
    local info = C_Container.GetContainerItemInfo(source.bag, source.slot)
    return info and info.itemID == source.itemID and info.hyperlink == source.link
        and info.stackCount == source.count and not info.isLocked and not info.isBound
        and C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)) == source.guid
end

-- Placement is deliberately staged through an acknowledged bag stack. Never
-- trade the cursor produced by SplitContainerItem directly.
local placementJob
local function CancelPlacement()
    local job = placementJob
    placementJob = nil
    if job and job.ticker then job.ticker:Cancel() end
end

local function StagingSlot()
    -- General bags accept all otherwise tradable carried items. Specialty and
    -- reagent bags need item-family checks and are deliberately excluded here.
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if bag == 0 or family == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if not C_Container.GetContainerItemInfo(bag, slot) then
                    return {bag = bag, slot = slot}
                end
            end
        end
    end
end

local function BagSource(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return end
    return {
        bag = bag, slot = slot, count = info.stackCount, link = info.hyperlink,
        itemID = info.itemID,
        guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)),
    }, info
end

local function PlaceItems(plan, partner, quantity, done)
    if placementJob then return nil, "A giveaway placement is already running." end
    if not TradeFrame or not TradeFrame:IsShown() or not EmptyOffer() or GetCursorInfo()
        or ReadableGUID("NPC") ~= partner.guid or not controller:IsMember(partner.guid) then
        return nil, "Trade or cursor changed; no giveaway item was added."
    end
    local planned, needsSlot = 0, false
    for _, source in ipairs(plan) do
        if not source.guid or type(source.amount) ~= "number" or source.amount < 1
            or source.amount % 1 ~= 0 or source.amount > source.count
            or (source.count > 1 and source.amount >= source.count) or not SourceUnchanged(source) then
            return nil, "Inventory changed. Reopen the trade to try again."
        end
        planned = planned + source.amount
        if source.amount < source.count then needsSlot = true end
    end
    if planned ~= quantity or #plan == 0 or #plan > 6 then
        return nil, "The giveaway quantity changed. Reopen the trade."
    end
    if needsSlot and not StagingSlot() then
        return nil, "Free one slot in a general bag so the giveaway quantity can be verified."
    end
    local job = {
        index = 1, placed = 0, phase = "prepare",
        serial = controller.tradeSerial, deadline = GetTime() + 5,
    }
    placementJob = job
    local function finish(ok, message)
        if placementJob ~= job then return end
        CancelPlacement()
        done(ok, message)
    end
    local function fail(message)
        if job.clicked and TradeFrame:IsShown() and controller.tradeSerial == job.serial
            and ReadableGUID("NPC") == partner.guid then
            -- Do not leave a partial or unverified automated offer ready to accept.
            finish(nil, message .. " The giveaway trade was cancelled.")
            if TradeFrame:IsShown() and controller.tradeSerial == job.serial
                and ReadableGUID("NPC") == partner.guid then CloseTrade() end
        else
            finish(nil, message)
        end
    end
    local function transition(phase)
        job.phase, job.deadline = phase, GetTime() + 5
    end
    local item = {itemID = plan[1].itemID, link = plan[1].link}
    local function prefix()
        local snapshot = SnapshotOffer(item)
        return job.placed == 0 and EmptyOffer()
            or snapshot and snapshot.quantity == job.placed
    end
    local function cursorMatches()
        local kind, itemID, link = GetCursorInfo()
        return kind == "item" and itemID == item.itemID and link == item.link
    end
    local function pickupAndOffer(pick, amount)
        if pick.count ~= amount or not SourceUnchanged(pick) or GetCursorInfo() or not prefix()
            or GetTradePlayerItemInfo(job.index) then
            fail("The verified giveaway amount or trade changed. No pickup was made.")
            return
        end
        -- Pick up and offer in the same Lua invocation. Do not trust a same-
        -- item cursor arriving on a later tick: this API does not report count.
        C_Container.PickupContainerItem(pick.bag, pick.slot)
        if not cursorMatches() or C_Container.GetContainerItemInfo(pick.bag, pick.slot)
            or InCombatLockdown() or not TradeFrame:IsShown()
            or controller.tradeSerial ~= job.serial or ReadableGUID("NPC") ~= partner.guid
            or not controller:IsMember(partner.guid) or not prefix() or GetTradePlayerItemInfo(job.index) then
            fail("Could not verify the picked-up stack and active offer. Check your cursor and bags.")
            return
        end
        transition("trade_ack")
        job.clicked = true
        ClickTradeButton(job.index)
        if placementJob == job and not GetCursorInfo() and GetTradePlayerItemInfo(job.index) then
            local offer = SnapshotOffer(item)
            if not offer or offer.quantity ~= job.placed + amount then
                fail("Unexpected outgoing trade quantity.")
            end
        end
    end
    local function step()
        if placementJob ~= job then return end
        if InCombatLockdown() or not TradeFrame:IsShown()
            or controller.tradeSerial ~= job.serial or ReadableGUID("NPC") ~= partner.guid
            or not controller:IsMember(partner.guid) then
            fail("Giveaway stopped because the trade changed. Check your cursor and bags.")
            return
        end
        if GetTime() >= job.deadline then
            fail("Giveaway acknowledgement timed out. No retry was made; check your cursor and bags.")
            return
        end
        local source = plan[job.index]
        if job.phase == "prepare" then
            if GetCursorInfo() or not prefix() or not SourceUnchanged(source)
                or GetTradePlayerItemInfo(job.index) then
                fail("Trade or inventory changed; giveaway preparation stopped.")
                return
            end
            if source.amount < source.count then
                job.staging = StagingSlot()
                if not job.staging then fail("Free one general bag slot and reopen trade."); return end
                transition("split_cursor")
                C_Container.SplitContainerItem(source.bag, source.slot, source.amount)
            else
                pickupAndOffer(source, source.amount)
            end
        elseif job.phase == "split_cursor" then
            if not GetCursorInfo() then return end
            if not cursorMatches() or C_Container.GetContainerItemInfo(job.staging.bag, job.staging.slot) then
                fail("Split cursor or destination changed. Place the cursor item safely yourself.")
                return
            end
            transition("split_ack")
            C_Container.PickupContainerItem(job.staging.bag, job.staging.slot)
        elseif job.phase == "split_ack" then
            if GetCursorInfo() then return end
            local original, originalInfo = BagSource(source.bag, source.slot)
            local isolated, isolatedInfo = BagSource(job.staging.bag, job.staging.slot)
            if not original or not isolated then return end
            if not Matches(originalInfo, item) or not Matches(isolatedInfo, item)
                or isolated.count > source.amount or originalInfo.isBound or isolatedInfo.isBound then
                fail("Split produced an unexpected stack. Nothing from it was added to trade.")
                return
            end
            if original.guid ~= source.guid or original.count ~= source.count - source.amount
                or isolated.count ~= source.amount or not isolated.guid or isolated.guid == source.guid
                or originalInfo.isLocked or isolatedInfo.isLocked then return end
            -- The isolated slot, not the original source, is now the only
            -- eligible pickup. A failed split has no full-stack fallback.
            job.pick = isolated
            transition("isolated_ready")
        elseif job.phase == "isolated_ready" then
            pickupAndOffer(job.pick, source.amount)
        elseif job.phase == "trade_ack" then
            if GetCursorInfo() then return end
            local snapshot = SnapshotOffer(item)
            local expected = job.placed + source.amount
            if snapshot and snapshot.quantity == job.placed then return end
            if not snapshot and EmptyOffer() then return end
            local _, _, count = GetTradePlayerItemInfo(job.index)
            if not snapshot or snapshot.quantity ~= expected or count ~= source.amount then
                -- Closing returns the offer instead of leaving an oversized
                -- stack ready for the user to accept.
                fail("Unexpected outgoing trade quantity.")
                return
            end
            job.placed = expected
            if job.index == #plan then finish(true); return end
            job.index = job.index + 1
            transition("prepare")
        end
    end
    local function pump()
        if job.stepping then return end
        job.stepping = true
        local ok = pcall(step)
        job.stepping = nil
        if not ok then fail("Giveaway preparation failed. Check your cursor and trade before continuing.") end
    end
    job.step = pump
    job.ticker = C_Timer.NewTicker(0.05, pump)
    return true
end

function controller:Notify(text)
    self.status = text
    Autosplit.Message(text)
    if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
end

function controller:Initialize()
    if self.engine then return end
    AutosplitCharDB = AutosplitCharDB or {}
    self.db = AutosplitCharDB
    self.engine = Autosplit.CreateRaidEngine({
        night = function() return self:Night() end,
        timestamp = time, time = GetTime, combat = InCombatLockdown,
        cursor = GetCursorInfo,
        member = function(guid) return self:IsMember(guid) end,
        find = FindItem,
        count = function(item) return self:Count(item) end,
        splitBusy = function() return Autosplit.SplitEngine.job ~= nil end,
        emptyOffer = EmptyOffer, validOffer = ValidOffer, place = PlaceItems,
        snapshot = SnapshotOffer, cancelPlacement = CancelPlacement,
        session = function() return self.tradeSerial end,
    }, self.db, function(text) self:Notify(text) end)
    -- Keep the last seven local raid nights; current-night reservations always survive reloads.
    local cutoff = date("%Y-%m-%d", time() - 7 * 24 * 60 * 60)
    for night in pairs(self.db.nights) do
        if night < cutoff then self.db.nights[night] = nil end
    end
end

function controller:SetQuantity(text)
    self:Initialize()
    if Autosplit.TradeBusy then return nil, "Finish the current trade before changing quantity." end
    local ok, error = self.engine:SetQuantity(text)
    self.status = ok and ("Giveaway quantity: %d per eligible raid member."):format(self.db.quantity) or error
    if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
    return ok, error
end

function controller:Select(item)
    self:Initialize()
    if Autosplit.TradeBusy then self:Notify("Finish the current trade before changing items."); return end
    if Autosplit.SplitEngine.job then self:Notify("Finish splitting before selecting a giveaway item."); return end
    local ok, error = self.engine:Select(item)
    if not ok then self:Notify(error) end
    if ok and Autosplit.RefreshWindow then Autosplit.RefreshWindow(true) end
end

function controller:SelectBag(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return end
    if info.isLocked or info.isBound then
        self:Notify("Choose an unlocked, unbound item that can be traded.")
        return
    end
    self:Select({itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID})
end

function controller:SelectCursor()
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" then return end
    -- A drop selects a template; the actual item is returned to its original slot.
    ClearCursor()
    if GetCursorInfo() then self:Notify("Return the item to your bags, then click it in the bag view."); return end
    local item = {itemID = itemID, link = link, icon = C_Item.GetItemIconByID(itemID)}
    if self:Count(item) == 0 then
        self:Notify("Choose an item from your carried bags.")
        return
    end
    local source = FindItem(item)
    if not source then self:Notify("Choose an unlocked, unbound item that can be traded."); return end
    self:Select(item)
end

function controller:ToggleEnabled()
    self:Initialize()
    if self.engine.active or Autosplit.TradeBusy then self:Notify("Finish the current trade first."); return end
    if not self.db.item then self:Notify("Choose a giveaway item first."); return end
    self.db.enabled = not self.db.enabled
    self:Notify(self.db.enabled and "Raid giveaway resumed." or "Raid giveaway paused.")
end

local settleTicker
local function StopSettlement()
    if settleTicker then settleTicker:Cancel(); settleTicker = nil end
    Autosplit.TradeBusy = false
    if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
end

local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED", "TRADE_SHOW",
    "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
    "PLAYER_TRADE_MONEY", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then controller:Initialize(); return end
    if not controller.engine then return end
    local engine = controller.engine
    if event == "TRADE_SHOW" then
        CancelPlacement()
        controller.tradeSerial = (controller.tradeSerial or 0) + 1
        Autosplit.TradeBusy = true
        local guid = ReadableGUID("NPC")
        local name = ReadableText(GetUnitName("NPC", true))
        if guid and controller:IsMember(guid) then
            -- Prefer the roster spelling of the exact GUID, since the trade
            -- unit can omit its name or realm during the opening event.
            for _, member in ipairs(controller:Roster()) do
                if member.guid == guid and member.name ~= "Unknown" then name = member.name; break end
            end
        end
        local partner = {guid = guid, name = name}
        local ok, error = engine:Begin(partner)
        if not ok and error then controller:Notify(error) end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        engine:AcceptUpdate(...)
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_MONEY_CHANGED"
        or event == "PLAYER_TRADE_MONEY" then
        engine:OfferChanged()
        if placementJob then placementJob.step() end
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local messageID, message = ...
        if (LE_GAME_ERR_TRADE_COMPLETE and messageID == LE_GAME_ERR_TRADE_COMPLETE)
            or (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE) then
            engine:CompleteMessage()
        elseif (LE_GAME_ERR_TRADE_CANCELLED and messageID == LE_GAME_ERR_TRADE_CANCELLED)
            or (ERR_TRADE_CANCELLED and message == ERR_TRADE_CANCELLED) then
            engine:Cancelled("WoW reported that the trade was cancelled.")
        end
    elseif event == "TRADE_CLOSED" then
        engine:Close()
        if engine.active and not settleTicker then
            settleTicker = C_Timer.NewTicker(0.2, function()
                engine:Poll()
                if not engine.active then
                    if settleTicker then settleTicker:Cancel(); settleTicker = nil end
                    -- Another trade can open while the previous one settles.
                    Autosplit.TradeBusy = TradeFrame and TradeFrame:IsShown() or false
                    if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
                end
            end)
        elseif not engine.active then StopSettlement() end
    elseif event == "BAG_UPDATE_DELAYED" then
        engine:Poll()
        if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
    else
        if Autosplit.RefreshWindow then Autosplit.RefreshWindow() end
    end
end)
