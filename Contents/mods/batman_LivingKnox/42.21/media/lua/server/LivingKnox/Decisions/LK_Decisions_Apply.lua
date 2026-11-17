-- Living Knox : cadre de décision des PNJ, application d'une décision (consignes, gestes, extensions qui
-- mènent un comportement ; LK05-T02, LK16-T06).
-- LK20-T09 : sorti de LK_Decisions.lua sans changement de comportement ; façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Decisions/LK_Decisions_Common"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers de Decisions/ (LK_Decisions_Common.lua)

-- Consigne ouverte émise par un autre module : jamais remplacée.
local function externalDirective(id)
    local D = LivingKnox.Directives
    if D == nil or D.get == nil then return nil end
    local e = D.get(id)
    if e == nil or e.done then return nil end
    if Decisions.state.issued[id] == e.v then return nil end
    return e
end

-- Consigne ouverte émise par ce module (ou par les routines LK05-T03 pour lui), ou nil.
local function ownOpen(id)
    local D = LivingKnox.Directives
    local e = D and D.get and D.get(id) or nil
    if e == nil or e.done or Decisions.state.issued[id] ~= e.v then return nil end
    return e
end

local function issued(id, v, why)
    if v == nil then
        Decisions.stats.refused = Decisions.stats.refused + 1
        LivingKnox.Log.debug("npc %s: decision directive refused: %s", id, tostring(why))
        return false
    end
    Decisions.state.issued[id] = v
    Decisions.stats.issued = Decisions.stats.issued + 1
    return true
end
-- Partagés avec les routines (LK05-T03) : leurs consignes comptent comme celles du cadre (jamais « externes »).
Decisions.ownOpen = ownOpen
Decisions.noteIssued = issued

-- Case de retour au foyer : case libre près du foyer (même bâtiment, LK_Materialize), sinon la case du foyer.
local function homeTarget(home)
    local Mat = LivingKnox.Materialize
    if Mat ~= nil and Mat.homeSquare ~= nil then
        local sq, bid = Mat.homeSquare(home)
        if sq == nil then return nil, "home not loaded" end
        local place = Mat.placeFor and Mat.placeFor(home, bid, P.cfg().HOME_PLACE_RADIUS) or nil
        if place ~= nil then return place:getX(), place:getY(), place:getZ() end
    end
    return home.x, home.y, home.z
end

-- Retour au foyer en marchant (consigne déjà en route : rien).
function Decisions.goHome(id, ctx)
    local D = LivingKnox.Directives
    local open = ownOpen(id)
    if open ~= nil and open.op == D.OP_MOVE and open.g ~= "run" then return end   -- déjà en route
    local x, y, z = homeTarget(ctx.home)
    if x == nil then
        LivingKnox.Log.debug("npc %s: cannot go home: %s", id, tostring(y))
        return
    end
    issued(id, D.moveTo(id, x, y, z, "walk"))
end

-- Course vers le foyer, sauf si une consigne de marche du moteur est déjà ouverte (any : toute marche ; sinon seule
-- une course compte comme « déjà en route »).
function Decisions.runHome(id, ctx, any)
    local D = LivingKnox.Directives
    local open = ownOpen(id)
    if open ~= nil and open.op == D.OP_MOVE and (any or open.g == "run") then return end
    local x, y, z = homeTarget(ctx.home)
    if x ~= nil then issued(id, D.moveTo(id, x, y, z, "run")) end
end

-- Regard vers l'angle angle (nil : rien).
function Decisions.face(id, angle)
    local D = LivingKnox.Directives
    if angle == nil then return end
    issued(id, D.face(id, angle))
end

-- Arrêt de la marche émise par le moteur (consigne ouverte), s'il y en a une.
function Decisions.stopOwnMove(id)
    local D = LivingKnox.Directives
    local open = ownOpen(id)
    if open ~= nil and open.op == D.OP_MOVE then issued(id, D.stop(id)) end
end

-- Vrai si le moteur a émis une course encore ouverte (retour au foyer, place de défense) : elle va à son terme avant
-- un regard (lk.windowsally MP du 2026-11-16 : course vers la place dedans coupée par le regard d'alerte).
function Decisions.runningOwnMove(id)
    local open = ownOpen(id)
    return open ~= nil and open.op == LivingKnox.Directives.OP_MOVE and open.g == "run"
end

-- Regard vers la case (x, y) : état neuf, premier regard, ou écart d'au moins FACE_DELTA degrés avec le dernier
-- regard (st.faced). Rend vrai si une consigne est émise.
function Decisions.faceTowards(id, st, ctx, x, y, fresh)
    if x == nil then return false end
    local a = Decisions.angleTo(x + 0.5 - ctx.x, y + 0.5 - ctx.y)
    if a == nil or not (fresh or st.faced == nil or LivingKnox.Geo.angleGap(a,
        st.faced) >= P.cfg().FACE_DELTA) then return false end
    st.faced = a
    Decisions.face(id, a)
    return true
end

-- Geste d'alerte, de reddition ou de défense (LK05-T08, LK06-T12) : posé par le comportement qui le garde
-- (extension à champ gesture, Decisions.setAlertGesture) après ses consignes (une consigne « face » ou « stop » remet
-- le geste au repos, LK_Directives.issue), reposé à chaque passage s'il a changé ; retiré par le moteur quand le
-- membre passe à un comportement qui ne garde pas de geste (seulement s'il est encore le nôtre).
local function alertGestures()
    local st = Decisions.state
    st.gestures = st.gestures or {}
    return st.gestures
end

function Decisions.setAlertGesture(id, gesture)
    local A = LivingKnox.Anim
    if A == nil then return end
    local mine = alertGestures()
    if gesture == nil then
        local had = mine[id]
        mine[id] = nil
        if had ~= nil and A.gestureOf(id) == had then A.setGesture(id, A.DEFAULT) end
        return
    end
    mine[id] = gesture
    if A.gestureOf(id) ~= gesture then A.setGesture(id, gesture) end
end

-- Vrai si le meneur lead du comportement garde son geste à ce passage (champ gesture).
local function holdsGesture(lead, ctx, st)
    if lead == nil or lead.gesture == nil then return false end
    if lead.gesture == true then return true end
    return lead.gesture(ctx, st) == true
end

-- Vrai si le meneur lead garde l'état de l'extension x (champ keeps).
local function keeps(lead, x)
    for _, k in ipairs(lead ~= nil and lead.keeps or {}) do
        if k == x.id then return true end
    end
    return false
end

-- Applique un état nouveau (fresh) ou en cours : geste retiré (sauf comportement qui garde le sien), vigilance
-- (perception de l'autorité et consigne courante, champ vg, MP), sorties de la routine et des autres extensions, puis
-- l'extension qui mène le comportement (LK16-T06) ; sans elle, ou après le soin et la routine pour une extension
-- overlay : soin (LK07-T03, comportement calme au foyer), routine (LK05-T03 : guet au poste, ronde, sommeil, corvées,
-- repas, au foyer), puis repli du moteur : retour au foyer s'il est loin, sinon fin de sa propre marche.
function Decisions.apply(id, st, ctx, fresh)
    local D = LivingKnox.Directives
    local S = LivingKnox.Senses
    local b = st.b
    local def = Decisions.BEHAVIOURS[b]
    local lead = P.extensionOf(b)
    if not holdsGesture(lead, ctx, st) then Decisions.setAlertGesture(id, nil) end
    if S ~= nil and S.setVigilance ~= nil then S.setVigilance(id, def.vigil) end
    if D == nil then return end
    if D.setVigil ~= nil then D.setVigil(id, def.vigil) end
    local R = LivingKnox.Routines
    local routine = R ~= nil and R.handles(b) and (ctx.home == nil or ctx.atHome)
    if R ~= nil and not routine then R.leave(id) end   -- routine interrompue ou finie : debout, mémoire oubliée
    for _, x in ipairs(Decisions.extensions) do
        if x.leave ~= nil and x ~= lead and not keeps(lead, x) then x.leave(id) end
    end
    if lead ~= nil and not lead.overlay then
        lead.apply(id, st, ctx, fresh)
        return
    end
    if lead == nil and def.owned then return end
    local Ca = LivingKnox.Care   -- LK07-T03 : soin (médecin ou blessé seul) mené pendant un comportement calme au foyer
    if Ca ~= nil and Ca.apply ~= nil and Ca.apply(id, st, ctx, fresh) then return end
    if routine then
        R.apply(id, st, ctx, fresh)
        return
    end
    if lead ~= nil then
        lead.apply(id, st, ctx, fresh)
        return
    end
    if not fresh then return end
    if ctx.home ~= nil and not ctx.atHome then
        Decisions.goHome(id, ctx)
    else
        Decisions.stopOwnMove(id)   -- fin d'une fuite au foyer
    end
end

P.externalDirective = externalDirective
