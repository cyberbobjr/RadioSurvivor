-- Living Knox : source de blessure « zombie » (attaque d'un zombie vanilla sur un PNJ), inscrite au registre des
-- sources (LK21-T02, ADR adr-blessures-soins.md D03). Règles de BodyDamage.AddRandomDamageFromZombie,
-- J/characters/BodyDamage/BodyDamage.java (42.22) :
--   - type : l'issue est décidée avant, par LK_Zombies.outcome (mêmes chances du vanilla : coup évité, lacération si
--     Rand.Next(100) > 65, morsure si Rand.Next(100) > 85, :1107-1116, :1232-1239) et passée dans hit.issue ;
--     griffure -> scratch (SetScratched, sans saignement, :1275), lacération -> laceration (SetCut, :1311), morsure
--     -> bite (SetBitten, :1346). Sans issue donnée : mêmes tirages, un attaquant, de face (seuils de
--     Config.ZOMBIES s'il est chargé, sinon griffure) ;
--   - partie, zombie debout (:1178-1206) : 1 fois sur 10 de Hand_L à Groin, sinon de Hand_L à Neck ; tête ou cou :
--     au-delà de 70 sur 100 (attaque de face), partie retirée de Hand_L à Torso_Lower (:1191-1204) ;
--   - partie, zombie rampant (:1208-1209) : 1 fois sur 10 de Groin à Foot_R, sinon de UpperLeg_L à Foot_R. Le vanilla
--     rate une fois sur 2 (:1210-1211) : le coup est déjà décidé par LK_Zombies, ce tirage n'est pas refait.
-- Virus de Knox (LK21-T04) : chaque plaie du coup peut le transmettre selon son type et les options du jeu
-- (LivingKnox.Virus.fromWounds, shared/LivingKnox/LK_Virus.lua ; SetBitten :616-623, generateZombieInfection
-- J/characters/BodyDamage/BodyPart.java:705-717).
-- Écarts : côté (dos, flanc), nombre d'attaquants pour le cou et défense des vêtements non repris (un PNJ n'a pas
-- de BodyDamage ni de défense de vêtements par partie).
require "LivingKnox/LK_WoundSources"
require "LivingKnox/LK_Virus"

local Wounds = LivingKnox.Wounds

local function isZombie(o)
    return o ~= nil and instanceof(o, "IsoZombie") and not instanceof(o, "IsoPlayer")
end

-- Issue d'une attaque qui porte, sans issue donnée : tirages du vanilla pour un attaquant de face.
local function rolledIssue(ctx)
    local c = LivingKnox.Config.ZOMBIES
    if c == nil then return "scratch" end
    local laceration = ctx.rnd() * 100 > c.LACERATION   -- même ordre de tirage que le vanilla (:1232, :1236)
    local bite = ctx.rnd() * 100 > c.BITE
    if bite then return "bite" end
    if laceration then return "laceration" end
    return "scratch"
end

local function standingPart(ctx)
    local part
    if Wounds.oneIn(ctx, 10) then part = Wounds.partBetween(ctx, "Hand_L", "Groin")
    else part = Wounds.partBetween(ctx, "Hand_L", "Neck") end
    if (part == "Head" or part == "Neck") and ctx.rnd() * 100 >= 71 then
        part = Wounds.partBetween(ctx, "Hand_L", "Torso_Lower")
    end
    return part
end

local function crawlingPart(ctx)
    if Wounds.oneIn(ctx, 10) then return Wounds.partBetween(ctx, "Groin", "Foot_R") end
    return Wounds.partBetween(ctx, "UpperLeg_L", "Foot_R")
end

Wounds.registerSource("zombie", {
    order = 10,
    match = function(hit)
        return hit.weapon == nil and isZombie(hit.attacker)
    end,
    wounds = function(hit, ctx)
        local kind = hit.issue
        if kind == nil or Wounds.kind(kind) == nil then kind = rolledIssue(ctx) end
        local crawling = isZombie(hit.attacker) and hit.attacker:isCrawling()
        local part = crawling and crawlingPart(ctx) or standingPart(ctx)
        return { { part = part, kind = kind } }
    end,
    after = function(list, added, _, ctx)
        LivingKnox.Virus.fromWounds(list, added, ctx)
    end,
})
