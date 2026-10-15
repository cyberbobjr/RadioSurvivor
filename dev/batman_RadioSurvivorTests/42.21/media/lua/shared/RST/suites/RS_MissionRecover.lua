--[[
rs.mission.recover - mission template "recover" and its cache (E11-T06, server/RadioSurvivor/RS_MissionRecover.lua,
RS_Caches.lua) on the real metagrid and the real world: a building drawn around the player, the cache (marked bag)
placed once by the server poll when its square is loaded, picked up by the player, another bag with the same mark
left at the depot and ignored, the cache left at the depot recognised by its item id, taken out of the world: the
objective is met but the mission stays active "to report" (E11-T13); a report before the deposit is refused, the
report to the requester afterwards (RS_Missions.spoken) succeeds through the common engine.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
player is moved, bags are put on the floor: test saves "rstest*" only). Asynchronous run (RST.start / RST.server).
The mission lives in an in-memory state built by the test (requester fiche, character, store whose save does
nothing): no notebook state, no ModData of the notebook, no reward item. The requester body is a stand-in at the
player's position, and the home of its group (the depot) is that position: RS_NPCProvider.presence is wrapped for the
stand-in id during the test only. Cleanup: the player goes back, the bags left on the floor or in the inventory are
removed, the wrapped function is restored.
Outside the game: tests/test_mission_recover.py (metagrid, cell and floor doubles).
]]

require "RST/RST"
require "RST/RST_Fixtures"

local F = RST.Fixtures

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionRecover is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local Recover = require "RadioSurvivor/RS_MissionRecover"
    local Caches = require "RadioSurvivor/RS_Caches"
    if type(M) ~= "table" or type(Recover) ~= "table" or type(Caches) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    return M, Recover, Caches, require "RadioSurvivor/RS_Config", require "RadioSurvivor/RS_NPCProvider"
end

-- Floor object (square, world object) of the item with this id around (x, y, z), radius r; nil when absent.
local function onFloor(id, x, y, z, r)
    local cell = getCell()
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell and cell:getGridSquare(x + dx, y + dy, z)
            local floor = sq and sq:getWorldObjects()
            for i = 0, (floor and floor:size() or 0) - 1 do
                local wo = floor:get(i)
                if wo:getItem() and wo:getItem():getID() == id then return sq, wo end
            end
        end
    end
    return nil
end

local function syncRemove(container, item)
    if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(container, item) end
end

local function syncAdd(container, item)
    if type(isServer) == "function" and isServer() then sendAddItemToContainer(container, item) end
end

-- The player picks the item up from the floor (same item, same id).
local function pickUp(p, sq, wo)
    local item = wo:getItem()
    sq:transmitRemoveItemFromSquare(wo)
    item:setWorldItem(nil)
    p:getInventory():AddItem(item); syncAdd(p:getInventory(), item)
    return item
end

-- The player drops the item on the floor of sq.
local function drop(p, item, sq)
    local from = item:getContainer()
    if from then from:Remove(item); syncRemove(from, item) end
    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
end

RST.suite("rs.mission.recover", { tags = { "server", "world" }, testTimeoutMs = 120000 }, function(s)
    s.test("cache placed once, another bag refused, the cache accepted at the depot by id", function(t)
        local M, Recover, Caches, Config, P = modules(t)
        local c = Config.Missions.recover
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
        local npc = { id = "rst-recover", incarnation = "rst-recover" }
        state.npcs[npc.id] = npc
        state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
        local ox, oy, oz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local body = { getX = function() return ox end, getY = function() return oy end }
        local presence = P.presence
        P.presence = function(id)
            if id == npc.incarnation then return { away = false, x = ox, y = oy, z = oz } end
            return presence(id)
        end
        t:defer(function() P.presence = presence end, "restore RS_NPCProvider.presence")
        Recover.resetForTests(); Caches.resetForTests()
        local offer = Recover.offer(c, npc, nil, body)
        if not offer then t:skip("no building fits around the player (" .. c.minDistance .. "-" .. c.maxDistance
            .. " tiles): move to a town and run again") end
        t:eq("recover", offer.kind)
        for _, clue in ipairs(offer.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        local m = M.create(state, npc, "char1", c.id)
        t:ok(m ~= nil and m.template == "recover", "recover mission not created")
        t:eq(true, M.accept(state, m, "char1", "Tester"))
        t:eq({ x = ox, y = oy, z = oz, r = c.depotRadius }, m.depot)
        local store = { data = state, save = function() return true end }
        t:eq({ false, "Zone" }, { M.spoken(store, m, p, "char1") }, "E11-T13: report before the deposit accepted")
        local watched = { { player = p, character = "char1" } }
        t:note("place " .. m.place .. " " .. m.siteKey .. " point " .. m.spot.x .. "," .. m.spot.y .. "," .. m.spot.z
            .. ", cache " .. m.cache.table)
        F.movePlayer(t, p, m.spot.x + 0.5, m.spot.y + 0.5, m.spot.z, function(t2)
            t2:waitUntil(function()
                M.observe(state, watched, store)
                return m.cache.placed
            end, 30000, function(t3)
                local at = m.cache.at
                local sq, wo = onFloor(m.cache.itemId, at.x, at.y, at.z, 0)
                t3:ok(wo ~= nil, "no bag of the cache on " .. at.x .. "," .. at.y)
                if not wo then return end
                local bag = wo:getItem()
                t3:eq(m.id, bag:getModData()[Caches.MARK])
                t3:ok(bag:getItemContainer():getItems():size() > 0, "empty cache")
                t3:note("bag '" .. tostring(bag:getDisplayName()) .. "' with " .. bag:getItemContainer():getItems():size()
                    .. " items")
                t3:eq(false, Caches.place(store, m.cache), "placed twice")
                t3:defer(function()
                    local left = p:getInventory():getItemWithIDRecursiv(m.cache.itemId)
                    if left then
                        local holder = left:getContainer()
                        holder:Remove(left); syncRemove(holder, left)
                    end
                    local fsq, fwo = onFloor(m.cache.itemId, at.x, at.y, at.z, 0)
                    if fwo then fsq:transmitRemoveItemFromSquare(fwo) end
                end, "remove the cache bag")
                pickUp(p, sq, wo)
                t3:eq(true, M.observe(state, watched, store), "bag held: mission changed")
                t3:eq(true, m.found)
                -- Back to the depot (home point of the stand-in).
                F.movePlayer(t3, p, ox + 0.5, oy + 0.5, oz, function(t4)
                    F.waitSquare(t4, ox, oy, oz, nil, function(t5)
                        local depot = getCell():getGridSquare(ox, oy, oz)
                        local forged = instanceItem(Config.Caches.bagType)
                        forged:getModData()[Caches.MARK] = m.id
                        depot:AddWorldInventoryItem(forged, 0.5, 0.5, 0, true)
                        t5:defer(function()
                            local fsq, fwo = onFloor(forged:getID(), ox, oy, oz, 0)
                            if fwo then fsq:transmitRemoveItemFromSquare(fwo) end
                        end, "remove the forged bag")
                        M.observe(state, watched, store)
                        t5:eq("active", m.state, "a bag with the mark but another id was accepted")
                        local held = p:getInventory():getItemWithIDRecursiv(m.cache.itemId)
                        t5:ok(held ~= nil, "the cache bag left the player")
                        if not held then return end
                        drop(p, held, depot)
                        t5:waitUntil(function()
                            M.observe(state, watched, store)
                            return m.deposited == true
                        end, 5000, function(t6)
                            t6:eq("active", m.state, "E11-T13: the deposit alone is not a success")
                            t6:eq(true, M.reportReady(m), "deposit not marked to report")
                            t6:eq({ true }, { M.spoken(store, m, p, "char1") }, "report to the requester")
                            t6:eq("success", m.state)
                            t6:eq(true, m.deposited)
                            t6:eq(nil, onFloor(m.cache.itemId, ox, oy, oz, c.depotRadius), "cache still on the floor")
                            t6:ok(onFloor(forged:getID(), ox, oy, oz, 0) ~= nil, "the forged bag was taken")
                            t6:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
                        end, "cache at the depot not accepted")
                    end)
                end)
            end, "cache not placed")
        end)
    end)
end)
