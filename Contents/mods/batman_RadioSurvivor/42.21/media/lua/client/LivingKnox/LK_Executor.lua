-- Living Knox : exécution des consignes de déplacement par la machine qui simule le corps (LK02-T07).
-- Fiche : docs/annexes/conception/consignes.md. Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Tourne sur un client MP et en solo (un serveur dédié n'exécute pas media/lua/client). Consignes lues :
--   solo : LivingKnox.Directives.entries (même machine) ; rapports remis par appel direct à Directives.onReport ;
--   client MP : consignes "dirState" reçues du serveur, PAR PNJ (LK03-T01) : numéro d'envoi r croissant, un envoi
--     plus ancien (r inférieur ou égal au dernier reçu pour ce PNJ, livraison non ordonnée ou doublon) est ignoré ;
--     { gone } = consigne oubliée (joueur sorti du rayon, PNJ oublié) ; rapports envoyés au serveur ("dirReport").
-- Une consigne n'est exécutée que par la machine qui simule le corps (LivingKnox.ZombieGuard.simulatedHere : client =
-- not isRemoteZombie()) : un zombie distant suit la position réseau et ne peut pas chercher de chemin. Sur un client
-- MP, il faut EN PLUS être l'exécutant désigné par le serveur (o = son compte, bail l) : le serveur ne le désigne
-- qu'après avoir vu le changement de propriétaire, si bien que le nouveau propriétaire reprend l'état publié (étape
-- k comprise) et jamais une consigne que l'ancien a déjà close.
-- Consigne périmée (LK03-T01) : jamais une consigne de numéro v inférieur à la dernière commencée ici pour ce PNJ, ni
-- une consigne (v, bail l) menée ici jusqu'à un état final ; une exécution interrompue (corps disparu ou devenu
-- distant) reprend au même bail depuis la position actuelle. Copie d'un corps apparue ici (chargement, recréation) :
-- demande "dirAsk" au serveur (une fois par ASK_MS et par PNJ), qui renvoie la consigne courante.
--
-- "move" : pathToLocation puis mode pathfind imposé (bPathfind vrai, setMoving(false)) : c'est le mode mesuré par
-- l'essai LK02-T10 (6,5 cases en 8 s, useless GARDÉ : PathFindState ne le teste pas, J/ai/states/PathFindState.java ;
-- en ligne dégagée, pathToAux passerait en walktoward, que useless bloque, J/ai/states/WalkTowardState.java:56).
-- Suivi toutes les EXEC_EVERY images : arrivée à Directives.ARRIVE case du centre de la case visée (même niveau) ->
-- arrêt et rapport "arrived" ; recherche de chemin terminée sans arrivée (PathFindState efface bPathfind en échec comme
-- en succès, J/ai/states/PathFindState.java:51-71) ou sans progrès de PROGRESS cases pendant STALL_MS -> nouvel essai,
-- au plus MAX_RETRIES, puis "failed". Rapport de marche au plus une fois par Directives.REPORT_MS.
-- "stop" : bPathfind et bMoving effacés (transitions vers idle, media/actiongroups/zombie/pathfind/to_idle.xml).
-- "face" : arrêt puis setDirectionAngle (direction transmise aux autres machines par le paquet zombie,
-- J/characters/NetworkZombieAI.java:196, 271).
-- Changement de propriétaire : l'ancien voit la copie devenir distante et abandonne son exécution sans toucher à la
-- copie ; le nouveau, qui n'a aucune exécution en cours pour ce numéro, repart de la position ACTUELLE du corps vers la
-- même case (pas de retour au départ). Les gestes sont réglés par le serveur (LivingKnox.Anim).
-- Plantes cultivées et feux de camp (LK04-T06) : la case visée en est déjà écartée par l'autorité
-- (Directives.moveTo) ; le chemin vanilla peut les traverser (la recherche de chemin d'un zombie n'évite pas les
-- plantes, J/pathfind/nativeCode/PathFindRequest.java:61-81, et le chemin trouvé n'est pas lisible en Lua) : limite
-- documentée dans docs/annexes/conception/consignes.md. Depuis LK05-T12, une consigne dont la ligne droite traverse leur zone
-- porte des points de passage (w, étape k publiée par l'autorité) : chemin cherché vers le point courant, étape
-- suivante à l'arrivée sur ce point (Directives.ARRIVE), annoncée dans le rapport (k) ; un nouveau propriétaire reprend
-- à l'étape publiée.
-- Rapports d'état (LK03-T02, fiche docs/annexes/conception/rapports.md) : position, orientation, activité, santé et pose de
-- chaque corps simulé ici, envoyés par le seul propriétaire réel (exécutant désigné du bail courant s'il y a une
-- consigne) à cadence bornée ("bodyReport", appel direct en solo) ; contrôles dans server/LivingKnox/LK_Reports.lua.
-- Perception (LK05-T01, fiche docs/annexes/conception/perception.md) : LivingKnox.Senses.scan à chaque passage, résumé
-- porté par le rapport d'état (champ sen) ; un changement de ce que voit ou entend le PNJ avance le rapport (MIN_MS).
-- Transfert de propriété (LK03-T03, fiche docs/annexes/conception/consignes.md) : sur un client MP, l'état utile tenu par le
-- serveur arrive par la remise "npcHand" (bail, santé acceptée, arme ; champs réservés étape de routine, cible,
-- munitions). Le nouveau propriétaire l'applique à sa copie dès qu'elle est locale (santé abaissée à la valeur
-- acceptée, jamais relevée ; arme reprise si sa table est plus ancienne) et n'envoie ses rapports d'état qu'après ;
-- copie locale sans remise : demande "dirClaim" (une par CLAIM_MS et par PNJ). L'ancien rend la remise (o = autre
-- compte) et se tait. Reprise rapide : bail ou remise reçus pour soi, ou copie devenue locale alors qu'un bail
-- attendait, déclenchent le passage à l'image suivante (sans attendre EXEC_EVERY). Chaque rapport (consigne ou état)
-- revérifie au moment de l'envoi que la copie est simulée ici et, sur un client, que le bail est le sien.
-- Geste ponctuel (LK04-T13, LivingKnox.Anim.actOf : ouvrir ou refermer une fenêtre, posé par l'autorité) : pendant
-- le geste, corps en marche arrêté (aucun essai compté) et tourné vers l'angle reçu ; chemin relancé à la fin du geste.
-- Un geste qui apparaît avance le passage à l'image suivante.
-- Corps déchargé (LK03-T07) : seules les copies présentes dans la liste des zombies de la cellule comptent
-- (Executor.loadedBodies) ; un corps mis de côté n'est ni exécuté ni rapporté jusqu'à son retour.
-- Blocage (LK04-T05, shared/LivingKnox/LK_Movement.lua) : aucun progrès vers l'étape pendant Movement.STUCK_MS (hors
-- geste ponctuel, escalade et attente devant une porte), ou nouveaux essais épuisés -> nouvelle requête de chemin,
-- puis point intermédiaire de déblocage, puis échec rapporté avec la raison "stuck" (détail wd).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"
require "LivingKnox/LK_Movement"

local Executor = LivingKnox.Executor or {}
LivingKnox.Executor = Executor

Executor.EXEC_EVERY = 10     -- images entre deux passages
Executor.STALL_MS = 4000     -- sans progrès pendant ce temps : nouvel essai
Executor.PROGRESS = 0.5      -- cases
Executor.MAX_RETRIES = 3
Executor.ASK_MS = 2000       -- client MP : au plus une demande "dirAsk" par PNJ dans ce délai
Executor.CLAIM_MS = 2000     -- client MP : au plus une demande de remise "dirClaim" par PNJ dans ce délai
Executor.DOOR_WAIT_MS = 4000 -- corps arrêté contre une porte ou une fenêtre fermée : attente de l'autorité (LK04-T02/T03)
-- États d'action d'un franchissement (dossiers media/actiongroups/zombie/, noms en minuscules, ActionGroup.java:75-96) :
-- PathFindState.exit efface bPathfind (J/ai/states/PathFindState.java:85-90) ; le corps reprend son chemin seul à la
-- sortie (ClimbThroughWindowState.java:243-262, ClimbOverFenceState.java:229-263). Pendant ce temps : ni essai ni échec.
Executor.CROSSING = { climbwindow = true, climbfence = true }

Executor.remote = Executor.remote or { rev = -1, d = {}, r = {} }   -- client MP : consignes reçues (r : par PNJ)
Executor.runs = Executor.runs or {}                         -- npcId -> exécution en cours sur cette machine
Executor.history = Executor.history or {}                   -- npcId -> { v, l, final } dernière consigne commencée
Executor.copies = Executor.copies or {}                     -- client MP : npcId -> copie du corps vue au passage
Executor.asked = Executor.asked or {}                       -- client MP : npcId -> heure de la dernière demande
Executor.hands = Executor.hands or {}                       -- client MP : npcId -> remise reçue pour soi (LK03-T03)
Executor.handR = Executor.handR or {}                       -- client MP : npcId -> r de la dernière remise reçue
Executor.claimed = Executor.claimed or {}                   -- client MP : npcId -> heure de la dernière demande
Executor.waitLocal = Executor.waitLocal or {}               -- client MP : npcId -> copie dont le bail attend
Executor.state = Executor.state or { ticks = 0, n = 0 }
Executor.stats = Executor.stats or { passes = 0, started = 0, resumed = 0, released = 0, retries = 0, reports = 0,
    arrived = 0, failed = 0, older = 0, stale = 0, waiting = 0, asks = 0, hands = 0, revoked = 0, claims = 0,
    healthSet = 0, muted = 0, soon = 0 }

local function log() return LivingKnox.Log end
local function D() return LivingKnox.Directives end
local function Mv() return LivingKnox.Movement end

local function now() return getTimestampMs() end

local function serverTime()
    if GameTime ~= nil and GameTime.getServerTimeMills ~= nil then return GameTime.getServerTimeMills() end
    return 0
end

-- Consignes connues ici : { [npcId] = consigne }.
function Executor.directives()
    if LivingKnox.isAuthority() then
        local Dir = D()
        return Dir and Dir.entries or {}
    end
    return Executor.remote.d
end

-- ---------------------------------------------------------------- réception (client MP)

-- Points de passage (LK05-T12) : liste facultative w de cases { x, y } et étape k.
local function validSteps(e)
    if e.w == nil then return true end
    if type(e.w) ~= "table" or (e.k ~= nil and type(e.k) ~= "number") then return false end
    for i = 1, #e.w do
        local p = e.w[i]
        if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then return false end
    end
    return true
end

local function validEntry(e)
    if type(e) ~= "table" or type(e.v) ~= "number" or type(e.op) ~= "string" then return false end
    if e.op == "move" then
        return type(e.x) == "number" and type(e.y) == "number" and type(e.z) == "number" and validSteps(e)
    elseif e.op == "face" then
        return type(e.a) == "number"
    end
    return e.op == "stop"
end

local function count(name)
    local st = Executor.stats
    st[name] = (st[name] or 0) + 1
end

-- Compte du joueur local (client MP), ou nil.
local function myName()
    local p = getPlayer()
    if p == nil then return nil end
    return p:getUsername()
end

-- Remise reçue (LK03-T03) : { o, l, hp, w, er, rs, tgt, am }, champs facultatifs typés.
local function validHand(h)
    if type(h) ~= "table" or type(h.r) ~= "number" or type(h.o) ~= "string" then return false end
    if h.hp ~= nil and type(h.hp) ~= "number" then return false end
    if h.w ~= nil and (type(h.w) ~= "table" or type(h.w.t) ~= "string" or type(h.w.l) ~= "string") then return false end
    return true
end

-- Remises reçues, PNJ par PNJ : la plus récente selon r. Pour soi : gardée (appliquée à la copie dès qu'elle est
-- locale) ; pour un autre compte : remise rendue (rapports d'état arrêtés ici).
local function receiveHands(d, me)
    for id, h in pairs(d) do
        if type(id) == "string" and validHand(h) then
            local last = Executor.handR[id]
            if last ~= nil and h.r <= last then
                count("older")
            else
                Executor.handR[id] = h.r
                if h.o == me then
                    Executor.hands[id] = h
                    count("hands")
                    Executor.state.soon = true
                elseif Executor.hands[id] ~= nil then
                    Executor.hands[id] = nil
                    count("revoked")
                    log().debug("npc %s: state handed over to %s, reports stop here", id, h.o)
                end
            end
        end
    end
end

-- Consignes reçues, PNJ par PNJ : la plus récente selon r ; { gone } retire la consigne. Bail reçu pour soi :
-- passage à l'image suivante (reprise rapide, LK03-T03).
function Executor.onServerCommand(module, command, args)
    local Dir = D()
    if Dir == nil or module ~= Dir.MODULE or not isClient() then return end
    if command ~= Dir.CMD_STATE and command ~= Dir.CMD_HAND then return end
    if type(args) ~= "table" or type(args.d) ~= "table" then return end   -- table vide envoyée = nil reçu
    local me = myName()
    if command == Dir.CMD_HAND then return receiveHands(args.d, me) end
    local remote = Executor.remote
    remote.r = remote.r or {}
    for id, e in pairs(args.d) do
        if type(id) == "string" and type(e) == "table" and type(e.r) == "number" then
            local last = remote.r[id]
            if last ~= nil and e.r <= last then
                count("older")
            elseif e.gone == true then
                remote.r[id] = e.r
                remote.d[id] = nil
            elseif validEntry(e) then
                remote.r[id] = e.r
                remote.d[id] = e
                if me ~= nil and e.o == me and not e.done then Executor.state.soon = true end
            end
            if e.r > remote.rev then remote.rev = e.r end
        end
    end
end

-- Vrai si cette machine peut commencer (ou reprendre) la consigne e du PNJ id ; sinon faux et la raison.
function Executor.mayStart(id, e)
    if e.done then return false, "done" end
    if isClient() and (e.o == nil or e.o ~= myName()) then return false, "not the designated executor" end
    local h = Executor.history[id]
    if h ~= nil then
        local l, hl = e.l or 0, h.l or 0
        if e.v < h.v or (e.v == h.v and l < hl) then return false, "stale" end
        if e.v == h.v and l == hl and h.final then return false, "already executed here" end
    end
    return true
end

-- ---------------------------------------------------------------- rapports

-- Remet un rapport à l'autorité : appel direct en solo, commande au serveur sur un client MP.
function Executor.report(id, run, z, s, why, detail)
    local Dir = D()
    -- Revérifié à chaque envoi (LK03-T03) : copie simulée ici et, sur un client MP, bail courant à soi.
    local e = isClient() and Executor.remote.d[id] or nil
    if not LivingKnox.ZombieGuard.simulatedHere(z)
        or (isClient() and (e == nil or e.o ~= myName() or (e.l or 0) ~= run.l)) then
        count("muted")
        return false
    end
    local st = Executor.state
    st.n = st.n + 1
    local args = { id = id, v = run.v, l = run.l, s = s, x = z:getX(), y = z:getY(), z = z:getZ(),
        a = z:getDirectionAngle(), n = st.n, t = serverTime(), why = why, k = run.k, wd = detail }
    run.lastReport = now()
    run.reported = s
    if s ~= "moving" then
        local h = Executor.history[id]
        if h ~= nil and h.v == run.v and h.l == run.l then h.final = true end
    end
    Executor.stats.reports = Executor.stats.reports + 1
    if LivingKnox.isAuthority() then
        return Dir.onReport(getPlayer(), args)
    end
    local player = getPlayer()
    if player == nil then return false end
    sendClientCommand(player, Dir.MODULE, Dir.CMD_REPORT, args)
    return true
end

-- ---------------------------------------------------------------- mouvements du corps (simulé ici)

-- Recherche de chemin vers la case de l'étape k (destination si k absent), mode pathfind imposé (voir l'en-tête).
function Executor.issuePath(z, e, k)
    local tx, ty, tz = D().stepTarget(e, k)
    z:pathToLocation(tx, ty, tz)
    z:setVariable("bPathfind", true)
    z:setMoving(false)
end

function Executor.halt(z)
    z:setVariable("bPathfind", false)
    z:setMoving(false)
end

-- Arrêt d'une exécution finale (stop, face, consigne close) : un corps en escalade (climbwindow, climbfence) remet
-- bPathFind à vrai en sortant de l'état et reprend seul son chemin (J/ai/states/ClimbOverFenceState.java:229-263,
-- ClimbThroughWindowState.java:243-262 ; base pz-knowledge pathfinding-and-obstacles.md) : l'arrêt est repris à la
-- fin de l'escalade (Executor.haltAfterCrossing). Campagne MP du 2026-10-15 : arrêt pendant l'enjambée d'une clôture,
-- corps arrivé à la destination 4 s plus tard.
local function haltRun(run, z)
    Executor.halt(z)
    run.crossHalt = Executor.crossing(z) ~= nil or nil
end

-- Exécution finale arrêtée pendant une escalade : une fois l'escalade finie, corps arrêté de nouveau (une fois).
function Executor.haltAfterCrossing(id, run, z)
    if not run.crossHalt or Executor.crossing(z) ~= nil then return end
    run.crossHalt = nil
    if z:getVariableBoolean("bPathfind") or z:isMoving() then
        Executor.halt(z)
        count("haltedAfterCrossing")
        log().info("npc %s: %s #%d body stopped again after its crossing (the engine resumed its path)", id,
            tostring(run.op), run.v)
    end
end

-- Porte fermée (IsoDoor ou porte IsoThumpable, copie locale tenue à jour par sync) sur un bord de la case du corps
-- (J/iso/IsoGridSquare.java:3065-3111, getDoorTo), ou nil. Cases non chargées ignorées. Porte basse (portail de
-- clôture) ignorée : le corps l'enjambe et ne s'y arrête jamais (J/characters/IsoZombie.java:1075, 3051-3058 ; LK04-T08).
function Executor.closedDoorNext(z)
    local sq = z:getCurrentSquare()
    if sq == nil then return nil end
    local cell = getCell()
    local x, y, lv = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nb = cell:getGridSquare(x + d[1], y + d[2], lv)
        local door = nb and sq:getDoorTo(nb)
        if door ~= nil and not door:IsOpen() and not (door:isHoppable() and not door:isTallHoppable()) then
            return door
        end
    end
    return nil
end

-- Fenêtre qui arrête le corps sur un bord de sa case (LK04-T03) : IsoWindow fermée et intacte, ou fenêtre, fenêtre
-- construite ou cadre barricadés (copie locale tenue à jour par sync ; IsoGridSquare.java:3131-3172, 3228-3236), ou nil.
function Executor.closedWindowNext(z)
    local sq = z:getCurrentSquare()
    if sq == nil then return nil end
    local cell = getCell()
    local x, y, lv = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nb = cell:getGridSquare(x + d[1], y + d[2], lv)
        if nb ~= nil then
            local w = sq:getWindowTo(nb)
            if w ~= nil and (w:isBarricaded() or (not w:IsOpen() and not w:isDestroyed())) then return w end
            local o = sq:getWindowThumpableTo(nb) or sq:getWindowFrameTo(nb)
            if o ~= nil and o:isBarricaded() then return o end
        end
    end
    return nil
end

-- Nom de l'état de franchissement du corps (climbwindow, climbfence), ou nil.
function Executor.crossing(z)
    local name = z:getActionStateName()
    if name ~= nil and Executor.CROSSING[name] then return name end
    return nil
end

local function mark(run, z)
    run.mark = { x = z:getX(), y = z:getY(), ms = now() }
end

local function start(id, e, z, previous)
    local run = { v = e.v, l = e.l or 0, op = e.op, z = z, phase = "moving", retries = 0, lastReport = 0,
        sx = z:getX(), sy = z:getY(), started = now() }
    local h = Executor.history[id]
    local again = h ~= nil and h.v == e.v
    Executor.history[id] = { v = e.v, l = run.l, final = false }
    Executor.runs[id] = run
    Executor.stats.started = Executor.stats.started + 1
    if e.op == "move" then
        if e.s == "moving" or previous ~= nil or again then Executor.stats.resumed = Executor.stats.resumed + 1 end
        -- Étape publiée par l'autorité (reprise par un nouveau propriétaire : pas de retour aux points déjà atteints).
        local n = D().stepCount(e)
        local k = (type(e.k) == "number" and e.k >= 1) and math.floor(e.k) or 1
        if k > n then k = n end
        run.k = k
        Executor.issuePath(z, e, k)
        mark(run, z)
        Mv().begin(run, now())
        log().debug("npc %s: move #%d to %d,%d,%d step %d/%d from %.1f,%.1f (%s)", id, e.v, e.x, e.y, e.z, k, n,
            z:getX(), z:getY(), e.s == "moving" and "resumed" or "started")
        Executor.report(id, run, z, "moving")
    elseif e.op == "stop" then
        haltRun(run, z)
        run.phase = "stopped"
        Executor.report(id, run, z, "stopped")
    elseif e.op == "face" then
        haltRun(run, z)
        z:setDirectionAngle(e.a)
        run.phase = "faced"
        Executor.report(id, run, z, "faced")
    end
    return run
end

local function fail(id, run, z, why, detail)
    Executor.halt(z)
    run.phase = "failed"
    run.unblock = nil
    Executor.stats.failed = Executor.stats.failed + 1
    log().warn("npc %s: move #%d failed here (%s%s)", id, run.v, why, detail and (": " .. detail) or "")
    Executor.report(id, run, z, "failed", why, detail)
end

-- Blocage (LK04-T05) : nouvelle requête de chemin, point de déblocage, ou échec "stuck" (LK_Movement.respond).
local function escalate(id, e, z, run, cause)
    local M = Mv()
    local t = now()
    local tx, ty = D().stepTarget(e, run.k)
    count("stuckSeen")
    local act, arg = M.respond(run, z, tx, ty, cause, t)
    if act == "repath" then
        log().info("npc %s: move #%d no progress for %d ms at %.1f,%.1f (%s), new path request", id, run.v,
            M.stillMs(run, t), z:getX(), z:getY(), cause)
        Executor.issuePath(z, e, run.k)
        mark(run, z)
        M.pause(run, t)
    elseif act == "unblock" then
        log().info("npc %s: move #%d stuck at %.1f,%.1f (%s), unblocking through %d,%d before step %d,%d", id, run.v,
            z:getX(), z:getY(), cause, arg.x, arg.y, tx, ty)
        z:pathToLocation(arg.x, arg.y, math.floor(z:getZ()))
        z:setVariable("bPathfind", true)
        z:setMoving(false)
        mark(run, z)
        M.pause(run, t)
    else
        M.stats.stuck = (M.stats.stuck or 0) + 1
        fail(id, run, z, M.REASON, arg)
    end
end

-- Geste ponctuel en cours (LK04-T13 : ouvrir ou refermer une fenêtre, posé par l'autorité, LivingKnox.Anim.actOf) :
-- corps tourné vers l'angle du geste (une écriture seulement s'il en diffère d'un degré ou plus ; direction transmise
-- aux autres machines par le paquet zombie). Rend vrai si un geste ponctuel est en cours.
function Executor.actFace(id, z)
    local A = LivingKnox.Anim
    local act, a = nil, nil
    if A ~= nil and A.actOf ~= nil then act, a = A.actOf(id) end
    if act == nil then return false end
    if type(a) == "number" then
        local d = z:getDirectionAngle() - a
        d = d - math.floor(d / 360) * 360   -- 0..360 sans l'opérateur % (tronqué vers zéro en Kahlua)
        if math.min(d, 360 - d) >= 1 then z:setDirectionAngle(a) end
    end
    return true
end

-- Vrai si la case visée (tx, ty, tz) touche la case du corps z par un bord fermé d'une porte (porte fermée, ni
-- portail bas enjambé) : pas d'arrivée à travers elle (LK04-T17, lk.traversal du 2026-10-12 : destination juste
-- derrière une porte verrouillée, corps « arrivé » à 1,0 case de son centre sans la franchir). L'autorité ouvre la
-- porte (le corps passe et arrive) ou la refuse (consigne en échec), comme pour toute porte du trajet.
function Executor.behindClosedDoor(z, tx, ty, tz)
    local sq = z:getCurrentSquare()
    if sq == nil or sq:getZ() ~= tz then return false end
    local dx, dy = tx - sq:getX(), ty - sq:getY()
    if math.abs(dx) + math.abs(dy) ~= 1 then return false end
    local ts = getCell():getGridSquare(tx, ty, tz)
    local door = ts ~= nil and sq:getDoorTo(ts) or nil
    if door == nil or door:IsOpen() then return false end
    return not (door:isHoppable() and not door:isTallHoppable())
end

-- Suivi d'un "move" en cours.
function Executor.follow(id, e, z, run)
    if run.phase ~= "moving" then return end
    -- Geste ponctuel (LK04-T13) : corps arrêté et tourné vers la fenêtre pendant le geste (aucun essai compté), chemin
    -- relancé à sa fin (fenêtre ouverte entre-temps par l'autorité, ou refermée derrière lui).
    if Executor.actFace(id, z) then
        if not run.acting then
            run.acting = true
            count("actPauses")
        end
        if z:getVariableBoolean("bPathfind") or z:isMoving() then Executor.halt(z) end
        mark(run, z)
        Mv().pause(run, now())
        if now() - run.lastReport >= D().REPORT_MS then Executor.report(id, run, z, "moving") end
        return
    elseif run.acting then
        run.acting = nil
        run.doorWait = nil
        run.unblock = nil
        count("actResumed")
        Executor.issuePath(z, e, run.k)
        mark(run, z)
        Mv().pause(run, now())
        return
    end
    local Dir = D()
    local d = Dir.distToTarget(e, z:getX(), z:getY(), z:getZ())
    if d ~= nil and d <= Dir.ARRIVE and not Executor.behindClosedDoor(z, e.x, e.y, e.z) then
        Executor.halt(z)
        run.phase = "arrived"
        Executor.stats.arrived = Executor.stats.arrived + 1
        log().debug("npc %s: move #%d arrived in %d ms", id, run.v, now() - run.started)
        Executor.report(id, run, z, "arrived")
        return
    end
    -- Point de passage atteint (même tolérance que l'arrivée) : étape suivante, rapport immédiat (k).
    local n = Dir.stepCount(e)
    if (run.k or 1) < n then
        local ds = Dir.distToStep(e, run.k, z:getX(), z:getY(), z:getZ())
        if ds ~= nil and ds <= Dir.ARRIVE then
            run.k = run.k + 1
            run.retries = 0
            Executor.stats.steps = (Executor.stats.steps or 0) + 1
            local tx, ty = Dir.stepTarget(e, run.k)
            -- Solo : l'autorité journalise déjà l'étape (INFO) ; ici en DEBUG pour ne pas doubler la ligne.
            local say = LivingKnox.isAuthority() and log().debug or log().info
            say("npc %s: move #%d step %d/%d reached here at %.1f,%.1f, next %d,%d", id, run.v, run.k - 1, n,
                z:getX(), z:getY(), tx, ty)
            Executor.issuePath(z, e, run.k)
            mark(run, z)
            Mv().begin(run, now())
            Executor.report(id, run, z, "moving")
            return
        end
    end
    if Dir.dist(z:getX(), z:getY(), run.mark.x, run.mark.y) >= Executor.PROGRESS then mark(run, z) end
    -- Franchissement en cours (fenêtre, clôture, LK04-T03) : compté comme progrès, durée mesurée.
    local cross = Executor.crossing(z)
    if cross ~= nil then
        if run.cross == nil then run.cross = { kind = cross, ms = now() } end
        mark(run, z)
        Mv().pause(run, now())
        if now() - run.lastReport >= Dir.REPORT_MS then Executor.report(id, run, z, "moving") end
        return
    elseif run.cross ~= nil then
        local ms = now() - run.cross.ms
        count("crossings")
        Executor.stats.crossMs = ms
        log().debug("npc %s: move #%d %s crossed in %d ms", id, run.v, run.cross.kind, ms)
        run.cross = nil
    end
    local searching = z:getVariableBoolean("bPathfind") or z:isMoving()
    -- Détour vers un point de déblocage (LK04-T05) : point atteint, recherche finie ou délai passé -> chemin relancé
    -- vers l'étape ; un point atteint remet les nouveaux essais à zéro (le corps a bougé).
    local M = Mv()
    local leg = M.legEnd(run, z, searching, Dir.ARRIVE, now())
    if leg ~= nil then
        count(leg == "reached" and "unblockReached" or "unblockEnded")
        if leg == "reached" then
            run.retries = 0
            M.stats.unblockReached = (M.stats.unblockReached or 0) + 1
        elseif leg == "timeout" then
            M.stats.unblockTimeout = (M.stats.unblockTimeout or 0) + 1
        end
        log().debug("npc %s: move #%d unblocking point %d,%d %s at %.1f,%.1f, path to the step again", id, run.v,
            run.unblock.x, run.unblock.y, leg, z:getX(), z:getY())
        run.unblock = nil
        Executor.issuePath(z, e, run.k)
        mark(run, z)
        M.pause(run, now())
        return
    elseif run.unblock ~= nil then
        if now() - run.lastReport >= Dir.REPORT_MS then Executor.report(id, run, z, "moving") end
        return
    end
    -- Porte ou fenêtre (LK04-T02, T03) : corps arrêté contre une porte ou une fenêtre fermée (sans cible, un zombie s'y
    -- arrête, J/characters/IsoZombie.java:1075-1091) : l'autorité l'ouvre (LK_Obstacles.lua, état reçu par sync) ou
    -- refuse la consigne ; attente de DOOR_WAIT_MS sans compter d'essai, puis chemin relancé dès qu'elle est ouverte.
    if not searching then
        local door = Executor.closedDoorNext(z)
        local blocker = door or Executor.closedWindowNext(z)
        if blocker ~= nil then
            run.doorWait = run.doorWait or now()
            run.waitFor = door ~= nil and "door" or "window"
            if now() - run.doorWait < Executor.DOOR_WAIT_MS then
                mark(run, z)
                M.pause(run, now())
                if now() - run.lastReport >= Dir.REPORT_MS then Executor.report(id, run, z, "moving") end
                return
            end
        elseif run.doorWait ~= nil then
            run.doorWait = nil
            count(run.waitFor == "window" and "windowResumed" or "doorResumed")
            Executor.issuePath(z, e, run.k)
            mark(run, z)
            M.pause(run, now())
            return
        end
    end
    -- Progrès vers l'étape (LK04-T05) : distance qui baisse ou case nouvelle ; sinon déblocage puis échec "stuck".
    if M.progress(run, z, Dir.distToStep(e, run.k, z:getX(), z:getY(), z:getZ()), now()) then
        escalate(id, e, z, run, "no approach")
        return
    end
    if not searching or now() - run.mark.ms >= Executor.STALL_MS then
        if run.retries >= Executor.MAX_RETRIES then
            escalate(id, e, z, run, searching and "no progress" or "no path")
            return
        end
        run.retries = run.retries + 1
        Executor.stats.retries = Executor.stats.retries + 1
        Executor.issuePath(z, e, run.k)
        mark(run, z)
    end
    if now() - run.lastReport >= Dir.REPORT_MS then Executor.report(id, run, z, "moving") end
end

-- ---------------------------------------------------------------- passage

-- Copie présente dans le monde de cette machine (LK03-T07) : vivante et dans la liste des zombies de la cellule.
-- Un joueur réanimé dont le chunk se décharge est mis de côté (même objet Java, ni mort ni retiré, référence Lua
-- toujours valable) et sort de cette liste ; il y revient au rechargement (J/VirtualZombieManager.java:677-684,
-- J/ReanimatedPlayers.java:68-112, J/iso/IsoChunk.java:3516 ; base pz-knowledge zombies-as-npc-bodies.md). Même
-- critère que LivingKnox.Bodies.inWorld côté autorité.
function Executor.inWorld(z)
    if z == nil or z:isDead() then return false end
    local cell = getCell()
    return cell ~= nil and cell:getZombieList():contains(z)
end

-- Corps connus ici ET présents dans le monde : seuls ceux-là sont exécutés, rapportés ou demandés. Un corps mis de
-- côté (sorti de la zone chargée) disparaît de la table : exécution lâchée, aucun rapport ; à son retour, il reprend
-- comme une copie réapparue (premier rapport aussitôt, consigne reprise au même bail).
function Executor.loadedBodies()
    local out = {}
    for id, z in pairs(LivingKnox.Anim.knownBodies()) do
        if Executor.inWorld(z) then
            out[id] = z
        else
            count("unloaded")
        end
    end
    return out
end

function Executor.pass()
    local Dir = D()
    if Dir == nil then return end
    local G = LivingKnox.ZombieGuard
    local known = Executor.loadedBodies()
    local directives = Executor.directives()
    local drop = {}
    local me = isClient() and myName() or nil
    for id, run in pairs(Executor.runs) do
        local z = known[id]
        local e = directives[id]
        if e == nil or z == nil or z ~= run.z or not G.simulatedHere(z) or (e.l or 0) ~= run.l
            or (me ~= nil and e.o ~= me) then
            drop[#drop + 1] = id
        end
    end
    for _, id in ipairs(drop) do   -- table modifiée hors de pairs
        Executor.runs[id] = nil
        Executor.stats.released = Executor.stats.released + 1
        log().debug("npc %s: execution released here (directive gone or body no longer simulated here)", id)
    end
    if isClient() then Executor.applyHands(known, me) end
    local waitLocal = {}
    for id, e in pairs(directives) do
        local z = known[id]
        local run = Executor.runs[id]
        -- Consigne close par l'autorité pendant la marche (refus devant une porte LK04-T02, délai dépassé) : corps
        -- arrêté une fois, exécution finale.
        if z ~= nil and e.done and run ~= nil and run.phase == "moving" and run.v == e.v and run.l == (e.l or 0)
            and G.simulatedHere(z) then
            haltRun(run, z)
            run.phase = e.s == "failed" and "failed" or "stopped"
            local h = Executor.history[id]
            if h ~= nil and h.v == run.v and h.l == run.l then h.final = true end
            count("closed")
            log().info("npc %s: %s #%d closed by the authority (%s), body stopped here", id, e.op, e.v, tostring(e.s))
        end
        if z ~= nil and run ~= nil and run.crossHalt and run.phase ~= "moving" and G.simulatedHere(z) then
            Executor.haltAfterCrossing(id, run, z)
        end
        if z ~= nil and e.done and G.simulatedHere(z) then Executor.actFace(id, z) end   -- arrivé : geste (LK04-T13)
        if z ~= nil and not e.done and G.simulatedHere(z) then
            if run ~= nil and run.v == e.v and run.l == (e.l or 0) then
                if e.op == "move" and run.phase == "moving" then
                    Executor.follow(id, e, z, run)
                else
                    Executor.actFace(id, z)   -- corps arrêté : tourné vers la fenêtre d'un geste ponctuel (LK04-T13)
                end
            else
                local ok, why = Executor.mayStart(id, e)
                if ok then
                    start(id, e, z, run)
                elseif why == "stale" then
                    count("stale")
                elseif why == "not the designated executor" then
                    count("waiting")
                end
            end
        elseif z ~= nil and not e.done and me ~= nil and e.o == me then
            waitLocal[id] = z   -- bail à soi, copie pas encore locale : vérifiée à chaque image (tick)
        end
    end
    Executor.waitLocal = waitLocal
    -- Perception (LK05-T01, shared/LivingKnox/LK_Senses.lua) : mesurée ici avant les rapports d'état qui la portent.
    local S = LivingKnox.Senses
    if S ~= nil and S.scan ~= nil then S.scan(known, now()) end
    -- LK06-T11 : fenêtres frappées par les zombies simulés ici, rapportées au serveur (client MP seulement).
    local thumps = isClient() and S ~= nil and S.thumpReport ~= nil and S.thumpReport(known, now()) or nil
    local player = thumps ~= nil and getPlayer() or nil
    if player ~= nil then sendClientCommand(player, "LivingKnox", S.CMD_THUMPS, thumps) end
    Executor.stateReports(known, directives, me)
    if isClient() then
        Executor.askNew(known)
        Executor.claimHands(known, me)
    end
    Executor.stats.passes = Executor.stats.passes + 1
end

-- ---------------------------------------------------------------- remise d'état (LK03-T03, client MP)

-- Applique la remise h à la copie locale z : santé abaissée à la santé acceptée par le serveur (jamais relevée :
-- pas de soin ; bornée à 0..HP_MAX, la santé voyageant en short x 1000, docs/annexes/conception/sante.md) ; arme voulue
-- reprise si la table des armes reçue est plus ancienne que celle de la remise (er). Rend vrai.
function Executor.applyHand(id, z, h)
    local c = LivingKnox.Config.REPORTS
    if type(h.hp) == "number" and h.hp > 0 and h.hp <= c.HP_MAX then
        local hp = z:getHealth()
        if hp > h.hp + c.HP_EPSILON then
            z:setHealth(h.hp)
            count("healthSet")
            log().debug("npc %s: health %.3f of the new local copy lowered to the accepted %.3f", id, hp, h.hp)
        end
    end
    local Eq = LivingKnox.Equipment
    if Eq ~= nil and Eq.remote ~= nil and type(h.er) == "number" and h.er > Eq.remote.rev then
        Eq.remote.w[id] = h.w and { t = h.w.t, l = h.w.l, h = h.w.h == true } or nil
    end
    h.applied = z
    return true
end

-- Remises pour soi appliquées aux copies devenues locales (une fois par objet de copie).
function Executor.applyHands(known, me)
    local G = LivingKnox.ZombieGuard
    for id, h in pairs(Executor.hands) do
        local z = known[id]
        if h.o == me and z ~= nil and h.applied ~= z and G.simulatedHere(z) then Executor.applyHand(id, z, h) end
    end
end

-- Copies locales sans remise pour soi : demande au serveur ("dirClaim"), une par CLAIM_MS et par PNJ.
function Executor.claimHands(known, me)
    local Dir = D()
    local G = LivingKnox.ZombieGuard
    local t = now()
    local ids = {}
    for id, z in pairs(known) do
        local h = Executor.hands[id]
        if G.simulatedHere(z) and (h == nil or h.o ~= me) and #ids < Dir.ASK_MAX then
            local last = Executor.claimed[id]
            if last == nil or t - last >= Executor.CLAIM_MS then
                Executor.claimed[id] = t
                ids[#ids + 1] = id
            end
        end
    end
    if #ids == 0 then return 0 end
    local player = getPlayer()
    if player == nil then return 0 end
    table.sort(ids)
    sendClientCommand(player, Dir.MODULE, Dir.CMD_CLAIM, { ids = ids })
    count("claims")
    return #ids
end

-- ---------------------------------------------------------------- rapports d'état (LK03-T02)
-- Le propriétaire réel (corps simulé ici et, sur un client MP, exécutant désigné o du bail courant s'il y a une
-- consigne) rapporte l'état de chaque corps : position, orientation, activité (phase de l'exécution), santé du
-- zombie, pose. Cadence (Config.REPORTS) : au plus toutes les STATE_MS s'il a bougé de MOVED cases ou si sa santé a
-- changé, au plus toutes les MIN_MS si son activité ou sa pose change, sinon toutes les IDLE_MS. Contrôles :
-- server/LivingKnox/LK_Reports.lua. Rien n'est envoyé si ce module n'est pas chargé.
Executor.sentState = Executor.sentState or {}   -- npcId -> dernier état rapporté d'ici { ms, act, pose, x, y, z, hp }

-- Activité d'un PNJ sur cette machine : phase de l'exécution en cours (moving, arrived, failed, stopped, faced),
-- "idle" sans exécution.
function Executor.activityOf(id)
    local run = Executor.runs[id]
    if run == nil or type(run.phase) ~= "string" then return "idle" end
    return run.phase
end

-- Pose du corps : "floor" (au sol), "crawl" (rampant), sinon "stand".
function Executor.poseOf(z)
    if z:isOnFloor() then return "floor" end
    if z:isCrawling() then return "crawl" end
    return "stand"
end

-- Vrai si l'état du corps z doit être rapporté maintenant (voir la cadence plus haut). Perception (LK05-T01) :
-- signature sig du résumé changée (cible apparue, vue, entendue, perdue, déplacée de 2 cases) = changement d'activité.
local function stateDue(last, act, pose, z, hp, t, sig)
    if last == nil then return true end
    local c = LivingKnox.Config.REPORTS
    local age = t - last.ms
    if (act ~= last.act or pose ~= last.pose or sig ~= last.sig) and age >= c.MIN_MS then return true end
    if age >= c.IDLE_MS then return true end
    if age < c.STATE_MS then return false end
    return D().dist(z:getX(), z:getY(), last.x, last.y) >= c.MOVED or math.abs(z:getZ() - last.z) >= c.MOVED
        or hp ~= last.hp
end

-- Rapports d'état des corps simulés ici. Rend le nombre envoyé.
function Executor.stateReports(known, directives, me)
    local R = LivingKnox.Reports
    if R == nil or R.CMD_REPORT == nil then return 0 end
    local S = LivingKnox.Senses   -- résumé de perception porté par le rapport (champ sen, LK05-T01) s'il est chargé
    local G = LivingKnox.ZombieGuard
    local t = now()
    local sent = 0
    local player = getPlayer()
    if player == nil then return 0 end
    for id, z in pairs(known) do
        local e = directives[id]
        local h = me ~= nil and Executor.hands[id] or nil
        -- Client MP (LK03-T03) : seulement avec la remise pour soi appliquée à cette copie.
        local handed = me == nil or (h ~= nil and h.o == me and h.applied == z)
        if handed and G.simulatedHere(z) and (me == nil or e == nil or e.o == me) then
            local act, pose, hp = Executor.activityOf(id), Executor.poseOf(z), z:getHealth()
            if h ~= nil and (type(h.hp) ~= "number" or hp < h.hp) then h.hp = hp end   -- plancher d'une copie recréée
            local sen, sig
            if S ~= nil and S.summary ~= nil then sen, sig = S.summary(id) end
            if stateDue(Executor.sentState[id], act, pose, z, hp, t, sig) then
                local st = Executor.state
                st.n = st.n + 1
                local args = { id = id, l = e and e.l or 0, n = st.n, x = z:getX(), y = z:getY(), z = z:getZ(),
                    a = z:getDirectionAngle(), act = act, hp = hp, pose = pose, t = serverTime(), sen = sen }
                Executor.sentState[id] = { ms = t, act = act, pose = pose, x = args.x, y = args.y, z = args.z, hp = hp,
                    sig = sig }
                if LivingKnox.isAuthority() then
                    R.onReport(player, args)
                else
                    sendClientCommand(player, R.MODULE, R.CMD_REPORT, args)
                end
                count("states")
                sent = sent + 1
            end
        end
    end
    local gone = {}
    for id in pairs(Executor.sentState) do
        if known[id] == nil then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do Executor.sentState[id] = nil end   -- table modifiée hors de pairs
    return sent
end

-- Client MP : copies de corps apparues depuis le passage précédent (chargement, recréation après 5 s sans paquet,
-- retour dans la zone) : consigne courante demandée au serveur ("dirAsk"), une fois par ASK_MS et par PNJ.
function Executor.askNew(known)
    local Dir = D()
    local ids = {}
    local t = now()
    for id, z in pairs(known) do
        if Executor.copies[id] ~= z then
            Executor.copies[id] = z
            local last = Executor.asked[id]
            if (last == nil or t - last >= Executor.ASK_MS) and #ids < Dir.ASK_MAX then
                Executor.asked[id] = t
                ids[#ids + 1] = id
            end
        end
    end
    local gone = {}
    for id in pairs(Executor.copies) do
        if known[id] == nil then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do Executor.copies[id] = nil end   -- table modifiée hors de pairs
    if #ids == 0 then return 0 end
    local player = getPlayer()
    if player == nil then return 0 end
    table.sort(ids)
    sendClientCommand(player, Dir.MODULE, Dir.CMD_ASK, { ids = ids })
    count("asks")
    return #ids
end

-- Vrai si une copie dont le bail attendait est devenue locale (vérifié à chaque image, LK03-T03).
local function becameLocal()
    local G = LivingKnox.ZombieGuard
    for _, z in pairs(Executor.waitLocal) do
        if G.simulatedHere(z) then return true end
    end
    return false
end

-- Vrai si un geste ponctuel (LK04-T13) vient d'apparaître pour un corps en marche ici : passage à l'image suivante
-- (corps arrêté au plus tôt, avant que le geste ne prenne de l'avance sur la bascule de l'autorité).
local function actPending()
    local A = LivingKnox.Anim
    if A == nil or A.actOf == nil then return false end
    for id, run in pairs(Executor.runs) do
        if run.phase == "moving" and not run.acting and A.actOf(id) ~= nil then return true end
    end
    return false
end

function Executor.tick()
    local st = Executor.state
    st.ticks = st.ticks + 1
    if st.ticks < Executor.EXEC_EVERY and not st.soon and not becameLocal() and not actPending() then return end
    if st.ticks < Executor.EXEC_EVERY then count("soon") end
    st.ticks = 0
    st.soon = false
    if not LivingKnox.hasLocalPlayer() or getCell() == nil then return end
    Executor.pass()
end

-- ---------------------------------------------------------------- abonnements

if not isServer() then
    local function onTick()
        LivingKnox.Executor.tick()
    end
    LivingKnox.subscribe("OnTick", "Executor.tick", onTick)
end
if isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.Executor.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "Executor.onServerCommand", onServerCommand)
end

return Executor
