if isClient() then return end
--[[
RadioSurvivor: its lanes in the queue of the core mod (E18-T04, CoreAI/CA_Transport). Returns the
transport. Order of the requests file: radio (10), then the lanes npc (20) and acks (30) of the NPC engine
(E18-T17), then lastPages (40).
- radio: requests of the radio voices (RadioSurvivor_Server.lua), written as key=value lines (format below);
- lastPages (E15-T03): kind=last_pages requests of RS_LastPages, written as RSV2 (kind=, payload=).
Caps stay in RadioSurvivor (decision of 2026-11-05).
]]
local T = require "CoreAI/CA_Transport"

-- voice (E05-T03): id of the voice sheet chosen by the frequency; absent = walt for the bridge.
-- kind=radio_call (E05-T05): spontaneous call of the voice, with voice, date and language only; a bridge
-- older than E05-T05 ignores it (unknown kind) and the server airs the fixed call_text after its delay.
-- memory (E07-T03): facts the voice remembers about this caller (hex RSV2 list, RS_Memory.field); absent = none.
-- persona (E07-T06): dynamic state of the voice (hex RSV2 table, RS_PersonaState.field); absent = never changed.
-- mission (E11-T08): mission of this voice for this caller (hex RSV2 table, RS_MissionVoice.field); absent = none.
-- jobs (E20-T02): missions this voice may give and cache tables (hex RSV2, RS_MissionVoice.jobs); absent = the sheet
-- does not allow start_mission.
-- kind=bulletin (E14-T02): evening bulletin of the chronicler; facts = confirmed facts of the day (hex RSV2 list
-- of English sentences, RS_Facts.bulletin); absent = nothing confirmed. A bridge older than E14-T02 ignores it.
-- trade (E13-T02): book of the smuggler for this caller (hex RSV2 table, RS_Trade.field); absent = no trade.
-- reputation (E04-T10): public reputation of this caller (level and last public act); absent = none.
-- story (E20-T08): story state of the voice (a name, RS_VoiceStory); absent = none yet.
-- dead (E22-T13): people this voice knew who died (hex RSV2 list of {name, day, facts}, RS_Memory.deadField);
-- absent = none.
-- recipe (E27-T04): pending recipe search of this caller to this voice (hex RSV2 { ids, ready, keywords },
-- RS_RecipeSearches.field); absent = none.
local RADIO_KEYS = { 'kind', 'caller', 'voice', 'name', 'date', 'days', 'radio', 'text', 'language', 'memory',
    'persona', 'mission', 'jobs', 'facts', 'trade', 'reputation', 'story', 'dead', 'recipe' }

local function radioLines(out, r)
    out[#out + 1] = 'sent=' .. string.format('%.0f', r.sentAt)
    for _, k in ipairs(RADIO_KEYS) do
        if r[k] ~= nil then out[#out + 1] = k .. '=' .. r[k] end
    end
end

T.register('radio', { order = 10, format = radioLines })
T.register('lastPages', { order = 40 })

return T
