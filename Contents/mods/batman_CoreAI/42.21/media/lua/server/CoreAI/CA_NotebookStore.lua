if isClient() then return end
--[[
CoreAI: private state of the notebook (E21-T04, design carnet-commun-e21.md, "Configuration et stocks"). Authority
only.

Two slot files written in turn (CA_SlotFile): Zomboid/Lua/batman_CoreAI/notebook-<hex of "mode/world">-<0|1>.txt,
header CANOTEBOOK1, data = { schema = 1, world, uidCounter, characters, npcs, bindings }. Never in a global ModData.
In memory, data.missions is the mission table of CA_MissionStore and each contact's history the table of CA_History:
both are written in their own files of the core mod, never in this one.

    Store.init(newWorld)       reads the three files of the core mod, then the companion states; true when ready
    Store.save()               missions, then histories, then this file, then the companion states
    Store.needsSave()          a change waits for the save (this state or a companion)
    Store.uid(prefix)          unique id counted in the state ("<prefix>-<ms>-<n>-<random>")
    Store.addCompanion(c)      state of a mod saved and loaded with the notebook:
                               c = { init = fn(newWorld) -> ok, save = fn() -> ok, dirty = fn() -> bool }
    Store.onPurge(fn)          fn(cid) -> true while the mod still needs the record of a dead character (C17 purge,
                               CA_NotebookPurge)
    Store.data, Store.run, Store.blocked, Store.dirty, Store.failures

- Storage blocked (a file of the core mod exists but no slot can be read, a newer schema, or a companion state
  unreadable): nothing is written, the files are kept for recovery. Only Store.init clears it.
- Failed write (C19): not blocked. The state stays in memory with Store.dirty, the next save writes it again (the other
  slot keeps the last good file), Store.failures counts the streak.
- Over the codec bounds (C18): the purge of dead characters is forced once, then the save is refused: never a file the
  decoder refuses.
- C17: one bounded purge pass of dead characters per game day, from the save.
]]
local Codec = require 'CoreAI/CA_Codec'
local SlotFile = require 'CoreAI/CA_SlotFile'
local MissionStore = require 'CoreAI/CA_MissionStore'
local History = require 'CoreAI/CA_History'
local Purge = require 'CoreAI/CA_NotebookPurge'

local Store = {data = nil, seq = 0, blocked = false, dirty = false, failures = 0, companions = {}, keepers = {}}
Store.DIR = 'batman_CoreAI/'
Store.HEADER = 'CANOTEBOOK1'
Store.SCHEMA = 1
Store.WARN_RATIO = 0.7   -- console warning when the state reaches 70 % of a codec bound

local function log(msg)
    print('[CoreAI] notebook: ' .. tostring(msg))
end

function Store.uid(prefix)
    Store.uidCounter = (Store.uidCounter or 0) + 1
    if Store.data then Store.data.uidCounter = (Store.data.uidCounter or 0) + 1 end
    local counter = Store.data and Store.data.uidCounter or Store.uidCounter
    return prefix .. '-' .. string.format('%.0f', getTimestampMs()) .. '-' .. counter .. '-' .. ZombRand(100000, 999999)
end

function Store.addCompanion(companion)
    for _, known in ipairs(Store.companions) do if known == companion then return end end
    Store.companions[#Store.companions + 1] = companion
    -- Registered after the start (Lua reload, late require): loaded at once with the same world start.
    if Store.data and not Store.blocked and not companion.init(Store.newWorld == true) then
        Store.blocked = true
        log('STORAGE BLOCKED: state of a mod using the notebook unreadable; preserve files for recovery')
    end
end

function Store.onPurge(fn)
    for _, known in ipairs(Store.keepers) do if known == fn then return end end
    Store.keepers[#Store.keepers + 1] = fn
end

local function block(reason)
    Store.blocked, Store.data = true, nil
    log('STORAGE BLOCKED: ' .. reason .. '; preserve files for recovery')
    return false
end

local function fresh()
    Store.data = nil
    return {schema = Store.SCHEMA, world = Store.uid('world'), characters = {}, npcs = {}, bindings = {}}
end

local function loaded(data)
    if type(data.schema) ~= 'number' or data.schema > Store.SCHEMA then return nil, 'notebook state written by a newer schema' end
    if type(data.world) ~= 'string' then return nil, 'notebook state without a world' end
    for _, key in ipairs({'characters', 'npcs', 'bindings'}) do
        if type(data[key]) ~= 'table' then data[key] = {} end
    end
    return data
end

function Store.init(newWorld)
    Store.base = SlotFile.worldBase(Store.DIR, 'notebook')
    Store.newWorld = newWorld == true
    Store.blocked, Store.dirty, Store.failures, Store.warned = false, false, 0, false
    local best, broken = SlotFile.read(Store.base, Store.HEADER)
    Store.seq = best and best.seq or 0
    local data
    if newWorld then
        data = fresh()
    elseif best then
        local why
        data, why = loaded(best.data)
        if not data then return block(why) end
    elseif broken then
        return block('both notebook state slots invalid')
    else
        data = fresh()
    end
    if not MissionStore.init(newWorld) then return block('mission state of the core mod unreadable') end
    data.missions = MissionStore.data.missions
    if not History.init(newWorld) then return block('exchange history of the core mod unreadable') end
    for c, record in pairs(data.characters) do
        for id, k in pairs(type(record) == 'table' and type(record.contacts) == 'table' and record.contacts or {}) do
            if type(k) == 'table' then k.history = History.lines(c, id) end
        end
    end
    Store.data = data
    for _, companion in ipairs(Store.companions) do
        if not companion.init(Store.newWorld) then return block('state of a mod using the notebook unreadable') end
    end
    Store.run = Store.uid('run')
    return Store.save()
end

local function failed(reason)
    Store.failures = (Store.failures or 0) + 1
    Store.dirty = true
    -- First failure of a streak, then every 20th: the save is retried by the next Store.save (tick, command, OnSave).
    if Store.failures == 1 or Store.failures % 20 == 0 then
        log('STORAGE WRITE FAILED (' .. reason .. '), attempt ' .. Store.failures
            .. '; state kept in memory, retried at the next save')
    end
    return false
end

-- The notebook file never holds the missions (CA_MissionStore) nor the exchange histories (CA_History): encoded
-- without them, put back right after.
local function encodeState()
    local data = Store.data
    local missions = data.missions
    data.missions = nil
    local histories = {}
    for _, record in pairs(data.characters) do
        for _, k in pairs(type(record) == 'table' and type(record.contacts) == 'table' and record.contacts or {}) do
            if type(k) == 'table' and k.history ~= nil then
                histories[#histories + 1] = {k, k.history}
                k.history = nil
            end
        end
    end
    local ok, body = pcall(Codec.encodeBytes, data)
    data.missions = missions
    for _, h in ipairs(histories) do h[1].history = h[2] end
    return ok, body
end

local function encode()
    local ok, body = encodeState()
    if ok then return body end
    -- Over the codec bounds: forced purge of the dead characters once, then refused.
    local okP, changed = pcall(Purge.run, Store.data, nil, true, Store.keepers)
    if okP and changed then
        ok, body = encodeState()
        if ok then
            log('state reduced to fit the serialization bounds')
            return body
        end
    end
    return nil, tostring(body)
end

local function warnSize(body)
    local ratio = math.max(#body / Codec.MAX_BYTES, (Codec.lastNodes or 0) / Codec.MAX_NODES)
    if ratio >= Store.WARN_RATIO and not Store.warned then
        Store.warned = true
        log(string.format('WARNING: notebook state at %d %% of its size limit (%d bytes, %d nodes)',
            math.floor(ratio * 100), #body, Codec.lastNodes or 0))
    elseif ratio < Store.WARN_RATIO * 0.9 then
        Store.warned = false
    end
end

-- C17: one bounded pass per game day, from the save (no event subscription of its own).
local function maintenance()
    local day = Purge.today()
    if type(day) ~= 'number' or day == Store.purgedDay then return end
    Store.purgedDay = day
    pcall(Purge.run, Store.data, day, false, Store.keepers)
end

-- The core history keeps only the contacts the notebook still holds (dropped contact or character).
local function keepContact(c, id)
    local record = Store.data.characters[c]
    return type(record) == 'table' and type(record.contacts) == 'table' and record.contacts[id] ~= nil
end

local function keepCharacter(c) return Store.data.characters[c] ~= nil end

function Store.save()
    if Store.blocked or not Store.data then return false end
    maintenance()
    local body, why = encode()
    if not body then return failed('state exceeds serialization bounds: ' .. tostring(why)) end
    MissionStore.attach(Store.data.missions)
    if not MissionStore.save() then return failed('mission state of the core mod not written') end
    History.retain(keepContact)
    History.retainRadio(keepCharacter)
    if not History.save() then return failed('exchange history of the core mod not written') end
    warnSize(body)
    local seq = Store.seq + 1
    local ok, err = SlotFile.writeBody(Store.base, Store.HEADER, seq, body)
    if not ok then return failed(tostring(err)) end
    Store.seq = seq
    for _, companion in ipairs(Store.companions) do
        if not companion.save() then return failed('state of a mod using the notebook not written') end
    end
    if Store.failures > 0 then log('storage write recovered after ' .. Store.failures .. ' failed attempt(s)') end
    Store.dirty, Store.failures = false, 0
    return true
end

function Store.needsSave()
    if Store.dirty then return true end
    for _, companion in ipairs(Store.companions) do
        if companion.dirty() then return true end
    end
    return false
end

return Store
