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
E21-T11: moved from batman_RadioSurvivorTests (it tests the engine only); the identity claim of the same file is
ca.claim (CA_Claim.lua).
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecks"
require "RST/RST_PeerChecks2"

local FILTER = { suite = "rst.selftest" }

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
