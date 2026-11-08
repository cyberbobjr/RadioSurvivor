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
--      fermée ; un zombie vu seulement derrière une vitre est rejoint par une porte, point 7), au plus
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
-- 7. Zombie à une fenêtre (E18-T34, décision de l'utilisateur du 2026-11-07) : plus d'offensive à la fenêtre (ouvrir
--    pour le laisser tomber dedans, LK06-T09, retirée : instable en MP, le zombie étant simulé par un client). Un
--    zombie qui frappe le bâtiment est une cible de sortie comme une autre (point 4) : vu derrière la vitre, un membre
--    valide sort le rejoindre par une porte et l'attaque dehors ; débordé, le groupe reste à l'intérieur (repli).
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
for k, v in pairs({
    ENGAGE_RANGE = 10,       -- LK06-T14 : zone de sortie (cases) sans LivingKnox.Zombies (repli de engageRange)
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
    elseif census.threat <= 0 and minute - (st.lastThreat or minute) >= cfg().END_MINUTES then
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
    -- Zombie engagé par la sortie en cours, gardé tant que la laisse le garde (aroundOnly : sortie par le chemin
    -- seulement), ou nil.
    local function engaged(aroundOnly)
        local cur = sally and C ~= nil and C.orders ~= nil and C.orders[id] or nil
        local cz = cur ~= nil and cur.k == "zombie" and cur.zt or nil
        local around = cur ~= nil and cur.leash ~= nil and cur.leash.around == true
        if cz == nil or (aroundOnly and not around) then return nil end
        if Zm ~= nil and Zm.isVanilla(cz) and Zm.inWorld(cz) and held(cz, distTo(body, cz)) then
            return { kind = "zombie", u = cur.u, d = distTo(body, cz), reason = "home defense", zombie = cz,
                around = around }
        end
        return nil
    end
    if not near then
        -- Sortie en cours (corps sorti de la zone en contournant le bâtiment) : le zombie engagé est gardé tant que
        -- la laisse le garde, sans retour au poste à mi-chemin.
        local kept = engaged(false)
        if kept ~= nil then return kept end
        -- En route : seulement se défendre d'une menace au contact, gardée par la laisse.
        local tg = ctx.target
        if tg ~= nil and (tg.d or 99) <= c.MELEE_ENGAGE then
            local o = tg.zombie
            if o == nil and tg.kind ~= "zombie" and C ~= nil and C.playerByName ~= nil then o = C.playerByName(tg.u) end
            if o ~= nil and held(o, distTo(body, o)) then return tg end
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
    -- E18-T34 : sortie par le chemin (zombie vu derrière une vitre) en cours dans la zone : le membre en route vers la
    -- porte ne voit plus le zombie ; il le garde au lieu de revenir à son poste (campagne MP du 2026-11-08,
    -- runs/20261108-013343-mp-004614dab2ad : aller-retour poste-porte toutes les 10 s, zombie entré par la vitre).
    local kept = engaged(true)
    if kept ~= nil then return kept end
    local cands, seen = {}, {}
    local function add(z, key)
        if seen[key] == nil and z ~= nil and Zm.isVanilla(z) and Zm.inWorld(z) and sameLevel(body, z) then
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
            -- vitre), le membre le rejoint par son chemin (porte, ouverture : Combat.engage, leash.around), y compris
            -- un zombie qui frappe le bâtiment (E18-T34, décision de l'utilisateur du 2026-11-07 : sortir l'attaquer
            -- dehors au lieu de lui ouvrir la fenêtre). Jamais de coup à travers une vitre fermée (Combat.lineOfStrike).
            tries = tries + 1
            if tries > c.MAX_TARGET_TRIES then break end
            if (C.lineOfStrike(body, z)) then return target(cd) end
            if Zm.sees(body, z) then
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

-- Comportement « defend » (appelé par Decisions.apply à chaque passage) : engagement, ou place, regard et geste.
function Defense.apply(id, st, ctx, fresh)
    local dv = ctx.defense
    if dv == nil then return end
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
    return { id = p.id, phase = p.phase, why = p.why, since = p.since, tx = p.tx, ty = p.ty, camp = p.camp == true,
        zombies = cs.zombies,
        hostiles = cs.hostiles, threat = cs.threat, assign = assign }
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

return Defense
