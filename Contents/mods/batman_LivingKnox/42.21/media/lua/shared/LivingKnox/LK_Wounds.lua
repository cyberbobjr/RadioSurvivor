-- Living Knox : modèle pur des plaies d'un PNJ, par partie du corps, aux règles du vanilla (LK21-T01, ADR
-- docs/architecture/decisions/adr-blessures-soins.md, D01 et D02 ; recherche docs/annexes/conception/blessures-moteur.md,
-- section 2). Le modèle du joueur (BodyDamage, BodyPart) ne tourne pas sur un IsoZombie (BodyDamage.java:1812-1814) :
-- ses règles sont reproduites ici. Chemins Java abrégés : J/ = zombie/ du Java décompilé 42.22.
--
-- Pur : aucun appel au jeu. Le temps (minutes de jeu) et le hasard (ctx.rnd, fonction qui rend un nombre de [0, 1))
-- viennent de l'appelant ; le corps incarné (LK_Health) et la simulation hors écran (LK_Simulation) font le même calcul.
-- ctx : { rnd (exigé pour add, extract et advance), minutesPerDay (90 par défaut), severity (option InjurySeverity 1, 2
-- ou 3 ; 2 par défaut), soiled = fn(part) -> sale, sanglant (vêtement sur la partie, facultatif), woundInfectionFactor
-- (option WoundInfectionFactor, 0 par défaut) }.
--
-- Unités : les nombres du vanilla sont par unité de GameTime.getMultiplier() (« tick »), qui vaut 48 par seconde réelle
-- (J/GameTime.java:911-917, base pz-knowledge api-42-21.md). Une minute de jeu dure minutesPerDay / 24 secondes réelles,
-- donc 2 x minutesPerDay ticks (180 avec la journée par défaut de 90 minutes, J/SandboxOptions.java:72, :403). Comme
-- au vanilla, la guérison suit le temps réel : une journée plus longue guérit en moins de jours.
--
-- Une plaie (table gardée dans la liste du PNJ, forme compacte : Wounds.pack, LK_WoundsForm.lua) :
--   kind     : type inscrit (Wounds.registerKind) ; part : partie du corps (Wounds.PARTS)
--   age      : minutes de jeu depuis la blessure
--   time     : durée de guérison restante, unités vanilla (scratchTime, cutTime... ; nil : ne guérit pas seule, balle)
--   bleed    : temps de saignement restant (bleedingTime), unités vanilla
--   bandage  : nil, ou { life = vie du bandage (0 : sale, BodyPart.java:134-136), alcohol = bandage à l'alcool }
--   stitch   : nil, ou temps des points (stitchTime, 0..50) ; splint : nil, ou facteur d'attelle (splintFactor)
--   foreign  : corps étranger dans la plaie (balle, éclat) ; infected : plaie infectée ; level : niveau d'infection
--              (woundInfectionLevel, -2..10) ; alcohol : désinfectant sur la plaie (alcoholLevel)
--   harm     : dégâts déjà faits à la partie (0..100) par cette plaie
--   virus    : vrai si la plaie a transmis le virus de Knox (BodyPart.isInfected de sa partie, LK21-T04, LK_Virus.lua) :
--              aucun tirage d'infection de plaie (:221), niveau d'infection +2e-4 par tick (:282-283)
-- La liste peut porter l'infection du corps (list.virus, LK_Virus.lua), sauvegardée avec elle.
-- Les soins (LK_Care, LK21-T05) changent une plaie par les transitions du vanilla rangées ici (Wounds.bandage, stitch,
-- splint, disinfect, extract) ; le choix du soin, du matériel et du soignant n'est pas ici.
--
-- Approximations d'un modèle par plaie et par minute (le vanilla calcule par partie et par image) :
--   - chaque plaie a ses propres compteurs ; deux plaies sur une même partie ne combinent pas leurs modificateurs
--     d'infection (une brûlure seule ne s'infecte donc jamais, comme au vanilla, :219) ;
--   - l'évolution est intégrée par segments : entre deux événements (saignement fini, bandage sale, plancher atteint...)
--     les vitesses sont constantes et le calcul est exact ; un tirage d'infection par segment (au plus SEGMENT_MINUTES),
--     l'infection prend effet à la fin du segment ;
--   - dégâts d'une partie plafonnés à 100 tant que ses plaies durent (BodyPart.ReduceHealth :450-452) ;
--   - régénération (LK21-T02, Wounds.regeneration, Wounds.healthCap ; appliquée par LK_Health) : santé générale rendue
--     comme BodyDamage.Update (J/characters/BodyDamage/BodyDamage.java:1887-1928, standardHealthAddition 0.002 par
--     tick, :79) répartie par AddGeneralHealth (:917-930) sur les parties abîmées. Le modèle n'a pas de santé par
--     partie : avec une perte générale (saignement, réparti sur les 17 parties par ReduceGeneralHealth :932-944, ou coup
--     sans plaie), toutes les parties sont supposées abîmées et une partie tenue par une plaie qui l'abîme encore ne
--     remonte pas (sa part, REGEN / 17, est sous ses dégâts par tick) ; sans perte générale, seules les parties tenues
--     sont abîmées et se partagent REGEN, qui retire des dégâts de leurs plaies (harm). PNJ éveillé sans faim ni soif
--     fortes : ni sommeil (0.02, :82), ni régénération réduite ;
--   - l'alcool posé sur une plaie (alcohol > 0) empêche une infection de prendre : au vanilla elle est guérie au tick
--     suivant (:259-263, setWoundInfectionLevel :1192-1198) ;
--   - une plaie aux points est guérie quand ses points atteignent 50 (plafond :388-390 ; au-delà, plus de douleur ni
--     de soin vanilla) ;
--   - les traits Cicatrisation rapide / lente et le niveau de soin du blessé n'existent pas pour un PNJ ;
--   - plaie infectée : au vanilla (WoundInfectionFactor = 0 par défaut, SandboxOptions.java:236) elle fait mal, use
--     le bandage et s'aggrave, sans perte de santé ; avec l'option, perte du malus « malade » de niveau 4 quand le
--     niveau cumulé dépasse 90 (BodyDamage.java:84, :1957, :2774-2790, MoodleStat.java:17), lu en fin de période.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"

local Wounds = LivingKnox.Wounds or {}
LivingKnox.Wounds = Wounds

-- ================================================================ constantes du vanilla
Wounds.MINUTES_PER_DAY = 90              -- SandboxOptions.java:72 (DayLength 4), :403
Wounds.TICK_FACTOR = 2                   -- ticks par minute de jeu = TICK_FACTOR x minutesPerDay (en-tête)
Wounds.DAMAGE_SCALER = 0.0057142857      -- BodyPart.java:30 (x5 au cou, :90-92 : PARTS.scaler)
Wounds.BLEED_DAMAGE = 0.2857143          -- BodyPart.java:29, perte de santé générale :161-168
Wounds.BLEED_HEAL = { open = 2e-5, bandaged = 2e-4 }   -- BodyPart.java:211, :204
Wounds.BLEED_WEAR = 3e-4                 -- usure du bandage d'une plaie qui saigne, BodyPart.java:208
Wounds.STITCH = { open = 2e-4, bandaged = 5e-4, max = 50, wear = 1e-4,   -- BodyPart.java:371-391
    openChance = 20000, bandagedChance = 80000 }
Wounds.INFECTION = { base = 40000, open = 10000, dirty = 35000, dirtyClothes = 20000, bloodyClothes = 24000,
    floor = 5000,                        -- BodyPart.java:221-257
    grow = 1e-5, alcohol = 2e-4, alcoholBandage = 6e-4, wear = 2e-4, max = 10, min = -2,   -- :258-305, :1192-1198
    virus = 2e-4 }                       -- partie porteuse du virus de Knox (:282-283, LK21-T04)
-- Tirages d'infection par tick : Rand.Next(Rand.AdjustForFramerate(n)) == 0 à chaque image, n x fps / 30
-- (RandInterface.java:29) : 30 tirages de 1 / n par seconde réelle, pour 48 ticks.
Wounds.ROLLS_PER_TICK = 30 / 48
Wounds.SICK = { threshold = 90, damage = 0.0165 }   -- BodyDamage.java:84, :1957 ; MoodleStat.java:17 (0.9)
Wounds.SEVERITY = { 0.5, 1, 1.5 }        -- InjurySeverity 1, 2, 3 (BodyPart.java:688-697, :1806-1813)
Wounds.MAX_WOUNDS = 64
Wounds.SEGMENT_MINUTES = 60
Wounds.REGEN = 0.002                     -- santé générale rendue par tick (BodyDamage.java:79, :1909)

-- Parties du corps, dans l'ordre de BodyPartType (J/characters/BodyDamage/BodyPartType.java:16-32) : modificateurs de
-- douleur, de dégâts (part de la santé générale, BodyDamage.calculateOverallHealth :2079-2089) et de saignement
-- (generateBleeding :1814), modèle de bandage visible ; blood : BloodBodyPartType de même nom
-- (J/characterTextures/BloodBodyPartType.java:14-30, sang et trous, LK21-T09) ; scaler : dégâts x5 au cou (:90-92).
local function part(id, pain, damage, bleed, bandage, scaler)
    return { id = id, blood = id, pain = pain, damage = damage, bleed = bleed, bandage = "Base.Bandage_" .. bandage,
        scaler = scaler or 1 }
end
Wounds.PARTS = {
    part("Hand_L", 0.5, 0.1, 0.2, "LeftHand"), part("Hand_R", 0.5, 0.1, 0.2, "RightHand"),
    part("ForeArm_L", 0.6, 0.2, 0.3, "LeftLowerArm"), part("ForeArm_R", 0.6, 0.2, 0.3, "RightLowerArm"),
    part("UpperArm_L", 0.6, 0.3, 0.4, "LeftUpperArm"), part("UpperArm_R", 0.6, 0.3, 0.4, "RightUpperArm"),
    part("Torso_Upper", 0.7, 0.35, 0.5, "Chest"), part("Torso_Lower", 0.78, 0.4, 0.9, "Abdomen"),
    part("Head", 0.8, 0.6, 1.0, "Head"), part("Neck", 0.8, 0.7, 1.5, "Neck", 5),
    part("Groin", 0.7, 0.4, 0.5, "Groin"),
    part("UpperLeg_L", 0.7, 0.3, 0.4, "LeftUpperLeg"), part("UpperLeg_R", 0.7, 0.3, 0.4, "RightUpperLeg"),
    part("LowerLeg_L", 0.6, 0.2, 0.3, "LeftLowerLeg"), part("LowerLeg_R", 0.6, 0.2, 0.3, "RightLowerLeg"),
    part("Foot_L", 0.5, 0.2, 0.2, "LeftFoot"), part("Foot_R", 0.5, 0.2, 0.2, "RightFoot"),
}
Wounds.PART = {}
for _, p in ipairs(Wounds.PARTS) do Wounds.PART[p.id] = p end

-- ================================================================ registre des types de plaie (D02)
-- Un fichier par type (shared/LivingKnox/Wounds/LK_Wound_<Kind>.lua, chargé par le jeu, qui requiert ce module)
-- appelle Wounds.registerKind(id, spec). Ce module ne nomme aucun type : tout ce qui leur est propre vient de spec.
-- Nombres par tick vanilla. spec :
--   order       : rang dans le registre (nombre)
--   time        : { min, max } durée de guérison tirée à la blessure ; nil : ne guérit pas seule (foreign exigé)
--   heal        : décroissance de time par tick { open, bandaged, splinted (x facteur d'attelle) } ; open exigé si time
--   floor       : { open, foreign } plancher de time sans bandage / avec corps étranger (plaie profonde : 3)
--   bleed       : termes du saignement tiré { { min, max, perTime = vrai si x durée tirée }, ... } (generateBleeding)
--   bleedOnAdd  : faux si la blessure ordinaire ne saigne pas (griffure de zombie) ; add(..., { bleed = true }) force
--   bleedFloor  : { foreign } plancher du saignement avec corps étranger (éclat : 3)
--   damage      : dégâts de partie par tick { open, bandaged, splinted } tant que la plaie dure (time > 0 ou foreign)
--   wear        : usure du bandage par tick tant que time > 0 ; bleedWear : usure par le saignement tant que time > 0
--                 (sinon BLEED_WEAR)
--   infect      : retrait de la base 40000 de la chance d'infection ; nil : jamais tirée (hors de la porte :219)
--   foreignInfect : retrait de plus avec corps étranger ; infectGrowth : aggravation par tick avec corps étranger
--   infectedOnAdd : plaie infectée dès la blessure (morsure)
--   virusChance : pour cent de transmission du virus de Knox quand un zombie fait la plaie (LK21-T04, LK_Virus.lua)
--   virusRoute  : voie de transmission, "saliva" (morsure) ou "blood" (défaut), ouverte ou non par l'option
--                 ZombieLore.Transmission (LK_Virus.TRANSMISSION)
--   foreign     : corps étranger { becomes = type après retrait, time = { min, max } nouvelle durée (facultatif) }
--   stitch, splint, bandage : la plaie se recoud, s'attelle, se bande (soins demandés, Wounds.needs, LK_WoundsNeeds.lua)
--   pain        : douleur { perTime, open, bandaged, foreign, splinted (x pendant l'attelle) } (BodyPart.getPain :903-937)
--   blood       : poids du sang visible 0..1 (LK21-T09)
-- Inscrire de nouveau un id le remplace (rechargement).
Wounds.kindList = Wounds.kindList or {}
Wounds.kindById = Wounds.kindById or {}

local NUMBER_FIELDS = { wear = true, bleedWear = true, infect = true, foreignInfect = true, infectGrowth = true,
    virusChance = true }
local FLAG_FIELDS = { bleedOnAdd = true, infectedOnAdd = true, stitch = true, splint = true, bandage = true }
local RATE_TABLES = { heal = true, damage = true, floor = true, bleedFloor = true, pain = true }

local function nonNegative(v)
    return LivingKnox.Num.finite(v) and v >= 0
end

local function rangeProblem(r)
    if type(r) ~= "table" or not nonNegative(r[1]) or not nonNegative(r[2]) or r[1] > r[2] then
        return "range must be { min, max } with 0 <= min <= max"
    end
    return nil
end

local function kindProblem(spec)
    if type(spec) ~= "table" then return "spec must be a table" end
    if type(spec.id) ~= "string" or string.match(spec.id, "^[a-z][a-z0-9_]*$") == nil then
        return "id must be a lowercase name"
    end
    if type(spec.order) ~= "number" then return spec.id .. " needs order" end
    if spec.time == nil and spec.foreign == nil then return spec.id .. " needs time or foreign" end
    if spec.time ~= nil then
        local why = rangeProblem(spec.time)
        if why then return spec.id .. ".time: " .. why end
        if type(spec.heal) ~= "table" or not nonNegative(spec.heal.open) then return spec.id .. " needs heal.open" end
    end
    for field in pairs(RATE_TABLES) do
        local t = spec[field]
        if t ~= nil then
            if type(t) ~= "table" then return spec.id .. "." .. field .. " must be a table" end
            for k, v in pairs(t) do
                if not nonNegative(v) then return spec.id .. "." .. field .. "." .. tostring(k) .. " must be >= 0" end
            end
        end
    end
    for field in pairs(NUMBER_FIELDS) do
        if spec[field] ~= nil and not nonNegative(spec[field]) then return spec.id .. "." .. field .. " must be >= 0" end
    end
    for field in pairs(FLAG_FIELDS) do
        if spec[field] ~= nil and type(spec[field]) ~= "boolean" then return spec.id .. "." .. field .. " must be a boolean" end
    end
    if spec.blood ~= nil and not (nonNegative(spec.blood) and spec.blood <= 1) then return spec.id .. ".blood must be 0..1" end
    if spec.virusRoute ~= nil and type(spec.virusRoute) ~= "string" then return spec.id .. ".virusRoute must be a name" end
    if spec.bleed ~= nil then
        if type(spec.bleed) ~= "table" then return spec.id .. ".bleed must be a list" end
        for _, term in ipairs(spec.bleed) do
            local why = rangeProblem(term)
            if why then return spec.id .. ".bleed: " .. why end
        end
    end
    local f = spec.foreign
    if f ~= nil then
        if type(f) ~= "table" or type(f.becomes) ~= "string" then return spec.id .. ".foreign needs becomes" end
        if f.time ~= nil and rangeProblem(f.time) then return spec.id .. ".foreign.time: " .. rangeProblem(f.time) end
    end
    return nil
end

local kindRegistry = LivingKnox.Registry.new("LivingKnox.Wounds.registerKind", {
    validate = function(spec)
        local why = kindProblem(spec)
        return why == nil, why
    end,
    items = Wounds.kindList, byKey = Wounds.kindById })

function Wounds.registerKind(id, spec)
    if type(spec) == "table" then spec.id = id end
    return kindRegistry:register(spec, 2)
end

function Wounds.kind(id)
    return Wounds.kindById[id]
end

function Wounds.kinds()
    return Wounds.kindList
end

-- ================================================================ outils
function Wounds.ticksPerMinute(ctx)
    local mpd = ctx ~= nil and ctx.minutesPerDay or nil
    if not (LivingKnox.Num.finite(mpd) and mpd > 0) then mpd = Wounds.MINUTES_PER_DAY end
    return Wounds.TICK_FACTOR * mpd
end

local function draw(ctx)
    if type(ctx) ~= "table" or type(ctx.rnd) ~= "function" then
        error("LivingKnox.Wounds: ctx.rnd is required", 3)
    end
    return ctx.rnd()
end

local function roll(ctx, r)
    return r[1] + (r[2] - r[1]) * draw(ctx)
end

local function severity(ctx)
    return Wounds.SEVERITY[ctx ~= nil and ctx.severity or 2] or 1
end

-- Saignement tiré pour une plaie de durée time (generateBleeding, BodyPart.java:1780-1815).
local function rollBleed(spec, time, p, ctx)
    local b = 0
    for _, term in ipairs(spec.bleed or {}) do
        local v = roll(ctx, term)
        if term.perTime then v = v * (time or 0) end
        b = b + v
    end
    return b * severity(ctx) * p.bleed
end

-- Vrai tant que la durée de guérison court.
function Wounds.hasTime(w)
    return w.time ~= nil and w.time > 0
end
local timeLeft = Wounds.hasTime

-- Vrai si la plaie est guérie : plus de corps étranger, durée finie ou points arrivés au plafond.
function Wounds.isHealed(w)
    if w.foreign then return false end
    if w.stitch ~= nil then return w.stitch >= Wounds.STITCH.max end
    return not timeLeft(w)
end

-- Vrai si la plaie porte un bandage encore propre (vie > 0, BodyPart.isBandageDirty :134-136).
function Wounds.isClean(w)
    return w.bandage ~= nil and w.bandage.life > 0
end

-- ================================================================ blessure
-- Ajoute à list une plaie de type kind sur la partie partId ; rend la plaie, ou nil et la raison.
-- opts.bleed : force (vrai) ou retire (faux) le saignement tiré. opts.time : { min, max } durée tirée à la place de
-- spec.time, pour une blessure vanilla de même type mais d'autre durée (griffure de fenêtre 12-20, BodyPart.java:857 ;
-- brûlure du feu 50-100, :1205 ; sources de LK21-T02, server/LivingKnox/Wounds/).
function Wounds.add(list, partId, kind, ctx, opts)
    local p, spec = Wounds.PART[partId], Wounds.kindById[kind]
    if p == nil then return nil, "unknown part" end
    if spec == nil then return nil, "unknown kind" end
    if #list >= Wounds.MAX_WOUNDS then return nil, "too many wounds" end
    local range = opts ~= nil and opts.time or spec.time
    if range ~= nil and rangeProblem(range) then return nil, "bad time range" end
    local w = { kind = kind, part = partId, age = 0, bleed = 0, foreign = spec.foreign ~= nil,
        infected = spec.infectedOnAdd == true, level = 0, alcohol = 0, harm = 0 }
    if spec.time ~= nil then w.time = roll(ctx, range) * severity(ctx) end
    local bleeds = opts ~= nil and opts.bleed or nil
    if bleeds == nil then bleeds = spec.bleedOnAdd ~= false end
    if bleeds then w.bleed = rollBleed(spec, w.time, p, ctx) end
    list[#list + 1] = w
    return w
end

-- ================================================================ transitions des soins (setters du vanilla)
-- Bandage posé : vie tirée par le soin (ISApplyBandage.lua:112, 0 avec un bandage sale :113-115).
function Wounds.bandage(w, life, alcoholic)
    w.bandage = { life = math.max(0, life or 0), alcohol = alcoholic == true }
end

function Wounds.unbandage(w)
    w.bandage = nil
end

-- Premier soin : chaque plaie de list qui saigne à nu reçoit un bandage sans alcool de vie tirée dans range
-- ({ min, max }) plus power (BandagePower de l'objet, 0 par défaut). Rend le saignement arrêté (fraction de la santé
-- maximale par heure) et le nombre de bandages posés. Corps incarné (LK_Health.stopBleeding) et simulation hors écran
-- (LK_MemberHealth.care) font ce même soin.
function Wounds.bandageBleeding(list, ctx, range, power)
    local stopped, count = 0, 0
    for _, w in ipairs(list) do
        local b = Wounds.woundBleeding(w, ctx)
        if b > 0 then
            Wounds.bandage(w, roll(ctx, range) + math.max(0, power or 0), false)
            stopped = stopped + b
            count = count + 1
        end
    end
    return stopped, count
end

-- Désinfectant : puissance d'alcool ajoutée (ISDisinfect.lua:71).
function Wounds.disinfect(w, power)
    w.alcohol = (w.alcohol or 0) + math.max(0, power or 0)
end

-- Points : temps de départ tiré par le soin (ISStitch.lua:119) ; le saignement et la durée s'arrêtent
-- (setStitched, BodyPart.java:876-882). Rend faux si la plaie ne se recoud pas (corps étranger d'abord,
-- ISHealthPanel.lua:1379).
function Wounds.stitch(w, stitchTime)
    local spec = w ~= nil and Wounds.kindById[w.kind] or nil
    if spec == nil or not spec.stitch or w.foreign or w.stitch ~= nil then return false end
    w.stitch = math.max(0, stitchTime or 0)
    w.time = 0
    w.bleed = 0
    return true
end

-- Attelle : facteur (docteur + 1) / 2 (ISSplint.lua:89-94).
function Wounds.splint(w, factor)
    local spec = w ~= nil and Wounds.kindById[w.kind] or nil
    if spec == nil or not spec.splint or w.splint ~= nil then return false end
    w.splint = math.max(0, factor or 0)
    return true
end

-- Retrait du corps étranger : la plaie devient spec.foreign.becomes ; avec foreign.time, nouvelle durée moins
-- docteur / 2 entier et nouveau saignement (setHaveBullet(false, docteur), BodyPart.java:1074-1097) ; sans, durée et
-- saignement gardés (setHaveGlass(false), :971-973).
function Wounds.extract(w, ctx, doctorLevel)
    local spec = w ~= nil and Wounds.kindById[w.kind] or nil
    if spec == nil or not w.foreign or spec.foreign == nil then return false end
    local f = spec.foreign
    local after = Wounds.kindById[f.becomes]
    if after == nil then return false end
    w.foreign = false
    w.kind = f.becomes
    if f.time ~= nil then
        w.time = math.max(0, (roll(ctx, f.time) - math.floor((doctorLevel or 0) / 2)) * severity(ctx))
        w.bleed = rollBleed(after, w.time, Wounds.PART[w.part], ctx)
    end
    return true
end

-- ================================================================ lectures
-- Perte de santé par saignement, en points de santé générale (0..100) par tick (BodyPart.java:161-163).
local function bleedPointsPerTick(w, bleed)
    if w.bandage ~= nil or bleed <= 0 then return 0 end
    return Wounds.BLEED_DAMAGE * Wounds.DAMAGE_SCALER * Wounds.PART[w.part].scaler * bleed / 10
end

-- Saignement d'une plaie : fraction de la santé maximale perdue par heure de jeu.
function Wounds.woundBleeding(w, ctx)
    return bleedPointsPerTick(w, w.bleed) * Wounds.ticksPerMinute(ctx) * 60 / 100
end

-- Saignement total de list : fraction de la santé maximale perdue par heure de jeu.
function Wounds.bleeding(list, ctx)
    local sum = 0
    for _, w in ipairs(list) do sum = sum + Wounds.woundBleeding(w, ctx) end
    return sum
end

local function soiled(ctx, partId)
    if ctx == nil or type(ctx.soiled) ~= "function" then return false, false end
    return ctx.soiled(partId)
end

-- Chance d'infection de la plaie par tick (BodyPart.java:219-257 et points :375, :381).
function Wounds.infectionChance(w, ctx)
    local spec = Wounds.kindById[w.kind]
    if spec == nil or w.infected or w.virus or (w.alcohol or 0) > 0 or (w.level or 0) < 0 then return 0 end
    local I, S = Wounds.INFECTION, Wounds.STITCH
    local bandaged = w.bandage ~= nil
    local life = bandaged and w.bandage.life or 0
    if bandaged and w.bandage.alcohol and life > 0 then return 0 end
    local p = 0
    if (spec.infect ~= nil and timeLeft(w)) or w.stitch ~= nil then
        local c = I.base
        if not bandaged then c = c - I.open elseif life <= 0 then c = c - I.dirty end
        if timeLeft(w) then c = c - (spec.infect or 0) end
        if w.foreign then c = c - (spec.foreignInfect or 0) end
        local dirty, bloody = soiled(ctx, w.part)
        if dirty then c = c - I.dirtyClothes end
        if bloody then c = c - I.bloodyClothes end
        if c <= I.floor then c = I.floor end
        p = 1 / c
    end
    if w.stitch ~= nil and w.stitch < S.max then
        if not bandaged then p = p + 1 / S.openChance
        elseif not w.bandage.alcohol then p = p + 1 / S.bandagedChance end
    end
    return p * Wounds.ROLLS_PER_TICK
end

-- Douleur de list (BodyPart.getPain :903-937, sans les modificateurs de partie ni d'option).
function Wounds.pain(list)
    local sum = 0
    for _, w in ipairs(list) do
        local spec = Wounds.kindById[w.kind]
        local pain = spec ~= nil and spec.pain or nil
        local v, bandaged = 0, w.bandage ~= nil
        if pain ~= nil and timeLeft(w) then
            local k = (w.splint ~= nil and pain.splinted) or 1
            v = v + (pain.perTime or 0) * w.time * k
            if bandaged and pain.bandaged ~= nil then v = v + pain.bandaged else v = v + (pain.open or 0) end
        end
        if pain ~= nil and w.foreign then v = v + (pain.foreign or 0) end
        if w.stitch ~= nil and w.stitch < 35 then v = v + (bandaged and (35 - w.stitch) / 2 or 35 - w.stitch) end
        if bandaged then v = v / 1.5 end
        if (w.level or 0) > 0 then v = v + w.level end
        sum = sum + v
    end
    return sum
end

-- Sang visible par BloodBodyPartType (0..1) : poids du type, double tant que la plaie saigne à nu (le vanilla ajoute
-- du sang au hasard pendant le saignement, BodyPart.java:164-166). Valeurs explicites pour LK21-T09.
function Wounds.blood(list)
    local out = {}
    for _, w in ipairs(list) do
        local spec, p = Wounds.kindById[w.kind], Wounds.PART[w.part]
        if spec ~= nil and p ~= nil and (spec.blood or 0) > 0 then
            local v = spec.blood
            if w.bleed > 0 and w.bandage == nil then v = v * 2 end
            out[p.blood] = math.min(1, (out[p.blood] or 0) + v)
        end
    end
    return out
end

-- ================================================================ évolution (D01)
local EPS = 1e-9

local function healRate(w, spec, bandaged)
    local h = spec.heal or {}
    if w.splint ~= nil and h.splinted ~= nil then return h.splinted * w.splint end
    if bandaged and h.bandaged ~= nil then return h.bandaged end
    return h.open or 0
end

local function timeFloor(w, spec, bandaged)
    local f, fl = 0, spec.floor
    if fl == nil then return 0 end
    if w.foreign and fl.foreign ~= nil then f = math.max(f, fl.foreign) end
    if not bandaged and fl.open ~= nil then f = math.max(f, fl.open) end
    return f
end

local function bleedFloor(w, spec)
    if w.foreign and spec.bleedFloor ~= nil and spec.bleedFloor.foreign ~= nil then return spec.bleedFloor.foreign end
    return 0
end

local function damageRate(w, spec, bandaged)
    local d = spec.damage
    if d == nil or not (timeLeft(w) or w.foreign) then return 0 end
    if w.splint ~= nil and d.splinted ~= nil then return d.splinted end
    if bandaged then return d.bandaged or 0 end
    return d.open or 0
end

-- Usure du bandage par tick (BodyPart.java:185, :193, :205-208, :304, :309, :330, :350, :374).
local function wearRate(w, spec)
    local wear = 0
    if timeLeft(w) then wear = wear + (spec.wear or 0) end
    if w.bleed > 0 then wear = wear + ((timeLeft(w) and spec.bleedWear) or Wounds.BLEED_WEAR) end
    if w.stitch ~= nil and w.stitch < Wounds.STITCH.max then wear = wear + Wounds.STITCH.wear end
    if w.infected then wear = wear + Wounds.INFECTION.wear end
    return wear
end

-- Variation du niveau d'infection par tick d'une plaie infectée (BodyPart.java:258-302).
local function levelRate(w, spec)
    local I = Wounds.INFECTION
    local r
    if w.alcohol > 0 then r = -I.alcohol
    elseif w.virus then r = I.virus
    elseif w.foreign and spec.infectGrowth ~= nil then r = spec.infectGrowth
    else r = I.grow end
    if w.bandage ~= nil and w.bandage.alcohol and w.bandage.life > 0 then r = r - I.alcoholBandage end
    return r
end

-- Fait évoluer la plaie w pendant ticks ; ajoute pertes et infections à out. partHarm : dégâts par partie.
local function evolve(w, spec, ticks, tpm, ctx, partHarm, out)
    local p = Wounds.PART[w.part]
    local scaler = Wounds.DAMAGE_SCALER * p.scaler
    local I, S = Wounds.INFECTION, Wounds.STITCH
    local left, guard = ticks, 0
    while left > EPS and guard < 100000 and not Wounds.isHealed(w) do
        guard = guard + 1
        local bandaged = w.bandage ~= nil
        local life = bandaged and w.bandage.life or 0
        -- Planchers posés au début du segment (BodyPart.java:213-215, :361-363).
        local tFloor = timeFloor(w, spec, bandaged)
        if timeLeft(w) and w.time < tFloor then w.time = tFloor end
        local bFloor = bleedFloor(w, spec)
        if w.bleed > 0 and w.bleed < bFloor then w.bleed = bFloor end
        if w.infected and w.level <= 0 and levelRate(w, spec) < 0 then
            w.infected = false   -- guérie (setWoundInfectionLevel :1192-1198)
            w.level = math.max(I.min, w.level)
        end
        local dt = math.min(left, Wounds.SEGMENT_MINUTES * tpm)
        local tRate = 0
        if timeLeft(w) and w.time > tFloor then
            tRate = healRate(w, spec, bandaged)
            if tRate > 0 then dt = math.min(dt, (w.time - tFloor) / tRate) end
        end
        local bRate = 0
        if w.bleed > bFloor then
            bRate = bandaged and Wounds.BLEED_HEAL.bandaged or Wounds.BLEED_HEAL.open
            dt = math.min(dt, (w.bleed - bFloor) / bRate)
        end
        local sRate = 0
        if w.stitch ~= nil and w.stitch < S.max then
            sRate = bandaged and S.bandaged or S.open
            dt = math.min(dt, (S.max - w.stitch) / sRate)
        end
        local wear = 0
        if bandaged and life > 0 then
            wear = wearRate(w, spec)
            if wear > 0 then dt = math.min(dt, life / wear) end
        end
        local aRate = 0
        if w.alcohol > 0 then
            aRate = I.alcohol
            dt = math.min(dt, w.alcohol / aRate)
        end
        local lRate = 0
        if w.infected then
            lRate = levelRate(w, spec)
            if lRate < 0 then dt = math.min(dt, w.level / -lRate)
            elseif lRate > 0 and w.level < I.max then dt = math.min(dt, (I.max - w.level) / lRate)
            else lRate = 0 end
        end
        local dRate = damageRate(w, spec, bandaged) * scaler
        local room = 100 - (partHarm[w.part] or 0)
        if dRate > 0 and room > EPS then dt = math.min(dt, room / dRate) else dRate = 0 end
        local chance = Wounds.infectionChance(w, ctx)
        if dt <= 0 then dt = math.min(left, EPS * 10) end

        -- Segment : vitesses constantes, saignement linéaire (perte exacte par la moyenne).
        local b1 = w.bleed - bRate * dt
        if bRate > 0 and b1 - bFloor < EPS then b1 = bFloor end
        out.bled = out.bled + (bleedPointsPerTick(w, w.bleed) + bleedPointsPerTick(w, b1)) / 2 * dt
        w.bleed = math.max(0, b1)
        if tRate > 0 then
            w.time = w.time - tRate * dt
            if w.time - tFloor < EPS then w.time = tFloor end
        end
        if sRate > 0 then w.stitch = math.min(S.max, w.stitch + sRate * dt) end
        if S.max - (w.stitch or 0) < EPS and w.stitch ~= nil then w.stitch = S.max end
        if wear > 0 then
            w.bandage.life = life - wear * dt
            if w.bandage.life < EPS then w.bandage.life = 0 end
        end
        if aRate > 0 then
            w.alcohol = w.alcohol - aRate * dt
            if w.alcohol < EPS then w.alcohol = 0 end
        end
        if lRate ~= 0 then
            w.level = math.min(I.max, w.level + lRate * dt)
            if lRate < 0 and w.level < EPS then w.level = 0 end
        end
        if dRate > 0 then
            local harm = math.min(room, dRate * dt)
            w.harm = w.harm + harm
            partHarm[w.part] = (partHarm[w.part] or 0) + harm
            out.harmed = out.harmed + harm * p.damage
        end
        if chance > 0 then
            local prob = 1 - (1 - chance) ^ dt
            if draw(ctx) < prob then
                w.infected = true
                out.infectedNow[#out.infectedNow + 1] = w
            end
        end
        left = left - dt
    end
end

-- Parties tenues : celles qu'une plaie abîme encore (dégâts par tick > 0, BodyPart.DamageUpdate :145-181).
local function heldParts(list)
    local held = {}
    for _, w in ipairs(list) do
        local spec = Wounds.kindById[w.kind]
        if spec ~= nil and damageRate(w, spec, w.bandage ~= nil) > 0 then held[w.part] = true end
    end
    return held
end

-- Santé générale au plus (fraction de la santé maximale) : les dégâts des parties tenues ne se régénèrent pas tant
-- que leur plaie les abîme (calculateOverallHealth, BodyDamage.java:2079-2089).
function Wounds.healthCap(list)
    local held, lost = heldParts(list), 0
    for _, w in ipairs(list) do
        if held[w.part] then lost = lost + (w.harm or 0) * Wounds.PART[w.part].damage end
    end
    return math.max(0, 1 - lost / 100)
end

-- Santé générale rendue en minutes de jeu (fraction de la santé maximale), REGEN par tick (en-tête) :
--   general vrai (perte générale à rattraper) : réparti sur les 17 parties, pondéré par leur part de la santé générale,
--   sans les parties tenues ;
--   general faux : partagé entre les parties tenues, retiré des dégâts (harm) de leurs plaies (list est modifiée).
function Wounds.regeneration(list, minutes, ctx, general)
    if not (LivingKnox.Num.finite(minutes) and minutes > 0) then return 0 end
    local ticks = minutes * Wounds.ticksPerMinute(ctx)
    local held = heldParts(list)
    local gain = 0
    if general then
        local weight = 0
        for _, p in ipairs(Wounds.PARTS) do
            if not held[p.id] then weight = weight + p.damage end
        end
        return Wounds.REGEN * ticks * weight / #Wounds.PARTS / 100
    end
    local n = 0
    for _ in pairs(held) do n = n + 1 end
    if n == 0 then return 0 end
    for partId in pairs(held) do
        local left = Wounds.REGEN * ticks / n
        for _, w in ipairs(list) do
            if w.part == partId and left > 0 and (w.harm or 0) > 0 then
                local back = math.min(left, w.harm)
                w.harm = w.harm - back
                left = left - back
                gain = gain + back * Wounds.PART[partId].damage
            end
        end
    end
    return gain / 100
end

-- Malus « malade » des plaies infectées, option WoundInfectionFactor seulement (en-tête ; lu en fin de période).
local function sickness(list, ticks, ctx)
    local factor = ctx ~= nil and ctx.woundInfectionFactor or 0
    if not (LivingKnox.Num.finite(factor) and factor > 0) then return 0 end
    local level = 0
    for _, w in ipairs(list) do
        if w.infected then level = level + w.level end
    end
    if math.min(100, level * 10 * factor) <= Wounds.SICK.threshold then return 0 end
    return Wounds.SICK.damage * ticks
end

-- Fait évoluer list pendant minutes de jeu ; retire les plaies guéries. Rend { hpLoss = fraction de la santé maximale
-- perdue, bled, harmed, sick (points de santé 0..100 par cause), healed = { plaies retirées }, infectedNow = { plaies
-- infectées pendant la période } }.
function Wounds.advance(list, minutes, ctx)
    local out = { hpLoss = 0, bled = 0, harmed = 0, sick = 0, healed = {}, infectedNow = {} }
    if not (LivingKnox.Num.finite(minutes) and minutes > 0) then return out end
    local tpm = Wounds.ticksPerMinute(ctx)
    local ticks = minutes * tpm
    local partHarm = {}
    for _, w in ipairs(list) do partHarm[w.part] = (partHarm[w.part] or 0) + (w.harm or 0) end
    for _, w in ipairs(list) do
        local spec = Wounds.kindById[w.kind]
        if spec ~= nil then evolve(w, spec, ticks, tpm, ctx, partHarm, out) end
        w.age = w.age + minutes
    end
    out.sick = sickness(list, ticks, ctx)
    for i = #list, 1, -1 do
        if Wounds.kindById[list[i].kind] ~= nil and Wounds.isHealed(list[i]) then
            table.insert(out.healed, 1, list[i])
            table.remove(list, i)
        end
    end
    out.hpLoss = (out.bled + out.harmed + out.sick) / 100
    return out
end

return Wounds
