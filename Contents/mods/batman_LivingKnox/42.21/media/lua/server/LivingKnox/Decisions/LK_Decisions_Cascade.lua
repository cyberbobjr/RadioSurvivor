-- Living Knox : cadre de décision des PNJ, cascade de priorités d'un membre et décision (logique pure, LK05-T02,
-- LK06-T05, LK06-T07).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- ================================================================ membre : cascade (pur)

-- Vrai si le comportement b est permis au membre (ctx.allowed : comportements de son rôle ; ctx.combatant).
function Decisions.allows(ctx, b)
    local def = Decisions.BEHAVIOURS[b]
    if def == nil then return false end
    if def.needs and not P.anyOf(ctx.allowed or {}, def.needs) then return false end
    if def.nonCombatant and ctx.combatant then return false end
    return true
end

local function atHomeOr(ctx, b)
    if ctx.home ~= nil and not ctx.atHome then return "home" end
    return b
end

-- LK06-T05 ----------------------------------------------------------------------------------------------------------

-- Fuite pondérée (pur, I6.5) : angle (degrés) d'éloignement depuis (x, y), somme des directions opposées aux menaces
-- (fuite permise, à RETREAT.WEIGH_DIST cases au plus), chacune pesée par l'inverse de sa distance (la plus proche
-- compte le plus) ; sans menace retenue : à l'opposé de src ({ x, y }) ; nil si rien ne donne de direction.
function Decisions.fleeAngle(x, y, threats, src)
    local sx, sy, n = 0, 0, 0
    for _, t in ipairs(threats or {}) do
        if t.flee and (t.d or 0) <= P.cfg().RETREAT.WEIGH_DIST then
            local dx, dy = x - (t.x + 0.5), y - (t.y + 0.5)
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                local w = 1 / math.max(len, 1)
                sx, sy, n = sx + dx / len * w, sy + dy / len * w, n + 1
            end
        end
    end
    if n == 0 and src ~= nil then return Decisions.angleTo(x - (src.x + 0.5), y - (src.y + 0.5)) end
    if math.abs(sx) < 1e-6 and math.abs(sy) < 1e-6 then return nil end
    return Decisions.angleTo(sx, sy)
end

-- Position d'un joueur de compte u pour le membre (pur) : perçu (ctx.seen), sinon lieu de l'agresseur du dernier coup
-- reçu (ctx.hit, même compte). Rend { x, y, d } ou nil.
function Decisions.playerSpot(ctx, u)
    local e = (ctx.seen or {})[u]
    if e ~= nil then return e end
    local hit = ctx.hit
    if hit == nil or hit.u ~= u or hit.x == nil then return nil end
    local dx, dy = hit.x + 0.5 - ctx.x, hit.y + 0.5 - ctx.y
    return { x = hit.x, y = hit.y, d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10 }
end

-- Reddition (pur) : compte du joueur auquel le membre se rend, raison ; ou nil. Entrées : ctx.canSurrender
-- (non-combattant d'un groupe qui ne tire pas le premier), ctx.seen ({ [compte] = { x, y, z, d } } joueurs perçus),
-- ctx.surrendered (reddition en cours de ce membre { u, last = dernière minute où le joueur était perçu à KEEP
-- cases }), ctx.betrayed ({ [compte] = vrai }), ctx.hit (dernier
-- coup reçu { u = compte d'un joueur ou nil }), ctx.health, ctx.threats.
function Decisions.surrenderTo(ctx)
    if not ctx.canSurrender then return nil end
    local c = P.cfg().SURRENDER
    local seen, betrayed = ctx.seen or {}, ctx.betrayed or {}
    local cur = ctx.surrendered
    if cur ~= nil and not betrayed[cur.u] then
        local e = seen[cur.u]
        if e ~= nil and e.d <= c.KEEP then return cur.u, string.format("still surrendering to %s at %.1f", cur.u, e.d) end
        if (ctx.minute or 0) - (cur.last or 0) <= c.LINGER then
            return cur.u, string.format("still surrendering to %s (out of sight)", cur.u)
        end
    end
    local hit = ctx.hit
    if hit ~= nil and hit.u ~= nil and not betrayed[hit.u] then
        local e = Decisions.playerSpot(ctx, hit.u)   -- perçu, sinon lieu du coup reçu
        if e ~= nil and e.d <= c.KEEP and (ctx.health or 1) < c.HEALTH then
            return hit.u, string.format("hit by %s at %.1f, health %d%%", hit.u, e.d,
                math.floor((ctx.health or 1) * 100 + 0.5))
        end
    end
    for _, t in ipairs(ctx.threats or {}) do
        if t.kind == "player" and t.flee and t.seen and t.d <= c.DIST and not betrayed[t.label] then
            return t.label, string.format("cornered by %s at %.1f", t.label, t.d)
        end
    end
    return nil
end

-- LK06-T07 (décision du 2026-10-12 : « tout le monde se bat ») : constantes mauvaises d'un membre (pur), quel que
-- soit son rôle : santé de référence sous Decisions.woundRatio() ou peur >= Decisions.fearHigh() (LK05-T16 : options
-- WoundedHealth et AfraidFear, relues à chaque appel). Rend la raison, ou nil (membre valide : il se bat contre un
-- zombie à portée, ne fuit pas et ne s'abrite pas).
function Decisions.unfitOf(ctx)
    local ratio = Decisions.woundRatio()
    if ctx.health ~= nil and ctx.health < ratio then
        return string.format("health %d%% < %d%%", math.floor(ctx.health * 100 + 0.5), math.floor(ratio * 100 + 0.5))
    end
    local fear, high = (ctx.needs or {}).fear or 0, Decisions.fearHigh()
    if fear >= high then
        return string.format("fear %d >= %d", math.floor(fear), high)
    end
    return nil
end

-- Rapport de repli hors de la défense : option DefenseWithdrawRatio (LivingKnox.Defense.ratios), sinon OVERWHELM.RATIO.
function Decisions.overwhelmRatio()
    local Df = LivingKnox.Defense
    if Df ~= nil and Df.ratios ~= nil then return (Df.ratios()) end
    return LivingKnox.Config.danger("DefenseWithdrawRatio", P.cfg().OVERWHELM.RATIO)
end

-- Poids des menaces perçues qui mettent en danger (pur) : menaces à fuir à RETREAT.DIST cases au plus ; zombie 1,
-- joueur hostile OVERWHELM.HOSTILE_WEIGHT.
function Decisions.threatWeight(threats)
    local w = 0
    local dist = Decisions.retreatDist()
    for _, t in ipairs(threats or {}) do
        if t.flee and (t.d or 0) <= dist then
            w = w + (t.kind == "player" and P.cfg().OVERWHELM.HOSTILE_WEIGHT or 1)
        end
    end
    return w
end

-- Groupe débordé (pur) : menace pondérée weight contre able membres valides ; before = le membre se repliait déjà
-- parce que débordé (hystérésis : il reste replié tant que menace > (rapport - 1) x valides). Rend la raison ou nil.
function Decisions.overwhelmedOf(weight, able, before)
    if weight == nil or weight <= 0 then return nil end
    local ratio = Decisions.overwhelmRatio()
    if able <= 0 then return string.format("overwhelmed: threat %d, no able member", weight) end
    local limit = before and (ratio - 1) or ratio
    if weight > limit * able then
        return string.format("overwhelmed: threat %d > %d x %d able member(s)", weight, limit, able)
    end
    return nil
end

-- Retraite (pur) : raison si le membre en danger doit se retirer, ou nil. Danger : cible d'attaque (ctx.target), coup
-- reçu récent (ctx.hit) ou menace à fuir à RETREAT.DIST cases. Blessé : santé < HEALTH ; à bout de nerfs : peur >=
-- FEAR (tout rôle depuis LK06-T07) ; moral du groupe (ctx.morale) sous LOW_MORALE : santé limite relevée, peur limite
-- abaissée. LK06-T07 : groupe débordé (ctx.overwhelmed, hors de la défense du foyer qui fait son propre repli). Au
-- foyer, seul un membre à bout de nerfs ou débordé sans défense se retire (il se terre) ; un blessé au foyer passe
-- par la défense (abri) ou la règle de fuite.
function Decisions.retreatOf(ctx)
    local c = P.cfg().RETREAT
    local t = ctx.threat
    local danger = ctx.target ~= nil or ctx.hit ~= nil or (t ~= nil and t.flee and t.d <= Decisions.retreatDist())
    if not danger then return nil end
    local low = ctx.morale ~= nil and ctx.morale < c.LOW_MORALE
    local hpLimit = c.HEALTH + (low and c.MORALE_HEALTH or 0)
    local fearLimit = c.FEAR - (low and c.MORALE_FEAR or 0)
    local fear = (ctx.needs or {}).fear or 0
    local wounded = ctx.health ~= nil and ctx.health < hpLimit
    local broken = fear >= fearLimit
    local over = ctx.overwhelmed
    if over ~= nil and ctx.defense ~= nil then over = nil end   -- défense du foyer : repli collectif de LK_Defense
    if not wounded and not broken and over == nil then return nil end
    if ctx.home ~= nil and ctx.atHome and not broken and (over == nil or wounded) then return nil end
    local why
    if wounded then
        why = string.format("health %d%% < %d%%", math.floor(ctx.health * 100 + 0.5), math.floor(hpLimit * 100 + 0.5))
    elseif broken then
        why = string.format("fear %d >= %d", math.floor(fear), math.floor(fearLimit))
    else
        why = over
    end
    if low then why = why .. ", group morale " .. ctx.morale end
    local onlyOver = not wounded and not broken   -- second retour : repli du seul débordement (hystérésis)
    if ctx.home ~= nil and not ctx.atHome then return why .. ", back home", onlyOver end
    if ctx.home == nil then return why .. ", fleeing", onlyOver end
    return why .. ", hiding at home", onlyOver
end

local RULES = {}

function RULES.threat(ctx)
    -- LK06-T05 : reddition, puis retraite, avant tout combat.
    local su, swhy = Decisions.surrenderTo(ctx)
    if su ~= nil then return "surrender", swhy, "p" .. su end
    local rwhy, onlyOver = Decisions.retreatOf(ctx)
    if rwhy ~= nil then return "retreat", rwhy, onlyOver and "overwhelmed" or "retreat" end
    -- LK05-T09 : défense du foyer (LivingKnox.Defense.contextFor) : place, cible depuis la place, avant le combat libre.
    local dv = ctx.defense
    -- LK11-T02 : sommation (LivingKnox.Encounters.contextFor), sans cible d'attaque ni cible de défense.
    local wn = ctx.warn
    if wn ~= nil and ctx.target == nil and (dv == nil or dv.target == nil) and Decisions.allows(ctx, "warn") then
        return "warn", wn.why, wn.key
    end
    if dv ~= nil then return "defend", dv.why, dv.key end
    -- LK06-T02 : cible d'attaque retenue par Hostility.chooseTarget (ctx.target) : un combattant engage la mêlée.
    -- LK06-T07 : tout membre valide (constantes bonnes, Decisions.unfitOf) se bat contre un zombie à portée, quel que
    -- soit son rôle ; un joueur reste la cible des seuls rôles qui permettent fight ou defend.
    local unfit = Decisions.unfitOf(ctx)
    local tg = ctx.target
    if tg ~= nil and unfit == nil then
        if tg.kind == "zombie" then   -- LK06-T04 : zombie proche à repousser (LivingKnox.Zombies.targetFor)
            return "fight", string.format("fight zombie %s at %.1f", tg.u, tg.d or 0), tg.u
        end
        if P.anyOf(ctx.allowed or {}, Decisions.COMBAT_BEHAVIOURS) then
            return "fight", string.format("attack player %s at %.1f (%s)", tg.u, tg.d or 0, tostring(tg.reason)),
                "p" .. tg.u
        end
    elseif tg ~= nil then
        -- Constantes mauvaises devant une cible : retraite (abri au foyer, retour au foyer, fuite pondérée sans foyer).
        local where = ", hiding at home"
        if ctx.home == nil then where = ", fleeing" elseif not ctx.atHome then where = ", back home" end
        return "retreat", string.format("%s %s at %.1f, %s%s", tg.kind == "zombie" and "zombie" or "player", tg.u,
            tg.d or 0, unfit, where), "retreat"
    end
    local t = ctx.threat
    if t == nil then
        -- LK05-T08 : alerte du groupe sans menace perçue par ce membre : dernière position connue partagée.
        local al = ctx.alert
        if al == nil then return nil end
        return "alert", string.format("group alert %s: %s %s last seen at %d,%d,%d (%.1f away, level %d)", al.id,
            al.kind, al.label, al.x, al.y, al.z, al.d, al.level), al.key
    end
    local what = string.format("%s %s at %.1f (%s)", t.kind, t.label or t.key, t.d, t.seen and "seen" or "heard")
    local afraid = ((ctx.needs or {}).fear or 0) >= Decisions.fearHigh()
    local flee = Decisions.fleeDist()
    if t.flee and (t.d <= flee or (afraid and t.d <= Decisions.fleeDistAfraid())) then
        -- LK06-T07 : fuite (ou abri au foyer) seulement aux constantes mauvaises ; un membre valide tient.
        if unfit ~= nil then
            if ctx.home ~= nil and ctx.atHome then
                return "retreat", what .. ", " .. unfit .. ", hiding at home", "retreat"
            end
            return "flee", what .. (t.d <= flee and ", too close, " or ", afraid, ") .. unfit, t.key
        end
        if t.d <= flee then return "watch", what .. ", too close, able member holds", t.key end
    end
    return "watch", what, t.key
end

local function needRule(name, behaviour)
    return function(ctx)
        local v = (ctx.needs or {})[name] or 0
        if v < Decisions.needHigh(name) then return nil end
        if ctx.unfed ~= nil and ctx.unfed[name] then return nil end   -- LK05-T07 : rien à prendre, repas récent
        if (ctx.trip ~= nil or ctx.hunt ~= nil) and name ~= "fear" then return nil end   -- LK05-T05, LK11-T05 : au retour
        return atHomeOr(ctx, behaviour), name .. " " .. v, name
    end
end

-- Peur (LK05-T06) : un membre apeuré fuit la source récente de sa peur si elle est proche (aucune menace perçue :
-- la règle threat passe avant) ; sinon il se met à l'abri au foyer. LK06-T07 : tout rôle (la peur élevée est une
-- constante mauvaise), et non plus les seuls non-combattants.
local fearAtHome = needRule("fear", "rest")
function RULES.fear(ctx)
    local b, why, key = fearAtHome(ctx)
    if b == nil then return nil end
    local src = ctx.fearFrom
    if src ~= nil and Decisions.allows(ctx, "flee") then
        local d = math.max(math.abs(src.x + 0.5 - ctx.x), math.abs(src.y + 0.5 - ctx.y))
        if d <= Decisions.fleeDistAfraid() then
            return "flee", string.format("%s, fleeing what scared it (%.1f away)", why, d), key
        end
    end
    return b, why, key
end
-- Faim, soif : repas réel au foyer (LK05-T07, routine « meal » de LK_Routines, ctx.meals) ; sans elle : au foyer.
local hungerHome, thirstHome = needRule("hunger", "home"), needRule("thirst", "home")
local hungerMeal, thirstMeal = needRule("hunger", "meal"), needRule("thirst", "meal")
function RULES.hunger(ctx) return (ctx.meals and hungerMeal or hungerHome)(ctx) end
function RULES.thirst(ctx) return (ctx.meals and thirstMeal or thirstHome)(ctx) end
RULES.fatigue = needRule("fatigue", "sleep")

function RULES.wound(ctx)
    if ctx.health == nil or ctx.health >= Decisions.woundRatio() then return nil end
    return atHomeOr(ctx, "rest"), string.format("health %d%%", math.floor(ctx.health * 100 + 0.5)), "wound"
end

function RULES.duty(ctx)
    -- LK05-T05 : membre de l'équipe d'une expédition en cours (LivingKnox.Expeditions.memberTrip), quel que soit son
    -- poste actuel ; une nouvelle expédition (autre numéro) interrompt l'état.
    local tr = ctx.trip
    if tr ~= nil then return "expedition", "expedition " .. tr.n .. " " .. tr.phase, "trip" .. tr.n end
    local hu = ctx.hunt   -- LK11-T05 : membre de l'équipe d'une vengeance en traque ou au retour (LivingKnox.Relations)
    if hu ~= nil then   -- LK11-T07 : même comportement pour un raid (kind "raid", LivingKnox.Raids)
        local kind = hu.kind or "revenge"
        return "revenge", kind .. " " .. hu.n .. " " .. hu.phase, (kind == "raid" and "raid" or "hunt") .. hu.n
    end
    local d = ctx.duty
    if d == nil then return nil end
    local why = "duty " .. d .. " (objective " .. tostring(ctx.objective) .. ")"
    if d == "sentry" then
        if not Decisions.allows(ctx, "guard") then return nil end
        -- LK05-T03 : poste de guet ou ronde selon l'heure (LivingKnox.Routines.sentryKind), poste par défaut.
        local kind = ctx.sentryKind == "patrol" and "patrol" or "guard"
        return atHomeOr(ctx, kind), why, d
    end
    if d == "rest" then return atHomeOr(ctx, ctx.night and "sleep" or "rest"), why, d end
    -- keeper, carer, forager, builder : corvées au foyer de jour (LK05-T04, routines chargées), sinon au foyer
    -- (expéditions LK05-T05, fortification LK14).
    -- Comme « home » : loin du foyer, la corvée commence par le retour (Decisions.apply), sans interrompre l'état.
    if ctx.chores and not ctx.night then return "chore", why, d end
    -- Cueilleur et bâtisseur la nuit sans expédition : aucun départ ni chantier avant le jour (départs de
    -- DEPART_FROM à DEPART_TO, pêche à l'aube et au crépuscule par une expédition, qui passe avant) : sommeil au
    -- foyer (lk.routines MP du 2026-11-04 : objectif « supply » la nuit, cueilleur debout toute la nuit).
    if ctx.night and (d == "forager" or d == "builder") then return atHomeOr(ctx, "sleep"), why, d end
    return "home", why, d
end

function RULES.routine(ctx)
    if ctx.chores and not ctx.night then return "chore", "routine", "routine" end
    return atHomeOr(ctx, ctx.night and "rest" or "home"), "routine", "routine"
end

-- Extension qui mène le comportement b, ou nil.
local function extensionOf(b)
    for _, x in ipairs(Decisions.extensions) do
        if x.id == b and x.apply ~= nil then return x end
    end
    return nil
end

-- Proposition de la règle fn (comportement permis au membre), ou nil.
local function proposal(ctx, fn)
    local b, why, key = fn(ctx)
    if b == nil or not Decisions.allows(ctx, b) then return nil end
    return b, why, key
end

-- Première proposition de la cascade : b, why, key, rang, nom de la règle. Avant chaque règle de PRIORITIES, les
-- règles des extensions placées devant elle (même rang : la règle suivante en interrompt l'état comme une autre).
local function firstProposal(ctx)
    for i, name in ipairs(Decisions.PRIORITIES) do
        for _, x in ipairs(Decisions.extensions) do
            for _, r in ipairs(x.rules or {}) do
                if r.before == name then
                    local b, why, key = proposal(ctx, r.rule)
                    if b ~= nil then return b, why, key, i, r.name end
                end
            end
        end
        local b, why, key = proposal(ctx, RULES[name])
        if b ~= nil then return b, why, key, i, name end
    end
    return nil
end

-- Décision d'un membre (pur) : ctx = { id, role, allowed, combatant, x, y, z, home, atHome, threat (menace la plus
-- proche ou nil), alert (alerte du groupe qui le concerne, Alert.forMember, LK05-T08, ou nil), needs, fearFrom
-- (source récente de la peur { x, y, z } ou nil, LK05-T06), health (0..1 ou nil), duty, objective, night, minute,
-- meals (vrai si les repas réels de LK05-T07 sont chargés), unfed (besoins mis de côté { hunger, thirst } ou nil),
-- sentryKind ("guard" ou "patrol", LK05-T03 ; absent = "guard"), chores (vrai si les corvées de LK05-T04 sont
-- chargées) } ; ces champs sont posés par les fournisseurs de contexte (Decisions.registerContext, LK16-T05), puis
-- par les extensions (input). Rend { b, p (rang de la règle), rule, why, key, start,
-- untilMin, angle (guet ou menace), away (fuite : angle d'éloignement) }.
function Decisions.decide(ctx)
    local b, why, key, i, rule = firstProposal(ctx)
    if b == nil then return nil end   -- inaccessible : la routine est toujours permise
    local rnd = Decisions.stream(ctx.id, ctx.minute or 0, i)
    local span = P.cfg().MINUTES[b] or { 5, 5 }
    local out = { b = b, p = i, rule = rule, why = why, key = key, start = ctx.minute or 0 }
    out.untilMin = out.start + P.pick(span[1], span[2], rnd)
    -- LK16-T06 : visée portée par le comportement (aim de l'extension qui le mène), tirages après la durée.
    local lead = extensionOf(b)
    if lead ~= nil and lead.aim ~= nil then lead.aim(ctx, out, rnd) end
    return out
end

-- Vrai si la décision out remplace l'état st : aucun état, échéance atteinte, ou interruption (autre règle, autre
-- comportement, autre cible).
function Decisions.replaces(st, out, minute)
    if st == nil then return true, "new" end
    if out.p ~= st.p or out.b ~= st.b or out.key ~= st.key then return true, "interrupted" end
    if minute >= st.untilMin then return true, "deadline" end
    return false
end

P.RULES = RULES
P.extensionOf = extensionOf
