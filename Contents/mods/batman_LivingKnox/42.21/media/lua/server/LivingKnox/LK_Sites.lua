-- Living Knox : choix du site d'un foyer de groupe sans charger la zone (LK08-T03). Fiche : docs/annexes/conception/sites.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
--   local site, reason = LivingKnox.Sites.pick("raiders", { seed = 42 })
--   -- bâtiment : { x, y, z, kind = "building", key = "b<id>", groupType, buildingId, buildingKind, label,
--   --              bounds = { x1, y1, x2, y2 }, baseDistance, groupDistance, attempts, fallback = nil | "isolated-building",
--   --              repli seulement : isolation, isolationTier, candidates, lair (true pour un repaire non habitable) }
--   -- clairière : { x, y, z = 0, kind = "clearing", key = "c<x>_<y>", groupType, zone (type de zone de forêt),
--   --               radius, baseDistance, groupDistance, attempts, forestZones, source = "metagrid" }
--
-- Style de foyer : réglage home du type de groupe (LivingKnox.GroupTypes, LK08-T02) : "building" (colons, neutres)
-- ou "forest" (pillards) ; opts.home le remplace.
-- Bâtiment : tirage et classement de RadioSurvivor/RS_Rescue (getBuildings de la métagrille, RS_Rescue.check :
-- habitable, ni construction de joueur ni sous-sol seul, assez grand, loin des bases, pas sur l'eau connue), types
-- admis par type de groupe (Sites.KINDS_BY_TYPE, sinon tous), loin des foyers des autres groupes, aucune pièce
-- explorée (I8.2, RoomDef:isExplored, voir la fiche : « déjà vu », pas « récemment »).
-- Clairière : zones de forêt de la métagrille (Sites.FOREST_ZONES), inscrites par le moteur à partir de la biomemap
-- seulement pour les cellules déjà approchées dans la partie (base world-placement.md, « Eau d'une case non
-- chargée ») : aucune source de forêt n'existe sans chargement pour une cellule jamais approchée. Point tiré dans une
-- zone de forêt au prorata de la surface, carré de rayon CLEARING_RADIUS entièrement en forêt et sans zone Water, loin
-- des routes (zones Nav), des bâtiments, des bases et des autres foyers. Aucune forêt qui convienne : REPLI sur le
-- bâtiment le plus isolé (LK08-T08), marqué fallback = "isolated-building", sauf opts.noFallback : habitable, ou
-- repaire (Sites.LAIR_KINDS : entrepôt, grange, garage, station-service, atelier, avec une pièce au sol d'au moins
-- LAIR_MIN_ROOM_AREA cases) pour les types de Sites.LAIR_TYPES ; mêmes distances aux bases et aux foyers. Isolement =
-- écart au plus proche autre bâtiment, plafonné à ISOLATION_RADIUS. Paliers dégressifs ISOLATION_TIERS répartis sur
-- les tirages (100 cases sur le premier tiers, 60 sur le deuxième, 30 sur le dernier) : le meilleur candidat vu est
-- rendu dès qu'il atteint le palier en cours, sinon à la fin des tirages quel que soit son isolement (isolationTier =
-- 0). Échec seulement si aucun bâtiment tiré ne respecte les règles. La clairière elle-même (arbres) n'est pas
-- vérifiée : à faire à l'aménagement, zone chargée.
-- Bases des joueurs : RS_Rescue.knownBases (refuges, joueurs connectés ou locaux, opts.avoid).
-- Foyers des autres groupes : LivingKnox.Groups (list, get(id).home) sauf opts.ignoreGroup, plus opts.homes.
-- Aucune lecture de case : seulement la métagrille (getBuildings, getCellData, getZonesIntersecting des cellules,
-- isValidSquare, getBuildingsIntersecting des cellules), BuildingDef et RoomDef. Rien n'est écrit (ni ModData, ni
-- fichier) ; le foyer n'est pas affecté ici (l'appelant : LivingKnox.Groups.setHome(id, site.x, site.y, site.z)).
-- Graine facultative (opts.seed, nombre ou chaîne) : même tirage pour la même carte, les mêmes mods de carte et les
-- mêmes cellules approchées ; sans graine, ZombRand.
-- Anneau autour d'un centre (E10-T05, opts.near = { x, y, min, max [, widen] }, foyer de bâtiment seulement) : seuls
-- les bâtiments des cellules qui croisent le carré de rayon max autour du centre sont examinés, dans un ordre mélangé
-- par la graine (au plus maxAttempts par palier) ; point du site à une distance (euclidienne) du centre comprise entre
-- min et max ; le bâtiment qui contient le centre est toujours exclu. Aucun bâtiment ne convient : max élargi par
-- paliers (opts.near.widen, sinon NEAR_WIDEN : x 2 puis x 4), chaque palier journalisé, puis repli sur la carte
-- entière (tirage habituel, min et bâtiment du centre toujours exclus). Site : nearDistance, nearTier (1 = anneau,
-- 2.. = paliers élargis, 0 = carte entière), nearMin, nearMax (nil sur la carte entière).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Groups"
local Rescue = require "RadioSurvivor/RS_Rescue"

local Sites = LivingKnox.Sites or {}
LivingKnox.Sites = Sites

Sites.CONFIG = {
    BASE_DISTANCE = 600,      -- cases entre le site et toute base de joueur (zone chargée : 79 cases au plus)
    GROUP_DISTANCE = 400,     -- cases entre le site et le foyer d'un autre groupe
    MAX_ATTEMPTS = 300,       -- tirages par recherche (bâtiments, clairières, repli)
    MAX_CELLS = 20000,        -- cases de la grille des cellules parcourues au plus pour relever les zones de forêt
    CLEARING_RADIUS = 8,      -- demi-côté du carré de camp entièrement en forêt, sans eau connue
    ROAD_DISTANCE = 40,       -- aucune zone Nav (route) dans ce rayon (carré)
    BUILDING_DISTANCE = 60,   -- aucun bâtiment dans ce rayon autour d'une clairière (carré)
    ISOLATION_RADIUS = 100,   -- repli : rayon du relevé des voisins, plafond de l'isolement mesuré
    ISOLATION_TIERS = { 100, 60, 30 }, -- repli : paliers d'isolement exigés, un par tranche égale des tirages
    LAIR_MIN_ROOM_AREA = 25,  -- repli : surface minimale d'une pièce de repaire au niveau 0 (cases)
    EXCLUDE_EXPLORED = true,  -- I8.2 : écarter un bâtiment dont une pièce est explorée
    NEAR_WIDEN = { 2, 4 },    -- E10-T05 : paliers d'élargissement de l'anneau opts.near (multiples de max)
}

-- Repaires (LK08-T08) : bâtiments non habitables admis au repli des types de Sites.LAIR_TYPES, après les types
-- habitables de RS_Rescue.KINDS (même format : any = au moins une de ces pièces ; main = pièce du point du site).
-- Noms de pièces vanilla (clés de media/lua/server/Items/Distributions.lua, 42.21).
Sites.LAIR_KINDS = {
    { kind = "warehouse", label = "warehouse",
      any = { "warehouse", "storageunit", "factory", "loggingfactory", "metalshop" } },
    { kind = "barn", label = "barn", any = { "barn", "farmstorage" } },
    { kind = "garage", label = "garage", any = { "garagestorage", "mechanic", "carsupply" } },
    { kind = "gasstation", label = "gas station", any = { "gasstore", "gasstorage", "fossoil" } },
    { kind = "workshop", label = "workshop", any = { "toolstore", "shed" } },
}
for _, rule in ipairs(Sites.LAIR_KINDS) do rule.main = rule.main or rule.any end

-- Types de groupe dont le repli admet les repaires.
Sites.LAIR_TYPES = { raiders = true }

-- Zones de forêt de la biomemap (media/lua/server/metazones/BiomeMapConfig.lua, canal G). "Forest" n'y est
-- affecté qu'aux rives argileuses des lacs (pixels 59 et 79) : écarté.
Sites.FOREST_ZONES = {
    DeepForest = true, PHForest = true, PRForest = true, FarmForest = true, FarmMixForest = true,
    BirchForest = true, BirchMixForest = true, OrganicForest = true,
}

-- Zones inscrites depuis la biomemap (une cellule qui en a une a été traitée). Relu dans biome_map_config si présent.
local DEFAULT_BIOME_ZONES = { "Water", "Forest", "ForagingNav", "DeepForest", "TrailerPark", "TownZone", "Farm",
    "FarmLand", "PHForest", "PRForest", "FarmMixForest", "FarmForest", "BirchForest", "BirchMixForest", "OrganicForest" }

-- Types de bâtiment (RS_Rescue.KINDS) admis par type de groupe ; un type absent admet tous les types habitables.
Sites.KINDS_BY_TYPE = {
    settlers = { "farmhouse", "house_garage", "house", "church", "school", "motel", "firestation", "apartments" },
    neutrals = { "house", "house_garage", "farmhouse", "motel", "apartments", "clinic", "church" },
}

local CELL = 256

local function log() return LivingKnox.Log end

local function metaGrid()
    local world = getWorld and getWorld()
    return world and world:getMetaGrid()
end

local function biomeZones()
    local set = {}
    local cfg = biome_map_config
    if type(cfg) == "table" then
        for _, entry in ipairs(cfg) do
            if type(entry) == "table" and type(entry.zone) == "string" then set[entry.zone] = true end
        end
    end
    for _, name in ipairs(DEFAULT_BIOME_ZONES) do set[name] = true end
    return set
end

local function inList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function pointRect(x, y, source)
    local fx, fy = math.floor(x), math.floor(y)
    return { x1 = fx, y1 = fy, x2 = fx + 1, y2 = fy + 1, source = source }
end

local function nearest(rect, list)
    local best = nil
    for _, other in ipairs(list) do
        local d = Rescue.gap(rect, other)
        if best == nil or d < best then best = d end
    end
    return best
end

-- Foyers des autres groupes : rectangles d'un point (fin exclusive). opts.ignoreGroup : identifiant à ignorer.
function Sites.groupHomes(opts)
    opts = opts or {}
    local out = {}
    local Groups = LivingKnox.Groups
    if Groups and Groups.list then
        for _, id in ipairs(Groups.list()) do
            if id ~= opts.ignoreGroup then
                local g = Groups.get(id)
                if g and g.home then out[#out + 1] = pointRect(g.home.x, g.home.y, id) end
            end
        end
    end
    for _, h in ipairs(opts.homes or {}) do
        if h.x then out[#out + 1] = pointRect(h.x, h.y, h.source or "home") end
    end
    return out
end

-- Style de foyer d'un type de groupe : "building" ou "forest", ou nil et la raison.
function Sites.homeStyle(groupType, opts)
    opts = opts or {}
    if opts.home ~= nil then
        if opts.home == "building" or opts.home == "forest" then return opts.home end
        return nil, "bad home style " .. tostring(opts.home)
    end
    local def = LivingKnox.GroupTypes and LivingKnox.GroupTypes.get(groupType)
    if def == nil then return nil, "unknown group type " .. tostring(groupType) end
    if def.home == "building" or def.home == "forest" then return def.home end
    return nil, "group type " .. tostring(groupType) .. " has no home style"
end

local function reasonSummary(reasons)
    local keys = {}
    for k in pairs(reasons) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. reasons[k] end
    return table.concat(parts, ", ")
end

local function count(reasons, why)
    reasons[why] = (reasons[why] or 0) + 1
end

-- Bâtiments de la métagrille qui croisent le rectangle élargi de r, sans le bâtiment d'identifiant skipId. Seules les
-- cellules couvertes sont interrogées (IsoMetaGrid:getBuildingsIntersecting parcourt toute la grille).
local function buildingsNear(grid, rect, r, skipId)
    local x1, y1 = math.max(0, rect.x1 - r), math.max(0, rect.y1 - r)
    local x2, y2 = rect.x2 + r, rect.y2 + r
    local found = ArrayList.new()
    for cy = math.floor(y1 / CELL), math.floor((y2 - 1) / CELL) do
        for cx = math.floor(x1 / CELL), math.floor((x2 - 1) / CELL) do
            local cell = grid:getCellData(cx, cy)
            if cell then cell:getBuildingsIntersecting(x1, y1, x2 - x1, y2 - y1, found) end
        end
    end
    local out = {}
    for i = 0, found:size() - 1 do
        local b = found:get(i)
        if skipId == nil or b:getIDString() ~= skipId then out[#out + 1] = b end
    end
    return out
end

local function buildingsAround(grid, rect, r, skipId)
    return #buildingsNear(grid, rect, r, skipId)
end

-- Isolement d'un bâtiment : écart (RS_Rescue.gap) au plus proche autre bâtiment, plafonné à ISOLATION_RADIUS (aucun
-- voisin dans le carré relevé = plafond). Entier.
local function isolationOf(grid, rect, skipId)
    local r = Sites.CONFIG.ISOLATION_RADIUS
    local best = r
    for _, other in ipairs(buildingsNear(grid, rect, r, skipId)) do
        local d = Rescue.gap(rect, { x1 = other:getX(), y1 = other:getY(), x2 = other:getX2(), y2 = other:getY2() })
        if d < best then best = d end
    end
    return math.floor(best)
end

-- Palier d'un isolement : le plus haut palier de ISOLATION_TIERS atteint, sinon 0.
local function tierOf(isolation)
    local best = 0
    for _, t in ipairs(Sites.CONFIG.ISOLATION_TIERS) do
        if isolation >= t and t > best then best = t end
    end
    return best
end

-- Palier exigé au tirage attempt (1..maxAttempts) : tranches égales, dans l'ordre de ISOLATION_TIERS.
local function tierAt(attempt, maxAttempts)
    local tiers = Sites.CONFIG.ISOLATION_TIERS
    if #tiers == 0 then return 0 end
    local i = math.floor((attempt - 1) * #tiers / math.max(1, maxAttempts)) + 1
    return tiers[math.min(i, #tiers)]
end

local function lairRule(kind)
    for _, rule in ipairs(Sites.LAIR_KINDS) do
        if rule.kind == kind then return rule end
    end
    return nil
end

-- Types habitables puis repaires (copie : RS_Rescue.KINDS n'est pas modifié).
local function lairRules()
    local out = {}
    for _, rule in ipairs(Rescue.KINDS) do out[#out + 1] = rule end
    for _, rule in ipairs(Sites.LAIR_KINDS) do out[#out + 1] = rule end
    return out
end

-- Une pièce du repaire (noms any de la règle) au niveau 0 d'au moins LAIR_MIN_ROOM_AREA cases.
local function lairRoom(b, rule)
    local rooms = b:getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room:getZ() == 0 and inList(rule.any, string.lower(room:getName() or ""))
            and room:getArea() >= Sites.CONFIG.LAIR_MIN_ROOM_AREA then
            return true
        end
    end
    return false
end

local function anyExplored(b)
    local rooms = b:getRooms()
    for i = 0, rooms:size() - 1 do
        if rooms:get(i):isExplored() then return true end
    end
    return false
end

-- Contexte commun d'une recherche (exposé pour revérifier un site : suite en jeu lk.sites).
local function context(groupType, opts, grid)
    local cfg = Sites.CONFIG
    return {
        groupType = groupType, opts = opts, grid = grid,
        bases = Rescue.knownBases(opts),
        homes = Sites.groupHomes(opts),
        baseDistance = opts.baseDistance or cfg.BASE_DISTANCE,
        groupDistance = opts.groupDistance or cfg.GROUP_DISTANCE,
        maxAttempts = opts.maxAttempts or cfg.MAX_ATTEMPTS,
        excludeExplored = (opts.allowExplored ~= true) and cfg.EXCLUDE_EXPLORED,
        draw = Rescue.drawer(opts.seed),
        near = opts.near,     -- normalisé par Sites.pick (centre et anneau, E10-T05)
        nearMax = opts.near and opts.near.max or nil,
    }
end
Sites.context = context

-- Bâtiments ----------------------------------------------------------------------------------------------------------

-- Examine un BuildingDef pour un foyer. fallback : repli des camps (types de bâtiment du groupe ignorés, repaires
-- admis pour Sites.LAIR_TYPES, isolement mesuré dans site.isolation et site.isolationTier, jamais un refus).
-- Rend le site, ou nil et la raison.
function Sites.checkBuilding(b, ctx, fallback)
    local lairs = fallback and Sites.LAIR_TYPES[ctx.groupType] == true
    local site, why = Rescue.check(b, ctx.bases, { minDistance = ctx.baseDistance, exclude = ctx.opts.exclude,
        minArea = ctx.opts.minArea, rules = lairs and lairRules() or nil }, ctx.grid)
    if site == nil then
        if lairs and why == "not habitable" then why = "neither habitable nor a lair" end
        return nil, why
    end
    local near, dNear = ctx.near, nil
    if near then
        local r = site.bounds
        if near.x >= r.x1 and near.x < r.x2 and near.y >= r.y1 and near.y < r.y2 then return nil, "center building" end
        dNear = math.sqrt((site.x - near.x) * (site.x - near.x) + (site.y - near.y) * (site.y - near.y))
        if dNear < near.min then return nil, "too close to the center" end
        if ctx.nearMax and dNear > ctx.nearMax then return nil, "beyond the ring" end
    end
    local lair = lairs and lairRule(site.kind) or nil
    if lair and not lairRoom(b, lair) then return nil, "lair room too small" end
    local kinds = ctx.opts.kinds or Sites.KINDS_BY_TYPE[ctx.groupType]
    if not fallback and kinds and not inList(kinds, site.kind) then return nil, "kind not wanted" end
    local dHome = nearest(site.bounds, ctx.homes)
    if dHome ~= nil and dHome < ctx.groupDistance then return nil, "near another group home" end
    if ctx.excludeExplored and anyExplored(b) then return nil, "explored by a player" end
    local out = { x = site.x, y = site.y, z = site.z, kind = "building", key = site.key, groupType = ctx.groupType,
                  buildingId = site.buildingId, buildingKind = site.kind, label = site.label, bounds = site.bounds,
                  baseDistance = site.baseDistance, groupDistance = dHome and math.floor(dHome) or nil,
                  nearDistance = dNear and math.floor(dNear) or nil }
    if fallback then
        out.isolation = isolationOf(ctx.grid, site.bounds, site.buildingId)
        out.isolationTier = tierOf(out.isolation)
        if lair then out.lair = true end
    end
    return out
end

local function pickBuilding(ctx)
    local list = ctx.grid:getBuildings()
    local n = list and list:size() or 0
    if n == 0 then return nil, "no building in the metagrid" end
    local reasons = {}
    for attempt = 1, ctx.maxAttempts do
        local site, why = Sites.checkBuilding(list:get(ctx.draw(n)), ctx, false)
        if site then
            site.attempts = attempt
            return site
        end
        count(reasons, why)
    end
    return nil, "no suitable building after " .. ctx.maxAttempts .. " draw(s): " .. reasonSummary(reasons)
end

-- Repli des camps : meilleur candidat (isolement le plus grand, le premier vu à égalité), rendu dès qu'il atteint le
-- palier du tirage en cours (tierAt), sinon après maxAttempts tirages. Échec si aucun candidat valide.
local function pickIsolated(ctx)
    local list = ctx.grid:getBuildings()
    local n = list and list:size() or 0
    if n == 0 then return nil, "no building in the metagrid" end
    local reasons, best, candidates = {}, nil, 0
    for attempt = 1, ctx.maxAttempts do
        local site, why = Sites.checkBuilding(list:get(ctx.draw(n)), ctx, true)
        if site then
            candidates = candidates + 1
            if best == nil or site.isolation > best.isolation then best = site end
        else
            count(reasons, why)
        end
        if best and best.isolation >= tierAt(attempt, ctx.maxAttempts) then
            best.attempts, best.candidates = attempt, candidates
            return best
        end
    end
    if best then
        best.attempts, best.candidates = ctx.maxAttempts, candidates
        return best
    end
    return nil, "no suitable isolated building after " .. ctx.maxAttempts .. " draw(s): " .. reasonSummary(reasons)
end
Sites.tierAt = tierAt

-- Anneau autour d'un centre (E10-T05) ------------------------------------------------------------------------------

-- Option near normalisée (entiers, min >= 0, max > min, paliers > 1 croissants), ou nil et la raison.
function Sites.normalizeNear(near)
    if type(near) ~= "table" or type(near.x) ~= "number" or type(near.y) ~= "number"
        or type(near.min) ~= "number" or type(near.max) ~= "number" or near.min < 0 or near.max <= near.min then
        return nil, "bad near option"
    end
    local widen, last = {}, 1
    for _, k in ipairs(near.widen or Sites.CONFIG.NEAR_WIDEN or {}) do
        if type(k) ~= "number" or k <= last then return nil, "bad near option (widen)" end
        widen[#widen + 1], last = k, k
    end
    return { x = math.floor(near.x), y = math.floor(near.y), min = math.floor(near.min), max = math.floor(near.max),
             widen = widen }
end

-- Bâtiments dont l'emprise est à maxR cases au plus du centre (cellules couvertes seulement).
local function ringCandidates(ctx, maxR)
    local center = pointRect(ctx.near.x, ctx.near.y)
    local out = {}
    for _, b in ipairs(buildingsNear(ctx.grid, center, maxR, nil)) do
        local r = { x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2() }
        if Rescue.gap(r, center) <= maxR then out[#out + 1] = b end
    end
    return out
end

-- Anneau puis paliers élargis : candidats mélangés par la graine, au plus maxAttempts examinés par palier. Un bâtiment
-- refusé pour une autre raison que « beyond the ring » n'est plus examiné aux paliers suivants.
local function pickNear(ctx)
    local near = ctx.near
    local tiers = { near.max }
    for _, k in ipairs(near.widen) do tiers[#tiers + 1] = math.floor(near.max * k) end
    local refused, notes = {}, {}
    for tier, maxR in ipairs(tiers) do
        ctx.nearMax = maxR
        local list = ringCandidates(ctx, maxR)
        for j = #list, 2, -1 do
            local k = ctx.draw(j) + 1
            list[j], list[k] = list[k], list[j]
        end
        local reasons, examined = {}, 0
        for _, b in ipairs(list) do
            if examined >= ctx.maxAttempts then break end
            local id = b:getIDString()
            if not refused[id] then
                examined = examined + 1
                local site, why = Sites.checkBuilding(b, ctx, false)
                if site then
                    site.attempts, site.nearTier, site.nearMin, site.nearMax = examined, tier, near.min, maxR
                    return site
                end
                if why ~= "beyond the ring" then refused[id] = true end
                count(reasons, why)
            end
        end
        local note = string.format("ring %d (%d-%d squares from %d,%d): %d building(s), %d examined%s", tier,
            near.min, maxR, near.x, near.y, #list, examined, examined > 0 and (": " .. reasonSummary(reasons)) or "")
        notes[#notes + 1] = note
        log().warn("sites: no building for %s in %s%s", tostring(ctx.groupType), note,
            tier < #tiers and "; widening" or "; whole map next")
    end
    ctx.nearMax = nil
    return nil, table.concat(notes, "; ")
end

-- Forêt --------------------------------------------------------------------------------------------------------------

-- Zones de forêt connues de la métagrille : { zones = { { x, y, w, h, type } }, cells, known, scanned, truncated }.
-- Une zone plus étroite que le carré de camp est ignorée. Lecture de la métagrille seulement (IsoMetaCell :
-- getZonesIntersecting ne lit que les métachunks existants, n'en crée aucun et ne charge rien).
function Sites.forestZones(grid, radius)
    radius = radius or Sites.CONFIG.CLEARING_RADIUS
    local out = { zones = {}, cells = 0, known = 0, scanned = 0, truncated = false }
    local biome = biomeZones()
    local minX, maxX, minY, maxY = grid:getMinX(), grid:getMaxX(), grid:getMinY(), grid:getMaxY()
    local side = 2 * radius + 1
    for cy = minY, maxY do
        for cx = minX, maxX do
            if out.scanned >= Sites.CONFIG.MAX_CELLS then
                out.truncated = true
                return out
            end
            out.scanned = out.scanned + 1
            local cell = grid:getCellData(cx, cy)
            if cell then
                out.cells = out.cells + 1
                local list = ArrayList.new()
                cell:getZonesIntersecting(cx * CELL, cy * CELL, 0, CELL, CELL, list)
                local known = false
                for i = 0, list:size() - 1 do
                    local zone = list:get(i)
                    local t = zone:getType()
                    if biome[t] then known = true end
                    if Sites.FOREST_ZONES[t] then
                        local w, h = zone:getWidth(), zone:getHeight()
                        if w >= side and h >= side then
                            out.zones[#out.zones + 1] = { x = zone:getX(), y = zone:getY(), w = w, h = h, type = t }
                        end
                    end
                end
                if known then out.known = out.known + 1 end
            end
        end
    end
    return out
end

local function covers(zone, x, y)
    return x >= zone.x and x < zone.x + zone.w and y >= zone.y and y < zone.y + zone.h
end

local function crosses(zone, x1, y1, x2, y2)
    return zone.x < x2 and x1 < zone.x + zone.w and zone.y < y2 and y1 < zone.y + zone.h
end

-- Décalages des sondes d'un carré de demi-côté r : -r, puis tous les 8 cases au plus, jusqu'à r ; 0 compris.
local function offsets(r)
    local out, v = {}, -r
    while v < r do
        out[#out + 1] = v
        v = v + math.min(8, r)
    end
    out[#out + 1] = r
    if not inList(out, 0) then out[#out + 1] = 0 end
    return out
end

-- Examine un point de clairière. Rend le site, ou nil et la raison.
function Sites.checkClearing(x, y, ctx)
    local grid, cfg = ctx.grid, Sites.CONFIG
    local r = math.max(1, cfg.CLEARING_RADIUS)
    if not grid:isValidSquare(x, y) or grid:getCellData(math.floor(x / CELL), math.floor(y / CELL)) == nil then
        return nil, "outside the map"
    end
    local key = "c" .. x .. "_" .. y
    if ctx.opts.exclude and ctx.opts.exclude[key] then return nil, "excluded" end
    local here = pointRect(x, y)
    local dBase = nearest(here, ctx.bases)
    if dBase ~= nil and dBase < ctx.baseDistance then return nil, "near a known base" end
    local dHome = nearest(here, ctx.homes)
    if dHome ~= nil and dHome < ctx.groupDistance then return nil, "near another group home" end
    local R = math.max(cfg.ROAD_DISTANCE, r)
    local list = grid:getZonesIntersecting(math.max(0, x - R), math.max(0, y - R), 0, 2 * R + 1, 2 * R + 1)
    local forest, water, road = {}, false, false
    for i = 0, (list and list:size() or 0) - 1 do
        local zone = list:get(i)
        local t = zone:getType()
        if t == "Nav" then
            road = true
        elseif t == "Water" or Sites.FOREST_ZONES[t] then
            local z = { x = zone:getX(), y = zone:getY(), w = zone:getWidth(), h = zone:getHeight(), type = t }
            if t == "Water" then
                if crosses(z, x - r, y - r, x + r + 1, y + r + 1) then water = true end
            else
                forest[#forest + 1] = z
            end
        end
    end
    if water then return nil, "water" end
    -- Carré entièrement en forêt : zones au grain du chunk (8 cases), sondes au plus tous les 8 cases et aux bords.
    local zoneType = nil
    local steps = offsets(r)
    for _, dy in ipairs(steps) do
        for _, dx in ipairs(steps) do
            local hit = nil
            for _, z in ipairs(forest) do
                if covers(z, x + dx, y + dy) then hit = z break end
            end
            if hit == nil then return nil, "forest edge" end
            if dx == 0 and dy == 0 then zoneType = hit.type end
        end
    end
    if road then return nil, "near a road" end
    if buildingsAround(grid, here, cfg.BUILDING_DISTANCE, nil) > 0 then return nil, "near a building" end
    return { x = x, y = y, z = 0, kind = "clearing", key = key, groupType = ctx.groupType, zone = zoneType, radius = r,
             baseDistance = dBase and math.floor(dBase) or nil, groupDistance = dHome and math.floor(dHome) or nil,
             source = "metagrid" }
end

local function pickClearing(ctx)
    local r = math.max(1, Sites.CONFIG.CLEARING_RADIUS)
    local found = Sites.forestZones(ctx.grid, r)
    local zones = found.zones
    local scan = found.cells .. " cell(s), " .. found.known .. " known"
        .. (found.truncated and ", scan truncated" or "")
    if #zones == 0 then return nil, "no forest zone known in the metagrid (" .. scan .. ")" end
    -- Tirage d'une zone au prorata de la surface utile, puis d'un point à au moins r cases de son bord.
    local cumul, total = {}, 0
    for i, z in ipairs(zones) do
        total = total + (z.w - 2 * r) * (z.h - 2 * r)
        cumul[i] = total
    end
    local reasons = {}
    for attempt = 1, ctx.maxAttempts do
        local v = ctx.draw(total)
        local lo, hi = 1, #zones
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if cumul[mid] > v then hi = mid else lo = mid + 1 end
        end
        local z = zones[lo]
        local x = z.x + r + ctx.draw(z.w - 2 * r)
        local y = z.y + r + ctx.draw(z.h - 2 * r)
        local site, why = Sites.checkClearing(x, y, ctx)
        if site then
            site.attempts = attempt
            site.forestZones = #zones
            return site
        end
        count(reasons, why)
    end
    return nil, "no suitable clearing after " .. ctx.maxAttempts .. " draw(s) in " .. #zones .. " forest zone(s) ("
        .. scan .. "): " .. reasonSummary(reasons)
end

-- API ----------------------------------------------------------------------------------------------------------------

-- Choisit le site du foyer d'un groupe de type groupType. opts (facultatifs) : seed, home ("building" | "forest"),
-- baseDistance, groupDistance, maxAttempts, minArea, avoid (points { x, y } ou rectangles { x1, y1, x2, y2 }),
-- homes (points de foyers supplémentaires), ignoreGroup (identifiant de groupe dont le foyer est ignoré), exclude
-- (ensemble de clés déjà prises), kinds (types de bâtiment admis), allowExplored, noFallback, near (anneau autour
-- d'un centre { x, y, min, max [, widen] }, foyer de bâtiment seulement : voir l'en-tête).
-- Rend le site (table simple, sans objet Java), ou nil et la raison (anglais).
function Sites.pick(groupType, opts)
    opts = opts or {}
    local style, why = Sites.homeStyle(groupType, opts)
    if style == nil then return nil, why end
    if opts.near ~= nil then
        if style ~= "building" then return nil, "near option needs a building home" end
        local near, bad = Sites.normalizeNear(opts.near)
        if near == nil then return nil, bad end
        local copy = {}
        for k, v in pairs(opts) do copy[k] = v end
        copy.near = near
        opts = copy
    end
    local grid = metaGrid()
    if grid == nil then return nil, "no metagrid" end
    local ctx = context(groupType, opts, grid)
    local site, reason
    if ctx.near then
        site, reason = pickNear(ctx)
        if site == nil then
            local whole, why2 = pickBuilding(ctx)
            if whole then
                whole.nearTier, whole.nearMin, whole.nearFallback = 0, ctx.near.min, reason
                log().warn("sites: no building for %s in any ring; whole map: %s %d squares from %d,%d",
                    groupType, whole.key, whole.nearDistance, ctx.near.x, ctx.near.y)
                site = whole
            else
                reason = reason .. "; whole map: " .. why2
            end
        elseif site.nearTier > 1 then
            log().info("sites: %s for %s in widened ring %d (%d-%d squares), %d squares from %d,%d", site.key,
                groupType, site.nearTier, site.nearMin, site.nearMax, site.nearDistance, ctx.near.x, ctx.near.y)
        end
    elseif style == "building" then
        site, reason = pickBuilding(ctx)
    else
        site, reason = pickClearing(ctx)
        if site == nil and not opts.noFallback then
            local fallback, why2 = pickIsolated(ctx)
            if fallback then
                fallback.fallback = "isolated-building"
                fallback.fallbackReason = reason
                log().warn("sites: no forest clearing for %s (%s); fallback to an isolated building: %s %s,"
                    .. " isolation %d (tier %d), best of %d candidate(s)", groupType, reason, fallback.buildingKind,
                    fallback.key, fallback.isolation, fallback.isolationTier, fallback.candidates)
                site = fallback
            else
                reason = reason .. "; fallback: " .. why2
            end
        end
    end
    if site == nil then
        log().warn("sites: no site for %s: %s", tostring(groupType), reason)
        return nil, reason
    end
    log().info("sites: picked a %s (%s) for %s after %d draw(s)", site.kind, site.key, groupType, site.attempts)
    return site
end

return Sites
