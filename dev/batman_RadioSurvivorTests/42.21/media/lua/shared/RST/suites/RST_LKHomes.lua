--[[
lk.homes - furnishing of a Living Knox group home at the first real load of its squares (LK08-T04,
server/LivingKnox/LK_Homes.lua): a building home gets planks on a few closed windows (outside side), a battery lamp
switched on, sleeping bags up to one bed per living member, an empty crate; a camp (home outside any room) gets a lit
campfire and tents. Vanilla objects only, placed once: a furnish mark is written in the private group registry
before the placement, and objects carry ModData LKHome = group id.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the first test group gets its home on the player's square; the camp test group gets its home on the
nearest loaded outdoor square at least 12 squares away). Solo: RST.run({ suite = "lk.homes", tags = "world" }).
Dedicated server: RST.server({ suite = "lk.homes", tags = "world" }) from an admin client standing in a house.
Cleanup (t:defer): everything placed is removed (LivingKnox.Homes.clear) and the test groups are removed.

What is checked (nominal path):
    - building: LivingKnox.Homes.check(gid, { force = true }) furnishes the home: mark state "done", style
      "building"; every planned object is found on its square with the group tag (barricade with PLANKS planks, lamp
      IsoLightSwitch on battery with power and activated, sleeping bag tiles with the "bed" flag, crate with a
      container); a second check answers "done" and places nothing; after LivingKnox.Homes.reset() (memory lost, as
      after a restart) the mark read from the registry still answers "done"; with the mark erased (registry older
      than the world), the tagged objects restore the mark and nothing is placed again;
    - camp: same for a camp: a campfire of the vanilla system lit on its square, tents tagged with the "bed" flag.
Every object is printed as a note "placed <kind> at x,y,z". E01-T16 (LK08-T04, "two clients see the same home"):
every connected client reads the squares of the placed objects with the same describer as the authority (world.keys,
RST_PeerChecks.lua: barricade planks, lamps and their on state, objects drawn with the sprites of the tagged objects,
crate content) and must find the same keys.
Outside the game: tests/test_lk_homes.py (the suite also runs there against doubles).
]]

require "RST/RST"
require "RST/RST_PeerChecks"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Homes is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Homes) ~= "table" or type(E.Groups) ~= "table" then
        t:skip("LivingKnox.Homes is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function newGroup(E, gtype, name, home, n)
    local G = E.Groups
    local g = assert(G.create({ type = gtype, name = name, day = G.today(), home = home }))
    local roles = { "worker", "fighter", "medic", "scout", "worker" }
    for i = 1, n do
        assert(G.addMember(g.id, { role = roles[i], day = G.today() }))
    end
    return g.id
end

local function cleanup(t, E, gid)
    t:defer(function()
        E.Homes.clear(gid)
        E.Groups.remove(gid)
    end, "clear furnishing and remove group " .. gid)
end

local function kindsOf(placed)
    local out = {}
    for _, p in ipairs(placed or {}) do out[p.k] = (out[p.k] or 0) + 1 end
    return out
end

local function describe(counts)
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = counts[k] .. " " .. k end
    return table.concat(parts, ", ")
end

-- Tagged objects of the group around the home, grouped by kind (one entry per tagged square object).
local function taggedObjects(E, gid, home)
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
                        local kind = o:getModData()[E.Homes.TAG_KIND]
                        out[kind] = out[kind] or {}
                        table.insert(out[kind], o)
                    end
                end
            end
        end
    end
    return out
end

local function count(list) return list and #list or 0 end

local function isBedTile(o)
    local p = o:getProperties()
    return p ~= nil and p:has(IsoFlagType.bed)
end

local function notePlaced(t, mark)
    for _, p in ipairs(mark.placed) do
        t:note("placed " .. p.k .. " at " .. p.x .. "," .. p.y .. "," .. p.z)
    end
end

-- LK08-T04 (E01-T16): the squares of the placed objects seen alike by every client (dedicated server only).
local function checkClients(t, E, gid, home, mark)
    if not (type(isServer) == "function" and isServer()) then return end   -- solo: the authority is the display
    local squares, seen, sprites, names = {}, {}, {}, {}
    for _, p in ipairs(mark.placed or {}) do
        local k = p.x .. "," .. p.y .. "," .. p.z
        if not seen[k] then
            seen[k] = true
            squares[#squares + 1] = { x = p.x, y = p.y, z = p.z }
        end
    end
    for _, list in pairs(taggedObjects(E, gid, home)) do
        for _, o in ipairs(list) do
            local name = o:getSprite() and o:getSprite():getName() or nil
            if name ~= nil and not sprites[name] then
                sprites[name] = true
                names[#names + 1] = name
            end
            local osq = o:getSquare()
            local k = osq:getX() .. "," .. osq:getY() .. "," .. osq:getZ()
            if not seen[k] then
                seen[k] = true
                squares[#squares + 1] = { x = osq:getX(), y = osq:getY(), z = osq:getZ() }
            end
        end
    end
    if #squares == 0 then return end
    RST.PeerChecks.checkSquares(t, squares, { barricade = true, light = true, sprite = names, container = names })
end

-- Second check, simulated restart and lost mark: never anything placed again.
local function checkNoDuplicate(t, E, gid, home, total)
    local H = E.Homes
    t:eq("done", H.check(gid, { force = true }), "second check")
    H.reset()
    t:eq("done", H.check(gid, { force = true }), "check after a memory reset (restart)")
    t:ok(E.Groups.update(function(d)
        d.groups[gid].furnish = nil
        return true, true
    end), "mark not erased")
    H.reset()
    local restored = H.check(gid, { force = true })
    t:ok(type(restored) == "table" and restored.state == "done", "mark not restored from the tagged objects")
    local after = 0
    for _, list in pairs(taggedObjects(E, gid, home)) do after = after + #list end
    t:eq(total, after, "tagged objects after the second check, the restart and the lost mark")
end

RST.suite("lk.homes", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("building home furnished once with vanilla objects, no duplicate", function(t)
        local E = module(t)
        local H = E.Homes
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local gid = newGroup(E, "settlers", "RST homes", home, 4)
        cleanup(t, E, gid)
        local mark, why = H.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        t:eq("done", mark.state, "mark state")
        t:eq("building", mark.style, "style")
        local stored = E.Groups.get(gid).furnish
        t:ok(stored ~= nil and stored.state == "done", "mark not stored in the group registry")
        local planned = kindsOf(mark.placed)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z .. ": " .. describe(planned))
        notePlaced(t, mark)
        t:ok((planned.lamp or 0) == 1, "no lamp placed")
        t:ok((planned.crate or 0) == 1, "no crate placed")
        local objs = taggedObjects(E, gid, home)
        t:eq(planned.barricade or 0, count(objs.barricade), "tagged barricades")
        t:eq(planned.lamp or 0, count(objs.lamp), "tagged lamps")
        t:eq(2 * (planned.bed or 0), count(objs.bed), "tagged sleeping bag tiles (two per bag)")
        t:eq(planned.crate or 0, count(objs.crate), "tagged crates")
        for _, w in ipairs(objs.barricade or {}) do
            -- The mark is on the window (IsoBarricade ModData is never saved).
            t:ok(instanceof(w, "IsoWindow"), "barricade mark not on a window")
            local b = H.barricadeOf(w)
            t:ok(b ~= nil and instanceof(b, "IsoBarricade"), "no group barricade on the marked window")
            t:eq(H.CFG.PLANKS, b:getNumPlanks(), "planks of a barricade")
        end
        for _, l in ipairs(objs.lamp or {}) do
            t:ok(instanceof(l, "IsoLightSwitch"), "lamp object class")
            t:ok(l:getUseBattery() and l:getHasBattery(), "lamp not on battery")
            t:ok(l:getPower() > 0, "lamp battery empty")
            t:ok(l:isActivated(), "lamp not switched on")
        end
        for _, b in ipairs(objs.bed or {}) do t:ok(isBedTile(b), "sleeping bag tile without the bed flag") end
        for _, c in ipairs(objs.crate or {}) do t:ok(c:getContainer() ~= nil, "crate without a container") end
        local total = 0
        for _, list in pairs(objs) do total = total + #list end
        checkNoDuplicate(t, E, gid, home, total)
        checkClients(t, E, gid, home, mark)
    end)

    s.test("camp home: lit campfire and tents, no duplicate", function(t)
        local E = module(t)
        local H = E.Homes
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local cell = getCell()
        local home
        for r = 12, 30 do
            for _, d in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }) do
                local sq = cell:getGridSquare(px + d[1], py + d[2], pz)
                if home == nil and sq ~= nil and sq:getBuildingDef() == nil and H.clearSquare(sq) then
                    local cand = { x = px + d[1], y = py + d[2], z = pz }
                    if H.ready(cand) == "camp" then home = cand end
                end
            end
            if home then break end
        end
        if home == nil then t:skip("no loaded outdoor square 12 to 30 squares from the player") end
        local gid = newGroup(E, "raiders", "RST camp", home, 4)
        cleanup(t, E, gid)
        local mark, why = H.check(gid, { force = true })
        t:ok(type(mark) == "table", "camp not furnished: " .. tostring(why))
        t:eq("camp", mark.style, "style")
        local planned = kindsOf(mark.placed)
        t:note("group " .. gid .. " camp " .. home.x .. "," .. home.y .. "," .. home.z .. ": " .. describe(planned))
        notePlaced(t, mark)
        t:eq(1, planned.fire or 0, "campfires placed")
        t:ok((planned.tent or 0) >= 1, "no tent placed")
        local sys = SCampfireSystem and SCampfireSystem.instance
        t:ok(sys ~= nil, "SCampfireSystem.instance missing")
        for _, e in ipairs(mark.placed) do
            if e.k == "fire" then
                local fire = sys:getLuaObjectOnSquare(cell:getGridSquare(e.x, e.y, e.z))
                t:ok(fire ~= nil, "no campfire on its square")
                t:ok(fire.isLit == true, "campfire not lit")
            end
        end
        local objs = taggedObjects(E, gid, home)
        t:eq(2 * (planned.tent or 0), count(objs.tent), "tagged tent tiles (two per tent)")
        for _, o in ipairs(objs.tent or {}) do t:ok(isBedTile(o), "tent tile without the bed flag") end
        local total = 0
        for _, list in pairs(objs) do total = total + #list end
        checkNoDuplicate(t, E, gid, home, total)
        checkClients(t, E, gid, home, mark)
    end)
end)

-- ------------------------------------------------------------------------------------------------ persistence steps
--[[
E01-T17 (autoclient.py --mp --phases restart --server-campaign mp-persist): furnishing kept by a real restart of the
dedicated server, nothing placed twice (LK08-T04, "aucun second amenagement apres redemarrage").
    lk.homes.before         (opt-in "manual") a "settlers" group at home on the requester's square (inside a house),
                            furnished at once; group id, home and tagged objects per kind written to
                            Zomboid/Lua/batman_RadioSurvivor/tests/lk-homes-persist.txt of the server. Nothing removed.
                            Run again: the group of the previous snapshot is removed first.
    lk.homes.after-restart  same group in the registry with its "done" mark, a check places nothing, the same tagged
                            objects per kind around the home; then the group and its furnishing are removed.
]]

RST.LKHomesPersist = RST.LKHomesPersist or {}
local P = RST.LKHomesPersist
P.FILE = RST.FILE_DIR .. "lk-homes-persist.txt"
P.HEADER = "LKHOMES1"

local function countKinds(E, gid, home)
    local counts, total = {}, 0
    for kind, list in pairs(taggedObjects(E, gid, home)) do
        counts[tostring(kind)] = #list
        total = total + #list
    end
    return counts, total
end

-- Snapshot lines: header, gid=, home=x,y,z, one kind=<name>:<count> per kind, end.
function P.encode(snap)
    local lines = { P.HEADER, "gid=" .. snap.gid, "home=" .. snap.home.x .. "," .. snap.home.y .. "," .. snap.home.z }
    local kinds = {}
    for k in pairs(snap.counts) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, k in ipairs(kinds) do lines[#lines + 1] = "kind=" .. k .. ":" .. snap.counts[k] end
    lines[#lines + 1] = "end"
    return lines
end

-- Returns the snapshot, or nil and a reason.
function P.decode(lines)
    if type(lines) ~= "table" or lines[1] ~= P.HEADER or lines[#lines] ~= "end" then
        return nil, "snapshot " .. P.FILE .. " missing or incomplete: run lk.homes.before first"
    end
    local snap = { counts = {}, total = 0 }
    for i = 2, #lines - 1 do
        local line = lines[i]
        local gid = string.match(line, "^gid=(.+)$")
        local x, y, z = string.match(line, "^home=(%-?%d+),(%-?%d+),(%-?%d+)$")
        local kind, n = string.match(line, "^kind=([^:]+):(%d+)$")
        if gid then snap.gid = gid
        elseif x then snap.home = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
        elseif kind then
            snap.counts[kind] = tonumber(n)
            snap.total = snap.total + tonumber(n)
        else
            return nil, "snapshot line " .. i .. " not understood: " .. line
        end
    end
    if not snap.gid or not snap.home then return nil, "snapshot without gid or home" end
    return snap
end

local function readSnapshotLines()
    if type(getFileReader) ~= "function" then return nil end
    local ok, reader = pcall(getFileReader, P.FILE, false)
    if not ok or reader == nil then return nil end
    local lines = {}
    pcall(function()
        while #lines < 100 do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = tostring(line)
        end
    end)
    pcall(function() reader:close() end)
    return lines
end

local function describeCounts(counts)
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = counts[k] .. " " .. k end
    return table.concat(parts, ", ")
end

RST.suite("lk.homes.before", { tags = { "world", "server", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("furnished group home written to the snapshot", function(t)
        local E = module(t)
        local H = E.Homes
        local old = P.decode(readSnapshotLines() or {})
        if old and E.Groups.get(old.gid) ~= nil then
            H.clear(old.gid)
            E.Groups.remove(old.gid)
            t:note("group " .. old.gid .. " of the previous snapshot removed")
        end
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        t:ok(sq ~= nil and sq:getBuildingDef() ~= nil, "the requester must stand inside a house")
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local gid = newGroup(E, "settlers", "RST homes persist", home, 4)
        local mark, why = H.check(gid, { force = true })
        t:ok(type(mark) == "table" and mark.state == "done", "home not furnished: " .. tostring(why))
        local counts, total = countKinds(E, gid, home)
        t:ok(total > 0, "no tagged object around the home")
        local ok, werr = RST.writeLines(P.FILE, P.encode({ gid = gid, home = home, counts = counts }))
        t:ok(ok, werr)
        local back, rerr = P.decode(readSnapshotLines())
        t:ok(back ~= nil and back.gid == gid and back.total == total, "snapshot read back: " .. tostring(rerr))
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z .. ": " .. describeCounts(counts))
    end)
end)

RST.suite("lk.homes.after-restart", { tags = { "world", "server", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("same furnishing after the restart, nothing placed twice", function(t)
        local E = module(t)
        local H = E.Homes
        local snap, why = P.decode(readSnapshotLines() or {})
        t:ok(snap ~= nil, why)
        local g = E.Groups.get(snap.gid)
        t:ok(g ~= nil, "group " .. snap.gid .. " lost by the restart")
        t:defer(function()
            H.clear(snap.gid)
            E.Groups.remove(snap.gid)
            RST.writeLines(P.FILE, { "consumed" })
        end, "clear furnishing and remove group " .. snap.gid)
        t:ok(g.furnish ~= nil and g.furnish.state == "done", "furnish mark not kept in the registry: "
            .. tostring(g.furnish and g.furnish.state))
        local sq = getCell():getGridSquare(snap.home.x, snap.home.y, snap.home.z)
        t:ok(sq ~= nil, "home square not loaded (the requester must be back in the house)")
        t:eq("done", H.check(snap.gid, { force = true }), "check after the restart")
        local counts, total = countKinds(E, snap.gid, snap.home)
        t:note("before: " .. describeCounts(snap.counts) .. "; after: " .. describeCounts(counts))
        t:eq(snap.counts, counts, "tagged objects per kind")
        t:eq(snap.total, total, "tagged objects")
    end)
end)
