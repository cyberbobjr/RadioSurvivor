--[[
lk.traversal - Living Knox bodies crossing windows, low fences and stairs (LK04-T03, LK04-T07), exterior doors of a
home closed on arrival (LK04-T10), locked home doors opened only with the key (LK04-T12). Tags "world" and
"server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Stand near a house with windows (ground floor), an exterior door, a low fence and stairs, all in the loaded area (the
sites are
searched within SEARCH squares of the player; a test whose site is missing is SKIP with the reason).
Solo: RST.run({ suite = "lk.traversal", tags = "world" }); dedicated server: RST.server({ suite = "lk.traversal",
tags = "world" }) from an admin client standing still (the body is then simulated by a client: crossing states and
durations are only measured in solo). Asynchronous run only (about 7 minutes; do not pause the game).

Checked here, for each site, with a fresh npc body standing on the start square of the lane or the next one (any
point of the square, its corner included), two squares before the obstacle, and a "move" to the
square two squares past it. A site is a straight lane of six walkable squares joined by open edges except the
obstacle, its start square accepted by LivingKnox.Bodies.freeSquare (LK04-T08: a start behind a wall sent the body
around, through another window); the body must go through the obstacle itself (crossing of the edge measured), or
never cross it for the locked window. Low gates (closed hoppable doors) are not fence sites.
    - open window: the body climbs through (action state "climbwindow" seen in solo) and arrives, no window toggle;
    - broken window (set with setSmashed, restored afterwards): same;
    - low fence (hoppable edge, no window frame, no stairs next to it): the body climbs over it ("climbfence");
    - refused door next to a low fence (LK04-T14): a low fence site with a closed door that a npc would not pass
      (double, locked, barricaded, home of a group: LivingKnox.Detour.doorRefusal; LK04-T17: garage doors are
      opened, all their panels) within one square of
      its lane; the game path may take the fence or the door; a refusal at the door gives a detour (LK17-T01,
      LivingKnox.Detour: the low fence or another gate): the move arrives, the body never crosses that door, the
      door is left as it was and every refusal counted gave a detour. Decor (solo campaign of 2026-10-15): when no door next to a
      low fence is refused, a fence with a single door within one square of its lane is taken and the test closes that
      door and nails one plank on it (refused: "barricaded door"; plank removed and door restored afterwards), places
      tried 2 PLACE_TRIES. No such site: SKIP;
    - stairs: "move" up to a free floor square next to the top of the stairs, then back down; both arrive; the bottom
      square is joined to the stairs by open edges (no wall, door, window or fence between: stairsEnds);
    - closed window, npc member of a settlers group (created for the test): the authority opens the window once,
      the body climbs through, then the authority closes it behind the body within CLOSE_MS of the arrival: exactly
      two toggles (LivingKnox.Obstacles.stats.windowToggles + 2, windowsClosed + 1), never broken; LK04-T18: closed by
      this npc with its gesture, the body stopped next to the window, facing it, at most ACT_REACH (1.5) squares from
      the middle of its edge at the toggle (LivingKnox.Obstacles.lastClose, distance printed);
    - closed window, npc member of a raiders group: same (any npc may open a closed window, LK04-T07);
    - locked window, settlers member: the move is refused (directive failed, reason "locked window"), the window
      stays closed, locked and unbroken (LivingKnox.Obstacles.stats.windowsRefused + 1; reason in the log);
    - locked window, detour through a door (LK17-T01): a window site (no door next to its lane) for which
      LivingKnox.Detour.plan, probed from the lane start, gives a door of the house (findDetourSite); the test closes
      and locks the window (restored afterwards), the npc (settlers member) walks the lane: the game path takes the
      window, the authority refuses it at contact ("locked window") and gives the same move a detour through a door
      (LivingKnox.Detour.stats.detours + 1, waypoints): the body arrives, never through the window ("climbwindow"
      never seen in solo; crossing of the window edge by position checked on a server only), through a door, and
      the window is left closed and locked. No such site: SKIP.
    - open exterior door of a home (LK04-T10): the nearest free single exterior door of a building that is no group's
      home is opened, a npc is spawned two squares inside, then a settlers group is created with its home in that
      building and the npc as member (LK04-T12: locking needs a member with the key at home; a new loaded home is an
      arrival): the authority closes and locks that door within SHUT_DELAY_MS + 10 s (LivingKnox.Obstacles.stats.shut
      + 1, or more when other exterior doors of the house were open: they are closed by the same arrival); reopened
      by the test as a player would, it stays open and unlocked for SHUT_DELAY_MS + 2 SHUT_RETRY_MS (one closing per
      arrival, no fight with the player). States of every exterior door of the house restored and group removed
      afterwards. No such door: SKIP.
    - locked home door, with the key (LK04-T12): the nearest single exterior door of a building that is no group's
      home, with a free lane through it; a npc spawned on the lane start becomes the member of a settlers group whose
      home is that building (he gets the key of the building: exactly one key on the body), the door is closed and
      locked, then the npc walks through it: the authority opens it (stats.opened + 1), the body goes through the door
      and arrives, the door is closed and locked again behind him within CLOSE_MS, still one key on the body;
    - locked home door, without the key: same, the key removed from the body first, lane starting OUTSIDE the
      building: the move is refused (directive failed, reason "locked door (no key)" on the door edge), the door
      stays closed and locked, no key given back;
    - locked home door, opened from inside without the key (LK04-T17): same, lane starting INSIDE the building: the
      authority opens the door as a player would from inside (IsoDoor canBeOpenFromInside), the body arrives, the
      door is closed behind it and left unlocked.
    - locked interior home door, relocked with the home key (LK04-T19): the nearest single door with both sides in
      the same building (no group's home), no key of its own (keyId -1: IsoDoor checkKeyId) and a free lane; a
      settlers group gets its home in that building and the npc as member (key of the building on the body); the door
      is closed and locked, the npc walks through it: opened from inside without its key, the body arrives, the door
      is closed AND locked behind it within CLOSE_MS (stats.locked + 1), still one key on the body;
    - locked interior home door, no home key: same, the key removed from the body first: the door is opened from
      inside, closed behind the body and left unlocked.
    - npc trapped in the home of another group (LK04-T20): a free single exterior door of a building without a home
      and without a broken window or bare frame, lane from inside; a npc of no group spawned on the lane start, then
      a settlers group (no member) gets its home in that building; every exterior door of the house is closed and
      locked, every exterior window closed (restored afterwards): by the usual rules no door or window lets the npc
      out. Refused at the door (home of another group), the authority gives the last resort (LivingKnox.Detour, LK04-T20:
      the door opened from inside, or a locked window): the move carries the last resort mark (Directives entry lr),
      the body leaves the house and arrives two squares out.
The window and fence tests above check the crossing itself: they leave out a site with any door within one square of
its lane (LK04-T14: the native path to a low fence took the closed garage door next to it, at about the same length).
They also leave out a site whose lane passes within Bodies.HAZARD_AVOID of a farming plant or a campfire: the
move would be split around it (Directives.planDetour) and pass beside the obstacle (solo campaign 2026-10-15).
The locked window test and the key test without the key check the refusal itself: they switch the detour after a
refusal off (hook LivingKnox.Obstacles.onRefusal, restored by t:defer).
Blocking is detected as the longest stretch with the body still (less than STILL squares in STILL_MS) outside a
crossing: measured, and FAIL when it reaches BLOCKED_MS. Figures are printed as "[LKT] measure ..." lines: trip time,
crossing time (LivingKnox.Executor.stats.crossMs, solo), longest still stretch, retries. Human climb (LK04-T11,
not on a server): once a crossing state was seen, the body must never be on the floor (isOnFloor, isKnockedDown,
ClimbWindowFlopped, ClimbFenceFlopped) until the end of the trip; FAIL otherwise. Low fences are edges that the
engine sees as such (LivingKnox.Edges.fenceTo: square flag HoppableW/N, not only a hoppable object over a
wall). The npc of a test that joins a group is left out of the decisions of that group (LivingKnox.Decisions,
isolate), and a move replaced by another directive before its end was read is a FAIL that says so. Every test removes its npc
(and its directive), restores the window state and removes its group with t:defer.
E01-T16 (LK04-T03, two observers): on a dedicated server the open window, broken window and low fence trips are
followed by every client on its own copy (RST.Steps "lk.track"): crossing through the obstacle edge seen, copy at the
target at the end.
Decor (decision of 2026-10-15, nothing cut): every site is first looked for around the player; when it is missing
there, the players are moved to the nearest buildings of the metagrid (RST.Places.ensure, solo and dedicated server,
PLACE_TRIES places within PLACE_RADIUS squares, inside the largest ground floor room, or around the building for the
low fences) and the site is looked for again at each place; the first place where it is found is used, the players go
back afterwards. From the same start place the same places are tried in the same order: same decor at each run. SKIP
only when none of the places has the site (reason with the number of places tried).
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_Places"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksLK2"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local ARRIVE_MS = 60000
local SEARCH = 25            -- squares around the player searched for a site
local STILL = 0.1            -- squares
local BLOCKED_MS = 30000     -- body still this long outside a crossing: blocked (LK04-T05 limit)
local CROSSING = { climbwindow = true, climbfence = true }
local CLOSE_MS = 10000       -- window closed behind the body within this time after its arrival
-- Level of the body read on the authority after an arrival reported by the executor. On a dedicated server the copy
-- of a client-simulated body only follows the owner's zombie packets (every 4 s, sooner on a state change): campaign
-- 2026-10-15, "stairs up" arrived at the client in 2991 ms, server copy still at 10658.2,10140.5,0 on the stairs.
local LEVEL_MS = 6000
local PLACE_TRIES = 10       -- places of the metagrid tried when a site is missing around the player (RST.Places)
local PLACE_RADIUS = 400     -- squares around the start place

local B, D = K.B, K.D
local measure = K.measurer("[LKT]")
local TRACK_TOL = 2.5   -- squares: copy of every client at the target at the end (arrival 1 + lag of a copy)

local clearLane   -- defined with atSite (players off the lane of a site)
local function O() return LivingKnox and LivingKnox.Obstacles end
local function X() return LivingKnox and LivingKnox.Executor end
local function GR() return LivingKnox and LivingKnox.Groups end
local function DT() return LivingKnox and LivingKnox.Detour end

local function cell() return getCell() end

-- Walkable square with a floor.
local function walkable(sq)
    return sq ~= nil and sq:isFree(false) and sq:TreatAsSolidFloor() and not sq:HasStairs()
end

-- Edge between (x, y) and its east ("W") or south ("N") neighbour: squares a (west / north) and b, unit normal a -> b.
local function edgeAt(x, y, z, kind)
    local a = cell():getGridSquare(x, y, z)
    local bx, by = x, y
    if kind == "W" then bx = x + 1 else by = y + 1 end
    local b = cell():getGridSquare(bx, by, z)
    if a == nil or b == nil then return nil end
    return { a = a, b = b, kind = kind, nx = bx - x, ny = by - y, key = bx .. "," .. by .. "," .. z .. "," .. kind }
end

-- Every door edge (west or north side of a square) within r squares of the square a (E18-T31).
local function doorEdgesNear(a, r)
    local out = {}
    local z = a:getZ()
    for x = a:getX() - r, a:getX() + r do
        for y = a:getY() - r, a:getY() + r do
            local p = cell():getGridSquare(x, y, z)
            if p ~= nil then
                for _, k in ipairs({ "W", "N" }) do
                    local e = edgeAt(x, y, z, k)
                    if e ~= nil and p:isDoorTo(e.b) then out[#out + 1] = e end
                end
            end
        end
    end
    return out
end

-- Nothing on the common edge of the neighbours p and q: no wall, door, window, window frame or low fence
-- (IsoGridSquare isBlockedTo / isDoorTo / isWindowTo / isHoppableTo / getWindowFrameTo).
local function openStep(p, q)
    return not p:isBlockedTo(q) and not p:isDoorTo(q) and not p:isWindowTo(q) and not p:isHoppableTo(q)
        and p:getWindowFrameTo(q) == nil
end

-- Start (two squares before a along the normal) and target (two squares past b), or nil: the six squares walkable
-- and joined by open edges except the obstacle, so that the straight lane through the obstacle is the shortest way
-- (LK04-T08: a start square behind a wall sent the body around, through another window); the start square accepted
-- by LivingKnox.Bodies.freeSquare, so that the body appears on it and not shifted to another room.
local function lane(e)
    local z = e.a:getZ()
    local s1 = cell():getGridSquare(e.a:getX() - e.nx, e.a:getY() - e.ny, z)
    local s2 = cell():getGridSquare(e.a:getX() - 2 * e.nx, e.a:getY() - 2 * e.ny, z)
    local t1 = cell():getGridSquare(e.b:getX() + e.nx, e.b:getY() + e.ny, z)
    local t2 = cell():getGridSquare(e.b:getX() + 2 * e.nx, e.b:getY() + 2 * e.ny, z)
    for _, sq in ipairs({ e.a, e.b, s1, s2, t1, t2 }) do
        if not walkable(sq) then return nil end
    end
    if not (openStep(s2, s1) and openStep(s1, e.a) and openStep(e.b, t1) and openStep(t1, t2)) then return nil end
    local Bd = B()
    if Bd ~= nil and Bd.freeSquare ~= nil and not Bd.freeSquare(s2) then return nil end
    return s2, t2
end

-- Position (x, y) relative to the edge e: distance past the edge along its normal (negative on the start side) and
-- lateral distance from the middle of the edge.
local function edgeOffset(e, x, y)
    local mx, my = e.b:getX() + 0.5 * e.ny, e.b:getY() + 0.5 * e.nx
    return (x - e.b:getX()) * e.nx + (y - e.b:getY()) * e.ny, math.abs((x - mx) * e.ny + (y - my) * e.nx)
end

-- True if a move from (ax, ay) to (bx, by) crosses the edge e through the obstacle itself (within e.lat squares of
-- the middle of the edge, one by default), from the start side to the far side.
local function crossed(e, ax, ay, bx, by)
    local a, la = edgeOffset(e, ax, ay)
    local b, lb = edgeOffset(e, bx, by)
    local lat = e.lat or 1
    return a < 0 and b >= 0 and la <= lat and lb <= lat
end

-- Nearest edge around the player accepted by pick(e) (returns the object), with its lane, or nil.
local function findSite(p, pick)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local best, bestD = nil, nil
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, pz, kind)
                local obj = e and pick(e)
                if obj ~= nil then
                    local start, target = lane(e)
                    local d = math.abs(x - px) + math.abs(y - py)
                    if start ~= nil and (bestD == nil or d < bestD) then
                        best, bestD = { e = e, obj = obj, start = start, target = target }, d
                    end
                end
            end
        end
    end
    return best
end

-- Nearest edge around the player accepted by pick(e), with its lane starting outside a building (fromInside false)
-- or inside one (true), whichever side of the edge that is: when e.a is not on the wanted side, the edge is taken
-- from b (a and b swapped, normal reversed, same key; flag reversed). findSite only builds lanes from a (west /
-- north), so a house whose doors open north or west to the outside never gave a lane from outside (lk.force,
-- campaign MP 2026-10-15: door 10661,10143 N of the spawn house, lane from inside, opened from inside without the
-- key). The reversed edge is for lane / onLane only: edgeOffset and crossed assume the original orientation.
local function findSiteFrom(p, pick, fromInside)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local best, bestD = nil, nil
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, pz, kind)
                local obj = e and pick(e)
                if obj ~= nil then
                    if (e.a:getBuildingDef() ~= nil) ~= fromInside then
                        e = { a = e.b, b = e.a, kind = e.kind, nx = -e.nx, ny = -e.ny, key = e.key, reversed = true }
                    end
                    local start, target = lane(e)
                    local d = math.abs(x - px) + math.abs(y - py)
                    -- From outside: the square in front of the door must not count as inside for the opening rule
                    -- (LivingKnox.Obstacles.opensFromInside, as IsoDoor.canBeOpenFromInside: a covered square without
                    -- a room next to a door square without a room passes the room test, nil == nil). MP campaign of
                    -- 2026-10-15: start under a porch, "opened and unlocked from inside", doors broken 0.
                    local Ob = LivingKnox and LivingKnox.Obstacles
                    local outsideOk = fromInside or Ob == nil or Ob.opensFromInside == nil
                        or not Ob.opensFromInside(obj, e.a)
                    if start ~= nil and (e.a:getBuildingDef() ~= nil) == fromInside and outsideOk
                        and (bestD == nil or d < bestD) then
                        best, bestD = { e = e, obj = obj, start = start, target = target }, d
                    end
                end
            end
        end
    end
    return best
end

-- Every edge around the player accepted by pick(e), with its lane, nearest first (Manhattan distance).
local function findSites(p, pick)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local out = {}
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, pz, kind)
                local obj = e and pick(e)
                if obj ~= nil then
                    local start, target = lane(e)
                    if start ~= nil then
                        out[#out + 1] = { e = e, obj = obj, start = start, target = target,
                            d = math.abs(x - px) + math.abs(y - py) }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.e.key < b.e.key
    end)
    return out
end

-- Players are solid: the player standing on the lane of a site (or next to it) blocks or pushes the body (solo
-- campaign of 2026-10-15, commit 54087fb: player placed on the door square 11313,6940 of "locked home door: refused
-- without the key", body counted through the door). A player within LANE_CLEAR squares of a square of the lane is
-- moved (RST.Fixtures.movePlayers, back at the end: on a server the other clients move by the same offset) to the
-- nearest free square farther than that, same level. A site routed through doors (site.doorEdges) also clears the
-- route start -> door edges: MP campaign of 2026-11-13 (runs/20261113-150840-parallel-3 shard3), both players in the
-- one-square corridor to the door 10655,10135 N of "destination behind a locked door elsewhere", body stuck there.
local LANE_CLEAR = 2
local function addSegment(out, x0, y0, x1, y1)
    local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
    for i = 0, n do
        out[#out + 1] = { x = x0 + (n > 0 and math.floor((x1 - x0) * i / n + 0.5) or 0),
            y = y0 + (n > 0 and math.floor((y1 - y0) * i / n + 0.5) or 0) }
    end
end
local function laneSquares(site)
    local out = {}
    local e = site.e
    if e == nil or site.start == nil or site.target == nil then return out end
    local x0, y0 = site.start:getX(), site.start:getY()
    addSegment(out, x0, y0, site.target:getX(), site.target:getY())
    local px, py = x0, y0
    for _, d in ipairs(site.doorEdges or {}) do
        if d.ax ~= nil and d.ay ~= nil then
            addSegment(out, px, py, d.ax, d.ay)
            px, py = d.ax, d.ay
            if d.bx ~= nil and d.by ~= nil then
                addSegment(out, px, py, d.bx, d.by)
                px, py = d.bx, d.by
            end
        end
    end
    return out
end
local function nearLane(squares, x, y)
    for _, q in ipairs(squares) do
        if math.abs(q.x - x) <= LANE_CLEAR and math.abs(q.y - y) <= LANE_CLEAR then return true end
    end
    return false
end
clearLane = function(t, site, run)
    local squares = laneSquares(site)
    local p = RST.Fixtures.player(t)
    if #squares == 0 or p == nil or not nearLane(squares, math.floor(p:getX()), math.floor(p:getY())) then
        return run(t, site)
    end
    local z = site.e.a:getZ()
    local cx, cy = math.floor(p:getX()), math.floor(p:getY())
    for r = LANE_CLEAR + 1, 12 do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sq = cell():getGridSquare(cx + dx, cy + dy, z)
                    if sq ~= nil and walkable(sq) and not nearLane(squares, sq:getX(), sq:getY()) then
                        print("[LKT] player off the lane of the site: " .. sq:getX() .. "," .. sq:getY() .. "," .. z)
                        return RST.Fixtures.movePlayers(t, p, sq:getX() + 0.5, sq:getY() + 0.5, z, function(t2)
                            return run(t2, site)
                        end)
                    end
                end
            end
        end
    end
    t:note("player left next to the lane of the site (no free square around)")
    return run(t, site)
end

-- Site of a test (decision of 2026-10-15, see the header): find(player) around the player, else at the places of
-- RST.Places.ensure (outdoor: around the buildings instead of inside); run(t, site) is the next step. SKIP with what
-- (text "no <what> found (n place(s) tried ...)") when no place has it.
local function atSite(t, what, find, run, outdoor, tries)
    local found
    local spec = { name = what, outdoor = outdoor == true, radius = PLACE_RADIUS, tries = tries or PLACE_TRIES,
        spot = function(p)
            local sq = p:getCurrentSquare()
            if sq == nil then return nil end
            found = find(p)
            if found == nil then return nil end
            return sq
        end }
    RST.Places.ensure(t, spec, function(t2)
        if found == nil then t2:skip("no " .. what .. " within " .. SEARCH .. " squares") end
        return clearLane(t2, found, run)
    end)
end

-- Ground floor window (IsoWindow) that can be opened: not barricaded, not perma locked, not invincible.
local function pickWindow(e)
    local w = e.a:getWindowTo(e.b)
    if w == nil or w:isBarricaded() or w:isPermaLocked() or w:isInvincible() then return nil end
    return w
end

-- Low fence: hoppable edge without window, window frame or door, no stairs on either side. A low gate (closed
-- hoppable door) is left out (a door edge).
local function pickFence(e)
    -- 2026-10-11 23:08: the edge 10747,9538 W carries a wall and a "HoppableW" counter: isHoppableTo (objects) is true,
    -- but the engine sees a wall (square flag removed): LivingKnox.Edges.fenceTo reads the flag.
    local edges = LivingKnox.Edges
    if edges == nil or not edges.fenceTo(e.a, e.b) then return nil end
    if e.a:getWindowTo(e.b) ~= nil or e.a:getWindowFrameTo(e.b) ~= nil then return nil end
    if e.a:getDoorTo(e.b) ~= nil then return nil end
    if e.a:HasStairs() or e.b:HasStairs() then return nil end
    return e.a:getHoppableTo(e.b)
end

-- Doors on the edges within one square of the lane of the edge e (six squares, from two before e.a to two past e.b),
-- the edge e itself left out: { { door, e (edgeAt) } }, nearest first along the lane (LK04-T14).
local function doorsByLane(e)
    local z = e.a:getZ()
    local x1, y1 = e.a:getX() - 2 * e.nx, e.a:getY() - 2 * e.ny
    local x2, y2 = e.b:getX() + 2 * e.nx, e.b:getY() + 2 * e.ny
    local minx, maxx = math.min(x1, x2) - 1, math.max(x1, x2) + 1
    local miny, maxy = math.min(y1, y2) - 1, math.max(y1, y2) + 1
    local out = {}
    for x = minx, maxx do
        for y = miny, maxy do
            for _, kind in ipairs({ "W", "N" }) do
                local inBox = (kind == "W" and x + 1 <= maxx) or (kind == "N" and y + 1 <= maxy)
                local de = inBox and edgeAt(x, y, z, kind) or nil
                local door = de and de.key ~= e.key and de.a:getDoorTo(de.b) or nil
                if door ~= nil then out[#out + 1] = { door = door, e = de, key = de.key } end
            end
        end
    end
    return out
end

-- LK04-T14 (solo test of 2026-10-11 22:30): the native path to a low fence took a closed garage door next to it,
-- refused by the authority. The crossing tests check the window or the fence itself: a site with a door within one
-- square of its lane is left out (the native path may take the door at about the same length). The detour after a
-- refused door has its own test (pickFenceByRefusedDoor).
-- Solo campaign of 2026-10-15 (low fence 11311,6938,W: "the body went around the obstacle"): a farming plant or a
-- campfire within Bodies.HAZARD_AVOID of the lane splits the move into steps around it (LivingKnox.Directives.planDetour,
-- LK05-T12: the garden comes first; "move #20 split into 3 steps around farming plants or campfires"), and the detour
-- passed beside the fence. A crossing site whose straight lane passes in the zone of a plant or a campfire is left out,
-- as planDetour sees it (Directives.hazardsOnLine with the HAZARD_AVOID margin, from the centre of the start square).
local function laneNearHazard(e)
    local Dir, Bd = D(), B()
    if Dir == nil or Dir.hazardsOnLine == nil or Bd == nil or Bd.HAZARD_AVOID == nil then return false end
    local s, t = lane(e)
    if s == nil then return false end
    return Dir.hazardsOnLine(s:getX() + 0.5, s:getY() + 0.5, t:getX() + 0.5, t:getY() + 0.5, s:getZ(),
        Bd.HAZARD_AVOID) > 0
end

local function rawPick(pick)
    return function(e)
        local obj = pick(e)
        if obj == nil or #doorsByLane(e) > 0 or laneNearHazard(e) then return nil end
        return obj
    end
end

-- Closed doors within one square of the lane of e that a npc without group or key would not pass
-- (LivingKnox.Detour.doorRefusal: double, locked, barricaded, home of a group...), low gates left out.
local function refusedDoorsByLane(e)
    local o = O()
    local out = {}
    for _, d in ipairs(doorsByLane(e)) do
        if not o.isOpen(d.door) and not o.isLowGate(d.door)
            and DT().doorRefusal("lkt-probe", d.door, d.e.a, d.e.b) ~= nil then
            out[#out + 1] = d
        end
    end
    return out
end

-- Single doors within one square of the lane of e that the test can make refused by nailing one plank on them
-- (closed first; LivingKnox.Obstacles.decide: "barricaded door"): not a low gate, not obstructed, not destroyed.
local function barricadableDoorsByLane(e)
    local o = O()
    local out = {}
    for _, d in ipairs(doorsByLane(e)) do
        if o.kindOf(d.door) == "single" and not o.isLowGate(d.door) and not d.door:isObstructed()
            and not d.door:isBarricaded() and d.door:getObjectIndex() ~= -1 then
            out[#out + 1] = d
        end
    end
    return out
end

-- Low fence site with a refused door within one square of its lane (LK04-T14), or with a single door there that the
-- test barricades (decor made by the test: solo campaign of 2026-10-15, no fence next to a refused door in 10 places).
local function pickFenceByRefusedDoor(e)
    local obj = pickFence(e)
    if obj == nil or DT() == nil or DT().doorRefusal == nil or laneNearHazard(e) then return nil end
    if #refusedDoorsByLane(e) == 0 and #barricadableDoorsByLane(e) == 0 then return nil end
    return obj
end


-- Decor built by the test when no place has a low fence next to a door (solo campaigns of 2026-10-15: 20 places
-- tried): a vanilla low wooden fence (WoodFenceLvl1, carpentry_02_40 HoppableW / carpentry_02_41 HoppableN) is put
-- across the outside strip along the wall of a single exterior door, its lane running along the wall in front of the
-- door (the door within one square of the lane). Planned here without touching the world ({ build = ... }), put by
-- buildFence in the test. Candidate: the six lane squares walkable and joined by open edges (the fence edge too,
-- before the fence), start square free, no door, window or stairs on the fence edge, no plant or campfire next to
-- the lane, the door single and closable.
local FENCE_SPRITE = { W = "carpentry_02_40", N = "carpentry_02_41" }
local function planFenceByDoor(p)
    local o = O()
    if o == nil or o.kindOf == nil then return nil end
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local best, bestD = nil, nil
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            for _, kind in ipairs({ "W", "N" }) do
                local de = edgeAt(x, y, pz, kind)
                local door = de and de.a:getDoorTo(de.b)
                if door ~= nil and o.kindOf(door) == "single" and not o.isLowGate(door) and not door:isObstructed()
                    and not door:isBarricaded() and (de.a:getBuildingDef() == nil) ~= (de.b:getBuildingDef() == nil) then
                    local out = de.a:getBuildingDef() == nil and de.a or de.b
                    -- Door W (wall along y): lane along y on the outside column, fence N; door N: lane along x, fence W.
                    local fkind = kind == "W" and "N" or "W"
                    for _, off in ipairs({ 0, -1, 1, -2 }) do
                        local fx, fy = out:getX(), out:getY()
                        if fkind == "N" then fy = fy + off else fx = fx + off end
                        local e = edgeAt(fx, fy, pz, fkind)
                        if e ~= nil and walkable(e.a) and walkable(e.b) and openStep(e.a, e.b)
                            and e.a:getDoorTo(e.b) == nil and not e.a:HasStairs() and not e.b:HasStairs() then
                            local start, target = lane(e)
                            local d = math.abs(x - px) + math.abs(y - py)
                            if start ~= nil and not laneNearHazard(e) and #barricadableDoorsByLane(e) > 0
                                and (bestD == nil or d < bestD) then
                                -- Fence object on b: its north (N) or west (W) edge is the edge e.
                                best, bestD = { e = e, start = start, target = target, build = { sq = e.b,
                                    sprite = FENCE_SPRITE[fkind], door = de.key } }, d
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Puts the planned fence of site (planFenceByDoor), removed afterwards (t:defer), and fills site.obj with it; the
-- site must then be a low fence site (pickFence) with its lane, else FAIL.
local function buildFence(t, site)
    local b = site.build
    local obj = IsoObject.new(getCell(), b.sq, b.sprite)
    t:ok(obj ~= nil, "fence " .. b.sprite .. " not created")
    if isServer() then b.sq:transmitAddObjectToSquare(obj, -1) else b.sq:AddTileObject(obj) end
    b.sq:RecalcProperties()
    t:defer(function()
        local sq = obj:getSquare()
        if sq ~= nil and obj:getObjectIndex() ~= -1 then
            if isServer() then sq:transmitRemoveItemFromSquare(obj) else sq:RemoveTileObject(obj) end
        end
    end, "remove the fence put by the test at " .. site.e.key)
    print("[LKT] refused door next to a low fence: fence " .. b.sprite .. " put by the test on " .. site.e.key
        .. " next to the door " .. b.door)
    site.obj = pickFence(site.e)
    t:ok(site.obj ~= nil, "the fence put on " .. site.e.key .. " is not a low fence for the engine")
    t:ok(lane(site.e) ~= nil, "no free lane through the fence put on " .. site.e.key)
end

-- Window site for the detour test (LK17-T01): a window lane with no door next to it (rawPick), for which
-- LivingKnox.Detour.plan, probed from the lane start as if the window were refused there, gives a door (no last
-- resort). The DETOUR_PROBE nearest window sites are tried. Adds detour (the plan) and doorEdges (edge of that door,
-- for the lane clearing) to the site.
local DETOUR_PROBE = 12
local function findDetourSite(p)
    local o, dt = O(), DT()
    if o == nil or dt == nil or dt.plan == nil then return nil end
    local sites = findSites(p, rawPick(pickWindow))
    for i = 1, math.min(#sites, DETOUR_PROBE) do
        local s = sites[i]
        local z = s.e.a:getZ()
        local sx, sy = s.start:getX() + 0.5, s.start:getY() + 0.5
        local body = { getX = function() return sx end, getY = function() return sy end, getZ = function() return z end }
        local entry = { v = -1, op = "move", x = s.target:getX(), y = s.target:getY(), z = z }
        local c = { e = o.edge(s.e.a:getX(), s.e.a:getY(), z, s.e.kind), sqA = s.e.a, sqB = s.e.b }
        local plan = dt.plan("lkt-probe", entry, c, body, { [s.e.key] = true })
        if plan ~= nil and plan.kind == "door" and not plan.lr and plan.w ~= nil and #plan.w >= 2 then
            local a, b = plan.w[1], plan.w[2]
            s.detour = plan
            s.doorEdges = { { ax = a.x, ay = a.y, bx = b.x, by = b.y, key = plan.via } }
            return s
        end
    end
    return nil
end

-- Exterior door for the home test (LK04-T10): nearest single door within SEARCH squares of the player, on its level,
-- with one side in a building and the other outside, both squares loaded and free, not barricaded, destroyed,
-- padlocked or obstructed (LivingKnox.Obstacles.shutRefusal), closed doors that are low gates left out, and its
-- building not already the home of a group. Returns { e, door, inside (square in the building) } or nil.
local function findHomeDoor(p)
    local o = O()
    local homes = o.refreshHomes(true).byBuilding
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local best, bd = nil, nil
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, pz, kind)
                local door = e and e.a:getDoorTo(e.b)
                if door ~= nil and o.shutRefusal(door) == nil and not door:isObstructed()
                    and (o.isOpen(door) or not o.isLowGate(door))
                    and e.a:getMovingObjects():size() == 0 and e.b:getMovingObjects():size() == 0 then
                    local da, db = e.a:getBuildingDef(), e.b:getBuildingDef()
                    local inside = (da ~= nil and db == nil) and e.a or ((db ~= nil and da == nil) and e.b or nil)
                    local def = inside and inside:getBuildingDef()
                    if def ~= nil and homes[def:getIDString()] == nil then
                        local d = math.abs(x - px) + math.abs(y - py)
                        if bd == nil or d < bd then best, bd = { e = e, door = door, inside = inside }, d end
                    end
                end
            end
        end
    end
    return best
end

-- Exterior doors (one side in the building def, the other not) on level z of the rectangle of def, loaded squares
-- only, except the door skip: { { door, key } } for keepDoors (same scan as the closing on arrival of
-- LivingKnox.Obstacles: edges around def:getX() - 1 .. def:getX2() - 1).
local function exteriorDoors(def, z, skip)
    local out = {}
    if def == nil then return out end
    local id = def:getIDString()
    local function inside(sq)
        local d = sq:getBuildingDef()
        return d ~= nil and d:getIDString() == id
    end
    for x = def:getX() - 1, def:getX2() - 1 do
        for y = def:getY() - 1, def:getY2() - 1 do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, z, kind)
                local door = e and e.a:getDoorTo(e.b)
                if door ~= nil and door ~= skip and inside(e.a) ~= inside(e.b) then
                    out[#out + 1] = { door = door, key = e.key }
                end
            end
        end
    end
    return out
end

local function spawnAt(t, sq)
    t:ok(B() ~= nil and D() ~= nil and O() ~= nil, "LivingKnox.Bodies, Directives or Obstacles is not loaded here")
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Opens or closes the window w (a toggle) with the body of npc id. Bodies.find returns two values (body, "bound"):
-- kept to the first one, as IsoWindow:ToggleWindow(IsoGameCharacter) refuses a second argument (Kahlua
-- MethodArguments.assertValid: "expected 1 argument, got 2", LK04-T08).
local function setOpen(w, id, open)
    if w:IsOpen() ~= open then w:ToggleWindow((B().find(id))) end
end

-- Window state saved now and restored by t:defer (registered after the npc: runs before its removal).
local function keepWindow(t, w, id)
    local was = { open = w:IsOpen(), smashed = w:isSmashed(), locked = w:isLocked() }
    t:defer(function()
        if w:isSmashed() ~= was.smashed then
            w:setSmashed(was.smashed)
            if not was.smashed then w:setGlassRemoved(false) end
        end
        setOpen(w, id, was.open)
        w:setIsLocked(was.locked)
        w:getSquare():RecalcProperties()
        if isServer() then w:sync() end
    end, "restore the window")
    return was
end

-- Door states saved now and restored by t:defer (LivingKnox.Obstacles.setDoor: fixed state, lock put back).
local function keepDoors(t, edges)
    for _, de in ipairs(edges) do
        local d = de.door
        if d ~= nil then
            local was = { open = O().isOpen(d), locked = d:isLocked() or d:isLockedByKey() }
            t:defer(function()
                -- setDoor never unlocks a door it leaves closed: lock taken off here first (LK04-T12 tests lock it).
                if not was.locked and (d:isLocked() or d:isLockedByKey()) then
                    d:setLockedByKey(false, false)
                    d:setIsLocked(false)
                    if isServer() then d:sync() end
                end
                O().setDoor(d, was.open, was.locked)
            end, "restore the door " .. de.key)
        end
    end
end

-- Decor of the refused door test: when no door next to the lane of site is refused yet, the nearest single door is
-- closed and one plank is nailed on it (IsoBarricade.AddBarricadeToObject, addPlank, as lk.force), plank removed and
-- door state restored afterwards (t:defer, reverse order).
local function refuseDoorNextTo(t, site)
    if #refusedDoorsByLane(site.e) > 0 then return end
    local d = barricadableDoorsByLane(site.e)[1]
    t:ok(d ~= nil, "no door next to the low fence " .. site.e.key)
    keepDoors(t, { d })
    O().setDoor(d.door, false, false)
    local b = IsoBarricade.AddBarricadeToObject(d.door, false)
    t:ok(b ~= nil, "barricade not added on the door " .. d.key)
    b:addPlank(nil, nil)
    if isServer() then b:transmitCompleteItemToClients() end
    t:defer(function()
        local sq = b:getSquare()
        if sq ~= nil and b:getObjectIndex() ~= -1 then
            if isServer() then sq:transmitRemoveItemFromSquare(b) else sq:RemoveTileObject(b) end
        end
    end, "remove the barricade of the door " .. d.key)
    print("[LKT] refused door next to a low fence: door " .. d.key .. " closed and barricaded by the test")
end

-- Tests of a refusal itself: the detour after a refusal (LK17-T01, hook LivingKnox.Obstacles.onRefusal of
-- LK_Detour.lua) is switched off during the test, restored by t:defer; the refusal then closes the move.
local function noDetour(t)
    local o = O()
    if o == nil then return end
    local was = o.onRefusal
    o.onRefusal = nil
    t:defer(function() o.onRefusal = was end, "restore the detour after a refusal")
end

-- 2026-10-11 23:08 (closed window, raiders: "expected arrived, got faced"): the decision framework of the group
-- (LivingKnox.Decisions, LK05) never replaces an open directive of another module, but issues its own as soon as the
-- test move is closed, in the same tick (guard duty: face #26), before the test reads the state. The npc of a test is
-- left out of the decisions of its group for the whole test (Decisions.evaluate skipped for it, put back by t:defer:
-- deferred calls run last in, first out, so nested wraps unwind in order).
local function isolate(t, id)
    local Dec = LivingKnox and LivingKnox.Decisions
    if Dec == nil or type(Dec.evaluate) ~= "function" then return end
    local base = Dec.evaluate
    Dec.evaluate = function(gid, g, mid, m, ...)
        if m ~= nil and m.npc == id then return nil end
        return base(gid, g, mid, m, ...)
    end
    t:defer(function() Dec.evaluate = base end, "decisions of the group back for " .. id)
end

local function groupOf(t, id, gtype)
    t:ok(GR() ~= nil and GR().isReady(), "LivingKnox.Groups is not ready")
    isolate(t, id)
    local g = GR().create({ type = gtype or "settlers", name = "Traversal" })   -- no home: no house rule applies
    t:ok(g ~= nil, "group not created")
    t:defer(function() GR().remove(g.id) end, "remove the group")
    t:ok(GR().addMember(g.id, { role = "fighter", npc = id }) ~= nil, "member not added")
    O().refreshHomes(true)
    return g.id
end

-- Trip of npc id to the square target: arrival (or the expected failure), longest still stretch outside a crossing,
-- crossing states seen. then(t, info) runs once the directive is closed. With edge (the site edge), info.via tells
-- whether the body went through the obstacle itself (LK04-T08: the body may go around it, through another door or
-- window): required on arrival, refused on the expected failure.
local function tripRaw(t, id, target, what, expectFail, after, edge, watch)
    local X0 = X()
    local base = X0 and { crossings = X0.stats.crossings or 0, retries = X0.stats.retries or 0 } or nil
    local v, why = D().moveTo(id, target:getX(), target:getY(), target:getZ(), "walk")
    t:ok(v ~= nil, what .. ": move refused: " .. tostring(why))
    local info = { start = getTimestampMs(), seen = {}, still = 0, maxStill = 0, last = nil, via = false, pos = nil,
        through = {} }
    local function step()
        local z = B().find(id)
        local now = getTimestampMs()
        if z ~= nil then
            local st = z:getActionStateName()
            if st ~= nil and CROSSING[st] then info.seen[st] = true end
            -- LK04-T11: body on the floor during or after a crossing (zombie landing: OnFloor of the vanilla nodes,
            -- ClimbWindowFlopped / ClimbFenceFlopped set by the Java state, cleared on exit).
            if (info.seen.climbwindow or info.seen.climbfence) and (z:isOnFloor() or z:isKnockedDown()
                or z:getVariableBoolean("ClimbWindowFlopped") or z:getVariableBoolean("ClimbFenceFlopped")) then
                info.floored = true
            end
            local p = info.pos
            if edge ~= nil and p ~= nil and crossed(edge, p.x, p.y, z:getX(), z:getY()) then info.via = true end
            for _, we in ipairs(watch or {}) do   -- crossings of other edges, either way
                if p ~= nil and (crossed(we, p.x, p.y, z:getX(), z:getY()) or crossed(we, z:getX(), z:getY(), p.x, p.y)) then
                    info.through[we.key] = true
                end
            end
            info.pos = { x = z:getX(), y = z:getY() }
            local last = info.last
            if last == nil or CROSSING[st or ""] or math.abs(z:getX() - last.x) + math.abs(z:getY() - last.y) >= STILL
                or math.abs(z:getZ() - last.z) >= 0.5 then
                info.last = { x = z:getX(), y = z:getY(), z = z:getZ(), ms = now }
            else
                local s = now - last.ms
                if s > info.maxStill then info.maxStill = s end
            end
        end
        local e = D().get(id)
        if e ~= nil and e.v ~= v then   -- move replaced by another directive (2026-10-11 23:08: face #26)
            info.replaced = tostring(e.op) .. " #" .. tostring(e.v)
            return true
        end
        return e ~= nil and e.done == true
    end
    t:waitUntil(step, ARRIVE_MS, function(t2)
        local e = D().get(id)
        local z = B().find(id)
        local seen = {}
        for k in pairs(info.seen) do seen[#seen + 1] = k end
        table.sort(seen)
        local cross, retries = "n/a", "n/a"
        if base ~= nil then
            local st = X().stats
            cross = ((st.crossings or 0) - base.crossings) .. " crossing(s), last " .. tostring(st.crossMs) .. " ms"
            retries = tostring((st.retries or 0) - base.retries)
        end
        measure(string.format("%s: %s by %s in %d ms, body at %s, crossing states [%s], %s, longest still %d ms, "
            .. "retries %s, through the obstacle %s, on the floor after a crossing %s", what, tostring(e and e.s),
            tostring(e and e.by), getTimestampMs() - info.start,
            z and string.format("%.1f,%.1f,%d", z:getX(), z:getY(), math.floor(z:getZ())) or "?",
            table.concat(seen, " "), cross, info.maxStill, retries, edge and tostring(info.via) or "n/a",
            tostring(info.floored == true)))
        t2:ok(info.replaced == nil, what .. ": move #" .. tostring(v) .. " replaced by " .. tostring(info.replaced)
            .. " before its end was read (decision of the group?)")
        if #seen > 0 and not isServer() then   -- LK04-T11: human landing, the body stays up
            t2:ok(info.floored ~= true, what .. ": body on the floor after the crossing (zombie landing)")
        end
        if edge ~= nil and not expectFail then
            t2:ok(info.via, what .. ": the body went around the obstacle " .. edge.key .. " (another way)")
        elseif edge ~= nil then
            t2:ok(not info.via, what .. ": the body went through the obstacle " .. edge.key)
        end
        t2:eq(expectFail and "failed" or "arrived", e and e.s, what .. ": directive state")
        t2:ok(info.maxStill < BLOCKED_MS, what .. ": body still for " .. info.maxStill .. " ms (blocked)")
        if after then after(t2, info, e) end
    end, what .. ": move not finished")
end

-- LK04-T03 (E01-T16): trip watched by every client on a dedicated server when observe is true (crossing tests): each
-- client follows its own copy (RST.Steps "lk.track", RST_PeerChecksLK2.lua) and must see it go through the obstacle
-- edge and stand at the target at the end (two observers: the requester and the second client).
local function trip(t, id, target, what, expectFail, after, edge, watch, observe)
    if not (observe and edge ~= nil and not expectFail and isServer()) then
        return tripRaw(t, id, target, what, expectFail, after, edge, watch)
    end
    local key = id .. "-" .. tostring(getTimestampMs())
    local e = { bx = edge.b:getX(), by = edge.b:getY(), nx = edge.nx, ny = edge.ny }
    RST.Steps.ask(t, "lk.track", { phase = "begin", key = key, npc = id, edge = e }, { target = "all", timeoutMs = 5000 },
        function(t1)
            tripRaw(t1, id, target, what, expectFail, function(t2, info, de)
                -- E18-T31 (MP pass runs/20261108-111228-mp-50034033a4c3, open window): arrival is told within
                -- Directives.ARRIVE (1 square) of the owner's copy; the other client took the body over right after,
                -- its copy 0.9 square behind, and the body stayed there (1.9 squares): TRACK_TOL.
                RST.Steps.ask(t2, "lk.track", { phase = "end", key = key, cross = true, tol = TRACK_TOL,
                    target = { x = target:getX() + 0.5, y = target:getY() + 0.5, z = target:getZ() } },
                    { target = "all", timeoutMs = 10000 }, function(t3)
                        if after then return after(t3, info, de) end
                    end)
            end, edge, watch)
        end)
end

-- True if the point (x, y, z) is on the start square of the lane of site or on the next one (one or two squares
-- before the edge), by its square (floor of the coordinates): a body may stand up anywhere on its square, its corner
-- included (2026-10-11 14:58: body at 10693.0,10245.0 on its start square 10693,10245, refused by a lateral distance
-- of 0.5). Else false and the reason.
local function onLane(site, x, y, z)
    local e = site.e
    if math.floor(z) ~= e.a:getZ() then return false, "body spawned on another level" end
    local sx, sy = math.floor(x), math.floor(y)
    local x0, y0 = site.start:getX(), site.start:getY()
    if (sx == x0 and sy == y0) or (sx == x0 + e.nx and sy == y0 + e.ny) then return true end
    return false, string.format("body spawned off the lane at %.1f,%.1f (start %d,%d)", x, y, x0, y0)
end

-- Body standing in the lane, one or two squares before the edge (the spawn may shift it, maybe into another room
-- behind a wall: LK04-T08), else SKIP with the place.
local function onStartSide(t, id, site)
    local z = B().find(id)
    t:ok(z ~= nil, "npc body lost")
    local ok, why = onLane(site, z:getX(), z:getY(), z:getZ())
    if not ok then t:skip(why) end
end

-- Stairs nearest the player p (on its level), then the two ends of a trip over them, or nil: bottom, a free floor
-- square of that level 3 to 5 squares (Manhattan) from the stairs and JOINED to them by open edges (openStep, through
-- free squares or stairs: no wall, door, window or fence between); top, the nearest free floor square one level up.
-- 2026-10-11 23:08: the nearest square, 10746,9531, was outside behind the wall of the hall; the body went in through
-- the closed window 10747,9532 W, over a table, and fell (zombie "obstacle" landing). Returns stairs, bottom, top.
local function stairsEnds(p)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local stairs = nil
    for r = 0, SEARCH do
        for x = px - r, px + r do
            for y = py - r, py + r do
                local sq = stairs == nil and cell():getGridSquare(x, y, pz) or nil
                if sq ~= nil and sq:HasStairs() then stairs = sq end
            end
        end
    end
    if stairs == nil then return nil end
    local sx, sy = stairs:getX(), stairs:getY()
    local top, td = nil, nil
    for dx = -5, 5 do
        for dy = -5, 5 do
            local sq = cell():getGridSquare(sx + dx, sy + dy, pz + 1)
            local d = math.abs(dx) + math.abs(dy)
            if walkable(sq) and d >= 1 and (td == nil or d < td) then top, td = sq, d end
        end
    end
    local seen, queue, head = { [sx .. "," .. sy] = true }, { stairs }, 1
    local bottom, bd = nil, nil
    while head <= #queue do
        local a = queue[head]
        head = head + 1
        for _, dir in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local x, y = a:getX() + dir[1], a:getY() + dir[2]
            local k = x .. "," .. y
            local b = (not seen[k] and math.abs(x - sx) <= 5 and math.abs(y - sy) <= 5)
                and cell():getGridSquare(x, y, pz) or nil
            if b ~= nil and (walkable(b) or b:HasStairs()) and openStep(a, b) then
                seen[k] = true
                queue[#queue + 1] = b
                local d = math.abs(x - sx) + math.abs(y - sy)
                if walkable(b) and d >= 3 and (bd == nil or d < bd) then bottom, bd = b, d end
            end
        end
    end
    return stairs, bottom, top
end

local function windowTest(prepare, what, expectFail, check, observe)
    local run
    local function test(t)
        atSite(t, "ground floor window with a free lane and no door next to it",
            function(p) return findSite(p, rawPick(pickWindow)) end, run)
    end
    run = function(t, site)
        print("[LKT] " .. what .. ": window " .. site.e.key .. ", start " .. site.start:getX() .. ","
            .. site.start:getY() .. ", target " .. site.target:getX() .. "," .. site.target:getY())
        local id = spawnAt(t, site.start)
        local w = site.obj
        local was = keepWindow(t, w, id)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            onStartSide(t2, id, site)
            local ctx = prepare(t2, w, id) or {}
            ctx.toggles = O().stats.windowToggles or 0
            ctx.refused = O().stats.windowsRefused or 0
            ctx.closed = O().stats.windowsClosed or 0
            trip(t2, id, site.target, what, expectFail, function(t3, info, e)
                check(t3, w, info, e, ctx, was, site)
            end, site.e, nil, observe)
        end, "npc still on the floor")
    end
    return test
end

-- Exterior door for the key tests (LK04-T12): single door with one side in a building that is no group's home, not
-- barricaded, destroyed, padlocked or obstructed, not a low gate. Returns the door, or nil.
local function pickHomeDoor(e)
    local o = O()
    local door = e.a:getDoorTo(e.b)
    if door == nil or o.shutRefusal(door) ~= nil or door:isObstructed() or o.isLowGate(door) then return nil end
    local da, db = e.a:getBuildingDef(), e.b:getBuildingDef()
    if (da == nil) == (db == nil) then return nil end
    local def = da or db
    if o.refreshHomes(false).byBuilding[def:getIDString()] ~= nil then return nil end
    return door
end

-- Same, with the lane starting outside the building (fromInside false) or inside it (true) (LK04-T17).
local function pickHomeDoorFrom(fromInside)
    return function(e)
        local door = pickHomeDoor(e)
        if door == nil or (e.a:getBuildingDef() ~= nil) ~= fromInside then return nil end
        -- From outside: the start side must not count as inside for the opening rule (porch: solo campaign of
        -- 2026-10-15, door 11313,6940 N opened "from inside" from the lane start, the body arrived through it).
        local Ob = LivingKnox and LivingKnox.Obstacles
        if not fromInside and Ob ~= nil and Ob.opensFromInside ~= nil and Ob.opensFromInside(door, e.a) then
            return nil
        end
        return door
    end
end

-- Locked exterior door of the home of a settler (LK04-T12): a settlers group is created with its home in the
-- building of the door and the npc as member (he gets the key of the building, LivingKnox.Obstacles.giveKey), the
-- door is closed and locked, then the npc walks through the lane of the door. withKey: the door is opened (unlocked)
-- by the authority and locked again behind the body, exactly one key on the body; without (key removed from the
-- body), lane starting outside: the move is refused ("locked door (no key)"), the door stays closed and locked, the
-- key is not given back. fromInside (LK04-T17, without the key, lane starting inside): the door opens from inside as
-- for a player (LivingKnox.Obstacles.opensFromInside), the body arrives, the door is closed behind it, not locked.
-- Every key of keyId on the body z removed, the keys of LivingKnox.Obstacles AND any other one (key ring included):
-- MP campaign of 2026-10-15 (commit 54087fb), "key not removed": the body carried another key of the same building
-- (vanilla item of the spawned body), still found by haveThisKeyId once the module's key was gone. Returns the number.
local function stripKeys(z, keyId)
    local n = O().removeKeys(z)
    local function strip(inv)
        local items = inv:getItems()
        local drop = {}
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if instanceof(it, "Key") and it:getKeyId() == keyId then
                drop[#drop + 1] = it
            elseif instanceof(it, "InventoryContainer") then
                n = n + strip(it:getInventory())
            end
        end
        for _, it in ipairs(drop) do inv:DoRemoveItem(it) end
        return #drop
    end
    n = n + strip(z:getInventory())
    if n > 0 then print("[LKT] keys of " .. tostring(keyId) .. " removed from the body: " .. n) end
    return n
end

local function keyTest(withKey, fromInside)
    local run
    local function test(t)
        local o = O()
        t:ok(o ~= nil and o.giveKey ~= nil and GR() ~= nil and GR().isReady(),
            "LivingKnox.Obstacles.giveKey or LivingKnox.Groups is not ready here")
        -- The refusal itself is checked without the key: detour after a refusal off (LK17-T01), otherwise the npc
        -- would enter through another door of the house.
        if not withKey and not fromInside then noDetour(t) end
        local pick = withKey and pickHomeDoor or pickHomeDoorFrom(fromInside == true)
        atSite(t, "free single exterior door of a building without a home, with a free lane"
            .. (withKey and "" or (fromInside and " from inside" or " from outside")),
            function(p) return findSite(p, pick) end, run)
    end
    run = function(t, site)
        local o = O()
        local door, e = site.obj, site.e
        local inside = e.a:getBuildingDef() ~= nil and e.a or e.b
        print("[LKT] key test: door " .. e.key .. ", start " .. site.start:getX() .. "," .. site.start:getY()
            .. ", target " .. site.target:getX() .. "," .. site.target:getY() .. ", key " .. tostring(withKey))
        local id = spawnAt(t, site.start)
        keepDoors(t, { { door = door, key = e.key } })
        keepDoors(t, exteriorDoors(inside:getBuildingDef(), inside:getZ(), door))   -- the arrival may close them
        isolate(t, id)
        local g = GR().create({ type = "settlers", name = "Keys",
            home = { x = inside:getX(), y = inside:getY(), z = inside:getZ() } })
        t:ok(g ~= nil, "group not created")
        t:defer(function() GR().remove(g.id) end, "remove the group")
        local H = LivingKnox.Homes
        if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
        t:ok(GR().addMember(g.id, { role = "worker", npc = id }) ~= nil, "member not added")
        o.refreshHomes(true)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            onStartSide(t2, id, site)
            local z = B().find(id)
            o.giveKey(id, z)
            o.setDoor(door, false, true)
            local keyId = o.doorKeyId(door)
            t2:ok(o.isLocked(door) and not o.isOpen(door), "door not closed and locked")
            t2:eq(1, #o.keysOf(z), "keys of the home on the body")
            t2:ok(o.hasKey(z, keyId), "the body has no key " .. tostring(keyId) .. " of the door")
            if not withKey then
                stripKeys(z, keyId)
                t2:ok(not o.hasKey(z, keyId), "key not removed")
            end
            local opened, refused = o.stats.opened or 0, o.stats.refused or 0
            local label = withKey and "locked home door, key"
                or (fromInside and "locked home door, no key, from inside" or "locked home door, no key")
            trip(t2, id, site.target, label, not withKey and not fromInside, function(t3)
                    if fromInside and not withKey then
                        t3:eq(opened + 1, o.stats.opened or 0, "doors opened by the authority")
                        t3:eq(refused, o.stats.refused or 0, "refusals by the authority")
                        t3:waitUntil(function() return not o.isOpen(door) end, CLOSE_MS, function(t4)
                            t4:ok(not o.isLocked(door), "door locked behind the body without a key")
                        end, "door not closed behind the body")
                    elseif withKey then
                        t3:eq(opened + 1, o.stats.opened or 0, "doors opened by the authority")
                        t3:waitUntil(function() return not o.isOpen(door) end, CLOSE_MS, function(t4)
                            t4:ok(o.isLocked(door), "door closed behind the body but not locked")
                            local z2 = B().find(id)
                            t4:eq(1, z2 and #o.keysOf(z2), "keys of the home on the body after the trip")
                        end, "door not closed behind the body")
                    else
                        t3:ok(not o.isOpen(door) and o.isLocked(door), "door changed without a key")
                        t3:eq(refused + 1, o.stats.refused or 0, "refusals by the authority")
                        local r = o.lastRefused
                        t3:eq(e.key, r and r.key, "edge of the refusal")
                        t3:eq("locked door (no key)", r and r.why, "reason of the refusal")
                        local z2 = B().find(id)
                        t3:eq(0, z2 and #o.keysOf(z2), "key given back to the body")
                    end
                end, e)
        end, "npc still on the floor")
    end
    return test
end

-- Interior door for the LK04-T19 tests: single door, both sides in the same building (no group's home) and not
-- outside, no key of its own (doorKeyId -1), not barricaded, destroyed, padlocked or obstructed, not a low gate.
-- Returns the door, or nil.
local function pickInteriorDoor(e)
    local o = O()
    local door = e.a:getDoorTo(e.b)
    if door == nil or o.shutRefusal(door) ~= nil or door:isObstructed() or o.isLowGate(door) then return nil end
    local da, db = e.a:getBuildingDef(), e.b:getBuildingDef()
    if da == nil or db == nil or da:getIDString() ~= db:getIDString() then return nil end
    if e.a:isOutside() or e.b:isOutside() then return nil end
    if o.doorKeyId(door) ~= -1 then return nil end
    if o.refreshHomes(false).byBuilding[da:getIDString()] ~= nil then return nil end
    return door
end

-- Locked interior door of the home of a settler (LK04-T19, decision of 2026-10-14): opened from inside without its
-- key, relocked behind the body when it carries the key of its home (withHomeKey), left unlocked otherwise.
local function interiorKeyTest(withHomeKey)
    local run
    local function test(t)
        local o = O()
        t:ok(o ~= nil and o.giveKey ~= nil and GR() ~= nil and GR().isReady(),
            "LivingKnox.Obstacles.giveKey or LivingKnox.Groups is not ready here")
        atSite(t, "free single interior door without a key of its own, in a building without a home, with a free lane",
            function(p) return findSite(p, pickInteriorDoor) end, run)
    end
    run = function(t, site)
        local o = O()
        local door, e = site.obj, site.e
        print("[LKT] interior key test: door " .. e.key .. ", start " .. site.start:getX() .. "," .. site.start:getY()
            .. ", target " .. site.target:getX() .. "," .. site.target:getY() .. ", home key " .. tostring(withHomeKey))
        local id = spawnAt(t, site.start)
        keepDoors(t, { { door = door, key = e.key } })
        keepDoors(t, exteriorDoors(e.a:getBuildingDef(), e.a:getZ(), door))   -- the arrival may close them
        isolate(t, id)
        local g = GR().create({ type = "settlers", name = "InnerKeys",
            home = { x = e.a:getX(), y = e.a:getY(), z = e.a:getZ() } })
        t:ok(g ~= nil, "group not created")
        t:defer(function() GR().remove(g.id) end, "remove the group")
        local H = LivingKnox.Homes
        if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
        t:ok(GR().addMember(g.id, { role = "worker", npc = id }) ~= nil, "member not added")
        o.refreshHomes(true)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            onStartSide(t2, id, site)
            local z = B().find(id)
            local homeKey = o.homeKeyOf(id)
            o.giveKey(id, z)
            o.setDoor(door, false, true)
            t2:ok(o.isLocked(door) and not o.isOpen(door), "door not closed and locked")
            t2:eq(-1, o.doorKeyId(door), "key of the interior door")
            t2:eq(1, #o.keysOf(z), "keys of the home on the body")
            t2:ok(o.hasKey(z, homeKey), "the body has no key " .. tostring(homeKey) .. " of its home")
            if not withHomeKey then
                stripKeys(z, homeKey)
                t2:ok(not o.hasKey(z, homeKey), "key not removed")
            end
            local opened, refused, locked = o.stats.opened or 0, o.stats.refused or 0, o.stats.locked or 0
            -- E18-T31 (MP passes runs/20261108-113401-mp-94d7b31b0956, -114408-mp-dd92da5ac93a: "5 exterior door(s)
            -- of its home locked" by the routine of the test group during the trip): those locks are left out.
            local secured = o.stats.securedDoors or 0
            local label = withHomeKey and "locked interior home door, home key" or "locked interior home door, no key"
            trip(t2, id, site.target, label, false, function(t3)
                t3:eq(opened + 1, o.stats.opened or 0, "doors opened by the authority")
                t3:eq(refused, o.stats.refused or 0, "refusals by the authority")
                t3:waitUntil(function() return not o.isOpen(door) end, CLOSE_MS, function(t4)
                    if withHomeKey then
                        t4:ok(o.isLocked(door), "door closed behind the body but not locked with its home key")
                        t4:eq(locked + 1, (o.stats.locked or 0) - ((o.stats.securedDoors or 0) - secured),
                            "doors locked by the authority (home routine left out)")
                        local z2 = B().find(id)
                        t4:eq(1, z2 and #o.keysOf(z2), "keys of the home on the body after the trip")
                    else
                        t4:ok(not o.isLocked(door), "door locked behind the body without its home key")
                    end
                end, "door not closed behind the body")
            end, e)
        end, "npc still on the floor")
    end
    return test
end

-- LK04-T20: exterior windows (IsoWindow) of the building def on level z, loaded edges only: { { w, key } }, and
-- whether one of them is open, broken or a bare window frame (an ordinary way out: the last resort is not needed).
local function exteriorWindows(def, z)
    local out, open = {}, false
    if def == nil then return out, open end
    local id = def:getIDString()
    local function inside(sq)
        local d = sq:getBuildingDef()
        return d ~= nil and d:getIDString() == id
    end
    for x = def:getX() - 1, def:getX2() - 1 do
        for y = def:getY() - 1, def:getY2() - 1 do
            for _, kind in ipairs({ "W", "N" }) do
                local e = edgeAt(x, y, z, kind)
                if e ~= nil and inside(e.a) ~= inside(e.b) then
                    local w = e.a:getWindowTo(e.b)
                    if w ~= nil then
                        out[#out + 1] = { w = w, key = e.key }
                        if w:isSmashed() or w:isDestroyed() then open = true end
                    elseif e.a:getWindowFrameTo(e.b) ~= nil then
                        open = true
                    end
                end
            end
        end
    end
    return out, open
end

-- LK04-T20 site: free single exterior door of a building without a home (pickHomeDoor), lane from inside, and no
-- broken window or bare frame in the building (its doors and windows can all be shut).
local function findTrappedSite(p)
    local site = findSiteFrom(p, pickHomeDoor, true)
    if site == nil then return nil end
    local def = site.e.a:getBuildingDef()
    local _, open = exteriorWindows(def, site.e.a:getZ())
    if open then return nil end
    return site
end

-- LK04-T20 (campaign MP of 2026-10-15): a npc that belongs to no group stands in a house that is the home of another
-- group, every exterior door of the house closed and locked and every exterior window closed: no door or window it
-- would take by the usual rules (home of another group). Refused at the door, the move gets the last resort of the
-- authority (LK17-T01, LivingKnox.Detour: door of the other home opened from inside, or a locked window): the
-- directive carries the last resort mark, the body leaves the house and arrives.
local trappedRun
local function trappedTest(t)
    local o = O()
    t:ok(o ~= nil and DT() ~= nil and o.onRefusal ~= nil and GR() ~= nil and GR().isReady(),
        "LivingKnox.Detour (detour after a refusal) or LivingKnox.Groups is not ready here")
    atSite(t, "free single exterior door of a building without a home, lane from inside, no broken window",
        findTrappedSite, trappedRun)
end
trappedRun = function(t, site)
    local o = O()
    local door, e = site.obj, site.e
    local inside = e.a
    local def = inside:getBuildingDef()
    local z = inside:getZ()
    local doors = exteriorDoors(def, z, door)
    local windows = exteriorWindows(def, z)
    print("[LKT] trapped: door " .. e.key .. ", start " .. site.start:getX() .. "," .. site.start:getY()
        .. ", target " .. site.target:getX() .. "," .. site.target:getY() .. ", " .. #doors .. " other door(s), "
        .. #windows .. " window(s)")
    local id = spawnAt(t, site.start)
    keepDoors(t, { { door = door, key = e.key } })
    keepDoors(t, doors)
    for _, we in ipairs(windows) do keepWindow(t, we.w, id) end
    local g = GR().create({ type = "settlers", name = "Trapped",
        home = { x = inside:getX(), y = inside:getY(), z = z } })   -- home of ANOTHER group: the npc is no member
    t:ok(g ~= nil, "group not created")
    t:defer(function() GR().remove(g.id) end, "remove the group")
    local H = LivingKnox.Homes
    if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
    o.refreshHomes(true)
    t:waitUntil(K.standing(id), STAND_MS, function(t2)
        onStartSide(t2, id, site)
        o.setDoor(door, false, true)
        for _, d in ipairs(doors) do o.setDoor(d.door, false, true) end
        for _, we in ipairs(windows) do setOpen(we.w, id, false) end
        t2:ok(not o.isOpen(door) and o.isLocked(door), "door " .. e.key .. " not closed and locked")
        t2:eq(nil, o.groupOf(id), "group of the npc")
        local last0 = DT().stats.lastResorts or 0
        trip(t2, id, site.target, "trapped in the home of another group", false, function(t3)
            local entry = D().entries and D().entries[id] or nil
            measure(string.format("trapped: %d last resort(s) given, %d step(s)", (DT().stats.lastResorts or 0)
                - last0, entry and type(entry.w) == "table" and #entry.w or 0))
            t3:ok(entry ~= nil and entry.lr == true, "move without the last resort mark")
            local zb2 = B().find(id)
            local sq = zb2 and zb2:getCurrentSquare() or nil
            local d2 = sq and sq:getBuildingDef() or nil
            t3:ok(sq ~= nil and (d2 == nil or d2:getIDString() ~= def:getIDString()),
                "body still in the house at the end")
            measure(string.format("trapped: door %s open %s locked %s", e.key, tostring(o.isOpen(door)),
                tostring(o.isLocked(door))))
        end)
    end, "npc still on the floor")
end

-- Site helpers, checked by the bench (tests/test_lk_obstacles.py, LK04-T08).
RST.LKTraversal = RST.LKTraversal or {}
RST.LKTraversal.pickInteriorDoor = pickInteriorDoor
RST.LKTraversal.pickHomeDoor = pickHomeDoor
RST.LKTraversal.findSite = findSite
RST.LKTraversal.findSiteFrom = findSiteFrom
RST.LKTraversal.findDetourSite = findDetourSite
RST.LKTraversal.pickWindow = pickWindow
RST.LKTraversal.pickFence = pickFence
RST.LKTraversal.rawPick = rawPick
RST.LKTraversal.doorsByLane = doorsByLane
RST.LKTraversal.laneSquares = laneSquares
RST.LKTraversal.refusedDoorsByLane = refusedDoorsByLane
RST.LKTraversal.pickFenceByRefusedDoor = pickFenceByRefusedDoor
RST.LKTraversal.setOpen = setOpen
RST.LKTraversal.crossed = crossed
RST.LKTraversal.onLane = onLane
RST.LKTraversal.stairsEnds = stairsEnds
-- LK04-T02: helpers of the trips, shared with lk.doors (RST_LKDoors.lua).
RST.LKTraversal.atSite = atSite
RST.LKTraversal.edgeAt = edgeAt
RST.LKTraversal.lane = lane
RST.LKTraversal.spawnAt = spawnAt
RST.LKTraversal.keepDoors = keepDoors
RST.LKTraversal.isolate = isolate
RST.LKTraversal.onStartSide = onStartSide
RST.LKTraversal.exteriorDoors = exteriorDoors
RST.LKTraversal.trip = trip

-- LK17-T01: locked window on the game path, detour through a door of the house given by the authority at the refusal.
local detourRun
local function detourTest(t)
    t:ok(O() ~= nil and DT() ~= nil and O().onRefusal ~= nil,
        "LivingKnox.Detour (detour after a refusal) is not loaded here")
    atSite(t, "window with a free lane and a door of the house for a detour", findDetourSite, detourRun)
end
detourRun = function(t, site)
    local o, dt = O(), DT()
    local de = site.doorEdges[1]
    print("[LKT] locked window, detour: window " .. site.e.key .. ", door " .. tostring(de.key) .. ", start "
        .. site.start:getX() .. "," .. site.start:getY() .. ", target " .. site.target:getX() .. ","
        .. site.target:getY())
    local id = spawnAt(t, site.start)
    local w = site.obj
    keepWindow(t, w, id)
    local doors = doorEdgesNear(site.e.a, dt.RADIUS or 15)
    local kept = {}
    for _, d in ipairs(doors) do
        local door = d.a:getDoorTo(d.b)
        if door ~= nil then kept[#kept + 1] = { door = door, key = d.key } end
    end
    keepDoors(t, kept)
    t:waitUntil(K.standing(id), STAND_MS, function(t2)
        onStartSide(t2, id, site)
        setOpen(w, id, false)
        w:setIsLocked(true)
        t2:ok(w:isLocked() and not w:IsOpen(), "window not closed and locked")
        groupOf(t2, id, "settlers")
        local detours, refusedW = dt.stats.detours or 0, o.stats.windowsRefused or 0
        local watched = { site.e }
        for _, d in ipairs(doors) do watched[#watched + 1] = d end
        trip(t2, id, site.target, "locked window, detour", false, function(t3, info, e)
            measure(string.format("locked window, detour: %d step(s), %d detour(s), %d window refusal(s)",
                e and type(e.w) == "table" and #e.w or 0, (dt.stats.detours or 0) - detours,
                (o.stats.windowsRefused or 0) - refusedW))
            t3:ok((dt.stats.detours or 0) > detours, "no detour given by the authority")
            t3:ok(e ~= nil and type(e.w) == "table" and #e.w >= 2, "move without the detour waypoints")
            local r = o.lastRefused
            t3:eq(site.e.key, r and r.key, "edge of the refusal")
            t3:eq("locked window", r and r.why, "reason of the refusal")
            if isServer() then
                t3:ok(not info.through[site.e.key], "the body went through the window " .. site.e.key)
            else
                t3:ok(info.seen.climbwindow ~= true, "climbwindow state seen")
            end
            local via = false
            for _, d in ipairs(doors) do via = via or info.through[d.key] == true end
            t3:ok(via, "the body never went through a door (" .. #doors .. " near the window)")
            t3:ok(not w:IsOpen() and w:isLocked() and not w:isSmashed(), "window changed")
        end, nil, watched)
    end, "npc still on the floor")
end

RST.suite("lk.traversal", { tags = { "world", "server" }, testTimeoutMs = 300000, timeoutMs = 2400000 }, function(s)
    s.test("open window: climbed through, no toggle", windowTest(function(t, w, id)
        if w:isSmashed() then t:skip("the nearest window is broken") end
        setOpen(w, id, true)
        t:ok(w:IsOpen(), "window not open")
    end, "open window", false, function(t, w, info, e, ctx)
        t:eq(ctx.toggles, O().stats.windowToggles or 0, "window toggles by the authority")
        if not isServer() then t:ok(info.seen.climbwindow == true, "climbwindow state never seen") end
    end, true), { timeoutMs = 300000 })

    s.test("broken window: climbed through, no toggle", windowTest(function(t, w, id)
        setOpen(w, id, false)
        if not w:isSmashed() then w:setSmashed(true) end
        w:getSquare():RecalcProperties()
        if isServer() then w:sync() end
        t:ok(w:isSmashed(), "window not broken")
    end, "broken window", false, function(t, w, info, e, ctx)
        t:eq(ctx.toggles, O().stats.windowToggles or 0, "window toggles by the authority")
        if not isServer() then t:ok(info.seen.climbwindow == true, "climbwindow state never seen") end
    end, true), { timeoutMs = 300000 })

    s.test("low fence: climbed over", function(t0)
        atSite(t0, "low fence with a free lane and no door next to it",
            function(p) return findSite(p, rawPick(pickFence)) end, function(t, site)
        print("[LKT] low fence " .. site.e.key)
        local id = spawnAt(t, site.start)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            onStartSide(t2, id, site)
            trip(t2, id, site.target, "low fence", false, function(t3, info)
                if not isServer() then t3:ok(info.seen.climbfence == true, "climbfence state never seen") end
            end, site.e, nil, true)
        end, "npc still on the floor")
        end, true)
    end, { timeoutMs = 300000 })

    s.test("refused door next to a low fence: around it, never through it", function(t0)
        t0:ok(O() ~= nil and DT() ~= nil and DT().doorRefusal ~= nil and O().onRefusal ~= nil,
            "LivingKnox.Detour (detour after a refusal) is not loaded here")
        atSite(t0, "low fence with a free lane next to a refused door",
            function(p) return findSite(p, pickFenceByRefusedDoor) or planFenceByDoor(p) end, function(t, site)
        local o = O()
        if site.build ~= nil then buildFence(t, site) end
        refuseDoorNextTo(t, site)
        local doors = refusedDoorsByLane(site.e)
        t:ok(#doors > 0, "no refused door next to the low fence " .. site.e.key)
        local watch, keys = {}, {}
        for i, d in ipairs(doors) do
            -- LK17-T01: the game path climbs the fence right next to the door: a crossing counts only within the
            -- span of the door itself (half a square from its middle), not one square beside it.
            d.e.lat = 0.5
            watch[i], keys[i] = d.e, d.key
        end
        print("[LKT] refused door next to a low fence: fence " .. site.e.key .. ", refused door(s) "
            .. table.concat(keys, " ") .. ", start " .. site.start:getX() .. "," .. site.start:getY() .. ", target "
            .. site.target:getX() .. "," .. site.target:getY())
        local id = spawnAt(t, site.start)
        keepDoors(t, doors)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            onStartSide(t2, id, site)
            local before = {}
            for i, d in ipairs(doors) do
                before[i] = tostring(o.isOpen(d.door)) .. " " .. tostring(o.isLocked(d.door))
            end
            local refused, detoured = o.stats.refused or 0, o.stats.detoured or 0
            trip(t2, id, site.target, "refused door next to a low fence", false, function(t3, info, e)
                measure(string.format("refused door next to a low fence: %d step(s), through the fence %s, "
                    .. "%d refusal(s), %d detour(s)", e and type(e.w) == "table" and #e.w or 0,
                    tostring(info.through[site.e.key] == true), (o.stats.refused or 0) - refused,
                    (o.stats.detoured or 0) - detoured))
                for i, d in ipairs(doors) do
                    t3:ok(not info.through[d.key], "the body went through the refused door " .. d.key)
                    t3:eq(before[i], tostring(o.isOpen(d.door)) .. " " .. tostring(o.isLocked(d.door)),
                        "state of the refused door " .. d.key)
                end
                -- LK17-T01: the game path may meet the refused door; every refusal must have given a detour.
                t3:eq((o.stats.refused or 0) - refused, (o.stats.detoured or 0) - detoured,
                    "refusals by the authority without a detour")
            end, nil, watch)
        end, "npc still on the floor")
        end, true, 2 * PLACE_TRIES)
    end, { timeoutMs = 300000 })

    s.test("stairs: up then down", function(t0)
        atSite(t0, "stairs with a free floor square at both ends (bottom joined to the stairs by open edges)",
            function(p)
                local st, bo, tp = stairsEnds(p)
                if st == nil or bo == nil or tp == nil then return nil end
                return { stairs = st, bottom = bo, top = tp, z = math.floor(p:getZ()) }
            end, function(t, site)
        local pz = site.z
        local stairs, bottom, top = site.stairs, site.bottom, site.top
        print("[LKT] stairs at " .. stairs:getX() .. "," .. stairs:getY() .. "," .. pz .. ", bottom "
            .. bottom:getX() .. "," .. bottom:getY() .. ", top " .. top:getX() .. "," .. top:getY() .. "," .. (pz + 1))
        local id = spawnAt(t, bottom)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local function level()
                local z = B().find(id)
                return z and math.floor(z:getZ())
            end
            trip(t2, id, top, "stairs up", false, function(t3)
                t3:waitQuiet(function() return level() == pz + 1 end, LEVEL_MS, function(t3b)
                    t3b:eq(pz + 1, level(), "level after the climb")
                    trip(t3b, id, bottom, "stairs down", false, function(t4)
                        t4:waitQuiet(function() return level() == pz end, LEVEL_MS, function(t4b)
                            t4b:eq(pz, level(), "level after the descent")
                        end, "level after the descent")
                    end)
                end, "level after the climb")
            end)
        end, "npc still on the floor")
        end)
    end, { timeoutMs = 350000 })

    local function closedWindow(gtype)
        return windowTest(function(t, w, id)
            if w:isSmashed() then t:skip("the nearest window is broken") end
            setOpen(w, id, false)
            w:setIsLocked(false)
            t:ok(not w:IsOpen(), "window not closed")
            groupOf(t, id, gtype)
            return { id = id }
        end, "closed window (" .. gtype .. ")", false, function(t, w, info, e, ctx, was, site)
            if not isServer() then t:ok(info.seen.climbwindow == true, "climbwindow state never seen") end
            t:ok(not w:isSmashed(), "window broken")
            t:waitUntil(function() return not w:IsOpen() end, CLOSE_MS, function(t2)
                -- LK04-T18: closed right behind the body (2026-10-13: closed with the body about 3 squares away).
                local lc = O().lastClose
                local mine = lc ~= nil and lc.key == site.e.key and lc.id == ctx.id
                measure(string.format("closed window (%s): closed behind the body, %d toggle(s), body %s square(s) "
                    .. "from the window at the toggle, facing it %s, gesture %s", gtype,
                    (O().stats.windowToggles or 0) - ctx.toggles, mine and string.format("%.2f", lc.d) or "?",
                    tostring(mine and lc.facing), tostring(mine and lc.gesture)))
                t2:eq(ctx.toggles + 2, O().stats.windowToggles or 0, "window toggles by the authority (open, close)")
                t2:eq(ctx.closed + 1, O().stats.windowsClosed or 0, "windows closed behind by the authority")
                t2:ok(not w:isSmashed(), "window broken")
                t2:ok(mine, "window not closed by this npc (LivingKnox.Obstacles.lastClose)")
                if mine then
                    t2:ok(lc.d <= (O().ACT_REACH or 1.5), string.format("window closed from %.2f squares away", lc.d))
                    t2:ok(lc.facing == true, "body not facing the window at the toggle")
                    t2:ok(lc.gesture == true, "window closed without the gesture")
                end
            end, "window not closed behind the body")
        end)
    end

    s.test("closed window: opened by a settler, closed behind, never broken", closedWindow("settlers"),
        { timeoutMs = 300000 })

    s.test("closed window: opened by a raider, closed behind, never broken", closedWindow("raiders"),
        { timeoutMs = 300000 })

    s.test("locked window: refused, left closed and unbroken", windowTest(function(t, w, id)
        if w:isSmashed() then t:skip("the nearest window is broken") end
        setOpen(w, id, false)
        w:setIsLocked(true)
        t:ok(w:isLocked() and not w:IsOpen(), "window not closed and locked")
        groupOf(t, id, "settlers")
        -- A detour through a door of the house is the right move (its own test below): cut here, so that the refusal
        -- itself is what this test sees.
        noDetour(t)
    end, "locked window", true, function(t, w, info, e, ctx, was, site)
        t:eq(ctx.toggles, O().stats.windowToggles or 0, "window toggles by the authority")
        t:ok(not w:IsOpen() and w:isLocked() and not w:isSmashed(), "window changed")
        t:eq(ctx.refused + 1, O().stats.windowsRefused or 0, "window refusals by the authority")
        local r = O().lastRefused
        t:eq(site.e.key, r and r.key, "edge of the refusal")
        t:eq("locked window", r and r.why, "reason of the refusal")
    end), { timeoutMs = 300000 })

    s.test("locked window: refused, detour through a door of the house", detourTest, { timeoutMs = 300000 })

    s.test("open exterior door of a home: closed and locked on arrival, left open once reopened", function(tt)
        local o0 = O()
        tt:ok(o0 ~= nil and o0.shutHome ~= nil and GR() ~= nil and GR().isReady(),
            "LivingKnox.Obstacles.shutHome or LivingKnox.Groups is not ready here")
        atSite(tt, "free single exterior door of a building without a home", findHomeDoor, function(t, site)
        local o = O()
        local door, e, inside = site.door, site.e, site.inside
        local others = exteriorDoors(inside:getBuildingDef(), inside:getZ(), door)
        print("[LKT] home door " .. e.key .. ", home " .. inside:getX() .. "," .. inside:getY() .. "," .. inside:getZ()
            .. ", " .. #others .. " other exterior door(s) in the loaded area")
        keepDoors(t, { { door = door, key = e.key } })
        keepDoors(t, others)   -- the arrival also closes the other open exterior doors of the house
        o.setDoor(door, true)
        t:ok(o.isOpen(door), "door not open")
        -- LK04-T12: locking needs a member with the key at home. A settler is spawned two squares inside the house
        -- (off the door squares), then the group is created with him: he gets the key of the building.
        local nx, ny = e.b:getX() - e.a:getX(), e.b:getY() - e.a:getY()
        local dir = (inside == e.b) and 1 or -1
        local member = spawnAt(t, cell():getGridSquare(inside:getX() + 2 * dir * nx, inside:getY() + 2 * dir * ny,
            inside:getZ()) or inside)
        local shut0 = o.stats.shut or 0
        isolate(t, member)   -- no chore walk through the door under test
        local g = GR().create({ type = "settlers", name = "HomeShut",
            home = { x = inside:getX(), y = inside:getY(), z = inside:getZ() } })   -- new home in the loaded area
        t:ok(g ~= nil, "group not created")
        t:defer(function() GR().remove(g.id) end, "remove the group")
        local H = LivingKnox.Homes
        if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
        t:ok(GR().addMember(g.id, { role = "worker", npc = member }) ~= nil, "member not added")
        o.refreshHomes(true)
        local t0 = getTimestampMs()
        t:waitUntil(function() return not o.isOpen(door) end, o.SHUT_DELAY_MS + 10000, function(t2)
            measure(string.format("home door closed %d ms after the arrival", getTimestampMs() - t0))
            -- This door closed and locked; other open exterior doors of the house may be closed by the same arrival
            -- (2026-10-11 14:58: "2 open exterior door(s) of its home closed and locked"): counted, not required.
            t2:ok(o.isLocked(door), "door closed but not locked")
            local shut1 = o.stats.shut or 0
            measure(string.format("home door: %d door(s) closed by the arrival", shut1 - shut0))
            t2:ok(shut1 >= shut0 + 1 and shut1 <= shut0 + 1 + #others,
                string.format("doors closed on arrival: %d, expected 1 to %d", shut1 - shut0, 1 + #others))
            o.setDoor(door, true)   -- reopened, as a player would: left open until the next arrival
            t2:sleep(o.SHUT_DELAY_MS + 2 * o.SHUT_RETRY_MS, function(t3)
                t3:ok(o.isOpen(door) and not o.isLocked(door),
                    "door reopened after the arrival closed again (no fight with the player)")
            end)
        end, "open exterior door of the home not closed")
        end)
    end, { timeoutMs = 300000 })

    s.test("locked home door: opened with the settler's key, locked behind", keyTest(true), { timeoutMs = 300000 })

    s.test("locked home door: refused without the key", keyTest(false), { timeoutMs = 300000 })

    s.test("locked home door: opened from inside without the key", keyTest(false, true), { timeoutMs = 300000 })

    s.test("locked interior home door: opened from inside, relocked with the home key", interiorKeyTest(true),
        { timeoutMs = 300000 })

    s.test("locked interior home door: opened from inside, left unlocked without the home key",
        interiorKeyTest(false), { timeoutMs = 300000 })

    s.test("npc trapped in the home of another group: out by the last resort", trappedTest,
        { timeoutMs = 300000 })
end)
