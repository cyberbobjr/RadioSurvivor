-- Living Knox : sorte de chantier « palisade » (LK14-T04, inscrite en LK16-T02) : palissade de rondins vanilla (LogWall)
-- sur le pourtour d'un camp, une étape, 4 rondins et 4 liens, sans outil
-- (M/scripts/generated/entities/walls/entity_logwall.txt:33-41). Réparation : définition « Log »
-- (M/lua/shared/Moveables/ISMoveableDefinitions.lua:656-668 ; « Tag.Rope » réduit ici à Base.Rope). Moteur :
-- LK_Fortify.lua (pose Fortify.buildStep, réparation Fortify.repairStructure, rattrapage hors écran
-- Fortify.STAGE_OFFSCREEN). Forme compacte du relevé hors écran : lettre « p ».
if isClient() then return end

require "LivingKnox/LK_Fortify"

local Fortify = LivingKnox.Fortify
local req = Fortify.req

Fortify.registerKind({ id = "palisade", code = "p", order = 30, unit = "stage(s)", ring = "camp",
    work = function(site, c) return Fortify.stageWork(site, c) end,
    stages = {
        { entity = "LogWall", sprites = { W = "carpentry_02_80", N = "carpentry_02_81" }, time = "palisade",
            materials = { req({ Fortify.LOG }, 4), req(Fortify.TIES, 4) } },
    },
    names = { LogWall = 1 },
    repair = { tools = { "HAMMER", "SAW" }, part = { Fortify.LOG, 2 },
        options = { { Fortify.NAILS, 4 }, { "Base.Screws", 2 }, { "Base.RippedSheets", 4 }, { "Base.Sheet", 2 },
            { "Base.Rope", 2 } },
        run = function(site, gid, who) return Fortify.repairStructure(site, gid, who) end },
    offscreen = Fortify.STAGE_OFFSCREEN,
})
