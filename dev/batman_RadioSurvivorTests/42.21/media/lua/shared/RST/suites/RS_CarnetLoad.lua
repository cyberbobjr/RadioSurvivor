--[[
rs.carnet.load - bounded load of the notebook on the authority (E00-T04, server/RS_Carnet_Server.lua: ensure, scan,
prune, tick, clockRunning; RS_State.save):
    no fiche      NPC_COUNT Living Knox test npcs are spawned around the requester (LivingKnox.API.testSpawnNpc) and
                  seen by the notebook provider; after a few notebook passes (scan once a second) none of them has a
                  fiche, the number of fiches is unchanged and no enrichment request was queued (no LLM call).
    idle server   during IDLE_MS nobody does anything: the authority sends no notebook snapshot to a player who did not
                  ask for one (sendServerCommand wrapped on a server, RS_CarnetClient.receive in solo; requests counted
                  by an OnClientCommand listener), and saves nothing when no mission clock runs and the state is
                  clean (RS_State.save wrapped). In MP the other clients count what they receive in the same window
                  (RST.Steps "carnet.count": snapshots received <= snapshot or hello requests they sent). Then the
                  state is marked changed: one save within SAVE_INTERVAL_MS + 2 s and the state is clean again.
    prune         two fiches of npcs whose bodies are removed and last seen more than NPC_UNSEEN_MS ago (seenAt moved
                  back: one hour of game is not waited): the uncontacted one is dropped at the next prune (once a
                  minute), the one contacted by the requester's character ("select" command) is kept. The enrichment
                  request asked by the contact is deferred and dropped first (a pending request keeps a fiche too).
Tags "server" and "world": the authority (solo, or RST.server from an admin client), save rstest*, Living Knox on
(test API: debug mode). MP: autoclient.py --mp --clients 2 --server-suite rs.carnet.load --server-tags world.
Cleanup: test npcs removed, contact and selection of the test fiche removed, wrappers restored.
Outside the game: tests/test_rs_mp_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

local Steps = RST.Steps
local NPC_COUNT = 30
local NPC_MIN = 10
local SEEN_MS = 15000
local SETTLE_MS = 3500
local IDLE_MS = 12000

local function notebook(t)
    if type(isClient) == "function" and isClient() then t:skip("the notebook state lives on the authority") end
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    if Server.store.blocked then t:skip("notebook storage blocked") end
    local C = require "RadioSurvivor/RS_Config"
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    return { Server = Server, S = Server.store, C = C, P = require "RadioSurvivor/RS_NPCProvider", p = p }
end

local function testApi(t)
    local ready, why = RST.Fixtures.npcReady()
    if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
    return LivingKnox.API
end

local function count(tbl)
    local k = 0
    for _ in pairs(tbl or {}) do k = k + 1 end
    return k
end

-- Test npcs spawned around the player (ring of radius 2 to 6), removed at the end; list of ids.
local function spawnMany(t, API, p, wanted)
    local ids = {}
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for r = 2, 6 do
        for dy = -r, r, 2 do
            for dx = -r, r, 2 do
                if #ids < wanted and math.max(math.abs(dx), math.abs(dy)) == r then
                    local id = API.testSpawnNpc(x + dx, y + dy, z)
                    if id ~= nil then
                        ids[#ids + 1] = id
                        t:defer(function() API.testRemoveNpc(id) end, "remove test npc " .. id)
                    end
                end
            end
        end
    end
    return ids
end

local function enrichRequests(Server)
    local k = 0
    for _, r in ipairs(Server.pending or {}) do if r.kind == "npc_enrich" then k = k + 1 end end
    return k
end

local function clockRunning(S)
    for _, m in pairs(S.data.missions or {}) do
        if m.state == "active" or m.state == "offer" then return true end
    end
    return false
end

local function nameOf(player)
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return "?"
end

RST.suite("rs.carnet.load", { tags = { "server", "world" }, testTimeoutMs = 150000, timeoutMs = 400000 }, function(s)
    s.test("loaded npcs without contact get no fiche and no LLM request (E00-T04)", function(t)
        local c = notebook(t)
        local API = testApi(t)
        local fiches, enrich, times = count(c.S.data.npcs), enrichRequests(c.Server), #(c.Server.enrichTimes or {})
        local ids = spawnMany(t, API, c.p, NPC_COUNT)
        if #ids < NPC_MIN then t:skip("only " .. #ids .. " test npc(s) spawned near the player (" .. NPC_MIN .. " needed)") end
        t:note(#ids .. " test npc(s) spawned without contact")
        local function seen()
            local objects = c.P.objects()
            for _, id in ipairs(ids) do if objects[id] == nil then return false end end
            return true
        end
        t:waitUntil(seen, SEEN_MS, function(t2)
            t2:sleep(SETTLE_MS, function(t3)
                for _, id in ipairs(ids) do
                    t3:eq(nil, c.Server.find(id) and c.Server.find(id).id, "fiche created for " .. id .. " without contact")
                end
                t3:eq(fiches, count(c.S.data.npcs), "number of notebook fiches")
                t3:eq(enrich, enrichRequests(c.Server), "enrichment requests queued")
                t3:eq(times, #(c.Server.enrichTimes or {}), "enrichment requests sent this hour")
            end)
        end, "the notebook provider never saw every test npc")
    end)

    s.test("an idle server pushes no snapshot and saves only after a change (E00-T04)", function(t)
        local c = notebook(t)
        local mp = type(isServer) == "function" and isServer()
        local sent, asked, saves = {}, {}, 0
        -- Requests of the clients (snapshot pull, hello): every OnClientCommand listener receives every command.
        local function listener(module, command, player)
            if module == c.C.MODULE and (command == "snapshot" or command == "hello") then
                local key = nameOf(player)
                asked[key] = (asked[key] or 0) + 1
            end
        end
        Events.OnClientCommand.Add(listener)
        t:defer(function() Events.OnClientCommand.Remove(listener) end, "remove the request counter")
        if mp then
            local send = sendServerCommand
            -- Both Java overloads pass through unchanged: (module, command, args) sends to every client,
            -- (player, module, command[, args]) to one. Shifting the broadcast form threw "No implementation found"
            -- in other mods' broadcasts during the window (MP campaign of 2026-10-15).
            sendServerCommand = function(a, b, c2, d)
                if type(a) == "string" then
                    if a == c.C.MODULE and b == "snapshot" then sent["*all*"] = (sent["*all*"] or 0) + 1 end
                    return send(a, b, c2)
                end
                if b == c.C.MODULE and c2 == "snapshot" then
                    local key = nameOf(a)
                    sent[key] = (sent[key] or 0) + 1
                end
                if d == nil then return send(a, b, c2) end
                return send(a, b, c2, d)
            end
            t:defer(function() sendServerCommand = send end, "sendServerCommand restored")
        elseif RS_CarnetClient ~= nil then
            local receive = RS_CarnetClient.receive
            RS_CarnetClient.receive = function(command, args)
                if command == "snapshot" then
                    local key = nameOf(c.p)
                    sent[key] = (sent[key] or 0) + 1
                end
                return receive(command, args)
            end
            t:defer(function() RS_CarnetClient.receive = receive end, "RS_CarnetClient.receive restored")
        end
        -- A save is "of an unchanged state" when the encoded state equals the one of the previous save (or of the start
        -- of the window): other modules save after a real change (fiche seen again: seenAt once a minute, npcs of
        -- other suites), which is not a save of an idle state. Encoding as RS_State.save does.
        local Codec = require "RadioSurvivor/RS_Codec"
        local function encoded()
            local ok, body = pcall(Codec.encodeBytes, c.S.data)
            return ok and body or nil
        end
        local last, unchanged = encoded(), 0
        local save = c.S.save
        c.S.save = function(...)
            saves = saves + 1
            local body = encoded()
            if body ~= nil and body == last then unchanged = unchanged + 1 end
            last = body
            return save(...)
        end
        t:defer(function() c.S.save = save end, "RS_State.save restored")
        local running, dirty = clockRunning(c.S), c.S.dirty
        local function check(t2, res)
            for key, k in pairs(sent) do
                t2:ok(k <= (asked[key] or 0), k .. " snapshot(s) pushed to " .. key .. " for " .. tostring(asked[key] or 0)
                    .. " request(s) in " .. IDLE_MS .. " ms")
            end
            for _, e in ipairs(res.list) do
                local d = e.data or {}
                t2:ok(d.snapshots ~= nil and d.snapshots <= (d.pulls or 0) + 1, "client " .. e.user .. " received "
                    .. tostring(d.snapshots) .. " snapshot(s) for " .. tostring(d.pulls) .. " request(s)")
            end
            if running or dirty then
                t2:note("save count not checked: " .. (running and "a mission clock runs" or "state already changed"))
            else
                t2:eq(0, unchanged, "saves of an unchanged state in " .. IDLE_MS .. " ms")
            end
            t2:note(saves .. " save(s) (" .. unchanged .. " of an unchanged state), snapshots pushed " .. count(sent)
                .. " player(s), requests " .. count(asked)
                .. " player(s)")
            local before = saves
            c.S.dirty = true
            t2:waitUntil(function() return saves > before and not c.S.dirty end, c.C.SAVE_INTERVAL_MS + 2000,
                function(t3) t3:note("changed state saved after " .. (saves - before) .. " save(s)") end,
                "a changed state was not saved within " .. (c.C.SAVE_INTERVAL_MS + 2000) .. " ms")
        end
        -- The other clients count what they receive during the same window; without one (solo) the window is a sleep.
        if #Steps.others(t) == 0 then
            t:sleep(IDLE_MS, function(t2) return check(t2, { list = {} }) end)
        else
            Steps.ask(t, "carnet.count", { ms = IDLE_MS }, { target = "others", timeoutMs = IDLE_MS + 5000 }, check)
        end
    end, { timeoutMs = 60000 })

    s.test("a contacted fiche is never pruned, an uncontacted one is (E00-T04)", function(t)
        local c = notebook(t)
        local API = testApi(t)
        local cid = c.Server.bound[c.p]
        if cid == nil then
            c.Server.command(c.C.MODULE, "hello", c.p, {})
            cid = c.Server.bound[c.p]
        end
        t:ok(type(cid) == "string", "no notebook character bound to the requester")
        local x, y, z = math.floor(c.p:getX()), math.floor(c.p:getY()), math.floor(c.p:getZ())
        local kept, dropped = API.testSpawnNpc(x + 2, y, z), API.testSpawnNpc(x - 2, y, z)
        t:ok(kept ~= nil and dropped ~= nil, "test npcs not spawned")
        local removed = {}
        local function remove(id)
            if not removed[id] then
                removed[id] = true
                API.testRemoveNpc(id)
            end
        end
        t:defer(function() remove(kept); remove(dropped) end, "remove the test npcs")
        local record = c.S.data.characters[cid]
        t:waitUntil(function() return c.P.objects()[kept] ~= nil and c.P.objects()[dropped] ~= nil end, SEEN_MS,
            function(t2)
                local fk, fd = c.Server.ensure(kept), c.Server.ensure(dropped)
                t2:ok(fk ~= nil and fd ~= nil, "no fiche for the test npcs")
                t2:defer(function()
                    record.contacts[fk.id] = nil
                    if c.Server.selected[cid] == fk.id then c.Server.selected[cid] = nil end
                    local pending = {}
                    for _, r in ipairs(c.Server.pending) do if r.npc ~= fk.id then pending[#pending + 1] = r end end
                    c.Server.pending = pending
                    c.S.dirty = true
                end, "contact, selection and requests of the kept fiche removed")
                -- Contact by the real command (select), as the notebook client sends it.
                c.Server.command(c.C.MODULE, "select", c.p, { incarnation = kept, world = c.S.data.world, run = c.S.run })
                t2:ok(record.contacts[fk.id] ~= nil, "the select command made no contact")
                -- A pending request also keeps a fiche: the enrichment asked by the contact is deferred and dropped,
                -- so that only the contact protects it.
                fk.enrichState, fk.enrichRetryAt = "deferred", getTimestampMs() + 3600000
                local pending = {}
                for _, r in ipairs(c.Server.pending) do if r.npc ~= fk.id then pending[#pending + 1] = r end end
                c.Server.pending = pending
                remove(kept)
                remove(dropped)
                local old = getTimestampMs() - c.C.NPC_UNSEEN_MS - 1000
                fk.seenAt, fd.seenAt = old, old
                t2:waitUntil(function() return c.S.data.npcs[fd.id] == nil end, c.C.PRUNE_INTERVAL_MS + 10000,
                    function(t3)
                        t3:ok(c.S.data.npcs[fk.id] ~= nil, "contacted fiche " .. fk.id .. " pruned")
                        t3:ok(record.contacts[fk.id] ~= nil, "contact of the kept fiche lost")
                    end, "the uncontacted fiche was never pruned (prune once a minute)")
            end, "the notebook provider never saw the test npcs")
    end, { timeoutMs = 120000 })
end)
