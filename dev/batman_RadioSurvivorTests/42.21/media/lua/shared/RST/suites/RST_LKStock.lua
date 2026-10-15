--[[
lk.stock - real stock of a Living Knox group in the containers of its home (LK08-T06,
server/LivingKnox/LK_Stock.lua): after the home is furnished (LK_Homes), a modest kit of vanilla items (canned food,
water bottles filled with water, first aid, ammo, materials) is created once in the containers placed for the group;
the server keeps a private reference inventory (item id, type, category, container) that is re-read while the home
area is loaded; an item taken by a player is found by its id in the player's inventory and reported as a "theft"
fact to LivingKnox.Hostility.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test group gets its home on the player's square). Solo: RST.run({ suite = "lk.stock",
tags = "world" }). Dedicated server: RST.server({ suite = "lk.stock", tags = "world" }) from an admin client standing
in a house.
Cleanup (t:defer): the item taken by the test is removed from the player's inventory, the stock reference is
erased, everything placed is removed (LivingKnox.Homes.clear, the crate goes with its content) and the group is
removed.

What is checked (nominal path):
    - LivingKnox.Homes.check(gid, { force = true }) furnishes the home, then LivingKnox.Stock.check(gid,
      { force = true }) fills it: action "filled", the containers placed for the group hold exactly the kit of the
      group type; the reference lists the same item ids as the categorised items really found in the home
      containers (all of them when there are fewer than Stock.MAX_ITEMS);
    - no duplicate: a second check, a check after LivingKnox.Stock.reset() (memory lost, as after a restart) and a
      check with the reference erased (registry older than the world: "restored") create nothing;
    - theft: one kit item moved from a group container to the player's inventory (same object, same id, as a
      transfer) is reported missing at the next check and attributed to the player (result "reported" when the
      player has a notebook character, otherwise "no key", noted).
Outside the game: tests/test_lk_stock.py (the suite also runs there against doubles).
]]

require "RST/RST"
require "RST/RST_PeerChecks"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Stock is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Stock) ~= "table" or type(E.Homes) ~= "table" or type(E.Groups) ~= "table" then
        t:skip("LivingKnox.Stock is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

-- Containers placed for the group by LK_Homes (crate, tents) around the home.
local function owned(E, gid, home)
    local cell = getCell()
    local R = E.Homes.CFG.RADIUS + 2
    local out = {}
    for dy = -R, R do
        for dx = -R, R do
            local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if o:hasModData() and o:getModData()[E.Homes.TAG] == gid then
                        for ci = 0, o:getContainerCount() - 1 do
                            local c = o:getContainerByIndex(ci)
                            if c ~= nil then out[#out + 1] = c end
                        end
                    end
                end
            end
        end
    end
    return out
end

local function itemsIn(containers)
    local n = 0
    for _, c in ipairs(containers) do n = n + c:getItems():size() end
    return n
end

local function kitSize(E, gtype)
    local kit = E.Stock.KITS[gtype] or E.Stock.KITS[E.Stock.DEFAULT_KIT]
    local n = 0
    for _, e in ipairs(kit) do n = n + (e[2] or 1) end
    return n
end

local function sortedIds(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.i end
    table.sort(out)
    return out
end

local function realEntries(E, gid, home)
    local style, def = E.Homes.ready(home)
    local cts = E.Stock.containers(gid, home, style, def and def:getIDString() or nil)
    if cts == nil then return {} end
    return E.Stock.read(cts)
end

local function describe(totals)
    local parts = {}
    for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do parts[#parts + 1] = tostring(totals[c]) .. " " .. c end
    return table.concat(parts, ", ")
end

RST.suite("lk.stock", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("home stock filled once, reference equals content, theft detected", function(t)
        local E = module(t)
        local S = E.Stock
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST stock", day = G.today(), home = home }))
        local gid = g.id
        for _, role in ipairs({ "worker", "fighter", "medic", "scout" }) do
            assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        local taken
        t:defer(function()
            if taken ~= nil then
                local inv = p:getInventory()
                if inv:containsID(taken:getID()) then
                    inv:Remove(taken)
                    sendRemoveItemFromContainer(inv, taken)
                end
            end
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
        end, "remove the taken item, the stock reference, the furnishing and group " .. gid)

        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        local r
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        t:eq("filled", r.action, "first check")
        local mine = owned(E, gid, home)
        t:ok(#mine > 0, "no container placed for the group")
        local kit = kitSize(E, "settlers")
        t:eq(kit, itemsIn(mine), "items in the group containers after the fill")
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z .. ": " .. describe(r.totals))

        local ref = S.reference(gid)
        t:ok(ref ~= nil, "no reference stored")
        local real = realEntries(E, gid, home)
        local refIds, realIds = sortedIds(ref.items), sortedIds(real)
        if #real <= S.MAX_ITEMS then
            t:eq(table.concat(realIds, ","), table.concat(refIds, ","), "reference ids = real ids")
        else
            t:eq(S.MAX_ITEMS, #refIds, "reference bounded to MAX_ITEMS")
            t:note(#real .. " categorised items in the home, " .. #refIds .. " tracked")
        end

        -- No duplicate: second check, memory reset (restart), lost reference.
        r = S.check(gid, { force = true })
        t:eq("checked", r.action, "second check")
        t:eq(0, r.missing + r.added, "changes found by the second check")
        S.reset()
        r = S.check(gid, { force = true })
        t:eq("checked", r.action, "check after a memory reset")
        t:ok(G.update(function(d)
            d.groups[gid].stock = nil
            return true, true
        end), "reference not erased")
        r = S.check(gid, { force = true })
        t:eq("restored", r.action, "check with the reference erased")
        t:eq(kit, itemsIn(owned(E, gid, home)), "items in the group containers after the restart and the lost reference")

        -- Theft: a kit item moved to the player's inventory (same object, same id).
        local from
        for _, c in ipairs(owned(E, gid, home)) do
            if taken == nil and c:getItems():size() > 0 then
                from = c
                taken = c:getItems():get(0)
            end
        end
        t:ok(taken ~= nil, "no item to take")
        from:Remove(taken)
        sendRemoveItemFromContainer(from, taken)
        p:getInventory():AddItem(taken)
        sendAddItemToContainer(p:getInventory(), taken)
        r = S.check(gid, { force = true })
        t:eq(1, r.missing, "missing items after the theft")
        t:ok(r.thefts[1] ~= nil, "theft not attributed")
        t:eq(tostring(p:getUsername()), r.thefts[1].player, "thief")
        t:note("theft of " .. tostring(taken:getFullType()) .. " by " .. r.thefts[1].player .. ": "
            .. tostring(r.thefts[1].result))
        for _, e in ipairs(S.reference(gid).items) do
            t:ok(e.i ~= taken:getID(), "taken item still in the reference")
        end
        -- E01-T16: the other clients see the crates of the group with the same content (theft included).
        local squares, sprites, seen = {}, {}, {}
        for _, c in ipairs(owned(E, gid, home)) do
            local okp, o = pcall(function() return c:getParent() end)
            local osq = okp and o ~= nil and o:getSquare() or nil
            if osq ~= nil then
                local key = osq:getX() .. "," .. osq:getY() .. "," .. osq:getZ()
                if not seen[key] then
                    seen[key] = true
                    squares[#squares + 1] = { x = osq:getX(), y = osq:getY(), z = osq:getZ() }
                end
                sprites[#sprites + 1] = o:getSprite():getName()
            end
        end
        RST.PeerChecks.checkSquares(t, squares, { container = sprites })
    end)
end)
