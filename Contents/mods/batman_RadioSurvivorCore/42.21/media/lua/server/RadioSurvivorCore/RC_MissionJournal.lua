if isClient() then return end
--[[
RadioSurvivorCore: server side of the mission journal (E18-T06, user decision of 2026-11-05). Authority only.

The client asks "missions" (module RadioSurvivorCore, at most JOURNAL_LIMIT per second and account); the authority
answers "missions" { missions = rows } with the open missions (offer, active, to report) its character sees, as the
engine projects them (RC_Missions.projection: copies only, never a receipt or another player's data) plus the
requester's name, in the notebook order (RC_MissionList); missions of a giver whose mod is not active are left out
(RC_Missions.present, E18-T25). The character of a player is the one of the mission engine (RC_Missions.binding:
RadioSurvivor's notebook binding, else the core identity); without one, an empty list.
E18-T25: "reputation" (same limit) answers "reputation" { reputation = RC_Reputation.projection(character) }: level,
trend, last acts by action and game day, never a number nor a text (each mod translates the acts it knows).
E18-T26: "contacts" (same limit) answers "contacts" { contacts = RC_Contacts.rows(character, player) }: the
interlocutors given by each active mod.
Solo: same Lua, the answers are handed to the notebook of the core mod directly.
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
        if M.present(m) and List.visible(m, character, known) then
            local p = M.projection(m, character)
            if List.open(p) then
                p.requester = M.requester(state, m)
                rows[#rows + 1] = p
            end
        end
    end
    return List.sort(rows)
end

local function reply(player, command, args)
    if isServer() then
        sendServerCommand(player, Journal.MODULE, command, args)
    else
        -- solo: same Lua, the notebook of the core mod (RC_Notebook) gets the answer directly
        local notebook = RadioSurvivorCore and RadioSurvivorCore.notebook
        if notebook and notebook.receive then notebook.receive(command, args) end
    end
end

-- Reputation of a character as the notebook shows it (RC_Reputation.projection: copies, no number).
function Journal.reputation(character)
    if type(character) ~= "string" then return { available = false } end
    return require("RadioSurvivorCore/RC_Reputation").projection(character)
end

function Journal.onClientCommand(module, command, player, args)
    if module ~= Journal.MODULE or player == nil then return end
    if command ~= "missions" and command ~= "reputation" and command ~= "contacts" then return end
    if isServer() and not RateLimit.allow(player, "core.missions", Journal.LIMIT[1], Journal.LIMIT[2]) then return end
    local character = M.binding()[player]
    if command == "missions" then
        reply(player, command, { missions = Journal.rows(character) })
    elseif command == "contacts" then
        reply(player, command, { contacts = require("RadioSurvivorCore/RC_Contacts").rows(character, player) })
    else
        reply(player, command, { reputation = Journal.reputation(character) })
    end
end

Events.OnClientCommand.Add(Journal.onClientCommand)

return Journal
