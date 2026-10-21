-- Living Knox : corps des PNJ côté autorité (serveur dédié ou hébergé, solo). Fiche : docs/annexes/conception/corps-registre.md.
-- Un client MP charge aussi ce fichier (media/lua/server) : chaque fonction y refuse d'agir.
--
-- Corps = « joueur réanimé » (décision LK02 du 2026-10-09, base B) : addZombiesInOutfit (zombie habillé), étiquette
-- et apparence posées, DoZombieInventory (vêtements devenus objets portés), square:createCorpse(zombie) (le cadavre
-- copie visuel, objets et ModData), body:reanimate() (zombie isReanimatedPlayer, ModData copiées, descripteur
-- partagé figé à cet instant). Java 42.21.0 : LuaManager.java:8355-8445, IsoZombie.java:3129,
-- IsoGridSquare.java:10109-10124, IsoDeadBody.java:378 et 1832-1946.
-- Un joueur réanimé n'est jamais virtualisé : au déchargement de son chunk le même objet est mis de côté, puis remis
-- dans la liste des zombies au rechargement (ReanimatedPlayers.java:39-114, aucun OnZombieCreate) ; il est sauvegardé
-- en entier dans reanimated.bin et relu au démarrage (ReanimatedPlayers.java:116-196).
--
-- Liaison corps <-> PNJ : Bodies.bound[id] garde l'objet du corps courant. Un balayage borné de la liste des zombies
-- (Bodies.SCAN_BUDGET zombies toutes les Bodies.SCAN_EVERY images) relit l'étiquette des joueurs réanimés :
-- corps courant non lié -> lié (retour de chunk, redémarrage) ; second corps courant -> doublon retiré ; génération
-- périmée ou inconnue, identifiant inconnu, PNJ virtuel ou mort -> orphelin retiré (setHealth(0) puis retrait : un
-- joueur réanimé vivant serait sinon remis de côté, VirtualZombieManager.java:677-684). Un joueur réanimé sans
-- étiquette (vrai joueur mort) n'est jamais touché. Zombie refait du cadavre d'un PNJ mort (LK07-T04) : cadavre
-- traîné jamais touché, cadavre relevé remis à terre (section « cadavre d'un PNJ mort »).
-- Retrait loin des joueurs (LK03-T04, Bodies.releasePass) : un PNJ incarné sans joueur proche pendant un délai est
-- rendu à la simulation abstraite avec son état (Bodies.release) ; voir la section « retrait loin des joueurs ».
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Appearance"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Stand"
require "LivingKnox/LK_Death"

local Bodies = LivingKnox.Bodies or {}
LivingKnox.Bodies = Bodies

Bodies.SCAN_EVERY = 15      -- images entre deux tranches de balayage
Bodies.SCAN_BUDGET = 64     -- zombies examinés par tranche (coût borné, indépendant de la population)
Bodies.MAX_EMBODIED = 50    -- corps de PNJ simultanés au plus (le jalon 1 n'en vise qu'un ou deux)
Bodies.MOVE_EPSILON = 1     -- déplacement (cases) au-delà duquel la dernière position vue est rafraîchie

Bodies.bound = Bodies.bound or {}
-- C30 : résultat du test de présence de Bodies.find, par PNJ, valable une image (même getWorld():getFrameNo() et
-- même getTimestampMs()) : { z, frame, ms }. getZombieList():contains parcourt toute la liste des zombies de la
-- cellule et find est appelé plusieurs fois par image pour un même PNJ. Le numéro d'image avance à chaque mise à jour
-- du monde (IsoWorld.updateInternal, J/iso/IsoWorld.java:2771), où les corps sont mis de côté ou retirés ; l'heure
-- couvre le serveur en pause (aucune mise à jour du monde) et les paquets traités en tête d'image. Vidé par
-- removeBody (despawn compris) ; un autre corps relié au PNJ (rawequal) ou un corps mort refait le test.
Bodies.foundCache = {}
Bodies.scanState = Bodies.scanState or { cursor = 0, ticks = 0, sweeps = 0 }

local function Identity() return LivingKnox.Identity end
local function Store() return LivingKnox.Store end
local function log() return LivingKnox.Log end

-- Vrai si cette machine peut toucher aux corps ; sinon faux et la raison.
function Bodies.canAct(creating)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    if creating and not LivingKnox.Config.isEnabled() then return false, "Living Knox is disabled (sandbox)" end
    -- Registre relu par OnInitGlobalModData ; rattrapage ici après une remise à zéro du Lua (événement passé).
    if not Store().isReady() and not Store().isBlocked() then Store().ensure() end
    if not Store().isReady() then
        local _, why = Store().isBlocked()
        return false, "registry unavailable" .. (why and (": " .. why) or "")
    end
    if getCell() == nil then return false, "world not ready" end
    return true
end

-- Corps présent dans le monde : vivant et dans la liste des zombies de la cellule (un corps mis de côté au
-- déchargement de son chunk n'y est plus).
function Bodies.inWorld(z)
    if z == nil or z:isDead() then return false end
    return getCell():getZombieList():contains(z)
end

local function positionOf(z)
    return Identity().position(math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()))
end

local function embodiedCount()
    local n = 0
    for _, npc in pairs(Store().data().npcs) do
        if npc.state == Identity().STATE_EMBODIED then n = n + 1 end
    end
    return n
end

-- Apparence posée avant DoZombieInventory et le cadavre (le descripteur partagé est figé à la réanimation) :
-- LivingKnox.Appearance.apply (LK02-T03 : peau humaine, coupe, barbe, couleurs, corps et vêtements sans sang,
-- saleté, plaie, trou ni pièce, aucun objet accroché ; LK02-T12 : vêtements concrets clothes rejoués s'ils sont
-- connus, sinon tenue rejouée avec sa variante). Rend le mode d'habillage et le nombre d'entrées sautées.
function Bodies.prepare(z, profile, clothes)
    return LivingKnox.Appearance.apply(z, profile, clothes)
end

Bodies.clothesFailed = Bodies.clothesFailed or {}

-- Relève les vêtements concrets d'un PNJ sur son corps s'ils ne le sont pas encore (LK02-T12) : premier corps, ou
-- corps créé avant LK02-T12, qui garde ainsi son apparence actuelle aux incarnations suivantes. Une erreur du
-- moteur est journalisée une fois par PNJ et n'interrompt ni la création ni le balayage. Rend vrai si relevé.
function Bodies.recordClothes(npc, z)
    if npc.clothes ~= nil then return false end
    local ok, clothes = pcall(LivingKnox.Appearance.describe, z)
    if not ok then
        if not Bodies.clothesFailed[npc.id] then
            Bodies.clothesFailed[npc.id] = true
            log().error("npc %s clothes not recorded: %s", npc.id, tostring(clothes))
        end
        return false
    end
    if clothes == nil then return false end
    npc.clothes = clothes
    log().info("npc %s clothes recorded (%s item(s))", npc.id, tostring(#clothes))
    return true
end

-- Hors des trajets, le corps reste « useless » (sinon il erre ; mesure LK02-T10). Réappliqué à chaque liaison.
function Bodies.applyRest(z)
    if not z:isUseless() then z:setUseless(true) end
end

-- Retire un zombie du monde sans retour possible. Rend vrai si retiré.
function Bodies.removeBody(z, why)
    if z == nil then return false end
    local where = "?"
    local gone = nil
    local ok, err = pcall(function()
        where = math.floor(z:getX()) .. "," .. math.floor(z:getY()) .. "," .. math.floor(z:getZ())
        gone = { o = z:getOnlineID(), x = z:getX(), y = z:getY(), z = z:getZ() }
        -- Invulnérable (LK07-T02) : setHealth(0) serait ignoré (J/characters/IsoGameCharacter.java:2903-2908).
        local H = LivingKnox.Health
        if H ~= nil and H.makeMortal ~= nil then H.makeMortal(z) end
        if z:isReanimatedPlayer() then z:setHealth(0) end
        z:removeFromWorld()
        z:removeFromSquare()
    end)
    for id, b in pairs(Bodies.bound) do
        if b == z then Bodies.bound[id] = nil end
    end
    Bodies.foundCache = {} -- C30
    if not ok then
        log().error("body at %s not removed (%s): %s", where, tostring(why), tostring(err))
        return false
    end
    log().info("body removed at %s (%s)", where, tostring(why))
    -- Serveur dédié : copie du client qui simulait ce corps retirée aussi (LivingKnox.Zombies.tellBodyGone).
    local Zm = LivingKnox.Zombies
    if Zm ~= nil and Zm.tellBodyGone ~= nil then Zm.tellBodyGone(gone) end
    return true
end

-- Remise debout dès la réanimation (LK02-T14, LK_Stand.lua) : sans elle, le corps reste couché 1 à 3 s puis joue le
-- relevé vanilla. Effet visuel seulement : une erreur du moteur est journalisée une fois et n'annule pas la création
-- (le corps se relève alors comme un joueur réanimé ordinaire).
Bodies.standFailed = Bodies.standFailed or false

function Bodies.standUp(z, id)
    local ok, stood, why = pcall(LivingKnox.Stand.now, z)
    if ok and stood then return true end
    if not ok then why = "engine error: " .. tostring(stood) end
    if not Bodies.standFailed then
        Bodies.standFailed = true
        log().warn("npc %s body not stood up at once, vanilla get-up instead (%s)", tostring(id), tostring(why))
    end
    return false
end

-- Crée un corps étiqueté (id, generation) sur la case sq, SANS toucher au registre (Bodies.embody le fait ; les
-- suites de test s'en servent pour fabriquer doublons et orphelins). clothes : vêtements concrets à rejouer
-- (facultatif, LK02-T12). Rend le zombie, ou nil et une raison.
-- MP (LK03-T06) : tout se fait dans ce seul appel Lua, sans attente. Le zombie temporaire reçoit un onlineId et
-- entre dans la liste des zombies (J/VirtualZombieManager.java:207-223), mais le cadavre l'en retire aussitôt
-- (IsoDeadBody.java:378-380 -> IsoZombie.removeFromWorld, J/characters/IsoZombie.java:3573-3585 : onlineId rendu,
-- aucun propriétaire). Les zombies ne partent aux clients que dans NetworkZombiePacker.postupdate, après le Lua de
-- l'image (J/network/ServerMap.java:548, J/network/GameServer.java:1010-1073), et seulement s'ils sont dans la liste
-- (attribution J/popman/NetworkZombieManager.java:60-131, envoi J/popman/NetworkZombiePacker.java:115-183) : aucun
-- client ne reçoit donc le zombie temporaire, ni le cadavre (aucun envoi dans IsoDeadBody). Ne jamais différer une
-- étape (événement, tick suivant) entre addZombiesInOutfit et reanimate.
function Bodies.createBody(sq, profile, id, generation, clothes)
    local tmp, body
    local ok, result, why = pcall(function()
        local list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, profile.outfit, profile.female and 100 or 0)
        if list == nil or list:size() == 0 then return nil, "addZombiesInOutfit created no zombie" end
        tmp = list:get(0)
        LivingKnox.Stand.rememberFresh(tmp) -- patron de l'état d'action « idle » (zombie qui vient de naître)
        Identity().writeTag(tmp:getModData(), id, generation)
        local _, skipped, placed = Bodies.prepare(tmp, profile, clothes)
        if skipped > 0 then
            log().warn("npc %s: %s recorded clothing item(s) no longer exist and were left out", tostring(id),
                tostring(skipped))
        end
        tmp:DoZombieInventory()
        -- Objets portés créés un par un par emplacement (WornItems.setFromItemVisuals) : un emplacement devenu
        -- exclusif d'un autre (mod qui change les emplacements) garde le dernier vêtement posé.
        local worn = (placed or 0) > 0 and tmp:getWornItems():size() or nil
        if worn ~= nil and worn < placed then
            log().warn("npc %s: %s recorded clothing item(s) could not be worn with the others (body locations "
                .. "changed by a mod) and were left out", tostring(id), tostring(placed - worn))
        end
        body = sq:createCorpse(tmp)
        if body == nil then return nil, "createCorpse returned nil" end
        Identity().clearTag(tmp:getModData()) -- le cadavre a sa propre copie (IsoDeadBody.java:378)
        tmp = nil
        local z = body:reanimate()
        if z == nil then return nil, "reanimate returned nil" end
        body = nil
        Bodies.applyRest(z)
        Bodies.standUp(z, id)
        return z
    end)
    if not ok then why = "engine error: " .. tostring(result) end
    if ok and result ~= nil then return result end
    -- Débris d'une création ratée : zombie temporaire encore dans le monde, cadavre étiqueté non réanimé.
    if tmp ~= nil then pcall(function() tmp:removeFromWorld(); tmp:removeFromSquare() end) end
    if body ~= nil then pcall(function() body:getSquare():removeCorpse(body, false) end) end
    return nil, why
end

local function loadedSquare(x, y, z)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil, "position must be three numbers"
    end
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if sq == nil then
        return nil, "square " .. math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) .. " is not loaded"
    end
    return sq
end

-- Case libre pour un nouveau corps (LK02-T11). Sans la remise debout de LK02-T14 (patron absent, erreur du moteur),
-- et pour la copie d'un client MP en attente de l'état de l'autorité (LK_Stand.lua), le corps naît couché et se
-- relève quand son reanimateTimer (30-90, soit 1-3 s) tombe à 0 ; si isBeingSteppedOn() est vrai à ce moment, le
-- compte à rebours repart, sans fin tant qu'un personnage reste là (ZombieOnGroundState.java:107-111).
-- isBeingSteppedOn (IsoGameCharacter.java:10240-10258) : personnage (instanceof IsoGameCharacter), hors véhicule,
-- pas au sol (isOnFloor), sur la case du corps ou l'une des 8 voisines, puis contact des os
-- (isCharacterStandingOnOther). Règle retenue, plus stricte que le contact : case chargée et praticable
-- (IsoGridSquare.isFree(false) : sol solide, ni mur, ni meuble plein, ni arbre, IsoGridSquare.java:2894-2915), et
-- aucun « personnage debout » sur elle ni sur ses 8 voisines (cases voisines non chargées ignorées, comme le Java).
-- Personnage debout = hors véhicule et pas au sol, ou corps Living Knox étiqueté même couché (il se relève dans les
-- secondes qui suivent : deux PNJ créés coup sur coup ne se gênent pas).
-- Recherche en anneaux carrés autour de la case voulue (rayon 0, 1... FREE_RADIUS), la plus proche d'abord.
Bodies.FREE_RADIUS = 4

local function standing(o)
    if not instanceof(o, "IsoGameCharacter") or o:isDead() then return false end
    if o:getVehicle() ~= nil then return false end
    if not o:isOnFloor() then return true end
    return instanceof(o, "IsoZombie") and o:hasModData() and Identity().readTag(o:getModData()) ~= nil
end

-- Vrai si aucun personnage debout n'occupe la case (x, y, z) ni ses 8 voisines.
function Bodies.clearAround(x, y, z)
    local cell = getCell()
    for dy = -1, 1 do
        for dx = -1, 1 do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            if sq ~= nil then
                local objects = sq:getMovingObjects()
                for i = 0, objects:size() - 1 do
                    if standing(objects:get(i)) then return false end
                end
            end
        end
    end
    return true
end

local ringCache = {}
-- Décalages (dx, dy) de l'anneau r (max(|dx|, |dy|) = r), triés par distance puis dy puis dx (ordre stable).
local function ring(r)
    if ringCache[r] then return ringCache[r] end
    local out = {}
    for dy = -r, r do
        for dx = -r, r do
            if math.max(math.abs(dx), math.abs(dy)) == r then out[#out + 1] = { dx, dy } end
        end
    end
    table.sort(out, function(a, b)
        local da, db = a[1] * a[1] + a[2] * a[2], b[1] * b[1] + b[2] * b[2]
        if da ~= db then return da < db end
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[1] < b[1]
    end)
    ringCache[r] = out
    return out
end
Bodies.ring = ring

-- ---------------------------------------------------------------- plantes cultivées et feux de camp (LK04-T06)
-- Fiche : docs/annexes/conception/neutralisation.md, « Plantes cultivées et feux de camp ». Le moteur fait, à chaque mise à
-- jour d'un zombie (J/characters/IsoZombie.java:2837-2847, toute machine qui met le zombie à jour) : plante cultivée
-- sur SA case détruite avec une chance de 1 / (100 / TrueMultiplier), en marche ou non ; feu de camp allumé sur sa
-- case éteint (SCampfireGlobalObject:putOut) avec une chance de 1 / (10000 / TrueMultiplier), en marche seulement.
-- Aucun réglage ne l'empêche, et la recherche de chemin d'un zombie ne contourne pas les plantes
-- (PathFindRequest.avoidFarmingPlants n'est vrai que pour un IsoPlayer, J/pathfind/nativeCode/PathFindRequest.java:
-- 61-81). Règle : un corps ne s'arrête ni ne naît sur une case portant une plante ou un feu de camp, ni sur l'une de
-- ses 8 voisines (marge pour la tolérance d'arrivée et la séparation des personnages).
-- Lecture (autorité seulement) : IsoGridSquare.hasFarmingPlant (système "farming", plante détruite comprise) et
-- IsoGridSquare.getCampfire (système "campfire", allumé ou non : un feu éteint peut être rallumé), tous deux par les
-- systèmes de GlobalObject du serveur (J/iso/IsoGridSquare.java:9713-9765 ; sur un client MP, getCampfire rend nil).
Bodies.HAZARD_AVOID = 1     -- cases autour d'une plante ou d'un feu de camp où un corps ne s'arrête pas

-- Danger porté par la case : "farming plant", "campfire" ou nil.
function Bodies.hazardOn(sq)
    if sq == nil then return nil end
    if sq:hasFarmingPlant() then return "farming plant" end
    if sq:getCampfire() ~= nil then return "campfire" end
    return nil
end

-- Danger le plus proche à r cases au plus (distance de Tchebychev) de (x, y, z), case comprise. Rend le danger et ses
-- coordonnées, ou nil. Cases non chargées ignorées.
function Bodies.hazardNear(x, y, z, r)
    local cell = getCell()
    for d = 0, r do
        for _, o in ipairs(ring(d)) do
            local sq = cell:getGridSquare(x + o[1], y + o[2], z)
            local what = Bodies.hazardOn(sq)
            if what ~= nil then return what, x + o[1], y + o[2] end
        end
    end
    return nil
end

-- Case praticable la plus proche de (x, y, z), à radius cases au plus, sans danger à clearance cases ou moins. Rend
-- la case, ou nil.
function Bodies.safeSquare(x, y, z, radius, clearance)
    local cell = getCell()
    for r = 0, radius do
        for _, d in ipairs(ring(r)) do
            local sq = cell:getGridSquare(x + d[1], y + d[2], z)
            if sq ~= nil and sq:isFree(false) and Bodies.hazardNear(x + d[1], y + d[2], z, clearance) == nil then
                return sq
            end
        end
    end
    return nil
end

-- Case retenue pour un corps voulu en (x, y, z) : la plus proche, à FREE_RADIUS cases au plus, qui satisfait la
-- règle ci-dessus, sans plante cultivée ni feu de camp sur elle ni sur ses voisines (HAZARD_AVOID). Rend la case, ou
-- nil et une raison.
-- Vrai si la case sq (chargée) satisfait la règle ci-dessus (praticable, aucun personnage debout ni danger sur elle
-- ou ses voisines).
function Bodies.freeSquare(sq)
    if sq == nil or not sq:isFree(false) then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    return Bodies.clearAround(x, y, z) and Bodies.hazardNear(x, y, z, Bodies.HAZARD_AVOID) == nil
end

function Bodies.findFreeSquare(x, y, z)
    local want, unloaded = loadedSquare(x, y, z)
    if not want then return nil, unloaded end
    local cx, cy, cz = want:getX(), want:getY(), want:getZ()
    local cell = getCell()
    for r = 0, Bodies.FREE_RADIUS do
        for _, d in ipairs(ring(r)) do
            local sq = cell:getGridSquare(cx + d[1], cy + d[2], cz)
            if Bodies.freeSquare(sq) then return sq end
        end
    end
    return nil, "no free square within " .. Bodies.FREE_RADIUS .. " of " .. cx .. "," .. cy .. "," .. cz
        .. " (loaded, walkable, no standing character, farming plant or campfire on it or next to it)"
end

-- Corps relié à l'instant : garde posée et liste des corps publiée aux clients dans la même image (LK03-T06,
-- LivingKnox.ZombieGuard.bodyBound). Sans garde chargée (suites isolées), rien.
function Bodies.guardNow(npcId, z)
    -- Santé de référence (LK07-T02) : corps rendu invulnérable et référence initialisée dans la même image.
    local H = LivingKnox.Health
    if H ~= nil and H.bodyBound ~= nil then
        local ok, err = pcall(H.bodyBound, npcId, z)
        if not ok then log().error("npc %s: reference health not set at bind: %s", tostring(npcId), tostring(err)) end
    end
    -- Clé du foyer (LK04-T12, LivingKnox.Obstacles.giveKey) : posée dans l'inventaire du corps à sa liaison
    -- (incarnation, retour de chunk, redémarrage), une fois par corps et par foyer.
    local O = LivingKnox.Obstacles
    if O ~= nil and O.giveKey ~= nil then
        local okK, errK = pcall(O.giveKey, npcId, z)
        if not okK then log().error("npc %s: home key not given at bind: %s", tostring(npcId), tostring(errK)) end
    end
    local G = LivingKnox.ZombieGuard
    if G == nil or G.bodyBound == nil then return false end
    return G.bodyBound(npcId, z)
end

local function embodyOn(npc, sq, want)
    if embodiedCount() >= Bodies.MAX_EMBODIED then
        return nil, "too many embodied npcs (" .. Bodies.MAX_EMBODIED .. ")"
    end
    local generation = Identity().nextGeneration(npc)
    local z, why = Bodies.createBody(sq, npc.profile, npc.id, generation, npc.clothes)
    if z == nil then return nil, why end
    Identity().markEmbodied(npc, generation)
    npc.want = want             -- position demandée ; la case retenue est npc.last
    npc.last = positionOf(z)
    -- Santé de naissance (réécrite par reanimate() selon la robustesse, J/iso/objects/IsoDeadBody.java:1876-1889) :
    -- référence de la conversion santé <-> blessure abstraite (LK09-T03, LK_Materialize).
    local full = z:getHealth()
    if Identity().validHealth(full) and full > 0 then npc.hpMax = full end
    Bodies.bound[npc.id] = z
    Bodies.guardNow(npc.id, z)
    Bodies.recordClothes(npc, z)
    -- LK13-T10 : écriture à la fin de l'image (créations d'une même image écrites une fois). Le corps neuf n'est
    -- sauvegardé par le moteur qu'avec la sauvegarde du monde (reanimated.bin), qui passe en tête d'image sur un
    -- serveur et après OnSave en solo : le registre est toujours écrit avant (fiche corps-registre.md).
    Store().markChanged()
    log().info("npc %s embodied (generation %s) at %s,%s,%s (wanted %s,%s,%s)", npc.id, tostring(generation),
        tostring(sq:getX()), tostring(sq:getY()), tostring(sq:getZ()), tostring(want.x), tostring(want.y),
        tostring(want.z))
    return z
end

-- Nouveau PNJ et son premier corps sur une case chargée et libre, la plus proche de (x, y, z) (Bodies.findFreeSquare).
-- profile : entrée de LivingKnox.Appearance.normalize ({ look = "<nom>" }, { female = true }, {}...), résolue une
-- fois pour toutes et gardée dans le registre. Rend l'identifiant et le zombie, ou nil et une raison.
-- Case non chargée ou aucune case libre : refus (rien n'est créé ; l'attente d'une case relève de la vie hors écran,
-- LK09). Registre : want = position demandée, last = case retenue.
function Bodies.spawn(profile, x, y, z)
    local ok, why = Bodies.canAct(true)
    if not ok then return nil, why end
    local p, bad = Identity().normalizeProfile(profile) -- refus immédiat d'une entrée fausse
    if not p then return nil, bad end
    local sq, refused = Bodies.findFreeSquare(x, y, z)
    if not sq then return nil, refused end
    local registry = Store().data()
    -- Entrée brute : Identity.create résout l'apparence avec le numéro du PNJ pour graine.
    local npc, err = Identity().create(registry, profile, math.floor(x), math.floor(y), math.floor(z))
    if not npc then return nil, err end
    local body, failed = embodyOn(npc, sq, npc.want)
    if not body then
        Identity().forget(registry, npc.id) -- numéro consommé, jamais réattribué
        Store().markChanged()
        return nil, failed
    end
    return npc.id, body
end

-- Nouveau corps (génération suivante) pour un PNJ virtuel, sur la case libre la plus proche de (x, y, z) (même
-- règle que spawn). Rend le zombie, ou nil et une raison.
function Bodies.embody(npcId, x, y, z)
    local ok, why = Bodies.canAct(true)
    if not ok then return nil, why end
    local npc = Identity().get(Store().data(), npcId)
    if not npc then return nil, "unknown npc " .. tostring(npcId) end
    if npc.state ~= Identity().STATE_VIRTUAL then return nil, "npc " .. npcId .. " is " .. npc.state end
    local sq, refused = Bodies.findFreeSquare(x, y, z)
    if not sq then return nil, refused end
    return embodyOn(npc, sq, Identity().position(math.floor(x), math.floor(y), math.floor(z)))
end

-- Corps courant d'un PNJ s'il est dans le monde. Rend le zombie et "bound", ou nil et l'état
-- ("virtual", "dead", "embodied" = corps attendu mais hors zone chargée ou pas encore relié, "unknown").
-- Numéro d'image du monde, ou nil sans monde (bancs de test sans getFrameNo : aucun cache).
local function frameNo()
    local w = getWorld ~= nil and getWorld() or nil
    if w == nil or w.getFrameNo == nil then return nil end
    return w:getFrameNo()
end

-- Bodies.inWorld(z) pour le corps relié à npcId, mis en cache pour l'image (C30).
local function boundInWorld(npcId, z)
    if z:isDead() then return false end
    local frame = frameNo()
    if frame == nil then return Bodies.inWorld(z) end
    local ms = getTimestampMs()
    local c = Bodies.foundCache[npcId]
    if c ~= nil and rawequal(c.z, z) and c.frame == frame and c.ms == ms then return c.ok end
    local ok = Bodies.inWorld(z)
    if c == nil then
        Bodies.foundCache[npcId] = { z = z, frame = frame, ms = ms, ok = ok }
    else
        c.z, c.frame, c.ms, c.ok = z, frame, ms, ok
    end
    return ok
end

function Bodies.find(npcId)
    local registry = Store().data()
    local npc = registry and Identity().get(registry, npcId)
    if not npc then return nil, "unknown" end
    local z = Bodies.bound[npcId]
    if z ~= nil and getCell() ~= nil and boundInWorld(npcId, z) then return z, "bound" end
    return nil, npc.state
end

-- Retire le corps d'un PNJ ; le PNJ redevient virtuel (forget = vrai : il quitte le registre). Un corps hors zone
-- chargée sera retiré comme orphelin à son retour. Rend vrai et le nombre de corps retirés, ou faux et une raison.
function Bodies.despawn(npcId, forget)
    local ok, why = Bodies.canAct(false)
    if not ok then return false, why end
    local registry = Store().data()
    local npc = Identity().get(registry, npcId)
    if not npc then return false, "unknown npc " .. tostring(npcId) end
    local removed = 0
    local z = Bodies.bound[npcId]
    if z ~= nil and Bodies.inWorld(z) then
        npc.last = positionOf(z)
        if Bodies.removeBody(z, "despawn " .. npcId) then removed = 1 end
    end
    Bodies.bound[npcId] = nil
    Bodies.lastHits[npcId] = nil
    if forget then
        Identity().forget(registry, npcId)
    elseif npc.state == Identity().STATE_EMBODIED then
        Identity().markVirtual(npc)
    end
    Store().markChanged()   -- LK13-T10 : fin de l'image (retraits d'une même image écrits une fois)
    log().info("npc %s despawned (%s body removed%s)", npcId, tostring(removed), forget and ", forgotten" or "")
    return true, removed
end

-- Résumé de chaque PNJ, trié par numéro : { id, generation, state, profile, want, last, weapon, clothes, inWorld }.
function Bodies.list()
    local registry = Store().data()
    local out = {}
    if not registry then return out end
    local cellReady = getCell() ~= nil
    for _, id in ipairs(Identity().sortedIds(registry)) do
        local npc = registry.npcs[id]
        local z = Bodies.bound[id]
        out[#out + 1] = { id = id, generation = npc.generation, state = npc.state, profile = npc.profile,
            want = npc.want, last = npc.last, weapon = npc.weapon, clothes = npc.clothes,
            inWorld = cellReady and z ~= nil and Bodies.inWorld(z) }
    end
    return out
end

-- ---------------------------------------------------------------- cadavre d'un PNJ mort (LK07-T04)
-- Fiche : docs/annexes/conception/sante.md, « Mort unique et cadavre (LK07-T04) ». Le cadavre copie les ModData du corps,
-- étiquette comprise (J/iso/objects/IsoDeadBody.java:378) : elle reste, pour retrouver le PNJ sur son cadavre
-- (LK07-T05). Deux chemins vanilla refont un zombie de ce cadavre (IsoDeadBody.reanimate copie les ModData,
-- J/iso/objects/IsoDeadBody.java:1832-1946) :
-- - cadavre traîné par un joueur (prise B42) : zombie temporaire isReanimatedForGrappleOnly, joueur réanimé, remis
--   en cadavre par le moteur au lâcher (J/iso/objects/IsoDeadBody.java:1817-1831, J/ai/states/
--   ZombieOnGroundState.java:80-91) : jamais touché (le retirer détruirait le cadavre et son contenu) ;
-- - cadavre devenu faux mort en pourrissant (option ZombieLore.DisableFakeDead = 2, 1 chance sur 100 par stade de
--   pourriture d'un cadavre de zombie, J/iso/objects/IsoDeadBody.java:1576-1581) qui se relève près d'un joueur
--   (updateFakeDead -> reanimateNow, 1636-1653) : zombie ordinaire étiqueté. Rien ne l'empêche depuis Lua (cadavre non
--   suivi) : le balayage le reconnaît (étiquette d'un PNJ mort) et le remet à terre (Bodies.layDown), cadavre et
--   inventaire gardés. Même règle pour un joueur réanimé étiqueté d'un PNJ mort (réanimation par un autre mod).
--   Serveur MP (LK07-T09) : la remise à terre attend RISEN_DELAY_MS depuis le premier passage du balayage sur ce
--   zombie. Un client ne retire son ancien cadavre qu'en recevant le zombie relevé (copie créée au sol,
--   ZombieOnGroundState.enter -> IsoDeadBody.removeDeadBody(reanimatedBodyId), J/ai/states/ZombieOnGroundState.java:
--   64-65, 116-117 ; reanimate() ne l'envoie pas lui-même, J/iso/objects/IsoDeadBody.java:1914-1918), et ne crée le
--   nouveau cadavre qu'avec cette copie (DeadZombiePacket ignoré sans elle, DeadCharacterPacket.isConsistent) : un
--   zombie remis à terre avant sa première copie laisse chez les clients l'ancien cadavre, sans le nouveau.
Bodies.stats = Bodies.stats or { laidDown = 0 }
Bodies.RISEN_DELAY_MS = 2000    -- copie d'un zombie neuf reçue en 0,2 à 0,3 s par les clients proches (mesuré)
Bodies.risenSeen = Bodies.risenSeen or {}

-- Vrai si le zombie relevé z peut être remis à terre maintenant (toujours hors serveur MP).
local function risenReady(z)
    if not isServer() then return true end
    local now = getTimestampMs()
    local first = Bodies.risenSeen[z]
    if first == nil then
        Bodies.risenSeen[z] = now
        return false
    end
    return now - first >= Bodies.RISEN_DELAY_MS
end

-- Remet à terre le zombie z, issu du cadavre du PNJ mort id : mort vanilla de l'autorité, sans attaquant, faux mort
-- levé ; le nouveau cadavre garde les ModData et l'inventaire. Rend vrai si fait.
function Bodies.layDown(z, id, why)
    local ok, err = pcall(function()
        local H = LivingKnox.Health
        if H ~= nil and H.makeMortal ~= nil then H.makeMortal(z) end
        if z:isFakeDead() then z:setFakeDead(false) end
        z:setAttackedBy(nil)
        z:die()
    end)
    if not ok then
        log().error("npc %s: risen corpse not laid down (%s): %s", tostring(id), tostring(why), tostring(err))
        return false
    end
    Bodies.risenSeen[z] = nil
    Bodies.stats.laidDown = Bodies.stats.laidDown + 1
    Bodies.trackCorpse(id, z, "laid down")
    log().warn("npc %s is dead but its corpse rose again (%s): laid down at %s,%s,%s", tostring(id), tostring(why),
        tostring(math.floor(z:getX())), tostring(math.floor(z:getY())), tostring(math.floor(z:getZ())))
    return true
end

-- LK07-T10 : cadavre suivi par LK_Death (serveur MP : renvoyé à un client qui ne l'a pas reçu). Sans effet ailleurs.
function Bodies.trackCorpse(id, z, why)
    local D = LivingKnox.Death
    if D == nil or D.track == nil then return end
    local ok, err = pcall(D.track, id, z, why)
    if not ok then log().error("npc %s: corpse not tracked: %s", tostring(id), tostring(err)) end
end

-- Vrai si z est le zombie temporaire d'un cadavre traîné (prise B42).
function Bodies.isDragged(z)
    return z:isReanimatedForGrappleOnly()
end

-- Zombie ordinaire (pas un joueur réanimé) étiqueté d'un PNJ mort : cadavre faux mort relevé, remis à terre.
local function examineRisen(z)
    if not z:hasModData() then return nil end
    local I = Identity()
    local id, generation = I.readTag(z:getModData())
    if not id then return nil end
    local _, npc = I.classify(Store().data(), id, generation)
    if npc == nil or npc.state ~= I.STATE_DEAD or Bodies.isDragged(z) then return nil end
    if not risenReady(z) then return "rising" end
    Bodies.layDown(z, id, "fake dead corpse")
    return "laid down"
end

-- Examine un zombie de la liste (voir l'en-tête). Rend l'action : nil (ignoré), "seen", "bound", "duplicate",
-- "orphan", "laid down" (LK07-T04 : zombie refait du cadavre d'un PNJ mort), "rising" (le même, remis à terre à un
-- balayage suivant : serveur MP, RISEN_DELAY_MS).
function Bodies.examine(z)
    if z == nil or z:isDead() then return nil end
    if not z:isReanimatedPlayer() then return examineRisen(z) end
    if not z:hasModData() then return nil end
    local I = Identity()
    local id, generation = I.readTag(z:getModData())
    if not id then return nil end
    local class, npc = I.classify(Store().data(), id, generation)
    if class ~= I.CURRENT and Bodies.isDragged(z) then return nil end   -- cadavre traîné : rendu par le moteur
    if class ~= I.CURRENT and npc ~= nil and npc.state == I.STATE_DEAD then
        if not risenReady(z) then return "rising" end
        Bodies.layDown(z, id, "reanimated corpse")
        return "laid down"
    end
    if class ~= I.CURRENT then
        Bodies.removeBody(z, "orphan " .. id .. " generation " .. tostring(generation) .. ": " .. class)
        return "orphan"
    end
    local b = Bodies.bound[id]
    if b == z then
        local p = positionOf(z)
        local last = npc.last
        if not last or math.abs(last.x - p.x) >= Bodies.MOVE_EPSILON or math.abs(last.y - p.y) >= Bodies.MOVE_EPSILON
            or last.z ~= p.z then
            npc.last = p
            Store().markDirty()
        end
        if Bodies.recordClothes(npc, z) then Store().markDirty() end
        return "seen"
    end
    if b ~= nil and Bodies.inWorld(b) then
        Bodies.removeBody(z, "duplicate of " .. id .. " generation " .. tostring(generation))
        return "duplicate"
    end
    Bodies.bound[id] = z
    Bodies.applyRest(z)
    Bodies.guardNow(id, z)
    npc.last = positionOf(z)
    Bodies.recordClothes(npc, z)
    Store().markDirty()
    log().info("npc %s bound to its body (generation %s)", id, tostring(generation))
    return "bound"
end

-- Examine au plus budget zombies de la liste, à partir du curseur (repris à zéro en fin de liste). Une liste qui
-- change entre deux tranches peut faire sauter un zombie : il est vu au tour suivant. Rend le nombre examiné.
function Bodies.scan(budget)
    local list = getCell():getZombieList()
    local st = Bodies.scanState
    local examined = 0
    local size = list:size()
    while examined < budget and examined < size do -- au plus un tour de la liste par appel
        local n = list:size()
        if n == 0 then
            st.cursor = 0
            break
        end
        if st.cursor >= n then
            st.cursor = 0
            st.sweeps = st.sweeps + 1
        end
        local z = list:get(st.cursor)
        st.cursor = st.cursor + 1
        examined = examined + 1
        Bodies.examine(z)
        -- Un retrait raccourcit la liste : reculer d'un cran pour ne pas sauter le zombie suivant.
        if list:size() < n and st.cursor > 0 then st.cursor = st.cursor - 1 end
    end
    return examined
end

-- Balayage complet immédiat (tests, console de dev) : coût proportionnel à la population, jamais appelé par tick.
function Bodies.scanAll()
    if not Bodies.canAct(false) then return 0 end
    Bodies.scanState.cursor = 0
    return Bodies.scan(getCell():getZombieList():size())
end

-- Corps à l'arrêt sur ou à côté d'une plante cultivée ou d'un feu de camp (LK04-T06) : consigne "move" courte (geste
-- walk) vers la case praticable la plus proche, à HAZARD_RADIUS cases au plus, sans danger à HAZARD_AVOID + 1 cases
-- (marge d'une case de plus que la règle : un corps arrêté à la tolérance d'arrivée, Directives.ARRIVE = 1 case du
-- centre visé, reste ainsi hors de la zone et le déplacement ne se répète pas). « À l'arrêt » = aucune consigne en
-- cours (aucune, ou close). Au plus une tentative par PNJ toutes les HAZARD_RETRY_MS. Rend le nombre de consignes
-- émises.
Bodies.HAZARD_EVERY = 4          -- tranches de balayage (SCAN_EVERY images) entre deux passages, soit 1 s
Bodies.HAZARD_RADIUS = 4
Bodies.HAZARD_RETRY_MS = 10000
Bodies.hazardMoves = Bodies.hazardMoves or {}   -- npcId -> { ms, x, y } dernière tentative

function Bodies.hazardPass()
    local D = LivingKnox.Directives
    if D == nil or D.moveTo == nil then return 0 end
    local issued = 0
    local t = getTimestampMs()
    for id, z in pairs(Bodies.bound) do
        local e = D.entries and D.entries[id]
        if (e == nil or e.done) and Bodies.inWorld(z) then
            local x, y, zz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local what, hx, hy = Bodies.hazardNear(x, y, zz, Bodies.HAZARD_AVOID)
            local last = Bodies.hazardMoves[id]
            if what ~= nil and (last == nil or t - last.ms >= Bodies.HAZARD_RETRY_MS) then
                local sq = Bodies.safeSquare(x, y, zz, Bodies.HAZARD_RADIUS, Bodies.HAZARD_AVOID + 1)
                Bodies.hazardMoves[id] = { ms = t, x = x, y = y }
                if sq == nil then
                    if last == nil or last.x ~= x or last.y ~= y then
                        log().warn("npc %s stopped next to a %s at %s,%s,%s and no safe square within %s",
                            id, what, tostring(hx), tostring(hy), tostring(zz), tostring(Bodies.HAZARD_RADIUS))
                    end
                else
                    local v, why = D.moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
                    if v ~= nil then
                        issued = issued + 1
                        log().info("npc %s stopped next to a %s at %s,%s,%s: moved away to %s,%s (#%s)", id, what,
                            tostring(hx), tostring(hy), tostring(zz), tostring(sq:getX()), tostring(sq:getY()),
                            tostring(v))
                    else
                        log().warn("npc %s next to a %s: move away refused: %s", id, what, tostring(why))
                    end
                end
            end
        end
    end
    return issued
end

-- ---------------------------------------------------------------- retrait loin des joueurs (LK03-T04)
-- Fiche : docs/annexes/conception/corps-registre.md, « Retrait loin des joueurs ». Réglages : LivingKnox.Config.BODIES.
-- Un PNJ incarné dont aucun joueur vivant n'est à RELEASE_RADIUS cases ou moins (écart en x et en y, niveaux ignorés)
-- pendant RELEASE_DELAY_MS d'affilée est rendu à la simulation abstraite (Bodies.release) : corps retiré s'il est
-- dans le monde, PNJ virtuel, état gardé au registre. Position mesurée : corps dans le monde, sinon dernière position
-- vue (npc.last, ou demandée npc.want) ; un corps mis de côté hors zone chargée (solo : 48 à 79 cases du joueur,
-- base world-placement.md) est donc rendu lui aussi quand le joueur s'éloigne. Serveur MP : un corps qu'un client
-- simule n'est jamais rendu (un client propriétaire est à 80 cases au plus, J/popman/NetworkZombieManager.java:
-- 121-127). Liste des joueurs vide (serveur sans joueur, reconnexion) : aucun joueur proche, le délai protège la
-- reconnexion ; serveur en pause (PauseEmpty) : OnTick ne tourne pas, et un écart de plus de RELEASE_GAP_MS entre
-- deux passages remet les délais à zéro.
Bodies.RELEASE_EVERY = 4         -- tranches de balayage (SCAN_EVERY images) entre deux passages, soit 1 s
Bodies.farSince = Bodies.farSince or {}   -- npcId -> heure réelle (ms) depuis laquelle aucun joueur n'est proche

local function releaseCfg() return LivingKnox.Config.BODIES end

-- Joueurs vivants : connectés (serveur MP) ou locaux (solo, getOnlinePlayers y est vide, LuaManager.java:3834).
function Bodies.livingPlayers()
    local out = {}
    local list = getOnlinePlayers()
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and not p:isDead() then out[#out + 1] = p end
        end
    end
    if not isServer() then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil and not p:isDead() then out[#out + 1] = p end
        end
    end
    return out
end

-- Vrai si un des joueurs players est à r cases ou moins de (x, y) (écart en x et en y).
function Bodies.playerNear(players, x, y, r)
    for _, p in ipairs(players) do
        if math.abs(p:getX() - x) <= r and math.abs(p:getY() - y) <= r then return true end
    end
    return false
end

-- Santé à garder pour le PNJ id dont le corps est z (dans le monde ou mis de côté), ou nil : plus basse des deux
-- valeurs connues, la santé du dernier rapport d'état accepté pour ce même corps (LK_Reports) et celle de la copie
-- de l'autorité quand c'est elle qui simule le corps (solo, ou serveur sans client propriétaire : sa santé fait foi,
-- base multiplayer.md). Jamais relevée : aucun soin n'est inventé.
function Bodies.keptHealth(id, z)
    -- LK07-T02 : la santé de référence tenue par l'autorité fait foi quand elle est connue.
    local H = LivingKnox.Health
    if H ~= nil and H.reference ~= nil then
        local ref = H.reference(id)
        if ref ~= nil then return ref end
    end
    local hp = nil
    local R = LivingKnox.Reports
    local s = R and R.states and R.states[id]
    if s ~= nil and z ~= nil and rawequal(s.body, z) and Identity().validHealth(s.hp) then hp = s.hp end
    if z ~= nil and not z:isDead() and (not isServer() or z:getOwner() == nil) then
        local own = z:getHealth()
        if Identity().validHealth(own) and (hp == nil or own < hp) then hp = own end
    end
    return hp
end

-- Rend le PNJ npcId à la simulation abstraite (LK09) : corps retiré s'il est dans le monde (un corps mis de côté hors
-- zone chargée est retiré comme orphelin à son retour par le balayage) ; PNJ virtuel ; gardés au registre : dernière
-- position vue (last, position approximative), santé (hp, Bodies.keptHealth), arme (weapon, inchangée), vêtements ;
-- consigne en cours ABANDONNÉE (Directives.forget : les détenteurs reçoivent { gone } ; la simulation abstraite n'a
-- pas de consigne et la matérialisation suivante en recevra une à jour, LK05/LK09-T03) ; état des rapports et geste
-- oubliés. Membre de groupe lié (LK09-T03, LK_Materialize.onReleased) : lien npc gardé, santé convertie en blessure
-- abstraite (wound), membre de nouveau traité par la simulation horaire, présent au foyer.
-- Rend vrai et le nombre de corps retirés, ou faux et une raison.
function Bodies.release(npcId, why)
    local ok, refused = Bodies.canAct(false)
    if not ok then return false, refused end
    local npc = Identity().get(Store().data(), npcId)
    if not npc then return false, "unknown npc " .. tostring(npcId) end
    if npc.state ~= Identity().STATE_EMBODIED then return false, "npc " .. npcId .. " is " .. npc.state end
    local z = Bodies.bound[npcId]
    local hp = Bodies.keptHealth(npcId, z)
    if hp ~= nil then npc.hp = hp end
    local dropped = "none"
    local D = LivingKnox.Directives
    if D ~= nil and D.forget ~= nil then
        local e = D.entries and D.entries[npcId]
        if e ~= nil and not e.done then dropped = tostring(e.op) .. " #" .. tostring(e.v) .. " abandoned" end
        D.forget(npcId)
    end
    if LivingKnox.Reports ~= nil and LivingKnox.Reports.forget ~= nil then LivingKnox.Reports.forget(npcId) end
    local A = LivingKnox.Anim
    if A ~= nil and A.setGesture ~= nil then A.setGesture(npcId, A.DEFAULT) end
    local inWorld = z ~= nil and Bodies.inWorld(z)
    local done, removed = Bodies.despawn(npcId, false)
    Bodies.farSince[npcId] = nil
    if not done then return false, removed end
    -- LK09-T03 : état simulé du membre de groupe lié mis à jour (santé -> blessure abstraite, présent au foyer).
    local M = LivingKnox.Materialize
    if M ~= nil and M.onReleased ~= nil then
        local okM, errM = pcall(M.onReleased, npcId, hp, npc)
        if not okM then log().error("npc %s: group member not updated at release: %s", npcId, tostring(errM)) end
    end
    local last = npc.last or npc.want
    log().info("npc %s released to the offscreen simulation (%s): body %s, last seen %s,%s,%s, health %s, "
        .. "weapon %s, directive %s", npcId, tostring(why), inWorld and "removed" or "out of the loaded area",
        tostring(last.x), tostring(last.y), tostring(last.z), hp and string.format("%.3f", hp) or "unknown",
        tostring(npc.weapon or "none"), dropped)
    return true, removed
end

-- Passage (autorité) : délai de chaque PNJ incarné sans joueur proche ; PNJ rendus à la simulation abstraite au bout
-- de RELEASE_DELAY_MS. Rend le nombre de PNJ rendus.
function Bodies.releasePass()
    local c = releaseCfg()
    local t = getTimestampMs()
    local st = Bodies.scanState
    if st.releaseMs ~= nil and t - st.releaseMs > c.RELEASE_GAP_MS then
        Bodies.farSince = {}   -- pause ou serveur figé : le temps sans passage ne compte pas
    end
    st.releaseMs = t
    local registry = Store().data()
    local players = Bodies.livingPlayers()
    local due = {}
    for _, id in ipairs(Identity().sortedIds(registry)) do
        local npc = registry.npcs[id]
        local far = false
        if npc.state == Identity().STATE_EMBODIED then
            local z = Bodies.bound[id]
            local x, y, owned
            if z ~= nil and Bodies.inWorld(z) then
                x, y = z:getX(), z:getY()
                owned = isServer() and z:getOwner() ~= nil
            else
                local p = npc.last or npc.want
                x, y = p.x + 0.5, p.y + 0.5
            end
            far = not owned and not Bodies.playerNear(players, x, y, c.RELEASE_RADIUS)
        end
        if not far then
            Bodies.farSince[id] = nil
        elseif Bodies.farSince[id] == nil then
            Bodies.farSince[id] = t
        elseif t - Bodies.farSince[id] >= c.RELEASE_DELAY_MS then
            due[#due + 1] = id
        end
    end
    local n = 0
    for _, id in ipairs(due) do   -- registre modifié hors du parcours
        local ok, why = Bodies.release(id, string.format("no player within %d squares for %d s", c.RELEASE_RADIUS,
            math.floor((t - Bodies.farSince[id]) / 1000)))
        if ok then
            n = n + 1
        else
            log().warn("npc %s not released: %s", id, tostring(why))
            Bodies.farSince[id] = t
        end
    end
    return n
end

-- Abonné OnTick (autorité) : une tranche de balayage toutes les SCAN_EVERY images, rien si le moteur est coupé ;
-- passage plantes et feux de camp toutes les HAZARD_EVERY tranches ; retrait loin des joueurs toutes les
-- RELEASE_EVERY tranches (LK03-T04) ; matérialisation des groupes à chaque tranche (LK09-T03, LK_Materialize).
function Bodies.tick()
    local st = Bodies.scanState
    st.ticks = st.ticks + 1
    if st.ticks < Bodies.SCAN_EVERY then return end
    st.ticks = 0
    if not Bodies.canAct(true) then return end
    Bodies.scan(Bodies.SCAN_BUDGET)
    st.hazard = (st.hazard or 0) + 1
    if st.hazard >= Bodies.HAZARD_EVERY then
        st.hazard = 0
        Bodies.hazardPass()
    end
    st.release = (st.release or 0) + 1
    if st.release >= Bodies.RELEASE_EVERY then
        st.release = 0
        Bodies.releasePass()
    end
    -- Matérialisation des groupes à l'approche d'un joueur (LK09-T03) : un passage par tranche, création étalée.
    local M = LivingKnox.Materialize
    if M ~= nil and M.pass ~= nil then M.pass() end
end

-- ---------------------------------------------------------------- mort et tueur (E04-T06)
-- Fiche : docs/annexes/conception/corps-registre.md, « Mort et tueur ». Java 42.21.0 (J/ = java/zombie/) :
-- - Coup d'un joueur en MP (mêlée, arme à feu) : paquet PlayerHitZombie traité par le serveur ; le joueur est celui
--   de la CONNEXION (J/network/fields/character/PlayerID.java:43), l'arme est relue dans SON inventaire serveur par
--   identifiant (J/network/fields/hit/Weapon.java:30-49), puis target.Hit(...) (J/network/fields/hit/
--   WeaponHit.java:79). IsoZombie.Hit déclenche OnHitZombie(zombie, wielder, bodyPart, weapon) AVANT les dégâts
--   (J/characters/IsoZombie.java:1109-1112), IsoGameCharacter.Hit pose setAttackedBy(wielder) (J/characters/
--   IsoGameCharacter.java:5739) ; coup mortel sur le serveur -> die() -> Kill(getAttackedBy()) -> onKilled ->
--   OnZombieDead dans le même appel (IsoGameCharacter.java:5836-5844, 13478-13486, 13463-13474 ; IsoZombie.java:
--   4599-4609). Solo : Kill(weapon, wielder) au même endroit.
-- - Explosion (bombe, piège) : Hit(arme du piège, lanceur) sur l'autorité (J/iso/objects/IsoTrap.java:783-790) ;
--   lanceur inconnu = faux zombie (getFakeZombieForHit). Cocktail Molotov (mode Fire) : feu seulement, aucun Hit
--   (IsoTrap.java:754-755).
-- - Feu : chaque dégât de brûlure pose setAttackedBy(null) et déclenche OnZombieDead une première fois
--   (IsoGameCharacter.java:5562-5577, 6044-6066), puis la mort le redéclenche : jamais de tueur.
-- - Véhicule : setAttackedBy(conducteur de la connexion) puis dégâts, sans OnHitZombie (J/network/fields/hit/
--   Hit.java:63, VehicleHitField.java:60-70 ; solo/hors réseau : IsoGameCharacter.java:11663-11722).
-- - Chute : setAttackedBy(null) (IsoZombie.java:2579). Kill(nil) d'un mod ou des pointes d'une armure (J/characters/
--   BodyDamage/BodyDamage.java:1362) : aucun tueur.
-- - En MP, le client propriétaire envoie la santé du zombie (J/popman/NetworkZombiePacker.java:230) et le serveur
--   appelle die() si elle est nulle (NetworkZombiePacker.java:100-101) : getAttackedBy() peut alors être un ANCIEN
--   attaquant. D'où la règle : un tueur n'est retenu que si le dernier coup relevé par OnHitZombie sur ce corps vient
--   du même joueur depuis au plus HIT_WINDOW_MS, ou si ce joueur conduit un véhicule à l'instant de la mort.
-- Catégories : melee, firearm (arme isRanged), fire (corps en feu sans coup récent, ou arme explosive), vehicle,
-- other (attaquant non joueur, ou joueur sans coup récent ni véhicule : non attribué), unknown (aucun attaquant).
Bodies.HIT_WINDOW_MS = 5000
Bodies.lastHits = Bodies.lastHits or {}   -- npcId -> { player, username, weapon, category, ms } (mémoire seulement)

local function isPlayer(o)
    return instanceof(o, "IsoPlayer") and not instanceof(o, "IsoAnimal")
end

-- Catégorie d'une arme (HandWeapon) : "fire" (explosif), "firearm" (à distance), sinon "melee" (mains nues comprises).
function Bodies.weaponCategory(weapon)
    if weapon == nil then return "unknown" end
    if weapon:isExplosive() then return "fire" end
    if weapon:isRanged() then return "firearm" end
    return "melee"
end

-- Abonné OnHitZombie (autorité) : dernier coup d'un joueur sur un corps courant de PNJ.
function Bodies.onHitZombie(z, wielder, _, weapon)
    if not LivingKnox.isAuthority() or not Store().isReady() or z == nil or not z:hasModData() then return end
    if not isPlayer(wielder) or weapon == nil then return end
    local I = Identity()
    local id, generation = I.readTag(z:getModData())
    if not id or I.classify(Store().data(), id, generation) ~= I.CURRENT then return end
    local hit = { player = wielder, username = wielder:getUsername(), weapon = weapon:getFullType(),
        category = Bodies.weaponCategory(weapon), ms = getTimestampMs() }
    Bodies.lastHits[id] = hit
    -- E09-T06 : coup d'un joueur sur un membre de groupe (fait "memberHit", lu par les incidents de trêve du carnet).
    local G = LivingKnox.Groups
    local gid, mid
    if G and G.findNpc then gid, mid = G.findNpc(id) end
    if gid then
        LivingKnox.publish("memberHit", { group = gid, member = mid, npc = id, player = wielder, u = hit.username,
            category = hit.category, weapon = hit.weapon, ms = hit.ms })
    end
end

-- Cause de la mort du corps z du PNJ id, selon la règle ci-dessus : { cause, killer = compte du joueur ou nil,
-- weapon = type d'objet ou nil, burning = vrai si le corps brûlait }. Consomme le dernier coup relevé.
-- LK07-T04 : cause décidée par la santé de référence avec la mort (Health.causeOf : "bleeding", "zombie") d'abord,
-- sans tueur. Un attaquant zombie n'est PAS une preuve à lui seul : un piège sans lanceur attaque par un faux zombie
-- (J/iso/objects/IsoTrap.java:784) ; seule l'attaque d'un zombie vanilla décidée par LK_Zombies donne "zombie".
function Bodies.deathCause(z, id)
    local hit = Bodies.lastHits[id]
    Bodies.lastHits[id] = nil
    local k = z:getAttackedBy()
    local burning = z:isOnFire() or nil
    local out = { cause = "unknown", burning = burning }
    local H = LivingKnox.Health
    local decided = H ~= nil and H.causeOf ~= nil and H.causeOf(id) or nil
    if decided ~= nil and Identity().DEATH_CAUSES[decided] then
        out.cause = decided
        return out
    end
    if isPlayer(k) then
        local vehicle = k:getVehicle()
        if hit ~= nil and rawequal(hit.player, k) and getTimestampMs() - hit.ms <= Bodies.HIT_WINDOW_MS then
            out.cause, out.killer, out.weapon = hit.category, hit.username, hit.weapon
        elseif vehicle ~= nil and rawequal(vehicle:getDriver(), k) then
            out.cause, out.killer = "vehicle", k:getUsername()
        elseif burning then
            out.cause = "fire"
        else
            out.cause = "other"
        end
    elseif burning then
        out.cause = "fire"
    elseif k ~= nil then
        out.cause = "other"
    end
    return out
end

-- Copie de la cause, transmise à l'écouteur de mort : le registre n'est jamais modifié par lui.
local function copyCause(c)
    return { cause = c.cause, killer = c.killer, weapon = c.weapon, burning = c.burning }
end

-- Écouteur de mort facultatif : function(id, zombie, cause). Le fournisseur Living Knox du carnet (E17-T03) s'y
-- branchera (Bodies.onDied = ...) pour émettre l'événement 'death' de RS_NPCProvider avec la cause en troisième
-- argument. Absent par défaut.

-- Abonné OnZombieDead (autorité) : le PNJ dont le corps courant meurt passe à l'état "dead" (suite : LK07), avec la
-- cause relevée (npc.death). Un second OnZombieDead (feu, cadavre traîné puis lâché, cadavre relevé remis à terre)
-- ne trouve plus de corps courant et ne fait rien : une seule mort par PNJ (LK07-T04).
function Bodies.onZombieDead(z)
    if not LivingKnox.isAuthority() or not Store().isReady() or z == nil or not z:hasModData() then return end
    local I = Identity()
    local id, generation = I.readTag(z:getModData())
    if not id then return end
    local class, npc = I.classify(Store().data(), id, generation)
    if class ~= I.CURRENT then return end
    local cause = Bodies.deathCause(z, id)
    -- LK07-T02 : mort décidée par la santé de référence, ou mort du moteur signalée et menée à son terme.
    local H = LivingKnox.Health
    if H ~= nil and H.onBodyDied ~= nil then
        local okH, errH = pcall(H.onBodyDied, id, z)
        if not okH then log().error("npc %s: health not closed at death: %s", id, tostring(errH)) end
    end
    -- LK07-T05 : butin de mort (arme gardée dans le cadavre, cartouches de l'arme en objets), avant le cadavre.
    local L = LivingKnox.Loot
    if L ~= nil and L.onDeath ~= nil then
        local okL, errL = pcall(L.onDeath, id, z)
        if not okL then log().error("npc %s: death loot not set: %s", id, tostring(errL)) end
    end
    I.markDead(npc)
    npc.death = cause
    npc.last = positionOf(z)
    Bodies.bound[id] = nil
    Bodies.trackCorpse(id, z, "death")   -- LK07-T10 : cadavre renvoyé à un client MP sans copie
    -- Écriture immédiate gardée (LK13-T10) : mort unique (LK07-T04), rare ; le cadavre et son butin (LK07-T05) sont
    -- déjà dans le monde, que le moteur peut sauvegarder avec son chunk sans attendre la fin de l'image.
    Store().save()
    log().info("npc %s died (generation %s): cause %s, killer %s, weapon %s%s", id, tostring(generation), cause.cause,
        tostring(cause.killer), tostring(cause.weapon), cause.burning and ", burning" or "")
    if Bodies.onDied ~= nil then
        local ok, err = pcall(Bodies.onDied, id, z, copyCause(cause))
        if not ok then log().error("npc %s death listener failed: %s", id, tostring(err)) end
    end
    -- E08-T07 : mort d'un membre de groupe devant les autres (fait "memberDied" de LK_Core, corps présent ; les
    -- témoins sont choisis par l'abonné d'après la scène). Le registre des groupes n'est pas modifié ici (LK07).
    -- LK07-T04 : cause, tueur et arme ajoutés (champs compatibles).
    local G = LivingKnox.Groups
    local gid, mid
    if G and G.findNpc then gid, mid = G.findNpc(id) end
    if gid then
        LivingKnox.publish("memberDied", { group = gid, member = mid, npc = id, day = G.today(), offscreen = false,
            body = z, cause = cause.cause, killer = cause.killer, weapon = cause.weapon })
        -- LK09-T03 : membre marqué mort dans le groupe, une seule fois et sans seconde publication (applyDeath quiet).
        local M = LivingKnox.Materialize
        if M ~= nil and M.onBodyDied ~= nil then
            local okM, errM = pcall(M.onBodyDied, id, gid, mid)
            if not okM then log().error("npc %s: group member death not recorded: %s", id, tostring(errM)) end
        end
    end
    -- LK07-T04 : fait "npcDied" pour tout PNJ dont le corps meurt (membre de groupe ou non), après le registre des
    -- groupes : point d'appel des événements publics de LK12-T02 (docs/specifications-techniques/api-living-knox.md, « Faits
    -- publiés »).
    local p = npc.last
    LivingKnox.publish("npcDied", { npc = id, generation = generation, cause = cause.cause, killer = cause.killer,
        weapon = cause.weapon, burning = cause.burning, group = gid, member = mid, x = p.x, y = p.y, z = p.z,
        body = z })
end

return Bodies
