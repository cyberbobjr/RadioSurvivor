-- Living Knox : contexte de jeu du modèle des plaies (LK21-T02, ADR adr-blessures-soins.md D01). Le modèle
-- (shared/LivingKnox/LK_Wounds.lua) est pur : le hasard, la durée d'une journée et les options sandbox lui viennent
-- d'ici, lus sur l'autorité seulement (LK_Health, sources de blessure).
--   rnd : tirage du jeu dans [0, 1) : ZombRand(RND_STEPS) / RND_STEPS (Rand.Next(int), J/Lua/LuaManager.java),
--         remplaçable (WoundContext.rnd) par un tirage fixe dans les bancs et les suites ;
--   minutesPerDay : GameTime.getMinutesPerDay (option DayLength, J/GameTime.java:861, J/SandboxOptions.java:437) ;
--   severity : option InjurySeverity 1, 2 ou 3 (J/SandboxOptions.java:154 ; getValue rend l'index 1..3 d'un
--              StrongEnumSandboxOption, :1821-1835) ; absente ou hors bornes : 2 (normale, défaut du vanilla) ;
--   woundInfectionFactor : option WoundInfectionFactor (0 par défaut, J/SandboxOptions.java:236), lue pour LK21-T04.
require "LivingKnox/LK_Core"

local WoundContext = LivingKnox.WoundContext or {}
LivingKnox.WoundContext = WoundContext

WoundContext.RND_STEPS = 1000000
WoundContext.DEFAULT_SEVERITY = 2

-- Tirage dans [0, 1) (remplaçable).
WoundContext.rnd = WoundContext.rnd or function()
    return ZombRand(WoundContext.RND_STEPS) / WoundContext.RND_STEPS
end

local function option(name)
    local so = getSandboxOptions ~= nil and getSandboxOptions() or nil
    local opt = so ~= nil and so:getOptionByName(name) or nil
    if opt == nil then return nil end
    return opt:getValue()
end

local function severity()
    local v = option("InjurySeverity")
    if v == 1 or v == 2 or v == 3 then return v end
    return WoundContext.DEFAULT_SEVERITY
end

local function minutesPerDay()
    local gt = getGameTime ~= nil and getGameTime() or nil
    local v = gt ~= nil and gt:getMinutesPerDay() or nil
    if LivingKnox.Num.finite(v) and v > 0 then return v end
    return nil
end

local function infectionFactor()
    local v = option("WoundInfectionFactor")
    if LivingKnox.Num.finite(v) and v >= 0 then return v end
    return 0
end

-- Contexte courant pour Wounds.add, Wounds.advance et les sources (table neuve à chaque appel).
function WoundContext.current()
    return { rnd = function() return WoundContext.rnd() end, minutesPerDay = minutesPerDay(), severity = severity(),
        woundInfectionFactor = infectionFactor() }
end

return WoundContext
