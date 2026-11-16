-- Reward kind `stashmap` (pool entry stashmap:<weight>, E20-T04): an annotated vanilla map to an undiscovered stash
-- (RS_Config.Rewards.vanillaStashes), handed to the recipient; once per voice and character (state.missionRewards,
-- noted at the reservation so that a map still to hand is never drawn twice).
-- E23-T05 (ADR D10): the vanilla stash (StashSystem.doStashItem: annotations, stash removed from the possible ones,
-- not undoable) is reserved only once the map has entered the inventory; the client receives the annotated map after.
-- Inventory full: nothing is consumed, the record stays reserved and RS_RewardRetry hands the map once there is room
-- (resume: the reserved stash still possible).
if isClient() then return end
local Rewards = require 'RadioSurvivor/RS_Rewards'
local Config = require 'RadioSurvivor/RS_Config'

local Stashmap = {}

-- Row of this voice and character: {stashmap = name of the stash given or reserved}.
local function ledger(state, source, cid)
    state.missionRewards = state.missionRewards or {}
    local key = cid .. ':' .. source.id
    local row = state.missionRewards[key]
    if not row then row = {}; state.missionRewards[key] = row end
    return row
end

-- Possible stash of this name (vanilla list: not yet handed by any map), or nil.
local function possibleStash(name)
    local possible = StashSystem.getPossibleStashes()
    if not possible then return nil end
    for i = 0, possible:size() - 1 do
        if possible:get(i):getName() == name then return StashSystem.getStash(name) end
    end
    return nil
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

local function detailOf(stash)
    local map = stash and instanceItem(stash:getItem())
    if not map then return nil end
    return {stash = stash, map = map}
end

local function available(ctx)
    if ledger(ctx.state, ctx.source, ctx.cid).stashmap then return nil end
    local stash = Stashmap.find()
    if not stash then return nil end
    if not ctx.player then return {stash = stash} end
    return detailOf(stash)
end

local function reserve(ctx, rec, detail)
    if not detail.map then return nil, 'items' end
    rec.stash = detail.stash:getName()
    ledger(ctx.state, ctx.source, ctx.cid).stashmap = rec.stash
    return true
end

local function cancel(ctx)
    ledger(ctx.state, ctx.source, ctx.cid).stashmap = nil
end

-- Map first (nothing consumed when it does not fit), then the vanilla stash, then the annotated map to the client.
local function apply(ctx, rec, detail)
    if not fits(ctx.player, detail.map) then return false end
    local inv = ctx.player:getInventory()
    if not inv:AddItem(detail.map) then return false end
    StashSystem.doStashItem(detail.stash, detail.map)
    if isServer() then sendAddItemToContainer(inv, detail.map) end
    return true
end

local function resume(_, rec)
    return detailOf(StashSystem and possibleStash(rec.stash) or nil)
end

local function describe()
    return 'An annotated map to an undiscovered stash has been handed over.'
end

Rewards.register('stashmap', {available = available, reserve = reserve, cancel = cancel, apply = apply,
    resume = resume, describe = describe})

return Stashmap
