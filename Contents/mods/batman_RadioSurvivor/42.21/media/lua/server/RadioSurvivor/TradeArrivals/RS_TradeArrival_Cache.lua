-- Radio Survivor: arrival mode `cache` of a trader (E20-T11, ADR D07/D08): nobody shows up. The booking team leaves the
-- payment in a container at the landing (a dumpster, a mailbox: holds = containers of RS_TradeHolds); the trader's
-- runner comes by at the start of the meeting window (signal hour: no lamp, no flare), unseen, and swaps the payment for
-- the goods in that same container once nobody has been in view for the delay of the sheet (RS_OutOfSight, as for the
-- other modes). No sound: nobody is heard coming or going.
-- Causes (checked from RS_TradeRun.WARN_HOURS before the window, checks of RS_TradeCauses): soldiers sweeping the town
-- (reproducible roll of the run below the chance of the cordon), a helicopter heard since HELI_HOURS before the
-- window. ASCII only (Kahlua lexer).
if isClient() then return end
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local Causes = require "RadioSurvivor/RS_TradeCauses"

local Cache = {}

Cache.SWEEP_CHANCE = { 5, 10, 20 }  -- per cent, by cordon (RS_Trade.CORDONS: calm, patrols, tight)
Cache.HELI_HOURS = 2                -- a helicopter heard two hours before the window keeps the runner home

Cache.mode = {
    signals = { hour = true },
    texts = {
        signal = "leave the payment inside the container at the cache before the meeting time, then stay away and out "
            .. "of sight; nobody comes to meet you",
        arrived = "your runner is near the cache now, waiting until nobody is watching",
    },
    sounds = {},
    holds = "containers",
    causes = {
        { name = "sweep", check = Causes.patrol(Cache.SWEEP_CHANCE), text = "soldiers sweeping the streets",
            fallback = "Nothing tonight. Soldiers are sweeping the streets. Leave the cache alone. Over." },
        { name = "overflight", check = Causes.helicopter(Cache.HELI_HOURS), text = "a helicopter over the town",
            fallback = "Nothing tonight. A helicopter is circling the town. My runner stays home. Over." },
    },
    lines = {
        Pier = "Dead drop",
        Cancel_late = "My runner went by the cache and found nothing to take. Over.",
        Done = "Your goods are in the cache. Take them when nobody is looking. Over.",
        Cheated = "You tried to short me. Your payment stays in the cache, no deal, and I will remember it. Over.",
        Cancel_nodrop = "My runner found the cache empty. No deal this time. Over.",
    },
}

Arrivals.register("cache", Cache.mode)

return Cache
