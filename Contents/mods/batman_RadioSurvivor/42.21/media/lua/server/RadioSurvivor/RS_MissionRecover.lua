if isClient() then return end
--[[
Mission template `recover` (E11-T06): pick up a cache (marked bag) left in a place chosen by the server and carry it
to the depot of the requester's group. Authority only. Catalogue: RS_Config.Missions.recover (offer id recover_v1).
Registered in RS_Missions (M.register); required by RS_Carnet_Server, whose once-a-second poll of the participants
(M.observe) also places the cache (RS_Caches) and checks the depot. Details:
docs/annexes/conception/carnet-implementation-04221.md, "Caches et gabarit recuperer"; design choices:
docs/annexes/conception/mission-recuperer.md.

Requester: an NPC fiche of the notebook only (a radio voice has no depot: RS_MissionVoice.TEMPLATES stays scout),
whose provider tells where its group lives (RS_NPCProvider.presence(id).x, y; Living Knox: home of the group). An NPC
without a known home offers nothing.
Place: drawn exactly as the scout template (RS_MissionScout.pick: habitable building of the metagrid at 60-250 tiles
of the requester's body, 60 tiles at least from any known base, nothing loaded), with the cache table drawn from the
closed list RS_Config.Caches.order (same seed), kept per requester for siteTtlMs in a memory of this file so that the
offer told by the bridge and the created mission name the same building and the same contents.
Cache: m.cache (RS_Caches.attach, one per mission) at the centre of the main room (m.spot) inside the building bounds
(m.bounds), placed once when the site is loaded (RS_Caches.place: marked bag on the floor, once even after a restart).
Map: the same approximate circle as the scout template around the building (m.mapZone), and the depot circle
(m.depot = { x, y, z, r }: home point, r = depotRadius), both projected to an engaged participant of an active mission
only (p.mapZone, p.depotZone; client/RadioSurvivor/RS_MapActions.lua draws and removes them).
Found: the poll marks m.found once a participant holds the bag (server copy of the inventory, bags included, by item
id m.cache.itemId).
Depot: the poll (at most once a second per mission, depot square loaded) looks for the bag by its item id lying on
the floor of a square of the depot area (square of side 2r + 1 around the home point, same floor), or inside a
container of an object there (getItemWithIDRecursiv: in a crate, a shelf, another bag). Any other bag, even of the
same type and contents, is not the cache. Found there: the bag is taken out of the world (it now belongs to the
group: transmitRemoveItemFromSquare, or container Remove + sendRemoveItemFromContainer) and the objective is met
(E11-T13): the mission waits "to report" (Recover.reportReady, no more depot scan) and succeeds only when a
participant reports to the requester in person (RS_Missions.spoken: intent report_done of the model on a notebook
talk, or the notebook button "Report" near the requester); then reputation and common reward lot by the engine (same
values as M01, claimed near the requester). The contents are not checked (decision to confirm). No delivery by the
notebook buttons (no Deliver).
The bridge sees the kind of place, clues without digits, the kind of cache (table name), whether the cache was placed
or found; never a coordinate, the area, the depot nor the item id.
]]
local M = require 'RadioSurvivor/RS_Missions'
local Scout = require 'RadioSurvivor/RS_MissionScout'
local Caches = require 'RadioSurvivor/RS_Caches'
local Rescue = require 'RadioSurvivor/RS_Rescue'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local P = require 'RadioSurvivor/RS_NPCProvider'
local S = require 'RadioSurvivor/RS_State'

local Recover = {idPrefix = 'recover', reportBySpeech = true} -- E11-T13: report in person
-- Requester fiche id -> {site = ..., at = ms} (memory only); mission id -> last depot scan (ms).
local sites, scanned = {}, {}
local SCAN_MS = 900

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function copyClueData(list)
    local out = {}
    for _, c in ipairs(list or {}) do
        if type(c) == 'table' and type(c.key) == 'string' then out[#out + 1] = {key = c.key, args = copyList(c.args)} end
    end
    return out
end

function Recover.resetForTests()
    sites, scanned = {}, {}
end

-- Home point of the requester's group ({ x, y, z } integer tiles), or nil when the provider cannot tell.
function Recover.home(npc)
    local presence = npc and npc.incarnation ~= nil and P.presence(npc.incarnation) or nil
    if type(presence) ~= 'table' or type(presence.x) ~= 'number' or type(presence.y) ~= 'number' then return nil end
    return {x = math.floor(presence.x), y = math.floor(presence.y), z = math.floor(tonumber(presence.z) or 0)}
end

-- Place and cache table kept for this requester (drawn again after siteTtlMs, or retryMs when none fitted).
function Recover.site(npc, body, c)
    local now = getTimestampMs()
    local entry = sites[npc.id]
    if entry and now - entry.at < (entry.site and c.siteTtlMs or c.retryMs) then return entry.site end
    local site, why = nil, 'no requester body'
    if body then
        local seed = 'recover:' .. tostring(npc.id) .. ':' .. tostring(npc.missionCount or 0) .. ':' .. tostring(now)
        site, why = Scout.pick(body:getX(), body:getY(), c, seed)
        if site then site.cacheTable = Caches.drawTable(Rescue.drawer(seed .. ':table')) end
    end
    if not site then Const.log('recover: no place for ' .. tostring(npc.id) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = now}
    return site
end

function Recover.offer(c, npc, record, body)
    -- A radio voice donor has no fiche (npc.incarnation); an NPC without a known home has no depot.
    if not npc or npc.incarnation == nil or not Recover.home(npc) then return nil end
    local site = Recover.site(npc, body, c)
    if not site then return nil end
    return {kind = 'recover', item = 'bag', cache = site.cacheTable, place = site.label, clues = copyList(site.clues),
        report = 'in_person', durationMs = c.durationMs, rewardType = c.rewardType, rewardCount = c.rewardCount}
end

-- The place and the cache told in the offer, the depot read again now; otherwise no mission.
function Recover.create(m, c, npc)
    local entry = npc and sites[npc.id]
    local site = entry and entry.site
    local home = Recover.home(npc)
    if not site or not home then return false end
    sites[npc.id] = nil
    local b = site.bounds
    m.spot = {x = site.x, y = site.y, z = site.z}
    m.bounds = {x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2}
    m.siteKey, m.place, m.clues = site.key, site.label, copyList(site.clues)
    m.clueData = copyClueData(site.clueData)
    m.placeKind = site.kind
    m.found, m.foundBy, m.deposited = false, '', false
    m.depot = {x = home.x, y = home.y, z = home.z, r = c.depotRadius}
    -- No delivery window: the notebook delivery commands find nothing to accept.
    m.quantity, m.delivered, m.accepted = 0, 0, {}
    if not Caches.attach(m, site.cacheTable, m.spot, m.bounds) then return false end
    m.mapZone = Scout.mapZone(b, c, tostring(m.id) .. ':' .. tostring(site.key))
end

-- The cache bag by item id in the depot area: (square, world object) on the floor, or (container, item) inside a
-- container of an object of the area. nil when absent or the depot square is not loaded.
function Recover.atDepot(m, cell)
    local d, id = m.depot, m.cache and m.cache.itemId
    if type(d) ~= 'table' or not id or not cell:getGridSquare(d.x, d.y, d.z) then return nil end
    for x = d.x - d.r, d.x + d.r do
        for y = d.y - d.r, d.y + d.r do
            local sq = cell:getGridSquare(x, y, d.z)
            if sq then
                local floor = sq:getWorldObjects()
                for i = 0, floor:size() - 1 do
                    local wo = floor:get(i)
                    local item = wo:getItem()
                    if item and item:getID() == id then return 'floor', sq, wo end
                end
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    for k = 0, o:getContainerCount() - 1 do
                        local item = o:getContainerByIndex(k):getItemWithIDRecursiv(id)
                        if item then return 'container', item:getContainer(), item end
                    end
                end
            end
        end
    end
    return nil
end

-- The bag delivered to the group: taken out of the world. Returns true when removed.
local function takeOut(kind, where, what)
    local ok = pcall(function()
        if kind == 'floor' then
            where:transmitRemoveItemFromSquare(what)
        else
            where:Remove(what)
            sendRemoveItemFromContainer(where, what)
        end
    end)
    return ok
end

-- Polled by M.observe with the server copy of a participant: placement of the cache, bag held by a participant, bag
-- left at the depot (objective met, E11-T13: the report is then expected; nothing more is polled).
function Recover.observe(m, player, name, state, store)
    if m.state ~= 'active' or m.deposited then return false end
    local changed = Caches.place(store or S, m.cache)
    local id = m.cache and m.cache.placed and m.cache.itemId
    if id and not m.found and not player:isDead() and player:getInventory():getItemWithIDRecursiv(id) ~= nil then
        m.found, m.foundBy = true, name or ''
        changed = true
    end
    local now = getTimestampMs()
    if not id or (scanned[m.id] and now - scanned[m.id] < SCAN_MS) then return changed end
    scanned[m.id] = now
    local cell = getCell()
    local kind, where, what = nil, nil, nil
    if cell then kind, where, what = Recover.atDepot(m, cell) end
    if not kind then return changed end
    if not takeOut(kind, where, what) then
        Const.log('recover: the bag of ' .. tostring(m.id) .. ' could not be taken out of the depot')
        return changed
    end
    m.deposited, m.delivered = true, 1
    scanned[m.id] = nil
    Const.log('recover: bag of ' .. tostring(m.id) .. ' left at the depot (' .. kind .. '), report expected')
    return true
end

-- E11-T13: objective met = bag left at the depot; the report to the requester is then expected.
function Recover.reportReady(m)
    return m.deposited == true
end

-- The bag is checked by the depot poll, never by a contribution of the player; the only contribution is the report
-- to the requester (payload 'speech', RS_Missions.spoken), once the bag is at the depot.
function Recover.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Recover.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Recover.prepare() return {kind = 'recover'} end
function Recover.apply() end
function Recover.progress(m) return m.delivered or 0, m.deposited == true end
function Recover.complete() end

function Recover.project(m, p)
    p.template, p.placeKind, p.report = 'recover', m.placeKind or '', 'in_person'
    p.clues = copyClueData(m.clueData)
    p.cache = m.cache and m.cache.table or ''
    p.placed = m.cache ~= nil and m.cache.placed == true
    p.found, p.foundBy, p.deposited = m.found == true, m.foundBy or '', m.deposited == true
    if m.state == 'active' and p.engaged then
        local z, d = m.mapZone, m.depot
        if type(z) == 'table' then p.mapZone = {x = z.x, y = z.y, r = z.r} end
        if type(d) == 'table' then p.depotZone = {x = d.x, y = d.y, r = d.r} end
    end
end

function Recover.context(m, ctx)
    ctx.kind, ctx.place, ctx.clues, ctx.report = 'recover', m.place, copyList(m.clues), 'in_person'
    ctx.item, ctx.cache = 'bag', m.cache and m.cache.table or nil
    ctx.placed = m.cache ~= nil and m.cache.placed == true
    ctx.found = m.found == true
end

M.register('recover', Recover)

return Recover
