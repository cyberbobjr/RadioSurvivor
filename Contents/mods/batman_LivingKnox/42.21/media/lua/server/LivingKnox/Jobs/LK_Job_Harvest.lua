-- Living Knox : tâche « harvest » (LK05-T11, décision du 2026-10-15) : plante cultivée mûre de la zone (vivante et
-- hasVegetable, SPlantGlobalObject:canHarvest), avec un conteneur de dépôt au foyer. Effet : Garden.harvestPlant
-- (comme SFarmingSystem:harvest, M/server/Farming/SFarmingSystem.lua:333-382). Préférée par le jardinier
-- (prefer = "garden"). Plante : jamais à côté, voir LK_Garden.placeNear. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"
require "LivingKnox/LK_Garden"

local Upkeep = LivingKnox.Upkeep
local Garden = LivingKnox.Garden

Upkeep.stats.harvested = Upkeep.stats.harvested or 0
Upkeep.stats.produce = Upkeep.stats.produce or 0   -- objets récoltés (légumes, extras, graines)

local function survey(gid, g, area)
    if Garden.farming() == nil or type(getVegetablesNumber) ~= "function" then return nil end
    local ripe = {}
    for _, e in ipairs(area.squares) do
        if e.sq:hasFarmingPlant() and Garden.ripe(Garden.plantAt(e.x, e.y, area.z)) then
            ripe[#ripe + 1] = { x = e.x, y = e.y }
        end
    end
    if #ripe == 0 or Garden.depotOf(gid, area.home) == nil then return nil end
    return ripe
end

local function apply(job, gid, who, sq)
    local plant = Garden.plantAt(job.x, job.y, job.z)
    if not Garden.ripe(plant) then return nil, "plant gone or not ripe" end
    local g = LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no home" end
    local depot, why = Garden.depotOf(gid, g.home)
    if depot == nil then return nil, "no container: " .. tostring(why) end
    local n, count, types = Garden.harvestPlant(plant, gid, depot)
    Upkeep.stats.harvested = Upkeep.stats.harvested + 1
    Upkeep.stats.produce = Upkeep.stats.produce + count
    return string.format("plant at %d,%d harvested: %d vegetable(s), %d item(s) into %s%s", job.x, job.y, n, count,
        depot.key, #types > 0 and (" (" .. table.concat(types, " ") .. ")") or "")
end

Upkeep.registerJob({ kind = "harvest", order = 30, prefer = "garden", gesture = "kneel", minutes = 3, groupLog = true,
    place = Garden.placeNear, survey = survey, apply = apply })
