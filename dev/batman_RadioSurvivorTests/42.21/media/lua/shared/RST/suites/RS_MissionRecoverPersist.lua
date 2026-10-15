--[[
rs.mission.recover persistence steps (E11-T06, E01-T17: "un seul sac apres redemarrage"; server/RadioSurvivor/
RS_Caches.lua). Played by autoclient.py --mp --phases restart --server-campaign mp-persist (base rs.mission.recover):
    rs.mission.recover.before         (opt-in "manual") a cache record (Caches.attach on a test mission id) on the
                                      requester's square, placed at once by Caches.place: one marked bag on the
                                      floor. The store of the test writes the record to the snapshot file at each
                                      save (Caches.place saves "placing" before the bag exists, then "placed", item
                                      id and square): the snapshot stands in for the private notebook state (RS_State,
                                      whose own persistence is checked by rs.identity). Nothing removed.
                                      Run again: the bags of the previous snapshot are removed first.
    rs.mission.recover.after-restart  the record of the snapshot, after a real restart of the dedicated server: one
                                      bag marked for it in the site bounds, the same item id (saved with the world),
                                      a placement attempt places nothing; then a stop between "placing" and "placed"
                                      (record copy with placing = true, placed = false) adopts the saved bag: still
                                      one bag. Then the bag is removed and the snapshot consumed.
Tags "server", "world", "manual": authority only, test saves rstest* only, exact names only.
Snapshot: Zomboid/Lua/batman_RadioSurvivor/tests/recover-persist.txt of the server (RST_Persist).
Outside the game: tests/test_persist_suites.py (doubles of tests/test_mission_recover.py).
]]

require "RST/RST"
require "RST/RST_Persist"

RST.RecoverPersist = RST.RecoverPersist or {}
local RP = RST.RecoverPersist
RP.FILE = "recover-persist.txt"
RP.HEADER = "RSRECOVER1"
RP.RADIUS = 3          -- site bounds around the requester's square
RP.SQUARE_MS = 60000   -- requester back in game, site square loaded after the restart

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Caches is not loaded on an MP client (authority only)")
    end
    local Caches = require "RadioSurvivor/RS_Caches"
    if type(Caches) ~= "table" or type(Caches.place) ~= "function" then t:skip("RS_Caches did not return its table") end
    return Caches, require "RadioSurvivor/RS_Config"
end

-- Floor items of the bounds marked RS_Cache = key: list of { item, square, object }.
function RP.markedBags(Caches, b, z, key)
    local out = {}
    local cell = getCell()
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell and cell:getGridSquare(x, y, z)
            local objects = sq and sq:getWorldObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local wo = objects:get(i)
                local item = wo:getItem()
                if item ~= nil and item:hasModData() and item:getModData()[Caches.MARK] == key then
                    out[#out + 1] = { item = item, square = sq, object = wo }
                end
            end
        end
    end
    return out
end

local function removeBags(Caches, rec)
    local n = 0
    for _, e in ipairs(RP.markedBags(Caches, rec.bounds, rec.spot.z, rec.key)) do
        e.square:transmitRemoveItemFromSquare(e.object)
        n = n + 1
    end
    return n
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Store double of the test: each save writes the record to the snapshot (what RS_State.save does for the notebook).
local function snapshotStore(rec)
    local store = { saves = 0 }
    store.save = function()
        store.saves = store.saves + 1
        local ok = RST.Persist.write(RP.FILE, RP.HEADER, { rec = rec, saves = store.saves })
        return ok and true or false
    end
    return store
end

RST.suite("rs.mission.recover.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("cache placed once, its record written to the snapshot", function(t)
        local Caches, Config = modules(t)
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local old = RST.Persist.read(RP.FILE, RP.HEADER)
        if old and type(old.rec) == "table" then
            t:note(removeBags(Caches, old.rec) .. " bag(s) of the previous snapshot removed")
        end
        local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local r = RP.RADIUS
        local key = "rst-cache-persist-" .. tostring(math.floor(RST.now()))
        local m = { id = key }
        local rec, why = Caches.attach(m, Config.Caches.order[1], { x = x, y = y, z = z },
            { x1 = x - r, y1 = y - r, x2 = x + r + 1, y2 = y + r + 1 })
        t:ok(rec ~= nil, "record not attached: " .. tostring(why))
        local store = snapshotStore(rec)
        Caches.resetForTests()
        t:eq(true, Caches.place(store, rec), "cache not placed (site square not loaded, building not ready or "
            .. "no free square around the player)")
        t:ok(rec.placed == true and rec.itemId ~= nil and type(rec.at) == "table", "record not settled")
        t:ok(store.saves >= 2, "placing and placed not both saved (" .. store.saves .. " save(s))")
        local bags = RP.markedBags(Caches, rec.bounds, z, key)
        t:eq(1, #bags, "marked bags on the floor")
        t:eq(rec.itemId, bags[1] and bags[1].item:getID(), "id of the bag")
        t:ok(bags[1] and bags[1].item:getItemContainer():getItems():size() > 0, "empty cache")
        local back, rerr = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(back ~= nil and back.rec.placed == true and back.rec.itemId == rec.itemId, "snapshot: " .. tostring(rerr))
        t:note("cache " .. key .. " (" .. rec.table .. ") bag " .. tostring(rec.itemId) .. " at " .. rec.at.x .. ","
            .. rec.at.y .. "," .. rec.at.z)
    end)
end)

RST.suite("rs.mission.recover.after-restart", { tags = { "server", "world", "manual" }, testTimeoutMs = 90000 },
    function(s)
    s.test("one bag after the restart, nothing placed again, a stop before 'placed' adopts it", function(t)
        local Caches = modules(t)
        local snap, why = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(snap ~= nil and type(snap.rec) == "table", why or "snapshot without a cache record")
        local rec = snap.rec
        t:ok(rec.placed == true and rec.itemId ~= nil, "the snapshot holds a record that was never placed")
        t:defer(function()
            removeBags(Caches, rec)
            RST.Persist.consume(RP.FILE)
        end, "remove the cache bag of " .. tostring(rec.key))
        t:waitUntil(function()
            local cell = getCell()
            return cell ~= nil and cell:getGridSquare(rec.at.x, rec.at.y, rec.at.z) ~= nil
        end, RP.SQUARE_MS, function(t2)
            local bags = RP.markedBags(Caches, rec.bounds, rec.spot.z, rec.key)
            t2:note(#bags .. " marked bag(s) after the restart")
            t2:eq(1, #bags, "marked bags after the restart")
            t2:eq(rec.itemId, bags[1] and bags[1].item:getID(), "id of the saved bag")
            local store = snapshotStore(rec)
            Caches.resetForTests()
            t2:eq(false, Caches.place(store, rec), "a placed record placed again")
            t2:eq(0, store.saves, "state saved by a placed record")
            local stopped = copy(rec)
            stopped.placed, stopped.placing, stopped.itemId, stopped.at = false, true, nil, nil
            local store2 = { save = function() return true end }
            Caches.resetForTests()
            t2:eq(true, Caches.place(store2, stopped), "stop between placing and placed: bag not adopted")
            t2:eq(rec.itemId, stopped.itemId, "adopted bag")
            t2:eq(1, #RP.markedBags(Caches, rec.bounds, rec.spot.z, rec.key), "marked bags after the adoption")
        end, "site square " .. rec.at.x .. "," .. rec.at.y .. "," .. rec.at.z .. " not loaded (the requester must be "
            .. "back where rs.mission.recover.before ran)")
    end)
end)
