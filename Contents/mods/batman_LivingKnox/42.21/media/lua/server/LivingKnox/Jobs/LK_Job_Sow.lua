-- Living Knox : tâche « sow » (LK15-T05, ADR registre des routines D07) : semer dans un sillon vide (état « plow ») de
-- la zone du foyer une graine du stock dont la variété est de saison (sowMonth de sa définition vanilla : rien hors
-- saison ; LK_Garden.sowable). Effet comme la commande vanilla « seed » (plant:seed(type, 0), refusée hors état
-- « plow » : M/server/Farming/farmingCommands.lua:89-97 ; M/server/Farming/SPlantGlobalObject.lua:715-732), UNE
-- graine par plante (ISSeedActionNew) retirée du conteneur et de la référence du stock dans la même écriture
-- (LK_Garden.takeSeed). Préférée par le jardinier (prefer = "garden"). Sillon : jamais à côté, voir
-- LK_Garden.placeNear. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"
require "LivingKnox/LK_Garden"

local Upkeep = LivingKnox.Upkeep
local Garden = LivingKnox.Garden

Upkeep.stats.sown = Upkeep.stats.sown or 0

local function survey(gid, g, area)
    if Garden.farming() == nil then return nil end
    local _, empty = Garden.plots(area)
    if #empty == 0 or Garden.findSeed(gid, Garden.month()) == nil then return nil end
    return empty
end

local function apply(job, gid, who, sq)
    local plant = Garden.plantAt(job.x, job.y, job.z)
    if type(plant) ~= "table" or plant.state ~= "plow" then return nil, "furrow gone or already sown" end
    local taken, typeOfSeed = Garden.takeSeed(gid, Garden.month(), who, "sowing " .. job.key)
    if taken == nil then return nil, "no seed in season: " .. tostring(typeOfSeed) end
    plant:seed(typeOfSeed, 0)
    Upkeep.stats.sown = Upkeep.stats.sown + 1
    return string.format("%s sown at %d,%d (%s from %s)", typeOfSeed, job.x, job.y, taken.t, taken.k)
end

Upkeep.registerJob({ kind = "sow", order = 44, prefer = "garden", gesture = "kneel", minutes = Garden.CFG.SOW_MINUTES,
    groupLog = true, place = Garden.placeNear, survey = survey, apply = apply })
