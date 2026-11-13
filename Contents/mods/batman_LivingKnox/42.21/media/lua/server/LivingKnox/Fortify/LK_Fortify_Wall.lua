-- Living Knox : sorte de chantier « wall » (LK14-T04, inscrite en LK16-T02) : mur en bois vanilla sur le pourtour d'un
-- foyer en bâtiment, en deux étapes (cadre WoodenWallFrame puis mur WoodenWallLvl1), marteau
-- (M/scripts/generated/entities/walls/entity_woodenwallframe.txt:33-43, entity_wood_walllvl1.txt:37-47). Réparation :
-- définition « Wood » des murs en bois (M/lua/shared/Moveables/ISMoveableDefinitions.lua:656-668 : marteau et scie,
-- pièce requise, une pièce facultative, la première présente en quantité ; ISMoveableSpriteProps.lua:3574-3599).
-- Moteur : LK_Fortify.lua (pose Fortify.buildStep, réparation Fortify.repairStructure, rattrapage hors écran
-- Fortify.STAGE_OFFSCREEN). Forme compacte du relevé hors écran : lettre « w ».
if isClient() then return end

require "LivingKnox/LK_Fortify"

local Fortify = LivingKnox.Fortify
local req = Fortify.req

Fortify.registerKind({ id = "wall", code = "w", order = 20, unit = "stage(s)", ring = "building",
    work = function(site, c) return Fortify.stageWork(site, c) end,
    stages = {
        { entity = "WoodenWallFrame", sprites = { W = "carpentry_02_100", N = "carpentry_02_101" }, time = "frame",
            materials = { req({ Fortify.PLANK }, 2), req({ Fortify.NAILS }, 2) }, tool = "HAMMER" },
        { entity = "WoodenWallLvl1", prev = "WoodenWallFrame",
            sprites = { W = "walls_exterior_wooden_01_44", N = "walls_exterior_wooden_01_45" }, time = "wall",
            materials = { req({ Fortify.PLANK }, 2), req({ Fortify.NAILS }, 4) }, tool = "HAMMER" },
    },
    -- Noms d'objet (getName) des murs en bois vanilla reconnus sur un bord : étapes faites.
    names = { WoodenWallFrame = 1, WoodenWallLvl1 = 2, WoodenWallLvl2 = 2, WoodenWallLvl3 = 2 },
    repair = { tools = { "HAMMER", "SAW" }, part = { Fortify.PLANK, 2 },
        options = { { Fortify.NAILS, 4 }, { "Base.Screws", 4 } },
        run = function(site, gid, who) return Fortify.repairStructure(site, gid, who) end },
    offscreen = Fortify.STAGE_OFFSCREEN,
})
