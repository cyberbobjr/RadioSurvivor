--[[
rst.rights - rights of the in-game test engine on a dedicated server (E01-T05, E01-T16): RST.server (module "RST",
command "run", server/RST/RST_Server.lua) asked by a REAL second client. Tag "server": the authority only, run by
RST.server from the admin client of the MP campaign (autoclient.py --mp --clients 2 --server-campaign mp); SKIP in
solo or without a second client.

    - "a user client is refused RST.server": the second client gets the access level "user" (RST.PeerChecks.asUser:
      /setaccesslevel sent by the requester, role read back on the server, admin again at the end) and sends a real
      run request (RST.Steps "rst.run", RST_PeerChecks2.lua): answer "denied", no run started by it;
    - "an admin client is told busy while a run is in progress": the second client, admin, sends a run request during
      this very run: answer "busy" (the right is checked first, then the run in progress), nothing started.
The filter of both requests selects only rst.selftest: even a wrong answer could not start anything heavy.

rs.claim - E00-T01 (E01-T16), same file (two accounts needed): the second client claims the notebook identity of the
requester's account through the real "hello" command (RST.Steps "carnet.claim", RST_PeerChecks2.lua) while its own
binding is dropped for the test; the server never binds it to the claimed identity (its own identity from the server
modData, or a new one for a state older than that rule) and tells it so. Binding, modData of the server copy and the
client's notebook are put back at the end (a "hello" sent by the server for it).
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecks"
require "RST/RST_PeerChecks2"

local FILTER = { suite = "rst.selftest" }

local KEY = "RS_CarnetCharacter"   -- RS_Carnet_Server.lua IDENTITY_KEY

local function notebook(t)
    local server = RS_CarnetServer
    if type(server) ~= "table" or type(server.store) ~= "table" or type(server.store.data) ~= "table" then
        t:skip("notebook state not loaded on this side (RS_CarnetServer)")
    end
    return server, server.store
end

local function serverOnly(t)
    if not (type(isServer) == "function" and isServer()) then
        t:skip("needs a dedicated server and a second client (MP campaign, autoclient.py --mp --clients 2)")
    end
    local others = RST.Steps.others(t)
    if #others == 0 then t:skip("no second client online (MP campaign, --clients 2)") end
    return others[1]
end

local function askRun(t, user, after)
    RST.Steps.ask(t, "rst.run", { filter = FILTER }, { target = { user }, timeoutMs = RST.PeerChecks2.RUN_MS },
        function(t2, res)
            local e = res.by[user]
            return after(t2, e and e.data or nil)
        end)
end

RST.suite("rst.rights", { tags = { "server" } }, function(s)
    s.test("a user client is refused RST.server (E01-T05)", function(t)
        serverOnly(t)
        RST.PeerChecks.asUser(t, function(t2, user)
            askRun(t2, user, function(t3, reply)
                t3:ok(type(reply) == "table", "no answer to the run request of " .. user)
                t3:eq("denied", reply and reply.command, "answer to the run request of the user " .. user)
                t3:ok(RST.running(), "this run stopped")
                t3:note(user .. " (user): " .. tostring(reply and reply.command) .. " - " .. tostring(reply and reply.reason))
            end)
        end)
    end)

    s.test("an admin client is told busy while a run is in progress (E01-T05)", function(t)
        local user = serverOnly(t)
        askRun(t, user, function(t2, reply)
            t2:ok(type(reply) == "table", "no answer to the run request of " .. user)
            t2:eq("busy", reply and reply.command, "answer to the run request of the admin " .. user)
            t2:note(user .. " (admin): " .. tostring(reply and reply.command) .. " - " .. tostring(reply and reply.reason))
        end)
    end)
end)

RST.suite("rs.claim", { tags = { "server" } }, function(s)
    -- E00-T01 (E01-T16): a REAL second client claims the identity of the requester's account in its notebook "hello"
    -- (the only command that carries a claim: identity(player, claimed) reads it while the player is not bound). Its
    -- binding is dropped for the test so that the claim is read; the server answers with the identity of the
    -- client's own account (server modData) or, for a state older than that rule, a new one: never the claimed
    -- identity. The binding, the modData of the server copy and the client's notebook are put back at the end.
    s.test("a real client claiming the identity of another account is refused (E00-T01)", function(t)
        local server, store = notebook(t)
        if not (type(isServer) == "function" and isServer()) then
            t:skip("needs a dedicated server and two accounts (MP campaign)")
        end
        local requester = t.ctx and t.ctx.player
        local others = RST.Steps.others(t)
        if requester == nil or #others == 0 then t:skip("no second client online (MP campaign, --clients 2)") end
        local peerName = others[1]
        local peer = RST.Steps.playerOf(peerName)
        local claimed, own = server.bound[requester], peer and server.bound[peer]
        if claimed == nil or own == nil then t:skip("both clients must be bound to a notebook identity first") end
        t:ne(claimed, own, "both clients share one identity")
        local owner0 = store.data.characters[claimed].owner
        local md0 = peer:getModData()[KEY]
        local C = require "RadioSurvivor/RS_Config"
        server.bound[peer] = nil
        t:defer(function()
            server.bound[peer] = own
            peer:getModData()[KEY] = md0
            server.command(C.MODULE, "hello", peer, {})   -- identity sent again to the client
        end, "binding of " .. peerName .. " restored")
        RST.Steps.ask(t, "carnet.claim", { character = claimed }, { target = { peerName },
            timeoutMs = RST.PeerChecks2.CLAIM_MS }, function(t2, res)
            local e = res.by[peerName]
            local answered = e and e.data and e.data.character or nil
            local now = server.bound[peer]
            t2:ne(claimed, now, "the server bound " .. peerName .. " to the claimed identity of another account")
            t2:ne(claimed, answered, "the client was told the claimed identity")
            t2:eq(now, answered, "identity told to the client")
            t2:eq(owner0, store.data.characters[claimed].owner, "owner of the claimed identity")
            t2:ne(claimed, peer:getModData()[KEY], "claimed identity written in the server copy of " .. peerName)
            t2:note(peerName .. " claimed " .. tostring(claimed) .. ", bound to " .. tostring(now)
                .. (now == own and " (its own identity)" or " (a new identity: no usable identity stored)"))
        end)
    end)
end)
