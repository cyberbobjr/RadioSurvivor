-- Mission rewards: closed server policy, no model-selected item, frequency, location or XP.
if isClient() then return end
local Config = require 'RadioSurvivor/RS_Config'
local Rep = require 'RadioSurvivorCore/RC_Reputation'
local Persona = require 'RadioSurvivor/RS_Persona'
local R = {}

-- E20-T03 (ADR D04, D05): reward kinds a voice sheet may put in its [rewards] pool, and the kind of their parameter
-- (RS_PersonaParams, checked by RS_Persona). Single owner of these names; E20-T04 turns them into a registry.
R.KINDS = {cache = {param = 'category'}, frequency = {}, stashmap = {}, lesson = {param = 'skill'}}
-- Skills a lesson may teach (pool entry lesson:<skill>:<weight>): names of vanilla Perks.
R.SKILLS = {'Doctor', 'Aiming', 'Reloading', 'Woodwork', 'Mechanics', 'Electricity', 'MetalWelding', 'Cooking',
    'Farming', 'Fishing', 'Trapping', 'PlantScavenging'}

-- Pool of the sheet ([rewards] pool=, RS_Persona): list of {kind, param, weight}.
local function pool(source)
    return type(source.rewards) == 'table' and source.rewards or {}
end

-- First pool entry of this kind, or nil.
local function entryOf(source, kind)
    for _, e in ipairs(pool(source)) do if e.kind == kind then return e end end
    return nil
end

-- Kinds of the pool in the order of their first appearance: the fixed cycle until E20-T04.
local function kindsOf(source)
    local out, seen = {}, {}
    for _, e in ipairs(pool(source)) do
        if not seen[e.kind] then seen[e.kind] = true; out[#out + 1] = e.kind end
    end
    return out
end

-- Cache table and taught skill: parameter of the first cache and lesson entries of the pool.
local function cacheTable(source)
    local e = entryOf(source, 'cache')
    return e and e.param
end

local function skillOf(source)
    local e = entryOf(source, 'lesson')
    return e and e.param
end

-- Where a cache reward is left: first place of the sheet with use=drop, else its first place.
function R.cachePlace(source)
    return Persona.placeFor(source, 'drop') or (type(source.places) == 'table' and source.places[1]) or nil
end

local function ledger(state, source, cid)
    state.missionRewards = state.missionRewards or {}
    local key = cid .. ':' .. source.id
    local row = state.missionRewards[key]
    if not row then row = {cursor = 0}; state.missionRewards[key] = row end
    return row
end

function R.multiplier()
    local n = SandboxVars and SandboxVars.RadioSurvivor and SandboxVars.RadioSurvivor.LessonMultiplier
    if type(n) ~= 'number' or n ~= n then return 1 end
    return math.max(0, math.min(5, n))
end

function R.frequency(source)
    local personas = require 'RadioSurvivor/RS_Personas'
    local ids = source.shares or {}
    if source.group then
        ids = {}
        local own = require('RadioSurvivor/RS_GroupRadio').voiceId(source.group)
        if own then ids[#ids + 1] = own end
        local others = personas.ids()
        for _, id in ipairs(others) do if id ~= own then ids[#ids + 1] = id end end
    end
    for _, id in ipairs(ids) do
        local sheet = personas.get(id)
        if id ~= source.id and sheet and sheet.state == 'active' then
            local frequencies = personas.served(id)
            if frequencies[1] then return {voice = id, khz = frequencies[1], name = sheet.name} end
        end
    end
    return nil
end

-- Match the vanilla eligibility check: possible stash AND an unvisited building. Sort names for determinism.
function R.stash()
    if not StashSystem or not getWorld then return nil end
    local possible = StashSystem.getPossibleStashes()
    if not possible then return nil end
    local allowed = Config.Rewards.vanillaStashes or {}
    local names = {}
    for i = 0, possible:size() - 1 do
        local name = possible:get(i):getName()
        if allowed[name] then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local stash = StashSystem.getStash(name)
        local room = stash and getWorld():getMetaGrid():getRoomAt(stash:getBuildingX(), stash:getBuildingY(), 0)
        local building = room and room:getBuilding()
        if building and not building:isHasBeenVisited() then return stash end
    end
    return nil
end

local function xpAmount(state, cid)
    local day = Rep.today()
    if not day then return 0 end
    local row = state.lessonDays and state.lessonDays[cid]
    local used = row and row.day == day and row.xp or 0
    return math.max(0, math.min(Config.Rewards.lessonXP * R.multiplier(), Config.Rewards.dailyXP * R.multiplier() - used))
end

local function available(state, source, m, cid, kind)
    if kind == 'cache' then
        local t = cacheTable(source)
        return t ~= nil and Config.Caches.tables[t] ~= nil and R.cachePlace(source) ~= nil and m.cache == nil
    elseif kind == 'frequency' then return R.frequency(source)
    elseif kind == 'stashmap' then
        local row = ledger(state, source, cid)
        return not row.stashmap and R.stash()
    elseif kind == 'lesson' then
        local skill = skillOf(source)
        return skill and Perks and Perks[skill] and xpAmount(state, cid) > 0
    end
    return false
end

function R.choose(state, source, m, cid, player)
    local row = ledger(state, source, cid)
    local order = kindsOf(source)
    for offset = 1, #order do
        local index = (row.cursor + offset - 1) % #order + 1
        local kind = order[index]
        local detail = available(state, source, m, cid, kind)
        if detail and kind == 'stashmap' and player then
            local map = instanceItem(detail:getItem())
            local inv = player:getInventory()
            if not map or inv:getCapacityWeight() + map:getActualWeight() > inv:getEffectiveCapacity(player) then
                detail = nil
            end
        end
        if detail then return kind, index, detail end
    end
    return nil
end

local function giveItem(player, item)
    if not item then return false end
    local inv = player:getInventory()
    if inv:getCapacityWeight() + item:getActualWeight() > inv:getEffectiveCapacity(player) then return false end
    if not inv:AddItem(item) then return false end
    if isServer() then sendAddItemToContainer(inv, item) end
    return true
end

-- Reserve before irreversible effects. An interrupted effect is kept as 'reserved', never silently reissued.
-- For caches the persistent record itself is the deferred outbox, handled by RC_Caches.poll.
function R.grant(store, source, m, player, cid, khz)
    if store.blocked or type(store.data) ~= 'table' then return nil, 'storage' end
    if not player or m.state ~= 'success' or not m.participants[cid] then return nil, 'state' end
    if m.extendedReward then return m.extendedReward, 'already_reserved' end
    local state = store.data
    local kind, index, detail = R.choose(state, source, m, cid, player)
    if not kind then return nil, 'unavailable' end
    -- Check inventory before reserving a non-retryable vanilla stash operation.
    local map
    if kind == 'stashmap' then
        map = instanceItem(detail:getItem())
        if not map then return nil, 'items' end
        local inv = player:getInventory()
        if inv:getCapacityWeight() + map:getActualWeight() > inv:getEffectiveCapacity(player) then return nil, 'capacity' end
    end
    local row = ledger(state, source, cid)
    local previous = row.cursor
    local rec = {kind = kind, character = cid, source = source.id, status = 'reserved'}
    m.extendedReward, row.cursor = rec, index
    if kind == 'lesson' then
        rec.skill, rec.xp = skillOf(source), xpAmount(state, cid)
    elseif kind == 'frequency' then rec.voice, rec.khz, rec.name = detail.voice, detail.khz, detail.name
    elseif kind == 'stashmap' then rec.stash = detail:getName()
    elseif kind == 'cache' then
        local p = R.cachePlace(source)
        rec.place = {id = p.id, x = p.x, y = p.y, z = p.z or 0, label = p.label}
        rec.table = cacheTable(source)
        local caches = require 'RadioSurvivor/RS_CacheAction'
        caches.attach(m, rec.table, p, {x1 = p.x - 3, y1 = p.y - 3, x2 = p.x + 4, y2 = p.y + 4})
    end
    if not store.save() then
        m.extendedReward, row.cursor = nil, previous
        if kind == 'cache' then m.cache = nil end
        return nil, 'storage'
    end
    if kind == 'cache' then
        local caches = require 'RadioSurvivor/RS_CacheAction'
        if not m.cache then
            local p = rec.place
            caches.attach(m, rec.table, p, {x1 = p.x - 3, y1 = p.y - 3, x2 = p.x + 4, y2 = p.y + 4})
            if not store.save() then return rec, 'recovery' end
        end
        if m.cache then caches.place(store, m.cache) end
        if khz then require('RadioSurvivor/RS_MapMarks').give(player, cid, khz, rec.place) end
    elseif kind == 'frequency' then
        require('RadioSurvivor/RS_RadioLog').add(cid, rec.khz, 'reply',
            (rec.name or rec.voice) .. ' (' .. string.format('%.1f MHz', rec.khz / 1000) .. ')', rec.voice)
    elseif kind == 'stashmap' then
        StashSystem.doStashItem(detail, map)
        if not giveItem(player, map) then return rec, 'recovery' end
        row.stashmap = rec.stash
    elseif kind == 'lesson' then
        state.lessonDays = state.lessonDays or {}
        local day = Rep.today()
        local daily = state.lessonDays[cid]
        if not daily or daily.day ~= day then daily = {day = day, xp = 0}; state.lessonDays[cid] = daily end
        daily.xp = daily.xp + rec.xp
        if not store.save() then return rec, 'recovery' end
        addXp(player, Perks[rec.skill], rec.xp)
    end
    rec.status = 'applied'
    if khz then require('RadioSurvivor/RS_RadioLog').add(cid, khz, 'reward', rec.kind) end
    if not store.save() then return rec, 'recovery' end
    return rec
end

function R.context(rec)
    if not rec then return nil end
    if rec.kind == 'cache' then return 'A supply bag has been left for you at the marked place.' end
    if rec.kind == 'frequency' then return 'A radio contact has been added to your private notebook.' end
    if rec.kind == 'stashmap' then return 'An annotated map to an undiscovered stash has been handed over.' end
    if rec.kind == 'lesson' then return 'A practical lesson in ' .. tostring(rec.skill) .. ' has been given.' end
end

return R
