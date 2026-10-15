--[[
rs.initiatives - NPC initiatives of the notebook (E08-T03, server/RadioSurvivor/RS_Initiatives.lua): a Living Knox npc
created next to the player (E08-T11: on a square heard by the player, RST.RSHelpers.heardSquares), given a
notebook fiche, notices a storm (observation recorded here) and speaks up on its
own, once; a busy npc (hit less than 30 s ago) says nothing. Tags "world" and "server": the authority (solo or
dedicated server), a save named rstest*, with a target player (t.ctx.player); Living Knox enabled; option
RadioSurvivor.InitiativeFrequency not "Off". Solo: RST.run({ suite = "rs.initiatives", tags = "world" }); MP:
RST.server({ suite = "rs.initiatives", tags = "world" }) from an admin client (campaign mp). E01-T16: the line of the
last test must reach the requester client (RST.Steps "lk.speech.seen": its speech view), in solo and in MP.
The last test needs the bridge program running (bridge/radio_bridge.py): the line written by the model is said by
the speech channel of LK11-T04 and drawn as a bubble over the npc. Without the bridge it fails after 60 s.
E08-T09: "a stopped bridge leaves the npc silent" marks the bridge as stopped (RS_Initiatives.bridge, no bridge
program needed): the initiative opens silently, no request, no template line (Provider.bark never called), nothing
said. Budget spent and option "Off" are covered by tests/test_initiatives.py.
Every test removes its npc and its pending request with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"
require "RST/RST_RSHelpers"

RST.RSInitiatives = RST.RSInitiatives or {}

local function B() return LivingKnox and LivingKnox.Bodies end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    local Server = RS_CarnetServer
    t:ok(Server ~= nil and Server.store.data ~= nil, "notebook server not ready")
    local I = require "RadioSurvivor/RS_Initiatives"
    if I.LEVELS[I.level()] == nil then t:skip("option RadioSurvivor.InitiativeFrequency is Off") end
    return Server, I, require "RadioSurvivor/RS_Observations"
end

-- New npc next to the player with a notebook fiche; waits until the notebook maps its body and the player hears it.
-- E08-T11: the spot is the pick-th square heard by the player (RST.RSHelpers.heardSquares, bounded search, nearest
-- first), not a fixed offset: on the MP test server the square 3 west of the start spot was out of earshot
-- (2026-10-15: I.tick nil instead of "silent"). pick differs per test (spots of the former bodies may still be busy).
local function npcWithFiche(t, Server, pick, after)
    local P = require "RadioSurvivor/RS_NPCProvider"
    local C = require "RadioSurvivor/RS_Config"
    local R = RST.RSHelpers
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local squares = R.heardSquares(p)
    t:ok(#squares > 0, "no free square heard by the player within " .. R.SPOT_RADIUS .. " squares of " .. R.at(p))
    local sq = squares[(pick - 1) % #squares + 1]
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    local fiche = Server.ensure(id)
    t:ok(fiche ~= nil, "no fiche for " .. tostring(id))
    t:defer(function()
        local kept = {}
        for _, r in ipairs(Server.pending) do if r.npc ~= fiche.id then kept[#kept + 1] = r end end
        Server.pending = kept
        B().despawn(id, true)
    end, "forget " .. id)
    t:waitUntil(function() return Server.objects[fiche.id] ~= nil and P.hears(body, p, C.HEARING_RANGE) end, 5000,
        function(t2) after(t2, id, fiche) end,
        "body of the fiche never mapped by the notebook or never heard by the player (" .. R.at(sq) .. ")")
end

-- Why I.tick opened nothing for this fiche (report of a failure).
local function idleReason(Server, I, fiche)
    local P = require "RadioSurvivor/RS_NPCProvider"
    local object = Server.objects[fiche.id]
    if object == nil then return "body not mapped" end
    local busy, reason = P.engaged(fiche.incarnation)
    return "listeners " .. #I.listeners(Server, object) .. ", pending " .. tostring(I.hasPending(Server, fiche.id))
        .. ", engaged " .. tostring(busy) .. (reason and (" (" .. tostring(reason) .. ")") or "")
end

local function storm(Obs, fiche, subject)
    return Obs.record(fiche.id, { fact = "weather", subject = subject, day = Obs.today(), place = "everywhere" })
end

local function pendingOf(Server, fiche)
    for _, r in ipairs(Server.pending) do
        if r.npc == fiche.id and r.kind == "npc_initiative" then return r end
    end
    return nil
end

RST.suite("rs.initiatives", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 240000 }, function(s)
    s.test("a fresh observation of a heard npc opens one initiative, never twice", function(t)
        local Server, I, Obs = setup(t)
        npcWithFiche(t, Server, 1, function(t2, _, fiche)
            local key, why = storm(Obs, fiche, "storm")
            t2:ok(key ~= nil, "observation refused: " .. tostring(why))
            I.reset()
            local kind = I.tick(Server)
            t2:ok(kind == "llm" or kind == "silent", "no initiative opened (" .. tostring(kind) .. "; "
                .. idleReason(Server, I, fiche) .. ")")
            if kind == "llm" then t2:ok(pendingOf(Server, fiche) ~= nil, "no npc_initiative request queued") end
            I.reset()
            t2:eq(nil, I.tick(Server), "a second initiative for the same event")
        end)
    end)

    s.test("a busy npc (hit less than 30 s ago) takes no initiative", function(t)
        local Server, I, Obs = setup(t)
        npcWithFiche(t, Server, 2, function(t2, id, fiche)
            B().lastHits[id] = { ms = getTimestampMs() }
            local key, why = storm(Obs, fiche, "blizzard")
            t2:ok(key ~= nil, "observation refused: " .. tostring(why))
            I.reset()
            t2:eq(nil, I.tick(Server), "initiative of a busy npc")
            t2:eq(nil, pendingOf(Server, fiche), "request of a busy npc")
            B().lastHits[id] = nil
        end)
    end)

    -- E08-T09: without an answer of the model the npc says nothing of its own (no template line).
    s.test("a stopped bridge leaves the npc silent", function(t)
        local Server, I, Obs = setup(t)
        local P = require "RadioSurvivor/RS_NPCProvider"
        local lines = RST.PeerChecks.recordSpeech(t)
        local barks, bark = 0, P.bark
        P.bark = function(...) barks = barks + 1; return bark(...) end
        t:defer(function() P.bark = bark end, "restore Provider.bark")
        npcWithFiche(t, Server, 3, function(t2, id, fiche)
            local key, why = storm(Obs, fiche, "fog")
            t2:ok(key ~= nil, "observation refused: " .. tostring(why))
            I.reset()
            I.bridge.down, I.bridge.probeAt = true, getTimestampMs() + 600000
            t2:defer(function() I.reset() end, "bridge considered present again")
            t2:eq("silent", I.tick(Server), "initiative of a stopped bridge (" .. idleReason(Server, I, fiche) .. ")")
            t2:eq(nil, pendingOf(Server, fiche), "request sent to a stopped bridge")
            t2:eq(0, barks, "Provider.bark called without the bridge")
            local mine = 0
            for _, line in ipairs(lines) do if line.npc == id then mine = mine + 1 end end
            t2:eq(0, mine, "line said without the bridge")
        end)
    end)

    s.test("with the bridge running, the line is said over the npc", function(t)
        local Server, I, Obs = setup(t)
        local lines = RST.PeerChecks.recordSpeech(t)
        npcWithFiche(t, Server, 4, function(t2, id, fiche)
            storm(Obs, fiche, "tropical_storm")
            I.reset()
            local said = I.stats.said
            t2:eq("llm", I.tick(Server), "no LLM initiative opened")
            local since = getTimestampMs()   -- E17-T15: cause of a missing reply named by the failure message
            t2:waitUntil(function() return I.stats.said > said end, 60000, function(t3)
                t3:note("initiative said after the bridge reply")
                -- E01-T16: the line reached the speech view of the requester client (bubble over the npc).
                local mine = {}
                for _, line in ipairs(lines) do if line.npc == id then mine[#mine + 1] = line end end
                t3:ok(#mine > 0, "initiative not said through LivingKnox.Speech (nobody heard it?)")
                RST.Steps.ask(t3, "lk.speech.seen", { lines = mine }, { target = "requester", timeoutMs = 10000 })
            end, function() return "no reply said within 60 s: " .. RST.RSHelpers.bridgeCause(Server, since) end)
        end)
    end)
end)

return RST.RSInitiatives
