-- Radio Survivor: cancellation checks shared by the arrival modes of the traders (E20-T11, ADR D07/D08; rare and
-- announced since E23-T08, ADR D05 of adr-troc-simple-et-cas-limites.md). Each mode keeps its own causes (name, text,
-- fallback, translation IGUI_RS_TradeRun_Cancel_<name>) and builds their check from these: the world they read is the
-- one of RS_TradeRun (contract in RS_TradeArrivals: run, hours, roll(salt, n), stormy()).
-- A patrol (soldiers on the river, a checkpoint, a sweep): 1 chance in PATROL_ONE_IN per run, reproducible roll.
-- A helicopter: 1 chance in HELICOPTER_ONE_IN per run, reproducible roll (no longer tied to a vanilla helicopter).
-- A storm: thunderstorm of the ClimateManager (the real weather of the game).
-- This file registers no mode (RS_TradeArrivals.register is never called here). ASCII only (Kahlua lexer).
if isClient() then return end

local Causes = {}

Causes.PATROL_ONE_IN = 75
Causes.HELICOPTER_ONE_IN = 100
-- Salt of each roll: the two rolls of a run are independent and the same for the same run.
Causes.PATROL_SALT = 7
Causes.HELICOPTER_SALT = 13

-- Check true when the reproducible roll of the run is 0 among `oneIn` (salt: one number per kind of cause).
function Causes.chance(oneIn, salt)
    local function check(world)
        return world.roll(salt, oneIn) == 0
    end
    return check
end

Causes.patrol = Causes.chance(Causes.PATROL_ONE_IN, Causes.PATROL_SALT)
Causes.helicopter = Causes.chance(Causes.HELICOPTER_ONE_IN, Causes.HELICOPTER_SALT)

-- Check true during a thunderstorm.
function Causes.storm(world)
    return world.stormy()
end

return Causes
