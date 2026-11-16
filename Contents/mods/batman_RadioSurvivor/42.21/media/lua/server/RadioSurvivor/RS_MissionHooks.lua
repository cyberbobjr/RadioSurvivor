if isClient() then return end
--[[
RadioSurvivor's giver and hooks of the common mission engine (E18-T05, CA_Missions of the core mod; user decision of
2026-11-05: registration and hooks). E21-T04: the store, the giver 'npc' and the hooks of the notebook are the notebook
server's (CoreAI/CA_NotebookServer, attachMissions); RadioSurvivor adds its radio voices. Attached once by RS_State
(RS_MissionHooks.attach()), before any mission is read.

- giver 'voice' = radio voice (remote: no body to join; donor records in the state of the voices, RS_State
  data.voiceDonors, E11-T08; its dead drops polled and projected by RS_DeadDrops; E23-T03, ADR D08: a mission waiting
  for its report has its delay stopped, reason 'bridge', while the bridge is not seen alive, CA_Bridge.alive);
- result of a voice mission section, per participant and team, and the story state of the voice (RS_MissionChain,
  E20-T08), in the state of the voices.
Requires of modules that require RS_State are made at call time (RS_State requires this file).
]]
local M = require 'CoreAI/CA_Missions'
local Bridge = require 'CoreAI/CA_Bridge'

local H = {}

local function voiceGiver()
    return {
        remote = true,
        find = function(_, id)
            -- E21-T04: the donor records live in the state of the voices (RS_State), not in the mission state.
            local voices = require('RadioSurvivor/RS_State').data
            local givers = type(voices) == 'table' and voices.voiceDonors or nil
            return givers and givers[id] or nil
        end,
        -- E20-T05, E20-T06: dead drops of a template declaring dropAccepts (poll, notebook, map, rule told to the voice).
        observeDrops = function(m, player, name, state, store)
            return require('RadioSurvivor/RS_DeadDrops').observe(m, player, name, state, store)
        end,
        projectDrops = function(m, p) return require('RadioSurvivor/RS_DeadDrops').project(m, p) end,
        dropsWhere = function(m) return require('RadioSurvivor/RS_DeadDrops').where(m) end,
        dropsRule = function(m) return require('RadioSurvivor/RS_DeadDrops').rule(m) end,
        -- E23-T03: without the bridge the voice cannot hear the report the mission waits for.
        paused = function(m)
            if M.reportReady(m) and not Bridge.alive() then return 'bridge' end
            return nil
        end,
    }
end

-- E20-T08: result of a voice mission section for this participant (its donor record of the voice) and the caller's
-- team; a success may set the story state of the voice (RS_MissionChain).
local function onVoiceResult(_, m, result, character)
    if m.donor ~= 'voice' or type(m.section) ~= 'string' then return end
    local voices = require('RadioSurvivor/RS_State').data -- E21-T04: chains and story in the state of the voices
    if type(voices) ~= 'table' then return end
    local donor = require('RadioSurvivor/RS_MissionVoice').donor(m.voice, character, true)
    require('RadioSurvivor/RS_MissionChain').record(voices, m, result, donor)
end

function H.attach()
    M.registerDonor('voice', voiceGiver())
    M.addResultListener(onVoiceResult)
end

return H
