-- A dead drop is collected only when nobody is close enough to watch it.
if isClient() then return end
local Config = require 'RadioSurvivor/RS_Config'
local D = {}
local unseen = {} -- Real-time delay deliberately restarts after a process restart.
local nextBox = 0

local function cfg() return Config.VoiceDelivery end

local function eligible(item, m)
    return item and m.accepted[item:getFullType()] == true and item:getCondition() > 0
        and not item:isFavorite() and not item:isEquipped()
end

local function eachSquare(m, visit)
    local cell = getCell()
    local p = m.deposit
    if not cell or not cell:getGridSquare(p.x, p.y, p.z) then return false end
    for r = 0, cfg().radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = p.x + dx, p.y + dy
                    local sq = cell:getGridSquare(x, y, p.z)
                    if sq and visit(sq, x, y) then return true end
                end
            end
        end
    end
    return false
end

local function boxAt(m)
    local b = m.deposit.box
    if not b then return nil end
    local cell = getCell()
    local sq = cell and cell:getGridSquare(b.x, b.y, m.deposit.z)
    local objects = sq and sq:getObjects()
    if not objects or not b.key then return nil end
    local object
    for i = 0, objects:size() - 1 do
        local candidateObject = objects:get(i)
        local marks = candidateObject:getModData().RS_DeadDrop
        if type(marks) == 'table' and marks[b.key] == true then object = candidateObject; break end
    end
    if not object or b.container >= object:getContainerCount() then return nil end
    local container = object:getContainerByIndex(b.container)
    if b.type and container:getType() ~= b.type then return nil end
    local sprite = object.getSprite and object:getSprite()
    if b.sprite and (not sprite or sprite:getName() ~= b.sprite) then return nil end
    return container
end

-- Snapshot existing contents so a mission never takes pre-existing household supplies.
-- Selection is bounded and deterministic, then persisted before the player deposits anything.
function D.prepare(m, store)
    local p = m.deposit
    if not p or p.ready then return p and p.ready or false end
    local cell = getCell()
    if not cell or not cell:getGridSquare(p.x, p.y, p.z) then return false end
    local baseline, n = {}, 0
    if p.mode ~= 'bag' then
        eachSquare(m, function(sq, x, y)
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                for k = 0, o:getContainerCount() - 1 do
                    local c = o:getContainerByIndex(k)
                    if c and c:getItems():size() <= cfg().maxItems then
                        local sprite = o.getSprite and o:getSprite()
                        p.box = {x = x, y = y, object = i, container = k,
                            type = c.getType and c:getType() or nil,
                            sprite = sprite and sprite:getName() or nil}
                        nextBox = nextBox + 1
                        p.box.key = tostring(getTimestampMs()) .. '-' .. tostring(nextBox)
                        local md = o:getModData()
                        if type(md.RS_DeadDrop) ~= 'table' then md.RS_DeadDrop = {} end
                        -- Opaque identity only, no voice, character or mission secrets in world metadata.
                        md.RS_DeadDrop[p.box.key] = true
                        for j = 0, c:getItems():size() - 1 do baseline[tostring(c:getItems():get(j):getID())] = true end
                        return true
                    end
                end
            end
            return false
        end)
    end
    if p.box then p.mode = 'box'
    else
        p.mode = 'bag'
        eachSquare(m, function(sq)
            local objects = sq:getWorldObjects()
            for i = 0, objects:size() - 1 do
                baseline[tostring(objects:get(i):getItem():getID())] = true
                n = n + 1
            end
            return false
        end)
        if n > cfg().maxItems then return false end
    end
    p.baseline, p.ready = baseline, true
    m.mapZone = {x = p.box and p.box.x or p.x, y = p.box and p.box.y or p.y, r = p.box and 1 or cfg().radius}
    if not store.save() then p.ready, p.baseline, p.box = nil, nil, nil; return false end
    return true
end

local function bagAt(m, id)
    local found, square, world
    eachSquare(m, function(sq)
        local objects = sq:getWorldObjects()
        for i = 0, objects:size() - 1 do
            local wo = objects:get(i)
            local item = wo:getItem()
            if item:getID() == id then found, square, world = item, sq, wo; return true end
        end
        return false
    end)
    return found, square, world
end

local function contents(container, m, strict)
    local items, out = container:getItems(), {}
    if items:size() > cfg().maxItems then return nil end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local old = m.deposit.baseline[tostring(item:getID())]
        if not old and eligible(item, m) then
            out[#out + 1] = item:getID()
        elseif strict then return nil end
    end
    local needed = m.quantity - m.delivered
    if #out < needed or (strict and #out ~= needed) then return nil end
    while #out > needed do table.remove(out) end
    return out
end

local function candidate(m)
    if m.deposit.mode == 'box' then
        local c = boxAt(m)
        local ids = c and contents(c, m, false)
        if ids then return {mode = 'box', ids = ids, count = #ids} end
    else
        local result
        eachSquare(m, function(sq)
            local objects = sq:getWorldObjects()
            for i = 0, objects:size() - 1 do
                local bag = objects:get(i):getItem()
                if not m.deposit.baseline[tostring(bag:getID())] and instanceof(bag, 'InventoryContainer')
                        and not bag:isFavorite() then
                    local ids = contents(bag:getItemContainer(), m, true)
                    if ids then
                        result = {mode = 'bag', bag = bag:getID(), ids = ids, count = #ids,
                            x = sq:getX(), y = sq:getY(), z = sq:getZ()}
                        return true
                    end
                end
            end
            return false
        end)
        return result
    end
    return nil
end

local function same(a, b)
    if not a or not b or a.mode ~= b.mode or a.bag ~= b.bag or #a.ids ~= #b.ids then return false end
    if a.mode == 'bag' and b.x and (a.x ~= b.x or a.y ~= b.y or a.z ~= b.z) then return false end
    local ids = {}
    for _, id in ipairs(a.ids) do ids[id] = true end
    for _, id in ipairs(b.ids) do if not ids[id] then return false end end
    return true
end

local function nearby(player, p)
    if not player or (player.isDead and player:isDead()) then return false end
    local dx, dy = player:getX() - p.x, player:getY() - p.y
    return dx * dx + dy * dy < cfg().unseenDistance * cfg().unseenDistance
end

function D.witness(m, participant)
    local point = m.deposit.box or m.deposit
    local pending = m.pickup or m.depositCandidate
    if m.deposit.mode == 'bag' and pending and pending.bag then
        local _, sq = bagAt(m, pending.bag)
        if sq then point = {x = sq:getX(), y = sq:getY()} end
    end
    if nearby(participant, point) then return true end
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do if nearby(players:get(i), point) then return true end end
    else
        for i = 0, getNumActivePlayers() - 1 do
            if nearby(getSpecificPlayer(i), point) then return true end
        end
    end
    return false
end

-- The durable pickup journal is distinct from M.transaction: the regular mission poll must be able to resume it.
-- A missing prepared item is ambiguous after interruption: fail closed, never credit an unproven pickup.
local function collect(m, store)
    local tx = m.pickup
    local cell = getCell()
    if not cell or not cell:getGridSquare(m.deposit.x, m.deposit.y, m.deposit.z) then return false end
    if tx.mode == 'bag' then
        local bag, sq, wo = bagAt(m, tx.bag)
        if not bag then
            tx.error = 'missing_bag'
            store.save()
            return false
        else
            local current = {mode = 'bag', bag = tx.bag, ids = contents(bag:getItemContainer(), m, true) or {},
                x = sq:getX(), y = sq:getY(), z = sq:getZ()}
            if not same(tx, current) then return false end
            sq:transmitRemoveItemFromSquare(wo)
            if bagAt(m, tx.bag) then
                tx.error = 'bag_remove_failed'
                store.save()
                return false
            end
        end
    else
        local container = boxAt(m)
        if not container then return false end
        for _, id in ipairs(tx.ids) do
            local item = container:getItemWithIDRecursiv(id)
            if not eligible(item, m) then
                tx.error = 'missing_items'
                store.save()
                return false
            end
        end
        for _, id in ipairs(tx.ids) do
            local item = container:getItemWithIDRecursiv(id)
            if item then
                container:DoRemoveItem(item)
                if isServer() then sendRemoveItemFromContainer(container, item) end
                if container:getItemWithIDRecursiv(id) then
                    tx.error = 'item_remove_failed'
                    store.save()
                    return false
                end
            end
        end
    end
    m.delivered = tx.before + tx.count
    tx.status = 'applied'
    if not store.save() then return false end
    m.pickup, m.depositCandidate = nil, nil
    unseen[m.id] = nil
    store.save()
    return true
end

function D.observe(m, player, _name, _state, store)
    if m.donor ~= 'voice' or m.state ~= 'active' or not m.deposit or not store then return false end
    if m.pickup and m.pickup.status == 'applied' then
        m.delivered = m.pickup.before + m.pickup.count
        m.pickup = nil
        return store.save()
    end
    if m.delivered >= m.quantity then return false end
    if m.pickup and m.pickup.error then return false end
    local prepared = not m.deposit.ready
    if not D.prepare(m, store) then return false end
    local found
    if not m.pickup then
        found = candidate(m)
        if not found then unseen[m.id] = nil; return prepared end
        if not same(found, m.depositCandidate) then
            m.depositCandidate, unseen[m.id] = found, nil
            if not store.save() then m.depositCandidate = nil; return false end
        end
    end
    if D.witness(m, player) then unseen[m.id] = nil; return prepared end
    if m.pickup then
        local now = getTimestampMs()
        if not unseen[m.id] then unseen[m.id] = now; return false end
        if now - unseen[m.id] < cfg().unseenMs then return false end
        return collect(m, store)
    end
    local now = getTimestampMs()
    if not unseen[m.id] then unseen[m.id] = now; return false end
    if now - unseen[m.id] < cfg().unseenMs then return false end
    found.before, found.status = m.delivered, 'prepared'
    m.pickup = found
    if not store.save() then m.pickup = nil; return false end
    return collect(m, store)
end

function D.resetForTests() unseen = {} end
return D
