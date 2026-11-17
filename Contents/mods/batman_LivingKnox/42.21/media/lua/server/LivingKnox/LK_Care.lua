-- Living Knox : soins des membres blessés au foyer, côté autorité (LK07-T03, LK21-T05). Fiche : docs/annexes/conception/
-- sante.md, section « Saignement et soins » ; ADR docs/architecture/decisions/adr-blessures-soins.md, D05 et D06.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce module décide QUI soigne QUI, demande le soin le plus urgent au registre des soins (LK_CareTreatments.lua,
-- Care/LK_Treat_<Id>.lua), prend le matériel par les sources (LK_CareSupplies.lua) et mène les gestes, avec les outils
-- des routines (Routines.exec). Il ne contient aucune règle propre à un soin : matériel, durée, geste et effet sur la
-- plaie viennent du soin inscrit. Il ne touche les plaies que par Health.wounds et Health.woundsChanged (LK_Health).
--
-- Blessés à soigner (« patients ») d'un groupe : membres présents au foyer (Routines.present), incarnés, dont une plaie
-- demande un soin inscrit (Care.treatable). Ordre : saignement décroissant, santé croissante, numéro.
-- Soignant : le médecin du groupe d'abord (membre dont le rôle permet « heal », ou poste « carer » ; jamais un médecin
-- qui saigne lui-même : il se soigne d'abord), libre, le plus petit numéro ; sinon le blessé se soigne lui-même. Une
-- tâche par blessé, un blessé par soignant ; tâches refaites au plus une fois par minute de jeu et par groupe.
-- Compétence de soin d'un PNJ (niveau Doctor du vanilla, absent d'un zombie) : CFG.LEVEL.medic pour un médecin,
-- CFG.LEVEL.other sinon (LK21-T07 la simulera par rôle).
-- Exécution (Care.apply, extension de recouvrement inscrite dans LivingKnox.Decisions, champ cover : comportements calmes
-- CALM, au foyer ; toute menace, fuite, combat ou défense l'interrompt) :
--   find    : soin le plus urgent faisable (Care.choose) avec le matériel des sources ; rien de faisable faute de
--             matériel : pénurie au journal du groupe (Stock.reportShortage, catégorie « medical ») et soins du groupe
--             mis de côté SHORTAGE_MINUTES ; le saignement continue et peut tuer (LK_Health) ;
--   go/face/take : du matériel est au foyer : le soignant va à une case libre à côté du conteneur, se tourne vers lui,
--             fouille (TAKE_GESTURE, TAKE_MINUTES) et prend le matériel (Care.takeMaterials : il passe dans son
--             inventaire ; rien n'est créé) ;
--   patient/pface : le médecin va à côté du blessé et se tourne vers lui ; un blessé seul reste sur place ;
--   treat   : geste du soin pendant la durée de l'action vanilla (unités maxTime, TICKS_PER_SECOND par seconde réelle,
--             J/GameTime.java:911-917), puis le soin est appliqué UNE fois (Care.finish) : matériel utilisé
--             (consume du soin), effet sur la plaie, plaies enregistrées, journal du groupe (kind « care »).
-- Soin interrompu avant la fin : rien n'est appliqué ; le matériel pris reste dans l'inventaire du soignant (source
-- « carer », reprise au soin suivant). Mémoire (tâches, phases) : non sauvegardée ; les plaies le sont avec le registre
-- des corps.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Health"
require "LivingKnox/LK_WoundContext"
require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée plus bas

local Care = LivingKnox.Care or {}
LivingKnox.Care = Care

-- Comportements de la cascade pendant lesquels un soin peut être mené (au foyer seulement).
Care.CALM = { home = true, rest = true, sleep = true, guard = true, patrol = true, chore = true, meal = true }
-- Geste de la prise au foyer (nœud généré par tools/gen_animsets.py, déjà utilisé par les routines).
Care.TAKE_GESTURE = "rummage"
Care.LOG_KIND = "care"
Care.TICKS_PER_SECOND = 48   -- unités maxTime d'une action par seconde réelle (J/GameTime.java:911-917)

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche).
Care.CFG = Care.CFG or {
    TAKE_MINUTES = 1,         -- minutes de jeu à fouiller le conteneur avant de prendre le matériel
    SHORTAGE_MINUTES = 60,    -- rien de faisable faute de matériel : soins du groupe mis de côté (minutes de jeu)
    FAIL_MINUTES = 30,        -- soignant qui n'atteint pas le stock ou le blessé : aucune tâche pendant ce délai
    NEAR = 2,                 -- cases : le blessé n'a pas bougé de plus depuis le choix de la place du médecin
    TAKE_TRIES = 2,           -- matériel parti entre le repérage et la prise : recherches au plus
    LEVEL = { medic = 3, other = 0 },   -- niveau de soin simulé (Doctor 0..10)
}

Care.state = Care.state or { npcs = {}, tasks = {}, aside = {}, failed = {}, assigned = {} }
Care.stats = Care.stats or { tasks = 0, selfCare = 0, items = 0, treated = 0, aborted = 0, shortages = 0 }

local function cfg() return Care.CFG end
local function exec() return LivingKnox.Routines.exec end
local function wctx() return LivingKnox.WoundContext.current() end

-- ================================================================ blessés et soignants

local function isMedic(g, m)
    if m.duty == "carer" then return true end
    local allowed = LivingKnox.Decisions.allowedOf(g.type, m.role)
    return allowed.heal == true
end

local function bodyOf(m)
    local B = LivingKnox.Bodies
    if m == nil or m.npc == nil or B == nil or B.find == nil then return nil end
    return (B.find(m.npc))
end

-- Blessés à soigner du groupe g (registre) : { { mid, npc, bleed, health, number }, ... } triés (voir l'en-tête).
function Care.patients(gid, g)
    local H = LivingKnox.Health
    local ctx = wctx()
    local out = {}
    for _, mid in ipairs(LivingKnox.Routines.present(g)) do
        local m = g.members[mid]
        local list = m.npc ~= nil and bodyOf(m) ~= nil and H.wounds(m.npc) or nil
        if list ~= nil and #Care.treatable(list, ctx) > 0 then
            out[#out + 1] = { mid = mid, npc = m.npc, bleed = H.bleeding(m.npc),
                health = LivingKnox.Decisions.healthOf(m), number = LivingKnox.Groups.memberNumber(mid) or 0 }
        end
    end
    table.sort(out, function(a, b)
        if a.bleed ~= b.bleed then return a.bleed > b.bleed end
        if a.health ~= b.health then return a.health < b.health end
        return a.number < b.number
    end)
    return out
end

local function failedAt(id, minute)
    local until_ = Care.state.failed[id]
    if until_ == nil then return false end
    if minute >= until_ then
        Care.state.failed[id] = nil
        return false
    end
    return true
end

-- Tâches du groupe gid encore valables (blessé à soigner, soignant vivant et incarné) ; rend les soignants occupés.
local function keepTasks(gid, g, wanted)
    local busy = {}
    for pid, t in pairs(Care.state.tasks) do
        if t.gid == gid then
            local carer = g.members[t.cmid]
            if wanted[pid] == nil or carer == nil or not carer.alive or bodyOf(carer) == nil then
                Care.state.tasks[pid] = nil
            else
                busy[t.carer] = true
            end
        end
    end
    return busy
end

-- Médecins libres du groupe g (présents, incarnés, ne saignent pas), par numéro.
local function medicsOf(g)
    local out = {}
    for _, mid in ipairs(LivingKnox.Routines.present(g)) do
        local m = g.members[mid]
        if m.npc ~= nil and isMedic(g, m) and LivingKnox.Health.bleeding(m.npc) <= 0 and bodyOf(m) ~= nil then
            out[#out + 1] = { mid = mid, npc = m.npc }
        end
    end
    return out
end

-- Soignant du blessé p : premier médecin libre, sinon lui-même ; ou nil.
local function carerFor(p, medics, busy, minute)
    for _, md in ipairs(medics) do
        if md.npc ~= p.npc and not busy[md.npc] and not failedAt(md.npc, minute) then return md end
    end
    if not busy[p.npc] and not failedAt(p.npc, minute) then return { mid = p.mid, npc = p.npc } end
    return nil
end

-- Tâches du groupe gid refaites (au plus une fois par minute de jeu) : tâches invalides retirées, chaque blessé sans
-- soignant reçoit un médecin libre, sinon lui-même. Rend la table des tâches (patient -> tâche).
function Care.assign(gid, g, minute)
    local st = Care.state
    if st.assigned[gid] == minute then return st.tasks end
    st.assigned[gid] = minute
    local list = Care.patients(gid, g)
    local wanted = {}
    for _, p in ipairs(list) do wanted[p.npc] = p end
    local busy = keepTasks(gid, g, wanted)
    local medics = medicsOf(g)
    for _, p in ipairs(list) do
        local carer = st.tasks[p.npc] == nil and carerFor(p, medics, busy, minute) or nil
        if carer ~= nil then
            busy[carer.npc] = true
            local own = carer.npc == p.npc
            local cm = g.members[carer.mid]
            st.tasks[p.npc] = { gid = gid, pmid = p.mid, carer = carer.npc, cmid = carer.mid, medic = not own,
                level = isMedic(g, cm) and cfg().LEVEL.medic or cfg().LEVEL.other, minute = minute }
            Care.stats.tasks = Care.stats.tasks + 1
            if own then Care.stats.selfCare = Care.stats.selfCare + 1 end
            LivingKnox.Log.info("group %s: %s %s (bleeding %.4f per hour, health %d%%)", gid, carer.mid,
                own and "treats its own wound" or ("goes to treat " .. p.mid), p.bleed,
                math.floor(p.health * 100 + 0.5))
        end
    end
    return st.tasks
end

-- Vrai si le PNJ id est le blessé d'une tâche de soin en cours (LK18-T02 : il ne s'écarte pas pour un passage).
function Care.caredFor(id)
    return Care.state.tasks[id] ~= nil
end

-- Tâche dont le PNJ id est le soignant : identifiant du blessé, tâche ; ou nil.
function Care.taskOf(id)
    for pid, t in pairs(Care.state.tasks) do
        if t.carer == id then return pid, t end
    end
    return nil
end

-- ================================================================ matériel et soin appliqué

-- Contexte des sources de matériel pour la mémoire de soin m.
local function supplyCtx(m)
    local B = LivingKnox.Bodies
    return { gid = m.gid, use = m.medic and ("care of " .. tostring(m.pmid)) or "own wound",
        carer = { id = m.carer, mid = m.cmid, body = B.find(m.carer) },
        patient = { id = m.patient, mid = m.pmid, body = B.find(m.patient) } }
end

-- Plan de soin du blessé de m (Care.choose avec le matériel des sources), ou nil et la raison.
local function planFor(m)
    local list = LivingKnox.Health.wounds(m.patient)
    if list == nil then return nil, "patient unknown" end
    local sctx = supplyCtx(m)
    return Care.choose(list, wctx(), function(o) return (Care.findMaterials(o, sctx)) end)
end

-- Matériel du plan utilisé (consume du soin) dans l'inventaire du soignant : used[id] = info, et types utilisés.
local function useMaterials(plan, inv)
    local t = Care.treatmentById[plan.id]
    local used, types = {}, {}
    for _, mat in ipairs(t.options[plan.option].materials) do
        local p = plan.picks[mat.id]
        used[mat.id] = mat.consume(p.item, inv)
        types[#types + 1] = used[mat.id].type
    end
    return used, types
end

local function logCare(m, plan, part, types)
    local text = string.format("%s %s: %s on %s with %s", tostring(m.cmid),
        m.medic and ("treated " .. tostring(m.pmid)) or "treated its own wound", plan.id, tostring(part),
        #types > 0 and table.concat(types, ", ") or "bare hands")
    local G = LivingKnox.Groups
    if G.addLog ~= nil then G.addLog(m.gid, Care.LOG_KIND, text) end
    LivingKnox.Log.info("group %s %s", tostring(m.gid), text)
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(m.gid, m.cmid, "care", text) end
end

-- Soin du plan de m appliqué une seule fois : matériel utilisé, effet sur la plaie, plaies enregistrées, journal. Rend
-- vrai si la plaie a changé.
function Care.finish(m)
    local plan = m ~= nil and m.plan or nil
    if plan == nil or m.applied then return false end
    m.applied = true
    local H = LivingKnox.Health
    local list = H.wounds(m.patient)
    local body = LivingKnox.Bodies.find(m.carer)
    local ctx = wctx()
    local w = list ~= nil and Care.target(list, ctx, plan) or nil
    if w == nil or body == nil then
        LivingKnox.Log.info("npc %s: %s of %s not applied (wound or carer gone)", tostring(m.carer), plan.id,
            tostring(m.patient))
        return false
    end
    local inv = body:getInventory()
    local used, types = useMaterials(plan, inv)
    local done = Care.treatmentById[plan.id].effect(w, used, { rnd = ctx.rnd, level = m.level, inv = inv, wctx = ctx })
    H.woundsChanged(m.patient)
    Care.stats.treated = Care.stats.treated + 1
    logCare(m, plan, w.part, types)
    return done == true
end

-- ================================================================ déroulé du soin

-- Fin du soin du PNJ id (comportement non calme, plus de tâche, corps retiré) : tâche libérée, geste de soin -> debout.
-- Rien n'est appliqué (le matériel pris reste au soignant). Rend vrai si une mémoire de soin existait.
function Care.leave(id)
    for pid, t in pairs(Care.state.tasks) do
        if t.carer == id then Care.state.tasks[pid] = nil end   -- tâche rendue (reprise au prochain choix)
    end
    local m = Care.state.npcs[id]
    if m == nil then return false end
    Care.state.npcs[id] = nil
    if m.phase ~= "done" then
        Care.stats.aborted = Care.stats.aborted + 1
        LivingKnox.Log.debug("npc %s: care of %s left in phase %s", id, tostring(m.patient), tostring(m.phase))
    end
    local A = LivingKnox.Anim
    local g = A ~= nil and A.gestureOf(id) or nil
    if g ~= nil and (g == Care.TAKE_GESTURE or g == m.gesture) then A.setGesture(id, A.DEFAULT) end
    return true
end

-- Soin abandonné, mémoire quittée ; minutes : aucune tâche pour ce soignant pendant ce délai.
local function abort(id, m, ctx, why, minutes)
    m.phase = "done"
    Care.stats.aborted = Care.stats.aborted + 1
    if minutes ~= nil then Care.state.failed[id] = ctx.minute + minutes end
    LivingKnox.Log.info("npc %s: care of %s given up: %s", id, tostring(m.patient), tostring(why))
    Care.leave(id)
end

local function shortage(id, m, ctx)
    local S = LivingKnox.Stock
    if S ~= nil and S.reportShortage ~= nil then S.reportShortage(ctx.gid, "medical", ctx.mid) end
    Care.stats.shortages = Care.stats.shortages + 1
    Care.state.aside[ctx.gid] = ctx.minute + cfg().SHORTAGE_MINUTES
    for pid, t in pairs(Care.state.tasks) do
        if t.gid == ctx.gid and t.carer ~= id then Care.state.tasks[pid] = nil end
    end
    abort(id, m, ctx, "no material to treat a wound", nil)
end

local function resetMove(m)
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
end

local function homeBuilding(g)
    local cell = getCell()
    local home = g.home
    local hsq = cell ~= nil and type(home) == "table" and cell:getGridSquare(home.x, home.y, home.z) or nil
    return hsq ~= nil and exec().buildingId(hsq) or nil
end

-- Geste du soin : le soignant s'agenouille (geste du soin) pour la durée de l'action vanilla.
local function startTreat(id, m)
    local t = Care.treatmentById[m.plan.id]
    local units = t.options[m.plan.option].duration(m.level)
    m.gesture = Care.gestureOf(t)
    exec().sitDown(id, m, m.gesture)
    m.untilMs = getTimestampMs() + math.max(0, units) * 1000 / Care.TICKS_PER_SECOND
    m.phase = "treat"
end

-- Après le matériel en main : le médecin va vers le blessé, le blessé seul soigne sur place.
local function toTreatment(id, m)
    if m.medic then
        resetMove(m)
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) == Care.TAKE_GESTURE then A.setGesture(id, A.DEFAULT) end
        m.phase = "patient"
        return
    end
    startTreat(id, m)
end

local PHASES = {}

-- Rend "hold" (le soin tient le membre), "stop" (soin quitté) ou "next" (phase suivante dans ce passage).
function PHASES.find(id, m, ctx, g)
    local plan, why = planFor(m)
    if plan == nil then
        if why == "material" then shortage(id, m, ctx) else abort(id, m, ctx, why, cfg().FAIL_MINUTES) end
        return "stop"
    end
    m.plan = plan
    local spot = Care.placeOf(plan.picks)
    if spot == nil then
        local ok, err = Care.takeMaterials(plan.picks, supplyCtx(m))
        if not ok then
            abort(id, m, ctx, err, cfg().FAIL_MINUTES)
            return "stop"
        end
        toTreatment(id, m)
        return m.phase == "treat" and "hold" or "next"
    end
    local cell = getCell()
    local place = cell ~= nil and exec().placeBeside(cell, spot.x, spot.y, spot.z, homeBuilding(g), {}) or nil
    if place == nil then
        abort(id, m, ctx, "no free square beside " .. spot.key, cfg().FAIL_MINUTES)
        return "stop"
    end
    m.spot, m.place, m.phase = spot, place, "go"
    return "next"
end

function PHASES.go(id, m, ctx, _, e)
    local res = exec().goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
    if res == "moving" then return "hold" end
    if res == "failed" then
        abort(id, m, ctx, "cannot reach " .. m.spot.key, cfg().FAIL_MINUTES)
        return "stop"
    end
    m.phase = "face"
    return "next"
end

function PHASES.face(id, m, ctx)
    local X = exec()
    if m.faceV == nil then
        X.faceTo(id, m, m.place.a)
        return "hold"
    end
    local e = X.entryOf(id)
    if e == nil or e.v ~= m.faceV or not e.done then return "hold" end
    X.sitDown(id, m, Care.TAKE_GESTURE)
    m.since, m.phase = ctx.minute, "take"
    return "hold"
end

function PHASES.take(id, m, ctx)
    if ctx.minute - m.since < cfg().TAKE_MINUTES then return "hold" end
    local ok, why = Care.takeMaterials(m.plan.picks, supplyCtx(m))
    if not ok then
        m.tries = m.tries + 1
        LivingKnox.Log.debug("npc %s: material not taken at %s: %s", id, m.spot.key, tostring(why))
        if m.tries >= cfg().TAKE_TRIES then
            abort(id, m, ctx, why, cfg().FAIL_MINUTES)
            return "stop"
        end
        m.phase, m.spot, m.place, m.plan = "find", nil, nil, nil
        resetMove(m)
        return "hold"
    end
    Care.stats.items = Care.stats.items + 1
    toTreatment(id, m)
    return m.phase == "treat" and "hold" or "next"
end

-- Va à côté du blessé (médecin) : "here", "moving", "failed" ou "gone" (corps du blessé absent).
local function toPatient(id, ctx, m, e)
    local body = LivingKnox.Bodies.find(m.patient)
    if body == nil then return "gone" end
    local px, py, pz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
    if m.pplace ~= nil and (pz ~= m.pplace.z or LivingKnox.Geo.cheb(px, py, m.pplace.ox, m.pplace.oy) > cfg().NEAR) then
        m.pplace, m.moveV, m.faceV, m.fails = nil, nil, nil, 0   -- le blessé a bougé : nouvelle place
    end
    if m.pplace == nil then
        local cell = getCell()
        m.pplace = cell ~= nil and exec().placeBeside(cell, px, py, pz, nil, {}) or nil
        if m.pplace == nil then return "failed" end
    end
    return exec().goTo(id, ctx, m.pplace.x, m.pplace.y, m.pplace.z, m, e)
end

function PHASES.patient(id, m, ctx, _, e)
    local res = toPatient(id, ctx, m, e)
    if res == "moving" then return "hold" end
    if res == "gone" or res == "failed" then
        abort(id, m, ctx, res == "gone" and "patient body gone" or "cannot reach the patient",
            res == "failed" and cfg().FAIL_MINUTES or nil)
        return "stop"
    end
    m.phase = "pface"
    return "next"
end

function PHASES.pface(id, m)
    local X = exec()
    if m.faceV == nil then
        X.faceTo(id, m, m.pplace.a)
        return "hold"
    end
    local e = X.entryOf(id)
    if e == nil or e.v ~= m.faceV or not e.done then return "hold" end
    startTreat(id, m)
    return "hold"
end

function PHASES.treat(id, m)
    local A = LivingKnox.Anim
    if A ~= nil and A.gestureOf(id) ~= m.gesture then exec().sitDown(id, m, m.gesture) end
    if getTimestampMs() < m.untilMs then return "hold" end
    Care.finish(m)
    m.phase = "done"
    Care.leave(id)   -- soin fini : debout, la routine reprend dans ce passage
    return "stop"
end

-- Mémoire de soin du PNJ id pour le blessé pid (tâche task), créée si besoin ; nil si aucune tâche.
local function memoryFor(id, ctx, pid, task)
    local m = Care.state.npcs[id]
    if pid == nil or (m ~= nil and m.patient ~= pid) then
        Care.leave(id)
        if pid == nil then return nil end
        m = nil
    end
    if m == nil then
        LivingKnox.Routines.leave(id)   -- routine interrompue (repas pris appliqué, entretien libéré), debout
        m = { carer = id, patient = pid, pmid = task.pmid, cmid = task.cmid, gid = ctx.gid, mid = ctx.mid,
            medic = task.medic, level = task.level, phase = "find", tries = 0, fails = 0 }
        Care.state.npcs[id] = m
        LivingKnox.Log.debug("npc %s: care of %s started (%s)", id, pid, task.medic and "medic" or "self")
    end
    return m
end

-- Une autre consigne est passée pendant une marche (suite de test, autre module) : reprise de la marche en cours.
local function resumeWalk(m, e)
    if m.lastV == nil or (e ~= nil and e.v == m.lastV) then return end
    if m.phase == "go" or m.phase == "face" then
        resetMove(m)
        m.phase = "go"
    elseif m.phase == "patient" or m.phase == "pface" then
        resetMove(m)
        m.phase = "patient"
    end
end

-- Groupe du membre de ctx s'il peut être soigné maintenant (comportement calme au foyer, soins non mis de côté), ou nil.
local function careGroup(st, ctx)
    if st == nil or not Care.CALM[st.b] or ctx.home == nil or not ctx.atHome or ctx.minute == nil then return nil end
    local data = LivingKnox.Groups.state.data
    local g = data ~= nil and data.groups[ctx.gid] or nil
    local aside = Care.state.aside[ctx.gid]
    if g == nil or (aside ~= nil and ctx.minute < aside) then return nil end
    return g
end

-- Soin mené par le PNJ id (contexte ctx du cadre de décision, comportement st.b) : rend vrai si le soin tient le membre
-- pour ce passage (Decisions.apply ne fait alors rien d'autre), faux sinon (soin quitté ou aucune tâche).
function Care.apply(id, st, ctx)
    if not LivingKnox.isAuthority() then return false end
    local g = careGroup(st, ctx)
    if g == nil then
        Care.leave(id)
        return false
    end
    Care.assign(ctx.gid, g, ctx.minute)
    local pid, task = Care.taskOf(id)
    local m = memoryFor(id, ctx, pid, task)
    if m == nil then return false end
    local e = exec().entryOf(id)
    resumeWalk(m, e)
    while PHASES[m.phase] ~= nil do
        local res = PHASES[m.phase](id, m, ctx, g, e)
        if res == "hold" then return true end
        if res == "stop" then return false end
        e = exec().entryOf(id)
    end
    return false
end

-- ================================================================ après une attaque (LK_Defense)

-- Point d'appel de LK_Defense (fin d'une défense du foyer) : les tâches du groupe sont refaites au passage suivant (les
-- blessés de l'attaque ont des plaies, Care.patients les trouve). Rend le nombre de membres de la marque.
function Care.afterAttack(gid, mark)
    if not LivingKnox.isAuthority() or type(mark) ~= "table" or type(mark.wounded) ~= "table" then return 0 end
    Care.state.assigned[gid] = nil
    local n = 0
    for _, mid in ipairs(mark.wounded) do
        if type(mid) == "string" then n = n + 1 end
    end
    if n > 0 then LivingKnox.Log.info("group %s: %d wounded member(s) to treat after the attack", gid, n) end
    return n
end

-- ================================================================ lecture, essais

-- Mémoire de soin du PNJ id (copie), ou nil : { patient, pmid, cmid, medic, level, phase, plan, ... }.
function Care.get(id)
    local m = Care.state.npcs[id]
    if m == nil then return nil end
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

function Care.reset()
    Care.state = { npcs = {}, tasks = {}, aside = {}, failed = {}, assigned = {} }
end

-- LK18-T01 (ADR adr-ceder-le-passage.md D02, fiche passage.md) : priorité de passage du comportement, déclarée ici.
LivingKnox.Passage.priority("care", 80)

-- LK21-T05 (ADR adr-blessures-soins.md D06) : le soin est une extension de recouvrement du cadre de décision (appels
-- par la table du module : un remplacement de Care.apply ou Care.leave, rechargement ou banc, reste celui appelé).
LivingKnox.Decisions.registerExtension({ id = "care", order = 60,
    cover = function(id, st, ctx, fresh) return Care.apply(id, st, ctx, fresh) end,
    forget = function(id) return Care.leave(id) end })

return Care
