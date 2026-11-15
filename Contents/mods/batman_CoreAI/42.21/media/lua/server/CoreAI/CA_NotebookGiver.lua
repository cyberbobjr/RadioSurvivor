if isClient() then return end
--[[
CoreAI: the common mission engine on the notebook (E18-T05, E21-T04): its store (CA_NotebookStore), the NPC provider,
the giver 'npc' (a fiche of the notebook, data.npcs) and the hooks of the notebook. Authority only. Attached once at
load (required by the notebook server, CA_NotebookServer, before any mission is read); a mod that hosts the speech of
its NPCs itself may register its own giver 'npc' and hooks afterwards.

    Giver.new(objects) -> giver   objects() -> { [fiche id] = loaded body }
    Giver.objects, Giver.bound, Giver.publish   set by the notebook server: loaded bodies of the fiches, notebook
                                                binding { [server player] = character }, push of the snapshots

Giver 'npc':
- find(state, id): the fiche;
- present(m, state): E18-T25, the fiche of an engine NPC (incarnation) needs its engine (CA_NPCProvider.available);
  without it its missions are hidden and frozen. A fiche of no engine (test fixtures) is always present;
- near(m, player): hand-over, report and claim next to the requester's loaded body (DELIVERY_RANGE);
- claim and lot: E11-T21 (decision D09: each mod pays its missions), the lot of an engine NPC is the reward source its
  engine registered (CA_Missions.registerNpcReward); nil (no engine source, fiche of no engine) keeps the common lot.
Hooks: result of a mission = trust of the notebook contact (the reputation facts are the engine's, E18-T22); dropped
mission forgotten by every notebook character (knownMissions); missions still listed for a character = its record
(knownMissions, E18-T06); name kept with a claimed lot = its record; character of a server player = the notebook
binding; a change from a world event publishes the notebook.
]]
local M = require 'CoreAI/CA_Missions'
local P = require 'CoreAI/CA_NPCProvider'
local C = require 'CoreAI/CA_NotebookConfig'
local Store = require 'CoreAI/CA_NotebookStore'

local Giver = {}
Giver.objects = function() return {} end
Giver.bound = function() return {} end
Giver.publish = function() end

-- Reward source of the engine of the requester's fiche and its engine id (incarnation), or nil.
local function engineReward(state, m)
    local npcs = type(state) == 'table' and state.npcs or nil
    local npc = npcs and npcs[m.npc]
    local source = M.npcReward()
    if not npc or npc.incarnation == nil or not source then return nil end
    return source, npc.incarnation
end

function Giver.new(objects)
    return {
        find = function(state, id)
            local npcs = type(state) == 'table' and state.npcs or nil
            return npcs and npcs[id] or nil
        end,
        present = function(m, state)
            local npcs = type(state) == 'table' and state.npcs or nil
            local npc = npcs and npcs[m.npc]
            if npc and npc.incarnation ~= nil then return P.available() == true end
            return true
        end,
        near = function(m, player) return P.near(player, objects()[m.npc], C.DELIVERY_RANGE) end,
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

local function bound() return Giver.bound() end
local function publish() Giver.publish() end

M.useStore(Store)
M.setProvider(P)
M.registerDonor('npc', Giver.new(function() return Giver.objects() end))
M.addResultListener(onResult)
M.addPruneListener(onPruned)
M.addChangeListener(publish)
M.setCharacterName(characterName)
M.setBinding(bound)
M.setKnownMissions(knownMissions)

return Giver
