if isClient() then return end
--[[
Mission template `signal` (E11-T07): light a signal of the asked colour inside a circle drawn around a place chosen by
the server, within a window of game hours. Authority only. Catalogue: RS_Config.Missions.signal (offer id signal_v1).
Registered in RS_Missions (M.register); required by RS_Carnet_Server. Design choices: docs/annexes/conception/mission-signaler.md.

Required mod Signal Smoke (mod.info require=\batman_SignalSmoke): its public module require('SignalSmoke/SignalSmoke')
returns a table with onSignal and COLORS. Its shared file is run at boot, before any server file, so the require is
resolved whatever the mod order. A module that is missing or lacks onSignal / COLORS is a broken install: an error
line is written to the log and the template is not offered.
Listener: SignalSmoke.onSignal (authority only: server or solo), subscribed once per session by Signal.install at
load (a Signal.resetForTests never subscribes it again to the same module). The event "started" carries the
registry entry decided by the server (x, y, z, colour { r, g, b }, kind, source) and
event.player (IsoPlayer at the origin, when known: thrown grenade, lit flare, chemlight dropped near a player) or
event.username. The colour name is found back by comparing the entry colour to SignalSmoke.COLORS.
Requester: an NPC fiche of the notebook only (a radio voice does not offer it: RS_MissionVoice.TEMPLATES).
Place: drawn as the scout template (RS_MissionScout.pick: habitable building at 60-250 tiles of the requester's body,
60 tiles at least from any known base, nothing loaded), kept per requester for siteTtlMs in a memory of this file so
that the offer told by the bridge and the created mission name the same building, colour and hour.
Zone: a circle centred on the building (m.mapZone = { x, y, r }, like the clear template: the signal must be lit
inside it), every floor, drawn on the map of an engaged participant of an active mission (client
RS_MapActions.lua, label IGUI_RS_MapZoneSignal) and removed once the mission is closed.
Colour: drawn among c.colors that Signal Smoke knows. Hour: start of a window of c.windowHours game hours, drawn
between leadHours and leadHours + spreadHours after the game hour of the draw, valid on any day while the mission
is active (the delay stays the M01 real-time rule).
Success: the first "started" signal whose player is a participant of an active signal mission (notebook character
bound on the server, RS_CarnetServer.bound), whose colour is the asked one, whose position lies in the circle and
whose game hour (GameTime:getHour at the event) is inside the window meets the objective (m.lit, E11-T13): the
mission waits "to report" (Signal.reportReady, no other signal judged) and succeeds only when a participant reports
to the requester in person (RS_Missions.spoken: intent report_done of the model on a notebook talk, or the notebook
button "Report" near the requester); then reputation and common reward lot as M01, claimed near the requester. Any
other signal changes nothing. The bridge sees the kind of place, clues without digits, colour, hour and window; never
a coordinate.
]]
local M = require 'RadioSurvivor/RS_Missions'
local Scout = require 'RadioSurvivor/RS_MissionScout'
local Clear = require 'RadioSurvivor/RS_MissionClear'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Rescue = require 'RadioSurvivor/RS_Rescue'
local S = require 'RadioSurvivor/RS_State'

local Signal = {idPrefix = 'signal', reportBySpeech = true} -- E11-T13: report in person
local COLOR_TOLERANCE = 0.02
-- Requester fiche id -> {site = ..., at = ms} (memory only); Signal Smoke module (false: unusable).
local sites = {}
local lib = nil
-- Signal Smoke modules the listener is subscribed to (module table -> true), for the whole session: never cleared by
-- Signal.resetForTests, so a reset followed by installs never subscribes twice to the same module (E11-T14).
local subscribedTo = {}

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

-- Signal Smoke public module (required mod), or nil when it is unusable (broken install: error logged). Checked once;
-- Signal.resetForTests forgets it.
function Signal.library()
    if lib == nil then
        local mod = require 'SignalSmoke/SignalSmoke'
        if type(mod) == 'table' and type(mod.onSignal) == 'function' and type(mod.COLORS) == 'table' then
            lib = mod
        else
            lib = false
            Const.log('ERROR signal: required mod batman_SignalSmoke is broken: module SignalSmoke/SignalSmoke '
                .. 'has no onSignal or COLORS (template signal disabled)')
        end
    end
    return lib or nil
end

-- Subscribes the listener once to Signal Smoke. Returns true when subscribed.
function Signal.install()
    local mod = Signal.library()
    if not mod then return false end
    if not subscribedTo[mod] then
        mod.onSignal(Signal.onSignal)
        subscribedTo[mod] = true
    end
    return true
end

-- Bench: forget the kept places and the detection. The subscriptions are kept: the listener stays subscribed once
-- per module for the session.
function Signal.resetForTests()
    sites, lib = {}, nil
end

-- Colours of the catalogue that Signal Smoke knows (catalogue order).
local function colors(c, mod)
    local out = {}
    for _, name in ipairs(c.colors or {}) do
        if type(mod.COLORS[name]) == 'table' then out[#out + 1] = name end
    end
    return out
end

-- Hour of day 0..23 of the game clock.
local function gameHour()
    local ok, h = pcall(function() return getGameTime():getHour() end)
    if ok and type(h) == 'number' then return math.floor(h) % 24 end
    return nil
end

-- Is game hour h inside the window starting at `hour` for `window` hours (across midnight too)?
function Signal.inWindow(hour, window, h)
    if type(hour) ~= 'number' or type(window) ~= 'number' or type(h) ~= 'number' then return false end
    -- Both in 0..23: the sum stays positive (Kahlua's % truncates toward zero for a negative operand).
    return (h - hour + 24) % 24 < window
end

-- Place, colour and hour kept for this requester (drawn again after siteTtlMs, or retryMs when none fitted).
function Signal.site(npc, body, c, mod)
    local now = getTimestampMs()
    local entry = sites[npc.id]
    if entry and now - entry.at < (entry.site and c.siteTtlMs or c.retryMs) then return entry.site end
    local seed = 'signal:' .. tostring(npc.id) .. ':' .. tostring(npc.missionCount or 0) .. ':' .. tostring(now)
    local site, why = nil, 'no requester body'
    local names, hour = colors(c, mod), gameHour()
    if #names == 0 then
        why = 'no colour known by Signal Smoke'
    elseif hour == nil then
        why = 'no game clock'
    elseif body then
        site, why = Scout.pick(body:getX(), body:getY(), c, seed)
        if site then
            local draw = Rescue.drawer(seed .. ':terms')
            site.zone = Clear.zone(site.bounds, c)
            site.color = names[draw(#names) + 1]
            site.hour = (hour + c.leadHours + draw(c.spreadHours + 1)) % 24
        end
    end
    if not site then Const.log('signal: no place for ' .. tostring(npc.id) .. ' (' .. tostring(why) .. ')') end
    sites[npc.id] = {site = site, at = now}
    return site
end

function Signal.offer(c, npc, record, body)
    -- A radio voice donor has no fiche (npc.incarnation): this template is for NPC fiches only.
    if not npc or (npc.incarnation == nil and not npc.voice) then return nil end
    local mod = Signal.library()
    if not mod then return nil end
    Signal.install()
    local site = Signal.site(npc, body, c, mod)
    if not site then return nil end
    return {kind = 'signal', place = site.label, clues = copyList(site.clues), color = site.color, hour = site.hour,
        windowHours = c.windowHours, report = 'in_person', durationMs = c.durationMs, rewardType = c.rewardType,
        rewardCount = c.rewardCount}
end

-- The place, colour and hour told in the offer; a requester without a kept place gives no mission.
function Signal.create(m, c, npc)
    local entry = npc and sites[npc.id]
    local site = entry and entry.site
    if not site then return false end
    sites[npc.id] = nil
    local z = site.zone
    m.mapZone = {x = z.x, y = z.y, r = z.r}
    m.siteKey, m.place, m.clues = site.key, site.label, copyList(site.clues)
    m.clueData = copyClueData(site.clueData)
    m.placeKind = site.kind
    m.color, m.hour, m.windowHours = site.color, site.hour, c.windowHours
    m.lit, m.litBy = false, ''
    -- No delivery: the delivery commands of the notebook find nothing to accept (M.checkItems refuses every item).
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- ---------------------------------------------------------------- signals of Signal Smoke

-- Name of a Signal Smoke colour { r, g, b }, or nil.
function Signal.colorName(mod, color)
    if type(color) ~= 'table' or not mod then return nil end
    for name, ref in pairs(mod.COLORS) do
        if type(ref) == 'table' and type(color.r) == 'number' and type(color.g) == 'number'
                and type(color.b) == 'number' and math.abs(color.r - ref.r) <= COLOR_TOLERANCE
                and math.abs(color.g - ref.g) <= COLOR_TOLERANCE and math.abs(color.b - ref.b) <= COLOR_TOLERANCE then
            return name
        end
    end
    return nil
end

local function openMissions(state)
    local out = {}
    for _, m in pairs(state and state.missions or {}) do
        -- E11-T13: a mission whose signal was seen judges no other one (it waits for its report).
        if m.template == 'signal' and m.state == 'active' and not m.transaction and not m.lit then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function inside(m, x, y)
    local z = m.mapZone
    return type(z) == 'table' and type(x) == 'number' and type(y) == 'number'
        and (x - z.x) * (x - z.x) + (y - z.y) * (y - z.y) <= z.r * z.r
end

-- Notebook character of a Signal Smoke event (its player, else its account among the bound players), or nil.
local function characterOf(event, resolve, players)
    local p = event.player
    if p ~= nil and instanceof(p, 'IsoPlayer') then return resolve(p), p end
    if type(event.username) ~= 'string' or not players then return nil end
    for player in pairs(players) do
        if player:getUsername() == event.username then return resolve(player), player end
    end
    return nil
end

-- Judges a Signal Smoke event for state (missions table): resolve(player) -> notebook character or nil; players: set
-- of bound server players (username fallback), or nil. Returns the mission whose objective is now met, or nil.
function Signal.count(state, event, resolve, players, hour)
    if type(event) ~= 'table' or event.type ~= 'started' or type(event.entry) ~= 'table' then return nil end
    local open = openMissions(state)
    if #open == 0 then return nil end
    local character = characterOf(event, resolve, players)
    if not character then return nil end
    local e = event.entry
    local color = Signal.colorName(Signal.library(), e.color)
    hour = hour or gameHour()
    for _, m in ipairs(open) do
        local member = m.participants[character]
        if member and color == m.color and inside(m, e.x, e.y) and Signal.inWindow(m.hour, m.windowHours, hour) then
            m.lit, m.litBy = true, member.name or ''
            m.revision = m.revision + 1
            Const.log('signal: ' .. tostring(m.id) .. ' seen (' .. tostring(color) .. ' ' .. tostring(e.kind)
                .. '), report expected')
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

function Signal.onSignal(event)
    if not S.data or S.blocked then return end
    local server = RS_CarnetServer
    local m = Signal.count(S.data, event, bound, server and server.bound or nil)
    if not m then return end
    S.dirty = true
    S.save()
    if server and server.publish then server.publish() end
end

-- ---------------------------------------------------------------- engine interface

-- E11-T13: objective met = signal seen; the report to the requester is then expected.
function Signal.reportReady(m)
    return m.lit == true
end

-- The signal is judged by the listener above, never by a contribution of the player; the only contribution is the
-- report to the requester (payload 'speech', RS_Missions.spoken), once the signal was seen.
function Signal.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Signal.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Signal.prepare() return {kind = 'signal'} end
function Signal.apply() end
function Signal.progress(m) return m.lit and 1 or 0, m.lit == true end
function Signal.complete() end

function Signal.project(m, p)
    p.template, p.placeKind, p.report = 'signal', m.placeKind or '', 'in_person'
    p.clues = copyClueData(m.clueData)
    p.color, p.hour, p.windowHours = m.color or '', m.hour or 0, m.windowHours or 0
    p.lit, p.litBy = m.lit == true, m.litBy or ''
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Signal.context(m, ctx)
    ctx.kind, ctx.place, ctx.clues, ctx.report = 'signal', m.place, copyList(m.clues), 'in_person'
    ctx.color, ctx.hour, ctx.windowHours, ctx.lit = m.color, m.hour, m.windowHours, m.lit == true
end

M.register('signal', Signal)
Signal.install()

return Signal
