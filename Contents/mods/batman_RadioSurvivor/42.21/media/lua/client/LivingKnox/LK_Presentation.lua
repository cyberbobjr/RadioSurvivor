-- Living Knox : pose relayée des corps de PNJ chez les clients qui ne les simulent pas (LK02-T07).
-- Fiche : docs/conception/consignes.md. Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Client MP seulement (en solo, la seule copie est simulée ici et n'a rien à recevoir). Le serveur relaie la pose du
-- dernier rapport accepté du propriétaire avec le geste, aux seuls clients proches, regroupée et bornée (LK03-T05,
-- server/LivingKnox/LK_Relay.lua : commande "animState", { d = { [npcId] = { r, g, p = { pr, v, s, a, x, y, z, t,
-- ts } } | { r, gone = true } } }). r : numéro d'envoi croissant (entrée plus ancienne ignorée) ; pr : numéro de
-- pose croissant par PNJ (une pose plus ancienne est ignorée, la même n'est pas recomptée) ; { gone } : PNJ sorti de
-- portée, pose oubliée. Le client qui entre en partie reçoit les poses à sa portée en réponse à "guardHello".
-- Ce qui est appliqué à la copie DISTANTE (isRemoteZombie) :
--   - geste : par LivingKnox.Anim, dont la table "animState" est réglée par le serveur d'après les mêmes rapports
--     (geste de la consigne en route, "idle" ou "crouch" à l'arrivée) ; rien n'est réécrit ici, pour ne pas lutter
--     avec le passage d'affichage d'Anim ;
--   - orientation : setDirectionAngle(a), une fois par pose reçue, seulement quand la pose est un arrêt (arrived,
--     stopped, faced, failed) et que la copie ne se déplace pas. Chaque paquet zombie réécrit déjà la direction
--     (J/characters/NetworkZombieAI.java:271) : la pose ne fait que l'anticiper, le paquet suivant a le dernier mot.
-- La position n'est JAMAIS touchée : la copie distante suit la position réseau (pathToLocationF du paquet, téléport
-- au-delà de 3 cases, J/characters/NetworkZombieAI.java:235-276).
-- Mesure du relais : délai = heure serveur synchronisée à la réception (GameTime.getServerTimeMills, 0 avant la
-- synchronisation : échantillon ignoré) - heure du rapport chez le propriétaire (t). Dernier, maximum et moyenne dans
-- Presentation.stats ; une ligne DEBUG par pose reçue.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"

local Presentation = LivingKnox.Presentation or {}
LivingKnox.Presentation = Presentation

Presentation.APPLY_EVERY = 10
Presentation.STILL = { arrived = true, stopped = true, faced = true, failed = true }

Presentation.poses = Presentation.poses or {}     -- npcId -> dernière pose reçue
Presentation.applied = Presentation.applied or {} -- npcId -> { pr, z } dernière pose appliquée à cette copie
Presentation.revs = Presentation.revs or {}       -- npcId -> dernier numéro d'envoi r reçu
Presentation.state = Presentation.state or { ticks = 0 }
Presentation.stats = Presentation.stats or { received = 0, older = 0, applied = 0, samples = 0, lastDelay = -1,
    maxDelay = -1, sumDelay = 0 }

local function log() return LivingKnox.Log end

local function serverTime()
    if GameTime ~= nil and GameTime.getServerTimeMills ~= nil then return GameTime.getServerTimeMills() end
    return 0
end

-- Pose connue d'un PNJ (copie de lecture), ou nil.
function Presentation.poseOf(npcId)
    return Presentation.poses[npcId]
end

-- Délai moyen du relais (ms), ou -1 sans échantillon.
function Presentation.meanDelay()
    local st = Presentation.stats
    if st.samples == 0 then return -1 end
    return st.sumDelay / st.samples
end

local function sample(id, pose)
    local t, here = pose.t, serverTime()
    if type(t) ~= "number" or t <= 0 or here <= 0 then return end
    local delay = here - t
    local st = Presentation.stats
    st.samples = st.samples + 1
    st.lastDelay = delay
    st.sumDelay = st.sumDelay + delay
    if delay > st.maxDelay then st.maxDelay = delay end
    log().debug("pose of npc %s received: %s, relay delay %d ms", id, tostring(pose.s), delay)
end

local function receivePose(id, pose)
    if type(pose) ~= "table" or type(pose.pr) ~= "number" then return end
    local known = Presentation.poses[id]
    if known ~= nil and pose.pr <= known.pr then
        if pose.pr < known.pr then Presentation.stats.older = Presentation.stats.older + 1 end
        return
    end
    Presentation.poses[id] = pose
    Presentation.stats.received = Presentation.stats.received + 1
    sample(id, pose)
end

function Presentation.onServerCommand(module, command, args)
    local A = LivingKnox.Anim
    if A == nil or module ~= A.MODULE or command ~= A.CMD_STATE or not isClient() then return end
    if type(args) ~= "table" or type(args.d) ~= "table" then return end
    for id, entry in pairs(args.d) do
        if type(id) == "string" and type(entry) == "table" and type(entry.r) == "number" then
            local known = Presentation.revs[id]
            if known ~= nil and entry.r <= known then
                Presentation.stats.older = Presentation.stats.older + 1
            else
                Presentation.revs[id] = entry.r
                if entry.gone == true then
                    Presentation.poses[id], Presentation.applied[id] = nil, nil
                else
                    receivePose(id, entry.p)
                end
            end
        end
    end
end

-- Applique la pose reçue à une copie distante. Rend vrai si l'orientation a été posée.
function Presentation.applyTo(z, pose)
    if not Presentation.STILL[pose.s] or type(pose.a) ~= "number" or z:isMoving() then return false end
    z:setDirectionAngle(pose.a)
    return true
end

function Presentation.pass()
    local known = LivingKnox.Anim.knownBodies()
    for id, z in pairs(known) do
        local pose = Presentation.poses[id]
        local done = Presentation.applied[id]
        if pose ~= nil and z:isRemoteZombie() and (done == nil or done.pr ~= pose.pr or done.z ~= z) then
            if Presentation.applyTo(z, pose) then Presentation.stats.applied = Presentation.stats.applied + 1 end
            Presentation.applied[id] = { pr = pose.pr, z = z }
        end
    end
end

function Presentation.tick()
    local st = Presentation.state
    st.ticks = st.ticks + 1
    if st.ticks < Presentation.APPLY_EVERY then return end
    st.ticks = 0
    if not isClient() or getCell() == nil then return end
    Presentation.pass()
end

if isClient() then
    local function onTick()
        LivingKnox.Presentation.tick()
    end
    local function onServerCommand(module, command, args)
        LivingKnox.Presentation.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnTick", "Presentation.tick", onTick)
    LivingKnox.subscribe("OnServerCommand", "Presentation.onServerCommand", onServerCommand)
end

return Presentation
