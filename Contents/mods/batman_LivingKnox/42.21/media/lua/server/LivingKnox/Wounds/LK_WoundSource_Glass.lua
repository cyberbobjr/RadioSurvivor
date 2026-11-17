-- Living Knox : source de blessure « glass » (verre brisé), inscrite au registre des sources (LK21-T02, ADR
-- adr-blessures-soins.md D03, règle « Verre brisé » de l'utilisateur, 2026-11-17). Enjamber une fenêtre brisée dont
-- le verre n'a pas été retiré (42.22) :
--   - 1 fois sur 2, blessure (ClimbThroughWindowState, J/ai/states/ClimbThroughWindowState.java:532-534) : ce
--     tirage est celui de « chance », fait ici (hit.risk = faux pour le sauter, la blessure est alors certaine) ;
--   - partie tirée de Hand_L à ForeArm_R (BodyDamage.setScratchedWindow, J/characters/BodyDamage/BodyDamage.java:
--     1631-1638) ; le vanilla y ajoute AddDamage(10) sur la partie : dégâts à passer par l'appelant (montant du coup) ;
--   - plaie (BodyPart.SetScratchedWindow, J/characters/BodyDamage/BodyPart.java:846-873) : 1 fois sur 7 une plaie
--     profonde avec éclats (generateDeepShardWound, :796-815, type « glass »), sinon une griffure de 12-20 qui
--     saigne (generateBleeding, :857, :872).
-- Sans match : appelée par son nom (hit.source = "glass"), par le passage d'une fenêtre (LK21-T12).
require "LivingKnox/LK_WoundSources"

local Wounds = LivingKnox.Wounds

Wounds.registerSource("glass", {
    order = 60,
    chance = 2,
    deepChance = 7,
    scratchTime = { 12, 20 },
    wounds = function(hit, ctx)
        local spec = Wounds.source("glass")
        if hit.risk ~= false and not Wounds.oneIn(ctx, spec.chance) then return {} end
        local part = Wounds.partBetween(ctx, "Hand_L", "ForeArm_R")
        if Wounds.oneIn(ctx, spec.deepChance) then return { { part = part, kind = "glass" } } end
        return { { part = part, kind = "scratch", opts = { time = spec.scratchTime, bleed = true } } }
    end,
})
