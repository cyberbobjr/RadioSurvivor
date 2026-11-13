-- Living Knox : tâche « dig » (LK15-T04, ADR registre des routines D07, Q01) : creuser un sillon sur une case de terre
-- libre, dehors, au rez-de-chaussée, dans la zone du foyer (conditions du menu vanilla : LK_Garden.canDig), au plus
-- Garden.CFG.MAX_PLOTS sillons et plantes vivantes par foyer, et seulement quand aucun sillon vide n'attend déjà sa
-- graine (un sillon à la fois). Outil de labour du stock (Garden.DIG_PLOW) s'il y en a un, gardé au stock ; sinon mains
-- nues, durée doublée comme ISPlowAction:getDuration (M/shared/Farming/TimedActions/ISPlowAction.lua:132-144). Effet :
-- LK_Garden.dig (comme ISPlowAction:complete sans joueur, puis SFarmingSystem:plow). Préférée par le jardinier
-- (prefer = "garden"). Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"
require "LivingKnox/LK_Garden"

local Upkeep = LivingKnox.Upkeep
local Garden = LivingKnox.Garden

Upkeep.stats.dug = Upkeep.stats.dug or 0

local function survey(gid, g, area)
    if Garden.farming() == nil then return nil end
    local n, empty = Garden.plots(area)
    if n >= Garden.CFG.MAX_PLOTS or #empty > 0 then return nil end
    local spot = Garden.digSpot(area)
    if spot == nil then return nil end
    return { spot }
end

local function duration(job, gid)
    local base = Garden.CFG.DIG_MINUTES
    if Garden.digTool(gid) ~= nil then return base end
    return base * 2
end

local function apply(job, gid, who, sq)
    if Garden.farming() == nil then return nil, "no farming system" end
    local g = LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no home" end
    local area, why = Upkeep.area(gid, g)
    if area == nil then return nil, why end
    if Garden.plots(area) >= Garden.CFG.MAX_PLOTS then return nil, "enough plots" end
    if not sq:isOutside() then return nil, "not outside" end
    local ok, reason = Garden.canDig(sq)
    if not ok then return nil, reason end
    local tool = Garden.digTool(gid)
    Garden.dig(sq)
    Upkeep.stats.dug = Upkeep.stats.dug + 1
    return string.format("furrow dug at %d,%d with %s", job.x, job.y, tool ~= nil and tool.t or "bare hands")
end

Upkeep.registerJob({ kind = "dig", order = 46, prefer = "garden", gesture = "kneel", minutes = Garden.CFG.DIG_MINUTES,
    duration = duration, survey = survey, apply = apply })
