-- Living Knox : type de groupe « solitaires » (E10-T04), données seules. Format : LK_GroupTypes.lua ; valeurs et
-- raisons : docs/annexes/conception/depart.md.
-- Groupe d'un seul membre formé par un PNJ incarné qui quitte son groupe (intention leave_group du carnet, décision Q3
-- du 2026-10-10 : solitaire durable, avec son abri, simulé hors écran). Jamais tiré par la population : aucune option
-- de poids (LK_Config.TYPE_WEIGHT_OPTIONS) ne le nomme, et un solitaire disparu n'appelle aucune relève. Taille 1 :
-- aucune recrue de la simulation (LK_Simulation.recruitRoom), aucun départ hors écran. Hostilité de départ neutre (50 :
-- attitude de départ 0, « cautious »). Le membre garde son rôle : chaque rôle est déclaré, avec les mêmes comportements
-- d'une vie seule (ni rondes ni pillage) ; les profils ne servent qu'au format (un solitaire n'est jamais tiré).
require "LivingKnox/LK_GroupTypes"

local ALONE = { "guard", "defend", "fight", "scavenge", "forage", "fish", "cook", "chores", "maintain", "fortify",
    "talk", "trade" }

LivingKnox.GroupTypes.register({
    format = 1,
    id = "loners",
    nameKey = "IGUI_LK_GroupType_loners",
    size = { min = 1, max = 1 },
    hostility = 50,
    home = "building",
    morale = 50,
    needs = { food = 50, medical = 50, ammo = 50 },
    roles = {
        deputy = { weight = 1, behaviours = ALONE },
        fighter = { weight = 1, behaviours = ALONE },
        scout = { weight = 1, behaviours = ALONE },
        medic = { weight = 1, behaviours = ALONE },
        worker = { weight = 1, behaviours = ALONE },
        breaker = { weight = 1, behaviours = ALONE },
    },
    profiles = {
        { id = "loner_deputy", role = "deputy", weight = 1 },
        { id = "loner_fighter", role = "fighter", weight = 1 },
        { id = "loner_scout", role = "scout", weight = 1 },
        { id = "loner_medic", role = "medic", weight = 1 },
        { id = "loner_worker", role = "worker", weight = 1 },
        { id = "loner_breaker", role = "breaker", weight = 1 },
    },
})
