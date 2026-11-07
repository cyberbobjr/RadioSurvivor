--[[
RadioSurvivorCore: bounds of the NPC speech (E18-T17), read by Living Knox, which emits the requests, and by
RadioSurvivor (RS_Config: same values, client checks of the notebook, group radio).
]]
local Speech = {
    HEARING_RANGE = 30, -- inspected SayChat default; our policy, not a claim of exact vanilla hearing
    NOISE_RANGE = 15,
    REQUEST_TIMEOUT_MS = 150000,
    COOLDOWN_MS = 10000,
    MAX_PENDING = 8,
    MAX_PER_HOUR = 60,
    ENRICH_PER_HOUR = 12,
    ENRICH_RETRY_MS = 300000,
    ENRICH_MAX_ATTEMPTS = 3,
    NARRATIVE_LANGUAGE = "FR", -- one canonical biography, independent of listener language
    MAX_TEXT_BYTES = 800,
    MAX_REPLY_BYTES = 1600,
}

-- E17-T11: game language code sent to the bridge as a hint (npc_talk). The game names a language after its Translate
-- folder (Language.name(), Languages.loadTranslateDirectory: EN, ES, ES_CL, PTBR, STREW, or a folder added by a mod),
-- so the code is checked by its form only, never against a list of known languages: 2 to 8 characters, ASCII letters
-- and underscores, starting with a letter, upper-cased (Languages.getByName ignores the case). Anything else -> "EN".
-- Same form as LANGUAGE_CODE in bridge/npc_protocol.py.
function Speech.languageCode(value)
    if type(value) ~= "string" then return "EN" end
    local code = string.upper(value)
    if #code < 2 or #code > 8 or not string.match(code, "^[A-Z][A-Z_]+$") then return "EN" end
    return code
end

return Speech
