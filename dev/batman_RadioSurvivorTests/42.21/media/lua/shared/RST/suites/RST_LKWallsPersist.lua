--[[
lk.walls persistence steps (LK14-T04, E01-T17: "mur conserve apres reconnexion et redemarrage";
server/LivingKnox/LK_Fortify.lua: plan, entityInfo, placeStructure). Short variant of lk.walls: the segment is placed
directly by Fortify.placeStructure (what Fortify.buildStep does once the materials are taken), without a builder.
Played by autoclient.py --mp --phases reconnect,restart --server-campaign mp-persist (base lk.walls):
    lk.walls.before            (opt-in "manual") a "settlers" group at home on the requester's square (inside a house,
                               no furnishing), the first ring wall site of its fortification plan gets a
                               WoodenWallLvl1 at full health; group, site, health and the corner posts around the edge
                               written to the snapshot. Run again while the group and its wall still exist (the
                               launcher takes a fresh snapshot after a reconnection): kept as they are, snapshot
                               written again. Otherwise what an older snapshot left is removed first.
    lk.walls.after-reconnect   same session: one WoodenWallLvl1 and no frame on the edge, same health, same corner
                               posts, the site counted as built by a new plan; the other clients see the wall
                               (RST.PeerChecks.checkSquares). Nothing removed.
    lk.walls.after-restart     the same after a real restart of the dedicated server; then the wall, the corner posts
                               added by the test and the group are removed, the snapshot consumed.
Tags "world", "server", "manual": authority only, test saves rstest* only, exact names only. Snapshot:
Zomboid/Lua/batman_RadioSurvivor/tests/walls-persist.txt of the server (RST_Persist).
Outside the game: tests/test_persist_suites.py (listing).
]]

require "RST/RST"
require "RST/RST_Persist"
require "RST/RST_PeerChecks"

RST.LKWallsPersist = RST.LKWallsPersist or {}
local WP = RST.LKWallsPersist
WP.FILE = "walls-persist.txt"
WP.HEADER = "LKWALLS1"
WP.WALL = "WoodenWallLvl1"
WP.FRAME = "WoodenWallFrame"
WP.SQUARE_MS = 60000

local function LK() return LivingKnox end
local function F() return LivingKnox.Fortify end

local function modules(t)
    if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
    local E = LK()
    t:ok(E ~= nil and E.Fortify ~= nil and E.Fortify.placeStructure ~= nil and E.Fortify.entityInfo ~= nil
        and E.Homes ~= nil, "LivingKnox fortification (Fortify.placeStructure, Homes) is not loaded")
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

-- Structures named name on the edge of a site (square of the site, same face).
function WP.onEdge(site, name)
    local sq = getCell():getGridSquare(site.x, site.y, site.z)
    local out = {}
    if sq == nil then return out end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == (site.north == true) and o:getName() == name then
            out[#out + 1] = o
        end
    end
    return out
end

-- Corner posts around the edge of a site (squares x..x+1, y..y+1): list of { x, y, o }.
function WP.corners(site)
    local out = {}
    for dy = 0, 1 do
        for dx = 0, 1 do
            local sq = getCell():getGridSquare(site.x + dx, site.y + dy, site.z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoThumpable") and o:isCorner() then
                        out[#out + 1] = { x = site.x + dx, y = site.y + dy, o = o }
                    end
                end
            end
        end
    end
    return out
end

local function cornerKeys(list)
    local keys = {}
    for _, c in ipairs(list) do keys[#keys + 1] = c.x .. "," .. c.y end
    table.sort(keys)
    return keys
end

-- Removes the wall (and any frame) of the site, the corner posts not listed in pre, and the group.
local function removeAll(E, snap)
    local n = 0
    local site = snap.site
    local sq = site and getCell():getGridSquare(site.x, site.y, site.z)
    if sq ~= nil then
        for _, name in ipairs({ WP.WALL, WP.FRAME }) do
            for _, o in ipairs(WP.onEdge(site, name)) do
                sq:transmitRemoveItemFromSquare(o)
                n = n + 1
            end
        end
        local keep = {}
        for _, k in ipairs(snap.cornersPre or {}) do keep[k] = true end
        for _, c in ipairs(WP.corners(site)) do
            if not keep[c.x .. "," .. c.y] and c.o:getSquare() ~= nil then
                c.o:getSquare():transmitRemoveItemFromSquare(c.o)
                n = n + 1
            end
        end
    end
    if snap.gid ~= nil and E.Groups.get(snap.gid) ~= nil then E.Groups.remove(snap.gid) end
    F().reset()
    return n
end

-- State of the edge now: wall count, frames, health, max health, corner keys.
local function edgeState(site)
    local walls = WP.onEdge(site, WP.WALL)
    local w = walls[1]
    return { walls = #walls, frames = #WP.onEdge(site, WP.FRAME), health = w and w:getHealth() or nil,
        maxHealth = w and w:getMaxHealth() or nil, corners = cornerKeys(WP.corners(site)) }
end

-- Snapshot still usable: group present, one wall on its edge.
local function alive(E, snap)
    if type(snap) ~= "table" or type(snap.site) ~= "table" or E.Groups.get(snap.gid) == nil then return false end
    if getCell():getGridSquare(snap.site.x, snap.site.y, snap.site.z) == nil then return false end
    return #WP.onEdge(snap.site, WP.WALL) == 1
end

local function writeSnap(t, snap)
    local ok, werr = RST.Persist.write(WP.FILE, WP.HEADER, snap)
    t:ok(ok, werr)
    local back, rerr = RST.Persist.read(WP.FILE, WP.HEADER)
    t:ok(back ~= nil and back.gid == snap.gid and back.site.id == snap.site.id, "snapshot: " .. tostring(rerr))
end

RST.suite("lk.walls.before", { tags = { "world", "server", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("ring wall segment placed, written to the snapshot", function(t)
        local E = modules(t)
        local old = RST.Persist.read(WP.FILE, WP.HEADER)
        if old and alive(E, old) then
            local st = edgeState(old.site)
            old.health, old.maxHealth, old.corners = st.health, st.maxHealth, st.corners
            writeSnap(t, old)
            t:note("group " .. old.gid .. " and its wall on " .. old.site.id .. " kept: snapshot written again")
            return
        elseif old and type(old.site) == "table" then
            t:note(removeAll(E, old) .. " structure(s) of an older snapshot removed")
        end
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST walls persist", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)
        local snap = { gid = gid, home = home }
        local plan = F().plan(gid, { force = true })
        if plan == nil or plan.outerSkipped ~= nil then
            G.remove(gid)
            t:skip("no ring around this house: " .. tostring(plan and plan.outerSkipped or "no plan"))
        end
        local site
        for _, st in ipairs(plan.sites) do
            if site == nil and st.kind == "wall" and not st.done and (st.have or 0) == 0 then site = st end
        end
        if site == nil then
            G.remove(gid)
            t:skip("no free wall segment left around this house")
        end
        snap.site = { x = site.x, y = site.y, z = site.z, north = site.north == true, id = site.id }
        snap.cornersPre = cornerKeys(WP.corners(snap.site))
        local esq = getCell():getGridSquare(site.x, site.y, site.z)
        t:ok(esq ~= nil, "edge square not loaded")
        local info, sprite = F().entityInfo(WP.WALL, site.north == true)
        t:ok(info ~= nil, "entity " .. WP.WALL .. ": " .. tostring(sprite))
        F().placeStructure(esq, site.north == true, info, sprite, nil)
        F().invalidate(gid)
        local st = edgeState(snap.site)
        t:eq(1, st.walls, WP.WALL .. " on the edge of " .. site.id)
        t:ok(st.maxHealth ~= nil and st.maxHealth > 0 and st.health == st.maxHealth, "wall at full health")
        snap.health, snap.maxHealth, snap.corners = st.health, st.maxHealth, st.corners
        writeSnap(t, snap)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z .. ": wall on " .. site.id
            .. " (" .. st.health .. "/" .. st.maxHealth .. "), corner posts " .. table.concat(st.corners, " "))
    end)
end)

-- Common check of the after steps; then(t) runs once the clients were asked (or at once without other client).
local function checkKept(t, E, snap, label)
    local site = snap.site
    t:waitUntil(function() return getCell():getGridSquare(site.x, site.y, site.z) ~= nil end, WP.SQUARE_MS,
        function(t2)
            t2:ok(E.Groups.get(snap.gid) ~= nil, "group " .. snap.gid .. " lost " .. label)
            local st = edgeState(site)
            t2:note(label .. ": walls " .. st.walls .. ", frames " .. st.frames .. ", health " .. tostring(st.health)
                .. "/" .. tostring(st.maxHealth) .. ", corner posts " .. table.concat(st.corners, " "))
            t2:eq(1, st.walls, WP.WALL .. " on the edge " .. label)
            t2:eq(0, st.frames, "frame on the edge " .. label)
            t2:eq(snap.maxHealth, st.maxHealth, "max health " .. label)
            t2:eq(snap.health, st.health, "health " .. label)
            t2:eq(snap.corners, st.corners, "corner posts " .. label)
            local plan = F().plan(snap.gid, { force = true })
            if plan ~= nil then
                for _, s2 in ipairs(plan.sites) do
                    if s2.id == site.id then t2:ok(s2.done == true, "site " .. site.id .. " not counted as built") end
                end
            end
            local around = {}
            for dy = -1, 1 do
                for dx = -1, 1 do around[#around + 1] = { x = site.x + dx, y = site.y + dy, z = site.z } end
            end
            RST.PeerChecks.checkSquares(t2, around, { thumpable = { WP.WALL, WP.FRAME } })
        end, "edge square " .. site.id .. " not loaded (the requester must be back in the house)")
end

RST.suite("lk.walls.after-reconnect", { tags = { "world", "server", "manual" }, testTimeoutMs = 90000 }, function(s)
    s.test("same wall after the reconnection, seen by every client", function(t)
        local E = modules(t)
        local snap, why = RST.Persist.read(WP.FILE, WP.HEADER)
        t:ok(snap ~= nil and type(snap.site) == "table", why or "snapshot without site")
        checkKept(t, E, snap, "after the reconnection")
    end)
end)

RST.suite("lk.walls.after-restart", { tags = { "world", "server", "manual" }, testTimeoutMs = 90000 }, function(s)
    s.test("same wall after the restart, seen by every client", function(t)
        local E = modules(t)
        local snap, why = RST.Persist.read(WP.FILE, WP.HEADER)
        t:ok(snap ~= nil and type(snap.site) == "table", why or "snapshot without site")
        t:defer(function()
            removeAll(E, snap)
            RST.Persist.consume(WP.FILE)
        end, "remove the wall, new corner posts and group " .. snap.gid)
        checkKept(t, E, snap, "after the restart")
    end)
end)
