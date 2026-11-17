-- Living Knox : événement de groupe « clash » de la simulation hors écran (LK09-T05, I9.1 ; un fichier par événement,
-- LK16-T09). Fiche : docs/annexes/conception/simulation.md. Ordre du tirage 50 (le dernier).
-- Combat abstrait entre un groupe d'un type ATTACKERS et un groupe d'un autre type, foyers connus proches l'un de
-- l'autre et loin des bases connues des joueurs (CA_Sites.knownBases, lue une fois par pas) ; morts consignés avec un
-- lieu approximatif (entrée remains), aucun cadavre posé dans le monde. La cible compte comme ayant eu son événement
-- du jour ; un groupe matérialisé n'est la cible d'aucun combat.
if isClient() then return end

require "LivingKnox/LK_Simulation"

local Simulation = LivingKnox.Simulation
local kit = Simulation.eventKit

local function signed(v)
    if v >= 0 then return "+" .. tostring(v) end
    return tostring(v)
end

-- Écart entre le foyer (case) et une base (rectangle à fin exclusive), même mesure que CA_Sites.gap.
local function baseGap(home, b)
    local gx = math.max(0, b.x1 - (home.x + 1), home.x - b.x2)
    local gy = math.max(0, b.y1 - (home.y + 1), home.y - b.y2)
    return math.sqrt(gx * gx + gy * gy)
end

-- Foyer à minDist cases au moins de chaque base connue (entrée sans x1, y1, x2, y2 numériques : ignorée).
local function farFromBases(home, bases, minDist)
    for _, b in ipairs(bases) do
        if type(b) == "table" and type(b.x1) == "number" and type(b.y1) == "number" and type(b.x2) == "number"
            and type(b.y2) == "number" and baseGap(home, b) < minDist then
            return false
        end
    end
    return true
end

-- Cibles possibles d'un combat lancé par le groupe gid (identifiants triés) : attaquant d'un type ATTACKERS, foyer
-- connu loin des bases, au moins MIN_FORCE membres au foyer ; cible d'un autre type (hors ATTACKERS), sans
-- événement ce jour, foyer connu à MAX_DISTANCE au plus et loin des bases, au moins un membre au foyer.
-- bases = nil (inconnues) : aucun combat.
local function clashTargets(data, ids, gid, e, bases, done)
    local g = data.groups[gid]
    if bases == nil or not e.ATTACKERS[g.type] or not g.home then return {} end
    if #kit.home(g, kit.living(g)) < e.MIN_FORCE then return {} end
    if not farFromBases(g.home, bases, e.PLAYER_DISTANCE) then return {} end
    local out = {}
    for _, tid in ipairs(ids) do
        local t = data.groups[tid]
        if tid ~= gid and not done[tid] and t and not e.ATTACKERS[t.type] and t.home
            and not Simulation.materialized(t) then
            local dx, dy = t.home.x - g.home.x, t.home.y - g.home.y
            if math.sqrt(dx * dx + dy * dy) <= e.MAX_DISTANCE and farFromBases(t.home, bases, e.PLAYER_DISTANCE)
                and #kit.home(t, kit.living(t)) > 0 then
                out[#out + 1] = tid
            end
        end
    end
    return out
end

-- Force au foyer : 1 par membre, 0.5 par membre gravement blessé (MemberHealth.seriouslyWounded, LK21-T03).
local function strength(g, home)
    local s = 0
    for _, mid in ipairs(home) do
        if LivingKnox.MemberHealth.seriouslyWounded(g.members[mid]) then s = s + 0.5 else s = s + 1 end
    end
    return s
end

-- Un tirage par membre au foyer : perte (lossRate, MAX_DEATHS au plus, au-delà : blessure), sinon blessure (coup de la
-- source SOURCE : plaies et HIT_MIN..HIT_MAX % de santé, LK21-T03).
local function casualties(g, home, lossRate, woundRate, e, rnd)
    local dead, wounded = {}, {}
    for _, mid in ipairs(home) do
        local r = rnd()
        if r < lossRate and #dead < e.MAX_DEATHS then
            dead[#dead + 1] = mid
        elseif r < lossRate + woundRate then
            kit.hit(g.members[mid], e.SOURCE, e.HIT_MIN, e.HIT_MAX, rnd)
            wounded[#wounded + 1] = mid
        end
    end
    return dead, wounded
end

local function roundedPlace(home, step)
    local function r(v) return math.floor(v / step + 0.5) * step end
    return r(home.x) .. "," .. r(home.y) .. "," .. home.z
end

-- Combat entre l'attaquant gid et la cible tid, au foyer de la cible. Victoire de l'attaquant avec la chance
-- force A / (force A + force D x DEFENSE_BONUS) ; pertes et blessés des deux côtés (taux du vainqueur ou du vaincu) ;
-- AMMO_COST munitions dépensées de chaque côté ; attaquant vainqueur : butin borné (LOOT_SHARE de chaque réserve de la
-- cible, LOOT_MAX au plus, sans dépasser 100) ; moral. Journal des deux groupes : clash, died..., (leader), remains
-- « <morts> at x,y,z » (foyer de la cible arrondi à PLACE_ROUND).
local function clash(data, gid, g, tid, e, rnd, day)
    local G, t = LivingKnox.Groups, data.groups[tid]
    local homeA, homeD = kit.home(g, kit.living(g)), kit.home(t, kit.living(t))
    local sa, sd = strength(g, homeA), strength(t, homeD) * e.DEFENSE_BONUS
    local won = rnd() * (sa + sd) < sa
    local deadA, woundedA, deadD, woundedD
    if won then
        deadA, woundedA = casualties(g, homeA, e.LOSS_WIN, e.WOUND_WIN, e, rnd)
        deadD, woundedD = casualties(t, homeD, e.LOSS_LOSE, e.WOUND_LOSE, e, rnd)
    else
        deadA, woundedA = casualties(g, homeA, e.LOSS_LOSE, e.WOUND_LOSE, e, rnd)
        deadD, woundedD = casualties(t, homeD, e.LOSS_WIN, e.WOUND_WIN, e, rnd)
    end
    local deltaA, deltaD = {}, {}
    for _, key in ipairs(G.NEEDS) do deltaA[key], deltaD[key] = 0, 0 end
    local beforeA, beforeD = g.needs.ammo, t.needs.ammo
    g.needs.ammo, t.needs.ammo = kit.clamp(beforeA - e.AMMO_COST), kit.clamp(beforeD - e.AMMO_COST)
    deltaA.ammo, deltaD.ammo = g.needs.ammo - beforeA, t.needs.ammo - beforeD
    if won then
        for _, key in ipairs(G.NEEDS) do
            local take = math.min(math.floor(t.needs[key] * e.LOOT_SHARE), e.LOOT_MAX, G.LEVEL_MAX - g.needs[key])
            if take > 0 then
                t.needs[key], g.needs[key] = t.needs[key] - take, g.needs[key] + take
                deltaA[key], deltaD[key] = deltaA[key] + take, deltaD[key] - take
            end
        end
    end
    local function needsText(delta)
        local parts = {}
        for _, key in ipairs(G.NEEDS) do parts[#parts + 1] = key .. " " .. signed(delta[key]) end
        return table.concat(parts, " ")
    end
    local outcomeA, outcomeD = "lost", "won"
    if won then outcomeA, outcomeD = "won", "lost" end
    G.appendLog(g, "clash", kit.cut("attack " .. tid .. " " .. outcomeA .. ": " .. #deadA .. " lost, " .. #woundedA
        .. " wounded, " .. needsText(deltaA)), day)
    G.appendLog(t, "clash", kit.cut("defend " .. gid .. " " .. outcomeD .. ": " .. #deadD .. " lost, " .. #woundedD
        .. " wounded, " .. needsText(deltaD)), day)
    local place = roundedPlace(t.home, e.PLACE_ROUND)
    local moraleA, moraleD = g.morale + e.MORALE_LOSE, t.morale + e.MORALE_WIN
    if won then moraleA, moraleD = g.morale + e.MORALE_WIN, t.morale + e.MORALE_LOSE end
    -- Morts d'un côté : toutes appliquées, puis une seule succession si le chef en était (jamais un mort du combat).
    local function bury(grp, dead, morale)
        local leaderDied = false
        for _, mid in ipairs(dead) do
            morale = morale + LivingKnox.Config.SIMULATION.MORALE_DEATH
            if G.applyDeath(grp, mid, day) then leaderDied = true end
        end
        if leaderDied then
            local successor = G.pickSuccessor(grp)
            if successor then G.applyLeader(grp, successor, day) end
        end
        if #dead > 0 then G.appendLog(grp, "remains", kit.cut(table.concat(dead, " ") .. " at " .. place), day) end
        return kit.clamp(morale)
    end
    g.morale = bury(g, deadA, moraleA)
    t.morale = bury(t, deadD, moraleD)
    LivingKnox.Log.info("simulation: clash %s attacks %s, attacker %s, losses %s/%s", gid, tid, outcomeA,
        tostring(#deadA), tostring(#deadD))
    return { target = tid, won = won, deadA = deadA, deadD = deadD, woundedA = woundedA, woundedD = woundedD,
        deltaA = deltaA, deltaD = deltaD, place = place }
end

Simulation.registerEvent({
    id = "clash", order = 50, config = "CLASH",
    bounds = { CHANCE = { 0, 1 }, CHANCE_NEEDY = { 0, 1 }, MAX_DISTANCE = { 0, 100000, true },
        PLAYER_DISTANCE = { 80, 100000, true }, MIN_FORCE = { 1, 32, true }, DEFENSE_BONUS = { 0.1, 10 },
        LOSS_WIN = { 0, 1 }, LOSS_LOSE = { 0, 1 }, WOUND_WIN = { 0, 1 }, WOUND_LOSE = { 0, 1 },
        MAX_DEATHS = { 0, 32, true }, HIT_MIN = { 0, 99, true }, HIT_MAX = { 0, 99, true },
        LOOT_SHARE = { 0, 1 }, LOOT_MAX = { 0, 100, true }, AMMO_COST = { 0, 100, true },
        MORALE_WIN = { -100, 100 }, MORALE_LOSE = { -100, 100 }, PLACE_ROUND = { 1, 1000, true } },
    -- Types attaquants : ensemble des chaînes de la liste ATTACKERS (autres entrées ignorées).
    prepare = function(e, raw)
        local attackers = {}
        if type(raw.ATTACKERS) == "table" then
            for _, t in ipairs(raw.ATTACKERS) do
                if type(t) == "string" then attackers[t] = true end
            end
        end
        e.ATTACKERS = attackers
    end,
    -- Une cible au moins (ctx.targets) ; plus probable quand une réserve est basse.
    chance = function(e, ctx)
        ctx.targets = clashTargets(ctx.data, ctx.ids, ctx.gid, e, ctx.bases, ctx.done)
        if #ctx.targets == 0 then return nil end
        local p = e.CHANCE
        if ctx.low > 0 then p = p + e.CHANCE_NEEDY end
        return p
    end,
    apply = function(e, ctx)
        local targets = ctx.targets
        if not targets or #targets == 0 then return nil end
        return clash(ctx.data, ctx.gid, ctx.g, kit.pick(targets, ctx.rnd), e, ctx.rnd, ctx.day)
    end,
})
