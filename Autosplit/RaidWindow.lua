local _, Autosplit = ...
local giveaway = Autosplit.Giveaway
local window, minimapButton
local ICON = "Interface\\AddOns\\Autosplit\\Icon"

local function Text(parent, font, x, y, width, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local function Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function ItemTooltip(button, entry)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry and entry.info then
        GameTooltip:SetBagItem(entry.bag, entry.slot)
        GameTooltip:AddLine("Click: select giveaway item", 0.35, 0.84, 1)
        GameTooltip:AddLine("Ctrl-click: split into singles", 0.7, 0.8, 0.9)
    else
        GameTooltip:AddLine("Empty bag slot")
    end
    GameTooltip:Show()
end

local function CreateBagButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(38, 38)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.04, 0.06, 0.09, 0.95)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        if not button.entry or not button.entry.info then return end
        if IsControlKeyDown() then
            Autosplit.OpenQuantity(button.entry.bag, button.entry.slot)
        elseif mouseButton == "LeftButton" then
            giveaway:SelectBag(button.entry.bag, button.entry.slot)
        end
    end)
    button:SetScript("OnEnter", function() ItemTooltip(button, button.entry) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function RefreshInventory()
    local entries = giveaway:Inventory()
    local y, column, previousBag = -6, 0, nil
    local labelIndex = 0
    for index, entry in ipairs(entries) do
        if entry.bag ~= previousBag then
            if previousBag ~= nil then y = y - 46 end
            labelIndex = labelIndex + 1
            local label = window.bagLabels[labelIndex]
            if not label then
                label = Text(window.bagContent, "GameFontNormalSmall", 0, 0, 460)
                window.bagLabels[labelIndex] = label
            end
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", 4, y)
            label:SetText(C_Container.GetBagName(entry.bag) or ("Bag " .. entry.bag))
            label:Show()
            previousBag, column, y = entry.bag, 0, y - 22
        end
        local button = window.bagButtons[index]
        if not button then
            button = CreateBagButton(window.bagContent)
            window.bagButtons[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 4 + column * 44, y)
        button.entry = entry
        button.icon:SetTexture(entry.info and entry.info.iconFileID)
        button.icon:SetDesaturated(entry.info and entry.info.isLocked or false)
        button.count:SetText(entry.info and entry.info.stackCount > 1 and entry.info.stackCount or "")
        button:Show()
        column = column + 1
        if column == 10 then column, y = 0, y - 44 end
    end
    for index = #entries + 1, #window.bagButtons do window.bagButtons[index]:Hide() end
    for index = labelIndex + 1, #window.bagLabels do window.bagLabels[index]:Hide() end
    window.bagContent:SetHeight(math.max(440, -y + 48))
end

local function RefreshRemaining()
    local count, unresolved = 0, 0
    local inRaid, hasItem = IsInRaid(), giveaway.db.item ~= nil
    if inRaid and hasItem then
        for _, member in ipairs(giveaway:Roster()) do
            local record = giveaway.engine:Recipient(member.guid, member.name)
            if not record and member.name ~= "Unknown" and member.name:find("%S") then
                count = count + 1
                local label = window.rosterLabels[count]
                if not label then
                    label = Text(window.rosterContent, "GameFontHighlightSmall", 0, -(count - 1) * 20, 290)
                    window.rosterLabels[count] = label
                    label:SetHeight(18)
                    label:SetWordWrap(false)
                end
                label:SetText(member.name)
                label:Show()
            elseif record and record.state ~= "served" then
                unresolved = unresolved + 1
            end
        end
    end
    for index = count + 1, #window.rosterLabels do window.rosterLabels[index]:Hide() end
    window.rosterContent:SetHeight(math.max(108, count * 20))
    window.rosterTitle:SetText(("Remaining players: %d"):format(count))
    window.remainingEmpty:SetText(not inRaid and "Join a raid to see remaining players."
        or not hasItem and "Choose a giveaway item first."
        or unresolved > 0 and "No eligible players. Check Unconfirmed."
        or "No eligible players remaining.")
    window.remainingEmpty:SetShown(count == 0)
end

local function RefreshAttempts()
    local history = giveaway.engine:Attempts()
    for index, record in ipairs(history) do
        local row = window.historyRows[index]
        if not row then
            row = {
                name = Text(window.historyContent, "GameFontHighlightSmall", 0, -(index - 1) * 40, 290),
                item = Text(window.historyContent, "GameFontNormalSmall", 0, -(index - 1) * 40 - 18, 290),
            }
            row.name:SetHeight(18)
            row.name:SetWordWrap(false)
            row.item:SetHeight(18)
            row.item:SetWordWrap(false)
            window.historyRows[index] = row
        end
        local clock = record.timestamp and date("%H:%M", record.timestamp) or "--:--"
        row.name:SetText(clock .. "  " .. record.name)
        local amount = "Unconfirmed; requested " .. (record.requestedQuantity or record.quantity or 1) .. " x "
        row.item:SetText(amount .. (record.link or ("Item " .. record.itemID)))
        row.name:Show()
        row.item:Show()
    end
    for index = #history + 1, #window.historyRows do
        window.historyRows[index].name:Hide()
        window.historyRows[index].item:Hide()
    end
    window.historyEmpty:SetShown(#history == 0)
    window.historyContent:SetHeight(math.max(108, #history * 40))
    window.rosterTitle:SetText(("Unconfirmed attempts: %d"):format(#history))
end

local function RefreshLists()
    local attempts = window.listMode == "unconfirmed"
    window.historyScroll:SetShown(attempts)
    window.rosterScroll:SetShown(not attempts)
    window.remainingTab:SetEnabled(attempts)
    window.attemptsTab:SetEnabled(not attempts)
    if attempts then RefreshAttempts() else RefreshRemaining() end
end

local function SelectList(mode)
    window.listMode = mode
    window.historyScroll:SetVerticalScroll(0)
    window.rosterScroll:SetVerticalScroll(0)
    RefreshLists()
end

function Autosplit.RefreshWindow(forceQuantity)
    if not window or not window:IsShown() then return end
    local db = giveaway.db
    RefreshInventory()
    RefreshLists()
    window.selection.icon:SetTexture(db.item and db.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    window.itemName:SetText(db.item and (db.item.link or ("Item " .. db.item.itemID)) or "Drop an item here, or click it in your bags")
    local busy = giveaway.engine.active or Autosplit.TradeBusy
    if busy or forceQuantity == true then window.quantity:ClearFocus() end
    window.quantity:EnableMouse(not busy)
    if not window.quantity:HasFocus() and not giveaway.engine.invalidQuantity then
        window.syncingQuantity = true
        window.quantity:SetText(tostring(db.quantity))
        window.syncingQuantity = false
    end
    window.stock:SetText(db.item and ("In bags: %d  |  Give: %d per person"):format(giveaway:Count(db.item), db.quantity) or "No item selected")
    window.toggle:SetText(db.enabled and "Pause giveaway" or "Resume giveaway")
    window.toggle:SetEnabled(db.item ~= nil and not giveaway.engine.active and not Autosplit.TradeBusy)
    window.clear:SetEnabled(db.item ~= nil and not giveaway.engine.active and not Autosplit.TradeBusy)
    window.state:SetText(giveaway.engine.invalidQuantity and "|cffffcc66Enter a valid quantity|r"
        or db.enabled and "|cff6fdf96Giveaway ON|r" or "|cff9aa6b3Giveaway paused|r")
    window.status:SetText(giveaway.status)
    window.night:SetText("Night: " .. giveaway:Night() .. "  |  Resets at 6 a.m. local")
end

local function CreateWindow()
    if window then return end
    giveaway:Initialize()
    window = CreateFrame("Frame", "AutosplitMainWindow", UIParent, "BasicFrameTemplateWithInset")
    window:Hide()
    window:SetSize(864, 650)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window.TitleText:SetText("Autosplit  |  Bags & Raid Giveaway")
    tinsert(UISpecialFrames, "AutosplitMainWindow")
    Text(window, "GameFontNormalLarge", 20, -42, 440, "Your bags")
    Text(window, "GameFontHighlightSmall", 20, -68, 455, "Click an item to give it away. Ctrl-click a stack to split it.")

    local bagScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    bagScroll:SetPoint("TOPLEFT", 18, -95)
    bagScroll:SetSize(454, 490)
    window.bagContent = CreateFrame("Frame", nil, bagScroll)
    window.bagContent:SetSize(448, 490)
    bagScroll:SetScrollChild(window.bagContent)
    window.bagButtons, window.bagLabels, window.rosterLabels = {}, {}, {}

    Text(window, "GameFontNormalLarge", 520, -42, 320, "Raid giveaway")
    window.state = Text(window, "GameFontHighlight", 520, -70, 320)
    window.selection = CreateFrame("Button", nil, window)
    window.selection:SetSize(54, 54)
    window.selection:SetPoint("TOPLEFT", 520, -99)
    window.selection:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    window.selection:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    window.selection.icon = window.selection:CreateTexture(nil, "ARTWORK")
    window.selection.icon:SetPoint("TOPLEFT", 5, -5)
    window.selection.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    window.selection:SetScript("OnReceiveDrag", function() giveaway:SelectCursor() end)
    window.selection:SetScript("OnClick", function() giveaway:SelectCursor() end)
    window.selection:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if giveaway.db.item then GameTooltip:SetHyperlink(giveaway.db.item.link or ("item:" .. giveaway.db.item.itemID))
        else GameTooltip:AddLine("Drop an inventory item to select it") end
        GameTooltip:Show()
    end)
    window.selection:SetScript("OnLeave", function() GameTooltip:Hide() end)
    window.itemName = Text(window, "GameFontNormal", 587, -101, 245)
    window.itemName:SetHeight(22)
    window.itemName:SetWordWrap(false)
    Text(window, "GameFontHighlightSmall", 587, -134, 70, "Quantity:")
    window.quantity = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.quantity:SetSize(74, 24)
    window.quantity:SetPoint("TOPLEFT", 658, -126)
    window.quantity:SetAutoFocus(false)
    window.quantity:SetMaxLetters(7)
    window.quantity:SetScript("OnTextChanged", function(self)
        if not window.syncingQuantity then giveaway:SetQuantity(self:GetText()) end
    end)
    window.quantity:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    window.quantity:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(tostring(giveaway.db.quantity))
    end)
    window.stock = Text(window, "GameFontHighlightSmall", 520, -167, 320)
    window.toggle = Button(window, "Pause giveaway", 520, -194, 166, function() giveaway:ToggleEnabled() end)
    window.clear = Button(window, "Clear item", 696, -194, 134, function() giveaway:Select(nil) end)
    local details = Text(window, "GameFontHighlightSmall", 520, -236, 310,
        "When a raid member opens trade, the selected quantity is added automatically. Finish with WoW's Trade button.\n\nEach person gets one giveaway tonight, even after a reload or item change.")
    details:SetHeight(92)
    details:SetJustifyV("TOP")
    window.listMode = "remaining"
    window.remainingTab = Button(window, "Remaining players", 520, -332, 150, function() SelectList("remaining") end)
    window.attemptsTab = Button(window, "Unconfirmed", 730, -332, 100, function() SelectList("unconfirmed") end)
    window.rosterTitle = Text(window, "GameFontNormal", 520, -371, 310)
    local rosterScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    rosterScroll:SetPoint("TOPLEFT", 520, -395)
    rosterScroll:SetSize(292, 108)
    window.rosterScroll = rosterScroll
    window.rosterContent = CreateFrame("Frame", nil, rosterScroll)
    window.rosterContent:SetSize(290, 108)
    rosterScroll:SetScrollChild(window.rosterContent)
    window.remainingEmpty = Text(window.rosterContent, "GameFontDisableSmall", 0, -4, 290)
    window.historyScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.historyScroll:SetPoint("TOPLEFT", 520, -395)
    window.historyScroll:SetSize(292, 108)
    window.historyContent = CreateFrame("Frame", nil, window.historyScroll)
    window.historyContent:SetSize(290, 108)
    window.historyScroll:SetScrollChild(window.historyContent)
    window.historyRows = {}
    window.historyEmpty = Text(window.historyContent, "GameFontDisableSmall", 0, -4, 290, "No unconfirmed trades tonight.")
    window.status = Text(window, "GameFontHighlightSmall", 520, -520, 310)
    window.status:SetHeight(64)
    window.status:SetJustifyV("TOP")
    window.night = Text(window, "GameFontDisableSmall", 20, -610, 805)
    window:SetScript("OnShow", Autosplit.RefreshWindow)
end

function Autosplit.ToggleWindow()
    CreateWindow()
    window:SetShown(not window:IsShown())
end

local function PositionMinimap()
    local angle = math.rad(giveaway.db.minimapAngle or 220)
    local radius = Minimap:GetWidth() / 2 + 8
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimap()
    if minimapButton or not Minimap then return end
    giveaway:Initialize()
    minimapButton = CreateFrame("Button", "AutosplitMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    minimapButton:SetNormalTexture(ICON)
    minimapButton:SetPushedTexture(ICON)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnClick", Autosplit.ToggleWindow)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Autosplit", 0.35, 0.84, 1)
        GameTooltip:AddLine("Click: bags and raid giveaway\nDrag: move around minimap\n/as: open menu", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            giveaway.db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
            PositionMinimap()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PositionMinimap()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", CreateMinimap)
