-- Living Knox : genre d'expédition « forage », la cueillette (LK05-T11, inscrit par la nourriture en LK16-T08 ; fiche
-- docs/annexes/conception/nourriture.md). De jour (Expeditions.dayHour), quand la nourriture est le premier manque
-- (Food.wanted) et qu'une zone de cueillette vanilla proche rapporte assez de nourriture à cette saison
-- (Food.pickTarget) : seulement la nourriture (Food.tripWant), lieu = case libre hors bâtiment de la zone, place de
-- chaque membre dans la zone (Food.spotIn) ; chaque membre arrivé cueille (geste Food.GESTURE) et fait un tirage des
-- tables vanilla (Food.round) toutes les Food.CFG.ROUND_MINUTES, Food.CFG.ROUNDS tirages par membre au départ ; objets
-- créés au dépôt (Food.make). Hors écran : tirages restants au retour abstrait, même flux. Moteur : LK_Expeditions.lua.
if isClient() then return end

require "LivingKnox/LK_Expeditions"
require "LivingKnox/LK_Food"

local Ex = LivingKnox.Expeditions
local Food = LivingKnox.Food

Ex.FORAGE = Food.KIND   -- identifiant public du genre (lu par la suite en jeu lk.forage)

-- Zone de cueillette (Food.pickTarget) ; une erreur est notée et laisse la place aux genres suivants.
local function pickTarget(gid, g)
    local ok, tg, why = pcall(Food.pickTarget, gid, g)
    if not ok then
        LivingKnox.Log.error("expedition: group %s foraging place failed: %s", gid, tostring(tg))
        return nil
    end
    if tg == nil then LivingKnox.Log.debug("expedition: group %s does not forage: %s", gid, tostring(why)) end
    return tg, why
end

local function start(cur, target, team)
    local zn = target.zone
    cur.k, cur.r = 0, #team * Food.CFG.ROUNDS
    cur.target.zone = { x = zn.x, y = zn.y, w = zn.w, h = zn.h }
end

-- Place du rank-ième membre : case libre de la zone visée (zone perdue : carré de 5 cases autour du point visé).
local function spot(t, rank)
    local tg = t.target
    local zn = type(tg.zone) == "table" and tg.zone or { x = tg.x - 2, y = tg.y - 2, w = 5, h = 5 }
    return Food.spotIn(zn, tg.x, tg.y, tg.z, Food.CFG.SPOT_RADIUS, rank)
end

Ex.registerKind({ id = Food.KIND, order = 20, gesture = Food.GESTURE, verb = "forages",
    hours = Ex.dayHour,
    wanted = Food.wanted,
    pickTarget = pickTarget,
    wants = Food.tripWant,
    start = start,
    valid = Ex.drawnValid,
    spot = spot,
    round = Ex.drawnRound,
    offscreen = Ex.drawnOffscreen,
    conditions = function() return Food.conditions() end,
    minutes = function() return Food.CFG.ROUND_MINUTES end,
    draw = function(gid, t, k, c) return Food.round(gid, t.n, k, t.target.room, c, t.cap - #t.carry) end,
    detail = function(c) return ", " .. Food.conditionText(c) end,
    make = function(itemType) return Food.make(itemType) end,
})
