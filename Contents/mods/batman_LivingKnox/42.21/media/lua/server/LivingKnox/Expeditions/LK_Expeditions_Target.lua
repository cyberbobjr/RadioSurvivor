-- Living Knox : expéditions, choix du lieu sur la métagrille, sans charger
-- LK20-T08 : sorti de LK_Expeditions.lua sans changement de comportement ; façade et vue d'ensemble :
-- LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Expeditions/LK_Expeditions_Common"

local Ex = LivingKnox.Expeditions
local P = Ex._   -- fonctions privées partagées entre les fichiers de Expeditions/ (LK_Expeditions_Common.lua)

-- ================================================================ choix du lieu (métagrille, sans charger)

local CELL = 256

-- Bâtiments de la métagrille qui croisent le carré de rayon r autour de (x, y) : { BuildingDef }, triés par
-- identifiant (cellules couvertes seulement, comme LK_Sites).
function Ex.buildingsNear(x, y, r)
    local world = getWorld and getWorld() or nil
    local grid = world ~= nil and world.getMetaGrid ~= nil and world:getMetaGrid() or nil
    if grid == nil or ArrayList == nil then return {} end
    local x1, y1, x2, y2 = math.max(0, x - r), math.max(0, y - r), x + r + 1, y + r + 1
    local found = ArrayList.new()
    for cy = math.floor(y1 / CELL), math.floor((y2 - 1) / CELL) do
        for cx = math.floor(x1 / CELL), math.floor((x2 - 1) / CELL) do
            local cell = grid:getCellData(cx, cy)
            if cell then cell:getBuildingsIntersecting(x1, y1, x2 - x1, y2 - y1, found) end
        end
    end
    local out, seen = {}, {}
    for i = 0, found:size() - 1 do
        local b = found:get(i)
        local id = b:getIDString()
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b) return a:getIDString() < b:getIDString() end)
    return out
end

-- Écart (cases) entre (x, y) et le rectangle [x1, x2[ x [y1, y2[ (0 dedans).
local function gapTo(x, y, x1, y1, x2, y2)
    local dx, dy = 0, 0
    if x < x1 then dx = x1 - x elseif x > x2 - 1 then dx = x - (x2 - 1) end
    if y < y1 then dy = y1 - y elseif y > y2 - 1 then dy = y - (y2 - 1) end
    return math.max(dx, dy)
end

-- Note d'une pièce pour les manques want ({ { c, m } }, ordre du manque) : somme de (rang inverse) x ROOM_SCORE des
-- catégories que son nom promet. Pur.
function Ex.roomScore(name, want)
    local n = #want
    local score = 0
    for i, w in ipairs(want) do
        if P.inList(Ex.ROOMS[w.c], name) then score = score + (n - i + 1) * P.cfg().ROOM_SCORE end
    end
    return score
end

-- Candidats (pur sur des descriptions) : list = { { id, x1, y1, x2, y2 (fin exclue), rooms = { { name, z, x1, y1,
-- x2, y2 } } } }, home = { x, y, z }, want, skip = { [id] = vrai }, homes = { { x, y } } (foyers des groupes : un
-- bâtiment qui en contient un est écarté). Rend les candidats triés (note décroissante, puis distance, puis
-- identifiant) : { id, d, score, room = { name, x, y } (centre de la meilleure pièce), label }.
function Ex.rank(list, home, want, skip, homes)
    local c = P.cfg()
    local out = {}
    for _, b in ipairs(list) do
        local d = gapTo(home.x, home.y, b.x1, b.y1, b.x2, b.y2)
        local lived = false
        for _, h in ipairs(homes or {}) do
            if gapTo(h.x, h.y, b.x1, b.y1, b.x2, b.y2) == 0 then lived = true end
        end
        if not skip[b.id] and not lived and d >= c.MIN_DIST and d <= c.MAX_DIST then
            local best, bestScore
            for _, r in ipairs(b.rooms) do
                if r.z == home.z and r.x2 > r.x1 and r.y2 > r.y1 then
                    local s = Ex.roomScore(r.name, want)
                    local area = (r.x2 - r.x1) * (r.y2 - r.y1)
                    if best == nil or s > bestScore or (s == bestScore and area > best.area) then
                        best, bestScore = { name = r.name, x = r.cx or math.floor((r.x1 + r.x2 - 1) / 2),
                            y = r.cy or math.floor((r.y1 + r.y2 - 1) / 2), area = area }, s
                    end
                end
            end
            if best ~= nil then
                out[#out + 1] = { id = b.id, d = d, score = bestScore - d * c.DIST_WEIGHT, room = best,
                    label = best.name .. " " .. best.x .. "," .. best.y }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.d ~= b.d then return a.d < b.d end
        return a.id < b.id
    end)
    return out
end

-- Description d'un BuildingDef pour Ex.rank. Centre de pièce = centre de son premier rectangle (RoomDef.RoomRect,
-- fin exclue, J/iso/RoomDef.java:482-496) : toujours dans la pièce, contrairement au centre de son emprise (pièce en
-- L, base world-placement.md).
local function describe(b)
    local rooms = {}
    local list = b:getRooms()
    for i = 0, list:size() - 1 do
        local r = list:get(i)
        local e = { name = string.lower(r:getName() or ""), z = r:getZ(), x1 = r:getX(), y1 = r:getY(),
            x2 = r:getX2(), y2 = r:getY2() }
        local rects = r:getRects()
        if rects ~= nil and rects:size() > 0 then
            local q = rects:get(0)
            e.cx, e.cy = math.floor((q:getX() + q:getX2() - 1) / 2), math.floor((q:getY() + q:getY2() - 1) / 2)
        end
        rooms[#rooms + 1] = e
    end
    return { id = b:getIDString(), x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2(), rooms = rooms }
end

local function buildingIdAt(x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return nil, false end
    local def = sq:getBuildingDef()
    return def ~= nil and def:getIDString() or nil, true
end

-- Case libre du bâtiment bid la plus proche de (x, y, z), à radius cases au plus, la rank-ième (1 = la plus proche) ;
-- place d'arrêt hors des portes et des couloirs (LK18-T03, LivingKnox.StopPlace).
local function freeNear(x, y, z, bid, radius, rank)
    local B = LivingKnox.Bodies
    return LivingKnox.StopPlace.nearest(x, y, z, radius, function(sq)
        return (bid == nil or P.X().buildingId(sq) == bid) and not sq:HasStairs() and B.freeSquare(sq)
    end, rank)
end
Ex.freeNear = freeNear   -- LK16-T08 : place d'un membre au bâtiment visé (genre de repli)

-- Bâtiments à écarter : foyer du groupe, foyers des autres groupes, derniers fouillés.
local function skipSet(g, data)
    local skip, homes = {}, {}
    for _, b in ipairs(type(g.trips) == "table" and g.trips.seen or {}) do skip[b] = true end
    local ids = {}
    for other in pairs(data.groups) do ids[#ids + 1] = other end
    table.sort(ids)
    for _, other in ipairs(ids) do
        local h = data.groups[other].home
        if type(h) == "table" then
            homes[#homes + 1] = { x = h.x, y = h.y }
            local bid = buildingIdAt(h.x, h.y, h.z)
            if bid ~= nil then skip[bid] = true end
        end
    end
    return skip, homes
end

-- Lieu d'une expédition du groupe gid (registre vivant g) pour les manques want : { x, y, z, b, room, label, d } ou
-- nil et une raison.
function Ex.pickTarget(gid, g, want, data)
    local home = g.home
    local c = P.cfg()
    local list = {}
    for i, b in ipairs(Ex.buildingsNear(home.x, home.y, c.MAX_DIST + 1)) do
        if i > c.MAX_BUILDINGS then break end
        local ok, d = pcall(describe, b)
        if ok then list[#list + 1] = d end
    end
    if #list == 0 then return nil, "no building near home" end
    local skip, homes = skipSet(g, data)
    local ranked = Ex.rank(list, home, want, skip, homes)
    if #ranked == 0 then return nil, "no building at " .. c.MIN_DIST .. ".." .. c.MAX_DIST .. " squares" end
    for i, cand in ipairs(ranked) do
        if i > c.MAX_CANDIDATES then break end
        local sq = freeNear(cand.room.x, cand.room.y, home.z, cand.id, c.SPOT_RADIUS, 1)
        if sq ~= nil then
            return { x = sq:getX(), y = sq:getY(), z = home.z, b = cand.id, room = cand.room.name, label = cand.label,
                d = cand.d, score = cand.score }
        end
    end
    return nil, "no loaded free square in the " .. math.min(#ranked, c.MAX_CANDIDATES) .. " best building(s)"
end

P.freeNear = freeNear
