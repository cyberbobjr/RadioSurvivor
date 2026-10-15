if isClient() then return end
--[[
Caches (E11-T06): a marked bag filled from one closed table of the server, placed once in the world, and the voice
action place_cache. Authority only. Configuration: RS_Config.Caches (bag type, closed list `order` of the tables and
their contents). Required by RadioSurvivor_Server (executor of place_cache) and RS_MissionRecover (cache of a
`recover` mission); RS_Carnet_Server polls the pending caches once a second (Caches.poll) while a player is connected.
Details: docs/carnet-implementation-04221.md, "Caches et gabarit recuperer"; design: docs/conception/mission-recuperer.md.

One cache per mission: the record is the field m.cache of the mission (private state RS_State, never global ModData):
    { key = mission id, table = name of RS_Config.Caches.order, spot = { x, y, z }, bounds = { x1, y1, x2, y2 }
      (x2, y2 exclusive), placing, placed, itemId, at = { x, y, z } }
A mission that already has a cache never gets a second one (Caches.attach refuses: 'cache_exists').
Deferred placement (Caches.place, at most every placeRetryMs per cache): once the site square itself is loaded
(getCell():getGridSquare of the point, never a neighbour chunk) and its building has passed its vanilla stories
(BuildingDef:isFullyStreamedIn, or one of its rooms explored), on the nearest free square of the same building around
the point (no stairs, isFree), else of the bounds at that floor. The bag (instanceItem(bagType)) gets ModData
RS_Cache = key and its contents (instanceItem of each line of the table, in its container) BEFORE it is put on the
floor by square:AddWorldInventoryItem(bag, 0.5, 0.5, 0, true), which sends the complete item to the clients.
Once only, even after a restart:
    1. rec.placing = true is saved (store.save) before anything is created; a failed save places nothing;
    2. the bag is created, marked and put on the floor; rec.placed, rec.itemId (InventoryItem:getID, saved with the
       item and kept by every MP transfer), rec.at are saved at once;
    3. a record found again with placing but not placed (stop between 1 and 2) first looks for a floor item marked
       RS_Cache = key in the site bounds: found, it is adopted (no second bag); absent (the chunk was not saved
       with it), the bag is placed again. A world restored to an older save than the private state can still lose
       the bag (never duplicate it).
Only caches of missions still 'active' (or 'success': reward cache of a voice mission) are placed; a failed, expired
or cancelled mission places nothing more.

Voice action place_cache { table } (RS_Actions executor; sheet actions=, budget.place_cache per game day, COOLDOWN_MS
per voice): the cache of the caller's last mission given by this voice (open, or its latest success: reward on the
spot, decision E11-T08), placed at that mission's place (scout: the building bounds, m.zone less the scout margin).
Refusals: storage, no_character, no_mission, cache_exists, no_place. The voice never gives a coordinate; the bridge
offers this action only once bridge/radio_bridge.py lists it in EXECUTABLE_ACTIONS.
]]
local Config = require 'RadioSurvivor/RS_Config'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local S = require 'RadioSurvivor/RS_State'
local Actions = require 'RadioSurvivor/RS_Actions'
local V = require 'RadioSurvivor/RS_MissionVoice'

local Caches = {}
Caches.MARK = 'RS_Cache'
Caches.COOLDOWN_MS = 60000
-- Cache key -> last placement attempt (ms), memory only.
local tried = {}

function Caches.resetForTests()
    tried = {}
end

function Caches.isTable(name)
    if type(name) ~= 'string' then return false end
    for _, t in ipairs(Config.Caches.order) do
        if t == name then return true end
    end
    return false
end

-- Table drawn with draw(n) -> 0..n-1 (RS_Rescue.drawer), in the closed order.
function Caches.drawTable(draw)
    local order = Config.Caches.order
    return order[draw(#order) + 1]
end

-- Place of a mission for its cache: spot and bounds of the template (retrieve_id, recover), else the building bounds
-- of a scout zone (m.zone less the scout margin, centre at floor 0). nil when the mission has no place.
function Caches.siteOf(m)
    if type(m.spot) == 'table' and type(m.bounds) == 'table' then
        local b = m.bounds
        return {x = m.spot.x, y = m.spot.y, z = m.spot.z or 0}, {x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2}
    end
    local z = m.zone
    if type(z) ~= 'table' then return nil end
    local r = (Config.Missions.scout and Config.Missions.scout.margin) or 0
    local b = {x1 = z.x1 + r, y1 = z.y1 + r, x2 = z.x2 - r, y2 = z.y2 - r}
    if b.x2 <= b.x1 or b.y2 <= b.y1 then b = {x1 = z.x1, y1 = z.y1, x2 = z.x2, y2 = z.y2} end
    return {x = math.floor((b.x1 + b.x2) / 2), y = math.floor((b.y1 + b.y2) / 2), z = 0}, b
end

-- The cache record of mission m (one per mission). Returns it, or nil and a reason.
function Caches.attach(m, tableName, spot, bounds)
    if m.cache ~= nil then return nil, 'cache_exists' end
    if not Caches.isTable(tableName) then return nil, 'bad_table' end
    if type(spot) ~= 'table' or type(bounds) ~= 'table' then return nil, 'no_place' end
    m.cache = {key = m.id, table = tableName, spot = {x = spot.x, y = spot.y, z = spot.z or 0},
        bounds = {x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2},
        placing = false, placed = false}
    return m.cache
end

-- ---------------------------------------------------------------- placement

-- Building of the site has passed its vanilla stories: fully loaded, or one of its rooms explored.
local function buildingReady(square)
    local building = square:getBuilding()
    local def = building and building:getDef()
    if not def then return true end
    if def:isFullyStreamedIn() then return true end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        if rooms:get(i):isExplored() then return true end
    end
    return false
end

local function freeSquare(square)
    return square ~= nil and square:isFree(false) and not square:HasStairs()
end

local function inBounds(b, x, y)
    return x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2
end

-- Nearest free square of the site's building around the point (rings up to the bounds), else of the bounds.
local function siteSquare(cell, rec, centre)
    local building = centre:getBuilding()
    local p, b = rec.spot, rec.bounds
    local reach = math.max(p.x - b.x1, b.x2 - 1 - p.x, p.y - b.y1, b.y2 - 1 - p.y, 0)
    local fallback
    for ring = 0, reach do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring and inBounds(b, p.x + dx, p.y + dy) then
                    local sq = cell:getGridSquare(p.x + dx, p.y + dy, p.z)
                    if freeSquare(sq) then
                        if building == nil or sq:getBuilding() == building then return sq end
                        fallback = fallback or sq
                    end
                end
            end
        end
    end
    return fallback
end

local function marked(item, key)
    return item ~= nil and item:hasModData() and item:getModData()[Caches.MARK] == key
end

-- Floor item of the site bounds marked for this cache (adoption after a stop between rec.placing and rec.placed).
local function findPlaced(cell, rec)
    local b = rec.bounds
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell:getGridSquare(x, y, rec.spot.z)
            local objects = sq and sq:getWorldObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local item = objects:get(i):getItem()
                    if marked(item, rec.key) then return item, sq end
                end
            end
        end
    end
    return nil
end

-- E12-T04: optional note of a cache record (rec.note = { name, text }, composed by the caller): a vanilla sheet of
-- paper (CanBeWrite, one page) written by addPage then locked by setLockedBy (every reader only gets "Read"), with a
-- custom name. nil when the item cannot be made.
Caches.NOTE_ITEM = 'Base.SheetPaper2'
Caches.NOTE_LOCK = 'RadioSurvivor'
function Caches.makeNote(note)
    if type(note) ~= 'table' or type(note.text) ~= 'string' or note.text == '' then return nil end
    local item = instanceItem(Caches.NOTE_ITEM)
    if item == nil or not instanceof(item, 'Literature') then return nil end
    item:addPage(1, note.text)
    item:setLockedBy(Caches.NOTE_LOCK)
    if type(note.name) == 'string' and note.name ~= '' then
        item:setName(note.name)
        item:setCustomName(true)
    end
    return item
end

-- The bag of a table, marked, with its contents (and the note of the record, E12-T04). nil when the bag type is
-- unknown.
function Caches.make(rec)
    local bag = instanceItem(Config.Caches.bagType)
    if not bag then return nil end
    bag:getModData()[Caches.MARK] = rec.key
    local inside = bag:getItemContainer()
    for _, line in ipairs(Config.Caches.tables[rec.table] or {}) do
        for _ = 1, line[2] do
            local it = instanceItem(line[1])
            if it then inside:AddItem(it) else Const.log('cache: unknown item ' .. tostring(line[1])) end
        end
    end
    if rec.note ~= nil then
        local note = Caches.makeNote(rec.note)
        if note then inside:AddItem(note) else Const.log('cache: note of ' .. tostring(rec.key) .. ' not made') end
    end
    return bag
end

local function settle(rec, item, sq)
    rec.placed, rec.placing, rec.itemId = true, false, item:getID()
    rec.at = {x = sq:getX(), y = sq:getY(), z = sq:getZ()}
    tried[rec.key] = nil
end

-- Deferred placement of one cache (see the header). store: RS_State or a double { save }. Returns true when the
-- record changed (placed or adopted).
function Caches.place(store, rec)
    if type(rec) ~= 'table' or rec.placed then return false end
    local c = Config.Caches
    local now = getTimestampMs()
    if tried[rec.key] and now - tried[rec.key] < c.placeRetryMs then return false end
    local cell = getCell()
    if not cell then return false end
    local centre = cell:getGridSquare(rec.spot.x, rec.spot.y, rec.spot.z)
    if not centre or not buildingReady(centre) then return false end
    tried[rec.key] = now
    if rec.placing then
        local item, at = findPlaced(cell, rec)
        if item then
            settle(rec, item, at)
            store.save()
            Const.log('cache: ' .. tostring(rec.key) .. ' found again on the floor, adopted')
            return true
        end
    end
    local sq = siteSquare(cell, rec, centre)
    if not sq then
        Const.log('cache: no free square for ' .. tostring(rec.key))
        return false
    end
    rec.placing = true
    if not store.save() then
        Const.log('cache: state not saved, ' .. tostring(rec.key) .. ' not placed')
        return false
    end
    local bag = Caches.make(rec)
    if not bag then
        Const.log('cache: unknown bag item ' .. tostring(c.bagType))
        return false
    end
    sq:AddWorldInventoryItem(bag, 0.5, 0.5, 0, true)
    settle(rec, bag, sq)
    store.save()
    Const.log('cache: ' .. tostring(rec.key) .. ' placed (' .. tostring(rec.table) .. ')')
    return true
end

-- Pending caches of the missions still active (or successful) of state. Returns true when one changed.
function Caches.poll(state, store)
    store = store or S
    local changed = false
    for _, m in pairs(type(state) == 'table' and state.missions or {}) do
        local rec = m.cache
        if type(rec) == 'table' and not rec.placed and not m.transaction
                and (m.state == 'active' or m.state == 'success') and Caches.place(store, rec) then
            m.revision = (m.revision or 0) + 1
            changed = true
        end
    end
    return changed
end

-- ---------------------------------------------------------------- voice action place_cache

-- Last mission given by this voice to this character: the open one, else its latest success. nil without any.
function Caches.voiceMission(state, voice, cid)
    local open = V.open(state, voice, cid)
    if open then return open end
    local d = V.donor(state, voice, cid, false)
    if not d then return nil end
    local best
    for _, m in pairs(state.missions) do
        if m.npc == d.id and m.state == 'success' and (not best or (m.closedAt or 0) > (best.closedAt or 0)) then
            best = m
        end
    end
    return best
end

local function validate(params)
    for key in pairs(params) do
        if key ~= 'table' then return false end
    end
    return Caches.isTable(params.table)
end

local function execute(params, ctx)
    local state = S.data
    if type(state) ~= 'table' or S.blocked then return false, 'storage' end
    local cid = type(ctx) == 'table' and ctx.cid or nil
    local record = type(cid) == 'string' and state.characters[cid] or nil
    if not record or record.retired then return false, 'no_character' end
    local m = Caches.voiceMission(state, ctx.voice, cid)
    if not m then return false, 'no_mission' end
    if m.cache ~= nil then return false, 'cache_exists' end
    local spot, bounds = Caches.siteOf(m)
    local rec, why = Caches.attach(m, params.table, spot, bounds)
    if not rec then return false, why end
    m.revision = m.revision + 1
    if not S.save() then
        m.cache = nil
        return false, 'storage'
    end
    Const.log('cache of ' .. tostring(m.id) .. ' requested by voice ' .. tostring(ctx.voice) .. ' (' .. params.table .. ')')
    return true
end

function Caches.register()
    return Actions.register('place_cache', {validate = validate, cooldownMs = Caches.COOLDOWN_MS, execute = execute})
end

Caches.register()

return Caches
