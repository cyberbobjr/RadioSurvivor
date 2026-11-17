-- Living Knox : stock du groupe, repas réels pris dans les conteneurs du foyer et pénuries (LK05-T07)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

-- ================================================================ repas réels (LK05-T07)

-- Vrai si l'objet, de la catégorie cat ("food" ou "water"), se mange ou se boit tel quel : nourriture ni pourrie, ni
-- gelée, ni crue dangereuse (Food.isRotten, isFrozen, isbDangerousUncooked : J/inventory/types/Food.java:1653, 1671,
-- 1974 ; InventoryItem.isCooked :2413) ; eau propre seulement (fluide principal Fluid.Water).
function Stock.consumable(item, cat)
    if item == nil then return false end
    if cat == "water" then
        local fc = item:getFluidContainer()
        return fc ~= nil and not fc:isEmpty() and Fluid ~= nil and fc:getPrimaryFluid() == Fluid.Water
    end
    if cat ~= "food" or Stock.categoryOf(item) ~= "food" then return false end
    if instanceof(item, "Food") then
        if item:isRotten() or item:isFrozen() then return false end
        if item:isbDangerousUncooked() and not item:isCooked() then return false end
    end
    return true
end

-- Conteneurs lisibles du foyer du groupe gid : liste de Stock.containers, ou nil et une raison.
local function homeContainers(gid)
    local g = LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no group or no home" end
    if not Stock.validRef(g.stock, g.home) then return nil, "no stock reference" end
    local style, def = LivingKnox.Homes.ready(g.home)
    if style == nil then return nil, def end
    local list, why = Stock.containers(gid, g.home, style, def ~= nil and def:getIDString() or nil)
    -- LK09-T06 : écarts hors écran appliqués avant toute prise du groupe dans les conteneurs.
    if list ~= nil and Stock.pendingCount(g.stock) > 0 then Stock.applyPending(gid, list, g) end
    return list, why
end
Stock.homeContainers = homeContainers   -- LK11-T08 : troc (LK_Trade.lua), mêmes conteneurs que les prises du groupe

local function firstConsumable(container, cat)
    local items = container:getItems()
    for j = 0, items:size() - 1 do
        local it = items:get(j)
        if Stock.categoryOf(it) == cat and Stock.consumable(it, cat) then return it end
    end
    return nil
end

-- Premier objet consommable de la catégorie cat ("food" ou "water") dans les conteneurs du foyer du groupe gid (ordre
-- des clés de conteneur, puis des objets : reproductible). Rend { key, x, y, z (case de l'objet qui porte le
-- conteneur), i, t, c }, ou nil et une raison ("none" : rien à manger ou à boire ; autre : stock ou zone illisible).
function Stock.findMeal(gid, cat)
    if cat ~= "food" and cat ~= "water" then return nil, "bad category" end
    local containers, why = homeContainers(gid)
    if containers == nil then return nil, why end
    for _, ct in ipairs(containers) do
        local it = firstConsumable(ct.container, cat)
        if it ~= nil then
            return { key = ct.key, x = ct.x, y = ct.y, z = ct.z, i = it:getID(), t = it:getFullType(), c = cat }
        end
    end
    return nil, "none"
end

-- Prend UN objet consommable de la catégorie cat dans le conteneur de clé key (relu maintenant : l'objet repéré a pu
-- partir entre-temps). L'objet est retiré du conteneur (et des clients sur un serveur), puis ôté de la référence dans la
-- même écriture du registre que apply(g) (facultatif, groupe vivant). who : texte du journal. Rend { i, t, c, k }, ou
-- nil et une raison ("gone" : plus rien de consommable dans ce conteneur).
function Stock.takeMeal(gid, cat, key, apply, who)
    if cat ~= "food" and cat ~= "water" then return nil, "bad category" end
    local containers, why = homeContainers(gid)
    if containers == nil then return nil, why end
    local ct
    for _, c in ipairs(containers) do
        if c.key == key then ct = c end
    end
    if ct == nil then return nil, "container gone" end
    local item = firstConsumable(ct.container, cat)
    if item == nil then return nil, "gone" end
    local id, t = item:getID(), item:getFullType()
    ct.container:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(ct.container, item) end
    local written = LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        if live == nil then return false, false end
        if type(live.home) == "table" and Stock.validRef(live.stock, live.home) then
            local kept = {}
            for _, e in ipairs(live.stock.items) do
                if e.i ~= id then kept[#kept + 1] = e end
            end
            live.stock.items = kept
        end
        if apply ~= nil then apply(live) end
        return true, true
    end)
    if not written then
        LivingKnox.Log.warn("stock: group %s: %s taken from %s but the registry was not written (counted as lost)", gid, t, key)
    end
    Stock.stats.meals = Stock.stats.meals + 1
    LivingKnox.Log.info("stock: group %s: %s %s %s (%s) from %s", gid, tostring(who or "member"),
        cat == "water" and "drank" or "ate", t, tostring(id), key)
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(gid, who, "meal", (cat == "water" and "drank " or "ate ") .. t .. " from " .. key) end
    Stock.updateRation(gid)
    return { i = id, t = t, c = cat, k = key }
end

-- Pénurie : un membre n'a rien trouvé à manger (cat "food"), à boire ("water") ou pour panser une plaie ("medical",
-- LK07-T03, LK_Care) dans le stock. Écrite au journal du
-- groupe (kind « shortage ») au plus une fois par SHORTAGE_HOURS et par catégorie ; le rationnement est relu.
-- Rend vrai si écrite.
function Stock.reportShortage(gid, cat, who)
    Stock.state.shortage = Stock.state.shortage or {}
    local slot = gid .. "|" .. tostring(cat)
    local h = P.hourNow()
    local last = Stock.state.shortage[slot]
    Stock.updateRation(gid)
    if last ~= nil and h - last < P.cfg().SHORTAGE_HOURS and h >= last then return false end
    Stock.state.shortage[slot] = h
    local a = Stock.needs(gid)
    local what = cat == "water" and "water to drink" or cat == "medical" and "bandage to treat a wound" -- LK07-T03
        or "food to eat"
    local text = string.format("no %s left for %s (ration %s)", what,
        tostring(who or "a member"), a ~= nil and a.rationName or "unknown")
    local G = LivingKnox.Groups
    G.update(function(data)
        local g = data.groups[gid]
        if g == nil then return false, false end
        G.appendLog(g, "shortage", string.sub(text, 1, G.TEXT_MAX), G.today())
        return true, true
    end)
    Stock.stats.shortages = Stock.stats.shortages + 1
    LivingKnox.Log.info("stock: group %s %s", gid, text)
    return true
end

P.homeContainers = homeContainers
