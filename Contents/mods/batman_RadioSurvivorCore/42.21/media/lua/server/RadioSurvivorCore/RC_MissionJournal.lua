if isClient() then return end
--[[
RadioSurvivorCore: server side of the mission journal (E18-T06, user decision of 2026-11-05). Authority only.

The client asks "missions" (module RadioSurvivorCore, at most JOURNAL_LIMIT per second and account); the authority
answers "missions" { missions = rows } with the open missions (offer, active, to report) its character sees, as the
engine projects them (RC_Missions.projection: copies only, never a receipt or another player's data) plus the
requester's name, in the notebook order (RC_MissionList). The character of a player is the one of the mission engine
(RC_Missions.binding: RadioSurvivor's notebook binding, else the core identity); without one, an empty list. Solo:
same Lua, the answer is handed to the client side directly.
]]
local M = require "RadioSurvivorCore/RC_Missions"
local List = require "RadioSurvivorCore/RC_MissionList"
local RateLimit = require "RadioSurvivorCore/RC_RateLimit"

local Journal = {}
Journal.MODULE = "RadioSurvivorCore"
Journal.LIMIT = { 4, 1 }   -- token bucket of "missions" per account (RC_RateLimit, MP server only)

-- Open missions seen by this character, projected, in the list order.
function Journal.rows(character)
    local rows = {}
    local store = M.store()
    local state = store and store.data
    if type(character) ~= "string" or type(state) ~= "table" or type(state.missions) ~= "table" then return rows end
    local known = M.knownMissions(state, character)
    for _, m in pairs(state.missions) do
        if List.visible(m, character, known) then
            local p = M.projection(m, character)
            if List.open(p) then
                p.requester = M.requester(state, m)
                rows[#rows + 1] = p
            end
        end
    end
    return List.sort(rows)
end

local function reply(player, rows)
    local args = { missions = rows }
    if isServer() then
        sendServerCommand(player, Journal.MODULE, "missions", args)
    else
        -- solo: same Lua, the notebook of the core mod (RC_Notebook, Missions tab) gets the answer directly
        local view = RadioSurvivorCore and RadioSurvivorCore.notebook and RadioSurvivorCore.notebook.journal
        if view and view.receive then view.receive(args) end
    end
end

function Journal.onClientCommand(module, command, player, args)
    if module ~= Journal.MODULE or command ~= "missions" or player == nil then return end
    if isServer() and not RateLimit.allow(player, "core.missions", Journal.LIMIT[1], Journal.LIMIT[2]) then return end
    reply(player, Journal.rows(M.binding()[player]))
end

Events.OnClientCommand.Add(Journal.onClientCommand)

return Journal
