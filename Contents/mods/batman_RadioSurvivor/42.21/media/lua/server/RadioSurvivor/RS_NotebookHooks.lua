if isClient() then return end
--[[
RadioSurvivor: what it registers in the notebook server (E21-T04), which knows nothing of the radio voices. Authority
only. The notebook server of the core mod (CoreAI/CA_NotebookServer) is required here (run once).

  Server.addPoll            caches still to place (reward cache of a voice mission, E11-T06: CA_Caches.poll, with the
                            voice action of RS_CacheAction); rewards still to hand once there is room (RS_RewardRetry,
                            E23-T05)
  Server.hooks.overheard    comfort of a player who heard two NPCs talk (RS_Comfort, E05-T15)
  Server.hooks.claim        replies of the calls on a group frequency, aired by the group radio (RS_GroupRadio, E08-T06)
  Server.hooks.callLanguage forced language of the radio calls (RadioSurvivor_Const.callLanguage)
  CA_Identity.onRetire      a dead character: what the voices remembered stays, marked dead with its name and the
                            game day (RS_Memory.markDead, E22-T13); its bonds with the voices (RS_VoiceBonds, E07-T10)
                            and its radio history (CA_History.data.radio, E06-T04) are forgotten
]]
if RS_NotebookHooks then return RS_NotebookHooks end -- registered once, even after a Lua reload of this file
local Server = require 'CoreAI/CA_NotebookServer'
local Identity = require 'CoreAI/CA_Identity'
local History = require 'CoreAI/CA_History'
local Radio = require 'RadioSurvivor/RadioSurvivor_Const'
local Caches = require 'RadioSurvivor/RS_CacheAction'
local GroupRadio = require 'RadioSurvivor/RS_GroupRadio'
local RewardRetry = require 'RadioSurvivor/RS_RewardRetry'

local Hooks = {}
RS_NotebookHooks = Hooks

function Hooks.pollCaches(state, store) return Caches.poll(state, store) end

function Hooks.overheard(player, character, seen)
    require('RadioSurvivor/RS_Comfort').overheard(player, character, seen)
end

function Hooks.claim(req)
    if not GroupRadio.owns(req.id) then return nil end
    return function(r, result, npc) return GroupRadio.reply(Server, r, result, npc) end
end

-- Name of the dead character as the voices knew it: the name of its radio requests (RadioSurvivor_Server).
local function nameOf(character)
    local desc = character and character.getDescriptor and character:getDescriptor()
    if not desc then return nil end
    return tostring(desc:getForename()) .. ' ' .. tostring(desc:getSurname())
end

function Hooks.forget(character, id)
    if History.data and type(History.data.radio) == 'table' and History.data.radio[id] ~= nil then
        History.data.radio[id], History.dirty = nil, true
    end
    require('RadioSurvivor/RS_Memory').markDead(id, nameOf(character), Radio.gameDay())
    require('RadioSurvivor/RS_VoiceBonds').forget(id)
end

if Server then
    Server.addPoll(Hooks.pollCaches)
    Server.addPoll(RewardRetry.poll)
    table.insert(Server.hooks.overheard, Hooks.overheard)
    table.insert(Server.hooks.claim, Hooks.claim)
    Server.hooks.callLanguage = Radio.callLanguage
    Identity.onRetire(Hooks.forget)
end

return Hooks
