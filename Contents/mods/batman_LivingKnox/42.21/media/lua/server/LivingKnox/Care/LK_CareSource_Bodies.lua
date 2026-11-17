-- Living Knox : sources de matériel des soins portées sur soi (LK21-T05, LK_CareSupplies.lua) : l'inventaire du
-- soignant, puis celui du blessé (premier niveau, IsoGameCharacter.getInventory, J/characters/IsoGameCharacter.java:2987).
-- Un objet du blessé passe au soignant, comme le vanilla met le matériel dans l'inventaire du soignant avant l'action
-- (ISHealthPanel.lua, toPlayerInventory). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_CareSupplies"

local Care = LivingKnox.Care

local function inventoryOf(who)
    local body = who ~= nil and who.body or nil
    return body ~= nil and body:getInventory() or nil
end

local function findIn(inv, match, skip)
    if inv == nil then return nil end
    local items = inv:getItems()
    for j = 0, items:size() - 1 do
        local it = items:get(j)
        if it ~= nil and not skip[it:getID()] and match(it) then return it end
    end
    return nil
end

Care.registerSupplySource({ id = "carer", order = 10,
    find = function(sctx, match, skip) return findIn(inventoryOf(sctx.carer), match, skip) end,
    take = function(sctx, item)
        local inv = inventoryOf(sctx.carer)
        if inv == nil or not inv:containsID(item:getID()) then return nil, "no longer carried" end
        return item
    end })

Care.registerSupplySource({ id = "patient", order = 20,
    find = function(sctx, match, skip)
        if sctx.patient == nil or sctx.carer == nil or sctx.patient.id == sctx.carer.id then return nil end
        return findIn(inventoryOf(sctx.patient), match, skip)
    end,
    take = function(sctx, item)
        local from, to = inventoryOf(sctx.patient), inventoryOf(sctx.carer)
        if from == nil or to == nil or not from:containsID(item:getID()) then return nil, "no longer carried" end
        from:DoRemoveItem(item)
        to:AddItem(item)
        return item
    end })
