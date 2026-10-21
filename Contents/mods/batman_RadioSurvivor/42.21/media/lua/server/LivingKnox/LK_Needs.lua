-- Living Knox : besoins individuels des membres (faim, soif, fatigue, peur), côté autorité (LK05-T06).
-- Fiche : docs/annexes/conception/besoins.md. Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi
-- media/lua/server, il s'arrête ici. Aucune jauge n'est tenue par un client.
--
-- Décision du 2026-10-08 (docs/annexes/plans/LK05-perception-decisions-routines.md) : quatre jauges de 0 à 100 par membre,
-- tenues par le serveur, même modèle à l'écran et hors écran.
--
-- Modèle (valeurs de départ propres au mod, à recalibrer en jeu ; raisons dans la fiche) :
--   1. Pas horaire (Needs.step, pur, entiers seulement, aucun hasard) : une heure de jeu k (intervalle d'âge du monde
--      [k-1, k[, comme LK_Simulation) avec une activité de la liste fermée ACTIVITIES fait varier faim, soif et fatigue
--      selon RATES[activité] ; la peur retombe de RATES[activité].calm si aucune menace n'a été perçue pendant l'heure.
--      En début de pas, un membre au point de repas (au foyer, ou en expédition avec ses rations) dont la faim atteint
--      ENVY.hunger mange (MEAL) si la réserve de nourriture du groupe n'est pas vide, et boit (DRINK) si sa soif atteint
--      ENVY.thirst. Ce repas est un geste abstrait : aucun objet ni aucune réserve ne change ici (la consommation du
--      groupe est déjà comptée par la simulation, LK09-T01). LK05-T07 : pour un membre VU pendant l'heure dont le groupe
--      a un stock réel (Needs.realMeals), plus de repas abstrait : il mange et boit dans les conteneurs du foyer
--      (comportement « meal », LK_Routines), et Needs.relieve applique le repas ; hors écran, repas abstrait inchangé.
--   2. Activité d'une heure : membre incarné évalué par la cascade (LK_Decisions) pendant cette heure -> activité la plus
--      souvent observée (Needs.observe, comportement -> activité par BEHAVIOUR_ACTIVITY), au foyer s'il y a été vu ;
--      sinon (hors écran, ou incarné jamais évalué) -> horaire abstrait (Needs.scheduleActivity) : expédition, sommeil
--      si la fatigue atteint ENVY.fatigue, nuit (sommeil, guet pour le poste sentry), tâche hors écran du groupe.
--      Le même pas s'applique dans les deux cas : à activité égale, à l'écran et hors écran donnent les mêmes jauges.
--   3. Peur : chaque menace distincte perçue par un membre incarné (Needs.perceive, appelé par LK_Decisions) la fait
--      monter aussitôt, une fois par menace et par heure (BUMP selon le genre, la distance, vue ou entendue ; trait
--      nervous x1,5, combattant x0,5), au plus THREATS_PER_HOUR menaces par membre et par heure. La menace la plus
--      proche est gardée FEAR_SOURCE_MINUTES comme source de la peur (fuite d'un non-combattant, LK_Decisions).
--   4. Rattrapage : chaque membre garde l'heure de son dernier pas (vitals.hour). La simulation hors écran
--      (LK_Simulation.advance) avance les membres de chaque groupe juste après chaque heure simulée, à l'écran comme
--      hors écran (même tâche et même expédition pour le pas, que les heures passent une par une ou en rattrapage) ;
--      puis un passage horaire (EveryHours, après la simulation) et au démarrage avance ceux qui resteraient en
--      retard (simulation désactivée, membre nouveau), au plus CATCHUP_HOURS heures par membre (les plus récentes ;
--      le reste est ignoré et journalisé). Coût : membres x heures, borné (64 groupes, 32 membres, rattrapage de la
--      simulation MAX_CATCHUP_HOURS), sauvegardé avec la simulation (une écriture de plus seulement si un membre
--      reçoit ses premières jauges).
--   5. Envies (Needs.get, lu par LK_Decisions.needsOf) : la cascade compare les jauges à ses seuils (NEED_HIGH) et
--      produit dormir (fatigue), rentrer au foyer pour manger ou boire (faim, soif), se mettre à l'abri ou fuir (peur).
--
-- Persistance (registre des groupes, schéma 1 inchangé, champ facultatif non contrôlé par LK_Groups : contrôlé ici et
-- remis à neuf s'il est malformé) : member.vitals = { hunger, thirst, fatigue, fear (entiers 0..100), hour (heure de
-- jeu du dernier pas, entier >= 0) }. Montées de peur entre deux pas : écrites dans le registre vivant, sauvegardées
-- au pas suivant. Activités observées, menaces de l'heure et source de la peur : mémoire seulement.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"

local Needs = LivingKnox.Needs or {}
LivingKnox.Needs = Needs

Needs.GAUGES = { "hunger", "thirst", "fatigue", "fear" }
-- Activités d'une heure (liste fermée ; ordre = départage à nombre d'observations égal).
Needs.ACTIVITIES = { "flee", "patrol", "work", "travel", "watch", "idle", "rest", "sleep" }
-- Comportement de la cascade (LivingKnox.Decisions.BEHAVIOURS) -> activité de l'heure.
Needs.BEHAVIOUR_ACTIVITY = { sleep = "sleep", rest = "rest", home = "idle", chore = "work", guard = "watch",
    watch = "watch", patrol = "patrol", flee = "flee", alert = "watch",   -- alert : LK05-T08
    meal = "idle",                                                       -- meal : repas réel, LK05-T07
    defend = "watch",                                                    -- defend : défense du foyer, LK05-T09
    warn = "watch",                                                      -- warn : sommation, LK11-T02
    expedition = "travel" }                                              -- expédition physique, LK05-T05

Needs.CFG = Needs.CFG or {
    START = { hunger = 20, thirst = 20, fatigue = 20, fear = 0 },   -- membre sans jauges : valeurs de départ
    -- Variation par heure de jeu selon l'activité ; calm = baisse de la peur sans menace pendant l'heure.
    RATES = {
        sleep = { hunger = 2, thirst = 3, fatigue = -12, calm = 18 },
        rest = { hunger = 3, thirst = 4, fatigue = -4, calm = 18 },
        idle = { hunger = 4, thirst = 5, fatigue = 3, calm = 12 },
        watch = { hunger = 4, thirst = 5, fatigue = 4, calm = 12 },
        work = { hunger = 5, thirst = 7, fatigue = 5, calm = 12 },
        patrol = { hunger = 5, thirst = 7, fatigue = 6, calm = 12 },
        travel = { hunger = 5, thirst = 7, fatigue = 6, calm = 8 },
        flee = { hunger = 6, thirst = 9, fatigue = 12, calm = 4 },
    },
    -- Seuils des envies (mêmes valeurs que LivingKnox.Decisions.CFG.NEED_HIGH).
    ENVY = { hunger = 70, thirst = 70, fatigue = 80, fear = 70 },
    MEAL = 60,                -- faim retirée par un repas (abstrait hors écran ; réel x part de ration, LK05-T07)
    DRINK = 60,               -- soif retirée en buvant (idem)
    -- Montée de la peur par menace distincte et par heure : zombie vu (proche : à NEAR cases ou moins), entendu ;
    -- joueur hostile vu, entendu ; joueur méfiant vu, entendu.
    BUMP = { zombieNear = 20, zombieSeen = 10, zombieHeard = 5, hostileSeen = 25, hostileHeard = 10, warySeen = 8,
        waryHeard = 4 },
    NEAR = 6,
    NERVOUS = 1.5,            -- trait nervous (LivingKnox.GroupTypes.TRAITS)
    COMBATANT = 0.5,          -- rôle qui permet fight ou defend
    THREATS_PER_HOUR = 16,    -- menaces distinctes comptées au plus par membre et par heure
    FEAR_SOURCE_MINUTES = 10, -- minutes de jeu : la menace la plus proche reste la source de la peur
    CATCHUP_HOURS = 24,       -- rattrapage au plus (heures manquantes au-delà : ignorées et journalisées)
}

Needs.state = Needs.state or { samples = {}, threats = {}, sources = {} }
Needs.stats = Needs.stats or { passes = 0, steps = 0, skipped = 0, bumps = 0, observed = 0, resets = 0 }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function cfg() return Needs.CFG end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function level(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return v
end

local function memberKey(gid, mid) return tostring(gid) .. "/" .. tostring(mid) end

-- Horloge ----------------------------------------------------------------------------------------------------------

-- Heure de jeu courante (âge du monde, entier, comme LK_Simulation), ou nil si l'horloge manque.
function Needs.currentHour()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= "number" or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours)
end

-- Pas couvrant la minute de jeu minute : l'heure k couvre [k-1, k[ (minute dans l'heure k-1 -> pas k).
function Needs.stepOf(minute)
    return math.floor(minute / 60) + 1
end

-- Nuit au pas k : heure du jour de son début (k + 6) % 24 entre NIGHT_START et NIGHT_END (Config.SIMULATION).
function Needs.isNight(k)
    local s = LivingKnox.Config.SIMULATION or {}
    local start, stop = s.NIGHT_START or 22, s.NIGHT_END or 6
    local hod = (k + 6) % 24
    return hod >= start or hod < stop
end

-- Jauges -----------------------------------------------------------------------------------------------------------

-- Jauges valides : quatre entiers 0..100 et une heure entière >= 0.
function Needs.valid(v)
    if type(v) ~= "table" or not isInt(v.hour, 0, 2147483647) then return false end
    for _, key in ipairs(Needs.GAUGES) do
        if not isInt(v[key], 0, 100) then return false end
    end
    return true
end

function Needs.fresh(hour)
    local s = cfg().START
    return { hunger = s.hunger, thirst = s.thirst, fatigue = s.fatigue, fear = s.fear, hour = hour }
end

-- Jauges vivantes du membre m (créées ou remises à neuf à l'heure hour si absentes ou malformées).
local function vitalsOf(m, hour)
    if not Needs.valid(m.vitals) then
        if m.vitals ~= nil then
            Needs.stats.resets = Needs.stats.resets + 1
            log().warn("needs: member %s had malformed gauges, reset", tostring(m.id))
        end
        m.vitals = Needs.fresh(hour)
    end
    return m.vitals
end

-- Pas d'une heure (pur, modifie v) : activity (ACTIVITIES ; inconnue = idle), fed (au point de repas ou avec ses
-- rations), food (réserve de nourriture non vide), threatened (menace perçue pendant l'heure). Rend v.
function Needs.step(v, activity, fed, food, threatened)
    local c = cfg()
    local r = c.RATES[activity] or c.RATES.idle
    -- Envies de début d'heure satisfaites au point de repas (geste abstrait, sans objet).
    if fed and food and v.hunger >= c.ENVY.hunger then v.hunger = v.hunger - c.MEAL end
    if fed and v.thirst >= c.ENVY.thirst then v.thirst = v.thirst - c.DRINK end
    v.hunger = level(v.hunger + r.hunger)
    v.thirst = level(v.thirst + r.thirst)
    v.fatigue = level(v.fatigue + r.fatigue)
    if not threatened then v.fear = level(v.fear - r.calm) end
    return v
end

local function onExpedition(g, mid, k)
    local e = g.expedition
    if type(e) ~= "table" or type(e.team) ~= "table" then return false end
    if k <= (e.departed or 0) or k > (e.returns or 0) then return false end
    for _, id in ipairs(e.team) do
        if id == mid then return true end
    end
    return false
end

-- Horaire abstrait du pas k (hors écran, ou membre incarné jamais évalué pendant l'heure) : activité et vrai si le
-- membre est au point de repas (ou en expédition avec ses rations). v : jauges au début du pas.
function Needs.scheduleActivity(g, mid, m, v, k)
    if onExpedition(g, mid, k) then return "travel", true end
    if v.fatigue >= cfg().ENVY.fatigue then return "sleep", true end
    if Needs.isNight(k) then
        if m.duty == "sentry" then return "watch", true end
        return "sleep", true
    end
    local task = g.task
    if task == "scavenge" then return "work", true end
    if task == "rest" or task == "heal" then return "rest", true end
    return "idle", true
end

-- Activité observée au pas k pour la clé key : { activity, home } ou nil.
local function observedActivity(key, k)
    local s = Needs.state.samples[key]
    if s == nil or s.k ~= k then return nil end
    local best, bestN
    for _, a in ipairs(Needs.ACTIVITIES) do
        local n = s.n[a] or 0
        if n > 0 and (best == nil or n > bestN) then best, bestN = a, n end
    end
    if best == nil then return nil end
    return best, s.home
end

-- Avance les jauges du membre m jusqu'à l'heure now (logique pure sur le registre vivant). Rend le nombre de pas.
function Needs.advanceMember(g, gid, mid, m, now)
    local v = vitalsOf(m, now)
    if now <= v.hour then return 0 end
    local from = v.hour + 1
    local cap = cfg().CATCHUP_HOURS
    if now - v.hour > cap then
        Needs.stats.skipped = Needs.stats.skipped + (now - v.hour - cap)
        from = now - cap + 1
    end
    local key = memberKey(gid, mid)
    local food = (g.needs and g.needs.food or 0) > 0
    local real = Needs.realMeals(g)
    for k = from, now do
        local activity, fed = observedActivity(key, k)
        if activity == nil then
            activity, fed = Needs.scheduleActivity(g, mid, m, v, k)
        elseif real then
            fed = false   -- LK05-T07 : membre vu pendant l'heure, repas réels seulement
        end
        Needs.step(v, activity, fed, food, Needs.state.threats[key] ~= nil and Needs.state.threats[key].k == k)
    end
    v.hour = now
    Needs.stats.steps = Needs.stats.steps + (now - from + 1)
    return now - from + 1
end

-- Avance les membres vivants du groupe g jusqu'à l'heure now (appelé aussi par LK_Simulation.advance après chaque
-- heure simulée : le pas voit la tâche et l'expédition de cette heure-là, que les heures passent une par une ou en
-- rattrapage). Rend changed, nombre de pas, plus long retard rencontré.
function Needs.advanceGroup(g, gid, now)
    local mids = {}
    for mid, m in pairs(g.members) do
        if m.alive then mids[#mids + 1] = mid end
    end
    table.sort(mids)
    local steps, changed, longest = 0, false, 0
    for _, mid in ipairs(mids) do
        local m = g.members[mid]
        local before = m.vitals
        local hour = Needs.valid(before) and before.hour or nil
        local n = Needs.advanceMember(g, gid, mid, m, now)
        if n > 0 or hour == nil then changed = true end
        if hour ~= nil and now - hour > longest then longest = now - hour end
        steps = steps + n
    end
    return changed, steps, longest
end

-- Avance tous les membres vivants du registre jusqu'à l'heure now. Rend changed, nombre de pas.
function Needs.advance(data, now)
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    local steps, changed, longest = 0, false, 0
    for _, gid in ipairs(ids) do
        local c, n, l = Needs.advanceGroup(data.groups[gid], gid, now)
        if c then changed = true end
        steps = steps + n
        if l > longest then longest = l end
    end
    if longest > cfg().CATCHUP_HOURS then
        log().warn("needs: %s hour(s) missed, %s applied, the rest skipped", tostring(longest),
            tostring(cfg().CATCHUP_HOURS))
    end
    -- Observations et menaces des pas passés : oubliées.
    for _, tbl in ipairs({ Needs.state.samples, Needs.state.threats }) do
        local old = {}
        for key, s in pairs(tbl) do
            if s.k <= now then old[#old + 1] = key end
        end
        for _, key in ipairs(old) do tbl[key] = nil end
    end
    return changed, steps
end

-- Passage horaire jusqu'à l'heure now (défaut : heure courante), une sauvegarde si quelque chose change. Rend le
-- nombre de pas, ou nil et une raison.
function Needs.pass(now)
    if not LivingKnox.isAuthority() then return nil, "not authority" end
    if not LivingKnox.Config.isEnabled() then return 0 end
    now = now or Needs.currentHour()
    if now == nil then return nil, "no game clock" end
    local G = Groups()
    if not G.ensure() then return nil, "group registry not ready" end
    local steps = 0
    local ok, why = G.update(function(data)
        local changed, n = Needs.advance(data, now)
        steps = n
        return changed, true
    end)
    if not ok then return nil, why end
    Needs.stats.passes = Needs.stats.passes + 1
    return steps
end

-- hour : heure de jeu lue à l'EveryHours (LK13-T09, file du pas horaire de LK_Simulation) ; nil = heure courante.
function Needs.onEveryHours(hour)
    Needs.pass(hour)
end

function Needs.onStart()
    if not Groups().isReady() then return end
    Needs.pass()
end

-- Entrées de la cascade (autorité) ---------------------------------------------------------------------------------

local function liveMember(gid, mid)
    local G = Groups()
    if G == nil or not G.isReady() then return nil end
    local g = G.state.data.groups[gid]
    local m = g and g.members[mid] or nil
    if m == nil or not m.alive then return nil end
    return m, g
end

-- Jauges courantes d'un membre vivant : { hunger, thirst, fatigue, fear } (copie), valeurs de départ s'il n'en a pas
-- encore ; nil si le membre est inconnu ou mort. Interface lue par LivingKnox.Decisions.needsOf.
function Needs.get(gid, mid)
    local m = liveMember(gid, mid)
    if m == nil then return nil end
    local v = Needs.valid(m.vitals) and m.vitals or cfg().START
    return { hunger = v.hunger, thirst = v.thirst, fatigue = v.fatigue, fear = v.fear }
end

-- Activité observée d'un membre incarné à la minute minute : comportement de la cascade et présence au foyer.
function Needs.observe(gid, mid, behaviour, atHome, minute)
    local a = Needs.BEHAVIOUR_ACTIVITY[behaviour]
    if a == nil or minute == nil then return end
    local key = memberKey(gid, mid)
    local k = Needs.stepOf(minute)
    local s = Needs.state.samples[key]
    if s == nil or s.k ~= k then
        s = { k = k, n = {}, home = false }
        Needs.state.samples[key] = s
    end
    s.n[a] = (s.n[a] or 0) + 1
    if atHome then s.home = true end
    Needs.stats.observed = Needs.stats.observed + 1
end

-- Montée de peur d'une menace (pur) : t = menace de LK_Decisions.threatsOf ({ kind, flee, seen, d }).
function Needs.bumpOf(t, nervous, combatant)
    local b = cfg().BUMP
    local v
    if t.kind == "zombie" then
        if t.seen then v = (t.d or 0) <= cfg().NEAR and b.zombieNear or b.zombieSeen else v = b.zombieHeard end
    elseif t.flee then
        v = t.seen and b.hostileSeen or b.hostileHeard
    else
        v = t.seen and b.warySeen or b.waryHeard
    end
    if nervous then v = v * cfg().NERVOUS end
    if combatant then v = v * cfg().COMBATANT end
    return math.floor(v + 0.5)
end

local function hasTrait(m, name)
    if type(m.traits) ~= "table" then return false end
    for _, t in ipairs(m.traits) do
        if t == name then return true end
    end
    return false
end

-- Menaces perçues par un membre incarné (liste triée de LK_Decisions.threatsOf) à la minute minute : peur montée
-- aussitôt, une fois par menace distincte et par heure ; menace la plus proche gardée comme source de la peur.
-- Rend la montée totale.
function Needs.perceive(gid, mid, threats, combatant, minute)
    if type(threats) ~= "table" or #threats == 0 or minute == nil then return 0 end
    local m = liveMember(gid, mid)
    if m == nil then return 0 end
    local key = memberKey(gid, mid)
    local k = Needs.stepOf(minute)
    local seen = Needs.state.threats[key]
    if seen == nil or seen.k ~= k then
        seen = { k = k, keys = {}, n = 0 }
        Needs.state.threats[key] = seen
    end
    local first = threats[1]
    Needs.state.sources[key] = { x = first.x, y = first.y, z = first.z, minute = minute }
    local v = vitalsOf(m, k - 1)
    local nervous = hasTrait(m, "nervous")
    local total = 0
    for _, t in ipairs(threats) do
        if seen.n >= cfg().THREATS_PER_HOUR then break end
        if not seen.keys[t.key] then
            seen.keys[t.key] = true
            seen.n = seen.n + 1
            total = total + Needs.bumpOf(t, nervous, combatant)
        end
    end
    if total > 0 then
        v.fear = level(v.fear + total)
        Needs.stats.bumps = Needs.stats.bumps + 1
    end
    Groups().touched(gid)   -- LK13-T08 : jauges changées en place sans écriture, connues du contrôle des vues
    return total
end

-- Source récente de la peur d'un membre (menace la plus proche perçue ces FEAR_SOURCE_MINUTES), ou nil.
function Needs.fearSource(gid, mid, minute)
    local s = Needs.state.sources[memberKey(gid, mid)]
    if s == nil or minute == nil or minute - s.minute > cfg().FEAR_SOURCE_MINUTES or minute < s.minute then
        return nil
    end
    return { x = s.x, y = s.y, z = s.z }
end

-- Repas réels (LK05-T07) ------------------------------------------------------------------------------------------

-- Vrai si les membres incarnés du groupe g mangent et boivent réellement dans le stock : routine des repas chargée
-- (LivingKnox.Routines, comportement « meal ») et référence de stock valide (LivingKnox.Stock). Sinon, le repas
-- abstrait au point de repas reste en vigueur pour eux aussi.
function Needs.realMeals(g)
    local R, S = LivingKnox.Routines, LivingKnox.Stock
    if R == nil or R.handles == nil or not R.handles("meal") then return false end
    if S == nil or S.validRef == nil or type(g) ~= "table" or type(g.home) ~= "table" then return false end
    return S.validRef(g.stock, g.home) == true
end

-- Applique un repas réel (pur, sur le groupe vivant g du registre) : retire amount (entier >= 0) à la jauge gauge
-- ("hunger" ou "thirst") du membre vivant mid. Rend la nouvelle valeur, ou nil (membre inconnu ou mort).
function Needs.relieve(g, mid, gauge, amount)
    if gauge ~= "hunger" and gauge ~= "thirst" then return nil end
    local m = type(g) == "table" and type(g.members) == "table" and g.members[mid] or nil
    if m == nil or not m.alive then return nil end
    local v = vitalsOf(m, Needs.currentHour() or 0)
    v[gauge] = level(v[gauge] - math.max(0, amount or 0))
    Needs.stats.meals = (Needs.stats.meals or 0) + 1
    return v[gauge]
end

-- Réinitialisation de la mémoire (nouvelle partie, tests).
function Needs.reset()
    Needs.state = { samples = {}, threats = {}, sources = {} }
end

return Needs
