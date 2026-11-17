if isClient() then return end
--[[
RadioSurvivor: recipe searches kept by the authority (E27-T04, ADR recettes-radio D04, D07). A voice whose [help] has a
delay looks through its notes before answering: the bridge returns the recipes it found as "searched" (radio_reply),
the server keeps them until the caller calls back once the game time has come.

- ONE search per notebook character and per voice: a new one replaces the old (D07); no expiry; cleared once
  delivered (RS_RecipeHelp), forgotten when the character dies (RS_NotebookHooks).
- Storage: private state of the voices (RS_State: S.data.recipeSearches[cid][voice] = { ids, keywords, readyAt }),
  readyAt in world hours (GameTime.getWorldAgeHours), never global ModData.
- Delays are data: DELAY_HOURS (voice [help] delay=, RS_Persona; the bridge words the same names, recipe_delay.py).
- Field recipe= of a radio request: hex RSV2 of { ids, ready, keywords } (protocole-carnet-v2.md, "Recette demandee").
Authority only. Console messages in English.
]]
local S = require 'RadioSurvivor/RS_State'
local Codec = require 'CoreAI/CA_Codec'

local Searches = {}

-- Game hours of each delay of a voice [help] (ADR D04: now, one hour, half a day, a day).
Searches.DELAY_HOURS = { now = 0, hour = 1, half_day = 12, day = 24 }
Searches.MAX_IDS = 8
Searches.MAX_KEYWORDS = 4
Searches.ID_CHARS = 128
Searches.KEYWORD_CHARS = 40

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

local function all(create)
    if not S.data or S.blocked then return nil end
    if type(S.data.recipeSearches) ~= 'table' then
        if not create then return nil end
        S.data.recipeSearches = {}
    end
    return S.data.recipeSearches
end

-- Strings of a list sent by the bridge, bounded; nil when it is not such a list.
local function strings(list, max, chars)
    if list == nil then return {} end
    if type(list) ~= 'table' or #list > max then return nil end
    local out = {}
    for _, value in ipairs(list) do
        if type(value) ~= 'string' or value == '' or #value > chars then return nil end
        out[#out + 1] = value
    end
    return out
end

-- Keeps the search { ids, keywords } of this character to this voice, ready after the hours of `delay`. False when
-- refused (no character, state unavailable, malformed search).
function Searches.store(cid, voice, delay, searched)
    if type(cid) ~= 'string' or type(voice) ~= 'string' or type(searched) ~= 'table' then return false end
    local ids = strings(searched.ids, Searches.MAX_IDS, Searches.ID_CHARS)
    local keywords = strings(searched.keywords, Searches.MAX_KEYWORDS, Searches.KEYWORD_CHARS)
    local store = all(true)
    if not ids or not keywords or not store then return false end
    store[cid] = store[cid] or {}
    store[cid][voice] = { ids = ids, keywords = keywords,
        readyAt = worldHours() + (Searches.DELAY_HOURS[delay] or 0) }
    S.dirty = true
    return true
end

-- Pending search of this character to this voice, or nil.
function Searches.pending(cid, voice)
    local store = all(false)
    local mine = store and store[cid]
    return mine and mine[voice] or nil
end

-- Field recipe= of a request of this character to this voice and whether it is ready; nil without a search.
function Searches.field(cid, voice)
    local search = Searches.pending(cid, voice)
    if not search then return nil, false end
    local ready = worldHours() >= search.readyAt
    return Codec.hexBytes(Codec.encodeBytes({ ids = search.ids, ready = ready, keywords = search.keywords })), ready
end

function Searches.clear(cid, voice)
    local store = all(false)
    if store and store[cid] and store[cid][voice] then
        store[cid][voice] = nil
        local left = 0
        for _ in pairs(store[cid]) do left = left + 1 end -- no next() in Kahlua
        if left == 0 then store[cid] = nil end
        S.dirty = true
    end
end

-- A dead character's searches are forgotten (CA_Identity.onRetire, RS_NotebookHooks).
function Searches.forget(cid)
    local store = all(false)
    if store and store[cid] ~= nil then
        store[cid], S.dirty = nil, true
    end
end

return Searches
