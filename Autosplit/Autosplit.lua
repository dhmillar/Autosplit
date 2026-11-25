local _, Autosplit = ...
local bags = C_Container
local maxBag = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1)
local reagentBag = Enum.BagIndex.ReagentBag or 5
local engine, dialog, ticker, selected

local function Message(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff59d5ffNE Tools:|r " .. text)
end

local function IsCarriedBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= maxBag and bag % 1 == 0
end

local function Accepts(bag, source)
    if not IsCarriedBag(bag) or bags.GetContainerNumSlots(bag) == 0 then return false end
    if bag == reagentBag then
        return not not select(17, C_Item.GetItemInfo(source.hyperlink or source.itemID))
    end
    local _, family = bags.GetContainerNumFreeSlots(bag)
    if family == 0 then return true end
    local itemFamily = C_Item.GetItemFamily(source.hyperlink or source.itemID)
    return family ~= nil and itemFamily ~= nil and bit.band(family, itemFamily) ~= 0
end

local api = {
    info = bags.GetContainerItemInfo,
    split = bags.SplitContainerItem,
    pickup = bags.PickupContainerItem,
    cursor = GetCursorInfo,
    combat = InCombatLockdown,
    time = GetTime,
    accepts = Accepts,
    guid = function(bag, slot)
        return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
    end,
    destinations = function(source)
        local result = {}
        -- Prefer specialized storage so ordinary bag space remains available.
        for bag = maxBag, 0, -1 do
            if Accepts(bag, source) then
                for slot = 1, bags.GetContainerNumSlots(bag) do
                    if not bags.GetContainerItemInfo(bag, slot) then
                        result[#result + 1] = {bag = bag, slot = slot}
                    end
                end
            end
        end
        return result
    end,
}

local function Quantity()
    local digits = dialog.quantity:GetText():match("^%s*(%d+)%s*$")
    return digits and tonumber(digits)
end

local function SetStatus(text, error)
    dialog.status:SetText(text or "")
    if error then dialog.status:SetTextColor(1, 0.35, 0.3)
    else dialog.status:SetTextColor(0.72, 0.85, 0.95) end
end

local function UpdatePreview()
    if engine.job or not selected then return end
    local number = Quantity()
    local valid = number and number >= 1 and number <= selected.count
    dialog.split:SetEnabled(not not valid)
    if not valid then
        SetStatus("Enter a whole number from 1 to " .. selected.count .. ".", true)
    elseif number == selected.count then
        SetStatus(("%d single-item stacks. Needs %d empty slots."):format(number, number - 1))
    else
        SetStatus(("%d single-item stacks; %d left in the original.\nNeeds %d empty slots."):format(number, selected.count - number, number))
    end
end

engine = Autosplit.CreateEngine(api, function(state, text, completed, total, success)
    if state == "started" then
        dialog.split:Disable()
        dialog.quantity:ClearFocus()
        dialog.quantity:EnableMouse(false)
        dialog.cancel:SetText("Stop")
        SetStatus("Splitting... 0 / " .. total)
        ticker = C_Timer.NewTicker(0.1, function() engine:Step() end)
    elseif state == "progress" then
        SetStatus(("Splitting... %d / %d"):format(completed, total))
    else
        if ticker then ticker:Cancel(); ticker = nil end
        dialog.quantity:EnableMouse(true)
        dialog.cancel:SetText("Close")
        SetStatus(text, not success)
        selected = nil
        dialog.split:Disable()
        Message(text)
    end
end)

local function StartSplit()
    if not selected or engine.job then return end
    if Autosplit.TradeBusy then SetStatus("Finish the current trade before splitting.", true); return end
    local ok, error = engine:Start(selected, Quantity())
    if not ok then SetStatus(error, true) end
end

local function CreateDialog()
    if dialog then return end
    dialog = CreateFrame("Frame", "AutosplitQuantityDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:Hide()
    dialog:SetSize(390, 272)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog.TitleText:SetText("NE Tools - Split Stack")
    tinsert(UISpecialFrames, "AutosplitQuantityDialog")

    local icon = dialog:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 20, -40)
    dialog.icon = icon

    local item = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    item:SetWidth(300)
    item:SetJustifyH("LEFT")
    dialog.item = item

    local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 22, -92)
    label:SetText("Number of items to separate into singles:")

    local edit = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    edit:SetSize(120, 28)
    edit:SetPoint("TOPLEFT", 26, -117)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(7)
    edit:SetScript("OnTextChanged", UpdatePreview)
    edit:SetScript("OnEnterPressed", StartSplit)
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.quantity = edit

    local status = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 22, -157)
    status:SetSize(346, 60)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    dialog.status = status

    local split = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    split:SetSize(112, 28)
    split:SetPoint("BOTTOMRIGHT", -144, 17)
    split:SetText("Split")
    split:SetScript("OnClick", StartSplit)
    dialog.split = split

    local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancel:SetSize(112, 28)
    cancel:SetPoint("BOTTOMRIGHT", -22, 17)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function()
        if engine.job then engine:Cancel() else dialog:Hide() end
    end)
    dialog.cancel = cancel
    dialog:SetScript("OnHide", function()
        engine:Cancel()
        selected = nil
        edit:ClearFocus()
    end)
end

local function OpenQuantity(bag, slot)
    if engine.job then Message("A split is already running."); return end
    if Autosplit.TradeBusy then Message("Finish the current trade before splitting."); return end
    if InCombatLockdown() then Message("Leave combat before splitting items."); return end
    if GetCursorInfo() or SpellIsTargeting() then Message("Clear your cursor first."); return end
    local source, error = engine:Snapshot(bag, slot)
    if not source then Message(error); return end
    CreateDialog()
    selected = source
    if StackSplitFrame then StackSplitFrame:Hide() end
    dialog.icon:SetTexture(source.icon)
    dialog.item:SetText(source.hyperlink or ("Item " .. source.itemID))
    dialog.cancel:SetText("Cancel")
    dialog.quantity:EnableMouse(true)
    dialog.quantity:SetText(tostring(source.count))
    UpdatePreview()
    dialog:Show()
    dialog.quantity:SetFocus()
    dialog.quantity:HighlightText()
end

Autosplit.Message = Message
Autosplit.SplitEngine = engine
Autosplit.OpenQuantity = OpenQuantity

-- Ctrl-only click shields avoid replacing Blizzard's item-use or click handlers.
-- Outside this gesture the original bag buttons receive their normal input.
local buttons = {}
local function Location(button)
    if not button.GetBagID then return end
    local bag, slot = button:GetBagID(), button:GetID()
    if IsCarriedBag(bag) and type(slot) == "number" and slot >= 1
        and slot <= bags.GetContainerNumSlots(bag) then
        return bag, slot
    end
end

local function RefreshButton(button)
    local shield = buttons[button]
    if not shield then return end
    if not IsControlKeyDown() or not button:IsShown() or GetCursorInfo() or SpellIsTargeting() then
        shield:Hide()
        return
    end
    local bag, slot = Location(button)
    local info = bag and bags.GetContainerItemInfo(bag, slot)
    shield:SetFrameLevel(button:GetFrameLevel() + 5)
    shield:SetShown(info ~= nil and info.stackCount > 1)
end

local function AttachButton(button)
    if buttons[button] or not button.GetBagID then return end
    local shield = CreateFrame("Button", nil, button)
    shield:Hide()
    shield:SetAllPoints(button)
    shield:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    shield:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
        if IsControlKeyDown() then
            local bag, slot = Location(button)
            if bag then OpenQuantity(bag, slot) end
        end
    end)
    shield:SetScript("OnEnter", function()
        local bag, slot = Location(button)
        if bag then
            GameTooltip:SetOwner(shield, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(bag, slot)
            GameTooltip:AddLine("Ctrl-click: Split into single items", 0.35, 0.84, 1)
            GameTooltip:Show()
        end
    end)
    shield:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[button] = shield
    button:HookScript("OnShow", RefreshButton)
    button:HookScript("OnHide", function() shield:Hide() end)
    RefreshButton(button)
end

local function RefreshButtons()
    for button in pairs(buttons) do RefreshButton(button) end
end

local hookedFrames = {}
local function AttachContainer(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true
    local function AttachItems()
        for _, button in ipairs(frame.Items or {}) do AttachButton(button) end
    end
    if frame.UpdateItemSlots then hooksecurefunc(frame, "UpdateItemSlots", AttachItems) end
    frame:HookScript("OnShow", AttachItems)
    AttachItems()
end

local baganatorAttached = false
local function AttachBags()
    AttachContainer(ContainerFrameCombinedBags)
    for index = 1, (NUM_CONTAINER_FRAMES or maxBag + 1) do
        AttachContainer(_G["ContainerFrame" .. index])
    end
    if not baganatorAttached and Baganator and Baganator.API and Baganator.API.Skins then
        baganatorAttached = true
        local skins = Baganator.API.Skins
        local function AttachRegion(details)
            if details.regionType == "ItemButton" then AttachButton(details.region) end
        end
        skins.RegisterListener(AttachRegion)
        for _, details in ipairs(skins.GetAllFrames()) do AttachRegion(details) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("CURSOR_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        AttachBags()
    elseif event == "BAG_UPDATE_DELAYED" then
        engine:Step()
        if IsControlKeyDown() then RefreshButtons() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if engine.job then engine:Step() end
    else
        RefreshButtons()
    end
end)

SLASH_AUTOSPLIT1 = "/autosplit"
SLASH_AUTOSPLIT2 = "/as"
SLASH_AUTOSPLIT3 = "/netools"
SlashCmdList.AUTOSPLIT = function(command)
    if command:lower():match("^%s*stop%s*$") then
        engine:Cancel()
        return
    end
    if Autosplit.ToggleWindow then Autosplit.ToggleWindow() end
end
