-- Living Knox : soins des membres blessés au foyer, côté autorité (LK07-T03). Fiche : docs/conception/sante.md,
-- section « Saignement et soins ». Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Module distinct de LK_Health (choix) : LK_Health tient la santé de référence et le saignement (seul écrivain de
-- npc.hp et npc.bleed) ; ce module décide QUI soigne, prend l'objet au stock et mène les gestes, avec les outils des
-- routines (Routines.exec). Il ne modifie la santé que par Health.stopBleeding et Health.noteHeal.
--
-- Blessés à soigner (« patients ») d'un groupe : membres présents au foyer (Routines.present), incarnés, qui saignent
-- (Health.bleeding > 0) ou notés blessés après une attaque repoussée (Care.afterAttack, appelé par LK_Defense ; note
-- gardée FLAG_HOURS heures, oubliée si la santé est pleine). Ordre : saignement décroissant, santé croissante, numéro.
-- Soigneur : le médecin du groupe d'abord (membre dont le rôle permet « heal », ou poste « carer » ; jamais un médecin
-- qui saigne lui-même : il se soigne d'abord), libre, le plus petit numéro ; sinon le blessé se soigne lui-même. Une
-- tâche par blessé, un blessé par soigneur ; tâches refaites au plus une fois par minute de jeu et par groupe.
-- Exécution (Care.apply, appelé par LivingKnox.Decisions.apply pour les comportements calmes CALM, au foyer ; toute
-- menace, fuite, combat ou défense l'interrompt) : le soigneur va à une case libre à côté du conteneur du foyer qui
-- contient un objet de soin (même règle que les repas), se tourne vers lui, fouille (geste TAKE_GESTURE,
-- TAKE_MINUTES), prend UN objet par LivingKnox.Stock.takeItem (retiré du conteneur et des clients sur un serveur, ôté
-- de la référence du stock dans la même écriture : ni perte ni vol à la relecture ; rien n'est jamais créé) ; puis
-- le médecin va à côté du blessé, se tourne vers lui et s'agenouille (TREAT_GESTURE, TREAT_MINUTES) ; un blessé seul
-- s'agenouille sur place. Le soin est appliqué UNE fois : à la fin, ou plus tôt si le soin est interrompu après la
-- prise (comme un repas) : saignement arrêté (Health.stopBleeding) et santé rendue (Health.noteHeal) = HEAL_PER_POWER
-- x BandagePower de l'objet x hpMax (x MEDIC_FACTOR pour un médecin), journal du groupe (kind « care »).
-- Objet de soin : objet que le vanilla accepte pour panser (InventoryItem.isCanBandage, script CanBandage,
-- J/inventory/InventoryItem.java:2607 ; M/client/ISUI/ISInventoryPaneContextMenu.lua:169) ; un objet propre
-- (getBandagePower >= GOOD_POWER, J/inventory/InventoryItem.java:3088) est préféré aux bandes sales (0,5).
-- Rien au stock : pénurie au journal du groupe (Stock.reportShortage, catégorie « medical ») et soins du groupe mis de
-- côté SHORTAGE_MINUTES ; le saignement continue et peut tuer (LK_Health). Mémoire (tâches, notes, phases) : non
-- sauvegardée ; le saignement, lui, est sauvegardé avec le registre des corps.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Health"

local Care = LivingKnox.Care or {}
LivingKnox.Care = Care

-- Comportements de la cascade pendant lesquels un soin peut être mené (au foyer seulement).
Care.CALM = { home = true, rest = true, sleep = true, guard = true, patrol = true, chore = true, meal = true }
-- Gestes existants (nœuds générés par tools/gen_animsets.py, déjà utilisés par les routines).
Care.TAKE_GESTURE = "rummage"
Care.TREAT_GESTURE = "kneel"
Care.GESTURES = { rummage = true, kneel = true }
Care.LOG_KIND = "care"

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche).
Care.CFG = Care.CFG or {
    TAKE_MINUTES = 1,         -- minutes de jeu à fouiller le conteneur avant de prendre l'objet
    TREAT_MINUTES = 5,        -- minutes de jeu agenouillé à soigner
    HEAL_PER_POWER = 0.03,    -- santé rendue (fraction de hpMax) par point de BandagePower (pansement 4 : 12 %)
    MEDIC_FACTOR = 1.5,       -- soin d'un médecin : santé rendue x 1,5
    GOOD_POWER = 1.5,         -- objet préféré si BandagePower >= (pansement 4, sparadrap 1,5 ; bandes sales 0,5)
    SHORTAGE_MINUTES = 60,    -- rien au stock : soins du groupe mis de côté (minutes de jeu)
    FAIL_MINUTES = 30,        -- soigneur qui n'atteint pas le stock ou le blessé : aucune tâche pendant ce délai
    FLAG_HOURS = 6,           -- blessé noté après une attaque : soigné dans ce délai, sinon oublié
    NEAR = 2,                 -- cases : le blessé n'a pas bougé de plus depuis le choix de la place du médecin
    TAKE_TRIES = 2,           -- objet parti entre le repérage et la prise : recherches au plus
}

Care.state = Care.state or { npcs = {}, tasks = {}, flagged = {}, aside = {}, failed = {}, assigned = {} }
Care.stats = Care.stats or { tasks = 0, selfCare = 0, items = 0, treated = 0, aborted = 0, shortages = 0,
    flagged = 0 }

local function log() return LivingKnox.Log end
local function cfg() return Care.CFG end
local function Groups() return LivingKnox.Groups end
local function Health() return LivingKnox.Health end
local function Routines() return LivingKnox.Routines end
local function exec() return LivingKnox.Routines.exec end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

-- ================================================================ objets de soin

-- Vrai si le vanilla accepte l'objet pour panser une plaie (script CanBandage).
function Care.isCareItem(it)
    return it ~= nil and instanceof(it, "InventoryItem") and it:isCanBandage() == true
end

local function power(it)
    local p = it ~= nil and it:getBandagePower() or 0
    if not finite(p) or p < 0 then return 0 end
    return p
end

local function goodItem(it) return Care.isCareItem(it) and power(it) >= cfg().GOOD_POWER end

-- Premier objet de soin du foyer du groupe gid, propre d'abord : { key, x, y, z, i, t }, ou nil et une raison
-- ("none" : aucun ; autre : stock ou zone illisible).
function Care.findItem(gid)
    local S = LivingKnox.Stock
    if S == nil or S.findItem == nil then return nil, "no stock module" end
    local found, why = S.findItem(gid, goodItem)
    if found ~= nil or why ~= "none" then return found, why end
    return S.findItem(gid, Care.isCareItem)
end

-- ================================================================ blessés et soigneurs

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

-- Note d'après attaque du membre mid du groupe gid, encore valable à la minute minute.
local function flaggedAt(gid, mid, minute)
    local f = Care.state.flagged[gid]
    local at = f and f[mid]
    if at == nil then return false end
    if minute - at > cfg().FLAG_HOURS * 60 or minute < at then
        f[mid] = nil
        return false
    end
    return true
end

-- Blessés à soigner du groupe g (registre) : { { mid, npc, bleed, health, number }, ... } triés (voir l'en-tête).
function Care.patients(gid, g, minute)
    local H = Health()
    local out = {}
    for _, mid in ipairs(Routines().present(g)) do
        local m = g.members[mid]
        if m.npc ~= nil and bodyOf(m) ~= nil then
            local bleed = H.bleeding(m.npc)
            local health = LivingKnox.Decisions.healthOf(m)
            local flagged = flaggedAt(gid, mid, minute)
            if flagged and health >= 1 and bleed <= 0 then
                Care.state.flagged[gid][mid] = nil
                flagged = false
            end
            if bleed > 0 or flagged then
                out[#out + 1] = { mid = mid, npc = m.npc, bleed = bleed, health = health,
                    number = Groups().memberNumber(mid) or 0 }
            end
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

-- Tâches du groupe gid refaites (au plus une fois par minute de jeu) : tâches invalides retirées, chaque blessé sans
-- soigneur reçoit un médecin libre, sinon lui-même. Rend la table des tâches (patient -> tâche).
function Care.assign(gid, g, minute)
    local st = Care.state
    if st.assigned[gid] == minute then return st.tasks end
    st.assigned[gid] = minute
    local list = Care.patients(gid, g, minute)
    local wanted = {}
    for _, p in ipairs(list) do wanted[p.npc] = p end
    local busy = {}
    for pid, t in pairs(st.tasks) do
        if t.gid == gid then
            local carer = g.members[t.cmid]
            if wanted[pid] == nil or carer == nil or not carer.alive or bodyOf(carer) == nil then
                st.tasks[pid] = nil
            else
                busy[t.carer] = true
            end
        end
    end
    -- Médecins libres (présents, incarnés, ne saignent pas), par numéro.
    local medics = {}
    for _, mid in ipairs(Routines().present(g)) do
        local m = g.members[mid]
        if m.npc ~= nil and isMedic(g, m) and Health().bleeding(m.npc) <= 0 and bodyOf(m) ~= nil then
            medics[#medics + 1] = { mid = mid, npc = m.npc }
        end
    end
    for _, p in ipairs(list) do
        if st.tasks[p.npc] == nil then
            local carer
            for _, md in ipairs(medics) do
                if carer == nil and md.npc ~= p.npc and not busy[md.npc] and not failedAt(md.npc, minute) then
                    carer = md
                end
            end
            if carer == nil and not busy[p.npc] and not failedAt(p.npc, minute) then carer = { mid = p.mid, npc = p.npc } end
            if carer ~= nil then
                busy[carer.npc] = true
                local own = carer.npc == p.npc
                st.tasks[p.npc] = { gid = gid, pmid = p.mid, carer = carer.npc, cmid = carer.mid, medic = not own,
                    minute = minute }
                Care.stats.tasks = Care.stats.tasks + 1
                if own then Care.stats.selfCare = Care.stats.selfCare + 1 end
                log().info("group %s: %s %s (bleeding %.4f per hour, health %d%%)", gid, carer.mid,
                    own and "treats its own wound" or ("goes to treat " .. p.mid), p.bleed,
                    math.floor(p.health * 100 + 0.5))
            end
        end
    end
    return st.tasks
end

-- Tâche dont le PNJ id est le soigneur : identifiant du blessé, tâche ; ou nil.
function Care.taskOf(id)
    for pid, t in pairs(Care.state.tasks) do
        if t.carer == id then return pid, t end
    end
    return nil
end

-- ================================================================ soin appliqué

-- Soin pris (m.pending) appliqué une seule fois : saignement arrêté, santé rendue, journal du groupe.
function Care.finish(m)
    if m == nil or not m.pending then return false end
    m.pending = false
    local H = Health()
    local npc = LivingKnox.Store.isReady() and LivingKnox.Identity.get(LivingKnox.Store.data(), m.patient) or nil
    local full = npc and npc.hpMax
    local stopped = H.stopBleeding(m.patient, m.medic and "treated by " .. tostring(m.cmid) or "treated itself")
    local amount = 0
    if finite(full) and full > 0 then
        amount = cfg().HEAL_PER_POWER * (m.power or 0) * full * (m.medic and cfg().MEDIC_FACTOR or 1)
    end
    local hp = amount > 0 and H.noteHeal(m.patient, amount) or nil
    local f = Care.state.flagged[m.gid]
    if f ~= nil then f[m.pmid] = nil end
    Care.stats.treated = Care.stats.treated + 1
    local text = string.format("%s %s with %s (bleeding stopped: %s)", tostring(m.cmid),
        m.medic and ("treated " .. tostring(m.pmid)) or "treated its own wound", m.took and m.took.t or "?",
        stopped > 0 and string.format("%.4f", stopped) or "none")
    local G = Groups()
    if G.addLog ~= nil then G.addLog(m.gid, Care.LOG_KIND, text) end
    log().info("group %s %s, health %s", tostring(m.gid), text, hp and string.format("%.3f", hp) or "unchanged")
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(m.gid, m.cmid, "care", text) end
    return true
end

-- Fin du soin du PNJ id (comportement non calme, plus de tâche, corps retiré) : soin pris appliqué maintenant,
-- tâche libérée, geste de soin -> debout. Rend vrai si une mémoire de soin existait.
function Care.leave(id)
    for pid, t in pairs(Care.state.tasks) do
        if t.carer == id then Care.state.tasks[pid] = nil end   -- tâche rendue (reprise au prochain choix)
    end
    local m = Care.state.npcs[id]
    if m == nil then return false end
    Care.state.npcs[id] = nil
    Care.finish(m)
    if m.phase ~= "done" then
        Care.stats.aborted = Care.stats.aborted + 1
        log().debug("npc %s: care of %s left in phase %s", id, tostring(m.patient), tostring(m.phase))
    end
    local A = LivingKnox.Anim
    if A ~= nil and Care.GESTURES[A.gestureOf(id)] then A.setGesture(id, A.DEFAULT) end
    return true
end

-- Soin abandonné (objet pris : déjà appliqué par l'appelant), mémoire quittée ; minutes : aucune tâche pour ce
-- soigneur pendant ce délai.
local function abort(id, m, ctx, why, minutes)
    m.phase = "done"
    Care.stats.aborted = Care.stats.aborted + 1
    if minutes ~= nil then Care.state.failed[id] = ctx.minute + minutes end
    log().info("npc %s: care of %s given up: %s", id, tostring(m.patient), tostring(why))
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
    abort(id, m, ctx, "nothing to treat a wound in the stock", nil)
end

local function restart(m)
    m.phase, m.spot, m.place = "find", nil, nil
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
end

local function homeBuilding(g)
    local cell = getCell()
    local home = g.home
    local hsq = cell ~= nil and type(home) == "table" and cell:getGridSquare(home.x, home.y, home.z) or nil
    return hsq ~= nil and exec().buildingId(hsq) or nil
end

-- Prend un objet de soin : celui repéré s'il est encore là, sinon le premier du foyer. Rend { i, t, k }, l'objet, ou
-- nil et une raison.
local function takeOne(m, ctx)
    local S = LivingKnox.Stock
    local picked
    local use = m.medic and ("care of " .. tostring(m.pmid)) or "own wound"
    local got, why = S.takeItem(ctx.gid, function(it)
        if it:getID() == m.spot.i and Care.isCareItem(it) then
            picked = it
            return true
        end
        return false
    end, ctx.mid, use)
    if got == nil then
        got, why = S.takeItem(ctx.gid, function(it)
            if Care.isCareItem(it) then
                picked = it
                return true
            end
            return false
        end, ctx.mid, use)
    end
    if got == nil then return nil, why end
    return got, picked
end

-- Va à côté du blessé (médecin) : "here", "moving", "failed" ou "gone" (corps du blessé absent).
local function toPatient(id, ctx, m, e)
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find ~= nil and (B.find(m.patient)) or nil
    if body == nil then return "gone" end
    local px, py, pz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
    if m.pplace ~= nil and (pz ~= m.pplace.z or cheb(px, py, m.pplace.ox, m.pplace.oy) > cfg().NEAR) then
        m.pplace, m.moveV, m.faceV, m.fails = nil, nil, nil, 0   -- le blessé a bougé : nouvelle place
    end
    if m.pplace == nil then
        local cell = getCell()
        m.pplace = cell ~= nil and exec().placeBeside(cell, px, py, pz, nil, {}) or nil
        if m.pplace == nil then return "failed" end
    end
    return exec().goTo(id, ctx, m.pplace.x, m.pplace.y, m.pplace.z, m, e)
end

-- Soin mené par le PNJ id (contexte ctx du cadre de décision, comportement st.b) : rend vrai si le soin tient le membre
-- pour ce passage (Decisions.apply ne fait alors rien d'autre), faux sinon (soin quitté ou aucune tâche).
function Care.apply(id, st, ctx, fresh)
    if not LivingKnox.isAuthority() then return false end
    if st == nil or not Care.CALM[st.b] or ctx.home == nil or not ctx.atHome or ctx.minute == nil then
        Care.leave(id)
        return false
    end
    local data = Groups().state.data
    local g = data ~= nil and data.groups[ctx.gid] or nil
    local aside = Care.state.aside[ctx.gid]
    if g == nil or (aside ~= nil and ctx.minute < aside) then
        Care.leave(id)
        return false
    end
    Care.assign(ctx.gid, g, ctx.minute)
    local pid, task = Care.taskOf(id)
    local m = Care.state.npcs[id]
    if pid == nil or (m ~= nil and m.patient ~= pid) then
        Care.leave(id)
        if pid == nil then return false end
        m = nil
    end
    local X = exec()
    if m == nil then
        Routines().leave(id)   -- routine interrompue (repas pris appliqué, entretien libéré), debout
        m = { patient = pid, pmid = task.pmid, cmid = task.cmid, gid = ctx.gid, mid = ctx.mid, medic = task.medic,
            phase = "find", tries = 0, fails = 0 }
        Care.state.npcs[id] = m
        log().debug("npc %s: care of %s started (%s)", id, pid, task.medic and "medic" or "self")
    end
    local e = X.entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face"
        or m.phase == "patient" or m.phase == "pface") then
        -- Une autre consigne est passée (suite de test, autre module) : reprise de la marche en cours.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = (m.phase == "go" or m.phase == "face") and "go" or "patient"
    end
    if m.phase == "done" then return false end
    if m.phase == "find" then
        local spot, why = Care.findItem(ctx.gid)
        if spot == nil then
            if why == "none" then
                shortage(id, m, ctx)
            else
                abort(id, m, ctx, why, cfg().FAIL_MINUTES)
            end
            return false
        end
        local cell = getCell()
        local place = cell ~= nil and X.placeBeside(cell, spot.x, spot.y, spot.z, homeBuilding(g), {}) or nil
        if place == nil then
            abort(id, m, ctx, "no free square beside " .. spot.key, cfg().FAIL_MINUTES)
            return false
        end
        m.spot, m.place, m.phase = spot, place, "go"
    end
    if m.phase == "go" then
        local res = X.goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return true end
        if res == "failed" then
            abort(id, m, ctx, "cannot reach " .. m.spot.key, cfg().FAIL_MINUTES)
            return false
        end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.faceV == nil then
            X.faceTo(id, m, m.place.a)
            return true
        end
        e = X.entryOf(id)
        if e == nil or e.v ~= m.faceV or not e.done then return true end
        X.sitDown(id, m, Care.TAKE_GESTURE)
        m.since, m.phase = ctx.minute, "take"
        return true
    end
    if m.phase == "take" then
        if ctx.minute - m.since < cfg().TAKE_MINUTES then return true end
        local got, item = takeOne(m, ctx)
        if got == nil then
            m.tries = m.tries + 1
            log().debug("npc %s: nothing taken at %s: %s", id, m.spot.key, tostring(item))
            if m.tries >= cfg().TAKE_TRIES then
                abort(id, m, ctx, item, cfg().FAIL_MINUTES)
                return false
            end
            restart(m)
            return true
        end
        m.took, m.power, m.pending = got, power(item), true
        Care.stats.items = Care.stats.items + 1
        if m.medic then
            m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
            local A = LivingKnox.Anim
            if A ~= nil and Care.GESTURES[A.gestureOf(id)] then A.setGesture(id, A.DEFAULT) end
            m.phase = "patient"
            e = X.entryOf(id)
        else
            X.sitDown(id, m, Care.TREAT_GESTURE)
            m.since, m.phase = ctx.minute, "treat"
            return true
        end
    end
    if m.phase == "patient" then
        local res = toPatient(id, ctx, m, e)
        if res == "moving" then return true end
        if res == "gone" then
            Care.finish(m)   -- objet pris : soin compté (le blessé est parti hors de la zone chargée)
            abort(id, m, ctx, "patient body gone", nil)
            return false
        end
        if res == "failed" then
            Care.finish(m)
            abort(id, m, ctx, "cannot reach the patient", cfg().FAIL_MINUTES)
            return false
        end
        m.phase = "pface"
    end
    if m.phase == "pface" then
        if m.faceV == nil then
            X.faceTo(id, m, m.pplace.a)
            return true
        end
        e = X.entryOf(id)
        if e == nil or e.v ~= m.faceV or not e.done then return true end
        X.sitDown(id, m, Care.TREAT_GESTURE)
        m.since, m.phase = ctx.minute, "treat"
        return true
    end
    if m.phase == "treat" then
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= Care.TREAT_GESTURE then X.sitDown(id, m, Care.TREAT_GESTURE) end
        if ctx.minute - m.since < cfg().TREAT_MINUTES then return true end
        Care.finish(m)
        m.phase = "done"
        Care.leave(id)   -- soin fini : debout, la routine reprend dans ce passage
        return false
    end
    return false
end

-- ================================================================ après une attaque (LK_Defense)

-- Point d'appel de LK_Defense (fin d'une défense du foyer) : les blessés de la marque (santé sous CARE_HEALTH de la
-- défense) sont notés à soigner, même sans saignement. Rend le nombre de membres notés.
function Care.afterAttack(gid, mark)
    if not LivingKnox.isAuthority() or type(mark) ~= "table" or type(mark.wounded) ~= "table" then return 0 end
    local minute = mark.minute or LivingKnox.Decisions.currentMinute()
    if not finite(minute) then return 0 end
    local f = Care.state.flagged[gid] or {}
    Care.state.flagged[gid] = f
    local n = 0
    for _, mid in ipairs(mark.wounded) do
        if type(mid) == "string" then
            f[mid] = minute
            n = n + 1
        end
    end
    Care.state.assigned[gid] = nil
    Care.stats.flagged = Care.stats.flagged + n
    if n > 0 then log().info("group %s: %d wounded member(s) to treat after the attack", gid, n) end
    return n
end

-- ================================================================ lecture, essais

-- Mémoire de soin du PNJ id (copie), ou nil : { patient, pmid, cmid, medic, phase, took, power, pending, ... }.
function Care.get(id)
    local m = Care.state.npcs[id]
    if m == nil then return nil end
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

function Care.reset()
    Care.state = { npcs = {}, tasks = {}, flagged = {}, aside = {}, failed = {}, assigned = {} }
end

return Care
