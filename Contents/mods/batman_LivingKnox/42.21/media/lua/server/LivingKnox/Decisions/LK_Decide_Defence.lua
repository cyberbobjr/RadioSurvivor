-- Living Knox : comportements de défense personnelle de la cascade (LK16-T06, chantier C2), menés hors du moteur de
-- décision : reddition (« surrender »), retraite (« retreat »), regard vers une menace (« watch »), alerte du groupe
-- (« alert ») et fuite (« flee »). Fiches : docs/annexes/conception/decisions.md, fuite-reddition.md, alerte.md.
-- Les RÈGLES qui les proposent restent dans LK_Decisions.lua (règle threat, décision D04 de l'ADR de remise en ordre) ;
-- ce fichier inscrit, pour chacun, l'extension propriétaire (Decisions.registerExtension) : visée (aim), geste gardé
-- (gesture) et application (apply, overlay : après le soin et la routine, comme avant la migration).
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée plus bas

local Decisions = LivingKnox.Decisions
local Defence = LivingKnox.DecideDefence or {}
LivingKnox.DecideDefence = Defence

local function cfg() return Decisions.CFG end

-- Angle (degrés) du membre vers la case (x, y), ou nil.
local function angleFrom(ctx, x, y) return Decisions.angleTo(x + 0.5 - ctx.x, y + 0.5 - ctx.y) end

-- Geste d'alerte (LK05-T08) : garde pour un membre valide, accroupi aux constantes mauvaises (LK06-T07).
local function alertGesture(ctx) return Decisions.unfitOf(ctx) ~= nil and "crouch" or "guard" end

-- ================================================================ visées (pures)

-- Fuite pondérée (LK06-T05, I6.5) : angle d'éloignement de toutes les menaces perçues, sinon de la source récente de
-- la peur (LK05-T06) ; côté de contournement tiré.
local function aimAway(ctx, out, rnd)
    local t = ctx.threat
    local src = t or ctx.fearFrom
    if src == nil then return end
    out.away = Decisions.fleeAngle(ctx.x, ctx.y, ctx.threats or { t }, src) or Decisions.pick(0, 7, rnd) * 45
    out.side = rnd() < 0.5 and -1 or 1
end

function Defence.aimRetreat(ctx, out, rnd)
    aimAway(ctx, out, rnd)
    local t = ctx.threat
    if t then out.angle = angleFrom(ctx, t.x, t.y) end
end

function Defence.aimSurrender(ctx, out)
    local u = string.sub(out.key or "", 2)   -- clé "p<compte>"
    local e = Decisions.playerSpot(ctx, u)
    if e ~= nil then out.angle = angleFrom(ctx, e.x, e.y) end
    out.u = u
end

function Defence.aimWatch(ctx, out)
    local t = ctx.threat
    if t then out.angle = angleFrom(ctx, t.x, t.y) end
end

function Defence.aimAlert(ctx, out)
    local al = ctx.alert
    if al then out.angle = angleFrom(ctx, al.x, al.y) end
end

-- ================================================================ applications

-- Pas de fuite de FLEE_STEP cases dans la direction st.away (puis +-45, +-90 degrés du côté st.side) vers une case
-- libre, en courant ; aucune case : regard vers la menace. Rend vrai si la consigne de fuite est émise.
function Defence.fleeStep(id, ctx, st)
    local D = LivingKnox.Directives
    local cell = getCell()
    local step = cfg().FLEE_STEP
    local offsets = { 0, 45 * st.side, -45 * st.side, 90 * st.side, -90 * st.side }
    for _, off in ipairs(offsets) do
        local a = (st.away + off) * math.pi / 180
        local tx = math.floor(ctx.x + step * math.cos(a))
        local ty = math.floor(ctx.y + step * math.sin(a))
        local sq = cell and cell:getGridSquare(tx, ty, ctx.z) or nil
        if sq ~= nil and sq:isFree(false) then
            local v = D.moveTo(id, tx, ty, ctx.z, "run")
            if v ~= nil then
                Decisions.noteIssued(id, v)
                return true
            end
        end
    end
    Decisions.stats.refused = Decisions.stats.refused + 1
    LivingKnox.Log.debug("npc %s: no square to flee to, watching instead", id)
    if ctx.threat then Decisions.face(id, angleFrom(ctx, ctx.threat.x, ctx.threat.y)) end
    return false
end

-- LK06-T05 : reddition : arrêt, regard vers le joueur, mains levées (geste SURRENDER_GESTURE, LK06-T12).
function Defence.applySurrender(id, st, ctx, fresh)
    Decisions.stopOwnMove(id)
    local e = Decisions.playerSpot(ctx, st.u)
    if e ~= nil then Decisions.faceTowards(id, st, ctx, e.x, e.y, fresh) end
    Decisions.setAlertGesture(id, Decisions.SURRENDER_GESTURE)
end

-- LK06-T05 : retraite : course vers le foyer ; sans foyer, fuite pondérée ; au foyer, accroupi face à la menace. Geste
-- posé après les consignes (une consigne « face » ou « stop » remet le geste au repos).
function Defence.applyRetreat(id, st, ctx, fresh)
    if ctx.home ~= nil and not ctx.atHome then
        Decisions.setAlertGesture(id, nil)
        Decisions.runHome(id, ctx, false)
        return
    end
    if ctx.home == nil then
        Decisions.setAlertGesture(id, nil)
        if fresh and st.away ~= nil then Defence.fleeStep(id, ctx, st) end
        return
    end
    Decisions.stopOwnMove(id)
    local t = ctx.threat
    if t ~= nil then Decisions.faceTowards(id, st, ctx, t.x, t.y, fresh) end
    Decisions.setAlertGesture(id, "crouch")
end

-- Regard vers la menace perçue (watch) ou la dernière position partagée par l'alerte (alert) ; geste d'alerte pendant
-- une alerte du groupe. LK06-T07 : en alerte, un membre aux constantes mauvaises loin du foyer y court d'abord (abri),
-- accroupi ensuite.
local function applyLook(id, st, ctx, fresh, t, gesture)
    if Decisions.runningOwnMove(id) then return end   -- course en cours (place de défense, abri) : regard à l'arrivée
    Decisions.faceTowards(id, st, ctx, t and t.x, t and t.y, fresh)
    if gesture ~= nil then Decisions.setAlertGesture(id, gesture) end
end

function Defence.applyWatch(id, st, ctx, fresh)
    applyLook(id, st, ctx, fresh, ctx.threat, ctx.alert ~= nil and alertGesture(ctx) or nil)
end

function Defence.applyAlert(id, st, ctx, fresh)
    if Decisions.unfitOf(ctx) ~= nil and ctx.home ~= nil and not ctx.atHome then
        Decisions.runHome(id, ctx, true)
        return
    end
    applyLook(id, st, ctx, fresh, ctx.alert, alertGesture(ctx))
end

-- Fuite (LK06-T07 : constantes mauvaises ou groupe débordé, tout rôle) : un pas à l'état neuf.
function Defence.applyFlee(id, st, ctx, fresh)
    if fresh then Defence.fleeStep(id, ctx, st) end
end

-- ================================================================ inscription (ordres 70 à 74, après les modules)

local function holdsWatchGesture(ctx) return ctx.alert ~= nil end

Decisions.registerExtension({ id = "surrender", order = 70, overlay = true, gesture = true,
    aim = Defence.aimSurrender, apply = Defence.applySurrender })
Decisions.registerExtension({ id = "retreat", order = 71, overlay = true, gesture = true,
    aim = Defence.aimRetreat, apply = Defence.applyRetreat })
Decisions.registerExtension({ id = "watch", order = 72, overlay = true, gesture = holdsWatchGesture,
    aim = Defence.aimWatch, apply = Defence.applyWatch })
Decisions.registerExtension({ id = "alert", order = 73, overlay = true, gesture = true,
    aim = Defence.aimAlert, apply = Defence.applyAlert })
Decisions.registerExtension({ id = "flee", order = 74, overlay = true, aim = aimAway, apply = Defence.applyFlee })

-- LK18-T01 (ADR adr-ceder-le-passage.md D02, fiche passage.md) : priorité de passage du comportement, déclarée ici.
LivingKnox.Passage.priority("flee", 100)
LivingKnox.Passage.priority("retreat", 100)
LivingKnox.Passage.priority("surrender", 70)
LivingKnox.Passage.priority("watch", 70)
LivingKnox.Passage.priority("alert", 70)

return Defence
