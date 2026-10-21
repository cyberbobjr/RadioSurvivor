--[[
rs.rescue.pick - choice of the building of a rescue (E12-T01, server/RadioSurvivor/RS_Rescue.lua): a habitable
building drawn from the metagrid, far from the known bases (safehouses, players, avoided points), with clues that
carry no coordinate, and no chunk loaded by the choice.
Tag "server": RS_Rescue starts with "if isClient() then return end" (authority only). Read-only: no item, no
ModData, no world change. Solo: RST.server("rs.rescue.pick") (the requester is the target player); dedicated
server: RST.server("rs.rescue.pick") from an admin client, or the autorun (no player: player checks are notes).
Asynchronous run only (a 3 s watch of LoadChunk); outside the game: tests/test_rescue.py.

Probe of "no chunk loaded" (the engine has no Lua counter of loaded chunks):
    - LoadChunk events counted during the picks (synchronous: must stay at 0) and for 3 s after them, with the
      position of each loaded chunk (IsoChunk:getGridSquare(0, 0, 0)): none may fall inside a picked building;
    - readable squares: getCell():getGridSquare at the centre of every chunk of a 21 x 21 chunk window around the
      player, before and after the picks (same count, and above 0 so the probe itself works), and at the centre of
      every chunk covered by each picked building (0 before the wait, 0 after);
    - BuildingDef:isFullyStreamedIn() of each picked building false.
getGridSquare never loads a chunk (it reads the chunk map, or the loaded server cells on a dedicated server): the
probes read, the picks are what is measured. Each site is printed as a note "site ..." with its coordinates, kind
and clues so that the tester can teleport there and judge the clues (docs/specifications-techniques/rescue.md).
]]

require "RST/RST"
require "RST/RST_PeerChecks"

local SEEDS = { 11, 23, 37, 41, 59 }
local WATCH_MS = 3000
local WINDOW = 10 -- chunks on each side of the player for the readable-square probe

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Rescue is not loaded on an MP client (authority only)")
    end
    local R = require "RadioSurvivor/RS_Rescue"
    if type(R) ~= "table" then t:skip("RS_Rescue did not return its table here") end
    return R
end

local function grid(t)
    local w = getWorld and getWorld()
    local g = w and w:getMetaGrid()
    t:ok(g ~= nil, "getWorld():getMetaGrid() is nil")
    return g
end

local function player(t)
    return t.ctx and t.ctx.player or nil
end

local function chunkReadable(cell, wx, wy, z)
    return cell:getGridSquare(wx * 8 + 4, wy * 8 + 4, z) ~= nil
end

-- Readable chunk centres in a window around (x, y); nil without a cell.
local function readableAround(x, y, half)
    local cell = getCell and getCell()
    if cell == nil then return nil end
    local wx0, wy0 = math.floor(x / 8), math.floor(y / 8)
    local n = 0
    for wy = wy0 - half, wy0 + half do
        for wx = wx0 - half, wx0 + half do
            if chunkReadable(cell, wx, wy, 0) then n = n + 1 end
        end
    end
    return n
end

-- Readable chunk centres covered by a site (0 = nothing of the building is loaded).
local function readableSite(site)
    local cell = getCell and getCell()
    if cell == nil then return 0 end
    local b = site.bounds
    local n = 0
    for wy = math.floor(b.y1 / 8), math.floor((b.y2 - 1) / 8) do
        for wx = math.floor(b.x1 / 8), math.floor((b.x2 - 1) / 8) do
            if chunkReadable(cell, wx, wy, 0) then n = n + 1 end
        end
    end
    return n
end

local function insideSite(site, x, y)
    local b = site.bounds
    return x >= b.x1 - 8 and x < b.x2 + 8 and y >= b.y1 - 8 and y < b.y2 + 8
end

-- LoadChunk listener, removed at the end of the test. Returns the record { count, positions }.
local function watchChunks(t)
    local rec = { count = 0, positions = {} }
    local function onLoad(chunk)
        rec.count = rec.count + 1
        local ok, sq = pcall(function() return chunk:getGridSquare(0, 0, 0) end)
        if ok and sq then rec.positions[#rec.positions + 1] = { x = sq:getX(), y = sq:getY() } end
    end
    Events.LoadChunk.Add(onLoad)
    t:defer(function() Events.LoadChunk.Remove(onLoad) end, "remove the LoadChunk listener")
    return rec
end

local function siteNote(t, seed, site, ms)
    t:note("site seed=" .. tostring(seed) .. " " .. site.kind .. " " .. site.key .. " at " .. site.x .. "," .. site.y
        .. "," .. site.z .. " after " .. site.attempts .. " draw(s), " .. ms .. " ms; clues: "
        .. table.concat(site.clues or {}, " | "))
end

local function checkSite(t, R, g, site, seed)
    local def = g:getBuildingAt(site.x, site.y, site.z)
    t:ok(def ~= nil, "seed " .. seed .. ": no building of the metagrid at the site point")
    t:eq(site.buildingId, def:getIDString(), "seed " .. seed .. ": building at the site point")
    local rule = R.classify(def)
    t:ok(rule ~= nil and rule.kind == site.kind, "seed " .. seed .. ": building no longer habitable as " .. site.kind)
    for _, base in ipairs(R.knownBases({})) do
        t:ok(R.gap(site.bounds, base) >= R.CONFIG.MIN_DISTANCE,
            "seed " .. seed .. ": site closer than MIN_DISTANCE to a " .. base.source)
    end
    local p = player(t)
    if p then
        local d = R.gap(site.bounds, { x1 = math.floor(p:getX()), y1 = math.floor(p:getY()),
            x2 = math.floor(p:getX()) + 1, y2 = math.floor(p:getY()) + 1 })
        t:ok(d >= R.CONFIG.MIN_DISTANCE, "seed " .. seed .. ": site too close to the test player")
    end
    t:ok(type(site.clues) == "table" and #site.clues >= 2, "seed " .. seed .. ": fewer than two clues")
    for _, clue in ipairs(site.clues) do
        t:ok(not string.find(clue, "%d"), "seed " .. seed .. ": clue with a digit: " .. clue)
    end
    return def
end

local function now()
    return getTimestampMs and getTimestampMs() or 0
end

RST.suite("rs.rescue.pick", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local R = module(t)
        for _, name in ipairs({ "pick", "check", "clues", "classify", "landmarkOf", "knownBases", "nearbyBuildings",
            "gap" }) do
            t:eq("function", type(R[name]), "RS_Rescue." .. name)
        end
    end)

    s.test("metagrid lists the buildings of the map", function(t)
        module(t)
        local list = grid(t):getBuildings()
        t:ok(list ~= nil and list:size() > 0, "getBuildings() is empty")
        t:note("metagrid buildings: " .. list:size() .. "; known bases: " .. #module(t).knownBases({}))
    end)

    s.test("seeded picks are habitable, far from the bases, with clues and reproducible", function(t)
        local R = module(t)
        local g = grid(t)
        for _, seed in ipairs(SEEDS) do
            local started = now()
            local site, reason = R.pick({ seed = seed })
            local ms = now() - started
            t:ok(site ~= nil, "seed " .. seed .. ": " .. tostring(reason))
            checkSite(t, R, g, site, seed)
            siteNote(t, seed, site, ms)
            local again = R.pick({ seed = seed, noClues = true })
            t:eq(site.key, again and again.key, "seed " .. seed .. ": same seed, same building")
        end
    end)

    s.test("no chunk is loaded by the picks (LoadChunk, readable squares, streaming)", function(t)
        local R = module(t)
        local g = grid(t)
        local p = player(t)
        local rec = watchChunks(t)
        local before = p and readableAround(p:getX(), p:getY(), WINDOW) or nil
        local sites = {}
        for _, seed in ipairs(SEEDS) do
            local site, reason = R.pick({ seed = seed, noClues = seed ~= SEEDS[1] })
            t:ok(site ~= nil, "seed " .. seed .. ": " .. tostring(reason))
            sites[#sites + 1] = site
        end
        t:eq(0, rec.count, "LoadChunk fired during the synchronous picks")
        if p then
            local after = readableAround(p:getX(), p:getY(), WINDOW)
            t:ok(before > 0, "probe broken: no readable chunk around the player")
            t:eq(before, after, "readable chunks around the player before / after the picks")
            t:note("readable chunk centres around the player: " .. before .. " before, " .. after .. " after")
        else
            t:note("no target player: readable-square probe around the player not run")
        end
        for _, site in ipairs(sites) do
            t:eq(0, readableSite(site), site.key .. ": a chunk of the picked building is readable")
            local def = g:getBuildingAt(site.x, site.y, site.z)
            t:ok(def ~= nil and not def:isFullyStreamedIn(), site.key .. ": building fully streamed in")
        end
        t:sleep(WATCH_MS, function(t2)
            for _, pos in ipairs(rec.positions) do
                for _, site in ipairs(sites) do
                    t2:ok(not insideSite(site, pos.x, pos.y), site.key .. ": a chunk of the building was loaded")
                end
            end
            for _, site in ipairs(sites) do
                t2:eq(0, readableSite(site), site.key .. ": a chunk of the picked building is readable after the wait")
            end
            t2:note("LoadChunk events during the " .. WATCH_MS .. " ms watch: " .. rec.count)
        end)
    end)

    s.test("an impossible distance is refused with a reason, within the draw bound", function(t)
        local R = module(t)
        local site, reason = R.pick({ seed = 1, minDistance = 1000000, avoid = { { x = 0, y = 0 } } })
        t:eq(nil, site, "a site was picked although every building is too close")
        t:ok(string.find(tostring(reason), "near a known base", 1, true) ~= nil, "reason: " .. tostring(reason))
        t:ok(string.find(tostring(reason), R.CONFIG.MAX_ATTEMPTS .. " draw(s)", 1, true) ~= nil,
            "reason without the draw bound: " .. tostring(reason))
    end)

    s.test("an avoided point keeps the site away", function(t)
        local R = module(t)
        local first = R.pick({ seed = SEEDS[1], noClues = true })
        t:ok(first ~= nil, "no site for the reference seed")
        local centre = { x = (first.bounds.x1 + first.bounds.x2) / 2, y = (first.bounds.y1 + first.bounds.y2) / 2 }
        local other = R.pick({ seed = SEEDS[1], noClues = true, avoid = { centre } })
        t:ok(other ~= nil, "no site once the first one is avoided")
        t:ok(other.key ~= first.key, "the avoided building was picked again")
        t:ok(R.gap(other.bounds, { x1 = math.floor(centre.x), y1 = math.floor(centre.y),
            x2 = math.floor(centre.x) + 1, y2 = math.floor(centre.y) + 1 }) >= R.CONFIG.MIN_DISTANCE,
            "second site too close to the avoided point")
    end)
end)

--[[
rs.rescue.run - running rescues (E12-T02): reserves counted in game hours (delay in game days), only while at least
one player is connected, one active rescue per team, distinct buildings, closing at zero reserves.
Tag "server". Runs on a WORK store (RS_Rescue.useStore): the private state, its rescues and the facts of the day
are never touched (the real rescues are not counted during the run, a few seconds). Solo:
RST.server("rs.rescue.run"); dedicated server: RST.server("rs.rescue.run") from an admin client (connected:
the reserves drop by the elapsed world age), or the autorun without player (empty server: the reserves stay frozen
while the world age moves, unless the server pauses when empty).
]]

local LIVE_MS = 4000

local function workStore(t, R)
    R.useStore(R.newStore())
    t:defer(function() R.useStore(nil) end, "back to the private state")
end

local function age()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or nil
end

RST.suite("rs.rescue.run", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local R = module(t)
        for _, name in ipairs({ "start", "startForTeam", "teamOf", "get", "activeFor", "list", "addReserves",
            "finish", "consume", "poll", "connected", "pendingScenes", "scenePlaced", "useStore", "newStore" }) do
            t:eq("function", type(R[name]), "RS_Rescue." .. name)
        end
    end)

    s.test("two teams get two rescues in distinct buildings, a team only one", function(t)
        local R = module(t)
        workStore(t, R)
        local a, ra = R.startForTeam("rst-team-a", { seed = SEEDS[1], days = 3 })
        t:ok(a ~= nil, "team a: " .. tostring(ra))
        t:eq(72, ra.reserves, "reserves of a three-day delay (hours)")
        local again, why, current = R.startForTeam("rst-team-a", { seed = SEEDS[2] })
        t:eq(nil, again, "second rescue accepted for the same team")
        t:eq("team_busy", why, "refusal reason")
        t:eq(a, current, "refusal names the running rescue")
        local b, rb = R.startForTeam("rst-team-b", { seed = SEEDS[1] })
        t:ok(b ~= nil and b ~= a, "team b: " .. tostring(rb))
        t:ok(ra.site.key ~= rb.site.key, "same building for two teams")
        t:note("team a: " .. ra.site.kind .. " " .. ra.site.key .. "; team b: " .. rb.site.kind .. " " .. rb.site.key)
    end)

    -- E12-T06 : the delay of a new rescue comes from the sandbox option RadioSurvivor.RescueDays (integer 1..10,
    -- default 3), changed here in memory as an admin would (option:setValue, restored afterwards); a running rescue
    -- keeps its reserves.
    s.test("a new rescue takes its delay from the RescueDays option", function(t)
        local R = module(t)
        local options = getSandboxOptions and getSandboxOptions()
        local o = options and options:getOptionByName("RadioSurvivor.RescueDays")
        t:ok(o ~= nil, "option RadioSurvivor.RescueDays not registered (sandbox-options.txt)")
        local v0 = o:getValue()
        t:defer(function() o:setValue(v0) end, "restore RadioSurvivor.RescueDays")
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        t:eq(v0, Const.rescueDays(), "delay read from the option")
        workStore(t, R)
        local v1 = v0 == 5 and 6 or 5
        o:setValue(v1)
        t:eq(v1, o:getValue(), "option changed in memory")
        local id, rec = R.startForTeam("rst-team-option", { seed = SEEDS[1] })
        t:ok(id ~= nil, "start: " .. tostring(rec))
        t:eq(v1, rec.days, "days of the new rescue")
        t:eq(v1 * 24, rec.reserves, "reserves of the new rescue (hours)")
        o:setValue(v1 == 5 and 9 or 2)
        t:eq(v1, R.get(id).days, "running rescue changed with the option")
        t:eq(v1 * 24, R.get(id).reserves, "reserves of the running rescue changed with the option")
        t:note("RescueDays " .. tostring(v0) .. " -> " .. tostring(v1) .. ": rescue " .. id .. " of " .. rec.days
            .. " day(s)")
    end)

    s.test("the requesting player's team (faction or alone) holds one rescue", function(t)
        local R = module(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        workStore(t, R)
        local team = R.teamOf(p)
        t:ok(type(team) == "string", "no team id for the player")
        local id, rec = R.start(p, { seed = SEEDS[3] })
        t:ok(id ~= nil, "start: " .. tostring(rec))
        t:eq(team, rec.team, "team of the rescue")
        local again, why = R.start(p, { seed = SEEDS[4] })
        t:eq(nil, again, "second rescue for the player's team")
        t:eq("team_busy", why, "refusal reason")
        t:note("player team " .. team)
    end)

    s.test("reserves drop with the world age only while a player is connected", function(t)
        local R = module(t)
        workStore(t, R)
        local id, rec = R.startForTeam("rst-team-live", { seed = SEEDS[5], days = 2 })
        t:ok(id ~= nil, "start: " .. tostring(rec))
        R.resetSession()
        R.poll(true)
        local start = age()
        local connected = R.connected()
        t:sleep(LIVE_MS, function(t2)
            R.poll(true)
            local ageNow = age()
            local live = R.get(id)
            local elapsed = ageNow - start
            if connected and R.connected() then
                t2:near(elapsed, live.consumed, 0.0001, "consumed hours = elapsed world age")
                t2:near(48 - elapsed, live.reserves, 0.0001, "reserves")
            elseif not connected and not R.connected() then
                t2:eq(0, live.consumed, "reserves dropped on an empty server")
            end
            t2:note("connected " .. tostring(connected) .. ", world age +" .. string.format("%.4f", elapsed)
                .. " h, consumed " .. string.format("%.4f", live.consumed) .. " h")
        end)
    end)

    s.test("zero reserves close the rescue too late, the team may be called again", function(t)
        local R = module(t)
        workStore(t, R)
        local id = R.startForTeam("rst-team-late", { seed = SEEDS[1], days = 1 })
        t:ok(id ~= nil, "start")
        R.consume(30)
        local rec = R.get(id)
        t:eq("missed", rec.state, "state at zero reserves")
        t:eq("pending", rec.scene, "scene of the outcome to place")
        t:eq(nil, R.activeFor("rst-team-late"), "still active")
        t:ok(R.startForTeam("rst-team-late", { seed = SEEDS[2] }) ~= nil, "no new rescue after the outcome")
        t:eq(nil, R.addReserves(id, 24), "delivery accepted on a closed rescue")
    end)
end)

--[[
rs.rescue.visit - delivery on site and approach (E12-T03, server/RadioSurvivor/RS_RescueVisit.lua). Tag "server".
WORK store (RS_Rescue.useStore) and a rescue whose site is the building where the target player stands (RS_Rescue.check
without base): stand INSIDE a building of the map, with a piece of furniture holding a container (fridge, counter,
shelf) within 8 tiles on your floor. The background poll of RS_RescueVisit is paused during the run. Creates two tins
of beans (Base.TinnedBeans: one in the player's inventory then in the furniture, one directly in the furniture); what
is left is removed at the end. A green smoke of the required mod Signal Smoke is lit for 30 game minutes next to the
building, then stopped (Signal Smoke unusable: FAIL). Solo: RST.server("rs.rescue.visit"). Outside the game:
tests/test_rescue_visit.py.
]]

local function visitModule(t)
    module(t)
    local V = require "RadioSurvivor/RS_RescueVisit"
    if type(V) ~= "table" then t:skip("RS_RescueVisit did not return its table here") end
    return V
end

-- Pauses the background poll of RS_RescueVisit for the test (the global table is the module).
local function pauseVisits(t, V)
    local poll = V.poll
    V.poll = function() return false end
    V.resetForTests()
    t:defer(function()
        V.poll = poll
        V.resetForTests()
    end, "resume the visit poll")
end

-- Rescue of the player's team in a work store, on the building where the player stands.
local function rescueHere(t, R, p)
    local g = grid(t)
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local def = g:getBuildingAt(x, y, z)
    if def == nil then t:skip("stand inside a building of the map") end
    local site, why = R.check(def, {}, { minDistance = 0, minArea = 1,
        rules = { { kind = "test", label = "building", main = {} } } }, g)
    if site == nil then t:skip("building refused: " .. tostring(why)) end
    workStore(t, R)
    local id, rec = R.startForTeam(R.teamOf(p), { site = site, days = 1 })
    t:ok(id ~= nil, "start: " .. tostring(rec))
    return id, rec
end

-- First container of a piece of furniture inside the bounds, within the scan radius, on the player's floor.
local function furnitureNear(V, rec, p)
    local cell = getCell()
    local b, r = rec.site.bounds, V.CONFIG.SCAN_RADIUS
    local px, py, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for x = math.max(b.x1, px - r), math.min(b.x2 - 1, px + r) do
        for y = math.max(b.y1, py - r), math.min(b.y2 - 1, py + r) do
            local sq = cell:getGridSquare(x, y, z)
            local objects = sq and sq:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                if o:getContainerCount() > 0 then return o:getContainerByIndex(0), x, y end
            end
        end
    end
    return nil
end

local function removeIfThere(container, item)
    if container:contains(item) then
        container:DoRemoveItem(item)
        if isServer() then sendRemoveItemFromContainer(container, item) end
    end
end

local function addTo(container, item)
    container:AddItem(item)
    if isServer() then sendAddItemToContainer(container, item) end
    return item
end

RST.suite("rs.rescue.visit", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local V = visitModule(t)
        for _, name in ipairs({ "poll", "gather", "remember", "isCarried", "findDeposits", "collect", "approach",
            "describe", "line", "smokePoint", "library", "categoryOf", "usable", "resetForTests" }) do
            t:eq("function", type(V[name]), "RS_RescueVisit." .. name)
        end
        t:eq("function", type(module(t).noteApproach), "RS_Rescue.noteApproach")
    end)

    s.test("only a supply carried in counts, the building loot does not", function(t)
        local V = visitModule(t)
        local R = module(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        pauseVisits(t, V)
        local id, rec = rescueHere(t, R, p)
        local container, cx, cy = furnitureNear(V, rec, p)
        if container == nil then t:skip("no furniture with a container within 8 tiles on this floor") end
        local inv = p:getInventory()
        local brought = addTo(inv, instanceItem("Base.TinnedBeans"))
        local loot = addTo(container, instanceItem("Base.TinnedBeans"))
        t:defer(function()
            removeIfThere(inv, brought)
            removeIfThere(container, brought)
            removeIfThere(container, loot)
        end, "remove the test tins")
        t:eq("food", V.usable(brought), "category of a tin of beans")
        t:ok(V.remember(rec.team, p) >= 1, "the carried tin was not remembered")
        inv:DoRemoveItem(brought)
        if isServer() then sendRemoveItemFromContainer(inv, brought) end
        addTo(container, brought)
        local before = R.get(id).reserves
        local hours = V.collect(R.get(id), rec.team, { p })
        t:eq(V.HOURS.food, hours, "hours added by the carried tin")
        t:near(before + V.HOURS.food, R.get(id).reserves, 0.001, "reserves after the deposit")
        t:ok(not container:contains(brought), "the carried tin is still in the furniture")
        t:ok(container:contains(loot), "the loot tin was taken")
        t:eq(0, V.collect(R.get(id), rec.team, { p }), "the loot tin counted")
        t:note("furniture at " .. cx .. "," .. cy .. "; reserves " .. before .. " -> " .. R.get(id).reserves .. " h")
    end)

    s.test("approach: the voice describes when no smoke can be lit, else lights a Signal Smoke smoke", function(t)
        local V = visitModule(t)
        local R = module(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        pauseVisits(t, V)
        local listener = V.onApproach
        local got = {}
        V.onApproach = function(rec, info, text) got[#got + 1] = { info = info, text = text } end
        t:defer(function() V.onApproach = listener end, "restore the approach listener")
        local mod = V.library()
        local library = V.library
        V.library = function() return nil end
        t:defer(function() V.library = library end, "restore the Signal Smoke module")
        local id = rescueHere(t, R, p)
        t:ok(V.approach(R.get(id), { p }), "no approach")
        local first = got[1]
        t:ok(first ~= nil and first.info.smoke == nil, "smoke without a usable Signal Smoke module")
        t:ok(type(first.text) == "string" and first.text ~= "" and not string.find(first.text, "IGUI_", 1, true),
            "description: " .. tostring(first and first.text))
        t:eq(first.info.dir, R.get(id).approach.dir, "approach kept in the rescue")
        t:ok(not V.approach(R.get(id), { p }), "second approach within the delay")
        t:note("description: " .. tostring(first.text))
        if mod == nil then
            t:fail("required mod Signal Smoke (batman_SignalSmoke) unusable: RS_RescueVisit.library() returned nil")
        end
        V.library = library
        R.finish(id, "abandoned")
        local id2 = R.startForTeam(R.teamOf(p), { site = R.get(id).site, days = 1 })
        t:ok(id2 ~= nil, "second work rescue")
        t:defer(function() mod.stop("rs:rescue:" .. id2) end, "stop the test smoke")
        t:ok(V.approach(R.get(id2), { p }), "no approach with Signal Smoke")
        t:eq(V.CONFIG.SMOKE_COLOR, got[2].info.smoke, "smoke colour")
        t:ok(mod.isActive("rs:rescue:" .. id2), "the smoke is not in the Signal Smoke registry")
        t:note("with smoke: " .. tostring(got[2].text))
    end)
end)

--[[
rs.rescue.saved - outcome "in time" (E12-T04, server/RadioSurvivor/RS_RescueScene.lua, RS_RescueVisit.leave). Tag
"server". WORK store and a rescue on the building where the target player stands (stand INSIDE a building of the map,
on a floor with free squares around the room centre), with the test voice "rst-rescue-voice" (its persona state and
memory are removed at the end). The background polls of RS_RescueVisit and RS_RescueScene are paused during the run.
The player is noted as the helper of a delivery, then the survivors leave (RS_RescueVisit.leave): rescue "saved",
cache and note prepared, new place of the voice, memory on the player. Then the scene is placed (site loaded: the
player stands in it): ONE duffel bag on the floor of the building, holding a locked note; a second poll places
nothing. The bag is removed at the end. Solo: RST.server("rs.rescue.saved"). Outside the game:
tests/test_rescue_scene.py.
]]

local SAVED_VOICE = "rst-rescue-voice"

local function sceneModule(t)
    module(t)
    local Sc = require "RadioSurvivor/RS_RescueScene"
    if type(Sc) ~= "table" then t:skip("RS_RescueScene did not return its table here") end
    return Sc
end

local function pauseScenes(t, Sc)
    local poll = Sc.poll
    Sc.poll = function() return false end
    t:defer(function() Sc.poll = poll end, "resume the scene poll")
    return poll
end

-- Persona state and memory of the test voice removed from the private state.
local function forgetTestVoice(t)
    t:defer(function()
        local S = require "RadioSurvivor/RS_State"
        if type(S.data) == "table" then
            if type(S.data.memory) == "table" then S.data.memory[SAVED_VOICE] = nil end
            if type(S.data.personaState) == "table" then S.data.personaState[SAVED_VOICE] = nil end
        end
    end, "forget the test voice")
end

-- Floor items of the bounds (floor z) marked RS_Cache = key: list of { item, square, object }.
local function markedBags(b, z, key)
    local out = {}
    local cell = getCell()
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            local objects = sq and sq:getWorldObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local wo = objects:get(i)
                local item = wo:getItem()
                if item and item:hasModData() and item:getModData().RS_Cache == key then
                    out[#out + 1] = { item = item, square = sq, object = wo }
                end
            end
        end
    end
    return out
end

-- Saved rescue of the player's team on the building where the player stands (work store, test voice).
local function savedHere(t, R, V, p)
    local g = grid(t)
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local def = g:getBuildingAt(x, y, z)
    if def == nil then t:skip("stand inside a building of the map") end
    local site, why = R.check(def, {}, { minDistance = 0, minArea = 1,
        rules = { { kind = "test", label = "building", main = {} } } }, g)
    if site == nil then t:skip("building refused: " .. tostring(why)) end
    workStore(t, R)
    forgetTestVoice(t)
    local id, rec = R.startForTeam(R.teamOf(p), { site = site, days = 1, voice = SAVED_VOICE, requester = "RST" })
    t:ok(id ~= nil, "start: " .. tostring(rec))
    t:eq(1, R.noteHelpers(id, { V.helper(p) }), "the player was not noted as a helper")
    t:ok(V.leave(id), "the survivors did not leave")
    return id
end

RST.suite("rs.rescue.saved", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local Sc = sceneModule(t)
        local R = module(t)
        local V = visitModule(t)
        for _, name in ipairs({ "prepare", "poll", "note", "move", "placeWords", "facts", "remember" }) do
            t:eq("function", type(Sc[name]), "RS_RescueScene." .. name)
        end
        for _, name in ipairs({ "noteHelpers", "helpedActive", "isWorkStore" }) do
            t:eq("function", type(R[name]), "RS_Rescue." .. name)
        end
        t:eq("function", type(R.sceneHook), "RS_Rescue.sceneHook (set by RS_RescueScene)")
        t:eq("function", type(V.leave), "RS_RescueVisit.leave")
    end)

    s.test("helpers then departure: saved, the voice moves and remembers the player", function(t)
        local Sc = sceneModule(t)
        local R = module(t)
        local V = visitModule(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        pauseVisits(t, V)
        pauseScenes(t, Sc)
        local id = savedHere(t, R, V, p)
        local rec = R.get(id)
        t:eq("saved", rec.state, "state")
        t:eq("pending", rec.scene, "scene")
        t:ok(type(rec.cache) == "table" and type(rec.cache.note) == "table", "no cache with a note prepared")
        t:ok(not string.find(rec.cache.note.text, "IGUI_", 1, true), "raw key in the note: " .. rec.cache.note.text)
        t:ok(type(rec.moved) == "table" and type(rec.moved.place) == "string", "no new place")
        t:ok(rec.moved.key ~= rec.site.key, "moved to the same building")
        local PersonaState = require "RadioSurvivor/RS_PersonaState"
        local state = PersonaState.get(SAVED_VOICE)
        t:eq(rec.moved.place, state and state.place, "place of the voice")
        local Memory = require "RadioSurvivor/RS_Memory"
        local h = V.helper(p)
        local facts = Memory.facts(SAVED_VOICE, h.caller, h.cid)
        t:eq(Sc.FACT_SAVED, facts[1], "memory of the voice on the player")
        t:note("helper " .. tostring(h.name) .. " (" .. tostring(h.caller) .. "), new place: " .. rec.moved.place
            .. "; note: " .. rec.cache.note.name)
    end)

    s.test("the scene is placed once, when the site is loaded", function(t)
        local Sc = sceneModule(t)
        local R = module(t)
        local V = visitModule(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        pauseVisits(t, V)
        local poll = pauseScenes(t, Sc)
        local id = savedHere(t, R, V, p)
        local rec = R.get(id)
        t:defer(function()
            for _, e in ipairs(markedBags(rec.site.bounds, rec.cache.spot.z, id)) do
                e.square:transmitRemoveItemFromSquare(e.object)
            end
        end, "remove the test bag")
        Sc.resetForTests()
        t:ok(poll(true), "the scene was not placed")
        t:eq("placed", R.get(id).scene, "scene state")
        local bags = markedBags(rec.site.bounds, rec.cache.spot.z, id)
        t:eq(1, #bags, "bags on the floor")
        local note = nil
        local items = bags[1] and bags[1].item:getItemContainer():getItems()
        for i = 0, (items and items:size() or 0) - 1 do
            if items:get(i):getFullType() == "Base.SheetPaper2" then note = items:get(i) end
        end
        t:ok(note ~= nil, "no note in the bag")
        t:eq("RadioSurvivor", note and note:getLockedBy(), "note locked")
        Sc.resetForTests()
        t:ok(not poll(true), "second poll placed something")
        t:eq(1, #markedBags(rec.site.bounds, rec.cache.spot.z, id), "bags after a second poll")
        local at = R.get(id).cache.at
        t:note("bag at " .. at.x .. "," .. at.y .. "," .. at.z .. ", table " .. R.get(id).cache.table
            .. ", note: " .. tostring(note and note:getName()))
    end)
end)

--[[
rs.rescue.missed - outcome "too late" (E12-T05, zombies since E12-T07; server/RadioSurvivor/RS_RescueLost.lua,
RS_Rescue.drawSurvivors). Tag "server". WORK store and a rescue on the building where the target player stands (stand
INSIDE a building of the map, on a floor with a few free squares around the room centre). The background polls of
RS_RescueVisit and RS_RescueLost are paused during the run. The reserves are consumed to zero (outcome "missed"),
then the scene is placed (site loaded: the player stands in it): one zombie per survivor (a reanimated player, found
in the zombie list by its mark), wearing the outfit the voice described (getOutfitName), no corpse placed, the
requester's zombie carrying a locked notebook "Last pages of RST" in its INVENTORY and the others none; a second poll
and a simulated stop between "placing" and "placed" place nothing more. The requester's zombie is then killed on the
authority (setAttackedBy + die): its corpse holds the notebook. Zombies and corpses are removed at the end (the
player is next to fresh zombies for a moment). Solo: RST.server("rs.rescue.missed"). Multiplayer (E12-T07, E01-T16):
the other clients hold a copy of the requester's zombie before it is killed (lk.present), then every client sees the
same corpse, notebook included, around the death square (world.keys, RST_PeerChecks.lua).
Outside the game: tests/test_rescue_lost.py.
]]

local function lostModule(t)
    module(t)
    local L = require "RadioSurvivor/RS_RescueLost"
    if type(L) ~= "table" then t:skip("RS_RescueLost did not return its table here") end
    return L
end

local function markIndex(L, o, prefix)
    if not o:hasModData() then return nil end
    local mark = o:getModData()[L.CONFIG.BODY_MARK]
    if type(mark) ~= "string" or string.sub(mark, 1, #prefix) ~= prefix then return nil end
    return tonumber(string.sub(mark, #prefix + 1))
end

-- Corpses of the rectangle x1..x2-1, y1..y2-1 (floor z) marked for the rescue id: index -> body, count.
local function lostBodies(L, b, z, id)
    local out, n = {}, 0
    local cell = getCell()
    local prefix = id .. "#"
    for x = b.x1, b.x2 - 1 do
        for y = b.y1, b.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            local objects = sq and sq:getStaticMovingObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                local index = instanceof(o, "IsoDeadBody") and markIndex(L, o, prefix) or nil
                if index then
                    out[index] = o
                    n = n + 1
                end
            end
        end
    end
    return out, n
end

-- Living zombies of the zombie list marked for the rescue id: index -> zombie, count.
local function lostZombies(L, id)
    local out, n = {}, 0
    local list = getCell():getZombieList()
    local prefix = id .. "#"
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        local index = zed ~= nil and not zed:isDead() and markIndex(L, zed, prefix) or nil
        if index then
            out[index] = zed
            n = n + 1
        end
    end
    return out, n
end

local function notebooks(container)
    local out = {}
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        if items:get(i):getFullType() == "Base.Notebook" then out[#out + 1] = items:get(i) end
    end
    return out
end

local function missedHere(t, R, p)
    local id, rec = rescueHere(t, R, p)
    R.consume((rec.reserves or 24) + 1)
    return id
end

RST.suite("rs.rescue.missed", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local L = lostModule(t)
        local R = module(t)
        for _, name in ipairs({ "prepare", "poll", "place", "pages", "document", "survivors", "resetForTests" }) do
            t:eq("function", type(L[name]), "RS_RescueLost." .. name)
        end
        for _, name in ipairs({ "drawSurvivors", "looks" }) do
            t:eq("function", type(R[name]), "RS_Rescue." .. name)
        end
        t:ok(type(R.OUTFITS) == "table" and #R.OUTFITS > 0, "RS_Rescue.OUTFITS")
    end)

    s.test("the survivors describe their outfits", function(t)
        lostModule(t)
        local R = module(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        local id = rescueHere(t, R, p)
        local rec = R.get(id)
        t:ok(#rec.survivors >= R.SURVIVORS.MIN and #rec.survivors <= R.SURVIVORS.MAX, "survivors " .. #rec.survivors)
        t:eq(#rec.survivors, #rec.looks, "one description per survivor")
        for i, line in ipairs(rec.looks) do
            t:ok(string.find(line, rec.survivors[i].look, 1, true) ~= nil, "description " .. i .. ": " .. line)
            t:ok(not string.find(line, "%d"), "digit in a description: " .. line)
        end
        t:note(table.concat(rec.looks, " "))
    end)

    s.test("too late: survivors are zombies in the described outfits, the requester carries the last pages",
        function(t)
        local L = lostModule(t)
        local R = module(t)
        local V = visitModule(t)
        local p = player(t)
        if p == nil then t:skip("no target player") end
        pauseVisits(t, V)
        local poll = L.poll
        L.poll = function() return false end
        t:defer(function() L.poll = poll L.resetForTests() end, "resume the too-late poll")
        local id = missedHere(t, R, p)
        local rec = R.get(id)
        t:eq("missed", rec.state, "state")
        t:ok(type(rec.lost) == "table", "no scene prepared")
        local b, z = rec.site.bounds, rec.site.z or 0
        local killedAt = nil
        t:defer(function()
            for _, zed in pairs(lostZombies(L, id)) do
                zed:setHealth(0)   -- a reanimated player only removed would come back with its chunk
                zed:removeFromWorld()
                zed:removeFromSquare()
            end
            local areas = { b }
            if killedAt ~= nil then
                areas[2] = { x1 = killedAt.x - 1, y1 = killedAt.y - 1, x2 = killedAt.x + 2, y2 = killedAt.y + 2 }
            end
            for _, area in ipairs(areas) do
                for _, body in pairs(lostBodies(L, area, killedAt and killedAt.z or z, id)) do
                    body:getSquare():removeCorpse(body, false)
                end
            end
        end, "remove the test zombies and corpses")
        L.resetForTests()
        t:ok(poll(true), "the scene was not placed")
        t:eq("placed", R.get(id).scene, "scene state")
        local zombies, n = lostZombies(L, id)
        t:eq(#rec.survivors, n, "zombies")
        local _, corpses = lostBodies(L, b, z, id)
        t:eq(0, corpses, "corpses placed")
        for i, survivor in ipairs(rec.survivors) do
            local zed = zombies[i]
            t:ok(zed ~= nil, "no zombie for survivor " .. i)
            t:eq(survivor.outfit, zed and zed:getOutfitName(), "outfit of survivor " .. i)
            t:ok(zed and zed:isReanimatedPlayer(), "survivor " .. i .. " is not a reanimated player (would lose "
                .. "its inventory)")
            if i > 1 then t:eq(0, #notebooks(zed and zed:getInventory()), "last pages carried by survivor " .. i) end
        end
        local carried = notebooks(zombies[1] and zombies[1]:getInventory())
        t:eq(1, #carried, "last pages in the requester's inventory")
        local note = carried[1]
        t:eq("RadioSurvivor", note and note:getLockedBy(), "last pages locked")
        L.resetForTests()
        t:ok(not poll(true), "second poll placed something")
        -- Simulated stop between placing and placed: adopted, nothing doubled.
        local d = R.store()
        local raw = d.rescues[id]
        raw.lost.placed, raw.lost.placing, raw.scene = false, true, "pending"
        L.resetForTests()
        t:ok(poll(true), "the scene was not adopted")
        local after, again = lostZombies(L, id)
        t:eq(n, again, "zombies after a stop")
        t:eq(1, #notebooks(after[1] and after[1]:getInventory()), "last pages after a stop")
        -- The requester is killed: its corpse holds the last pages.
        local requester = after[1]
        t:ok(requester ~= nil and requester:getCurrentSquare() ~= nil, "requester's zombie not on a square")
        -- E12-T07 (E01-T16): the other clients hold a copy of the zombie before its death (a zombie killed before
        -- its copy reached a client leaves no corpse there), then see the same corpse with the last pages.
        RST.PeerChecks.waitCopies(t, { requester }, function(tw)
            local sq = requester:getCurrentSquare()
            tw:ok(sq ~= nil, "requester's zombie not on a square")
            killedAt = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
            requester:setAttackedBy(p)
            requester:die()
            local area = { x1 = killedAt.x - 1, y1 = killedAt.y - 1, x2 = killedAt.x + 2, y2 = killedAt.y + 2 }
            tw:waitUntil(function() return lostBodies(L, area, killedAt.z, id)[1] ~= nil end, 5000, function(t2)
                local body = lostBodies(L, area, killedAt.z, id)[1]
                local inBody = notebooks(body:getContainer())
                t2:eq(1, #inBody, "last pages in the requester's corpse")
                t2:eq(rec.survivors[1].outfit, body:getOutfitName(), "outfit of the requester's corpse")
                t2:note("outfits " .. table.concat(R.get(id).lost.outfits, ", ") .. "; pages: "
                    .. tostring(inBody[1] and inBody[1]:getName()))
                -- world.keys: corpse keys (worn clothes and content, the notebook included) of the 3 x 3 squares.
                RST.PeerChecks.checkSquares(t2, RST.PeerChecks.around(killedAt.x, killedAt.y, killedAt.z, 1),
                    { corpse = true }, nil, true)
            end, "no corpse of the requester after its death")
        end)
    end)
end)
