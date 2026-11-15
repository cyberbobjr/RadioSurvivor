-- Living Knox : routines des PNJ au foyer, côté autorité (LK05-T03, découpé en LK15-T02 ; ADR D04, D05). Fiche :
-- docs/annexes/conception/routines.md. Java 42.21.0 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce fichier porte le relevé du foyer (Routines.survey, ensurePosts : postes de guet, couchages, ronde ; sauvegardé
-- avec le groupe), les affectations (postes, ronde, couchages) et le registre des activités :
-- Routines.registerActivity(spec) ; Routines.apply confie le membre à l'activité de son comportement, par ordre (la
-- première qui rend vrai l'emporte). Une activité de plan (guet, ronde, sommeil) porte son plan (spec.plan, LK16-T07) :
-- Routines.runPlanned l'exécute. Les activités sont dans media/lua/server/LivingKnox/Routines/ (LK_Routine_Watch,
-- _Sleep, _Meal, _Chores ; corvées : Chores/) ; LK_Fortify.lua (barricades, « chore » 10) et LK_Upkeep.lua
-- (entretien, « chore » 20) s'inscrivent aussi. Outils d'exécution partagés (aller, regarder, s'asseoir, geste,
-- quitter, plan exécuté) : LK_RoutineExec.lua (Routines.exec). Mémoire des membres : non sauvegardée (recalculée).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_RoutineExec"
require "LivingKnox/LK_StopPlace"

local Routines = LivingKnox.Routines or {}
LivingKnox.Routines = Routines
local E = Routines.exec
local buildingId, standable, DIRS = E.buildingId, E.standable, Routines.DIRS

Routines.FORMAT = 1

Routines.POST_KINDS = { door = true, window = true }
Routines.SIT = "sit"
-- Corvées (LK05-T04) : registre Routines.registerChore (LK16-T07), Routines/LK_Routine_Chores.lua et Chores/.
-- Repas réels (LK05-T07) : besoin -> catégorie du stock ; gestes existants (aucun clip de repas n'est généré : fouille
-- pour prendre, assis pour consommer).
Routines.MEAL = { hunger = "food", thirst = "water" }
Routines.MEAL_TAKE_GESTURE = "rummage"
Routines.MEAL_EAT_GESTURE = "sit"
-- Gestes posés par les routines : remis au repos quand la routine s'arrête (Routines.leave). Le geste d'une corvée
-- inscrite s'y ajoute (Routines.registerChore).
Routines.GESTURES = Routines.GESTURES or { sit = true, kneel = true, warmhands = true, rummage = true, hammer = true,
    smoke = true }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche).
Routines.CFG = Routines.CFG or {
    MAX_POSTS = 6,             -- postes de guet relevés au plus (portes d'abord)
    MAX_BEDS = 6,              -- couchages relevés au plus
    MAX_ROUND = 8,             -- cases d'une ronde au plus
    MIN_ROUND = 3,             -- en dessous, pas de ronde
    ROUND_MARGINS = { 2, 3, 1 },   -- cases entre le bâtiment et la ronde, dans l'ordre d'essai
    DAWN_END = 8,              -- heure du jour : fin de l'aube (la nuit finit à Config.SIMULATION.NIGHT_END)
    MAX_FAILS = 2,             -- trajets manqués vers une même case avant d'y renoncer (jusqu'au plan suivant)
    RETRY_MS = 10000,          -- relevé impossible (zone non chargée) : nouvel essai au plus toutes les 10 s
    BED_QUALITY = { goodBed = 4, averageBed = 3, badBed = 2, badChair = 1 },
    -- Corvées (LK05-T04).
    CHORE_MINUTES = 30,        -- minutes de jeu d'une corvée (créneau, décalé par membre)
    MAX_FIRES = 4,             -- feux et poêles relevés au plus
    MAX_FURNITURE = 12,        -- meubles à ranger relevés au plus
    CARE_HEALTH = 0.75,        -- santé (0..1) sous laquelle un membre présent est soigné par un autre
    -- Types de conteneur (propriété de tuile « container ») qui ne sont pas des meubles à ranger : cuisson, feu, lessive.
    NOT_FURNITURE = { stove = true, microwave = true, toaster = true, coffeemaker = true, fireplace = true,
        woodstove = true, brazier = true, campfire = true, barbecue = true, barbecuepropane = true,
        clothingwasher = true, clothingdryer = true },
    -- Poids des corvées (par poste, rôle et trait) : portés par chaque corvée (Chores/, LK16-T07).
    -- Repas réels (LK05-T07).
    MEAL_TAKE_MINUTES = 1,     -- minutes de jeu à fouiller le conteneur avant de prendre l'objet
    MEAL_EAT_MINUTES = 5,      -- minutes de jeu assis à manger ou boire
    MEAL_GAP_MINUTES = 60,     -- après un repas : pas de nouveau repas du même besoin avant (minutes de jeu)
    UNFED_MINUTES = 60,        -- rien à prendre (ou conteneur hors d'atteinte) : besoin mis de côté (minutes de jeu)
    MEAL_TRIES = 2,            -- objet parti entre le repérage et la prise : recherches au plus
}

Routines.state = Routines.state or { npcs = {}, valid = {}, tried = {}, spots = {}, byChore = {}, unfed = {} }
Routines.stats = Routines.stats or { surveys = 0, notLoaded = 0, moves = 0, faces = 0, stops = 0, sits = 0,
    refused = 0, laps = 0, gaveUp = 0, spotSurveys = 0, chores = 0, gestures = 0 }
Routines.stats.meals = Routines.stats.meals or 0        -- LK05-T07 : objets pris pour un repas
Routines.stats.fasts = Routines.stats.fasts or 0        -- LK05-T07 : besoins mis de côté (rien à prendre)

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Decisions() return LivingKnox.Decisions end
local function Groups() return LivingKnox.Groups end
local function now() return getTimestampMs() end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function leash() return Decisions().CFG.HOME_RADIUS end

-- ================================================================ heures (pur)

function Routines.hourOfDay(hour) return (hour + 7) % 24 end

-- "night", "dawn" ou "day" à l'heure d'âge hour (nuit de Config.SIMULATION, comme le cadre de décision).
function Routines.period(hour)
    if Decisions().isNight(hour) then return "night" end
    if Routines.hourOfDay(hour) < cfg().DAWN_END then return "dawn" end
    return "day"
end

-- Heure dans le quart (0 = première heure du quart).
function Routines.hourInWatch(hour)
    local c = Decisions().CFG
    return (hour + 7 + 24 - c.WATCH_START) % c.WATCH_HOURS
end

-- Guet ou ronde du guetteur selon l'heure (Routines.sentryKind) : Routines/LK_Routine_Watch.lua (LK16-T07).

-- ================================================================ relevé du foyer

-- Qualité du meilleur couchage de la case (BED_QUALITY), ou nil.
function Routines.bedQuality(sq)
    if IsoFlagType == nil or IsoFlagType.bed == nil then return nil end
    local objs = sq:getObjects()
    if objs == nil then return nil end
    local best
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local props = o ~= nil and o:getSprite() ~= nil and o:getProperties() or nil
        if props ~= nil and props:has(IsoFlagType.bed) then
            local q = cfg().BED_QUALITY[props:get("BedType") or "averageBed"] or cfg().BED_QUALITY.averageBed
            if best == nil or q > best then best = q end
        end
    end
    return best
end

local function byPlace(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.d ~= b.d then return a.d < b.d end
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return (a.a or 0) < (b.a or 0)
end

-- Ronde autour du rectangle (x1, y1)-(x2, y2) du bâtiment : coins et milieux des côtés, sens horaire depuis le
-- nord-ouest ; chaque point à la première marge praticable, hors bâtiment, dans la laisse du foyer.
local function roundAround(cell, home, x1, y1, x2, y2)
    local mx, my = math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2)
    -- { x de base, signe x, y de base, signe y } : la marge m éloigne le point du bâtiment.
    local spots = { { x1, -1, y1, -1 }, { mx, 0, y1, -1 }, { x2, 1, y1, -1 }, { x2, 1, my, 0 }, { x2, 1, y2, 1 },
        { mx, 0, y2, 1 }, { x1, -1, y2, 1 }, { x1, -1, my, 0 } }
    local out = {}
    for _, s in ipairs(spots) do
        for _, m in ipairs(cfg().ROUND_MARGINS) do
            local x, y = s[1] + s[2] * m, s[3] + s[4] * m
            local sq = cell:getGridSquare(x, y, home.z)
            if standable(sq) and buildingId(sq) == nil and cheb(x, y, home.x, home.y) <= leash() then
                local last = out[#out]
                if last == nil or last.x ~= x or last.y ~= y then out[#out + 1] = { x = x, y = y, z = home.z } end
                break
            end
        end
        if #out >= cfg().MAX_ROUND then break end
    end
    if #out >= 2 and out[1].x == out[#out].x and out[1].y == out[#out].y then out[#out] = nil end
    if #out < cfg().MIN_ROUND then return {} end
    return out
end

-- Relevé du foyer home = { x, y, z } dans la zone chargée. Rend { v, hx, hy, hz, camp, posts, round, beds }, ou nil et
-- une raison (zone du foyer non chargée).
function Routines.survey(home)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R = leash()
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil, "home square not loaded" end
    for _, c in ipairs({ { -R, -R }, { R, -R }, { R, R }, { -R, R } }) do
        if cell:getGridSquare(home.x + c[1], home.y + c[2], home.z) == nil then return nil, "home area not loaded" end
    end
    local out = { v = Routines.FORMAT, hx = home.x, hy = home.y, hz = home.z, posts = {}, round = {}, beds = {} }
    local bid = buildingId(hsq)
    if bid == nil then
        out.camp = true
        return out
    end
    local posts, beds, used = {}, {}, {}
    local x1, y1, x2, y2
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil and buildingId(sq) == bid then
                if x1 == nil or x < x1 then x1 = x end
                if x2 == nil or x > x2 then x2 = x end
                if y1 == nil or y < y1 then y1 = y end
                if y2 == nil or y > y2 then y2 = y end
                local q = Routines.bedQuality(sq)
                if q ~= nil then
                    beds[#beds + 1] = { x = x, y = y, q = q, rank = -q, d = cheb(x, y, home.x, home.y) }
                elseif standable(sq) then
                    for _, d in ipairs(DIRS) do
                        local nb = cell:getGridSquare(x + d[1], y + d[2], home.z)
                        if nb ~= nil and buildingId(nb) ~= bid then
                            local kind
                            if sq:getDoorTo(nb) ~= nil then
                                kind = "door"
                            elseif sq:getWindowTo(nb) ~= nil or sq:getWindowThumpableTo(nb) ~= nil then
                                kind = "window"
                            end
                            if kind ~= nil then
                                posts[#posts + 1] = { x = x, y = y, z = home.z, a = d[3], k = kind,
                                    rank = kind == "door" and 1 or 2, d = cheb(x, y, home.x, home.y) }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(posts, byPlace)
    -- LK18-T03 : le guetteur se tient hors des portes, des seuils et des couloirs (LivingKnox.StopPlace), dans le
    -- bâtiment, au plus près de l'ouverture qu'il garde (même regard).
    local function postPlace(sq)
        return standable(sq) and buildingId(sq) == bid and Routines.bedQuality(sq) == nil
            and not used[sq:getX() .. "," .. sq:getY()]
    end
    local SP = LivingKnox.StopPlace
    for _, p in ipairs(posts) do
        local free = #out.posts < cfg().MAX_POSTS and not used[p.x .. "," .. p.y]
        local sq = free and SP.nearest(p.x, p.y, p.z, SP.SHIFT_RADIUS, postPlace) or nil
        if sq ~= nil then
            used[p.x .. "," .. p.y] = true
            used[sq:getX() .. "," .. sq:getY()] = true
            out.posts[#out.posts + 1] = { x = sq:getX(), y = sq:getY(), z = p.z, a = p.a, k = p.k }
        end
    end
    -- Couchages : meilleure qualité d'abord ; une case de lit voisine d'un lit déjà retenu = le même lit.
    table.sort(beds, byPlace)
    local chosen = {}
    for _, b in ipairs(beds) do
        if #out.beds >= cfg().MAX_BEDS then break end
        local same = false
        for _, c in ipairs(chosen) do
            if cheb(b.x, b.y, c.x, c.y) <= 1 then same = true end
        end
        if not same then
            chosen[#chosen + 1] = b
            for _, d in ipairs(DIRS) do
                local sx, sy = b.x + d[1], b.y + d[2]
                local sq = cell:getGridSquare(sx, sy, home.z)
                local key = sx .. "," .. sy
                if not used[key] and standable(sq) and buildingId(sq) == bid and Routines.bedQuality(sq) == nil then
                    used[key] = true
                    local a = (d[3] + 180) % 360   -- de la place vers le lit
                    out.beds[#out.beds + 1] = { x = sx, y = sy, z = home.z, bx = b.x, by = b.y, a = a, q = b.q }
                    break
                end
            end
        end
    end
    out.round = roundAround(cell, home, x1, y1, x2, y2)
    return out
end

-- Forme d'un relevé sauvegardé pour le foyer home. Rend vrai, ou faux et une raison.
local function validList(list, max, check)
    if type(list) ~= "table" then return false end
    local n = 0
    for k in pairs(list) do
        if not isInt(k, 1, max) then return false end
        n = n + 1
    end
    if list[n] == nil and n > 0 then return false end
    for i = 1, n do
        local e = list[i]
        if type(e) ~= "table" or not isInt(e.x, 0, 2147483647) or not isInt(e.y, 0, 2147483647)
            or not isInt(e.z, -32, 31) or not check(e) then
            return false
        end
    end
    return true
end

function Routines.validPosts(p, home)
    if type(p) ~= "table" or p.v ~= Routines.FORMAT then return false, "unknown format" end
    if type(home) ~= "table" or p.hx ~= home.x or p.hy ~= home.y or p.hz ~= home.z then return false, "home moved" end
    if p.camp ~= nil and p.camp ~= true then return false, "bad camp flag" end
    local c = cfg()
    if not validList(p.posts, c.MAX_POSTS, function(e)
        return isInt(e.a, 0, 359) and Routines.POST_KINDS[e.k] == true
    end) then
        return false, "bad posts"
    end
    if not validList(p.round, c.MAX_ROUND, function() return true end) then return false, "bad round" end
    if not validList(p.beds, c.MAX_BEDS, function(e)
        return isInt(e.bx, 0, 2147483647) and isInt(e.by, 0, 2147483647) and isInt(e.a, 0, 359) and isInt(e.q, 1, 4)
    end) then
        return false, "bad beds"
    end
    return true
end

local function summary(p)
    local doors = 0
    for _, e in ipairs(p.posts) do
        if e.k == "door" then doors = doors + 1 end
    end
    return string.format("%d post(s) (%d door, %d window), round of %d square(s), %d bed(s)%s", #p.posts, doors,
        #p.posts - doors, #p.round, #p.beds, p.camp and ", camp (no building)" or "")
end

-- Relevé du foyer du groupe vivant g (registre), fait et sauvegardé s'il manque, est malformé ou si le foyer a
-- changé. Rend le relevé, ou nil (pas de foyer, zone non chargée : nouvel essai au plus toutes les RETRY_MS).
function Routines.ensurePosts(gid, g)
    if type(g) ~= "table" or type(g.home) ~= "table" then return nil end
    local home = g.home
    local key = home.x .. "," .. home.y .. "," .. home.z
    local st = Routines.state
    if st.valid[gid] == key and g.posts ~= nil then return g.posts end
    local ok, why = Routines.validPosts(g.posts, home)
    if ok then
        st.valid[gid] = key
        return g.posts
    end
    local t = now()
    if st.tried[gid] ~= nil and t - st.tried[gid] < cfg().RETRY_MS then return nil end
    st.tried[gid] = t
    local p, notLoaded = Routines.survey(home)
    if p == nil then
        Routines.stats.notLoaded = Routines.stats.notLoaded + 1
        log().debug("group %s: home survey postponed: %s", gid, tostring(notLoaded))
        return nil
    end
    p.day = Groups().today()
    if g.posts ~= nil then log().warn("group %s: home survey redone (%s)", gid, tostring(why)) end
    Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false end
        live.posts = p
        return true
    end)
    g.posts = p   -- g peut être une copie : même relevé que le registre
    st.valid[gid] = key
    Routines.stats.surveys = Routines.stats.surveys + 1
    log().info("group %s home %s surveyed: %s", gid, key, summary(p))
    return p
end

-- Oublie le relevé d'un groupe (foyer modifié, essais) : il sera refait au prochain passage. Rend vrai si oublié.
function Routines.resurvey(gid)
    Routines.state.valid[gid], Routines.state.tried[gid] = nil, nil
    local done = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or live.posts == nil then return false, false end
        live.posts = nil
        return true, true
    end)
    return done == true
end

-- ================================================================ affectations (pur)

-- Membres présents (vivants, hors expédition), triés par numéro : { mid, ... }.
function Routines.present(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local out = {}
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then out[#out + 1] = mid end
    end
    local G = Groups()
    table.sort(out, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    return out
end

local function rankOf(list, mid)
    for i, v in ipairs(list) do
        if v == mid then return i end
    end
    return nil
end

-- Guetteurs présents (poste "sentry"), triés par numéro.
function Routines.sentries(g)
    local out = {}
    for _, mid in ipairs(Routines.present(g)) do
        if g.members[mid].duty == "sentry" then out[#out + 1] = mid end
    end
    return out
end

-- Poste de guet du guetteur mid à l'heure hour : les postes tournent à chaque quart. nil sans poste.
function Routines.postFor(posts, g, mid, hour)
    local list = type(posts) == "table" and posts.posts or nil
    if type(list) ~= "table" or #list == 0 then return nil end
    local i = rankOf(Routines.sentries(g), mid) or 1
    return list[((Decisions().watchOf(hour) + i - 1) % #list) + 1]
end

-- Point de départ de la ronde du guetteur mid (guetteurs répartis sur la boucle).
function Routines.roundStart(posts, g, mid)
    local n = #posts.round
    local s = Routines.sentries(g)
    local i = rankOf(s, mid) or 1
    local spread = math.max(1, math.floor(n / math.max(1, #s)))
    return ((i - 1) * spread) % n + 1
end

-- Couchage du membre mid : rang du membre parmi les présents qui ne sont pas de garde = rang du couchage (le lit
-- d'un guetteur n'est pas perdu ; à la relève, le relevé reprend le lit laissé) ; un guetteur qui dort malgré tout
-- (fatigue) : les lits restants, après ceux des autres. nil s'il en manque.
function Routines.bedFor(posts, g, mid)
    local list = type(posts) == "table" and posts.beds or nil
    if type(list) ~= "table" then return nil end
    local sleepers, sentries = {}, {}
    for _, other in ipairs(Routines.present(g)) do
        if g.members[other].duty ~= "sentry" then
            sleepers[#sleepers + 1] = other
        else
            sentries[#sentries + 1] = other
        end
    end
    local r = rankOf(sleepers, mid)
    if r == nil then
        r = rankOf(sentries, mid)
        if r == nil then return nil end
        r = #sleepers + r
    end
    return list[r]
end

-- Outils de tri et de voisinage partagés avec les corvées (LK_Routine_Chores.lua).
Routines.cheb, Routines.byPlace, Routines.rankOf = cheb, byPlace, rankOf

-- ================================================================ registre des activités (LK15-T02, ADR D04)

-- Activité : { id (unique), behaviour (comportement servi : "chore", "meal", "guard", "patrol", "sleep"), order
-- (plus petit d'abord, à égalité par id), run(id, st, ctx, g, fresh) -> vrai quand elle a pris le membre }.
-- Activité de plan (LK16-T07) : plan(posts, g, mid, hour, angle) -> { kind, key, x, y, z, a, sit, points, start } ou
-- nil, à la place de run (run = Routines.runPlanned avec ce plan). kind : "post" (aller au poste, regarder), "round",
-- "bed" (aller au couchage, regarder le lit, s'asseoir), "face" (regarder dans la direction a), "sit" (s'arrêter et
-- s'asseoir). Inscrite par Routines.registerActivity ; liste triée à l'inscription (sans next : Kahlua).
Routines.activities = Routines.activities or {}

local function validActivity(spec)
    if type(spec) == "table" and type(spec.id) == "string" and type(spec.behaviour) == "string"
        and type(spec.order) == "number" and type(spec.run) == "function"
        and (spec.plan == nil or type(spec.plan) == "function") then
        return true
    end
    return false, "spec needs id, behaviour, order and run (or plan)"
end

-- LK16-T01 : socle commun (LivingKnox.Registry) ; Routines.activities en est la liste.
local activities = LivingKnox.Registry.new("LivingKnox.Routines.registerActivity",
    { validate = validActivity, items = Routines.activities })

-- Inscrit une activité (spec, voir ci-dessus). Une activité déjà inscrite sous le même id est remplacée (rechargement).
function Routines.registerActivity(spec)
    if type(spec) == "table" and spec.run == nil and type(spec.plan) == "function" then
        spec.run = function(id, st, ctx, g, fresh) return Routines.runPlanned(spec, id, st, ctx, g, fresh) end
    end
    return activities:register(spec, 2)
end

-- Plan du comportement b pour le membre mid à l'heure hour : celui de la première activité de b qui porte un plan
-- (ordre des activités), ou nil.
function Routines.plan(b, posts, g, mid, hour, angle)
    for _, a in ipairs(Routines.activities) do
        if a.behaviour == b and a.plan ~= nil then return a.plan(posts, g, mid, hour, angle) end
    end
    return nil
end

-- Rend vrai si une activité est inscrite pour le comportement b (la cascade confie alors le membre à la routine).
function Routines.handles(b)
    for _, a in ipairs(Routines.activities) do
        if a.behaviour == b then return true end
    end
    return false
end

-- Routine du comportement st.b pour le membre id : les activités de ce comportement, par ordre ; la première qui rend
-- vrai l'emporte. Groupe absent : rien. Aucun module ni comportement n'est nommé ici.
function Routines.apply(id, st, ctx, fresh)
    local data = Groups().state.data
    local g = data ~= nil and data.groups[ctx.gid] or nil
    if g == nil then return end
    for _, a in ipairs(Routines.activities) do
        if a.behaviour == st.b and a.run(id, st, ctx, g, fresh) then return end
    end
end

-- Routine de plan (guet, ronde, sommeil) de l'activité a : relevé du foyer, plan de l'activité, exécution. Rend faux
-- sans plan.
function Routines.runPlanned(a, id, st, ctx, g, fresh)
    local posts = Routines.ensurePosts(ctx.gid, g)
    local plan = a.plan(posts, g, ctx.mid, math.floor(ctx.minute / 60), st.angle)
    if plan == nil then return false end
    Routines.execPlan(id, st, ctx, plan, fresh)
    return true
end

-- ================================================================ état et accès

-- Mémoire d'un membre (copie), ou nil : { key, kind, k (point de ronde), fails, sat, ... }.
function Routines.get(id)
    local m = Routines.state.npcs[id]
    if m == nil then return nil end
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

function Routines.reset()
    Routines.state = { npcs = {}, valid = {}, tried = {}, spots = {}, byChore = {}, unfed = {} }
end

-- LK16-T05 : champs de contexte de la cascade (LivingKnox.Decisions.registerContext, ordre 10) : poste de guet ou
-- ronde selon l'heure (LK05-T03, postes relevés au foyer), corvées (LK05-T04), repas réels et besoins mis de côté
-- (LK05-T07 : rien à prendre, repas récent). sentryKind et unfed viennent de Routines/ (absents : champs absents).
LivingKnox.Decisions.registerContext({ id = "routines", order = 10, fill = function(ctx, src)
    if Routines.sentryKind ~= nil then
        ctx.sentryKind = Routines.sentryKind(math.floor(src.minute / 60), Routines.ensurePosts(src.gid, src.g))
    end
    ctx.chores = Routines.handles("chore") or nil
    ctx.meals = Routines.handles("meal") or nil
    if ctx.meals and Routines.unfed ~= nil then ctx.unfed = Routines.unfed(src.gid, src.mid, src.minute) end
end })

return Routines
