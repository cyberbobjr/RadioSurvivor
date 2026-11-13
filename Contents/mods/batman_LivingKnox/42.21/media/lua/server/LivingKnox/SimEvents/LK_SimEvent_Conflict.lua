-- Living Knox : événement de groupe « conflict » de la simulation hors écran (LK09-T05 ; un fichier par événement,
-- LK16-T09). Fiche : docs/annexes/conception/simulation.md. Ordre du tirage 30.
-- Deux membres au foyer s'opposent (le premier hors chef ; le second est le chef si contesté), blessure légère possible
-- de l'un d'eux, moral. Aucun changement de chef (journal seulement).
if isClient() then return end

require "LivingKnox/LK_Simulation"

local Simulation = LivingKnox.Simulation
local kit = Simulation.eventKit

Simulation.registerEvent({
    id = "conflict", order = 30, config = "CONFLICT",
    bounds = { CHANCE = { 0, 1 }, CHANCE_LOW_NEED = { 0, 1 }, MORALE_MAX = { 0, 100, true },
        MIN_MEMBERS = { 2, 32, true }, MORALE = { -100, 100 }, WOUND_CHANCE = { 0, 1 }, WOUND_MIN = { 0, 99, true },
        WOUND_MAX = { 0, 99, true }, CONTEST_CHANCE = { 0, 1 } },
    -- Assez de monde au foyer, et moral bas ou une réserve basse (chance accrue par réserve basse).
    chance = function(e, ctx)
        if #ctx.home >= e.MIN_MEMBERS and (ctx.g.morale < e.MORALE_MAX or ctx.low > 0) then
            return e.CHANCE + e.CHANCE_LOW_NEED * ctx.low
        end
        return nil
    end,
    apply = function(e, ctx)
        local g, rnd = ctx.g, ctx.rnd
        local home = kit.home(g, kit.living(g))
        if #home < 2 then return nil end
        local others, leaderHome = {}, false
        for _, mid in ipairs(home) do
            if mid == g.leader then leaderHome = true else others[#others + 1] = mid end
        end
        local a = kit.pick(others, rnd)
        local b, contested
        if leaderHome and rnd() < e.CONTEST_CHANCE then
            b, contested = g.leader, true
        else
            contested = false
            local rest = {}
            for _, mid in ipairs(home) do
                if mid ~= a then rest[#rest + 1] = mid end
            end
            b = kit.pick(rest, rnd)
        end
        local parts, wounded = { a .. " vs " .. b }, nil
        if contested then parts[#parts + 1] = "leader contested" end
        if rnd() < e.WOUND_CHANCE then
            wounded = a
            if rnd() < 0.5 then wounded = b end
            kit.hurt(g.members[wounded], e.WOUND_MIN, e.WOUND_MAX, rnd)
            parts[#parts + 1] = wounded .. " wounded"
        end
        g.morale = kit.clamp(g.morale + e.MORALE)
        LivingKnox.Groups.appendLog(g, "conflict", kit.cut(table.concat(parts, ", ")), ctx.day)
        return { a = a, b = b, contested = contested, wounded = wounded }
    end,
})
