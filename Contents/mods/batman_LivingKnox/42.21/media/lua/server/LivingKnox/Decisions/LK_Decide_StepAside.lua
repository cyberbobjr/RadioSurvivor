-- Living Knox : action "s'ecarter" d'un PNJ qui cede le passage (LK18-T02). ADR :
-- docs/architecture/decisions/adr-ceder-le-passage.md (D03, D05, D06). Fiche : docs/annexes/conception/passage.md.
--
-- Ordre donne par l'autorite (LK_PassageAuthority, decision de LivingKnox.Passage.arbitrate) :
--   StepAside.order(id, decision, moverId) : le bloqueur id marche aussitot (Directives.moveTo) vers la case decidee
--   decision.to (pas de cote ou recul ; marche visant decision.aim quand l'autorite en donne une) ; il y attend que
--   le demandeur soit passe (passed : demandeur au-dela de la case quittee, du cote oppose a son depart, a PASSED
--   case au moins ; consigne du demandeur close ; corps parti) ou HOLD_MS au plus, puis rend la main.
-- Reprise :
--   - membre mene par le cadre de decision (consigne du cadre, ou aucune consigne ouverte) : extension "stepAside"
--     de la cascade (Decisions.registerExtension) : sa regle, placee devant "threat", propose le comportement
--     tant que l'ordre dure (le cadre ne le renvoie pas a son poste pendant l'ecart) ; la consigne de l'ecart est
--     notee comme celle du cadre (Decisions.noteIssued). Ordre fini : la regle se tait, la cascade rend au membre son
--     comportement (etat neuf : la routine le ramene a son poste) ;
--   - PNJ hors du cadre (consigne ouverte d'un autre module : suite de test, API ; ou PNJ sans groupe) : sa marche
--     interrompue est relancee vers la meme case, ou, sans marche, retour a la case quittee.
-- Fin des ordres verifiee par StepAside.tick (OnTick de l'autorite) toutes les CHECK_MS au plus.
-- Autorite seulement : un client MP charge aussi media/lua/server, il s'arrete ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Decisions"

local Decisions = LivingKnox.Decisions
local StepAside = LivingKnox.StepAside or {}
LivingKnox.StepAside = StepAside

StepAside.ID = "stepAside"
StepAside.HOLD_MS = 8000     -- attente bornee a l'ecart
StepAside.PASSED = 1.5       -- cases : demandeur au-dela de la case quittee par le bloqueur
StepAside.CHECK_MS = 500     -- fin des ordres verifiee au plus toutes les CHECK_MS

StepAside.orders = StepAside.orders or {}   -- bloqueur -> { to, action, mover, ms, from, start, member, v, resume }
StepAside.state = StepAside.state or { lastCheck = 0 }
StepAside.stats = StepAside.stats or { ordered = 0, passed = 0, timeout = 0, left = 0, resumed = 0 }

local function now() return getTimestampMs() end

-- Consigne ouverte du PNJ id emise hors du cadre de decision (suite de test, API, autre module), ou nil.
local function foreignOpen(id)
    local e = LivingKnox.Directives.get(id)
    if e == nil or e.done or Decisions.ownOpen(id) ~= nil then return nil end
    return e
end

-- Vrai si le PNJ id a un ordre d'ecart en cours.
function StepAside.active(id)
    return StepAside.orders[id] ~= nil
end

-- Ordre au bloqueur id : s'ecarter vers decision.to (marche visant decision.aim, sinon decision.to) pour le demandeur
-- moverId. Rend vrai, ou faux et la raison.
function StepAside.order(id, decision, moverId)
    if StepAside.orders[id] ~= nil then return false, "already stepping aside" end
    local body = LivingKnox.Bodies.find(id)
    if body == nil then return false, "no body" end
    local foreign = foreignOpen(id)
    local o = { to = decision.to, action = decision.action, mover = moverId, ms = now(),
        from = { x = math.floor(body:getX()), y = math.floor(body:getY()), z = math.floor(body:getZ()) },
        member = Decisions.get(id) ~= nil and foreign == nil }
    local mz = LivingKnox.Bodies.find(moverId)
    if mz ~= nil then o.start = { x = mz:getX(), y = mz:getY() } end
    if not o.member then
        if foreign ~= nil and foreign.op == LivingKnox.Directives.OP_MOVE then
            o.resume = { x = foreign.x, y = foreign.y, z = foreign.z, g = foreign.g }
        else
            o.resume = { x = o.from.x, y = o.from.y, z = o.from.z, g = "walk" }
        end
    end
    local aim = decision.aim or decision.to
    local v, why = LivingKnox.Directives.moveTo(id, aim.x, aim.y, aim.z, "walk")
    if v == nil then return false, why end
    if o.member then Decisions.noteIssued(id, v) end
    o.v = v
    StepAside.orders[id] = o
    StepAside.stats.ordered = StepAside.stats.ordered + 1
    LivingKnox.Log.info("npc %s: %s to %d,%d,%d for %s (%s)", id, tostring(o.action), o.to.x, o.to.y, o.to.z, moverId,
        o.member and "decision frame resumes after" or "move resumed after")
    return true
end

-- Vrai si le demandeur est passe (voir l'en-tete) : (mx, my) sa position, open vrai si sa consigne est ouverte.
function StepAside.passed(o, mx, my, open)
    if mx == nil or not open then return true end
    local ox, oy = o.from.x + 0.5, o.from.y + 0.5
    local dx, dy = mx - ox, my - oy
    if dx * dx + dy * dy < StepAside.PASSED * StepAside.PASSED then return false end
    if o.start == nil then return true end
    return dx * (ox - o.start.x) + dy * (oy - o.start.y) > 0
end

-- Raison de finir l'ordre o a l'instant t ("timeout", "passed"), ou nil.
function StepAside.endOf(o, t)
    if t - o.ms >= StepAside.HOLD_MS then return "timeout" end
    local mz = LivingKnox.Bodies.find(o.mover)
    local e = LivingKnox.Directives.get(o.mover)
    local open = mz ~= nil and e ~= nil and not e.done
    if StepAside.passed(o, mz and mz:getX() or nil, mz and mz:getY() or nil, open) then return "passed" end
    return nil
end

-- Fin de l'ordre du PNJ id (raison why) : reprise de la marche interrompue (PNJ hors du cadre) ; un membre du cadre
-- reprend son comportement a sa prochaine evaluation. Rend vrai si un ordre existait.
function StepAside.finish(id, why)
    local o = StepAside.orders[id]
    if o == nil then return false end
    StepAside.orders[id] = nil
    StepAside.stats[why] = (StepAside.stats[why] or 0) + 1
    local resumed = "behaviour resumed by the decision frame"
    if o.resume ~= nil and LivingKnox.Bodies.find(id) ~= nil then
        local r = o.resume
        local v, rwhy = LivingKnox.Directives.moveTo(id, r.x, r.y, r.z, r.g)
        if v ~= nil then
            StepAside.stats.resumed = StepAside.stats.resumed + 1
            resumed = string.format("move to %d,%d,%d resumed (#%d)", r.x, r.y, r.z, v)
        else
            resumed = "move not resumed: " .. tostring(rwhy)
        end
    end
    LivingKnox.Log.info("npc %s: stepped aside for %s, %s after %d ms, %s", id, tostring(o.mover), why, now() - o.ms, resumed)
    return true
end

-- Ordres finis (demandeur passe ou HOLD_MS), au plus une verification par CHECK_MS. Rend le nombre d'ordres finis.
function StepAside.tick()
    local t = now()
    if t - StepAside.state.lastCheck < StepAside.CHECK_MS then return 0 end
    StepAside.state.lastCheck = t
    local ends = {}
    for id, o in pairs(StepAside.orders) do
        local why = StepAside.endOf(o, t)
        if why ~= nil then ends[#ends + 1] = { id = id, why = why } end
    end
    table.sort(ends, function(a, b) return a.id < b.id end)
    for _, x in ipairs(ends) do StepAside.finish(x.id, x.why) end   -- table modifiee hors de pairs
    return #ends
end

-- ================================================================ extension du cadre de decision

-- Regle (devant "threat") : le membre qui a un ordre en cours s'ecarte.
function StepAside.rule(ctx)
    local o = StepAside.orders[ctx.id]
    if o == nil or not o.member then return nil end
    return StepAside.ID, "making way for " .. tostring(o.mover), o.mover
end

-- Application : la consigne de l'ecart est deja donnee par l'ordre ; le membre attend a l'ecart.
function StepAside.apply(id, st, ctx, fresh)
    return StepAside.orders[id] ~= nil
end

-- Membre sorti du comportement (autre regle gagnante) ou oublie : ordre retire, sans reprise.
function StepAside.leave(id)
    if StepAside.orders[id] == nil then return end
    StepAside.orders[id] = nil
    StepAside.stats.left = StepAside.stats.left + 1
end

function StepAside.reset()
    StepAside.orders = {}
    StepAside.state = { lastCheck = 0 }
end

Decisions.registerExtension({ id = StepAside.ID, order = 5,
    rules = { { name = StepAside.ID, before = "threat", rule = StepAside.rule } },
    behaviour = { vigil = "guard", minutes = { 1, 1 } },
    apply = StepAside.apply, leave = StepAside.leave })

if LivingKnox.isAuthority() and Events ~= nil then
    local function onTick()
        LivingKnox.StepAside.tick()
    end
    LivingKnox.subscribe("OnTick", "StepAside.tick", onTick)
end

return StepAside
