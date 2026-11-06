--[[
lk.agreements - agreements kept by Living Knox (E18-T20, LK_Agreements) on the team ids of the core mod (RC_Teams),
with or without RadioSurvivor. Tag "server" (solo or dedicated server, authority only). The truce is concluded
directly (the model's decision is the bridge's part), with a test group id (form checked only, never a group of the
engine): the player's team is covered by the hook of Living Knox at once, the agreement is kept in the private file of
Living Knox. Cleanup: the agreement is removed (cancelAgreement). Outside the game: tests/test_agreements.py,
tests/test_lk_agreements.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local GID = "grp-990002"

RST.suite("lk.agreements", { tags = { "server" } }, function(s)
    s.test("truce of a team concluded and covered by Living Knox (E18-T20)", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only") end
        local A = type(LivingKnox) == "table" and LivingKnox.Agreements or nil
        t:ok(A ~= nil and type(A.conclude) == "function", "LivingKnox.Agreements not loaded")
        local Teams = require "RadioSurvivorCore/RC_Teams"
        local Identity = require "RadioSurvivorCore/RC_Identity"
        local p = RST.Fixtures.player(t)
        if not p then t:skip("no target player") end
        local cid = Identity.of(p)
        if not cid then t:skip("player without an identity of the core mod yet") end
        local team = Teams.idOf(p)
        t:ok(type(team) == "string" and string.find(team, "^fac%-%d+$") ~= nil, "team id " .. tostring(team))
        if A.agreementOf(GID, team) then A.cancelAgreement(GID, team) end
        local neg, why = A.negotiation(p, GID)
        if not neg then t:skip("no offer for this player (" .. tostring(why) .. "): owner or negotiator needed") end
        local ok, reason, a = A.conclude(p, GID, "truce", { team = team, revision = neg.revision }, { character = cid })
        t:ok(ok, "concluded: " .. tostring(reason))
        t:defer(function() A.cancelAgreement(GID, team) end, "agreement removed")
        t:eq("pending", a and a.state)
        t:eq(true, A.covered(GID, cid), "player covered by the hook of Living Knox")
        t:eq(true, A.save(), "private file of Living Knox written")
        t:note("agreement " .. tostring(a and a.id) .. " of team " .. team)
    end)
end)
