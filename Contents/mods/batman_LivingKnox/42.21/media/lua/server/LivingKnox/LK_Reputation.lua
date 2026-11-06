if isClient() then return end
--[[
Living Knox: its facts in the reputation of the core mod (E18-T22, user decision of 2026-11-06: one reputation per
character in the core mod, each mod reports its own facts). Authority only.

npc.memberKilled (E04-T09, Q5): a member of a group killed by a player the server attributes (fact npcDied of
LK_Bodies.onZombieDead: killer account from the death cause) costs RC_ReputationConfig.memberKilled to this character
only, once per death (eventId lk-<npc>-g<generation>-memberKilled-<character>), unless the death of the same body was
already charged as npc.requesterKilled (RadioSurvivor, provider 'death' event of the same call: RC_Reputation
.chargedFor). Killer: living player of the account (LK_Bodies.livingPlayers, as LK_Relations.playerByName), then its
bound identity (RC_Identity.of, as LK_Hostility.keyOf). Never a client claim, no penalty by proximity.
]]
local Rep = require "RadioSurvivorCore/RC_Reputation"
local Identity = require "RadioSurvivorCore/RC_Identity"

LivingKnox = LivingKnox or {}
local Reputation = LivingKnox.Reputation or {}
LivingKnox.Reputation = Reputation

function Reputation.killerOf(account)
    if type(account) ~= "string" or account == "" then return nil end
    local bodies = LivingKnox.Bodies
    if bodies == nil or bodies.livingPlayers == nil then return nil end
    for _, p in ipairs(bodies.livingPlayers()) do
        if p:getUsername() == account then return Identity.of(p) end
    end
    return nil
end

function Reputation.onNpcDied(info)
    if type(info) ~= "table" or info.group == nil or info.npc == nil then return nil end
    local killer = Reputation.killerOf(info.killer)
    if killer == nil or Rep.chargedFor(info.npc, killer) then return nil end
    local eventId = "lk-" .. tostring(info.npc) .. "-g" .. tostring(info.generation) .. "-memberKilled-" .. killer
    return Rep.record(nil, eventId, killer, "npc.memberKilled", nil,
        { npc = info.npc, group = info.group, cause = info.cause })
end

if not Reputation.subscribed and type(LivingKnox.listen) == "function" then
    Reputation.subscribed = true
    LivingKnox.listen("npcDied", "Reputation.memberKilled", function(info) Reputation.onNpcDied(info) end)
end

return Reputation
