if isClient() then return end
--[[
RadioSurvivor: its lanes in the queue of the core mod (E18-T04, RadioSurvivorCore/RC_Transport). Returns the
transport. Order of the requests file kept from RS_Transport: radio, npc, acks, lastPages.
- radio: requests of the radio voices (RadioSurvivor_Server.lua), written as key=value lines (format below);
- npc: notebook and NPC requests (RS_Carnet_Server: talk, enrich, member, initiative, conversation, incident...);
- acks: acknowledgements of applied answers; lastPages (E15-T03): kind=last_pages requests of RS_LastPages.
Every lane but radio is written as RSV2 (kind=, payload=). Caps stay in RadioSurvivor (decision of 2026-11-05).
]]
local T = require "RadioSurvivorCore/RC_Transport"

-- voice (E05-T03): id of the voice sheet chosen by the frequency; absent = walt for the bridge.
-- kind=radio_call (E05-T05): spontaneous call of the voice, with voice, date and language only; a bridge
-- older than E05-T05 ignores it (unknown kind) and the server airs the fixed call_text after its delay.
-- memory (E07-T03): facts the voice remembers about this caller (hex RSV2 list, RS_Memory.field); absent = none.
-- persona (E07-T06): dynamic state of the voice (hex RSV2 table, RS_PersonaState.field); absent = never changed.
-- mission (E11-T08): mission of this voice for this caller (hex RSV2 table, RS_MissionVoice.field); absent = none.
-- kind=bulletin (E14-T02): evening bulletin of the chronicler; facts = confirmed facts of the day (hex RSV2 list
-- of English sentences, RS_Facts.bulletin); absent = nothing confirmed. A bridge older than E14-T02 ignores it.
-- trade (E13-T02): book of the smuggler for this caller (hex RSV2 table, RS_Trade.field); absent = no trade.
-- reputation (E04-T10): public reputation of this caller (level and last public act); absent = none.
local RADIO_KEYS = { 'kind', 'caller', 'voice', 'name', 'date', 'days', 'radio', 'text', 'language', 'memory',
    'persona', 'mission', 'facts', 'trade', 'reputation' }

local function radioLines(out, r)
    out[#out + 1] = 'sent=' .. string.format('%.0f', r.sentAt)
    for _, k in ipairs(RADIO_KEYS) do
        if r[k] ~= nil then out[#out + 1] = k .. '=' .. r[k] end
    end
end

T.register('radio', { order = 10, format = radioLines })
T.register('npc', { order = 20 })
T.register('acks', { order = 30 })
T.register('lastPages', { order = 40 })

return T
