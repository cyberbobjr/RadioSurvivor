-- Radio Survivor: action `remember`, what a voice remembers about its callers (E07-T03, E22-T13).
-- Every voice has `remember` without listing it in its sheet (RS_Actions.UNIVERSAL): the bridge always offers it
-- (single parameter `fact`); RS_Actions judges it (catalogue, parameters), then the executor below stores the fact.
-- No game effect: memory only.
-- The memory lives on the authority, in the private state RS_State (S.data.memory, never in global ModData); otherwise
-- (state not loaded yet or blocked) in a table in memory, lost at a server restart, like the counters of RS_Actions.
-- Key: voice + caller + notebook character (ctx.cid when there is one), so that a new character in solo (a single
-- caller key, "solo") does not inherit the memories of the previous one.
-- At each later radio request of the same caller to the same voice, RadioSurvivor_Server joins the facts to the
-- request (field memory=, RSV2 hex of a list of strings, Memory.field); the bridge puts them in the prompt as
-- unverified memories, never as proof (docs/specifications-techniques/protocole-carnet-v2.md, "Memoire des voix").
-- Bounds (RadioSurvivor_Const), without any eviction: at most MEMORY_CALLER_CHARS characters of facts and
-- MEMORY_MAX_FACTS facts per (voice, caller, character); past that a new fact is refused (memory_full, logged) and
-- nothing is forgotten; a fact identical after normalisation (case, spaces) is refreshed, not duplicated;
-- MEMORY_FACT_CHARS characters per fact. No bound on the number of callers: the state grows by at most
-- MEMORY_CALLER_CHARS per character and per voice.
-- Death (E22-T13): CA_Identity.onRetire (RS_NotebookHooks) calls markDead; the memories of the character stay, marked
-- dead (name, game day of the death). They are no longer joined as the memories of a caller (retired filter when
-- read), but every request to a voice carries the dead people it knew (field dead=, Memory.deadField): at most
-- MEMORY_DEAD_MAX, latest deaths first, MEMORY_DEAD_CHARS characters of facts each.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "CoreAI/CA_Codec"
local S = require "RadioSurvivor/RS_State"
local Notebook = require "CoreAI/CA_NotebookStore" -- E21-T04: notebook characters
local Actions = require "RadioSurvivor/RS_Actions"

local Memory = {}

-- No delay between two `remember` of a voice: the delay of RS_Actions is per voice, not per caller, and would refuse
-- the memory of a second caller right after the one of a first. The 3 actions at most per reply and the bounds above
-- limit the writing.
Memory.COOLDOWN_MS = 0

-- Memory used while RS_State is not loaded (see the header).
local volatile = {}

function Memory.resetForTests()
    volatile = {}
end

local function store()
    if S.data and not S.blocked then
        if type(S.data.memory) ~= "table" then S.data.memory = {} end
        return S.data.memory, true
    end
    return volatile, false
end

-- One-line fact: controls and line breaks to spaces, rich text marks removed, spaces reduced, cut at
-- MEMORY_FACT_CHARS (or maxChars: place of RS_PersonaState, name of a dead person); "" when nothing is left.
function Memory.clean(text, maxChars)
    if type(text) ~= "string" then return "" end
    local limit = maxChars or Const.MEMORY_FACT_CHARS
    text = string.gsub(text, "[%c<>%[%]]", " ")
    text = Const.oneLine(string.gsub(text, "%s+", " "))
    if string.len(text) > limit then
        text = Const.oneLine(string.sub(text, 1, limit))
    end
    return text
end

-- Comparison form (duplicates): lower case, spaces already reduced by clean.
local function normal(text)
    return string.lower(text)
end

-- Key of a caller: length of the account key first, so that no account name is mistaken for another (caller,
-- character) pair.
local function keyOf(caller, cid)
    local who = tostring(caller or "?")
    return tostring(string.len(who)) .. ":" .. who .. "/" .. tostring(cid or "-")
end

local function voiceOf(all, voice, create)
    local v = all[voice]
    if type(v) ~= "table" then
        if not create then return nil end
        v = { seq = 0, callers = {} }
        all[voice] = v
    end
    if type(v.callers) ~= "table" then v.callers = {} end
    if type(v.seq) ~= "number" then v.seq = 0 end
    return v
end

-- Character retired at its death (or gone from the state): its memories are no longer read as a caller's.
local function retired(cid)
    if cid == nil or not Notebook.data then return false end
    local record = Notebook.data.characters[cid]
    return type(record) ~= "table" or record.retired == true
end

local function isFact(f)
    return type(f) == "table" and type(f.text) == "string" and f.text ~= ""
end

-- Stores a fact already cleaned. Returns true, or false and "memory_full" when the entry of this caller already holds
-- MEMORY_MAX_FACTS facts or the fact would take it past MEMORY_CALLER_CHARS characters (nothing is evicted; logged).
-- A fact identical after normalisation replaces the old one (refreshed, moved last), its size counted once.
function Memory.add(voice, caller, cid, fact)
    local all, persistent = store()
    local v = voiceOf(all, voice, true)
    local key = keyOf(caller, cid)
    local entry = v.callers[key]
    local wanted = normal(fact)
    local kept, used = {}, 0
    if type(entry) == "table" and type(entry.facts) == "table" then
        for _, f in ipairs(entry.facts) do
            if isFact(f) and normal(f.text) ~= wanted then
                kept[#kept + 1] = f
                used = used + string.len(f.text)
            end
        end
    end
    if #kept >= Const.MEMORY_MAX_FACTS or used + string.len(fact) > Const.MEMORY_CALLER_CHARS then
        Const.log("memory of voice " .. tostring(voice) .. " for caller " .. tostring(caller) .. " ("
            .. tostring(cid or "-") .. ") is full (" .. #kept .. " facts, " .. used .. " characters): fact refused")
        return false, "memory_full"
    end
    if type(entry) ~= "table" then
        entry = { caller = caller, cid = cid }
        v.callers[key] = entry
    end
    v.seq = v.seq + 1
    entry.seq = v.seq
    kept[#kept + 1] = { text = fact, seq = v.seq }
    entry.facts = kept
    if persistent then S.dirty = true end
    return true
end

-- Facts of the caller for this voice, oldest first; empty list when there is none (or its character is dead).
function Memory.facts(voice, caller, cid)
    local out = {}
    if voice == nil or retired(cid) then return out end
    local all = store()
    local v = voiceOf(all, voice, false)
    local entry = v and v.callers[keyOf(caller, cid)]
    if type(entry) ~= "table" or type(entry.facts) ~= "table" then return out end
    for _, f in ipairs(entry.facts) do
        if isFact(f) and #out < Const.MEMORY_MAX_FACTS then out[#out + 1] = f.text end
    end
    return out
end

-- Field memory= of a radio request: RSV2 hex of the list of facts (one line, reversible, size bounded by the bounds
-- above), or nil without any memory (field absent).
function Memory.field(voice, caller, cid)
    local facts = Memory.facts(voice, caller, cid)
    if #facts == 0 then return nil end
    return Codec.hexBytes(Codec.encodeBytes(facts))
end

-- Death of a character (E22-T13): its memories stay in every voice, marked dead with its name (cleaned, at most
-- MEMORY_NAME_CHARS characters) and the game day of the death (YYYY-MM-DD, or nil). A death marked once is kept.
function Memory.markDead(cid, name, day)
    if cid == nil then return end
    local all, persistent = store()
    local marked = false
    local shown = Memory.clean(name, Const.MEMORY_NAME_CHARS)
    for _, v in pairs(all) do
        if type(v) == "table" and type(v.callers) == "table" then
            for _, entry in pairs(v.callers) do
                if type(entry) == "table" and entry.cid == cid and entry.dead == nil then
                    v.seq = (tonumber(v.seq) or 0) + 1
                    entry.dead = { name = shown ~= "" and shown or nil, day = type(day) == "string" and day or nil,
                        seq = v.seq }
                    marked = true
                end
            end
        end
    end
    if marked and persistent then S.dirty = true end
end

-- Facts of one dead person on one line, latest first, joined by "; ", cut at MEMORY_DEAD_CHARS characters.
local function deadFacts(entry)
    local parts = {}
    for i = #entry.facts, 1, -1 do
        local f = entry.facts[i]
        if isFact(f) then parts[#parts + 1] = f.text end
    end
    local text = table.concat(parts, "; ")
    if string.len(text) > Const.MEMORY_DEAD_CHARS then
        text = Const.oneLine(string.sub(text, 1, Const.MEMORY_DEAD_CHARS))
    end
    return text
end

local function laterDeath(a, b)
    return a.seq > b.seq
end

-- Dead people this voice knew: { { name, day, facts } }, latest deaths first, at most MEMORY_DEAD_MAX; name and day
-- absent when unknown; a dead person without any fact is left out.
function Memory.dead(voice)
    local found = {}
    local v = voice ~= nil and voiceOf(store(), voice, false) or nil
    if v == nil then return found end
    for _, entry in pairs(v.callers) do
        if type(entry) == "table" and type(entry.dead) == "table" and type(entry.facts) == "table" then
            local facts = deadFacts(entry)
            if facts ~= "" then
                found[#found + 1] = { seq = tonumber(entry.dead.seq) or 0, name = entry.dead.name,
                    day = entry.dead.day, facts = facts }
            end
        end
    end
    table.sort(found, laterDeath)
    local out = {}
    for i = 1, math.min(#found, Const.MEMORY_DEAD_MAX) do
        local d = found[i]
        out[i] = { name = d.name, day = d.day, facts = d.facts }
    end
    return out
end

-- Field dead= of a radio request: RSV2 hex of Memory.dead(voice), or nil when the voice knew nobody who died.
function Memory.deadField(voice)
    local dead = Memory.dead(voice)
    if #dead == 0 then return nil end
    return Codec.hexBytes(Codec.encodeBytes(dead))
end

-- Single parameter `fact`: a string, not empty once cleaned (RS_Actions already bounds its raw length).
local function validate(params)
    for key in pairs(params) do
        if key ~= "fact" then return false end
    end
    return Memory.clean(params.fact) ~= ""
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or ctx.voice == nil or ctx.caller == nil then return false, "failed" end
    return Memory.add(ctx.voice, ctx.caller, ctx.cid, Memory.clean(params.fact))
end

function Memory.register()
    return Actions.register("remember", { validate = validate, cooldownMs = Memory.COOLDOWN_MS,
        maxParamChars = Const.MEMORY_FACT_CHARS, execute = execute })
end

Memory.register()

return Memory
