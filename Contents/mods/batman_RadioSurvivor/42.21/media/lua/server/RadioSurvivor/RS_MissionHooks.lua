if isClient() then return end
--[[
RadioSurvivor's givers and hooks of the common mission engine (E18-T05, CA_Missions of the core mod; user decision of
2026-11-05: registration and hooks). Attached once by RS_State (RS_MissionHooks.attach(S)), before any mission is read.

- store: the notebook state RS_State (its S.save writes the mission file of the core mod first, then the notebook);
- NPC engine: RS_NPCProvider (Living Knox through its adapter, or no engine);
- givers: 'npc' = NPC fiche of the notebook (S.data.npcs; the mission of an engine NPC is paid by the reward source
  its engine registered in the core, M.npcReward: each mod pays its missions, E11-T21),
  'voice' = radio voice (S.data.voiceDonors, E11-T08; its dead drops polled and projected by RS_DeadDrops);
- result of a mission: trust of the notebook contact (the reputation fact of each participant and the offers closed
  to a bad reputation are the core engine's, E18-T22); result of a voice mission section, per participant and team,
  and the story state of the voice (RS_MissionChain, E20-T08);
- dropped mission: forgotten by every notebook character (knownMissions);
- missions still listed for a character: its notebook record (knownMissions, E18-T06: same list in the journal);
- character of a server player: the notebook binding (RS_CarnetServer.bound); a change from a world event publishes
  the notebook (RS_CarnetServer.publish).
Requires of modules that require RS_State are made at call time (RS_State requires this file).
]]
local M = require 'CoreAI/CA_Missions'
local P = require 'RadioSurvivor/RS_NPCProvider'

local H = {}

-- Reward source of the engine of the requester's fiche and its engine id (incarnation), or nil.
local function engineReward(state, m)
    local npcs = type(state) == 'table' and state.npcs or nil
    local npc = npcs and npcs[m.npc]
    local source = M.npcReward()
    if not npc or npc.incarnation == nil or not source then return nil end
    return source, npc.incarnation
end

local function npcGiver()
    return {
        find = function(state, id)
            local npcs = type(state) == 'table' and state.npcs or nil
            return npcs and npcs[id] or nil
        end,
        -- E18-T25: the fiche of an engine NPC (Living Knox: incarnation) needs its engine; without it its missions are
        -- hidden and frozen. A fiche of no engine (test fixtures) is always present.
        present = function(m, state)
            local npcs = type(state) == 'table' and state.npcs or nil
            local npc = npcs and npcs[m.npc]
            if npc and npc.incarnation ~= nil then return P.available() == true end
            return true
        end,
        -- E11-T21 (decision D09): the lot of an engine NPC is its engine's (same path as that engine alone); nil (no
        -- engine source, fiche of no engine) keeps the common lot.
        claim = function(store, m, player, character, token)
            local source, id = engineReward(store.data, m)
            if not source then return nil end
            return source.claim(store, m, player, character, token, id)
        end,
        lot = function(m)
            local source, id = engineReward(M.store().data, m)
            if not source or not source.lot then return nil end
            return source.lot(m, id)
        end,
    }
end

local function voiceGiver()
    return {
        find = function(state, id)
            local givers = type(state) == 'table' and state.voiceDonors or nil
            return givers and givers[id] or nil
        end,
        -- E20-T05, E20-T06: dead drops of a template declaring dropAccepts (poll, notebook, map, rule told to the voice).
        observeDrops = function(m, player, name, state, store)
            return require('RadioSurvivor/RS_DeadDrops').observe(m, player, name, state, store)
        end,
        projectDrops = function(m, p) return require('RadioSurvivor/RS_DeadDrops').project(m, p) end,
        dropsWhere = function(m) return require('RadioSurvivor/RS_DeadDrops').where(m) end,
        dropsRule = function(m) return require('RadioSurvivor/RS_DeadDrops').rule(m) end,
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

-- E20-T08: result of a voice mission section for this participant (its donor record of the voice) and the caller's
-- team; a success may set the story state of the voice (RS_MissionChain).
local function onVoiceResult(state, m, result, character)
    if m.donor ~= 'voice' or type(m.section) ~= 'string' then return end
    local donor = require('RadioSurvivor/RS_MissionVoice').donor(state, m.voice, character, true)
    require('RadioSurvivor/RS_MissionChain').record(state, m, result, donor)
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
    M.addResultListener(onVoiceResult)
    M.addPruneListener(onPruned)
    M.addChangeListener(publish)
    M.setCharacterName(characterName)
    M.setBinding(binding)
    M.setKnownMissions(knownMissions)
end

return H
