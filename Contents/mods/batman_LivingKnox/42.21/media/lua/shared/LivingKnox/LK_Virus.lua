-- Living Knox : virus de Knox d'un PNJ, règles pures du vanilla (LK21-T04, ADR docs/architecture/decisions/
-- adr-blessures-soins.md, D04 ; recherche docs/annexes/conception/blessures-moteur.md, section 2.7). Chemins Java
-- abrégés : J/ = zombie/ du Java décompilé 42.22.
--
-- Pur : aucun appel au jeu. Options, heure du monde et hasard viennent du contexte ctx de l'appelant
-- (LK_WoundContext.lua pour le jeu) : { rnd (fonction, [0, 1)), transmission (option ZombieLore.Transmission, 1 par
-- défaut), mortality (option ZombieLore.Mortality, 5 par défaut), worldHours (âge du monde en heures), virusDelay
-- (délai imposé en heures, réglage des essais, facultatif) }.
--
-- État d'un corps infecté : list.virus = { since = heure de l'infection, due = heure de la mort } (heures d'âge du
-- monde), porté par la liste de plaies (LK_Wounds) et sauvegardé avec elle (LK_WoundsForm.lua) : le virus suit les
-- plaies partout où elles passent (corps, membre hors écran) et survit à la guérison de la morsure, comme
-- BodyDamage.isInfected au vanilla. Une plaie qui a transmis le virus porte w.virus = vrai (BodyPart.isInfected de sa
-- partie : aucun tirage d'infection de plaie, :221 ; niveau d'infection +2e-4 par tick, :282-283, LK_Wounds).
-- Transmission par la donnée du type de plaie (Wounds.registerKind) : virusChance (pour cent) et virusRoute
-- ("saliva" : morsure ; "blood" : griffure, coupure).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Wounds"

local Virus = LivingKnox.Virus or {}
LivingKnox.Virus = Virus

-- Voies ouvertes par chaque valeur de l'option ZombieLore.Transmission (J/SandboxOptions.java:1908) :
-- 1 sang et salive, 2 salive seule (generateZombieInfection l'écarte, J/characters/BodyDamage/BodyPart.java:710-712),
-- 3 tout le monde est infecté, 4 aucune (SetBitten :616-619, :710-712).
Virus.TRANSMISSION = {
    [1] = { blood = true, saliva = true },
    [2] = { saliva = true },
    [3] = { blood = true, saliva = true },
    [4] = {},
}
Virus.DEFAULT_TRANSMISSION = 1   -- défaut du vanilla (:1908)
Virus.DEFAULT_ROUTE = "blood"

-- Après la mort, le corps se relève (IsoGameCharacter.shouldBecomeZombieAfterDeath,
-- J/characters/IsoGameCharacter.java:10523-10540) : toujours (ALWAYS), si infecté (INFECTED), jamais (absent).
Virus.RISE = { [1] = "INFECTED", [2] = "INFECTED", [3] = "ALWAYS" }

-- Délai avant la mort, en heures, par valeur de l'option ZombieLore.Mortality (J/SandboxOptions.java:1909) :
-- BodyDamage.pickMortalityDuration (J/characters/BodyDamage/BodyDamage.java:1789-1807), tiré dans { min, max }.
-- 7 « jamais » : absent, l'infection est fausse et ne tue pas (BodyPart.java:620-623, :713-716). Traits Résilient et
-- Prédisposé à la maladie (x 1,25, x 0,75) : sans objet pour un PNJ.
Virus.MORTALITY = {
    [1] = { 0, 0 },                    -- instantanée
    [2] = { 0, 30 / 3600 },            -- 0 à 30 secondes
    [3] = { 0.5 / 60, 1 / 60 },        -- 0,5 à 1 minute
    [4] = { 3, 12 },                   -- 3 à 12 heures
    [5] = { 48, 72 },                  -- 2 à 3 jours
    [6] = { 168, 336 },                -- 1 à 2 semaines
}
Virus.DEFAULT_MORTALITY = 5   -- défaut du vanilla (:1909)
Virus.HOURS_MAX = 1e7         -- borne des heures sauvegardées

local function finite(v)
    return LivingKnox.Num.finite(v)
end

local function option(v, default)
    if type(v) == "number" and v == math.floor(v) then return v end
    return default
end

local function transmission(ctx)
    return option(ctx ~= nil and ctx.transmission or nil, Virus.DEFAULT_TRANSMISSION)
end

local function mortality(ctx)
    return option(ctx ~= nil and ctx.mortality or nil, Virus.DEFAULT_MORTALITY)
end

-- Vrai si une plaie de type spec (Wounds.registerKind), faite par un zombie, transmet le virus : voie ouverte par
-- l'option de transmission, mortalité qui tue, puis chance du type (100 : sans tirage, comme SetBitten ; sinon
-- Rand.Next(100) < chance, :706).
function Virus.transmits(spec, ctx)
    local chance = spec ~= nil and spec.virusChance or nil
    if not finite(chance) or chance <= 0 then return false end
    local routes = Virus.TRANSMISSION[transmission(ctx)]
    if routes == nil or not routes[spec.virusRoute or Virus.DEFAULT_ROUTE] then return false end
    if Virus.MORTALITY[mortality(ctx)] == nil then return false end
    if chance >= 100 then return true end
    return ctx.rnd() * 100 < chance
end

-- Nouvelle infection { since, due } à l'heure ctx.worldHours, délai tiré dans MORTALITY (ou ctx.virusDelay) ; nil si
-- la mortalité ne tue pas ou si l'heure est inconnue (aucune échéance inventée).
function Virus.contract(ctx)
    local hours = ctx ~= nil and ctx.worldHours or nil
    if not finite(hours) or hours < 0 then return nil end
    local range = Virus.MORTALITY[mortality(ctx)]
    if range == nil then return nil end
    local delay = ctx.virusDelay
    if not (finite(delay) and delay >= 0) then delay = range[1] + (range[2] - range[1]) * ctx.rnd() end
    return { since = hours, due = hours + delay }
end

-- Plaies added, faites par un zombie et ajoutées à list : chaque plaie qui transmet le virus le porte (w.virus) ; la
-- première infection du corps fixe list.virus (une seconde morsure ne change pas l'échéance, comme infectionTime au
-- vanilla, BodyDamage.java:1868-1871). Rend le nombre de plaies qui l'ont transmis.
function Virus.fromWounds(list, added, ctx)
    local n = 0
    local W = LivingKnox.Wounds
    for _, w in ipairs(added or {}) do
        if Virus.transmits(W.kind(w.kind), ctx) then
            local v = list.virus or Virus.contract(ctx)
            if v ~= nil then
                list.virus = v
                w.virus = true
                n = n + 1
            end
        end
    end
    return n
end

-- Vrai si une des plaies added porte le virus (contamination par ce coup).
function Virus.carried(added)
    for _, w in ipairs(added or {}) do
        if w.virus then return true end
    end
    return false
end

-- Vrai si l'échéance de l'infection v est atteinte à l'heure hours.
function Virus.isDue(v, hours)
    return v ~= nil and finite(hours) and hours >= v.due
end

-- Vrai si un corps mort se relève : option de transmission et infection (voir RISE).
function Virus.rises(infected, ctx)
    local rule = Virus.RISE[transmission(ctx)]
    return rule == "ALWAYS" or (rule == "INFECTED" and infected == true)
end

-- Vrai si v est une infection valide ; sinon faux et la raison.
function Virus.valid(v)
    if type(v) ~= "table" then return false, "virus must be a table" end
    if not finite(v.since) or v.since < 0 or v.since > Virus.HOURS_MAX then return false, "bad virus start" end
    if not finite(v.due) or v.due < v.since or v.due > Virus.HOURS_MAX then return false, "bad virus due" end
    return true
end

return Virus
