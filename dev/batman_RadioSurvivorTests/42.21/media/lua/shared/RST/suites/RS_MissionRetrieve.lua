--[[
rs.mission.retrieve - mission template "retrieve_id" (E11-T05, server/RadioSurvivor/RS_MissionRetrieve.lua) on the
real metagrid and the real world: a building drawn around the player, the body placed by the server poll once its
square is loaded (RandomizedWorldBase.createRandomDeadBody), an ID card named after the body in its container, another
ID card refused, the card of the body accepted by its item id and removed, success by the common engine.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
player is moved, a body is created: test saves "rstest*" only). Asynchronous run (RST.start / RST.server).
The mission lives in an in-memory state built by the test (requester fiche, character, store whose save does
nothing): no notebook state, no ModData of the notebook, no reward item. The requester body is a stand-in at the
player's position. Cleanup: the player goes back, the extra card is taken back, the body is removed from its square.
E01-T16 (E11-T05): the other connected players are moved with the player (F.movePlayers); every client sees the
body with the card, then without it once the player took it (world.keys around the body square).
Outside the game: tests/test_mission_retrieve.py (metagrid, cell and corpse doubles).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"

local F = RST.Fixtures

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionRetrieve is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local Retrieve = require "RadioSurvivor/RS_MissionRetrieve"
    if type(M) ~= "table" or type(Retrieve) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    return M, Retrieve, require "RadioSurvivor/RS_Config"
end

-- Body of the mission on its square (ModData mark), or nil.
local function findBody(m, Retrieve)
    local at = m.bodyAt
    local sq = at and getCell() and getCell():getGridSquare(at.x, at.y, at.z)
    local bodies = sq and sq:getDeadBodys()
    for i = 0, (bodies and bodies:size() or 0) - 1 do
        local body = bodies:get(i)
        if body:getModData()[Retrieve.MARK] == m.id then return body, sq end
    end
    return nil
end

local function syncRemove(container, item)
    if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(container, item) end
end

local function syncAdd(container, item)
    if type(isServer) == "function" and isServer() then sendAddItemToContainer(container, item) end
end

RST.suite("rs.mission.retrieve", { tags = { "server", "world" }, testTimeoutMs = 90000 }, function(s)
    s.test("body placed once, another ID card refused, the body's card accepted by id", function(t)
        local M, Retrieve, Config = modules(t)
        local c = Config.Missions.retrieve_id
        local p = F.player(t)
        if not p then t:skip("no target player") end
        if not Retrieve.available() then t:skip("RandomizedWorldBase is not exposed here") end
        local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
        local npc = { id = "rst-retrieve", incarnation = "rst-retrieve" }
        state.npcs[npc.id] = npc
        state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
        local ox, oy = p:getX(), p:getY()
        local body = { getX = function() return ox end, getY = function() return oy end }
        Retrieve.resetForTests()
        local offer = Retrieve.offer(c, npc, nil, body)
        if not offer then t:skip("no building fits around the player (" .. c.minDistance .. "-" .. c.maxDistance
            .. " tiles): move to a town and run again") end
        t:eq("retrieve_id", offer.kind)
        for _, clue in ipairs(offer.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        local m = M.create(state, npc, "char1", c.id)
        t:ok(m ~= nil and m.template == "retrieve_id", "retrieve_id mission not created")
        t:eq(true, M.accept(state, m, "char1", "Tester"))
        local store = { data = state, save = function() return true end }
        local watched = { { player = p, character = "char1" } }
        t:note("place " .. m.place .. " " .. m.siteKey .. " point " .. m.spot.x .. "," .. m.spot.y .. "," .. m.spot.z)
        -- E11-T05: every connected player is moved by the same offset (F.movePlayers), so that the second client
        -- loads the body's square and checks it.
        F.movePlayers(t, p, m.spot.x + 0.5, m.spot.y + 0.5, m.spot.z, function(t2)
            t2:waitUntil(function()
                M.observe(state, watched)
                return m.placed
            end, 30000, function(t3)
                local corpse, sq = findBody(m, Retrieve)
                t3:ok(corpse ~= nil, "no body with the mission mark on " .. m.bodyAt.x .. "," .. m.bodyAt.y)
                if corpse then t3:defer(function() sq:removeCorpse(corpse, false) end, "remove the body") end
                local card = corpse and corpse:getContainer():getItemWithID(m.cardId)
                t3:ok(card ~= nil, "card of the mission not in the body")
                t3:eq(false, corpse and corpse:isFakeDead(), "fake dead body")
                t3:note("body of " .. tostring(m.person) .. ", card '" .. tostring(card and card:getDisplayName()) .. "'")
                t3:eq(false, Retrieve.place(m, c), "placed twice")
                -- E11-T05 (E01-T16): every connected client sees the body with the same content (the ID card
                -- included), then without the card once the player took it (world.keys, RST_PeerChecks.lua).
                local squares = sq and RST.PeerChecks.around(sq:getX(), sq:getY(), sq:getZ(), 1) or {}
                RST.PeerChecks.checkSquares(t3, squares, { corpse = true }, function(t3b)
                    -- Another ID card, even named alike, and the right id while the card is still in the body.
                    local other = F.giveItem(t3b, p, "Base.IDcard")[1]
                    if card then other:setName(card:getName()) end
                    t3b:eq({ false, "WrongCard" }, { M.report(store, m, p, "char1", { other:getID() }, "rst-1") })
                    t3b:eq({ false, "WrongCard" }, { M.report(store, m, p, "char1", { m.cardId }, "rst-2") })
                    t3b:eq("active", m.state)
                    t3b:ok(p:getInventory():getItemWithIDRecursiv(other:getID()) ~= nil, "the refused card was taken")
                    if not card then return end
                    -- The player takes the card from the body (same item, same id).
                    local from = corpse:getContainer()
                    from:Remove(card); syncRemove(from, card)
                    p:getInventory():AddItem(card); syncAdd(p:getInventory(), card)
                    t3b:defer(function()
                        local inv = p:getInventory()
                        local left = inv:getItemWithIDRecursiv(m.cardId)
                        if left then
                            local holder = left:getContainer()
                            holder:Remove(left); syncRemove(holder, left)
                        end
                    end, "take the card back")
                    t3b:eq(true, M.observe(state, watched), "card held: mission changed")
                    t3b:eq(true, m.found)
                    t3b:eq({ true }, { M.report(store, m, p, "char1", { m.cardId }, "rst-3") }, "hand-over of the card")
                    t3b:eq("success", m.state)
                    t3b:eq(nil, p:getInventory():getItemWithIDRecursiv(m.cardId), "card still on the player")
                    t3b:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
                    RST.PeerChecks.checkSquares(t3b, squares, { corpse = true }, nil, true)
                end, true)
            end, "body not placed")
        end)
    end)
end)
