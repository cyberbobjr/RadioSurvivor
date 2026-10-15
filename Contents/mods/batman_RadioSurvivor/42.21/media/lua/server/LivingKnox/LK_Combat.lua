-- Living Knox : mêlée des PNJ, côté autorité (LK06-T02). Fiche : docs/conception/combat.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...). Un client MP charge aussi ce fichier (media/lua/server) : il n'y trouve
-- que les constantes et les réglages ; le geste de frappe est minuté chez le propriétaire du corps par
-- client/LivingKnox/LK_CombatClient.lua.
--
-- Engagement (Combat.engage) : un PNJ prend pour cible un joueur, décidé par l'autorité seule (cascade de LK_Decisions,
-- comportement "fight", cible de Hostility.chooseTarget d'action "attack" ; ou API et suites de test). Ordre numéroté
-- c (croissant sur la session, jamais réutilisé) ; arme : celle du PNJ (Equipment.wantedOf) si c'est une arme de
-- mêlée, sinon mains nues (Base.BareHands, arme vanilla des coups sans arme) ; portée = MaxRange de l'arme (au moins
-- MIN_REACH) + REACH_BONUS ; cadence = une frappe par boucle du clip de frappe joué par le corps (STRIKE_MS).
-- Passage de l'autorité (toutes les PASS_MS) pour chaque PNJ engagé :
--   - hors de portée : consigne "move" en course vers la case du joueur (Directives.moveTo), renouvelée quand le joueur
--     s'éloigne de REPATH cases ou après RETRY_MS ; geste de frappe retiré ;
--   - à portée (même niveau) : consigne "face" vers le joueur (renouvelée s'il tourne de FACE_DELTA degrés), puis geste
--     "strike" (clip d'attaque du joueur en boucle, tools/anim_table.json : LKActorStrike2H, LKActorStrike1H) ;
--   - fin : joueur parti, mort, trop loin (GIVE_UP), corps absent ou mort, ou décision changée (Combat.leave) ;
--     défense du foyer (LK05-T09, opts.leash) : cible hors de la laisse du poste ni à portée ni sous un tir dégagé.
-- Touche : rapportée par la machine qui simule le corps (client propriétaire, solo) au moment de l'impact de chaque
-- boucle du clip ("combatHit" { id, c, n, u, x, y, z }, appel direct en solo), puis CONTRÔLÉE ici : ordre courant c,
-- expéditeur = propriétaire du corps (getOwnerPlayer ; ancien propriétaire encore persuadé de simuler : ignoré),
-- numéro n croissant par expéditeur et par ordre (doublon ou rejeu ignoré), même cible, cible vivante et hors véhicule,
-- geste de frappe en cours, même niveau, distance des copies du serveur <= portée + REACH_SLACK, et pas plus d'une
-- touche par CADENCE_MIN x STRIKE_MS. Acceptée : dommages appliqués UNE fois par le serveur avec le chemin vanilla des
-- coups entre joueurs : BodyDamage:DamageFromWeapon(arme, -1) (J/characters/BodyDamage/BodyDamage.java:1014-1100 :
-- partie tirée au hasard, défense des vêtements, blessure, douleur ; sur un serveur, modificateur PvP de mêlée du
-- serveur et syncDamage), puis sendDamage(joueur) (J/Lua/LuaManager.java:3743-3748 : état complet des blessures au
-- client du joueur, idempotent). Cible zombie : Combat.applyToZombie (LK06-T04, voir plus bas).
-- LK05-T18 : cible zombie simulée par un autre client et absente chez le propriétaire du corps : la touche arrive quand
-- même, marquée nf (« vue nulle part là-bas ») ; mêmes contrôles sur les copies de l'autorité, refus sans WARN.
-- Diffusion (serveur MP) : "combatState" { d = { [npcId] = { r, c, u, k, rc, iv, im } | { r, gone = true } } } aux
-- destinataires des consignes (Directives.targets : joueurs à NEAR_RADIUS cases et propriétaire), seulement à ceux qui
-- n'ont pas la révision courante (r croissant, livraison non ordonnée) ; { gone } aux détenteurs à la fin. Mémoire
-- seulement : un redémarrage oublie les engagements (la cascade les reprend).
--
-- Tir (LK06-T03, fiche combat.md, section « Tir ») : un PNJ dont l'arme du registre est une arme à feu ET qui a des
-- munitions (LivingKnox.Ammo : cartouches dans l'arme ou réserve réelle de l'inventaire du corps) est engagé en mode
-- "ranged" (champ m de l'ordre) au lieu de la mêlée ; sans munition, mêlée à mains nues comme avant. Portée = MaxRange
-- de l'arme (au plus FIRE_RANGE). Passage de l'autorité :
--   - arme vide : rechargement animé sur place (regard vers la cible, geste "reload" pendant RELOAD_MS[handgun|rifle],
--     deux boucles pour des cartouches libres), puis Ammo.reload ; plus aucune munition : fin de l'ordre de tir et
--     nouvel engagement (mêlée à mains nues) ;
--   - tir possible (même niveau, portée, hors véhicule, ligne de tir LosUtil.lineClear Clear, ClearThroughOpenDoor
--     ou, depuis LK06-T08, ClearThroughWindow : vitre fermée cassée au tir comme le vanilla ; même appel que
--     LK_Senses) : regard, geste "aim" pendant AIM_MS, puis geste "shoot" (clip de tir du joueur en
--     boucle : un tir par boucle, SHOT_MS) ; sinon approche en course comme la mêlée (geste "aim" au lieu de "guard").
-- Tir rapporté par le propriétaire comme une touche (même message, mêmes contrôles, phase "shoot"), puis contrôlé :
-- ligne de tir sur les copies du serveur, cadence, et UNE cartouche retirée de l'arme (Ammo.consume) avant tout effet :
-- aucun tir sans munition côté serveur. Tir accepté : bruit pour les zombies (addSound, rayon SoundRadius x
-- FirearmNoiseMultiplier, moitié à l'intérieur, comme ISReloadWeaponAction.attackHook), son vanilla de l'arme
-- (SwingSound) et éclair joués une fois par chaque client proche (commande "combatShot", appel direct en solo,
-- client/LivingKnox/LK_CombatClient.lua), puis touche décidée par le serveur seul, de façon déterministe : chance
-- vanilla simplifiée (Combat.hitChance, CombatManager.calculateHitChanceData sans visée progressive, mouvement, météo,
-- lumière ni moodles) comparée à un tirage reproductible (Combat.roll : PNJ, ordre, numéro du tir). Touché :
-- DamageFromWeapon(arme à feu, -1) (blessure par balle ; sur un serveur, x PVPFirearmDamageModifier) puis sendDamage.
--
-- Cible zombie (LK06-T04, fiche zombies.md) : Combat.engage accepte aussi un zombie vanilla (objet IsoZombie) ;
-- ordre de genre k = "zombie", u = clé du zombie (LivingKnox.Zombies.keyOf), zo = son identifiant réseau (diffusé :
-- le propriétaire du corps le retrouve dans sa cellule), zt = l'objet (autorité seulement). Combat.targetFor rend,
-- faute de cible joueur, le zombie que le combattant doit repousser (Zombies.targetFor). Même approche, mêmes
-- gestes, même rapport et mêmes contrôles que contre un joueur ; la touche acceptée passe par Combat.applyToZombie
-- (Zombies.hurt : dégâts vanilla reproductibles, mort décidée une fois par l'autorité).
--
-- Vitres et portes (LK06-T08, fiche zombies.md) : un coup de mêlée exige la ligne de coup vanilla
-- (Combat.lineOfStrike : ni mur, ni porte fermée, ni vitre fermée ou barricadée entre les deux, rapport refusé sinon) ;
-- cible vue derrière une vitre fermée ou une porte vitrée fermée : le PNJ de mêlée l'attend en garde sur place
-- (phase "hold") au lieu de contourner, sauf sortie de défense du foyer (LK06-T14, leash.around : il la rejoint par
-- son chemin, porte ou ouverture) ; tir à travers une vitre fermée : vitre cassée (Combat.smashWindowOnLine).
--
-- Coup au sol (LK06-T09, fiche combat.md, section « Coup au sol ») : une cible zombie au sol (isOnFloor : tombé d'une
-- fenêtre, renversé ; un rampant reste frappé debout) est frappée comme le joueur vanilla vise le sol (une cible au
-- sol n'est touchée que par une attaque au sol, J/CombatManager.java:1578) : geste "strikefloor" (clips
-- Bob_AttackFloorBat, Bob_AttackFloor1Hand des nœuds vanilla 2HOnFloor, 1HOnFloor) avec une arme, "stomp"
-- (Bob_AttackFloorStamp, StompDefault) à mains nues ; même cadence, même rapport, mêmes contrôles. Dégâts au sol et
-- réaction « Floor » : LivingKnox.Zombies.hurt.
--
-- Sons de la mêlée (LK06-T11, fiche combat.md, section « Sons de la mêlée ») : comme le joueur vanilla
-- (J/ai/states/SwipeStatePlayer.java:212-223, 348-373 ; J/CombatManager.java:723-790), un élan au début de chaque
-- boucle du clip de frappe et un impact quand le coup touche, sans bruit pour les zombies (SoundRadius des armes de
-- mêlée à 0, base sounds-and-noise.md). Élan : joué localement par chaque client proche qui voit le geste de frappe
-- (LK_CombatClient.lua, nom sw de l'ordre diffusé : SwingSound de l'arme, "AttackShove" à mains nues, "AttackStomp"
-- pour le piétinement) ; impact : à chaque touche ACCEPTÉE ici, nom choisi par Combat.impactSound (HitSound du
-- script de l'arme, HitFloorSound pour un coup au sol) et envoyé une fois à chaque client proche ("combatMelee"
-- { m = { k, npc, o, x, y, z, sw, hit } }, appel direct de View.onMelee en solo). Coup manqué (rien rapporté) :
-- élan seul.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Combat = LivingKnox.Combat or {}
LivingKnox.Combat = Combat

Combat.MODULE = "LivingKnox"
Combat.CMD_STATE = "combatState"   -- serveur -> clients proches : { d = { [npcId] = ordre | { r, gone } } }
Combat.CMD_HIT = "combatHit"       -- propriétaire -> serveur : { id, c, n, u, x, y, z }
Combat.CMD_SHOT = "combatShot"     -- serveur -> clients proches : { s = { id, k, npc, x, y, z, snd } } (LK06-T03)
Combat.CMD_MELEE = "combatMelee"   -- serveur -> clients proches : { m = { k, npc, o, x, y, z, sw, hit } } (LK06-T11)
-- Sons vanilla d'une attaque sans arme (J/ai/states/SwipeStatePlayer.java:212-223, scripts sounds_player_combat.txt) :
-- poussée debout, piétinement d'une cible au sol.
Combat.SHOVE_SOUND, Combat.STOMP_SOUND = "AttackShove", "AttackStomp"
Combat.MELEE, Combat.RANGED = "melee", "ranged"
Combat.KIND_PLAYER = "player"
Combat.KIND_ZOMBIE = "zombie"      -- LK06-T04
Combat.BARE_HANDS = "Base.BareHands"
-- Gestes de frappe de mêlée (LK06-T09 : coup au sol "strikefloor" avec une arme, "stomp" à mains nues).
Combat.STRIKE_GESTURES = { strike = true, strikefloor = true, stomp = true }

-- Réglages (valeurs de départ, raisons dans la fiche ; lus à chaque appel).
LivingKnox.Config.COMBAT = LivingKnox.Config.COMBAT or {
    PASS_MS = 250,          -- passage de l'autorité sur les PNJ engagés
    STRIKE_MS = 1250,       -- boucle du clip de frappe : Bob_AttackBat01_Hit et Bob_Attack1Hand01_Hit durent 1,0 s
                            -- (4800 tics à 4800 tics/s), joués à la vitesse 0,80 par nos nœuds
    IMPACT_MS = 312,        -- impact dans la boucle : AttackCollisionCheck à 25 % du clip (2HDefault.xml, 1HDefault.xml)
    CADENCE_MIN = 0.6,      -- touches acceptées espacées d'au moins CADENCE_MIN x STRIKE_MS (gigue du réseau)
    MIN_REACH = 1.0,        -- cases : portée minimale d'une arme de mêlée
    REACH_BONUS = 0.5,      -- cases : rayon des deux corps (le moteur vise le point le plus proche de la cible)
    REACH_SLACK = 1.0,      -- cases tolérées en plus par le serveur (positions des copies du serveur en retard)
    FACE_DELTA = 30,        -- degrés : nouvelle consigne "face" si le joueur a tourné d'au moins autant
    REPATH = 2,             -- cases : nouvelle consigne "move" si le joueur s'est éloigné d'autant de la case visée
    MOVE_MS = 1000,         -- au plus une consigne "move" par PNJ dans ce délai
    RETRY_MS = 3000,        -- consigne "move" close sans être à portée : nouvel essai après ce délai
    GIVE_UP = 30,           -- cases : au-delà, l'engagement prend fin
    MAX_ENGAGED = 16,       -- PNJ engagés au plus (coût borné par passage)
    WARN_EVERY_MS = 60000,  -- une ligne par (expéditeur, raison) au plus par minute
    -- Tir (LK06-T03).
    SHOT_MS = 1000,         -- boucle du clip de tir : Bob_AttackHandgun 0,667 s joué à 0,667, Bob_AttackRifle 0,5 s
                            -- joué à 0,5 (tools/anim_table.json : LKActorShootHandgun, LKActorShootRifle)
    SHOT_IMPACT_MS = 100,   -- coup de feu dans la boucle : AttackCollisionCheck à 0,1 % du clip (HandgunDefault.xml,
                            -- FirearmDefault.xml), après le fondu d'entrée
    AIM_MS = 600,           -- visée avant le premier tir d'une série
    FIRE_RANGE = 20,        -- cases : portée de tir maximale (MaxRange de l'arme sinon, pistolet 15)
    RELOAD_MS = { handgun = 1875, rifle = 2167 },   -- une boucle du clip de rechargement : Bob_Reload_Handgun_Load 1,5 s,
                            -- Bob_Reload_Rifle_Load 1,733 s, joués à 0,80 (vitesse vanilla de base, ISReloadWeaponAction)
    RELOAD_ROUNDS_LOOPS = 2,   -- boucles pour des cartouches libres (un échange de chargeur : une boucle)
    AIM_LEVEL = 3,          -- compétence Visée prêtée aux PNJ (chance de toucher et zone de visée)
    -- Résultats de LosUtil.lineClear admis pour un tir (LK06-T08 : vitre comprise, cassée au tir comme
    -- CombatManager.smashWindowBetween ; porte vitrée fermée exclue, J/CombatManager.java:1719) et pour un coup de
    -- mêlée (vitre seulement ouverte ou cassée, voir Combat.lineOfStrike).
    LINE_OF_FIRE = { Clear = true, ClearThroughOpenDoor = true, ClearThroughWindow = true },
    LINE_OF_STRIKE = { Clear = true, ClearThroughOpenDoor = true, ClearThroughWindow = true },
    NOISE_INSIDE = 0.5,     -- rayon du bruit à l'intérieur (ISReloadWeaponAction.attackHook)
    -- Constantes vanilla de la chance de toucher (J/combat/CombatConfigKey.java:20-55, valeurs par défaut).
    HIT = { POINT_BLANK_DISTANCE = 3.5, POINT_BLANK_BONUS = 40, POINT_BLANK_DROP_OFF = 0.7, SIGHTLESS_BASE = 15,
        OPTIMAL_BONUS = 15, OPTIMAL_DROP_OFF = 4, OPTIMAL_DROP_OFF_INCREMENT = 0.3, MIN = 5, MAX_START = 95,
        MAX = 100 },
}

if isClient() then return Combat end

require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_Anim"
require "LivingKnox/LK_Equipment"
require "LivingKnox/LK_Ammo"

Combat.orders = Combat.orders or {}     -- npcId -> ordre courant (autorité)
Combat.weapons = Combat.weapons or {}   -- type -> objet HandWeapon de l'autorité (instancié une fois)
Combat.sent = Combat.sent or {}         -- compte -> { p = joueur, ids = { [npcId] = r } } (serveur)
Combat.warned = Combat.warned or {}
Combat.state = Combat.state or { seq = 0, r = 0, lastPass = nil, shots = 0 }
Combat.stats = Combat.stats or { engaged = 0, ended = 0, moves = 0, faces = 0, strikes = 0, reports = 0,
    applied = 0, refused = 0, ignored = 0, duplicates = 0, stale = 0, messages = 0, zombieUnhandled = 0,
    why = {} }
for _, k in ipairs({ "shots", "hits", "misses", "reloads", "outOfAmmo", "noises", "shotMessages", "volleys" }) do
    Combat.stats[k] = Combat.stats[k] or 0   -- LK06-T03
end
for _, k in ipairs({ "holds", "windowsSmashed" }) do
    Combat.stats[k] = Combat.stats[k] or 0   -- LK06-T08
end
Combat.stats.rearmed = Combat.stats.rearmed or 0   -- LK07-T08 : ordre renouvelé, arme changée
for _, k in ipairs({ "meleeSounds", "meleeMessages", "meleeSilent" }) do
    Combat.stats[k] = Combat.stats[k] or 0   -- LK06-T11
end

local function cfg() return LivingKnox.Config.COMBAT end
local function log() return LivingKnox.Log end
local function Bodies() return LivingKnox.Bodies end
local function D() return LivingKnox.Directives end
local function Anim() return LivingKnox.Anim end

local function now() return getTimestampMs() end
local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function count(name)
    local st = Combat.stats
    st[name] = (st[name] or 0) + 1
end

local function nameOf(player)
    local Dir = D()
    if Dir ~= nil and Dir.senderName ~= nil then return Dir.senderName(player) end
    return player and tostring(player:getUsername()) or "?"
end

local function angleTo(dx, dy)
    if dx == 0 and dy == 0 then return nil end
    local a = math.atan2(dy, dx) * 180 / math.pi
    return a - math.floor(a / 360) * 360
end

local function angleGap(a, b)
    local g = math.abs(a - b)
    g = g - math.floor(g / 360) * 360
    if g > 180 then g = 360 - g end
    return g
end

-- ---------------------------------------------------------------- joueurs et arme

-- Joueur de compte name (serveur : joueurs connectés ; solo : joueurs locaux), mort compris, ou nil.
function Combat.playerByName(name)
    if type(name) ~= "string" then return nil end
    local list = getOnlinePlayers()
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and nameOf(p) == name then return p end
        end
    end
    if not isServer() then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil and nameOf(p) == name then return p end
        end
    end
    return nil
end

local function weaponItem(fullType)
    local w = Combat.weapons[fullType]
    if w == nil then
        w = instanceItem(fullType)
        if w == nil or not instanceof(w, "HandWeapon") then return nil end
        Combat.weapons[fullType] = w
    end
    return w
end

-- Arme du PNJ id : { t = type, w = objet HandWeapon de l'autorité, reach, bare, ranged, h }. Arme à feu avec des
-- munitions (LivingKnox.Ammo.available) : tir (ranged, portée MaxRange au plus FIRE_RANGE, h = deux mains). Arme à feu
-- sans munition, arme absente ou inconnue : mains nues.
function Combat.weaponOf(id)
    local E = LivingKnox.Equipment
    local spec = E ~= nil and E.wantedOf ~= nil and E.wantedOf(id) or nil
    local w = spec ~= nil and weaponItem(spec.t) or nil
    if w ~= nil and w:isRanged() then
        local Am = LivingKnox.Ammo
        local B = Bodies()
        local z = B and B.find(id)
        if Am ~= nil and z ~= nil and Am.available(z, w:getFullType()) > 0 then
            local range = w:getMaxRange()
            if not finite(range) or range <= 0 then range = cfg().FIRE_RANGE end
            return { t = w:getFullType(), w = w, reach = math.min(range, cfg().FIRE_RANGE), bare = false,
                ranged = true, h = spec.h == true }
        end
    end
    local bare = false
    if w == nil or w:isRanged() then
        w = weaponItem(Combat.BARE_HANDS)
        bare = true
    end
    if w == nil then return nil end
    local range = w:getMaxRange()
    if not finite(range) or range < cfg().MIN_REACH then range = cfg().MIN_REACH end
    return { t = w:getFullType(), w = w, reach = range + cfg().REACH_BONUS, bare = bare }
end

local function soundName(s)
    if type(s) ~= "string" or s == "" or s == "null" then return nil end
    return s
end

-- LK06-T11 : élan d'un coup de mêlée avec l'arme w (bare : mains nues), comme le joueur vanilla : SwingSound du script
-- de l'arme (événement PlaySwingSound des nœuds 1HDefault, 2HDefault et de leurs coups au sol,
-- J/ai/states/SwipeStatePlayer.java:359-373) ; sans arme, la poussée "AttackShove" (SwipeStatePlayer.java:212-223 ;
-- le piétinement "AttackStomp" est choisi par le client d'après le geste affiché). Rend le nom ou nil.
function Combat.swingSound(w, bare)
    if bare then return Combat.SHOVE_SOUND end
    if w == nil then return nil end
    return soundName(w:getSwingSound())
end

-- LK06-T11 : impact d'un coup de mêlée accepté avec l'arme w, geste g, comme J/CombatManager.java:723-790 : coup au
-- sol ("strikefloor", "stomp") : HitFloorSound du script, sinon HitSound ; debout : HitSound (getZombieHitSound, le
-- même contre un joueur ou un zombie). Mains nues debout : HitSound de Base.BareHands ("BareHandsHit"), alors que la
-- poussée vanilla n'a pas d'impact (décision à confirmer, fiche combat.md) : la frappe du PNJ blesse. Rend le nom ou
-- nil.
function Combat.impactSound(w, g)
    if w == nil then return nil end
    if g == "strikefloor" or g == "stomp" then
        local s = soundName(w:getHitFloorSound())
        if s ~= nil then return s end
    end
    return soundName(w:getZombieHitSound())
end

-- ---------------------------------------------------------------- engagement

local function touch(o)
    local st = Combat.state
    st.r = st.r + 1
    o.r = st.r
end

-- Les consignes du combat comptent comme celles du cadre de décision (jamais "externes" pour lui).
local function noteIssued(id, v, why)
    if v == nil then
        log().debug("npc %s: combat directive refused: %s", id, tostring(why))
        return nil
    end
    local De = LivingKnox.Decisions
    if De ~= nil and De.noteIssued ~= nil then De.noteIssued(id, v) end
    return v
end

-- Cible d'un ordre : joueur de compte o.u, ou zombie o.zt (LK06-T04) encore chargé ou mort. Rend l'objet ou nil.
function Combat.targetOf(o)
    if o.k ~= Combat.KIND_ZOMBIE then return Combat.playerByName(o.u) end
    local tz = o.zt
    if tz == nil then return nil end
    if tz:isDead() then return tz end
    local Zm = LivingKnox.Zombies
    if Zm == nil or not Zm.inWorld(tz) then return nil end
    return tz
end

-- Nom d'une cible dans le journal : compte du joueur, « zombie <clé> ».
local function label(o)
    if o.k == Combat.KIND_ZOMBIE then return "zombie " .. tostring(o.u) end
    return tostring(o.u)
end

-- Engage le PNJ id contre le joueur de compte target, ou contre le zombie vanilla target (objet IsoZombie,
-- LK06-T04). opts : { source = "decisions" | "api", why, leash }. Même cible déjà engagée : ordre gardé (laisse
-- remplacée). leash = { x, y, z, r, around } (LK05-T09, défense du foyer) : l'ordre prend fin plutôt que d'approcher
-- une cible à plus de r cases (x et y) de la case (x, y, z) ou à un autre niveau ; around (LK06-T14, sortie de
-- défense) : cible vue derrière une vitre rejointe par le chemin au lieu de l'attente en garde. Rend le numéro c, ou
-- nil et une raison.
function Combat.engage(id, target, opts)
    if not LivingKnox.isAuthority() then return nil, "not the authority (MP client)" end
    if not LivingKnox.Config.isEnabled() then return nil, "Living Knox is disabled" end
    opts = opts or {}
    if type(id) ~= "string" or id == "" then return nil, "bad npc id " .. tostring(id) end
    local kind, tz = Combat.KIND_PLAYER, nil
    if instanceof(target, "IsoZombie") then
        local Zm = LivingKnox.Zombies
        if Zm == nil then return nil, "zombie targets need LivingKnox.Zombies" end
        local ok, why = Zm.isVanilla(target)
        if not ok then return nil, "zombie target refused: " .. tostring(why) end
        kind, tz, target = Combat.KIND_ZOMBIE, target, Zm.keyOf(target)
    elseif type(target) ~= "string" or target == "" then
        return nil, "bad target " .. tostring(target)
    end
    local B = Bodies()
    local z = B and B.find(id)
    if z == nil or z:isDead() then return nil, "npc " .. id .. " has no body in the loaded area" end
    if kind == Combat.KIND_PLAYER then
        local p = Combat.playerByName(target)
        if p == nil then return nil, "player " .. target .. " is not here" end
        if p:isDead() then return nil, "player " .. target .. " is dead" end
    end
    local o = Combat.orders[id]
    if o ~= nil and o.u == target then
        if opts.source ~= nil then o.source = opts.source end
        o.leash = opts.leash   -- LK05-T09
        return o.c
    end
    local n = 0
    for _ in pairs(Combat.orders) do n = n + 1 end
    if o == nil and n >= cfg().MAX_ENGAGED then return nil, "too many npcs engaged" end
    local weapon = Combat.weaponOf(id)
    if weapon == nil then return nil, "no melee weapon item (" .. Combat.BARE_HANDS .. ")" end
    if o ~= nil then Combat.disengage(id, "new target " .. target) end
    local st = Combat.state
    st.seq = st.seq + 1
    local ranged = weapon.ranged == true
    o = { c = st.seq, u = target, k = kind, m = ranged and Combat.RANGED or Combat.MELEE, t = weapon.t,
        bare = weapon.bare, reach = weapon.reach, h = weapon.h == true,
        iv = ranged and cfg().SHOT_MS or cfg().STRIKE_MS, im = ranged and cfg().SHOT_IMPACT_MS or cfg().IMPACT_MS,
        source = opts.source or "api", since = now(), phase = "approach", hits = 0, shots = 0, reloads = 0,
        lastN = {}, leash = opts.leash }
    if not ranged then o.sw = Combat.swingSound(weapon.w, weapon.bare) end   -- LK06-T11
    if tz ~= nil then o.zt, o.zo = tz, tz:getOnlineID() end
    touch(o)
    Combat.orders[id] = o
    count("engaged")
    if ranged then
        log().info("npc %s: ranged #%d against %s with %s (range %.2f, one shot every %d ms, %d round(s) in the "
            .. "weapon): %s", id, o.c, label(o), o.t, o.reach, o.iv, LivingKnox.Ammo.loaded(z, o.t),
            tostring(opts.why or o.source))
    else
        log().info("npc %s: melee #%d against %s with %s (reach %.2f, one strike every %d ms): %s", id, o.c, label(o),
            weapon.bare and "bare hands" or weapon.t, o.reach, o.iv, tostring(opts.why or o.source))
    end
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then
        Ac.noteNpc(id, "combat", string.format("%s #%d against %s with %s: %s", ranged and "ranged" or "melee", o.c,
            label(o), weapon.bare and "bare hands" or tostring(weapon.t), tostring(opts.why or o.source)))
    end
    Combat.step(id)
    return o.c
end

-- Fin de l'engagement du PNJ id : geste de frappe retiré, marche du combat arrêtée. Rend vrai s'il était engagé.
function Combat.disengage(id, why)
    local o = Combat.orders[id]
    if o == nil then return false end
    Combat.orders[id] = nil
    count("ended")
    local A = Anim()
    local g = A ~= nil and A.gestureOf(id) or nil
    if Combat.STRIKE_GESTURES[g] or (o.m == Combat.RANGED and (g == "aim" or g == "shoot" or g == "reload")) then
        A.setGesture(id, A.DEFAULT)
    end
    local Dir = D()
    local e = Dir and Dir.get and Dir.get(id) or nil
    if e ~= nil and not e.done and e.v == o.moveV and e.op == Dir.OP_MOVE then noteIssued(id, Dir.stop(id)) end
    Combat.gone(id)
    if o.m == Combat.RANGED then
        log().info("npc %s: ranged #%d against %s ended after %d shot(s), %d hit(s): %s", id, o.c, label(o), o.shots,
            o.hits, tostring(why))
    else
        log().info("npc %s: melee #%d against %s ended after %d hit(s): %s", id, o.c, label(o), o.hits, tostring(why))
    end
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then
        Ac.noteNpc(id, "combat", string.format("%s #%d against %s ended: %d hit(s), %d shot(s): %s",
            o.m == Combat.RANGED and "ranged" or "melee", o.c, label(o), o.hits, o.shots or 0, tostring(why)))
    end
    return true
end

-- Cadre de décision (LK_Decisions, comportement "fight") : cible ctx.target = { u, d, reason } (joueur) ou
-- { kind = "zombie", u, d, reason, zombie } (LK06-T04).
function Combat.apply(id, st, ctx, fresh)
    local tg = ctx and ctx.target or nil
    if tg == nil then return end
    local target = tg.kind == Combat.KIND_ZOMBIE and tg.zombie or tg.u
    local c, why = Combat.engage(id, target, { source = "decisions", why = st and st.why })
    if c == nil then
        log().debug("npc %s: melee refused: %s", id, tostring(why))
        return
    end
    if fresh then Combat.step(id) end
end

-- Décision changée (LK_Decisions) : fin d'un engagement décidé par le cadre (un engagement de l'API reste).
function Combat.leave(id)
    local o = Combat.orders[id]
    if o ~= nil and o.source == "decisions" then Combat.disengage(id, "decision changed") end
end

-- PNJ oublié : engagement retiré sans consigne.
function Combat.forget(id)
    if Combat.orders[id] == nil then return end
    Combat.orders[id] = nil
    Combat.gone(id)
end

-- Cible du membre npcId du groupe gid, d'après sa perception (joueurs vus) et Hostility.chooseTarget : { u, d,
-- reason } si l'action retenue est "attack" ; sinon (LK06-T04) le zombie vanilla à repousser (Zombies.targetFor :
-- { kind = "zombie", u, d, reason, zombie }) ; sinon nil. Lecture seule.
function Combat.targetFor(gid, npcId, per, players)
    local Ho = LivingKnox.Hostility
    if Ho ~= nil and Ho.chooseTarget ~= nil and Ho.candidatesOf ~= nil then
        local cands = Ho.candidatesOf(per, players)
        if #cands > 0 then
            local res = Ho.chooseTarget(gid, npcId, cands)
            local t = res and res.target or nil
            if t ~= nil and t.action == "attack" then return { u = t.u, d = t.d, reason = t.reason } end
        end
    end
    local Zm = LivingKnox.Zombies
    if Zm ~= nil and Zm.targetFor ~= nil then return Zm.targetFor(npcId) end
    return nil
end

-- ---------------------------------------------------------------- passage de l'autorité

local function openMove(id, o)
    local Dir = D()
    local e = Dir.get(id)
    if e == nil or e.done or e.op ~= Dir.OP_MOVE or e.v ~= o.moveV then return nil end
    return e
end

local function approach(id, o, p, t)
    local c = cfg()
    local A = Anim()
    if o.phase == "strike" or o.phase == "aim" or o.phase == "shoot" then
        o.phase = "approach"
        o.faced = nil
    end
    local g = A.gestureOf(id)
    if Combat.STRIKE_GESTURES[g] then A.setGesture(id, "guard") end
    if g == "shoot" or g == "reload" then A.setGesture(id, "aim") end
    local tx, ty, tz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    if o.moveMs ~= nil and t - o.moveMs < c.MOVE_MS then return end
    local open = openMove(id, o)
    local need
    if open ~= nil then
        need = tz ~= o.moveZ or math.max(math.abs(tx - o.moveX), math.abs(ty - o.moveY)) >= c.REPATH
    else
        need = o.moveX ~= tx or o.moveY ~= ty or o.moveZ ~= tz or o.moveMs == nil or t - o.moveMs >= c.RETRY_MS
    end
    if not need then return end
    o.moveMs = t
    local v = noteIssued(id, D().moveTo(id, tx, ty, tz, "run"))
    if v ~= nil then
        o.moveV, o.moveX, o.moveY, o.moveZ = v, tx, ty, tz
        count("moves")
    end
end

-- LK06-T09 : vrai si la cible p de l'ordre o est un zombie au sol (tombé, renversé) ; un rampant se frappe debout
-- comme le vanilla (isProne faux).
function Combat.onFloor(o, p)
    if o.k ~= Combat.KIND_ZOMBIE then return false end
    local S = LivingKnox.Senses   -- MP : chute vue par le client qui simule le zombie (LK06-T11)
    if S ~= nil and S.onFloor ~= nil then return S.onFloor(p) end
    return p:isOnFloor() and not p:isCrawling()
end

-- Geste de frappe de l'ordre o contre la cible p : "strike", ou coup au sol ("strikefloor" avec une arme, "stomp" à
-- mains nues) contre un zombie au sol.
function Combat.strikeGesture(o, p)
    if not Combat.onFloor(o, p) then return "strike" end
    return o.bare and "stomp" or "strikefloor"
end

local function strike(id, o, z, p)
    local A = Anim()
    local a = angleTo(p:getX() - z:getX(), p:getY() - z:getY())
    if o.phase ~= "strike" or (a ~= nil and (o.faced == nil or angleGap(a, o.faced) >= cfg().FACE_DELTA)) then
        if a ~= nil then
            o.faced = a
            if noteIssued(id, D().face(id, a)) ~= nil then count("faces") end
        end
    end
    if o.phase ~= "strike" then
        o.phase = "strike"
        count("strikes")
    end
    local g = Combat.strikeGesture(o, p)   -- LK06-T09 : coup au sol contre un zombie à terre
    if A.gestureOf(id) ~= g then A.setGesture(id, g) end   -- après "face", qui remet le repos
end

-- LK06-T08 : cible vue derrière une vitre fermée ou une porte vitrée fermée (aucun coup possible) : le PNJ de mêlée
-- l'attend sur place, tourné vers elle, en garde (phase "hold"), au lieu de contourner ; il frappe dès que la vitre
-- est ouverte ou cassée.
local function hold(id, o, z, p)
    local A = Anim()
    local a = angleTo(p:getX() - z:getX(), p:getY() - z:getY())
    if o.phase ~= "hold" or (a ~= nil and (o.faced == nil or angleGap(a, o.faced) >= cfg().FACE_DELTA)) then
        if a ~= nil then
            o.faced = a
            if noteIssued(id, D().face(id, a)) ~= nil then count("faces") end
        end
    end
    if o.phase ~= "hold" then
        o.phase = "hold"
        count("holds")
    end
    if A.gestureOf(id) ~= "guard" then A.setGesture(id, "guard") end
end

-- ---------------------------------------------------------------- tir (LK06-T03)

-- Ligne de tir entre le corps z et le joueur p : LosUtil.lineClear (coordonnées entières, portes non ignorées), même
-- appel que LivingKnox.Senses.lineOfSight et IsoGameCharacter.CanSee (base perception.md). Rend vrai ou faux et le
-- résultat nommé (LosUtil.TestResults).
function Combat.lineOfFire(z, p)
    if LosUtil == nil or LosUtil.lineClear == nil then return false, "no LosUtil" end
    local r = tostring(LosUtil.lineClear(getCell(), math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()),
        math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), false))
    return cfg().LINE_OF_FIRE[r] == true, r
end

-- LK06-T08 (fiche zombies.md, « Vitres et portes ») : fenêtres traversées par la ligne de a à b.
-- Fenêtre (IsoWindow) du bord commun de deux cases voisines du niveau lv (diagonale : par l'une des deux cases
-- d'angle), ou nil.
local function edgeWindow(cell, ax, ay, bx, by, lv)
    local sa = cell:getGridSquare(ax, ay, lv)
    if sa == nil then return nil end
    if ax ~= bx and ay ~= by then
        for _, c in ipairs({ { bx, ay }, { ax, by } }) do
            local sc = cell:getGridSquare(c[1], c[2], lv)
            if sc ~= nil then
                local w = sa:getWindowTo(sc)
                if w == nil then
                    local sb = cell:getGridSquare(bx, by, lv)
                    if sb ~= nil then w = sc:getWindowTo(sb) end
                end
                if w ~= nil then return w end
            end
        end
        return nil
    end
    local sb = cell:getGridSquare(bx, by, lv)
    if sb == nil then return nil end
    return sa:getWindowTo(sb)
end

-- Première fenêtre (IsoWindow) sur la ligne des cases de a à b (même niveau, pas d'une case sur l'axe principal),
-- ou nil.
function Combat.windowOnLine(a, b)
    local cell = getCell()
    if cell == nil then return nil end
    local x0, y0, lv = math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ())
    local x1, y1 = math.floor(b:getX()), math.floor(b:getY())
    local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
    local px, py = x0, y0
    for i = 1, n do
        local x = math.floor(x0 + (x1 - x0) * i / n + 0.5)
        local y = math.floor(y0 + (y1 - y0) * i / n + 0.5)
        if x ~= px or y ~= py then
            local w = edgeWindow(cell, px, py, x, y, lv)
            if w ~= nil then return w end
        end
        px, py = x, y
    end
    return nil
end

-- Vrai si la fenêtre w empêche un coup de mêlée : vitre fermée intacte, ou barricadée (IsoWindow.isBlocked,
-- J/iso/objects/IsoWindow.java:1120-1122).
function Combat.windowBlocks(w)
    if w:isBarricaded() then return true end
    return not w:isDestroyed() and not w:IsOpen()
end

-- Ligne de coup de mêlée entre le corps z et la cible p, règle vanilla de CombatManager (J/CombatManager.java:1582,
-- 1635 : ni Blocked ni ClearThroughClosedDoor, ni fenêtre bloquée du bord commun, isWindowBlockedTo) : à travers une
-- fenêtre ouverte ou cassée et non barricadée seulement. Rend vrai ou faux et le résultat nommé.
function Combat.lineOfStrike(z, p)
    if LosUtil == nil or LosUtil.lineClear == nil then return false, "no LosUtil" end
    local r = tostring(LosUtil.lineClear(getCell(), math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()),
        math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), false))
    if cfg().LINE_OF_STRIKE[r] ~= true then return false, r end
    local sa, sb = z:getCurrentSquare(), p:getCurrentSquare()
    if sa ~= nil and sb ~= nil and sa ~= sb and math.abs(sa:getX() - sb:getX()) <= 1
        and math.abs(sa:getY() - sb:getY()) <= 1 and sb:isWindowBlockedTo(sa) then
        return false, "ClosedWindow"
    end
    if r == "ClearThroughWindow" then
        local w = Combat.windowOnLine(z, p)
        if w == nil or Combat.windowBlocks(w) then return false, "ClosedWindow" end
    end
    return true, r
end

-- Vrai si la cible p est vue par z derrière une vitre fermée ou une porte vitrée fermée (ligne de vue sans ligne de
-- coup) : le PNJ de mêlée attend à la vitre au lieu de contourner (Combat.step).
function Combat.behindGlass(z, p)
    if LosUtil == nil or LosUtil.lineClear == nil then return false end
    local r = tostring(LosUtil.lineClear(getCell(), math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()),
        math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), false))
    if r == "ClearThroughClosedDoor" then return true end
    if r ~= "ClearThroughWindow" then return false end
    local w = Combat.windowOnLine(z, p)
    return w == nil or Combat.windowBlocks(w)
end

-- Tir à travers une vitre fermée : vitre cassée avant la touche, comme CombatManager.smashWindowBetween
-- (J/CombatManager.java:682-684, 2322-2331 : IsoWindow.smashWindow, son, bruit et envoi aux clients par le serveur,
-- J/iso/objects/IsoWindow.java:261-296) ; PNJ id, corps z, cible p. Rend la fenêtre cassée ou nil.
function Combat.smashWindowOnLine(id, z, p)
    local w = Combat.windowOnLine(z, p)
    if w == nil or w:isDestroyed() or w:IsOpen() then return nil end
    w:smashWindow()
    count("windowsSmashed")
    local sq = w:getSquare()
    log().info("npc %s shot through a closed window at %d,%d,%d: glass broken", id, sq:getX(), sq:getY(), sq:getZ())
    return w
end

-- Chance de toucher (0..100) d'un tir de l'arme w à d cases : portage simplifié de
-- CombatManager.calculateHitChanceData (J/CombatManager.java:2036-2075, 2134-2215) : min(HitChance, 95) +
-- AimingPerkHitChanceModifier x Visée + meilleur des deux termes de distance (sans viseur : bout portant et chute ;
-- zone de visée MinSightRange x (1 - Visée/30) à MaxSightRange x (1 + Visée/30) : bonus gaussien, chute au-delà),
-- sans temps de visée, mouvement, météo, lumière, moodles ni douleur ; tronquée, bornée à [5, 100].
function Combat.hitChance(w, d)
    local k = cfg().HIT
    local aim = cfg().AIM_LEVEL
    local chance = math.min(w:getHitChance(), k.MAX_START) + w:getAimingPerkHitChanceModifier() * aim
    local pb = k.POINT_BLANK_DISTANCE
    local sightless = 0
    if d > pb then
        sightless = (pb - d) * (k.SIGHTLESS_BASE + (pb - d) * -k.POINT_BLANK_DROP_OFF)
    elseif d < pb then
        sightless = (pb - d) / pb * k.POINT_BLANK_BONUS
    end
    local lo = w:getMinSightRange() * (1 - aim / 30)
    local hi = w:getMaxSightRange() * (1 + aim / 30)
    local sights
    if d < lo then
        sights = 0
        if d > pb then sights = (d - lo) * (k.OPTIMAL_DROP_OFF + (d - lo) * -k.OPTIMAL_DROP_OFF_INCREMENT) end
    elseif d > hi then
        sights = -((d - hi) * (k.OPTIMAL_DROP_OFF + (d - hi) * k.OPTIMAL_DROP_OFF_INCREMENT))
    else
        local mid = lo + (hi - lo) * 0.5
        local w2 = 2 * ((hi - lo) / 7)
        sights = w2 > 0 and k.OPTIMAL_BONUS * math.exp(-((d - mid) * (d - mid)) / (w2 * w2)) or k.OPTIMAL_BONUS
    end
    chance = chance + math.max(sightless, sights)
    if chance >= 0 then chance = math.floor(chance) else chance = math.ceil(chance) end   -- (int), vers zéro
    return math.max(k.MIN, math.min(k.MAX, chance))
end

-- Tirage reproductible 0..99 du tir numéro k de l'ordre c du PNJ id (générateur de Park et Miller, sans opérateur
-- binaire ; quotients sous 2^31 : % de Kahlua exact, base kahlua-lua.md).
function Combat.roll(id, c, k)
    local m = 2147483647
    local s = 7
    local text = tostring(id)
    for i = 1, #text do s = (s * 31 + string.byte(text, i)) % m end
    s = (s + c * 7919 + k * 104729) % m
    if s == 0 then s = 1 end
    for _ = 1, 3 do s = (s * 16807) % m end
    return s % 100
end

local function setG(id, g)
    local A = Anim()
    if A.gestureOf(id) ~= g then A.setGesture(id, g) end
end

local function faceTarget(id, o, z, p, force)
    local a = angleTo(p:getX() - z:getX(), p:getY() - z:getY())
    if a ~= nil and (force or o.faced == nil or angleGap(a, o.faced) >= cfg().FACE_DELTA) then
        o.faced = a
        if noteIssued(id, D().face(id, a)) ~= nil then count("faces") end
    end
end

-- Durée du rechargement de l'ordre o selon le plan d'Ammo (une boucle du clip, deux pour des cartouches libres).
function Combat.reloadMs(o, plan)
    local c = cfg()
    local ms = o.h and c.RELOAD_MS.rifle or c.RELOAD_MS.handgun
    if plan == LivingKnox.Ammo.PLAN_ROUNDS then ms = ms * c.RELOAD_ROUNDS_LOOPS end
    return ms
end

-- Fin de l'ordre o, nouvel engagement contre la même cible avec l'arme du moment (Combat.weaponOf).
local function rearm(id, o, why)
    local target, source = o.u, o.source
    if o.k == Combat.KIND_ZOMBIE then target = o.zt end   -- cible zombie : l'objet (la clé n'est pas un compte)
    Combat.disengage(id, why)
    Combat.engage(id, target, { source = source, why = why, leash = o.leash })
end

-- Plus aucune munition : fin de l'ordre de tir, nouvel engagement contre la même cible (mêlée à mains nues).
local function outOfAmmo(id, o)
    count("outOfAmmo")
    log().info("npc %s: out of ammo for %s, melee instead", id, o.t)
    rearm(id, o, "out of ammo")
end

-- Pas d'un ordre de tir (voir l'en-tête). z, p : corps et cible ; d : distance ; t : horloge.
local function rangedStep(id, o, z, p, d, t)
    local Am = LivingKnox.Ammo
    local spec = Am.spec(o.t)
    local loaded = Am.loaded(z, o.t)
    if o.phase == "reload" then
        if t < o.reloadUntil then return end
        loaded = Am.reload(id, z, o.t)
        o.reloadUntil = nil
        o.reloads = o.reloads + 1
        o.phase = "approach"
        count("reloads")
    end
    if spec == nil or loaded < spec.per then
        local plan = spec ~= nil and Am.plan(z, o.t) or nil
        if plan == nil then
            outOfAmmo(id, o)
            return
        end
        o.phase = "reload"
        o.reloadUntil = t + Combat.reloadMs(o, plan)
        faceTarget(id, o, z, p, true)   -- remplace une marche en cours : rechargement sur place
        setG(id, "reload")
        log().info("npc %s: reloading %s (%s, %d ms)", id, o.t, plan, o.reloadUntil - t)
        return
    end
    local clear = false
    if math.floor(p:getZ()) == math.floor(z:getZ()) and d <= o.reach and p:getVehicle() == nil then
        clear = Combat.lineOfFire(z, p)
    end
    if not clear then
        approach(id, o, p, t)
        return
    end
    local aiming = o.phase == "aim" or o.phase == "shoot"
    faceTarget(id, o, z, p, not aiming)
    if not aiming then
        o.phase = "aim"
        o.aimSince = t
    elseif o.phase == "aim" and t - o.aimSince >= cfg().AIM_MS then
        o.phase = "shoot"
        count("volleys")
    end
    setG(id, o.phase)   -- après "face", qui remet le repos
end

-- Un pas de l'engagement du PNJ id (autorité). Rend la phase ("approach", "strike", "aim", "shoot", "reload") ou nil
-- (fin).
function Combat.step(id)
    local o = Combat.orders[id]
    if o == nil then return nil end
    local B = Bodies()
    local z = B and B.find(id)
    if z == nil or z:isDead() then
        Combat.disengage(id, "no body")
        return nil
    end
    local H = LivingKnox.Health
    if H ~= nil and H.decided ~= nil and H.decided[id] then
        Combat.disengage(id, "npc dying")
        return nil
    end
    local p = Combat.targetOf(o)
    if p == nil then
        Combat.disengage(id, "target gone")
        return nil
    end
    if p:isDead() then
        Combat.disengage(id, "target dead")
        return nil
    end
    local dx, dy = p:getX() - z:getX(), p:getY() - z:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d > cfg().GIVE_UP then
        Combat.disengage(id, string.format("target too far (%.1f squares)", d))
        return nil
    end
    local lh = o.leash   -- LK05-T09 : défense du foyer, aucune approche hors de la laisse du poste
    if lh ~= nil and (math.floor(p:getZ()) ~= lh.z or math.max(math.abs(math.floor(p:getX()) - lh.x),
        math.abs(math.floor(p:getY()) - lh.y)) > lh.r) then
        -- Cible hors de la laisse : frappe à portée ou tir dégagé seulement, jamais d'approche.
        local reach = math.floor(p:getZ()) == math.floor(z:getZ()) and d <= o.reach and p:getVehicle() == nil
        if not reach or (o.m == Combat.RANGED and not Combat.lineOfFire(z, p)) then
            Combat.disengage(id, "target out of the defense leash")
            return nil
        end
    end
    if not o.bare then   -- LK07-T08 : arme changée (remplacée par un autre mod) : nouvel ordre avec celle portée
        local E = LivingKnox.Equipment
        local w = E ~= nil and E.wantedOf ~= nil and E.wantedOf(id) or nil
        if w == nil or w.t ~= o.t then
            count("rearmed")
            log().info("npc %s: weapon %s changed to %s, new order", id, o.t, tostring(w and w.t or "none"))
            rearm(id, o, "weapon changed")
            local cur = Combat.orders[id]
            return cur and cur.phase
        end
    end
    if o.m == Combat.RANGED then
        rangedStep(id, o, z, p, d, now())
        local cur = Combat.orders[id]   -- plus de munition : remplacé par un ordre de mêlée
        return cur and cur.phase
    end
    local same = math.floor(p:getZ()) == math.floor(z:getZ()) and p:getVehicle() == nil
    if same and d <= o.reach and Combat.lineOfStrike(z, p) then
        strike(id, o, z, p)
    elseif same and not (lh ~= nil and lh.around) and Combat.behindGlass(z, p) then
        hold(id, o, z, p)   -- LK06-T08 (LK06-T14 : sortie de défense, leash.around : chemin par une porte)
    else
        approach(id, o, p, now())
    end
    return o.phase
end

-- ---------------------------------------------------------------- touches

Combat.SUSPECT = { ["not the owner"] = true, ["out of reach"] = true, ["too fast"] = true, ["other level"] = true,
    ["wrong target"] = true, ["bad report"] = true }

-- Nom du rapport dans le journal : touche de mêlée ou tir (ordre de tir en cours du PNJ).
local function what(id)
    local o = Combat.orders[id]
    if o ~= nil and o.m == Combat.RANGED then return "shot" end
    return "melee hit"
end

local function note(name, id, reason, detail)
    local key = tostring(name) .. "|" .. reason
    local last = Combat.warned[key]
    if last ~= nil and now() - last < cfg().WARN_EVERY_MS then return end
    Combat.warned[key] = now()
    -- Rapport « à l'aveugle » (nf, LK05-T18 : cible absente chez l'expéditeur) : écart de position attendu, sans WARN.
    local say = (Combat.SUSPECT[reason] and not Combat.blindReport) and log().warn or log().info
    say("%s of npc %s reported by %s refused: %s%s%s", what(id), tostring(id), tostring(name), reason,
        detail and (" (" .. detail .. ")") or "", Combat.blindReport and ", target not seen by the sender" or "")
end

local function refuse(name, id, reason, detail)
    local st = Combat.stats
    st.refused = st.refused + 1
    st.why[reason] = (st.why[reason] or 0) + 1
    note(name, id, reason, detail)
    return false, reason
end

-- Course attendue (rapport d'un ordre remplacé, doublon, ancien propriétaire) : ignoré, sans avertissement.
local function ignore(id, reason, stat)
    count("ignored")
    if stat ~= nil then count(stat) end
    Combat.stats.why[reason] = (Combat.stats.why[reason] or 0) + 1
    log().debug("%s of npc %s ignored: %s", what(id), tostring(id), reason)
    return false, reason
end

-- Dommages au joueur p, une fois, par le chemin vanilla des coups entre joueurs (voir l'en-tête).
function Combat.applyToPlayer(id, o, p)
    local w = weaponItem(o.t)
    if w == nil then return false end
    p:getBodyDamage():DamageFromWeapon(w, -1)
    if isServer() then sendDamage(p) end
    return true
end

-- Coup accepté sur une cible zombie (LK06-T04) : LivingKnox.Zombies.hurt (dégâts vanilla reproductibles, mort décidée
-- une fois par l'autorité). Rend vrai si appliqué.
function Combat.applyToZombie(id, o, target)
    local Zm = LivingKnox.Zombies
    if Zm == nil or Zm.hurt == nil or target == nil then
        count("zombieUnhandled")
        log().debug("npc %s: hit on a zombie not applied (LivingKnox.Zombies missing)", id)
        return false
    end
    return (Zm.hurt(id, o, target, weaponItem(o.t)))
end

-- Coup accepté sur la cible p de l'ordre o : joueur ou zombie. Rend vrai si appliqué.
function Combat.applyTo(id, o, p)
    if o.k == Combat.KIND_ZOMBIE then return Combat.applyToZombie(id, o, p) end
    return Combat.applyToPlayer(id, o, p)
end

-- Multiplicateur sandbox du bruit des armes à feu (ISReloadWeaponAction.attackHook), 1 par défaut.
local function noiseMultiplier()
    local so = getSandboxOptions ~= nil and getSandboxOptions() or nil
    local opt = so ~= nil and so:getOptionByName("FirearmNoiseMultiplier") or nil
    local v = opt ~= nil and opt:getValue() or 1
    if not finite(v) or v < 0 then return 1 end
    return v
end

-- Effets d'un coup de feu du PNJ id (corps z, arme w) : bruit pour les zombies (autorité), son vanilla de l'arme et
-- éclair joués UNE fois par chaque client proche (même entrée, clé unique ; solo : appel direct). Rend l'entrée.
function Combat.shotEffects(id, o, z, w)
    local x, y, zz = z:getX(), z:getY(), z:getZ()
    local sq = z:getCurrentSquare()
    local r = w:getSoundRadius() * noiseMultiplier()
    if sq ~= nil and not sq:isOutside() then r = r * cfg().NOISE_INSIDE end
    if addSound ~= nil then
        addSound(nil, math.floor(x), math.floor(y), math.floor(zz), math.floor(r), math.floor(w:getSoundVolume()))
        count("noises")
    end
    local st = Combat.state
    st.shots = (st.shots or 0) + 1
    if st.session == nil then st.session = now() end
    local entry = { k = tostring(st.session) .. "-" .. st.shots, npc = id, o = z:getOnlineID(), x = x, y = y, z = zz,
        snd = w:getSwingSound() }
    if isServer() then
        local targets = D().targets ~= nil and D().targets(z) or {}
        local names = {}
        for n in pairs(targets) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            sendServerCommand(targets[n], Combat.MODULE, Combat.CMD_SHOT, { s = entry })
            count("shotMessages")
        end
    else
        local V = LivingKnox.CombatView
        if V ~= nil and V.onShot ~= nil then V.onShot(entry) end
    end
    return entry
end

-- LK06-T11 : impact d'un coup de mêlée accepté du PNJ id (ordre o, corps z, cible p) joué UNE fois par chaque client
-- proche (même relais que les coups de feu : Directives.targets, clé unique ; solo : appel direct de View.onMelee).
-- Aucun bruit pour les zombies (mêlée vanilla : SoundRadius 0). Rend l'entrée, ou nil si l'arme n'a aucun impact.
function Combat.meleeEffects(id, o, z, p)
    local A = Anim()
    local g = A ~= nil and A.gestureOf(id) or nil
    if not Combat.STRIKE_GESTURES[g] then g = Combat.strikeGesture(o, p) end
    local hit = Combat.impactSound(weaponItem(o.t), g)
    if hit == nil then
        count("meleeSilent")
        return nil
    end
    local st = Combat.state
    st.melee = (st.melee or 0) + 1
    if st.session == nil then st.session = now() end
    local entry = { k = "m" .. tostring(st.session) .. "-" .. st.melee, npc = id, o = z:getOnlineID(), x = z:getX(),
        y = z:getY(), z = z:getZ(), sw = g == "stomp" and Combat.STOMP_SOUND or o.sw, hit = hit }
    count("meleeSounds")
    if isServer() then
        local targets = D().targets ~= nil and D().targets(z) or {}
        local names = {}
        for n in pairs(targets) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            sendServerCommand(targets[n], Combat.MODULE, Combat.CMD_MELEE, { m = entry })
            count("meleeMessages")
        end
    else
        local V = LivingKnox.CombatView
        if V ~= nil and V.onMelee ~= nil then V.onMelee(entry) end
    end
    return entry
end

-- Tir accepté par onHit (contrôles faits) : une cartouche retirée de l'arme AVANT tout effet (sinon refus), effets,
-- puis touche décidée ici (Combat.hitChance, Combat.roll). Rend vrai si le joueur p est touché.
function Combat.fire(name, id, o, z, p, d, t)
    local Am = LivingKnox.Ammo
    if not Am.consume(z, o.t) then return refuse(name, id, "no ammo") end
    local w = weaponItem(o.t)
    o.lastHitMs = t
    o.shots = o.shots + 1
    count("shots")
    Combat.shotEffects(id, o, z, w)
    Combat.smashWindowOnLine(id, z, p)   -- LK06-T08 : vitre fermée sur la ligne de tir
    local chance = Combat.hitChance(w, d)
    local roll = Combat.roll(id, o.c, o.shots)
    local hit = roll <= chance
    if hit then
        Combat.applyTo(id, o, p)
        o.hits = o.hits + 1
        count("hits")
        count("applied")
    else
        count("misses")
    end
    log().info("npc %s shot at %s with %s (ranged #%d, shot %d, %.2f squares, chance %d, roll %d: %s, %d round(s) left, "
        .. "reported by %s%s)", id, label(o), o.t, o.c, o.shots, d, chance, roll, hit and "hit" or "missed",
        Am.loaded(z, o.t), name, Combat.blindReport and ", target not seen there" or "")
    return hit, hit and "hit" or "missed"
end

-- Touche rapportée. player : expéditeur (serveur : joueur de la connexion ; solo : joueur local). Rend vrai si les
-- dommages ont été appliqués, sinon faux et la raison.
function Combat.onHit(player, args)
    if not LivingKnox.isAuthority() then return false, "not the authority" end
    count("reports")
    -- LK05-T18 : rapport d'une touche sur un zombie absent chez l'expéditeur (nf, LK_CombatClient.lua) : mêmes
    -- contrôles sur les copies de l'autorité ; seulement compté et journalisé à part.
    Combat.blindReport = type(args) == "table" and args.nf == true or nil
    if Combat.blindReport then count("blindReports") end
    local name = isServer() and nameOf(player) or "local"
    if type(args) ~= "table" or type(args.id) ~= "string" or type(args.c) ~= "number" or type(args.n) ~= "number"
        or type(args.u) ~= "string" then
        return refuse(name, type(args) == "table" and args.id or "?", "bad report")
    end
    local id = args.id
    local o = Combat.orders[id]
    if o == nil then return ignore(id, "no combat order", "stale") end
    if args.c ~= o.c then return ignore(id, "older combat order", "stale") end
    local B = Bodies()
    local z = B and B.find(id)
    if z == nil or z:isDead() then return ignore(id, "no body") end
    local H = LivingKnox.Health
    if H ~= nil and H.decided ~= nil and H.decided[id] then return ignore(id, "npc dying") end
    if isServer() and not D().isOwner(z, player) then
        if D().isPreviousOwner(id, name) then return ignore(id, "previous owner") end
        return refuse(name, id, "not the owner")
    end
    local last = o.lastN[name]
    if last ~= nil and args.n <= last then return ignore(id, "duplicate", "duplicates") end
    o.lastN[name] = args.n   -- avant les autres contrôles : un rapport refusé n'est jamais rejoué
    if args.u ~= o.u then return refuse(name, id, "wrong target", tostring(args.u) .. " instead of " .. o.u) end
    local p = Combat.targetOf(o)   -- joueur, ou zombie (LK06-T04) : mêmes contrôles
    if p == nil then return refuse(name, id, "target gone") end
    if p:isDead() then return refuse(name, id, "target dead") end
    if p:getVehicle() ~= nil then return refuse(name, id, "target in a vehicle") end
    local ranged = o.m == Combat.RANGED
    if ranged and o.phase ~= "shoot" then return refuse(name, id, "not shooting") end
    if not ranged and o.phase ~= "strike" then return refuse(name, id, "not striking") end
    local dz = math.abs(math.floor(p:getZ()) - math.floor(z:getZ()))
    if dz > 0 then return refuse(name, id, "other level", string.format("%d levels", dz)) end
    local dx, dy = p:getX() - z:getX(), p:getY() - z:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    local reach = o.reach + cfg().REACH_SLACK
    if d > reach then
        return refuse(name, id, "out of reach", string.format("%.2f squares, reach %.2f", d, reach))
    end
    if ranged then
        local clear, res = Combat.lineOfFire(z, p)
        if not clear then return refuse(name, id, "no line of fire", tostring(res)) end
    else
        local clear, res = Combat.lineOfStrike(z, p)   -- LK06-T08 : vitre fermée, porte fermée, mur
        if not clear then return refuse(name, id, "no line of strike", tostring(res)) end
    end
    local t = now()
    if o.lastHitMs ~= nil and t - o.lastHitMs < o.iv * cfg().CADENCE_MIN then
        return refuse(name, id, "too fast", string.format("%d ms after the previous hit", t - o.lastHitMs))
    end
    if ranged then return Combat.fire(name, id, o, z, p, d, t) end
    if not Combat.applyTo(id, o, p) then return refuse(name, id, "not applied") end
    o.lastHitMs = t
    o.hits = o.hits + 1
    count("applied")
    Combat.meleeEffects(id, o, z, p)   -- LK06-T11 : impact entendu par les clients proches
    log().info("npc %s hit %s with %s (melee #%d, hit %d, %.2f squares, reported by %s%s)", id, label(o),
        o.bare and "bare hands" or o.t, o.c, o.hits, d, name, Combat.blindReport and ", target not seen there" or "")
    return true
end

-- ---------------------------------------------------------------- diffusion (serveur MP)

local function wire(o)
    return { r = o.r, c = o.c, u = o.u, k = o.k, m = o.m, rc = o.reach, iv = o.iv, im = o.im, zo = o.zo, sw = o.sw }
end

local function holder(name, p)
    local s = Combat.sent[name]
    if s == nil then
        s = { p = p, ids = {} }
        Combat.sent[name] = s
    end
    s.p = p
    return s
end

-- Fin d'un ordre : { gone } aux clients qui le détiennent (serveur).
function Combat.gone(id)
    if not isServer() then return 0 end
    local st = Combat.state
    local n = 0
    for _, s in pairs(Combat.sent) do
        if s.ids[id] ~= nil then
            st.r = st.r + 1
            local d = {}
            d[id] = { r = st.r, gone = true }
            sendServerCommand(s.p, Combat.MODULE, Combat.CMD_STATE, { d = d })
            s.ids[id] = nil
            count("messages")
            n = n + 1
        end
    end
    return n
end

-- Passage d'envoi : ordres courants aux destinataires qui n'ont pas la révision courante. Rend le nombre de messages.
function Combat.sendPass()
    if not isServer() then return 0 end
    local B = Bodies()
    local Dir = D()
    if B == nil or Dir == nil or Dir.targets == nil then return 0 end
    local batch = {}
    for id, o in pairs(Combat.orders) do
        local z = B.find(id)
        if z ~= nil then
            for name, p in pairs(Dir.targets(z)) do
                local s = Combat.sent[name]
                if s == nil or s.ids[id] ~= o.r then
                    local b = batch[name]
                    if b == nil then
                        b = { p = p, d = {} }
                        batch[name] = b
                    end
                    b.d[id] = wire(o)
                end
            end
        end
    end
    local n = 0
    for name, b in pairs(batch) do
        sendServerCommand(b.p, Combat.MODULE, Combat.CMD_STATE, { d = b.d })
        local s = holder(name, b.p)
        for id, e in pairs(b.d) do s.ids[id] = e.r end
        count("messages")
        n = n + 1
    end
    return n
end

-- Entrée en partie d'un client ("guardHello") : tout lui est renvoyé au passage suivant.
function Combat.onHello(player)
    Combat.sent[nameOf(player)] = nil
end

-- OnTick (autorité) : un passage au plus par PASS_MS.
function Combat.tick()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    local st = Combat.state
    local t = now()
    if st.lastPass ~= nil and t - st.lastPass < cfg().PASS_MS then return end
    st.lastPass = t
    local ids = {}
    for id in pairs(Combat.orders) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do Combat.step(id) end
    Combat.sendPass()
end

-- État d'un engagement (copie), ou nil : { c, u, k, m, t, bare, reach, iv, phase, hits, shots, reloads, source, zo,
-- sw }.
function Combat.get(id)
    local o = Combat.orders[id]
    if o == nil then return nil end
    return { c = o.c, u = o.u, k = o.k, m = o.m, t = o.t, bare = o.bare, reach = o.reach, iv = o.iv, phase = o.phase,
        hits = o.hits, shots = o.shots, reloads = o.reloads, source = o.source, zo = o.zo, sw = o.sw }
end

-- Réinitialisation (nouvelle partie, tests).
function Combat.reset()
    Combat.orders, Combat.sent, Combat.warned = {}, {}, {}
    Combat.state = { seq = 0, r = 0, lastPass = nil, shots = 0 }
end

local function onTick()
    LivingKnox.Combat.tick()
end

LivingKnox.subscribe("OnTick", "Combat.tick", onTick)

if isServer() then
    require "LivingKnox/LK_ZombieGuard"
    local function onClientCommand(module, command, player, args)
        if module ~= Combat.MODULE or player == nil then return end
        if command == Combat.CMD_HIT then
            LivingKnox.Combat.onHit(player, args)
        elseif command == LivingKnox.ZombieGuard.CMD_HELLO then
            LivingKnox.Combat.onHello(player)
        end
    end
    LivingKnox.subscribe("OnClientCommand", "Combat.onClientCommand", onClientCommand)
end

return Combat
