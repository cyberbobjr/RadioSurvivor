if isClient() then return end
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Codec = require 'RadioSurvivor/RS_Codec'
local T = {radio = {}, npc = {}, acks = {}, session = 'initializing', generation = 0}
-- lastPages (E15-T03): kind=last_pages requests of RS_LastPages (RSV2 payload, same lines as the NPC kinds).
T.lastPages = {}

-- One writer for Walt and the carnet; Python remains one process and one lock.
function T.write()
    T.generation = T.generation + 1
    local out = {'protocol=2', 'session=' .. T.session, 'generation=' .. T.generation}
    for _, r in ipairs(T.radio) do
        out[#out + 1] = 'req=' .. r.id
        out[#out + 1] = 'sent=' .. string.format('%.0f', r.sentAt)
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
        for _, k in ipairs({'kind', 'caller', 'voice', 'name', 'date', 'days', 'radio', 'text', 'language', 'memory',
                'persona', 'mission', 'facts', 'trade', 'reputation'}) do
            if r[k] ~= nil then out[#out + 1] = k .. '=' .. r[k] end
        end
    end
    for _, list in ipairs({T.npc, T.acks, T.lastPages}) do
        for _, r in ipairs(list) do
            out[#out + 1] = 'req=' .. r.id
            out[#out + 1] = 'kind=' .. r.kind
            out[#out + 1] = 'payload=' .. Codec.hexBytes(Codec.encodeBytes(r))
        end
    end
    out[#out + 1] = 'commit=' .. T.generation
    out[#out + 1] = 'end'
    local writer = getFileWriter(Const.REQUESTS_FILE, true, false)
    if not writer then return false end
    writer:write(table.concat(out, '\n') .. '\n')
    writer:close()
    return true
end

function T.setRadio(pending, session)
    T.radio, T.session = pending, session
    return T.write()
end

function T.readNpc()
    local reader = getFileReader(Const.RESPONSES_FILE, false)
    if not reader then return nil end
    local answers, current, bytes, complete = {}, nil, 0, false
    local line = reader:readLine()
    while line do
        bytes = bytes + #line
        if bytes > 1048576 then break end
        if line == 'end' then complete = true; break end
        local k, v = line:match('^(%a+)=(.*)$')
        if k == 'resp' then current = v end
        if k == 'payload' and current then
            local raw = Codec.unhexBytes(v)
            local decoded = raw and Codec.decodeBytes(raw)
            if type(decoded) == 'table' and decoded.id == current then answers[current] = decoded end
        end
        line = reader:readLine()
    end
    reader:close()
    return complete and answers or nil
end

return T
