if isClient() then return end
--[[
Mission template `scout` (E11-T03): reach a place chosen by the server, then report to the requester in person.
Authority only. Catalogue: CA_MissionConfig.Missions.scout. Registered in CA_Missions (M.register); required by
RS_Carnet_Server, which polls the zones (M.observe) and turns a phrase said to the requester into the report
(M.spoken). Details: docs/annexes/conception/carnet-implementation-04221.md, "Gabarit reconnaitre".

Place: a habitable building of the metagrid (CA_Sites.check: no player-built building, no basement-only one, no
water, inside the map), between minDistance and maxDistance tiles of the requester's body, and at least minDistance
tiles away from every known base (vanilla safehouses, connected players: CA_Sites.knownBases). Only the cells around
the requester are read (IsoMetaCell:getBuildingsIntersecting); no square is read or loaded. The place is drawn when
an offer is computed and kept in memory per requester for siteTtlMs (a restart draws again), so that the offer told
by the bridge and the created mission name the same building.
Zone: the footprint of the building (BuildingDef bounds, exclusive ends) widened by `margin` tiles, every floor.
Presence: polled by the server on the server copy of each connected participant (IsoPlayer:getX/getY of the server
player; never a position sent by a client). The first living participant inside marks the mission zoneReached
(saved with the private state, RS_State; never in global ModData).
Report (E11-T13): once the zone is reached (Scout.reportReady), the mission waits "to report"; a participant reports
to the requester in person (admitted notebook `talk` within SELECT_RANGE of the body whose reply carries intent
report_done, chosen by the model and checked again by the server, or the notebook button "Report" near the
requester); the mission succeeds then, never before. A report before the visit is nothing. Delay, reputation,
collective result and reward lot: the common engine (same values as M01).
Radio voice requester (E11-T08, RS_MissionVoice.lua): the same template, drawn around the caller's server position
(the "body" given to Scout.site), m.report = 'radio'; the report is announced to the voice on its frequency (action
report_mission of its reply, E11-T13).
Aimed place (E20-T10): an offer that receives `aim` (a place { x, y, z, label } named by the giver: target= of a
voice's mission section) draws nothing; Scout.siteAt takes the building whose room covers that tile on the metagrid
(IsoMetaGrid:getBuildingAt(x, y, z), loaded or not: IsoMetaGrid.java:271-280), wherever the requester stands and
without the habitability or distance rules of a draw (the giver chose it), labelled with the place's label; no
building there: no offer. Kept per requester like a drawn place, so that create names the same building.
The bridge sees the place only as clues without digits (CA_Sites.clues) and its kind; the coordinates stay here.
Notebook (E11-T09): the same clues as translatable data (CA_Sites.clueData: m.clueData = list of { key, args } with
codes and town names only, never a coordinate), projected as p.clues and rendered by the client in its own language
(IGUI_RS_Clue_<key>); no translated text is composed on the server.
Map area (E11-T10): at creation (any requester: NPC fiche or radio voice), Scout.mapZone draws a circle of about one
block (radius c.mapZoneRadius, 30 tiles; larger for a building whose half diagonal leaves too little room) that holds
the whole building footprint, its centre moved away from the building centre by a random offset (between half and all
the room left: radius - half diagonal - 1 tile), direction and length drawn by CA_Sites.drawer from the mission id and
the place key (same draw for the same mission). Kept as m.mapZone = { x, y, r } (integer tiles) in the private state.
The client gets it only in the notebook projection (p.mapZone) of a participant of an active mission, never the
building bounds nor m.zone; it draws the area on the player's world map and removes it once the mission is no longer
active (client/RadioSurvivor/RS_MapActions.lua, MapActions.zones). Missions created before E11-T10 have no area.
]]
local M = require 'CoreAI/CA_Missions'
local Sites = require 'CoreAI/CA_Sites'
local function log(msg)
    print('[CoreAI] ' .. tostring(msg))
end

local Scout = {idPrefix = 'scout', reportBySpeech = true, voiceName = 'scout',
    voiceText = 'visit a building and report on it'}
local CELL = 256
-- Requester fiche id -> {site = ..., at = ms} or {at = ms} when no place was found (memory only).
local sites = {}

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

-- Optional: a world without a metagrid (early boot, bench) simply offers no scout mission.
local function metaGrid()
    local ok, grid = pcall(function() return getWorld():getMetaGrid() end)
    if ok then return grid end
    return nil
end

-- Clues of RS_Rescue speak of a shelter; a scouting target is only a place. Returns the English clues (bridge) and
-- their translatable data (notebook, E11-T09), same order.
local function clues(b, grid)
    local out = {}
    local lines, data = Sites.clueData(b, grid)
    for i, line in ipairs(lines) do
        out[i] = (string.gsub(line, '^The shelter is ', 'The place is '))
    end
    return out, data
end

-- Copy of the clue data (plain values only).
local function copyClueData(list)
    local out = {}
    for _, c in ipairs(list or {}) do
        if type(c) == 'table' and type(c.key) == 'string' then out[#out + 1] = {key = c.key, args = copyList(c.args)} end
    end
    return out
end

-- Buildings of the metagrid crossing the square of half side r around (x, y), cell by cell.
local function buildingsAround(grid, x, y, r)
    local x1, y1 = math.max(0, math.floor(x - r)), math.max(0, math.floor(y - r))
    local x2, y2 = math.floor(x + r) + 1, math.floor(y + r) + 1
    local found = ArrayList.new()
    for cy = math.floor(y1 / CELL), math.floor((y2 - 1) / CELL) do
        for cx = math.floor(x1 / CELL), math.floor((x2 - 1) / CELL) do
            local cell = grid:getCellData(cx, cy)
            if cell then cell:getBuildingsIntersecting(x1, y1, x2 - x1, y2 - y1, found) end
        end
    end
    return found
end

-- Draws a place around (x, y): site table (plain values only) or nil and a reason.
function Scout.pick(x, y, c, seed)
    local grid = metaGrid()
    if grid == nil then return nil, 'no metagrid' end
    local found = buildingsAround(grid, x, y, c.maxDistance)
    local n = found:size()
    if n == 0 then return nil, 'no building around the requester' end
    local here = {x1 = math.floor(x), y1 = math.floor(y), x2 = math.floor(x) + 1, y2 = math.floor(y) + 1}
    local bases = Sites.knownBases({avoid = {{x = x, y = y, source = 'requester'}}})
    -- Random start, then consecutive buildings: each one examined at most once, maxAttempts at most.
    local start = Sites.drawer(seed)(n)
    for i = 0, math.min(c.maxAttempts, n) - 1 do
        local b = found:get((start + i) % n)
        local site = Sites.check(b, bases, {minDistance = c.minDistance}, grid)
        if site and Sites.gap(site.bounds, here) <= c.maxDistance then
            site.clues, site.clueData = clues(b, grid)
            return site
        end
    end
    return nil, 'no suitable building around the requester'
end

-- E20-T10: site of the building at a place named by the giver ({ x, y, z, label }), or nil and a reason. Same
-- fields as a drawn site; kind from CA_Sites.KINDS (else 'building'), label = the place's label.
function Scout.siteAt(place)
    local grid = metaGrid()
    if grid == nil then return nil, 'no metagrid' end
    local b = grid:getBuildingAt(place.x, place.y, place.z or 0)
    if b == nil then return nil, 'no building at the place' end
    local rule = Sites.classify(b)
    local id = b:getIDString()
    local site = {x = place.x, y = place.y, z = place.z or 0, buildingId = id, key = 'b' .. tostring(id),
        kind = rule and rule.kind or 'building', label = tostring(place.label or ''), bounds = Sites.bounds(b)}
    site.clues, site.clueData = clues(b, grid)
    return site
end

-- E20-T10: the site at the aimed place, kept for this requester as a drawn one; nil when no building stands there.
function Scout.aimedSite(npc, place)
    local site, why = Scout.siteAt(place)
    if not site then log('scout: no building at ' .. tostring(place.label) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = getTimestampMs()}
    return site
end

-- Place kept for this requester (drawn again after siteTtlMs); nil when none fits.
function Scout.site(npc, body, c)
    local now = getTimestampMs()
    local entry = sites[npc.id]
    if entry and now - entry.at < (entry.site and c.siteTtlMs or c.retryMs) then return entry.site end
    local site, why = nil, 'no requester body'
    if body then
        site, why = Scout.pick(body:getX(), body:getY(), c, tostring(npc.id) .. ':' .. tostring(npc.missionCount or 0)
            .. ':' .. tostring(now))
    end
    if not site then log('scout: no place for ' .. tostring(npc.id) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = now}
    return site
end

-- Bench: forget the kept places.
function Scout.resetForTests()
    sites = {}
end

-- aim (E20-T10): place named by the giver, or nil (drawn around the body).
function Scout.offer(c, npc, record, body, character, aim)
    local site
    if aim then site = Scout.aimedSite(npc, aim) else site = Scout.site(npc, body, c) end
    if not site then return nil end
    return {kind = 'scout', place = site.label, clues = copyList(site.clues), report = 'in_person',
        durationMs = c.durationMs, rewardType = c.rewardType, rewardCount = c.rewardCount}
end

-- E11-T10: approximate area { x, y, r } (integer tiles) around bounds { x1, y1, x2, y2 } (x2, y2 exclusive): every
-- point of the footprint lies within r of (x, y), and (x, y) is never the building centre (offset >= half the room
-- left, at least about 5 tiles). Same seed, same area.
function Scout.mapZone(bounds, c, seed)
    local w, h = bounds.x2 - bounds.x1, bounds.y2 - bounds.y1
    local half = math.sqrt(w * w + h * h) / 2
    local r = math.max(c.mapZoneRadius or 30, math.ceil((half + 1) / 0.6))
    -- Integer rounding of the centre moves it by less than 1 tile: keep that tile out of the room.
    local room = r - half - 1
    local draw = Sites.drawer(seed)
    local d = room * (500 + draw(501)) / 1000
    local a = draw(360) * math.pi / 180
    local x = math.floor((bounds.x1 + bounds.x2) / 2 + d * math.cos(a) + 0.5)
    local y = math.floor((bounds.y1 + bounds.y2) / 2 + d * math.sin(a) + 0.5)
    return {x = x, y = y, r = r}
end

-- The place told in the offer; a requester without a kept place gives no mission.
function Scout.create(m, c, npc)
    local entry = npc and sites[npc.id]
    local site = entry and entry.site
    if not site then return false end
    sites[npc.id] = nil
    local b, r = site.bounds, c.margin
    m.zone = {x1 = b.x1 - r, y1 = b.y1 - r, x2 = b.x2 + r, y2 = b.y2 + r}
    m.siteKey, m.place, m.clues = site.key, site.label, copyList(site.clues)
    m.clueData = copyClueData(site.clueData) -- E11-T09: clues shown by the notebook, translated by the client
    m.placeKind = site.kind -- CA_Sites.KINDS kind (house, church...), translated by the notebook
    m.zoneReached, m.reachedBy = false, ''
    m.mapZone = Scout.mapZone(b, c, tostring(m.id) .. ':' .. tostring(site.key)) -- E11-T10
end

function Scout.inside(m, x, y)
    local z = m.zone
    return type(x) == 'number' and type(y) == 'number' and x >= z.x1 and x < z.x2 and y >= z.y1 and y < z.y2
end

-- Polled by M.observe with the server copy of a participant.
function Scout.observe(m, player, name)
    if m.zoneReached or not m.zone or player:isDead() or not Scout.inside(m, player:getX(), player:getY()) then
        return false
    end
    m.zoneReached, m.reachedBy, m.reachedAt = true, name or '', getTimestampMs()
    return true
end

-- E11-T13: objective met = zone visited (server poll); the report is then expected.
function Scout.reportReady(m)
    return m.zoneReached == true
end

-- Only a report to the requester (payload 'speech', M.spoken) is a contribution, and only after the visit.
function Scout.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not m.zoneReached then return nil, 'Zone' end
    return {kind = 'report'}
end

function Scout.prepare()
    return {kind = 'scout_report'}
end

function Scout.apply() end

function Scout.progress()
    return 1, true
end

function Scout.complete() end

-- report: 'in_person' (NPC requester, E11-T03) or 'radio' (radio voice requester, E11-T08, set at creation).
function Scout.project(m, p)
    p.template, p.zoneReached, p.reachedBy = 'scout', m.zoneReached == true, m.reachedBy or ''
    p.placeKind, p.report = m.placeKind or '', m.report or 'in_person'
    p.clues = copyClueData(m.clueData) -- E11-T09: keys and codes only (a mission saved before has none)
    -- E11-T10: the approximate area, only for a participant (p.engaged, set by M.projection) of an active mission.
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Scout.context(m, ctx)
    ctx.kind, ctx.place, ctx.clues, ctx.zoneReached, ctx.report = 'scout', m.place, copyList(m.clues),
        m.zoneReached == true, m.report or 'in_person'
end

-- E20-T02: the job told to a radio voice (kind of building, never its position).
function Scout.voiceBrief(m)
    return {job = 'Go and look at a building (kind: ' .. tostring(m.place) .. '), then call you back on this '
        .. 'frequency to report.',
        facts = {'The caller has been to the place (checked by the server): ' .. M.yesNo(m.zoneReached == true) .. '.'}}
end

M.register('scout', Scout)

return Scout
