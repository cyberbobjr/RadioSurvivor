-- Radio Survivor: arrival mode `road` of a trader (E20-T11, ADR D07/D08): a driver from outside the zone pulls up at a
-- roadside landing at night when a member of the booking team shows a lit lamp or a red flare there during the meeting
-- window, gets out, and drives off once the exchange is done (bag left on the floor, as for the boat).
-- Sounds: vanilla 42.22 media/scripts/generated/sounds/vehicles/sounds_vehicle_van.txt:60-67 (VehicleDoorCloseVan,
-- the driver gets out) and :123-130 (VehicleTrunkCloseVan, the load is stowed before he leaves): one-shot events. The
-- engine (VehicleEnginePickUpVan, same file:3-12) and the horn (VehicleHorn, sounds_vehicle_default.txt:23-30) are
-- held sounds of a real vehicle (BaseVehicle.onHornStart/onHornStop, 42.22 BaseVehicle.java:8148-8173), not played.
-- Causes (checked from RS_TradeRun.WARN_HOURS before the window, checks of RS_TradeCauses): an army checkpoint on the
-- roads (reproducible roll of the run below the chance of the cordon), a helicopter heard since HELI_HOURS before the
-- window, a thunderstorm. ASCII only (Kahlua lexer).
if isClient() then return end
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local Causes = require "RadioSurvivor/RS_TradeCauses"

local Road = {}

Road.CHECKPOINT_CHANCE = { 10, 20, 35 }  -- per cent, by cordon (RS_Trade.CORDONS: calm, patrols, tight)
Road.HELI_HOURS = 2                      -- a helicopter heard two hours before the window keeps the truck away

Road.mode = {
    signals = { lamp = true, flare = true },
    texts = {
        signal = "a red flare or a lit lamp held up at the roadside meeting point, then you pull over",
        arrived = "your truck is parked at the meeting point now",
    },
    sounds = { approach = "VehicleDoorCloseVan", leave = "VehicleTrunkCloseVan" },
    causes = {
        { name = "checkpoint", check = Causes.patrol(Road.CHECKPOINT_CHANCE), text = "an army checkpoint on the road",
            fallback = "No run tonight. The army put a checkpoint on the road. Stay off it. Over." },
        { name = "air_patrol", check = Causes.helicopter(Road.HELI_HOURS), text = "a helicopter over the roads",
            fallback = "No run tonight. A helicopter is flying over the roads. I am not driving under it. Over." },
        { name = "washout", check = Causes.storm, text = "a storm flooding the roads",
            fallback = "No run tonight. The storm has the roads under water. I am staying put. Over." },
    },
    lines = {
        Pier = "Roadside meeting point",
        Cancel_late = "I pulled over and nobody showed the signal. I am gone. Over.",
        Done = "Your goods are in the bag by the road. Pleasure doing business. Over.",
        Cancel_nodrop = "Nobody left me a bag by the road. I am gone. Over.",
    },
}

Arrivals.register("road", Road.mode)

return Road
