-- Living Knox : stock du groupe, application du journal d'écarts aux conteneurs réels (LK09-T06)
-- LK20-T08 : sorti de LK_Stock.lua sans changement de comportement ; façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Stock/LK_Stock_Common"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

-- Objet vanilla d'un écart « add » : créé, eau remplie, marqué (groupe et marque d'application). Rend l'objet, ou nil
-- et une raison (type refusé : l'écart est abandonné).
local function makePending(gid, op, mark)
    if string.sub(op.t, 1, 5) ~= "Base." then return nil, "not a vanilla item" end
    local item = instanceItem(op.t)
    if item == nil then return nil, "unknown item" end
    if op.c == "water" then
        local fc = item:getFluidContainer()
        if fc == nil or Fluid == nil or Fluid.Water == nil then return nil, "cannot fill" end
        fc:Empty()
        fc:addFluid(Fluid.Water, fc:getCapacity())
    end
    local md = item:getModData()
    md[Stock.TAG] = gid
    md[Stock.OP_TAG] = mark
    return item
end

-- Application, étape 1 : objets des conteneurs par identifiant et par marque d'application, et conteneur de dépôt
-- (posé par LK_Homes, sinon le premier). Rend byId, byMark, depot.
local function indexContainers(containers)
    local byId, byMark, depot = {}, {}, nil
    for _, ct in ipairs(containers) do
        if depot == nil and ct.owned then depot = ct end
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            byId[it:getID()] = { item = it, ct = ct }
            if it:hasModData() then
                local mk = it:getModData()[Stock.OP_TAG]
                if type(mk) == "string" then byMark[mk] = { item = it, ct = ct } end
            end
        end
    end
    depot = depot or containers[1]
    return byId, byMark, depot
end

-- Application, étape 2 : écart « take » op : objet retiré s'il est encore là (et des clients sur un serveur).
local function applyTake(op, byId, rep, done)
    local hit = byId[op.i]
    if hit ~= nil then
        hit.ct.container:DoRemoveItem(hit.item)
        if isServer() then sendRemoveItemFromContainer(hit.ct.container, hit.item) end
        byId[op.i] = nil
        rep.removed = rep.removed + 1
    else
        rep.gone = rep.gone + 1
    end
    done[op.u] = true
end

-- Application, étape 3 : écart « add » op : objet repris s'il porte déjà sa marque, sinon créé au dépôt (type refusé :
-- écart abandonné ; erreur ou aucun dépôt : écart gardé). Rend l'objet et son conteneur, ou nil.
local function applyAdd(gid, op, byMark, depot, rep, done)
    local mark = gid .. ":" .. op.u
    local hit = byMark[mark]
    local item, ct
    if hit ~= nil then
        item, ct = hit.item, hit.ct
        rep.adopted = rep.adopted + 1
    elseif depot ~= nil then
        local ok, made, why = pcall(makePending, gid, op, mark)
        if ok and made ~= nil then
            item, ct = made, depot
            depot.container:AddItem(item)
            if isServer() then sendAddItemToContainer(depot.container, item) end
            rep.made = rep.made + 1
        elseif ok then
            done[op.u] = true
            rep.dropped = rep.dropped + 1
            LivingKnox.Log.warn("stock: group %s pending %s not created: %s (dropped)", gid, op.t, tostring(why))
        else
            rep.kept = rep.kept + 1
            LivingKnox.Log.error("stock: group %s pending %s not created: %s (kept)", gid, op.t, tostring(made))
        end
    else
        rep.kept = rep.kept + 1
    end
    return item, ct
end

-- Application, étape 4 : écarts appliqués dans l'ordre du journal. Rend le bilan, les numéros traités, les entrées de
-- référence des objets créés ou repris et ces objets (marques effacées après l'écriture).
local function applyOps(gid, ops, byId, byMark, depot)
    local rep = { removed = 0, gone = 0, made = 0, adopted = 0, dropped = 0, kept = 0 }
    local done, refs, marked = {}, {}, {}
    for _, op in ipairs(ops) do
        if op.o == "take" then
            applyTake(op, byId, rep, done)
        else
            local item, ct = applyAdd(gid, op, byMark, depot, rep, done)
            if item ~= nil then
                done[op.u] = true
                marked[#marked + 1] = item
                local cat = Stock.categoryOf(item)
                if cat ~= nil then refs[#refs + 1] = { i = item:getID(), t = item:getFullType(), c = cat, k = ct.key } end
            end
        end
    end
    return rep, done, refs, marked
end

-- Application, étape 5 : en une écriture, écarts traités ôtés du journal (par numéro) et objets créés ajoutés à la
-- référence. Rend vrai si écrit.
local function writeApplied(gid, done, refs)
    return LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock.validRef(live.stock, live.home) then
            return false, false
        end
        local lp = P.pendOf(live.stock, false, gid)
        if lp ~= nil then
            local kept = {}
            for _, op in ipairs(lp.ops) do
                if not done[op.u] then kept[#kept + 1] = op end
            end
            lp.ops = kept
        end
        local have = {}
        for _, e in ipairs(live.stock.items) do have[e.i] = true end
        for _, r in ipairs(refs) do
            if not have[r.i] and #live.stock.items < Stock.MAX_ITEMS then
                live.stock.items[#live.stock.items + 1] = r
                have[r.i] = true
            end
        end
        return true, true
    end)
end

-- Applique le journal d'écarts du groupe gid aux conteneurs lisibles du foyer (containers = Stock.containers) ; g :
-- copie du groupe (facultative). Objets pris retirés s'ils sont encore là ; objets ajoutés créés (ou repris s'ils
-- portent déjà leur marque) dans le conteneur posé par LK_Homes, sinon le premier ; puis, en une écriture, écarts
-- traités ôtés du journal (par numéro : un écart ajouté entre-temps reste) et objets créés ajoutés à la référence ;
-- marques effacées après l'écriture. Rend { removed, gone, made, adopted, dropped, kept }, ou nil et une raison.
-- LK20-T08 : étapes nommées ci-dessus, même ordre qu'avant.
function Stock.applyPending(gid, containers, g)
    g = g or LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" or not Stock.validRef(g.stock, g.home) then
        return nil, "no stock reference"
    end
    local p = P.pendOf(g.stock, false, gid)
    if p == nil or #p.ops == 0 then return nil, "nothing pending" end
    local byId, byMark, depot = indexContainers(containers)
    local rep, done, refs, marked = applyOps(gid, p.ops, byId, byMark, depot)
    local written = writeApplied(gid, done, refs)
    -- LK13-T06 : registre écrit dans son fichier avant d'effacer les marques (sinon une sauvegarde du monde sans marque
    -- suivie d'un arrêt avant l'écriture différée ferait recréer les objets).
    if written then written = LivingKnox.Groups.flush() end
    if written then
        for _, item in ipairs(marked) do item:getModData()[Stock.OP_TAG] = nil end
    else
        LivingKnox.Log.warn("stock: group %s pending stock changes applied but the registry was not written (marks kept)", gid)
    end
    Stock.stats.applied = Stock.stats.applied + 1
    Stock.stats.removed = Stock.stats.removed + rep.removed
    Stock.stats.gone = Stock.stats.gone + rep.gone
    Stock.stats.made = Stock.stats.made + rep.made
    Stock.stats.adopted = Stock.stats.adopted + rep.adopted
    LivingKnox.Log.info("stock: group %s offscreen changes applied into %s: %d removed, %d already gone, %d created, "
        .. "%d resumed, %d dropped, %d kept", gid, depot ~= nil and depot.key or "no container", rep.removed, rep.gone,
        rep.made, rep.adopted, rep.dropped, rep.kept)
    Stock.updateRation(gid)
    return rep
end
