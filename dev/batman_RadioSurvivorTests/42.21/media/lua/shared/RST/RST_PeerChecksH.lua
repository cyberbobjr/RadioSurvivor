--[[
RST_PeerChecksH - client checks of the second client (E01-T16) for the Living Knox suites whose "Reste" asked what
another client sees: health view, alert cry and orientation, positions, upkeep effects. Development mod only. Load
with: require "RST/RST_PeerChecksH" (shared: the suites that ask these steps require it, so every machine that loads
the suites registers the handlers; they run on the clients and, in solo, in the same Lua state).

Client handlers (RST.Steps.on); every body is found by its npc id in LivingKnox.Anim.knownBodies() (local copy):
    lk.health.view  { npc, hp, max, tol }: LivingKnox.HealthView.get(npc) (copy received from the server, versioned;
                    solo: read on the authority) gives hp and max within tol of the authority's reference (the copy is rounded);
                    polled (the npcHealth command is not ordered with RSTStep).
    lk.alert.view   { phase = "begin" | "end", key, cries }: begin = counters of LivingKnox.AlertView noted; end = new
                    cries received here (received - duplicate - refused) = cries (one delivery each), every one of
                    them played once (played = new cries), a vanilla shout voice (View.VOICES) last; data: deltas.
    lk.facing       { bodies = { { npc, x, y }, ... }, maxDeg }: the local copy of each body faces the point x, y
                    (getDirectionAngle, degrees, 0 = +x) within maxDeg; polled until all at once or the deadline.
    lk.positions    { bodies = { { npc, x, y, z }, ... }, tol }: the local copy of each body stands within tol squares
                    of the authority's position (same level); polled (an owner sends the full state every 4 s).
    world.upkeep    { gens = { { x, y, z, fuel, cond }, ... }, clean = { { x, y, z }, ... } }: the generator of each
                    square has that fuel (0.05 l) and condition; no broken glass and no blood on the clean squares.
                    A square not loaded here: SKIP.
Authority helpers: RST.PeerChecksH.bodiesOf(npcs, extra) -> list { npc, x, y, z } read on the authority.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecksH = RST.PeerChecksH or {}
local H = RST.PeerChecksH
local Steps = RST.Steps

H.counters = H.counters or {}   -- key -> AlertView counters noted at "begin"

local function bodyOf(npc)
    local A = LivingKnox and LivingKnox.Anim
    if A == nil or type(A.knownBodies) ~= "function" or type(npc) ~= "string" then return nil end
    return A.knownBodies()[npc]
end

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- ---------------------------------------------------------------- lk.health.view

Steps.on("lk.health.view", function(args)
    local V = LivingKnox and LivingKnox.HealthView
    if V == nil or type(V.get) ~= "function" then return Steps.fail("LivingKnox.HealthView is not loaded here") end
    local want, max, tol = tonumber(args.hp), tonumber(args.max), tonumber(args.tol) or 0.01
    if want == nil then return Steps.fail("no reference health to compare") end
    local last = "no health known here for " .. tostring(args.npc)
    return function(ctx)
        local s = V.get(args.npc)
        if s ~= nil then
            -- The copy sent to the clients is rounded (1.981 here for 1.981295 on the authority, MP campaign of
            -- 2026-10-15): the maximum is compared with the same tolerance as the health.
            local ok = math.abs((tonumber(s.hp) or -1) - want) <= tol
                and (max == nil or math.abs((tonumber(s.max) or -1) - max) <= tol)
            last = "health here " .. tostring(s.hp) .. "/" .. tostring(s.max) .. ", authority " .. tostring(want) .. "/"
                .. tostring(max)
            if ok then return Steps.pass(last, { hp = s.hp, max = s.max, wounds = s.wounds }) end
        end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.alert.view

local ALERT_KEYS = { "received", "duplicate", "refused", "played" }

Steps.on("lk.alert.view", function(args)
    local V = LivingKnox and LivingKnox.AlertView
    if V == nil then return Steps.fail("LivingKnox.AlertView is not loaded on this client") end
    local key = tostring(args.key)
    if args.phase == "begin" then
        local snap = {}
        for _, k in ipairs(ALERT_KEYS) do snap[k] = V.stats[k] or 0 end
        H.counters[key] = snap
        return Steps.pass("alert view counters noted")
    end
    local snap = H.counters[key]
    if snap == nil then return Steps.fail("no snapshot " .. key .. " on this client (begin missed)") end
    local cries = tonumber(args.cries) or 0
    return function(ctx)
        local d = {}
        for _, k in ipairs(ALERT_KEYS) do d[k] = (V.stats[k] or 0) - snap[k] end
        local fresh = d.received - d.duplicate
        local voice = V.last and V.last.s or nil
        local text = "cries received " .. fresh .. " (authority " .. cries .. "), duplicates " .. d.duplicate
            .. ", refused " .. d.refused .. ", voices played " .. d.played .. ", last voice " .. tostring(voice)
        if fresh == cries and d.played == fresh and d.refused == 0 and (cries == 0 or V.VOICES[voice]) then
            H.counters[key] = nil
            return Steps.pass(text, d)
        end
        if ctx.final then
            H.counters[key] = nil
            return Steps.fail(text, d)
        end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.facing

local function angleGap(z, x, y)
    local a = safe(function() return z:getDirectionAngle() end)
    if a == nil then return nil end
    local want = math.atan2(y + 0.5 - z:getY(), x + 0.5 - z:getX()) * 180 / math.pi
    local d = math.abs(a - want)   -- Kahlua: % truncates toward zero, kept out of the way
    while d >= 360 do d = d - 360 end
    if d > 180 then d = 360 - d end
    return d
end

Steps.on("lk.facing", function(args)
    local bodies, maxDeg = args.bodies or {}, tonumber(args.maxDeg) or 45
    local last = "no body checked"
    return function(ctx)
        local parts, ok = {}, true
        for _, b in ipairs(bodies) do
            local z = bodyOf(b.npc)
            local d = z ~= nil and angleGap(z, b.x, b.y) or nil
            parts[#parts + 1] = tostring(b.npc) .. " " .. (d ~= nil and (math.floor(d + 0.5) .. " deg") or "no copy")
            if d == nil or d > maxDeg then ok = false end
        end
        last = "angle to the point: " .. table.concat(parts, ", ") .. " (max " .. maxDeg .. ")"
        if ok then return Steps.pass(last) end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.positions

Steps.on("lk.positions", function(args)
    local bodies, tol = args.bodies or {}, tonumber(args.tol) or 2
    local last = "no body checked"
    return function(ctx)
        local parts, ok = {}, true
        for _, b in ipairs(bodies) do
            local z = bodyOf(b.npc)
            if z == nil then
                ok = false
                parts[#parts + 1] = tostring(b.npc) .. " no copy"
            else
                local dx, dy = z:getX() - b.x, z:getY() - b.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local same = math.floor(z:getZ()) == math.floor(b.z or 0)
                parts[#parts + 1] = string.format("%s %.1f squares%s", tostring(b.npc), dist, same and "" or " other level")
                if dist > tol or not same then ok = false end
            end
        end
        last = "distance to the authority's position: " .. table.concat(parts, ", ") .. " (max " .. tol .. ")"
        if ok then return Steps.pass(last) end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- world.upkeep

local function generatorAt(sq)
    local g = safe(function() return sq:getGenerator() end)
    if g ~= nil then return g end
    local objects = sq:getObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local o = objects:get(i)
        if instanceof(o, "IsoGenerator") then return o end
    end
    return nil
end

Steps.on("world.upkeep", function(args)
    local gens, clean = args.gens or {}, args.clean or {}
    local cell = getCell()
    for _, s in ipairs(gens) do
        if cell == nil or cell:getGridSquare(s.x, s.y, s.z) == nil then
            return Steps.skip("square " .. s.x .. "," .. s.y .. "," .. s.z .. " not loaded here")
        end
    end
    for _, s in ipairs(clean) do
        if cell == nil or cell:getGridSquare(s.x, s.y, s.z) == nil then
            return Steps.skip("square " .. s.x .. "," .. s.y .. "," .. s.z .. " not loaded here")
        end
    end
    local last = "nothing checked"
    return function(ctx)
        local gaps = {}
        for _, s in ipairs(gens) do
            local g = generatorAt(getCell():getGridSquare(s.x, s.y, s.z))
            if g == nil then
                gaps[#gaps + 1] = "no generator at " .. s.x .. "," .. s.y
            else
                local fuel, cond = g:getFuel(), g:getCondition()
                if math.abs(fuel - s.fuel) > 0.05 or cond ~= s.cond then
                    gaps[#gaps + 1] = string.format("generator %d,%d fuel %.2f condition %d (authority %.2f, %d)", s.x,
                        s.y, fuel, cond, s.fuel, s.cond)
                end
            end
        end
        for _, s in ipairs(clean) do
            local sq = getCell():getGridSquare(s.x, s.y, s.z)
            if sq:getBrokenGlass() ~= nil then gaps[#gaps + 1] = "broken glass at " .. s.x .. "," .. s.y end
            if sq:haveBlood() then gaps[#gaps + 1] = "blood at " .. s.x .. "," .. s.y end
        end
        if #gaps == 0 then
            return Steps.pass(#gens .. " generator(s) and " .. #clean .. " clean square(s) as on the authority")
        end
        last = table.concat(gaps, "; ")
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- authority helpers

-- { npc, x, y, z } of each npc id whose body the authority holds (B = LivingKnox.Bodies).
function H.bodiesOf(npcs)
    local out = {}
    local B = LivingKnox and LivingKnox.Bodies
    if B == nil then return out end
    for _, npc in ipairs(npcs) do
        local z = B.find(npc)
        if z ~= nil then
            out[#out + 1] = { npc = npc, x = z:getX(), y = z:getY(), z = math.floor(z:getZ()) }
        end
    end
    return out
end

return H
