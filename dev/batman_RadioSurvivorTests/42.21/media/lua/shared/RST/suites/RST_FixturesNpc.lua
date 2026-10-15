--[[
rst.fixtures.npc - in-game check of the NPC fixture (RST.Fixtures.spawnNpc, E01-T10) and of its cleanup.
Tags "world" and "shared": only on a save named rstest* (world guard, RST.lua), on the authority with a target
player: solo RST.run({ suite = "rst.fixtures.npc", tags = "world" }), server RST.server({ suite = "rst.fixtures.npc",
tags = "world" }). Needs Living Knox enabled (sandbox LivingKnox.Enabled) and registered as the NPC provider of the
notebook: otherwise both tests are SKIP with the refusal reason of RST.Fixtures.npcReady(). Asynchronous run only.

Test 1 "spawnNpc makes an NPC seen by the provider": a test NPC appears near the player through the public Living
    Knox API (LivingKnox.API.testSpawnNpc); RS_NPCProvider.objects() holds its body under the returned id, the body
    is within F.NPC_OFFSET + 2 squares of the player on the same floor, RS_NPCProvider.npc(id) gives its record
    (signature "lk:<id>"), and LivingKnox.API.testNpcs() lists it.
Test 2 "the NPC is gone after the previous test": checks the undo of test 1: RS_NPCProvider no longer sees the id
    (objects, npc), the body is dead or out of the cell zombie list, LivingKnox.API.testNpcs() no longer lists it.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local function provider() return require "RadioSurvivor/RS_NPCProvider" end

local function inList(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

RST.suite("rst.fixtures.npc", { tags = { "world", "shared" } }, function(s)
    local F = RST.Fixtures
    local state = {}

    s.test("spawnNpc makes an NPC seen by the provider", function(t)
        local ready, why = F.npcReady()
        if not ready then t:skip(why) end
        local p = F.player(t)
        t:ok(p ~= nil, "no target player")
        state.id, state.body = nil, nil
        F.spawnNpc(t, p, function(t2, id, body)
            local P = provider()
            state.id, state.body = id, body
            t2:ok(string.match(id, "^lk%-%d+$") ~= nil, "provider id " .. tostring(id))
            t2:ok(rawequal(P.objects()[id], body), "body listed by RS_NPCProvider.objects()")
            t2:eq(id, P.id(body), "RS_NPCProvider.id(body)")
            local record = P.npc(id)
            t2:ok(record ~= nil, "RS_NPCProvider.npc(id) record")
            t2:eq("lk:" .. id, record.signature, "signature")
            t2:eq(math.floor(p:getZ()), math.floor(body:getZ()), "same floor as the player")
            local dx, dy = body:getX() - p:getX(), body:getY() - p:getY()
            t2:ok(math.sqrt(dx * dx + dy * dy) <= F.NPC_OFFSET + 2, "body near the player")
            t2:ok(inList(LivingKnox.API.testNpcs(), id), "listed by LivingKnox.API.testNpcs()")
            t2:note("npc " .. id .. " at " .. math.floor(body:getX()) .. "," .. math.floor(body:getY()) .. ","
                .. math.floor(body:getZ()))
        end)
    end)

    s.test("the NPC is gone after the previous test", function(t)
        local ready, why = F.npcReady()
        if not ready then t:skip(why) end
        t:ok(state.id ~= nil, "previous test did not spawn an NPC")
        local P = provider()
        t:ok(P.objects()[state.id] == nil, "body still seen by RS_NPCProvider.objects()")
        t:ok(P.npc(state.id) == nil, "record still given by RS_NPCProvider.npc()")
        local body = state.body
        t:ok(body:isDead() or not getCell():getZombieList():contains(body), "body still in the world")
        t:ok(not inList(LivingKnox.API.testNpcs(), state.id), "still listed by LivingKnox.API.testNpcs()")
    end)
end)
