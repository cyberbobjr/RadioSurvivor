-- Living Knox : type de groupe « colons » (LK08-T02), données seules. Format : LK_GroupTypes.lua ; valeurs et
-- raisons : docs/conception/groupes.md, section « Types et profils ».
-- Colons amicaux installés dans un vrai bâtiment (décision LK00 du 2026-10-03) : peu hostiles, bien pourvus.
-- Format 2 (E08-T06) : un poste émetteur au foyer (homeRadio) : le groupe est une voix du réseau radio tant qu'un
-- membre vivant y est présent (docs/conception/radio-groupes.md).
require "LivingKnox/LK_GroupTypes"

LivingKnox.GroupTypes.register({
    format = 2,
    id = "settlers",
    nameKey = "IGUI_LK_GroupType_settlers",
    size = { min = 4, max = 8 },
    hostility = 10,
    home = "building",
    homeRadio = true,
    morale = 60,
    needs = { food = 55, medical = 50, ammo = 40 },
    roles = {
        deputy = { weight = 1, behaviours = { "guard", "defend", "fight", "talk", "trade" } },
        fighter = { weight = 3, behaviours = { "guard", "patrol", "defend", "fight", "expedition" } },
        scout = { weight = 2, behaviours = { "scout", "expedition", "scavenge", "forage" } },
        medic = { weight = 1, behaviours = { "heal", "cook", "chores", "talk" } },
        worker = { weight = 4, behaviours = { "chores", "cook", "maintain", "garden", "forage", "fish", "fortify" } },
    },
    profiles = {
        { id = "second", role = "deputy", weight = 10, max = 1, weapons = { "Base.Shotgun", "Base.Pistol" } },
        { id = "guard", role = "fighter", weight = 30, weapons = { "Base.HuntingRifle", "Base.Shotgun",
            "Base.BaseballBat" } },
        { id = "scout", role = "scout", weight = 20, weapons = { "Base.HuntingKnife", "Base.Pistol" },
            traits = { { id = "keenHearing", chance = 40 } } },
        { id = "doctor", role = "medic", weight = 10, max = 1, weapons = { "Base.KitchenKnife" },
            traits = { { id = "tidy", chance = 30 } } },
        { id = "farmer", role = "worker", weight = 30, outfits = { "Generic01", "Generic03" },
            weapons = { "Base.Shovel", "Base.HandAxe" }, traits = { { id = "smoker", chance = 15 } } },
        { id = "handyman", role = "worker", weight = 15, weapons = { "Base.Hammer", "Base.Wrench" } },
    },
})
