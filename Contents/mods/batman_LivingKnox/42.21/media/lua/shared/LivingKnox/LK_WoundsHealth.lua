-- Living Knox : santé générale d'un corps qui porte des plaies (LK21-T03, ADR docs/architecture/decisions/
-- adr-blessures-soins.md, D01). Une seule copie de la formule, appelée par le corps incarné (LK_Health, santé en points
-- rapportée à hpMax) et par la simulation hors écran (LK_MemberHealth, santé d'un membre en fraction).
--
-- Pur : aucun appel au jeu. Santé en fraction de la santé maximale (0..1). Règles du modèle (LK_Wounds.lua) :
--   1. Wounds.advance fait évoluer les plaies (saignement, dégâts de partie, guérison, bandage, infection) ; la santé
--      baisse de hpLoss ;
--   2. puis elle remonte comme celle d'un joueur éveillé et nourri du vanilla (Wounds.regeneration,
--      J/characters/BodyDamage/BodyDamage.java:1887-1928), sans dépasser ce que les plaies tiennent encore
--      (Wounds.healthCap) quand une perte générale reste à rattraper ; jamais au-dessus de 1 ;
--   3. la régénération ne baisse jamais la santé.
-- Une santé rendue à 0 ou moins : mort (décidée par l'appelant).
require "LivingKnox/LK_Wounds"

local Wounds = LivingKnox.Wounds

-- Fait évoluer les plaies list pendant minutes de jeu et rend la nouvelle santé (fraction, <= 0 : mort) et le bilan de
-- Wounds.advance. health : santé avant (fraction). regen faux : aucune régénération (PNJ affamé, le vanilla ne
-- régénère pas un joueur qui meurt de faim) ; nil ou vrai : régénération du vanilla.
function Wounds.healthStep(list, health, minutes, ctx, regen)
    local out = Wounds.advance(list, minutes, ctx)
    local lowered = health - out.hpLoss
    local h = lowered
    if h > 0 and regen ~= false then
        local cap = Wounds.healthCap(list)
        local general = h < cap - 1e-9
        local gain = Wounds.regeneration(list, minutes, ctx, general)
        if general then h = math.min(cap, h + gain) else h = math.min(1, h + gain) end
        if h < lowered then h = lowered end
    end
    return h, out
end

return Wounds
