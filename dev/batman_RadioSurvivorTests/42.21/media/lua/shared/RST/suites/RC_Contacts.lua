--[[
rc.contacts - contacts of the core mod (E18-T26): what the authority sends to the Contacts tab of the notebook
(RC_Contacts.rows: rows of every source registered by an active mod, history of the core mod). Tag "server" (dedicated
server or solo authority). Outside the game: tests/test_core_notebook.py, tests/test_lk_contacts.py.

Works on a copy: a probe source is registered for the test only and made inert after it; the history line written
for the test is removed. With Living Knox alone and an NPC in its registry, the source "lk" lists it once the bound
character has an exchange with it.
]]

require "RST/RST"

local function active(id)
    local mods = getActivatedMods and getActivatedMods() or nil
    for i = 0, (mods and mods:size() or 0) - 1 do
        if string.gsub(tostring(mods:get(i)), "^\\", "") == id then return true end
    end
    return false
end

local function boundCharacter(t)
    local M = require "RadioSurvivorCore/RC_Missions"
    local list = getOnlinePlayers and getOnlinePlayers()
    local player = list and list:size() > 0 and list:get(0) or (getSpecificPlayer and getSpecificPlayer(0))
    local character = player and M.binding()[player]
    if not character then t:skip("no online player bound to a character") end
    return character, player
end

RST.suite("rc.contacts", { tags = { "server" } }, function(s)
    s.test("rows of the registered sources, with the core history", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only") end
        local C = require "RadioSurvivorCore/RC_Contacts"
        local H = require "RadioSurvivorCore/RC_History"
        local character, player = boundCharacter(t)
        local peer = "rcc:probe"
        C.registerSource("rcc-probe", { list = function(c)
            if c ~= character then return {} end
            return { { id = peer, name = "Probe Contact", alive = true } }
        end })
        t:defer(function()
            C.registerSource("rcc-probe", { list = function() return {} end })
            local peers = H.data and H.data.characters[character]
            if peers then peers[peer] = nil end
        end, "probe source made inert, its history line removed")
        H.append(character, peer, { id = "rcc-1", author = "Tester", text = "hello" })
        local found
        for _, r in ipairs(C.rows(character, player)) do if r.id == peer then found = r end end
        t:ok(found ~= nil, "probe contact listed")
        t:eq({ "rcc-probe", "Probe Contact", 1 }, { found and found.source, found and found.name,
            found and #found.history }, "source, name and history of the row")
        t:eq(0, #C.rows("rcc-nobody", nil) > 0 and 1 or 0, "no contact for another character")
    end)

    s.test("Living Knox alone: its source is registered, RadioSurvivor's is not", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only") end
        local C = require "RadioSurvivorCore/RC_Contacts"
        local rs, lk = active("batman_RadioSurvivor"), active("batman_LivingKnox")
        t:eq(rs, C.sources.rs ~= nil, "source rs registered only with RadioSurvivor")
        t:eq(lk and not rs, C.sources.lk ~= nil, "source lk registered only with Living Knox alone")
        t:note("RadioSurvivor " .. tostring(rs) .. ", Living Knox " .. tostring(lk))
    end)
end)
