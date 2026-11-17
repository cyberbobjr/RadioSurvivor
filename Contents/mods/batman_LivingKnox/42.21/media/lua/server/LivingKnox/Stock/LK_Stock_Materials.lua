-- Living Knox : stock du groupe, matériaux d'entretien pris dans les conteneurs du foyer (LK05-T10)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

-- ================================================================ matériaux d'entretien (LK05-T10)
-- Entretien du foyer (LK_Upkeep.lua, fiche docs/annexes/conception/entretien.md) : carburant, pièces et produits pris dans les
-- conteneurs du foyer, relus au moment de la prise, jamais créés. Un récipient (fluide) est vidé de la quantité exacte
-- utilisée comme le vanilla (FluidContainer.adjustAmount(quantité - prise), ISAddFuel.lua:56-61, ISCleanBlood.lua) ;
-- sur un serveur, l'objet resté dans son meuble part aux clients proches par sendItemStats (copie du fluide :
-- J/network/GameServer.java:2944-2964, J/network/packets/ItemStatsPacket.java:160-168, 520-523) ; syncItemFields ne
-- vise que l'inventaire d'un joueur ou un objet posé au sol (J/inventory/InventoryItem.java:4154-4170). Un objet pris
-- entier (pièce) est retiré comme un repas (DoRemoveItem, sendRemoveItemFromContainer) et ôté de la référence s'il y
-- était suivi.

-- Fluide principal d'un récipient non vide parmi la liste fluids ({ "Petrol" }, ...), ou nil ; quantité en litres.
local function fluidIn(item, fluids)
    local fc = item ~= nil and item:getFluidContainer() or nil
    if fc == nil or fc:isEmpty() or Fluid == nil then return nil end
    local primary = fc:getPrimaryFluid()
    for _, name in ipairs(fluids) do
        if Fluid[name] ~= nil and primary == Fluid[name] then return name, fc:getAmount(), fc end
    end
    return nil
end

-- Premier objet des conteneurs du foyer (ordre des clés, puis des objets) tel que pred(objet) : { key, x, y, z, i, t },
-- objet, conteneur ; ou nil et une raison ("none" : aucun ; autre : stock ou zone illisible).
function Stock.findItem(gid, pred)
    local containers, why = P.homeContainers(gid)
    if containers == nil then return nil, why end
    for _, ct in ipairs(containers) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            if it ~= nil and pred(it) then
                return { key = ct.key, x = ct.x, y = ct.y, z = ct.z, i = it:getID(), t = it:getFullType() }, it,
                    ct.container
            end
        end
    end
    return nil, "none"
end

-- Premier récipient du foyer dont le fluide principal est dans fluids et qui en contient au moins least litres :
-- { key, x, y, z, i, t, fluid, amount }, ou nil et une raison.
function Stock.findFluid(gid, fluids, least)
    local found, item = Stock.findItem(gid, function(it)
        local name, amount = fluidIn(it, fluids)
        return name ~= nil and amount >= (least or 0) and amount > 0
    end)
    if found == nil then return nil, item end
    found.fluid, found.amount = fluidIn(item, fluids)   -- LK05-T11 : champs annoncés, lus maintenant
    return found
end

-- Verse au plus want litres d'un fluide de la liste fluids, pris dans UN récipient du foyer qui en contient au moins
-- least litres (relu maintenant). Retire exactement la quantité rendue. who, use : texte du journal. Rend { i, t, k,
-- fluid, amount, left }, ou nil et une raison.
function Stock.drawFluid(gid, fluids, want, least, who, use)
    if type(want) ~= "number" or want <= 0 then return nil, "nothing wanted" end
    local found, item = Stock.findItem(gid, function(it)
        local name, amount = fluidIn(it, fluids)
        return name ~= nil and amount >= (least or 0) and amount > 0
    end)
    if found == nil then return nil, item end
    local name, amount, fc = fluidIn(item, fluids)
    local q = math.min(amount, want)
    fc:adjustAmount(amount - q)
    if isServer() then sendItemStats(item) end
    Stock.stats.fluids = (Stock.stats.fluids or 0) + 1
    LivingKnox.Log.info("stock: group %s: %s used %.3f l of %s from %s (%s) in %s for %s", gid, tostring(who or "member"), q,
        name, found.t, tostring(found.i), found.key, tostring(use or "upkeep"))
    return { i = found.i, t = found.t, k = found.key, fluid = name, amount = q, left = fc:getAmount() }
end

-- Prend UN objet du foyer tel que pred(objet) (pièce de réparation...) : retiré du conteneur (et des clients sur un
-- serveur), ôté de la référence s'il y était suivi. Rend { i, t, k } et l'objet retiré (LK11-T06 : le même objet est
-- donné au joueur), ou nil et une raison. apply(g) facultatif (LK11-T06) : appelé sur le groupe vivant dans la MÊME
-- écriture du registre que la mise à jour de la référence (le registre est alors écrit même si l'objet n'était pas
-- suivi).
function Stock.takeItem(gid, pred, who, use, apply)
    local found, item, container = Stock.findItem(gid, pred)
    if found == nil then return nil, item end
    container:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(container, item) end
    local id = found.i
    local written = LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, live ~= nil
        end
        local kept, gone = {}, false
        for _, e in ipairs(live.stock.items) do
            if e.i ~= id then kept[#kept + 1] = e else gone = true end
        end
        if apply ~= nil then apply(live) end
        if not gone then return apply ~= nil, true end
        live.stock.items = kept
        return true, true
    end)
    if not written then
        LivingKnox.Log.warn("stock: group %s: %s taken from %s but the registry was not read (reference unchanged)", gid,
            found.t, found.key)
    end
    Stock.stats.parts = (Stock.stats.parts or 0) + 1
    LivingKnox.Log.info("stock: group %s: %s used %s (%s) from %s for %s", gid, tostring(who or "member"), found.t,
        tostring(id), found.key, tostring(use or "upkeep"))
    return { i = id, t = found.t, k = found.key }, item
end

-- LK05-T11 : objet d'identifiant id resté au foyer mais sorti des catégories suivies (bouteille vidée pour arroser) :
-- ôté de la référence, pour que la relecture suivante ne le compte pas perdu. Rend vrai s'il y était.
function Stock.untrack(gid, id)
    local gone = false
    LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, false
        end
        local kept = {}
        for _, e in ipairs(live.stock.items) do
            if e.i ~= id then kept[#kept + 1] = e else gone = true end
        end
        if not gone then return false, false end
        live.stock.items = kept
        return true, true
    end)
    return gone
end
