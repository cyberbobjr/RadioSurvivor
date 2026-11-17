-- Living Knox : obstacles, verre brisé d'une fenêtre (LK21-T12, ADR docs/architecture/decisions/adr-blessures-soins.md,
-- D03, « Verre brisé (utilisateur, 2026-11-17) »). Façade et vue d'ensemble : LK_Obstacles.lua.
--
-- Une fenêtre brisée ne s'oppose pas au corps : le moteur l'enjambe (climbwindow). Le vanilla blesse un joueur qui
-- enjambe une fenêtre brisée dont le verre reste, 1 fois sur 2 (ClimbThroughWindowState.java:532-534), et lui offre
-- l'action « retirer le verre brisé » (ISRemoveBrokenGlass). Règle pure : LivingKnox.EdgeRules.glassStep.
--   - Retrait (PNJ qui n'est pas pressé) : fenêtre au verre restant au contact (REACH case du milieu du bord), sur le
--     trajet (étape courante ou suivante) et en face du corps : geste "removeglass" (LivingKnox.Anim.startAct ;
--     l'exécutant arrête le corps, le tourne vers la fenêtre, puis relance son chemin à la fin du geste). Verre retiré
--     GLASS_REMOVE_MS après le début du geste par l'autorité, comme ISRemoveBrokenGlass:complete :
--     IsoWindow:removeBrokenGlass() (setGlassRemoved(true) hors client, IsoWindow.java:1300-1306) puis, sur un
--     serveur, sync() (état absolu, verre retiré compris, envoyé à toutes les connexions, IsoWindow.java:733-760).
--     Le geste dure un peu plus que l'action : le verre est retiré avant que le chemin ne reprenne.
--   - Pressé (fuite, combat, urgence : inHurry) : aucun geste ; le corps enjambe aussitôt.
--   - Enjambée d'une fenêtre au verre restant, par tout PNJ en marche (pressé, ou retrait manqué) : risque du vanilla
--     une fois par escalade, tirage « 1 fois sur 2 » de la source "glass" fait ici, puis LivingKnox.Health.applyHit
--     (GLASS_DAMAGE, comme AddDamage(10) du vanilla, BodyDamage.java:1631-1638 ; source "glass", risk = false : la
--     plaie est alors certaine, partie et sorte tirées par la source, LK_WoundSource_Glass.lua).
-- Mémoire seulement : un redémarrage oublie les gestes en cours (le verre reste, le PNJ le retire au passage suivant).
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Obstacles/LK_Obstacles_Common"
require "LivingKnox/LK_Passage"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers de Obstacles/ (LK_Obstacles_Common.lua)

-- Action vanilla ISRemoveBrokenGlass : 100 unités de maxTime, à 48 unités par seconde réelle (multiplicateur de
-- GameTime à vitesse 1 ; base pz-knowledge api-42-21.md) : 2,08 s.
Obstacles.GLASS_REMOVE_MS = 2080
Obstacles.GLASS_GESTURE_MS = 2330     -- geste tenu 250 ms de plus (trois passages) : verre retiré avant la reprise
Obstacles.GLASS_DAMAGE = 10           -- AddDamage(10) sur la partie blessée (BodyDamage.setScratchedWindow)
-- Priorité de passage (LivingKnox.Passage) à partir de laquelle le comportement courant presse le PNJ : alerte,
-- défense, soin, combat, fuite (70 à 100) ; corvées, repas, expédition, garde (30 à 60) ne pressent pas.
Obstacles.HURRY_PRIORITY = 70

Obstacles.glassActs = Obstacles.glassActs or {}   -- clé de bord -> retrait du verre en cours { win, wk, e, id, ms, doneMs }
Obstacles.glassClimbs = Obstacles.glassClimbs or {}   -- npcId -> clé de la fenêtre au verre restant qu'il escalade

-- Vrai si le comportement courant du PNJ id le presse : priorité de passage de son genre (LK_PassageAuthority.kindOf,
-- comportement au cadre de décision ou soin) au moins HURRY_PRIORITY. Aucun genre : priorité par défaut, pas pressé.
function Obstacles.inHurry(id)
    local Pa, Au = LivingKnox.Passage, LivingKnox.PassageAuthority
    if Pa == nil or Au == nil or Au.kindOf == nil then return false end
    return Pa.priorityOf(Au.kindOf(id)) >= Obstacles.HURRY_PRIORITY
end

-- Conduite du PNJ id devant la fenêtre w de sorte wk (EdgeRules.glassStep) : "remove", "risk" ou nil.
function Obstacles.glassStep(id, w, wk)
    return LivingKnox.EdgeRules.glassStep(LivingKnox.Edges.windowFacts(w, wk), Obstacles.inHurry(id))
end

-- Retire le verre de la fenêtre w sur l'autorité, comme ISRemoveBrokenGlass:complete (voir l'en-tête).
function Obstacles.removeGlass(w)
    w:removeBrokenGlass()
    if isServer() then w:sync() end
end

-- Fenêtre au verre restant que le PNJ id (corps z) doit d'abord dégager : la plus proche au contact, sur le trajet
-- (onWay(c)) et en face du corps, avec la conduite "remove". Rend l'élément de windowsNear, ou nil.
local function glassToRemove(id, z, onWay)
    for _, c in ipairs(Obstacles.windowsNear(z:getX(), z:getY(), math.floor(z:getZ()))) do
        if onWay(c) and Obstacles.facing(z, c.e) then
            if Obstacles.glassStep(id, c.win, c.wk) == "remove" then return c end
            return nil   -- fenêtre du trajet sans verre, ou PNJ pressé
        end
    end
    return nil
end

-- Retrait du verre avant l'enjambée, pour le PNJ id (corps z) : onWay(c) dit si la fenêtre c de
-- windowsNear est sur son trajet. Rend vrai si un retrait est en cours ou vient de commencer.
function Obstacles.checkGlass(id, z, onWay, t)
    if P.climbing(z) then return false end
    for _, r in pairs(Obstacles.glassActs) do
        if r.id == id then return true end
    end
    local c = glassToRemove(id, z, onWay)
    if c == nil or Obstacles.glassActs[c.e.key] ~= nil then return false end
    if not P.windowGesture(id, z, c.e, "removeglass", Obstacles.GLASS_GESTURE_MS) then return false end
    Obstacles.glassActs[c.e.key] = { win = c.win, wk = c.wk, e = c.e, id = id, ms = t,
        doneMs = t + Obstacles.GLASS_REMOVE_MS }
    P.count("glassGestures")
    LivingKnox.Log.info("npc %s: removes the broken glass of the window %s", id, c.e.key)
    return true
end

-- Raison d'interrompre le retrait r (corps z), ou nil : fenêtre disparue, plus de verre à retirer ou PNJ devenu
-- pressé (glassStep n'est plus "remove"), corps hors du monde, consigne "move" plus en cours.
local function glassStopReason(r, z)
    if P.gone(r.win) then return "window removed" end
    if Obstacles.glassStep(r.id, r.win, r.wk) ~= "remove" then return "no glass to remove now" end
    if z == nil or not LivingKnox.Bodies.inWorld(z) then return "body gone" end
    if P.moveState(r.id) ~= "moving" then return "move no longer running" end
    return nil
end

-- Retraits en cours, à chaque passage : verre retiré à doneMs, ou geste interrompu (glassStopReason). Le geste
-- échu est retiré par LivingKnox.Anim ; l'exécutant relance alors le chemin.
function Obstacles.glassActPass(t)
    local keys = {}
    for key in pairs(Obstacles.glassActs) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    for _, key in ipairs(keys) do
        local r = Obstacles.glassActs[key]
        local why = glassStopReason(r, LivingKnox.Bodies.find(r.id))
        if why ~= nil then
            Obstacles.glassActs[key] = nil
            P.count("glassGesturesStopped")
            local A = LivingKnox.Anim
            if A ~= nil and A.endAct ~= nil then A.endAct(r.id, "removeglass") end
            LivingKnox.Log.info("npc %s: glass removal at the window %s stopped: %s", r.id, key, why)
        elseif t >= r.doneMs then
            Obstacles.glassActs[key] = nil
            Obstacles.removeGlass(r.win)
            P.count("glassRemoved")
            LivingKnox.Log.info("npc %s: broken glass of the window %s removed", r.id, key)
        end
    end
end

-- Risque du vanilla pour le PNJ id (corps z) qui enjambe une fenêtre au verre restant (voir l'en-tête). Rend vrai si
-- le PNJ est blessé.
function Obstacles.glassRisk(id, z)
    local Wo, Ctx, H = LivingKnox.Wounds, LivingKnox.WoundContext, LivingKnox.Health
    local spec = Wo ~= nil and Wo.source ~= nil and Wo.source("glass") or nil
    if spec == nil or Ctx == nil or H == nil or H.applyHit == nil then return false end
    if not Wo.oneIn(Ctx.current(), spec.chance) then return false end
    H.applyHit(id, z, Obstacles.GLASS_DAMAGE, nil, nil, nil, { source = "glass", risk = false })
    return true
end

-- Escalade par le corps z du PNJ id (état climbwindow, à ALIGN case au plus du milieu du bord) d'une fenêtre au verre
-- restant : risque couru une seule fois par escalade (glassClimbs, oublié hors escalade).
function Obstacles.climbedGlass(id, z)
    if z:getActionStateName() ~= "climbwindow" then
        Obstacles.glassClimbs[id] = nil
        return
    end
    if Obstacles.glassClimbs[id] ~= nil then return end
    for _, c in ipairs(Obstacles.windowsNear(z:getX(), z:getY(), math.floor(z:getZ()))) do
        if c.d <= Obstacles.ALIGN and LivingKnox.EdgeRules.glassLeft(LivingKnox.Edges.windowFacts(c.win, c.wk)) then
            Obstacles.glassClimbs[id] = c.e.key
            P.count("glassClimbs")
            local hurt = Obstacles.glassRisk(id, z)
            LivingKnox.Log.info("npc %s: climbs the window %s over broken glass%s", id, c.e.key,
                hurt and ", cut" or ", unhurt")
            return
        end
    end
end
