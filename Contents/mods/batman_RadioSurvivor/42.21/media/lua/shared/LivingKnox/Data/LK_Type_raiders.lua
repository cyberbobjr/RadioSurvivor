-- Living Knox : type de groupe « pillards » (LK08-T02), données seules. Format : LK_GroupTypes.lua ; valeurs et
-- raisons : docs/conception/groupes.md, section « Types et profils ».
-- Pillards hostiles installés dans un camp en forêt (décision LK00 du 2026-10-03) : armés, peu de soins.
-- Format 2 (E08-T10, décision de l'utilisateur du 2026-10-14) : un poste émetteur au camp (homeRadio), comme les
-- colons : le groupe est une voix du réseau radio tant qu'un membre vivant y est présent (docs/conception/
-- radio-groupes.md).
require "LivingKnox/LK_GroupTypes"

LivingKnox.GroupTypes.register({
    format = 2,
    id = "raiders",
    nameKey = "IGUI_LK_GroupType_raiders",
    size = { min = 4, max = 8 },
    hostility = 90,
    home = "forest",
    homeRadio = true,
    morale = 50,
    needs = { food = 40, medical = 30, ammo = 50 },
    roles = {
        deputy = { weight = 1, behaviours = { "raid", "fight", "guard", "talk" } },
        fighter = { weight = 5, behaviours = { "raid", "fight", "guard", "patrol", "defend" } },
        scout = { weight = 2, behaviours = { "scout", "raid", "scavenge" } },
        breaker = { weight = 2, behaviours = { "breach", "raid", "fight" } },
        worker = { weight = 1, behaviours = { "chores", "cook", "forage" } },
    },
    profiles = {
        { id = "lieutenant", role = "deputy", weight = 10, max = 1, weapons = { "Base.Revolver", "Base.Pistol" } },
        { id = "thug", role = "fighter", weight = 40, weapons = { "Base.BaseballBat", "Base.Machete",
            "Base.LeadPipe" }, traits = { { id = "drinker", chance = 25 } } },
        { id = "gunman", role = "fighter", weight = 15, max = 2, weapons = { "Base.Shotgun", "Base.VarmintRifle" } },
        { id = "lookout", role = "scout", weight = 20, weapons = { "Base.HuntingKnife" },
            traits = { { id = "keenHearing", chance = 60 } } },
        { id = "breaker", role = "breaker", weight = 15, max = 2, weapons = { "Base.Sledgehammer", "Base.Axe",
            "Base.Crowbar" }, traits = { { id = "strong", chance = 50 } } },
        { id = "camp_hand", role = "worker", weight = 10, max = 1, weapons = { "Base.KitchenKnife",
            "Base.MeatCleaver" }, traits = { { id = "smoker", chance = 40 } } },
    },
})
