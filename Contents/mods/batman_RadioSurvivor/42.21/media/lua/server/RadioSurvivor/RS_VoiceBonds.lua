-- Radio Survivor: bond between a radio voice and a notebook character (E07-T10, decision of the user, 2026-10-18).
--
-- A voice gives the frequency of another voice (action share_frequency) only exceptionally: the model proposes it when
-- the caller negotiated, earned strong trust or truly persuaded the voice; the server only lets it happen when the
-- character has a real bond with that voice and not too often:
--   - bond: at least MIN_ANSWERS answers of this voice to this character, over at least MIN_DAYS different game days,
--     or a good reputation of the character (RS_Reputation level 'good');
--   - rarity: once per VOICE_DAYS game days for one voice and one character, once per CHARACTER_DAYS game days for one
--     character, all voices together.
-- Counters in the private state of the notebook (record.voiceBonds, record.lastShareDay; RS_State, never global
-- ModData), kept with the character and dropped with it. Authority only. Console messages in English.
if isClient() then return end

local S = require "RadioSurvivor/RS_State"
local Rep = require "RadioSurvivor/RS_Reputation"

local B = {}
B.MIN_ANSWERS = 4
B.MIN_DAYS = 2
B.VOICE_DAYS = 7
B.CHARACTER_DAYS = 3

local function record(cid)
    local chars = S.data and not S.blocked and S.data.characters or nil
    local rec = type(cid) == "string" and chars and chars[cid] or nil
    if type(rec) ~= "table" or rec.retired then return nil end
    return rec
end

local function bondOf(rec, voice, create)
    if type(rec.voiceBonds) ~= "table" then
        if not create then return nil end
        rec.voiceBonds = {}
    end
    local bond = rec.voiceBonds[voice]
    if not bond and create then
        bond = { answers = 0, days = 0 }
        rec.voiceBonds[voice] = bond
    end
    return bond
end

-- An answer of this voice to this character went on the air (RadioSurvivor_Server, not a briefing).
function B.answered(cid, voice)
    local rec = record(cid)
    local day = Rep.today()
    if not rec or type(voice) ~= "string" or not day then return false end
    local bond = bondOf(rec, voice, true)
    bond.answers = bond.answers + 1
    if bond.lastDay ~= day then
        bond.days = bond.days + 1
        bond.lastDay = day
    end
    S.dirty = true
    return true
end

-- May this voice share a frequency with this character now? true, or false and the reason (action log):
-- 'no_character', 'not_trusted', 'voice_too_soon', 'too_soon'.
function B.allowed(cid, voice)
    local rec = record(cid)
    local day = Rep.today()
    if not rec or type(voice) ~= "string" or not day then return false, "no_character" end
    local bond = bondOf(rec, voice, false) or { answers = 0, days = 0 }
    local trusted = (bond.answers >= B.MIN_ANSWERS and bond.days >= B.MIN_DAYS) or Rep.level(cid, S.data) == "good"
    if not trusted then return false, "not_trusted" end
    if type(bond.sharedDay) == "number" and day - bond.sharedDay < B.VOICE_DAYS then return false, "voice_too_soon" end
    if type(rec.lastShareDay) == "number" and day - rec.lastShareDay < B.CHARACTER_DAYS then return false, "too_soon" end
    return true
end

-- A frequency was given by this voice to this character.
function B.shared(cid, voice)
    local rec = record(cid)
    local day = Rep.today()
    if not rec or type(voice) ~= "string" or not day then return false end
    bondOf(rec, voice, true).sharedDay = day
    rec.lastShareDay = day
    S.dirty = true
    return true
end

return B
