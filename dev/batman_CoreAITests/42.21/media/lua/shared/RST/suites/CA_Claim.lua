--[[
ca.claim - E00-T01 (E01-T16; E21-T11: moved from batman_RadioSurvivorTests): the second client claims the notebook
identity of the requester's account through the real "hello" command (RST.Steps "carnet.claim",
RST_PeerChecksCarnet.lua) while its own binding is dropped for the test; the server never binds it to the claimed
identity (its own identity from the server modData, or a new one for a state older than that rule) and tells it so.
Binding, modData of the server copy and the client's notebook are put back at the end (a "hello" sent by the server
for it).
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecksCarnet"

local KEY = "CA_Character"   -- CA_NotebookServer.lua IDENTITY_KEY

local function notebook(t)
    local server = CoreAI and CoreAI.notebookServer
    if type(server) ~= "table" or type(server.store) ~= "table" or type(server.store.data) ~= "table" then
        t:skip("notebook state not loaded on this side (CoreAI.notebookServer)")
    end
    return server, server.store
end

RST.suite("ca.claim", { tags = { "server" } }, function(s)
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
        local C = require "CoreAI/CA_NotebookConfig"
        server.bound[peer] = nil
        t:defer(function()
            server.bound[peer] = own
            peer:getModData()[KEY] = md0
            server.command(C.MODULE, "hello", peer, {})   -- identity sent again to the client
        end, "binding of " .. peerName .. " restored")
        RST.Steps.ask(t, "carnet.claim", { character = claimed }, { target = { peerName },
            timeoutMs = RST.PeerCarnet.CLAIM_MS }, function(t2, res)
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
