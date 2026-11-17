-- Living Knox : expéditions, phases au registre, mémoire des membres, conteneurs du lieu et fouille d'un conteneur
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ phases (registre)

local function setPhase(gid, n, phase, minute, why)
    local c = P.cfg()
    local span = { search = c.SEARCH_MINUTES, back = c.BACK_MINUTES, deliver = 0 }
    LivingKnox.Groups.update(function(d)
        local g = d.groups[gid]
        local t = g and g.trips and g.trips.cur or nil
        if t == nil or t.n ~= n or t.phase == phase then return false, false end
        t.phase = phase
        t.due = minute + (span[phase] or 0)
        return true, true
    end)
    LivingKnox.Log.info("expedition: group %s trip %d %s (%s)", gid, n, phase, tostring(why))
end

local function memOf(id, gid, n, mid)
    local mem = Ex.state.npcs
    local m = mem[id]
    if m == nil or m.n ~= n or m.gid ~= gid then
        m = { gid = gid, n = n, mid = mid, fails = 0 }
        mem[id] = m
    end
    return m
end

local function resetSteps(m)
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
    m.faced = nil   -- pêche (LK05-T11) : de nouveau tourné vers l'eau après une interruption
end

-- Remis debout s'il tient le geste de fouille d'un genre.
local function standUp(id)
    local A = LivingKnox.Anim
    if A == nil then return end
    local now = A.gestureOf(id)
    for _, spec in ipairs(P.kindRegistry:list()) do
        if spec.gesture ~= nil and now == spec.gesture then
            A.setGesture(id, A.DEFAULT)
            return
        end
    end
end

local function claimsOf(gid, n)
    local key = gid .. "#" .. n
    Ex.state.claims[key] = Ex.state.claims[key] or {}
    return Ex.state.claims[key]
end

-- Conteneurs du bâtiment visé (mémoire, relevés à la première demande) : { { key, x, y, z, place } } du plus proche
-- au plus loin du point visé (cases non chargées ignorées ; relevé gardé pour toute l'expédition).
function Ex.siteContainers(gid, t)
    local key = gid .. "#" .. t.n
    local cached = Ex.state.sites[key]
    if cached ~= nil then return cached end
    local cell = getCell()
    local tg = t.target
    local R = P.cfg().SEARCH_RADIUS
    local found = {}
    for x, y in LivingKnox.Geo.squaresAround(tg.x, tg.y, R) do
        local sq = cell:getGridSquare(x, y, tg.z)
        if sq ~= nil and P.X().buildingId(sq) == tg.b then
            local objs = sq:getObjects()
            local seen = {}
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if o ~= nil and o.getContainerCount ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
                    for ci = 0, o:getContainerCount() - 1 do
                        local ct = o:getContainerByIndex(ci)
                        if ct ~= nil then
                            local ctype = tostring(ct:getType())
                            local k = (seen[ctype] or 0) + 1
                            seen[ctype] = k
                            found[#found + 1] = { key = x .. "," .. y .. "," .. tg.z .. "," .. ctype .. "," .. k,
                                x = x, y = y, z = tg.z, d = LivingKnox.Geo.cheb(x, y, tg.x, tg.y) }
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    local out, used = {}, {}
    for _, f in ipairs(found) do
        if #out >= P.cfg().MAX_CONTAINERS then break end
        local p = P.X().placeBeside(cell, f.x, f.y, f.z, tg.b, used)
        f.place = p
        out[#out + 1] = f
    end
    Ex.state.sites[key] = out
    LivingKnox.Log.info("expedition: group %s trip %d: %d container(s) to search in building %s", gid, t.n, #out, tg.b)
    return out
end

-- Conteneur de clé key sur sa case (relu maintenant) : conteneur et objet porteur, ou nil.
local function containerAt(f)
    local sq = getCell():getGridSquare(f.x, f.y, f.z)
    if sq == nil then return nil end
    local objs = sq:getObjects()
    local seen = {}
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o ~= nil and o.getContainerCount ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
            for ci = 0, o:getContainerCount() - 1 do
                local ct = o:getContainerByIndex(ci)
                if ct ~= nil then
                    local ctype = tostring(ct:getType())
                    local k = (seen[ctype] or 0) + 1
                    seen[ctype] = k
                    if f.x .. "," .. f.y .. "," .. f.z .. "," .. ctype .. "," .. k == f.key then return ct, o end
                end
            end
        end
    end
    return nil
end

local function remaining(t)
    local left, wanted = 0, {}
    for _, w in ipairs(t.want) do
        wanted[w.c] = w.m
        left = left + w.m
    end
    return left, wanted
end

-- Prochain conteneur libre pour le PNJ id : ni fouillé, ni réservé par un autre membre (réservation récente).
local function claimNext(gid, t, id, minute)
    local list = Ex.siteContainers(gid, t)
    local claims = claimsOf(gid, t.n)
    for key, cl in pairs(claims) do
        if cl.id == id then claims[key] = nil end
    end
    for _, f in ipairs(list) do
        local cl = claims[f.key]
        local stale = cl ~= nil and minute - cl.minute > P.cfg().CLAIM_MINUTES
        if not P.inList(t.searched, f.key) and (cl == nil or stale) then
            claims[f.key] = { id = id, minute = minute }
            return f
        end
    end
    return nil, "none"
end

-- Fin de la fouille ? Rend vrai et la raison si l'expédition doit rentrer.
function Ex.searchDone(gid, t, minute)
    local left = remaining(t)
    if left <= 0 then return true, "wants covered" end
    if #t.carry >= t.cap then return true, "load full" end
    if minute >= t.due then return true, "search time over" end
    for _, f in ipairs(Ex.siteContainers(gid, t)) do
        if not P.inList(t.searched, f.key) then return false end
    end
    return true, "nothing left to search"
end

local function carriedOf(gid, n)
    local key = gid .. "#" .. n
    Ex.state.carried[key] = Ex.state.carried[key] or {}
    return Ex.state.carried[key]
end

-- Fouille du conteneur f par le PNJ id (membre mid) : butin vanilla tiré si jamais ouvert, objets manquants pris
-- (catégorie, consommable, manque, charge), retirés du conteneur et des clients. Conteneur marqué fouillé, objets
-- portés écrits au registre dans la même écriture. Rend le nombre d'objets pris.
function Ex.searchContainer(gid, n, f, id, mid)
    local ct, obj = containerAt(f)
    local taken, entries = {}, {}
    local t = P.curOf(gid)
    if t == nil or t.n ~= n then return 0 end
    if ct ~= nil then
        if ct.isExplored ~= nil and not ct:isExplored() then
            -- Premier regard sur ce conteneur : butin vanilla comme à l'ouverture par un joueur.
            if ItemPickerJava ~= nil and ItemPickerJava.fillContainer ~= nil then
                ItemPickerJava.fillContainer(ct, nil)
                Ex.stats.filled = Ex.stats.filled + 1
            end
            ct:setExplored(true)
            if isServer() and obj ~= nil and sendItemsInContainer ~= nil then sendItemsInContainer(obj, ct) end
        end
        local _, wanted = remaining(t)
        local room = t.cap - #t.carry
        local items = ct:getItems()
        local picks = {}
        for j = 0, items:size() - 1 do
            if #picks >= room then break end
            local it = items:get(j)
            local cat = it ~= nil and LivingKnox.Stock.categoryOf(it) or nil
            if cat ~= nil and (wanted[cat] or 0) > 0
                and ((cat ~= "food" and cat ~= "water") or LivingKnox.Stock.consumable(it, cat)) then
                wanted[cat] = wanted[cat] - 1
                picks[#picks + 1] = { it = it, c = cat }
            end
        end
        local carried = carriedOf(gid, n)
        for _, p in ipairs(picks) do
            ct:DoRemoveItem(p.it)
            if isServer() then sendRemoveItemFromContainer(ct, p.it) end
            local i = p.it:getID()
            carried[i] = p.it
            taken[#taken + 1] = p.it:getFullType()
            entries[#entries + 1] = { t = p.it:getFullType(), c = p.c, i = i }
        end
    end
    local G = LivingKnox.Groups
    G.update(function(d)
        local g = d.groups[gid]
        local cur = g and g.trips and g.trips.cur or nil
        if cur == nil or cur.n ~= n then return false, false end
        if not P.inList(cur.searched, f.key) and #cur.searched < 1000 then cur.searched[#cur.searched + 1] = f.key end
        for _, e in ipairs(entries) do
            cur.carry[#cur.carry + 1] = e
            for _, w in ipairs(cur.want) do
                if w.c == e.c and w.m > 0 then
                    w.m = w.m - 1
                    break
                end
            end
        end
        return true, true
    end)
    Ex.stats.searched = Ex.stats.searched + 1
    Ex.stats.taken = Ex.stats.taken + #entries
    LivingKnox.Log.info("expedition: group %s trip %d: %s (%s) searched %s%s: %s", gid, n, tostring(mid), tostring(id), f.key,
        ct == nil and " (gone)" or "", #taken > 0 and table.concat(taken, " ") or "nothing taken")
    return #entries
end

P.setPhase = setPhase
P.memOf = memOf
P.resetSteps = resetSteps
P.standUp = standUp
P.claimsOf = claimsOf
P.remaining = remaining
P.claimNext = claimNext
P.carriedOf = carriedOf
