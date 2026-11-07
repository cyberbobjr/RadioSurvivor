if isClient() then return end
--[[
RadioSurvivorCore: exchange history kept by the core mod (E18-T11, user decision of 2026-11-05). Authority only.

Lines per character and per interlocutor (an NPC id of the notebook, "lk:lk-1"), oldest first, each a plain table
{ id, author, text } written by the mod that holds the conversation; at most MAX lines are kept by append (same bound
as RadioSurvivor's MAX_HISTORY). Read by the notebook for its display and by the speech of the NPCs as memory.

Two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_RadioSurvivorCore/history-<hex of "mode/world">-
<0|1>.txt, header RCHISTORY1, data = { schema = 1, characters = { [character] = { [peer] = { lines } } } }. Never in a
global ModData.

    History.init(newWorld)
    History.lines(c, peer)           -- the line table (created empty), shared with the caller
    History.find(c, peer)            -- the line table, or nil
    History.append(c, peer, line, max)
    History.retain(keep)             -- drops every (c, peer) for which keep(c, peer) is false
    History.radio(c, create)         -- E18-T19: radio history of a character { seq, frequencies } (RadioSurvivor's
                                     -- typed lines per frequency, RS_RadioLog rules), created when asked, or nil
    History.retainRadio(keep)        -- drops the radio history of every character for which keep(c) is false
    History.save()                   -- true when written

Storage blocked: a file exists but no slot can be read (or a newer schema): nothing is written, files kept.
]]
local SlotFile = require "RadioSurvivorCore/RC_SlotFile"

local History = { data = nil, seq = 0, blocked = false, dirty = false, base = nil }
History.DIR = "batman_RadioSurvivorCore/"
History.HEADER = "RCHISTORY1"
History.SCHEMA = 1
History.MAX = 40

local function log(msg)
    print("[RadioSurvivorCore] history: " .. tostring(msg))
end

local function fresh()
    return { schema = History.SCHEMA, characters = {}, radio = {} }
end

function History.init(newWorld)
    History.base = SlotFile.worldBase(History.DIR, "history")
    History.blocked, History.dirty = false, false
    local best, broken = SlotFile.read(History.base, History.HEADER)
    History.seq = best and best.seq or 0
    if newWorld then
        History.data = fresh()
    elseif best then
        local data = best.data
        if type(data.schema) ~= "number" or data.schema > History.SCHEMA then
            History.blocked, History.data = true, nil
            log("STORAGE BLOCKED: history written by a newer schema; preserve files for recovery")
            return false
        end
        if type(data.characters) ~= "table" then data.characters = {} end
        if type(data.radio) ~= "table" then data.radio = {} end
        History.data = data
    elseif broken then
        History.blocked, History.data = true, nil
        log("STORAGE BLOCKED: both history slots invalid; preserve files for recovery")
        return false
    else
        History.data = fresh()
    end
    if not History.save() then return false end
    return true
end

function History.find(c, peer)
    local peers = History.data and History.data.characters[c]
    return peers and peers[peer] or nil
end

function History.lines(c, peer)
    if not History.data then return {} end
    local peers = History.data.characters[c]
    if not peers then
        peers = {}
        History.data.characters[c] = peers
    end
    local list = peers[peer]
    if not list then
        list = {}
        peers[peer] = list
    end
    return list
end

function History.append(c, peer, line, max)
    local list = History.lines(c, peer)
    list[#list + 1] = line
    max = max or History.MAX
    while #list > max do table.remove(list, 1) end
    History.dirty = true
    return list
end

function History.retain(keep)
    if not History.data then return 0 end
    -- Keys collected first: no table is changed while it is walked (Kahlua).
    local drop, empty = {}, {}
    for c, peers in pairs(History.data.characters) do
        local left = 0
        for peer in pairs(peers) do
            if keep(c, peer) then left = left + 1 else drop[#drop + 1] = { c, peer } end
        end
        if left == 0 then empty[#empty + 1] = c end
    end
    for _, d in ipairs(drop) do History.data.characters[d[1]][d[2]] = nil end
    for _, c in ipairs(empty) do History.data.characters[c] = nil end
    return #drop
end

-- E18-T19: radio history of a character (the voices heard and answered on the radio), kept with the exchanges.
function History.radio(c, create)
    if not History.data or type(c) ~= "string" then return nil end
    if type(History.data.radio) ~= "table" then History.data.radio = {} end
    local r = History.data.radio[c]
    if r == nil and create then
        r = { seq = 0, frequencies = {} }
        History.data.radio[c] = r
        History.dirty = true
    end
    return r
end

function History.retainRadio(keep)
    if not History.data or type(History.data.radio) ~= "table" then return 0 end
    local drop = {}
    for c in pairs(History.data.radio) do if not keep(c) then drop[#drop + 1] = c end end
    for _, c in ipairs(drop) do History.data.radio[c] = nil end
    return #drop
end

function History.save()
    if History.blocked or not History.data then return false end
    local seq = History.seq + 1
    local ok, why = SlotFile.write(History.base, History.HEADER, seq, History.data)
    if not ok then
        History.dirty = true
        log("STORAGE WRITE FAILED (" .. tostring(why) .. "); kept in memory, retried at the next save")
        return false
    end
    History.seq, History.dirty = seq, false
    return true
end

return History
