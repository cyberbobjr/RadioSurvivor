-- Living Knox : expéditions, dépôt au foyer et clôture de l'expédition (Expeditions.deliver)
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ dépôt au foyer

-- Conteneur de dépôt du foyer : conteneur posé par LK_Homes (caisse, tente), sinon le premier (ordre des clés) ; ou
-- nil et une raison.
local function depotOf(gid, g)
    if not LivingKnox.Stock.validRef(g.stock, g.home) then return nil, "no stock reference" end
    local style, def = LivingKnox.Homes.ready(g.home)
    if style == nil then return nil, def end
    local list, why = LivingKnox.Stock.containers(gid, g.home, style, def ~= nil and def:getIDString() or nil)
    if list == nil then return nil, why end
    for _, ct in ipairs(list) do
        if ct.owned then return ct end
    end
    if #list > 0 then return list[1] end
    return nil, "no container at home"
end

local function makeAbstract(e)
    local item = instanceItem(e.t)
    if item == nil then return nil end
    local fc = item:getFluidContainer()
    if e.c == "water" and fc ~= nil and Fluid ~= nil and Fluid.Water ~= nil then
        fc:Empty()
        fc:addFluid(Fluid.Water, fc:getCapacity())
    end
    return item
end

-- Dépôt, étape 1 : objets d'une entrée e de la charge (créés par le genre, créés hors écran ou portés en mémoire).
-- Rend la liste des objets, le nombre d'objets jetés (empoisonnés) et le nombre créés.
local function itemsOf(gid, t, e, kind, carried)
    local items, bad, created = {}, 0, 0
    if e.a and e.f and kind ~= nil and kind.make ~= nil then
        -- Genre à tirages (cueillette, pêche : LK05-T11) : objet tiré, créé maintenant par son genre (cueillette :
        -- graines comprises ; pêche : aucune) ; un objet empoisonné est jeté.
        local ok, list, nbad = pcall(kind.make, e.t)
        if ok then
            items, bad = list, nbad or 0
        else
            LivingKnox.Log.error("expedition: group %s trip %d: %s not made: %s", gid, t.n, e.t, tostring(list))
        end
        created = #items
    elseif e.a then
        local ok, it = pcall(makeAbstract, e)
        if ok and it ~= nil then
            items[1] = it
            created = 1
        end
    elseif e.i ~= nil and carried[e.i] ~= nil then
        items[1] = carried[e.i]
    end
    return items, bad, created
end

-- Dépôt, étape 2 : objets portés rangés dans le conteneur de dépôt (et envoyés aux clients sur un serveur). Rend les
-- entrées de référence, les objets comptés par catégorie, et les nombres perdus, créés et jetés.
local function unload(gid, t, depot, kind)
    local carried = P.carriedOf(gid, t.n)
    local refs, counts, lost, created, poisoned = {}, {}, 0, 0, 0
    for _, e in ipairs(t.carry) do
        local items, bad, made = itemsOf(gid, t, e, kind, carried)
        created = created + made
        poisoned = poisoned + bad
        if #items == 0 and bad == 0 then lost = lost + 1 end
        for _, item in ipairs(items) do
            depot.container:AddItem(item)
            if isServer() then sendAddItemToContainer(depot.container, item) end
            local cat = LivingKnox.Stock.categoryOf(item)
            if cat == nil and not e.f then cat = e.c end   -- objet d'une cueillette hors catégories (graines) : non suivi
            if cat ~= nil then refs[#refs + 1] = { i = item:getID(), t = item:getFullType(), c = cat, k = depot.key } end
            if not e.f or item:getFullType() == e.t then counts[e.c] = (counts[e.c] or 0) + 1 end
        end
    end
    return refs, counts, lost, created, poisoned
end

-- Dépôt, étape 3 : clôture de l'expédition (journal « return », derniers lieux fouillés) et objets déposés ajoutés à
-- la référence du stock, en une écriture.
local function closeTrip(gid, t, kind, refs, minute, text)
    local G = LivingKnox.Groups
    G.update(function(d)
        local live = d.groups[gid]
        local s = live and live.trips or nil
        if s == nil or s.cur == nil or s.cur.n ~= t.n then return false, false end
        if type(live.home) == "table" and LivingKnox.Stock.validRef(live.stock, live.home) then
            local have = {}
            for _, e in ipairs(live.stock.items) do have[e.i] = true end
            for _, r in ipairs(refs) do
                if not have[r.i] and #live.stock.items < LivingKnox.Stock.MAX_ITEMS then
                    live.stock.items[#live.stock.items + 1] = r
                end
            end
        end
        s.cur = nil
        s.last = minute
        local seen = s.seen
        if kind ~= nil and kind.seen and not P.inList(seen, t.target.b) then seen[#seen + 1] = t.target.b end
        while #seen > P.cfg().SEEN_MAX do table.remove(seen, 1) end
        G.appendLog(live, "return", P.cut(text), G.today())
        return true, true
    end)
end

-- Dépôt des objets portés par l'expédition du groupe gid (phase deliver) quand la zone du foyer est lisible ;
-- clôture de l'expédition (journal « return »), référence du stock à jour dans la même écriture. Rend vrai si fait.
-- LK20-T08 : étapes nommées ci-dessus, même ordre qu'avant.
function Ex.deliver(gid)
    local t, g = P.curOf(gid)
    if t == nil or t.phase ~= "deliver" then return false end
    local depot, why = depotOf(gid, g)
    if depot == nil then
        local key = gid .. "#" .. t.n
        if Ex.state.checked[key] ~= why then
            Ex.state.checked[key] = why
            LivingKnox.Log.info("expedition: group %s trip %d waits to unload: %s", gid, t.n, tostring(why))
        end
        return false
    end
    local kind = Ex.kindOf(t)
    local refs, counts, lost, created, poisoned = unload(gid, t, depot, kind)
    local minute = LivingKnox.Decisions.currentMinute() or t.start
    local parts = {}
    for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do
        if counts[c] then parts[#parts + 1] = c .. " +" .. counts[c] end
    end
    local text = string.format("trip %d back from %s: %d back, %s%s%s", t.n, tostring(t.target.label), #t.team,
        #parts > 0 and table.concat(parts, " ") or "nothing found", lost > 0 and (", " .. lost .. " lost") or "",
        poisoned > 0 and (", " .. poisoned .. " poisoned thrown away") or "")
    closeTrip(gid, t, kind, refs, minute, text)
    Ex.state.carried[gid .. "#" .. t.n] = nil
    Ex.state.claims[gid .. "#" .. t.n] = nil
    Ex.state.sites[gid .. "#" .. t.n] = nil
    Ex.stats.delivered = Ex.stats.delivered + 1
    Ex.stats.deposited = Ex.stats.deposited + #refs
    Ex.stats.lost = Ex.stats.lost + lost
    Ex.stats.created = Ex.stats.created + created
    LivingKnox.Log.info("expedition: group %s %s (into %s%s)", gid, text, depot.key,
        created > 0 and (", " .. created .. " found offscreen") or "")
    LivingKnox.Stock.updateRation(gid)
    return true
end
