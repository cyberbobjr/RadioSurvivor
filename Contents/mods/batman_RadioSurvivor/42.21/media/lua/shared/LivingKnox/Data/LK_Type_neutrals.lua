-- Living Knox : type de groupe « neutres » (LK08-T02), données seules. Format : LK_GroupTypes.lua ; valeurs et
-- raisons : docs/conception/groupes.md, section « Types et profils ».
-- Groupe neutre méfiant installé dans un vrai bâtiment (décision LK00 du 2026-10-03) : petit, prudent.
require "LivingKnox/LK_GroupTypes"

LivingKnox.GroupTypes.register({
    format = 1,
    id = "neutrals",
    nameKey = "IGUI_LK_GroupType_neutrals",
    size = { min = 4, max = 6 },
    hostility = 45,
    home = "building",
    morale = 50,
    needs = { food = 50, medical = 45, ammo = 45 },
    roles = {
        deputy = { weight = 1, behaviours = { "guard", "defend", "fight", "talk", "trade" } },
        fighter = { weight = 2, behaviours = { "guard", "patrol", "defend", "fight" } },
        scout = { weight = 2, behaviours = { "scout", "expedition", "scavenge", "forage" } },
        medic = { weight = 1, behaviours = { "heal", "chores", "cook" } },
        worker = { weight = 3, behaviours = { "chores", "cook", "maintain", "forage", "fish", "fortify", "trade" } },
    },
    profiles = {
        { id = "elder", role = "deputy", weight = 10, max = 1, weapons = { "Base.Revolver" },
            traits = { { id = "smoker", chance = 30 } } },
        { id = "hunter", role = "fighter", weight = 25, weapons = { "Base.HuntingRifle", "Base.VarmintRifle",
            "Base.HuntingKnife" } },
        { id = "lookout", role = "scout", weight = 20, weapons = { "Base.HuntingKnife" },
            traits = { { id = "keenHearing", chance = 40 }, { id = "nervous", chance = 25 } } },
        { id = "nurse", role = "medic", weight = 10, max = 1, traits = { { id = "tidy", chance = 40 } } },
        { id = "drifter", role = "worker", weight = 35, weapons = { "Base.HandAxe", "Base.Crowbar", "Base.Plank" },
            traits = { { id = "drinker", chance = 15 } } },
    },
})
