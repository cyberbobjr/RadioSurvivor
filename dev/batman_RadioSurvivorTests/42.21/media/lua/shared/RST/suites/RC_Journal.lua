--[[
rc.journal - mission journal of the core mod (E18-T06): rows the authority sends to a player's journal.
Tag "server": RC_MissionJournal starts with "if isClient() then return end" (authority only: dedicated server or solo).
Run it with RST.server("rc.journal") or the MP campaign; outside the game: tests/test_core_journal.py.

Works on an in-memory mission store (RC_Missions.useStore) put back after each test: no persistent state changed.
The character is the one the engine binds to the first online player (RadioSurvivor's notebook binding, else the core
identity); SKIP without such a player.
]]

require "RST/RST"

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RC_MissionJournal is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivorCore/RC_Missions"
    local J = require "RadioSurvivorCore/RC_MissionJournal"
    if type(M) ~= "table" or type(J) ~= "table" then t:skip("core mission modules not loaded here") end
    return M, J
end

local function boundCharacter(t, M)
    local list = getOnlinePlayers and getOnlinePlayers()
    local player = list and list:size() > 0 and list:get(0) or (getSpecificPlayer and getSpecificPlayer(0))
    local character = player and M.binding()[player]
    if not character then t:skip("no online player bound to a character") end
    return character
end

-- Runs fn(state, store) with an in-memory store, then puts the real store back.
local function withStore(M, fn)
    local real = M.store()
    local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
    local store = { data = state, save = function() return true end }
    M.useStore(store)
    local ok, err = pcall(fn, state, store)
    M.useStore(real)
    if not ok then error(err, 0) end
end

RST.suite("rc.journal", { tags = { "server" } }, function(s)
    s.test("open missions of the player's character, requester and state", function(t)
        local M, J = modules(t)
        local character = boundCharacter(t, M)
        withStore(M, function(state)
            local npc = { id = "rcj-npc", name = "Ruth" }
            state.npcs[npc.id] = npc
            local m = M.create(state, npc, character, "first_aid_v1")
            t:ok(m ~= nil, "offer created")
            local rows = J.rows(character)
            t:eq(1, #rows, "one row")
            t:eq({ m.id, "offer", "Ruth" }, { rows[1].id, rows[1].state, rows[1].requester }, "row of the offer")
            t:eq(0, #J.rows("rcj-someone-else"), "never another character's mission")
            m.state = "success"
            t:eq(0, #J.rows(character), "a closed mission leaves the journal")
        end)
    end)
end)
