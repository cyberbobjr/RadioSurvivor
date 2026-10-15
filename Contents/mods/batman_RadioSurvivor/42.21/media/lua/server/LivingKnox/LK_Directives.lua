-- Living Knox : consignes de déplacement des corps de PNJ, côté autorité (LK02-T07). Fiche : docs/conception/consignes.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...). Un client MP charge aussi ce fichier (media/lua/server) : il n'y
-- trouve que des constantes et des fonctions qui refusent d'agir ; l'exécution est dans client/LivingKnox/LK_Executor.lua
-- et l'affichage chez les autres clients dans client/LivingKnox/LK_Presentation.lua.
--
-- Consigne : une par PNJ, fixée par l'autorité (serveur dédié ou hébergé, solo), numérotée (v croissant, jamais réutilisé
-- dans la session) : "move" (aller à une case, geste walk | run | crouch), "stop" (s'arrêter), "face" (se tourner vers une
-- direction). Gardée en mémoire seulement : un redémarrage abandonne le trajet en cours (le corps reste où il a été
-- sauvegardé, useless) ; les décisions relèvent de LK05, qui réémettra une consigne à jour plutôt qu'un ordre périmé.
-- Serveur -> clients (LK03-T01) : consignes PAR PNJ ("dirState" { rev, d = { [npcId] = { r, v, l, o, op, x, y, z, g,
-- a, done, s, w, k, vg } | { r, gone = true } } }), envoyées aux seuls joueurs à NEAR_RADIUS cases du corps (et au
-- propriétaire), à chaque changement, puis réémises : arrivée d'un joueur dans le rayon, réapparition du corps (nouvel
-- onlineId ou nouvel objet sur le serveur ; demande "dirAsk" d'un client dont la copie apparaît), changement de
-- propriétaire (nouveau bail l, exécutant désigné o), entrée en partie ("guardHello"). r : numéro d'envoi croissant
-- (ordre des messages, livraison non ordonnée) ; v : numéro de la consigne ; l : bail (seul l'exécutant désigné o
-- exécute, et ses rapports doivent porter ce bail). Joueur sorti du rayon : { gone = true } (il oublie la consigne).
--
-- Exécution : seule la machine qui SIMULE le corps l'exécute (client propriétaire en MP, solo), en recherche de chemin
-- (mode pathfind mesuré par LK02-T10 : useless gardé, voir la fiche) ; elle rapporte position, orientation et état
-- ("dirReport" : moving, arrived, failed, stopped, faced), au plus une fois par REPORT_MS en marche et à chaque
-- changement d'état. Le serveur n'accepte un rapport que de la connexion propriétaire du corps (getOwnerPlayer,
-- J/popman/NetworkZombieManager.java:137-181), pour la consigne courante, plus récent que le précédent du même
-- expéditeur et plausible (proche de la copie du serveur, distance parcourue bornée par une vitesse maximale, arrivée
-- à la tolérance de la case visée) ; il garde alors la pose (Directives.poses, numéro pr croissant), la confie au relais
-- des gestes (LivingKnox.Relay, LK03-T05 : clients proches seulement, regroupé et borné, avec le geste) et règle le
-- geste par LivingKnox.Anim (geste de la consigne en route, "idle" ou "crouch" à l'arrivée).
--
-- Corps simulé par le serveur (aucun client propriétaire, LK03-T04) : AUCUNE consigne n'y est exécutée. La consigne
-- ouverte est SUSPENDUE (Directives.suspend) : ni close, ni rejouée, ni perdue ; le corps est mis au repos (état
-- neutre : setMoving(false), trajet fermé donc useless rendu par la garde, sans cible, geste "idle") ; le temps
-- suspendu ne compte pas dans TRIP_TIMEOUT_MS. Dès qu'un client redevient propriétaire, le nouveau bail
-- (Directives.transfer, LK03-T01/T03) la reprend depuis la position actuelle et l'étape publiée, geste rétabli.
-- Raison : le serveur ne peut pas chercher de chemin (pathToAux ne pose jamais bPathfind sur le serveur,
-- J/characters/IsoGameCharacter.java:5923-5958) et un corps loin de tous les clients n'est vu de personne ; un
-- corps resté longtemps loin des joueurs est retiré et repasse en simulation abstraite (Bodies.releasePass).
--
-- Points de passage (LK05-T12) : un "move" dont la ligne droite traverse la zone d'une plante cultivée ou d'un feu de
-- camp porte en plus w = { { x, y }, ... } (contournement calculé par l'autorité, Directives.planDetour) et k (étape
-- courante, 1 = premier point) ; l'exécutant passe à l'étape suivante à l'arrivée sur un point (même tolérance) et
-- l'annonce dans son rapport (k) ; l'autorité l'accepte d'une étape à la fois et republie la table. Sans w : format
-- antérieur, une seule étape. Porte d'abord (LK04-T09) : sans détour de potager, w peut aussi guider le corps par
-- une porte ou un portail plutôt que par une fenêtre ou une clôture (Directives.planDoors, case avant et case après
-- chaque porte, LivingKnox.Obstacles.planDoorRoute).
--
-- Transfert de propriété (LK03-T03) : le serveur compare À CHAQUE IMAGE le propriétaire de chaque corps relié avec
-- celui qui détient la « remise » (Directives.ownerWatch) ; au changement : nouveau bail (consigne ouverte ou close)
-- et remise "npcHand" { r, d = { [npcId] = { r, o, l, hp, w, er, rs, tgt, am } } } envoyée au nouveau propriétaire
-- (état utile tenu par le serveur : bail l, santé acceptée hp, arme w et révision er de la table des armes ; champs
-- réservés rs étape de routine, tgt cible, am munitions, absents tant qu'aucun module ne les tient) et à l'ancien
-- (o = nouveau propriétaire : il rend la remise et cesse ses rapports d'état). Un client dont la copie est locale sans
-- remise la demande ("dirClaim" { ids }), réponse au seul propriétaire réel. Rapport d'un ancien propriétaire encore
-- persuadé de simuler le corps (paquet ZombieList non fiable, jusqu'à 3 s) : ignoré sans avertissement pendant
-- OWNER_GRACE_MS (Directives.isPreviousOwner, aussi lu par LK_Reports.lua). Mesure : délai entre le changement vu
-- par le serveur et le premier rapport du nouvel exécutant (stats.resumeLast, resumeMax, ligne INFO "resumed by").
-- Blocage (LK04-T05, shared/LivingKnox/LK_Movement.lua) : un rapport "failed" porte la raison why (courte) et un
-- détail wd ; la raison est gardée dans la consigne close (e.why, e.wd, lue par Directives.get). Raison "stuck"
-- (exécutant sans progrès malgré une nouvelle requête et un point de déblocage) : case visée notée
-- (Movement.noteStuck) et refusée au même PNJ par moveTo pendant Movement.AVOID_MS ; le cadre de décision en tient
-- compte (Movement.takeStuck).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"
require "LivingKnox/LK_Movement"

local Directives = LivingKnox.Directives or {}
LivingKnox.Directives = Directives

Directives.MODULE = "LivingKnox"
Directives.CMD_STATE = "dirState"     -- serveur -> client : { rev, d = { [npcId] = consigne (r, l, o ; w, k ; vg) | gone } }
Directives.CMD_REPORT = "dirReport"   -- client propriétaire -> serveur : { id, v, l, s, x, y, z, a, n, t, why, k, wd }
Directives.CMD_ASK = "dirAsk"         -- client -> serveur : { ids = { npcId, ... } } (copie apparue chez lui)
Directives.CMD_HAND = "npcHand"       -- serveur -> nouveau et ancien propriétaire : { r, d = { [npcId] = remise } }
Directives.CMD_CLAIM = "dirClaim"     -- client -> serveur : { ids = { npcId, ... } } (copie locale sans remise)

Directives.OP_MOVE, Directives.OP_STOP, Directives.OP_FACE = "move", "stop", "face"
Directives.MOVE_GESTURES = { walk = true, run = true, crouch = true }
Directives.REPORT_STATES = { moving = true, arrived = true, failed = true, stopped = true, faced = true }
Directives.OP_STATES = { move = { moving = true, arrived = true, failed = true }, stop = { stopped = true },
    face = { faced = true } }
-- Directions nommées -> angle de setDirectionAngle (degrés ; vecteur (cos, sin), y croissant = sud,
-- J/characters/IsoGameCharacter.java:2630-2635, J/iso/IsoDirections.java:13-20).
Directives.ANGLES = { E = 0, SE = 45, S = 90, SW = 135, W = 180, NW = 225, N = 270, NE = 315 }

Directives.ARRIVE = 1.0          -- cases : tolérance d'arrivée (distance au centre de la case visée, même niveau)
Directives.STEP_TIGHT = 0.5      -- cases : tolérance d'un point de passage "serré" (w[i].t : porte à côté d'une fenêtre)
Directives.MAX_TRIP = 60         -- cases : distance maximale d'une consigne "move"
Directives.REPORT_MS = 1000      -- rapport de marche au plus une fois par seconde (exécutant et serveur)
-- Seuils partagés avec les rapports d'état (LK03-T02) : LivingKnox.Config.REPORTS (preuves dans LK_Config.lua).
Directives.MAX_SPEED = LivingKnox.Config.REPORTS.MAX_SPEED   -- cases par seconde (course mesurée 4,78)
Directives.SLACK = LivingKnox.Config.REPORTS.SLACK           -- cases tolérées en plus de MAX_SPEED x durée
Directives.MAX_GAP = LivingKnox.Config.REPORTS.MAX_GAP       -- cases : écart maximal avec la copie du serveur
Directives.TRIP_TIMEOUT_MS = 180000   -- au-delà, la consigne "move" est déclarée échouée (timeout ; temps suspendu exclu)
Directives.SLOW_EVERY = 15       -- images entre deux passages du serveur
Directives.WARN_EVERY_MS = 60000 -- une ligne WARN par (expéditeur, raison) au plus par minute
-- Rayon d'envoi (LK03-T01) : un client ne reçoit les zombies qu'à relevantRange x 8 cases de son joueur (écart en x et
-- en y), relevantRange = vue demandée (12 à 20) / 2 + 2, soit 8 à 12 morceaux, 96 cases au plus
-- (J/network/GameServer.java:2615-2616, J/core/raknet/UdpConnection.java:216-240) ; le propriétaire est choisi à
-- (relevantRange - 2) x 8 cases au plus (J/popman/NetworkZombieManager.java:121-127). Même mesure ici (écart en x et
-- en y, niveaux ignorés), avec une marge : tout client qui peut voir le corps, ou le simuler, a la consigne.
Directives.NEAR_RADIUS = 100
Directives.LEASE_GRACE_MS = 2000 -- rapport FINAL de l'ancien exécutant accepté ce temps après un transfert (en vol)
Directives.ASK_MAX = 16          -- identifiants au plus par demande "dirAsk" (et "dirClaim")
-- Ancien propriétaire (LK03-T03) : un client peut se croire propriétaire jusqu'à 3 s après le changement (ZombieList
-- non fiable, renvoyé au plus tard toutes les 3 s, base multiplayer.md « Changement de propriétaire d'un zombie »,
-- J/popman/NetworkZombieSimulator.java:76-115) ; ses rapports sont ignorés (course) pendant ce délai, avec une marge.
Directives.OWNER_GRACE_MS = 4000

Directives.entries = Directives.entries or {}   -- npcId -> consigne courante (autorité)
Directives.poses = Directives.poses or {}       -- npcId -> dernière pose acceptée (autorité)
Directives.accepted = Directives.accepted or {} -- npcId -> { by, x, y, v, ms } dernier rapport accepté
Directives.lastN = Directives.lastN or {}       -- npcId -> { l, n } dernier rapport accepté du bail courant
Directives.holders = Directives.holders or {}   -- npcId -> { [compte] = joueur } clients qui ont la consigne (serveur)
Directives.bodySeen = Directives.bodySeen or {} -- npcId -> { z, o } corps et onlineId vus au dernier passage (serveur)
Directives.hands = Directives.hands or {}       -- npcId -> compte qui détient la remise ("server" : aucun) (serveur)
Directives.handPrev = Directives.handPrev or {} -- npcId -> { name, ms } ancien détenteur et heure du changement
Directives.warned = Directives.warned or {}
Directives.state = Directives.state or { rev = 0, seq = 0, pr = 0, ticks = 0, lease = 0 }
Directives.stats = Directives.stats or { issued = 0, published = 0, reports = 0, accepted = 0, rejected = 0,
    stale = 0, relayed = 0, stepIgnored = 0, leases = 0, reemitted = 0, dropped = 0, asked = 0,
    graced = 0, handed = 0, claims = 0, claimIgnored = 0, previousOwner = 0, resumed = 0, suspended = 0,
    unsuspended = 0 }

local function log() return LivingKnox.Log end
local function Bodies() return LivingKnox.Bodies end
local function Guard() return LivingKnox.ZombieGuard end
local function Anim() return LivingKnox.Anim end

local function now() return getTimestampMs() end

local function serverTime()
    if GameTime ~= nil and GameTime.getServerTimeMills ~= nil then return GameTime.getServerTimeMills() end
    return 0
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end
Directives.dist = dist

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

-- Distance du point (x, y, z) au centre de la case visée ; nil si le niveau diffère.
function Directives.distToTarget(e, x, y, z)
    if math.floor(z) ~= e.z then return nil end
    return dist(x, y, e.x + 0.5, e.y + 0.5)
end

-- Étapes d'une consigne "move" (LK05-T12) : points de passage e.w = { { x, y }, ... } (même niveau que la destination),
-- puis la destination (e.x, e.y). Étape k : 1 = premier point de passage ; stepCount(e) = la destination. Une consigne
-- sans e.w n'a qu'une étape (format antérieur inchangé).
function Directives.stepCount(e)
    if type(e.w) ~= "table" then return 1 end
    return #e.w + 1
end

-- Case visée à l'étape k (x, y, z) ; la destination pour k absent ou hors des points de passage.
function Directives.stepTarget(e, k)
    if type(e.w) == "table" and type(k) == "number" and k >= 1 and k <= #e.w then
        local p = e.w[k]
        return p.x, p.y, e.z
    end
    return e.x, e.y, e.z
end

-- Distance du point (x, y, z) au centre de la case de l'étape k ; nil si le niveau diffère.
function Directives.distToStep(e, k, x, y, z)
    if math.floor(z) ~= e.z then return nil end
    local tx, ty = Directives.stepTarget(e, k)
    local d = dist(x, y, tx + 0.5, ty + 0.5)
    -- Point "serré" (Obstacles.planDoorRoute : porte à côté d'une fenêtre ou d'une clôture) : distance mise à
    -- l'échelle, pour que la tolérance ARRIVE de l'exécutant et de l'autorité vaille STEP_TIGHT case pour ce point.
    local p = type(e.w) == "table" and type(k) == "number" and e.w[k] or nil
    if type(p) == "table" and p.t == true then d = d * Directives.ARRIVE / Directives.STEP_TIGHT end
    return d
end

-- Angle (degrés) d'une direction : nom ("N", "SE"...) ou nombre. Rend l'angle dans [0, 360), ou nil.
function Directives.angleOf(dir)
    if type(dir) == "string" then return Directives.ANGLES[string.upper(dir)] end
    if finite(dir) then return dir - math.floor(dir / 360) * 360 end
    return nil
end

-- ---------------------------------------------------------------- consignes (autorité)

local function refuseUnlessAuthority()
    if not LivingKnox.isAuthority() then return "not the authority (MP client)" end
    return nil
end

-- Copie sûre pour le réseau (chaînes, nombres, booléens).
-- Points de passage (LK05-T12) : liste w et étape courante k, seulement pour une consigne qui en a.
-- Bail et exécutant désigné (LK03-T01) : l (numéro de bail, croissant, jamais réutilisé) et o (compte du joueur
-- propriétaire, "server" si le serveur simule) ; absents en solo (une seule machine).
-- Vigilance (LK05-T03) : vg = vigilance de la perception décidée par l'autorité (LivingKnox.Senses.MODEL.VIGIL : sleep,
-- busy, rest, guard), lue par l'exécutant d'un client MP (Senses.vigilanceOf) ; absente si aucune n'est posée.
local function wire(e, r)
    local out = { r = r, v = e.v, l = e.l, o = e.o, op = e.op, x = e.x, y = e.y, z = e.z, g = e.g, a = e.a,
        done = e.done == true, s = e.s, vg = e.vg }
    if type(e.w) == "table" then
        local w = {}
        for i = 1, #e.w do w[i] = { x = e.w[i].x, y = e.w[i].y, t = e.w[i].t == true or nil } end
        out.w, out.k = w, e.k or 1
    end
    return out
end

local function count(name)
    local st = Directives.stats
    st[name] = (st[name] or 0) + 1
end

local function senderName(player)
    if player == nil then return "?" end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return "?"
end
Directives.senderName = senderName

-- Exécutant d'un corps vu du serveur : compte du joueur propriétaire, ou "server" (aucun propriétaire).
function Directives.ownerName(z)
    if z == nil or z:getOwner() == nil then return "server" end
    return senderName(z:getOwnerPlayer())
end

-- Vrai si le corps z est simulé par le serveur MP lui-même (aucune connexion propriétaire) : ses consignes sont
-- suspendues (LK03-T04). Toujours faux en solo (la seule machine est propriétaire).
function Directives.serverHeld(z)
    return isServer() and z ~= nil and z:getOwner() == nil
end

-- Nouveau bail : exécutant = propriétaire actuel (serveur MP). L'ancien (l, o) est gardé pour le délai de grâce.
local function grant(e, z)
    local st = Directives.state
    st.lease = (st.lease or 0) + 1
    e.pl, e.po = e.l, e.o
    e.l = st.lease
    e.leasedMs = now()
    if isServer() then e.o = Directives.ownerName(z) else e.o = nil end
end

-- Numéro d'envoi suivant : chaque message porte l'état courant au moment de l'envoi, donc un numéro plus grand
-- = un état au moins aussi récent (le client garde le plus grand par PNJ).
local function nextR()
    local st = Directives.state
    st.rev = st.rev + 1
    return st.rev
end

local function sendEntries(player, d)
    sendServerCommand(player, Directives.MODULE, Directives.CMD_STATE, { rev = Directives.state.rev, d = d })
end

local function sendEntry(player, id, e)
    local d = {}
    d[id] = wire(e, nextR())
    sendEntries(player, d)
    count("published")
end

local function sendGone(player, id)
    local d = {}
    d[id] = { r = nextR(), gone = true }
    sendEntries(player, d)
    count("dropped")
end

-- Vrai si le joueur p est à NEAR_RADIUS cases du corps z (écart en x et en y, comme la portée réseau du moteur).
function Directives.isNear(p, z)
    local R = Directives.NEAR_RADIUS
    return math.abs(p:getX() - z:getX()) <= R and math.abs(p:getY() - z:getY()) <= R
end

-- Destinataires de la consigne du corps z : joueurs connectés à NEAR_RADIUS cases, et le propriétaire. Rend
-- { [compte] = joueur } et vrai si la liste des joueurs connectés n'était pas vide.
function Directives.targets(z)
    local out, any = {}, false
    local list = getOnlinePlayers()
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil then
                any = true
                if Directives.isNear(p, z) then out[senderName(p)] = p end
            end
        end
    end
    if z:getOwner() ~= nil then
        local op = z:getOwnerPlayer()
        if op ~= nil then out[senderName(op)] = op end
    end
    return out, any
end

-- Serveur : envoie la consigne du PNJ id aux destinataires. force : à tous (changement d'état, réémission) ; sinon
-- aux nouveaux seulement (arrivée dans le rayon). Les détenteurs sortis du rayon reçoivent { gone }. Corps absent
-- de la zone chargée ou liste des joueurs vide (déconnexion, redémarrage : base multiplayer.md) : détenteurs gardés,
-- rien n'est retiré. Rend le nombre d'envois.
function Directives.sync(id, force)
    if not isServer() then return 0 end
    local e = Directives.entries[id]
    local held = Directives.holders[id] or {}
    local B = Bodies()
    local z = B and B.find(id)
    local targets, any = nil, false
    if z ~= nil then targets, any = Directives.targets(z) end
    local sent = 0
    if not any then
        if force and e ~= nil then
            for _, p in pairs(held) do
                sendEntry(p, id, e)
                sent = sent + 1
            end
        end
        return sent
    end
    if e ~= nil then
        for name, p in pairs(targets) do
            if force or held[name] == nil then
                sendEntry(p, id, e)
                sent = sent + 1
            end
        end
    end
    for name, p in pairs(held) do
        if targets[name] == nil or e == nil then sendGone(p, id) end
    end
    if e ~= nil then Directives.holders[id] = targets else Directives.holders[id] = nil end
    return sent
end

-- Compatibilité : republie la consigne d'un PNJ (ou de tous) à ses destinataires.
function Directives.publish(id)
    if not isServer() then return false end
    if id ~= nil then
        Directives.sync(id, true)
        return true
    end
    for eid in pairs(Directives.entries) do Directives.sync(eid, true) end
    return true
end

-- Trajet ouvert fermé (aucun module n'en ouvre depuis LK03-T04 ; fermeture gardée par prudence) : useless rendu par
-- la garde au passage suivant.
local function endServerRun(id)
    if Guard().isTravelling(id) then Guard().setTravelling(id, false) end
end

local function setGesture(id, g)
    local ok, why = Anim().setGesture(id, g)
    if not ok then log().warn("npc %s: gesture %s refused: %s", id, tostring(g), tostring(why)) end
end

-- Enregistre une nouvelle consigne (numéro suivant, bail donné au propriétaire actuel du corps z), geste, envoi aux
-- destinataires. Elle remplace la consigne courante du PNJ. Rend le numéro.
local function issue(id, e, z)
    local st = Directives.state
    st.seq = st.seq + 1
    e.v = st.seq
    e.issued = now()
    e.s = "issued"
    e.done = false
    endServerRun(id)
    grant(e, z)
    e.pl, e.po = nil, nil   -- nouvelle consigne : aucun rapport d'un bail précédent n'est attendu
    local S = LivingKnox.Senses   -- LK05-T03 : vigilance courante portée par la consigne
    if S ~= nil and type(S.vigilance) == "table" then e.vg = S.vigilance[id] end
    Directives.entries[id] = e
    Directives.accepted[id] = nil
    Directives.lastN[id] = nil
    Directives.stats.issued = Directives.stats.issued + 1
    local held = Directives.serverHeld(z)   -- LK03-T04 : aucun client propriétaire, consigne suspendue d'emblée
    if e.op == Directives.OP_MOVE and not held then setGesture(id, e.g) else setGesture(id, Anim().DEFAULT) end
    Directives.sync(id, true)
    if held then Directives.suspend(id, e, z) end
    return e.v
end

-- Corps relié d'un PNJ connu, ou nil et une raison.
local function boundBody(id)
    local B = Bodies()
    if B == nil then return nil, "LivingKnox.Bodies is not loaded" end
    local ok, why = B.canAct(true)
    if not ok then return nil, why end
    if type(id) ~= "string" or id == "" then return nil, "bad npc id " .. tostring(id) end
    local z, where = B.find(id)
    if z == nil then return nil, "npc " .. id .. " has no body in the loaded area (" .. tostring(where) .. ")" end
    return z
end

-- Plantes cultivées et feux de camp (LK04-T06, fiche docs/conception/consignes.md) : une case visée qui porte une
-- plante ou un feu de camp, ou dont une voisine en porte (Bodies.HAZARD_AVOID), est décalée vers la case praticable la
-- plus proche sans danger à HAZARD_AVOID + 1 cases, à SHIFT_RADIUS cases au plus ; sinon la consigne est refusée.
-- Le trajet lui-même peut traverser ces cases (la recherche de chemin d'un zombie ne les évite pas) : les cases
-- dangereuses de la ligne droite sont comptées et signalées (mesure du risque, la fiche donne la probabilité).
Directives.SHIFT_RADIUS = 3

-- Cases distinctes du segment (x0, y0) -> (x1, y1) au niveau z (pas d'un quart de case) qui portent une plante ou un
-- feu de camp ; avec margin (LK05-T12), cases de la zone dangereuse : danger à margin cases ou moins (Tchebychev).
-- memo (facultatif) : table case -> danger | false partagée entre appels de même margin. Rend le nombre et la première
-- trouvée ("x,y danger"), ou 0.
function Directives.hazardsOnLine(x0, y0, x1, y1, z, margin, memo)
    local B = Bodies()
    local len = dist(x0, y0, x1, y1)
    local steps = math.max(1, math.ceil(len * 4))
    local seen, n, first = {}, 0, nil
    local cell = getCell()
    local r = margin or 0
    for i = 0, steps do
        local sx = math.floor(x0 + (x1 - x0) * i / steps)
        local sy = math.floor(y0 + (y1 - y0) * i / steps)
        local key = sx .. "," .. sy
        if not seen[key] then
            seen[key] = true
            local what
            if r <= 0 then
                what = B.hazardOn(cell:getGridSquare(sx, sy, z))
            else
                local known = memo and memo[key]
                if known == nil then
                    known = B.hazardNear(sx, sy, z, r) or false
                    if memo then memo[key] = known end
                end
                if known ~= false then what = known end
            end
            if what ~= nil then
                n = n + 1
                if first == nil then first = key .. " " .. what end
            end
        end
    end
    return n, first
end

-- ---------------------------------------------------------------- points de passage (LK05-T12)
-- Une ligne droite départ -> destination qui traverse la zone dangereuse (plante ou feu de camp et ses 8 voisines,
-- hazardsOnLine avec margin = Bodies.HAZARD_AVOID) est découpée en étapes qui contournent la boîte englobante des
-- dangers voisins de la ligne (dangers à LINK cases ou moins les uns des autres réunis), à DETOUR_MARGIN cases de
-- celle-ci : la zone s'arrête à 1 case des dangers, un point de passage est à 3, et un corps arrivé à la tolérance
-- (ARRIVE = 1 case du centre) reste à 2 cases au moins, hors zone. Candidats, dans un ordre fixe : un coin de la boîte
-- élargie (4), puis deux coins voisins dans les deux sens (8) ; chaque segment vérifié par hazardsOnLine, chaque point
-- chargé, praticable (isFree(false)) et hors zone (sinon la case la plus proche à NUDGE case qui l'est) ; trajet total
-- au plus ligne droite + MAX_DETOUR ; le plus court gagne (le premier à égalité : déterministe). Données déjà en
-- mémoire seulement (getGridSquare d'une case non chargée rend nil : point refusé). Entre deux étapes, le chemin reste
-- celui du jeu (non exposé à Lua) : le risque est réduit, pas supprimé. Corps parti DE la zone (arrêt à côté d'une
-- plante) : le premier segment n'est vérifié que sur les cases portant un danger (il quitte forcément la zone).
Directives.MAX_STEPS = 4         -- étapes d'une consigne au plus, destination comprise
Directives.DETOUR_MARGIN = 3     -- cases entre la boîte des dangers et un point de passage
Directives.LINK = 4              -- dangers à LINK cases ou moins réunis dans la même boîte (aucun passage entre eux)
Directives.MAX_BOX = 24          -- côté maximal (cases) de la boîte des dangers ; au-delà, pas de contournement
Directives.MAX_DETOUR = 30       -- cases de trajet en plus de la ligne droite, au plus
Directives.NUDGE = 1             -- point de passage impraticable : case de remplacement à NUDGE case au plus

-- Boîte englobante des dangers proches de la ligne, étendue de proche en proche (LINK). Rend minx, miny, maxx, maxy,
-- ou nil et une raison.
local function hazardBox(x0, y0, x1, y1, z)
    local B = Bodies()
    local cell = getCell()
    local m = B.HAZARD_AVOID
    local found, queue = {}, {}
    local box = nil
    local function add(x, y)
        local key = x .. "," .. y
        if found[key] then return end
        found[key] = true
        queue[#queue + 1] = { x, y }
        if box == nil then
            box = { x, y, x, y }
        else
            box[1], box[2] = math.min(box[1], x), math.min(box[2], y)
            box[3], box[4] = math.max(box[3], x), math.max(box[4], y)
        end
    end
    local function scan(cx, cy, r)
        for dx = -r, r do
            for dy = -r, r do
                if B.hazardOn(cell:getGridSquare(cx + dx, cy + dy, z)) ~= nil then add(cx + dx, cy + dy) end
            end
        end
    end
    local len = dist(x0, y0, x1, y1)
    local steps = math.max(1, math.ceil(len * 4))
    local seen = {}
    for i = 0, steps do
        local sx = math.floor(x0 + (x1 - x0) * i / steps)
        local sy = math.floor(y0 + (y1 - y0) * i / steps)
        local key = sx .. "," .. sy
        if not seen[key] then
            seen[key] = true
            scan(sx, sy, m)
        end
    end
    if box == nil then return nil, "no hazard near the line" end
    local i = 1
    while i <= #queue do
        scan(queue[i][1], queue[i][2], Directives.LINK)
        if box[3] - box[1] + 1 > Directives.MAX_BOX or box[4] - box[2] + 1 > Directives.MAX_BOX then
            return nil, string.format("hazard area wider than %d squares", Directives.MAX_BOX)
        end
        i = i + 1
    end
    return box[1], box[2], box[3], box[4]
end

-- Point de passage praticable hors zone à (x, y, z), ou à NUDGE case au plus. Rend x, y, ou nil.
local function waypointAt(x, y, z)
    local B = Bodies()
    local sq = getCell():getGridSquare(x, y, z)
    if sq ~= nil and sq:isFree(false) and B.hazardNear(x, y, z, B.HAZARD_AVOID + 1) == nil then return x, y end
    local alt = B.safeSquare(x, y, z, Directives.NUDGE, B.HAZARD_AVOID + 1)
    if alt == nil then return nil end
    return alt:getX(), alt:getY()
end

-- Points de passage du trajet (x0, y0) (position du corps) -> case (tx, ty) au niveau z. Rend une liste
-- { { x, y }, ... } (vide si la ligne droite est hors zone), ou nil et une raison (aucun contournement simple).
function Directives.planDetour(x0, y0, tx, ty, z)
    local B = Bodies()
    local m = B.HAZARD_AVOID
    local memo = {}
    local ex, ey = tx + 0.5, ty + 0.5
    local startIn = B.hazardNear(math.floor(x0), math.floor(y0), z, m) ~= nil
    local function clear(ax, ay, bx, by, first)
        if first and startIn then return Directives.hazardsOnLine(ax, ay, bx, by, z) == 0 end
        return Directives.hazardsOnLine(ax, ay, bx, by, z, m, memo) == 0
    end
    if clear(x0, y0, ex, ey, true) then return {} end
    local minx, miny, maxx, maxy = hazardBox(x0, y0, ex, ey, z)
    if minx == nil then return nil, miny end
    local g = Directives.DETOUR_MARGIN
    local raw = { { minx - g, miny - g }, { maxx + g, miny - g }, { maxx + g, maxy + g }, { minx - g, maxy + g } }
    local corners = {}
    for i = 1, 4 do
        local cx, cy = waypointAt(raw[i][1], raw[i][2], z)
        if cx ~= nil then corners[i] = { x = cx, y = cy } else corners[i] = false end
    end
    local candidates = {}
    for i = 1, 4 do candidates[#candidates + 1] = { i } end
    for i = 1, 4 do
        local j = i + 1
        if j > 4 then j = 1 end
        candidates[#candidates + 1] = { i, j }
        candidates[#candidates + 1] = { j, i }
    end
    local direct = dist(x0, y0, ex, ey)
    local best, bestLen = nil, nil
    for _, c in ipairs(candidates) do
        local pts, ok = {}, #c + 1 <= Directives.MAX_STEPS
        for _, ci in ipairs(c) do
            if corners[ci] == false then ok = false else pts[#pts + 1] = corners[ci] end
        end
        if ok then
            local len, ax, ay = 0, x0, y0
            for n = 1, #pts + 1 do
                local bx, by = ex, ey
                if n <= #pts then bx, by = pts[n].x + 0.5, pts[n].y + 0.5 end
                len = len + dist(ax, ay, bx, by)
                if len > direct + Directives.MAX_DETOUR or (bestLen ~= nil and len >= bestLen)
                    or not clear(ax, ay, bx, by, n == 1) then
                    ok = false
                    break
                end
                ax, ay = bx, by
            end
            if ok then best, bestLen = pts, len end
        end
    end
    if best == nil then
        return nil, string.format("no clear detour around the hazards in %d,%d-%d,%d", minx, miny, maxx, maxy)
    end
    local out = {}
    for i = 1, #best do out[i] = { x = best[i].x, y = best[i].y } end
    return out
end

-- Porte d'abord (LK04-T09, fiche docs/conception/deplacement.md, section « Porte d'abord ») : quand la ligne droite
-- n'a pas de détour de potager (planDetour rend une liste vide), les points de passage par une porte ou un portail
-- calculés par l'autorité (LivingKnox.Obstacles.planDoorRoute, absent sur un client MP) remplacent une fenêtre ou une
-- clôture basse franchie par le chemin vanilla. Un itinéraire dont un segment passe SUR la case d'une plante ou d'un
-- feu de camp (hazardsOnLine sans marge) est écarté : le potager prime (LK04-T06). Campagne solo du 2026-10-15
-- (runs/20261015-122214-c3211ee9c847) : avec la marge HAZARD_AVOID, une plante sur la case voisine de la sortie d'une
-- porte écartait tout trajet par cette porte, deux PNJ restés 11 min contre la fenêtre (11317.5,6938.5) ; frôler une
-- plante en passant ne la détruit pas (seul un zombie sur sa case, J/characters/IsoZombie.java:2837-2842). Corps à un
-- autre niveau que la destination : rien (itinéraire d'un seul niveau). Rend les points (ou nil), le relevé, et la raison d'un
-- itinéraire écarté.
function Directives.planDoors(id, body, x, y, z)
    local O = LivingKnox.Obstacles
    if O == nil or O.planDoorRoute == nil or math.floor(body:getZ()) ~= z then return nil end
    local bx, by = body:getX(), body:getY()
    local w, info = O.planDoorRoute(id, bx, by, x, y, z)
    if w == nil or #w == 0 then return nil, info end
    local memo, ax, ay = {}, bx, by
    for i = 1, #w + 1 do
        local px, py = x + 0.5, y + 0.5
        if i <= #w then px, py = w[i].x + 0.5, w[i].y + 0.5 end
        local n, first = Directives.hazardsOnLine(ax, ay, px, py, z, 0, memo)
        if n > 0 then return nil, info, tostring(first) end
        ax, ay = px, py
    end
    return w, info
end

-- Consigne "aller à" la case (x, y, z), geste walk (défaut), run ou crouch. Case chargée, praticable, à MAX_TRIP
-- cases au plus du corps, décalée hors des plantes et feux de camp (voir plus haut). Rend le numéro de la consigne,
-- ou nil et une raison.
function Directives.moveTo(id, x, y, z, gesture)
    local refused = refuseUnlessAuthority()
    if refused then return nil, refused end
    local body, why = boundBody(id)
    if not body then return nil, why end
    if not finite(x) or not finite(y) or not finite(z) then return nil, "target must be three numbers" end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local g = gesture or "walk"
    if not Directives.MOVE_GESTURES[g] then return nil, "move gesture must be walk, run or crouch, not " .. tostring(g) end
    local far = dist(body:getX(), body:getY(), x + 0.5, y + 0.5)
    if far > Directives.MAX_TRIP then
        return nil, string.format("target %d,%d,%d is %.1f squares away (max %d)", x, y, z, far, Directives.MAX_TRIP)
    end
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return nil, string.format("target square %d,%d,%d is not loaded", x, y, z) end
    if not sq:isFree(false) then return nil, string.format("target square %d,%d,%d is not walkable", x, y, z) end
    local Mv = LivingKnox.Movement   -- LK04-T05 : case d'un échec "stuck" récent de ce PNJ
    local avoid = Mv ~= nil and Mv.avoided ~= nil and Mv.avoided(id, x, y, z) or nil
    if avoid ~= nil then return nil, avoid end
    local B = Bodies()
    local what, hx, hy = B.hazardNear(x, y, z, B.HAZARD_AVOID)
    if what ~= nil then
        local safe = B.safeSquare(x, y, z, Directives.SHIFT_RADIUS, B.HAZARD_AVOID + 1)
        if safe == nil then
            return nil, string.format("target %d,%d,%d is next to a %s at %d,%d and no safe square within %d", x, y, z,
                what, hx, hy, Directives.SHIFT_RADIUS)
        end
        log().info("npc %s: move target %d,%d,%d shifted to %d,%d (%s at %d,%d)", id, x, y, z, safe:getX(),
            safe:getY(), what, hx, hy)
        x, y = safe:getX(), safe:getY()
        avoid = Mv ~= nil and Mv.avoided ~= nil and Mv.avoided(id, x, y, z) or nil
        if avoid ~= nil then return nil, avoid end
    end
    local bx, by = body:getX(), body:getY()
    local steps, noDetour = Directives.planDetour(bx, by, x, y, z)
    local doorSteps, doorInfo, doorDropped = nil, nil, nil
    if steps ~= nil and #steps == 0 then doorSteps, doorInfo, doorDropped = Directives.planDoors(id, body, x, y, z) end
    local e = { op = Directives.OP_MOVE, x = x, y = y, z = z, g = g }
    if steps ~= nil and #steps > 0 then e.w, e.k = steps, 1 end
    if doorSteps ~= nil and #doorSteps > 0 then e.w, e.k = doorSteps, 1 end
    -- LK04-T20 : dernier recours d'un PNJ enfermé (Obstacles.planDoorRoute, itinéraire "trapped") : les décisions au
    -- contact (Obstacles.decide, decideWindow) autorisent alors la fenêtre verrouillée ou le foyer d'un autre groupe
    -- abordés de l'intérieur. Champ de l'autorité seulement (wire ne l'envoie pas : l'exécutant n'en a pas besoin).
    if doorInfo ~= nil and doorInfo.lastResort == true then e.lr = true end
    local v = issue(id, e, body)
    log().info("npc %s: move #%d to %d,%d,%d (%s) from %.1f,%.1f", id, v, x, y, z, g, bx, by)
    if doorDropped ~= nil then
        log().warn("npc %s: move #%d door route dropped: it passes next to %s; the vanilla path may use a window or "
            .. "a fence", id, v, doorDropped)
    end
    if e.w ~= nil then
        local parts = {}
        for i = 1, #e.w do parts[i] = e.w[i].x .. "," .. e.w[i].y end
        if doorSteps ~= nil and #doorSteps > 0 and e.lr then
            log().info("npc %s: move #%d split into %d steps (%s; %d squares searched, %d ms): %s then %d,%d", id, v,
                #e.w + 1, tostring(doorInfo.reason), doorInfo.nodes or 0, doorInfo.ms or 0, table.concat(parts, " "),
                x, y)
        elseif doorSteps ~= nil and #doorSteps > 0 then
            log().info("npc %s: move #%d split into %d steps %s (%d squares searched, %d ms): %s then %d,%d", id, v,
                #e.w + 1, tostring(doorInfo.reason), doorInfo.nodes or 0, doorInfo.ms or 0, table.concat(parts, " "),
                x, y)
        else
            log().info("npc %s: move #%d split into %d steps around farming plants or campfires: %s then %d,%d", id,
                v, #e.w + 1, table.concat(parts, " "), x, y)
        end
    elseif doorInfo ~= nil and (doorInfo.climbs or 0) > 0 then
        -- LK04-T20 : aucune porte pour sortir et aucun itinéraire de dernier recours : le chemin natif gardé échouera
        -- probablement (fenêtre barricadée, refus au contact) : WARN.
        local warn = doorInfo.noExitDoor ~= nil and not e.lr
        local say = warn and log().warn or log().info
        say("npc %s: move #%d keeps the vanilla path over %d window or fence crossing(s): %s%s", id, v,
            doorInfo.climbs, tostring(doorInfo.reason), e.lr and " (last resort allowed at contact)" or "")
    elseif steps == nil then
        local n, first = Directives.hazardsOnLine(bx, by, x + 0.5, y + 0.5, z)
        if n > 0 then
            log().warn("npc %s: move #%d straight line crosses %d farming plant or campfire square(s) (first %s) and "
                .. "%s: the vanilla path may cross them", id, v, n, first, tostring(noDetour))
        else
            log().warn("npc %s: move #%d straight line passes next to farming plants or campfires and %s", id, v,
                tostring(noDetour))
        end
    end
    return v
end

-- Étape suivante d'une consigne à points de passage (autorité) : numéro k, journal, table republiée.
local function advanceStep(id, e, k, by)
    e.k = k
    local tx, ty = Directives.stepTarget(e, k)
    log().info("npc %s: move #%d step %d/%d reached (by %s), next %d,%d", id, e.v, k - 1, Directives.stepCount(e),
        tostring(by), tx, ty)
    Directives.sync(id, true)
end

-- Consigne "s'arrêter". Rend le numéro, ou nil et une raison.
function Directives.stop(id)
    local refused = refuseUnlessAuthority()
    if refused then return nil, refused end
    local z, why = boundBody(id)
    if not z then return nil, why end
    local v = issue(id, { op = Directives.OP_STOP }, z)
    log().info("npc %s: stop #%d", id, v)
    return v
end

-- Consigne "se tourner vers" dir (nom N, NE, E, SE, S, SW, W, NW ou angle en degrés). Rend le numéro, ou nil et une
-- raison.
function Directives.face(id, dir)
    local refused = refuseUnlessAuthority()
    if refused then return nil, refused end
    local z, why = boundBody(id)
    if not z then return nil, why end
    local a = Directives.angleOf(dir)
    if a == nil then return nil, "direction must be N, NE, E, SE, S, SW, W, NW or a number, not " .. tostring(dir) end
    local v = issue(id, { op = Directives.OP_FACE, a = a }, z)
    log().info("npc %s: face #%d to %s degrees", id, v, tostring(a))
    return v
end

-- Vigilance du PNJ portée par sa consigne courante (LK05-T03, champ vg) : changée sans nouvelle consigne (même numéro
-- v), republiée aux détenteurs si elle change (serveur). Sans consigne : rien (l'exécutant garde la vigilance déduite).
-- Rend vrai si la consigne a changé.
function Directives.setVigil(id, kind)
    if not LivingKnox.isAuthority() then return false end
    local e = Directives.entries[id]
    if e == nil or e.vg == kind then return false end
    e.vg = kind
    Directives.sync(id, true)
    return true
end

-- Consigne courante d'un PNJ (copie), ou nil.
function Directives.get(id)
    local e = Directives.entries[id]
    if e == nil then return nil end
    local out = wire(e, Directives.state.rev)
    out.by, out.issued = e.by, e.issued
    out.why, out.wd = e.why, e.wd   -- raison et détail d'un échec (LK04-T05)
    return out
end

-- Oublie la consigne d'un PNJ (corps retiré, PNJ oublié) ; ses détenteurs reçoivent { gone }. La remise (LK03-T03)
-- est oubliée même sans consigne. Rend vrai si une consigne existait.
function Directives.forget(id)
    Directives.hands[id], Directives.handPrev[id] = nil, nil
    if Directives.entries[id] == nil then return false end
    Directives.entries[id] = nil
    Directives.poses[id] = nil
    Directives.accepted[id] = nil
    Directives.lastN[id] = nil
    Directives.bodySeen[id] = nil
    endServerRun(id)
    if isServer() then
        for _, p in pairs(Directives.holders[id] or {}) do sendGone(p, id) end
    end
    Directives.holders[id] = nil
    return true
end

-- ---------------------------------------------------------------- fin d'une consigne

local function finish(id, e, s, by, why, detail)
    e.done = true
    e.s = s
    e.by = by
    if s == "failed" then e.why, e.wd = why, detail end
    endServerRun(id)
    if e.op == Directives.OP_MOVE then
        setGesture(id, (e.g == "crouch" and s == "arrived") and "crouch" or Anim().DEFAULT)
    end
    Directives.sync(id, true)
    local ms = now() - (e.issued or now())
    if s == "failed" then
        log().warn("npc %s: %s #%d failed after %d ms (%s%s, by %s)", id, e.op, e.v, ms, tostring(why),
            detail and (": " .. detail) or "", tostring(by))
        local Mv = LivingKnox.Movement   -- LK04-T05 : case visée d'un échec "stuck" évitée par ce PNJ
        if Mv ~= nil and why == Mv.REASON and e.op == Directives.OP_MOVE then Mv.noteStuck(id, e) end
    else
        log().info("npc %s: %s #%d %s after %d ms (by %s)", id, e.op, e.v, s, ms, tostring(by))
    end
end

-- Refus d'une consigne ouverte par l'autorité (LK04-T02 : porte barricadée, verrouillée ou d'un autre foyer sur le
-- trajet, LK_Obstacles.lua) : close en échec (by "server", raison why), publiée ; l'exécutant arrête le corps à la
-- réception de la consigne close (LK_Executor.lua). Rend vrai si une consigne ouverte a été close.
function Directives.abort(id, why)
    if not LivingKnox.isAuthority() then return false end
    local e = Directives.entries[id]
    if e == nil or e.done then return false end
    finish(id, e, "failed", "server", why)
    return true
end

-- Pose gardée (numéro par PNJ croissant) ; serveur : confiée au relais des gestes (LK03-T05, clients proches) ; en
-- solo, gardée seulement.
local function relay(id, e, s, x, y, z, a, t, by)
    local st = Directives.state
    st.pr = st.pr + 1
    local g = Anim().gestureOf(id)
    local pose = { pr = st.pr, v = e.v, s = s, a = a, g = g, x = x, y = y, z = z, t = t or 0, ts = serverTime() }
    Directives.poses[id] = pose
    pose.by = by
    local R = LivingKnox.Relay
    if isServer() and R ~= nil and R.touch ~= nil then
        R.touch(id)
        Directives.stats.relayed = Directives.stats.relayed + 1
    end
    return pose
end

-- ---------------------------------------------------------------- rapports (client propriétaire, solo)

local function reject(name, id, reason, detail)
    Directives.stats.rejected = Directives.stats.rejected + 1
    local key = tostring(name) .. "|" .. reason
    local last = Directives.warned[key]
    if last == nil or now() - last >= Directives.WARN_EVERY_MS then
        Directives.warned[key] = now()
        log().warn("report on npc %s from %s refused: %s%s", tostring(id), tostring(name), reason,
            detail and (" (" .. detail .. ")") or "")
    end
    return false, reason
end

-- Vrai si player est le propriétaire du corps z (serveur) ; solo : la seule machine.
function Directives.isOwner(z, player)
    if not isServer() then return true end
    if player == nil then return false end
    local owner = z:getOwnerPlayer()
    return owner ~= nil and owner == player
end

-- Rapport d'exécution. player : expéditeur (serveur : joueur de la connexion ; solo : joueur local). Rend vrai si
-- accepté, sinon faux et la raison.
-- Bail (LK03-T01) : un rapport porte le bail l sous lequel il a été produit. Accepté : bail courant (e.l) et
-- expéditeur = propriétaire du corps ; numéro n croissant dans ce bail. Rapport de l'ANCIEN bail (e.pl, de l'ancien
-- exécutant e.po), livré après le transfert : un état final (arrived, stopped, faced, failed) l'est encore pendant
-- LEASE_GRACE_MS si le nouvel exécutant n'a encore rien rapporté (aucune consigne perdue ni rejouée par le nouveau) ;
-- sinon ignoré sans avertissement (course attendue). Bail inconnu (plus grand que le courant) : refusé.
function Directives.onReport(player, args)
    if not LivingKnox.isAuthority() then return false, "not the authority" end
    Directives.stats.reports = Directives.stats.reports + 1
    local name = senderName(player)
    if type(args) ~= "table" then return reject(name, "?", "bad report") end
    local id = args.id
    if type(id) ~= "string" or type(args.v) ~= "number" or type(args.n) ~= "number" or type(args.l) ~= "number"
        or not Directives.REPORT_STATES[args.s] or not finite(args.x) or not finite(args.y) or not finite(args.z) then
        return reject(name, id, "bad report")
    end
    local e = Directives.entries[id]
    if e == nil then return reject(name, id, "no directive") end
    -- Numéro avant l'état : le rapport final d'une consigne déjà remplacée (stop #n livré après le move #n+1) est
    -- une course attendue, pas un rapport suspect (campagne MP 2026-10-14 : "state stopped for move" en WARN).
    if args.v ~= e.v or e.done then
        Directives.stats.stale = Directives.stats.stale + 1   -- consigne remplacée ou close : rien à faire
        return false, "stale"
    end
    if not Directives.OP_STATES[e.op][args.s] then return reject(name, id, "state " .. args.s .. " for " .. e.op) end
    local B = Bodies()
    local z = B and B.find(id)
    if z == nil then return reject(name, id, "no body") end
    local last = Directives.lastN[id]
    local graced = false
    if isServer() and e.pl ~= nil and args.l == e.pl and name == e.po then
        local fresh = now() - (e.leasedMs or 0) <= Directives.LEASE_GRACE_MS
        if args.s == "moving" or not fresh or (last ~= nil and last.l == e.l) then
            Directives.stats.stale = Directives.stats.stale + 1   -- ancien bail : le nouvel exécutant reprend
            return false, "previous lease"
        end
        graced = true
    else
        if not Directives.isOwner(z, player) then
            if Directives.isPreviousOwner(id, name) then   -- LK03-T03 : ancien propriétaire pas encore prévenu
                count("previousOwner")
                Directives.stats.stale = Directives.stats.stale + 1
                return false, "previous owner"
            end
            return reject(name, id, "not the owner", "owner " .. senderName(z:getOwnerPlayer()))
        end
        if args.l > e.l then return reject(name, id, "unknown lease", "lease " .. args.l .. ", current " .. e.l) end
        if args.l < e.l then
            Directives.stats.stale = Directives.stats.stale + 1   -- bail remplacé (reconnexion, retour du corps)
            return false, "previous lease"
        end
        if last ~= nil and last.l == e.l and args.n <= last.n then
            Directives.stats.stale = Directives.stats.stale + 1   -- rapport plus ancien livré après un plus récent
            return false, "older"
        end
    end
    local gap = dist(args.x, args.y, z:getX(), z:getY())
    if gap > Directives.MAX_GAP then
        return reject(name, id, "far from the body", string.format("%.1f squares", gap))
    end
    local prev = Directives.accepted[id]
    local t = now()
    if prev ~= nil and prev.v == e.v then
        local moved = dist(args.x, args.y, prev.x, prev.y)
        local allowed = Directives.SLACK + Directives.MAX_SPEED * (t - prev.ms) / 1000
        if moved > allowed then
            return reject(name, id, "too fast", string.format("%.1f squares in %d ms", moved, t - prev.ms))
        end
    end
    if args.s == "arrived" and e.op == Directives.OP_MOVE then
        local d = Directives.distToTarget(e, args.x, args.y, args.z)
        if d == nil or d > Directives.ARRIVE + 0.25 then
            return reject(name, id, "not at the target", d and string.format("%.2f squares", d) or "other level")
        end
    end
    if graced then
        count("graced")
        log().info("npc %s: %s #%d final report %s from %s (previous lease %d) accepted after the transfer to %s", id,
            e.op, e.v, args.s, name, args.l, tostring(e.o))
    else
        Directives.lastN[id] = { l = e.l, n = args.n }
        if e.handMs ~= nil and e.handL == e.l then   -- LK03-T03 : premier rapport du nouvel exécutant
            local ms = t - e.handMs
            local st = Directives.stats
            st.resumed = st.resumed + 1
            st.resumeLast = ms
            if st.resumeMax == nil or ms > st.resumeMax then st.resumeMax = ms end
            log().info("npc %s: %s #%d resumed by %s %d ms after the owner change (lease %d)", id, e.op, e.v, name,
                ms, e.l)
            e.handMs, e.handL = nil, nil
        end
    end
    Directives.accepted[id] = { by = name, x = args.x, y = args.y, v = e.v, ms = t }
    Directives.stats.accepted = Directives.stats.accepted + 1
    if e.by ~= name then
        if e.by ~= nil then log().info("npc %s: %s #%d now executed by %s (was %s)", id, e.op, e.v, name, e.by) end
        e.by = name
    end
    endServerRun(id)   -- un client simule le corps : le serveur cesse tout trajet en ligne droite
    local a = finite(args.a) and args.a or nil
    -- Étape (LK05-T12) : k = étape suivante annoncée à l'arrivée sur un point de passage ; acceptée seulement d'une
    -- étape à la fois et près du point atteint, sinon ignorée (le rapport de position reste valable).
    local cur = e.k or 1
    if type(args.k) == "number" and args.k ~= cur and type(e.w) == "table" then
        local ds = Directives.distToStep(e, cur, args.x, args.y, args.z)
        if args.k == cur + 1 and args.k <= Directives.stepCount(e) and ds ~= nil
            and ds <= Directives.ARRIVE + 0.25 then
            if args.s == "moving" then advanceStep(id, e, args.k, name) else e.k = args.k end
        else
            Directives.stats.stepIgnored = (Directives.stats.stepIgnored or 0) + 1
        end
    end
    if args.s == "moving" then
        e.s = "moving"
    else
        local Mv = LivingKnox.Movement   -- raison et détail bornés (texte d'un client)
        finish(id, e, args.s, name, Mv.cleanWhy(args.why), Mv.cleanWhy(args.wd, Mv.DETAIL_MAX))
    end
    relay(id, e, args.s, args.x, args.y, args.z, a, type(args.t) == "number" and args.t or 0, name)
    return true
end

-- ---------------------------------------------------------------- corps simulé par le serveur (LK03-T04)
-- Aucune consigne n'est exécutée par le serveur : la consigne ouverte d'un corps sans client propriétaire est
-- suspendue, le corps mis au repos (état neutre). Voir l'en-tête et docs/conception/consignes.md, « Corps simulé par
-- le serveur ».

-- Suspend la consigne ouverte e du corps z (serveur, aucun client propriétaire) : elle reste ouverte et publiée (bail
-- donné à "server" : aucun client ne l'exécute), le corps s'arrête (setMoving(false) ; trajet fermé, la garde rend
-- useless et efface toute cible au passage suivant) et le geste revient à "idle". Idempotent. Rend vrai si la
-- consigne vient d'être suspendue.
function Directives.suspend(id, e, z)
    if e.done or e.suspended ~= nil then return false end
    e.suspended = now()
    endServerRun(id)
    if z ~= nil then z:setMoving(false) end
    setGesture(id, Anim().DEFAULT)
    count("suspended")
    log().info("npc %s: %s #%d suspended, no client simulates the body: at rest until a client owns it", id, e.op,
        e.v)
    return true
end

-- Reprise d'une consigne suspendue par le nouveau propriétaire name : le temps suspendu est rendu au délai maximal
-- (e.issued décalé d'autant) et le geste de la consigne rétabli. L'exécution elle-même suit le nouveau bail.
local function unsuspend(id, e, name)
    if e.suspended == nil then return false end
    local paused = math.max(0, now() - e.suspended)
    e.issued = (e.issued or now()) + paused
    e.suspended = nil
    if e.op == Directives.OP_MOVE then setGesture(id, e.g) end
    count("unsuspended")
    log().info("npc %s: %s #%d resumed by %s after %d ms suspended", id, e.op, e.v, tostring(name), paused)
    return true
end

-- Serveur (LK03-T01), pour une consigne dont le corps est présent : dans cet ordre,
-- 1. changement de propriétaire (consigne ouverte, ou close depuis LK03-T02) : nouveau bail donné au nouveau
--    propriétaire (ou "server"), envoi à tous les destinataires ; le moteur ne change de propriétaire qu'à chaque
--    image, après le Lua, et au plus une fois par 2 s hors déconnexion (J/popman/NetworkZombieManager.java:60-131,
--    135-181, 209-224 ; J/popman/NetworkZombiePacker.java:118-165) : le passage (SLOW_EVERY images) le voit au
--    plus 15 images après ;
-- 2. réapparition du corps sur le serveur (autre objet ou nouvel onlineId : retour de chunk, nouveau corps) :
--    réémission à tous les destinataires (les clients recréent alors leur copie) ;
-- 3. sinon, joueurs entrés dans le rayon : la consigne leur est envoyée ; sortis : { gone }.
-- Rend la raison d'une réémission ("owner", "body", "player") ou nil.
local function noteBody(id, z)
    Directives.bodySeen[id] = { z = z, o = z:getOnlineID() }
end

-- Consigne close (LK03-T02) : le bail suit aussi le propriétaire, car il désigne l'expéditeur des rapports d'état
-- (LK_Reports.lua) ; l'exécutant n'a rien à reprendre (consigne close), seule la ligne du journal passe en DEBUG.
-- Changement de propriétaire d'une consigne (serveur) : nouveau bail donné au propriétaire actuel name, envoi à tous
-- les destinataires. Heure notée pour la mesure de reprise (consigne ouverte, LK03-T03).
function Directives.transfer(id, e, z, name)
    local was = e.o
    grant(e, z)
    Directives.lastN[id] = nil
    count("leases")
    if not e.done and name ~= "server" then e.handMs, e.handL = e.leasedMs, e.l else e.handMs, e.handL = nil, nil end
    local say = e.done and log().debug or log().info
    say("npc %s: %s #%d leased to %s (was %s, lease %d)", id, e.op, e.v, name, tostring(was), e.l)
    noteBody(id, z)
    -- LK03-T04 : rendue au serveur, la consigne ouverte est suspendue ; reprise par un client, elle repart.
    if not e.done and name == "server" then
        Directives.suspend(id, e, z)
    elseif not e.done then
        unsuspend(id, e, name)
    end
    Directives.sync(id, true)
end

function Directives.watch(id, e, z)
    local name = Directives.ownerName(z)
    if e.o ~= name then
        Directives.transfer(id, e, z, name)
        return "owner"
    end
    local seen = Directives.bodySeen[id]
    if seen == nil or not rawequal(seen.z, z) or seen.o ~= z:getOnlineID() then
        noteBody(id, z)
        if seen ~= nil then
            count("reemitted")
            log().debug("npc %s: body reappeared (onlineId %s), directive #%d sent again", id,
                tostring(z:getOnlineID()), e.v)
            Directives.sync(id, true)
            return "body"
        end
    end
    if Directives.sync(id, false) > 0 then
        count("reemitted")
        return "player"
    end
    return nil
end

-- Passage de l'autorité : consignes de PNJ disparus oubliées, délai maximal d'un "move" (temps suspendu exclu) ;
-- serveur seulement : bail, réémission et destinataires (Directives.watch), consigne ouverte d'un corps sans client
-- propriétaire suspendue (LK03-T04 ; filet si le changement n'est pas passé par transfer).
function Directives.serverPass()
    local B = Bodies()
    if B == nil or not B.canAct(false) then return end
    local gone = {}
    for id, e in pairs(Directives.entries) do
        local z, where = B.find(id)
        if z ~= nil and isServer() then Directives.watch(id, e, z) end
        if z == nil and (where == "unknown" or where == "dead" or where == "virtual") then
            gone[#gone + 1] = id
        elseif z ~= nil and not e.done then
            if Directives.serverHeld(z) then
                Directives.suspend(id, e, z)
            elseif e.suspended == nil and e.op == Directives.OP_MOVE
                and now() - (e.issued or now()) > Directives.TRIP_TIMEOUT_MS then
                finish(id, e, "failed", e.by or "?", "timeout")
            end
        end
    end
    for _, id in ipairs(gone) do   -- table modifiée hors de pairs
        log().info("npc %s: directive dropped (npc %s)", id, tostring(select(2, B.find(id))))
        Directives.forget(id)
    end
end

-- ---------------------------------------------------------------- transfert de propriété (LK03-T03)
-- Le moteur change le propriétaire après le Lua de l'image (J/popman/NetworkZombiePacker.java:118-165) : comparé à
-- chaque image par ownerWatch, le changement est vu à l'image suivante, au lieu d'attendre le passage lent (15
-- images). La remise part avec le nouveau bail ; le client nouveau propriétaire reprend dès qu'il a le bail et sait
-- sa copie locale (LK_Executor : passage immédiat, voir la fiche consignes.md, « Transfert de propriété »).

-- Joueur connecté de ce compte, ou nil.
local function onlinePlayer(name)
    local list = getOnlinePlayers()
    if list == nil then return nil end
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p ~= nil and senderName(p) == name then return p end
    end
    return nil
end

-- Vrai si le compte name détenait la remise du PNJ id avant le dernier changement de propriétaire, il y a au plus
-- OWNER_GRACE_MS, ou la détient encore (changement pas encore vu : traité à l'image suivante). Serveur seulement.
function Directives.isPreviousOwner(id, name)
    if not isServer() or type(name) ~= "string" or name == "?" or name == "server" then return false end
    if Directives.hands[id] == name then return true end
    local prev = Directives.handPrev[id]
    return prev ~= nil and prev.name == name and now() - prev.ms <= Directives.OWNER_GRACE_MS
end

-- État utile du PNJ id remis au propriétaire name : { o, l, hp, w, er } (sans r). hp : santé du dernier rapport
-- d'état accepté pour ce même corps (LK_Reports) ; w, er : arme voulue et révision de la table des armes
-- (LK_Equipment). Réservés, absents tant qu'aucun module ne les tient : rs (étape de routine, LK05), tgt (cible
-- courante, LK06), am (munitions : LK_Equipment ne connaît que l'arme visible).
function Directives.handState(id, z, name)
    local e = Directives.entries[id]
    local out = { o = name, l = e and e.l or 0 }
    local R = LivingKnox.Reports
    local s = R and R.states and R.states[id]
    if s ~= nil and rawequal(s.body, z) and finite(s.hp) then out.hp = s.hp end
    local Eq = LivingKnox.Equipment
    if Eq ~= nil and type(Eq.wantedOf) == "function" then
        local w = Eq.wantedOf(id)
        if w ~= nil then out.w = { t = w.t, l = w.l, h = w.h == true } end
        out.er = Eq.state and Eq.state.rev or 0
    end
    return out
end

-- Remise du PNJ id au propriétaire actuel name (serveur). Consigne : nouveau bail si l'exécutant désigné diffère
-- (Directives.transfer). Envoi au nouveau propriétaire (joueur) et à l'ancien détenteur (o = nouveau : il la rend),
-- et au joueur player qui la demande ("dirClaim") même sans changement. outside = vrai : corps hors du monde, seul
-- le détenteur est mis à jour (aucun bail, l'ancien rend la remise).
function Directives.handover(id, z, name, player, outside)
    local e = Directives.entries[id]
    if not outside and e ~= nil and e.o ~= name then Directives.transfer(id, e, z, name) end
    local was = Directives.hands[id]
    local to = {}
    if was ~= name then
        Directives.hands[id] = name
        if was ~= nil then
            Directives.handPrev[id] = { name = was, ms = now() }
            if was ~= "server" then to[was] = onlinePlayer(was) end
        end
        if name ~= "server" and not outside then to[name] = z:getOwnerPlayer() end
        log().debug("npc %s: state handed to %s (was %s)", id, name, tostring(was))
    end
    if player ~= nil then to[senderName(player)] = player end
    local hand = nil
    for _, p in pairs(to) do
        hand = hand or Directives.handState(id, z, name)
        hand.r = nextR()
        local d = {}
        d[id] = hand
        sendServerCommand(p, Directives.MODULE, Directives.CMD_HAND, { r = hand.r, d = d })
        count("handed")
    end
end

-- Serveur, à chaque image : propriétaire de chaque corps relié comparé au détenteur de la remise.
function Directives.ownerWatch()
    if not isServer() then return end
    local B = Bodies()
    if B == nil or B.bound == nil or getCell() == nil then return end
    local changed = nil
    for id, z in pairs(B.bound) do
        if z ~= nil and not z:isDead() and Directives.hands[id] ~= Directives.ownerName(z) then
            changed = changed or {}
            changed[#changed + 1] = id
        end
    end
    if changed == nil then return end
    for _, id in ipairs(changed) do   -- envois et baux hors de pairs
        local z = B.bound[id]
        Directives.handover(id, z, Directives.ownerName(z), nil, not B.inWorld(z))
    end
end

-- Demande d'un client dont la copie est locale sans remise ("dirClaim") : remise (et bail) au seul propriétaire réel.
-- Rend le nombre de remises envoyées.
function Directives.onClaim(player, args)
    local ids = type(args) == "table" and args.ids or nil
    if type(ids) ~= "table" then return 0 end
    local B = Bodies()
    local n = 0
    for i = 1, Directives.ASK_MAX do
        local id = ids[i]
        if type(id) ~= "string" then break end
        count("claims")
        local z = B and B.find(id)
        if z ~= nil and Directives.isOwner(z, player) then
            Directives.handover(id, z, senderName(player), player)
            n = n + 1
        else
            count("claimIgnored")   -- copie qui n'est plus (ou pas encore) celle du propriétaire : course
        end
    end
    return n
end

-- ---------------------------------------------------------------- réseau

-- Entrée en partie d'un joueur ("guardHello", première connexion ou reconnexion) : consignes des corps à
-- NEAR_RADIUS cases de lui (ou qu'il détenait) envoyées en un message ; consigne ouverte dont il était l'exécutant
-- désigné (reconnexion) : nouveau bail donné au propriétaire actuel (sa session précédente est close, ses numéros de
-- rapport repartent de 1). Rend le nombre de consignes envoyées.
function Directives.onHello(player)
    local name = senderName(player)
    local B = Bodies()
    local d, n = {}, 0
    -- Remises détenues par ce compte (LK03-T03) : son nouvel état Lua n'en a plus ; renvoyées à l'image suivante.
    local mine = {}
    for id, h in pairs(Directives.hands) do
        if h == name then mine[#mine + 1] = id end
    end
    for _, id in ipairs(mine) do Directives.hands[id] = nil end   -- table modifiée hors de pairs
    for id, e in pairs(Directives.entries) do
        local z = B and B.find(id)
        local held = Directives.holders[id]
        local sent = false
        if z ~= nil and e.o == name then   -- consigne close comprise : bail des rapports d'état (LK03-T02)
            grant(e, z)
            Directives.lastN[id] = nil
            count("leases")
            local say = e.done and log().debug or log().info
            say("npc %s: %s #%d leased to %s after %s joined (lease %d)", id, e.op, e.v, tostring(e.o), name, e.l)
            Directives.sync(id, true)
            held = Directives.holders[id]
            sent = held ~= nil and held[name] ~= nil   -- déjà envoyée à ce joueur par sync
        end
        if not sent and ((z ~= nil and Directives.isNear(player, z)) or (held ~= nil and held[name] ~= nil)) then
            d[id] = wire(e, nextR())
            n = n + 1
            Directives.holders[id] = Directives.holders[id] or {}
            Directives.holders[id][name] = player
        end
    end
    if n > 0 then
        sendEntries(player, d)
        count("published")
    end
    return n
end

-- Demande d'un client dont la copie d'un corps vient d'apparaître (chargement, recréation après 5 s sans paquet) :
-- consigne courante de chaque PNJ demandé, ou { gone } s'il n'en a pas (ASK_MAX identifiants au plus).
function Directives.onAsk(player, args)
    local ids = type(args) == "table" and args.ids or nil
    if type(ids) ~= "table" then return 0 end
    local name = senderName(player)
    local d, n = {}, 0
    for i = 1, Directives.ASK_MAX do
        local id = ids[i]
        if type(id) ~= "string" then break end
        local e = Directives.entries[id]
        if e ~= nil then
            d[id] = wire(e, nextR())
            Directives.holders[id] = Directives.holders[id] or {}
            Directives.holders[id][name] = player
        else
            d[id] = { r = nextR(), gone = true }
        end
        n = n + 1
    end
    if n > 0 then
        sendEntries(player, d)
        count("asked")
    end
    return n
end

function Directives.onClientCommand(module, command, player, args)
    if module ~= Directives.MODULE or not isServer() or player == nil then return end
    if command == Directives.CMD_REPORT then
        Directives.onReport(player, args)
    elseif command == Directives.CMD_ASK then
        Directives.onAsk(player, args)
    elseif command == Directives.CMD_CLAIM then
        Directives.onClaim(player, args)
    elseif command == Guard().CMD_HELLO then
        Directives.onHello(player)   -- gestes et poses : LivingKnox.Relay.onHello (LK03-T05)
    end
end

function Directives.tick()
    local st = Directives.state
    if isServer() then Directives.ownerWatch() end   -- à chaque image (LK03-T03)
    st.ticks = st.ticks + 1
    if st.ticks < Directives.SLOW_EVERY then return end
    st.ticks = 0
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    Directives.serverPass()
end

-- ---------------------------------------------------------------- abonnements (autorité ; commandes : serveur seulement,
-- en solo l'exécutant lit Directives.entries et appelle Directives.onReport directement)

if LivingKnox.isAuthority() then
    local function onTick()
        LivingKnox.Directives.tick()
    end
    LivingKnox.subscribe("OnTick", "Directives.tick", onTick)
end
if isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Directives.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Directives.onClientCommand", onClientCommand)
end

return Directives
