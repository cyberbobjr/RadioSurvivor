if isClient() then return end
--[[
CoreAI: rows of the mission journal (E18-T06, user decision of 2026-11-05). Authority only. E21-T04: the notebook
reads the snapshot of the notebook server (CoreAI/CA_NotebookServer); these builders stay for the mods and the tests
that list the missions of a character the same way.

    Journal.rows(character) -> rows      open missions (offer, active, to report, to claim) this character sees, as the
                                         engine projects them (CA_Missions.projection: copies only, never a receipt or
                                         another player's data) plus the requester's name, in the notebook order
                                         (CA_MissionList); missions of a giver whose mod is not active are left out
                                         (CA_Missions.present, E18-T25)
    Journal.lotLeft(m) -> boolean        a lot is left to collect: the common lot of the engine, or the reward path of
                                         a giver whose requester can be joined (near)
]]
local M = require "CoreAI/CA_Missions"
local List = require "CoreAI/CA_MissionList"

local Journal = {}

function Journal.lotLeft(m)
    local giver = M.donor(m.donor or "npc")
    if giver == nil or giver.near == nil then return false end
    return (m.rewardCount or 0) > 0 or giver.claim ~= nil
end

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

return Journal
