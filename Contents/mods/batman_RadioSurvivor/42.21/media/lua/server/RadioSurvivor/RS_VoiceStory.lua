if isClient() then return end
--[[
Story state of a radio voice (E20-T08, ADR D09). Authority only.

A free name ([a-z][a-z0-9_]*, 32 characters at most, e.g. 'returned') telling where the voice's story stands. It is
distinct from the life state of the sheet (state= active, silent, gone, dead: RS_Persona) and from the dynamic state
of the voice (morale, supplies, place: RS_PersonaState). It is set by the success of a mission section declaring
sets_state= (RS_MissionChain.record), once: setting the value it already has changes nothing.
Stored in the private state RS_State (S.data.voiceStory[voice] = name), saved with it and read again at load; never in
the sheet file nor in a global ModData. Readers: the radio request (field story=, RadioSurvivor_Server; the bridge
tells it to the model without knowing any name) and the public API of the mod (RS_API: voiceStoryState).
]]
local S = require "RadioSurvivor/RS_State"

local Story = {}

Story.MAX_CHARS = 32

-- True for a story state name: a to z, 0 to 9 and _, starting with a letter, MAX_CHARS characters at most.
function Story.valid(value)
    return type(value) == "string" and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
        and string.len(value) <= Story.MAX_CHARS
end

-- Story state of this voice in this state table, or nil.
function Story.of(state, voice)
    local all = type(state) == "table" and state.voiceStory or nil
    local value = type(all) == "table" and all[voice] or nil
    if Story.valid(value) then return value end
    return nil
end

-- Sets the story state of this voice in this state table. Returns true when it changed (the caller saves).
function Story.set(state, voice, value)
    if type(state) ~= "table" or type(voice) ~= "string" or not Story.valid(value) then return false end
    if Story.of(state, voice) == value then return false end
    if type(state.voiceStory) ~= "table" then state.voiceStory = {} end
    state.voiceStory[voice] = value
    return true
end

-- Story state of this voice in the loaded private state, or nil (none, or state not loaded).
function Story.value(voice)
    if S.blocked then return nil end
    return Story.of(S.data, voice)
end

return Story
