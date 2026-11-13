-- Living Knox : événement de groupe « departure » de la simulation hors écran (LK09-T05 ; un fichier par événement,
-- LK16-T09). Fiche : docs/annexes/conception/simulation.md. Ordre du tirage 10 (le premier).
-- Un membre part quand le moral est bas : jamais le chef, ni un membre lié à un PNJ (le registre des corps garde sa
-- référence), ni un absent (expédition). Journal departure puis left ; moral.
if isClient() then return end

require "LivingKnox/LK_Simulation"

local Simulation = LivingKnox.Simulation
local kit = Simulation.eventKit

-- Membres qui peuvent partir : au foyer, hors chef, sans PNJ lié.
local function departureCandidates(g, home)
    local out = {}
    for _, mid in ipairs(home) do
        if mid ~= g.leader and g.members[mid].npc == nil then out[#out + 1] = mid end
    end
    return out
end

Simulation.registerEvent({
    id = "departure", order = 10, config = "DEPARTURE",
    bounds = { CHANCE = { 0, 1 }, MORALE_MAX = { 0, 100, true }, MIN_LEFT = { 1, 32, true }, MORALE = { -100, 100 } },
    -- Chance proportionnelle au moral qui manque sous MORALE_MAX, s'il resterait MIN_LEFT vivants et un partant possible.
    chance = function(e, ctx)
        local g = ctx.g
        if g.morale < e.MORALE_MAX and #ctx.living - 1 >= e.MIN_LEFT and #departureCandidates(g, ctx.home) > 0 then
            return e.CHANCE * (e.MORALE_MAX - g.morale) / e.MORALE_MAX
        end
        return nil
    end,
    apply = function(e, ctx)
        local g, gid, day = ctx.g, ctx.gid, ctx.day
        local candidates = departureCandidates(g, kit.home(g, kit.living(g)))
        if #candidates == 0 then return nil end
        local mid = kit.pick(candidates, ctx.rnd)
        LivingKnox.Groups.appendLog(g, "departure", kit.cut(mid .. " " .. g.members[mid].role .. ": low morale"), day)
        LivingKnox.Groups.applyLeave(g, mid, day)
        g.morale = kit.clamp(g.morale + e.MORALE)
        LivingKnox.Log.info("simulation: member %s left group %s (low morale)", mid, gid)
        return { member = mid }
    end,
})
