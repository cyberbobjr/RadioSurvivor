-- Living Knox : défense coordonnée du foyer, côté autorité (LK05-T09). Fiche : docs/annexes/conception/defense.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
-- Aucune décision côté client : les clients ne reçoivent que les consignes LK03, les gestes et les ordres de combat.
--
-- 1. Déclenchement (Defense.update, plan de groupe refait au plus toutes les PLAN_MS, lu par la cascade) : le groupe
--    a une alerte en cours (LivingKnox.Alert, LK05-T08) ET le recensement de l'autorité compte au moins une menace
--    près du foyer : zombies vanilla (LivingKnox.Zombies.isVanilla) et joueurs que le groupe tient pour hostiles
--    (Alert.playerKind) à THREAT_RADIUS cases au plus de la case du foyer (en x et en y), au plus LEVELS étage d'écart.
--    Foyer sans poste relevé (LivingKnox.Routines.ensurePosts) : aucune défense, la cascade reste celle de LK05-T08 /
--    LK06. Foyer sans bâtiment (camp) : places de défense en plein air (point 8). Fin : aucune menace recensée depuis
--    END_MINUTES minutes de jeu.
-- 2. Rapport de forces (Defense.assess, pur) : menace = zombies + HOSTILE_WEIGHT x hostiles ; combattants valides =
--    membres présents de tout rôle (LK06-T07 : tout le monde se bat), santé >= Decisions.woundRatio() et
--    peur < Decisions.fearHigh() (constantes bonnes, options LK05-T16), dans le rayon des renforts. Repli à
--    l'intérieur (« withdraw », I6.3, I6.6 : décision collective du groupe, au nom de son chef) si aucun combattant
--    valide ou menace > WITHDRAW_RATIO x combattants ; retour aux postes (« hold ») quand menace <= HOLD_RATIO x
--    combattants (hystérésis : pas de va-et-vient). LK05-T14 : THREAT_RADIUS, WITHDRAW_RATIO (HOLD_RATIO = rapport -
--    1) et REINFORCE_RADIUS réglables (options DefenseRadius, DefenseWithdrawRatio, AlertReach) ; un zombie n'est
--    recensé qu'à Config.zombieAlertDistance() cases du foyer au plus.
-- 3. Affectations (Defense.assign, pur, déterministe : numéros de membre, rang des postes) :
--    - hold : chaque combattant valide (par numéro) prend un poste de guet du foyer (portes puis fenêtres, relevé
--      LK05-T03) ; postes classés d'abord s'ils donnent sur la menace (direction extérieure du poste à 90 degrés au
--      plus de la direction de la menace), puis par distance à la menace ; un membre garde son poste tant qu'il reste
--      parmi les postes retenus (pas d'échange à chaque mouvement de la menace) ; un poste par membre ;
--    - membres aux constantes mauvaises (blessés, apeurés), combattants en surnombre et tout le monde en repli : abri
--      intérieur (Defense.shelters : case praticable du bâtiment du foyer, hors bord du bâtiment et hors poste, la plus
--      éloignée de la menace) ; constantes mauvaises aux abris les plus éloignés, combattants valides aux plus
--      proches de la menace ; un abri par membre (assign garde le champ combatant de ses entrées : tous vrais ici) ;
--    - renforts (I6.1 inversé : défense du bâtiment, pas poursuite) : un membre incarné à REINFORCE_RADIUS cases au
--      plus du foyer, même dehors, reçoit sa place et y court ; plus loin : hors de la défense.
-- 4. Combat autour des postes (Defense.contextFor, Defense.targetFor, LivingKnox.Combat.engage). LK06-T14 (décision
--    de l'utilisateur du 2026-10-13) : un membre apte attaque les zombies jusqu'à la portée d'engagement sans attendre
--    le corps à corps, y compris en défense.
--    - Sortie (phase « hold », place de combattant valide : fighter) : zone = Defense.engageRange(npc) cases (option
--      ZombieEngage<Rôle> du rôle du membre, défaut 10, bornée par ZombieAlertDistance) autour de sa place. Corps dans la
--      zone (à zone + 1 case au plus de sa place) : cible = zombie vanilla le plus proche du corps, dans la zone, au
--      même niveau ; mêlée seulement par une ligne de coup (Combat.lineOfStrike : ni mur, ni porte fermée, ni vitre
--      fermée ; un zombie vu seulement derrière une vitre reste à l'offensive à la fenêtre du point 7), au plus
--      MAX_TARGET_TRIES lignes ; tir (poste, arme à feu chargée) : zombie à portée de l'arme avec une ligne de tir
--      dégagée (Combat.lineOfFire), recensé ou dans la zone. Laisse de l'ordre = zone : le membre va au-devant du
--      zombie, le frappe, et revient à sa place quand plus aucune cible n'est dans la zone. Cible la plus proche par
--      membre : plusieurs zombies dans la zone se répartissent entre les membres selon leurs positions.
--    - Sans sortie (repli « withdraw », membre aux constantes mauvaises : place non fighter) : mêlée seulement sur une
--      menace à MELEE_ENGAGE cases au plus du corps (zombie à la porte, intrus entré), laisse COMBAT_LEASH ; corps à
--      plus de POST_LEASH cases de sa place : il revient ;
--    - en route (corps hors de la zone) : seulement se défendre d'une menace au contact (MELEE_ENGAGE) ;
--    - joueur : seulement la cible retenue par la cascade (Hostility.chooseTarget, aide : trêve et reddition
--      respectées), à MELEE_ENGAGE cases ou sous un tir dégagé : aucune sortie contre un joueur ;
--    - l'ordre de combat porte la laisse (Combat.engage, opts.leash) : LK_Combat ne fait jamais approcher le corps
--      d'une cible hors de la laisse ; hors laisse, frappe à portée ou tir dégagé seulement, sinon fin de l'ordre.
--      Une cible n'est choisie que si cet ordre la garde (dans la laisse, ou à portée de l'arme : Defense.held) :
--      aucun ordre démarré puis aussitôt abandonné (« target out of the defense leash » en boucle, LK06-T14).
--    Hors de ces conditions, aucune cible : la cascade ne choisit plus « fight » (LK06-T04) pendant la défense.
-- 5. Exécution (Defense.apply, appelée par LivingKnox.Decisions.apply pour le comportement « defend ») : engagement
--    (Combat.engage, source « decisions ») ou fin de l'engagement (Combat.leave), sinon course vers la place
--    (Directives.moveTo « run »), regard vers la menace (ou vers l'extérieur du poste), geste « guard » (membre valide)
--    ou « crouch » (constantes mauvaises, LK06-T07). Place injoignable après MAX_FAILS trajets : notée bloquée
--    BLOCK_MINUTES (le plan
--    suivant donne une autre place), regard sur place en attendant : aucun membre ne reste à pousser contre un mur.
-- 6. Après l'attaque (fin de la défense) : marque Defense.after(gid) = { id, minute, minutes, wounded = { mid ... } }
--    (blessés : santé < CARE_HEALTH), entrée « defense » au journal du groupe, et point d'appel des soins
--    LivingKnox.Care.afterAttack(gid, marque) (LK07-T03, LK_Care.lua : blessés notés à soigner) ; aucun soin ici.
-- 7. Offensive à la fenêtre (LK06-T09, fiche defense.md, section « Offensive à la fenêtre ») : décision de
--    l'utilisateur du 2026-10-12, faire comme un joueur : ouvrir la fenêtre pour que le zombie tombe à l'intérieur et
--    l'achever au sol. Defense.updateOffense, à chaque plan en phase « hold » seulement (jamais en repli : groupe
--    débordé) : une fenêtre (IsoWindow) du bâtiment du foyer, au niveau du foyer, frappée de l'extérieur par un zombie
--    recensé (getThumpTarget, ThumpState), fermée, intacte, sans barricade, ouvrable (canOpen : ni bloquée, ni à
--    alarme armée, sol de l'autre côté ; verrouillée : ouverte de l'intérieur comme le vanilla). Rapport : zombies
--    qui attendent (OFFENSE_WAIT_RADIUS cases autour de la case extérieure, dehors) <= OFFENSE_RATIO x combattants
--    valides à OFFENSE_HELP_RADIUS cases de la case intérieure, sinon pas d'ouverture (chooseOffense, pur) ; ouvreur :
--    le plus proche du bord. Une offensive à la fois par groupe. L'ouvreur court à la case intérieure, joue le geste
--    openwindow du joueur tourné vers la fenêtre ; Defense.tick (OnTick) bascule la fenêtre (ToggleWindow avec son
--    corps) à l'instant du clip (OFFENSE_OPEN_TOGGLE_MS). La suite est vanilla : le zombie en ThumpState voit sa cible
--    devenir invalide et enjambe la fenêtre ouverte (J/ai/states/ThumpState.java:183-193, IsoWindow.getThumpableFor
--    :455-465), tombe à l'intérieur (OnFloor des nœuds zombie, ClimbThroughWindowState.java:105-127, 296-308) ; le
--    défenseur de la fenêtre recule d'un pas (case de chute libre) et les membres proches l'achèvent au sol (coup au
--    sol de LK_Combat et LK_Zombies, réaction « Floor » qui le garde à terre). Fin : plus aucun zombie à
--    OFFENSE_WAIT_RADIUS cases de la fenêtre (deux côtés), OFFENSE_END_MS après l'ouverture, fenêtre refermée ou
--    disparue ; abandon (fenêtre écartée OFFENSE_BLOCK_MINUTES) si elle n'est pas ouverte en OFFENSE_OPEN_MS ; annulée
--    avant l'ouverture si le groupe passe en repli ou si l'ouvreur devient inapte.
--    Cible des coups (LK06-T11, décision de l'utilisateur du 2026-10-14) : getThumpTarget sur la machine qui simule le
--    zombie (solo, zombie simulé par le serveur) ; sinon (serveur, zombie simulé par un client : paquet Thump seulement
--    relayé) la fenêtre que le client propriétaire du zombie rapporte (commande zombieThumps, LivingKnox.Senses,
--    contrôlée à la réception : zombie connu et simulé par ce client, fenêtre réelle, copie du zombie à portée) et récente
--    (Senses.CHECK.THUMP_MS), du bâtiment du foyer, zombie dehors (Defense.thumpTargetOf). Aucune déduction par la
--    seule proximité d'une vitre.
--    Refermeture (LK06-T11, décision du 2026-10-14) : fenêtre ouverte, plus aucun zombie près d'elle (ou délai
--    OFFENSE_END_MS écoulé) : l'offensive passe à l'état « closing » ; un membre valide (l'ouvreur d'abord, sinon le
--    plus proche du bord) joue le geste closewindow du joueur tourné vers la fenêtre (à OFFENSE_REACH du milieu du
--    bord, sinon il rejoint la case intérieure) ; Defense.tick la ferme à l'instant du clip (OFFENSE_CLOSE_TOGGLE_MS)
--    si aucun personnage (zombie, corps de PNJ, joueur) n'occupe les deux cases du bord, l'auteur du geste excepté ;
--    sinon nouvel essai, abandon (fenêtre laissée ouverte) après OFFENSE_CLOSE_MS. Les autres membres gardent leurs
--    places de recul pendant ce temps (case intérieure libre). La défense ne finit pas tant qu'une offensive est en
--    cours. Fenêtre déverrouillée par l'ouverture : laissée déverrouillée.
--    Retenue (demande du 2026-10-15, campagne MP : zombie frappé debout pendant qu'il enjambait, achevé sans coup au
--    sol) : comme un joueur vanilla, pendant l'ouverture et l'attente de la chute (états « opening » et « open »),
--    aucun membre n'engage (mêlée ni tir) un zombie de l'offensive (Defense.offenseHolds : zombie recensé qui attend
--    dehors à OFFENSE_WAIT_RADIUS cases de la case extérieure, ou qui enjambe, noté à chaque plan) tant qu'il n'est
--    pas au sol. Libéré, pour de bon : au sol (isOnFloor : coup au sol), entré debout (dans le bâtiment, hors de
--    l'état climbwindow, depuis OFFENSE_STAND_MS), OFFENSE_FALL_MS après l'ouverture (délai d'abandon), ou fin de
--    l'offensive ; ensuite combat normal (relevé compris).
-- 8. Campement (LK05-T18, décision de l'utilisateur du 2026-10-14) : un groupe dont le foyer est hors de tout bâtiment
--    (relevé « camp » de LK_Routines : feu de camp, tentes) se bat sur place au lieu de rester sans défense. Mêmes
--    déclencheurs, seuils, rapport de forces, phases, sorties (point 4), blessés et fin que la défense d'une maison ;
--    seules les places changent (Defense.campPosts, Defense.campShelters) :
--    - postes : CAMP_POSTS places en couronne à CAMP_RING cases du foyer (N, E, S, W, puis diagonales), regard vers
--      l'extérieur ; case praticable la plus proche du point de la couronne (une case au plus, à CAMP_RING +- 1 du
--      foyer) ; classés et donnés comme les postes d'une maison (face à la menace d'abord, puis distance) ;
--    - abris (membres aux constantes mauvaises, surnombre, repli) : cases praticables à CAMP_CENTER case au plus du
--      foyer, hors postes : les non-combattants sont regroupés au centre du camp, derrière la couronne ;
--    - repli (groupe débordé) : tout le monde au centre, mêlée au contact seulement (aucun bâtiment où entrer) ;
--    - aucune offensive à la fenêtre (point 7) : pas de fenêtre.
--    Interrupteur CFG.CAMP (faux : ancien comportement, aucune défense au camp).
-- Mémoire seulement (plans, places bloquées, marques) : un redémarrage les oublie (la cascade les refait).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"

local Defense = LivingKnox.Defense or {}
LivingKnox.Defense = Defense

Defense.PHASES = { "hold", "withdraw" }
Defense.ROLES = { "post", "shelter" }
Defense.COMBAT_BEHAVIOURS = { "fight", "defend" }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Defense.CFG = Defense.CFG or {
    PLAN_MS = 1000,          -- plan du groupe refait au plus toutes les PLAN_MS (ou à chaque minute de jeu)
    THREAT_RADIUS = 12,      -- cases (x et y) autour de la case du foyer : menaces recensées
    LEVELS = 1,              -- étages d'écart au plus entre une menace et le foyer
    HOSTILE_WEIGHT = 3,      -- un joueur hostile compte comme autant de zombies
    WITHDRAW_RATIO = 3,      -- repli si menace > WITHDRAW_RATIO x combattants valides (ou aucun combattant valide)
    HOLD_RATIO = 2,          -- retour aux postes si menace <= HOLD_RATIO x combattants valides
    REINFORCE_RADIUS = 30,   -- cases (un étage = 3 cases) : membres appelés à la défense (comme Alert.CFG.REACH)
    MELEE_ENGAGE = 2.0,      -- cases : menace assez proche du corps pour une mêlée
    POST_LEASH = 3,          -- cases : au-delà de sa place, un combattant ne s'engage plus et revient
    COMBAT_LEASH = 1,        -- cases : laisse de l'ordre de combat (LK_Combat, opts.leash) : approche seulement d'une
                             -- cible à cette distance de la place (porte, fenêtre), sinon frappe à portée ou tir dégagé
    END_MINUTES = 2,         -- minutes de jeu sans menace recensée avant la fin de la défense
    MAX_TARGET_TRIES = 3,    -- lignes de tir essayées au plus par membre et par passage
    MAX_FAILS = 2,           -- trajets manqués vers une place avant de la noter bloquée
    BLOCK_MINUTES = 5,       -- minutes de jeu : place bloquée écartée des plans suivants
    MAX_SHELTERS = 8,        -- abris intérieurs gardés au plus
    FACE_DELTA = 30,         -- degrés : nouvelle consigne « face » si la direction a tourné d'au moins autant
    CARE_HEALTH = 0.75,      -- santé (0..1) sous laquelle un membre est noté blessé après l'attaque
}
-- Offensive à la fenêtre (LK06-T09, point 7 de l'en-tête ; valeurs de départ, raisons dans la fiche).
for k, v in pairs({
    OFFENSE = true,          -- interrupteur
    OFFENSE_WAIT_RADIUS = 2, -- cases (x et y) autour de la case extérieure de la fenêtre : zombies qui attendent
    OFFENSE_HELP_RADIUS = 3, -- cases (x et y) autour de la case intérieure : combattants valides comptés
    OFFENSE_RATIO = 1,       -- ouverture si zombies qui attendent <= OFFENSE_RATIO x combattants valides comptés
    OFFENSE_REACH = 1.6,     -- cases : corps de l'ouvreur au plus à cette distance du milieu du bord pour le geste
                             -- (case de la fenêtre, arrivée d'une consigne à Directives.ARRIVE = 1 case du centre)
    OFFENSE_OPEN_MS = 20000, -- ouverture non faite dans ce délai (trajet, geste) : abandon, fenêtre écartée
    OFFENSE_END_MS = 45000,  -- fenêtre ouverte : offensive close au plus tard après ce délai
    OFFENSE_BLOCK_MINUTES = 5, -- minutes de jeu : fenêtre abandonnée écartée des offensives suivantes
    OFFENSE_TICK_MS = 100,   -- passage de l'autorité pour basculer la fenêtre à l'instant du geste
    OFFENSE_OPEN_TOGGLE_MS = 1000,  -- fenêtre ouverte à cet instant du geste openwindow (Obstacles.OPEN_TOGGLE_MS)
    OFFENSE_OPEN_GESTURE_MS = 1750, -- durée du geste openwindow (Obstacles.OPEN_GESTURE_MS)
    OFFENSE_CLOSE = true,    -- LK06-T11 : refermeture de la fenêtre après l'offensive
    OFFENSE_CLOSE_MS = 20000, -- refermeture non faite dans ce délai (embrasure occupée, trajet) : fenêtre laissée ouverte
    OFFENSE_CLOSE_TOGGLE_MS = 1080,  -- fenêtre fermée à cet instant du geste closewindow (Obstacles.CLOSE_TOGGLE_MS)
    OFFENSE_CLOSE_GESTURE_MS = 2080, -- durée du geste closewindow (Obstacles.CLOSE_GESTURE_MS)
    ENGAGE_RANGE = 10,       -- LK06-T14 : zone de sortie (cases) sans LivingKnox.Zombies (repli de engageRange)
    OFFENSE_HOLD = true,     -- retenue : aucun coup sur un zombie de l'offensive avant sa chute (point 7)
    OFFENSE_FALL_MS = 15000, -- fenêtre ouverte depuis ce délai : retenue levée (zombie qui n'enjambe pas)
    OFFENSE_STAND_MS = 1000, -- zombie debout dans le bâtiment, hors de climbwindow, depuis ce délai : retenue levée
    CAMP = true,             -- LK05-T18 : défense en plein air d'un foyer sans bâtiment (point 8)
    CAMP_RING = 3,           -- cases (Tchebychev) du foyer aux postes du camp
    CAMP_POSTS = 8,          -- postes du camp au plus (N, E, S, W, puis diagonales)
    CAMP_CENTER = 1,         -- cases (Tchebychev) du foyer aux abris du centre du camp
}) do
    if Defense.CFG[k] == nil then Defense.CFG[k] = v end
end

Defense.state = Defense.state or { groups = {}, npcs = {}, after = {}, n = 0 }
Defense.stats = Defense.stats or { plans = 0, started = 0, ended = 0, withdrawals = 0, holds = 0, engaged = 0,
    blocked = 0, moves = 0, faces = 0, refused = 0, careCalls = 0 }
for _, k in ipairs({ "offenses", "offenseRefused", "windowsOpened", "offenseGestures", "offenseEnded",
    "offenseGivenUp", "thumpReported", "windowsClosed", "closeGestures", "closeWaits", "closeGivenUp",
    "offenseHeld", "offenseFreed" }) do
    Defense.stats[k] = Defense.stats[k] or 0   -- LK06-T09
end

local function log() return LivingKnox.Log end
local function cfg() return Defense.CFG end

-- LK05-T14 : seuils réglables (options sandbox, LivingKnox.Config.danger) ; repli : valeurs de CFG.
-- Rayon de recensement autour du foyer : joueurs hostiles, et zombies dans la limite de Config.zombieAlertDistance().
function Defense.radii()
    local C = LivingKnox.Config
    local r = C.danger("DefenseRadius", cfg().THREAT_RADIUS)
    local zmax = C.zombieAlertDistance()
    return r, (zmax ~= nil and zmax < r) and zmax or r
end
-- Rapports de repli et de retour aux postes ; option DefenseWithdrawRatio : retour = rapport - 1 (hystérésis).
function Defense.ratios()
    local w = LivingKnox.Config.danger("DefenseWithdrawRatio", nil)
    if w == nil then return cfg().WITHDRAW_RATIO, cfg().HOLD_RATIO end
    return w, w - 1
end
-- Rayon des renforts (un étage = 3 cases) : portée de l'alerte (option AlertReach).
function Defense.reinforceRadius() return LivingKnox.Config.danger("AlertReach", cfg().REINFORCE_RADIUS) end
local function Decisions() return LivingKnox.Decisions end
local function Groups() return LivingKnox.Groups end
local function now() return getTimestampMs() end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function count(name)
    Defense.stats[name] = (Defense.stats[name] or 0) + 1
end

local function angleGap(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

local function spotKey(role, x, y, z) return string.format("%s %d,%d,%d", role, x, y, z) end

-- ================================================================ pur

-- Phase de la défense (pur) : "hold" ou "withdraw" et la raison. threat = menace pondérée, able = combattants
-- valides, prev = phase précédente (nil au départ).
function Defense.assess(threat, able, prev)
    local withdraw, hold = Defense.ratios()
    if able <= 0 then return "withdraw", string.format("threat %d, no able fighter", threat) end
    if prev == "withdraw" then
        if threat <= hold * able then
            return "hold", string.format("threat %d <= %d x %d able fighter(s)", threat, hold, able)
        end
        return "withdraw", string.format("threat %d > %d x %d able fighter(s)", threat, hold, able)
    end
    if threat > withdraw * able then
        return "withdraw", string.format("threat %d > %d x %d able fighter(s)", threat, withdraw, able)
    end
    return "hold", string.format("threat %d <= %d x %d able fighter(s)", threat, withdraw, able)
end

-- Postes classés pour une menace en (tx, ty) (pur) : { { i, p, facing, gap, d, key }, ... }. Postes qui donnent sur
-- la menace d'abord (direction extérieure p.a à 90 degrés au plus), puis distance (Tchebychev) à la menace, puis rang
-- du relevé. Sans position de menace : ordre du relevé. blocked = { [clé] = vrai } écartées.
function Defense.rankPosts(posts, tx, ty, blocked)
    local out = {}
    for i, p in ipairs(posts or {}) do
        local key = spotKey("post", p.x, p.y, p.z)
        if not (blocked and blocked[key]) then
            local e = { i = i, p = p, key = key, facing = true, gap = 0, d = 0 }
            if tx ~= nil then
                local a = Decisions().angleTo(tx + 0.5 - (p.x + 0.5), ty + 0.5 - (p.y + 0.5))
                e.gap = a ~= nil and angleGap(a, p.a) or 0
                e.facing = e.gap <= 90
                e.d = cheb(p.x, p.y, tx, ty)
            end
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if a.facing ~= b.facing then return a.facing end
        if a.d ~= b.d then return a.d < b.d end
        return a.i < b.i
    end)
    return out
end

-- Affectations (pur). input = { phase, posts (relevé), shelters ({ { x, y, z }, ... } du plus éloigné au plus proche
-- de la menace), home ({ x, y, z }), tx, ty (menace, ou nil), members = { { mid, number, combatant, valid }, ... },
-- prev = { [mid] = clé de place }, blocked = { [clé] = vrai } }. Rend { [mid] = { role, x, y, z, a, key } } : a =
-- direction du regard à la place (menace, ou extérieur d'un poste qui ne donne pas sur elle ; nil : vers la menace).
function Defense.assign(input)
    local list = {}
    for _, m in ipairs(input.members or {}) do list[#list + 1] = m end
    table.sort(list, function(a, b) return a.number < b.number end)
    local out = {}
    local tx, ty = input.tx, input.ty
    local function lookFrom(x, y)
        if tx == nil then return nil end
        return Decisions().angleTo(tx + 0.5 - (x + 0.5), ty + 0.5 - (y + 0.5))
    end
    if input.phase == "hold" then
        local fighters = {}
        for _, m in ipairs(list) do
            if m.combatant and m.valid then fighters[#fighters + 1] = m end
        end
        local ranked = Defense.rankPosts(input.posts and input.posts.posts or {}, tx, ty, input.blocked)
        local chosen, byKey = {}, {}
        for i = 1, math.min(#fighters, #ranked) do
            chosen[#chosen + 1] = ranked[i]
            byKey[ranked[i].key] = ranked[i]
        end
        local taken = {}
        local function give(m, e)
            local p = e.p
            local a = e.facing and lookFrom(p.x, p.y) or p.a
            out[m.mid] = { role = "post", x = p.x, y = p.y, z = p.z, a = a or p.a, key = e.key, what = p.k,
                fighter = true }
            taken[e.key] = true
        end
        local prev = input.prev or {}
        for _, m in ipairs(fighters) do   -- poste gardé tant qu'il reste retenu
            local e = byKey[prev[m.mid] or ""]
            if e ~= nil and not taken[e.key] then give(m, e) end
        end
        for _, m in ipairs(fighters) do
            if out[m.mid] == nil then
                for _, e in ipairs(chosen) do
                    if not taken[e.key] then
                        give(m, e)
                        break
                    end
                end
            end
        end
    end
    -- Abris : non-combattants (constantes mauvaises) aux plus éloignés de la menace, combattants aux plus proches.
    local spots = {}
    for _, s in ipairs(input.shelters or {}) do
        local key = spotKey("shelter", s.x, s.y, s.z)
        if not (input.blocked and input.blocked[key]) then spots[#spots + 1] = { x = s.x, y = s.y, z = s.z, key = key } end
    end
    local home = input.home
    local first, last = 1, #spots
    local function shelter(m, fromEnd)
        local s
        if first <= last then
            if fromEnd then
                s = spots[last]
                last = last - 1
            else
                s = spots[first]
                first = first + 1
            end
        elseif home ~= nil then
            s = { x = home.x, y = home.y, z = home.z, key = spotKey("shelter", home.x, home.y, home.z) }
        end
        if s ~= nil then
            out[m.mid] = { role = "shelter", x = s.x, y = s.y, z = s.z, a = lookFrom(s.x, s.y), key = s.key,
                fighter = m.combatant == true and m.valid == true }
        end
    end
    for _, m in ipairs(list) do
        if out[m.mid] == nil and not (m.combatant and m.valid) then shelter(m, false) end
    end
    for _, m in ipairs(list) do
        if out[m.mid] == nil then shelter(m, true) end
    end
    return out
end

-- ================================================================ monde (autorité)

local function exec() return LivingKnox.Routines and LivingKnox.Routines.exec or nil end

local function buildingOf(sq)
    local X = exec()
    if X ~= nil and X.buildingId ~= nil then return X.buildingId(sq) end
    local def = sq ~= nil and sq:getBuildingDef() or nil
    return def ~= nil and def:getIDString() or nil
end

local function standable(sq)
    local X = exec()
    if X ~= nil and X.standable ~= nil then return X.standable(sq) end
    return sq ~= nil and sq:isFree(false) and not sq:HasStairs()
end

-- Abris du foyer home (même bâtiment, même niveau, à HOME_RADIUS cases au plus) : cases praticables dont les quatre
-- voisines sont du bâtiment (ni bord, ni porte, ni fenêtre) et qui ne sont pas des postes ; triées de la plus
-- éloignée de la menace (tx, ty) à la plus proche (puis proche du foyer, y, x). Rend au plus MAX_SHELTERS cases.
function Defense.shelters(home, posts, tx, ty)
    local cell = getCell()
    local out = {}
    if cell == nil or home == nil then return out end
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    local bid = hsq ~= nil and buildingOf(hsq) or nil
    if bid == nil then return out end
    local isPost = {}
    for _, p in ipairs(posts and posts.posts or {}) do isPost[p.x .. "," .. p.y] = true end
    local R = Decisions().CFG.HOME_RADIUS
    local cands = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil and not isPost[x .. "," .. y] and buildingOf(sq) == bid and standable(sq) then
                local inner = true
                for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
                    local nb = cell:getGridSquare(x + d[1], y + d[2], home.z)
                    if nb == nil or buildingOf(nb) ~= bid then inner = false end
                end
                if inner then
                    cands[#cands + 1] = { x = x, y = y, z = home.z, far = tx ~= nil and cheb(x, y, tx, ty) or 0,
                        d = cheb(x, y, home.x, home.y) }
                end
            end
        end
    end
    table.sort(cands, function(a, b)
        if a.far ~= b.far then return a.far > b.far end
        if a.d ~= b.d then return a.d < b.d end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    for i = 1, math.min(#cands, cfg().MAX_SHELTERS) do out[i] = { x = cands[i].x, y = cands[i].y, z = cands[i].z } end
    return out
end

-- LK05-T18 : directions des postes d'un camp, dans l'ordre du relevé (N, E, S, W, puis diagonales NE, SE, SW, NW).
local CAMP_DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } }
-- Voisines essayées autour du point de la couronne, dans cet ordre (le point d'abord).
local CAMP_NEAR = { { 0, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } }

-- Postes d'un camp autour du foyer home (point 8), même forme qu'un relevé de LK_Routines : { camp = true, posts = {
-- { x, y, z, a, k = "camp" }, ... } }. Pour chaque direction, case praticable la plus proche du point de la couronne
-- (CAMP_RING cases du foyer) : le point, sinon ses voisines (ordre fixe) restées à CAMP_RING +- 1 du foyer ; regard
-- (a) vers l'extérieur ; une case par poste. Peut rendre zéro poste (rien de praticable : aucune défense).
function Defense.campPosts(home)
    local out = { camp = true, posts = {} }
    local cell = getCell()
    if cell == nil or home == nil then return out end
    local R = cfg().CAMP_RING
    local used = {}
    for _, d in ipairs(CAMP_DIRS) do
        if #out.posts >= cfg().CAMP_POSTS then break end
        local cx, cy = home.x + d[1] * R, home.y + d[2] * R
        local pick = nil
        for _, o in ipairs(CAMP_NEAR) do
            local x, y = cx + o[1], cy + o[2]
            local ring = cheb(x, y, home.x, home.y)
            if pick == nil and not used[x .. "," .. y] and ring >= R - 1 and ring <= R + 1
                and standable(cell:getGridSquare(x, y, home.z)) then
                pick = { x = x, y = y }
            end
        end
        if pick ~= nil then
            used[pick.x .. "," .. pick.y] = true
            out.posts[#out.posts + 1] = { x = pick.x, y = pick.y, z = home.z, a = Decisions().angleTo(d[1], d[2]),
                k = "camp" }
        end
    end
    return out
end

-- Abris du centre d'un camp (point 8) : cases praticables à CAMP_CENTER cases au plus du foyer, hors postes, triées
-- de la plus éloignée de la menace (tx, ty) à la plus proche (puis proche du foyer, y, x), comme Defense.shelters.
function Defense.campShelters(home, posts, tx, ty)
    local cell = getCell()
    local out = {}
    if cell == nil or home == nil then return out end
    local isPost = {}
    for _, p in ipairs(posts and posts.posts or {}) do isPost[p.x .. "," .. p.y] = true end
    local R = cfg().CAMP_CENTER
    local cands = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            if not isPost[x .. "," .. y] and standable(cell:getGridSquare(x, y, home.z)) then
                cands[#cands + 1] = { x = x, y = y, far = tx ~= nil and cheb(x, y, tx, ty) or 0,
                    d = cheb(x, y, home.x, home.y) }
            end
        end
    end
    table.sort(cands, function(a, b)
        if a.far ~= b.far then return a.far > b.far end
        if a.d ~= b.d then return a.d < b.d end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    for i = 1, math.min(#cands, cfg().MAX_SHELTERS) do out[i] = { x = cands[i].x, y = cands[i].y, z = home.z } end
    return out
end

-- Recensement des menaces près du foyer home du groupe gid (copies de l'autorité) : zombies vanilla et joueurs
-- hostiles à THREAT_RADIUS cases (x et y), LEVELS étage(s) d'écart au plus. Rend { zombies, hostiles, threat,
-- list = { { kind, key, x, y, z, d (au foyer), zombie | player } } triée (distance au foyer, clé), tx, ty (centre) }.
function Defense.census(gid, g, players)
    local c = cfg()
    local home = g.home
    local out = { zombies = 0, hostiles = 0, threat = 0, list = {} }
    local cell = getCell()
    if cell == nil or home == nil then return out end
    local Zm = LivingKnox.Zombies
    local R, RZ = Defense.radii()
    local zl = cell:getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z ~= nil and math.abs(z:getX() - (home.x + 0.5)) <= RZ + 0.5 and math.abs(z:getY() - (home.y + 0.5)) <= RZ + 0.5
            and math.abs(math.floor(z:getZ()) - home.z) <= c.LEVELS and Zm ~= nil and Zm.isVanilla(z) then
            local x, y = math.floor(z:getX()), math.floor(z:getY())
            out.list[#out.list + 1] = { kind = "zombie", key = Zm.keyOf(z), x = x, y = y, z = math.floor(z:getZ()),
                d = cheb(x, y, home.x, home.y), zombie = z }
            out.zombies = out.zombies + 1
        end
    end
    local A = LivingKnox.Alert
    for _, p in ipairs(players or {}) do
        local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        if cheb(x, y, home.x, home.y) <= R and math.abs(z - home.z) <= c.LEVELS and A ~= nil and A.playerKind ~= nil
            and A.playerKind(gid, g.type, p) == "hostile" then
            out.list[#out.list + 1] = { kind = "player", key = "p:" .. tostring(p:getUsername()), u = tostring(p:getUsername()),
                x = x, y = y, z = z, d = cheb(x, y, home.x, home.y), player = p }
            out.hostiles = out.hostiles + 1
        end
    end
    table.sort(out.list, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    out.threat = out.zombies + c.HOSTILE_WEIGHT * out.hostiles
    if #out.list > 0 then
        local sx, sy = 0, 0
        for _, e in ipairs(out.list) do sx, sy = sx + e.x, sy + e.y end
        out.tx, out.ty = math.floor(sx / #out.list + 0.5), math.floor(sy / #out.list + 0.5)
    end
    return out
end

local function groupState(gid)
    local st = Defense.state.groups[gid]
    if st == nil then
        st = { blocked = {}, prev = {} }
        Defense.state.groups[gid] = st
    end
    return st
end

local function bodyOf(m)
    local B = LivingKnox.Bodies
    if m.npc == nil or B == nil or B.find == nil then return nil end
    return B.find(m.npc)
end

-- Membres de la défense : présents, incarnés, à REINFORCE_RADIUS cases du foyer (un étage = 3 cases).
local function defenders(gid, g)
    local out = {}
    local R = LivingKnox.Routines
    local G = Groups()
    local mids = R ~= nil and R.present ~= nil and R.present(g) or {}
    local home = g.home
    for _, mid in ipairs(mids) do
        local m = g.members[mid]
        local body = bodyOf(m)
        if body ~= nil then
            local x, y, z = body:getX(), body:getY(), math.floor(body:getZ())
            if cheb(x, y, home.x + 0.5, home.y + 0.5) + 3 * math.abs(z - home.z) <= Defense.reinforceRadius() then
                -- LK06-T07 : tout membre se bat, quel que soit son rôle ; valide = constantes bonnes (santé >=
                -- Decisions.woundRatio(), peur < Decisions.fearHigh() : options LK05-T16), sinon abri.
                local fear = (Decisions().needsOf(gid, mid) or {}).fear or 0
                out[#out + 1] = { mid = mid, number = G.memberNumber(mid) or 0, combatant = true,
                    valid = Decisions().healthOf(m) >= Decisions().woundRatio() and fear < Decisions().fearHigh() }
            end
        end
    end
    return out
end

local function blockedSet(st, minute)
    local out, old = {}, {}
    for key, at in pairs(st.blocked) do
        if minute - at >= cfg().BLOCK_MINUTES then old[#old + 1] = key else out[key] = true end
    end
    for _, key in ipairs(old) do st.blocked[key] = nil end
    return out
end

-- Fin de la défense du groupe gid : marque d'après l'attaque, journal, point d'appel des soins (LK07-T03).
local function finish(gid, g, st, minute, why)
    local plan = st.plan
    st.plan, st.prev, st.lastThreat = nil, {}, nil
    count("ended")
    local wounded = {}
    for _, mid in ipairs(LivingKnox.Routines and LivingKnox.Routines.present(g) or {}) do
        if Decisions().healthOf(g.members[mid]) < cfg().CARE_HEALTH then wounded[#wounded + 1] = mid end
    end
    local mark = { id = plan.id, minute = minute, minutes = math.max(0, minute - plan.since), wounded = wounded,
        why = why }
    Defense.state.after[gid] = mark
    local text = string.format("home defense %s over after %d min (%s); wounded: %s", plan.id, mark.minutes, why,
        #wounded > 0 and table.concat(wounded, " ") or "none")
    log().info("group %s %s", gid, text)
    local G = Groups()
    if G.addLog ~= nil then G.addLog(gid, "defense", text) end
    local Care = LivingKnox.Care   -- LK07-T03 (LK_Care.lua) : point d'appel des soins après l'attaque
    if Care ~= nil and Care.afterAttack ~= nil then
        count("careCalls")
        Care.afterAttack(gid, mark)
    end
end

-- Plan de défense du groupe gid (registre g) à la minute de jeu minute : refait au plus toutes les PLAN_MS, ou à une
-- nouvelle minute de jeu. Rend le plan { id, phase, why, since, tx, ty, census, assign = { [mid] = place } } ou nil
-- (pas de défense).
function Defense.update(gid, g, minute, players)
    if not LivingKnox.isAuthority() or g == nil or minute == nil then return nil end
    local st = groupState(gid)
    local t = now()
    if st.at ~= nil and st.minute == minute and t - st.at < cfg().PLAN_MS then return st.plan end
    st.at, st.minute = t, minute
    local R = LivingKnox.Routines
    local posts = (g.home ~= nil and R ~= nil and R.ensurePosts ~= nil) and R.ensurePosts(gid, g) or nil
    if posts ~= nil and posts.camp then   -- LK05-T18 : camp, places en plein air (point 8)
        posts = cfg().CAMP and Defense.campPosts(g.home) or nil
    end
    if posts == nil or #(posts.posts or {}) == 0 then
        if st.plan ~= nil then finish(gid, g, st, minute, "home has no post") end
        return nil
    end
    local census = Defense.census(gid, g, players)
    if census.threat > 0 then st.lastThreat = minute end
    if st.plan == nil then
        local A = LivingKnox.Alert
        if census.threat <= 0 or A == nil or A.isActive == nil or not A.isActive(gid, minute) then return nil end
    elseif census.threat <= 0 and minute - (st.lastThreat or minute) >= cfg().END_MINUTES and st.offense == nil then
        finish(gid, g, st, minute, "no threat left")
        return nil
    end
    Defense.stats.plans = Defense.stats.plans + 1
    local members = defenders(gid, g)
    local able = 0
    for _, m in ipairs(members) do
        if m.combatant and m.valid then able = able + 1 end
    end
    local plan = st.plan
    local fresh = plan == nil
    if fresh then
        Defense.state.n = Defense.state.n + 1
        plan = { id = "def-" .. Defense.state.n, since = minute }
        st.plan = plan
        count("started")
    end
    local phase, why = Defense.assess(census.threat, able, plan.phase)
    if census.tx ~= nil then plan.tx, plan.ty = census.tx, census.ty end
    local changed = plan.phase ~= phase
    plan.camp = posts.camp == true
    if changed or plan.shelters == nil then
        plan.shelters = plan.camp and Defense.campShelters(g.home, posts, plan.tx, plan.ty)
            or Defense.shelters(g.home, posts, plan.tx, plan.ty)
    end
    plan.phase, plan.why, plan.census = phase, why, census
    plan.assign = Defense.assign({ phase = phase, posts = posts, shelters = plan.shelters, home = g.home, tx = plan.tx,
        ty = plan.ty, members = members, prev = st.prev, blocked = blockedSet(st, minute) })
    st.prev = {}
    for mid, a in pairs(plan.assign) do st.prev[mid] = a.key end
    if cfg().OFFENSE and not plan.camp then Defense.updateOffense(gid, g, st, plan, census, members, minute, t) end   -- LK06-T09
    if changed then
        local G = Groups()
        local leader = g.leader or "?"
        local text
        if fresh then
            text = string.format("home defense %s (%s, leader %s): %d zombie(s), %d hostile(s), %d able fighter(s) of %d "
                .. "member(s), threat from %s%s", plan.id, phase, leader, census.zombies, census.hostiles, able,
                #members, plan.tx ~= nil and (plan.tx .. "," .. plan.ty) or "?", plan.camp and ", camp" or "")
        elseif phase == "withdraw" then
            text = string.format("home defense %s: leader %s orders everyone inside (%s)", plan.id, leader, why)
        else
            text = string.format("home defense %s: back to the posts (%s)", plan.id, why)
        end
        count(phase == "withdraw" and "withdrawals" or "holds")
        log().info("group %s %s; %s", gid, text, why)
        if G.addLog ~= nil then G.addLog(gid, "defense", text) end
    end
    return plan
end

-- Place bloquée (trajet manqué MAX_FAILS fois) : écartée des plans du groupe pendant BLOCK_MINUTES.
function Defense.noteBlocked(gid, key, minute)
    local st = groupState(gid)
    st.blocked[key] = minute or 0
    st.at = nil   -- plan refait au prochain passage
    count("blocked")
end

-- ================================================================ offensive à la fenêtre (LK06-T09, point 7)

local function Obs() return LivingKnox.Obstacles end

-- Bord de la fenêtre w, même forme que LivingKnox.Obstacles.edge : { key, kind, ax, ay, bx, by, ex, ey, mx, my, z }
-- (a = case ouest ou nord du bord ; la fenêtre est posée sur la case b, dont elle est le bord ouest ou nord).
function Defense.windowEdge(w)
    local sq = w:getSquare()
    if sq == nil then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local e
    if w:getNorth() then
        e = { kind = "N", z = z, ax = x, ay = y - 1, bx = x, by = y, ex = x, ey = y, mx = x + 0.5, my = y }
    else
        e = { kind = "W", z = z, ax = x - 1, ay = y, bx = x, by = y, ex = x, ey = y, mx = x, my = y + 0.5 }
    end
    e.key = e.ex .. "," .. e.ey .. "," .. z .. "," .. e.kind
    return e
end

-- Angle (convention de setDirectionAngle : E 0, S 90, W 180, N 270) qui tourne un corps placé en (px, py) face au
-- bord e (comme Obstacles.faceAngle).
function Defense.faceWindow(e, px, py)
    local west
    if e.kind == "W" then
        west = px < e.ex
        return west and 0 or 180
    end
    west = py < e.ey
    return west and 90 or 270
end

-- Fenêtre w que l'offensive peut ouvrir de l'intérieur (outside : case extérieure). Rend vrai, ou faux et la raison.
-- Verrouillée : ouverte quand même, comme le joueur vanilla de l'intérieur (OpenWindowState.java:128, 167 : seul un
-- personnage dehors est arrêté par le verrou ; IsoWindow.ToggleWindow déverrouille, IsoWindow.java:705-715).
function Defense.canOpen(w, outside)
    if not instanceof(w, "IsoWindow") then return false, "not a window" end
    if w:getSquare() == nil or w:getObjectIndex() == -1 then return false, "window removed" end
    if w:IsOpen() then return false, "window already open" end
    if w:isDestroyed() then return false, "window broken" end
    if w:isBarricaded() then return false, "barricaded window" end
    if w:isPermaLocked() then return false, "window that cannot be opened" end
    local O = Obs()
    if O ~= nil and O.alarmArmed ~= nil and O.alarmArmed(w) then return false, "window of an alarmed house" end
    if outside == nil or not outside:TreatAsSolidFloor() then return false, "window over a drop" end
    return true
end

-- Case du zombie z d'après sa position (LK06-T11) : sur un serveur, getCurrentSquare() de la copie d'un zombie simulé
-- par un client peut manquer ou retarder (campagne MP du 2026-10-15 : zombie à 10653,4 contre la vitre, rapport refusé
-- comme « dans le foyer » faute de case) ; la case de getX/getY/getZ, recalée à chaque paquet du propriétaire, sert de
-- repli. Rend la case ou nil.
function Defense.squareOf(z)
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())) or nil
    return sq or z:getCurrentSquare()
end

-- Objet que frappe le zombie z, ou nil (LK06-T11, point 7 de l'en-tête). Machine qui simule le zombie : getThumpTarget.
-- Serveur, zombie simulé par un client (sa copie n'a jamais de cible de coups : paquet Thump seulement relayé,
-- J/network/packets/character/ThumpPacket.java:54-63) : fenêtre rapportée par le client qui le simule
-- (Senses.thumpOf, commande zombieThumps contrôlée à la réception), gardée seulement si elle est encore là, que l'un
-- de ses côtés est du bâtiment bid (foyer défendu), que le zombie est dehors (hors de bid), au même niveau et à
-- Senses.CHECK.THUMP_REACH cases au plus du milieu du bord. bid nil : rien sur rapport.
function Defense.thumpTargetOf(z, bid)
    local t = z:getThumpTarget()
    if t ~= nil or not isServer() or bid == nil then return t end
    local S = LivingKnox.Senses
    local r = S ~= nil and S.thumpOf ~= nil and S.thumpOf(z:getOnlineID()) or nil
    if r == nil then return nil end
    local w = S.windowAt(r.x, r.y, r.z, r.k)
    local zsq = Defense.squareOf(z)
    local why = nil
    if w == nil then
        why = "window gone"
    elseif zsq == nil then
        why = "no square for the zombie"
    elseif buildingOf(zsq) == bid then
        why = "zombie inside the home"
    elseif math.floor(z:getZ()) ~= r.z or S.edgeDist(z:getX(), z:getY(), r.x, r.y, r.k) > S.CHECK.THUMP_REACH then
        why = "zombie away from the window"
    else
        local e = Defense.windowEdge(w)
        local cell = getCell()
        local sa = e ~= nil and cell:getGridSquare(e.ax, e.ay, e.z) or nil
        local sb = e ~= nil and cell:getGridSquare(e.bx, e.by, e.z) or nil
        if not ((sa ~= nil and buildingOf(sa) == bid) or (sb ~= nil and buildingOf(sb) == bid)) then
            why = "window of another building"
        end
    end
    local key = string.format("%d,%d,%d,%s %s", r.x, r.y, r.z, r.k, tostring(bid))
    local seen = Defense.state.thumps or {}
    Defense.state.thumps = seen
    local o = z:getOnlineID()
    if seen[o] ~= key .. tostring(why) then   -- une ligne par zombie, fenêtre, foyer et issue
        seen[o] = key .. tostring(why)
        log().info("zombie %s thumps window %s,%s,%s,%s (reported by %s): %s for the home building %s", tostring(o), r.x,
            r.y, r.z, r.k, tostring(r.by), why ~= nil and ("ignored, " .. why) or "kept", tostring(bid))
    end
    if why ~= nil then return nil end
    count("thumpReported")
    return w
end

-- Fenêtres du foyer (bâtiment bid, niveau lv) frappées de l'extérieur par un zombie recensé (getThumpTarget, état
-- ThumpState, ou rapport du propriétaire : Defense.thumpTargetOf) : { { w, e, key, inside, outside (cases),
-- thumpers }, ... } triées par clé de bord.
function Defense.thumpedWindows(census, bid, lv)
    local byKey, out = {}, {}
    local cell = getCell()
    if cell == nil or bid == nil then return out end
    for _, ce in ipairs(census and census.list or {}) do
        local z = ce.zombie
        local t = z ~= nil and Defense.thumpTargetOf(z, bid) or nil
        local zsq = z ~= nil and Defense.squareOf(z) or nil
        if t ~= nil and instanceof(t, "IsoWindow") and zsq ~= nil and buildingOf(zsq) ~= bid then
            local e = Defense.windowEdge(t)
            if e ~= nil and e.z == lv then
                local c = byKey[e.key]
                if c == nil then
                    local sa, sb = cell:getGridSquare(e.ax, e.ay, e.z), cell:getGridSquare(e.bx, e.by, e.z)
                    local ina = sa ~= nil and buildingOf(sa) == bid
                    local inb = sb ~= nil and buildingOf(sb) == bid
                    if ina ~= inb then
                        c = { w = t, e = e, key = e.key, inside = ina and sa or sb, outside = ina and sb or sa,
                            thumpers = 0 }
                        byKey[e.key] = c
                        out[#out + 1] = c
                    end
                end
                if c ~= nil then c.thumpers = c.thumpers + 1 end
            end
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Zombies recensés à OFFENSE_WAIT_RADIUS cases (x et y) au plus de la case sq, même niveau ; outsideOf = bid : dehors
-- seulement (hors du bâtiment bid).
local function zombiesNear(census, sq, outsideOf)
    local n = 0
    local R = cfg().OFFENSE_WAIT_RADIUS
    for _, ce in ipairs(census and census.list or {}) do
        local z = ce.zombie
        if z ~= nil and ce.z == sq:getZ() and cheb(ce.x, ce.y, sq:getX(), sq:getY()) <= R then
            local zsq = Defense.squareOf(z)
            if outsideOf == nil or zsq == nil or buildingOf(zsq) ~= outsideOf then n = n + 1 end
        end
    end
    return n
end

-- Choix de l'offensive (pur). phase : phase de la défense ; cands = { { key, waiting, helpers = { { mid, number, d },
-- ... } }, ... } (helpers : combattants valides près de la fenêtre, d = distance au milieu du bord). Rend { key, mid,
-- waiting, helpers } ou nil et la raison. Jamais en repli (groupe débordé) ; fenêtre retenue : la moins assiégée dont
-- les zombies qui attendent restent <= OFFENSE_RATIO x combattants comptés (rapport favorable : ils tombent un par un) ;
-- ouvreur : le plus proche du bord (puis numéro de membre).
function Defense.chooseOffense(phase, cands)
    if phase ~= "hold" then return nil, "group overwhelmed (" .. tostring(phase) .. ")" end
    local ratio = cfg().OFFENSE_RATIO
    local list = {}
    for _, c in ipairs(cands or {}) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        if a.waiting ~= b.waiting then return a.waiting < b.waiting end
        return a.key < b.key
    end)
    local why = "no window thumped"
    for _, c in ipairs(list) do
        local n = #(c.helpers or {})
        if n == 0 then
            why = string.format("window %s: no able member near it", c.key)
        elseif c.waiting > ratio * n then
            why = string.format("window %s: %d zombie(s) waiting > %d x %d able member(s)", c.key, c.waiting, ratio, n)
        else
            local best = nil
            for _, h in ipairs(c.helpers) do
                local better = best == nil
                if not better and (h.posted == true) ~= (best.posted == true) then
                    better = h.posted == true
                elseif not better then
                    better = h.d < best.d or (h.d == best.d and h.number < best.number)
                end
                if better then best = h end
            end
            return { key = c.key, mid = best.mid, waiting = c.waiting, helpers = n }
        end
    end
    return nil, why
end

local function addLog(gid, text)
    local G = Groups()
    if G.addLog ~= nil then G.addLog(gid, "defense", text) end
end

-- Fin de l'offensive du groupe gid (état st) : giveUp écarte la fenêtre OFFENSE_BLOCK_MINUTES.
local function offenseEnd(gid, st, why, giveUp, minute)
    local off = st.offense
    if off == nil then return end
    st.offense = nil
    if giveUp then
        st.offBlocked[off.key] = minute or 0
        count("offenseGivenUp")
    else
        count("offenseEnded")
    end
    local A = LivingKnox.Anim
    if off.state == "opening" and A ~= nil and A.endAct ~= nil then A.endAct(off.npc, "openwindow") end
    if off.state == "closing" and off.actAt ~= nil and A ~= nil and A.endAct ~= nil then
        A.endAct(off.npc, "closewindow")   -- LK06-T11 : geste de refermeture en cours
    end
    local text = string.format("window offensive at %s over: %s", off.key, why)
    log().info("group %s %s", gid, text)
    addLog(gid, text)
end

-- Places de recul autour de la case intérieure inside (bâtiment bid) : un pas vers l'intérieur, à l'opposé de
-- outside, puis les deux cases voisines de celle-ci le long du mur ; praticables et du bâtiment seulement. Toutes à
-- une case (x et y) de la case de chute : à portée de coup et dans la laisse COMBAT_LEASH.
local function backSpots(inside, outside, bid)
    local ix, iy, z = inside:getX(), inside:getY(), inside:getZ()
    local nx, ny = ix - outside:getX(), iy - outside:getY()   -- vers l'intérieur
    local out = {}
    for _, d in ipairs({ { nx, ny }, { nx + ny, ny + nx }, { nx - ny, ny - nx } }) do
        local sq = getCell():getGridSquare(ix + d[1], iy + d[2], z)
        if sq ~= nil and buildingOf(sq) == bid and standable(sq) then
            out[#out + 1] = { x = ix + d[1], y = iy + d[2], z = z }
        end
    end
    return out
end

-- Offensive à la fenêtre du groupe gid pour le plan plan (recensement census, membres de defenders), à la minute de
-- jeu minute et à l'heure t : suivi de l'offensive en cours, ou choix d'une nouvelle (point 7 de l'en-tête).
function Defense.updateOffense(gid, g, st, plan, census, members, minute, t)
    local c = cfg()
    st.offBlocked = st.offBlocked or {}
    local old = {}
    for key, at in pairs(st.offBlocked) do
        if minute - at >= c.OFFENSE_BLOCK_MINUTES then old[#old + 1] = key end
    end
    for _, key in ipairs(old) do st.offBlocked[key] = nil end
    local valid = {}
    for _, m in ipairs(members) do
        if m.combatant and m.valid then valid[m.mid] = m end
    end
    local off = st.offense
    if off ~= nil then
        local w = off.w
        if w:getSquare() == nil or w:getObjectIndex() == -1 then
            offenseEnd(gid, st, "window removed", false, minute)
        elseif off.state == "opening" then
            if w:IsOpen() then
                off.state, off.openedAt = "open", t   -- ouverte par quelqu'un d'autre : la suite est la même
            elseif plan.phase ~= "hold" then
                offenseEnd(gid, st, "group overwhelmed, window kept closed", false, minute)
            elseif w:isDestroyed() or w:isBarricaded() then
                offenseEnd(gid, st, "window broken or barricaded", false, minute)
            elseif valid[off.mid] == nil then
                offenseEnd(gid, st, "opener " .. off.mid .. " unfit or gone", false, minute)
            elseif t - off.since > c.OFFENSE_OPEN_MS then
                offenseEnd(gid, st, "window not opened in time", true, minute)
            end
        elseif off.state == "closing" then
            Defense.followClosing(gid, st, off, valid, minute, t)
        elseif not w:IsOpen() and not w:isDestroyed() then
            offenseEnd(gid, st, "window closed again", false, minute)
        elseif t - off.openedAt > c.OFFENSE_END_MS then
            Defense.startClosing(gid, st, off, valid, "time out", minute, t)
        elseif zombiesNear(census, off.outside, nil) + zombiesNear(census, off.inside, nil) == 0 then
            Defense.startClosing(gid, st, off, valid, "no zombie left at the window", minute, t)
        end
    end
    if st.offense == nil and plan.phase == "hold" and g.home ~= nil then
        local hsq = getCell():getGridSquare(g.home.x, g.home.y, g.home.z)
        local bid = hsq ~= nil and buildingOf(hsq) or nil
        local cands = {}
        for _, w in ipairs(Defense.thumpedWindows(census, bid, g.home.z)) do
            local ok, why = Defense.canOpen(w.w, w.outside)
            if st.offBlocked[w.key] ~= nil then ok, why = false, "window given up a moment ago" end
            if ok then
                w.waiting = zombiesNear(census, w.outside, bid)
                w.bid = bid
                w.helpers = {}
                -- Combattants valides comptés : corps OU place de défense à OFFENSE_HELP_RADIUS cases de la case
                -- intérieure, même niveau (un défenseur en route vers le poste de la fenêtre compte).
                local ix, iy = w.inside:getX(), w.inside:getY()
                for mid, m in pairs(valid) do
                    local body = bodyOf(g.members[mid])
                    local a = plan.assign[mid]
                    local placed = a ~= nil and a.z == w.e.z and cheb(a.x, a.y, ix, iy) <= c.OFFENSE_HELP_RADIUS
                    local near = body ~= nil and math.floor(body:getZ()) == w.e.z
                        and cheb(body:getX(), body:getY(), ix + 0.5, iy + 0.5) <= c.OFFENSE_HELP_RADIUS + 0.5
                    if body ~= nil and (placed or near) then
                        local dx, dy = body:getX() - w.e.mx, body:getY() - w.e.my
                        w.helpers[#w.helpers + 1] = { mid = mid, number = m.number, d = math.sqrt(dx * dx + dy * dy),
                            posted = a ~= nil and a.x == ix and a.y == iy and a.z == w.e.z }
                    end
                end
                table.sort(w.helpers, function(a, b) return a.number < b.number end)
                cands[#cands + 1] = w
            elseif st.offWhy ~= w.key .. why then
                st.offWhy = w.key .. why
                log().debug("group %s: window %s thumped, no offensive: %s", gid, w.key, why)
            end
        end
        local choice, why = nil, nil
        if #cands > 0 then choice, why = Defense.chooseOffense(plan.phase, cands) end
        if choice ~= nil then
            local w
            for _, cd in ipairs(cands) do
                if cd.key == choice.key then w = cd end
            end
            local m = g.members[choice.mid]
            st.offense = { key = w.key, w = w.w, e = w.e, inside = w.inside, outside = w.outside, mid = choice.mid,
                npc = m and m.npc, state = "opening", since = t, waiting = choice.waiting, bid = w.bid,
                backs = backSpots(w.inside, w.outside, w.bid), held = {} }
            count("offenses")
            local text = string.format("window offensive at %s: %s opens it, %d zombie(s) waiting, %d able member(s) "
                .. "near it", w.key, choice.mid, choice.waiting, choice.helpers)
            log().info("group %s %s", gid, text)
            addLog(gid, text)
        elseif why ~= nil and st.offWhy ~= why then
            st.offWhy = why
            count("offenseRefused")
            log().info("group %s: no window offensive: %s", gid, why)
        end
    end
    off = st.offense
    if off ~= nil and (off.state == "open" or off.state == "closing") and #off.backs > 0 then
        -- Fenêtre ouverte : la case intérieure reste libre pour la chute du zombie ; l'ouvreur prend la première
        -- place de recul, le défenseur posté à la fenêtre (s'il est un autre) la suivante : tous deux à une case de
        -- la chute, tournés vers la fenêtre, pour l'achever au sol.
        local ix, iy, iz = off.inside:getX(), off.inside:getY(), off.inside:getZ()
        -- Refermeture (LK06-T11) : l'auteur du geste a sa propre consigne (contextFor) ; l'ouvreur, s'il en est un
        -- autre, et le défenseur posté gardent leurs places de recul : case intérieure libre.
        local order = {}
        local opener = off.opener or off.mid
        local closer = off.state == "closing" and off.mid or nil
        if plan.assign[opener] ~= nil and opener ~= closer then order[1] = opener end
        local posted = {}
        for mid, a in pairs(plan.assign) do
            if mid ~= opener and mid ~= closer and a.x == ix and a.y == iy and a.z == iz then posted[#posted + 1] = mid end
        end
        table.sort(posted)
        for _, mid in ipairs(posted) do order[#order + 1] = mid end
        for i, mid in ipairs(order) do
            local a = plan.assign[mid]
            local b = off.backs[math.min(i, #off.backs)]
            plan.assign[mid] = { role = "post", x = b.x, y = b.y, z = b.z, a = Defense.faceWindow(off.e, b.x + 0.5,
                b.y + 0.5), key = spotKey("post", b.x, b.y, b.z), what = "window", fighter = a.fighter }
        end
    end
    if off ~= nil and (off.state == "opening" or off.state == "open") then Defense.noteHeld(off, census) end
    plan.offense = off ~= nil and { key = off.key, mid = off.mid, state = off.state } or nil
end

-- Zombie z au sol : isOnFloor, ou chute rapportée par le client qui le simule (MP, LivingKnox.Senses.onFloor :
-- la copie du serveur ne voit pas les 2 s à terre après l'enjambée, campagne MP du 2026-10-15).
function Defense.down(z)
    if z:isOnFloor() then return true end
    local S = LivingKnox.Senses
    return S ~= nil and S.onFloor ~= nil and S.onFloor(z)
end

-- Retenue (point 7) : zombies de l'offensive off notés d'après le recensement census : dehors (hors du bâtiment
-- off.bid) à OFFENSE_WAIT_RADIUS cases de la case extérieure, ou en train d'enjamber (climbwindow) près du bord ; un
-- zombie déjà au sol n'est pas noté. Une entrée par clé ({ since }), jamais retirée avant la fin de l'offensive.
function Defense.noteHeld(off, census)
    if not cfg().OFFENSE_HOLD or off.held == nil then return end
    local R = cfg().OFFENSE_WAIT_RADIUS
    local ox, oy, oz = off.outside:getX(), off.outside:getY(), off.outside:getZ()
    for _, ce in ipairs(census and census.list or {}) do
        local z = ce.zombie
        if z ~= nil and off.held[ce.key] == nil and ce.z == oz and cheb(ce.x, ce.y, ox, oy) <= R
            and not Defense.down(z) then
            local zsq = Defense.squareOf(z)
            local outside = zsq == nil or buildingOf(zsq) ~= off.bid
            if outside or z:getActionStateName() == "climbwindow" then off.held[ce.key] = { since = now() } end
        end
    end
end

-- Vrai si le zombie z (clé key) ne doit pas être engagé par un membre du groupe gid : zombie de l'offensive en cours
-- (ouverture ou attente de la chute) pas encore au sol (point 7, retenue). Lève la retenue de ce zombie pour de bon
-- quand il est au sol, entré debout depuis OFFENSE_STAND_MS, ou OFFENSE_FALL_MS après l'ouverture.
function Defense.offenseHolds(gid, z, key)
    local st = gid ~= nil and Defense.state.groups[gid] or nil
    local off = st and st.offense or nil
    if off == nil or off.held == nil or (off.state ~= "opening" and off.state ~= "open") then return false end
    local h = off.held[key]
    if h == nil or h.free ~= nil then return false end
    local c = cfg()
    local t = now()
    local why = nil
    if Defense.down(z) then
        why = "on the floor"
    elseif off.openedAt ~= nil and t - off.openedAt >= c.OFFENSE_FALL_MS then
        why = "not fallen " .. c.OFFENSE_FALL_MS .. " ms after the opening"
    else
        local zsq = Defense.squareOf(z)
        if zsq ~= nil and buildingOf(zsq) == off.bid and z:getActionStateName() ~= "climbwindow" then
            h.standing = h.standing or t
            if t - h.standing >= c.OFFENSE_STAND_MS then why = "came in standing" end
        else
            h.standing = nil
        end
    end
    if why ~= nil then
        h.free = why
        count("offenseFreed")
        log().info("group %s: window offensive at %s: zombie %s %s, members may hit it", tostring(gid), off.key,
            tostring(key), why)
        return false
    end
    if not h.told then
        h.told = true
        log().info("group %s: window offensive at %s: zombie %s left alone until it falls inside", tostring(gid),
            off.key, tostring(key))
    end
    count("offenseHeld")
    return true
end

-- Distance du corps body au milieu du bord e.
local function edgeGap(body, e)
    local dx, dy = body:getX() - e.mx, body:getY() - e.my
    return math.sqrt(dx * dx + dy * dy)
end

-- Auteur de la refermeture (LK06-T11) parmi les membres valides valid : l'ouvreur s'il l'est encore, sinon le plus
-- proche du milieu du bord au niveau de la fenêtre (puis numéro). Rend mid ou nil.
function Defense.chooseCloser(g, off, valid)
    local opener = off.opener or off.mid
    if valid[opener] ~= nil and bodyOf(g.members[opener]) ~= nil then return opener end
    local best, bestD, bestN = nil, nil, nil
    for mid, m in pairs(valid) do
        local body = bodyOf(g.members[mid])
        if body ~= nil and math.floor(body:getZ()) == off.e.z then
            local d = edgeGap(body, off.e)
            if best == nil or d < bestD or (d == bestD and (m.number or 0) < bestN) then
                best, bestD, bestN = mid, d, m.number or 0
            end
        end
    end
    return best
end

-- Fin de l'offensive, fenêtre ouverte (why : raison) : refermeture par un membre (OFFENSE_CLOSE), sinon fin.
function Defense.startClosing(gid, st, off, valid, why, minute, t)
    local G = Groups()
    local g = G.get ~= nil and G.get(gid) or nil
    if not cfg().OFFENSE_CLOSE or g == nil then
        offenseEnd(gid, st, why, false, minute)
        return
    end
    off.opener = off.opener or off.mid
    off.state, off.closeSince, off.closeWhy = "closing", t, why
    off.actAt, off.toggleAt = nil, nil
    local mid = Defense.chooseCloser(g, off, valid)
    off.mid = mid or off.opener
    local m = g.members[off.mid]
    off.npc = m and m.npc or nil
    st.at = nil   -- plan refait au prochain passage
    local text = string.format("window offensive at %s: %s, %s closes the window", off.key, why, off.mid)
    log().info("group %s %s", gid, text)
    addLog(gid, text)
end

-- Suivi de la refermeture (plan du groupe) : fenêtre disparue, déjà fermée, brisée ou barricadée : fin ; délai
-- OFFENSE_CLOSE_MS dépassé : fenêtre laissée ouverte ; auteur inapte ou parti : un autre membre.
function Defense.followClosing(gid, st, off, valid, minute, t)
    local w = off.w
    local A = LivingKnox.Anim
    if not w:IsOpen() then
        offenseEnd(gid, st, "window closed (" .. off.closeWhy .. ")", false, minute)
    elseif w:isDestroyed() or w:isBarricaded() then
        offenseEnd(gid, st, "window broken or barricaded, left as it is (" .. off.closeWhy .. ")", false, minute)
    elseif t - off.closeSince > cfg().OFFENSE_CLOSE_MS then
        count("closeGivenUp")
        offenseEnd(gid, st, "window left open: not closed in time, its squares stay occupied or no member reached "
            .. "it (" .. off.closeWhy .. ")", false, minute)
    elseif valid[off.mid] == nil then
        local G = Groups()
        local g = G.get ~= nil and G.get(gid) or nil
        local mid = g ~= nil and Defense.chooseCloser(g, off, valid) or nil
        if mid ~= nil and mid ~= off.mid then
            if A ~= nil and A.endAct ~= nil and off.actAt ~= nil then A.endAct(off.npc, "closewindow") end
            log().info("group %s: window %s: closer %s unfit or gone, %s closes it", gid, off.key, off.mid, mid)
            off.mid, off.npc, off.actAt, off.toggleAt = mid, g.members[mid].npc, nil, nil
        end
    end
end

-- Objet mobile (zombie vivant, corps de PNJ en escalade, joueur, véhicule) sur l'une des deux cases du bord de
-- l'offensive off, l'objet except (auteur du geste), les corps de PNJ debout et les personnages morts exceptés ;
-- les cadavres (IsoDeadBody) ne sont pas des objets mobiles de la case.
function Defense.windowBusy(off, except)
    local cell = getCell()
    for _, p in ipairs({ { off.e.ax, off.e.ay }, { off.e.bx, off.e.by } }) do
        local sq = cell:getGridSquare(p[1], p[2], off.e.z)
        local list = sq ~= nil and sq:getMovingObjects() or nil
        for i = 0, (list ~= nil and list:size() or 0) - 1 do
            local o = list:get(i)
            -- Personnage mort encore sur la case (animation de mort avant le cadavre) : ne compte pas.
            local dead = instanceof(o, "IsoGameCharacter") and o:isDead()
            -- Corps de PNJ debout sur une case du bord, hors escalade (campagne MP du 2026-10-15 : l'ouvreur resté sur
            -- la case intérieure après la mise à mort bloquait la refermeture par un autre membre, fenêtre laissée
            -- ouverte) : il ne gêne pas la vitre, comme le joueur vanilla qui la ferme depuis cette case.
            local npc = not dead and instanceof(o, "IsoZombie") and o:hasModData()
                and LivingKnox.Identity.readTag(o:getModData()) ~= nil
            local climbing = npc and string.find(tostring(o:getActionStateName()), "^climb") ~= nil
            if o ~= except and not dead and not (npc and not climbing) then return true, o end
        end
    end
    return false
end

-- Fermeture de la fenêtre à l'instant du geste closewindow (Defense.tick). Rend vrai si fermée.
function Defense.closeNow(gid, st, off, t)
    off.toggleAt = nil
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find(off.npc) or nil
    local A = LivingKnox.Anim
    if body == nil or body:isDead() or A == nil or A.actOf(off.npc) ~= "closewindow" then
        off.actAt = nil   -- geste interrompu : nouvel essai au passage suivant de la cascade
        return false
    end
    local busy, who = Defense.windowBusy(off, body)
    if busy then
        count("closeWaits")
        if not off.busyTold then   -- une ligne par offensive : ce qui occupe l'embrasure (diagnostic MP)
            off.busyTold = true
            local what = who ~= nil and tostring(who.getObjectName and who:getObjectName() or who) or "?"
            if instanceof(who, "IsoZombie") then
                local nid = who:hasModData() and LivingKnox.Identity.readTag(who:getModData()) or nil
                what = (nid ~= nil and ("body of " .. tostring(nid)) or ("zombie z:" .. tostring(who:getOnlineID())))
            elseif instanceof(who, "IsoPlayer") then
                what = "player " .. tostring(who:getUsername())
            end
            log().info("group %s: window %s not closed yet: %s at %.1f,%.1f on its squares", gid, off.key, what,
                who ~= nil and who:getX() or -1, who ~= nil and who:getY() or -1)
        end
        if A.endAct ~= nil then A.endAct(off.npc, "closewindow") end
        off.actAt = nil   -- embrasure occupée : nouveau geste au passage suivant (abandon après OFFENSE_CLOSE_MS)
        log().debug("group %s: window %s not closed: its squares are occupied", gid, off.key)
        return false
    end
    local O = Obs()
    if O ~= nil and O.setWindow ~= nil then
        O.setWindow(off.w, false, body)
    elseif off.w:IsOpen() then
        off.w:ToggleWindow(body)
    end
    if off.w:IsOpen() then
        off.actAt = nil
        return false
    end
    count("windowsClosed")
    local text = string.format("window offensive at %s: %s closed the window", off.key, off.mid)
    log().info("group %s %s", gid, text)
    addLog(gid, text)
    off.state = "closed"
    offenseEnd(gid, st, "window closed (" .. tostring(off.closeWhy) .. ")", false, st.minute)
    return true
end

-- Bascule de la fenêtre de l'offensive off du groupe gid à l'instant du geste (Defense.tick). Rend vrai si ouverte.
function Defense.openNow(gid, st, off, t)
    off.toggleAt = nil
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find(off.npc) or nil
    local A = LivingKnox.Anim
    if body == nil or body:isDead() or A == nil or A.actOf(off.npc) ~= "openwindow" then
        off.actAt = nil   -- geste interrompu : nouvel essai au passage suivant de la cascade
        return false
    end
    local ok, why = Defense.canOpen(off.w, off.outside)
    if not ok then
        offenseEnd(gid, st, why, false, st.minute)
        return false
    end
    local O = Obs()
    if O ~= nil and O.setWindow ~= nil then
        O.setWindow(off.w, true, body)
    else
        off.w:ToggleWindow(body)   -- vanilla : OpenWindowState.onSuccess, IsoWindow.ToggleWindow
    end
    if not off.w:IsOpen() then
        offenseEnd(gid, st, "window did not open", true, st.minute)
        return false
    end
    off.state, off.openedAt = "open", t
    count("windowsOpened")
    st.at = nil   -- plan refait au prochain passage : défenseur de la fenêtre en recul
    local text = string.format("window offensive at %s: %s opened the window, %d zombie(s) waiting", off.key, off.mid,
        off.waiting or 0)
    log().info("group %s %s", gid, text)
    addLog(gid, text)
    return true
end

-- OnTick (autorité) : fenêtres basculées à l'instant du geste d'ouverture, au plus toutes les OFFENSE_TICK_MS.
function Defense.tick()
    if not LivingKnox.isAuthority() then return end
    local s = Defense.state
    local t = now()
    if s.lastTick ~= nil and t - s.lastTick < cfg().OFFENSE_TICK_MS then return end
    s.lastTick = t
    local due = {}
    for gid, st in pairs(s.groups) do
        local off = st.offense
        if off ~= nil and (off.state == "opening" or off.state == "closing") and off.toggleAt ~= nil
            and t >= off.toggleAt then
            due[#due + 1] = gid
        end
    end
    table.sort(due)
    for _, gid in ipairs(due) do
        local st = s.groups[gid]
        if st.offense.state == "closing" then
            Defense.closeNow(gid, st, st.offense, t)
        else
            Defense.openNow(gid, st, st.offense, t)
        end
    end
end

-- ================================================================ cascade (autorité)

local function sameLevel(a, b) return math.floor(a:getZ()) == math.floor(b:getZ()) end

local function distTo(body, o)
    local dx, dy = o:getX() - body:getX(), o:getY() - body:getY()
    return math.sqrt(dx * dx + dy * dy)
end

local function lineOfFire(body, o)
    local C = LivingKnox.Combat
    if C == nil or C.lineOfFire == nil then return false end
    return C.lineOfFire(body, o) == true
end

-- LK06-T14 : zone de sortie (cases) du PNJ npcId, membre valide en phase « hold » : portée d'engagement des zombies
-- de son rôle (Zombies.engageRange : option ZombieEngage<Rôle>, bornée par ZombieAlertDistance), repli
-- CFG.ENGAGE_RANGE ; sans npcId : rôle fighter.
function Defense.engageRange(npcId)
    local Zm = LivingKnox.Zombies
    if Zm ~= nil and Zm.engageRange ~= nil then return Zm.engageRange(npcId) end
    return cfg().ENGAGE_RANGE
end

-- Sortie permise au PNJ npcId à la place a pendant la phase phase : vrai et la laisse (cases), ou faux et
-- COMBAT_LEASH. Sortie : phase « hold » et place de combattant valide (a.fighter) ; jamais en repli ni pour un membre
-- inapte.
function Defense.leashFor(a, phase, npcId)
    if phase == "hold" and a ~= nil and a.fighter == true then return true, Defense.engageRange(npcId) end
    return false, cfg().COMBAT_LEASH
end

-- Cible o gardée par l'ordre de combat de laisse r autour de la place a (règle de Combat.step, LK05-T09) : dans la
-- laisse (même niveau que la place, à r cases au plus en x et en y, cases entières), ou au même niveau que le corps à
-- reach cases au plus (portée de l'arme w ; arme à feu : avec une ligne de tir dégagée). Pur sauf la ligne de tir.
function Defense.held(body, o, d, a, r, w)
    local oz = math.floor(o:getZ())
    if oz == a.z and cheb(math.floor(o:getX()), math.floor(o:getY()), a.x, a.y) <= r then return true end
    if w == nil or oz ~= math.floor(body:getZ()) or d > w.reach then return false end
    return w.ranged ~= true or lineOfFire(body, o)
end

-- Cible du membre (corps body, contexte ctx de la cascade, place a, recensement census, phase de la défense) :
-- { kind = "zombie", u, d, reason, zombie, around } ou { u, d, reason } (joueur, cible de la cascade seulement), ou
-- nil ; around (LK06-T14) : zombie vu sans ligne de coup, rejoint par le chemin. Voir l'en-tête (point 4).
function Defense.targetFor(id, body, ctx, a, census, phase)
    local c = cfg()   -- LK06-T07 : tout membre ; LK06-T14 : sortie des membres valides en « hold »
    local C = LivingKnox.Combat
    local w = C ~= nil and C.weaponOf ~= nil and C.weaponOf(id) or nil
    local sally, r = Defense.leashFor(a, phase, id)
    local zone = sally and r + 1 or c.POST_LEASH
    local near = cheb(body:getX(), body:getY(), a.x + 0.5, a.y + 0.5) <= zone and math.floor(body:getZ()) == a.z
    local function held(o, d) return Defense.held(body, o, d, a, r, w) end
    local Zm = LivingKnox.Zombies
    local gid = ctx.gid
    local function spared(z, key)   -- point 7 : zombie de l'offensive pas encore tombé
        return Defense.offenseHolds(gid, z, key or (Zm ~= nil and Zm.keyOf(z)) or "?")
    end
    if not near then
        -- Sortie en cours (corps sorti de la zone en contournant le bâtiment) : le zombie engagé est gardé tant que
        -- la laisse le garde, sans retour au poste à mi-chemin.
        local cur = sally and C ~= nil and C.orders ~= nil and C.orders[id] or nil
        local cz = cur ~= nil and cur.k == "zombie" and cur.zt or nil
        if cz ~= nil and Zm ~= nil and Zm.isVanilla(cz) and Zm.inWorld(cz) and held(cz, distTo(body, cz))
            and not spared(cz, cur.u) then
            return { kind = "zombie", u = cur.u, d = distTo(body, cz), reason = "home defense", zombie = cz,
                around = cur.leash ~= nil and cur.leash.around == true }
        end
        -- En route : seulement se défendre d'une menace au contact, gardée par la laisse.
        local tg = ctx.target
        if tg ~= nil and (tg.d or 99) <= c.MELEE_ENGAGE then
            local o = tg.zombie
            if o == nil and tg.kind ~= "zombie" and C ~= nil and C.playerByName ~= nil then o = C.playerByName(tg.u) end
            if o ~= nil and held(o, distTo(body, o)) and not (tg.zombie ~= nil and spared(o, tg.u)) then return tg end
        end
        return nil
    end
    local ranged = a.role == "post" and w ~= nil and w.ranged == true
    local function ok(o, d)
        if not sameLevel(body, o) then return false end
        if d <= c.MELEE_ENGAGE then return held(o, d) end
        return ranged and d <= w.reach and lineOfFire(body, o)
    end
    -- Joueur : cible retenue par la cascade (attitude, aide, trêve, reddition).
    local tg = ctx.target
    if tg ~= nil and tg.kind ~= "zombie" then
        local p = C ~= nil and C.playerByName ~= nil and C.playerByName(tg.u) or nil
        if p ~= nil and not p:isDead() and ok(p, distTo(body, p)) then return tg end
    end
    if Zm == nil then return nil end
    local cands, seen = {}, {}
    local function add(z, key)
        if seen[key] == nil and z ~= nil and Zm.isVanilla(z) and Zm.inWorld(z) and sameLevel(body, z)
            and not spared(z, key) then
            seen[key] = true
            cands[#cands + 1] = { z = z, key = key, d = distTo(body, z) }
        end
    end
    for _, e in ipairs(census and census.list or {}) do
        if e.zombie ~= nil then add(e.zombie, e.key) end
    end
    if sally then   -- zombies de la zone, recensés ou non (le recensement est centré sur le foyer)
        local cell = getCell()
        local zl = cell ~= nil and cell:getZombieList() or nil
        for i = 0, (zl ~= nil and zl:size() or 0) - 1 do
            local z = zl:get(i)
            if z ~= nil and math.floor(z:getZ()) == a.z and math.abs(math.floor(z:getX()) - a.x) <= r
                and math.abs(math.floor(z:getY()) - a.y) <= r and Zm.isVanilla(z) then
                add(z, Zm.keyOf(z))
            end
        end
    end
    table.sort(cands, function(x, y)
        if x.d ~= y.d then return x.d < y.d end
        return x.key < y.key
    end)
    local tries = 0
    local function target(cd)
        return { kind = "zombie", u = cd.key, d = cd.d, reason = "home defense", zombie = cd.z }
    end
    for _, cd in ipairs(cands) do
        local z = cd.z
        if cd.d <= c.MELEE_ENGAGE then
            if (lineOfFire(body, z) or cd.d <= 1.5) and held(z, cd.d) then return target(cd) end
        elseif ranged and cd.d <= w.reach then
            tries = tries + 1
            if tries > c.MAX_TARGET_TRIES then break end
            if lineOfFire(body, z) then return target(cd) end
        elseif sally and held(z, cd.d) and C ~= nil and C.lineOfStrike ~= nil then
            -- LK06-T14 : sortie de mêlée vers un zombie vu (Zombies.sees) ; sans ligne de coup directe (vu derrière une
            -- vitre), le membre le rejoint par son chemin (porte, ouverture : Combat.engage, leash.around), sauf un
            -- zombie qui frappe le bâtiment (getThumpTarget : fenêtre, porte, barricade), laissé au contact et à
            -- l'offensive à la fenêtre (point 7). Jamais de coup à travers une vitre fermée (Combat.lineOfStrike).
            tries = tries + 1
            if tries > c.MAX_TARGET_TRIES then break end
            if (C.lineOfStrike(body, z)) then return target(cd) end
            local asq = getCell():getGridSquare(a.x, a.y, a.z)   -- place du membre : dans le foyer
            if Defense.thumpTargetOf(z, asq and buildingOf(asq) or nil) == nil and (Zm.sees(body, z)) then
                local out = target(cd)
                out.around = true
                return out
            end
        elseif not sally then
            break   -- triées par distance : plus rien à portée
        end
    end
    return nil
end

-- Entrée de la cascade (LivingKnox.Decisions.context) : rôle du membre mid dans la défense du foyer, ou nil. Rend
-- { id (défense), phase, role, x, y, z, a, key = "def:<rôle> x,y,z", why, target, sally, leash (cases, LK06-T14) }.
function Defense.contextFor(gid, g, mid, m, body, ctx, players, minute)
    local plan = Defense.update(gid, g, minute, players)
    if plan == nil then return nil end
    local a = plan.assign[mid]
    if a == nil then return nil end
    local out = { id = plan.id, phase = plan.phase, role = a.role, x = a.x, y = a.y, z = a.z, a = a.a, key = "def:" .. a.key,
        what = a.what, fighter = a.fighter }
    local cs = plan.census
    local off = plan.offense   -- LK06-T09 : ouvreur de la fenêtre, aucune autre cible le temps d'ouvrir
    if off ~= nil and off.state == "opening" and off.mid == mid then
        out.offense = { key = off.key }
        out.key = "def:offense " .. off.key
        out.why = string.format("home defense %s %s: opening the window %s for the zombie(s) at it (%d zombie(s), "
            .. "%d hostile(s))", plan.id, plan.phase, off.key, cs.zombies, cs.hostiles)
        return out
    end
    if off ~= nil and off.state == "closing" and off.mid == mid then   -- LK06-T11 : refermeture
        out.offense = { key = off.key, close = true }
        out.key = "def:close " .. off.key
        out.why = string.format("home defense %s %s: closing the window %s after the offensive", plan.id, plan.phase,
            off.key)
        return out
    end
    out.sally, out.leash = Defense.leashFor(a, plan.phase, m.npc)   -- LK06-T14 : zone de sortie, ou COMBAT_LEASH
    out.target = Defense.targetFor(m.npc, body, ctx, a, plan.census, plan.phase)
    out.why = string.format("home defense %s %s: %s %d,%d,%d (%d zombie(s), %d hostile(s)%s)", plan.id, plan.phase,
        a.role, a.x, a.y, a.z, cs.zombies, cs.hostiles, out.target ~= nil and (", engaging " .. tostring(out.target.u))
        or "")
    return out
end

-- ================================================================ exécution (autorité)

local function note(id, mem, v, why, what)
    if not Decisions().noteIssued(id, v, why) then
        count("refused")
        return false
    end
    mem.lastV = v
    count(what)
    return true
end

local function entryOf(id)
    local D = LivingKnox.Directives
    return D ~= nil and D.get ~= nil and D.get(id) or nil
end

-- Course vers la place : "here", "moving" ou "failed".
local function goTo(id, ctx, dv, mem, e)
    local D = LivingKnox.Directives
    if ctx.z == dv.z then
        local dx, dy = ctx.x - (dv.x + 0.5), ctx.y - (dv.y + 0.5)
        if math.sqrt(dx * dx + dy * dy) <= D.ARRIVE then return "here" end
    end
    if mem.moveV ~= nil and e ~= nil and e.v == mem.moveV then
        if not e.done then return "moving" end
        if e.s == "arrived" then return "here" end
        mem.fails = mem.fails + 1
        mem.moveV = nil
    end
    if mem.fails >= cfg().MAX_FAILS then return "failed" end
    local v, why = D.moveTo(id, dv.x, dv.y, dv.z, "run")
    if not note(id, mem, v, why, "moves") then
        mem.fails = mem.fails + 1
        log().debug("npc %s: defense move to %d,%d,%d refused: %s", id, dv.x, dv.y, dv.z, tostring(why))
        return mem.fails >= cfg().MAX_FAILS and "failed" or "moving"
    end
    mem.moveV = v
    return "moving"
end

-- Ouvreur de l'offensive (comportement « defend », Defense.apply) : course vers la case intérieure de la fenêtre,
-- puis geste openwindow tourné vers elle (la fenêtre s'ouvre à l'instant du clip, Defense.tick). LK06-T11 : même
-- conduite pour la refermeture (dv.offense.close : geste closewindow, fermeture par Defense.tick).
local function applyOpener(id, ctx, dv)
    local C = LivingKnox.Combat
    if C ~= nil and C.leave ~= nil then C.leave(id) end   -- garde derrière la vitre interrompue
    local st = Defense.state.groups[ctx.gid]
    local off = st and st.offense or nil
    local close = dv.offense.close == true   -- LK06-T11 : refermeture
    local want = close and "closing" or "opening"
    if off == nil or off.key ~= dv.offense.key or off.state ~= want or off.actAt ~= nil then return end
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find(id) or nil
    if body == nil then return end
    local e = off.e
    local dx, dy = body:getX() - e.mx, body:getY() - e.my
    local A = LivingKnox.Anim
    if math.floor(body:getZ()) == e.z and math.sqrt(dx * dx + dy * dy) <= cfg().OFFENSE_REACH then
        local g = close and "closewindow" or "openwindow"
        local ok, why = A.startAct(id, g, close and cfg().OFFENSE_CLOSE_GESTURE_MS or cfg().OFFENSE_OPEN_GESTURE_MS,
            Defense.faceWindow(e, body:getX(), body:getY()))
        if not ok then
            log().warn("npc %s: %s gesture at %s refused: %s", id, g, off.key, tostring(why))
            return
        end
        off.actAt = now()
        off.toggleAt = off.actAt + (close and cfg().OFFENSE_CLOSE_TOGGLE_MS or cfg().OFFENSE_OPEN_TOGGLE_MS)
        count(close and "closeGestures" or "offenseGestures")
        if close then
            log().info("npc %s: closing the window %s after the offensive", id, off.key)
        else
            log().info("npc %s: opening the window %s for the zombie(s) at it", id, off.key)
        end
        return
    end
    local key = (close and "close:" or "off:") .. off.key
    local mem = Defense.state.npcs[id]
    if mem == nil or mem.key ~= key then
        mem = { key = key, fails = 0 }
        Defense.state.npcs[id] = mem
    end
    local res = goTo(id, ctx, { x = off.inside:getX(), y = off.inside:getY(), z = off.inside:getZ() }, mem, entryOf(id))
    if res == "failed" and not mem.gaveUp then
        mem.gaveUp = true
        log().info("npc %s: cannot reach the window %s to %s it", id, off.key, close and "close" or "open")
    end
end
Defense.applyOpener = applyOpener

-- Comportement « defend » (appelé par Decisions.apply à chaque passage) : engagement, ou place, regard et geste.
function Defense.apply(id, st, ctx, fresh)
    local dv = ctx.defense
    if dv == nil then return end
    if dv.offense ~= nil then   -- LK06-T09 : ouvreur de la fenêtre (LK06-T11 : ou auteur de la refermeture)
        applyOpener(id, ctx, dv)
        return
    end
    local C = LivingKnox.Combat
    if dv.target ~= nil and C ~= nil and C.engage ~= nil then
        local tg = dv.target
        local before = C.get ~= nil and C.get(id) or nil
        local c, why = C.engage(id, tg.kind == "zombie" and tg.zombie or tg.u, { source = "decisions",
            why = "home defense " .. dv.id .. ": " .. tostring(tg.reason),
            leash = { x = dv.x, y = dv.y, z = dv.z, r = dv.leash or cfg().COMBAT_LEASH,
                around = dv.sally == true and tg.around == true } })
        if c ~= nil then
            if before == nil or before.c ~= c then count("engaged") end
            if fresh and C.step ~= nil then C.step(id) end
            return
        end
        log().debug("npc %s: defense engagement refused: %s", id, tostring(why))
    end
    if C ~= nil and C.leave ~= nil then C.leave(id) end   -- plus de cible : retour à la place
    local mem = Defense.state.npcs[id]
    if mem == nil or mem.key ~= dv.key then
        mem = { key = dv.key, fails = 0 }
        Defense.state.npcs[id] = mem
    end
    local e = entryOf(id)
    if mem.lastV ~= nil and (e == nil or e.v ~= mem.lastV) then   -- autre consigne entre-temps (combat, test)
        mem.lastV, mem.moveV, mem.faced, mem.fails = nil, nil, nil, 0
    end
    local res = goTo(id, ctx, dv, mem, e)
    if res == "moving" then return end
    if res == "here" then mem.reached = true end
    if res == "failed" and not mem.gaveUp then
        mem.gaveUp = true
        log().info("npc %s: cannot reach its defense place %s, another place next time", id, dv.key)
        Defense.noteBlocked(ctx.gid, string.sub(dv.key, 5), ctx.minute)
    end
    local a = dv.a
    if a ~= nil and (mem.faced == nil or angleGap(a, mem.faced) >= cfg().FACE_DELTA) then
        if note(id, mem, LivingKnox.Directives.face(id, a), nil, "faces") then mem.faced = a end
    end
    Decisions().setAlertGesture(id, dv.fighter and "guard" or "crouch")   -- après « face », qui remet le repos
end

-- ================================================================ lecture, mémoire

-- Plan en cours du groupe gid (copie partielle), ou nil : { id, phase, why, since, tx, ty, zombies, hostiles, threat,
-- assign = { [mid] = { role, x, y, z, key } } }.
function Defense.get(gid)
    local st = Defense.state.groups[gid]
    local p = st and st.plan or nil
    if p == nil then return nil end
    local assign = {}
    for mid, a in pairs(p.assign or {}) do assign[mid] = { role = a.role, x = a.x, y = a.y, z = a.z, key = a.key } end
    local cs = p.census or {}
    local off = p.offense   -- LK06-T09
    return { id = p.id, phase = p.phase, why = p.why, since = p.since, tx = p.tx, ty = p.ty, camp = p.camp == true,
        zombies = cs.zombies,
        hostiles = cs.hostiles, threat = cs.threat, assign = assign,
        offense = off ~= nil and { key = off.key, mid = off.mid, state = off.state } or nil }
end

-- Marque de la dernière attaque repoussée du groupe gid (point d'appel des soins, LK07-T03), ou nil.
function Defense.after(gid)
    local a = Defense.state.after[gid]
    if a == nil then return nil end
    local wounded = {}
    for i, mid in ipairs(a.wounded) do wounded[i] = mid end
    return { id = a.id, minute = a.minute, minutes = a.minutes, wounded = wounded, why = a.why }
end

function Defense.forget(id)
    Defense.state.npcs[id] = nil
end

function Defense.forgetGroup(gid)
    Defense.state.groups[gid] = nil
    Defense.state.after[gid] = nil
end

function Defense.reset()
    Defense.state = { groups = {}, npcs = {}, after = {}, n = 0 }
end

local function onTick()
    LivingKnox.Defense.tick()
end

LivingKnox.subscribe("OnTick", "Defense.tick", onTick)   -- LK06-T09 : bascule des fenêtres à l'instant du geste

return Defense
