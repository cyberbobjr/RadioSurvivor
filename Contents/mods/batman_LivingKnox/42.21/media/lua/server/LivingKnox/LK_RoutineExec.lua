-- Living Knox : outils d'exécution partagés des routines des PNJ au foyer (LK05-T03, T04, T07, T10 ; découpés en
-- LK15-T02, ADR D05). Fiche : docs/annexes/conception/routines.md.
-- Aller à une case, regarder, s'asseoir, case voisine d'un objet, geste, quitter une routine (mémoire oubliée, geste
-- remis au repos) et exécuter un plan (Routines.execPlan). Utilisés par LK_Routines.lua, les activités
-- (media/lua/server/LivingKnox/Routines/), l'entretien (LK_Upkeep.lua, Jobs/), le soin, les expéditions et la défense ;
-- Routines.exec est la table publique de ces outils. Autorité seulement : un client MP charge aussi media/lua/server.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"

local Routines = LivingKnox.Routines or {}
LivingKnox.Routines = Routines

-- Directions orthogonales : décalage et angle de setDirectionAngle (y croissant = sud, Directives.ANGLES).
Routines.DIRS = { { 0, -1, 270 }, { 1, 0, 0 }, { 0, 1, 90 }, { -1, 0, 180 } }
local DIRS = Routines.DIRS

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Decisions() return LivingKnox.Decisions end

-- ================================================================ outils de case (pur)

local function buildingId(sq)
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()   -- long au-delà de 2^53 : texte exact (base world-placement.md)
end

-- Case où un corps peut se tenir : praticable (isFree sans compter les personnages), pas un escalier (isFree y est
-- vrai, J/iso/IsoGridSquare.java:2173-2175).
local function standable(sq)
    return sq ~= nil and sq:isFree(false) and not sq:HasStairs()
end

-- Place d'une corvée devant l'objet de la case (x, y) : case voisine (nord, est, sud, ouest) praticable, du bâtiment
-- bid, sans lit, libre dans used, sans mur ni porte fermée entre les deux (isBlockedTo). Rend { x, y, z, a, ox, oy }
-- (a : regard vers l'objet), ou nil.
local function placeBeside(cell, x, y, z, bid, used)
    local osq = cell:getGridSquare(x, y, z)
    if osq == nil then return nil end
    for _, d in ipairs(DIRS) do
        local sx, sy = x + d[1], y + d[2]
        local sq = cell:getGridSquare(sx, sy, z)
        local key = sx .. "," .. sy
        if not used[key] and standable(sq) and (bid == nil or buildingId(sq) == bid) and Routines.bedQuality(sq) == nil
            and not sq:isBlockedTo(osq) then
            used[key] = true
            return { x = sx, y = sy, z = z, a = (d[3] + 180) % 360, ox = x, oy = y }
        end
    end
    return nil
end

-- ================================================================ outils de déplacement

local function entryOf(id)
    local D = LivingKnox.Directives
    return D ~= nil and D.get ~= nil and D.get(id) or nil
end

local function note(id, m, v, why, what)
    if not Decisions().noteIssued(id, v, why) then
        Routines.stats.refused = Routines.stats.refused + 1
        return false
    end
    m.lastV = v
    Routines.stats[what] = Routines.stats[what] + 1
    return true
end

local function faceTo(id, m, a)
    if a == nil then return false end
    local v, why = LivingKnox.Directives.face(id, a)
    if note(id, m, v, why, "faces") then
        m.faceV = v
        return true
    end
    return false
end

-- Geste final de la routine (assis par défaut ; corvées : CHORE_GESTURE).
local function sitDown(id, m, gesture)
    gesture = gesture or Routines.SIT
    local A = LivingKnox.Anim
    if A == nil or A.gestureOf(id) == gesture then return end
    if A.setGesture(id, gesture) then
        m.sat = true
        if gesture == Routines.SIT then
            Routines.stats.sits = Routines.stats.sits + 1
        else
            Routines.stats.gestures = Routines.stats.gestures + 1
        end
    end
end

local function reached(ctx, x, y, z, m, e)
    if ctx.z == z then
        local dx, dy = ctx.x - (x + 0.5), ctx.y - (y + 0.5)
        if math.sqrt(dx * dx + dy * dy) <= LivingKnox.Directives.ARRIVE then return true end
    end
    -- Case visée décalée par l'autorité (plantes, feu de camp à côté) : l'arrivée acceptée compte.
    return m.moveV ~= nil and e ~= nil and e.v == m.moveV and e.done and e.s == "arrived"
end

-- Va à la case (x, y, z) : "here" (arrivé), "moving" (en route ou consigne émise), "failed" (renoncé).
local function goTo(id, ctx, x, y, z, m, e)
    if reached(ctx, x, y, z, m, e) then return "here" end
    if m.moveV ~= nil and e ~= nil and e.v == m.moveV then
        if not e.done then return "moving" end
        m.fails = m.fails + 1   -- trajet clos sans arrivée (échec, arrêt)
        m.moveV = nil
    end
    if m.fails >= cfg().MAX_FAILS then return "failed" end
    -- Case évitée après un trajet "stuck" (Movement.AVOID_MS) : cet échec est déjà compté ; attendre la fin de
    -- l'évitement au lieu de compter le refus comme un second échec (campagnes solo du 2026-11-13 : repas mis de côté
    -- une heure de jeu après un seul trajet bloqué).
    local Mv = LivingKnox.Movement
    if Mv ~= nil and Mv.avoided ~= nil and Mv.avoided(id, x, y, z) ~= nil then return "moving" end
    local v, why = LivingKnox.Directives.moveTo(id, x, y, z, "walk")
    if not note(id, m, v, why, "moves") then
        m.fails = m.fails + 1
        log().debug("npc %s: routine move to %d,%d,%d refused: %s", id, x, y, z, tostring(why))
        return m.fails >= cfg().MAX_FAILS and "failed" or "moving"
    end
    m.moveV = v
    return "moving"
end

-- Case où s'asseoir sans couchage : sur place si le corps est dans le bâtiment du foyer (ou si le foyer est un camp),
-- sinon une case libre près du foyer, dans son bâtiment (LivingKnox.Materialize.placeFor, comme le retour au foyer).
-- Rend x, y, z, ou nil (sur place).
local function sitPlace(ctx)
    local home = ctx.home
    local cell = getCell()
    if home == nil or cell == nil then return nil end
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    local bid = hsq ~= nil and buildingId(hsq) or nil
    if bid == nil then return nil end
    local here = cell:getGridSquare(math.floor(ctx.x), math.floor(ctx.y), ctx.z)
    if here ~= nil and buildingId(here) == bid then return nil end
    local Mat = LivingKnox.Materialize
    local place = Mat ~= nil and Mat.placeFor ~= nil and Mat.placeFor(home, bid, Decisions().CFG.HOME_PLACE_RADIUS) or nil
    if place == nil then return home.x, home.y, home.z end
    return place:getX(), place:getY(), place:getZ()
end

-- Arrêt puis geste (assis par défaut) sur place.
local function sitHere(id, m, e, gesture)
    if m.stopV == nil then
        local v, why = LivingKnox.Directives.stop(id)
        if note(id, m, v, why, "stops") then m.stopV = v end
        return
    end
    if e ~= nil and e.v == m.stopV and e.done then sitDown(id, m, gesture) end
end

local function runRound(id, ctx, plan, m, e)
    local pts = plan.points
    local n = #pts
    if m.k == nil or m.k > n then m.k = plan.start end
    for _ = 1, 2 do
        local p = pts[m.k]
        local res = goTo(id, ctx, p.x, p.y, p.z, m, e)
        if res == "moving" then return end
        if res == "failed" then
            Routines.stats.gaveUp = Routines.stats.gaveUp + 1
            log().debug("npc %s: round point %d,%d skipped", id, p.x, p.y)
        end
        m.k = (m.k % n) + 1
        if m.k == plan.start then Routines.stats.laps = Routines.stats.laps + 1 end
        m.fails, m.moveV = 0, nil
    end
end

-- Outils d'exécution partagés avec l'entretien du foyer (LK05-T10, LK_Upkeep.lua) : même déplacement, regard et geste
-- que les corvées et les repas, mémoire du membre dans Routines.state.npcs (kind « upkeep »).
Routines.exec = { goTo = goTo, faceTo = faceTo, sitDown = sitDown, placeBeside = placeBeside, standable = standable,
    buildingId = buildingId, entryOf = entryOf }

-- ================================================================ exécution d'un plan (autorité)

-- Exécute le plan (Routines.plan ou chorePlan) du membre id pour le comportement st.b, à chaque passage : mémoire du
-- plan (l'ancien plan est quitté d'abord), consignes, geste. Tail de l'ancien Routines.apply (LK15-T02, sans changement).
function Routines.execPlan(id, st, ctx, plan, fresh)
    local mem = Routines.state.npcs
    local m = mem[id]
    if m == nil or m.key ~= plan.key then
        if m ~= nil then Routines.leave(id) end   -- autre plan (relève, réveil, corvée suivante) : debout d'abord
        m = { key = plan.key, kind = plan.kind, fails = 0, chore = plan.chore }
        mem[id] = m
        if plan.chore ~= nil then
            Routines.stats.chores = Routines.stats.chores + 1
            local by = Routines.state.byChore or {}
            Routines.state.byChore = by
            by[plan.chore] = (by[plan.chore] or 0) + 1
            log().debug("npc %s: chore %s (%s, %s)", id, plan.key, tostring(ctx.duty), st.why or st.b)
        else
            log().debug("npc %s: routine %s (%s)", id, plan.key, st.b)
        end
    end
    local gesture = plan.gesture or (plan.sit and Routines.SIT or nil)
    local e = entryOf(id)
    -- Une autre consigne est passée entre-temps (menace, retour au foyer, suite de test) : la routine reprend.
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) then
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
    end
    if plan.kind == "face" then
        if fresh or m.lastV == nil then faceTo(id, m, plan.a) end
    elseif plan.kind == "sit" then
        -- Sans couchage : à l'intérieur d'abord (maison tenue la nuit, I3.3), puis assis.
        if m.place == nil then
            local x, y, z = sitPlace(ctx)
            m.place = x ~= nil and { x = x, y = y, z = z } or false
        end
        if m.place and not m.placed then
            local res = goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
            if res == "moving" then return end
            m.placed = true   -- arrivé ou renoncé : assis là où il est
            e = entryOf(id)
        end
        sitHere(id, m, e, gesture)
    elseif plan.kind == "round" then
        runRound(id, ctx, plan, m, e)
    else
        local res = goTo(id, ctx, plan.x, plan.y, plan.z, m, e)
        if res == "moving" then return end
        if res == "failed" then
            if not m.gaveUp then
                m.gaveUp = true
                Routines.stats.gaveUp = Routines.stats.gaveUp + 1
                log().info("npc %s: cannot reach %s, staying here", id, plan.key)
            end
            if gesture ~= nil then sitHere(id, m, e, gesture) elseif m.faceV == nil then faceTo(id, m, plan.a) end
            return
        end
        if m.faceV == nil then
            faceTo(id, m, plan.a)
            return
        end
        if gesture ~= nil and e ~= nil and e.v == m.faceV and e.done then sitDown(id, m, gesture) end
    end
end

-- ================================================================ fin de routine

-- Fin d'une routine (le membre passe à un comportement sans routine) : geste de routine (assis, corvée) -> debout,
-- mémoire oubliée ; repas pris mais pas encore appliqué (LK05-T07) : appliqué maintenant.
function Routines.leave(id)
    local m = Routines.state.npcs[id]
    if m == nil then return end
    Routines.state.npcs[id] = nil
    Routines.finishMeal(id, m)
    local U = LivingKnox.Upkeep   -- LK05-T10 : tâche d'entretien libérée (reprise par un autre membre)
    if m.kind == "upkeep" and U ~= nil and U.release ~= nil then U.release(id, m) end
    local F = LivingKnox.Fortify   -- LK14-T03 : chantier de barricade libéré
    if m.kind == "fortify" and F ~= nil and F.release ~= nil then F.release(id, m) end
    local A = LivingKnox.Anim
    if A ~= nil and Routines.GESTURES[A.gestureOf(id)] then A.setGesture(id, A.DEFAULT) end
end

function Routines.forget(id)
    local m = Routines.state.npcs[id]
    Routines.state.npcs[id] = nil
    if m ~= nil then Routines.finishMeal(id, m) end
    local U = LivingKnox.Upkeep   -- LK05-T10
    if m ~= nil and m.kind == "upkeep" and U ~= nil and U.release ~= nil then U.release(id, m) end
    local F = LivingKnox.Fortify   -- LK14-T03
    if m ~= nil and m.kind == "fortify" and F ~= nil and F.release ~= nil then F.release(id, m) end
end

return Routines
