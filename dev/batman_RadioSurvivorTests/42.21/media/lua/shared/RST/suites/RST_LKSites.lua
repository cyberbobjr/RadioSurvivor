--[[
lk.sites - choice of the home site of a Living Knox group without loading the area (LK08-T03,
server/LivingKnox/LK_Sites.lua): a habitable building for the group types whose home is "building" (settlers,
neutrals), a forest clearing for "forest" (raiders) or, when no forest zone is known without loading, the most
isolated building seen (LK08-T08: habitable or a lair such as a warehouse, barn, garage, gas station or workshop;
degressive isolation tiers, best candidate at worst) marked fallback = "isolated-building"; far from the player bases
(safehouses, players, avoided points) and from the homes of the other groups; no chunk loaded by the choice. Every
seed must give a site.
Tag "server": LK_Sites starts with "if isClient() then return end" (authority only). Read-only: no item, no
ModData, no group home written, no world change. Solo: RST.server("lk.sites") (the requester is the target player);
dedicated server: RST.server("lk.sites") from an admin client. Asynchronous run only (a 3 s watch of LoadChunk);
outside the game: tests/test_lk_sites.py.

Probe of "no chunk loaded" (the engine has no Lua counter of loaded chunks), as in rs.rescue.pick:
    - LoadChunk events counted during the picks (synchronous: must stay at 0) and for 3 s after them, with the
      position of each loaded chunk: none may fall inside a picked site;
    - readable squares: getCell():getGridSquare at the centre of every chunk of a 21 x 21 chunk window around the
      player, before and after the picks (same count, above 0), and at the centre of every chunk covered by each
      site (0 before the wait, 0 after);
    - BuildingDef:isFullyStreamedIn() of each picked building false.
Every site is printed as a note "site type=... seed=..." with its coordinates, kind and source so that the tester can
teleport there (forest clearing: trees and slope are not checked by the choice, see docs/annexes/conception/sites.md).
]]

require "RST/RST"

local SEEDS = { 11, 23, 37, 41, 59 }
local WATCH_MS = 3000
local WINDOW = 10 -- chunks on each side of the player for the readable-square probe

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Sites is not loaded on an MP client (authority only)")
    end
    require "LivingKnox/LK_Sites"
    local S = LivingKnox and LivingKnox.Sites
    if type(S) ~= "table" then t:skip("LivingKnox.Sites is not loaded here") end
    return S
end

local function grid(t)
    local w = getWorld and getWorld()
    local g = w and w:getMetaGrid()
    t:ok(g ~= nil, "getWorld():getMetaGrid() is nil")
    return g
end

local function types()
    local GT = LivingKnox and LivingKnox.GroupTypes
    return GT and GT.ids() or {}
end

local function player(t)
    return t.ctx and t.ctx.player or nil
end

-- Rectangle covered by a site (fin exclusive).
local function bounds(site)
    if site.bounds then return site.bounds end
    local r = site.radius or 0
    return { x1 = site.x - r, y1 = site.y - r, x2 = site.x + r + 1, y2 = site.y + r + 1 }
end

local function chunkReadable(cell, wx, wy, z)
    return cell:getGridSquare(wx * 8 + 4, wy * 8 + 4, z) ~= nil
end

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

local function readableSite(site)
    local cell = getCell and getCell()
    if cell == nil then return 0 end
    local b = bounds(site)
    local n = 0
    for wy = math.floor(b.y1 / 8), math.floor((b.y2 - 1) / 8) do
        for wx = math.floor(b.x1 / 8), math.floor((b.x2 - 1) / 8) do
            if chunkReadable(cell, wx, wy, 0) then n = n + 1 end
        end
    end
    return n
end

local function insideSite(site, x, y)
    local b = bounds(site)
    return x >= b.x1 - 8 and x < b.x2 + 8 and y >= b.y1 - 8 and y < b.y2 + 8
end

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

local function now()
    return getTimestampMs and getTimestampMs() or 0
end

local function siteNote(t, gtype, seed, site, ms)
    t:note("site type=" .. gtype .. " seed=" .. tostring(seed) .. " " .. site.kind .. " " .. site.key .. " at "
        .. site.x .. "," .. site.y .. "," .. site.z .. " (" .. tostring(site.buildingKind or site.zone)
        .. (site.fallback and (", FALLBACK " .. site.fallback .. " isolation " .. tostring(site.isolation)
            .. " tier " .. tostring(site.isolationTier) .. (site.lair and " lair" or "") .. " best of "
            .. tostring(site.candidates)) or "") .. ") base " .. tostring(site.baseDistance)
        .. ", home " .. tostring(site.groupDistance) .. ", " .. site.attempts .. " draw(s), " .. ms .. " ms")
end

-- Checks a site against the rules again (same context as the pick).
local function checkSite(t, S, g, gtype, site, seed)
    local label = gtype .. " seed " .. seed
    local style = S.homeStyle(gtype)
    local ctx = S.context(gtype, {}, g)
    if site.kind == "building" then
        t:ok(style == "building" or site.fallback == "isolated-building",
            label .. ": building for a forest group without the fallback mark")
        local def = g:getBuildingAt(site.x, site.y, site.z)
        t:ok(def ~= nil, label .. ": no building of the metagrid at the site point")
        t:eq(site.buildingId, def:getIDString(), label .. ": building at the site point")
        local again, why = S.checkBuilding(def, ctx, site.fallback ~= nil)
        t:ok(again ~= nil, label .. ": building no longer accepted: " .. tostring(why))
        if site.fallback and again then
            t:eq(site.isolation, again.isolation, label .. ": isolation measured again")
            t:eq(site.isolationTier, again.isolationTier, label .. ": isolation tier")
            t:ok(site.isolation >= S.tierAt(site.attempts, S.CONFIG.MAX_ATTEMPTS)
                or site.attempts == S.CONFIG.MAX_ATTEMPTS, label .. ": returned below the tier of its last draw")
            t:ok(site.attempts <= S.CONFIG.MAX_ATTEMPTS, label .. ": more draws than MAX_ATTEMPTS")
        end
    else
        t:eq("forest", style, label .. ": clearing for a building group")
        t:eq("clearing", site.kind, label .. ": unknown kind")
        local again, why = S.checkClearing(site.x, site.y, ctx)
        t:ok(again ~= nil, label .. ": clearing no longer accepted: " .. tostring(why))
    end
    local Rescue = require "RadioSurvivor/RS_Rescue"
    for _, base in ipairs(ctx.bases) do
        t:ok(Rescue.gap(bounds(site), base) >= S.CONFIG.BASE_DISTANCE,
            label .. ": site closer than BASE_DISTANCE to a " .. base.source)
    end
    for _, home in ipairs(ctx.homes) do
        t:ok(Rescue.gap(bounds(site), home) >= S.CONFIG.GROUP_DISTANCE,
            label .. ": site closer than GROUP_DISTANCE to the home of " .. home.source)
    end
end

RST.suite("lk.sites", { tags = { "server" }, testTimeoutMs = 90000 }, function(s)
    s.test("module exports", function(t)
        local S = module(t)
        for _, name in ipairs({ "pick", "checkBuilding", "checkClearing", "forestZones", "groupHomes", "homeStyle",
            "context", "tierAt" }) do
            t:eq("function", type(S[name]), "LivingKnox.Sites." .. name)
        end
        t:ok(#types() > 0, "no group type registered")
    end)

    s.test("forest zones known without loading", function(t)
        local S = module(t)
        local g = grid(t)
        local started = now()
        local found = S.forestZones(g)
        local area = 0
        local byType = {}
        for _, z in ipairs(found.zones) do
            area = area + z.w * z.h
            byType[z.type] = (byType[z.type] or 0) + 1
        end
        local parts = {}
        for k, n in pairs(byType) do parts[#parts + 1] = k .. " " .. n end
        table.sort(parts)
        t:note("cells with data " .. found.cells .. ", known (biomemap zones registered) " .. found.known
            .. ", grid slots scanned " .. found.scanned .. (found.truncated and " (truncated)" or "")
            .. "; forest zones " .. #found.zones .. " (" .. table.concat(parts, ", ") .. "), area " .. area
            .. " squares, " .. (now() - started) .. " ms")
        if #found.zones == 0 then
            t:note("no forest zone known: forest groups use the isolated-building fallback in this game")
        end
    end)

    s.test("seeded picks per group type are valid, far from bases and homes, varied and reproducible", function(t)
        local S = module(t)
        local g = grid(t)
        for _, gtype in ipairs(types()) do
            local keys, distinct = {}, 0
            for _, seed in ipairs(SEEDS) do
                local started = now()
                local site, reason = S.pick(gtype, { seed = seed })
                local ms = now() - started
                t:ok(site ~= nil, gtype .. " seed " .. seed .. ": " .. tostring(reason))
                checkSite(t, S, g, gtype, site, seed)
                siteNote(t, gtype, seed, site, ms)
                if not keys[site.key] then distinct = distinct + 1 end
                keys[site.key] = true
                local again = S.pick(gtype, { seed = seed })
                t:eq(site.key, again and again.key, gtype .. " seed " .. seed .. ": same seed, same site")
            end
            t:ok(distinct >= 2, gtype .. ": the same site for every seed")
            t:note(gtype .. ": " .. distinct .. " distinct site(s) for " .. #SEEDS .. " seeds")
        end
    end)

    s.test("no chunk is loaded by the picks (LoadChunk, readable squares, streaming)", function(t)
        local S = module(t)
        local g = grid(t)
        local p = player(t)
        local rec = watchChunks(t)
        local before = p and readableAround(p:getX(), p:getY(), WINDOW) or nil
        local sites = {}
        for _, gtype in ipairs(types()) do
            for _, seed in ipairs(SEEDS) do
                local site, reason = S.pick(gtype, { seed = seed + 1000 })
                t:ok(site ~= nil, gtype .. " seed " .. seed .. ": " .. tostring(reason))
                sites[#sites + 1] = site
            end
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
            t:eq(0, readableSite(site), site.key .. ": a chunk of the site is readable")
            if site.kind == "building" then
                local def = g:getBuildingAt(site.x, site.y, site.z)
                t:ok(def ~= nil and not def:isFullyStreamedIn(), site.key .. ": building fully streamed in")
            end
        end
        t:sleep(WATCH_MS, function(t2)
            for _, pos in ipairs(rec.positions) do
                for _, site in ipairs(sites) do
                    t2:ok(not insideSite(site, pos.x, pos.y), site.key .. ": a chunk of the site was loaded")
                end
            end
            for _, site in ipairs(sites) do
                t2:eq(0, readableSite(site), site.key .. ": a chunk of the site is readable after the wait")
            end
            t2:note("LoadChunk events during the " .. WATCH_MS .. " ms watch: " .. rec.count)
        end)
    end)

    s.test("an impossible distance is refused with a reason, within the draw bound", function(t)
        local S = module(t)
        local opts = { seed = 1, baseDistance = 1000000, avoid = { { x = 0, y = 0 } } }
        local site, reason = S.pick("settlers", opts)
        t:eq(nil, site, "a building was picked although every building is too close")
        t:ok(string.find(tostring(reason), "near a known base", 1, true) ~= nil, "reason: " .. tostring(reason))
        t:ok(string.find(tostring(reason), S.CONFIG.MAX_ATTEMPTS .. " draw(s)", 1, true) ~= nil,
            "reason without the draw bound: " .. tostring(reason))
        local camp, why = S.pick("raiders", opts)
        t:eq(nil, camp, "a camp was picked although every point is too close")
        t:note("raiders, impossible distance: " .. tostring(why))
    end)

    s.test("the home of another group keeps the site away", function(t)
        local S = module(t)
        local Rescue = require "RadioSurvivor/RS_Rescue"
        for _, gtype in ipairs(types()) do
            local first = S.pick(gtype, { seed = SEEDS[1] })
            t:ok(first ~= nil, gtype .. ": no site for the reference seed")
            local other = S.pick(gtype, { seed = SEEDS[1], homes = { { x = first.x, y = first.y } } })
            t:ok(other ~= nil, gtype .. ": no site once the first one is a group home")
            t:ok(other.key ~= first.key, gtype .. ": the home site was picked again")
            t:ok(Rescue.gap(bounds(other), { x1 = first.x, y1 = first.y, x2 = first.x + 1, y2 = first.y + 1 })
                >= S.CONFIG.GROUP_DISTANCE, gtype .. ": second site too close to the first home")
        end
    end)
end)
