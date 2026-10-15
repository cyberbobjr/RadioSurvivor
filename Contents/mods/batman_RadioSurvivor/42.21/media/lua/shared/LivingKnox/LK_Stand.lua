-- Living Knox : corps de PNJ debout dès son apparition (LK02-T14). Fiche : docs/conception/corps-et-animations.md,
-- section « Apparition debout ». Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- Pourquoi le corps naît couché : IsoDeadBody.reanimate pose setOnFloor(true), reprend fallOnFront du cadavre, puis
-- fait passer l'ActionContext du zombie (J/iso/objects/IsoDeadBody.java:1874-1880, 1930-1937). La transition vanilla
-- idle -> onground ne demande que bOnFloor (media/actiongroups/zombie/idle/to_onground.xml, variable liée à
-- isOnFloor, J/characters/IsoGameCharacter.java:850) ; ZombieOnGroundState.enter rend le corps non collidable et
-- arme reanimateTimer à 30-90 (J/ai/states/ZombieOnGroundState.java:37-67, 157-159). L'état onground ne sort que
-- vers getup-fromOnBack / getup-fromOnFront (relevé Zombie_GetUp) quand le minuteur tombe à 0
-- (media/actiongroups/zombie/onground/to_getup-*.xml) : couché 1 à 3 s, puis relevé.
-- Aucun mod ne peut ajouter une transition : les actiongroups ne sont lus que dans le media du jeu
-- (J/characters/action/ActionGroup.java:32-47, getMediaFile). L'ActionContext n'est pas exposé à Lua, mais
-- IsoGameCharacter l'est : playbackRecordCurrentStateSnapshot / playbackSetCurrentStateSnapshot
-- (J/characters/IsoGameCharacter.java:11516-11528) relèvent et imposent l'état d'action courant
-- (J/characters/action/ActionStateContainer.java:199-243 ; ActionStateSnapshot = nom d'état + sous-états, objet
-- opaque pour Lua, jamais indexé ici). Le relevé est pris sur un zombie qui vient de naître : son ActionContext est
-- sur l'état initial « idle » du groupe zombie, sans sous-état (setGroup, J/characters/IsoZombie.java:412-413,
-- J/VirtualZombieManager.java:324-325, J/characters/action/ActionContext.java:210-213).
--
-- Remise debout (Stand.now) : setOnFloor(false), fallOnFront et knockedDown effacés, collidable rendu (ce que fait
-- ZombieGetUpState.exit, J/ai/states/ZombieGetUpState.java:47-53), état d'action imposé à « idle » (l'état idle n'a
-- plus de raison de repartir vers onground puisque bOnFloor est faux) et état Java changé tout de suite
-- (ZombieIdleState ; sinon il ne suit l'état d'action qu'à la mise à jour suivante,
-- J/characters/component/StateMachineComponent.java:67-87). Machine qui affiche le corps : alpha remis à 0, le
-- moteur le ramène vers sa cible (1 si visible) en quelques images (J/iso/IsoObject.java:3845-3870) : le fondu
-- masque la seule image encore couchée et le fondu d'animation (0,3 s) du couché vers le debout.
--
-- Où :
--   autorité (solo, serveur) : LivingKnox.Bodies.createBody, dans l'appel même de la réanimation ;
--   client MP : toute copie d'un corps de PNJ naît dans ZombieOnGroundState, car le serveur garde l'identifiant du
--     cadavre réanimé dans chaque paquet (J/characters/NetworkZombieAI.java:198, ZombiePacket.java:242-244) et le
--     client force alors l'état au sol (J/popman/NetworkZombieSimulator.java:226-233). LK_ZombieGuard.adopt confie la
--     copie à Stand.watch : remise debout si elle est couchée par ce seul effet, c'est-à-dire si ce client la simule
--     ou si l'état réseau de l'autorité (getRealState) est un état debout ; sinon attente bornée (WATCH_MS).
-- Un corps renversé plus tard (coup, chute) n'est jamais touché : l'autorité ne remet debout qu'à la création, et un
-- client ne surveille une copie que pendant WATCH_MS après son apparition, et seulement tant qu'elle n'a pas été vue
-- debout.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local Stand = LivingKnox.Stand or {}
LivingKnox.Stand = Stand

Stand.WATCH_MS = 5000     -- client : délai pendant lequel une copie apparue couchée peut être remise debout
Stand.FADE_IN = true      -- machine qui affiche : alpha remis à 0 à la remise debout (fondu d'apparition)
Stand.IDLE = "idle"
-- États d'action (dossiers d'actiongroups, en minuscules) d'un corps couché par la réanimation.
Stand.LYING_ACTIONS = { onground = true, ["getup-fromonback"] = true, ["getup-fromonfront"] = true }
-- États réseau de l'autorité (NetworkVariables.ZombieState, J/network/NetworkVariables.java:8-71) qui prouvent
-- qu'elle est debout. getup-fromOnBack/Front n'y figurent pas : un relevé de l'autorité arrive en « idle ».
Stand.STANDING_REAL = { idle = true, walktoward = true, ["walktoward-network"] = true, pathfind = true,
    turnalerted = true, ["face-target"] = true }

Stand.snapshot = Stand.snapshot     -- ActionStateSnapshot de l'état « idle » sans sous-état (objet opaque)
Stand.watched = Stand.watched or {} -- client MP : { z, untilMs }
Stand.stats = Stand.stats or { stood = 0, refused = 0, watched = 0, dropped = 0 }

local function log() return LivingKnox.Log end

-- Relève une fois le patron de l'état « idle » sur un zombie qui VIENT de naître (OnZombieCreate, zombie temporaire
-- de la création). Rend vrai si un patron est disponible.
function Stand.rememberFresh(z)
    if Stand.snapshot ~= nil then return true end
    if z == nil or z:getActionStateName() ~= Stand.IDLE then return false end
    local snap = z:playbackRecordCurrentStateSnapshot()
    if snap ~= nil then Stand.snapshot = snap end
    return Stand.snapshot ~= nil
end

-- Vrai si le corps est couché au sens de la réanimation : au sol, ou dans un état d'action couché ou de relevé.
function Stand.isLying(z)
    if z:isOnFloor() then return true end
    return Stand.LYING_ACTIONS[z:getActionStateName()] == true
end

-- Remet le corps debout tout de suite. Rend vrai, ou faux et la raison.
function Stand.now(z)
    if z == nil or z:isDead() then return false, "no live body" end
    if Stand.snapshot == nil then
        Stand.stats.refused = Stand.stats.refused + 1
        return false, "no idle state snapshot yet"
    end
    z:setOnFloor(false)
    z:setFallOnFront(false)
    z:setKnockedDown(false)
    z:setCollidable(true)
    z:playbackSetCurrentStateSnapshot(Stand.snapshot)
    z:changeState(ZombieIdleState.instance())
    if Stand.FADE_IN and LivingKnox.hasLocalPlayer() then z:setAlpha(0) end
    Stand.stats.stood = Stand.stats.stood + 1
    return true
end

-- Client MP : décide pour une copie surveillée. Rend "stood", "standing" (rien à faire), "dead" ou nil (attendre).
local function decide(z)
    if z:isDead() then return "dead" end
    if not Stand.isLying(z) then return "standing" end
    if not z:isRemoteZombie() or Stand.STANDING_REAL[z:getRealState()] == true then
        local ok, why = Stand.now(z)
        if ok then return "stood" end
        log().debug("stand: copy left to the vanilla get-up (%s)", tostring(why))
        return "standing"
    end
    return nil
end

-- Client MP : copie d'un corps de PNJ qui vient d'apparaître ici (LK_ZombieGuard.adopt). Décision immédiate, sinon
-- surveillance bornée.
function Stand.watch(z)
    if not isClient() or z == nil then return end
    for _, w in ipairs(Stand.watched) do
        if w.z == z then return end
    end
    local result = decide(z)
    if result ~= nil then return end
    Stand.watched[#Stand.watched + 1] = { z = z, untilMs = getTimestampMs() + Stand.WATCH_MS }
    Stand.stats.watched = Stand.stats.watched + 1
end

-- Client MP, à chaque image tant qu'une copie est surveillée.
function Stand.clientPass()
    local list = Stand.watched
    if #list == 0 then return end
    local now = getTimestampMs()
    local keep = {}
    for _, w in ipairs(list) do
        local result = decide(w.z)
        if result == nil then
            if now <= w.untilMs then
                keep[#keep + 1] = w
            else
                Stand.stats.dropped = Stand.stats.dropped + 1
            end
        end
    end
    Stand.watched = keep
end

-- ================================================================ abonnements
if Events ~= nil then   -- Events absent : VM de test sans moteur (tests/test_kahlua.py)
    local function onZombieCreate(z)
        if LivingKnox.Stand.snapshot == nil then LivingKnox.Stand.rememberFresh(z) end
    end
    LivingKnox.subscribe("OnZombieCreate", "Stand.onZombieCreate", onZombieCreate)

    if isClient() then
        local function onTick()
            LivingKnox.Stand.clientPass()
        end
        LivingKnox.subscribe("OnTick", "Stand.clientPass", onTick)
    end
end

return Stand
