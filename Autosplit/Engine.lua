local _, Autosplit = ...

-- Inventory operations are injected so the real queue can also be tested without WoW.
function Autosplit.CreateEngine(api, onChange)
    local engine = {}
    local timeout = 5

    local function sameItem(info, source)
        return info and info.itemID == source.itemID and info.hyperlink == source.hyperlink
    end

    function engine:Snapshot(bag, slot)
        local info = api.info(bag, slot)
        if not info or info.stackCount < 2 then
            return nil, "Choose a stack containing at least two items."
        end
        if info.isLocked then
            return nil, "That stack is busy. Try again in a moment."
        end
        return {
            bag = bag, slot = slot, itemID = info.itemID,
            hyperlink = info.hyperlink, count = info.stackCount,
            guid = api.guid(bag, slot), icon = info.iconFileID,
        }
    end

    function engine:Matches(source, count)
        local info = api.info(source.bag, source.slot)
        return sameItem(info, source) and info.stackCount == count
            and (not source.guid or api.guid(source.bag, source.slot) == source.guid), info
    end

    function engine:Finish(message, success)
        local job = self.job
        self.job = nil
        if job then
            onChange("finished", message, job.completed, job.quantity, success)
        end
    end

    function engine:Cancel()
        if self.job then
            self:Finish("Stopped. Items already separated stay in their slots.", false)
        end
    end

    function engine:Start(source, quantity)
        if self.job then return nil, "A split is already running." end
        if api.combat() then return nil, "Leave combat before splitting items." end
        if api.cursor() then return nil, "Clear your cursor before splitting items." end
        if type(quantity) ~= "number" or quantity ~= quantity or quantity % 1 ~= 0
            or quantity < 1 or quantity > source.count then
            return nil, "Enter a whole number from 1 to " .. source.count .. "."
        end
        local matches, info = self:Matches(source, source.count)
        if not matches then return nil, "The selected stack changed. Ctrl-click it again." end
        if info.isLocked then return nil, "That stack is busy. Try again in a moment." end

        -- For a full split, the final singleton already occupies the source slot.
        local moves = quantity == source.count and quantity - 1 or quantity
        local destinations = api.destinations(source)
        if #destinations < moves then
            return nil, ("Need %d compatible empty bag slots; only %d available."):format(moves, #destinations)
        end
        self.job = {
            source = source, quantity = quantity, moves = moves,
            completed = 0, expected = source.count, destinations = destinations,
            deadline = api.time() + timeout,
        }
        onChange("started", nil, 0, quantity)
        self:Step()
        return true
    end

    function engine:Step()
        if self.stepping or not self.job then return end
        self.stepping = true
        self:Advance()
        self.stepping = false
    end

    function engine:Advance()
        local job = self.job
        if api.combat() then
            self:Finish("Stopped because combat started.", false)
            return
        end
        if api.cursor() then
            self:Finish("Stopped: an item or action is on your cursor. Place it safely before retrying.", false)
            return
        end

        local matches, sourceInfo = self:Matches(job.source, job.expected)
        if job.pending then
            local target = api.info(job.pending.bag, job.pending.slot)
            if matches and not sourceInfo.isLocked and sameItem(target, job.source)
                and target.stackCount == 1 and not target.isLocked then
                job.completed = job.completed + 1
                job.pending = nil
                job.deadline = api.time() + timeout
                onChange("progress", nil, job.completed, job.quantity)
                if job.completed == job.moves then
                    self:Finish(("Done: %d single-item stacks ready."):format(job.quantity), true)
                    return
                end
                -- Continue on the next event/timer tick, never in a tight loop.
                return
            elseif api.time() >= job.deadline then
                self:Finish("Stopped: the inventory did not confirm the last move. Check your bags before retrying.", false)
            end
            return
        end

        if not matches then
            self:Finish("Stopped: the original stack changed or moved.", false)
            return
        end
        if sourceInfo.isLocked then
            if api.time() >= job.deadline then
                self:Finish("Stopped: the stack stayed locked for too long.", false)
            end
            return
        end
        local destination = job.destinations[job.completed + 1]
        if api.info(destination.bag, destination.slot) or not api.accepts(destination.bag, job.source) then
            self:Finish("Stopped: a reserved empty slot changed. Ctrl-click the stack to try again.", false)
            return
        end

        api.split(job.source.bag, job.source.slot, 1)
        local cursorType, cursorID = api.cursor()
        if cursorType ~= "item" or cursorID ~= job.source.itemID then
            self:Finish("WoW could not pick up one item. Check your cursor and try again.", false)
            return
        end
        -- Recheck immediately before placement; never swap with or merge into another stack.
        if api.info(destination.bag, destination.slot) then
            self:Finish("Stopped: the destination filled. Place the item on your cursor safely.", false)
            return
        end
        job.expected = job.expected - 1
        job.pending = destination
        job.deadline = api.time() + timeout
        api.pickup(destination.bag, destination.slot)
        if api.cursor() then
            self:Finish("WoW could not place the item. Place it from your cursor into an empty slot.", false)
        end
    end

    return engine
end
