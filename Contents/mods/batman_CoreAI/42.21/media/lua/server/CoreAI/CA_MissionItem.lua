if isClient() then return end
--[[
Mission template `item` (E20-T15, ADR D06, D10): find a personal item the server put at a place named by the giver and
leave it at one of the mission's dead drops, then report by radio. Authority only. Catalogue:
CA_MissionConfig.Missions.item (offer id item_v1). Registered in CA_Missions (M.register); required by
CA_NotebookServer.

Giver: a radio voice only, under the name `item` (declaration voiceName); an NPC fiche is never offered one.
Parameters of its sheet section (declaration params): item = full type of a vanilla item script (kind `item` of
RadioSurvivor's RS_PersonaParams: a photo, a locket, a pocket watch...; required), label = how the voice names it
(optional text, e.g. "Ellen's locket"; else the display name of its script), collect_hours (game hours before a drop
is collected, E20-T05).
Place (declaration aimAt, RadioSurvivor's RS_MissionTarget): the place `target` of the sheet; the building at it
(IsoMetaGrid:getBuildingAt(x, y, z), IsoMetaGrid.java:271-280, footprint BuildingDef getX/getY, getX2/getY2
exclusive), else a square zone of entry.zoneHalf tiles around it, at the level of the place. aimAt refuses a section
without item= or with a type the item scripts do not know (ScriptManager.FindItem, ScriptManager.java:1325): 'no_item'.
Placement (deferred, once, the reward cache rules of CA_Caches): m.personal is a cache record of its own (key
<mission id>:item, never m.cache, which stays free for a reward cache) placed by Caches.place with the maker
Item.make: a new item of that type (instanceItem), marked ModData CA_Cache = key, put on the nearest free floor square
of the building around the place (AddWorldInventoryItem(item, 0.5, 0.5, 0, true): sent to the clients), once the
square of the place is loaded and the building has passed its vanilla stories; the placing flag is saved first and a
floor item already marked with the key is adopted after a stop (never a second item). The engine poll of a participant
(Item.observe, once a second on the server) places it; the mission keeps m.itemId = InventoryItem:getID() (random at
creation, saved with the item, kept by every MP transfer).
Found: the same poll sets m.found once a participant holds it (server copy of the inventory, bags included).
Deposit (dead drops of the giver, RadioSurvivor's RS_DeadDrops: all marked on the map, collected out of everyone's
view after a delay in game hours): only the item whose id is m.itemId is taken (strategy dropAccepts =
M.onlyItem('itemId')); another item of the same type is left where it is. Once collected (m.delivered = quantity = 1),
the objective is met and the radio report succeeds without touching any inventory (check of 'speech').
Notebook (MissionViews/CA_View_Item): name of the item, place label, found or not, drop points; map: a
circle around the place (m.mapZone, style Item). The voice is told the item's name, the place and the drop labels,
whether the item was found and collected; never a coordinate nor the item id.
ASCII only (Kahlua lexer).
]]
local M = require 'CoreAI/CA_Missions'
local Config = require 'CoreAI/CA_MissionConfig'
local Caches = require 'CoreAI/CA_Caches'
local Clear = require 'CoreAI/CA_MissionClear' -- Clear.zone: circle around the place's bounds

local Item = {idPrefix = 'item', voiceName = 'item', mapStyle = 'Item',
    voiceText = 'find a personal item at a place and leave it at a dead drop',
    params = {item = 'item', label = 'text', collect_hours = 'count'}}

local function entry() return Config.Missions.item end

local function itemScript(fullType)
    local scripts = getScriptManager and getScriptManager()
    if not scripts then return nil, false end
    return scripts:FindItem(fullType), true
end

-- Footprint { x1, y1, x2, y2 } (x2, y2 exclusive) of the building at the place, else of a zone around it.
function Item.bounds(place, c)
    local x, y, z = math.floor(place.x), math.floor(place.y), math.floor(tonumber(place.z) or 0)
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    local def = grid and grid:getBuildingAt(x, y, z)
    if def then return {x1 = def:getX(), y1 = def:getY(), x2 = def:getX2(), y2 = def:getY2()} end
    local h = c.zoneHalf
    return {x1 = x - h, y1 = y - h, x2 = x + h + 1, y2 = y + h + 1}
end

-- Declaration aimAt (set-up of a voice mission with a target place, RadioSurvivor's RS_MissionTarget): the item of
-- the section's parameters at `place`; also called on a scratch table to check a section before the mission exists.
-- Returns true, or false and 'no_item'.
function Item.aimAt(m, place, params)
    local fullType = type(params) == 'table' and params.item or nil
    if type(fullType) ~= 'string' or fullType == '' then return false, 'no_item' end
    local script, known = itemScript(fullType)
    if known and script == nil then return false, 'no_item' end
    local c = entry()
    local b = Item.bounds(place, c)
    local z = math.floor(tonumber(place.z) or 0)
    local spot = {x = math.floor(place.x), y = math.floor(place.y), z = z}
    m.place, m.placeKind = tostring(place.label or ''), nil
    m.itemType, m.itemLabel = fullType, type(params.label) == 'string' and params.label or ''
    m.itemName = script and tostring(script:getDisplayName()) or fullType
    m.spot, m.bounds = spot, b
    m.personal = {key = tostring(m.id) .. ':item', table = 'personal', fullType = fullType, spot = spot,
        bounds = {x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2}, placing = false, placed = false}
    m.mapZone = Clear.zone(b, c)
    return true
end

-- Maker of the record (Caches.place): the personal item, marked for adoption; nil for an unknown type.
function Item.make(rec)
    local it = instanceItem(rec.fullType)
    if not it then return nil end
    it:getModData()[Caches.MARK] = rec.key
    return it
end

-- ---------------------------------------------------------------- engine interface

-- A radio voice only (its donor record carries `voice`); the place and the item come with the set-up (aimAt).
function Item.offer(c, npc)
    if type(npc) ~= 'table' or npc.voice == nil then return nil end
    return {kind = 'item', report = 'radio'}
end

function Item.create(m)
    m.place, m.itemType, m.itemLabel, m.itemName = '', '', '', ''
    m.found, m.foundBy = false, ''
    -- One item, collected at a dead drop; no hand-over in person (the notebook delivery finds nothing to accept).
    m.quantity, m.delivered, m.accepted = 1, 0, {}
end

-- Poll of a participant (server copy): placement of the item, then the item held by a participant.
function Item.observe(m, player, name, _state, store)
    local changed = false
    local rec = m.personal
    if type(rec) == 'table' and not rec.placed and Caches.place(store or M.store(), rec, Item.make) then
        m.itemId, changed = rec.itemId, true
    end
    if m.itemId ~= nil and not m.found and not player:isDead()
            and player:getInventory():getItemWithIDRecursiv(m.itemId) ~= nil then
        m.found, m.foundBy, changed = true, name or '', true
    end
    return changed
end

Item.dropAccepts = M.onlyItem('itemId')
Item.voiceReportReady = M.allCollected

-- Only the radio report ('speech', CA_Missions.spoken) once the item is collected; nothing taken from an inventory.
function Item.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Item.voiceReportReady(m) then return nil, 'Items' end
    return {report = true}
end
function Item.prepare() return {kind = 'voice_item_report'} end
function Item.apply() end
function Item.progress() return 0, true end
function Item.complete() end

function Item.project(m, p)
    p.template, p.place, p.report = 'item', m.place or '', 'radio'
    p.itemType, p.itemLabel = m.itemType or '', m.itemLabel or ''
    p.found, p.foundBy = m.found == true, m.foundBy or ''
    p.quantity, p.delivered = m.quantity, m.delivered
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Item.context(m, ctx)
    ctx.kind, ctx.place, ctx.report = 'item', m.place, 'radio'
    ctx.placed, ctx.found = type(m.personal) == 'table' and m.personal.placed == true, m.found == true
end

-- How the voice names the item: the sheet's label, else "the <display name of its script>".
local function named(m)
    if type(m.itemLabel) == 'string' and m.itemLabel ~= '' then return m.itemLabel end
    return 'the ' .. tostring(m.itemName or m.itemType)
end

-- E20-T02: the job told to the voice; only the item the server placed counts (verified yes/no only).
function Item.voiceBrief(m)
    return {job = 'Find ' .. named(m) .. ' at ' .. tostring(m.place) .. ', leave it at one of your drop points ('
        .. tostring(M.dropsWhere(m) or '') .. '), then report to you on this frequency after collection. Only that '
        .. 'very item counts; another one of the same kind is never taken.',
        facts = {'Item found by a participant (checked by the server): ' .. M.yesNo(m.found == true) .. '.',
            M.dropsRule(m),
            'Item collected at a drop point: ' .. M.yesNo(Item.voiceReportReady(m)) .. '.'}}
end

M.register('item', Item)

return Item
