--[[
rst.fixtures — in-game check of the world fixtures (RST_Fixtures.lua) and of their automatic cleanup.
Tags "world" and "shared": only on a save named rstest* (world guard, RST.lua), in solo (RST.run({ suite = "rst",
tags = "world" })) or on the server (RST.server({ suite = "rst", tags = "world" })).
Each "... after the previous test" test checks the undo of the test just before it: tests run in declaration order.
The move test waits in steps (waitSquare, then movePlayer with a continuation): needs an asynchronous run.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local ITEM = "Base.Pencil"

local function onServer()
    return type(isServer) == "function" and isServer()
end

-- Position tolerance: exact in solo, client-reported position on the server.
local function eps()
    if onServer() then return 1.0 end
    return 0.01
end

RST.suite("rst.fixtures", { tags = { "world", "shared" } }, function(s)
    local F = RST.Fixtures
    local state = {}

    s.test("giveItem adds the items to the player", function(t)
        local p = F.player(t)
        t:ok(p ~= nil, "no target player")
        local inv = p:getInventory()
        state.before = inv:getItems():size()
        local items = F.giveItem(t, p, ITEM, 2)
        t:eq(2, #items)
        state.ids = {}
        for i, item in ipairs(items) do
            state.ids[i] = item:getID()
            t:eq(ITEM, item:getFullType())
            t:ok(inv:getItemWithIDRecursiv(item:getID()) ~= nil, "given item not in the inventory")
        end
        t:eq(state.before + 2, inv:getItems():size())
    end)

    s.test("given items are gone after the previous test", function(t)
        local inv = F.player(t):getInventory()
        t:ok(state.ids ~= nil and #state.ids == 2, "previous test did not run")
        for _, id in ipairs(state.ids) do
            t:ok(inv:getItemWithIDRecursiv(id) == nil, "item #" .. tostring(id) .. " still on the player")
        end
        t:eq(state.before, inv:getItems():size())
    end)

    s.test("removeItem takes an item off the player", function(t)
        local p = F.player(t)
        local inv = p:getInventory()
        local item = F.giveItem(t, p, ITEM)[1]
        state.removedId = item:getID()
        F.removeItem(t, p, item)
        t:ok(inv:getItemWithIDRecursiv(state.removedId) == nil, "removed item still on the player")
    end)

    s.test("removed then given item is gone after the previous test", function(t)
        -- undo order: removeItem puts the item back, then giveItem removes it.
        t:ok(state.removedId ~= nil, "previous test did not run")
        t:ok(F.player(t):getInventory():getItemWithIDRecursiv(state.removedId) == nil, "item left on the player")
    end)

    s.test("movePlayer moves the player to a loaded square", function(t)
        local p = F.player(t)
        state.origin = { x = p:getX(), y = p:getY(), z = p:getZ() }
        local tx = math.floor(state.origin.x) + 3 + 0.5
        local ty = math.floor(state.origin.y) + 0.5
        local tz = math.floor(state.origin.z)
        F.waitSquare(t, tx, ty, tz, 5000, function(t2, square)
            t2:ok(square ~= nil, "target square")
            F.movePlayer(t2, p, tx, ty, tz, function(t3, origin)
                t3:near(state.origin.x, origin.x, 1e-6, "returned origin x")
                t3:near(tx, p:getX(), eps(), "x after the move")
                t3:near(ty, p:getY(), eps(), "y after the move")
            end)
        end)
    end)

    s.test("position restored after the previous test", function(t)
        local p = F.player(t)
        t:ok(state.origin ~= nil, "previous test did not run")
        t:near(state.origin.x, p:getX(), eps(), "x restored")
        t:near(state.origin.y, p:getY(), eps(), "y restored")
        t:near(state.origin.z, p:getZ(), eps(), "z restored")
    end)
end)
