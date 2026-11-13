-- Living Knox : événement de groupe « recruit » de la simulation hors écran (LK09-T05 ; un fichier par événement,
-- LK16-T09). Fiche : docs/annexes/conception/simulation.md. Ordre du tirage 20.
-- Un survivant rejoint le groupe (profil tiré du type, Simulation.drawRecruit) quand la nourriture et le moral le
-- permettent et qu'il reste de la place (Simulation.recruitRoom). Journal recruit « wanderer: <membre> <rôle> » puis
-- joined ; moral.
if isClient() then return end

require "LivingKnox/LK_Simulation"

local Simulation = LivingKnox.Simulation
local kit = Simulation.eventKit

Simulation.registerEvent({
    id = "recruit", order = 20, config = "RECRUIT",
    bounds = { CHANCE = { 0, 1 }, FOOD_MIN = { 0, 100, true }, MORALE_MIN = { 0, 100, true }, MORALE = { -100, 100 } },
    chance = function(e, ctx)
        local g = ctx.g
        if g.needs.food >= e.FOOD_MIN and g.morale >= e.MORALE_MIN and Simulation.recruitRoom(g) then return e.CHANCE end
        return nil
    end,
    apply = function(e, ctx)
        local g, gid, day = ctx.g, ctx.gid, ctx.day
        local spec = Simulation.drawRecruit(g, ctx.rnd)
        if not spec then return nil end
        local mid = LivingKnox.Groups.applyMember(g, spec, day)
        if not mid then return nil end
        kit.logRecruit(g, "wanderer", mid, spec.role, day)
        g.morale = kit.clamp(g.morale + e.MORALE)
        LivingKnox.Log.debug("simulation: wanderer %s joined group %s", mid, gid)
        return { member = mid, role = spec.role }
    end,
})
