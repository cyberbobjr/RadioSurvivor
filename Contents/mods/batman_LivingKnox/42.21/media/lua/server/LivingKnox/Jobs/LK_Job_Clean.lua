-- Living Knox : tâche « clean » (LK05-T10) : case du bâtiment du foyer tachée de sang (IsoGridSquare.haveBlood,
-- J/iso/IsoGridSquare.java:4657-4675 ; faux si l'option bloodDecals vaut 0), avec un produit (Fluid.Bleach ou
-- Fluid.CleaningLiquid, au moins ZomboidGlobals.CleanBloodBleachAmount) et un outil (tag CleanStains, non cassé) au
-- foyer. Effet comme ISCleanBlood:complete : produit diminué de la dose, removeBlood(false, false) (paquet RemoveBlood
-- aux clients proches sur un serveur, :4818-4840), removeGrime. L'outil reste. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Upkeep = LivingKnox.Upkeep
local CLEANERS = { "Bleach", "CleaningLiquid" }
local CFG = Upkeep.CFG
CFG.CLEAN_AMOUNT = CFG.CLEAN_AMOUNT or 0.24999   -- produit par case nettoyée si ZomboidGlobals.CleanBloodBleachAmount manque

Upkeep.stats.cleaned = Upkeep.stats.cleaned or 0

local function cleanAmount()
    local g = ZomboidGlobals
    if type(g) == "table" and type(g.CleanBloodBleachAmount) == "number" then return g.CleanBloodBleachAmount end
    return CFG.CLEAN_AMOUNT
end

local function isCleanTool(it)
    if ItemTag == nil or ItemTag.CLEAN_STAINS == nil then return false end
    return it:hasTag(ItemTag.CLEAN_STAINS) and not it:isBroken()
end

local function survey(gid, g, area)
    local blood = {}
    for _, e in ipairs(area.squares) do
        if e.inside and e.sq:haveBlood() then blood[#blood + 1] = e end
    end
    local S = LivingKnox.Stock
    if #blood == 0 or S.findFluid(gid, CLEANERS, cleanAmount()) == nil or S.findItem(gid, isCleanTool) == nil then
        return nil
    end
    local out = {}
    for _, e in ipairs(blood) do out[#out + 1] = { x = e.x, y = e.y, bid = area.bid } end
    return out
end

local function apply(job, gid, who, sq)
    if not sq:haveBlood() then return nil, "no blood left" end
    if LivingKnox.Stock.findItem(gid, isCleanTool) == nil then return nil, "no cleaning tool" end
    local amount = cleanAmount()
    local got, why = LivingKnox.Stock.drawFluid(gid, CLEANERS, amount, amount, who, "blood " .. job.key)
    if got == nil then return nil, "no cleaning product: " .. tostring(why) end
    sq:removeBlood(false, false)
    sq:removeGrime()
    Upkeep.stats.cleaned = Upkeep.stats.cleaned + 1
    return string.format("blood cleaned at %d,%d (%.3f l of %s)", job.x, job.y, got.amount, got.fluid)
end

Upkeep.registerJob({ kind = "clean", order = 50, gesture = "kneel", minutes = 3, standOnSelf = true,
    survey = survey, apply = apply })
