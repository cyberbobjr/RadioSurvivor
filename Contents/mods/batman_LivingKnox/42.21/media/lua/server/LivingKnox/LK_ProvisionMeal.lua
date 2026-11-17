-- Living Knox : repas et boisson pris sur les provisions portées (LK05-T20), extension « provision » de la cascade de
-- décision (Decisions.registerExtension, LK_Decisions.lua). Fiche : docs/annexes/conception/besoins.md, section
-- « Provisions sur soi et gourde inépuisable ». Objets et effets : LK_Provisions.lua.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Décision de l'utilisateur du 2026-11-04 (plan LK05) :
--   - hors combat et loin du foyer (ou sans foyer), un membre affamé (règle hunger de la cascade) qui porte une
--     provision la mange sur place, assis ; assoiffé, il boit à sa gourde (règle thirst). Au foyer, le repas réel dans
--     le stock (LK05-T07) reste la règle : aucune provision n'y est mangée ;
--   - en combat (cible d'attaque ou menace hostile perçue), faim >= CFG.HUNGER_FIGHT sans ennemi à CFG.CONTACT cases ou
--     moins : il décroche d'environ CFG.DISENGAGE cases en courant, à l'opposé des ennemis (case hors de la vue de
--     l'ennemi le plus proche si possible, LivingKnox.Senses.lineOfSight), s'arrête, mange assis, puis la cascade le
--     rend au combat (faim retombée sous le seuil). Ennemi au contact : la règle threat d'abord. Reddition, retraite et
--     constantes mauvaises gardent la priorité (la règle threat les traite).
-- Règles inscrites avant les règles threat, hunger et thirst de PRIORITIES (même rang). Le repas est atomique : l'objet
-- n'est retiré et la jauge baissée qu'à la fin (CFG.EAT_MINUTES, CFG.DRINK_MINUTES) ; interrompu avant, rien n'est
-- consommé. Au foyer et au calme, les provisions manquantes sont remplacées sur le stock (Provisions.refill).
-- Mémoire des membres : non sauvegardée (recalculée).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Needs"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_RoutineExec"
require "LivingKnox/LK_Provisions"
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée plus bas

local Meal = LivingKnox.ProvisionMeal or {}
LivingKnox.ProvisionMeal = Meal

Meal.ID = "provision"
Meal.SIT = "sit"   -- geste existant (Routines.SIT) : assis pour manger ou boire

-- Réglages (valeurs et raisons : fiche besoins.md).
Meal.CFG = Meal.CFG or {
    HUNGER_FIGHT = 90,     -- faim à partir de laquelle un membre en combat décroche pour manger
    CONTACT = 3,           -- cases : ennemi à cette distance ou moins = au contact, la menace d'abord
    DISENGAGE = 8,         -- cases : longueur du décrochage
    EAT_MINUTES = 5,       -- minutes de jeu assis à manger (comme Routines.CFG.MEAL_EAT_MINUTES)
    DRINK_MINUTES = 2,     -- minutes de jeu à boire
    MINUTES = { 20, 20 },  -- minutes de jeu : durée de l'état « provision » (décrochage et repas y tiennent)
}

Meal.state = Meal.state or { npcs = {} }
Meal.stats = Meal.stats or { started = 0, disengaged = 0, hidden = 0, done = 0, interrupted = 0 }

local function cfg() return Meal.CFG end

-- ================================================================ règles (pur)

-- Ennemi le plus proche du membre : cible d'attaque ou menace hostile perçue (fuite permise) ; { x, y, d } ou nil.
function Meal.nearestEnemy(ctx)
    local best
    local tg = ctx.target
    if tg ~= nil and tg.d ~= nil then best = { x = tg.x, y = tg.y, d = tg.d } end
    for _, t in ipairs(ctx.threats or {}) do
        if t.flee and (best == nil or t.d < best.d) then best = { x = t.x, y = t.y, d = t.d } end
    end
    if best == nil and ctx.threat ~= nil and ctx.threat.flee then
        best = { x = ctx.threat.x, y = ctx.threat.y, d = ctx.threat.d }
    end
    return best
end

local function carried(ctx)
    return ctx.provisions or {}
end

local function fightRule(ctx)
    local hunger = (ctx.needs or {}).hunger or 0
    if hunger < cfg().HUNGER_FIGHT or (carried(ctx).food or 0) <= 0 then return nil end
    local e = Meal.nearestEnemy(ctx)
    if e == nil and ctx.target == nil then return nil end   -- pas en combat : règles hunger, thirst
    if e ~= nil and e.d <= cfg().CONTACT then return nil end
    local D = LivingKnox.Decisions
    if D.surrenderTo(ctx) ~= nil or D.retreatOf(ctx) ~= nil or D.unfitOf(ctx) ~= nil then return nil end
    return Meal.ID, string.format("hunger %d, enemy at %.1f: disengage to eat", hunger, e and e.d or 0), "fight"
end

local function away(ctx)
    return ctx.home == nil or not ctx.atHome
end

local function needRule(need, enough)
    return function(ctx)
        local v = (ctx.needs or {})[need] or 0
        if v < LivingKnox.Decisions.needHigh(need) or not away(ctx) or not enough(carried(ctx)) then return nil end
        return Meal.ID, string.format("%s %d, away from home: %s", need, v,
            need == "thirst" and "canteen" or "provision"), need
    end
end

-- ================================================================ exécution (autorité)

local function entryOf(id)
    return LivingKnox.Directives.get(id)
end

-- Case du décrochage : à DISENGAGE cases du membre, à l'opposé des ennemis (Decisions.fleeAngle), praticable ; d'abord
-- une case hors de la vue de l'ennemi le plus proche. Rend { x, y, z, hidden } ou nil.
function Meal.disengageSpot(ctx)
    local cell = getCell()
    local e = Meal.nearestEnemy(ctx)
    if cell == nil or e == nil then return nil end
    local D = LivingKnox.Decisions
    local base = D.fleeAngle(ctx.x, ctx.y, ctx.threats, e) or D.angleTo(ctx.x - (e.x + 0.5), ctx.y - (e.y + 0.5)) or 0
    local S = LivingKnox.Senses
    local first
    for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
        local a = (base + off) * math.pi / 180
        local x = math.floor(ctx.x + cfg().DISENGAGE * math.cos(a))
        local y = math.floor(ctx.y + cfg().DISENGAGE * math.sin(a))
        local sq = cell:getGridSquare(x, y, ctx.z)
        if sq ~= nil and sq:isFree(false) then
            local hidden = false
            if S ~= nil and S.lineOfSight ~= nil and S.MODEL ~= nil then
                local r = S.lineOfSight(e.x, e.y, ctx.z, x, y, ctx.z)
                hidden = (S.MODEL.LOS[r] or 0) <= 0
            end
            if hidden then return { x = x, y = y, z = ctx.z, hidden = true } end
            if first == nil then first = { x = x, y = y, z = ctx.z, hidden = false } end
        end
    end
    return first
end

local function issue(id, v, why)
    return LivingKnox.Decisions.noteIssued(id, v, why)
end

-- Arrêt puis geste assis ; rend vrai une fois assis.
local function sit(id, m)
    local D = LivingKnox.Directives
    if m.stopV == nil then
        local v, why = D.stop(id)
        if issue(id, v, why) then
            m.stopV = v
            return false
        end
        m.stopV = false   -- arrêt refusé (déjà immobile, corps absent) : assis où il est
    end
    if m.stopV then   -- arrêt émis : attendu fini (une autre consigne passée entre-temps le remplace)
        local e = entryOf(id)
        if e ~= nil and e.v == m.stopV and not e.done then return false end
    end
    local A = LivingKnox.Anim
    if A ~= nil and A.gestureOf(id) ~= Meal.SIT then
        if A.setGesture(id, Meal.SIT) then m.sat = true end
    end
    return true
end

local function finish(id, st, ctx, m)
    m.phase = "done"
    local z = LivingKnox.Bodies.find(id)
    local ok, why
    if st.key == "thirst" then
        ok, why = LivingKnox.Provisions.drink(ctx.gid, ctx.mid, z)
    else
        ok, why = LivingKnox.Provisions.eat(ctx.gid, ctx.mid, z)
    end
    if ok then
        Meal.stats.done = Meal.stats.done + 1
    else
        LivingKnox.Log.debug("npc %s: provision %s not taken: %s", tostring(id), tostring(st.key), tostring(why))
    end
end

-- Comportement « provision » (à chaque passage) : décrochage (combat), arrêt, assis, repas, effet une fois.
function Meal.apply(id, st, ctx, fresh)
    local mem = Meal.state.npcs
    local m = mem[id]
    if m == nil or m.start ~= st.start or m.key ~= st.key then
        if m ~= nil then Meal.leave(id) end
        m = { start = st.start, key = st.key, phase = st.key == "fight" and "away" or "stop" }
        mem[id] = m
        Meal.stats.started = Meal.stats.started + 1
        LivingKnox.Log.debug("npc %s: provision %s (%s)", tostring(id), tostring(st.key), tostring(st.why))
    end
    if m.phase == "away" then
        local e = entryOf(id)
        if m.moveV == nil then
            local spot = Meal.disengageSpot(ctx)
            local v, why
            if spot ~= nil then v, why = LivingKnox.Directives.moveTo(id, spot.x, spot.y, spot.z, "run") end
            if spot ~= nil and issue(id, v, why) then
                m.moveV, m.spot = v, spot
                Meal.stats.disengaged = Meal.stats.disengaged + 1
                if spot.hidden then Meal.stats.hidden = Meal.stats.hidden + 1 end
                LivingKnox.Log.info("npc %s (%s %s) disengages to %d,%d,%d (%s) to eat: %s", tostring(id), tostring(ctx.gid),
                    tostring(ctx.mid), spot.x, spot.y, spot.z, spot.hidden and "out of sight" or "in sight",
                    tostring(st.why))
                return
            end
            m.phase = "stop"   -- aucune case : il mange où il est
        elseif e ~= nil and e.v == m.moveV and not e.done then
            return
        else
            m.phase = "stop"   -- arrivé, ou trajet clos : il mange où il est
        end
    end
    if m.phase == "stop" then
        if not sit(id, m) then return end
        m.since, m.phase = ctx.minute, "eat"
        return
    end
    if m.phase == "eat" then
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= Meal.SIT and A.setGesture(id, Meal.SIT) then m.sat = true end
        local need = st.key == "thirst" and cfg().DRINK_MINUTES or cfg().EAT_MINUTES
        if ctx.minute - m.since < need then return end
        finish(id, st, ctx, m)
    end
end

-- Membre sorti du comportement (ou oublié) : mémoire oubliée, geste remis au repos ; rien de consommé avant la fin.
function Meal.leave(id)
    local m = Meal.state.npcs[id]
    if m == nil then return end
    Meal.state.npcs[id] = nil
    if m.phase ~= "done" then Meal.stats.interrupted = Meal.stats.interrupted + 1 end
    local A = LivingKnox.Anim
    if m.sat and A ~= nil and A.gestureOf(id) == Meal.SIT then A.setGesture(id, A.DEFAULT) end
end

-- Entrée de la cascade : provisions portées par le corps.
function Meal.input(ctx, body)
    local n, _, canteen = LivingKnox.Provisions.carried(body)
    ctx.provisions = { food = n, canteen = canteen ~= nil }
end

-- Après la décision : au foyer et au calme, provisions manquantes remplacées sur le stock.
function Meal.observe(ctx, st, body)
    if ctx.home == nil or not ctx.atHome or ctx.threat ~= nil or ctx.target ~= nil then return end
    if (carried(ctx).food or 0) >= LivingKnox.Provisions.CFG.COUNT then return end
    LivingKnox.Provisions.refill(ctx.gid, ctx.mid, ctx.id, body, ctx.minute)
end

-- Mémoire (nouvelle partie, tests).
function Meal.reset()
    Meal.state = { npcs = {} }
end

LivingKnox.Decisions.registerExtension({ id = Meal.ID, order = 10,
    rules = {
        { name = "provision.fight", before = "threat", rule = fightRule },
        { name = "provision.hunger", before = "hunger", rule = needRule("hunger", function(c)
            return (c.food or 0) > 0 end) },
        { name = "provision.thirst", before = "thirst", rule = needRule("thirst", function(c)
            return c.canteen == true end) },
    },
    behaviour = { vigil = "guard", minutes = cfg().MINUTES },
    apply = Meal.apply, leave = Meal.leave, input = Meal.input, observe = Meal.observe })

-- Activité de l'heure pour le pas horaire des besoins (LK_Needs.observe).
LivingKnox.Needs.BEHAVIOUR_ACTIVITY[Meal.ID] = "idle"

-- LK18-T01 (ADR adr-ceder-le-passage.md D02, fiche passage.md) : priorité de passage du comportement, déclarée ici.
LivingKnox.Passage.priority(Meal.ID, 50)

return Meal
