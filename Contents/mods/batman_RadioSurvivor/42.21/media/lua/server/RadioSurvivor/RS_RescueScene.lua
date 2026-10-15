if isClient() then return end
--[[
Outcome scene of a rescue (E12-T04: "saved"; the "missed" scene is E12-T05). Authority only (dedicated server or
solo). Design choices: docs/conception/secours-issue.md.

Outcome "saved" (decided by RS_RescueVisit: a real delivery was made, then no member of the team is near any more).
RS_Rescue.finish calls Scene.prepare(rec, result) through Rescue.sceneHook, in the same call, on the real record of
the rescue (private state RS_State, or the work store of the in-game suites):
  - cache: a cache record attached to the rescue (RS_Caches.attach: key = rescue id, table drawn from the closed list
    RS_Config.Caches.order by RS_Rescue.drawer(rescue id), spot = site point, bounds = building bounds) with a note
    (rec.cache.note = { name, text }, RS_Caches.makeNote: vanilla sheet of paper, locked) composed now in the language
    of the authority (IGUI_RS_RescueNote_*, English text when the mod translations cannot be read): names of the
    helpers, signature of the requester. Never a coordinate nor a frequency;
  - new place of the voice: a building drawn by RS_Rescue.pick (metagrid only, nothing loaded, far from the known
    bases, excluding the old site and the buildings of the running rescues), kept in rec.moved = { key, kind, label,
    place }; its words (English, town level, Const.PERSONA_PLACE_CHARS characters at most) become the `place` of the
    persona state of the voice (RS_PersonaState.apply: the bridge puts it in the prompt, "Where you say you are"),
    morale raised by CONFIG.MORALE_UP (stepped by RS_PersonaState);
  - memory of the voice on every helper (RS_Memory.add, voice + caller key + notebook character): the voice
    remembers that they came in time and who came with them; the bridge joins these facts to the next radio
    requests of the same caller (field memory=);
  - life log: RS_LifeLog.rescue(cid, 'saved', label) for each helper bound to a notebook character (not in a work
    store, like the fact of the day).
A rescue without voice (rec.voice nil) gets the cache and the note only.
Placement (Scene.poll every CONFIG.POLL_MS real time, OnTickEvenPaused): the cache of every "saved" rescue whose
scene is pending is placed by RS_Caches.place once the site square is loaded and its building has passed its
vanilla stories, once only even after a restart (placing / placed saved with the private state, bag adopted when
found again); then RS_Rescue.scenePlaced closes the scene. Scene.onPlaced(rescue id, cache record) is an optional
single listener.
ASCII only in the code (Kahlua lexer).
]]
local Rescue = require "RadioSurvivor/RS_Rescue"
local Caches = require "RadioSurvivor/RS_Caches"
local Memory = require "RadioSurvivor/RS_Memory"
local PersonaState = require "RadioSurvivor/RS_PersonaState"
local LifeLog = require "RadioSurvivor/RS_LifeLog"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local S = require "RadioSurvivor/RS_State"

local Scene = {}

Scene.CONFIG = {
    POLL_MS = 2000,
    MAX_NAMES = 4,       -- helper names written in the note and in a memory fact
    MORALE_UP = 2,
}

-- English texts when the translations of the mod cannot be read on this machine.
local ENGLISH = {
    IGUI_RS_RescueNote_Item = "A note from %1",
    IGUI_RS_RescueNote_Text = "To %1,\n\nYou came for us in time. We will never forget it.\n\nWe are leaving this "
        .. "place for somewhere safer. We left you what we could spare.\n\nWe will keep listening on the radio.\n\n%2",
    IGUI_RS_RescueNote_Signer = "the people you saved",
    IGUI_RS_RescueNote_Friends = "our friends",
}

-- Memory facts (English, prompt data like the clues; RS_Memory.clean bounds them).
Scene.FACT_SAVED = "Came in time with supplies; we got out thanks to them"
Scene.FACT_WITH = "Came with "
Scene.PLACE_FALLBACK = "somewhere safer, far from the old place"

local nextPoll = 0
local reloaded = false

local function log(msg)
    Const.log("rescue: " .. msg)
end

-- Mod translations on this machine (an MP server does not load them: Translator.loadFiles once, base api-42-21.md).
local function hasText()
    return getTextOrNull ~= nil and getTextOrNull("IGUI_RS_RescueNote_Item", "x") ~= nil
end

local function translated()
    if hasText() then return true end
    if not reloaded and isServer() and Translator ~= nil and Translator.loadFiles ~= nil then
        reloaded = true
        Translator.loadFiles()
        log("mod translations reloaded on the server (rescue note)")
    end
    return hasText()
end

local function tr(key, a, b)
    local t = nil
    if translated() then
        if a == nil then t = getTextOrNull(key) -- no nil argument to the Java overloads
        elseif b == nil then t = getTextOrNull(key, a)
        else t = getTextOrNull(key, a, b) end
    end
    if t ~= nil then return t end
    local args = { a, b }
    return (string.gsub(ENGLISH[key] or key, "%%(%d)", function(d) return tostring(args[tonumber(d)] or "") end))
end

-- Bench and suites: next poll at once, translations checked again.
function Scene.resetForTests()
    nextPoll, reloaded = 0, false
end

-- ---------------------------------------------------------------- helpers

-- Names of the helpers of a rescue (at most CONFIG.MAX_NAMES), in their order.
function Scene.helperNames(rec)
    local out = {}
    for _, h in ipairs(type(rec.helpers) == "table" and rec.helpers or {}) do
        if #out >= Scene.CONFIG.MAX_NAMES then break end
        out[#out + 1] = h.name
    end
    return out
end

-- ---------------------------------------------------------------- note

-- Note left in the cache: { name, text } in the language of the authority.
function Scene.note(rec)
    local names = Scene.helperNames(rec)
    local to = #names > 0 and table.concat(names, ", ") or tr("IGUI_RS_RescueNote_Friends")
    local signer = rec.requester or tr("IGUI_RS_RescueNote_Signer")
    return { name = tr("IGUI_RS_RescueNote_Item", signer), text = tr("IGUI_RS_RescueNote_Text", to, signer) }
end

-- ---------------------------------------------------------------- new place of the voice

local function article(word)
    local c = string.sub(word, 1, 1)
    if c == "a" or c == "e" or c == "i" or c == "o" or c == "u" then return "an " end
    return "a "
end

-- Words of a place (English, no digit, at most Const.PERSONA_PLACE_CHARS characters): building label and town
-- (RS_Rescue.town key and name, vanilla map only), shortened when too long.
function Scene.placeWords(label, townKey, town)
    local max = Const.PERSONA_PLACE_CHARS
    local tail = " out in the country"
    if town ~= nil and townKey == "TownIn" then tail = " in " .. town
    elseif town ~= nil and townKey == "TownOutskirts" then tail = " outside " .. town
    elseif town ~= nil and townKey == "TownCountry" then tail = " out past " .. town end
    local words = article(label) .. label .. tail
    if string.len(words) > max then words = "a place" .. tail end
    if string.len(words) > max then words = Scene.PLACE_FALLBACK end
    return words
end

-- New place of the survivors: a building of the metagrid far from the known bases (RS_Rescue.pick, nothing read
-- nor loaded), other than the old site and the sites of the running rescues. Returns { key, kind, label, place }
-- (place only when no building was found).
function Scene.move(rec)
    local exclude = { [rec.site.key] = true }
    local d = Rescue.store()
    for _, other in pairs(d and d.rescues or {}) do
        if other.state == "active" or other.scene == "pending" then exclude[other.site.key] = true end
    end
    local site, why = Rescue.pick({ seed = rec.id .. "|moved", exclude = exclude, noClues = true })
    if not site then
        log(rec.id .. ": no new place found for the survivors (" .. tostring(why) .. ")")
        return { place = Scene.PLACE_FALLBACK }
    end
    local _, key, town = Rescue.town((site.bounds.x1 + site.bounds.x2) / 2, (site.bounds.y1 + site.bounds.y2) / 2)
    return { key = site.key, kind = site.kind, label = site.label, place = Scene.placeWords(site.label, key, town) }
end

-- ---------------------------------------------------------------- memory of the voice

-- Facts the voice keeps on one helper: saved in time, and the others who came (when there are).
function Scene.facts(rec, helper)
    local out = { Scene.FACT_SAVED }
    local others = {}
    for _, name in ipairs(Scene.helperNames(rec)) do
        if name ~= helper.name then others[#others + 1] = name end
    end
    if #others > 0 then out[#out + 1] = Scene.FACT_WITH .. table.concat(others, ", ") end
    return out
end

function Scene.remember(rec)
    local n = 0
    for _, h in ipairs(type(rec.helpers) == "table" and rec.helpers or {}) do
        for _, fact in ipairs(Scene.facts(rec, h)) do
            local text = Memory.clean(fact)
            if text ~= "" then Memory.add(rec.voice, h.caller, h.cid, text) end
        end
        n = n + 1
    end
    return n
end

-- ---------------------------------------------------------------- outcome

-- Rescue.sceneHook: prepares the scene of an outcome on the real record of the rescue (see the header).
function Scene.prepare(rec, result)
    if result ~= "saved" or type(rec) ~= "table" or type(rec.site) ~= "table" then return false end
    local tableName = Caches.drawTable(Rescue.drawer(rec.id))
    local cache, why = Caches.attach(rec, tableName, { x = rec.site.x, y = rec.site.y, z = rec.site.z or 0 },
        rec.site.bounds)
    if cache then
        cache.note = Scene.note(rec)
    else
        log(rec.id .. ": no cache for the saved survivors (" .. tostring(why) .. ")")
    end
    rec.moved = Scene.move(rec)
    local remembered = 0
    if type(rec.voice) == "string" then
        local current = PersonaState.get(rec.voice)
        local morale = (current and current.morale or Const.PERSONA_LEVEL_DEFAULT) + Scene.CONFIG.MORALE_UP
        PersonaState.apply(rec.voice, { place = rec.moved.place, morale = morale })
        remembered = Scene.remember(rec)
    end
    if not Rescue.isWorkStore() then
        local label = rec.requester or rec.site.label
        for _, h in ipairs(type(rec.helpers) == "table" and rec.helpers or {}) do
            if h.cid then LifeLog.rescue(h.cid, "saved", label) end
        end
    end
    log(rec.id .. ": survivors saved, cache " .. tostring(cache and cache.table) .. " to place, moved to "
        .. tostring(rec.moved.key or "nowhere known") .. ", " .. remembered .. " helper(s) remembered by "
        .. tostring(rec.voice or "no voice"))
    return true
end

-- ---------------------------------------------------------------- placement

local WORK_SAVER = { save = function() return true end }

-- Pending scenes of saved rescues: cache placed when the site is loaded (see the header). force: ignore the
-- spacing. Returns true when a scene was placed.
function Scene.poll(force)
    local now = getTimestampMs()
    if not force and now < nextPoll then return false end
    nextPoll = now + Scene.CONFIG.POLL_MS
    local d = Rescue.store()
    if not d then return false end
    local ids = {}
    for id, rec in pairs(d.rescues) do
        if rec.scene == "pending" and rec.state == "saved" and type(rec.cache) == "table" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local saver = Rescue.isWorkStore() and WORK_SAVER or S
    local changed = false
    for _, id in ipairs(ids) do
        local rec = d.rescues[id]
        if not rec.cache.placed then Caches.place(saver, rec.cache) end
        if rec.cache.placed and Rescue.scenePlaced(id) then
            changed = true
            log(id .. ": scene of the saved survivors placed (cache " .. tostring(rec.cache.itemId) .. ")")
            if Scene.onPlaced then Scene.onPlaced(id, rec.cache) end
        end
    end
    return changed
end

RS_RescueScene = Scene
Rescue.sceneHook = function(rec, result) return RS_RescueScene.prepare(rec, result) end
if not RS_RescueSceneHooked and Events and Events.OnTickEvenPaused then
    RS_RescueSceneHooked = true
    Events.OnTickEvenPaused.Add(function() RS_RescueScene.poll(false) end)
end

return Scene
