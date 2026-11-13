-- Living Knox : genre d'expédition « fish », la pêche (LK05-T11, décision du 2026-10-15 ; inscrit par la nourriture en
-- LK16-T08 ; fiche docs/annexes/conception/nourriture.md). À l'aube et au crépuscule seulement (Food.fishHour :
-- fenêtres Food.FISH_HOURS, hors des heures de jour), quand la nourriture est le premier manque (Food.wanted) et
-- qu'une rive libre est à portée (Food.fishTarget) : seulement la nourriture (Food.tripWant), même équipe, mêmes phases
-- et même dépôt qu'une cueillette ; chaque membre arrivé sur sa rive (Food.shoreSpot) se tourne vers l'eau,
-- s'agenouille (Food.GESTURE) et fait un tirage des tables du filet vanilla (Food.fishRound) toutes les
-- Food.CFG.FISH_MINUTES, Food.CFG.FISH_ROUNDS tirages par membre au plus ; prises créées au dépôt (Food.make). Hors
-- écran : tirages restants au retour abstrait, même flux. Moteur : LK_Expeditions.lua.
if isClient() then return end

require "LivingKnox/LK_Expeditions"
require "LivingKnox/LK_Food"

local Ex = LivingKnox.Expeditions
local Food = LivingKnox.Food

Ex.FISH = Food.FISH_KIND   -- identifiant public du genre (lu par la suite en jeu lk.forage)

local function log() return LivingKnox.Log end

-- Rive visée (Food.fishTarget) ; sans rive, la raison est rendue (« no fishing: ... ») ; une erreur est notée.
local function pickTarget(gid, g)
    local ok, tg, why = pcall(Food.fishTarget, gid, g)
    if not ok then
        log().error("expedition: group %s fishing place failed: %s", gid, tostring(tg))
        return nil
    end
    if tg ~= nil then return tg end
    log().debug("expedition: group %s does not fish: %s", gid, tostring(why))
    return nil, "no fishing: " .. tostring(why)
end

local function start(cur, target, team)
    cur.k, cur.r = 0, #team * Food.CFG.FISH_ROUNDS
end

-- Place du rank-ième membre : rive libre la plus proche de la rive visée ; angle vers l'eau voisine.
local function spot(t, rank)
    local tg = t.target
    local sq, wx, wy = Food.shoreSpot(tg.x, tg.y, tg.z, Food.CFG.SHORE_RADIUS, rank)
    if sq == nil then return nil end
    local D = LivingKnox.Decisions
    local a = D ~= nil and D.angleTo ~= nil and D.angleTo(wx - sq:getX(), wy - sq:getY()) or nil
    return sq, a
end

Ex.registerKind({ id = Food.FISH_KIND, order = 10, gesture = Food.GESTURE, verb = "fishes",
    hours = Food.fishHour,
    wanted = Food.wanted,
    pickTarget = pickTarget,
    wants = Food.tripWant,
    start = start,
    valid = Ex.drawnValid,
    spot = spot,
    round = Ex.drawnRound,
    offscreen = Ex.drawnOffscreen,
    conditions = function() return Food.conditions() end,
    minutes = function() return Food.CFG.FISH_MINUTES end,
    draw = function(gid, t, k) return Food.fishRound(gid, t.n, k, t.cap - #t.carry) end,
    detail = function() return "" end,
    make = function(itemType) return Food.make(itemType) end,
})
