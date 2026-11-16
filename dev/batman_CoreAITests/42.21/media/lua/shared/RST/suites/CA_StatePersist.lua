--[[
ca.state persistence steps (E16-T08, C17-C20: private notebook state bounded, reliable writes; E21-T04: notebook
store of the core mod, server/CoreAI/CA_NotebookStore.lua and CA_NotebookPurge.lua). Played by autoclient.py --mp
--phases restart --server-campaign mp-persist (base ca.state):
    ca.state.before         (opt-in "manual") five test character records added to the real notebook store
                            (CoreAI.notebookServer.store = CA_NotebookStore), saved once at the real game day, then saved
                            again through the real S.save -> daily purge -> Purge.run path with the purge clock moved
                            DROP_DAYS + 1 game days ahead (CA_Reputation.today, the clock the purge reads, replaced
                            for that one save and restored at once; GameTime untouched):
                              living  never retired                  -> kept as is
                              old     retired, not in use            -> stripped then dropped
                              busy    retired as long, in use (a reputation entry for that save only) -> stripped, kept
                              recent  retired 10 days before         -> stripped, kept
                              alive2  never retired, no contact      -> kept as is
                            The slot file of the new generation is read back (header, checksum, decoded state) and
                            the snapshot records the kept records, the dropped ids, the generation and the path.
    ca.state.after-restart  after a real restart of the dedicated server: the state loaded by S.init and the slot
                            file of the current generation both hold every kept record with the same fields, none
                            of the dropped ones, exactly as many test records as kept (no duplicate, no ghost).
                            Then the test records are removed, the state saved and the snapshot consumed.
Tags "server", "world", "manual": authority only, test saves rstest* only, exact names only. The forward pass also
treats the other dead characters of the test world as DROP_DAYS + 1 days older (what the purge does to them anyway).
Snapshot: Zomboid/Lua/batman_CoreAITests/tests/state-persist.txt of the server (RST_Persist).
Outside the game: tests/test_rs_state_persist_suite.py (real CA_NotebookStore, CA_NotebookPurge and RST engine, restart
simulated by a new Lua state on the same files).
]]

require "RST/RST"
require "RST/RST_CarnetHelpers"
require "RST/RST_Persist"

RST.StatePersist = RST.StatePersist or {}
local SP = RST.StatePersist
SP.FILE = "state-persist.txt"
SP.HEADER = "RSSTATE-PERSIST1"
SP.PREFIX = "!rst-state-"   -- "!" sorts before every real character id: first in the bounded purge batch
SP.OWNER = "rst-state-test"

local N = RST.CarnetHelpers

local function setup(t)
    if type(isClient) == "function" and isClient() then t:skip("the notebook state lives on the authority") end
    local S = N.notebook(t).store
    if S.blocked then t:skip("notebook storage blocked") end
    local Purge = require "CoreAI/CA_NotebookPurge"
    local Rep = require "CoreAI/CA_Reputation"
    t:ok(type(Rep) == "table" and type(Rep.today) == "function", "CA_Reputation (purge clock) not loaded")
    return S, Purge, Rep
end

local function isTest(cid)
    return type(cid) == "string" and string.sub(cid, 1, #SP.PREFIX) == SP.PREFIX
end

local function testIds(characters)
    local out = {}
    for cid in pairs(type(characters) == "table" and characters or {}) do
        if isTest(cid) then out[#out + 1] = cid end
    end
    table.sort(out)
    return out
end

local function removeTestRecords(S)
    local ids = testIds(S.data.characters)
    for _, cid in ipairs(ids) do S.data.characters[cid] = nil end
    return #ids
end

local function count(t)
    local n = 0
    for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
    return n
end

-- Fields the purge decides on, compared before and after the restart.
local function summary(record)
    return { retired = record.retired == true, stripped = record.stripped == true, retiredDay = record.retiredDay,
        contacts = count(record.contacts), known = count(record.knownMissions), owner = record.owner }
end

local function record(cid, name, retiredDay, retired)
    return { id = cid, owner = SP.OWNER, name = name, retired = retired or nil, retiredDay = retiredDay,
        contacts = { ["rst-state-npc"] = { name = "RST" } }, knownMissions = { ["rst-state-mission"] = true } }
end

-- One S.save with the purge clock (CA_Reputation.today) at `day`; restored before returning, error or not.
local function saveAt(S, Rep, day)
    local real = Rep.today
    Rep.today = function() return day end
    local ok, saved = pcall(S.save)
    Rep.today = real
    if not ok then return false, tostring(saved) end
    return saved == true, "S.save refused (failures " .. tostring(S.failures) .. ")"
end

-- Slot file of the current write, read and checked by the slot reader of the core mod (header, checksum, decoder):
-- { generation, data }.
local function slotOf(S)
    local file = S.base .. "-" .. (S.seq % 2) .. ".txt"
    local slot = (require "CoreAI/CA_SlotFile").readSlot(file, S.HEADER)
    return slot and { generation = slot.seq, data = slot.data } or nil, file
end

-- Every kept record present with the snapshot fields, no dropped one, no other test record; prefix "where".
local function compare(t, characters, snap, where)
    for cid, want in pairs(snap.kept) do
        local got = characters[cid]
        t:ok(got ~= nil, where .. ": kept record " .. cid .. " lost")
        if got ~= nil then
            local have = summary(got)
            for key, value in pairs(want) do
                t:eq(value, have[key], where .. ": " .. cid .. "." .. key)
            end
        end
    end
    for _, cid in ipairs(snap.purged) do
        t:ok(characters[cid] == nil, where .. ": purged record " .. cid .. " back")
    end
    t:eq(count(snap.kept), #testIds(characters), where .. ": test records (duplicate or ghost)")
end

RST.suite("ca.state.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 },
    function(s)
    s.test("purge after some game weeks through the real save, kept records snapshotted", function(t)
        local S, Purge, Rep = setup(t)
        local today = Rep.today()
        if type(today) ~= "number" then t:skip("no game clock (CA_Reputation.today)") end
        local stale = removeTestRecords(S)
        if stale > 0 then t:note(stale .. " test record(s) of a previous run removed") end
        local stamp = string.format("%.0f", RST.now())
        local id = function(name) return SP.PREFIX .. stamp .. "-" .. name end
        local ahead = today + Purge.DROP_DAYS + 1
        local chars = S.data.characters
        chars[id("living")] = record(id("living"), "RST living", nil, false)
        chars[id("old")] = record(id("old"), "RST old", ahead - Purge.DROP_DAYS - 10, true)
        chars[id("busy")] = record(id("busy"), "RST busy", ahead - Purge.DROP_DAYS - 10, true)
        chars[id("recent")] = record(id("recent"), "RST recent", ahead - Purge.STRIP_DAYS - 3, true)
        chars[id("alive2")] = { id = id("alive2"), owner = SP.OWNER, name = "RST alive2", contacts = {},
            knownMissions = {} }
        local written = false
        t:defer(function()
            if not written then
                removeTestRecords(S)
                S.save()
            end
        end, "test records removed when no snapshot was written")
        t:ok(S.save(), "test records not saved at the real game day")
        -- busy is in use for the forward pass only: a reputation entry (Purge.inUse), dropped right after.
        local data = Rep.data
        t:ok(type(data) == "table", "reputation state of the core mod not loaded")
        local hadTable = type(data.reputation) == "table"
        if not hadTable then data.reputation = {} end
        data.reputation[id("busy")] = { rstTest = true }
        local saved, why = saveAt(S, Rep, ahead)
        data.reputation[id("busy")] = nil
        if not hadTable then data.reputation = nil end
        t:ok(saved, "forward save: " .. tostring(why))
        t:eq(today, Rep.today(), "purge clock restored")
        t:ok(chars[id("old")] == nil, "old dead record not dropped " .. (Purge.DROP_DAYS + 1) .. " days later")
        for _, name in ipairs({ "busy", "recent" }) do
            local r = chars[id(name)]
            t:ok(r ~= nil and r.stripped == true and count(r.contacts) == 0, name .. ": not kept stripped")
        end
        local living = chars[id("living")]
        t:ok(living ~= nil and not living.stripped and count(living.contacts) == 1, "living record touched")
        local slot, file = slotOf(S)
        t:ok(slot ~= nil and slot.generation == S.seq, "slot file " .. file .. " not valid after the save")
        local kept = {}
        for _, name in ipairs({ "living", "busy", "recent", "alive2" }) do kept[id(name)] = summary(chars[id(name)]) end
        local snap = { kept = kept, purged = { id("old") }, generation = S.seq, path = S.base }
        compare(t, slot.data.characters, snap, "slot file before the restart")
        local ok, werr = RST.Persist.write(SP.FILE, SP.HEADER, snap)
        t:ok(ok, "snapshot not written: " .. tostring(werr))
        written = true
        t:note("generation " .. S.seq .. ", purge day " .. ahead .. " (real " .. today .. "), file " .. file)
    end)
end)

RST.suite("ca.state.after-restart", { tags = { "server", "world", "manual" },
    testTimeoutMs = 60000 }, function(s)
    s.test("state read from disk equals the snapshot: kept present, purged absent, no duplicate", function(t)
        local S = setup(t)
        local snap, why = RST.Persist.read(SP.FILE, SP.HEADER)
        t:ok(snap ~= nil and type(snap.kept) == "table", why or "snapshot without records")
        t:defer(function()
            removeTestRecords(S)
            S.save()
            RST.Persist.consume(SP.FILE)
        end, "test records removed, state saved")
        t:eq(snap.path, S.base, "state file of the same world")
        t:ok(S.seq >= snap.generation, "generation went back: " .. tostring(S.seq) .. " < "
            .. tostring(snap.generation))
        compare(t, S.data.characters, snap, "state after the restart")
        local slot, file = slotOf(S)
        t:ok(slot ~= nil and slot.generation == S.seq, "slot file " .. file .. " not valid after the restart")
        compare(t, slot.data.characters, snap, "slot file after the restart")
        t:note("generation " .. snap.generation .. " -> " .. S.seq .. ", file " .. file)
    end)
end)
