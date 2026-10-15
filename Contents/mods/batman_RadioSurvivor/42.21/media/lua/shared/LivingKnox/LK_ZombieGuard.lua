-- Living Knox : neutralisation des comportements de zombie des corps de PNJ (LK02-T04).
-- Fiche : docs/conception/neutralisation.md. Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Seuls les corps de PNJ sont touchés, jamais un zombie sans étiquette :
--   autorité (serveur, solo) : corps reliés par LivingKnox.Bodies.bound (étiquette relue par le sondage borné de
--     LK_Bodies) ;
--   client MP : les ModData d'un zombie ne sont pas transmises ; le serveur envoie la liste { onlineId -> PNJ }
--     (module "LivingKnox", commande "guardRoster", numéro de version croissant) et le client retrouve ses copies
--     locales par un sondage borné de la liste des zombies (onlineId connu ET isReanimatedPlayer).
-- Apparition (LK03-T06, fiche neutralisation.md « Apparition chez les clients MP ») : le serveur publie la liste
--   dès qu'un corps est relié (création, retour de chunk), dans la même image que la réanimation, donc avant
--   l'envoi des paquets de zombies (NetworkZombiePacker.postupdate, J/network/ServerMap.java:548, appelé après le
--   Lua, J/network/GameServer.java:1010-1073). Chaque entrée porte aussi l'identifiant de tenue persistante du corps
--   (descripteur partagé, J/SharedDescriptors.java:44-96), que le client connaît DÈS OnZombieCreate (posé avant
--   l'événement, J/VirtualZombieManager.java:197-207, 265-271 ; onlineId et drapeaux ne viennent qu'après,
--   J/popman/NetworkZombieSimulator.java:176-188). Client : copie rendue muette dans OnZombieCreate si cet
--   identifiant est dans la liste, puis confirmée au tick suivant par onlineId + isReanimatedPlayer (sinon voix
--   rendue, après HOLD_MS pour un joueur réanimé : liste attendue) ; copie arrivée avant la liste : retrouvée parmi
--   les zombies nés récemment dès la réception de la liste. Identifiants de tenue des corps sortis de la liste
--   (chunk déchargé) retenus GONE_MS : copie recréée à leur retour muette dès OnZombieCreate.
--   Une copie confirmée est repassée à chaque image pendant FRESH_MS (habillage par le descripteur partagé, qui
--   remet le préfixe vanilla : J/characters/IsoZombie.java:3792-3805).
-- Ce qui est posé, et où :
--   simulateur (client propriétaire en MP, serveur quand il simule lui-même, solo) : useless TOUJOURS, trajet compris
--     (repérage, bruit, errance et regroupement coupés : J/characters/IsoZombie.java:1309, 1700, 2005,
--     J/ai/states/ZombieIdleState.java:78, J/ai/ZombieGroupManager.java:70 ; LK06-T10 : voir « trajets » plus bas),
--     cible effacée, repas annulé
--     (setEatBodyTarget, J/characters/IsoZombie.java:4136-4184), cible de coups effacée (setThumpTarget,
--     J/iso/IsoMovingObject.java:407-413) ;
--   toute machine (serveur, clients, solo) : noTeeth. La morsure est décidée par le simulateur
--     (J/ai/states/AttackState.java:137 ; client : GameClient.sendZombieHit, le serveur applique le paquet sans
--     relire noTeeth, J/network/fields/hit/Bite.java:58-80) et noTeeth n'est pas transmis : chaque machine qui peut
--     devenir propriétaire le porte déjà ;
--   chaque machine qui joue des sons (clients, solo) : préfixe de voix inexistant (voix jouées localement,
--     J/characters/IsoZombie.java:2888-2929 ; le serveur n'en joue aucune). Le préfixe contient « Zombie » pour
--     survivre au contrôle du constructeur (J/characters/IsoZombie.java:393-395). Cris de douleur, de chute, de
--     mort, de repas et de relevé ne sont pas des sons distincts : ce sont des états (paramètre FMOD ZombieState)
--     de l'unique événement de voix (J/audio/parameters/ParameterZombieState.java ; IsoZombie.playHurtSound ne
--     joue rien, J/characters/IsoZombie.java:3473-3476). Une voix vanilla déjà lancée (avant la liaison ou après
--     une remise du préfixe par setFemaleEtc, J/characters/IsoZombie.java:3732-3747) est arrêtée par son nom
--     (LK06-T06) ; hurtSound reçoit aussi un nom inexistant.
-- Tout est réappliqué de façon idempotente à chaque passage (nouveau propriétaire, retour de chunk, copie recréée
-- par le client après 5 s sans paquet).
-- Coût : un passage toutes les APPLY_EVERY images, sur les seuls corps connus (au plus Bodies.MAX_EMBODIED) ;
-- client : tranche de SCAN_BUDGET zombies toutes les SLOW_EVERY images, seulement si la liste n'est pas vide.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Guard = LivingKnox.ZombieGuard or {}
LivingKnox.ZombieGuard = Guard

Guard.MODULE = "LivingKnox"
Guard.CMD_HELLO = "guardHello"     -- client -> serveur : demande de la liste (entrée en partie)
Guard.CMD_ROSTER = "guardRoster"   -- serveur -> client(s) : { rev, bodies = { { o = onlineId, id, t = trajet } } }
Guard.SILENT_VOICE = "LKSilentZombie"
Guard.SILENT_HURT = Guard.SILENT_VOICE .. "Hurt"   -- hurtSound : jamais joué par un zombie, posé par prudence
-- Voix vanilla d'un zombie (media/scripts/generated/sounds/zombies/sounds_zombie_voice_*.txt) : un seul événement
-- par zombie, qui porte aussi les cris de douleur, chute, mort, repas et relevé (paramètre ZombieState).
Guard.ZOMBIE_VOICES = {
    "MaleZombieVoiceA", "MaleZombieVoiceB", "MaleZombieVoiceC", "MaleZombieSprinterVoiceA",
    "MaleZombieSprinterVoiceB", "FemaleZombieVoiceA", "FemaleZombieVoiceB", "FemaleZombieVoiceC",
    "FemaleZombieSprinterVoiceA", "FemaleZombieSprinterVoiceB",
}
Guard.APPLY_EVERY = 3        -- images entre deux passages sur les corps connus
Guard.SLOW_EVERY = 15        -- images entre deux passages lents (liste du serveur, tranche client, dangers)
Guard.SCAN_BUDGET = 64       -- zombies examinés par tranche côté client
Guard.HELLO_RETRY = 600      -- images avant de redemander la liste tant qu'aucune n'est reçue
Guard.FRESH_MS = 3000        -- client : copie confirmée repassée à chaque image pendant ce délai (habillage)
Guard.SEEN_MS = 10000        -- client : zombies nés récemment gardés pour une liste reçue après eux
Guard.SEEN_MAX = 1024        -- client : au-delà, un zombie né n'est retrouvé que par le sondage borné
Guard.BORN_MAX = 512         -- client : zombies nés pendant une seule image retenus au plus
-- Client : identifiants de tenue des corps sortis de la liste (corps déchargé avec son chunk) gardés GONE_MS pour
-- rendre muette dès OnZombieCreate la copie recréée à son retour, même si elle arrive avant la nouvelle liste
-- (paquets de zombies et commandes Lua non ordonnés entre eux). Campagne MP du 2026-10-15 (lk.spawnclean, retour
-- de chunk) : copie née avant la liste, identifiant de tenue absent de la liste, préfixe vanilla pendant 54 images
-- jusqu'à l'adoption.
Guard.GONE_MS = 300000
Guard.GONE_MAX = 256
-- Client : copie rendue muette à sa naissance (identifiant de tenue d'un corps connu) mais pas encore confirmée par
-- son onlineId : gardée muette HOLD_MS au plus en attendant la liste (adoption), puis voix rendue.
Guard.HOLD_MS = 3000

Guard.travel = Guard.travel or {}   -- autorité : npcId -> true pendant un trajet autorisé (posé par LK02-T07)
Guard.state = Guard.state or { ticks = 0, slow = 0, rev = 0, signature = "", cursor = 0, hello = 0 }
Guard.roster = Guard.roster or { rev = -1, count = 0, byId = {}, byOnline = {}, byOutfit = {} }   -- client MP
Guard.cache = Guard.cache or {}     -- client MP : npcId -> copie locale du corps
Guard.born = Guard.born or {}       -- client MP : { z, ms, pre } zombies nés depuis la dernière image
Guard.seen = Guard.seen or {}       -- client MP : onlineId -> { z, ms } zombies nés depuis moins de SEEN_MS
Guard.seenCount = Guard.seenCount or 0
Guard.recent = Guard.recent or {}   -- client MP : npcId -> instant (ms) jusqu'auquel la copie est repassée par image
Guard.hazardSeen = Guard.hazardSeen or {}
Guard.gone = Guard.gone or {}       -- client MP : identifiant de tenue -> instant (ms) de fin de mémoire
Guard.goneCount = Guard.goneCount or 0
Guard.held = Guard.held or {}       -- client MP : copie muette en attente de la liste -> instant (ms) de fin d'attente
Guard.stats = Guard.stats or { passes = 0, bodies = 0, scanned = 0, published = 0, actions = 0 }
Guard.stats.voicesStopped = Guard.stats.voicesStopped or 0   -- voix vanilla encore jouées puis arrêtées
Guard.stats.preSilenced = Guard.stats.preSilenced or 0       -- copies rendues muettes dans OnZombieCreate
Guard.stats.adopted = Guard.stats.adopted or 0               -- copies confirmées à leur apparition
Guard.stats.restored = Guard.stats.restored or 0             -- voix rendue à un zombie pris à tort (liste périmée)

local function log() return LivingKnox.Log end

-- ---------------------------------------------------------------- trajets (consultés par la garde, posés en LK02-T07)

-- Autorité : ouvre ou ferme un trajet autorisé. Le changement part aux clients avec la liste suivante (champ t).
-- LK06-T10 : le drapeau ne lève PLUS useless. Un corps non useless exécute IsoZombie.RespondToSound
-- (J/characters/IsoZombie.java:1303-1420, seule garde Lua possible : useless, ligne 1309) : depuis LK06-T08 les bruits
-- des PNJ ont une source nil (attrait non nul), et le corps entendait jusqu'à son propre bruit de pas, émis sur sa
-- case donc « derrière » lui (IsoUtils.isSimilarDirection faux), d'où setTurnAlertedValues (alerted vrai,
-- lignes 1383, 1395, 1520), l'état turnalerted (media/actiongroups/zombie/*/to_turnalerted.xml) et un chemin remplacé
-- par pathToSound (constat en jeu du 2026-10-12 : 7 s en turnalerted, 0,52 case parcourue). Aucun autre levier Lua :
-- alerted est une variable d'animation en lecture seule, ni timeSinceSeenFlesh, ni soundReactDelay, ni ghost, ni
-- l'ouïe d'un zombie n'ont de mutateur exposé. Un corps marche donc en état pathfind (PathFindState ne teste pas
-- useless ; seul WalkTowardState.enter le fait, J/ai/states/WalkTowardState.java:56), comme LK_Executor.issuePath.
function Guard.setTravelling(npcId, on)
    if not LivingKnox.isAuthority() or type(npcId) ~= "string" then return false end
    Guard.travel[npcId] = on and true or nil
    return true
end

-- Vrai si le PNJ est en trajet autorisé (autorité : état local ; client : dernière liste reçue).
function Guard.isTravelling(npcId)
    if LivingKnox.isAuthority() then return Guard.travel[npcId] == true end
    local e = Guard.roster.byId[npcId]
    return e ~= nil and e.t == true
end

-- ---------------------------------------------------------------- application sur un corps

-- Vrai si cette machine simule le zombie : client = not isRemoteZombie() ; serveur = aucune connexion
-- propriétaire (isRemoteZombie y vaut vrai pour un zombie qu'il simule, J/characters/component/
-- NetworkZombieComponent.java:23) ; solo = toujours.
function Guard.simulatedHere(z)
    local side = LivingKnox.side()
    if side == LivingKnox.SIDE_CLIENT then return not z:isRemoteZombie() end
    if side == LivingKnox.SIDE_SERVER then return z:getOwner() == nil end
    return true
end

Guard.voiceBroken = Guard.voiceBroken or false

-- Arrête les voix vanilla encore jouées par l'émetteur du corps (nom de la voix courante compris, utile pour un
-- préfixe d'un autre mod). Rend le nombre de voix arrêtées. isPlaying(String) compare le nom du GameSound joué
-- (fmod/fmod/FMODSoundEmitter.java:603-614, 910, 937) ; stopSoundByName ignore un nom inconnu (lignes 166-186).
local function stopVoices(emitter, current)
    local n = 0
    if current ~= nil and emitter:isPlaying(current) then
        emitter:stopSoundByName(current)
        n = n + 1
    end
    for _, name in ipairs(Guard.ZOMBIE_VOICES) do
        if name ~= current and emitter:isPlaying(name) then
            emitter:stopSoundByName(name)
            n = n + 1
        end
    end
    return n
end

-- Voix coupée par un préfixe inexistant ; quand le préfixe change ou que sweep est vrai, les voix vanilla en cours
-- sont arrêtées. Rend le nombre de changements faits.
local function silenceNow(z, sweep)
    local desc = z:getDescriptor()
    if desc == nil then return 0 end
    local n = 0
    local current = nil
    if desc:getVoicePrefix() ~= Guard.SILENT_VOICE then
        current = z:getVoiceSoundName()
        desc:setVoicePrefix(Guard.SILENT_VOICE)
        n = n + 1
        sweep = true
    end
    if z:getHurtSound() ~= Guard.SILENT_HURT then
        z:setHurtSound(Guard.SILENT_HURT)
        n = n + 1
    end
    if sweep then
        local emitter = z:getEmitter()
        if emitter ~= nil then
            local stopped = stopVoices(emitter, current)
            Guard.stats.voicesStopped = Guard.stats.voicesStopped + stopped
            n = n + stopped
        end
    end
    return n
end

function Guard.silence(z, sweep)
    if Guard.voiceBroken then return 0 end
    local ok, changed = pcall(silenceNow, z, sweep == true)
    if ok then return changed end
    Guard.voiceBroken = true  -- une seule ligne d'erreur, pas une par passage
    log().error("voice cut failed, voices left on: %s", tostring(changed))
    return 0
end

-- Voix vanilla rendue à un zombie rendu muet à tort (liste périmée) : préfixe et hurtSound tels que les pose
-- setFemaleEtc (J/characters/IsoZombie.java:3732-3739). Rend vrai si rendue.
function Guard.unsilence(z)
    local ok, done = pcall(function()
        local desc = z:getDescriptor()
        if desc == nil or desc:getVoicePrefix() ~= Guard.SILENT_VOICE then return false end
        local prefix = z:isFemale() and "FemaleZombie" or "MaleZombie"
        desc:setVoicePrefix(prefix)
        z:setHurtSound(prefix .. "Hurt")
        return true
    end)
    if not ok then
        log().error("voice restore failed: %s", tostring(done))
        return false
    end
    if done then Guard.stats.restored = Guard.stats.restored + 1 end
    return done
end

-- Applique la garde à un corps de PNJ. travelling : drapeau de trajet (sans effet depuis LK06-T10, voir
-- Guard.setTravelling) ; simulated : cette machine le simule ; voice : cette machine joue les voix ; sweep : chercher
-- aussi une voix vanilla encore jouée (passage lent). Rend le nombre de changements faits (0 quand tout était déjà en
-- place).
function Guard.apply(z, travelling, simulated, voice, sweep)
    local n = 0
    if not z:isNoTeeth() then
        z:setNoTeeth(true)
        n = n + 1
    end
    if simulated then
        if not z:isUseless() then
            z:setUseless(true)
            n = n + 1
        end
        if z:getTarget() ~= nil then
            z:setTarget(nil)
            n = n + 1
        end
        if z:getEatBodyTarget() ~= nil then
            z:setEatBodyTarget(nil, false)
            n = n + 1
        end
        if z:getThumpTarget() ~= nil then
            z:setThumpTarget(nil)
            n = n + 1
        end
    end
    if voice then n = n + Guard.silence(z, sweep) end
    Guard.stats.actions = Guard.stats.actions + n
    return n
end

-- Comportements que l'API ne coupe pas (J/characters/IsoZombie.java:2837-2847) : plante cultivée détruite au hasard
-- sous le corps, feu de camp éteint par un corps en marche. Signalés une fois par case (mesure en jeu). L'évitement
-- (LK04-T06) est ailleurs : destination décalée (Directives.moveTo), corps à l'arrêt écarté (Bodies.hazardPass),
-- création hors de ces cases (Bodies.findFreeSquare). Sur un client MP, hasLitCampfire vaut toujours faux (systèmes
-- de GlobalObject du serveur seulement, J/iso/IsoGridSquare.java:9740-9757) : seul le serveur peut signaler un feu.
function Guard.checkHazards(z, npcId)
    local sq = z:getCurrentSquare()
    if sq == nil then return nil end
    local what = nil
    if sq:hasFarmingPlant() then
        what = "farming plant"
    elseif z:isMoving() and sq:hasLitCampfire() then
        what = "lit campfire"
    end
    if what == nil then return nil end
    local key = tostring(npcId) .. "@" .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ() .. ":" .. what
    if not Guard.hazardSeen[key] then
        Guard.hazardSeen[key] = true
        log().warn("npc %s is on a %s at %s,%s,%s: the engine may destroy it (not preventable)", tostring(npcId),
            what, tostring(sq:getX()), tostring(sq:getY()), tostring(sq:getZ()))
    end
    return what
end

-- ---------------------------------------------------------------- autorité (serveur, solo)

local function bound()
    local B = LivingKnox.Bodies
    return B and B.bound or nil
end

-- Liste publiée aux clients : corps reliés, dans le monde, avec un onlineId attribué. Rend la liste triée par
-- numéro de PNJ et sa signature.
function Guard.buildRoster()
    local list, ids = {}, {}
    local b = bound()
    if b == nil or getCell() == nil then return list, "" end
    local zombies = getCell():getZombieList()
    for id, z in pairs(b) do
        if z ~= nil and not z:isDead() and zombies:contains(z) then
            local onlineId = z:getOnlineID()
            if type(onlineId) == "number" and onlineId >= 0 then
                ids[#ids + 1] = { id = id, o = onlineId, p = z:getPersistentOutfitID() }
            end
        end
    end
    table.sort(ids, function(a, c) return a.id < c.id end)
    local parts = {}
    for i, e in ipairs(ids) do
        local t = Guard.travel[e.id] == true
        list[i] = { o = e.o, p = e.p, id = e.id, t = t }
        parts[i] = e.id .. "=" .. e.o .. "/" .. tostring(e.p) .. (t and "T" or "")
    end
    return list, table.concat(parts, ";")
end

function Guard.rosterArgs(list)
    return { rev = Guard.state.rev, bodies = list }
end

-- Serveur : renvoie la liste à tous les clients quand elle change (corps relié ou retiré, nouvel onlineId, trajet).
function Guard.publish(force)
    if not isServer() then return false end
    local list, signature = Guard.buildRoster()
    local st = Guard.state
    if signature == st.signature and not force then return false end
    st.signature = signature
    st.rev = st.rev + 1
    sendServerCommand(Guard.MODULE, Guard.CMD_ROSTER, Guard.rosterArgs(list))
    Guard.stats.published = Guard.stats.published + 1
    log().debug("guard roster %d sent (%d body(ies))", st.rev, #list)
    return true
end

function Guard.authorityPass(slow)
    local b = bound()
    if b == nil then return end
    local voice = LivingKnox.hasLocalPlayer()  -- solo : voix jouées ici
    for id, z in pairs(b) do
        if z ~= nil and not z:isDead() then
            local simulated = Guard.simulatedHere(z)
            Guard.apply(z, Guard.travel[id] == true, simulated, voice, slow)
            Guard.stats.bodies = Guard.stats.bodies + 1
            if slow and simulated then Guard.checkHazards(z, id) end
        end
    end
    if slow then Guard.publish(false) end
end

-- Autorité : corps relié à l'instant (création, retour de chunk, redémarrage ; appelé par LivingKnox.Bodies). La
-- garde est posée tout de suite (solo : voix coupée avant le premier passage) et, sur un serveur, la liste part dans
-- la même image, avant l'envoi des paquets de zombies (voir l'en-tête).
function Guard.bodyBound(npcId, z)
    if not LivingKnox.isAuthority() or z == nil then return false end
    local ok, err = pcall(Guard.apply, z, Guard.travel[npcId] == true, Guard.simulatedHere(z),
        LivingKnox.hasLocalPlayer(), true)
    if not ok then log().error("guard not applied to npc %s at bind: %s", tostring(npcId), tostring(err)) end
    Guard.publish(false)
    return true
end

-- Serveur : un client entré en partie demande la liste courante (réponse à lui seul).
function Guard.onClientCommand(module, command, player, args)
    if module ~= Guard.MODULE or command ~= Guard.CMD_HELLO or not isServer() or player == nil then return end
    local list = Guard.buildRoster()
    sendServerCommand(player, Guard.MODULE, Guard.CMD_ROSTER, Guard.rosterArgs(list))
end

-- ---------------------------------------------------------------- client MP

-- Liste reçue du serveur ; une liste plus ancienne (livraison non ordonnée) est ignorée.
function Guard.onServerCommand(module, command, args)
    if module ~= Guard.MODULE or command ~= Guard.CMD_ROSTER or not isClient() then return end
    if type(args) ~= "table" or type(args.rev) ~= "number" then return end
    local roster = Guard.roster
    if args.rev < roster.rev then return end
    local byId, byOnline, byOutfit, count = {}, {}, {}, 0
    if type(args.bodies) == "table" then
        for _, e in ipairs(args.bodies) do
            if type(e) == "table" and type(e.id) == "string" and type(e.o) == "number" then
                local entry = { id = e.id, o = e.o, t = e.t == true }
                if type(e.p) == "number" and e.p ~= 0 then
                    entry.p = e.p
                    byOutfit[e.p] = entry
                end
                byId[e.id] = entry
                byOnline[e.o] = entry
                count = count + 1
            end
        end
    end
    -- Corps sortis de la liste : identifiant de tenue retenu GONE_MS (copie recréée au retour de son chunk).
    local now = getTimestampMs()
    for _, old in pairs(roster.byId or {}) do
        if old.p ~= nil and byOutfit[old.p] == nil and Guard.goneCount < Guard.GONE_MAX then
            if Guard.gone[old.p] == nil then Guard.goneCount = Guard.goneCount + 1 end
            Guard.gone[old.p] = now + Guard.GONE_MS
        end
    end
    for p in pairs(byOutfit) do
        if Guard.gone[p] ~= nil then
            Guard.gone[p] = nil
            Guard.goneCount = Guard.goneCount - 1
        end
    end
    roster.rev, roster.count, roster.byId, roster.byOnline, roster.byOutfit = args.rev, count, byId, byOnline,
        byOutfit
    -- Copie locale oubliée si le PNJ a quitté la liste ou changé d'onlineId (retour de chunk côté serveur).
    local stale = {}
    for id, z in pairs(Guard.cache) do
        local e = byId[id]
        if e == nil or z:getOnlineID() ~= e.o then stale[#stale + 1] = id end
    end
    for _, id in ipairs(stale) do
        Guard.cache[id] = nil
        Guard.recent[id] = nil
    end
    -- Copies déjà nées chez ce client (liste reçue après elles) : rendues muettes dès maintenant.
    Guard.adoptSeen()
end

local function matches(z, entry)
    return z ~= nil and not z:isDead() and z:getOnlineID() == entry.o and z:isReanimatedPlayer()
end

-- Client : copie reconnue comme corps de PNJ ; garde posée tout de suite (voix arrêtée si elle jouait déjà), puis
-- repassée à chaque image pendant FRESH_MS.
function Guard.adopt(z, entry)
    Guard.held[z] = nil
    Guard.cache[entry.id] = z
    Guard.recent[entry.id] = getTimestampMs() + Guard.FRESH_MS
    Guard.apply(z, entry.t, not z:isRemoteZombie(), true, true)
    -- Copie née au sol par l'identifiant du cadavre réanimé : remise debout (LK02-T14, LK_Stand.lua).
    if LivingKnox.Stand ~= nil then LivingKnox.Stand.watch(z) end
    Guard.stats.adopted = Guard.stats.adopted + 1
    log().debug("guard: npc %s copy adopted at its appearance (onlineId %s)", entry.id, tostring(entry.o))
end

-- Client : entrées de la liste dont la copie est née récemment ici (Guard.seen) mais pas encore reconnue.
function Guard.adoptSeen()
    for id, entry in pairs(Guard.roster.byId) do
        local s = Guard.seen[entry.o]
        if s ~= nil and Guard.cache[id] ~= s.z and matches(s.z, entry) then Guard.adopt(s.z, entry) end
    end
end

-- Client : abonné OnZombieCreate. onlineId et drapeaux ne sont pas encore posés, l'identifiant de tenue persistante
-- l'est déjà (voir l'en-tête) : s'il désigne un corps de la liste, voix coupée sur-le-champ. Confirmation à l'image
-- suivante (Guard.bornPass).
function Guard.onZombieCreate(z)
    if not isClient() or z == nil or #Guard.born >= Guard.BORN_MAX then return end
    local e = { z = z, ms = getTimestampMs() }
    Guard.born[#Guard.born + 1] = e
    local byOutfit = Guard.roster.byOutfit or {}
    local ok, p = pcall(function() return z:getPersistentOutfitID() end)
    local gone = ok and p ~= nil and Guard.gone[p] or nil
    if ok and p ~= nil and p ~= 0 and (byOutfit[p] ~= nil or (gone ~= nil and gone >= e.ms)) then
        e.pre = true
        Guard.silence(z, false)
        Guard.stats.preSilenced = Guard.stats.preSilenced + 1
    end
end

-- Client, à chaque image : zombies nés depuis l'image précédente (onlineId désormais posé). Corps de la liste :
-- adopté ; rendu muet à tort par une liste périmée : voix rendue. Tous sont retenus SEEN_MS pour une liste reçue
-- plus tard.
function Guard.bornPass()
    local born = Guard.born
    if #born == 0 then return end
    Guard.born = {}
    for _, e in ipairs(born) do
        local z = e.z
        local id = z:getOnlineID()
        if not z:isDead() and type(id) == "number" and id >= 0 then
            if Guard.seen[id] == nil then
                if Guard.seenCount < Guard.SEEN_MAX then
                    Guard.seen[id] = { z = z, ms = e.ms }
                    Guard.seenCount = Guard.seenCount + 1
                end
            else
                Guard.seen[id] = { z = z, ms = e.ms }
            end
            local entry = Guard.roster.byOnline[id]
            if entry ~= nil and matches(z, entry) then
                Guard.adopt(z, entry)
            elseif e.pre and z:isReanimatedPlayer() then
                -- Copie d'un corps connu dont la liste n'est pas encore arrivée : muette jusqu'à son adoption
                -- (Guard.adoptSeen à la réception), HOLD_MS au plus (Guard.heldPass).
                Guard.held[z] = e.ms + Guard.HOLD_MS
            elseif e.pre then
                Guard.unsilence(z)
            end
        elseif e.pre then
            Guard.unsilence(z)
        end
    end
end

-- Client, à chaque image : copies muettes en attente de la liste. Adoptée : sortie (Guard.adopt) ; morte : oubliée ;
-- attente dépassée : voix rendue (zombie ordinaire au même identifiant de tenue) ; sinon voix recoupée (habillage).
function Guard.heldPass()
    local now = getTimestampMs()
    local done = {}
    for z, untilMs in pairs(Guard.held) do
        if z:isDead() then
            done[#done + 1] = { z = z }
        elseif now > untilMs then
            done[#done + 1] = { z = z, restore = true }
        else
            Guard.silence(z, false)
        end
    end
    for _, d in ipairs(done) do
        Guard.held[d.z] = nil
        if d.restore then Guard.unsilence(d.z) end
    end
end

-- Client, passage lent : identifiants de tenue des corps sortis de la liste oubliés après GONE_MS.
function Guard.forgetGone()
    local now = getTimestampMs()
    local done = {}
    for p, untilMs in pairs(Guard.gone) do
        if now > untilMs then done[#done + 1] = p end
    end
    for _, p in ipairs(done) do
        Guard.gone[p] = nil
        Guard.goneCount = Guard.goneCount - 1
    end
end

-- Client, à chaque image : copies adoptées depuis moins de FRESH_MS, voix recoupée si l'habillage l'a remise.
function Guard.recentPass()
    local now = getTimestampMs()
    local done = {}
    for id, untilMs in pairs(Guard.recent) do
        local z, entry = Guard.cache[id], Guard.roster.byId[id]
        if now > untilMs or z == nil or entry == nil or not matches(z, entry) then
            done[#done + 1] = id
        else
            Guard.silence(z, false)
        end
    end
    for _, id in ipairs(done) do Guard.recent[id] = nil end
end

-- Client, passage lent : oubli des zombies nés depuis plus de SEEN_MS.
function Guard.forgetSeen()
    local now = getTimestampMs()
    local old = {}
    for id, s in pairs(Guard.seen) do
        if now - s.ms > Guard.SEEN_MS then old[#old + 1] = id end
    end
    for _, id in ipairs(old) do Guard.seen[id] = nil end
    Guard.seenCount = Guard.seenCount - #old
end

-- Tranche du sondage client : au plus budget zombies depuis le curseur ; onlineId de la liste d'abord (une table),
-- puis isReanimatedPlayer (un zombie ordinaire au même onlineId n'est jamais pris). Rend le nombre examiné.
function Guard.clientScan(budget)
    local list = getCell():getZombieList()
    local st = Guard.state
    local size = list:size()
    local examined = 0
    while examined < budget and examined < size do
        if st.cursor >= list:size() then st.cursor = 0 end
        local z = list:get(st.cursor)
        st.cursor = st.cursor + 1
        examined = examined + 1
        if z ~= nil then
            local entry = Guard.roster.byOnline[z:getOnlineID()]
            if entry ~= nil and Guard.cache[entry.id] ~= z and matches(z, entry) then
                Guard.cache[entry.id] = z
                log().debug("guard: npc %s found here (onlineId %s)", entry.id, tostring(entry.o))
            end
        end
    end
    Guard.stats.scanned = Guard.stats.scanned + examined
    return examined
end

local function sendHello()
    local player = getPlayer()
    if player == nil then return false end
    sendClientCommand(player, Guard.MODULE, Guard.CMD_HELLO, { v = 1 })
    return true
end

function Guard.clientPass(slow)
    local st = Guard.state
    if Guard.roster.rev < 0 then
        st.hello = st.hello - Guard.APPLY_EVERY
        if st.hello <= 0 and sendHello() then st.hello = Guard.HELLO_RETRY end
    end
    if slow then
        Guard.forgetSeen()
        Guard.forgetGone()
    end
    -- Tranche du sondage d'abord : une copie retrouvée est traitée dans le même passage.
    if slow and Guard.roster.count > 0 then Guard.clientScan(Guard.SCAN_BUDGET) end
    for id, entry in pairs(Guard.roster.byId) do
        local z = Guard.cache[id]
        if z ~= nil and not matches(z, entry) then
            Guard.cache[id] = nil
            z = nil
        end
        if z ~= nil then
            local simulated = not z:isRemoteZombie()
            Guard.apply(z, entry.t, simulated, true, slow)
            Guard.stats.bodies = Guard.stats.bodies + 1
            if slow and simulated then Guard.checkHazards(z, id) end
        end
    end
end

-- ---------------------------------------------------------------- abonnements

function Guard.tick()
    local st = Guard.state
    if isClient() and getCell() ~= nil then
        Guard.bornPass()
        Guard.heldPass()
        Guard.recentPass()
    end
    st.ticks = st.ticks + 1
    if st.ticks < Guard.APPLY_EVERY then return end
    st.ticks = 0
    st.slow = st.slow + Guard.APPLY_EVERY
    local slow = st.slow >= Guard.SLOW_EVERY
    if slow then st.slow = 0 end
    if getCell() == nil then return end
    Guard.stats.passes = Guard.stats.passes + 1
    if LivingKnox.isAuthority() then
        Guard.authorityPass(slow)
    else
        Guard.clientPass(slow)
    end
end

-- La garde ne dépend pas de l'option Enabled : un corps existant ne doit jamais redevenir un zombie.
local function onTick()
    LivingKnox.ZombieGuard.tick()
end

LivingKnox.subscribe("OnTick", "ZombieGuard.tick", onTick)

if isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.ZombieGuard.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "ZombieGuard.onClientCommand", onClientCommand)
elseif isClient() then
    local function onServerCommand(module, command, args)
        LivingKnox.ZombieGuard.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "ZombieGuard.onServerCommand", onServerCommand)
    local function onZombieCreate(z)
        LivingKnox.ZombieGuard.onZombieCreate(z)
    end
    LivingKnox.subscribe("OnZombieCreate", "ZombieGuard.onZombieCreate", onZombieCreate)
end

return Guard
