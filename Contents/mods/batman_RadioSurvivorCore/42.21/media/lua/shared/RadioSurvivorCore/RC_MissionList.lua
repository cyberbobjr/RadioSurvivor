--[[
RadioSurvivorCore: one list of missions per character (E18-T06), shared by the mission journal of the core mod
(RC_MissionJournal) and RadioSurvivor's notebook (Missions tab): which missions a character sees, their order and the
state shown. Pure functions, loaded on every machine (media/lua/shared).

    List.visible(m, character, known)   the character takes part, is invited, or still knows the mission (known: set
                                        of mission ids kept by RadioSurvivor's notebook, or nil)
    List.sort(rows)                     mission id order (stable from one refresh to the next); returns rows
    List.stateKey(row)                  'toReport' once the objective is met (E11-T13), else the mission state
    List.open(row)                      offer, active or to report: what the journal lists
]]
local List = {}

function List.visible(m, character, known)
    if type(m) ~= "table" or type(character) ~= "string" then return false end
    if type(m.participants) == "table" and m.participants[character] ~= nil then return true end
    if type(m.invited) == "table" and m.invited[character] == true then return true end
    return type(known) == "table" and known[m.id] == true
end

function List.sort(rows)
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

function List.stateKey(row)
    if type(row) ~= "table" then return nil end
    if row.toReport then return "toReport" end
    return row.state
end

function List.open(row)
    local key = List.stateKey(row)
    return key == "offer" or key == "active" or key == "toReport"
end

return List
