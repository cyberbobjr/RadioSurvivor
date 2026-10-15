--[[
lk.defense - coordinated home defense of Living Knox npcs (LK05-T09, server/LivingKnox/LK_Defense.lua, behaviour
"defend" of LK_Decisions.lua). Tags "world" and "server": the authority only, on a save named rstest*, with a target
player (t.ctx.player); the suite puts him inside a house by itself (RST.Places, solo; a house with a door or a window
within 10 squares), where the test group gets its home; the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.defense", tags = "world" }).
Asynchronous run only (about 2 to 5 minutes). Multiplayer: final session.

What is done (the player is protected by god mode and hidden from the perception of the test group):
    - a test group "settlers" (two fighters, one worker, and one more worker wounded to 45 % of its health: unfit,
      LK06-T07) is created with its home on the player's square (no
      furnishing: LivingKnox.Homes.skip); its members get bodies near the player; the home is surveyed (posts at
      the doors and windows, LK05-T03);
    - a small horde of HORDE ordinary zombies (3 to 5) is created out of the first post of the home, about HORDE_HOME
      squares from the home square (at least HORDE_MIN squares from the post; LK06-T14): the alert is raised, the
      defense starts (phase "hold": 3 to 5 zombies against three able members), each member runs to a post facing
      the horde (LK06-T07: every role fights; the worker too, at a post when the home has three posts, else in the
      shelter nearest to the horde), in guard;
    - LK06-T14: an able defender goes out to meet a zombie of the horde within the engage range of its post
      (LivingKnox.Defense.engageRange(npc): option ZombieEngage<Role> of its role, 10 by default) without waiting
      at the door for it, hits it, and comes back to its post (melee, or shots when a loaded firearm and a clear
      line of fire allow it); the suite measures the farthest engaged zombie from the defender's place ("sally"
      line: more than MELEE_ENGAGE squares expected) and checks that no defender leaves its place by more than its
      engage range + 2 squares once it got there (useless sortie) and that no defender stays on its way to the same
      place for more than STUCK_MS (no member stuck);
    - after HORDE_MS (or when every zombie is dead) the zombies left are removed: the defenders go back to their
      places ("back at places" line), the defense ends, an "after the attack" mark is written (wounded members, call
      point of the care of LK07-T03) and the members leave "defend".
Steady state (decision 6 of the user, 2026-10-14): once every defender reached its place, the suite waits (at most
STABLE_MS) until each one is at its post in guard or fighting before checking the gestures; no check is removed.
Second test, camp (LK05-T18, decision of the user, 2026-10-14): the same run with the home on an open square out of
any building (RST.Places outdoor, CAMP_OPEN free squares around it): the survey says "camp", the posts are the ring
of LivingKnox.Defense.campPosts (CAMP_RING squares around the home), the horde comes from out of the first one, the
wounded member is at the centre of the camp (CAMP_CENTER), and the same sortie, way back and end are checked.
Both tests (LK05-T18, MP passes of 2026-10-15: two camp members killed at every pass, the shooter 180 s in "shoot"
without a kill): no member of the group dies against the horde, and no shooter stays in "shoot" at the same target
without a shot for SHOOT_STALL_MS. Every SNAP_MS the fight is printed ("during the fight": members, horde, owners of
the bodies and zombies) and, on a dedicated server, each client prints what its copies do (RST.LKHelpers.probeZombies).
E01-T16 (LK05-T09): once the defenders are back at their places, every connected client sees each member within
POS_TOL squares of the authority's position (step lk.positions, RST_PeerChecksH.lua; solo: the local player).
Every phase prints "[LKD] measure ..." lines; the user checks the posts, the worker in guard, the defender who goes
out to hit a zombie a few squares away and its way back to its post. Cleanup (t:defer): perception restored, zombies
and bodies removed, test group removed, god mode restored.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksH"

require "RST/RST_Places"

local K = RST.LKHelpers
local measure = K.measurer("[LKD]")

local HORDE = 3             -- ordinary zombies of the horde (3 to 5: still a "hold" against three able members)
local HORDE_HOME = 8        -- squares from the home square to the horde (LK06-T14: inside DefenseRadius 8)
local HORDE_MIN = 3         -- squares from the first post to the horde at least (beyond MELEE_ENGAGE 2)
local BODIES_MS = 60000     -- materialization of the three members
local POSTS_MS = 30000      -- home survey (posts) done
local START_MS = 60000      -- defense started after the horde is created (alert: the horde must be seen)
local PLACES_MS = 60000     -- fighters at their posts
local HORDE_MS = 180000     -- the horde is fought this long at most, then removed
local END_MS = 240000       -- defense over after the horde is gone (game minutes: depends on the day length)
local STUCK_MS = 30000      -- a defender on its way to the same place longer than this is stuck
local WOUNDED = "m-4"       -- LK06-T07 / LK06-T14: wounded member (health 45 %, under WoundedHealth 50): never goes
                            -- out to fight; only defends itself from a zombie at contact (MELEE_ENGAGE of its body, or
                            -- inside COMBAT_LEASH of its place: LK_Defense point 4, "sans sortie"), the camp has no wall
local CONTACT_TOL = 1.0     -- squares: the zombie and the body move between the engagement and a sample
local CONTACT_TOL_MP = 2.5  -- dedicated server: the server copy of a zombie lags behind its owner (packets every 4 s at
                            -- most): MP pass of 2026-10-15, wounded member's hit at 1.38 squares counted "beyond contact"
local WOUND = 0.55          -- share of the full health taken from the wounded member (bleeding stopped)
local STABLE_MS = 30000     -- decision 6 (2026-10-14): each defender at its post in guard or fighting, at most this long
local CAMP_OPEN = 5         -- LK05-T18: squares around the camp home free of any building (ring of posts at 3)
local CAMP_SEARCH = 30      -- squares around the player searched for such a camp square (MP: the player is not moved)

local SHOOT_STALL_MS = 20000 -- a shooter in "shoot" at the same target without a shot this long is stalled
local SNAP_MS = 10000       -- "[LKD] measure during the fight" every this long (positions, horde, owners)
local POS_SETTLE_MS = 2000  -- members at their places: copies of the clients caught up before lk.positions
local POS_TOL = 2.5         -- squares: member positions seen by every client at the end (LK05-T09, E01-T16)

local function LK() return LivingKnox end
local function Dec() return LivingKnox.Decisions end
local function Df() return LivingKnox.Defense end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function sortedMids(gid)
    local out = {}
    for mid in pairs(memberNpcs(gid)) do out[#out + 1] = mid end
    table.sort(out)
    return out
end

local function bodyCount(gid)
    local n = 0
    for _, npc in pairs(memberNpcs(gid)) do
        if LK().Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

local function allStanding(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        if not K.standing(npc)() then return false end
    end
    return true
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function describe(gid)
    local parts = {}
    local npcs = memberNpcs(gid)
    local plan = Df().get(gid)
    for _, mid in ipairs(sortedMids(gid)) do
        local npc = npcs[mid]
        local st = Dec().get(npc)
        local body = LK().Bodies.find(npc)
        local a = plan and plan.assign[mid] or nil
        local o = LK().Combat and LK().Combat.get(npc) or nil
        local owner = body ~= nil and isServer() and body:getOwnerPlayer() or nil
        parts[#parts + 1] = string.format("%s %s at %s place %s gesture %s combat %s%s", mid, st and st.b or "none",
            body and string.format("%.1f,%.1f", body:getX(), body:getY()) or "?", a and a.key or "-",
            LK().Anim.gestureOf(npc), o and tostring(o.u) or "-",
            owner ~= nil and (" owner " .. tostring(owner:getUsername())) or "")
    end
    return table.concat(parts, "; ")
end

-- Horde on the authority: key, position, owner (MP), dead or gone.
local function hordeOf(horde)
    local parts = {}
    for _, z in ipairs(horde) do
        local state = z:isDead() and "dead" or (getCell():getZombieList():contains(z) and "alive" or "gone")
        local owner = isServer() and z:getOwnerPlayer() or nil
        parts[#parts + 1] = string.format("%s %s at %.1f,%.1f owner %s", LK().Zombies.keyOf(z), state, z:getX(),
            z:getY(), owner ~= nil and tostring(owner:getUsername()) or "-")
    end
    return table.concat(parts, "; ")
end

-- Place of each defender reached (at most ARRIVE + 0.5 squares) and its state "defend"; engaged: a defender in a
-- fight (LK06-T14: gone out to meet a zombie) counts as placed.
local function atPlaces(gid, engaged)
    local plan = Df().get(gid)
    if plan == nil then return false end
    local npcs = memberNpcs(gid)
    for mid, a in pairs(plan.assign) do
        local npc = npcs[mid]
        local body = npc and LK().Bodies.find(npc) or nil
        local st = npc and Dec().get(npc) or nil
        if mid ~= WOUNDED then   -- the wounded member is followed apart (never fights)
            if body == nil or st == nil or st.b ~= "defend" then return false end
            local dx, dy = body:getX() - (a.x + 0.5), body:getY() - (a.y + 0.5)
            local fighting = engaged and LK().Combat ~= nil and LK().Combat.get(npc) ~= nil
            if not fighting and math.sqrt(dx * dx + dy * dy) > LK().Directives.ARRIVE + 0.5 then return false end
        end
    end
    return true
end

-- Square to stand on inside the player's house (ground floor), or nil.
local function houseSpot(p)
    local sq = p:getCurrentSquare()
    if not RST.Places.inside(sq) then return nil end
    return RST.Places.freeNear(sq, 3)
end

-- LK05-T18: open square for a camp (no building within CAMP_OPEN squares: ring of posts and room around it), or nil.
-- The player's square first, then the nearest one within CAMP_SEARCH squares of him (rings, nearest first): a server
-- cannot move a client (RST.Places moves the player in solo only), and the MP spawn point is inside a house (campaign
-- of 2026-10-15: SKIP). The camp stays well inside the area the clients load and simulate around the player.
-- No wall, fence or hedge edge between two squares of the open area either (MP pass of 2026-10-15: a camp spot
-- next to a garden fence, members routed over it).
local function edgesOpen(sq, r)
    local cell = getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for dy = -r, r do
        for dx = -r, r do
            local a = cell:getGridSquare(x + dx, y + dy, z)
            for _, u in ipairs({ { 1, 0 }, { 0, 1 } }) do
                if dx + u[1] <= r and dy + u[2] <= r then
                    local b = cell:getGridSquare(x + dx + u[1], y + dy + u[2], z)
                    if a == nil or b == nil or a:isBlockedTo(b) then return false end   -- walls and low fences too
                end
            end
        end
    end
    return true
end
local function campOpen(sq) return RST.Places.openAround(sq, CAMP_OPEN) and edgesOpen(sq, CAMP_OPEN) end

local function campSpot(p)
    local sq = p:getCurrentSquare()
    if sq == nil then return nil end
    if campOpen(sq) then return sq end
    local cell = getCell()
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    for r = 1, CAMP_SEARCH do
        for dy = -r, r do
            local step = (dy == -r or dy == r) and 1 or 2 * r   -- ring r only: its two rows, then its two sides
            for dx = -r, r, step do
                local q = cell:getGridSquare(px + dx, py + dy, pz)
                if q ~= nil and q:isFree(false) and q:getRoom() == nil and q:getBuildingDef() == nil
                    and campOpen(q) then
                    return q
                end
            end
        end
    end
    return nil
end

-- Every defender (the wounded member apart) settled: fighting (LK06-T14: gone out to meet a zombie), or at its place
-- (ARRIVE + 0.5 squares) in guard. Decision 6 of the user (2026-10-14): checked before the gesture checks, so that a
-- member still running to its post is not taken for a fault.
local function settled(gid)
    local plan = Df().get(gid)
    if plan == nil then return false end
    local npcs = memberNpcs(gid)
    for mid, a in pairs(plan.assign) do
        local npc = npcs[mid]
        if mid ~= WOUNDED then
            local body = npc and LK().Bodies.find(npc) or nil
            local st = npc and Dec().get(npc) or nil
            if body == nil or st == nil or st.b ~= "defend" then return false end
            if LK().Combat == nil or LK().Combat.get(npc) == nil then
                local dx, dy = body:getX() - (a.x + 0.5), body:getY() - (a.y + 0.5)
                if math.sqrt(dx * dx + dy * dy) > LK().Directives.ARRIVE + 0.5 then return false end
                if LK().Anim.gestureOf(npc) ~= "guard" then return false end
            end
        end
    end
    return true
end

-- One defense run (t, the player on square sq). camp: LK05-T18, the home is an open square out of any building.
local function scenario(t, sq, camp)
        local E = LK()
        local p = RST.Fixtures.player(t)
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST defense", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "fighter", "guard" },
            { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        -- The target player is hidden from the members of the test group: only the horde is a threat here.
        local perceived = E.Senses.perceived
        E.Senses.perceived = function(id)
            local per = perceived(id)
            if per == nil or G.findNpc(id) ~= gid then return per end
            per.p = {}
            return per
        end
        local removers, horde = {}, {}
        t:defer(function()
            for _, remove in ipairs(removers) do remove() end
            E.Senses.perceived = perceived
            p:setGodMod(wasGod)
            E.Alert.forget(gid)
            E.Defense.forgetGroup(gid)
            local npcs = memberNpcs(gid)
            for _, npc in pairs(npcs) do
                if E.Combat then E.Combat.disengage(npc, "suite lk.defense over") end
            end
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        local posts
        t:waitUntil(function()
            return bodyCount(gid) == 4 and allStanding(gid)
        end, BODIES_MS, function(t2)
            local wnpc = memberNpcs(gid)[WOUNDED]
            local wz = E.Bodies.find(wnpc)
            local full = E.Health.get(wnpc).max
            local whp = E.Health.applyHit(wnpc, wz, full * WOUND, "Torso_Upper", nil, nil)
            E.Health.stopBleeding(wnpc, "suite lk.defense: steady wounded member")
            measure(string.format("wounded member %s %s: health %.3f of %.3f (ratio %.2f, wounded under %.2f)", WOUNDED,
                wnpc, whp or -1, full, (whp or 0) / full, Dec().woundRatio()))
            t2:ok(whp ~= nil and whp / full < Dec().woundRatio(), "wounded member not under the wounded threshold")
            measure("members before: " .. describe(gid))
            t2:waitUntil(function()
                local live = G.state.data.groups[gid]
                posts = live and E.Routines.ensurePosts(gid, live) or nil
                return posts ~= nil
            end, POSTS_MS, function(t3)
                if camp then
                    -- LK05-T18: the survey of an open home says "camp"; the defense puts its posts in a ring around it.
                    t3:ok(posts.camp == true, "open home not surveyed as a camp")
                    posts = Df().campPosts(home)
                    measure(string.format("camp: %d post(s) in a ring of %d squares", #posts.posts, Df().CFG.CAMP_RING))
                    if #posts.posts == 0 then t3:skip("no walkable square around the camp: no post") end
                elseif posts.camp or #posts.posts == 0 then
                    t3:skip("no door or window next to the home: no post")
                end
                local first = posts.posts[1]
                local rad = first.a * math.pi / 180
                local ox, oy = math.floor(math.cos(rad) + 0.5), math.floor(math.sin(rad) + 0.5)
                local anchor = getCell():getGridSquare(first.x, first.y, first.z)
                local out = math.max(HORDE_MIN, HORDE_HOME - cheb(first.x, first.y, home.x, home.y))
                for i = 1, HORDE do
                    local side = i - math.floor((HORDE + 1) / 2)
                    local z, remove = K.spawnVanilla(t3, anchor, ox * out + oy * side, oy * out + ox * side)
                    removers[#removers + 1] = remove
                    horde[#horde + 1] = z
                    measure(string.format("zombie %d created at %.1f,%.1f,%d", i, z:getX(), z:getY(),
                        math.floor(z:getZ())))
                end
                measure(string.format("horde of %d %d squares out of post %d,%d,%d (%s, facing %d), engage range %d",
                    HORDE, out, first.x, first.y, first.z, first.k, first.a, Df().engageRange()))
                t3:waitUntil(function() return Df().get(gid) ~= nil end, START_MS, function(t4)
                    local plan = Df().get(gid)
                    measure(string.format("defense started: %s %s (%s), %d zombie(s), threat from %s,%s%s", plan.id,
                        plan.phase, tostring(plan.why), plan.zombies, tostring(plan.tx), tostring(plan.ty),
                        plan.camp and ", camp" or ""))
                    t4:eq("hold", plan.phase, "phase against a small horde")
                    t4:eq(camp == true, plan.camp == true, "defense of a camp")
                    local roles = {}
                    for _, mid in ipairs(sortedMids(gid)) do
                        roles[#roles + 1] = mid .. " " .. tostring(plan.assign[mid] and plan.assign[mid].key)
                    end
                    measure("places: " .. table.concat(roles, "; "))
                    t4:eq("post", plan.assign["m-1"] and plan.assign["m-1"].role, "fighter m-1 at a post")
                    t4:ok(plan.assign[WOUNDED] == nil or plan.assign[WOUNDED].role ~= "post",
                        "wounded member " .. WOUNDED .. " sent to a post")
                    local wplace = plan.assign[WOUNDED]   -- LK05-T18: non-combatants gathered at the centre of the camp
                    if camp and wplace ~= nil then
                        t4:ok(cheb(wplace.x, wplace.y, home.x, home.y) <= Df().CFG.CAMP_CENTER,
                            "wounded member " .. WOUNDED .. " not at the centre of the camp: " .. tostring(wplace.key))
                    end
                    -- LK06-T07: the able worker fights too: a post when the home has three posts.
                    t4:eq(#posts.posts >= 3 and "post" or "shelter", plan.assign["m-2"] and plan.assign["m-2"].role,
                        "worker m-2 place (" .. #posts.posts .. " post(s))")
                    -- Sorties seen while the defenders go to their places (MP pass of 2026-10-15 10:52: m-2 went
                    -- out and killed the three zombies before the steady state; the sampling began after the fight
                    -- and found no sortie): the farthest engaged zombie is measured from the start of the defense.
                    local early = { sally = 0, who = "-" }
                    local function sampleSally()
                        local cur = Df().get(gid)
                        if cur == nil then return end
                        local npcs = memberNpcs(gid)
                        for mid, npc in pairs(npcs) do
                            local a = mid ~= WOUNDED and cur.assign[mid] or nil
                            local o = a ~= nil and E.Combat.get(npc) or nil
                            if o ~= nil and o.k == "zombie" then
                                for _, z in ipairs(horde) do
                                    if E.Zombies.keyOf(z) == o.u then
                                        local zd = cheb(z:getX(), z:getY(), a.x + 0.5, a.y + 0.5)
                                        if zd > early.sally then
                                            early.sally, early.who = zd, mid .. " " .. o.u
                                            measure(string.format("sally (before the steady state) %s engages %s "
                                                .. "%.1f squares from %s", mid, o.u, zd, a.key))
                                        end
                                    end
                                end
                            end
                        end
                    end
                    -- A defense already over (horde killed within seconds, MP pass of 2026-10-15) ends the wait too.
                    t4:waitUntil(function()
                        sampleSally()
                        return Df().get(gid) == nil or atPlaces(gid, true)
                    end, PLACES_MS,
                        function(t4b)
                    -- Decision 6 (2026-10-14): wait for a steady state (each defender at its post in guard, or
                    -- fighting), at most STABLE_MS, before the checks; a member still running is not a fault.
                    local settleFrom = getTimestampMs()
                    t4b:waitUntil(function()
                        sampleSally()
                        return Df().get(gid) == nil or settled(gid)
                    end, STABLE_MS, function(t5)
                        measure(string.format("at places: %s (steady after %d ms)", describe(gid),
                            getTimestampMs() - settleFrom))
                        local worker = memberNpcs(gid)["m-2"]   -- LK06-T14: in guard, or gone out to fight
                        t5:ok(Df().get(gid) == nil or E.Anim.gestureOf(worker) == "guard"
                            or E.Combat.get(worker) ~= nil,
                            "able worker neither in guard nor fighting: " .. tostring(E.Anim.gestureOf(worker)))
                        local started = getTimestampMs()
                        local sorties, stuck, maxOut, engaged = 0, 0, 0, 0
                        local sally, sallyWho = early.sally, early.who   -- LK06-T14: farthest engaged zombie
                        local live = 0   -- samples taken while the defense was still on
                        local track = {}   -- npc -> { key (place), since, reached, told }
                        -- wounded member: fights beyond contact (sortie), fights at contact (self-defense),
                        -- farthest from the home square, farthest from its place
                        local wEngaged, wContact, wFar, wOut = 0, 0, 0, 0
                        -- The wounded member's way to its place is not "leaving" it (MP campaign of 2026-10-15: the
                        -- way to the shelter went out by a side door, 5 squares off): wOut counts once it got there.
                        local wKey, wReached, wWay = nil, false, 0
                        local lastSnap = getTimestampMs()
                        -- LK05-T18 (MP pass of 2026-10-15): a shooter in "shoot" against the same zombie without a
                        -- single shot for SHOOT_STALL_MS (no report from the machine of its body) is stalled.
                        local shooting, stalled = {}, 0
                        local contactTol = (isServer() and not (RST.Steps.isSolo and RST.Steps.isSolo()))
                            and CONTACT_TOL_MP or CONTACT_TOL
                        t5:waitUntil(function()
                            local cur = Df().get(gid)
                            local npcs = memberNpcs(gid)
                            local alive = 0
                            for _, z in ipairs(horde) do
                                if not z:isDead() and getCell():getZombieList():contains(z) then alive = alive + 1 end
                            end
                            local wn = npcs[WOUNDED]
                            local wb = wn and E.Bodies.find(wn) or nil
                            if wb ~= nil then
                                local wo = E.Combat.get(wn)
                                local wa = cur and cur.assign[WOUNDED] or nil
                                if wo ~= nil then
                                    -- LK_Defense point 4: a member without sortie strikes only a threat at
                                    -- MELEE_ENGAGE of its body, kept by the leash COMBAT_LEASH around its place.
                                    local contact = false
                                    for _, z in ipairs(horde) do
                                        if wo.k == "zombie" and E.Zombies.keyOf(z) == wo.u then
                                            local dx, dy = z:getX() - wb:getX(), z:getY() - wb:getY()
                                            contact = math.sqrt(dx * dx + dy * dy)
                                                    <= E.Defense.CFG.MELEE_ENGAGE + contactTol
                                                or (wa ~= nil and cheb(math.floor(z:getX()), math.floor(z:getY()),
                                                    wa.x, wa.y) <= E.Defense.CFG.COMBAT_LEASH)
                                        end
                                    end
                                    if contact then wContact = wContact + 1 else wEngaged = wEngaged + 1 end
                                end
                                wFar = math.max(wFar, cheb(wb:getX(), wb:getY(), home.x + 0.5, home.y + 0.5))
                                if wa ~= nil then
                                    if wa.key ~= wKey then wKey, wReached = wa.key, false end
                                    local wd = cheb(wb:getX(), wb:getY(), wa.x + 0.5, wa.y + 0.5)
                                    if wd <= E.Directives.ARRIVE + 0.5 then wReached = true end
                                    if wReached then wOut = math.max(wOut, wd) else wWay = math.max(wWay, wd) end
                                end
                            end
                            for mid, npc in pairs(npcs) do
                                local a = mid ~= WOUNDED and cur and cur.assign[mid] or nil
                                local body = E.Bodies.find(npc)
                                local st = Dec().get(npc)
                                if a ~= nil and body ~= nil and st ~= nil and st.b == "defend" then
                                    local d = cheb(body:getX(), body:getY(), a.x + 0.5, a.y + 0.5)
                                    local now = getTimestampMs()
                                    local w = track[npc]
                                    if w == nil or w.key ~= a.key then   -- new place: on its way
                                        w = { key = a.key, since = now, reached = false }
                                        track[npc] = w
                                    end
                                    local o = E.Combat.get(npc)
                                    local sw = shooting[npc]
                                    if o ~= nil and o.m == "ranged" and o.phase == "shoot" then
                                        local tnow = getTimestampMs()
                                        if sw == nil or sw.c ~= o.c or sw.u ~= o.u or sw.shots ~= o.shots then
                                            shooting[npc] = { c = o.c, u = o.u, shots = o.shots, since = tnow }
                                        elseif not sw.told and tnow - sw.since > SHOOT_STALL_MS then
                                            sw.told = true
                                            stalled = stalled + 1
                                            measure(string.format("stalled shooter? %s at %s for %d ms, %d shot(s)",
                                                mid, tostring(o.u), tnow - sw.since, o.shots or 0))
                                        end
                                    else
                                        shooting[npc] = nil
                                    end
                                    -- A defender in a fight is not "on its way" (MP pass of 2026-10-15 10:18: a
                                    -- member fighting at the door for 30 s counted as stuck): its clock restarts.
                                    if o ~= nil and not w.reached then w.since = now end
                                    if o ~= nil then
                                        engaged = engaged + 1
                                        for _, z in ipairs(horde) do
                                            if o.k == "zombie" and E.Zombies.keyOf(z) == o.u then
                                                local zd = cheb(z:getX(), z:getY(), a.x + 0.5, a.y + 0.5)
                                                if zd > sally then
                                                    sally, sallyWho = zd, mid .. " " .. o.u
                                                    measure(string.format("sally %s engages %s %.1f squares from %s, "
                                                        .. "body %.1f squares from it", mid, o.u, zd, a.key, d))
                                                end
                                            end
                                        end
                                    end
                                    if d <= E.Directives.ARRIVE + 0.5 then
                                        w.reached, w.since, w.told = true, now, false
                                    elseif w.reached and d > Df().engageRange(npc) + 2 then
                                        sorties = sorties + 1
                                        measure(string.format("sortie? %s %.1f squares from %s", mid, d, a.key))
                                        w.reached, w.since = false, now
                                    elseif not w.reached and now - w.since > STUCK_MS and not w.told then
                                        w.told = true
                                        stuck = stuck + 1
                                        measure(string.format("stuck? %s on its way to %s for %d ms", mid, a.key,
                                            now - w.since))
                                    end
                                    if w.reached and d > maxOut then maxOut = d end
                                end
                            end
                            if cur == nil then return true end
                            live = live + 1
                            if getTimestampMs() - lastSnap >= SNAP_MS then
                                lastSnap = getTimestampMs()
                                measure("during the fight: " .. describe(gid) .. "; horde " .. hordeOf(horde))
                                local ids = {}
                                for _, z in ipairs(horde) do ids[#ids + 1] = z:getOnlineID() end
                                for _, mid in ipairs(sortedMids(gid)) do
                                    local b = E.Bodies.find(memberNpcs(gid)[mid])
                                    if b ~= nil then ids[#ids + 1] = b:getOnlineID() end
                                end
                                K.probeZombies(ids, "defense " .. gid)
                            end
                            return alive == 0 or getTimestampMs() - started >= HORDE_MS
                        end, HORDE_MS + 30000, function(t6)
                            measure(string.format("fight: %s; engaged samples %d, farthest from a place %.1f, sorties "
                                .. "%d, stuck %d, sally %.1f (%s)", describe(gid), engaged, maxOut, sorties, stuck,
                                sally, sallyWho))
                            for _, remove in ipairs(removers) do remove() end
                            measure("zombies left removed")
                            local wst = Dec().get(wnpc)
                            local wa = plan.assign[WOUNDED]
                            measure(string.format("wounded member %s: place %s, behaviour %s, fights beyond contact %d, "
                                .. "at contact %d, farthest from the home square %.1f, from its place %.1f once there "
                                .. "(reached %s, farthest on its way %.1f)", WOUNDED, tostring(wa and wa.key),
                                tostring(wst and wst.b), wEngaged, wContact, wFar, wOut, tostring(wReached), wWay))
                            t6:eq(0, wEngaged, "wounded member engaged a zombie beyond contact (went out to fight)")
                            t6:ok(wOut <= E.Defense.CFG.COMBAT_LEASH + E.Defense.CFG.MELEE_ENGAGE + 0.5,
                                string.format("wounded member left its place (%.1f squares)", wOut))
                            t6:eq(0, sorties, "defenders beyond the engage range of their place (useless sortie)")
                            t6:eq(0, stuck, "defenders stuck on their way")
                            -- LK05-T18 (MP pass of 2026-10-15, camp: two members killed at every pass, the shooter
                            -- 180 s in "shoot" without a kill): nobody dies against 3 zombies, no stalled shooter.
                            local dead = {}
                            local gl = G.get(gid)
                            for mid, m in pairs(gl and gl.members or {}) do
                                if m.alive == false then dead[#dead + 1] = mid end
                            end
                            table.sort(dead)
                            t6:eq(0, #dead, "members killed by the horde (" .. table.concat(dead, " ") .. ")")
                            t6:eq(0, stalled, "shooters in \"shoot\" without a shot for " .. SHOOT_STALL_MS .. " ms")
                            -- The horde may be killed before any sample (MP pass of 2026-10-15 10:02: defense over
                            -- within seconds, from the door): the sortie is then not measurable here.
                            if live == 0 and sally == 0 then
                                t6:note("defense over before the fight could be sampled: sortie not measured")
                            else
                                t6:ok(sally > E.Defense.CFG.MELEE_ENGAGE, string.format("no defender went out to meet "
                                    .. "a zombie (farthest engaged zombie %.1f squares from its place)", sally))
                            end
                            t6:waitUntil(function() return Df().get(gid) == nil or atPlaces(gid) end, PLACES_MS,
                                function(t6b)
                                measure("back at places: " .. describe(gid))
                                -- LK05-T09 (E01-T16): every connected client sees the members at the same places
                                -- as the authority (lk.positions, RST_PeerChecksH.lua; solo: the local player).
                                -- Bodies still settling at their places (MP pass of 2026-10-15 12:01: lk-2 seen 2.6
                                -- squares from the authority's position by the second client, at the arrival):
                                -- POS_SETTLE_MS first, so the copies of every client catch up.
                                t6b:sleep(POS_SETTLE_MS, function(t6s)
                                local list = {}
                                for _, mid in ipairs(sortedMids(gid)) do list[#list + 1] = memberNpcs(gid)[mid] end
                                RST.Steps.ask(t6s, "lk.positions", { bodies = RST.PeerChecksH.bodiesOf(list),
                                    tol = POS_TOL }, { target = "all", timeoutMs = 15000 }, function(t6c)
                                    t6c:waitUntil(function()
                                        if Df().get(gid) ~= nil then return false end
                                        for _, npc in pairs(memberNpcs(gid)) do
                                            local st = Dec().get(npc)
                                            if st ~= nil and st.b == "defend" then return false end
                                        end
                                        return true
                                    end, END_MS, function(t7)
                                        local mark = Df().after(gid)
                                        measure(string.format("defense over: mark %s after %s min, wounded %s; members %s",
                                            mark and mark.id or "none", mark and tostring(mark.minutes) or "?",
                                            mark and (#mark.wounded > 0 and table.concat(mark.wounded, " ") or "none") or "?",
                                            describe(gid)))
                                        t7:ok(mark ~= nil, "no after-the-attack mark")
                                    end, "defense not over after the horde")
                                end)
                                end)
                            end, "defenders not back at their places")
                        end, "fight not over")
                    end, "defenders not steady (each at its post in guard, or fighting)")
                    end, "defenders did not reach their places")
                end, "defense not started by the horde")
            end, "home not surveyed")
        end, "group members not materialized and standing")
end

local function start(t)
    local E = LK()
    t:ok(E ~= nil and E.Defense ~= nil and E.Decisions ~= nil and E.Alert ~= nil,
        "LivingKnox.Defense is not loaded on this side")
    t:ok(E.Groups.ensure(), "group registry not ready")
    t:ok(RST.Fixtures.player(t) ~= nil, "no target player (t.ctx.player)")
end

RST.suite("lk.defense", { tags = { "world", "server" }, testTimeoutMs = 720000, timeoutMs = 900000 }, function(s)
    s.test("small horde near the home: posts manned, fight from the posts, no sortie, nobody stuck, defense over",
        function(t)
        start(t)
        -- The suite puts the player inside a house by itself (RST.Places, solo).
        RST.Places.ensure(t, { name = "house (ground floor)", spot = houseSpot,
            building = function(def) return def:isResidential() end }, function(t2, sq)
            scenario(t2, sq, false)
        end)
    end)
    -- LK05-T18 (decision of the user, 2026-10-14): a group camping in the open fights on the spot.
    s.test("camp attacked by a small horde: ring of posts, wounded at the centre, sortie and back, defense over",
        function(t)
        start(t)
        if not (LK() and LK().Defense and LK().Defense.CFG.CAMP) then t:skip("camp defense switched off") end
        -- The suite puts the player on an open square out of any building (RST.Places, solo).
        RST.Places.ensure(t, { name = "open ground for a camp", spot = campSpot, outdoor = true }, function(t2, sq)
            scenario(t2, sq, true)
        end)
    end)
end)
