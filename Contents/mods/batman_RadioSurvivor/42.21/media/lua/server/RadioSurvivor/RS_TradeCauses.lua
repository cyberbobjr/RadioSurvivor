-- Radio Survivor: cancellation checks shared by the arrival modes of the traders (E20-T11, ADR D07/D08; extracted
-- from the boat mode of E20-T07). Each mode keeps its own causes (name, text, fallback, translation
-- IGUI_RS_TradeRun_Cancel_<name>) and builds their check from these functions: the world they read is the one of
-- RS_TradeRun (contract in RS_TradeArrivals: run, cordonLevel, patrolRoll(), helicopterSince(hours), stormy()).
-- A patrol: reproducible roll of the run below the chance of the cordon (per cent, by RS_Trade.CORDONS level).
-- A helicopter: a vanilla helicopter heard since `hours` hours before the meeting window.
-- A storm: thunderstorm of the ClimateManager.
-- This file registers no mode (RS_TradeArrivals.register is never called here). ASCII only (Kahlua lexer).
if isClient() then return end

local Causes = {}

-- Check true when the patrol roll of the run is below chances[cordon level].
function Causes.patrol(chances)
    local function check(world)
        return world.patrolRoll() < (chances[world.cordonLevel] or 0)
    end
    return check
end

-- Check true when a helicopter was heard since `hours` hours before the window of the run.
function Causes.helicopter(hours)
    local function check(world)
        return world.helicopterSince(world.run.start - hours)
    end
    return check
end

-- Check true during a thunderstorm.
function Causes.storm(world)
    return world.stormy()
end

return Causes
