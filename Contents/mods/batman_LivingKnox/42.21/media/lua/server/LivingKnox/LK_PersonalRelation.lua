if isClient() then return end
--[==[
Living Knox: personal relation of an NPC toward a player character (E09-T04, kept by Living Knox since E18-T21,
decision confirmed by default on 2026-11-06; moved from RadioSurvivor's RS_Relations, rules unchanged). Authority
only. Design: docs/annexes/conception/relations.md. Decision of 2026-10-13: personal gap bounded to one level above
or below the attitude of the NPC's group.

Key: Living Knox NPC id ('lk-<n>') + character id (identity of the core mod, RC_Identity; = LK_Hostility.keyOf).
Shown level = level of the group attitude (LivingKnox.API.attitude, 5 levels of E09-T01) moved by the personal gap
(-1, 0, +1), clamped to hostile..trusting. Without a group basis the level starts from the start attitude of the
group type (hostile, else cautious). Trend (E09-T01 rule): sign of the sum of the senses of the three last relation
facts, group facts and personal changes merged by game day (group facts first on the same day); without any personal
change, the trend of the group. This module never recalculates the group attitude.

A change happens only through R.apply, called with a direction (up, down) and the short id of a REAL fact this NPC
knows, offered in the request (R.offer). The server checks again at the reply: same relation revision, fact still
known to this NPC and never used for a change of this relation, direction consistent with the nature of the fact,
gap within -1..+1. A sentence alone proves nothing (ADR B11, B15).
Citable facts (all with a known nature):
  group     facts of LK_Hostility of the NPC's group toward the character (seen by a member or attributable):
            'att:<group>:<n>', sign of the fact (Living Knox);
  extra     facts the caller knows and passes in `extra` (same list at the offer and at the reply), each
            { key, fact, sign = 1 | -1, day (or nil), source, kind (or nil) }: RadioSurvivor's notebook adds the
            observations this NPC saw ('obs:<key>', source 'seen') and the closed missions of this NPC the character
            took part in ('mis:<id>', source 'mission'). Golden rule of 2026-11-06: each mod brings its own context.

Private state, two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_LivingKnox/personal-relations-<hex of
"mode/world">-<0|1>.txt, header LKPREL1, never a global ModData:
  data = { relations = { [npc id] = { [character] = { gap = -1..1, revision = n,
           changes = { { sign, day, fact, what }, ... } (TREND_FACTS last), used = { fact key, ... } (MAX_USED last,
           oldest first) } } } }
No hand-over of games saved before the split (user decision of 2026-11-06: the mod was never published, every
game starts from scratch). Purge (R.prune, at start, every game day and at the
death of a character): relations of NPCs gone from the Living Knox registry and of retired characters.
Console messages in English.
]==]
local SlotFile = require "RadioSurvivorCore/RC_SlotFile"
local Identity = require "RadioSurvivorCore/RC_Identity"
local WorldStart = require "RadioSurvivorCore/RC_WorldStart"
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Hostility"

local R = LivingKnox.PersonalRelation or {}
LivingKnox.PersonalRelation = R

R.DIR = "batman_LivingKnox/"
R.HEADER = "LKPREL1"
R.LEVELS = {"hostile", "wary", "cautious", "favorable", "trusting"}
R.GAP_MAX = 1          -- decision 2026-10-13: one level above or below the group
R.TREND_FACTS = 3      -- decision E09-T01
R.MAX_USED = 64        -- fact keys kept per relation (a citable fact is far more recent)
R.MAX_CITABLE = 8      -- facts offered to the model per request (the most recent)
R.PANEL_FACTS = 3
R.store = R.store or {seq = 0, base = nil, blocked = false}

local RANK = {}
for i, level in ipairs(R.LEVELS) do RANK[level] = i end

local function log(msg) print("[LivingKnox] personal relations: " .. tostring(msg)) end

local function fresh() return {relations = {}} end

-- Storage ---------------------------------------------------------------------------------------------------------

function R.init(newWorld)
    local st = R.store
    if R.data ~= nil or st.blocked then return R.data ~= nil end
    st.base = SlotFile.worldBase(R.DIR, "personal-relations")
    if WorldStart.isNewWorld(newWorld == true) then
        R.data, st.seq = fresh(), 0
        return R.save()
    end
    local best, broken = SlotFile.read(st.base, R.HEADER)
    if best == nil then
        if broken then
            st.blocked = true
            log("STORAGE BLOCKED: file unreadable, kept as is; relations are not saved this session")
            return false
        end
        R.data, st.seq = fresh(), 0
        return true
    end
    local data = best.data
    if type(data.relations) ~= "table" then
        st.blocked = true
        log("STORAGE BLOCKED: file without relations, kept as is")
        return false
    end
    R.data, st.seq = data, best.seq
    return true
end

-- True when the state is loaded (loaded now if the world exists and OnInitGlobalModData was missed).
function R.ensure()
    if R.data ~= nil then return true end
    if R.store.blocked or getWorld == nil or getWorld() == nil then return false end
    return R.init(false)
end

function R.save()
    local st = R.store
    if R.data == nil or st.blocked then return false end
    local ok, why = SlotFile.write(st.base, R.HEADER, st.seq + 1, R.data)
    if not ok then
        log("ERROR not saved: " .. tostring(why))
        return false
    end
    st.seq = st.seq + 1
    return true
end

-- Tests only: replaces the state in memory (nil: read again from the files at the next call).
function R.useData(data)
    R.data = data
    R.store.blocked = false
end

local function validNpc(id) return type(id) == "string" and string.match(id, "^lk%-%d+$") ~= nil end

local function pairOf(npcId, character, create)
    if not R.ensure() or not validNpc(npcId) or type(character) ~= "string" then return nil end
    local all = R.data.relations
    local byNpc = all[npcId]
    if type(byNpc) ~= "table" then
        if not create then return nil end
        byNpc = {}
        all[npcId] = byNpc
    end
    local p = byNpc[character]
    if type(p) ~= "table" then
        if not create then return nil end
        p = {gap = 0, revision = 0, changes = {}, used = {}}
        byNpc[character] = p
    end
    return p
end

-- Reading ---------------------------------------------------------------------------------------------------------

-- Current game day (1 = first day), 1 without a clock.
function R.today()
    local gt = getGameTime and getGameTime()
    if not gt then return 1 end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return 1 end
    return math.floor(hours / 24) + 1
end

local function groupOf(npcId)
    local G = LivingKnox.Groups
    if not validNpc(npcId) or not G or not G.ensure() then return nil end
    local gid = G.findNpc(npcId)
    if not gid then return nil end
    return G.state.data.groups[gid], gid
end

-- Group basis: { level, trend, facts = { { key, fact, sign, day }, ... }, known = true when it comes from the group
-- attitude (false: default level without any group basis) }.
function R.base(npcId, character)
    local g, gid = groupOf(npcId)
    local API, H = LivingKnox.API, LivingKnox.Hostility
    if gid and API and H.validPlayerKey(character) then
        local attitude = API.attitude(gid, character)
        if attitude and RANK[attitude.level] then
            local trend = attitude.trend
            if trend ~= "up" and trend ~= "down" then trend = "stable" end
            local facts = {}
            for _, f in ipairs(API.attitudeFacts(gid, character) or {}) do
                facts[#facts + 1] = {key = "att:" .. gid .. ":" .. string.format("%.0f", f.n), fact = f.fact,
                    sign = f.sign, day = f.day}
            end
            return {level = attitude.level, trend = trend, facts = facts, known = true}
        end
    end
    local hostile = g ~= nil and H.levelOf(H.startFor(g.type)) == "hostile"
    return {level = hostile and "hostile" or "cautious", trend = "stable", facts = {}, known = false}
end

local function trendOf(base, p)
    if not p or #p.changes == 0 then return base.trend end
    local list = {}
    for i, f in ipairs(base.facts) do
        if type(f.day) == "number" then list[#list + 1] = {sign = f.sign, day = f.day, order = 0, i = i} end
    end
    for i, c in ipairs(p.changes) do list[#list + 1] = {sign = c.sign, day = c.day, order = 1, i = i} end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        if a.order ~= b.order then return a.order < b.order end
        return a.i < b.i
    end)
    local s = 0
    for i = math.max(1, #list - R.TREND_FACTS + 1), #list do s = s + list[i].sign end
    if s > 0 then return "up" end
    if s < 0 then return "down" end
    return "stable"
end

local function shown(base, p)
    local rank = math.max(1, math.min(#R.LEVELS, RANK[base.level] + (p and p.gap or 0)))
    return R.LEVELS[rank], trendOf(base, p)
end

-- Relation shown for this NPC and character: { level, trend, group = level of the group } (labels only, never the
-- gap nor a number). Read only.
function R.view(npcId, character)
    local base = R.base(npcId, character)
    local level, trend = shown(base, pairOf(npcId, character, false))
    return {level = level, trend = trend, group = base.level}
end

local function isUsed(p, key)
    for _, k in ipairs(p and p.used or {}) do if k == key then return true end end
    return false
end

-- Real facts this NPC knows about the character, never used for a change of this relation, oldest first:
-- { { key, fact, sign, day (or nil), source = 'group' | source of the extra fact, kind }, ... }. Read only.
function R.facts(npcId, character, extra)
    local p = pairOf(npcId, character, false)
    local out = {}
    local function add(f)
        if type(f.key) == "string" and (f.sign == 1 or f.sign == -1) and not isUsed(p, f.key) then
            out[#out + 1] = f
        end
    end
    for _, f in ipairs(R.base(npcId, character).facts) do
        add({key = f.key, fact = f.fact, sign = f.sign, day = f.day, source = "group"})
    end
    for _, f in ipairs(type(extra) == "table" and extra or {}) do
        if type(f) == "table" and type(f.fact) == "string" and type(f.source) == "string" and f.source ~= "group" then
            add({key = f.key, fact = f.fact, sign = f.sign, day = type(f.day) == "number" and f.day or nil,
                source = f.source, kind = f.kind})
        end
    end
    return out
end

-- Context of a request (context.relation) and its server binding (nil without citable fact):
-- context = { level, trend, group, facts = { { id = 'f<i>', fact, nature = 'good' | 'bad', source, day, kind } } }
-- (short ids only; no key, no number but the game day); binding = { character, revision, ids = { ['f<i>'] = key } }.
-- Only the directions the gap still allows are offered (gap +1: no good fact; gap -1: no bad fact).
function R.offer(npcId, character, extra)
    local view = R.view(npcId, character)
    local p = pairOf(npcId, character, false)
    local gap = p and p.gap or 0
    local list = {}
    for _, f in ipairs(R.facts(npcId, character, extra)) do
        if (f.sign > 0 and gap < R.GAP_MAX) or (f.sign < 0 and gap > -R.GAP_MAX) then list[#list + 1] = f end
    end
    while #list > R.MAX_CITABLE do table.remove(list, 1) end
    local context = {level = view.level, trend = view.trend, group = view.group, facts = {}}
    if #list == 0 then return context, nil end
    local binding = {character = character, revision = p and p.revision or 0, ids = {}}
    for i, f in ipairs(list) do
        local id = "f" .. i
        context.facts[i] = {id = id, fact = f.fact, nature = f.sign > 0 and "good" or "bad", source = f.source,
            day = f.day, kind = f.kind}
        binding.ids[id] = f.key
    end
    return context, binding
end

local function living(character)
    local record = Identity.record(character)
    return record ~= nil and not record.retired
end

-- Applies a change of the relation cited by the model (extra: same list as at the offer). Returns the new view and
-- the fact key, or nil and the reason (English).
function R.apply(npcId, character, binding, dir, factId, extra)
    if type(binding) ~= "table" then return nil, "no relation fact offered in the request" end
    if binding.character ~= character or not living(character) then return nil, "relation target changed" end
    if dir ~= "up" and dir ~= "down" then return nil, "bad relation direction" end
    local key = type(factId) == "string" and binding.ids[factId] or nil
    if not key then return nil, "relation fact not offered" end
    local p = pairOf(npcId, character, false)
    if (p and p.revision or 0) ~= binding.revision then return nil, "relation revision changed" end
    if isUsed(p, key) then return nil, "relation fact already used" end
    local fact
    for _, f in ipairs(R.facts(npcId, character, extra)) do if f.key == key then fact = f end end
    if not fact then return nil, "relation fact unknown to this NPC" end
    local sign = dir == "up" and 1 or -1
    if fact.sign ~= sign then return nil, "relation direction contradicts the fact" end
    local gap = p and p.gap or 0
    if gap + sign > R.GAP_MAX or gap + sign < -R.GAP_MAX then return nil, "relation gap at its bound" end
    p = pairOf(npcId, character, true)
    if not p then return nil, "relation storage unavailable" end
    p.gap, p.revision = gap + sign, p.revision + 1
    -- what: nature id of the fact (E09-T07: shown by the notebook panel, translated on the client).
    p.changes[#p.changes + 1] = {sign = sign, day = R.today(), fact = key, what = fact.fact}
    while #p.changes > R.TREND_FACTS do table.remove(p.changes, 1) end
    p.used[#p.used + 1] = key
    while #p.used > R.MAX_USED do table.remove(p.used, 1) end
    R.save()
    return R.view(npcId, character), key
end

-- Relations of NPCs gone from the registry and of retired characters dropped. Returns true when something was
-- removed. A registry or an identity registry that is not ready removes nothing.
function R.prune()
    if not R.ensure() then return false end
    local S = LivingKnox.Store
    local registry = S and S.isReady() and S.data() or nil
    local identities = Identity.ensure()
    local removed, doomed = false, {}
    for npcId, byNpc in pairs(R.data.relations) do
        if type(byNpc) ~= "table" or (registry and not registry.npcs[npcId]) then doomed[#doomed + 1] = npcId
        elseif identities then
            local gone = {}
            for character in pairs(byNpc) do
                if not living(character) then gone[#gone + 1] = character end
            end
            for _, character in ipairs(gone) do byNpc[character] = nil; removed = true end
        end
    end
    for _, npcId in ipairs(doomed) do R.data.relations[npcId] = nil; removed = true end
    if removed then R.save() end
    return removed
end

-- Relations of one NPC dropped (in-game test fixtures, server diagnostic). Returns true when something was removed.
function R.forget(npcId)
    if not R.ensure() or R.data.relations[npcId] == nil then return false end
    R.data.relations[npcId] = nil
    R.save()
    return true
end

-- Panel of a contact (E09-T07), for ONE character. Identifiers and game days only, translated by the reader; no gap,
-- no attitude value, no fact key:
--   { level = one of LEVELS or nil (nothing known: no group basis and no personal change), trend, group = level of
--     the group (nil without group basis), today = game day,
--     facts = { { fact = nature id, nature = 'good' | 'bad' | 'neutral', source = 'group' | 'personal', day }, ... }
--             (PANEL_FACTS last ones, oldest first, merged by game day as for the trend) }.
local function natureOf(sign)
    if sign == 1 then return "good" end
    if sign == -1 then return "bad" end
    return "neutral"
end

local function panelFacts(base, p)
    local list = {}
    for i, f in ipairs(base.facts or {}) do
        if type(f.fact) == "string" and type(f.day) == "number" then
            list[#list + 1] = {fact = f.fact, nature = natureOf(f.sign), source = "group", day = f.day, order = 0, i = i}
        end
    end
    for i, c in ipairs(p and p.changes or {}) do
        if type(c.day) == "number" then
            list[#list + 1] = {fact = type(c.what) == "string" and c.what or "other", nature = natureOf(c.sign),
                source = "personal", day = c.day, order = 1, i = i}
        end
    end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        if a.order ~= b.order then return a.order < b.order end
        return a.i < b.i
    end)
    local out = {}
    for i = math.max(1, #list - R.PANEL_FACTS + 1), #list do
        local f = list[i]
        out[#out + 1] = {fact = f.fact, nature = f.nature, source = f.source, day = f.day}
    end
    return out
end

function R.panel(npcId, character)
    local base = R.base(npcId, character)
    local p = pairOf(npcId, character, false)
    local level, trend = shown(base, p)
    local known = base.known or (p ~= nil and #p.changes > 0)
    return {level = known and level or nil, trend = known and trend or nil, group = base.known and base.level or nil,
        today = R.today(), facts = panelFacts(base, p)}
end

-- Copy of a relation (tests, server diagnostic): holds the gap, never to be sent to a client.
function R.debugPair(npcId, character)
    local p = pairOf(npcId, character, false)
    if not p then return nil end
    local out = {gap = p.gap, revision = p.revision, changes = {}, used = {}}
    for i, c in ipairs(p.changes) do out.changes[i] = {sign = c.sign, day = c.day, fact = c.fact, what = c.what} end
    for i, k in ipairs(p.used) do out.used[i] = k end
    return out
end

-- Engine events -----------------------------------------------------------------------------------------------------
if not R.subscribed and type(LivingKnox.subscribe) == "function" then
    R.subscribed = true
    LivingKnox.subscribe("OnInitGlobalModData", "PersonalRelation.init", function(newWorld)
        if R.init(newWorld) then R.prune() end
    end)
    LivingKnox.subscribe("EveryDays", "PersonalRelation.prune", function() R.prune() end)
    Identity.onRetire(function() R.prune() end)
end

return R
