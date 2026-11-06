if isClient() then return end
--[[
RadioSurvivorCore: contacts of a character, given by each mod (E18-T26, decision of 2026-11-06: one Contacts tab in
the notebook of the core mod, every mod gives its own interlocutors). Authority only.

    Contacts.registerSource(name, { list = function(character, player) -> rows })
    Contacts.rows(character, player) -> rows of every registered source, sorted by name

A source is registered by the server code of its mod, so the contacts of a mod that is not active are neither listed
nor touched (its data stays in its own files and comes back with it). A row is a copy, never a live table:
    { id (unique, e.g. "lk:lk-3"), source (set here), name, alive, groupName?, near?, relation? (panel of the mod),
      history? (lines of RC_History for (character, id) when the source gives none) }
Read by the command "contacts" of the module RadioSurvivorCore (RC_MissionJournal).
]]
local History = require "RadioSurvivorCore/RC_History"

local Contacts = { sources = {}, order = {} }

function Contacts.registerSource(name, source)
    if type(name) ~= "string" or type(source) ~= "table" or type(source.list) ~= "function" then return nil end
    if not Contacts.sources[name] then Contacts.order[#Contacts.order + 1] = name end
    Contacts.sources[name] = source
    return source
end

local function copyLines(lines)
    local out = {}
    for i, l in ipairs(type(lines) == "table" and lines or {}) do
        out[i] = { id = l.id, author = l.author, text = l.text }
    end
    return out
end

function Contacts.rows(character, player)
    local out = {}
    if type(character) ~= "string" then return out end
    for _, name in ipairs(Contacts.order) do
        for _, row in ipairs(Contacts.sources[name].list(character, player) or {}) do
            if type(row) == "table" and type(row.id) == "string" then
                row.source = name
                if row.history == nil then row.history = copyLines(History.find(character, row.id)) end
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(a, b)
        local x, y = tostring(a.name or ""), tostring(b.name or "")
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return out
end

return Contacts
