-- Living Knox : tâche « repair » (LK05-T10) : générateur DU GROUPE arrêté (le vanilla refuse un générateur en marche :
-- M/shared/TimedActions/ISFixGenerator.lua:6-11) d'état < REPAIR_BELOW, avec une pièce REPAIR_PART (Base.ElectronicsScrap)
-- des conteneurs du foyer : pièce retirée, état + REPAIR_STEP (ISFixGenerator:complete, :62-77 : +4 + Électricité/2,
-- compétence 0 ici), setCondition synchronisé (:503-511). Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Upkeep = LivingKnox.Upkeep
-- Réglages rangés dans ceux du moteur (Upkeep.CFG), valeurs de départ si absentes.
local CFG = Upkeep.CFG
CFG.REPAIR_BELOW = CFG.REPAIR_BELOW or 60      -- état (0..100) sous lequel un générateur arrêté est réparé
CFG.REPAIR_STEP = CFG.REPAIR_STEP or 4         -- état gagné par pièce (ISFixGenerator, compétence 0)
CFG.REPAIR_PART = CFG.REPAIR_PART or "Base.ElectronicsScrap"

Upkeep.stats.repairs = Upkeep.stats.repairs or 0

local function isPart(it) return it:getFullType() == CFG.REPAIR_PART end

local function survey(gid, g, area)
    local gens = Upkeep.groupGenerators(area, gid)
    if #gens == 0 or LivingKnox.Stock.findItem(gid, isPart) == nil then return nil end
    local out = {}
    for _, e in ipairs(gens) do
        if not e.gen:isActivated() and e.gen:getCondition() < CFG.REPAIR_BELOW then
            out[#out + 1] = { x = e.x, y = e.y }
        end
    end
    return out
end

local function apply(job, gid, who, sq)
    local gen = Upkeep.groupGeneratorOn(sq, gid)
    if gen == nil then return nil, "generator of the group gone" end
    if gen:isActivated() then return nil, "generator running" end
    local cond = gen:getCondition()
    if cond >= 100 then return nil, "generator in good condition" end
    local got, why = LivingKnox.Stock.takeItem(gid, isPart, who, "generator " .. job.key)
    if got == nil then return nil, "no part: " .. tostring(why) end
    gen:setCondition(cond + CFG.REPAIR_STEP)
    Upkeep.stats.repairs = Upkeep.stats.repairs + 1
    return string.format("generator at %d,%d repaired %d -> %d (%s)", job.x, job.y, cond, gen:getCondition(), got.t)
end

Upkeep.registerJob({ kind = "repair", order = 20, gesture = "rummage", minutes = 5, groupLog = true,
    survey = survey, apply = apply })
