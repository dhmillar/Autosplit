local _, Autosplit = ...

-- Persistent recipient ledger and trade lifecycle, independent of frames and bag APIs.
function Autosplit.CreateRaidEngine(api, db, notify)
    local engine = {db = db}
    db.nights = db.nights or {}
    local function validQuantity(quantity)
        return type(quantity) == "number" and quantity == quantity and quantity % 1 == 0
            and quantity >= 1 and quantity <= 9999999
    end
    if not validQuantity(db.quantity) then db.quantity = 1 end

    function engine:SetQuantity(quantity)
        if self.active then return nil, "Finish the current trade before changing quantity." end
        if type(quantity) == "string" then
            local digits = quantity:match("^%s*(%d+)%s*$")
            quantity = digits and tonumber(digits)
        end
        if not validQuantity(quantity) then
            self.invalidQuantity = true
            return nil, "Enter a whole giveaway quantity from 1 to 9999999."
        end
        db.quantity = quantity
        self.invalidQuantity = nil
        return true
    end

    function engine:Ledger(night)
        night = night or api.night()
        db.nights[night] = db.nights[night] or {}
        return db.nights[night], night
    end

    function engine:Recipient(guid)
        local ledger = self:Ledger()
        return ledger[guid]
    end

    function engine:History(unconfirmed)
        local ledger = self:Ledger()
        local history = {}
        for guid, record in pairs(ledger) do
            if (not unconfirmed and record.state == "served") or (unconfirmed and record.state ~= "served") then
                history[#history + 1] = {
                    guid = guid, name = record.name, itemID = record.itemID,
                    link = record.link, timestamp = record.timestamp, quantity = record.quantity or 1,
                    requestedQuantity = record.requestedQuantity, quantityMismatch = record.quantityMismatch,
                    state = record.state, reason = record.reason,
                }
            end
        end
        table.sort(history, function(a, b)
            local aTime, bTime = a.timestamp or 0, b.timestamp or 0
            if aTime ~= bTime then return aTime > bTime end
            if a.name ~= b.name then return a.name < b.name end
            return a.guid < b.guid
        end)
        return history
    end

    function engine:Attempts()
        return self:History(true)
    end

    function engine:Select(item)
        if self.active then return nil, "Finish the current trade before changing the giveaway item." end
        if not db.item or not item or db.item.itemID ~= item.itemID or db.item.link ~= item.link then
            db.quantity = 1
            self.invalidQuantity = nil
        end
        db.item = item
        db.enabled = item ~= nil
        notify(item and ("Giveaway ready: %d per raid member tonight."):format(db.quantity) or "Giveaway item cleared.")
        return true
    end

    local function fullNameKey(name)
        if type(name) ~= "string" then return nil end
        local player, realm = name:match("^([^%-]+)%-(.+)$")
        if not player or not realm then return nil end
        return player:lower() .. "-" .. realm:lower():gsub("[%s%-]", "")
    end

    local function checkedSnapshot(item, snapshot)
        if type(snapshot) ~= "table" or snapshot.itemID ~= item.itemID or not validQuantity(snapshot.quantity)
            or type(snapshot.link) ~= "string" or snapshot.link == "" then return nil end
        return {itemID = snapshot.itemID, link = snapshot.link, quantity = snapshot.quantity}
    end

    function engine:Begin(partner)
        if self.active then return nil, "Waiting for the previous trade to settle." end
        if not db.enabled or not db.item then return nil end
        if self.invalidQuantity or not validQuantity(db.quantity) then return nil, "Enter a valid giveaway quantity first." end
        local quantity = db.quantity
        if api.combat() then return nil, "Giveaway paused during combat." end
        if not partner or type(partner.guid) ~= "string" or partner.guid == "" or type(partner.name) ~= "string"
            or partner.name == "Unknown" or not partner.name:find("%S")
            or not api.member(partner.guid) then return nil, "The raid trade recipient could not be verified." end
        partner = {guid = partner.guid, name = partner.name}
        local item = {itemID = db.item.itemID, link = db.item.link}
        local ledger, night = self:Ledger()
        if ledger[partner.guid] then
            return nil, partner.name .. " already received an item tonight (or has an unresolved trade)."
        end
        local identity = fullNameKey(partner.name)
        if identity then
            for _, candidate in pairs(ledger) do
                if type(candidate)=="table" and fullNameKey(candidate.name)==identity then
                    return nil, partner.name .. " is already in the giveaway ledger for tonight."
                end
            end
        end
        local source, error = api.find(item, quantity)
        if not source then return nil, error or "No unlocked, tradable copies remain in your bags." end
        if api.cursor() or api.splitBusy() then return nil, "Clear your cursor and finish splitting first." end
        if not api.emptyOffer() then return nil, "Giveaway skipped: your trade already contains items or money." end
        local total = api.count(item)
        if total < quantity then return nil, ("Need %d giveaway items; only %d remain."):format(quantity, total) end
        local entry = {
            state = "pending", guid = partner.guid, name = partner.name, itemID = item.itemID,
            link = item.link, before = total, timestamp = api.timestamp(),
            quantity = quantity, requestedQuantity = quantity,
        }
        ledger[partner.guid] = entry
        local active = {
            partner = partner, night = night, item = item, source = source,
            entry = entry, quantity = quantity, phase = "placing", session = api.session(),
        }
        self.active = active
        local function placed(ok, message)
            if self.active ~= active or active.phase ~= "placing" then return end
            if not ok or not api.validOffer(item, quantity) then
                entry.state, entry.reason = "uncertain", message or "The outgoing quantity was not confirmed."
                active.phase = "failed"
                notify(entry.reason)
                return
            end
            active.phase = "offered"
            self:OfferChanged()
            local snapshot = checkedSnapshot(item, api.snapshot(item))
            if snapshot and snapshot.quantity == quantity then active.verifiedOffer = snapshot end
            notify(("%d offered to %s. Finish with WoW's Trade button."):format(quantity, partner.name))
        end
        local ok, placementError = api.place(source, partner, quantity, placed)
        if not ok then
            placed(nil, placementError or "Could not offer the item. Check your cursor and trade.")
            return nil, placementError
        end
        if active.phase == "placing" then notify("Preparing a verified giveaway stack for " .. partner.name .. ".") end
        return true
    end

    function engine:AcceptUpdate(playerAccepted, targetAccepted)
        local active = self.active
        if not active or active.phase == "closing" or active.session ~= api.session() then return end
        -- Capture while trade slots and the NPC unit still exist. Either side
        -- accepting supplies a snapshot; simultaneous 1,1 is not required.
        if playerAccepted == 1 or targetAccepted == 1 or playerAccepted == true or targetAccepted == true then
            local snapshot = checkedSnapshot(active.item, api.snapshot(active.item))
            if not snapshot then active.offerContradiction = true end
            active.acceptedSnapshot = snapshot
            active.entry.acceptedSnapshot = snapshot
        end
    end

    function engine:OfferChanged()
        local active = self.active
        if not active or active.phase == "closing" or active.session ~= api.session() then return end
        local snapshot = checkedSnapshot(active.item, api.snapshot(active.item))
        if active.verifiedOffer and (not snapshot or snapshot.quantity ~= active.verifiedOffer.quantity
            or snapshot.link ~= active.verifiedOffer.link) then active.offerContradiction = true end
        active.entry.observedQuantity = snapshot and snapshot.quantity or nil
        if snapshot then active.hadOffer = true end
        if not api.emptyOffer() then
            local accepted = active.acceptedSnapshot
            if accepted and (not snapshot or accepted.quantity ~= snapshot.quantity
                or accepted.itemID ~= snapshot.itemID or accepted.link ~= snapshot.link) then
                active.acceptedSnapshot, active.entry.acceptedSnapshot = nil, nil
            end
        end
        -- Empty teardown slots do not overwrite the accepted snapshot. A
        -- subsequent acceptance of an empty offer clears it in AcceptUpdate.
    end

    function engine:CommitCompleted(reconciledSnapshot)
        local active = self.active
        if not active or active.phase ~= "closing" or not active.completedMessage or active.cancelled
            or active.session ~= api.session() then return end
        local snapshot = active.acceptedSnapshot or reconciledSnapshot
        if not snapshot or not validQuantity(snapshot.quantity) then return end
        api.cancelPlacement()
        local entry = active.entry
        entry.state, entry.timestamp = "served", api.timestamp()
        entry.quantity = snapshot.quantity
        entry.completionEvidence = reconciledSnapshot and "server completion + verified offer and bag debit" or "server trade completion"
        entry.quantityMismatch = snapshot.quantity ~= active.quantity or nil
        entry.reason = nil
        self.active = nil
        if entry.quantityMismatch then
            notify(("%s received %d (requested %d). The actual completed trade was recorded.")
                :format(active.partner.name, snapshot.quantity, active.quantity))
        else
            notify(("%s received %d. No repeats tonight."):format(active.partner.name, snapshot.quantity))
        end
    end

    function engine:CompleteMessage()
        local active = self.active
        if not active or active.cancelled or active.session ~= api.session() then return end
        active.completedMessage, active.entry.completionSeen = true, true
        self:CommitCompleted()
    end

    function engine:Cancelled(reason)
        local active = self.active
        if not active or active.session ~= api.session() then return end
        active.cancelled = true
        active.entry.cancellationSeen = true
        active.entry.reason = reason or "Trade cancelled."
        api.cancelPlacement()
    end

    function engine:Close()
        if not self.active or self.active.phase == "closing" then return end
        api.cancelPlacement()
        self.active.phase = "closing"
        self.active.deadline = api.time() + 5
        self:CommitCompleted()
    end

    function engine:Poll()
        local active = self.active
        if not active or active.phase ~= "closing" or api.time() < active.deadline then return end
        local total = api.count(active.item)
        local delta = type(total) == "number" and active.entry.before - total or nil
        if active.completedMessage and active.verifiedOffer and not active.offerContradiction
            and delta == active.verifiedOffer.quantity and not api.cursor() then
            self:CommitCompleted(active.verifiedOffer)
            if not self.active then return end
        end
        -- Acceptance plus a bag decrease cannot establish trade success. A
        -- server completion message is required, and is handled independently
        -- of bag timing or same-item incoming trades in CompleteMessage.
        if not active.completedMessage and (active.cancelled or (not active.hadOffer and not active.acceptedSnapshot))
            and delta == 0 and not api.cursor() then
            local ledger = self:Ledger(active.night)
            ledger[active.partner.guid] = nil
            notify("Trade cancelled or no item transferred. " .. active.partner.name .. " can try again.")
        else
            active.entry.state = "uncertain"
            active.entry.reason = active.completedMessage
                and "Completion arrived without a usable accepted-item snapshot."
                or "No confirmed completion message was received."
            notify("Trade outcome uncertain for " .. active.partner.name .. "; repeat giveaway blocked tonight.")
        end
        self.active = nil
    end

    return engine
end
