-- Living Knox : PNJ contre zombies vanilla, dans les deux sens, côté autorité (LK06-T04). Fiche :
-- docs/annexes/conception/zombies.md. Java 42.21.0 cité en abrégé (J = zombie/...). Un client MP charge aussi ce fichier
-- (media/lua/server) : il n'y trouve que les constantes et les réglages ; la part du client propriétaire d'un zombie
-- est client/LivingKnox/LK_ZombiesClient.lua.
--
-- 1. Les PNJ repoussent et tuent les zombies.
--    Cible : tout membre (LK06-T07 : quel que soit son rôle ; un combattant d'abord sans cible joueur) prend pour
--    cible le zombie vanilla le plus proche à DEFEND_RANGE cases au plus, même niveau, en vue (LosUtil.lineClear dans
--    SIGHT : tout sauf Blocked, vitre et porte vitrée comprises, LK06-T08) sur les copies de l'autorité
--    (Zombies.targetFor, appelé par
--    Combat.targetFor pour un combattant, directement par LK_Decisions sinon : la cascade choisit alors « fight » si
--    le membre a des constantes bonnes, Decisions.unfitOf). Un zombie vanilla = zombie vivant de la cellule, ni corps de PNJ (tag
--    du registre), ni « useless » (corps d'un autre moteur), ni faux mort.
--    Mêlée ou tir : le chemin de LK_Combat (engagement, touche rapportée par le propriétaire du CORPS du PNJ,
--    contrôles du serveur sur ses copies) ; la touche acceptée arrive ici (Zombies.hurt, par Combat.applyToZombie).
--    Dégâts : calcul vanilla d'un coup sur un zombie, tirage reproductible (J/characters/IsoGameCharacter.java:
--    5709-5714 ; base combat-and-xp.md « Dégâts d'un coup d'arme sur un zombie ») : Rand(MinDamage, MaxDamage)
--    remplacé par Combat.roll, x NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER (1,5) x (0,3 + 0,1 x WEAPON_LEVEL), dès le
--    4e coup de mêlée sur le même zombie x (coups - 2) x 1,5, puis x 0,15 en mêlée (arme à feu : rien de plus).
--    Coup au sol (LK06-T09 ; zombie isOnFloor, non rampant, frappé en mêlée), comme l'attaque au sol du joueur :
--    arme : x max(5, CriticalDamageMultiplier de l'arme) (J/characters/IsoGameCharacter.java:5817-5821) ; mains
--    nues : piétinement, dégâts de base Rand(0,7, 1,0) + Force x 0,2, x puissance de piétinement des chaussures
--    (J/CombatManager.java:868-872 ; Force STRENGTH et chaussures STOMP_POWER prêtées), sans le x 5. Coup non mortel :
--    réaction vanilla « Floor » (setHitReaction, J/CombatManager.java:2410, 2433-2436 : le zombie reste à terre, état
--    hitreaction-onfloor puis onground et nouveau délai avant de se relever), posée sur la copie de l'autorité et, sur
--    un serveur, par le client qui simule le zombie (champ r de "zombieHurt").
--    Application, UNE fois et par une seule décision de mort :
--      - coup mortel (santé de la copie de l'autorité - dégâts <= 0) : la mort est décidée ici. Serveur :
--        setAttackedBy(corps du PNJ) + die() (la mort d'un zombie part toujours du serveur, paquet de mort vers tous
--        les clients ; J/characters/IsoGameCharacter.java:13478-13496) ; solo : Kill(arme, corps) ;
--      - coup non mortel : setHealth sur la copie de l'autorité ; sur un serveur dont un client simule le zombie, ce
--        client (getOwnerPlayer) reçoit "zombieHurt" { o, d } et abaisse SA copie (le paquet du propriétaire porte la
--        santé et écrase celle du serveur : base multiplayer.md « Santé d'un zombie en MP ») ; la valeur étant
--        absolue, les deux écritures ne s'additionnent jamais. Copie du client bornée à HURT_FLOOR : seul le
--        serveur décide la mort.
-- 2. Les zombies attaquent les PNJ par une interaction propre (aucun zombie vanilla ne cible un zombie : base
--    zombies-as-npc-bodies.md). Passage de l'autorité toutes les PASS_MS : un zombie vanilla debout (ou rampant) à
--    REACH cases au plus d'un corps de PNJ vivant (REACH_CRAWL rampant, comme AttackState,
--    J/ai/states/AttackState.java:186-190), même niveau, avec la ligne de coup vanilla (LK06-T08 :
--    LivingKnox.Combat.lineOfStrike, ni mur, ni porte fermée, ni vitre fermée ou barricadée), est « au contact » ;
--    première attaque WINDUP_MS après le
--    contact, puis une toutes les ATTACK_MS ; le contact rompu remet l'élan à zéro. Issue décidée par l'autorité
--    seule, de façon reproductible (Combat.roll : PNJ, zombie, numéro de l'attaque), sur le modèle de
--    BodyDamage.AddRandomDamageFromZombie (J/characters/BodyDamage/BodyDamage.java:1101-1220) : coup évité si le
--    tirage <= AVOID - (attaquants - 1) x AVOID_EXTRA, sinon griffure, lacération si un second tirage dépasse
--    LACERATION - (attaquants - 1) x LACERATION_EXTRA, morsure si un troisième dépasse BITE - ... ; dégâts =
--    DAMAGE[issue] x santé de naissance du PNJ, retirés par LivingKnox.Health.applyHit (blessure notée, mort
--    décidée une fois par Health.kill avec le zombie pour attaquant). Même issue chez tous les clients : ils ne
--    reçoivent que la santé de référence (commande "npcHealth" de LK_Health) et, à la mort, le paquet vanilla.
--    Infection et transformation (I6.10) : non traitées (fiche, points ouverts).
-- 3. Attrait (LK06-T04, refait par LK06-T08) : un zombie ne repère jamais un corps de PNJ. Il vient par le bruit, que
--    le moteur ne prend en compte que si sa source n'est PAS un zombie (WorldSound.sourceIsZombie : getSoundAttract
--    rend 0 et getBiggestSoundZomb l'ignore, J/WorldSoundManager.java:230, 259-261, 478) : tout bruit de PNJ est
--    donc émis avec addSound(nil, ...) :
--    - vue : un PNJ vu par un zombie vanilla (LURE_RADIUS cases, même niveau, LosUtil.lineClear dans SIGHT : vitre
--      intacte non barricadée ni masquée par un rideau fermé, porte vitrée ou ouverte ; au plus LOS_TRIES zombies,
--      les plus proches) émet au plus toutes les LURE_MS un bruit à sa case, de rayon calculé pour que CE zombie
--      l'entende malgré l'atténuation vanilla (Zombies.lureRadius : pièces différentes x 1,2, dehors x 1,4,
--      multiplicateur d'ouïe du zombie, J/WorldSoundManager.java:256-277, 407-422) ;
--    - pas : un PNJ qui marche ou court (geste "walk" / "run" et corps déplacé d'au moins STEP_MIN_MOVE case) émet un
--      bruit de pas toutes les STEP_MS, rayon vanilla d'un joueur chaussé (DoFootstepSound :
--      ceil(allure x 1,4 x 10), moitié dans une pièce ; J/characters/IsoPlayer.java:6584-6619,
--      J/characters/IsoGameCharacter.java:5312-5358) ;
--    - tir et cri : LK_Combat (tir) et LK_Alert (cri) émettent déjà addSound(nil, ...) ; mêlée : aucun bruit, comme le
--      vanilla (SoundRadius 0 des armes de mêlée, J/characters/IsoLivingCharacter.java:126-129).
--    Le zombie qui suit un bruit (pathToSound) frappe la fenêtre, la porte ou la barricade qui lui barre le chemin
--    (IsoZombie.collideWith et tryThump, chasingSound, J/characters/IsoZombie.java:1076-1090, 3101-3110), puis la
--    franchit une fois cassée (ThumpState, J/ai/states/ThumpState.java:183-199) : aucun faux coup n'est écrit ici.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"

local Zombies = LivingKnox.Zombies or {}
LivingKnox.Zombies = Zombies

Zombies.MODULE = "LivingKnox"
Zombies.CMD_HURT = "zombieHurt"   -- serveur -> client qui simule le zombie : { o = onlineId, d = dégâts, r = réaction }
Zombies.KIND = "zombie"
Zombies.OUTCOMES = { "scratch", "laceration", "bite" }

-- Réglages (valeurs de départ, raisons dans la fiche ; lus à chaque appel).
LivingKnox.Config.ZOMBIES = LivingKnox.Config.ZOMBIES or {
    PASS_MS = 250,            -- passage de l'autorité (contacts, attaques, attrait)
    DEFEND_RANGE = 10,        -- cases : un membre prend pour cible le zombie le plus proche à cette distance
                              -- (LK06-T14 : 10, décision de l'utilisateur du 2026-10-13 ; avant : 5)
    -- Résultats de LosUtil.lineClear par lesquels on se voit (cible, attrait ; LK06-T08) : tout sauf Blocked, comme
    -- IsoGameCharacter.CanSee (vitre même fermée, porte vitrée ; rideau fermé, barricade de 3 planches ou plus,
    -- tôle et mur : Blocked).
    SIGHT = { Clear = true, ClearThroughOpenDoor = true, ClearThroughWindow = true, ClearThroughClosedDoor = true },
    LOS_TRIES = 3,            -- lignes de vue essayées au plus par recherche de cible
    REACH = 1.0,              -- cases : allonge d'un zombie debout (AttackState.java:186)
    REACH_CRAWL = 1.3,        -- cases : allonge d'un rampant (AttackState.java:189)
    WINDUP_MS = 1000,         -- première attaque après le contact
    ATTACK_MS = 2000,         -- attaques suivantes d'un même zombie
    AVOID = 15, AVOID_EXTRA = 10,             -- BodyDamage.java:1107, 1114 (baseChance)
    LACERATION = 65, LACERATION_EXTRA = 15,   -- BodyDamage.java:1109, 1116
    BITE = 85, BITE_EXTRA = 30,               -- BodyDamage.java:1108, 1115
    DAMAGE = { scratch = 0.05, laceration = 0.10, bite = 0.20 },   -- fraction de la santé de naissance du PNJ
    WEAPON_LEVEL = 3,         -- niveau d'arme prêté aux PNJ (dégâts sur un zombie)
    -- Coup au sol (LK06-T09).
    FLOOR_MIN_MULT = 5,       -- arme visée au sol : x max(FLOOR_MIN_MULT, CriticalDamageMultiplier)
    STRENGTH = 5,             -- Force prêtée aux PNJ (piétinement : + Force x 0,2)
    STOMP_POWER = 1.0,        -- puissance de piétinement prêtée (StompPower par défaut d'un vêtement : Item.java:392)
    FLOOR_REACTION = "Floor", -- réaction vanilla d'un coup au sol (HitReaction.FLOOR)
    HURT_FLOOR = 0.01,        -- santé minimale posée par le client propriétaire (la mort reste au serveur)
    LURE_RADIUS = 10,         -- cases : un zombie vanilla qui voit un PNJ à cette distance est attiré
    LURE_MS = 3000,           -- au plus un bruit d'attrait par PNJ dans ce délai
    LURE_VOLUME = 20,         -- volume du bruit d'attrait
    LURE_MARGIN = 1.25,       -- rayon d'attrait = distance x atténuation x LURE_MARGIN / ouïe + 1
    LURE_CAP = 40,            -- rayon d'attrait maximal
    STEP_MS = 1000,           -- au plus un bruit de pas par PNJ dans ce délai
    STEP_MIN_MOVE = 0.3,      -- cases parcourues depuis le bruit précédent pour un nouveau bruit de pas
    STEP_RADIUS = { walk = 7, run = 11 },   -- ceil(0,5 / 0,75 x 1,4 x 10) : joueur chaussé qui marche / court
    STEP_INSIDE = 0.5,        -- rayon des pas dans une pièce (IsoGameCharacter.java:5346-5348)
    HITS_KEPT = 256,          -- compteurs de coups par zombie gardés au plus
}

if isClient() then return Zombies end

require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Health"
require "LivingKnox/LK_Combat"

Zombies.contacts = Zombies.contacts or {}   -- "<npcId>|<clé zombie>" -> { id, key, since, n, next }
Zombies.hitsOn = Zombies.hitsOn or {}       -- clé zombie -> coups de mêlée de PNJ reçus (hausse vanilla)
Zombies.serials = Zombies.serials or {}     -- objet zombie -> numéro (solo : onlineId -1)
Zombies.lured = Zombies.lured or {}         -- npcId -> heure du dernier bruit d'attrait
Zombies.steps = Zombies.steps or {}         -- npcId -> { x, y, t } position et heure du dernier relevé de pas
Zombies.state = Zombies.state or { serial = 0, lastPass = nil, hitsKept = 0 }
Zombies.stats = Zombies.stats or { passes = 0, contacts = 0, attacks = 0, avoided = 0, scratch = 0, laceration = 0,
    bite = 0, deaths = 0, lures = 0, hits = 0, kills = 0, hurtMessages = 0, targets = 0 }
Zombies.stats.steps = Zombies.stats.steps or 0   -- LK06-T08

local function cfg() return LivingKnox.Config.ZOMBIES end
local function log() return LivingKnox.Log end
local function Bodies() return LivingKnox.Bodies end
local function Health() return LivingKnox.Health end

local function now() return getTimestampMs() end
local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function count(name, n)
    local st = Zombies.stats
    st[name] = (st[name] or 0) + (n or 1)
end

-- ---------------------------------------------------------------- reconnaître un zombie vanilla

-- Numéro d'un zombie : identifiant réseau (serveur MP), sinon numéro tenu ici (solo : onlineId -1).
function Zombies.numberOf(z)
    local o = z:getOnlineID()
    if finite(o) and o >= 0 then return o end
    local s = Zombies.serials[z]
    if s == nil then
        local st = Zombies.state
        st.serial = st.serial + 1
        s = 100000 + st.serial
        Zombies.serials[z] = s
    end
    return s
end

-- Clé stable d'un zombie dans la session : "z:<onlineId>" (MP), "z@<numéro>" (solo).
function Zombies.keyOf(z)
    local o = z:getOnlineID()
    if finite(o) and o >= 0 then return "z:" .. tostring(o) end
    return "z@" .. tostring(Zombies.numberOf(z))
end

-- Vrai si z est un corps de PNJ (tag du registre) ou le corps d'un autre moteur (useless).
function Zombies.isBody(z)
    if z:isUseless() then return true end
    if z:hasModData() and LivingKnox.Identity.readTag(z:getModData()) then return true end
    return false
end

-- Zombie vanilla vivant, chargé, ni corps ni faux mort. Rend vrai, ou faux et la raison.
function Zombies.isVanilla(z)
    if z == nil or not instanceof(z, "IsoZombie") then return false, "not a zombie" end
    if z:isDead() then return false, "dead" end
    if z:isFakeDead() then return false, "fake dead" end
    if Zombies.isBody(z) then return false, "npc body" end
    return true
end

-- Vrai si z est encore dans la liste des zombies de la cellule.
function Zombies.inWorld(z)
    local cell = getCell()
    return cell ~= nil and cell:getZombieList():contains(z)
end

-- Vrai si a voit b (LosUtil.lineClear dans SIGHT), et le résultat nommé.
function Zombies.sees(a, b)
    if LosUtil == nil or LosUtil.lineClear == nil then return false, "no LosUtil" end
    local r = tostring(LosUtil.lineClear(getCell(), math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ()),
        math.floor(b:getX()), math.floor(b:getY()), math.floor(b:getZ()), false))
    return cfg().SIGHT[r] == true, r
end

local function lineClear(a, b) return (Zombies.sees(a, b)) end

local function sameLevel(a, b) return math.floor(a:getZ()) == math.floor(b:getZ()) end

local function distance(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------- cible d'un combattant

-- Rôle du membre dont le PNJ est npcId (registre des groupes, lecture en place), ou nil.
function Zombies.roleOf(npcId)
    local G = LivingKnox.Groups
    if npcId == nil or G == nil or G.findNpc == nil or G.peek == nil then return nil end
    local gid, mid = G.findNpc(npcId)
    local g = gid ~= nil and G.peek(gid) or nil
    local m = g ~= nil and g.members ~= nil and g.members[mid] or nil
    return m ~= nil and m.role or nil
end

-- Portée d'engagement (cases) du PNJ npcId (ou du rôle role) : option de son rôle (LK06-T14,
-- Config.zombieEngageOption : ZombieEngage<Rôle>, rôle inconnu ou PNJ hors groupe : fighter ; repli DEFEND_RANGE),
-- jamais au-delà de Config.zombieAlertDistance() (un zombie ignoré par l'alerte ne devient pas une cible).
function Zombies.engageRange(npcId, role)
    local C = LivingKnox.Config
    if role == nil then role = Zombies.roleOf(npcId) end
    local range = C.danger(C.zombieEngageOption(role), cfg().DEFEND_RANGE)
    local zmax = C.zombieAlertDistance()
    if zmax ~= nil and zmax < range then return zmax end
    return range
end

-- Zombie vanilla que le PNJ npcId doit repousser : le plus proche à Zombies.engageRange(npcId) cases, même niveau, ligne
-- dégagée. Rend { kind = "zombie", u = clé, d, reason, zombie } ou nil. Lecture seule.
function Zombies.targetFor(npcId)
    if not LivingKnox.isAuthority() then return nil end
    local B = Bodies()
    local body = B and B.find(npcId)
    if body == nil or body:isDead() then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local list = cell:getZombieList()
    local range = Zombies.engageRange(npcId)
    local cands = {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and z ~= body and math.abs(z:getX() - body:getX()) <= range
            and math.abs(z:getY() - body:getY()) <= range and sameLevel(z, body) and Zombies.isVanilla(z) then
            local d = distance(z, body)
            if d <= range then cands[#cands + 1] = { z = z, d = d, key = Zombies.keyOf(z) } end
        end
    end
    table.sort(cands, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    for i = 1, math.min(#cands, cfg().LOS_TRIES) do
        local c = cands[i]
        if lineClear(body, c.z) then
            count("targets")
            return { kind = Zombies.KIND, u = c.key, d = c.d, reason = "zombie", zombie = c.z }
        end
    end
    return nil
end

-- ---------------------------------------------------------------- coups des PNJ sur un zombie

local function combat(key, default)
    local ok, v = pcall(function() return getCombatConfig():get(CombatConfigKey[key]) end)
    if ok and finite(v) then return v end
    return default
end

-- Vrai si le zombie z est au sol pour un coup de mêlée (LK06-T09) : isOnFloor, non rampant (un rampant se frappe
-- debout, isProne faux).
-- MP : la chute vue par le client qui simule le zombie compte aussi (LivingKnox.Senses.onFloor, LK06-T11).
function Zombies.isDown(z)
    local S = LivingKnox.Senses
    if S ~= nil and S.onFloor ~= nil then return S.onFloor(z) end
    return z:isOnFloor() and not z:isCrawling()
end

-- Dégâts du coup numéro hits (coups de mêlée de PNJ reçus par ce zombie, celui-ci compris) de l'arme w, ordre o du
-- PNJ id ; tirage reproductible. floor (LK06-T09) : coup au sol (arme x max(5, critique) ; mains nues : piétinement).
-- Voir l'en-tête.
function Zombies.damageOf(id, o, w, hits, floor)
    local c = cfg()
    local roll = LivingKnox.Combat.roll(id, o.c, 1000 + hits)
    local melee = not w:isRanged()
    local stomp = floor and melee and w:getFullType() == LivingKnox.Combat.BARE_HANDS
    local v
    if stomp then   -- J/CombatManager.java:868-872
        v = (0.7 + 0.3 * roll / 99 + c.STRENGTH * 0.2) * c.STOMP_POWER
    else
        local lo, hi = w:getMinDamage(), w:getMaxDamage()
        if not finite(lo) or lo < 0 then lo = 0 end
        if not finite(hi) or hi < lo then hi = lo end
        v = lo + (hi - lo) * roll / 99
    end
    local level = math.max(0, math.min(10, c.WEAPON_LEVEL))
    v = v * combat("NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER", 1.5)
        * (combat("BASE_WEAPON_DAMAGE_MULTIPLIER", 0.3) + level * combat("WEAPON_LEVEL_DAMAGE_MULTIPLIER_INCREMENT", 0.1))
    if not melee then return v end
    if floor and not stomp then   -- IsoGameCharacter.java:5817-5821 (visée au sol, sans poussée)
        local crit = w:getCriticalDamageMultiplier()
        v = v * math.max(c.FLOOR_MIN_MULT, finite(crit) and crit or 0)
    end
    if hits >= 4 then v = v * (hits - 2) * 1.5 end   -- IsoGameCharacter.java:5709-5714
    return v * combat("GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER", 0.15)
end

local function noteHit(key, ranged)
    if ranged then return Zombies.hitsOn[key] or 0 end
    local st = Zombies.state
    local n = (Zombies.hitsOn[key] or 0) + 1
    if Zombies.hitsOn[key] == nil then
        st.hitsKept = st.hitsKept + 1
        if st.hitsKept > cfg().HITS_KEPT then   -- borne : on oublie tout (un zombie revu repart de zéro)
            Zombies.hitsOn = {}
            st.hitsKept = 1
        end
    end
    Zombies.hitsOn[key] = n
    return n
end

-- Coup accepté par LK_Combat (contrôles faits) du PNJ id, ordre o, sur le zombie z avec l'arme w. Rend vrai et les
-- dégâts, la santé restante et vrai si le coup tue ; ou faux et la raison.
function Zombies.hurt(id, o, z, w)
    if not LivingKnox.isAuthority() then return false, "not the authority" end
    if w == nil then return false, "no weapon item" end
    local ok, why = Zombies.isVanilla(z)
    if not ok then return false, why end
    local key = Zombies.keyOf(z)
    local hits = noteHit(key, w:isRanged())
    local floor = not w:isRanged() and Zombies.isDown(z)   -- LK06-T09 : coup au sol
    local dmg = Zombies.damageOf(id, o, w, math.max(1, hits), floor)
    if floor then count("floorHits") end
    local before = z:getHealth()
    local left = before - dmg
    count("hits")
    if left <= 0 then
        local body = Bodies().find(id)
        Zombies.hitsOn[key] = nil
        count("kills")
        log().info("npc %s killed zombie %s with %s (%.3f damage%s, health was %.3f)", id, key, w:getFullType(), dmg,
            floor and " on the floor" or "", before)
        if isServer() then
            if body ~= nil then z:setAttackedBy(body) end
            z:die()
        else
            z:Kill(w, body)
        end
        return true, dmg, 0, true
    end
    z:setHealth(left)
    local reaction = floor and cfg().FLOOR_REACTION or nil
    if reaction ~= nil then z:setHitReaction(reaction) end   -- LK06-T09 : reste à terre (réaction vanilla)
    if isServer() then
        local owner = z:getOwnerPlayer()   -- client qui simule le zombie (nil : le serveur le simule)
        if owner ~= nil then
            sendServerCommand(owner, Zombies.MODULE, Zombies.CMD_HURT, { o = z:getOnlineID(), d = dmg, r = reaction })
            count("hurtMessages")
        end
    end
    log().debug("npc %s hurt zombie %s with %s%s: %.3f, health %.3f", id, key, w:getFullType(),
        floor and " on the floor" or "", dmg, left)
    return true, dmg, left, false
end

-- ---------------------------------------------------------------- attaques des zombies sur les PNJ

-- Vrai si le zombie z peut atteindre le corps body (ligne de coup vanilla de LK_Combat, LK06-T08) : pas à travers
-- un mur, une porte fermée ni une vitre fermée ou barricadée.
function Zombies.canReach(z, body)
    local C = LivingKnox.Combat
    if C == nil or C.lineOfStrike == nil then return true end
    return (C.lineOfStrike(z, body))
end

-- Tirage reproductible 0..99 du tirage salt (1..3) de l'attaque n du zombie numéro zn sur le PNJ id.
function Zombies.roll(id, zn, n, salt)
    return LivingKnox.Combat.roll(id, zn, n * 4 + salt)
end

-- Issue de l'attaque n du zombie numéro zn sur le PNJ id, attackers zombies au contact : "avoided", "scratch",
-- "laceration" ou "bite" (voir l'en-tête). Pure.
function Zombies.outcome(id, zn, n, attackers)
    local c = cfg()
    local extra = math.max(1, attackers) - 1
    if Zombies.roll(id, zn, n, 1) <= c.AVOID - extra * c.AVOID_EXTRA then return "avoided" end
    if Zombies.roll(id, zn, n, 3) > c.BITE - extra * c.BITE_EXTRA then return "bite" end
    if Zombies.roll(id, zn, n, 2) > c.LACERATION - extra * c.LACERATION_EXTRA then return "laceration" end
    return "scratch"
end

local function fullOf(id, body)
    local H = Health()
    local st = H and H.get and H.get(id) or nil
    if st ~= nil and finite(st.max) and st.max > 0 then return st.max end
    local h = body:getHealth()
    if finite(h) and h > 0 then return h end
    return 1
end

-- Attaque n du zombie z (clé key) sur le PNJ id (corps body). Rend l'issue.
function Zombies.attack(id, body, z, key, n, attackers)
    local zn = Zombies.numberOf(z)
    local out = Zombies.outcome(id, zn, n, attackers)
    count("attacks")
    count(out)
    if out == "avoided" then
        log().debug("npc %s avoided zombie %s (attack %d, %d attacker(s))", id, key, n, attackers)
        return out
    end
    local H = Health()
    local amount = cfg().DAMAGE[out] * fullOf(id, body)
    local deaths = H.stats.deaths
    local hp = H.applyHit(id, body, amount, "zombie " .. out, z, nil)
    log().info("npc %s: %s by zombie %s (attack %d, %d attacker(s), %.3f damage, health %s)", id, out, key, n,
        attackers, amount, hp ~= nil and string.format("%.3f", hp) or "?")
    if H.stats.deaths > deaths then count("deaths") end
    return out
end

-- Atténuation vanilla d'un bruit de la case sb entendu sur la case sa (J/WorldSoundManager.java:270-275) : 1 même
-- pièce (ou dehors tous deux), 1,2 deux pièces, 1,68 l'une dehors.
function Zombies.roomPenalty(sa, sb)
    if sa == nil or sb == nil then return 1 end
    local ra, rb = sa:getRoom(), sb:getRoom()
    if ra == rb then return 1 end
    if ra == nil or rb == nil then return 1.2 * 1.4 end
    return 1.2
end

-- Multiplicateur d'ouïe du zombie z (option Ouïe, météo, objets portés ; WorldSoundManager.getHearingMultiplier,
-- J/WorldSoundManager.java:407-422) ; 1 si illisible.
-- LK06-T11 (campagne MP du 2026-10-15, lk.windowkill 1 fois sur 3) : avec l'option Ouïe au hasard (4 : 1 à 3 ; 5 :
-- normale ou faible), chaque machine tire SA valeur du champ hearing à la création de sa copie
-- (J/characters/IsoZombie.java:3206, Rand local, jamais transmis) : copie du serveur « normale » (1,0), copie du
-- client qui simule le zombie et réagit seul au bruit « faible » (0,45). Sur un serveur, l'ouïe la plus faible
-- possible (Poor, 0,45, x objets portés et météo du zombie) est donc retenue : le bruit d'attrait porte assez loin
-- quelle que soit la copie qui l'entend.
Zombies.POOR_HEARING = 0.45   -- WorldSoundManager.getHearingMultiplier(3)

function Zombies.hearingOf(z)
    if getWorldSoundManager == nil then return 1 end
    local W = getWorldSoundManager()
    local m = W ~= nil and W:getHearingMultiplier(z) or nil
    if not (finite(m) and m > 0.05) then m = 1 end
    local lore = isServer() and SandboxVars ~= nil and SandboxVars.ZombieLore or nil
    local opt = lore ~= nil and lore.Hearing or nil
    if opt == 4 or opt == 5 or opt == 3 then
        local f = 1
        if z.getWornItemsHearingMultiplier ~= nil then f = f * z:getWornItemsHearingMultiplier() end
        if z.getWeatherHearingMultiplier ~= nil then f = f * z:getWeatherHearingMultiplier() end
        local worst = Zombies.POOR_HEARING * f
        if finite(worst) and worst > 0.05 and worst < m then m = worst end
    end
    return m
end

-- Rayon du bruit d'attrait émis à la case du corps body pour que le zombie z l'entende (getSoundAttract > 0 :
-- distance² < (rayon x ouïe)² / atténuation), avec la marge LURE_MARGIN, borné à LURE_CAP.
function Zombies.lureRadius(z, body)
    local c = cfg()
    local x, y = math.floor(body:getX()), math.floor(body:getY())
    local dx, dy = z:getX() - x, z:getY() - y
    local d = math.sqrt(dx * dx + dy * dy)
    local pen = Zombies.roomPenalty(z:getCurrentSquare(), body:getCurrentSquare())
    local r = math.ceil(d * math.sqrt(pen) * c.LURE_MARGIN / Zombies.hearingOf(z)) + 1
    return math.min(c.LURE_CAP, r)
end

-- Bruit d'attrait du PNJ id (corps body), vu par le zombie z. Source nil : voir l'en-tête (3). Rend vrai si émis.
local function lure(id, body, z, t)
    local last = Zombies.lured[id]
    if last ~= nil and t - last < cfg().LURE_MS then return false end
    if addSound == nil then return false end
    Zombies.lured[id] = t
    local r = Zombies.lureRadius(z, body)
    addSound(nil, math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ()), r, cfg().LURE_VOLUME)
    count("lures")
    log().debug("npc %s seen by zombie %s: lure noise radius %d", id, Zombies.keyOf(z), r)
    return true
end

-- Bruit de pas du PNJ id (corps body) à l'heure t : voir l'en-tête (3). Rend le rayon émis ou nil.
function Zombies.stepNoise(id, body, t)
    local c = cfg()
    local x, y = body:getX(), body:getY()
    local st = Zombies.steps[id]
    if st == nil then
        Zombies.steps[id] = { x = x, y = y, t = t }
        return nil
    end
    if t - st.t < c.STEP_MS then return nil end
    local dx, dy = x - st.x, y - st.y
    st.x, st.y, st.t = x, y, t
    if dx * dx + dy * dy < c.STEP_MIN_MOVE * c.STEP_MIN_MOVE then return nil end
    local A = LivingKnox.Anim
    local g = A ~= nil and A.gestureOf ~= nil and A.gestureOf(id) or nil
    local r = g ~= nil and c.STEP_RADIUS[g] or nil
    if r == nil or addSound == nil then return nil end
    local sq = body:getCurrentSquare()
    if sq ~= nil and sq:getRoom() ~= nil then r = math.floor(r * c.STEP_INSIDE) end
    if r < 1 then return nil end
    addSound(nil, math.floor(x), math.floor(y), math.floor(body:getZ()), r, r)
    count("steps")
    return r
end

-- Passage de l'autorité : contacts, attaques et attrait. Rend le nombre d'attaques.
function Zombies.pass(t)
    t = t or now()
    count("passes")
    local B = Bodies()
    local H = Health()
    local cell = getCell()
    if B == nil or H == nil or cell == nil then return 0 end
    local bodies = {}
    for id, z in pairs(B.bound) do
        if z ~= nil and not z:isDead() and not H.decided[id] and B.inWorld(z) then
            bodies[#bodies + 1] = { id = id, z = z, touching = {}, near = {} }
        end
    end
    table.sort(bodies, function(a, b) return a.id < b.id end)
    local seen = {}
    if #bodies > 0 then
        local c = cfg()
        local range = c.LURE_RADIUS
        local list = cell:getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil then
                local candidate = nil
                for _, b in ipairs(bodies) do
                    if z ~= b.z and math.abs(z:getX() - b.z:getX()) <= range
                        and math.abs(z:getY() - b.z:getY()) <= range and sameLevel(z, b.z) then
                        if candidate == nil then candidate = Zombies.isVanilla(z) end
                        if not candidate then break end
                        local d = distance(z, b.z)
                        local crawling = z:isCrawling()
                        local reach = crawling and c.REACH_CRAWL or c.REACH
                        if d <= reach and (crawling or not z:isOnFloor()) and Zombies.canReach(z, b.z) then
                            b.touching[#b.touching + 1] = { z = z, key = Zombies.keyOf(z), d = d }
                        elseif d <= range then
                            b.near[#b.near + 1] = { z = z, d = d, key = Zombies.keyOf(z) }
                        end
                    end
                end
            end
        end
        for _, b in ipairs(bodies) do
            table.sort(b.touching, function(x, y) return x.key < y.key end)
            for _, e in ipairs(b.touching) do
                if H.decided[b.id] or b.z:isDead() then break end   -- mort décidée par une attaque précédente
                local ck = b.id .. "|" .. e.key
                seen[ck] = true
                local ct = Zombies.contacts[ck]
                if ct == nil then
                    ct = { id = b.id, key = e.key, since = t, n = 0, next = t + c.WINDUP_MS }
                    Zombies.contacts[ck] = ct
                    count("contacts")
                end
                if t >= ct.next then
                    ct.n = ct.n + 1
                    ct.next = ct.next + c.ATTACK_MS
                    if ct.next <= t then ct.next = t + c.ATTACK_MS end   -- passage en retard : pas de rafale
                    Zombies.attack(b.id, b.z, e.z, e.key, ct.n, #b.touching)
                end
            end
            -- LK06-T09 (campagne MP du 2026-10-15, lk.windowkill) : un zombie au contact à travers une fenêtre OUVERTE
            -- (offensive : vitre ouverte par un membre) attaque mais, sans bruit ni cible, ne l'enjambe jamais : il est
            -- attiré aussi (bruit à la case du PNJ : chemin du bruit par la fenêtre, ClimbThroughWindowState).
            if #b.near == 0 and #b.touching > 0 and not H.decided[b.id] and not b.z:isDead() then
                local zt = b.touching[1].z
                local sz, sb = zt:getCurrentSquare(), b.z:getCurrentSquare()
                if sz ~= nil and sb ~= nil and sz ~= sb and sz:getWindowTo(sb) ~= nil then lure(b.id, b.z, zt, t) end
            end
            if #b.near > 0 and not H.decided[b.id] and not b.z:isDead() then
                table.sort(b.near, function(x, y)
                    if x.d ~= y.d then return x.d < y.d end
                    return x.key < y.key
                end)
                for i = 1, math.min(#b.near, c.LOS_TRIES) do
                    if lineClear(b.near[i].z, b.z) then
                        lure(b.id, b.z, b.near[i].z, t)
                        break
                    end
                end
            end
        end
    end
    for _, b in ipairs(bodies) do
        if not H.decided[b.id] and not b.z:isDead() then Zombies.stepNoise(b.id, b.z, t) end
    end
    for ck in pairs(Zombies.contacts) do
        if not seen[ck] then Zombies.contacts[ck] = nil end
    end
    return Zombies.stats.attacks
end

-- OnTick (autorité) : un passage au plus par PASS_MS.
function Zombies.tick()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    if not LivingKnox.Config.isEnabled() then return end
    local st = Zombies.state
    local t = now()
    if st.lastPass ~= nil and t - st.lastPass < cfg().PASS_MS then return end
    st.lastPass = t
    Zombies.pass(t)
end

-- PNJ oublié : contacts et attrait retirés.
function Zombies.forget(id)
    for ck, ct in pairs(Zombies.contacts) do
        if ct.id == id then Zombies.contacts[ck] = nil end
    end
    Zombies.lured[id] = nil
    Zombies.steps[id] = nil
end

-- Réinitialisation (nouvelle partie, tests).
function Zombies.reset()
    Zombies.contacts, Zombies.hitsOn, Zombies.serials, Zombies.lured, Zombies.steps = {}, {}, {}, {}, {}
    Zombies.state = { serial = 0, lastPass = nil, hitsKept = 0 }
end

local function onTick()
    LivingKnox.Zombies.tick()
end

LivingKnox.subscribe("OnTick", "Zombies.tick", onTick)

-- Serveur dédié : le retrait Lua d'un zombie n'est pas transmis au client qui le simule (copie fantôme debout, vue
-- 83 s dans la campagne MP du 2026-10-15, qui empêchait un corps voisin de se relever : isBeingSteppedOn ; base
-- multiplayer.md « Zombie simulé par un client vu du serveur »). Appelé par LivingKnox.Bodies.removeBody avec
-- { o, x, y, z } relevés avant le retrait : commande "bodyGone" à tous les clients, chacun retire sa copie de cet
-- identifiant réseau près de cette position (client/LivingKnox/LK_ZombiesClient.lua). Rend vrai si envoyée.
Zombies.CMD_GONE = "bodyGone"
function Zombies.tellBodyGone(g)
    if type(g) ~= "table" or type(g.o) ~= "number" or g.o < 0 then return false end
    if not (isServer and isServer()) or sendServerCommand == nil then return false end
    sendServerCommand(Zombies.MODULE, Zombies.CMD_GONE, { o = g.o, x = g.x, y = g.y, z = g.z })
    Zombies.stats.goneSent = (Zombies.stats.goneSent or 0) + 1
    return true
end

return Zombies
