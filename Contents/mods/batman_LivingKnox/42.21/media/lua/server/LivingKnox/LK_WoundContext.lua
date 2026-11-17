-- Living Knox : contexte de jeu du modèle des plaies (LK21-T02, ADR adr-blessures-soins.md D01). Le modèle
-- (shared/LivingKnox/LK_Wounds.lua) est pur : le hasard, la durée d'une journée et les options sandbox lui viennent
-- d'ici, lus sur l'autorité seulement (LK_Health, sources de blessure).
--   rnd : tirage du jeu dans [0, 1) : ZombRand(RND_STEPS) / RND_STEPS (Rand.Next(int), J/Lua/LuaManager.java),
--         remplaçable (WoundContext.rnd) par un tirage fixe dans les bancs et les suites ;
--   minutesPerDay : GameTime.getMinutesPerDay (option DayLength, J/GameTime.java:861, J/SandboxOptions.java:437) ;
--   severity : option InjurySeverity 1, 2 ou 3 (J/SandboxOptions.java:154 ; getValue rend l'index 1..3 d'un
--              StrongEnumSandboxOption, :1821-1835) ; absente ou hors bornes : 2 (normale, défaut du vanilla) ;
--   woundInfectionFactor : option WoundInfectionFactor (0 par défaut, J/SandboxOptions.java:236), lue pour LK21-T04 ;
--   transmission, mortality : options ZombieLore.Transmission et ZombieLore.Mortality (J/SandboxOptions.java:1908-1909,
--              EnumSandboxOption.getValue : index 1..n) ; absentes : défauts du vanilla (LK_Virus.lua, LK21-T04) ;
--   worldHours : âge du monde en heures (GameTime.getWorldAgeHours, J/GameTime.java), heure d'une infection ;
--   virusDelay : délai imposé avant la mort par le virus (Config.INFECTION.DELAY_HOURS, réglage des essais ; nil :
--              délai tiré dans la table du vanilla).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"

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

-- Âge du monde en heures, ou nil (horloge absente).
function WoundContext.worldHours()
    local gt = getGameTime ~= nil and getGameTime() or nil
    local v = gt ~= nil and gt:getWorldAgeHours() or nil
    if LivingKnox.Num.finite(v) and v >= 0 then return v end
    return nil
end

local function testDelay()
    local c = LivingKnox.Config.INFECTION
    local v = c ~= nil and c.DELAY_HOURS or nil
    if LivingKnox.Num.finite(v) and v >= 0 then return v end
    return nil
end

-- Contexte courant pour Wounds.add, Wounds.advance, les sources et le virus (table neuve à chaque appel).
function WoundContext.current()
    return { rnd = function() return WoundContext.rnd() end, minutesPerDay = minutesPerDay(), severity = severity(),
        woundInfectionFactor = infectionFactor(), transmission = option("ZombieLore.Transmission"),
        mortality = option("ZombieLore.Mortality"), worldHours = WoundContext.worldHours(), virusDelay = testDelay() }
end

return WoundContext
