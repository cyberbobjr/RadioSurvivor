-- Living Knox : expéditions, exécution du comportement « expedition » : fouille, tirages et trajets (Expeditions.apply)
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ exécution (comportement « expedition »)

-- Case de retour au foyer (comme LK_Decisions : case libre près du foyer).
local function homeSpot(home, rank)
    local sq, bid = LivingKnox.Materialize.homeSquare(home)
    if sq == nil then return home.x, home.y, home.z end
    local place = P.freeNear(home.x, home.y, home.z, bid, LivingKnox.Decisions.CFG.HOME_PLACE_RADIUS, rank)
    if place == nil then return home.x, home.y, home.z end
    return place:getX(), place:getY(), place:getZ()
end

local function rankIn(list, v)
    for i, x in ipairs(list) do
        if x == v then return i end
    end
    return 1
end

-- Conteneur écarté sans fouille (hors d'atteinte) : marqué fouillé, réservation rendue, rien n'est pris.
local function skipContainer(gid, n, f, id, why)
    LivingKnox.Log.info("expedition: group %s trip %d: npc %s skips %s (%s)", gid, n, tostring(id), f.key, why)
    LivingKnox.Groups.update(function(d)
        local cur = d.groups[gid] and d.groups[gid].trips and d.groups[gid].trips.cur
        if cur == nil or cur.n ~= n or P.inList(cur.searched, f.key) then return false, false end
        cur.searched[#cur.searched + 1] = f.key
        return true, true
    end)
    P.claimsOf(gid, n)[f.key] = nil
end

-- Fouille des conteneurs du lieu par un membre arrivé (round du genre de repli) : conteneur réservé, place à côté,
-- regard, geste du genre (kind.gesture) RUMMAGE_MINUTES, prise ; retour quand la fouille est finie.
function Ex.searchRound(id, ctx, t, m, e, kind)
    local minute = ctx.minute
    if m.job == nil then
        local f = P.claimNext(ctx.gid, t, id, minute)
        if f == nil then
            P.standUp(id)
            local done, why = Ex.searchDone(ctx.gid, t, minute)
            if done then P.setPhase(ctx.gid, t.n, "back", minute, why) end
            return
        end
        if f.place == nil then
            skipContainer(ctx.gid, t.n, f, id, "no free square beside it")   -- hors d'atteinte : rien n'est pris
            return
        end
        m.job = f
        P.resetSteps(m)
    end
    local f = m.job
    local claims = P.claimsOf(ctx.gid, t.n)
    if claims[f.key] ~= nil and claims[f.key].id == id then claims[f.key].minute = minute end
    local res = P.X().goTo(id, ctx, f.place.x, f.place.y, f.place.z, m, e)
    if res == "moving" then return end
    if res == "failed" then
        skipContainer(ctx.gid, t.n, f, id, "cannot reach it")
        m.job = nil
        return
    end
    if m.faceV == nil then
        P.X().faceTo(id, m, f.place.a)
        return
    end
    if m.since == nil then
        local entry = P.X().entryOf(id)
        if entry == nil or entry.v ~= m.faceV or not entry.done then return end
        P.X().sitDown(id, m, kind.gesture)
        m.since = minute
        return
    end
    if minute - m.since < P.cfg().RUMMAGE_MINUTES then return end
    Ex.searchContainer(ctx.gid, t.n, f, id, ctx.mid)
    claims[f.key] = nil
    m.job, m.since = nil, nil
    P.standUp(id)
    local cur = P.curOf(ctx.gid)
    if cur ~= nil and cur.n == t.n then
        local done, why = Ex.searchDone(ctx.gid, cur, minute)
        if done then P.setPhase(ctx.gid, t.n, "back", minute, why) end
    end
end

-- ================================================================ genres à tirages (LK05-T11, LK16-T08)

-- Fin des tirages ? Rend vrai et la raison si l'équipe doit rentrer.
function Ex.drawnDone(t, minute)
    local left = P.remaining(t)
    if left <= 0 then return true, "wants covered" end
    if #t.carry >= t.cap then return true, "load full" end
    if (t.k or 0) >= (t.r or 0) then return true, "foraging done" end
    if minute >= t.due then return true, "search time over" end
    return false
end

local function addFinds(cur, entries)
    for _, e in ipairs(entries) do
        if #cur.carry >= cur.cap then break end
        cur.carry[#cur.carry + 1] = e
        for _, w in ipairs(cur.want) do
            if w.c == e.c and w.m > 0 then
                w.m = w.m - 1
                break
            end
        end
    end
end

-- Tirage suivant (kind.draw) de l'expédition à tirages n du groupe gid (membre mid), conditions du moment
-- (kind.conditions) ; objets notés à créer au dépôt. Rend le nombre d'objets notés.
function Ex.drawNext(gid, n, mid)
    local t = P.curOf(gid)
    local kind = t ~= nil and Ex.kindOf(t) or nil
    if kind == nil or kind.draw == nil or t.n ~= n or (t.k or 0) >= (t.r or 0) or #t.carry >= t.cap then
        return 0
    end
    local k = (t.k or 0) + 1
    local c = kind.conditions()
    local entries, text = kind.draw(gid, t, k, c)
    local added = 0
    LivingKnox.Groups.update(function(d)
        local g = d.groups[gid]
        local cur = g and g.trips and g.trips.cur or nil
        if cur == nil or cur.n ~= n or cur.kind ~= t.kind or (cur.k or 0) >= k then return false, false end
        cur.k = k
        local before = #cur.carry
        addFinds(cur, entries)
        added = #cur.carry - before
        return true, true
    end)
    Ex.stats.taken = Ex.stats.taken + added
    LivingKnox.Log.info("expedition: group %s trip %d: %s %s (draw %d of %d, %s%s): %s", gid, n, tostring(mid), kind.verb, k,
        t.r or 0, tostring(t.target.room), kind.detail(c), text)
    return added
end

-- Tirages d'un membre arrivé (round d'un genre à tirages) : à sa place (retour après une interruption), tourné vers
-- l'angle de sa place s'il en a un, geste du genre, un tirage toutes les kind.minutes() minutes de jeu.
function Ex.drawnRound(id, ctx, t, m, e, kind)
    local minute = ctx.minute
    local A = LivingKnox.Anim
    if m.spot ~= nil and not m.stay then
        local res = P.X().goTo(id, ctx, m.spot.x, m.spot.y, m.spot.z, m, e)
        if res == "moving" then
            m.since = nil
            return
        end
        if res == "failed" then m.stay = true end   -- place hors d'atteinte : il cueille là où il est
    end
    if m.spot ~= nil and m.spot.a ~= nil and not m.faced and not m.stay then
        -- Pêche : tourné vers l'eau d'abord (comme la fouille : consigne de regard puis attente de sa fin).
        if m.faceV == nil then
            P.X().faceTo(id, m, m.spot.a)
            return
        end
        local entry = P.X().entryOf(id)
        if entry == nil or entry.v ~= m.faceV or not entry.done then return end
        m.faced = true
    end
    if m.since == nil then
        P.X().sitDown(id, m, kind.gesture)
        m.since = minute
        return
    end
    if A ~= nil and A.gestureOf(id) ~= kind.gesture then P.X().sitDown(id, m, kind.gesture) end
    if minute - m.since < kind.minutes() then return end
    m.since = minute
    Ex.drawNext(ctx.gid, t.n, ctx.mid)
    local cur = P.curOf(ctx.gid)
    if cur ~= nil and cur.n == t.n then
        local done, why = Ex.drawnDone(cur, minute)
        if done then P.setPhase(ctx.gid, t.n, "back", minute, why) end
    end
end

-- Place d'un membre à l'arrivée (kind.spot : case et angle du regard), ou nil (point visé).
local function spotFor(t, rank)
    local kind = Ex.kindOf(t)
    if kind == nil or kind.spot == nil then return nil end
    return kind.spot(t, rank)
end

-- Vrai si un membre de l'équipe de l'expédition t du groupe gid est arrivé au lieu (mémoire de cette session).
function Ex.anyArrived(gid, t)
    for _, m in pairs(Ex.state.npcs) do
        if m.gid == gid and m.n == t.n and m.arrived and P.inList(t.team, m.mid) then return true end
    end
    return false
end

-- Applique l'expédition au membre (contexte ctx du cadre de décision), à chaque passage.
function Ex.apply(id, st, ctx, fresh)
    local t = P.curOf(ctx.gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not P.inList(t.team, ctx.mid) then return end
    local m = P.memOf(id, ctx.gid, t.n, ctx.mid)
    local e = P.X().entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) then
        -- Une autre consigne est passée entre-temps (menace, suite de test) : l'étape en cours reprend.
        P.resetSteps(m)
        m.since = nil
    end
    if m.phase ~= t.phase then
        if m.phase == "search" then
            P.standUp(id)
            m.job, m.since = nil, nil
        end
        if t.phase == "back" then P.resetSteps(m) end   -- un trajet vers le lieu en cours ne repart pas pour rien
        m.phase = t.phase
    end
    if t.phase == "out" or (t.phase == "search" and not m.arrived) then
        if m.spot == nil then
            local tg = t.target
            local sq, a = spotFor(t, rankIn(t.team, ctx.mid))
            m.spot = sq ~= nil and { x = sq:getX(), y = sq:getY(), z = sq:getZ(), a = a } or { x = tg.x, y = tg.y, z = tg.z }
        end
        local res = P.X().goTo(id, ctx, m.spot.x, m.spot.y, m.spot.z, m, e)
        if res == "moving" then return end
        m.arrived = true
        P.resetSteps(m)
        e = P.X().entryOf(id)
        Ex.stats.arrived = Ex.stats.arrived + 1
        LivingKnox.Log.info("expedition: npc %s (%s %s) %s building %s", id, ctx.gid, ctx.mid,
            res == "failed" and "gave up reaching" or "reached", t.target.b)
        if t.phase == "out" then P.setPhase(ctx.gid, t.n, "search", ctx.minute, ctx.mid .. " arrived") end
        t = P.curOf(ctx.gid)
        if t == nil then return end
        m.phase = t.phase
    end
    if t.phase == "search" then
        local kind = Ex.kindOf(t)
        if kind ~= nil then kind.round(id, ctx, t, m, e, kind) end
        return
    end
    if t.phase == "back" then
        -- Dépôt ouvert par un membre qui a été au lieu (il porte le butin) ; mémoire perdue (redémarrage) : le premier.
        if ctx.atHome and (m.arrived or not Ex.anyArrived(ctx.gid, t)) then
            P.standUp(id)
            P.setPhase(ctx.gid, t.n, "deliver", ctx.minute, ctx.mid .. " back home")
            Ex.deliver(ctx.gid)
            return
        end
        if m.home == nil then
            local x, y, z = homeSpot(ctx.home, rankIn(t.team, ctx.mid))
            m.home = { x = x, y = y, z = z }
        end
        P.X().goTo(id, ctx, m.home.x, m.home.y, m.home.z, m, e)
    end
end

P.addFinds = addFinds
