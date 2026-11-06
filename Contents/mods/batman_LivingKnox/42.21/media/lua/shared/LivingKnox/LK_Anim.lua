-- Living Knox : gestes des corps de PNJ (LK02-T05). Fiche : docs/annexes/conception/corps-et-animations.md, « Animations ».
-- Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Les nœuds ajoutés aux AnimSets des zombies (common/media/AnimSets/zombie/<état>/lkactor_*.xml, générés par
-- tools/gen_animsets.py) n'acceptent qu'un personnage portant la variable d'animation LKActor = vrai ; LKGesture
-- choisit le geste. Ces variables :
--   - ne sont pas synchronisées (J/network/NetworkVariables.java) et sont propres à chaque objet : chaque machine qui
--     affiche le corps les pose sur sa copie locale (solo : directement ; client MP : copies retrouvées par la garde,
--     LivingKnox.ZombieGuard.cache, à partir de la liste guardRoster du serveur) ;
--   - ne peuvent pas être posées sur un zombie par le serveur : setVariable y est sans effet
--     (J/characters/IsoGameCharacter.java:11374-11396, GameServer.server et IsoZombie) ; le serveur n'anime rien.
-- Autorité (serveur, solo) : LivingKnox.Anim.setGesture(npcId, geste) fixe le geste voulu. Solo : appliqué au passage
-- suivant. Serveur : le changement est confié au relais (LivingKnox.Relay, server/LivingKnox/LK_Relay.lua, LK03-T05),
-- qui l'envoie aux seuls clients proches, regroupé et borné (module "LivingKnox", commande "animState" :
-- { d = { [npcId] = { r, g, p } | { r, gone = true } } }), et au client qui entre en partie (réponse à "guardHello").
-- Livraison non ordonnée : entrée plus ancienne (r inférieur ou égal au dernier reçu pour ce PNJ) ignorée ; { gone }
-- oublie le geste (repos). Volet MP prévu, non validé en jeu.
-- Réapplication idempotente toutes les APPLY_EVERY images : une copie recréée (retour de chunk, copie cliente
-- recréée après 5 s sans paquet) n'a pas les variables et les reçoit au passage suivant ; rien n'est réécrit quand
-- elles sont déjà justes. Un corps qui n'est plus connu perd les deux variables (un zombie ordinaire n'en garde
-- jamais).
--
-- Gestes ponctuels (LK04-T13 ; fiche corps-et-animations.md, « Gestes d'ouverture ») : ouvrir ou fermer une fenêtre.
-- L'autorité les pose par Anim.startAct(npcId, geste, durée, angle) PAR-DESSUS le geste voulu, sans le remplacer :
-- Anim.gestureOf rend toujours le geste voulu (lu par les consignes, les routines, l'équipement), Anim.shownOf le geste
-- affiché (geste ponctuel en cours, sinon le geste voulu). Un geste ponctuel s'éteint seul à son échéance (passage de
-- l'autorité, puis envoi du geste voulu) ou par Anim.endAct. Relais : l'entrée porte le geste affiché g et, pendant un
-- geste ponctuel, l'angle fa vers lequel le corps doit se tourner (lu par l'exécutant, LK_Executor.lua). Chaque geste
-- ponctuel joue deux clips (nœuds lkactor_*windowstart puis lkactor_*window) : le premier pose VAR_PHASE à sa fin
-- (événement SetVariable) ; VAR_PHASE est effacée à chaque changement de geste affiché.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"

local Anim = LivingKnox.Anim or {}
LivingKnox.Anim = Anim

Anim.VAR_ACTOR = "LKActor"       -- BOOL : vrai pour un corps de PNJ (condition de tous nos nœuds)
Anim.VAR_GESTURE = "LKGesture"   -- STRING : un des gestes ci-dessous
Anim.DEFAULT = "idle"
Anim.GESTURES = { idle = true, walk = true, run = true, crouch = true, aim = true, guard = true, strike = true,
    sit = true,    -- sit : assis au sol (repos et sommeil des routines, LK05-T03)
    -- Corvées au foyer (LK05-T04) : accroupi les mains en avant (feu, soins), fouille d'un meuble, marteau, cigarette,
    -- assis les mains vers le feu. Gestes seuls : aucun objet en main ni modifié.
    kneel = true, rummage = true, hammer = true, smoke = true, warmhands = true,
    -- Tir (LK06-T03) : clip de tir du joueur en boucle (un coup de feu par boucle), rechargement en boucle.
    shoot = true, reload = true,
    -- Coup au sol (LK06-T09) : arme visée au sol (clips Bob_AttackFloorBat, Bob_AttackFloor1Hand) ou piétinement à
    -- mains nues (Bob_AttackFloorStamp), en boucle comme "strike".
    strikefloor = true, stomp = true,
    -- Reddition (LK06-T12) : debout, les deux mains levées (clip de l'emote vanilla de reddition, Bob_EmoteSurrender).
    surrender = true }
-- Gestes ponctuels (LK04-T13), posés par startAct seulement : ouvrir une fenêtre fermée, refermer une fenêtre.
-- LK04-T04 (passage bloqué, LK_Obstacles.lua) : "force" (frapper une barricade ou une porte) et "wait" (attendre
-- devant un passage bloqué), joués par un clip existant (ACT_CLIP) : l'exécutant garde le corps arrêté et tourné vers
-- l'obstacle comme pour une fenêtre.
Anim.ACTS = { openwindow = true, closewindow = true, force = true, wait = true }
-- Clip affiché (valeur de VAR_GESTURE) d'un geste ponctuel qui n'a pas ses propres nœuds ; sinon son propre nom.
Anim.ACT_CLIP = { force = "strike", wait = "idle" }
Anim.VAR_PHASE = "LKActPhase"    -- BOOL : second clip d'un geste ponctuel (posé par le premier nœud)
Anim.ACT_MAX_MS = 10000          -- durée maximale d'un geste ponctuel
Anim.MODULE = "LivingKnox"
Anim.CMD_STATE = "animState"     -- serveur -> client proche : { d = { [npcId] = { r, g, p } | { r, gone } } }
Anim.APPLY_EVERY = 3             -- images entre deux passages d'affichage

Anim.wanted = Anim.wanted or {}                     -- autorité : npcId -> geste voulu (absent = "idle")
Anim.remote = Anim.remote or { r = {}, g = {} }     -- client MP : npcId -> dernier numéro d'envoi r, geste reçu
Anim.remote.a = Anim.remote.a or {}                 -- client MP : npcId -> angle reçu d'un geste ponctuel (fa)
Anim.acts = Anim.acts or {}                         -- autorité : npcId -> { g, a, untilMs } geste ponctuel en cours
Anim.applied = Anim.applied or {}                   -- machine d'affichage : npcId -> objet portant nos variables
Anim.state = Anim.state or { ticks = 0, rev = 0 }
Anim.stats = Anim.stats or { passes = 0, sets = 0, cleared = 0, relayed = 0, older = 0 }
Anim.stats.acts = Anim.stats.acts or 0
Anim.stats.actsEnded = Anim.stats.actsEnded or 0

local function log() return LivingKnox.Log end
local function Guard() return LivingKnox.ZombieGuard end

function Anim.isGesture(g)
    return type(g) == "string" and Anim.GESTURES[g] == true
end

function Anim.isAct(g)
    return type(g) == "string" and Anim.ACTS[g] == true
end

-- Geste affichable (geste voulu ou geste ponctuel), reçu par un client.
function Anim.isShown(g)
    return Anim.isGesture(g) or Anim.isAct(g)
end

-- Geste voulu d'un PNJ sur cette machine (autorité : état local ; client : dernière table reçue, qui porte le geste
-- affiché, geste ponctuel compris).
function Anim.gestureOf(npcId)
    local g
    if LivingKnox.isAuthority() then
        g = Anim.wanted[npcId]
        if Anim.isGesture(g) then return g end
        return Anim.DEFAULT
    end
    g = Anim.remote.g[npcId]
    if Anim.isShown(g) then return g end
    return Anim.DEFAULT
end

-- Geste ponctuel en cours d'un PNJ sur cette machine : geste et angle (degrés, convention de setDirectionAngle), ou
-- nil. Autorité : tant que son échéance n'est pas passée ; client : dernière table reçue.
function Anim.actOf(npcId)
    if LivingKnox.isAuthority() then
        local a = Anim.acts[npcId]
        if a ~= nil and a.untilMs > getTimestampMs() then return a.g, a.a end
        return nil
    end
    local g = Anim.remote.g[npcId]
    if Anim.isAct(g) then return g, Anim.remote.a and Anim.remote.a[npcId] end
    return nil
end

-- Geste affiché d'un PNJ : geste ponctuel en cours, sinon geste voulu.
function Anim.shownOf(npcId)
    local g = Anim.actOf(npcId)
    if g ~= nil then return g end
    return Anim.gestureOf(npcId)
end

-- Valeur posée dans VAR_GESTURE pour le geste affiché g : clip d'un geste ponctuel sans nœuds propres (ACT_CLIP,
-- LK04-T04), sinon g.
function Anim.clipOf(g)
    return Anim.ACT_CLIP[g] or g
end

-- ---------------------------------------------------------------- autorité

-- Serveur : changement confié au relais (LK03-T05) ; sans relais chargé (suite isolée), rien n'est envoyé.
function Anim.notify(npcId)
    if not isServer() then return false end
    local R = LivingKnox.Relay
    if R == nil or R.touch == nil then return false end
    Anim.stats.relayed = Anim.stats.relayed + 1
    return R.touch(npcId)
end

-- Autorité : fixe le geste d'un PNJ ("idle" efface l'entrée). Rend vrai, ou faux et une raison.
function Anim.setGesture(npcId, gesture)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    if type(npcId) ~= "string" or npcId == "" then return false, "bad npc id " .. tostring(npcId) end
    if not Anim.isGesture(gesture) then return false, "unknown gesture " .. tostring(gesture) end
    local value = gesture
    if gesture == Anim.DEFAULT then value = nil end
    if Anim.wanted[npcId] == value then return true end
    Anim.wanted[npcId] = value
    log().debug("npc %s gesture %s", npcId, gesture)
    Anim.notify(npcId)
    return true
end

-- Autorité : geste ponctuel g (Anim.ACTS) pendant ms millisecondes, corps tourné vers l'angle a (facultatif). Remplace
-- un geste ponctuel en cours. Rend vrai, ou faux et une raison.
function Anim.startAct(npcId, g, ms, a)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    if type(npcId) ~= "string" or npcId == "" then return false, "bad npc id " .. tostring(npcId) end
    if not Anim.isAct(g) then return false, "unknown act " .. tostring(g) end
    if type(ms) ~= "number" or ms <= 0 or ms > Anim.ACT_MAX_MS then return false, "bad act duration " .. tostring(ms) end
    if a ~= nil and type(a) ~= "number" then return false, "bad act angle " .. tostring(a) end
    Anim.acts[npcId] = { g = g, a = a, untilMs = getTimestampMs() + ms }
    Anim.stats.acts = Anim.stats.acts + 1
    log().debug("npc %s act %s for %d ms", npcId, g, ms)
    Anim.notify(npcId)
    return true
end

-- Autorité : fin anticipée du geste ponctuel du PNJ (seulement s'il s'agit de g, quand g est donné). Rend vrai si un
-- geste a été retiré.
function Anim.endAct(npcId, g)
    local a = Anim.acts[npcId]
    if a == nil or (g ~= nil and a.g ~= g) then return false end
    Anim.acts[npcId] = nil
    Anim.stats.actsEnded = Anim.stats.actsEnded + 1
    Anim.notify(npcId)
    return true
end

-- Autorité : gestes ponctuels échus retirés (le relais envoie alors le geste voulu). Rend leur nombre.
function Anim.expireActs(t)
    local done = {}
    for id, a in pairs(Anim.acts) do
        if a.untilMs <= t then done[#done + 1] = id end
    end
    for _, id in ipairs(done) do   -- table modifiée hors de pairs
        Anim.acts[id] = nil
        Anim.stats.actsEnded = Anim.stats.actsEnded + 1
        Anim.notify(id)
    end
    return #done
end

-- ---------------------------------------------------------------- client MP

-- Entrées du relais (LK03-T05), PNJ par PNJ : la plus récente (r) gagne ; { gone } ou geste "idle" : repos. Geste
-- ponctuel (LK04-T13) : angle fa gardé avec lui.
function Anim.onServerCommand(module, command, args)
    if module ~= Anim.MODULE or command ~= Anim.CMD_STATE or not isClient() then return end
    if type(args) ~= "table" or type(args.d) ~= "table" then return end
    local remote = Anim.remote
    if remote.a == nil then remote.a = {} end   -- table remplacée sans elle (état client remis à zéro)
    for id, entry in pairs(args.d) do
        if type(id) == "string" and type(entry) == "table" and type(entry.r) == "number" then
            local known = remote.r[id]
            if known ~= nil and entry.r <= known then
                Anim.stats.older = Anim.stats.older + 1
            else
                remote.r[id] = entry.r
                if entry.gone == true or not Anim.isShown(entry.g) or entry.g == Anim.DEFAULT then
                    remote.g[id] = nil
                else
                    remote.g[id] = entry.g
                end
                if Anim.isAct(remote.g[id]) and type(entry.fa) == "number" then
                    remote.a[id] = entry.fa
                else
                    remote.a[id] = nil
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- affichage (solo, client MP)

-- Pose nos variables sur la copie locale d'un corps. Rend le nombre de variables écrites (0 = déjà justes). Geste
-- changé : VAR_PHASE effacée (un geste ponctuel repart de son premier clip, LK04-T13).
function Anim.applyTo(z, gesture)
    local n = 0
    if not z:getVariableBoolean(Anim.VAR_ACTOR) then
        z:setVariable(Anim.VAR_ACTOR, true)
        n = n + 1
    end
    if z:getVariableString(Anim.VAR_GESTURE) ~= gesture then
        z:setVariable(Anim.VAR_GESTURE, gesture)
        z:clearVariable(Anim.VAR_PHASE)
        n = n + 1
    end
    Anim.stats.sets = Anim.stats.sets + n
    return n
end

function Anim.clearFrom(z)
    z:clearVariable(Anim.VAR_ACTOR)
    z:clearVariable(Anim.VAR_GESTURE)
    z:clearVariable(Anim.VAR_PHASE)
    Anim.stats.cleared = Anim.stats.cleared + 1
end

-- Corps affichés ici : { [npcId] = zombie }. Solo : corps reliés par LK_Bodies ; client MP : copies retrouvées par
-- la garde (même contrôle que la garde : onlineId de la liste et joueur réanimé).
function Anim.knownBodies()
    local out = {}
    if LivingKnox.isAuthority() then
        local B = LivingKnox.Bodies
        if B == nil or B.bound == nil then return out end
        for id, z in pairs(B.bound) do
            if z ~= nil and not z:isDead() then out[id] = z end
        end
        return out
    end
    local G = Guard()
    for id, z in pairs(G.cache) do
        local entry = G.roster.byId[id]
        if entry ~= nil and z ~= nil and not z:isDead() and z:getOnlineID() == entry.o and z:isReanimatedPlayer() then
            out[id] = z
        end
    end
    return out
end

-- Passage d'affichage : variables posées sur chaque corps connu, retirées d'un objet qui n'est plus le corps courant.
function Anim.displayPass()
    local known = Anim.knownBodies()
    local stale = {}
    for id, z in pairs(Anim.applied) do
        if known[id] ~= z then stale[#stale + 1] = id end
    end
    for _, id in ipairs(stale) do   -- table modifiée hors de pairs
        local old = Anim.applied[id]
        Anim.applied[id] = nil
        if old ~= nil and not old:isDead() then Anim.clearFrom(old) end
    end
    for id, z in pairs(known) do
        Anim.applyTo(z, Anim.clipOf(Anim.shownOf(id)))
        Anim.applied[id] = z
    end
    Anim.stats.passes = Anim.stats.passes + 1
end

function Anim.tick()
    local st = Anim.state
    st.ticks = st.ticks + 1
    if st.ticks < Anim.APPLY_EVERY then return end
    st.ticks = 0
    if LivingKnox.isAuthority() then Anim.expireActs(getTimestampMs()) end
    if not LivingKnox.hasLocalPlayer() or getCell() == nil then return end   -- serveur : rien à afficher
    Anim.displayPass()
end

-- ---------------------------------------------------------------- abonnements

local function onTick()
    LivingKnox.Anim.tick()
end

LivingKnox.subscribe("OnTick", "Anim.tick", onTick)

if isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.Anim.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "Anim.onServerCommand", onServerCommand)
end

return Anim
