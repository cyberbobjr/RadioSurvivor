-- Reward kind `stashmap` (pool entry stashmap:<weight>, E20-T04): an annotated vanilla map to an undiscovered stash
-- (RS_Config.Rewards.vanillaStashes), handed to the recipient; once per voice and character (state.missionRewards).
-- Realizable only when the map fits the inventory: the vanilla stash operation cannot be retried.
if isClient() then return end
local Rewards = require 'RadioSurvivor/RS_Rewards'
local Config = require 'RadioSurvivor/RS_Config'

local Stashmap = {}

-- Row of this voice and character: {stashmap = name of the stash already given}.
local function ledger(state, source, cid)
    state.missionRewards = state.missionRewards or {}
    local key = cid .. ':' .. source.id
    local row = state.missionRewards[key]
    if not row then row = {}; state.missionRewards[key] = row end
    return row
end

-- Match the vanilla eligibility check: possible stash AND an unvisited building. Sort names for determinism.
function Stashmap.find()
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

local function fits(player, item)
    local inv = player:getInventory()
    return inv:getCapacityWeight() + item:getActualWeight() <= inv:getEffectiveCapacity(player)
end

local function available(ctx)
    if ledger(ctx.state, ctx.source, ctx.cid).stashmap then return nil end
    local stash = Stashmap.find()
    if not stash then return nil end
    if not ctx.player then return {stash = stash} end
    local map = instanceItem(stash:getItem())
    if not map or not fits(ctx.player, map) then return nil end
    return {stash = stash, map = map}
end

local function reserve(_, rec, detail)
    if not detail.map then return nil, 'items' end
    rec.stash = detail.stash:getName()
    return true
end

local function giveItem(player, item)
    if not fits(player, item) then return false end
    local inv = player:getInventory()
    if not inv:AddItem(item) then return false end
    if isServer() then sendAddItemToContainer(inv, item) end
    return true
end

local function apply(ctx, rec, detail)
    StashSystem.doStashItem(detail.stash, detail.map)
    if not giveItem(ctx.player, detail.map) then return false end
    ledger(ctx.state, ctx.source, ctx.cid).stashmap = rec.stash
    return true
end

local function describe()
    return 'An annotated map to an undiscovered stash has been handed over.'
end

Rewards.register('stashmap', {available = available, reserve = reserve, apply = apply, describe = describe})

return Stashmap
