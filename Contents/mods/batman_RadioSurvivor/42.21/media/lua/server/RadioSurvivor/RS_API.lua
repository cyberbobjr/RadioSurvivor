if isClient() then return end
--[[
Public API of RadioSurvivor for other mods (E20-T08), on the authority only: global RadioSurvivor.API, required by
RadioSurvivor_Server. No dependency on any other mod: a consumer (an NPC engine, ADR D09) checks that the table
exists, then API.version() >= the version it knows.
Version: API.VERSION (whole number). Within a version, functions are only added; a removal or a change of meaning
takes a new version.
  API.version() -> VERSION
  API.voiceStoryState(voiceId) -> story state of the voice (name such as 'returned', set by the success of a mission
                                  declaring sets_state=, RS_VoiceStory), or nil (none yet, or state not loaded)
]]
local Story = require "RadioSurvivor/RS_VoiceStory"

local API = {}
API.VERSION = 1

function API.version()
    return API.VERSION
end

function API.voiceStoryState(voiceId)
    if type(voiceId) ~= "string" then return nil end
    return Story.value(voiceId)
end

RadioSurvivor = RadioSurvivor or {}
RadioSurvivor.API = API

return API
