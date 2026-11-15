--[[
rs.memory persistence steps (E22-T13: "en multijoueur, un fait retenu revient au prompt apres un redemarrage du
serveur"; server/RadioSurvivor/RS_Memory.lua, private state RS_State). Base "rs.memory" of the phased MP run
(autoclient.py --mp --phases restart --server-campaign mp-persist):
    rs.memory.before          (opt-in "manual") the voice walt, a say-only sheet (remember is no sheet action: every
                              voice has it, RS_Actions.UNIVERSAL), remembers one fact through the REAL action judge
                              (RS_Actions.decide, executor of RS_Memory) for the test caller CALLER (no notebook
                              character); the private state is saved and the fact written to the snapshot.
    rs.memory.after-restart   the fact is still remembered, and still in the memory= field the server joins to the
                              next request of that caller to walt (RS_Memory.field, decoded as the bridge does). Then
                              the test caller is removed from the memory of walt and the snapshot consumed.
Run again, .before first removes the test caller of an earlier run. Tags "server", "world", "manual": authority only,
test saves rstest*, exact names only. Snapshot: Zomboid/Lua/batman_CoreAITests/tests/memory-persist.txt of the server
(RST_Persist). Outside the game: tests/test_persist_suites.py (listing and campaign plan).
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_Persist"

RST.MemoryPersist = RST.MemoryPersist or {}
local MP = RST.MemoryPersist
MP.FILE = "memory-persist.txt"
MP.HEADER = "RSMEMORY1"
MP.VOICE = "walt"
MP.CALLER = "rst-memory-persist"

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Memory is not loaded on an MP client (authority only)")
    end
    local Memory = require "RadioSurvivor/RS_Memory"
    local Actions = require "RadioSurvivor/RS_Actions"
    local Personas = require "RadioSurvivor/RS_Personas"
    local S = require "RadioSurvivor/RS_State"
    if type(Memory) ~= "table" or type(Actions) ~= "table" or type(Personas) ~= "table" or type(S) ~= "table" then
        t:skip("RS_Memory, RS_Actions, RS_Personas or RS_State did not return its table here")
    end
    t:ok(S.data ~= nil and not S.blocked, "private state of the voices not loaded (or blocked)")
    return Memory, Actions, Personas, S
end

-- Removes the test caller from the memory of the voice (an earlier run, or the cleanup).
local function forgetTestCaller(S)
    local voice = type(S.data.memory) == "table" and S.data.memory[MP.VOICE] or nil
    if type(voice) ~= "table" or type(voice.callers) ~= "table" then return end
    local doomed = {}
    for key, entry in pairs(voice.callers) do
        if type(entry) == "table" and entry.caller == MP.CALLER then doomed[#doomed + 1] = key end
    end
    for _, key in ipairs(doomed) do voice.callers[key] = nil end
    if #doomed > 0 then S.dirty = true end
end

local function contains(list, value)
    for _, v in pairs(list) do
        if v == value then return true end
    end
    return false
end

RST.suite("rs.memory.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("a say-only voice remembers a fact through the real judge, state saved", function(t)
        local Memory, Actions, Personas, S = modules(t)
        local sheet = Personas.get(MP.VOICE)
        t:ok(sheet ~= nil, "voice " .. MP.VOICE .. " not installed")
        forgetTestCaller(S)
        local fact = "RST persist fact " .. string.format("%.0f", RST.now())
        local decisions = Actions.decide(sheet, MP.CALLER, { { type = "remember", fact = fact } }, RST.now(), {})
        t:eq(1, #decisions, "one decision")
        t:eq("ok", decisions[1].reason, "remember judged for " .. MP.VOICE)
        t:ok(contains(Memory.facts(MP.VOICE, MP.CALLER, nil), fact), "fact not remembered")
        t:ok(S.save(), "private state not saved")
        local ok, why = RST.Persist.write(MP.FILE, MP.HEADER, { voice = MP.VOICE, caller = MP.CALLER, fact = fact })
        t:ok(ok, "snapshot not written: " .. tostring(why))
        t:note("voice " .. MP.VOICE .. ", fact '" .. fact .. "'")
    end)
end)

RST.suite("rs.memory.after-restart", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("the fact is still remembered and joined to the next request", function(t)
        local Memory, _, _, S = modules(t)
        local snap, why = RST.Persist.read(MP.FILE, MP.HEADER)
        t:ok(snap ~= nil, why or "no snapshot")
        t:defer(function()
            forgetTestCaller(S)
            RST.Persist.consume(MP.FILE)
        end, "test caller forgotten, snapshot consumed")
        t:ok(contains(Memory.facts(snap.voice, snap.caller, nil), snap.fact), "fact lost by the restart")
        local field = Memory.field(snap.voice, snap.caller, nil)
        t:ok(field ~= nil, "no memory= field for the next request")
        local Codec = require "CoreAI/CA_Codec"
        local sent = Codec.decodeBytes(Codec.unhexBytes(field))
        t:ok(type(sent) == "table" and contains(sent, snap.fact), "fact missing from the memory= field")
    end)
end)
