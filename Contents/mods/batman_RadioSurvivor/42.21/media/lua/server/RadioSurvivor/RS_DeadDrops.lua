-- Dead drops of a radio voice mission (E20-T01, E20-T05, E20-T06, ADR D06). Authority only.
-- Any mission template that declares the strategy dropAccepts(m, item) (RC_Missions: deliver = accepted goods,
-- retrieve_id = the card of the mission by item id) gets dead drops when a voice gives it: the set-up is registered for
-- that declaration (RS_MissionVoice.registerDeclaredSetup), the poll and projection are the voice giver's drop hooks
-- (RS_MissionHooks: observeDrops, projectDrops, dropsWhere, dropsRule, called by the engine).
-- The mission carries all the drops of its sheet section (`drops=`: a list of places, or `any`/none = every place
-- with use=drop), all marked on the participant's map; the player leaves items at any of them and deposits add up
-- toward the quantity, each item credited once (m.credited: ids saved with the mission). Only items the template's
-- strategy accepts are taken. A drop is collected only out of everyone's view and after m.collectHours game hours
-- (RS_OutOfSight; default RS_Config.DeadDrops.collectDelayHours, section parameter collect_hours). A drop whose delay
-- passed while its square was unloaded is due: it is collected at the first pass where the square is loaded again.
-- Drop record (m.drops[i], private state): id, label, x, y, z, mode ('box' preferred on odd missions, 'bag' otherwise;
-- a drop without a container becomes 'bag'), ready, baseline (ids present at preparation, never taken), box (marked
-- container), hiddenSince (RS_OutOfSight), due, pickup (write-ahead journal of a pickup in progress).
-- Registered in RS_MissionVoice (V.registerDeclaredSetup). ASCII only (Kahlua lexer).
if isClient() then return end
local Config = require 'RadioSurvivor/RS_Config'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Voice = require 'RadioSurvivor/RS_MissionVoice'
local Persona = require 'RadioSurvivor/RS_Persona'
local Missions = require 'RadioSurvivorCore/RC_Missions'
local OutOfSight = require 'RadioSurvivor/RS_OutOfSight'
local D = {}
local nextBox = 0
local sight = OutOfSight.engine()

local function cfg() return Config.DeadDrops end

-- Composition: the out-of-sight watcher (tests or another engine may inject theirs).
function D.useSight(watcher) sight = watcher end

local function delayOf(m)
    return type(m.collectHours) == 'number' and m.collectHours or cfg().collectDelayHours
end

-- Strategy of the mission's template (declaration dropAccepts): the items a drop may collect for this mission.
local function accepts(m, item)
    local t = Missions.template(m)
    return t ~= nil and type(t.dropAccepts) == 'function' and t.dropAccepts(m, item) == true
end

local function credited(m, id)
    return type(m.credited) == 'table' and m.credited[tostring(id)] == true
end

local function fresh(m, d, item)
    return not d.baseline[tostring(item:getID())] and not credited(m, item:getID())
end

local function squareOf(d, x, y)
    local cell = getCell()
    return cell and cell:getGridSquare(x or d.x, y or d.y, d.z)
end

local function eachSquare(d, visit)
    if not squareOf(d) then return false end
    for r = 0, cfg().radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = squareOf(d, d.x + dx, d.y + dy)
                    if sq and visit(sq, d.x + dx, d.y + dy) then return true end
                end
            end
        end
    end
    return false
end

local function boxAt(d)
    local b = d.box
    if not b or not b.key then return nil end
    local sq = squareOf(d, b.x, b.y)
    local objects = sq and sq:getObjects()
    if not objects then return nil end
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

-- Marks the first container (bounded size) near the drop as the agreed box; its contents become the baseline.
local function markBox(d, baseline)
    return eachSquare(d, function(sq, x, y)
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            for k = 0, o:getContainerCount() - 1 do
                local c = o:getContainerByIndex(k)
                if c and c:getItems():size() <= cfg().maxItems then
                    local sprite = o.getSprite and o:getSprite()
                    nextBox = nextBox + 1
                    d.box = {x = x, y = y, object = i, container = k, type = c.getType and c:getType() or nil,
                        sprite = sprite and sprite:getName() or nil,
                        key = tostring(getTimestampMs()) .. '-' .. tostring(nextBox)}
                    local md = o:getModData()
                    if type(md.RS_DeadDrop) ~= 'table' then md.RS_DeadDrop = {} end
                    -- Opaque identity only, no voice, character or mission secrets in world metadata.
                    md.RS_DeadDrop[d.box.key] = true
                    for j = 0, c:getItems():size() - 1 do baseline[tostring(c:getItems():get(j):getID())] = true end
                    return true
                end
            end
        end
        return false
    end)
end

-- Snapshot of the existing contents of one drop, so a mission never takes pre-existing household supplies.
-- Selection is bounded and deterministic, then persisted before the player deposits anything.
function D.prepare(m, d, store)
    if d.ready then return true end
    if not squareOf(d) then return false end
    local baseline, n = {}, 0
    if d.mode ~= 'bag' then markBox(d, baseline) end
    if d.box then
        d.mode = 'box'
    else
        d.mode = 'bag'
        eachSquare(d, function(sq)
            local objects = sq:getWorldObjects()
            for i = 0, objects:size() - 1 do
                baseline[tostring(objects:get(i):getItem():getID())] = true
                n = n + 1
            end
            return false
        end)
        if n > cfg().maxItems then return false end
    end
    d.baseline, d.ready = baseline, true
    if not store.save() then d.ready, d.baseline, d.box = nil, nil, nil; return false end
    return true
end

-- Items of a container the drop may take: new items the strategy accepts, at most `needed`; strict (a bag): every
-- item must be such an item and there must be no more than `needed`.
local function contents(m, d, container, needed, strict)
    local items, out = container:getItems(), {}
    if items:size() > cfg().maxItems then return nil end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if fresh(m, d, item) and accepts(m, item) then
            out[#out + 1] = item:getID()
        elseif strict then return nil end
    end
    if #out == 0 or (strict and #out > needed) then return nil end
    while #out > needed do table.remove(out) end
    return out
end

local function bagCandidate(m, d, needed)
    local result
    eachSquare(d, function(sq)
        local objects = sq:getWorldObjects()
        for i = 0, objects:size() - 1 do
            local wo = objects:get(i)
            local bag = wo:getItem()
            if fresh(m, d, bag) and instanceof(bag, 'InventoryContainer') and not bag:isFavorite() then
                local ids = contents(m, d, bag:getItemContainer(), needed, true)
                if ids then result = {ids = ids, square = sq, world = wo}; return true end
            end
        end
        return false
    end)
    return result
end

local function removeFromBox(container, ids)
    local removed = {}
    for _, id in ipairs(ids) do
        local item = container:getItemWithIDRecursiv(id)
        if item then
            container:DoRemoveItem(item)
            if isServer() then sendRemoveItemFromContainer(container, item) end
            if not container:getItemWithIDRecursiv(id) then removed[#removed + 1] = id end
        end
    end
    return removed
end

local function removeBag(found)
    found.square:transmitRemoveItemFromSquare(found.world)
    local objects = found.square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == found.world then return {} end
    end
    return found.ids
end

local function credit(m, ids)
    if type(m.credited) ~= 'table' then m.credited = {} end
    for _, id in ipairs(ids) do m.credited[tostring(id)] = true end
    m.delivered = m.delivered + #ids
end

-- Pickup of the goods of a loaded drop. The journal is saved before anything is destroyed; only the items really
-- removed are credited.
local function collect(m, d, store)
    local needed = m.quantity - m.delivered
    local container, found
    if d.mode == 'box' then
        container = boxAt(d)
        local ids = container and contents(m, d, container, needed, false)
        found = ids and {ids = ids}
    else
        found = bagCandidate(m, d, needed)
    end
    if not found then return false end
    d.pickup = {ids = found.ids}
    if not store.save() then d.pickup = nil; return false end
    local removed = container and removeFromBox(container, found.ids) or removeBag(found)
    credit(m, removed)
    d.pickup = nil
    store.save()
    return #removed > 0
end

-- A journal left by an interrupted pickup is ambiguous (removed or not): fail closed, never credit an unproven pickup.
local function dropJournal(m, d, store)
    if not d.pickup then return end
    d.pickup = nil
    Const.log('dead drop pickup of mission ' .. tostring(m.id) .. ' interrupted: not credited')
    store.save()
end

local function observeDrop(m, d, store)
    dropJournal(m, d, store)
    local changed = false
    if not d.ready then
        if not D.prepare(m, d, store) then return false end
        changed = true
    end
    local point = d.box and {x = d.box.x, y = d.box.y, z = d.z} or d
    local ready, moved = sight.watch(d, point, delayOf(m))
    if not ready and not d.due then
        if moved then store.save() end
        return changed
    end
    if not squareOf(d) then
        if not d.due then d.due = true; store.save() end
        return changed
    end
    local wasDue = d.due
    d.due = nil
    local collected = collect(m, d, store)
    if not collected and (wasDue or moved) then store.save() end
    return changed or collected
end

-- Poll of the voice giver (hook observeDrops, called by RC_Missions.observe): every drop, in the order of the mission.
function D.observe(m, _player, _name, _state, store)
    if m.donor ~= 'voice' or m.state ~= 'active' or type(m.drops) ~= 'table' or not store then return false end
    local changed = false
    for _, d in ipairs(m.drops) do
        if m.delivered >= m.quantity then break end
        if observeDrop(m, d, store) then changed = true end
    end
    return changed
end

-- Notebook projection (hook projectDrops, called by RC_Missions.projection): drops with their label and mode, whether
-- everything was collected; map zones for a participant.
function D.project(m, p)
    p.drops, p.collectHours = {}, delayOf(m)
    p.depositCollected = m.delivered >= m.quantity
    if p.engaged then p.dropZones = {} end
    for _, d in ipairs(type(m.drops) == 'table' and m.drops or {}) do
        p.drops[#p.drops + 1] = {label = d.label, mode = d.mode, ready = d.ready == true}
        if p.engaged then
            local at = d.box or d
            p.dropZones[#p.dropZones + 1] = {x = at.x, y = at.y, r = d.box and 1 or cfg().radius, label = d.label}
        end
    end
end

-- Labels of the drops, as told to the voice (no coordinate).
function D.where(m)
    local labels = {}
    for _, d in ipairs(type(m.drops) == 'table' and m.drops or {}) do labels[#labels + 1] = tostring(d.label) end
    return table.concat(labels, ', ')
end

-- Collection rule told to the voice (hook dropsRule, read by the template's voiceBrief through RC_Missions.dropsRule).
function D.rule(m)
    return 'Collection rule: the caller may use any of the drop points and split the goods between them; deposits '
        .. 'add up. A drop is collected only out of sight of everyone (nobody within about '
        .. tostring(OutOfSight.VIEW_TILES) .. ' tiles), about ' .. tostring(delayOf(m)) .. ' game hours after the '
        .. 'last person left; coming back in sight before that restarts the wait. In a bag, leave only the requested '
        .. 'goods: the whole bag is taken. Never claim collection before the server confirms it.'
end

-- Set-up of a voice mission with dead drops: every drop of its section (E20-T03 places with use=drop).
local function dropPlaces(sheet, section)
    local wanted = type(section) == 'table' and type(section.drops) == 'table' and section.drops or {}
    if #wanted == 0 then return Persona.placesFor(sheet, 'drop') end
    local byId, out = {}, {}
    for _, p in ipairs(Persona.placesFor(sheet, 'drop')) do byId[p.id] = p end
    for _, id in ipairs(wanted) do
        if byId[id] then out[#out + 1] = byId[id] end
    end
    return out
end

local function hasPlaces(sheet, section)
    if #dropPlaces(sheet, section) == 0 then return false, 'no_place' end
    return true
end

local function setUp(m, sheet, donor, section)
    local mode = donor.missionCount % 2 == 1 and 'box' or 'bag'
    local params = type(section) == 'table' and type(section.params) == 'table' and section.params or {}
    m.collectHours = params.collect_hours or cfg().collectDelayHours
    m.drops, m.credited = {}, {}
    -- Saved atomically with acceptance by RS_MissionVoice; do not persist a half-created mission.
    local noSave = {save = function() return true end}
    for _, place in ipairs(dropPlaces(sheet, section)) do
        local d = {id = place.id, label = place.label, x = place.x, y = place.y, z = place.z or 0, mode = mode}
        m.drops[#m.drops + 1] = d
        D.prepare(m, d, noSave)
    end
    -- A mission without a place of its own (deliver) takes place at its drops; retrieve_id keeps its search place.
    if m.place == nil or m.place == '' then m.place, m.placeKind = D.where(m), 'dead drop' end
end

Voice.registerDeclaredSetup('dropAccepts', {check = hasPlaces, apply = setUp})

return D
