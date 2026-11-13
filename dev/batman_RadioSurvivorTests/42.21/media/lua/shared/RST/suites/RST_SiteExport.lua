--[[
site.export - export of the loaded site around the requesting player, replayed by the offline bench (E19-T08, ADR
banc mimetique D05). Tags "world" and "manual": the authority only (solo or dedicated server), on a save named
rstest*, never part of a campaign (opt-in: exact name). Reads the world, changes nothing.
Solo (autoclient): python tools/autoclient/autoclient.py --save <rstest save> --suite site.export --tags world
Dedicated server: RST.server({ suite = "site.export", tags = "world" }) from an admin client standing on the site.

Every loaded square within RADIUS squares (Chebyshev) of the player, levels LEVELS, is read with the 42.22 API
(IsoGridSquare isFree, TreatAsSolidFloor, isOutside, getRoom, isWallTo, getDoorTo, getWindowTo,
getWindowThumpableTo, getWindowFrameTo, isHoppableTo, HasStairs...), ROWS_PER_STEP columns of squares per tick
(t:sleep chain), then ONE text file is written with RST.writeLines (getFileWriter, Zomboid/Lua of the machine running
the Lua): FILE. Through autoclient the file is copied to the run folder (tools/autoclient/runs/<run>/). The export
describes a game building: it stays local, never versioned (tests/site_world.py reads it).

Format: ASCII, one record per line, fields separated by one space; "-" = none; flags = comma list or "-". Edge E is
"W" (west edge of the square x, y: between x - 1 and x) or "N" (north edge: between y - 1 and y), the edge keys of
the bench doubles (tests/test_lk_obstacles.py).
    H ox oy oz radius version...              origin (player square), radius, game version (rest of the line)
    G id keyId x1 y1 x2 y2                    building (BuildingDef getIDString, getKeyId, getX, getY, getX2, getY2)
    S x y z building roomId room flags        square; flags among blocked (not isFree(false)), solid, solidtrans,
                                              nofloor (not TreatAsSolidFloor), outside, tree, bush, water
    W x y z E                                 wall (isWallTo)
    D x y z E cls keyId ddi gdi flags         door (getDoorTo); cls door (IsoDoor) | thump (IsoThumpable); getKeyId;
                                              IsoDoor.getDoubleDoorIndex / getGarageDoorIndex; flags among open,
                                              locked, lockedByKey, barricaded, hoppable, tall, obstructed, padlock,
                                              forceLocked
    O x y z E cls flags                       window (getWindowTo: window; getWindowThumpableTo: built;
                                              getWindowFrameTo: frame, first found); flags among open, locked,
                                              smashed, barricaded, permaLocked, invincible
    F x y z E                                 low fence: isHoppableTo without a door on the edge
    C x y z type                              container of an object (getContainerByIndex(i):getType())
    B x y z bedType                           bed (sprite property bed, BedType or -)
    T x y z                                   stairs (HasStairs)
Tunables (debug console before the run): RST.SiteExport.RADIUS, LEVELS, ROWS_PER_STEP.
Outside the game: tests/test_site_replay.py (round trip of this exporter on the bench doubles).
]]

require "RST/RST"

local X = RST.SiteExport or {}
RST.SiteExport = X

X.RADIUS = X.RADIUS or 70
X.LEVELS = X.LEVELS or { 0, 1 }
X.ROWS_PER_STEP = X.ROWS_PER_STEP or 4
X.FILE = RST.FILE_DIR .. "site-export.txt"

local function word(v)
    if v == nil then return "-" end
    local s = string.gsub(tostring(v), "%s+", "_")
    if s == "" then return "-" end
    return s
end

local function flagList(obj, readers)
    local out = {}
    for _, r in ipairs(readers) do
        if r[2](obj) == true then out[#out + 1] = r[1] end
    end
    if #out == 0 then return "-" end
    return table.concat(out, ",")
end

local function at(x, y, z) return x .. " " .. y .. " " .. z end

local function isThump(o) return instanceof(o, "IsoThumpable") end

-- ---------------------------------------------------------------- squares

X.SQUARE_FLAGS = {
    { "blocked", function(sq) return not sq:isFree(false) end },
    { "solid", function(sq) return sq:isSolid() end },
    { "solidtrans", function(sq) return sq:isSolidTrans() end },
    { "nofloor", function(sq) return not sq:TreatAsSolidFloor() end },
    { "outside", function(sq) return sq:isOutside() end },
    { "tree", function(sq) return sq:HasTree() end },
    { "bush", function(sq) return sq:hasBush() end },
    { "water", function(sq) return sq:isWaterSquare() end },
}

local function buildingLine(job, def)
    if def == nil then return end
    local id = def:getIDString()
    if job.buildings[id] then return end
    job.buildings[id] = true
    job.lines[#job.lines + 1] = "G " .. word(id) .. " " .. def:getKeyId() .. " " .. def:getX() .. " " .. def:getY()
        .. " " .. def:getX2() .. " " .. def:getY2()
end

local function squareLine(job, sq, x, y, z)
    local def = sq:getBuildingDef()
    buildingLine(job, def)
    local room = sq:getRoom()
    local rdef = room ~= nil and room:getRoomDef() or nil
    return "S " .. at(x, y, z) .. " " .. word(def and def:getIDString()) .. " " .. word(rdef and rdef:getIDString())
        .. " " .. word(room and room:getName()) .. " " .. flagList(sq, X.SQUARE_FLAGS)
end

local function stairsLine(job, sq, x, y, z)
    if sq:HasStairs() then return "T " .. at(x, y, z) end
    return nil
end

-- Objects of the square: containers and beds.
local function objectLines(job, sq, x, y, z)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        for c = 0, o:getContainerCount() - 1 do
            local cont = o:getContainerByIndex(c)
            if cont ~= nil then job.lines[#job.lines + 1] = "C " .. at(x, y, z) .. " " .. word(cont:getType()) end
        end
        local props = o:getSprite() ~= nil and o:getProperties() or nil
        if props ~= nil and IsoFlagType ~= nil and props:has(IsoFlagType.bed) then
            job.lines[#job.lines + 1] = "B " .. at(x, y, z) .. " " .. word(props:get("BedType"))
        end
    end
    return nil
end

-- Square describers, in order: each returns one line or nil (and may append more lines itself).
X.SQUARE_RECORDS = { squareLine, stairsLine, objectLines }

-- ---------------------------------------------------------------- edges

X.DOOR_FLAGS = {
    { "open", function(d) return d:IsOpen() end },
    { "locked", function(d) return d:isLocked() end },
    { "lockedByKey", function(d) return d:isLockedByKey() end },
    { "barricaded", function(d) return d:isBarricaded() end },
    { "hoppable", function(d) return d:isHoppable() end },
    { "tall", function(d) return d:isTallHoppable() end },
    { "obstructed", function(d) return d:isObstructed() end },
    { "padlock", function(d) return isThump(d) and d:isLockedByPadlock() end },
    { "forceLocked", function(d)
        local props = d:getProperties()
        return props ~= nil and props:has("forceLocked")
    end },
}

local WINDOW_FULL = {
    { "open", function(w) return w:IsOpen() end },
    { "locked", function(w) return w:isLocked() end },
    { "smashed", function(w) return w:isSmashed() end },
    { "barricaded", function(w) return w:isBarricaded() end },
    { "permaLocked", function(w) return w:isPermaLocked() end },
    { "invincible", function(w) return w:isInvincible() end },
}
local WINDOW_BUILT = {
    { "open", function(w) return w:IsOpen() end },
    { "locked", function(w) return w:isLocked() end },
    { "barricaded", function(w) return w:isBarricaded() end },
}
local WINDOW_FRAME = {
    { "barricaded", function(w) return w:isBarricaded() end },
}

-- Window kinds of an edge, first found wins (same order as LivingKnox.Obstacles.windowOf).
X.WINDOW_KINDS = {
    { cls = "window", find = function(sq, nb) return sq:getWindowTo(nb) end, flags = WINDOW_FULL },
    { cls = "built", find = function(sq, nb) return sq:getWindowThumpableTo(nb) end, flags = WINDOW_BUILT },
    { cls = "frame", find = function(sq, nb) return sq:getWindowFrameTo(nb) end, flags = WINDOW_FRAME },
}

local function wallLine(sq, nb, where)
    if sq:isWallTo(nb) then return "W " .. where end
    return nil
end

local function doorLine(sq, nb, where)
    local d = sq:getDoorTo(nb)
    if d == nil then return nil end
    return "D " .. where .. " " .. (isThump(d) and "thump" or "door") .. " " .. d:getKeyId() .. " "
        .. IsoDoor.getDoubleDoorIndex(d) .. " " .. IsoDoor.getGarageDoorIndex(d) .. " " .. flagList(d, X.DOOR_FLAGS)
end

local function windowLine(sq, nb, where)
    for _, k in ipairs(X.WINDOW_KINDS) do
        local w = k.find(sq, nb)
        if w ~= nil then return "O " .. where .. " " .. k.cls .. " " .. flagList(w, k.flags) end
    end
    return nil
end

local function fenceLine(sq, nb, where)
    if sq:isHoppableTo(nb) and sq:getDoorTo(nb) == nil then return "F " .. where end
    return nil
end

-- Edge describers: function(square, neighbour, "x y z E") -> line or nil.
X.EDGE_RECORDS = { wallLine, doorLine, windowLine, fenceLine }

-- West ("W") and north ("N") edges of a square: neighbour offsets.
X.EDGES = { { "W", -1, 0 }, { "N", 0, -1 } }

-- ---------------------------------------------------------------- walk

local function describe(job, cell, sq, x, y, z)
    local lines = job.lines
    for _, f in ipairs(X.SQUARE_RECORDS) do
        local line = f(job, sq, x, y, z)
        if line ~= nil then lines[#lines + 1] = line end
    end
    for _, e in ipairs(X.EDGES) do
        local nb = cell:getGridSquare(x + e[2], y + e[3], z)
        if nb ~= nil then
            local where = at(x, y, z) .. " " .. e[1]
            for _, f in ipairs(X.EDGE_RECORDS) do
                local line = f(sq, nb, where)
                if line ~= nil then lines[#lines + 1] = line end
            end
        end
    end
    job.squares = job.squares + 1
end

local function version()
    if type(getCore) ~= "function" then return "unknown" end
    local core = getCore()
    return core ~= nil and tostring(core:getVersion()) or "unknown"
end

-- New export job around the square (ox, oy, oz), radius r: { lines, squares, ... }; X.advance walks it.
function X.newJob(ox, oy, oz, r)
    local job = { ox = ox, oy = oy, oz = oz, r = r, lines = {}, buildings = {}, squares = 0, rows = {}, next = 1 }
    job.lines[1] = "H " .. at(ox, oy, oz) .. " " .. r .. " " .. string.gsub(version(), "[\r\n]", " ")
    for _, z in ipairs(X.LEVELS) do
        for x = ox - r, ox + r do job.rows[#job.rows + 1] = { x = x, z = z } end
    end
    return job
end

-- Walks at most n columns (x, z) of the job; true when every column is done.
function X.advance(job, n)
    local cell = getCell()
    local last = math.min(#job.rows, job.next + n - 1)
    for i = job.next, last do
        local row = job.rows[i]
        for y = job.oy - job.r, job.oy + job.r do
            local sq = cell:getGridSquare(row.x, y, row.z)
            if sq ~= nil then describe(job, cell, sq, row.x, y, row.z) end
        end
    end
    job.next = last + 1
    return job.next > #job.rows
end

local function count(lines, kind)
    local n = 0
    for _, line in ipairs(lines) do
        if string.sub(line, 1, 2) == kind .. " " then n = n + 1 end
    end
    return n
end

RST.suite("site.export", { tags = { "world", "manual" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("loaded site written to the export file", function(t)
        if type(isClient) == "function" and isClient() then
            t:skip("site.export reads the world of the authority (solo or dedicated server)")
        end
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local job = X.newJob(math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), X.RADIUS)
        local function step(t2)
            if not X.advance(job, X.ROWS_PER_STEP) then
                t2:sleep(0, step)
                return
            end
            local ok, err = RST.writeLines(X.FILE, job.lines)
            t2:ok(ok, err)
            t2:ok(job.squares > 0, "no loaded square around the player")
            t2:note("site " .. job.ox .. "," .. job.oy .. "," .. job.oz .. " radius " .. job.r .. ": " .. job.squares
                .. " squares, " .. count(job.lines, "G") .. " buildings, " .. count(job.lines, "D") .. " doors, "
                .. count(job.lines, "O") .. " windows, " .. count(job.lines, "F") .. " fences, "
                .. count(job.lines, "W") .. " walls -> Zomboid/Lua/" .. X.FILE)
            print("[RST] site export written: " .. #job.lines .. " lines to Zomboid/Lua/" .. X.FILE)
        end
        step(t)
    end)
end)
