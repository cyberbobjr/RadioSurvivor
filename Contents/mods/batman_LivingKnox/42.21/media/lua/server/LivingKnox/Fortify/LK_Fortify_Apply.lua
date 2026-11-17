-- Living Knox : fortification du foyer, pose du travail fait hors écran quand la zone du foyer est chargée
-- (LK14-T05 : Fortify.applyPending, applyBarricade, STAGE_OFFSCREEN)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify
local P = Fortify._   -- fonctions privées partagées entre les fichiers de Fortify/ (LK_Fortify_Common.lua)

local function markOf(o)
    if o == nil or not o:hasModData() then return nil end
    return o:getModData()[Fortify.OP_TAG]
end

-- Pose un écart de barricade op (marque mark) : rend l'issue ("placed", "already", "adopted", "dropped", "kept"),
-- l'objet marqué et le nombre de planches posées.
local function applyBarricade(gid, op, mark)
    local site = { id = op.id, x = op.x, y = op.y, z = op.z, north = op.n, opp = op.o, steps = op.b }
    local o, sq = Fortify.openingOf(site)
    if sq == nil then return "kept" end
    if o == nil then return "dropped", nil, 0, "opening gone" end
    -- Marque sur l'ouverture, pas sur la barricade : IsoBarricade.save n'écrit pas la ModData (J/iso/objects/
    -- IsoBarricade.java:621-632, sans IsoObject.save) ; IsoWindow, IsoDoor et IsoThumpable la sauvegardent.
    if markOf(o) == mark then return "adopted", o, 0 end
    local plan = Fortify.plan(gid)
    local e = plan ~= nil and plan.entry or nil
    if e ~= nil and e.x == op.x and e.y == op.y and e.z == op.z and e.north == op.n then
        return "dropped", nil, 0, "home entry"
    end
    if Fortify.openingKind(o) == "door" and o:IsOpen() then return "dropped", nil, 0, "door open" end
    local addOpp, have = P.sideFor(o, site)
    if addOpp == nil then return "dropped", nil, 0, have end
    if have >= op.b then return "already" end
    local k = math.min(op.b - have, op.b - op.a)
    local b = Fortify.addPlanks(o, addOpp, k)
    if b == nil then return "dropped", nil, 0, "barricade not added" end
    o:getModData()[Fortify.OP_TAG] = mark
    return "placed", o, k
end

-- Pose un écart de mur ou de palissade op (marque mark), étape par étape par Fortify.placeStructure, comme
-- Fortify.buildStep sans prise de matériaux. Mêmes issues qu'applyBarricade.
local function applyRing(op, mark)
    local cell = getCell()
    local north = op.n == true
    local sq = cell ~= nil and cell:getGridSquare(op.x, op.y, op.z) or nil
    local ox, oy = op.x, op.y - 1
    if not north then ox, oy = op.x - 1, op.y end
    local other = sq ~= nil and cell:getGridSquare(ox, oy, op.z) or nil
    if sq == nil or other == nil then return "kept" end
    local kind, cur, obj = P.builtOn(sq, north)
    cur = cur or 0
    if kind ~= nil and kind ~= op.k then return "dropped", nil, 0, "other structure (" .. kind .. ")" end
    if markOf(obj) == mark then return "adopted", obj, 0 end
    if cur >= op.b then return "already" end
    if cur < op.a then return "dropped", nil, 0, "earlier stage missing" end
    local stages = Fortify.STAGES[op.k]
    local placed, last = 0, nil
    for n = cur + 1, op.b do
        local stage = stages[n]
        local prev
        if stage.prev ~= nil then
            prev = P.structureOn(sq, north, stage.prev)
            if prev == nil then return placed > 0 and "placed" or "dropped", last, placed, "no " .. stage.prev end
        elseif not P.groundOk(sq) or other:getBuildingDef() ~= nil or other:isWaterSquare() then
            return "dropped", nil, 0, "ground"
        elseif sq:isBlockedTo(other) then
            return "dropped", nil, 0, "edge closed"
        end
        local info, sprite = Fortify.entityInfo(stage.entity, north)
        if info == nil then return placed > 0 and "placed" or "dropped", last, placed, sprite end
        last = Fortify.placeStructure(sq, north, info, sprite, prev)
        placed = placed + 1
    end
    if last ~= nil then last:getModData()[Fortify.OP_TAG] = mark end
    return "placed", last, placed
end

-- LK16-T02 : pose hors écran de la sorte barricade (spec.offscreen.apply).
Fortify.applyBarricade = applyBarricade

-- LK16-T02 : rattrapage hors écran d'une sorte à étapes (spec.stages : mur, palissade), partagé par leurs fichiers :
-- étape suivante (matériaux et outil de l'étape, STAGE_MINUTES), matériaux des étapes restantes, pose par étapes.
Fortify.STAGE_OFFSCREEN = {
    nextStage = function(e, c)
        local st = Fortify.STAGES[e.k][e.h + 1]
        if st == nil then return nil end
        return st.materials, st.tool, c.STAGE_MINUTES
    end,
    remaining = function(e)
        local out = {}
        local stages = Fortify.STAGES[e.k]
        for n = e.h + 1, e.s do
            for _, r in ipairs(stages[n] ~= nil and stages[n].materials or {}) do out[#out + 1] = r end
        end
        return out
    end,
    apply = function(_, op, mark) return applyRing(op, mark) end,
}

-- Ouvre une boîte de clous entamée hors écran (entrée b = { i, u }) comme OpenBox100 : BOX_NAILS - u clous marqués
-- ajoutés au conteneur de la boîte (envoyés aux clients proches sur un serveur), boîte retirée par Stock.takeItem.
-- Boîte absente : clous déjà créés (marque) = repris, sinon boîte partie (rien). Rend l'issue.
local function openUsedBox(gid, b)
    local St = P.Stock()
    local mark = gid .. ":box:" .. tostring(b.i)
    if St.homeContainers == nil or St.homeContainers(gid) == nil then return "kept" end   -- conteneurs illisibles
    local f, box, ctr = St.findItem(gid, function(it) return it:getID() == b.i end)
    if f == nil then
        if St.findItem(gid, function(it) return markOf(it) == mark end) ~= nil then return "adopted" end
        LivingKnox.Log.warn("fortify: group %s: used box of nails %s gone before it was opened", gid, tostring(b.i))
        return "dropped"
    end
    local n = P.cfg().BOX_NAILS - b.u
    if n > 0 then
        local list = ctr:AddItems(Fortify.NAILS, n)
        if list ~= nil then
            for j = 0, list:size() - 1 do list:get(j):getModData()[Fortify.OP_TAG] = mark end
            if isServer() then sendAddItemsToContainer(ctr, list) end
        end
    end
    local id = box:getID()
    local got, why = St.takeItem(gid, function(it) return it:getID() == id end, "offscreen", "fortify box")
    if got == nil then
        LivingKnox.Log.warn("fortify: group %s: used box of nails %s not removed: %s", gid, tostring(id), tostring(why))
    end
    Fortify.stats.boxesOpened = Fortify.stats.boxesOpened + 1
    return "placed"
end

-- Efface les marques d'application des clous créés pour le groupe gid (conteneurs du foyer).
local function clearNailMarks(gid)
    local St = P.Stock()
    local list = St.homeContainers ~= nil and St.homeContainers(gid) or nil
    if list == nil then return end
    local prefix = gid .. ":box:"
    for _, ct in ipairs(list) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            local mk = markOf(it)
            if type(mk) == "string" and string.sub(mk, 1, #prefix) == prefix then it:getModData()[Fortify.OP_TAG] = nil end
        end
    end
end

-- LK20-T07 (D09) : étapes nommées de Fortify.applyPending, sans changement de comportement.

-- Pose les écarts ops du groupe gid par la sorte inscrite de chacun ; issues comptées dans rep. Rend les numéros
-- d'écart traités ({ [u] = vrai }) et les objets marqués.
local function applyOps(gid, ops, rep)
    local done, marked = {}, {}
    for _, op in ipairs(ops) do
        local mark = gid .. ":" .. op.u
        local apply = Fortify.kinds.byId[op.k].offscreen.apply   -- LK16-T02 : pose de la sorte inscrite
        local ok, res, obj, n, reason = pcall(apply, gid, op, mark)
        if not ok then
            rep.kept = rep.kept + 1
            LivingKnox.Log.error("fortify: group %s offscreen change %s (%s) not placed: %s (kept)", gid, tostring(op.u), op.id,
                tostring(res))
        elseif res == "kept" then
            rep.kept = rep.kept + 1
        else
            done[op.u] = true
            rep[res] = rep[res] + 1
            rep.steps = rep.steps + (n or 0)
            if obj ~= nil then marked[#marked + 1] = obj end
            if res == "dropped" then
                LivingKnox.Log.warn("fortify: group %s offscreen change %s (%s, %d -> %d) dropped: %s", gid, tostring(op.u),
                    op.id, op.a, op.b, tostring(reason))
            end
        end
    end
    return done, marked
end

-- Ouvre les boîtes entamées boxes du groupe gid ; issues comptées dans rep. Rend les boîtes traitées ({ [i] = vrai }).
local function openBoxes(gid, boxes, rep)
    local doneBox = {}
    for _, b in ipairs(boxes) do
        local ok, res = pcall(openUsedBox, gid, b)
        if not ok then
            rep.kept = rep.kept + 1
            LivingKnox.Log.error("fortify: group %s used box of nails %s not opened: %s (kept)", gid,
                tostring(b.i), tostring(res))
        elseif res == "kept" then
            rep.kept = rep.kept + 1
        else
            doneBox[b.i] = true
            if res == "placed" then rep.boxes = rep.boxes + 1 end
        end
    end
    return doneBox
end

-- Ôte du relevé gardé au registre les écarts done et les boîtes doneBox traités, puis écrit le registre. Rend vrai
-- si c'est écrit.
local function writeApplied(gid, done, doneBox)
    local written = LivingKnox.Groups.update(function(data)
        local live = data.groups[gid]
        local lf = live ~= nil and Fortify.fortView(live.fort, live.home) or nil
        if lf == nil then return false, false end
        local kept = {}
        for _, op in ipairs(lf.pend.ops) do
            if not done[op.u] then kept[#kept + 1] = op end
        end
        lf.pend.ops = kept
        local keptBoxes = {}
        for _, b in ipairs(lf.boxes) do
            if not doneBox[b.i] then keptBoxes[#keptBoxes + 1] = b end
        end
        lf.boxes = keptBoxes
        live.fort = Fortify.packFort(lf)   -- LK13-T07 : forme compacte (ancienne forme réécrite)
        return true, true
    end)
    if written == true and not LivingKnox.Groups.flush() then written = false end   -- LK13-T06 : écrit avant d'ôter les marques
    return written
end

-- Compteurs et journal de la pose rep du groupe gid.
local function reportApplied(gid, rep)
    Fortify.stats.applied = Fortify.stats.applied + 1
    for _, k in ipairs({ "placed", "already", "adopted", "dropped", "kept" }) do
        Fortify.stats[k] = Fortify.stats[k] + rep[k]
    end
    LivingKnox.Log.info("fortify: group %s offscreen work placed: %d change(s) placed (%d step(s)), %d already there, "
        .. "%d resumed, %d dropped, %d kept, %d box(es) of nails opened", gid, rep.placed, rep.steps, rep.already,
        rep.adopted, rep.dropped, rep.kept, rep.boxes)
end

-- Pose le travail fait hors écran du groupe gid (zone du foyer chargée) : écarts de pose puis boîtes entamées, en
-- une écriture du registre (écarts traités ôtés), marques effacées après elle. Rend { placed, already, adopted,
-- dropped, kept, steps, boxes }, ou nil et une raison.
function Fortify.applyPending(gid)
    P.settle(gid)   -- LK13-T11
    local g = P.liveGroup(gid)
    local f = g ~= nil and P.readView(gid, g.fort, g.home) or nil
    if f == nil then return nil, "no offscreen survey" end
    if #f.pend.ops == 0 and #f.boxes == 0 then return nil, "nothing pending" end
    local survey, why = Fortify.survey(gid)   -- toute la zone du pourtour chargée
    if survey == nil then return nil, why end
    local rep = { placed = 0, already = 0, adopted = 0, dropped = 0, kept = 0, steps = 0, boxes = 0 }
    local ops, boxes = {}, {}
    for _, op in ipairs(f.pend.ops) do ops[#ops + 1] = op end
    for _, b in ipairs(f.boxes) do boxes[#boxes + 1] = { i = b.i, u = b.u } end
    local done, marked = applyOps(gid, ops, rep)
    local doneBox = openBoxes(gid, boxes, rep)
    local written = writeApplied(gid, done, doneBox)
    if written == true then
        for _, o in ipairs(marked) do o:getModData()[Fortify.OP_TAG] = nil end
        if rep.boxes > 0 or #boxes > 0 then clearNailMarks(gid) end
    else
        LivingKnox.Log.warn("fortify: group %s offscreen work placed but the registry was not written (marks kept)", gid)
    end
    if rep.boxes > 0 then P.Stock().check(gid, { force = true }) end   -- clous ajoutés acceptés dans la référence
    Fortify.invalidate(gid)
    reportApplied(gid, rep)
    return rep
end
