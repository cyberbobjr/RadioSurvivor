--[[
rs.rescue.missed persistence steps (E12-T05, E01-T17: "aucun doublon de zombies ni de cahier apres un vrai
redemarrage"; server/RadioSurvivor/RS_RescueLost.lua). rs.rescue.missed only simulates the stop; these steps go
through a real restart of the dedicated server (autoclient.py --mp --phases restart --server-campaign mp-persist,
base rs.rescue.missed):
    rs.rescue.missed.before         (opt-in "manual") a rescue of the requester's team in a WORK store
                                    (RS_Rescue.useStore), on the building where the requester stands, reserves
                                    consumed to zero ("missed"), the scene placed by RS_RescueLost.poll: one zombie
                                    per survivor (reanimated player, ModData RS_RescueBody) in the outfit described,
                                    the requester's zombie carrying the locked last pages. The whole work store is
                                    written to the snapshot (it stands in for the private notebook state). The
                                    zombies stay in the world (saved by the server with reanimated.bin). Run again:
                                    the zombies of the previous snapshot are removed first.
    rs.rescue.missed.after-restart  the work store of the snapshot set again: the zombies of the rescue come back
                                    with their chunk (waited for up to RETURN_MS); exactly one per survivor (its
                                    living zombie, or its marked corpse in the building when it was killed, e.g. by
                                    the Living Knox NPCs the other steps settle in the same house), one notebook
                                    among them, carried by the requester; a poll places nothing; a stop
                                    between "placing" and "placed" adopts them (still the same count, one notebook).
                                    Then zombies and marked corpses are removed and the snapshot consumed.
Tags "server", "world", "manual": authority only, test saves rstest* only, exact names only. The requester stands
INSIDE a building of the map, with a few free squares around the room centre; the background polls of
RS_RescueVisit and RS_RescueLost are paused during each step. The players are next to awake zombies between the steps
(the launcher puts them in god mode).
Snapshot: Zomboid/Lua/batman_RadioSurvivor/tests/rescue-persist.txt of the server (RST_Persist).
Outside the game: tests/test_persist_suites.py (listing; the placement itself: tests/test_rescue_lost.py).
]]

require "RST/RST"
require "RST/RST_Persist"

RST.RescuePersist = RST.RescuePersist or {}
local RP = RST.RescuePersist
RP.FILE = "rescue-persist.txt"
RP.HEADER = "RSRESCUE1"
RP.RETURN_MS = 60000

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Rescue is not loaded on an MP client (authority only)")
    end
    local R = require "RadioSurvivor/RS_Rescue"
    local L = require "RadioSurvivor/RS_RescueLost"
    local V = require "RadioSurvivor/RS_RescueVisit"
    if type(R) ~= "table" or type(L) ~= "table" or type(V) ~= "table" then
        t:skip("RS_Rescue, RS_RescueLost or RS_RescueVisit did not return its table here")
    end
    return R, L, V
end

-- Background polls paused for the step; returns the real RS_RescueLost.poll.
local function pause(t, L, V)
    local vpoll, lpoll = V.poll, L.poll
    V.poll = function() return false end
    L.poll = function() return false end
    V.resetForTests()
    L.resetForTests()
    t:defer(function()
        V.poll, L.poll = vpoll, lpoll
        V.resetForTests()
        L.resetForTests()
    end, "resume the visit and too-late polls")
    return lpoll
end

local function markIndex(L, o, prefix)
    if not o:hasModData() then return nil end
    local mark = o:getModData()[L.CONFIG.BODY_MARK]
    if type(mark) ~= "string" or string.sub(mark, 1, #prefix) ~= prefix then return nil end
    return tonumber(string.sub(mark, #prefix + 1))
end

-- Living zombies of the zombie list marked for the rescue: list of { index, zombie }.
function RP.zombies(L, id)
    local out = {}
    local list = getCell():getZombieList()
    local prefix = id .. "#"
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        local index = zed ~= nil and not zed:isDead() and markIndex(L, zed, prefix) or nil
        if index then out[#out + 1] = { index = index, zombie = zed } end
    end
    return out
end

-- Marked corpses of the rectangle (floor z).
local function corpses(L, b, z, id)
    local out = {}
    local cell = getCell()
    local prefix = id .. "#"
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            local objects = sq and sq:getStaticMovingObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                if instanceof(o, "IsoDeadBody") and markIndex(L, o, prefix) then out[#out + 1] = o end
            end
        end
    end
    return out
end

local function notebooks(container)
    local n = 0
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        if items:get(i):getFullType() == "Base.Notebook" then n = n + 1 end
    end
    return n
end

-- Notebooks carried by the marked zombies: total, and those of the requester (index 1).
local function pages(found)
    local total, requester = 0, 0
    for _, e in ipairs(found) do
        local n = notebooks(e.zombie:getInventory())
        total = total + n
        if e.index == 1 then requester = requester + n end
    end
    return total, requester
end

-- Survivors of the rescue back in the world: living marked zombies, then marked corpses of the site (killed meanwhile,
-- for example by Living Knox NPCs of other steps defending the same building). List of { index, holder, zombie }, one
-- per index.
function RP.survivors(L, snap)
    local out, seen = {}, {}
    for _, e in ipairs(RP.zombies(L, snap.id)) do
        if not seen[e.index] then
            seen[e.index] = true
            out[#out + 1] = { index = e.index, holder = e.zombie:getInventory(), zombie = e.zombie }
        end
    end
    if snap.bounds then
        local prefix = snap.id .. "#"
        for _, body in ipairs(corpses(L, snap.bounds, snap.z or 0, snap.id)) do
            local index = markIndex(L, body, prefix)
            if index and not seen[index] then
                seen[index] = true
                out[#out + 1] = { index = index, holder = body:getContainer() }
            end
        end
    end
    return out
end

-- Notebooks among the survivors found: total, and those of the requester (index 1).
local function survivorPages(found)
    local total, requester = 0, 0
    for _, e in ipairs(found) do
        local n = notebooks(e.holder)
        total = total + n
        if e.index == 1 then requester = requester + n end
    end
    return total, requester
end

local function removeScene(L, snap)
    local n = 0
    for _, e in ipairs(RP.zombies(L, snap.id)) do
        e.zombie:setHealth(0)   -- a reanimated player only removed would come back with its chunk
        e.zombie:removeFromWorld()
        e.zombie:removeFromSquare()
        n = n + 1
    end
    if snap.bounds then
        for _, body in ipairs(corpses(L, snap.bounds, snap.z or 0, snap.id)) do
            body:getSquare():removeCorpse(body, false)
            n = n + 1
        end
    end
    return n
end

RST.suite("rs.rescue.missed.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("too-late scene placed, work store written to the snapshot", function(t)
        local R, L, V = modules(t)
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local old = RST.Persist.read(RP.FILE, RP.HEADER)
        if old and type(old.id) == "string" then
            t:note(removeScene(L, old) .. " zombie(s) or corpse(s) of the previous snapshot removed")
        end
        local poll = pause(t, L, V)
        local grid = getWorld():getMetaGrid()
        local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local def = grid:getBuildingAt(x, y, z)
        if def == nil then t:skip("stand inside a building of the map") end
        local site, why = R.check(def, {}, { minDistance = 0, minArea = 1,
            rules = { { kind = "test", label = "building", main = {} } } }, grid)
        if site == nil then t:skip("building refused: " .. tostring(why)) end
        R.useStore(R.newStore())
        t:defer(function() R.useStore(nil) end, "back to the private state")
        local id, rec = R.startForTeam(R.teamOf(p), { site = site, days = 1 })
        t:ok(id ~= nil, "start: " .. tostring(rec))
        R.consume((rec.reserves or 24) + 1)
        t:eq("missed", R.get(id).state, "state")
        t:ok(poll(true), "the scene was not placed")
        t:eq("placed", R.get(id).scene, "scene state")
        local found = RP.zombies(L, id)
        t:eq(#rec.survivors, #found, "zombies")
        local total, requester = pages(found)
        t:eq(1, total, "last pages among the zombies")
        t:eq(1, requester, "last pages carried by the requester")
        local b = rec.site.bounds
        local snap = { id = id, n = #rec.survivors, store = R.store(), bounds = { x1 = b.x1, y1 = b.y1, x2 = b.x2,
            y2 = b.y2 }, z = rec.site.z or 0 }
        local ok, werr = RST.Persist.write(RP.FILE, RP.HEADER, snap)
        t:ok(ok, werr)
        local back, rerr = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(back ~= nil and back.id == id and type(back.store.rescues[id]) == "table", "snapshot: " .. tostring(rerr))
        t:note("rescue " .. id .. ": " .. #found .. " zombie(s), outfits " .. table.concat(R.get(id).lost.outfits or {},
            ", "))
    end)
end)

RST.suite("rs.rescue.missed.after-restart", { tags = { "server", "world", "manual" }, testTimeoutMs = 120000 },
    function(s)
    s.test("same zombies and one notebook after the restart, nothing placed again", function(t)
        local R, L, V = modules(t)
        local snap, why = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(snap ~= nil and type(snap.id) == "string" and type(snap.store) == "table", why or "snapshot without rescue")
        local poll = pause(t, L, V)
        R.useStore(snap.store)
        t:defer(function()
            R.useStore(nil)
            removeScene(L, snap)
            RST.Persist.consume(RP.FILE)
        end, "remove the zombies and corpses of " .. snap.id)
        local rec = R.get(snap.id)
        t:ok(rec ~= nil and rec.state == "missed" and rec.scene == "placed", "rescue of the snapshot not placed")
        -- A survivor counts as its living zombie or, killed before or after the restart, as its marked corpse.
        t:waitUntil(function() return #RP.survivors(L, snap) >= snap.n end, RP.RETURN_MS, function(t2)
            local found = RP.survivors(L, snap)
            local living = #RP.zombies(L, snap.id)
            local total, requester = survivorPages(found)
            t2:note(living .. " zombie(s) and " .. (#found - living) .. " marked corpse(s) after the restart, "
                .. total .. " notebook(s)")
            t2:eq(snap.n, #found, "survivors (zombies or corpses) after the restart")
            t2:eq(1, total, "last pages after the restart")
            t2:eq(1, requester, "last pages carried by the requester")
            for _, e in ipairs(found) do
                if e.zombie and not e.zombie:isReanimatedPlayer() then
                    t2:note("zombie " .. e.index .. " is no longer a reanimated player after the restart")
                end
            end
            L.resetForTests()
            t2:ok(not poll(true), "a poll after the restart placed something")
            local raw = R.store().rescues[snap.id]
            raw.lost.placed, raw.lost.placing, raw.scene = false, true, "pending"
            L.resetForTests()
            t2:ok(poll(true), "stop between placing and placed: scene not adopted")
            local again = RP.survivors(L, snap)
            t2:eq(snap.n, #again, "survivors after the adoption")
            t2:eq(1, (survivorPages(again)), "last pages after the adoption")
        end, "fewer than " .. snap.n .. " marked zombies or corpses within " .. RP.RETURN_MS .. " ms (lost, or the "
            .. "requester is not back in the building)")
    end)
end)
