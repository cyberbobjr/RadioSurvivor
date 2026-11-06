if isClient() then return end
--[[
Living Knox: its NPCs in the Contacts tab of the notebook of the core mod (E18-T26, RC_Contacts source "lk"). Authority
only.

The NPCs a character knows: those with a personal relation toward it (LK_PersonalRelation) or an exchange history with
it (RC_History, peer "lk:<npc id>"), still in the Living Knox registry. A row: id "lk:<npc id>" (the history key of
the core mod), name (LivingKnox.Names), groupName, alive, relation = panel of the personal relation (identifiers and game
days, translated by Living Knox's page of the notebook).
With RadioSurvivor active, its notebook fiches already list these NPCs (with their relation through the API): the
source is not registered, so a contact is never listed twice.
]]
require "LivingKnox/LK_Core"
require "LivingKnox/LK_PersonalRelation"
local Names = require "LivingKnox/LK_Names"
local History = require "RadioSurvivorCore/RC_History"
local Contacts = require "RadioSurvivorCore/RC_Contacts"

local LKC = {}
LivingKnox.Contacts = LKC

-- getActivatedMods (LuaManager.java:6065): Java list of the loaded mod ids, a leading "\" dropped. Absent outside the
-- game (offline benches): RadioSurvivor counts as present, as in RS_LivingKnox.
local function radioSurvivorActive()
    if type(getActivatedMods) ~= "function" then return true end
    local mods = getActivatedMods()
    for i = 0, (mods and mods:size() or 0) - 1 do
        if string.gsub(tostring(mods:get(i)), "^\\", "") == "batman_RadioSurvivor" then return true end
    end
    return false
end

-- Living Knox NPC ids known to a character (set).
function LKC.known(character)
    local ids = {}
    local R = LivingKnox.PersonalRelation
    if R.ensure() and type(R.data) == "table" and type(R.data.relations) == "table" then
        for npcId, byCharacter in pairs(R.data.relations) do
            if type(byCharacter) == "table" and byCharacter[character] ~= nil then ids[npcId] = true end
        end
    end
    local hist = History.data and History.data.characters and History.data.characters[character]
    for peer in pairs(type(hist) == "table" and hist or {}) do
        local id = string.match(tostring(peer), "^lk:(lk%-%d+)$")
        if id then ids[id] = true end
    end
    return ids
end

function LKC.list(character)
    local rows = {}
    for id in pairs(LKC.known(character)) do
        local named = Names.of(id)
        if named then
            rows[#rows + 1] = { id = "lk:" .. id, name = named.name, alive = true,
                groupName = named.groupName ~= "" and named.groupName or nil,
                relation = LivingKnox.PersonalRelation.panel(id, character) }
        end
    end
    return rows
end

LKC.registered = false
function LKC.register()
    if LKC.registered or radioSurvivorActive() then return false end
    Contacts.registerSource("lk", { list = function(character) return LKC.list(character) end })
    LKC.registered = true
    return true
end
LKC.register()

return LKC
