if isClient() then return end
--[[
Rewards still to hand (E23-T05, ADR D10). Authority only. Poll of the notebook server (CA_NotebookServer.addPoll,
registered by RS_NotebookHooks; once a second while identified players are connected): a successful voice mission
whose reward stays reserved (its effect did not happen: inventory full for a stash map) is applied again for its
recipient, connected, by RS_Rewards.retry (only the kinds that can resume it). Ledgers of the rewards in the state of
the voices (RS_State), as RS_MissionVoice.reward. ASCII only (Kahlua lexer).
]]
local Rewards = require 'RadioSurvivor/RS_Rewards'
local S = require 'RadioSurvivor/RS_State'
local Personas = require 'RadioSurvivor/RS_Personas'

local Retry = {}

local function pending(m)
    local rec = m.donor == 'voice' and m.state == 'success' and m.extendedReward or nil
    return type(rec) == 'table' and rec.status == 'reserved' and rec or nil
end

-- poll(state, store, watched) -> true when a mission changed (notebook server: saved and published).
function Retry.poll(state, _, watched)
    if type(state) ~= 'table' or type(state.missions) ~= 'table' then return false end
    local players = {}
    for _, entry in ipairs(watched or {}) do players[entry.character] = entry.player end
    local changed = false
    for _, m in pairs(state.missions) do
        local rec = pending(m)
        local player = rec and players[rec.character]
        local source = player and Personas.get(rec.source)
        if source and Rewards.retry(S, source, m, player, rec.character, m.khz) then
            m.rewardLabel = Rewards.context(rec)
            m.revision = (m.revision or 0) + 1
            changed = true
        end
    end
    return changed
end

return Retry
