if isClient() then return end
--[[
Mission template `clear` (E11-T04): kill N zombies inside a circle drawn around a place chosen by the server.
Authority only. Catalogue: RS_Config.Missions.clear (offer id clear_v1). Registered in RS_Missions (M.register);
required by RS_Carnet_Server. Details: docs/carnet-implementation-04221.md, "Gabarit nettoyer"; design choices:
docs/conception/mission-nettoyer.md.

Requester: an NPC fiche of the notebook only (a radio voice does not offer it: RS_MissionVoice.TEMPLATES).
Place: drawn exactly as the scout template (RS_MissionScout.pick: habitable building of the metagrid at 60-250 tiles
of the requester's body, 60 tiles at least from any known base, nothing loaded), kept per requester for siteTtlMs in
a memory of this file so that the offer told by the bridge and the created mission name the same building.
Zone: a circle centred on the building (m.mapZone = { x, y, r }, r = zoneRadius tiles, larger for a big building so
that the whole footprint lies inside), every floor. It is the counting zone itself, drawn on the map of an engaged
participant of an active mission (client/RadioSurvivor/RS_MapActions.lua, label IGUI_RS_MapZoneClear): unlike the
scout and retrieve_id areas it is not moved off the building, the player must know where a kill counts.
Target N: from the zombie density of the zone, read on the metagrid without loading anything
(IsoMetaGrid:getChunkDataFromTile(x, y):getUnadjustedZombieIntensity(), 0..255 of the lot headers, chunks of 8 x 8
tiles whose centre lies in the circle; IsoMetaChunk.java:66-136), as the game turns it into a population: uniform
distribution (sandbox Distribution = 2) reads 128, the result is multiplied by ZombieConfig.PopulationMultiplier;
sandbox Zombies = 6 (none) or a multiplier of 0 offers nothing. density = mean / 255 x multiplier;
N = minKills + (maxKills - minKills) x min(1, density / fullDensity), rounded, within [minKills, maxKills]; a density
below minDensity offers nothing (an empty countryside place would make an impossible mission). Kept in the offer.
Count (E04-T06 rule, same window as LivingKnox.Bodies.deathCause, without depending on Living Knox): OnHitZombie on
the authority records the last hit of a player on each zombie (wielder IsoPlayer, weapon, time), only while an active
clear mission exists; at OnZombieDead (authority only: the server decides the death, a client gets its own
OnZombieDead from the death packet and loads nothing of this file), the zombie counts only when
    - it is not an NPC body of the provider (RS_NPCProvider.id) nor a body tagged by Living Knox (ModData lkNpcId,
      any generation, read through LivingKnox.Identity.readTag when it is loaded);
    - it was not counted before (ModData RS_ClearCounted: a burning zombie fires OnZombieDead twice, a dragged corpse
      dies again when released, its ModData being copied);
    - getAttackedBy() is a player (not an animal) and either its last recorded hit on this zombie is at most
      HIT_WINDOW_MS old, or it drives a vehicle at that instant (vehicle hits have no OnHitZombie). Fire (attacker
      reset to nil at each burn, Molotov), timed traps without a thrower, falls and Kill(nil): never counted;
    - the killer is the server player bound to a notebook character (RS_CarnetServer.bound) who takes part in an
      active clear mission whose circle holds the zombie position at death (server copy of the zombie).
One kill counts for one mission only (the first of these missions by id). m.kills and m.tally[character] rise, the
revision too; at N the objective is met (E11-T13): the mission waits "to report" (Clear.reportReady, no more counting)
and succeeds only when a participant reports to the requester in person (RS_Missions.spoken: intent report_done of the
model on a notebook talk, or the notebook button "Report" near the requester); then reputation and common reward lot
as M01, claimed near the requester. The notebook state is marked dirty and published at once, saved at N.
The bridge sees the kind of place, clues without digits, N and the count; never a coordinate nor the circle.
]]
local M = require 'RadioSurvivor/RS_Missions'
local Scout = require 'RadioSurvivor/RS_MissionScout'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local P = require 'RadioSurvivor/RS_NPCProvider'
local S = require 'RadioSurvivor/RS_State'

local Clear = {idPrefix = 'clear', reportBySpeech = true} -- E11-T13: report in person
Clear.MARK = 'RS_ClearCounted'
Clear.HIT_WINDOW_MS = 5000   -- E04-T06: a kill is attributed only to a recent hit (LivingKnox.Bodies.HIT_WINDOW_MS)
local CHUNK = 8
local HITS_SWEEP = 200       -- recorded hits kept before the old ones are swept
-- Requester fiche id -> {site = ..., at = ms} (memory only); zombie object -> last hit of a player (memory only).
local sites, hits, hitCount = {}, {}, 0

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

local function metaGrid()
    local ok, grid = pcall(function() return getWorld():getMetaGrid() end)
    if ok then return grid end
    return nil
end

-- Zombie population settings of the sandbox: multiplier (nil: no zombie at all) and uniform distribution.
local function population()
    local sv = SandboxVars or {}
    if sv.Zombies == 6 then return nil end
    local cfg = type(sv.ZombieConfig) == 'table' and sv.ZombieConfig or {}
    local mult = tonumber(cfg.PopulationMultiplier) or 1
    if mult <= 0 then return nil end
    return mult, sv.Distribution == 2
end

-- Mean density of the circle (0..1 x multiplier) from the lot headers; nil when the metagrid cannot tell.
function Clear.density(grid, zone)
    local mult, uniform = population()
    if not mult then return 0 end
    local sum, n = 0, 0
    local x0 = math.floor((zone.x - zone.r) / CHUNK) * CHUNK
    local y0 = math.floor((zone.y - zone.r) / CHUNK) * CHUNK
    for y = y0, zone.y + zone.r, CHUNK do
        for x = x0, zone.x + zone.r, CHUNK do
            local cx, cy = x + CHUNK / 2, y + CHUNK / 2
            if (cx - zone.x) * (cx - zone.x) + (cy - zone.y) * (cy - zone.y) <= zone.r * zone.r then
                local ok, chunk = pcall(function() return grid:getChunkDataFromTile(x, y) end)
                if not ok then return nil end
                if chunk then
                    sum = sum + (uniform and 128 or chunk:getUnadjustedZombieIntensity())
                    n = n + 1
                end
            end
        end
    end
    if n == 0 then return nil end
    return sum / n / 255 * mult
end

-- Number of kills asked for a density (documented in the header).
function Clear.target(c, density)
    local share = math.min(1, math.max(0, density) / c.fullDensity)
    local n = math.floor(c.minKills + (c.maxKills - c.minKills) * share + 0.5)
    return math.max(c.minKills, math.min(c.maxKills, n))
end

-- Counting circle around the building bounds { x1, y1, x2, y2 } (x2, y2 exclusive): centre of the footprint, radius
-- zoneRadius or more so that every corner lies inside with zoneMargin tiles to spare.
function Clear.zone(bounds, c)
    local w, h = bounds.x2 - bounds.x1, bounds.y2 - bounds.y1
    local half = math.sqrt(w * w + h * h) / 2
    return {x = math.floor((bounds.x1 + bounds.x2) / 2), y = math.floor((bounds.y1 + bounds.y2) / 2),
        r = math.max(c.zoneRadius, math.ceil(half) + c.zoneMargin)}
end

-- Place kept for this requester (drawn again after siteTtlMs, or retryMs when none fitted); nil when none fits.
function Clear.site(npc, body, c)
    local now = getTimestampMs()
    local entry = sites[npc.id]
    if entry and now - entry.at < (entry.site and c.siteTtlMs or c.retryMs) then return entry.site end
    local site, why = nil, 'no requester body'
    local grid = metaGrid()
    if body and grid then
        site, why = Scout.pick(body:getX(), body:getY(), c, 'clear:' .. tostring(npc.id) .. ':'
            .. tostring(npc.missionCount or 0) .. ':' .. tostring(now))
        if site then
            site.zone = Clear.zone(site.bounds, c)
            local density = Clear.density(grid, site.zone)
            if density == nil then
                site, why = nil, 'no zombie density on the metagrid'
            elseif density < c.minDensity then
                site, why = nil, 'too few zombies around ' .. tostring(site.key)
            else
                site.density, site.kills = density, Clear.target(c, density)
            end
        end
    elseif body then
        why = 'no metagrid'
    end
    if not site then Const.log('clear: no place for ' .. tostring(npc.id) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = now}
    return site
end

-- Bench: forget the kept places and the recorded hits.
function Clear.resetForTests()
    sites, hits, hitCount = {}, {}, 0
end

function Clear.offer(c, npc, record, body)
    -- A radio voice donor has no fiche (npc.incarnation): this template is for NPC fiches only.
    if not npc or npc.incarnation == nil then return nil end
    local site = Clear.site(npc, body, c)
    if not site then return nil end
    return {kind = 'clear', place = site.label, clues = copyList(site.clues), kills = site.kills, report = 'in_person',
        durationMs = c.durationMs, rewardType = c.rewardType, rewardCount = c.rewardCount}
end

-- The place and the number told in the offer; a requester without a kept place gives no mission.
function Clear.create(m, c, npc)
    local entry = npc and sites[npc.id]
    local site = entry and entry.site
    if not site then return false end
    sites[npc.id] = nil
    local z = site.zone
    m.mapZone = {x = z.x, y = z.y, r = z.r}
    m.siteKey, m.place, m.clues = site.key, site.label, copyList(site.clues)
    m.clueData = copyClueData(site.clueData)
    m.placeKind = site.kind
    m.target, m.kills, m.tally = site.kills, 0, {}
    -- No delivery: the delivery commands of the notebook find nothing to accept (M.checkItems refuses every item).
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- ---------------------------------------------------------------- kills (E04-T06 rule)

local function isPlayer(o)
    return o ~= nil and instanceof(o, 'IsoPlayer') and not instanceof(o, 'IsoAnimal')
end

local function openMissions(state)
    local out = {}
    for _, m in pairs(state and state.missions or {}) do
        -- E11-T13: a mission whose target is reached counts no more (it waits for its report).
        if m.template == 'clear' and m.state == 'active' and not m.transaction and not Clear.reportReady(m) then
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Last hit of a player on a zombie (also called by the in-game suite). Old entries are swept past HITS_SWEEP.
function Clear.noteHit(z, wielder, weapon)
    if z == nil or not isPlayer(wielder) then return end
    local now = getTimestampMs()
    if not hits[z] then hitCount = hitCount + 1 end
    hits[z] = {player = wielder, weapon = weapon and weapon:getFullType() or nil, ms = now}
    if hitCount > HITS_SWEEP then
        local kept, n = {}, 0
        for zombie, hit in pairs(hits) do
            if now - hit.ms <= Clear.HIT_WINDOW_MS then kept[zombie], n = hit, n + 1 end
        end
        hits, hitCount = kept, n
    end
end

-- Body of an NPC (provider id, or a Living Knox tag of any generation): never a zombie to clear.
local function npcBody(z, md)
    if P.id(z) ~= nil then return true end
    local I = LivingKnox and LivingKnox.Identity
    return md ~= nil and I ~= nil and I.readTag ~= nil and I.readTag(md) ~= nil
end

-- Recorded hit of z, removed from the memory.
local function takeHit(z)
    local hit = hits[z]
    if hit then hits[z], hitCount = nil, hitCount - 1 end
    return hit
end

-- Attributed killer of z (IsoPlayer) at its death, or nil. Consumes the recorded hit.
function Clear.killer(z)
    local hit = takeHit(z)
    local k = z:getAttackedBy()
    if not isPlayer(k) then return nil end
    if hit and rawequal(hit.player, k) and getTimestampMs() - hit.ms <= Clear.HIT_WINDOW_MS then return k end
    local vehicle = k:getVehicle()
    if vehicle ~= nil and rawequal(vehicle:getDriver(), k) then return k end
    return nil
end

local function inside(m, x, y)
    local z = m.mapZone
    return type(z) == 'table' and (x - z.x) * (x - z.x) + (y - z.y) * (y - z.y) <= z.r * z.r
end

-- Counts the death of z for state (missions table): resolve(player) -> notebook character or nil. Returns the
-- mission credited, or nil. Sets the ModData mark of z once credited (no second count of the same zombie).
function Clear.count(state, z, resolve)
    local open = openMissions(state)
    if #open == 0 or z == nil then return nil end
    local md = z:hasModData() and z:getModData() or nil
    if (md and md[Clear.MARK]) or npcBody(z, md) then takeHit(z); return nil end
    local k = Clear.killer(z)
    local character = k and resolve(k)
    if not character then return nil end
    local x, y = z:getX(), z:getY()
    for _, m in ipairs(open) do
        if m.participants[character] and inside(m, x, y) then
            z:getModData()[Clear.MARK] = m.id
            m.kills = (m.kills or 0) + 1
            m.tally = m.tally or {}
            m.tally[character] = (m.tally[character] or 0) + 1
            m.revision = m.revision + 1
            return m
        end
    end
    return nil
end

-- Notebook character of a server player (RS_Carnet_Server binding), or nil.
local function bound(player)
    local server = RS_CarnetServer
    return server and server.bound and server.bound[player] or nil
end

function Clear.onHitZombie(z, wielder, bodyPart, weapon)
    if #openMissions(S.data) > 0 then Clear.noteHit(z, wielder, weapon) end
end

function Clear.onZombieDead(z)
    if not S.data or S.blocked then return end
    local m = Clear.count(S.data, z, bound)
    if not m then return end
    S.dirty = true
    if Clear.reportReady(m) then S.save() end -- E11-T13: objective met, saved at once
    if RS_CarnetServer and RS_CarnetServer.publish then RS_CarnetServer.publish() end
end

-- ---------------------------------------------------------------- engine interface

-- E11-T13: objective met = target reached; the report to the requester is then expected.
function Clear.reportReady(m)
    return (m.kills or 0) >= (m.target or 1)
end

-- Kills are counted by the events above, never by a contribution of the player; the only contribution is the report
-- to the requester (payload 'speech', RS_Missions.spoken), once the target is reached.
function Clear.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Clear.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Clear.prepare() return {kind = 'clear'} end
function Clear.apply() end
function Clear.progress(m) return m.kills or 0, (m.kills or 0) >= (m.target or 1) end
function Clear.complete() end

-- Shared count and the part of each participant (names only), the circle for a participant of an active mission.
function Clear.project(m, p)
    p.template, p.placeKind, p.report = 'clear', m.placeKind or '', 'in_person'
    p.clues = copyClueData(m.clueData)
    p.kills, p.target = m.kills or 0, m.target or 0
    p.tally = {}
    for character, n in pairs(m.tally or {}) do
        local member = m.participants[character]
        p.tally[#p.tally + 1] = {name = member and member.name or '?', count = n}
    end
    table.sort(p.tally, function(a, b) return a.name < b.name end)
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Clear.context(m, ctx)
    ctx.kind, ctx.place, ctx.clues, ctx.report = 'clear', m.place, copyList(m.clues), 'in_person'
    ctx.kills, ctx.target = m.kills or 0, m.target or 0
end

M.register('clear', Clear)
Events.OnHitZombie.Add(Clear.onHitZombie)
Events.OnZombieDead.Add(Clear.onZombieDead)

return Clear
