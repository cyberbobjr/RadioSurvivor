--[[
RST_PeerChecksLK2 - client checks and player actions of the second client for Living Knox suites (E01-T16:
LK02-T04, LK02-T07, LK02-T08, LK03-T01, LK04-T03, LK07-T05, LK11-T08), asked by the authority through RST.Steps.
Development mod only. Load with: require "RST/RST_PeerChecksLK2" (shared: the suites that ask these steps require it,
so every machine that loads the suites registers the handlers; they run on the clients and, in solo, in the same Lua
state). One OnTick sampler (clients and solo), subscribed at the first watcher, idle while nothing is watched.
Every body is the local copy found by its npc id in LivingKnox.Anim.knownBodies().

Client handlers (RST.Steps.on)
    lk.contact      { npc, ms, maxDist }: during ms, at each tick, the copy of npc here never targets the local player,
                    is never in an attack or lunge state, never eats; the health of the local player never drops; the
                    copy stays within maxDist squares (contact kept). Data: samples, target, attack, eat, health0,
                    minHealth, maxDist, near (samples within maxDist).
    lk.track        { phase = "begin", key, npc, edge = { bx, by, nx, ny } }: watches the copy of npc at each tick:
                    side of the edge (b square bx, by, normal nx, ny: a < 0 start side, a >= 0 far side), the first
                    crossing to the far side and its lateral distance from the middle of the edge, samples, the last
                    position. PASS "armed".
                    { phase = "end", key, target = { x, y, z }, tol, cross = true | false | nil }: polled until the
                    copy stands within tol of target on its level (no target: at once); cross = true: the copy was
                    seen crossing through the edge (lateral <= CROSS_LATERAL); false: never on the far side. Data:
                    crossed, lateral, samples, x, y, z. The watcher is removed.
    lk.probe        { phase = "start" | "stop", key }: RST.LKProbe on this machine (cost of the engine OnTick
                    subscribers, Living Knox messages) from start to stop; stop returns the probe lines and the pose
                    relay delay of LivingKnox.Presentation in data { lines, relay } (observer cost, LK02-T08 section 6).
    rst.shot        { name, settleMs }: after settleMs, takeScreenshot("<name>-<account>.png") (Zomboid/Screenshots,
                    collected by the launcher). Data: file.
    corpse.drag     { x, y, z, r, holdMs }: the local player grabs the nearest corpse within r squares of x, y, z
                    (ISGrabCorpseAction, as the vanilla grab key), drags it for holdMs, then lets it go
                    (setDoGrappleLetGo, as the key pressed again). PASS once released; data: draggedMs.
    lk.trade.window { npc, give, take, menu }: the "Trade" option of the context menu of the local player
                    (LivingKnox.TradeView.fill on the square of the copy of npc: option text and target checked), then
                    the option as a click calls it (TradeView.open: window and "open" request); once the offer is
                    shown, every given item of type give and the item id take are ticked and proposed
                    (TradeView.propose). Data: { ok, reason, line } of the answer of the server. FAIL: no option, no
                    offer, item take not offered here, no answer.
Kahlua: no next(), no goto; nothing suspends. Every handler is pcall-protected by RST.Steps.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecksLK2 = RST.PeerChecksLK2 or {}
local P2 = RST.PeerChecksLK2
local Steps = RST.Steps

P2.CROSS_LATERAL = 1.5
P2.tracks = P2.tracks or {}     -- key -> track watcher
P2.contacts = P2.contacts or {} -- running lk.contact samplers (by step seq)
P2.probes = P2.probes or {}     -- key -> probe

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function bodyOf(npc)
    local A = LivingKnox and LivingKnox.Anim
    if A == nil or type(A.knownBodies) ~= "function" or type(npc) ~= "string" then return nil end
    return A.knownBodies()[npc]
end
P2.bodyOf = bodyOf

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    return safe(getPlayer)
end

local function lower(s) return string.lower(tostring(s)) end

-- ---------------------------------------------------------------- tick sampler

local function sampleTrack(w)
    local z = bodyOf(w.npc)
    if z == nil then return end
    local x, y = z:getX(), z:getY()
    w.samples = w.samples + 1
    w.last = { x = x, y = y, z = z:getZ() }
    local e = w.edge
    if e == nil then return end
    local a = (x - e.bx) * e.nx + (y - e.by) * e.ny
    local mx, my = e.bx + 0.5 * e.ny, e.by + 0.5 * e.nx
    local lat = math.abs((x - mx) * e.ny + (y - my) * e.nx)
    if a >= 0 then w.far = true end
    if w.prev ~= nil and w.prev.a < 0 and a >= 0 and not w.crossed then
        w.crossed = true
        w.lateral = math.min(w.prev.lat, lat)
    end
    w.prev = { a = a, lat = lat }
end

function P2.tick()
    local any = false
    for _, w in pairs(P2.tracks) do
        any = true
        sampleTrack(w)
    end
    if not any and P2._ticking and type(Events) == "table" and Events.OnTick then
        Events.OnTick.Remove(P2._ticking)
        P2._ticking = nil
    end
end

local function onTick() RST.PeerChecksLK2.tick() end

local function attach()
    if P2._ticking or type(Events) ~= "table" or Events.OnTick == nil then return end
    Events.OnTick.Add(onTick)
    P2._ticking = onTick
end

-- ---------------------------------------------------------------- lk.contact

Steps.on("lk.contact", function(args)
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    local ms, maxDist = tonumber(args.ms) or 60000, tonumber(args.maxDist) or 3
    local bd = p:getBodyDamage()
    local s = { samples = 0, near = 0, target = 0, attack = 0, eat = 0, health0 = bd:getOverallBodyHealth(),
        maxDist = 0, absent = 0 }
    s.minHealth = s.health0
    local t0 = getTimestampMs()
    return function(ctx)
        local z = bodyOf(args.npc)
        if z == nil then
            s.absent = s.absent + 1
        else
            s.samples = s.samples + 1
            if z:getTarget() == p then s.target = s.target + 1 end
            if z:getEatBodyTarget() ~= nil then s.eat = s.eat + 1 end
            local st = lower(z:getCurrentStateName())
            if string.find(st, "attack", 1, true) or string.find(st, "lunge", 1, true) then s.attack = s.attack + 1 end
            local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
            local d = math.sqrt(dx * dx + dy * dy)
            if d > s.maxDist then s.maxDist = d end
            if d <= maxDist then s.near = s.near + 1 end
        end
        local h = bd:getOverallBodyHealth()
        if h < s.minHealth then s.minHealth = h end
        if getTimestampMs() - t0 < ms and not ctx.final then return nil end
        local text = string.format("%d ms at contact: %d sample(s) (%d within %.1f squares, %d without a copy), "
            .. "target %d, attack/lunge %d, eat %d, health %.1f -> min %.1f, max distance %.1f", getTimestampMs() - t0,
            s.samples, s.near, maxDist, s.absent, s.target, s.attack, s.eat, s.health0, s.minHealth, s.maxDist)
        if s.samples == 0 then return Steps.fail("no copy of " .. tostring(args.npc) .. " here: " .. text, s) end
        if s.target > 0 or s.attack > 0 or s.eat > 0 or s.minHealth < s.health0 - 0.01 then
            return Steps.fail(text, s)
        end
        if s.near * 2 < s.samples then return Steps.fail("contact not kept: " .. text, s) end
        return Steps.pass(text, s)
    end
end)

-- ---------------------------------------------------------------- lk.track

Steps.on("lk.track", function(args)
    local key = tostring(args.key)
    if args.phase == "begin" then
        local e = type(args.edge) == "table" and args.edge or nil
        P2.tracks[key] = { npc = args.npc, edge = e and { bx = e.bx, by = e.by, nx = e.nx, ny = e.ny } or nil,
            samples = 0, crossed = false, far = false }
        attach()
        local z = bodyOf(args.npc)
        return Steps.pass("watching " .. tostring(args.npc) .. (z and "" or " (no copy here yet)"))
    end
    local w = P2.tracks[key]
    if w == nil then return Steps.fail("no watcher " .. key .. " on this client (begin missed)") end
    local tol = tonumber(args.tol)
    local target = type(args.target) == "table" and args.target or nil
    return function(ctx)
        sampleTrack(w)
        local at, dist = true, nil
        if target ~= nil and tol ~= nil then
            if w.last == nil then
                at = false
            else
                local dx, dy = w.last.x - target.x, w.last.y - target.y
                dist = math.sqrt(dx * dx + dy * dy)
                at = dist <= tol and math.floor(w.last.z) == math.floor(target.z or 0)
            end
        end
        if not at and not ctx.final then return nil end
        P2.tracks[key] = nil
        local data = { crossed = w.crossed, far = w.far, lateral = w.lateral, samples = w.samples,
            x = w.last and w.last.x, y = w.last and w.last.y, z = w.last and w.last.z, dist = dist }
        local text = string.format("%s: %d sample(s), crossed %s (lateral %s), on the far side %s, copy at %s%s",
            tostring(w.npc), w.samples, tostring(w.crossed), w.lateral and string.format("%.2f", w.lateral) or "-",
            tostring(w.far), w.last and string.format("%.1f,%.1f,%d", w.last.x, w.last.y, math.floor(w.last.z)) or "?",
            dist and string.format(", %.1f squares from the target", dist) or "")
        if w.samples == 0 then return Steps.fail("no copy of " .. tostring(w.npc) .. " seen here", data) end
        if not at then return Steps.fail("copy never at the target: " .. text, data) end
        if args.cross == true and not (w.crossed and (w.lateral or 99) <= P2.CROSS_LATERAL) then
            return Steps.fail("copy not seen going through the obstacle: " .. text, data)
        end
        if args.cross == false and w.far then
            return Steps.fail("copy seen on the far side of the obstacle: " .. text, data)
        end
        return Steps.pass(text, data)
    end
end)

-- ---------------------------------------------------------------- lk.probe

Steps.on("lk.probe", function(args)
    local key = tostring(args.key)
    local ok, Probe = pcall(function()
        require "RST/RST_LKProbe"
        return RST.LKProbe
    end)
    if not ok or type(Probe) ~= "table" then return Steps.fail("RST_LKProbe not loaded here") end
    if args.phase == "start" then
        local probe, why = Probe.start()
        if probe == nil then return Steps.fail("probe not started: " .. tostring(why)) end
        P2.probes[key] = probe
        return Steps.pass("probe started")
    end
    local probe = P2.probes[key]
    if probe == nil then return Steps.fail("no probe " .. key .. " on this client (start missed)") end
    P2.probes[key] = nil
    local summary = Probe.stop(probe)
    local lines = summary and Probe.lines(summary) or {}
    local Pr = LivingKnox and LivingKnox.Presentation
    local relay = nil
    if Pr ~= nil and type(Pr.stats) == "table" then
        relay = string.format("pose relay delay last %s ms, max %s ms, mean %s ms over %s pose(s)",
            tostring(Pr.stats.lastDelay), tostring(Pr.stats.maxDelay),
            tostring(type(Pr.meanDelay) == "function" and math.floor(Pr.meanDelay()) or "?"), tostring(Pr.stats.samples))
    end
    return Steps.pass((lines[1] or "probe stopped") .. (relay and ("; " .. relay) or ""), { lines = lines, relay = relay })
end)

-- ---------------------------------------------------------------- rst.shot

Steps.on("rst.shot", function(args, ctx)
    if type(takeScreenshot) ~= "function" then return Steps.skip("takeScreenshot is not exposed here") end
    local name = string.gsub(tostring(args.name or "rst"), "[^%w%-_]", "_")
    local user = string.gsub(tostring(ctx.user ~= "" and ctx.user or "local"), "[^%w%-_]", "_")
    local file = name .. "-" .. user .. ".png"
    local settle = tonumber(args.settleMs) or 500
    local t0 = getTimestampMs()
    return function(c)
        if getTimestampMs() - t0 < settle and not c.final then return nil end
        local okShot, err = pcall(takeScreenshot, file)
        if not okShot then return Steps.fail("takeScreenshot failed: " .. tostring(err)) end
        return Steps.pass("screenshot " .. file, { file = file })
    end
end)

-- ---------------------------------------------------------------- corpse.drag

local function nearestCorpse(x, y, z, r)
    local best, bestD
    for dy = -r, r do
        for dx = -r, r do
            local sq = getCell() and getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = 0, (list and list:size() or 0) - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") then
                    local d = dx * dx + dy * dy
                    if bestD == nil or d < bestD then best, bestD = o, d end
                end
            end
        end
    end
    return best
end

Steps.on("corpse.drag", function(args)
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    if ISGrabCorpseAction == nil or ISTimedActionQueue == nil then return Steps.fail("ISGrabCorpseAction not loaded") end
    local body = nearestCorpse(math.floor(args.x), math.floor(args.y), math.floor(args.z or 0), tonumber(args.r) or 2)
    if body == nil then return Steps.fail("no corpse within " .. tostring(args.r) .. " squares here") end
    -- Same queue as the vanilla grab of the context menu (ISWorldObjectContextMenu.lua:1493-1500): walk next to the
    -- corpse first (ISGrabCorpseAction:isValid needs getSquare():canReachTo of the corpse square: MP campaign of
    -- 2026-10-15, "Cannot reach destination corpseBody" from a client standing a few squares away), then both hands
    -- free, then the grab.
    if ISPathFindAction ~= nil and ISPathFindAction.pathToGrabCorpse ~= nil then
        ISTimedActionQueue.add(ISPathFindAction:pathToGrabCorpse(p, body))
    end
    local primary, secondary = p:getPrimaryHandItem(), p:getSecondaryHandItem()
    if primary ~= nil and ISUnequipAction ~= nil then
        ISTimedActionQueue.add(ISUnequipAction:new(p, primary, 50))
    end
    if secondary ~= nil and secondary ~= primary and ISUnequipAction ~= nil then
        ISTimedActionQueue.add(ISUnequipAction:new(p, secondary, 50))
    end
    ISTimedActionQueue.add(ISGrabCorpseAction:new(p, body))
    local holdMs = tonumber(args.holdMs) or 2000
    local st = { phase = "grab" }
    return function(ctx)
        local now = getTimestampMs()
        if st.phase == "grab" and p:isDraggingCorpse() then
            st.phase, st.at = "hold", now
        elseif st.phase == "hold" and now - st.at >= holdMs then
            p:setDoGrappleLetGo()
            st.phase, st.released = "release", now
        elseif st.phase == "release" and not p:isDraggingCorpse() then
            return Steps.pass("corpse dragged " .. (st.released - st.at) .. " ms then released",
                { draggedMs = st.released - st.at })
        end
        if ctx.final then return Steps.fail("corpse drag stopped at the phase " .. st.phase) end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.trade.window

local function stubContext()
    local ctx = { options = {} }
    function ctx:addOption(text, target, fn, ...)
        local o = { name = text, target = target, fn = fn, args = { ... } }
        self.options[#self.options + 1] = o
        return o
    end
    return ctx
end

Steps.on("lk.trade.window", function(args)
    local V = LivingKnox and LivingKnox.TradeView
    if V == nil or type(V.open) ~= "function" then return Steps.fail("LivingKnox.TradeView not loaded here") end
    local z = bodyOf(args.npc)
    if z == nil then return Steps.fail("no copy of " .. tostring(args.npc) .. " here") end
    local st = { phase = "offer" }
    if args.menu ~= false then
        local sq = z:getSquare()
        local objs = sq and sq:getObjects()
        local first = objs and objs:size() > 0 and objs:get(0) or nil
        if first == nil then return Steps.fail("no object on the square of the copy to click") end
        local ctx = stubContext()
        V.fill(0, ctx, { first }, false)
        local want = getText("IGUI_LK_Trade_Menu")
        local option = nil
        for _, o in ipairs(ctx.options) do
            if o.name == want and o.target == args.npc then option = o end
        end
        if option == nil then
            return Steps.fail("no option '" .. tostring(want) .. "' for " .. tostring(args.npc) .. " in the context menu ("
                .. #ctx.options .. " option(s))")
        end
        option.fn(option.target)
    else
        V.open(args.npc)
    end
    local receive = V.receive
    return function(c)
        local s = V.state
        if st.phase == "offer" then
            if s.pending == nil and s.offer ~= nil then
                local gives, take = 0, false
                for _, e in ipairs(s.offer.give or {}) do
                    if e.t == args.give then
                        V.toggle("give", e.i)
                        gives = gives + 1
                    end
                end
                for _, e in ipairs(s.offer.take or {}) do
                    if e.i == args.take then
                        V.toggle("take", e.i)
                        take = true
                    end
                end
                if gives == 0 or not take then
                    V.receive = receive
                    return Steps.fail("offer here: " .. gives .. " " .. tostring(args.give) .. " to give, item "
                        .. tostring(args.take) .. " offered " .. tostring(take))
                end
                V.receive = function(reply)
                    if type(reply) == "table" and reply.op == "propose" then st.reply = reply end
                    return receive(reply)
                end
                st.n = V.propose()
                if st.n == nil then
                    V.receive = receive
                    return Steps.fail("proposal not sent: " .. tostring(s.status))
                end
                st.phase = "answer"
            elseif s.pending == nil and s.offer == nil then
                V.receive = receive
                return Steps.fail("no offer from the group: " .. tostring(s.status))
            end
        elseif st.phase == "answer" and st.reply ~= nil then
            V.receive = receive
            if s.window ~= nil and s.window.setVisible ~= nil then pcall(function() s.window:setVisible(false) end) end
            local r = st.reply
            return Steps.pass("proposal #" .. tostring(st.n) .. ": ok " .. tostring(r.ok) .. ", reason "
                .. tostring(r.reason), { ok = r.ok == true, reason = r.reason, line = r.line })
        end
        if c.final then
            V.receive = receive
            return Steps.fail("trade window stopped at the phase " .. st.phase .. " (status " .. tostring(s.status) .. ")")
        end
        return nil
    end
end)

return P2
