if isClient() then return end
--[[
Living Knox: reward of a mission given by one of its NPCs (E18-T29). Authority only.

The lot of an NPC is a real item of its household surplus, handed to the player who claims it: an item of a tracked
category the group holds above its target reserve, never while the group rations (Stock.needs: ration and next level
both 0), and only when it fits in the player's inventory. Without such an item, the lot announced with the mission
(RC_Missions.claim: rewardType x rewardCount); without an announced lot either, a lot created on the spot from the
closed table of the group's type (E18-T33: RC_MissionConfig.NPC_REWARD_TABLES -> Caches.tables), announced by the
notebook (R.lot, projected as rewardTable).

    R.resolve(npcId)                         -> { group, member, data, role } | nil, reason   living member of a group
    R.take(gid, character, player)           -> item, found | nil, reason   one surplus item taken from the household
    R.lot(m)                                 -> name of the created lot table, or nil (a lot is announced)
    R.claim(store, m, player, character, token) -> true | false, reason | nil (common lot)
        reward path of the giver "npc" of Living Knox alone (LK_TalkAlone); write-ahead marker on the mission before
        the item leaves the household, so an interrupted claim is never paid twice.

RadioSurvivor (RS_NPCRewards) reads R.resolve and R.take for its own "cache" reward of a Living Knox NPC.
]]
require "LivingKnox/LK_Core"
-- LivingKnox.Groups and LivingKnox.Stock are read at call time (loaded with every server file of the engine).

local R = LivingKnox.MissionRewards or {}
LivingKnox.MissionRewards = R

-- Living member of a group with at least one living member, or nil and a reason.
function R.resolve(npcId)
    local G = LivingKnox.Groups
    if npcId == nil or G == nil or G.findNpc == nil then return nil, "requester unavailable" end
    local gid, mid = G.findNpc(npcId)
    local g = gid and G.get(gid)
    local member = g and g.members and g.members[mid]
    if member == nil or member.alive ~= true then return nil, "requester unavailable" end
    return { group = gid, member = mid, data = g, role = member.role }
end

-- One item of the household surplus of group gid: above the target reserve of its category, no rationing now nor at
-- the next reading, fitting in the player's inventory. The item leaves the household container (Stock.takeItem).
function R.take(gid, character, player)
    local S = LivingKnox.Stock
    if S == nil then return nil, "stock unavailable" end
    local assessment = S.needs(gid)
    if assessment == nil or assessment.ration ~= 0 or assessment.next ~= 0 then return nil, "stock rationed" end
    local found, item = S.takeItem(gid, function(it)
        local cat = S.categoryOf(it)
        if cat == nil or (assessment.have[cat] or 0) <= (assessment.want[cat] or 0) then return false end
        if player then
            local inv = player:getInventory()
            if inv:getCapacityWeight() + it:getActualWeight() > inv:getEffectiveCapacity(player) then return false end
        end
        return true
    end, character, "mission reward")
    if not found then return nil, item end
    return item, found
end

local function give(player, item)
    local inv = player:getInventory()
    if not inv:AddItem(item) then return false end
    if isServer() then sendAddItemToContainer(inv, item) end
    return true
end

local function config() return require "RadioSurvivorCore/RC_MissionConfig" end

-- Name of the lot created for mission m (a table of Caches.tables), or nil when the mission announces its own lot.
-- The group's type is read now (unknown type: food); a dead requester gives nothing.
function R.lot(m)
    if (m.rewardCount or 0) > 0 then return nil end
    local r = R.resolve(m.npc)
    if r == nil then return nil end
    local MC = config()
    local name = MC.NPC_REWARD_TABLES[r.data.type] or "food"
    if MC.Caches.tables[name] == nil then return nil end
    return name
end

-- Items of the created lot, all instanced before anything is given; nil and a reason when one cannot be.
local function createLot(name, player)
    local items, weight = {}, 0
    for _, entry in ipairs(config().Caches.tables[name]) do
        for _ = 1, entry[2] do
            local item = instanceItem(entry[1])
            if item == nil then return nil, "Items" end
            items[#items + 1] = item
            weight = weight + item:getActualWeight()
        end
    end
    local inv = player:getInventory()
    if inv:getCapacityWeight() + weight > inv:getEffectiveCapacity(player) then return nil, "Capacity" end
    return items
end

-- Created lot handed to the player, behind the same write-ahead marker as the household item.
local function claimCreated(store, m, player, character, token, name)
    local items, why = createLot(name, player)
    if items == nil then return false, why end
    local ids = {}
    for i, item in ipairs(items) do ids[i] = item:getID() end
    m.transaction = { kind = "reward", token = token, character = character, ids = ids, stage = "prepared" }
    if not store.save() then m.transaction = nil; return false, "Storage" end
    m.claimedBy = character
    m.claimedName = m.participants[character].name
    m.createdLot = name
    m.revision = m.revision + 1
    if not store.save() then return false, "Recovery" end
    for _, item in ipairs(items) do
        if not give(player, item) then
            m.transaction.error = "inventory_add"
            store.save()
            return false, "Recovery"
        end
    end
    m.transaction.stage = "applied"
    if not store.save() then return false, "Recovery" end
    m.transaction = nil
    if not store.save() then return false, "Recovery" end
    return true
end

-- nil: no household surplus and a lot announced (or a supply lot already paid at completion): the common lot of the
-- engine is claimed. No surplus and no announced lot: the created lot (R.lot).
function R.claim(store, m, player, character, token)
    -- A supply contract with an engine reward paid that exact lot from the reserve at completion: never charge twice.
    if m.supply and (m.rewardCount or 0) > 0 then return nil end
    if m.transaction or m.state ~= "success" or not m.participants[character] or m.claimedBy ~= "" then
        return false, "State"
    end
    local r = R.resolve(m.npc)
    if r == nil then return nil end
    local created = R.lot(m)
    m.transaction = { kind = "reward", token = token, character = character, ids = {}, stage = "prepared" }
    if not store.save() then m.transaction = nil; return false, "Storage" end
    local item = R.take(r.group, character, player)
    if item == nil then
        -- Nothing left the household: the marker goes away; the announced lot, else the created one.
        m.transaction = nil
        store.save()
        if created then return claimCreated(store, m, player, character, token, created) end
        return nil
    end
    m.transaction.ids[1] = item:getID()
    m.claimedBy = character
    m.claimedName = m.participants[character].name
    m.householdItem = item:getFullType()
    m.revision = m.revision + 1
    if not store.save() then return false, "Recovery" end
    if not give(player, item) then
        m.transaction.error = "inventory_add"
        store.save()
        return false, "Recovery"
    end
    m.transaction.stage = "applied"
    if not store.save() then return false, "Recovery" end
    m.transaction = nil
    if not store.save() then return false, "Recovery" end
    return true
end

return R
