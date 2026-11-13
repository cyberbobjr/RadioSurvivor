-- Living Knox : genre d'expédition de repli « building » (LK05-T05, inscrit en LK16-T08) : de jour
-- (Expeditions.dayHour), bâtiment de la métagrille choisi selon les manques (Expeditions.pickTarget), place libre du
-- bâtiment près du point visé (une par rang), fouille des conteneurs (Expeditions.searchRound, geste rummage), butin
-- abstrait hors écran (Expeditions.searchOffscreen) ; le bâtiment fouillé entre dans les derniers fouillés (seen).
-- Genre de repli : essayé après les autres genres, lu pour une expédition sans champ kind (registre d'avant LK16-T08).
-- Moteur : LK_Expeditions.lua.
if isClient() then return end

require "LivingKnox/LK_Expeditions"

local Ex = LivingKnox.Expeditions

local function spot(t, rank)
    local tg = t.target
    return Ex.freeNear(tg.x, tg.y, tg.z, tg.b, Ex.CFG.SPOT_RADIUS, rank)
end

Ex.registerKind({ id = "building", order = 100, fallback = true, gesture = "rummage", seen = true,
    hours = Ex.dayHour, pickTarget = Ex.pickTarget, spot = spot, round = Ex.searchRound,
    offscreen = Ex.searchOffscreen })
