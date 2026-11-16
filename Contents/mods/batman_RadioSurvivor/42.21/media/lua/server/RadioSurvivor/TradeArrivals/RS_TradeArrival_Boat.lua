-- Radio Survivor: arrival mode `boat` of a trader (E20-T07, ADR D07; behaviour of the Ohio smuggler since E13-T03).
-- The boat crosses the river at night and comes alongside the landing when a member of the booking team shows a lit
-- lamp or a red flare there during the meeting window. Its outboard is heard cut when it comes alongside and started
-- again when it leaves.
-- Sounds: vanilla 42.22 media/scripts/generated/sounds/objects/sounds_object_generator.txt:13-31 (GeneratorStarting,
-- GeneratorStopping: one-shot small engine, distanceMax 100); no boat sound exists in the vanilla sound scripts.
-- Causes (checked from RS_TradeRun.WARN_HOURS before the window, checks of RS_TradeCauses, ADR D05 of E23): a patrol
-- boat (1 chance in 75 per run), a helicopter (1 chance in 100 per run), a thunderstorm (ClimateManager).
-- ASCII only (Kahlua lexer).
if isClient() then return end
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local Causes = require "RadioSurvivor/RS_TradeCauses"

local Boat = {}

Boat.mode = {
    signals = { lamp = true, flare = true },
    texts = {
        signal = "a red flare or a lit lamp held up at the landing, then you come alongside",
        arrived = "your boat is at the landing now",
        drop = "the payment goes in a bag left on the ground at the landing, never in a vehicle",
    },
    sounds = { approach = "GeneratorStopping", leave = "GeneratorStarting" },
    causes = {
        { name = "patrol", check = Causes.patrol, text = "a patrol boat on the river",
            fallback = "No run tonight. A patrol boat is working the river. Stay off the bank. Over." },
        { name = "helicopter", check = Causes.helicopter, text = "a helicopter over the river",
            fallback = "No run tonight. A helicopter is sweeping the river. Keep your heads down. Over." },
        { name = "storm", check = Causes.storm, text = "a storm on the river",
            fallback = "No run tonight. There is a storm on the river, no boat crosses in that. Over." },
    },
}

Arrivals.register("boat", Boat.mode)

return Boat
