-- Living Knox : stock du foyer, source de matériel des soins (LK21-T05, LK_CareSupplies.lua). Objet repéré dans un
-- conteneur du foyer (LivingKnox.Stock.findItem), pris par LivingKnox.Stock.takeItem (retiré du conteneur et des clients,
-- ôté de la référence du stock dans la même écriture : ni perte ni vol à la relecture ; rien n'est créé), puis mis dans
-- l'inventaire du soignant (comme les provisions, LK_Provisions.lua). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Stock"

local Care = LivingKnox.Care

Care.registerSupplySource({ id = "stock", order = 30,
    find = function(sctx, match, skip)
        local S = LivingKnox.Stock
        local found, item = S.findItem(sctx.gid, function(it) return not skip[it:getID()] and match(it) end)
        if found == nil then return nil end
        return item, { key = found.key, x = found.x, y = found.y, z = found.z }
    end,
    take = function(sctx, item)
        local body = sctx.carer ~= nil and sctx.carer.body or nil
        if body == nil then return nil, "no carer body" end
        local id = item:getID()
        local got, taken = LivingKnox.Stock.takeItem(sctx.gid, function(it) return it:getID() == id end,
            sctx.carer.mid, sctx.use)
        if got == nil then return nil, taken end
        body:getInventory():AddItem(taken)
        return taken
    end })
