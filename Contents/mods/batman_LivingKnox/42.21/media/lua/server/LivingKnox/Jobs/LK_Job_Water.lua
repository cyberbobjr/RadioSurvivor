-- Living Knox : tâche « water » (LK05-T11, fiche nourriture.md) : plante cultivée de la zone vivante dont le niveau
-- d'eau est sous le besoin de son stade, hors pluie (I4.5), avec de l'eau dans un récipient du foyer. Effet comme la
-- commande vanilla « water » (plant:water(nil, doses), +10 par dose, M/server/Farming/farmingCommands.lua:100-107) et
-- ISWaterPlantAction:useItemOneUnit (dose = farmingFluidContainerMillilitresPerUse, M/shared/defines.lua:52). Préférée
-- par le jardinier (prefer = "garden"). Plante : jamais à côté, voir LK_Garden.placeNear. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"
require "LivingKnox/LK_Garden"

local Upkeep = LivingKnox.Upkeep
local Garden = LivingKnox.Garden

Upkeep.stats.watered = Upkeep.stats.watered or 0

local function survey(gid, g, area)
    if Garden.farming() == nil or Garden.raining() then return nil end
    local plants = {}
    for _, e in ipairs(area.squares) do
        if e.sq:hasFarmingPlant() then
            local plant = Garden.plantAt(e.x, e.y, area.z)
            if not Garden.ripe(plant) and Garden.waterUses(plant) > 0 then plants[#plants + 1] = { x = e.x, y = e.y } end
        end
    end
    if #plants == 0 or Garden.findWater(gid, Garden.waterPerUse()) == nil then return nil end
    return plants
end

local function apply(job, gid, who, sq)
    if Garden.raining() then return nil, "raining" end
    local plant = Garden.plantAt(job.x, job.y, job.z)
    local uses = Garden.waterUses(plant)
    if uses <= 0 then return nil, "plant gone or not thirsty" end
    local per = Garden.waterPerUse()
    local src, fluids = Garden.findWater(gid, per)
    if src == nil then return nil, "no water" end
    uses = math.min(uses, math.floor(src.amount / per + 1e-6))
    if uses <= 0 then return nil, "not enough water" end
    local S = LivingKnox.Stock
    local got, why = S.drawFluid(gid, fluids, uses * per, per, who, "plant " .. job.key)
    if got == nil then return nil, "no water: " .. tostring(why) end
    uses = math.floor(got.amount / per + 1e-6)
    local before = plant.waterLvl
    if uses > 0 then plant:water(nil, uses) end
    if got.left < 1e-6 then S.untrack(gid, got.i) end   -- récipient vidé : plus de l'eau
    Upkeep.stats.watered = Upkeep.stats.watered + 1
    return string.format("plant at %d,%d watered %d -> %d (%d dose(s), %.2f l of %s from %s)", job.x, job.y,
        before, plant.waterLvl, uses, got.amount, got.fluid, got.t)
end

Upkeep.registerJob({ kind = "water", order = 40, prefer = "garden", gesture = "kneel", minutes = 2,
    place = Garden.placeNear, survey = survey, apply = apply })
