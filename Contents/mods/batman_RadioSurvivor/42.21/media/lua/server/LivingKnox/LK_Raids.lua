-- Living Knox : raids des groupes pillards sur les bases des joueurs (LK11-T07). Fiche : docs/conception/raids.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...). Autorité seulement (serveur dédié ou hébergé, solo) : un client MP
-- charge aussi media/lua/server, il s'arrête ici.
--
-- Décision du 2026-10-08 (docs/plan/LK11-interactions-joueurs.md) : raids rares et annoncés ; base repérée par ses
-- signes d'occupation ; éclaireurs qu'on peut éliminer pour annuler le raid ; attaque par l'effectif réel parti du
-- foyer pillard ; fréquence réglable et désactivable (options sandbox LivingKnox.RaidsEnabled, LivingKnox.RaidDays).
--
-- 1. Repérage (Raids.survey, chaque heure de jeu, cases chargées autour des joueurs) : la base d'un joueur est le
--    refuge vanilla où il se tient (SafeHouse.getSafeHouse(case), J/iso/areas/SafeHouse.java:137-150, 184-200), sinon le
--    bâtiment de sa case (getBuildingDef, par la pièce). Signes lus par le serveur sur les cases chargées de la base
--    (Raids.signs) : refuge vanilla (3 points), générateur allumé (IsoGenerator:isActivated, J/iso/objects/
--    IsoGenerator.java:458 ; 2 points), au moins BARRICADES_MIN ouvertures barricadées (BarricadeAble:isBarricaded ;
--    1 point : des histoires vanilla barricadent aussi des maisons), au moins CONSTRUCTIONS_MIN IsoThumpable sans
--    marque d'un foyer Living Knox (1 point : constructions du menu « Construire », mais aussi quelques objets
--    d'histoires vanilla). Base retenue : SCORE_MIN points, hors de HOME_GAP cases du foyer de tout groupe (les
--    groupes barricadent et fortifient leur propre foyer). Écartés (peu fiables) : lumières (allumées au départ du
--    monde dans les maisons alimentées par le réseau), véhicules (épaves partout), bruit (passager, zombies).
--    Le groupe pillard (type dont un rôle permet "raid") au foyer le plus proche, à DETECT_RANGE cases au plus, note
--    la base (phase "watch") ; elle n'est « occupée » qu'après SEEN_DAYS jours de jeu différents de signes.
-- 2. Éclaireurs (Raids.offscreenHour, pas horaire de LK_Simulation, aucun tirage, aucun accès aux cases) : base
--    occupée, raids activés, RaidDays jours depuis le départ du raid précédent (tous groupes) et depuis le début du
--    monde, aucun autre raid en cours, un occupant hostile au groupe (attitude LK11-T03 dans LEVELS ; occupant sans
--    identité du carnet : niveau de départ du type) : 1 à SCOUTS_MAX membres réels (rôle "scout" d'abord, puis tout
--    rôle "raid", hors chef, valides, sans corps, MIN_HOME restent) partent en expédition abstraite place "raid"
--    (absents du foyer, jamais matérialisés au foyer) ; trajet abstrait (Relations.travelHours), SCOUT_HOURS heures
--    autour de la base. Corps créés seulement à distance des joueurs (Relations.embodyTeam : SPAWN_MIN cases au
--    moins de tout joueur vivant, côté foyer, modèle de la vengeance LK11-T05) ; ronde à WATCH_RADIUS cases.
--    Éclaireurs tous morts (traque comprise) : raid ANNULÉ (fin "cancelled").
-- 3. Annonce (fin du guet, au moins un éclaireur vivant) : réplique IGUI_LK_Raid_Scouted d'un éclaireur incarné,
--    entrée « raid » au journal du groupe, fait public "raidAnnounced" (point d'appel de la radio du carnet).
--    Retour des éclaireurs, puis ANNOUNCE_HOURS heures d'attente.
-- 4. Attaque : membres réels de rôle "raid" au foyer (TEAM_MIN à TEAM_MAX, éclaireurs revenus compris, MIN_HOME
--    restent ; aucun membre créé), même trajet abstrait, ATTACK_HOURS heures à la base : corps à distance des joueurs,
--    marche vers la base et ronde serrée (ATTACK_RADIUS) par le comportement « revenge » du cadre de décision
--    (Relations.applyHunt) ; portes et barricades forcées par LK04-T04 (LK_Obstacles : pillards, policy "force") ;
--    engagement par le choix de cible existant (Hostility.chooseTarget : pillards hostiles qui tirent les premiers).
-- 5. Fin : retour au foyer (fin "done"), équipe anéantie ("wiped"), occupants plus hostiles avant le départ
--    ("peace"), raids désactivés ("disabled"), base oubliée ("forgotten"). Champ raid effacé, raidLast = heure du
--    départ des éclaireurs (fréquence), fait "raidEnded".
-- Registre : champs facultatifs raid et raidLast du groupe (registre privé des groupes, schéma 1 inchangé, ignorés
-- par LK_Groups, contrôlés ici). Persistant ; mémoire seulement : répliques en attente, raisons déjà journalisées.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Relations"

local Raids = LivingKnox.Raids or {}
LivingKnox.Raids = Raids

-- Réglages (valeurs de départ propres au mod, à recalibrer en jeu ; fiche raids.md).
Raids.CFG = Raids.CFG or {
    SCORE = { safehouse = 3, generator = 2, barricades = 1, constructions = 1 },
    SCORE_MIN = 2,
    BARRICADES_MIN = 2,       -- ouvertures barricadées de la base
    CONSTRUCTIONS_MIN = 2,    -- IsoThumpable sans marque de foyer
    GENERATOR_MARGIN = 3,     -- cases autour de la base où un générateur compte
    SCAN_MAX = 8000,          -- cases lues au plus par base et par relevé
    SEEN_DAYS = 2,            -- jours de jeu différents de signes : base occupée
    FORGET_DAYS = 7,          -- base surveillée sans nouveau signe depuis ce nombre de jours : oubliée
    DETECT_RANGE = 3000,      -- cases entre le foyer du groupe pillard et la base, au plus
    HOME_GAP = 60,            -- cases : base trop près du foyer d'un groupe (ses propres défenses) : ignorée
    OCCUPANTS_MAX = 4,
    LEVELS = { hostile = true },   -- attitude d'un occupant qui justifie le raid
    SCOUTS_MAX = 2,
    SCOUT_HOURS = 4,          -- heures de guet autour de la base
    WATCH_RADIUS = 30,        -- cases : ronde des éclaireurs autour de la base
    ANNOUNCE_HOURS = 24,      -- heures entre le retour des éclaireurs et le départ de l'attaque
    TEAM_MIN = 2,
    TEAM_MAX = 6,
    MIN_HOME = 1,             -- vivants qui restent au foyer
    WOUND_MAX = 20,           -- blessure abstraite au plus d'un partant
    ATTACK_HOURS = 3,         -- heures à la base
    ATTACK_RADIUS = 2,        -- cases : ronde serrée autour du centre de la base
    SPEED = 300,              -- cases par heure de jeu (trajet abstrait)
    MAT_RADIUS = 80,          -- un joueur vivant à cet écart de la base : l'équipe sur place reçoit ses corps
    PER_PASS = 2,             -- corps créés au plus par passage
}
Raids.PHASES = { "watch", "scout", "ready", "raid" }
Raids.STEPS = { "out", "at", "back" }
Raids.ENDINGS = { "cancelled", "done", "wiped", "peace", "disabled", "forgotten" }
Raids.SIGNS = { "safehouse", "generator", "barricades", "constructions" }
Raids.stats = Raids.stats or { surveys = 0, spotted = 0, scouts = 0, announced = 0, launched = 0, cancelled = 0,
    ended = 0, spawned = 0, spawnWaits = 0 }
Raids.state = Raids.state or { warned = {}, lines = {} }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Hostility() return LivingKnox.Hostility end
local function Relations() return LivingKnox.Relations end
local function cfg() return Raids.CFG end

local function isNumber(v) return type(v) == "number" and v == v and v > -1e12 and v < 1e12 end
local function isInt(v, lo, hi) return isNumber(v) and math.floor(v) == v and v >= lo and v <= hi end
local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end
local function cut(s) return string.sub(s, 1, Groups().TEXT_MAX or 200) end

local function inList(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

local function byNumber(a, b) return (Groups().memberNumber(a) or 0) < (Groups().memberNumber(b) or 0) end

-- Réglages sandbox (LivingKnox.Config.raids) : { enabled, days }.
function Raids.settings()
    local C = LivingKnox.Config
    if C == nil or C.raids == nil then return { enabled = true, days = 14 } end
    return C.raids()
end

-- ------------------------------------------------------------------------------------------- forme du registre

local function validBase(b)
    return type(b) == "table" and type(b.id) == "string" and #b.id >= 1 and #b.id <= 64
        and isInt(b.x1, -1e7, 1e7) and isInt(b.y1, -1e7, 1e7) and isInt(b.x2, b.x1 or 0, 1e7)
        and isInt(b.y2, b.y1 or 0, 1e7) and isInt(b.x, -1e7, 1e7) and isInt(b.y, -1e7, 1e7) and isInt(b.z, -32, 31)
        and (b.src == "building" or b.src == "safehouse")
end

local function validOccupants(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for k, o in pairs(list) do
        if not isInt(k, 1, cfg().OCCUPANTS_MAX) or type(o) ~= "table" or type(o.u) ~= "string" or #o.u < 1
            or #o.u > 64 or (o.k ~= nil and not Hostility().validPlayerKey(o.k)) then
            return false
        end
        n = n + 1
    end
    return n >= 1 and n == #list
end

local function validTeam(list)
    if type(list) ~= "table" then return false end
    local n = 0
    for k, mid in pairs(list) do
        if not isInt(k, 1, 32) or not Groups().memberNumber(mid) then return false end
        n = n + 1
    end
    return n >= 1 and n == #list
end

-- Raid relu valide (champ raid d'un groupe). Rend vrai, ou faux et une raison.
function Raids.validRaid(r)
    if type(r) ~= "table" or r.v ~= 1 then return false, "not a raid record" end
    if not inList(Raids.PHASES, r.phase) then return false, "bad phase" end
    if not validBase(r.base) then return false, "bad base" end
    if not validOccupants(r.occ) then return false, "bad occupants" end
    if type(r.signs) ~= "string" or #r.signs > 64 then return false, "bad signs" end
    if not isInt(r.seen, 1, 1e6) or not isInt(r.last, 0, 1e9) or not isInt(r.k, 0, 1e6) then
        return false, "bad counters"
    end
    if r.ending ~= nil and not inList(Raids.ENDINGS, r.ending) then return false, "bad ending" end
    if r.phase ~= "watch" and not isInt(r.start, 0, 1e9) then return false, "bad start hour" end
    if r.phase == "ready" and not isInt(r.due, 0, 1e9) then return false, "bad due hour" end
    if r.phase == "scout" or r.phase == "raid" then
        if not inList(Raids.STEPS, r.step) then return false, "bad step" end
        if not validTeam(r.team) then return false, "bad team" end
        if not isInt(r.dep, 0, 1e9) or not isInt(r.arrive, r.dep or 0, 1e9) or not isInt(r.leave, r.arrive or 0, 1e9)
            or not isInt(r.travel, 1, 1e6) then
            return false, "bad hours"
        end
    end
    return true
end

-- Raid valide du groupe g (registre vivant), ou nil ; un raid malformé est oublié (avertissement). Contrôle aussi
-- raidLast (oublié s'il est malformé).
local function raidOf(g, gid)
    if type(g) ~= "table" then return nil end
    if g.raidLast ~= nil and not isInt(g.raidLast, 0, 1e9) then
        log().warn("raid: group %s raidLast dropped: %s", tostring(gid), tostring(g.raidLast))
        g.raidLast = nil
    end
    local r = g.raid
    if r == nil then return nil end
    local ok, why = Raids.validRaid(r)
    if ok then return r end
    log().warn("raid: group %s record dropped: %s", tostring(gid), tostring(why))
    g.raid = nil
    return nil
end
Raids.raidOf = raidOf

local function liveGroups()
    local G = Groups()
    if not G.isReady() then return nil end
    return G.state.data
end

-- ------------------------------------------------------------------------------------------- types et membres

-- Rôle qui permet le comportement behaviour dans le type du groupe.
function Raids.roleHas(groupType, role, behaviour)
    local def = LivingKnox.GroupTypes.get(groupType)
    local r = def and def.roles and def.roles[role] or nil
    return inList(r and r.behaviours, behaviour)
end

-- Type pillard : un de ses rôles permet "raid" (pillards livrés : adjoint, combattants, éclaireurs, casseurs).
function Raids.isRaiderType(groupType)
    local def = LivingKnox.GroupTypes.get(groupType)
    for _, r in pairs(def and def.roles or {}) do
        if inList(r.behaviours, "raid") then return true end
    end
    return false
end

local function memberEmbodied(m)
    local Si = LivingKnox.Simulation
    return Si ~= nil and Si.isEmbodied ~= nil and Si.isEmbodied(m)
end

-- Partants possibles (pur, registre vivant) : vivants au foyer (hors expédition), hors chef, rôle "raid", blessure
-- abstraite au plus WOUND_MAX, sans corps ; scouting = rôle "scout" d'abord ; puis par numéro. Rend la liste et le
-- nombre de vivants au foyer.
function Raids.candidates(g, scouting)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local out, present, scout = {}, 0, {}
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            present = present + 1
            if mid ~= g.leader and Raids.roleHas(g.type, m.role, "raid") and (m.wound or 0) <= cfg().WOUND_MAX
                and not memberEmbodied(m) then
                out[#out + 1] = mid
                scout[mid] = scouting == true and Raids.roleHas(g.type, m.role, "scout")
            end
        end
    end
    table.sort(out, function(a, b)
        if scout[a] ~= scout[b] then return scout[a] == true end
        return byNumber(a, b)
    end)
    return out, present
end

-- ------------------------------------------------------------------------------------------- repérage

-- Base du joueur p (case chargée) : refuge vanilla qui contient sa case, sinon bâtiment de sa case ; ou nil (dehors).
-- Rend { id, x1, y1, x2, y2 (inclus), x, y, z = 0 (centre), src, top (dernier niveau) }.
function Raids.baseOf(p)
    local sq = p ~= nil and p:getCurrentSquare() or nil
    if sq == nil then return nil end
    local def = sq.getBuildingDef ~= nil and sq:getBuildingDef() or nil
    local top = def ~= nil and def:getMaxLevel() or 0
    local sh
    if SafeHouse ~= nil and SafeHouse.getSafeHouse ~= nil then
        local ok, v = pcall(SafeHouse.getSafeHouse, sq)
        if ok then sh = v end
    end
    local b
    if sh ~= nil then
        local x, y = sh:getX(), sh:getY()
        b = { id = "sh:" .. x .. "," .. y, x1 = x, y1 = y, x2 = x + sh:getW() - 1, y2 = y + sh:getH() - 1,
            src = "safehouse" }
    elseif def ~= nil then
        b = { id = "b:" .. def:getIDString(), x1 = def:getX(), y1 = def:getY(), x2 = def:getX2() - 1,
            y2 = def:getY2() - 1, src = "building" }
    else
        return nil
    end
    if b.x2 < b.x1 then b.x2 = b.x1 end
    if b.y2 < b.y1 then b.y2 = b.y1 end
    b.x, b.y, b.z = math.floor((b.x1 + b.x2) / 2), math.floor((b.y1 + b.y2) / 2), 0
    b.top = math.max(0, math.min(top, 31))
    return b
end

local OPENINGS = { "IsoDoor", "IsoWindow", "IsoWindowFrame", "IsoThumpable" }

local function isOpening(o)
    for _, n in ipairs(OPENINGS) do
        if instanceof(o, n) then return true end
    end
    return false
end

local function homeTagged(o)
    local tag = LivingKnox.Homes and LivingKnox.Homes.TAG or "LKHome"
    return o:hasModData() and o:getModData()[tag] ~= nil
end

-- Signes d'occupation de la base b sur les cases chargées (niveaux 0..b.top ; bords sud et est portés par les cases
-- hors du rectangle ; générateurs à GENERATOR_MARGIN cases autour). Rend { safehouse, generator, barricades,
-- constructions (nombres), score, text, squares }.
function Raids.signs(b)
    local c = cfg()
    local out = { safehouse = b.src == "safehouse" and 1 or 0, generator = 0, barricades = 0, constructions = 0,
        squares = 0 }
    local cell = getCell()
    if cell ~= nil then
        local m = c.GENERATOR_MARGIN
        for z = 0, b.top or 0 do
            for x = b.x1 - m, b.x2 + m do
                for y = b.y1 - m, b.y2 + m do
                    if out.squares >= c.SCAN_MAX then break end
                    local inside = x >= b.x1 and x <= b.x2 + 1 and y >= b.y1 and y <= b.y2 + 1
                    local sq = cell:getGridSquare(x, y, z)
                    if sq ~= nil then
                        out.squares = out.squares + 1
                        local objs = sq:getObjects()
                        for i = 0, objs:size() - 1 do
                            local o = objs:get(i)
                            if instanceof(o, "IsoGenerator") then
                                if o:isActivated() then out.generator = out.generator + 1 end
                            elseif inside then
                                if isOpening(o) and o:isBarricaded() then out.barricades = out.barricades + 1 end
                                if instanceof(o, "IsoThumpable") and not homeTagged(o) then
                                    out.constructions = out.constructions + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local score, names = 0, {}
    if out.safehouse > 0 then score, names[#names + 1] = score + c.SCORE.safehouse, "safehouse" end
    if out.generator > 0 then score, names[#names + 1] = score + c.SCORE.generator, "generator" end
    if out.barricades >= c.BARRICADES_MIN then score, names[#names + 1] = score + c.SCORE.barricades, "barricades" end
    if out.constructions >= c.CONSTRUCTIONS_MIN then
        score, names[#names + 1] = score + c.SCORE.constructions, "constructions"
    end
    out.score, out.text = score, table.concat(names, " ")
    return out
end

-- Foyer d'un groupe à HOME_GAP cases au plus du centre de la base (ses propres défenses) : vrai.
local function nearGroupHome(data, b)
    for _, g in pairs(data.groups) do
        if type(g.home) == "table" and cheb(g.home.x, g.home.y, b.x, b.y) <= cfg().HOME_GAP then return true end
    end
    return false
end

-- Groupe pillard qui repère la base b (registre passé en argument) : type pillard, présent (non disparu), un vivant
-- au moins, foyer à DETECT_RANGE cases au plus ; le plus proche (puis par numéro). Rend gid, ou nil.
function Raids.watcherFor(data, b)
    local G = Groups()
    local best, bestD
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids, function(a, c) return (G.idNumber(a) or 0) < (G.idNumber(c) or 0) end)
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        if not G.isGone(g) and type(g.home) == "table" and G.livingCount(g) > 0 and Raids.isRaiderType(g.type) then
            local d = cheb(g.home.x, g.home.y, b.x, b.y)
            if d <= cfg().DETECT_RANGE and (bestD == nil or d < bestD) then best, bestD = gid, d end
        end
    end
    return best
end

-- Occupant ajouté ou complété (clé du carnet connue depuis) : vrai.
local function addOccupant(r, u, k)
    for _, o in ipairs(r.occ) do
        if o.u == u then
            if k ~= nil and o.k ~= k then
                o.k = k
                return true
            end
            return false
        end
    end
    if #r.occ >= cfg().OCCUPANTS_MAX then return false end
    r.occ[#r.occ + 1] = { u = u, k = k }
    return true
end

local function copyBase(b)
    return { id = b.id, x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2, x = b.x, y = b.y, z = b.z, src = b.src }
end

-- Signe d'occupation de la base b vu le jour day chez le joueur de compte u (clé du carnet k ou nil), noté par le
-- groupe g (registre vivant). Rend "spotted", "seen", "occupant" ou nil (rien de changé).
function Raids.note(g, gid, b, signs, u, k, day)
    local G = Groups()
    local r = raidOf(g, gid)
    if r ~= nil and r.phase == "watch" and r.base.id ~= b.id and r.last <= day - cfg().FORGET_DAYS then
        log().info("raid: group %s forgets the base at %d,%d (not seen since day %d)", gid, r.base.x, r.base.y, r.last)
        g.raid, r = nil, nil
    end
    if r == nil then
        g.raid = { v = 1, phase = "watch", base = copyBase(b), signs = string.sub(signs.text, 1, 64), seen = 1,
            last = day, k = 0, occ = { { u = u, k = k } } }
        G.appendLog(g, "raid", cut(string.format("spotted a player base at %d,%d (%s)", b.x, b.y, signs.text)), day)
        Raids.stats.spotted = Raids.stats.spotted + 1
        log().info("raid: group %s spotted the base %s at %d,%d (%s, score %d) of %s", gid, b.id, b.x, b.y, signs.text,
            signs.score, u)
        return "spotted"
    end
    if r.base.id ~= b.id then return nil end
    local added = addOccupant(r, u, k)
    if r.phase == "watch" and r.last ~= day then
        r.seen, r.last, r.signs = r.seen + 1, day, string.sub(signs.text, 1, 64)
        log().info("raid: group %s saw the base at %d,%d again (day %d, %d day(s), %s)", gid, b.x, b.y, day, r.seen,
            signs.text)
        return "seen"
    end
    return added and "occupant" or nil
end

-- Relevé (autorité, chaque heure de jeu) : base et signes de chaque joueur vivant, puis note par le groupe pillard
-- qui la repère. Rend le nombre de bases notées.
function Raids.survey()
    if not LivingKnox.isAuthority() then return 0 end
    local C = LivingKnox.Config
    if C ~= nil and not C.isEnabled() then return 0 end
    if not Raids.settings().enabled then return 0 end
    local G, B = Groups(), LivingKnox.Bodies
    if B == nil or not G.ensure() then return 0 end
    Raids.stats.surveys = Raids.stats.surveys + 1
    local seen, done = {}, {}
    for _, p in ipairs(B.livingPlayers()) do
        local b = Raids.baseOf(p)
        if b ~= nil then
            local u = p:getUsername()
            local key = done[b.id] or nil
            if key == nil then
                key = Raids.signs(b)
                done[b.id] = key
            end
            if key.score >= cfg().SCORE_MIN then
                seen[#seen + 1] = { b = b, signs = key, u = u, k = Hostility().keyOf(p) }
            end
        end
    end
    if #seen == 0 then return 0 end
    local day, noted = G.today(), 0
    G.update(function(data)
        local changed = false
        for _, s in ipairs(seen) do
            if nearGroupHome(data, s.b) then
                if Raids.state.warned[s.b.id] ~= "home" then
                    Raids.state.warned[s.b.id] = "home"
                    log().info("raid: base %s at %d,%d is next to a group home: ignored", s.b.id, s.b.x, s.b.y)
                end
            else
                local gid = Raids.watcherFor(data, s.b)
                if gid ~= nil and Raids.note(data.groups[gid], gid, s.b, s.signs, s.u, s.k, day) ~= nil then
                    noted = noted + 1
                    changed = true
                end
            end
        end
        return changed, changed
    end)
    return noted
end

-- ------------------------------------------------------------------------------------------- hors écran

local function publishRaid(name, gid, r, extra)
    local keys = {}
    for _, o in ipairs(r.occ) do keys[#keys + 1] = o.k or o.u end
    local info = { group = gid, base = r.base.id, x = r.base.x, y = r.base.y, src = r.base.src, players = keys,
        day = Groups().today() }
    for k, v in pairs(extra or {}) do info[k] = v end
    LivingKnox.publish(name, info)
end

-- Un occupant au moins est hostile au groupe (attitude dans LEVELS ; sans identité du carnet : niveau de départ du
-- type). Registre des attitudes illisible : non (pas de raid sur une erreur de lecture).
function Raids.hostileOccupant(gid, g, r)
    local H = Hostility()
    local start = H.levelOf(H.startFor(g.type))
    for _, o in ipairs(r.occ) do
        local level = start
        if o.k ~= nil then
            local att = H.get(gid, o.k)
            if att == nil then return false end
            level = att.level
        end
        if cfg().LEVELS[level] then return true end
    end
    return false
end

-- Heure du dernier départ de raid (tous groupes) et raid en cours ailleurs que gid.
local function lastRaid(data, gid)
    local last, busy
    for id, g in pairs(data.groups) do
        local r = type(g) == "table" and g.raid or nil
        if type(r) == "table" and r.phase ~= "watch" then
            if id ~= gid then busy = id end
            if isNumber(r.start) and (last == nil or r.start > last) then last = r.start end
        end
        if type(g) == "table" and isNumber(g.raidLast) and (last == nil or g.raidLast > last) then last = g.raidLast end
    end
    return last, busy
end

-- Fréquence : RaidDays jours de jeu depuis le dernier départ (tous groupes) et depuis le début du monde. Rend vrai,
-- ou faux et la raison.
function Raids.allowed(data, gid, hour, days)
    local gap = math.max(0, days) * 24
    if hour < gap then return false, "world too young" end
    local last, busy = lastRaid(data, gid)
    if busy ~= nil then return false, "raid of " .. busy .. " under way" end
    if last ~= nil and hour - last < gap then return false, "last raid too recent" end
    return true
end

local function teamText(team) return table.concat(team, " ") end

local function endRaid(g, gid, r, ending, day)
    g.raid = nil
    if isNumber(r.start) then g.raidLast = r.start end
    Groups().appendLog(g, "raid", cut(string.format("raid on %d,%d ended: %s", r.base.x, r.base.y, ending)), day)
    Raids.stats.ended = Raids.stats.ended + 1
    if ending == "cancelled" then Raids.stats.cancelled = Raids.stats.cancelled + 1 end
    log().info("raid: group %s raid on %s ended: %s", gid, r.base.id, ending)
    publishRaid("raidEnded", gid, r, { ending = ending })
end
Raids.endRaid = endRaid

-- Départ d'une équipe (éclaireurs ou attaque) en expédition abstraite place "raid".
local function depart(g, gid, r, hour, day, scouting)
    local c = cfg()
    if type(g.home) ~= "table" then return nil, "no home" end
    if g.expedition ~= nil then return nil, "expedition under way" end
    if type(g.trips) == "table" and g.trips.cur ~= nil then return nil, "physical expedition under way" end
    local cands, present = Raids.candidates(g, scouting)
    local size
    if scouting then
        size = math.min(c.SCOUTS_MAX, #cands, present - c.MIN_HOME)
        if size < 1 then return nil, "no scout available" end
    else
        size = math.min(c.TEAM_MAX, #cands, present - c.MIN_HOME)
        if size < c.TEAM_MIN then return nil, "team too small" end
    end
    local team, copy = {}, {}
    for i = 1, size do team[i], copy[i] = cands[i], cands[i] end
    local travel = Relations().travelHours(g.home, r.base, c.SPEED)
    r.phase = scouting and "scout" or "raid"
    r.step, r.team, r.travel, r.dep, r.arrive = "out", team, travel, hour, hour + travel
    r.leave = r.arrive + math.max(1, math.floor(scouting and c.SCOUT_HOURS or c.ATTACK_HOURS))
    r.k, r.due = r.k + 1, nil
    if scouting then r.start = hour end
    g.expedition = { place = "raid", team = copy, departed = hour, returns = r.leave + travel }
    local what = scouting and "scouts" or "raiders"
    Groups().appendLog(g, "raid", cut(string.format("%s %s left for the base at %d,%d, %d h away", what,
        teamText(team), r.base.x, r.base.y, travel)), day)
    log().info("raid: group %s %s %s left at hour %d for the base %s at %d,%d, arrival hour %d", gid, what,
        teamText(team), hour, r.base.id, r.base.x, r.base.y, r.arrive)
    if scouting then
        Raids.stats.scouts = Raids.stats.scouts + 1
        publishRaid("raidScouting", gid, r, { team = copy })
    else
        Raids.stats.launched = Raids.stats.launched + 1
        publishRaid("raidLaunched", gid, r, { team = copy })
    end
    return true
end

-- Annonce à la fin du guet : réplique d'un éclaireur incarné (dite au prochain passage, hors écriture du registre),
-- journal, fait public.
local function announce(g, gid, r, hour, day)
    local wait = math.max(1, math.min(r.travel, hour - r.dep)) + math.floor(cfg().ANNOUNCE_HOURS)
    Groups().appendLog(g, "raid", cut(string.format("scouts saw the base at %d,%d (%s): attack in about %d h",
        r.base.x, r.base.y, r.signs, wait)), day)
    Raids.stats.announced = Raids.stats.announced + 1
    log().info("raid: group %s scouts saw the base %s at %d,%d: raid announced, attack in about %d h", gid, r.base.id,
        r.base.x, r.base.y, wait)
    local B = LivingKnox.Bodies
    for _, mid in ipairs(Relations().livingTeam(g, r.team)) do
        local m = g.members[mid]
        if m.npc ~= nil and B ~= nil and B.find ~= nil and B.find(m.npc) ~= nil then
            Raids.state.lines[#Raids.state.lines + 1] = { npc = m.npc, key = "IGUI_LK_Raid_Scouted" }
            break
        end
    end
    publishRaid("raidAnnounced", gid, r, { hours = wait, team = r.team })
end

-- Une heure de jeu pour le raid du groupe g (registre vivant data, sans sauvegarde : appelé par Simulation.advance
-- avant chaque heure simulée du groupe, après la vengeance, dans la même écriture). Rend la phase après l'heure, ou
-- nil.
function Raids.offscreenHour(data, g, gid, hour)
    local r = raidOf(g, gid)
    if r == nil then return nil end
    local day = math.floor(hour / 24) + 1
    local set = Raids.settings()
    local trip = r.phase == "scout" or r.phase == "raid"
    if trip and (type(g.expedition) ~= "table" or g.expedition.place ~= "raid") then
        log().warn("raid: group %s lost its %s expedition: raid closed", gid, r.phase)
        endRaid(g, gid, r, "cancelled", day)
        return nil
    end
    if not set.enabled and (r.phase == "watch" or r.phase == "ready") then
        endRaid(g, gid, r, "disabled", day)
        return nil
    end
    if r.phase == "watch" then
        if r.last <= math.floor(hour / 24) + 1 - cfg().FORGET_DAYS then
            endRaid(g, gid, r, "forgotten", day)
            return nil
        end
        if r.seen < cfg().SEEN_DAYS then return "watch" end
        local ok, why = Raids.allowed(data, gid, hour, set.days)
        if ok and not Raids.hostileOccupant(gid, g, r) then ok, why = false, "no hostile occupant" end
        if ok then ok, why = depart(g, gid, r, hour, day, true) end
        if not ok and Raids.state.warned[gid] ~= why then
            Raids.state.warned[gid] = why
            log().info("raid: group %s does not scout the base at %d,%d yet: %s", gid, r.base.x, r.base.y,
                tostring(why))
        end
        return r.phase
    end
    if r.phase == "ready" then
        if hour < r.due then return "ready" end
        if not Raids.hostileOccupant(gid, g, r) then
            endRaid(g, gid, r, "peace", day)
            return nil
        end
        local ok, why = depart(g, gid, r, hour, day, false)
        if not ok and Raids.state.warned[gid] ~= why then
            Raids.state.warned[gid] = why
            log().info("raid: group %s cannot launch the raid yet: %s", gid, tostring(why))
        end
        return r.phase
    end
    -- Équipe dehors (éclaireurs ou attaque).
    if #Relations().livingTeam(g, r.team) == 0 then
        g.expedition = nil
        if r.phase == "scout" then
            Groups().appendLog(g, "raid", cut(string.format("scouts %s did not come back: raid on %d,%d called off",
                teamText(r.team), r.base.x, r.base.y)), day)
            endRaid(g, gid, r, "cancelled", day)
        else
            endRaid(g, gid, r, "wiped", day)
        end
        return nil
    end
    if r.step == "out" and hour >= r.arrive then
        r.step = "at"
        log().info("raid: group %s %s reached the base at %d,%d at hour %d, until hour %d", gid,
            r.phase == "scout" and "scouts" or "raiders", r.base.x, r.base.y, hour, r.leave)
    end
    if r.step == "at" and hour >= r.leave then
        if r.phase == "scout" then
            announce(g, gid, r, hour, day)
        else
            Groups().appendLog(g, "raid", cut(string.format("raid on %d,%d: %d still standing, heading home",
                r.base.x, r.base.y, #Relations().livingTeam(g, r.team))), day)
        end
        Relations().turnBack(g, r, hour, "raid", "step")
    end
    return r.phase
end

-- Retour de l'équipe (LK_Simulation.simulateHour, heure returns de l'expédition "raid", registre vivant). Rend vrai
-- si l'expédition est close.
function Raids.raidReturn(g, gid, hour, day)
    local r = raidOf(g, gid)
    if r ~= nil and (r.phase == "scout" or r.phase == "raid") and Relations().delayReturn(g, r.team, hour) then
        return false
    end
    g.expedition = nil
    if r == nil or (r.phase ~= "scout" and r.phase ~= "raid") then return true end
    local back = Relations().livingTeam(g, r.team)
    if r.phase == "scout" then
        if #back == 0 then
            endRaid(g, gid, r, "cancelled", day)
            return true
        end
        r.phase, r.due = "ready", hour + math.max(0, math.floor(cfg().ANNOUNCE_HOURS))
        r.step, r.team, r.dep, r.arrive, r.leave, r.travel = nil, nil, nil, nil, nil, nil
        Groups().appendLog(g, "raid", cut(string.format("scouts back home (%d): raid on %d,%d at hour %d", #back,
            r.base.x, r.base.y, r.due)), day)
        log().info("raid: group %s scouts back home at hour %d, raid due at hour %d", gid, hour, r.due)
        return true
    end
    Groups().appendLog(g, "raid", cut(string.format("raid on %d,%d: %d back home", r.base.x, r.base.y, #back)), day)
    endRaid(g, gid, r, "done", day)
    return true
end

-- ------------------------------------------------------------------------------------------- à l'écran

-- Membre d'un raid à la base ou au retour (contexte du cadre de décision, par Relations.memberHunt) :
-- { n, phase = "hunt" | "back", zone, rank, kind = "raid", stage = "scout" | "raid", patrol }, ou nil.
function Raids.memberHunt(gid, mid)
    local data = liveGroups()
    local g = data and data.groups[gid] or nil
    local r = g and g.raid or nil
    if type(r) ~= "table" or (r.phase ~= "scout" and r.phase ~= "raid") or (r.step ~= "at" and r.step ~= "back")
        or type(r.team) ~= "table" or type(r.base) ~= "table" then
        return nil
    end
    for i, x in ipairs(r.team) do
        if x == mid then
            return { n = r.k, phase = r.step == "at" and "hunt" or "back", rank = i, kind = "raid", stage = r.phase,
                zone = { x = r.base.x, y = r.base.y, z = r.base.z },
                patrol = r.phase == "scout" and cfg().WATCH_RADIUS or cfg().ATTACK_RADIUS }
        end
    end
    return nil
end

-- Répliques en attente (annonces), dites hors de l'écriture du registre.
function Raids.flushLines()
    local lines = Raids.state.lines
    if #lines == 0 then return 0 end
    Raids.state.lines = {}
    local said = 0
    for _, l in ipairs(lines) do
        if Relations().say(l.npc, l.key, nil, "hostile") then said = said + 1 end
    end
    return said
end

-- Passage (autorité, chaque minute de jeu) : répliques en attente, puis corps des équipes à la base dont un joueur
-- vivant est à MAT_RADIUS cases, à distance des joueurs (Relations.embodyTeam) ; PER_PASS au plus. Rend le nombre de
-- corps créés.
function Raids.pass()
    Raids.flushLines()
    local B, Mat = LivingKnox.Bodies, LivingKnox.Materialize
    if B == nil or Mat == nil or Mat.embodyMember == nil or not B.canAct(true) then return 0 end
    local data = liveGroups()
    if data == nil then return 0 end
    local players = B.livingPlayers()
    if #players == 0 then return 0 end
    local c, created = cfg(), 0
    for _, gid in ipairs(Groups().list()) do
        local g = data.groups[gid]
        local r = g and g.raid or nil
        if type(r) == "table" and (r.phase == "scout" or r.phase == "raid") and r.step == "at"
            and type(g.expedition) == "table" and g.expedition.place == "raid" and Raids.validRaid(r)
            and B.playerNear(players, r.base.x + 0.5, r.base.y + 0.5, c.MAT_RADIUS) then
            created = created + Relations().embodyTeam(gid, g, r.team, { x = r.base.x, y = r.base.y, z = r.base.z },
                players, c.PER_PASS - created, "raid", Raids.stats, Raids.state.warned)
            if created >= c.PER_PASS then return created end
        end
    end
    return created
end

if Events ~= nil then
    LivingKnox.subscribe("EveryHours", "Raids.survey", function() LivingKnox.Raids.survey() end)
    LivingKnox.subscribe("EveryOneMinute", "Raids.pass", function() LivingKnox.Raids.pass() end)
end

return Raids
