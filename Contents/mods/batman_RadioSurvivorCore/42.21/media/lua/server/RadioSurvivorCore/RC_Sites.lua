if isClient() then return end
--[[
RadioSurvivorCore: building draw by the metagrid and descriptive clues (E18-T05, moved from RadioSurvivor's rescue
module, code unchanged). Authority only (dedicated server or solo). Used by the mission templates (scout, clear,
recover, retrieve_id, signal), by RadioSurvivor's rescues (RS_Rescue, same functions under the same names) and by
Living Knox's places. Details: docs/specifications-techniques/rescue.md.

    local Sites = require "RadioSurvivorCore/RC_Sites"
    local site, reason = Sites.pick({ seed = 42, minDistance = 600, avoid = { { x = 100, y = 200 } } })
    -- site = { x, y, z, buildingId, key, kind, label, bounds = { x1, y1, x2, y2 }, attempts, clues = { ... } }

Draw: a random index in getWorld():getMetaGrid():getBuildings() (every BuildingDef of the map once the folders are
merged), at most CONFIG.MAX_ATTEMPTS times; each attempt reads only the BuildingDef and its RoomDef (names, levels,
rectangles), the metagrid zone at the chosen point and the known bases: no getGridSquare, LoadChunk, getChunk nor
getBuildingAt(x, y) (which walks the whole list). Seed (opts.seed, number or string): reproducible Park-Miller draw for
the same map and the same mods; without a seed, ZombRand.

Habitable: first kind of Sites.KINDS whose rooms match (church, school, police station, fire station, hospital,
clinic, motel, farmhouse, apartment building, house with a garage, house); never a player building (isUserDefined), a
basement alone or a surface under CONFIG.MIN_AREA.
Known base: vanilla safehouses (SafeHouse.getSafehouseList), position of the connected players (server) or local
players (solo), points or rectangles given by the caller (opts.avoid). Does not cover: offline players, buildings
without a declared safehouse, parked vehicles, stashes. Distance = gap between the building rectangle and the base.
Dry land: a map building stands on floor squares; the chosen point is the centre of a room rectangle, and a "Water"
zone of the metagrid at that point (cells already approached only) rules the building out.

Clues (Sites.clues): in English, meant for the bridge prompt, without any digit: kind, size and floors of the
building, nearby landmarks drawn from the close buildings of the metagrid (IsoMetaCell:getBuildingsIntersecting of the
useful cells only) with a direction and a distance in words, nearest town when the vanilla map is loaded
(getLotDirectories, centres of the vanilla annotations). Nothing is sent to the bridge here, nothing written in ModData.
The returned site holds plain (serialisable) values only, never a Java object.
]]
local Sites = {}

Sites.CONFIG = {
    MIN_DISTANCE = 600,      -- tiles between the building and any known base (loaded area: 79 tiles at most)
    MAX_ATTEMPTS = 300,      -- draws per call
    MIN_AREA = 20,           -- total room area (tiles, all levels)
    LANDMARK_RADIUS = 160,   -- tiles around the building for the nearby landmarks
    MAX_LANDMARKS = 3,
    VANILLA_MAP = "Muldraugh, KY",
}

-- Habitable building kinds, first match wins. all: every one of these rooms; any: at least one; min: smallest number
-- of rooms of a name. main: preferred rooms for the site point.
Sites.KINDS = {
    { kind = "church", label = "church", any = { "church" }, main = { "church" } },
    { kind = "school", label = "school", any = { "classroom", "elementaryclassroom" }, main = { "classroom" } },
    { kind = "police", label = "police station", any = { "policestorage" } },
    { kind = "firestation", label = "fire station", any = { "firestorage" } },
    { kind = "hospital", label = "hospital", any = { "hospitalroom" }, main = { "hospitalroom" } },
    { kind = "clinic", label = "medical clinic", any = { "medical", "medicalstorage" }, main = { "medical" } },
    { kind = "motel", label = "motel", any = { "motelroom", "motelroomoccupied" }, main = { "motelroom" } },
    { kind = "farmhouse", label = "farmhouse", all = { "bedroom" }, any = { "barn", "farmstorage" },
      main = { "livingroom", "kitchen" } },
    { kind = "apartments", label = "apartment building", min = { bedroom = 4, kitchen = 2 },
      main = { "livingroom", "kitchen" } },
    { kind = "house_garage", label = "house with a garage", all = { "bedroom", "garagestorage" },
      main = { "livingroom", "kitchen" } },
    { kind = "house", label = "house", all = { "bedroom" }, any = { "kitchen", "livingroom" },
      main = { "livingroom", "kitchen" } },
}

-- Nearby landmarks: first match wins (any only).
Sites.LANDMARKS = {
    { kind = "gas", label = "a gas station", any = { "gasstore", "fossoil" } },
    { kind = "grocery", label = "a grocery store",
      any = { "grocery", "gigamart", "conveniencestore", "cornerstore", "generalstore" } },
    { kind = "church", label = "a church", any = { "church" } },
    { kind = "school", label = "a school", any = { "classroom", "elementaryclassroom" } },
    { kind = "police", label = "a police station", any = { "policestorage" } },
    { kind = "firestation", label = "a fire station", any = { "firestorage" } },
    { kind = "hospital", label = "a hospital", any = { "hospitalroom" } },
    { kind = "pharmacy", label = "a pharmacy", any = { "pharmacy" } },
    { kind = "clinic", label = "a medical clinic", any = { "medical", "medicalstorage" } },
    { kind = "motel", label = "a motel", any = { "motelroom", "motelroomoccupied" } },
    { kind = "gunstore", label = "a gun store", any = { "gunstore" } },
    { kind = "bar", label = "a bar", any = { "bar" } },
    { kind = "restaurant", label = "a restaurant", any = { "spiffo_dining", "pizzawhirled" } },
    { kind = "liquor", label = "a liquor store", any = { "liquorstore" } },
    { kind = "hardware", label = "a hardware store", any = { "toolstore" } },
    { kind = "mechanic", label = "a car repair shop", any = { "mechanic" } },
    { kind = "post", label = "a post office", any = { "post" } },
    { kind = "library", label = "a library", any = { "library" } },
    { kind = "theatre", label = "a movie theater", any = { "theatre" } },
    { kind = "bakery", label = "a bakery", any = { "bakery" } },
    { kind = "clothing", label = "a clothing store", any = { "clothingstore", "departmentstore" } },
    { kind = "bookstore", label = "a bookstore", any = { "bookstore" } },
    { kind = "gym", label = "a gym", any = { "gym" } },
    { kind = "daycare", label = "a daycare", any = { "daycare" } },
    { kind = "warehouse", label = "a warehouse", any = { "warehouse" } },
    { kind = "barn", label = "a barn", any = { "barn" } },
}

-- Towns of the vanilla map: centre of the annotations (media/maps/Muldraugh, KY/worldmap-annotations.lua, knowledge
-- base knox-geography.md) and rough radius in tiles. Used only when the vanilla map is loaded.
Sites.TOWNS = {
    { name = "Louisville", x = 13077, y = 2238, r = 2200 },
    { name = "Valley Station", x = 13447, y = 5278, r = 900 },
    { name = "West Point", x = 11654, y = 6864, r = 900 },
    { name = "Muldraugh", x = 10754, y = 9926, r = 900 },
    { name = "Riverside", x = 6450, y = 5430, r = 800 },
    { name = "Brandenburg", x = 2056, y = 6070, r = 800 },
    { name = "Ekron", x = 634, y = 9746, r = 600 },
    { name = "Irvington", x = 2427, y = 14185, r = 800 },
    { name = "Echo Creek", x = 3589, y = 10952, r = 600 },
    { name = "March Ridge", x = 10130, y = 12801, r = 700 },
    { name = "Fallas Lake", x = 7253, y = 8279, r = 600 },
    { name = "Rosewood", x = 8159, y = 11661, r = 700 },
}

local CELL = 256

local function log(msg)
    print("[RadioSurvivorCore] sites: " .. tostring(msg))
end

local function metaGrid()
    local world = getWorld and getWorld()
    return world and world:getMetaGrid()
end

-- Draw: draw(n) -> integer from 0 to n - 1. Seed: Park-Miller (quotients under 2^31, no bitwise operator).
local PM = 2147483647
local function seedNumber(seed)
    if type(seed) == "number" then return math.floor(math.abs(seed)) % PM end
    local h = 7
    local s = tostring(seed)
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % PM end
    return h
end

local function drawer(seed)
    if seed == nil then
        return function(n) return ZombRand(n) end
    end
    local x = (seedNumber(seed) * 7919 + 104729) % PM
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % PM
        x = (x + (x % 65521) * 31337) % PM
        if x == 0 then x = 1 end
        return math.floor(x / PM * n)
    end
    for _ = 1, 6 do draw(1) end
    return draw
end
-- Exposed for the other place draws without loading (LivingKnox/LK_Sites, LK08-T03); same draw.
Sites.drawer = drawer

-- Rooms of a building: count per name (lower case), total area, levels.
local function roomCounts(b)
    local counts = {}
    local rooms = b:getRooms()
    for i = 0, rooms:size() - 1 do
        local name = rooms:get(i):getName()
        if name then
            name = string.lower(name)
            counts[name] = (counts[name] or 0) + 1
        end
    end
    return counts, rooms
end

local function matches(rule, counts)
    if rule.all then
        for _, name in ipairs(rule.all) do
            if not counts[name] then return false end
        end
    end
    if rule.any then
        local found = false
        for _, name in ipairs(rule.any) do
            if counts[name] then found = true break end
        end
        if not found then return false end
    end
    if rule.min then
        for name, n in pairs(rule.min) do
            if (counts[name] or 0) < n then return false end
        end
    end
    return true
end

local function firstRule(rules, counts)
    for _, rule in ipairs(rules) do
        if matches(rule, counts) then return rule end
    end
    return nil
end

-- Habitable kind of a BuildingDef (rule of Sites.KINDS), or nil.
function Sites.classify(b)
    if b == nil then return nil end
    return firstRule(Sites.KINDS, (roomCounts(b)))
end

-- Landmark (rule of Sites.LANDMARKS) of a BuildingDef, or nil.
function Sites.landmarkOf(b)
    if b == nil then return nil end
    return firstRule(Sites.LANDMARKS, (roomCounts(b)))
end

local function bounds(b)
    return { x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2() }
end
Sites.bounds = bounds

-- Gap between two rectangles with exclusive ends (0 when they touch or overlap).
local function gap(a, b)
    local gx = math.max(0, b.x1 - a.x2, a.x1 - b.x2)
    local gy = math.max(0, b.y1 - a.y2, a.y1 - b.y2)
    return math.sqrt(gx * gx + gy * gy)
end
Sites.gap = gap

local function pointRect(x, y, source)
    local fx, fy = math.floor(x), math.floor(y)
    return { x1 = fx, y1 = fy, x2 = fx + 1, y2 = fy + 1, source = source }
end

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    elseif getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

-- Known bases: list of rectangles { x1, y1, x2, y2 (exclusive), source }. See the header.
function Sites.knownBases(opts)
    opts = opts or {}
    local out = {}
    if SafeHouse and SafeHouse.getSafehouseList then
        local list = SafeHouse.getSafehouseList()
        for i = 0, (list and list:size() or 0) - 1 do
            local sh = list:get(i)
            local x, y = sh:getX(), sh:getY()
            out[#out + 1] = { x1 = x, y1 = y, x2 = x + sh:getW(), y2 = y + sh:getH(), source = "safehouse" }
        end
    end
    for _, p in ipairs(players()) do
        out[#out + 1] = pointRect(p:getX(), p:getY(), "player")
    end
    for _, a in ipairs(opts.avoid or {}) do
        if a.x1 then
            out[#out + 1] = { x1 = a.x1, y1 = a.y1, x2 = a.x2, y2 = a.y2, source = a.source or "avoid" }
        elseif a.x then
            out[#out + 1] = pointRect(a.x, a.y, a.source or "avoid")
        end
    end
    return out
end

local function nearestBase(rect, bases)
    local best, bestBase = nil, nil
    for _, base in ipairs(bases) do
        local d = gap(rect, base)
        if best == nil or d < best then best, bestBase = d, base end
    end
    return best, bestBase
end

local function inList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- Site point: centre of the first rectangle of a room, preferably a "main" room of the kind at level 0, else the
-- largest room at level 0 or above, else the first room.
local function sitePoint(rooms, rule)
    local best, bestScore = nil, nil
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        local z = room:getZ()
        if z >= 0 and room:getRects():size() > 0 then
            local name = string.lower(room:getName() or "")
            local score = room:getArea() - z * 10000
            if inList(rule.main, name) then score = score + 100000 end
            if bestScore == nil or score > bestScore then best, bestScore = room, score end
        end
    end
    if best == nil then return nil end
    local rect = best:getRects():get(0)
    local x = math.floor((rect:getX() + rect:getX2() - 1) / 2)
    local y = math.floor((rect:getY() + rect:getY2() - 1) / 2)
    return x, y, best:getZ()
end

local function onWater(grid, x, y)
    local zones = grid:getZonesAt(x, y, 0)
    for i = 0, (zones and zones:size() or 0) - 1 do
        if zones:get(i):getType() == "Water" then return true end
    end
    return false
end

local function insideMap(grid, x, y)
    if not grid:isValidSquare(x, y) then return false end
    return grid:getCellData(math.floor(x / CELL), math.floor(y / CELL)) ~= nil
end

-- Examines a BuildingDef: site (plain table), or nil and the refusal reason. opts.rules (optional) replaces the list
-- of admitted kinds (Sites.KINDS by default; same format): LivingKnox/LK_Sites adds the hideouts (LK08-T08).
function Sites.check(b, bases, opts, grid)
    opts = opts or {}
    if b == nil then return nil, "missing" end
    if b:isUserDefined() then return nil, "player-built" end
    if b:getRooms():size() == 0 or b:isBasement() then return nil, "no ground room" end
    local counts, rooms = roomCounts(b)
    local rule = firstRule(opts.rules or Sites.KINDS, counts)
    if rule == nil then return nil, "not habitable" end
    if b:getArea() < (opts.minArea or Sites.CONFIG.MIN_AREA) then return nil, "too small" end
    local id = b:getIDString()
    local key = "b" .. tostring(id)
    if opts.exclude and opts.exclude[key] then return nil, "excluded" end
    local rect = bounds(b)
    local d = nearestBase(rect, bases or {})
    if d ~= nil and d < (opts.minDistance or Sites.CONFIG.MIN_DISTANCE) then return nil, "near a known base" end
    local x, y, z = sitePoint(rooms, rule)
    if x == nil then return nil, "no ground room" end
    if not insideMap(grid, x, y) then return nil, "outside the map" end
    if onWater(grid, x, y) then return nil, "water" end
    return { x = x, y = y, z = z, buildingId = id, key = key, kind = rule.kind, label = rule.label,
             bounds = rect, baseDistance = d and math.floor(d) or nil }
end

local function reasonSummary(reasons)
    local keys = {}
    for k in pairs(reasons) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. reasons[k] end
    return table.concat(parts, ", ")
end

-- Draws a habitable building far from the known bases. opts (optional): seed, minDistance, maxAttempts, minArea,
-- avoid (list of { x, y } or { x1, y1, x2, y2 }), exclude (set of site keys already taken), noClues.
-- Returns the site, or nil and the reason.
function Sites.pick(opts)
    opts = opts or {}
    local grid = metaGrid()
    if grid == nil then return nil, "no metagrid" end
    local list = grid:getBuildings()
    local n = list and list:size() or 0
    if n == 0 then return nil, "no building in the metagrid" end
    local bases = Sites.knownBases(opts)
    local draw = drawer(opts.seed)
    local maxAttempts = opts.maxAttempts or Sites.CONFIG.MAX_ATTEMPTS
    local reasons = {}
    for attempt = 1, maxAttempts do
        local b = list:get(draw(n))
        local site, why = Sites.check(b, bases, opts, grid)
        if site then
            site.attempts = attempt
            if not opts.noClues then site.clues, site.clueData = Sites.clueData(b, grid) end
            log("picked a " .. site.kind .. " (" .. site.key .. ") after " .. attempt .. " draw(s)")
            return site
        end
        reasons[why] = (reasons[why] or 0) + 1
    end
    local reason = "no suitable building after " .. maxAttempts .. " draw(s): " .. reasonSummary(reasons)
    log(reason)
    return nil, reason
end

-- Clues ----------------------------------------------------------------------------------------------------------

local NUMBER_WORDS = { "two", "three", "four", "five" }
-- Neighbours counted as houses (clue "built-up street" or "isolated").
local RESIDENTIAL = { house = true, house_garage = true, farmhouse = true, apartments = true }

local function sizeWord(area)
    if area < 60 then return "small " end
    if area < 200 then return "" end
    if area < 500 then return "large " end
    return "very large "
end

local function floorsWord(b)
    local top = b:getMaxLevel()
    local bottom = math.max(0, b:getMinLevel())
    local levels = top - bottom + 1
    if levels <= 1 then return "single-storey " end
    if levels <= #NUMBER_WORDS + 1 then return NUMBER_WORDS[levels - 1] .. "-storey " end
    return "tall "
end

local function article(word)
    local c = string.sub(word, 1, 1)
    if c == "a" or c == "e" or c == "i" or c == "o" or c == "u" then return "an " end
    return "a "
end

-- Direction in words from point (x, y) to (tx, ty); north is towards decreasing y.
local function direction(x, y, tx, ty)
    local dx, dy = tx - x, ty - y
    local ax, ay = math.abs(dx), math.abs(dy)
    local ns = dy < 0 and "north" or "south"
    local ew = dx < 0 and "west" or "east"
    if ax > ay * 2.4 then return ew end
    if ay > ax * 2.4 then return ns end
    return ns .. "-" .. ew
end
Sites.direction = direction

local function distanceWords(d)
    if d < 25 then return "right next to it" end
    if d < 80 then return "a short walk" end
    return "a few blocks"
end

-- Buildings of the metagrid whose footprint crosses the rectangle (r around rect), b itself excluded. Asks only the
-- covered cells (IsoMetaGrid:getBuildingsIntersecting walks the whole grid).
function Sites.nearbyBuildings(grid, b, r)
    local rect = bounds(b)
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
    local id = b:getIDString()
    for i = 0, found:size() - 1 do
        local other = found:get(i)
        if other:getIDString() ~= id then out[#out + 1] = other end
    end
    return out
end

local function hasDigits(s)
    return string.find(s, "%d") ~= nil
end
Sites.hasDigits = hasDigits

-- Word codes of a clue (E11-T09: clues translated by the notebook, IGUI_RS_ClueSize_<code>,
-- IGUI_RS_ClueFloors_<code>, IGUI_RS_Dir_<code>, IGUI_RS_ClueDistance_<code>).
local SIZE_CODES = { ["small "] = "small", [""] = "medium", ["large "] = "large", ["very large "] = "very_large" }
local FLOOR_CODES = { ["single-storey "] = "single", ["two-storey "] = "two", ["three-storey "] = "three",
    ["four-storey "] = "four", ["five-storey "] = "five", ["tall "] = "tall" }
local DISTANCE_CODES = { ["a short walk"] = "short", ["a few blocks"] = "blocks" }

-- Town clue: { English text, key, name } or nil.
local function townData(cx, cy)
    local ok, dirs = pcall(getLotDirectories)
    local vanilla = false
    if ok and dirs then
        for i = 0, dirs:size() - 1 do
            if dirs:get(i) == Sites.CONFIG.VANILLA_MAP then vanilla = true break end
        end
    end
    if not vanilla then return nil end
    local best, bestD = nil, nil
    for _, town in ipairs(Sites.TOWNS) do
        local dx, dy = town.x - cx, town.y - cy
        local d = math.sqrt(dx * dx + dy * dy) / town.r
        if bestD == nil or d < bestD then best, bestD = town, d end
    end
    if best == nil then return nil end
    if bestD <= 0.5 then return "It is in " .. best.name .. ".", "TownIn", best.name end
    if bestD <= 1 then return "It is on the outskirts of " .. best.name .. ".", "TownOutskirts", best.name end
    if bestD <= 2 then return "It is out in the country, some way from " .. best.name .. ".", "TownCountry", best.name end
    return "It is out in the countryside, far from any town.", "TownFar", nil
end
-- Exposed for the fact log (RS_Facts, E14-T01): place rounded to the town, same rule as the clues.
Sites.town = townData

-- Clues of a BuildingDef in two parallel lists: English sentences without digits (bridge prompt) and translatable
-- data { key = <suffix of IGUI_RS_Clue_>, args = { codes or proper name } } (notebook, E11-T09). A sentence that
-- holds a digit is dropped with its data.
function Sites.clueData(b, grid)
    grid = grid or metaGrid()
    local counts = roomCounts(b)
    local rule = firstRule(Sites.KINDS, counts) or { kind = "building", label = "building" }
    local out, data = {}, {}
    local function add(text, key, args)
        out[#out + 1] = text
        data[#data + 1] = { key = key, args = args or {} }
    end
    local size, floors = sizeWord(b:getArea()), floorsWord(b)
    local words = size .. floors .. rule.label
    add("The shelter is " .. article(words) .. words .. ".", "Kind",
        { rule.kind, SIZE_CODES[size] or "medium", FLOOR_CODES[floors] or "tall" })
    if b:getMinLevel() < 0 then add("It has a basement.", "Basement") end
    local rect = bounds(b)
    local cx, cy = (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2
    local nearest, houses = {}, 0
    if grid then
        for _, other in ipairs(Sites.nearbyBuildings(grid, b, Sites.CONFIG.LANDMARK_RADIUS)) do
            local mark = Sites.landmarkOf(other)
            local orect = bounds(other)
            if mark then
                local d = gap(rect, orect)
                local prev = nearest[mark.kind]
                if prev == nil or d < prev.d then
                    nearest[mark.kind] = { d = d, kind = mark.kind, label = mark.label,
                        dir = direction(cx, cy, (orect.x1 + orect.x2) / 2, (orect.y1 + orect.y2) / 2) }
                end
            elseif gap(rect, orect) < 80 and RESIDENTIAL[(Sites.classify(other) or {}).kind or ""] then
                houses = houses + 1
            end
        end
    end
    local marks = {}
    for _, m in pairs(nearest) do marks[#marks + 1] = m end
    table.sort(marks, function(a, b2)
        if a.d ~= b2.d then return a.d < b2.d end
        return a.label < b2.label
    end)
    for i = 1, math.min(#marks, Sites.CONFIG.MAX_LANDMARKS) do
        local m = marks[i]
        local dir = (string.gsub(m.dir, "-", "_"))
        if m.d < 25 then
            add("There is " .. m.label .. " right next to it, to the " .. m.dir .. ".", "LandmarkNext", { m.kind, dir })
        else
            local words2 = distanceWords(m.d)
            add("There is " .. m.label .. " " .. words2 .. " to the " .. m.dir .. ".", "Landmark",
                { m.kind, DISTANCE_CODES[words2] or "blocks", dir })
        end
    end
    if #marks == 0 then add("There is no shop or public building nearby.", "NoLandmark") end
    if houses == 0 then
        add("It stands on its own, with no other house close by.", "Isolated")
    elseif houses <= 4 then
        add("There are a few other houses around it.", "FewHouses")
    else
        add("It is in a built-up street, among many houses.", "BuiltUp")
    end
    local town, key, name = townData(cx, cy)
    if town then add(town, key, { name }) end
    local clean, cleanData = {}, {}
    for i, line in ipairs(out) do
        if not hasDigits(line) then
            clean[#clean + 1] = line
            cleanData[#cleanData + 1] = data[i]
        end
    end
    return clean, cleanData
end

-- Descriptive clues of a BuildingDef (list of English sentences without digits).
function Sites.clues(b, grid)
    return (Sites.clueData(b, grid))
end

return Sites
