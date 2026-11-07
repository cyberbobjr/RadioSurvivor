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
E18-T29: "mission" { action = "deliver" | "claim", mission, revision, items? } (same limit): hand-over of items or claim
of the lot of a mission the character takes part in, next to the requester (the giver's near(m, player); a giver
without it, RadioSurvivor's notebook giver or a radio voice, is refused: its own notebook handles them). Checks and
effects are the engine's (RC_Missions.deliver, RC_Missions.claim, reward path of the giver). A refusal answers "error"
{ reason }; the list is sent again in every case.
Solo: same Lua, the answers are handed to the notebook of the core mod directly.
]]
local M = require "RadioSurvivorCore/RC_Missions"
local List = require "RadioSurvivorCore/RC_MissionList"
local RateLimit = require "RadioSurvivorCore/RC_RateLimit"

local Journal = {}
Journal.MODULE = "RadioSurvivorCore"
Journal.LIMIT = { 4, 1 }   -- token bucket of "missions" per account (RC_RateLimit, MP server only)

-- Templates whose objective is a hand-over of items to the requester (window of the notebook).
Journal.HANDOVER = { deliver = true, retrieve_id = true }

local seq = 0
local function token(kind)
    seq = seq + 1
    return "rc-" .. kind .. "-" .. tostring(getTimestampMs()) .. "-" .. seq
end

-- Gesture of a participant on one of its missions: true, or false and the reason shown to the player.
function Journal.act(player, character, args)
    local store = M.store()
    if type(store) ~= "table" or type(store.data) ~= "table" or store.blocked then return false, "Storage" end
    local missions = store.data.missions
    local m = type(args.mission) == "string" and type(missions) == "table" and missions[args.mission] or nil
    if not m or type(character) ~= "string" or not m.participants[character] or not M.present(m)
            or m.revision ~= args.revision then
        return false, "State"
    end
    local giver = M.donor(m.donor or "npc")
    if not giver or not giver.near then return false, "State" end
    if not giver.near(m, player) then return false, "Range" end
    if args.action == "deliver" then
        if m.state ~= "active" or not Journal.HANDOVER[m.template or "deliver"] then return false, "State" end
        return M.deliver(store, m, player, character, args.items, token("deliver"))
    elseif args.action == "claim" then
        return M.claim(store, m, player, character, token("claim"))
    end
    return false, "State"
end

-- A lot is left to collect: the common lot of the engine, or the reward path of a giver the journal can reach.
function Journal.lotLeft(m)
    local giver = M.donor(m.donor or "npc")
    if giver == nil or giver.near == nil then return false end
    return (m.rewardCount or 0) > 0 or giver.claim ~= nil
end

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
            -- E18-T29: a success whose lot this participant can still collect from a giver near its body.
            if p.state == "success" and p.engaged and p.claimedName == "" and Journal.lotLeft(m) then p.toClaim = true end
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
    if command ~= "missions" and command ~= "reputation" and command ~= "contacts" and command ~= "mission" then
        return
    end
    if isServer() and not RateLimit.allow(player, "core.missions", Journal.LIMIT[1], Journal.LIMIT[2]) then return end
    local character = M.binding()[player]
    if command == "mission" then
        local ok, reason = Journal.act(player, character, type(args) == "table" and args or {})
        if not ok then reply(player, "error", { reason = reason or "State" }) end
        reply(player, "missions", { missions = Journal.rows(character) })
    elseif command == "missions" then
        reply(player, command, { missions = Journal.rows(character) })
    elseif command == "contacts" then
        reply(player, command, { contacts = require("RadioSurvivorCore/RC_Contacts").rows(character, player) })
    else
        reply(player, command, { reputation = Journal.reputation(character) })
    end
end

Events.OnClientCommand.Add(Journal.onClientCommand)

return Journal
