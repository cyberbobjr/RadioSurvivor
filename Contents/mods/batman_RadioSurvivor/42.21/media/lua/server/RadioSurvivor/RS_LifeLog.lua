if isClient() then return end
--[[
Life log of a notebook character (E15-T01), material of its last pages (E15-T03). Authority only (dedicated server or
solo). Design notes: docs/annexes/conception/releve-de-vie.md.

    local LifeLog = require "RadioSurvivor/RS_LifeLog"
    LifeLog.get(cid)              -- log of this character (live or frozen), or nil
    LifeLog.frozen()              -- ids of the frozen logs (dead characters), oldest death first
    LifeLog.release(cid)          -- drops a frozen log once its last pages are written (E15-T03)
    LifeLog.rescue(cid, outcome, label)   -- rescue done ('saved') or missed ('missed') by a living character (E12)
    LifeLog.onFrozen = function(cid, log, character) end   -- optional single listener, called at the death

Identity: only a character of the notebook (E00-T01: RS_CarnetServer.bound[player] -> id of
S.data.characters, same owner, not retired) has a log. A player without an identity has none, and nothing is read
from a client: every value comes from the server copy of the player (IsoPlayer) or from the private state.
Storage: private state of the notebook (RS_State: S.data.lifelogs = { seq, logs = { [cid] = log } }), saved with it,
never in global ModData nor in the player's ModData (readable by clients).

Poll (every POLL_MS of real time, OnTickEvenPaused), for every bound and living player:
  kills       IsoPlayer:getZombieKills() (counted by the server, saved with the player)
  hours       IsoPlayer:getHoursSurvived() (advanced by GameTime on the server for every connected player)
  profession  SurvivorDesc:getCharacterProfession():getName(), path of the registry id such as "doctor" (same
              call as the vanilla stats window; never a translated name: getText gives raw keys on an MP server)
  towns       vanilla towns of RS_Rescue.TOWNS whose centre is within TOWN_FACTOR * radius of the server position
              (same "in <town>" rule as the rescue clues), only when the vanilla map is loaded
              (getLotDirectories); first visit only, in visit order, no coordinate kept
  phrases     the MAX_PHRASES last lines said by this character on the radio (RS_RadioLog kind "said"): text and
              game time only, never the frequency (secret frequencies never reach the bridge prompt)
  missions    missions of the engine (S.data.missions) closed with this character as a participant: template,
              result, requester name, kind of place; noted once per mission id
Rescues are pushed by E12 through LifeLog.rescue (no rescue outcome exists before E12-T04/T05).

Death (own OnCharacterDeath subscription, players only): one last poll, the missions still open listed as "open"
(never as accomplished), then the log is FROZEN (dead = true, death time) and kept for E15-T03, which reads it, writes
the last pages and calls LifeLog.release. Frozen logs are bounded (MAX_FROZEN, the oldest death dropped). The
character is found by the notebook binding, the server modData identity, or the binding seen at the last poll: the
order of the OnCharacterDeath subscribers does not matter (RS_Carnet_Server.characterDeath clears the binding, the
modData identity and the radio history of the dead character; the phrases already copied stay in the log).
A live log whose character is gone or retired without a freeze (death missed) is dropped at the next poll.

Bounds: MAX_TOWNS towns, MAX_PHRASES phrases of RS_RadioLog.MAX_TEXT characters, MAX_MISSIONS closed missions,
MAX_OPEN missions open at the death and MAX_RESCUES rescues (oldest dropped, totals kept as counters), labels of
MAX_LABEL characters: one log stays under MAX_BYTES bytes of the RSV2 encoding. The set `noted` (ids of the closed
missions already noted) only holds ids still present in S.data.missions (engine retention, RS_Missions.prune) and is
emptied at the freeze. ASCII only in this file (Kahlua lexer).

Sandbox option RadioSurvivor.LastPages (E15-T04, on by default, Const.lastPages, read at every pass): off = no log at
all. The poll samples nothing and drops every log already kept (live or frozen), a death freezes nothing (no onFrozen,
so no last pages). Turned on again: logs start afresh at the next poll.
]]
local S = require "RadioSurvivor/RS_State"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Rescue = require "RadioSurvivor/RS_Rescue"
local RadioLog = require "RadioSurvivor/RS_RadioLog"

local L = {}
L.POLL_MS = 15000
L.TOWN_FACTOR = 0.5
L.MAX_TOWNS = 12
L.MAX_PHRASES = 8
L.MAX_MISSIONS = 12
L.MAX_RESCUES = 8
L.MAX_OPEN = 4
L.MAX_FROZEN = 8
L.MAX_LABEL = 80
L.MAX_BYTES = 12288
L.RESCUE_OUTCOMES = { saved = true, missed = true }

-- Same key as RS_Carnet_Server (server copy of the player's modData, written by the server only).
local IDENTITY_KEY = "RS_CarnetCharacter"

local pollAt = 0
local seen = {}          -- player -> character id at the last poll
local vanillaMap = nil   -- nil: not checked yet in this session

function L.resetForTests()
    pollAt, seen, vanillaMap = 0, {}, nil
end

local function store()
    if not S.data or S.blocked then return nil end
    local s = S.data.lifelogs
    if type(s) ~= "table" then
        s = { seq = 0, logs = {} }
        S.data.lifelogs = s
    end
    return s
end

local function ownerOf(player)
    return isServer() and player:getUsername() or "solo"
end

local function clean(text, limit)
    if type(text) ~= "string" then return "" end
    text = Const.oneLine(string.gsub(text, "[%c<>%[%]]", " "))
    if string.len(text) > limit then text = Const.oneLine(string.sub(text, 1, limit)) end
    return text
end

-- Bound character of a living player, or nil.
local function boundCharacter(player)
    local server = RS_CarnetServer
    local cid = server and server.bound and server.bound[player]
    local record = type(cid) == "string" and S.data.characters[cid] or nil
    if not record or record.retired or record.owner ~= ownerOf(player) then return nil end
    return cid, record
end

local function newLog(cid, record)
    return { cid = cid, name = clean(record.name, L.MAX_LABEL), dead = false, started = RadioLog.when(),
        kills = 0, hours = 0, profession = "", towns = {}, phrases = {}, phraseSeq = 0, missions = {}, noted = {},
        rescues = {}, totals = { success = 0, failed = 0, cancelled = 0, saved = 0, missed = 0 } }
end

local function push(list, entry, max)
    list[#list + 1] = entry
    while #list > max do table.remove(list, 1) end
end

local function vanillaLoaded()
    if vanillaMap == nil then
        vanillaMap = false
        local dirs = type(getLotDirectories) == "function" and getLotDirectories() or nil
        if dirs then
            for i = 0, dirs:size() - 1 do
                if dirs:get(i) == Rescue.CONFIG.VANILLA_MAP then vanillaMap = true end
            end
        end
    end
    return vanillaMap
end

-- Vanilla town whose centre is within TOWN_FACTOR * radius of (x, y), or nil.
function L.townAt(x, y)
    if not vanillaLoaded() then return nil end
    for _, town in ipairs(Rescue.TOWNS) do
        local dx, dy = town.x - x, town.y - y
        if math.sqrt(dx * dx + dy * dy) <= town.r * L.TOWN_FACTOR then return town.name end
    end
    return nil
end

local function sampleTown(log, player)
    local name = L.townAt(player:getX(), player:getY())
    if not name then return false end
    for _, t in ipairs(log.towns) do
        if t.name == name then return false end
    end
    push(log.towns, { name = name, when = RadioLog.when(), hours = log.hours }, L.MAX_TOWNS)
    return true
end

-- Last lines said by this character on the radio (RS_RadioLog), most recent last.
local function samplePhrases(log, record)
    local radio = record and record.radio
    if type(radio) ~= "table" or type(radio.frequencies) ~= "table" then return false end
    local said = {}
    for _, f in ipairs(radio.frequencies) do
        for _, line in ipairs(f.lines or {}) do
            if line.kind == "said" and type(line.seq) == "number" then said[#said + 1] = line end
        end
    end
    table.sort(said, function(a, b) return a.seq < b.seq end)
    local last = said[#said]
    if not last or last.seq == log.phraseSeq then return false end
    local phrases = {}
    for i = math.max(1, #said - L.MAX_PHRASES + 1), #said do
        phrases[#phrases + 1] = { text = clean(said[i].text, RadioLog.MAX_TEXT), when = tostring(said[i].when or "") }
    end
    log.phrases, log.phraseSeq = phrases, last.seq
    return true
end

local function requesterOf(m)
    if type(m.requesterName) == "string" then return clean(m.requesterName, L.MAX_LABEL) end
    local npc = S.data.npcs and S.data.npcs[m.npc]
    return npc and clean(npc.name, L.MAX_LABEL) or ""
end

local function missionEntry(m, result, log)
    return { template = tostring(m.template or "deliver"), result = result, requester = requesterOf(m),
        place = clean(m.placeKind, L.MAX_LABEL), when = RadioLog.when(), hours = log.hours }
end

local function isOpen(m)
    return m.state == "offer" or m.state == "active"
end

-- Closed missions of this character, noted once each; ids of pruned missions forgotten (they never come back).
local function sampleMissions(log, cid)
    local changed = false
    local missions = S.data.missions or {}
    for id, m in pairs(missions) do
        if type(m) == "table" and type(m.participants) == "table" and m.participants[cid] and not isOpen(m)
                and not log.noted[id] then
            log.noted[id] = true
            local result = tostring(m.state)
            push(log.missions, missionEntry(m, result, log), L.MAX_MISSIONS)
            if result == "success" then log.totals.success = log.totals.success + 1
            elseif result == "failed" then log.totals.failed = log.totals.failed + 1
            else log.totals.cancelled = log.totals.cancelled + 1 end
            changed = true
        end
    end
    for id in pairs(log.noted) do
        if not missions[id] then log.noted[id] = nil end
    end
    return changed
end

local function sample(log, cid, player, record)
    local changed = false
    local kills = math.floor(tonumber(player:getZombieKills()) or 0)
    if kills ~= log.kills then log.kills, changed = kills, true end
    local hours = tonumber(player:getHoursSurvived()) or 0
    if math.floor(hours) ~= math.floor(log.hours) then changed = true end
    log.hours = math.floor(hours * 10) / 10
    local d = player:getDescriptor()
    local prof = d and d:getCharacterProfession()
    local profession = prof and clean(prof:getName(), L.MAX_LABEL) or ""
    if profession ~= log.profession then log.profession, changed = profession, true end
    changed = sampleTown(log, player) or changed
    changed = samplePhrases(log, record) or changed
    changed = sampleMissions(log, cid) or changed
    return changed
end

local function prune(s)
    local frozen = {}
    for cid, log in pairs(s.logs) do
        local record = S.data.characters[cid]
        if log.dead then frozen[#frozen + 1] = log
        elseif not record or record.retired then s.logs[cid] = nil end
    end
    table.sort(frozen, function(a, b) return (a.deathSeq or 0) < (b.deathSeq or 0) end)
    for i = 1, #frozen - L.MAX_FROZEN do s.logs[frozen[i].cid] = nil end
end

-- Option RadioSurvivor.LastPages off: every log dropped (see the header).
local function dropAll(s)
    seen = {}
    local n = 0
    for cid in pairs(s.logs) do
        s.logs[cid] = nil
        n = n + 1
    end
    if n > 0 then
        S.dirty = true
        Const.log("lifelog: option LastPages off, " .. n .. " log(s) dropped")
    end
    return false
end

function L.poll()
    local s = store()
    if not s then return false end
    if not Const.lastPages() then return dropAll(s) end
    local changed = false
    local present = {}
    local server = RS_CarnetServer
    for player, _ in pairs(server and server.bound or {}) do
        local cid, record = boundCharacter(player)
        if cid and not player:isDead() then
            present[player] = true
            seen[player] = cid
            local log = s.logs[cid]
            if not log then
                log = newLog(cid, record)
                s.logs[cid] = log
                changed = true
            end
            if not log.dead then changed = sample(log, cid, player, record) or changed end
        end
    end
    for player in pairs(seen) do
        if not present[player] then seen[player] = nil end
    end
    prune(s)
    if changed then S.dirty = true end
    return changed
end

function L.tick()
    local now = getTimestampMs()
    if now < pollAt then return end
    pollAt = now + L.POLL_MS
    L.poll()
end

-- OnCharacterDeath: freezes the log of a dead notebook character (see the header).
function L.characterDeath(character)
    local s = store()
    if not s or not instanceof(character, "IsoPlayer") then return end
    local server = RS_CarnetServer
    local cid = (server and server.bound and server.bound[character]) or character:getModData()[IDENTITY_KEY]
        or seen[character]
    seen[character] = nil
    if not Const.lastPages() then return end
    local log = type(cid) == "string" and s.logs[cid] or nil
    local record = log and S.data.characters[cid]
    if not log or log.dead or not record or record.owner ~= ownerOf(character) then return end
    sample(log, cid, character, record)
    local openAtDeath = {}
    for _, m in pairs(S.data.missions or {}) do
        if type(m) == "table" and type(m.participants) == "table" and m.participants[cid] and m.state == "active" then
            push(openAtDeath, missionEntry(m, "open", log), L.MAX_OPEN)
        end
    end
    s.seq = (tonumber(s.seq) or 0) + 1
    log.dead, log.deathSeq, log.deathWhen, log.open, log.noted = true, s.seq, RadioLog.when(), openAtDeath, {}
    prune(s)
    S.dirty = true
    S.save()
    Const.log("lifelog: frozen " .. cid .. " (" .. log.kills .. " kills, " .. #log.towns .. " towns)")
    if L.onFrozen then L.onFrozen(cid, log, character) end
end

-- Rescue outcome of a living character (E12-T04/T05). Returns true when noted.
function L.rescue(cid, outcome, label)
    local s = store()
    local log = s and type(cid) == "string" and s.logs[cid] or nil
    if not log or log.dead or not L.RESCUE_OUTCOMES[outcome] or not Const.lastPages() then return false end
    push(log.rescues, { outcome = outcome, label = clean(label, L.MAX_LABEL), when = RadioLog.when(),
        hours = log.hours }, L.MAX_RESCUES)
    log.totals[outcome] = log.totals[outcome] + 1
    S.dirty = true
    return true
end

function L.get(cid)
    local s = store()
    return s and type(cid) == "string" and s.logs[cid] or nil
end

function L.frozen()
    local s = store()
    local list = {}
    for cid, log in pairs(s and s.logs or {}) do
        if log.dead then list[#list + 1] = { cid = cid, seq = log.deathSeq or 0 } end
    end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.cid end
    return out
end

function L.release(cid)
    local s = store()
    local log = s and type(cid) == "string" and s.logs[cid] or nil
    if not log or not log.dead then return false end
    s.logs[cid] = nil
    S.dirty = true
    return true
end

Events.OnTickEvenPaused.Add(L.tick)
Events.OnCharacterDeath.Add(L.characterDeath)

return L
