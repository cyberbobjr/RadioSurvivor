--[[
RST_PeerChecksLK - client checks and player actions of the Living Knox multiplayer suites (lk.ownerreports,
lk.handover, lk.relay, lk.spawnclean, lk.deathswing), asked by the authority through RST.Steps. Development mod only.
Shared file: the game runs it on the server, on each client and in solo; it only registers step handlers and one tick
sampler (clients and solo, idle while nothing is watched). Load with: require "RST/RST_PeerChecksLK".

Client handlers (RST.Steps.on)
    lk.report.forge   { report }: this client sends a state report of a Living Knox body (module "LivingKnox",
                      command "bodyReport", as LK_Executor sends them; solo: LivingKnox.Reports.onReport, the direct
                      call of the executor) built by the server: forged report of a non-owner, teleport, health rise.
                      PASS "sent" (solo: data { accepted, why } of the direct call).
    lk.gesture.watch  { key, id, g }: arms a watcher noting the first tick at which the gesture of npc id here
                      (LivingKnox.Anim.gestureOf, the table relayed by the server) is g, on the synchronised server
                      clock (GameTime.getServerTimeMills; 0 before the synchronisation). PASS "armed".
    lk.gesture.seen   { key, t0 }: waits for the watcher; PASS with data { delay = first tick seen - t0 } (t0: server
                      clock when the authority set the gesture). FAIL at the deadline, SKIP before the clock sync.
    lk.gesture.not    { id, g, waitMs }: after waitMs, the gesture of npc id here is not g (relay filtered by range).
    lk.appear.watch   { key, x, y, z, r }: arms a watcher of the zombies standing within r squares of x, y, z at each
                      tick (zombies already there are left out): objects, online ids, most at once, voice prefix and
                      zombie voices playing (LivingKnox.ZombieGuard.ZOMBIE_VOICES on the emitter), and the guard
                      counters of this machine (voicesStopped, preSilenced, adopted, restored). PASS "armed".
    lk.appear.check   { key, id, strict }: the watcher's verdict, once the copy of npc id is known here
                      (LivingKnox.Anim.knownBodies): a single zombie at once, no zombie of another online id, no voice
                      played; strict (MP client) also: voice prefix silent from the first tick the copy was seen and
                      no voice stopped by the guard (a voice that started). Data: the figures.
    lk.melee.swing    { key, id, sw, hit }: waits until a swing (sw) is played here on the copy of npc id
                      (LivingKnox.CombatView.stats.meleeSwings grows and the emitter of the copy plays sw); then
                      arms a death watcher on that copy (OnZombieDead or isDead) and answers PASS at once, so that
                      the authority kills the npc during the swing.
    lk.melee.silence  { key, listenMs }: once the death of the watched copy is seen and listenMs are over: no swing
                      nor impact played here after the death (CombatView counters), the emitter of the dead copy
                      plays neither sw nor hit, and a swing playing at the death was stopped (bodySoundsStopped).
                      Data: playingAtDeath, latency from the swing to the death, counters.
Authority helpers (suite code)
    PL.peer(t)                    account of the first other online client (server), nil in solo or alone
    PL.accountOf(player)          account name of a player (getUsername), or nil
    PL.watchTarget(t)             step target of the "other client" checks: { peer } on a server with a peer,
                                  "requester" in solo (the handler then runs here), nil without any
Kahlua: no next(), no goto; nothing suspends. Every handler is pcall-protected by RST.Steps.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecksLK = RST.PeerChecksLK or {}
local PL = RST.PeerChecksLK
local Steps = RST.Steps

PL.gestures = PL.gestures or {}   -- key -> { id, g, seen }
PL.appears = PL.appears or {}     -- key -> appear watcher
PL.deaths = PL.deaths or {}       -- key -> death watcher of a melee swing
PL.SILENT = "LKSilentZombie"      -- LivingKnox.ZombieGuard.SILENT_VOICE when the module is absent

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function Guard() return LivingKnox and LivingKnox.ZombieGuard end
local function Anim() return LivingKnox and LivingKnox.Anim end
local function View() return LivingKnox and LivingKnox.CombatView end

local function isClientSide() return type(isClient) == "function" and isClient() and true or false end
local function isServerSide() return type(isServer) == "function" and isServer() and true or false end

local function now() return RST.now() end

-- Synchronised server clock on an MP client (0 before the synchronisation), the real clock elsewhere.
local function serverClock()
    if isClientSide() then
        if GameTime ~= nil and GameTime.getServerTimeMills ~= nil then return GameTime.getServerTimeMills() end
        return 0
    end
    return now()
end
PL.serverClock = serverClock

function PL.accountOf(player)
    if player == nil then return nil end
    return safe(function() return tostring(player:getUsername()) end)
end

function PL.peer(t)
    if not isServerSide() then return nil end
    return Steps.others(t)[1]
end

function PL.watchTarget(t)
    if Steps.isSolo() then return "requester" end
    local peer = PL.peer(t)
    if peer == nil then return nil end
    return { peer }
end

-- Copy of npc id displayed here (client: copy found by the guard; solo: the bound body), or nil.
local function copyOf(id)
    local A = Anim()
    if A == nil or A.knownBodies == nil then return nil end
    return A.knownBodies()[id]
end
PL.copyOf = copyOf

local function voices()
    local G = Guard()
    return (G and G.ZOMBIE_VOICES) or {}
end

local function silentName()
    local G = Guard()
    return (G and G.SILENT_VOICE) or PL.SILENT
end

local function prefixOf(z)
    return safe(function()
        local d = z:getDescriptor()
        return d and d:getVoicePrefix() or nil
    end)
end

-- Name of a zombie voice playing on the emitter of z, or nil.
local function voicePlaying(z)
    local em = safe(function() return z:getEmitter() end)
    if em == nil then return nil end
    for _, name in ipairs(voices()) do
        if safe(function() return em:isPlaying(name) end) then return name end
    end
    return nil
end

local function playing(z, name)
    if z == nil or name == nil then return false end
    local em = safe(function() return z:getEmitter() end)
    if em == nil then return false end
    return safe(function() return em:isPlaying(name) end) and true or false
end

local function zombiesNear(x, y, z, r)
    local out = {}
    local cell = getCell and getCell() or nil
    local list = cell and cell:getZombieList() or nil
    for i = 0, (list and list:size() or 0) - 1 do
        local zb = list:get(i)
        if zb ~= nil and math.floor(zb:getZ()) == z and math.abs(zb:getX() - x) <= r and math.abs(zb:getY() - y) <= r then
            out[#out + 1] = zb
        end
    end
    return out
end

local function guardCounters()
    local G = Guard()
    local st = G and G.stats or {}
    return { stopped = st.voicesStopped or 0, pre = st.preSilenced or 0, adopted = st.adopted or 0,
        restored = st.restored or 0 }
end

local function viewCounters()
    local V = View()
    local st = V and V.stats or {}
    return { swings = st.meleeSwings or 0, impacts = st.meleeImpacts or 0, stopped = st.bodySoundsStopped or 0 }
end

-- ---------------------------------------------------------------- tick sampler (clients and solo)

local function sampleGestures()
    local A = Anim()
    for _, w in pairs(PL.gestures) do
        if w.seen == nil and A ~= nil and A.gestureOf(w.id) == w.g then
            w.seen = serverClock()
            w.seenReal = now()
        end
    end
end

local function sampleAppear(w)
    local near = zombiesNear(w.x, w.y, w.z, w.r)
    local count = 0
    local present = {}
    local silent = silentName()
    for _, zb in ipairs(near) do
        if not w.before[zb] then
            count = count + 1
            present[#present + 1] = zb
            local rec = w.objects[zb]
            if rec == nil then
                rec = { first = now(), firstPrefix = prefixOf(zb), loud = 0, voice = 0 }
                w.objects[zb] = rec
                w.order[#w.order + 1] = zb
            end
            -- Ghost or ambient zombie (lk.appear.check): a copy of the npc is a reanimated player, a vanilla ghost of
            -- its body keeps its persistent outfit id; an ambient zombie of the reloaded chunk has neither.
            if rec.reanimated == nil then rec.reanimated = safe(function() return zb:isReanimatedPlayer() end) end
            if rec.outfit == nil then rec.outfit = safe(function() return zb:getPersistentOutfitID() end) end
            rec.o = safe(function() return zb:getOnlineID() end)
            if prefixOf(zb) ~= silent then rec.loud = rec.loud + 1 end
            local v = voicePlaying(zb)
            if v ~= nil then
                rec.voice = rec.voice + 1
                rec.voiceName = v
            end
        end
    end
    if count > w.most then w.most = count end
    w.present = w.present or {}
    w.present[#w.present + 1] = present
    w.ticks = w.ticks + 1
end

local function markDeath(w, instant)
    if w.deathMs ~= nil then return end
    w.deathMs = now()
    w.playingAtDeath = w.lastPlaying or instant or false
    w.atDeath = viewCounters()
end

local function sampleDeath(w)
    if w.deathMs ~= nil then return end
    local dead = safe(function() return w.copy:isDead() end)
    if dead then
        markDeath(w, false)
        return
    end
    w.lastPlaying = playing(w.copy, w.sw)
end

function PL.tick()
    sampleGestures()
    for _, w in pairs(PL.appears) do
        if w.active then sampleAppear(w) end
    end
    for _, w in pairs(PL.deaths) do sampleDeath(w) end
end

function PL.onZombieDead(zb)
    for _, w in pairs(PL.deaths) do
        if w.deathMs == nil and rawequal(w.copy, zb) then markDeath(w, playing(zb, w.sw)) end
    end
end

if not PL._subscribed and type(Events) == "table" and not isServerSide() then
    if Events.OnTick then Events.OnTick.Add(function() RST.PeerChecksLK.tick() end) end
    if Events.OnZombieDead then Events.OnZombieDead.Add(function(zb) RST.PeerChecksLK.onZombieDead(zb) end) end
    PL._subscribed = true
end

-- ---------------------------------------------------------------- handlers

Steps.on("lk.report.forge", function(args)
    local report = args.report
    if type(report) ~= "table" then return Steps.fail("no report given") end
    local player = getPlayer and getPlayer() or nil
    if player == nil then return Steps.fail("no local player") end
    if isClientSide() then
        sendClientCommand(player, "LivingKnox", "bodyReport", report)
        return Steps.pass("report sent (n " .. tostring(report.n) .. ")")
    end
    local R = LivingKnox and LivingKnox.Reports
    if R == nil or R.onReport == nil then return Steps.fail("LivingKnox.Reports not loaded here") end
    local ok, why = R.onReport(player, report)
    return Steps.pass("report handed (direct call): " .. tostring(ok) .. " " .. tostring(why),
        { accepted = ok and true or false, why = why })
end)

Steps.on("lk.gesture.watch", function(args)
    if type(args.key) ~= "string" or type(args.id) ~= "string" or type(args.g) ~= "string" then
        return Steps.fail("lk.gesture.watch { key, id, g }")
    end
    if Anim() == nil then return Steps.fail("LivingKnox.Anim not loaded here") end
    PL.gestures[args.key] = { id = args.id, g = args.g }
    sampleGestures()
    return Steps.pass("watching gesture " .. args.g .. " of " .. args.id .. " (now " .. Anim().gestureOf(args.id) .. ")")
end)

Steps.on("lk.gesture.seen", function(args)
    local w = PL.gestures[args.key]
    if w == nil then return Steps.fail("no gesture watcher " .. tostring(args.key)) end
    return function(ctx)
        if w.seen ~= nil then
            PL.gestures[args.key] = nil
            if w.seen <= 0 or type(args.t0) ~= "number" or args.t0 <= 0 then
                return Steps.skip("server clock not synchronised here: gesture " .. w.g .. " seen, delay unknown")
            end
            local delay = w.seen - args.t0
            return Steps.pass("gesture " .. w.g .. " of " .. w.id .. " seen " .. delay .. " ms after it was set",
                { delay = delay })
        end
        if ctx.final then
            PL.gestures[args.key] = nil
            return Steps.fail("gesture " .. w.g .. " of " .. w.id .. " not seen here (gesture here: "
                .. tostring(Anim() and Anim().gestureOf(w.id)) .. ")")
        end
        return nil
    end
end)

Steps.on("lk.gesture.not", function(args)
    local waitMs = tonumber(args.waitMs) or 1500
    return function(ctx)
        if now() - ctx.startedMs < waitMs and not ctx.final then return nil end
        local A = Anim()
        if A == nil then return Steps.fail("LivingKnox.Anim not loaded here") end
        local g = A.gestureOf(args.id)
        if g == args.g then
            return Steps.fail("gesture " .. args.g .. " of " .. tostring(args.id) .. " received here, out of range")
        end
        return Steps.pass("gesture of " .. tostring(args.id) .. " here: " .. tostring(g), { g = g })
    end
end)

Steps.on("lk.appear.watch", function(args)
    local x, y, z, r = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.r) or 3
    if type(args.key) ~= "string" or x == nil or y == nil or z == nil then
        return Steps.fail("lk.appear.watch { key, x, y, z, r }")
    end
    local w = { x = x, y = y, z = z, r = r, before = {}, objects = {}, order = {}, most = 0, ticks = 0,
        guard0 = guardCounters(), active = true, startMs = now() }
    local pre = zombiesNear(x, y, z, r)
    for _, zb in ipairs(pre) do w.before[zb] = true end
    PL.appears[args.key] = w
    return Steps.pass("watching " .. r .. " squares around " .. x .. "," .. y .. "," .. z .. " (" .. #pre
        .. " zombie(s) already there, left out)")
end)

Steps.on("lk.appear.check", function(args)
    local w = PL.appears[args.key]
    if w == nil then return Steps.fail("no appearance watcher " .. tostring(args.key)) end
    return function(ctx)
        local copy = copyOf(args.id)
        if copy == nil and not ctx.final then return nil end
        w.active = false
        PL.appears[args.key] = nil
        local g = guardCounters()
        local o = copy and safe(function() return copy:getOnlineID() end)
        local copies, ghosts, ambient, loud, voice, firstLoud, voiceName = 0, 0, 0, 0, 0, false, nil
        local outfit = copy and safe(function() return copy:getPersistentOutfitID() end) or nil
        local isAmbient = {}
        for _, zb in ipairs(w.order) do
            local rec = w.objects[zb]
            local mine = rawequal(zb, copy) or (o ~= nil and rec.o == o)
            if mine then
                copies = copies + 1
                loud = loud + rec.loud
                if rec.firstPrefix ~= silentName() then firstLoud = true end
                voice = voice + rec.voice
                voiceName = voiceName or rec.voiceName
            elseif rec.reanimated == false and type(outfit) == "number" and outfit ~= 0
                and type(rec.outfit) == "number" and rec.outfit ~= outfit then
                -- MP campaign of 2026-10-15: an ambient zombie of the reloaded chunk walked within RADIUS of the
                -- npc and was counted as a ghost; it is neither a reanimated player nor dressed as the npc.
                ambient = ambient + 1
                isAmbient[zb] = true
            else
                ghosts = ghosts + 1
                voice = voice + rec.voice
                voiceName = voiceName or rec.voiceName
            end
        end
        local most = 0
        for _, list in ipairs(w.present or {}) do
            local n = 0
            for _, zb in ipairs(list) do
                if not isAmbient[zb] then n = n + 1 end
            end
            if n > most then most = n end
        end
        local data = { ticks = w.ticks, most = most, mostAll = w.most, copies = copies, ghosts = ghosts,
            ambient = ambient, loudTicks = loud,
            firstLoud = firstLoud, voiceTicks = voice, voice = voiceName,
            stopped = g.stopped - w.guard0.stopped, pre = g.pre - w.guard0.pre,
            adopted = g.adopted - w.guard0.adopted, restored = g.restored - w.guard0.restored, o = o }
        local text = string.format("%d tick(s): most %d at once, copy objects %d, other zombies %d, ambient zombies "
            .. "%d, voice played %d tick(s)%s, vanilla prefix %d tick(s) (first %s), guard: stopped %d, pre-silenced "
            .. "%d, adopted %d, restored %d", w.ticks, most, copies, ghosts, ambient, voice,
            voiceName and (" (" .. voiceName .. ")") or "", loud, tostring(firstLoud), data.stopped, data.pre,
            data.adopted, data.restored)
        if copy == nil then return Steps.fail("copy of " .. tostring(args.id) .. " never known here; " .. text, data) end
        if copies == 0 then return Steps.fail("copy of " .. args.id .. " not seen near the watched square; " .. text, data) end
        if ghosts > 0 or most > 1 then return Steps.fail("second zombie seen near the npc; " .. text, data) end
        if voice > 0 then return Steps.fail("zombie voice played by the npc copy; " .. text, data) end
        if args.strict then
            if loud > 0 then return Steps.fail("npc copy with a vanilla voice prefix; " .. text, data) end
            if data.stopped > 0 then return Steps.fail("guard had to stop a started voice; " .. text, data) end
        end
        return Steps.pass(text, data)
    end
end)

Steps.on("lk.melee.swing", function(args)
    if View() == nil then return Steps.skip("LivingKnox.CombatView not loaded here (no melee sound played)") end
    if type(args.key) ~= "string" or type(args.id) ~= "string" or type(args.sw) ~= "string" then
        return Steps.fail("lk.melee.swing { key, id, sw, hit }")
    end
    local swings0 = viewCounters().swings
    return function(ctx)
        local copy = copyOf(args.id)
        if copy ~= nil and viewCounters().swings > swings0 and playing(copy, args.sw) then
            local w = { copy = copy, sw = args.sw, hit = args.hit, swingMs = now(), lastPlaying = true }
            PL.deaths[args.key] = w
            return Steps.pass("swing " .. args.sw .. " playing on the copy of " .. args.id, { swingMs = w.swingMs })
        end
        if ctx.final then
            return Steps.fail("no swing " .. args.sw .. " played here on the copy of " .. args.id .. " (copy "
                .. tostring(copy ~= nil) .. ", swings " .. (viewCounters().swings - swings0) .. ")")
        end
        return nil
    end
end)

Steps.on("lk.melee.silence", function(args)
    local w = PL.deaths[args.key]
    if w == nil then return Steps.fail("no death watcher " .. tostring(args.key)) end
    local listen = tonumber(args.listenMs) or 4000
    return function(ctx)
        if w.deathMs == nil or now() - w.deathMs < listen then
            if not ctx.final then return nil end
            PL.deaths[args.key] = nil
            if w.deathMs == nil then return Steps.fail("death of the watched copy not seen here") end
        end
        PL.deaths[args.key] = nil
        local c = viewCounters()
        local swingNow, hitNow = playing(w.copy, w.sw), playing(w.copy, w.hit)
        local data = { playingAtDeath = w.playingAtDeath and true or false, latency = w.deathMs - w.swingMs,
            swings = c.swings - w.atDeath.swings, impacts = c.impacts - w.atDeath.impacts,
            stopped = c.stopped - w.atDeath.stopped, swingNow = swingNow, hitNow = hitNow }
        local text = string.format("death %d ms after the swing (swing playing at the death %s, body sounds stopped "
            .. "%d); in the next %d ms: swings %d, impacts %d; dead copy plays swing %s, impact %s", data.latency,
            tostring(data.playingAtDeath), data.stopped, listen, data.swings, data.impacts, tostring(swingNow),
            tostring(hitNow))
        if data.swings > 0 or data.impacts > 0 then return Steps.fail("melee sound played after the death: " .. text, data) end
        if swingNow or hitNow then return Steps.fail("melee sound still playing on the dead copy: " .. text, data) end
        if data.playingAtDeath and data.stopped < 1 then
            return Steps.fail("swing playing at the death not stopped: " .. text, data)
        end
        return Steps.pass(text, data)
    end
end)

return PL
