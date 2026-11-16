-- Living Knox : tâche « seeds » (LK15-T06, ADR registre des routines D08, Q01 ; décision de l'utilisateur du
-- 2026-11-13 : les graines du jardinier arrivent automatiquement). Un groupe qui a un jardinier (rôle portant le
-- comportement « garden ») et moins de Garden.CFG.SEED_LOW graines semables au foyer reçoit un sachet
-- (Garden.CFG.SEED_PACKET graines d'une variété de saison, LK_Garden.seedVariety), au plus une fois tous les
-- Garden.CFG.SEED_DAYS jours de jeu : un membre (ordre du registre, jardinier compris) va au conteneur de dépôt et
-- l'y range. Tâche du registre plutôt qu'un dépôt sans geste : le sachet arrive par la main d'un membre, à l'écran,
-- et seulement quand le foyer est chargé (relevé et effet du moteur LK_Upkeep.lua). Effet : LK_Garden.receiveSeeds
-- (conteneur, clients, référence du stock). Conditions relues au moment de l'effet.
if isClient() then return end

require "LivingKnox/LK_Upkeep"
require "LivingKnox/LK_Garden"

local Upkeep = LivingKnox.Upkeep
local Garden = LivingKnox.Garden

Upkeep.stats.seedPackets = Upkeep.stats.seedPackets or 0
Upkeep.stats.seedsReceived = Upkeep.stats.seedsReceived or 0

local function today() return LivingKnox.Groups.today() end

-- Conteneur de dépôt et bâtiment de sa case (place à côté dans le même bâtiment), ou nil.
local function depotOf(gid, g)
    local depot = Garden.depotOf(gid, g.home)
    if depot == nil then return nil end
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(depot.x, depot.y, depot.z) or nil
    local bid = sq ~= nil and LivingKnox.Homes.buildingId(sq) or nil
    return depot, bid
end

local function survey(gid, g, area)
    if Garden.seedOffer(gid, g, today(), Garden.month()) == nil then return nil end
    local depot, bid = depotOf(gid, g)
    if depot == nil then return nil end
    return { { x = depot.x, y = depot.y, bid = bid } }
end

local function apply(job, gid, who, sq)
    local g = LivingKnox.Groups.get(gid)
    if g == nil or type(g.home) ~= "table" then return nil, "no home" end
    local day = today()
    local offer, why = Garden.seedOffer(gid, g, day, Garden.month())
    if offer == nil then return nil, why end
    local depot = depotOf(gid, g)
    if depot == nil then return nil, "no container" end
    local n = Garden.receiveSeeds(gid, depot, offer, day)
    if n <= 0 then return nil, "no seed created" end
    Upkeep.stats.seedPackets = Upkeep.stats.seedPackets + 1
    Upkeep.stats.seedsReceived = Upkeep.stats.seedsReceived + n
    return string.format("%d %s received into %s (%s, day %d)", n, offer.seed, depot.key, offer.typeOfSeed, day)
end

Upkeep.registerJob({ kind = "seeds", order = 70, gesture = "rummage",
    minutes = Garden.CFG.SEED_MINUTES, groupLog = true, survey = survey, apply = apply })
