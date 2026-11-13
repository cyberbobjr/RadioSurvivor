-- Living Knox : tâche « glass » (LK05-T10) : verre brisé (IsoBrokenGlass) sur une case du bâtiment du foyer, retiré
-- comme le ramassage vanilla : triggerEvent OnObjectAboutToBeRemoved puis transmitRemoveItemFromSquare
-- (M/shared/Moveables/ISMoveableSpriteProps.lua:1481-1491 ; J/iso/IsoGridSquare.java:5076-5098). « Déchets » = verre
-- brisé : seul débris vanilla avec un objet de case. Moteur : LK_Upkeep.lua.
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Upkeep = LivingKnox.Upkeep

Upkeep.stats.glass = Upkeep.stats.glass or 0

local function survey(gid, g, area)
    local out = {}
    for _, e in ipairs(area.squares) do
        if e.inside and e.sq:getBrokenGlass() ~= nil then out[#out + 1] = { x = e.x, y = e.y, bid = area.bid } end
    end
    return out
end

local function apply(job, gid, who, sq)
    local glass = sq:getBrokenGlass()
    if glass == nil then return nil, "no broken glass left" end
    triggerEvent("OnObjectAboutToBeRemoved", glass)
    sq:transmitRemoveItemFromSquare(glass)
    Upkeep.stats.glass = Upkeep.stats.glass + 1
    return string.format("broken glass removed at %d,%d", job.x, job.y)
end

Upkeep.registerJob({ kind = "glass", order = 60, gesture = "rummage", minutes = 2, standOnSelf = true,
    survey = survey, apply = apply })
