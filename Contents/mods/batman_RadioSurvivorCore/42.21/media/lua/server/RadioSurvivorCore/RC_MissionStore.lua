if isClient() then return end
--[[
RadioSurvivorCore: private state of the common mission engine (E18-T05). Authority only.

Two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_RadioSurvivorCore/missions-<hex of "mode/world">-<0|1>.txt,
header RCMISSIONS1, data = { schema = 1, missions = { [id] = mission } }. Never in a global ModData.

    Store.init(newWorld)   -- reads the file
    Store.save()                   -- true when written and read back
    Store.data, Store.blocked

Storage blocked: a file exists but no slot can be read (or a newer schema): nothing is written, files kept.
]]
local SlotFile = require "RadioSurvivorCore/RC_SlotFile"

local Store = { data = nil, seq = 0, blocked = false, dirty = false, base = nil }
Store.DIR = "batman_RadioSurvivorCore/"
Store.HEADER = "RCMISSIONS1"
Store.SCHEMA = 1

local function log(msg)
    print("[RadioSurvivorCore] missions: " .. tostring(msg))
end

local function fresh()
    return { schema = Store.SCHEMA, missions = {} }
end

function Store.init(newWorld)
    Store.base = SlotFile.worldBase(Store.DIR, "missions")
    Store.blocked, Store.dirty = false, false
    local best, broken = SlotFile.read(Store.base, Store.HEADER)
    Store.seq = best and best.seq or 0
    if newWorld then
        Store.data = fresh()
    elseif best then
        local data = best.data
        if type(data.schema) ~= "number" or data.schema > Store.SCHEMA then
            Store.blocked, Store.data = true, nil
            log("STORAGE BLOCKED: mission state written by a newer schema; preserve files for recovery")
            return false
        end
        if type(data.missions) ~= "table" then data.missions = {} end
        Store.data = data
    elseif broken then
        Store.blocked, Store.data = true, nil
        log("STORAGE BLOCKED: both mission state slots invalid; preserve files for recovery")
        return false
    else
        Store.data = fresh()
    end
    if not Store.save() then return false end
    return true
end

-- Replaces the mission table kept in memory (the caller's state and this store share one table).
function Store.attach(missions)
    if Store.data and type(missions) == "table" then Store.data.missions = missions end
end

function Store.save()
    if Store.blocked or not Store.data then return false end
    local seq = Store.seq + 1
    local ok, why = SlotFile.write(Store.base, Store.HEADER, seq, Store.data)
    if not ok then
        Store.dirty = true
        log("STORAGE WRITE FAILED (" .. tostring(why) .. "); kept in memory, retried at the next save")
        return false
    end
    Store.seq, Store.dirty = seq, false
    return true
end

return Store
