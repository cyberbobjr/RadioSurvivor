-- Living Knox : événement de groupe « illness » de la simulation hors écran (LK09-T05 ; un fichier par événement,
-- LK16-T09). Fiche : docs/annexes/conception/simulation.md. Ordre du tirage 40.
-- Un malade au foyer, contagion à chaque autre (SPREAD, MAX_SICK au plus) ; un malade soigné (réserve medical >=
-- MEDICAL_PER_SICK et non vide) consomme MEDICAL_PER_SICK et prend la moitié de la blessure ; moral.
if isClient() then return end

require "LivingKnox/LK_Simulation"

local Simulation = LivingKnox.Simulation
local kit = Simulation.eventKit

Simulation.registerEvent({
    id = "illness", order = 40, config = "ILLNESS",
    bounds = { CHANCE = { 0, 1 }, CHANCE_HUNGRY = { 0, 1 }, SPREAD = { 0, 1 }, MAX_SICK = { 1, 32, true },
        WOUND_MIN = { 0, 99, true }, WOUND_MAX = { 0, 99, true }, MEDICAL_PER_SICK = { 0, 100, true },
        MORALE = { -100, 100 } },
    -- Toujours possible ; plus probable quand la nourriture est sous NEED_LOW.
    chance = function(e, ctx)
        local p = e.CHANCE
        if ctx.g.needs.food < LivingKnox.Config.SIMULATION.NEED_LOW then p = p + e.CHANCE_HUNGRY end
        return p
    end,
    apply = function(e, ctx)
        local g, rnd = ctx.g, ctx.rnd
        local home = kit.home(g, kit.living(g))
        if #home == 0 then return nil end
        local first = kit.pick(home, rnd)
        local sick = { first }
        for _, mid in ipairs(home) do
            if mid ~= first and #sick < e.MAX_SICK and rnd() < e.SPREAD then sick[#sick + 1] = mid end
        end
        local treated, used = 0, 0
        for _, mid in ipairs(sick) do
            local lo, hi = e.WOUND_MIN, e.WOUND_MAX
            if g.needs.medical > 0 and g.needs.medical >= e.MEDICAL_PER_SICK then
                g.needs.medical = g.needs.medical - e.MEDICAL_PER_SICK
                used = used + e.MEDICAL_PER_SICK
                treated = treated + 1
                lo, hi = math.floor(lo / 2), math.floor(hi / 2)
            end
            kit.hurt(g.members[mid], lo, hi, rnd)
        end
        g.morale = kit.clamp(g.morale + e.MORALE)
        LivingKnox.Groups.appendLog(g, "illness", kit.cut(table.concat(sick, " ") .. " sick, " .. treated
            .. " treated, medical -" .. used), ctx.day)
        return { sick = sick, treated = treated, medical = used }
    end,
})
