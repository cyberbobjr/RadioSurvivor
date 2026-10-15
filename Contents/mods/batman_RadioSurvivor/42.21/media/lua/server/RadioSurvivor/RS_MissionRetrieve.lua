if isClient() then return end
--[[
Mission template `retrieve_id` (E11-T05): find the body of a missing person in a place chosen by the server and bring
their ID card back to the requester. Authority only. Catalogue: RS_Config.Missions.retrieve_id (offer id
retrieve_id_v1). Registered in RS_Missions (M.register); required by RS_Carnet_Server, whose once-a-second poll of the
participants (M.observe) also places the body. Details: docs/carnet-implementation-04221.md, "Gabarit retrouver";
design choices: docs/conception/mission-retrouver.md.

Requester: an NPC fiche of the notebook only (a radio voice does not offer it: RS_MissionVoice.TEMPLATES). Offered only
where the game can make a corpse (exposed class RandomizedWorldBase; a bench without it offers nothing).
Place: drawn exactly as the scout template (RS_MissionScout.pick: habitable building of the metagrid at 60-250 tiles
of the requester's body, 60 tiles at least from any known base, nothing loaded), kept per requester for siteTtlMs in
a memory of this file so that the offer told by the bridge and the created mission name the same building. The
mission keeps the site point (centre of the main room, m.spot) and the building bounds in the private state.
Map area: the same approximate circle as the scout template (RS_MissionScout.mapZone, m.mapZone, projected to an
engaged participant of an active mission only; client/RadioSurvivor/RS_MapActions.lua draws and removes it).
Deferred placement: the body is placed by the server poll of a participant (Retrieve.observe), at most every
placeRetryMs, once the site square is loaded (getCell():getGridSquare of the point itself, never a neighbour chunk)
and the building has passed its vanilla stories (BuildingDef:isFullyStreamedIn, or one of its rooms explored):
RandomizedWorldBase.createRandomDeadBody on the nearest free square of the same building (no stairs, isFree), else of
the building bounds at that level (random outfit, no crawler, never fake dead), sent to the clients by the game
(GameServer.sendCorpse). Then a new Base.IDcard named after the body (InventoryItem:nameAfterDescriptor, the vanilla
naming of a dead person's card) goes into the body's container (sendAddItemToContainer on a server). The mission
keeps m.cardId = InventoryItem:getID() (random at creation, saved with the item, kept by every MP transfer) and
m.person (name of the body); the body carries ModData RS_RetrieveMission = mission id. Placed once: m.placed is saved
with the private state at the next save (a crash in between may place a second body; its card is a different item).
Found: the poll marks m.found once a participant holds the card (server copy of the inventory, bags included).
Hand-over: the delivery exchange of the notebook (prepare_delivery / confirm_delivery, within DELIVERY_RANGE of the
requester's body, RS_Carnet_Server): the mission exposes quantity 1 and the accepted identity card types so that the
window lists every ID card of the player; Retrieve.check accepts only the item whose id is m.cardId, still in the
server inventory of the player (never its displayed name): any other card is refused ('WrongCard') before any
effect. The card is removed (write-ahead transaction of the engine), then success, reputation and common reward lot
by the engine (same values as M01). The bridge sees only the kind of place, clues without digits, whether the body
was placed or the card found, and the name of the dead person; never a coordinate, the zone nor the item id.
]]
local M = require 'RadioSurvivor/RS_Missions'
local Scout = require 'RadioSurvivor/RS_MissionScout'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Config = require 'RadioSurvivor/RS_Config'

local Retrieve = {idPrefix = 'retrieve'}
Retrieve.MARK = 'RS_RetrieveMission'
-- Requester fiche id -> {site = ..., at = ms} (memory only); mission id -> last placement attempt (ms).
local sites, tried = {}, {}

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function copyMap(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function copyClueData(list)
    local out = {}
    for _, c in ipairs(list or {}) do
        if type(c) == 'table' and type(c.key) == 'string' then out[#out + 1] = {key = c.key, args = copyList(c.args)} end
    end
    return out
end

-- The game can make a corpse here (exposed vanilla class); without it the template is never offered.
function Retrieve.available()
    return RandomizedWorldBase ~= nil
end

-- Place kept for this requester (drawn again after siteTtlMs, or retryMs when none fitted); nil when none fits.
function Retrieve.site(npc, body, c)
    local now = getTimestampMs()
    local entry = sites[npc.id]
    if entry and now - entry.at < (entry.site and c.siteTtlMs or c.retryMs) then return entry.site end
    local site, why = nil, 'no requester body'
    if body then
        site, why = Scout.pick(body:getX(), body:getY(), c, 'retrieve:' .. tostring(npc.id) .. ':'
            .. tostring(npc.missionCount or 0) .. ':' .. tostring(now))
    end
    if not site then Const.log('retrieve: no place for ' .. tostring(npc.id) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = now}
    return site
end

-- Bench: forget the kept places and the placement attempts.
function Retrieve.resetForTests()
    sites, tried = {}, {}
end

function Retrieve.offer(c, npc, record, body)
    -- A radio voice donor has no fiche (npc.incarnation): this template is for NPC fiches only.
    if not Retrieve.available() or not npc or (npc.incarnation == nil and not npc.voice) then return nil end
    local site = Retrieve.site(npc, body, c)
    if not site then return nil end
    return {kind = 'retrieve_id', item = 'ID card', place = site.label, clues = copyList(site.clues),
        report = 'in_person', durationMs = c.durationMs, rewardType = c.rewardType, rewardCount = c.rewardCount}
end

-- The place told in the offer; a requester without a kept place gives no mission.
function Retrieve.create(m, c, npc)
    local entry = npc and sites[npc.id]
    local site = entry and entry.site
    if not site then return false end
    sites[npc.id] = nil
    local b = site.bounds
    m.spot = {x = site.x, y = site.y, z = site.z}
    m.bounds = {x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2}
    m.siteKey, m.place, m.clues = site.key, site.label, copyList(site.clues)
    m.clueData = copyClueData(site.clueData)
    m.placeKind = site.kind
    m.placed, m.found, m.foundBy, m.person = false, false, '', ''
    -- Fields of the notebook delivery exchange: one piece, any identity card listed, the right one checked by id.
    m.quantity, m.delivered, m.accepted = 1, 0, copyMap(c.cards)
    m.mapZone = Scout.mapZone(b, c, tostring(m.id) .. ':' .. tostring(site.key))
end

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

-- Nearest free square of the site's building around the point (rings up to the bounds), else of the bounds.
local function bodySquare(cell, m, centre)
    local building = centre:getBuilding()
    local p, b = m.spot, m.bounds
    local reach = math.max(p.x - b.x1, b.x2 - 1 - p.x, p.y - b.y1, b.y2 - 1 - p.y, 0)
    local fallback
    for ring = 0, reach do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local x, y = p.x + dx, p.y + dy
                    if x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2 then
                        local sq = cell:getGridSquare(x, y, p.z)
                        if freeSquare(sq) then
                            if building == nil or sq:getBuilding() == building then return sq end
                            fallback = fallback or sq
                        end
                    end
                end
            end
        end
    end
    return fallback
end

-- Deferred placement of the body and its card (see the header). Returns true when placed now.
function Retrieve.place(m, c)
    if m.placed or type(m.spot) ~= 'table' or type(m.bounds) ~= 'table' then return false end
    local now = getTimestampMs()
    if tried[m.id] and now - tried[m.id] < c.placeRetryMs then return false end
    local cell = getCell()
    if not cell then return false end
    local centre = cell:getGridSquare(m.spot.x, m.spot.y, m.spot.z)
    if not centre or not buildingReady(centre) then return false end
    tried[m.id] = now
    local sq = bodySquare(cell, m, centre)
    if not sq then
        Const.log('retrieve: no free square for the body of ' .. tostring(m.id))
        return false
    end
    local card = instanceItem(c.cardType)
    if not card then
        Const.log('retrieve: unknown card item ' .. tostring(c.cardType))
        return false
    end
    local body = RandomizedWorldBase.createRandomDeadBody(sq, IsoDirections.getRandom(), c.blood, 0, nil)
    if not body then
        Const.log('retrieve: the game made no body for ' .. tostring(m.id))
        return false
    end
    -- createRandomDeadBody makes a fake dead body one time in 20 (RandomizedWorldBase.java:498-503).
    body:setFakeDead(false)
    body:getModData()[Retrieve.MARK] = m.id
    local desc = body:getDescriptor()
    if desc then
        card:nameAfterDescriptor(desc)
        m.person = tostring(desc:getForename()) .. ' ' .. tostring(desc:getSurname())
    end
    local container = body:getContainer()
    container:AddItem(card)
    sendAddItemToContainer(container, card)
    m.cardId, m.placed = card:getID(), true
    m.bodyAt = {x = sq:getX(), y = sq:getY(), z = sq:getZ()}
    tried[m.id] = nil
    Const.log('retrieve: body of ' .. tostring(m.id) .. ' placed with its card')
    return true
end

-- Polled by M.observe with the server copy of a participant: placement, then the card held by a participant.
function Retrieve.observe(m, player, name)
    local changed = Retrieve.place(m, Config.Missions.retrieve_id)
    if m.placed and not m.found and m.cardId and not player:isDead()
            and player:getInventory():getItemWithIDRecursiv(m.cardId) ~= nil then
        m.found, m.foundBy = true, name or ''
        changed = true
    end
    return changed
end

-- Only the card of this mission, by item id, still in the server inventory of the player.
function Retrieve.voiceReportReady(m) return m.found == true end

function Retrieve.check(m, player, ids)
    if m.donor == 'voice' and ids == 'speech' then ids = {m.cardId} end
    if type(ids) ~= 'table' or #ids ~= 1 or not m.cardId then return nil, 'WrongCard' end
    local id = ids[1]
    if id ~= m.cardId then return nil, 'WrongCard' end
    local item = player:getInventory():getItemWithIDRecursiv(id)
    if not item or item:getID() ~= m.cardId then return nil, 'WrongCard' end
    return {ids = {id}, item = item, type = item:getFullType()}
end

function Retrieve.prepare(m, e)
    return {kind = 'retrieve_card', ids = e.ids, types = {e.type}, before = m.delivered, count = 1}
end

function Retrieve.apply(m, e)
    local container = e.item:getContainer()
    local ok = pcall(function()
        container:Remove(e.item)
        sendRemoveItemFromContainer(container, e.item)
    end)
    if not ok then return 'inventory_remove' end
end

function Retrieve.progress(m)
    m.delivered = 1
    return 1, true
end

function Retrieve.complete() end

function Retrieve.project(m, p)
    p.template, p.placeKind, p.report = 'retrieve_id', m.placeKind or '', 'in_person'
    p.clues = copyClueData(m.clueData)
    p.person, p.found, p.foundBy = m.person or '', m.found == true, m.foundBy or ''
    -- Delivery window of the notebook: one piece among the identity cards (the server checks the item id).
    p.quantity, p.delivered, p.accepted = m.quantity, m.delivered, copyMap(m.accepted)
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Retrieve.context(m, ctx)
    ctx.kind, ctx.place, ctx.clues, ctx.report = 'retrieve_id', m.place, copyList(m.clues), 'in_person'
    ctx.item, ctx.placed, ctx.found = 'ID card', m.placed == true, m.found == true
    if m.person and m.person ~= '' then ctx.person = m.person end
end

M.register('retrieve_id', Retrieve)

return Retrieve
