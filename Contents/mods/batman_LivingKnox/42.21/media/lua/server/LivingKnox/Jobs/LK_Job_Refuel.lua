-- Living Knox : tâche « refuel » (LK05-T10, LK05-T19) : remplir le générateur DU GROUPE de la zone du foyer dont le
-- carburant est sous REFUEL_BELOW litres (sur getMaxFuel = 10, J/iso/objects/IsoGenerator.java:436-456), avec un
-- récipient d'essence (Fluid.Petrol) des conteneurs du foyer. Effet comme ISAddFuel:complete (M/shared/TimedActions/
-- ISAddFuel.lua:52-63) : prise = min(litres du récipient, place libre), récipient vidé d'autant, setFuel (synchronisé
-- par le Java sur un serveur, :448-456). Générateur : marque LK_Homes.GEN_TAG seulement. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Upkeep = LivingKnox.Upkeep
-- Réglage rangé dans ceux du moteur (Upkeep.CFG), valeur de départ si absente.
local CFG = Upkeep.CFG
CFG.REFUEL_BELOW = CFG.REFUEL_BELOW or 5       -- litres de carburant (sur 10) sous lesquels le générateur est rempli
local PETROL = { "Petrol" }

Upkeep.stats.refuels = Upkeep.stats.refuels or 0

local function survey(gid, g, area)
    local gens = Upkeep.groupGenerators(area, gid)
    if #gens == 0 or LivingKnox.Stock.findFluid(gid, PETROL, 0) == nil then return nil end
    local out = {}
    for _, e in ipairs(gens) do
        if e.gen:getFuel() < CFG.REFUEL_BELOW then out[#out + 1] = { x = e.x, y = e.y } end
    end
    return out
end

local function apply(job, gid, who, sq)
    local gen = Upkeep.groupGeneratorOn(sq, gid)
    if gen == nil then return nil, "generator of the group gone" end
    local before = gen:getFuel()
    local room = gen:getMaxFuel() - before
    if room <= 0 then return nil, "generator full" end
    local got, why = LivingKnox.Stock.drawFluid(gid, PETROL, room, 0, who, "generator " .. job.key)
    if got == nil then return nil, "no petrol: " .. tostring(why) end
    gen:setFuel(before + got.amount)
    Upkeep.stats.refuels = Upkeep.stats.refuels + 1
    return string.format("generator at %d,%d refuelled %.2f -> %.2f l (%s)", job.x, job.y, before, gen:getFuel(), got.t)
end

Upkeep.registerJob({ kind = "refuel", order = 10, gesture = "kneel", minutes = 3, groupLog = true,
    survey = survey, apply = apply })
