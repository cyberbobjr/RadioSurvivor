--[[
rs.observations - notebook and Living Knox triggers of the NPC observations (E08-T07,
server/RadioSurvivor/RS_ObservationTriggers.lua) on the running engine: each fact once per admissible witness, never
for an NPC that could not see it, no coordinate, no fiche created by a trigger.
Scene (every test): Living Knox test npcs around the requester (LivingKnox.API.testSpawnNpc): A and B (2 squares),
C (3 squares, NOT in the group), D (3 squares, in the group, NO fiche) and F (FAR_DX squares, when that square is
loaded); a test group (LivingKnox.Groups.create, home at the requester, furnishing skipped, players hidden from its
members) with A, B, D, F and one member without body; fiches of A, B, C, F (RS_CarnetServer.ensure).
    assault_seen  LivingKnox.Hostility.record(group, character, "hit", witnessed, witnesses A and D): A remembers it
                  once (same call again: still once); B, C, F nothing; D still has no fiche.
    group_death   D (in the group, no fiche) is killed (Kill, reference health lowered): the members with a fiche that
                  see D within witnessRange when it dies (computed just before the kill: same floor, distance,
                  CanSee) remember it once (subject <group>-<member>), the others nothing, C (other group) nothing,
                  even seconds later (no second publication). The squares of A, B and D are chosen BEFORE the spawn
                  with a line of sight that holds (witnessSpots: LosUtil.lineClear, the rule of CanSee, from A and B
                  to D and from their free neighbours, so that a body pushed by one square still sees): the default
                  spots when they qualify, otherwise the nearest free squares around the requester (outdoors first).
                  No such squares, or no witness seeing D at the kill: FAIL (never a SKIP).
    off screen    the member without body dies (LivingKnox.Groups.markDead): members present at home with a fiche (A,
                  B, F) remember it once at the area of the home; C nothing.
    player_return A and F are known to the requester's character (contacts) and were last heard one game day ago
                  (nearHour moved back, the day is not waited): at the next notebook polls A (in hearing range)
                  remembers the comeback once; F only if it hears the player then; B (no contact) nothing.
    mission_done  a mission of A succeeds (RS_Missions.finish): A remembers it once per participant; finishing again
                  changes nothing; B nothing. The suite brings the template: the "deliver" offer of the catalogue with
                  test supply terms (RS_Missions.create(state, A, character, offer id, terms): with Living Knox the
                  engine supplies are the only deliver offers of an NPC fiche, and a test group has none), created,
                  accepted and finished in one step (no engine poll in between); a refused creation is a FAIL.
Every test: number of fiches unchanged by the triggers; every place is a coarse area (area-<x>-<y>), never a position.
Tags "server" and "world": the authority (solo, or RST.server from an admin client), save rstest*, Living Knox on
(test API: debug mode). MP: autoclient.py --mp --clients 2 --server-suite rs.observations --server-tags world.
Cleanup: test group removed, test npcs and the corpse removed, contacts and test mission removed. Observations
written in the fiches of the test npcs stay (fiches pruned later by the notebook), so does the reputation record of the
mission success (RS_Missions.finish).
Outside the game: tests/test_rs_mp_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local FAR_DX = 40
local SEEN_MS = 15000
local SETTLE_MS = 3000
local DEAD_MS = 10000

local function LK() return LivingKnox end

-- ---------------------------------------------------------------- group_death: squares with a line of sight

local DEFAULT_SPOTS = { A = { 2, 0 }, B = { 2, 1 }, C = { 3, -1 }, D = { 3, 1 }, F = { FAR_DX, 0 } }
local SEARCH_RADIUS = 10

-- Line of sight from square (x0, y0) to (x1, y1) as CanSee computes it (perception.md: lineClear ~= Blocked); nil
-- when LosUtil is not exposed here.
local function losClear(x0, y0, x1, y1, z)
    if LosUtil == nil or LosUtil.lineClear == nil then return nil end
    local ok, res = pcall(LosUtil.lineClear, getCell(), x0, y0, z, x1, y1, z, false)
    if not ok then return nil end
    return tostring(res) ~= "Blocked"
end

local function freeSquare(x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return nil end
    local ok, free = pcall(function() return sq:isFree(false) end)
    if not ok or not free then return nil end
    local okS, stairs = pcall(function() return sq:HasStairs() end)
    if okS and stairs then return nil end
    return sq
end

-- The observer square o sees t, and every free neighbour of o that o sees also sees the free neighbours of t that t
-- sees (a body pushed by one square keeps the line: lineClear is not stable near a wall corner, perception.md).
local function robustSight(ox, oy, tx, ty, z)
    if losClear(ox, oy, tx, ty, z) ~= true then return false end
    for ay = -1, 1 do
        for ax = -1, 1 do
            local nx, ny = ox + ax, oy + ay
            if freeSquare(nx, ny, z) and losClear(ox, oy, nx, ny, z) then
                for by = -1, 1 do
                    for bx = -1, 1 do
                        local mx, my = tx + bx, ty + by
                        if freeSquare(mx, my, z) and losClear(tx, ty, mx, my, z)
                            and losClear(nx, ny, mx, my, z) ~= true then
                            return false
                        end
                    end
                end
            end
        end
    end
    return true
end

-- A at a, B at a + (0, 1), D at a + (1, 1) (offsets of the default layout): every square free, distinct from the
-- requester's square, A and B both seeing D robustly within range.
local function layoutAt(ax, ay, z, px, py, range)
    local A, B, D = { ax, ay }, { ax, ay + 1 }, { ax + 1, ay + 1 }
    for _, s in ipairs({ A, B, D }) do
        if (s[1] == px and s[2] == py) or not freeSquare(s[1], s[2], z) then return nil end
    end
    for _, s in ipairs({ A, B }) do
        local dx, dy = s[1] - D[1], s[2] - D[2]
        if dx * dx + dy * dy > range * range then return nil end
        if not robustSight(s[1], s[2], D[1], D[2], z) then return nil end
    end
    return { A = A, B = B, D = D }
end

-- Absolute squares of A, B, D for the death scene: the default layout when it qualifies, else the nearest anchor
-- (outdoors first, then any square) within SEARCH_RADIUS of the requester; without LosUtil the default layout
-- (the measure at the kill decides). Returns layout, how (text), or nil and the reason.
local function witnessSpots(x, y, z, range)
    local function abs(off) return { x + off[1], y + off[2] } end
    if LosUtil == nil or LosUtil.lineClear == nil then
        return { A = abs(DEFAULT_SPOTS.A), B = abs(DEFAULT_SPOTS.B), D = abs(DEFAULT_SPOTS.D) },
            "default spots (LosUtil not exposed here)"
    end
    local d = layoutAt(x + DEFAULT_SPOTS.A[1], y + DEFAULT_SPOTS.A[2], z, x, y, range)
    if d ~= nil then return d, "default spots" end
    for pass = 1, 2 do
        for r = 1, SEARCH_RADIUS do
            for dy = -r, r do
                for dx = -r, r do
                    if math.max(math.abs(dx), math.abs(dy)) == r then
                        local sq = getCell():getGridSquare(x + dx, y + dy, z)
                        if sq ~= nil and (pass == 2 or sq:isOutside()) then
                            local l = layoutAt(x + dx, y + dy, z, x, y, range)
                            if l ~= nil then
                                return l, "searched spots (" .. (pass == 1 and "outdoors" or "any square") .. ", "
                                    .. r .. " squares away)"
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, "no free squares within " .. SEARCH_RADIUS .. " of the requester where A and B see D (LosUtil)"
end

local function setup(t)
    if type(isClient) == "function" and isClient() then t:skip("observations live on the authority") end
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    local ready, why = RST.Fixtures.npcReady()
    if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
    local E = LK()
    t:ok(E.Groups ~= nil and E.Hostility ~= nil and E.Bodies ~= nil, "Living Knox server part not loaded here")
    t:ok(E.Groups.ensure(), "group registry not ready")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local C = require "RadioSurvivor/RS_Config"
    local cid = Server.bound[p]
    if cid == nil then
        Server.command(C.MODULE, "hello", p, {})
        cid = Server.bound[p]
    end
    t:ok(type(cid) == "string", "no notebook character bound to the requester")
    return { Server = Server, S = Server.store, C = C, E = E, API = E.API, p = p, cid = cid,
        Obs = require "RadioSurvivor/RS_Observations", P = require "RadioSurvivor/RS_NPCProvider",
        M = require "RadioSurvivor/RS_Missions" }
end

local function count(tbl)
    local k = 0
    for _, _ in pairs(tbl or {}) do k = k + 1 end
    return k
end

-- Corpses of a test npc (tagged with its id) removed around (x, y, z).
local function removeCorpses(E, id, x, y, z)
    for dy = -4, 4 do
        for dx = -4, 4 do
            local sq = getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = (list and list:size() or 0) - 1, 0, -1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") and o:hasModData() and E.Identity.readTag(o:getModData()) == id then
                    sq:removeCorpse(o, false)
                end
            end
        end
    end
end

-- The scene of the header, then after(t, sc). sc.ids[name] = provider id, sc.fiches[name] = fiche, sc.gid, sc.mid
-- (member id of each name, and "M" for the member without body).
-- sightLine true: A, B and D on the squares of witnessSpots (group_death with a body).
local function scene(t, after, sightLine)
    local c = setup(t)
    local E, API, p = c.E, c.API, c.p
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local at = {}
    for name, off in pairs(DEFAULT_SPOTS) do at[name] = { x + off[1], y + off[2] } end
    if sightLine then
        local l, how = witnessSpots(x, y, z, c.C.Observations.witnessRange)
        t:ok(l ~= nil, "group_death scene: " .. tostring(how))
        at.A, at.B, at.D = l.A, l.B, l.D
        t:note("death scene: " .. how .. ": A " .. at.A[1] .. "," .. at.A[2] .. ", B " .. at.B[1] .. "," .. at.B[2]
            .. ", D " .. at.D[1] .. "," .. at.D[2] .. " (requester " .. x .. "," .. y .. ")")
    end
    local ids = {}
    for _, name in ipairs({ "A", "B", "C", "D", "F" }) do
        local s = at[name]
        local id, why = API.testSpawnNpc(s[1], s[2], z)
        if id ~= nil then
            ids[name] = id
            t:defer(function() API.testRemoveNpc(id) end, "remove test npc " .. name .. " " .. id)
        elseif name ~= "F" then
            t:skip("test npc " .. name .. " not spawned: " .. tostring(why))
        else
            t:note("far npc F not spawned (" .. tostring(why) .. "): its negative checks are left out")
        end
    end
    local G = E.Groups
    local g = G.create({ type = "settlers", name = "RST witnesses", day = G.today(), home = { x = x, y = y, z = z } })
    t:ok(g ~= nil, "test group not created")
    local gid = g.id
    if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
    -- The member without body is materialized by Living Knox as a real npc while the requester is near (not a test
    -- npc: testRemoveNpc refuses it) and G.remove leaves that body in the world: a leaked body stood on the spot of
    -- the next suites (rs.relation npc moved behind a wall, select refused). Its npc is despawned with the group.
    t:defer(function()
        local spawned = {}
        for _, id in pairs(ids) do spawned[id] = true end
        local g2 = G.get(gid)
        local extra = {}
        for _, m in pairs(g2 and g2.members or {}) do
            if m.npc ~= nil and not spawned[m.npc] then extra[#extra + 1] = m.npc end
        end
        G.remove(gid)
        for _, npc in ipairs(extra) do
            if E.Directives ~= nil and E.Directives.forget ~= nil then E.Directives.forget(npc) end
            E.Bodies.despawn(npc, true)
        end
    end, "remove test group " .. gid .. " and the bodies of its materialized members")
    if E.Senses ~= nil and E.Senses.perceived ~= nil then
        local perceived = E.Senses.perceived
        E.Senses.perceived = function(id)
            local per = perceived(id)
            if per ~= nil and G.findNpc(id) == gid then
                local out = {}
                for k, v in pairs(per) do out[k] = v end
                out.p = {}
                return out
            end
            return per
        end
        t:defer(function() E.Senses.perceived = perceived end, "players visible again to " .. gid)
    end
    local mid = {}
    for _, name in ipairs({ "A", "B", "D", "F" }) do
        if ids[name] ~= nil then
            mid[name] = G.addMember(gid, { role = "worker", npc = ids[name], day = G.today() })
            t:ok(mid[name] ~= nil, "npc " .. name .. " not added to the test group")
        end
    end
    mid.M = G.addMember(gid, { role = "worker", day = G.today() })
    t:ok(mid.M ~= nil, "member without body not added")
    t:waitUntil(function()
        local objects = c.P.objects()
        for _, id in pairs(ids) do if objects[id] == nil then return false end end
        return true
    end, SEEN_MS, function(t2)
        local fiches = {}
        for _, name in ipairs({ "A", "B", "C", "F" }) do
            if ids[name] ~= nil then
                fiches[name] = c.Server.ensure(ids[name])
                t2:ok(fiches[name] ~= nil, "no fiche for test npc " .. name)
            end
        end
        t2:waitUntil(function()
            for _, f in pairs(fiches) do if c.Server.objects[f.id] == nil then return false end end
            return true
        end, SEEN_MS, function(t3)
            return after(t3, { c = c, ids = ids, fiches = fiches, gid = gid, mid = mid, x = x, y = y, z = z })
        end, "bodies of the test fiches never mapped by the notebook")
    end, "the notebook provider never saw every test npc")
end

-- Observations of fact in the fiche of name: list of entries (copies).
local function facts(sc, name, fact)
    local out = {}
    local f = sc.fiches[name]
    if f == nil then return out end
    for _, item in ipairs(sc.c.Obs.list(f.id)) do if item.fact == fact then out[#out + 1] = item end end
    return out
end

local function checkCommon(t, sc, before, fact)
    t:eq(before, count(sc.c.S.data.npcs), "fiches created or removed by the trigger " .. fact)
    t:eq(nil, sc.c.Server.find(sc.ids.D), "fiche created for D (no contact)")
    for name in pairs(sc.fiches) do
        for _, item in ipairs(facts(sc, name, fact)) do
            t:ok(string.find(item.place, "^area%-%-?%d+%-%-?%d+$") ~= nil, fact .. " of " .. name .. ": place '"
                .. tostring(item.place) .. "' is not a coarse area")
        end
    end
end

-- Exactly once for each name of want, never for the other fiches.
local function onlyFor(t, sc, fact, want, subject)
    for name in pairs(sc.fiches) do
        local list = facts(sc, name, fact)
        if want[name] then
            t:eq(1, #list, fact .. " of witness " .. name)
            if list[1] ~= nil and subject ~= nil then t:eq(subject, list[1].subject, fact .. " subject for " .. name) end
        else
            t:eq(0, #list, fact .. " of " .. name .. ", who could not witness it")
        end
    end
end

RST.suite("rs.observations", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 600000 }, function(s)
    s.test("assault_seen: only the named witnesses with a fiche, once (E08-T07)", function(t)
        scene(t, function(t2, sc)
            local before = count(sc.c.S.data.npcs)
            local H = sc.c.E.Hostility
            local opts = { witnessed = true, witnesses = { sc.ids.A, sc.ids.D }, x = sc.x, y = sc.y }
            t2:ok(H.record(sc.gid, sc.c.cid, "hit", opts) ~= nil, "assault not recorded by LK_Hostility")
            t2:ok(H.record(sc.gid, sc.c.cid, "hit", opts) ~= nil, "second assault not recorded")
            onlyFor(t2, sc, "assault_seen", { A = true }, sc.c.cid)
            checkCommon(t2, sc, before, "assault_seen")
        end)
    end)

    s.test("group_death: the members that see the death remember it once, nobody else (E08-T07)", function(t)
        scene(t, function(t2, sc)
            local E, B = sc.c.E, sc.c.E.Bodies
            local victim = B.find(sc.ids.D)
            t2:ok(victim ~= nil, "body of D not found")
            local range = sc.c.C.Observations.witnessRange
            local want, seen = {}, {}
            for _, name in ipairs({ "A", "B", "F" }) do
                local body = sc.ids[name] and B.find(sc.ids[name])
                if body ~= nil and math.floor(body:getZ()) == math.floor(victim:getZ()) then
                    local dx, dy = body:getX() - victim:getX(), body:getY() - victim:getY()
                    if dx * dx + dy * dy <= range * range and body:CanSee(victim) then
                        want[name] = true
                        seen[#seen + 1] = name
                    end
                end
            end
            t2:ok(want.A or want.B, "neither A nor B sees D at the kill (CanSee) although their squares were chosen "
                .. "with a line of sight: D at " .. math.floor(victim:getX()) .. "," .. math.floor(victim:getY()))
            t2:note("witnesses expected: " .. table.concat(seen, ", "))
            local before = count(sc.c.S.data.npcs)
            local vx, vy, vz = math.floor(victim:getX()), math.floor(victim:getY()), math.floor(victim:getZ())
            t2:defer(function() removeCorpses(E, sc.ids.D, vx, vy, vz) end, "remove the corpse of D")
            if E.Health ~= nil and E.Health.setBirth ~= nil then E.Health.setBirth(sc.ids.D, 0.01) end
            victim:Kill(nil)
            t2:waitUntil(function()
                local npc = E.Store.data().npcs[sc.ids.D]
                return npc ~= nil and npc.state == "dead"
            end, DEAD_MS, function(t3)
                t3:sleep(SETTLE_MS, function(t4)
                    onlyFor(t4, sc, "group_death", want, sc.gid .. "-" .. tostring(sc.mid.D))
                    checkCommon(t4, sc, before, "group_death")
                end)
            end, "D not dead after Kill")
        end, true)
    end)

    s.test("group_death off screen: members present at home remember it once (E08-T07)", function(t)
        scene(t, function(t2, sc)
            local before = count(sc.c.S.data.npcs)
            local G = sc.c.E.Groups
            t2:ok(G.markDead(sc.gid, sc.mid.M, G.today()), "member without body not marked dead")
            onlyFor(t2, sc, "group_death", { A = true, B = true, F = sc.fiches.F ~= nil }, sc.gid .. "-" .. sc.mid.M)
            checkCommon(t2, sc, before, "group_death")
            local home = sc.c.Obs.area(sc.x, sc.y)
            for _, item in ipairs(facts(sc, "A", "group_death")) do t2:eq(home, item.place, "place = area of the home") end
        end)
    end)

    s.test("player_return: a known character heard again after a day, once (E08-T07)", function(t)
        scene(t, function(t2, sc)
            local record = sc.c.S.data.characters[sc.c.cid]
            local hour = math.floor(getGameTime():getWorldAgeHours())
            local known = {}
            for _, name in ipairs({ "A", "F" }) do
                local f = sc.fiches[name]
                if f ~= nil then
                    record.contacts[f.id] = { history = {}, note = "", trust = "Unassessed", trend = "Stable",
                        stage = "stranger", exchanges = 0, nearHour = hour - sc.c.C.Observations.returnHours }
                    known[#known + 1] = f.id
                end
            end
            t2:defer(function()
                for _, id in ipairs(known) do record.contacts[id] = nil end
                sc.c.S.dirty = true
            end, "test contacts removed")
            local before = count(sc.c.S.data.npcs)
            t2:sleep(SETTLE_MS, function(t3)
                local farHears = false
                local bodyF = sc.fiches.F and sc.c.Server.objects[sc.fiches.F.id]
                if bodyF ~= nil then farHears = sc.c.P.hears(sc.c.p, bodyF, sc.c.C.HEARING_RANGE) == true end
                t3:note("far npc F hears the player: " .. tostring(farHears))
                onlyFor(t3, sc, "player_return", { A = true, F = farHears }, sc.c.cid)
                checkCommon(t3, sc, before, "player_return")
                t3:ok((record.contacts[sc.fiches.A.id].nearHour or 0) >= hour, "last hour heard of A not updated")
            end)
        end)
    end)

    s.test("mission_done: the requester remembers a success once per participant (E08-T07)", function(t)
        scene(t, function(t2, sc)
            local S, M = sc.c.S, sc.c.M
            local fiche = sc.fiches.A
            -- Template brought by the suite: the deliver offer of the catalogue with test supply terms (with Living
            -- Knox the engine supplies are the only deliver offers of an NPC fiche, RS_Missions Deliver.create).
            local entry = sc.c.C.Missions and sc.c.C.Missions.deliver
            local terms = { kind = "supply", unit = "value", need = "medical", level = 0, quantity = 1,
                durationMs = entry and entry.durationMs or 7200000, accepted = { ["Base.Bandage"] = true },
                values = { ["Base.Bandage"] = 1 }, rewardType = "", rewardCount = 0, noRefund = true,
                supplier = "rst-observations", supply = "rst-observations-offer" }
            if fiche.mission ~= nil and S.data.missions[fiche.mission] == nil then fiche.mission = nil end
            local m = M.create(S.data, fiche, sc.c.cid, entry and entry.id or nil, terms)
            t2:ok(m ~= nil, "test mission of A not created (deliver template with test supply terms)")
            t2:defer(function()
                S.data.missions[m.id] = nil
                if fiche.mission == m.id then fiche.mission = nil end
                fiche.nextOfferAt = nil
                S.dirty = true
            end, "test mission removed")
            t2:ok(M.accept(S.data, m, sc.c.cid, "RST"), "mission not accepted")
            local before = count(S.data.npcs)
            t2:ok(M.finish(S.data, m, "success"), "mission not finished")
            t2:eq(false, M.finish(S.data, m, "success"), "mission finished twice")
            onlyFor(t2, sc, "mission_done", { A = true }, sc.c.cid)
            checkCommon(t2, sc, before, "mission_done")
        end)
    end)
end)
