-- Radio Survivor: bond between a radio voice and a notebook character (E07-T10, decision of the user, 2026-10-18).
--
-- A voice gives the frequency of another voice (action share_frequency) only exceptionally: the model proposes it when
-- the caller negotiated, earned strong trust or truly persuaded the voice; the server only lets it happen when the
-- character has a real bond with that voice and not too often:
--   - bond: at least MIN_ANSWERS answers of this voice to this character, over at least MIN_DAYS different game days,
--     or a good reputation of the character (RS_Reputation level 'good');
--   - rarity: once per VOICE_DAYS game days for one voice and one character, once per CHARACTER_DAYS game days for one
--     character, all voices together.
-- Counters in the private state of the voices (RS_State: S.data.voiceBonds[cid] = { voices = { [voice] = bond },
-- lastShareDay }, never global ModData), for a living notebook character (CA_NotebookStore), forgotten when it dies
-- (B.forget, RS_NotebookHooks). Authority only. Console messages in English.
if isClient() then return end

local S = require "RadioSurvivor/RS_State"
local Notebook = require "CoreAI/CA_NotebookStore"
local Rep = require "CoreAI/CA_Reputation"

local B = {}
B.MIN_ANSWERS = 4
B.MIN_DAYS = 2
B.VOICE_DAYS = 7
B.CHARACTER_DAYS = 3

-- Bonds of a living notebook character (created when asked), or nil.
local function record(cid, create)
    local chars = Notebook.data and Notebook.data.characters or nil
    local character = type(cid) == "string" and chars and chars[cid] or nil
    if type(character) ~= "table" or character.retired or not S.data or S.blocked then return nil end
    if type(S.data.voiceBonds) ~= "table" then S.data.voiceBonds = {} end
    local rec = S.data.voiceBonds[cid]
    if not rec then
        rec = { voices = {} }
        if create then S.data.voiceBonds[cid] = rec end
    end
    return rec
end

local function bondOf(rec, voice, create)
    local bond = rec.voices[voice]
    if not bond and create then
        bond = { answers = 0, days = 0 }
        rec.voices[voice] = bond
    end
    return bond
end

-- An answer of this voice to this character went on the air (RadioSurvivor_Server, not a briefing).
function B.answered(cid, voice)
    local rec = record(cid, true)
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
    local trusted = (bond.answers >= B.MIN_ANSWERS and bond.days >= B.MIN_DAYS) or Rep.level(cid) == "good"
    if not trusted then return false, "not_trusted" end
    if type(bond.sharedDay) == "number" and day - bond.sharedDay < B.VOICE_DAYS then return false, "voice_too_soon" end
    if type(rec.lastShareDay) == "number" and day - rec.lastShareDay < B.CHARACTER_DAYS then return false, "too_soon" end
    return true
end

-- A frequency was given by this voice to this character.
function B.shared(cid, voice)
    local rec = record(cid, true)
    local day = Rep.today()
    if not rec or type(voice) ~= "string" or not day then return false end
    bondOf(rec, voice, true).sharedDay = day
    rec.lastShareDay = day
    S.dirty = true
    return true
end

-- A dead character's bonds are forgotten (CA_Identity.onRetire, RS_NotebookHooks).
function B.forget(cid)
    if S.data and type(S.data.voiceBonds) == "table" and S.data.voiceBonds[cid] ~= nil then
        S.data.voiceBonds[cid], S.dirty = nil, true
    end
end

return B
