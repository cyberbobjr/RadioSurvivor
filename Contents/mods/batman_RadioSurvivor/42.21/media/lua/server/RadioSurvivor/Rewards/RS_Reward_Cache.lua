-- Reward kind `cache` (pool entry cache:<category>:<weight>, E20-T04, ADR D05): a marked bag left at a place of the
-- sheet, filled with contents drawn in the category (shared catalogue personas/_categories.txt or a [category]
-- section of the sheet): each item line gives a quantity drawn in its range (a fixed number gives that number).
-- The drawn contents are saved in the mission cache record (RC_Caches.attachContents), which is the deferred outbox
-- placed by RC_Caches.poll: a restart places the same contents.
if isClient() then return end
local Rewards = require 'RadioSurvivor/RS_Rewards'
local Persona = require 'RadioSurvivor/RS_Persona'
local Caches = require 'RadioSurvivorCore/RC_Caches'

local Cache = {}

-- Where a cache reward is left: first place of the sheet with use=drop, else its first place.
function Cache.place(source)
    return Persona.placeFor(source, 'drop') or (type(source.places) == 'table' and source.places[1]) or nil
end

-- Category of this id for the sheet: its own [category] section first, else the shared catalogue.
function Cache.category(source, id)
    local own = type(source.categories) == 'table' and source.categories[id] or nil
    if own then return own end
    return require('RadioSurvivor/RS_Personas').rules().categories[id]
end

-- Contents drawn in the category: list of {fullType, count}, item lines drawn at 0 left out.
function Cache.contents(category, random)
    local out = {}
    for _, item in ipairs(category.items) do
        local count = item.min + random(item.max - item.min + 1)
        if count > 0 then out[#out + 1] = {item.type, count} end
    end
    return out
end

local function bounds(p)
    return {x1 = p.x - 3, y1 = p.y - 3, x2 = p.x + 4, y2 = p.y + 4}
end

local function attach(ctx, rec)
    return Caches.attachContents(ctx.m, rec.category, rec.items, rec.place, bounds(rec.place))
end

local function available(ctx)
    if ctx.m.cache ~= nil then return nil end
    local category = Cache.category(ctx.source, ctx.param)
    local place = Cache.place(ctx.source)
    if not category or type(category.items) ~= 'table' or #category.items == 0 or not place then return nil end
    return {category = category, place = place}
end

local function reserve(ctx, rec, detail)
    local p = detail.place
    rec.place = {id = p.id, x = p.x, y = p.y, z = p.z or 0, label = p.label}
    rec.category = ctx.param
    rec.items = Cache.contents(detail.category, ctx.random)
    local cache, why = attach(ctx, rec)
    if not cache then return nil, why end
    return true
end

local function cancel(ctx)
    ctx.m.cache = nil
end

local function apply(ctx, rec)
    if not ctx.m.cache then
        attach(ctx, rec)
        if not ctx.store.save() then return false end
    end
    if ctx.m.cache then Caches.place(ctx.store, ctx.m.cache) end
    if ctx.khz then require('RadioSurvivor/RS_MapMarks').give(ctx.player, ctx.cid, ctx.khz, rec.place) end
    return true
end

local function describe()
    return 'A supply bag has been left for you at the marked place.'
end

Rewards.register('cache', {param = 'category', available = available, reserve = reserve, cancel = cancel,
    apply = apply, describe = describe})

return Cache
