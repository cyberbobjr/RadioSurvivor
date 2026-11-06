if isClient() then return end
--[[
RadioSurvivor's givers and hooks of the common mission engine (E18-T05, RC_Missions of the core mod; user decision of
2026-11-05: registration and hooks). Attached once by RS_State (RS_MissionHooks.attach(S)), before any mission is read.

- store: the notebook state RS_State (its S.save writes the mission file of the core mod first, then the notebook);
- NPC engine: RS_NPCProvider (Living Knox through its adapter, or no engine);
- givers: 'npc' = NPC fiche of the notebook (S.data.npcs; reward path RS_NPCRewards for a Living Knox NPC),
  'voice' = radio voice (S.data.voiceDonors, E11-T08; its dead drop polled by RS_VoiceDelivery);
- result of a mission: trust of the notebook contact (the reputation fact of each participant and the offers closed
  to a bad reputation are the core engine's, E18-T22);
- dropped mission: forgotten by every notebook character (knownMissions);
- missions still listed for a character: its notebook record (knownMissions, E18-T06: same list in the journal);
- character of a server player: the notebook binding (RS_CarnetServer.bound); a change from a world event publishes
  the notebook (RS_CarnetServer.publish).
Requires of modules that require RS_State are made at call time (RS_State requires this file).
]]
local M = require 'RadioSurvivorCore/RC_Missions'
local P = require 'RadioSurvivor/RS_NPCProvider'

local H = {}

local function npcGiver()
    return {
        find = function(state, id)
            local npcs = type(state) == 'table' and state.npcs or nil
            return npcs and npcs[id] or nil
        end,
        claim = function(store, m, player, character, token)
            local npc = store.data.npcs and store.data.npcs[m.npc]
            if npc and npc.incarnation ~= nil then
                return require('RadioSurvivor/RS_NPCRewards').claim(store, m, player, character, token)
            end
            return nil
        end,
    }
end

local function voiceGiver()
    return {
        find = function(state, id)
            local givers = type(state) == 'table' and state.voiceDonors or nil
            return givers and givers[id] or nil
        end,
        observeDeliver = function(m, player, name, state, store)
            return require('RadioSurvivor/RS_VoiceDelivery').observe(m, player, name, state, store)
        end,
    }
end

local function onResult(state, m, result, character)
    local record = state.characters and state.characters[character]
    local known = record and record.contacts[m.npc]
    if known then
        known.trust = result == 'success' and 'Favourable' or 'Cautious'
        known.trend = result == 'success' and 'Rising' or 'Falling'
    end
end

local function onPruned(state, id)
    for _, record in pairs(state.characters or {}) do record.knownMissions[id] = nil end
end

local function characterName(state, character)
    local record = state.characters and state.characters[character]
    return record and record.name or nil
end

local function knownMissions(state, character)
    local record = state.characters and state.characters[character]
    return record and record.knownMissions or nil
end

local function binding()
    return RS_CarnetServer and RS_CarnetServer.bound or nil
end

local function publish()
    if RS_CarnetServer and RS_CarnetServer.publish then RS_CarnetServer.publish() end
end

function H.attach(S)
    M.useStore(S)
    M.setProvider(P)
    M.registerDonor('npc', npcGiver())
    M.registerDonor('voice', voiceGiver())
    M.addResultListener(onResult)
    M.addPruneListener(onPruned)
    M.addChangeListener(publish)
    M.setCharacterName(characterName)
    M.setBinding(binding)
    M.setKnownMissions(knownMissions)
end

return H
