--[[
rs.personas.update - update of the installed voice sheets on an existing game (E05-T11,
server/RadioSurvivor/RS_Personas.lua, Personas.install), on the real files of the authority:
    - a sheet installed before E05-T07 (fixed frequency, version of commit 24832ea shipped with the test mod in
      rstdata/gus-24832ea.txt), never touched, without fingerprint: replaced by the delivered sheet with ranges;
    - the same old sheet recorded in the fingerprint file (unmodified since its copy): replaced too;
    - a sheet changed by the admin (one more line): kept, never overwritten.
Each case writes gus.txt and personas-fingerprints.txt, calls Personas.install() and restores both files in the same
step (no periodic reload can read the test content), then again in t:defer if the step failed.
Tags "world" and "server" (authority only: solo or dedicated server, test saves rstest*):
RST.run({ suite = "rs.personas.update", tags = { "world", "server" } }).
]]

require "RST/RST"

local TEST_MOD = "batman_RadioSurvivorTests"
local OLD = "rstdata/gus-24832ea.txt"
local VOICE = "gus"

local function readAll(reader)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

local function write(path, lines)
    local writer = getFileWriter(path, true, false)
    if not writer then return false end
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
    return true
end

local function same(a, b)
    return a ~= nil and b ~= nil and table.concat(a, "\n") == table.concat(b, "\n")
end

local function setup(t)
    if type(isClient) == "function" and isClient() then t:skip("voice sheets live on the authority") end
    local P = require "RadioSurvivor/RS_Personas"
    local path = P.DIR .. "/" .. VOICE .. ".txt"
    local original = readAll(getFileReader(path, false))
    t:ok(original ~= nil and #original > 0, "Zomboid/Lua/" .. path .. " missing")
    local fingerprints = readAll(getFileReader(P.FINGERPRINTS, false)) or {}
    local delivered = readAll(getModFileReader(P.MOD_ID, P.BUNDLED_DIR .. "/" .. VOICE .. ".txt", false))
    t:ok(delivered ~= nil, "bundled sheet " .. VOICE .. ".txt not readable")
    local old = readAll(getModFileReader(TEST_MOD, OLD, false))
    t:ok(old ~= nil and #old > 0, OLD .. " not readable in the test mod")
    local function restore()
        write(path, original)
        write(P.FINGERPRINTS, fingerprints)
    end
    t:defer(restore, "restore " .. VOICE .. ".txt and the fingerprint file")
    return { P = P, path = path, original = original, fingerprints = fingerprints, delivered = delivered, old = old,
        restore = restore }
end

-- Fingerprint file without the line of the voice, plus { name fingerprint } when given.
local function fingerprintLines(c, value)
    local out = { c.P.FINGERPRINTS_HEADER }
    for i = 2, #c.fingerprints do
        if string.sub(c.fingerprints[i], 1, string.len(VOICE) + 5) ~= VOICE .. ".txt " then
            out[#out + 1] = c.fingerprints[i]
        end
    end
    if value then out[#out + 1] = VOICE .. ".txt " .. value end
    return out
end

-- Writes the sheet and the fingerprint file, installs, reads the result back, restores. Returns the sheet installed
-- and the fingerprint file written by install.
local function play(t, c, sheet, fingerprint)
    t:ok(write(c.path, sheet), "cannot write " .. c.path)
    t:ok(write(c.P.FINGERPRINTS, fingerprintLines(c, fingerprint)), "cannot write " .. c.P.FINGERPRINTS)
    local ok, copied, updated = pcall(c.P.install)
    local after = readAll(getFileReader(c.path, false))
    local record = readAll(getFileReader(c.P.FINGERPRINTS, false)) or {}
    c.restore()
    t:ok(ok, "Personas.install raised: " .. tostring(copied))
    t:note("install: " .. tostring(copied) .. " copied, " .. tostring(updated) .. " updated")
    return after, record
end

local function recorded(record, value)
    for _, line in ipairs(record) do
        if line == VOICE .. ".txt " .. value then return true end
    end
    return false
end

RST.suite("rs.personas.update", { tags = { "world", "server" } }, function(s)
    s.test("old sheet without fingerprint (before E05-T07) replaced by the delivered sheet with ranges", function(t)
        local c = setup(t)
        local P = c.P
        local oldPrint = P.fingerprint(c.old)
        local known = false
        for _, f in ipairs(P.KNOWN_DELIVERED[VOICE] or {}) do if f == oldPrint then known = true end end
        t:ok(known, "fingerprint " .. oldPrint .. " of " .. OLD .. " not in KNOWN_DELIVERED." .. VOICE)
        local Persona = require "RadioSurvivor/RS_Persona"
        local oldSheet = Persona.parseLines(c.old, VOICE)
        t:ok(oldSheet ~= nil and #oldSheet.frequency_ranges == 0, "the old sheet should have fixed frequencies")
        local after, record = play(t, c, c.old, nil)
        t:ok(same(after, c.delivered), VOICE .. ".txt not replaced by the delivered version")
        t:ok(recorded(record, P.fingerprint(c.delivered)), "fingerprint of the delivered sheet not recorded")
        local sheet = Persona.parseLines(after, VOICE)
        t:ok(sheet ~= nil and #sheet.frequency_ranges > 0, "installed sheet without frequency_range")
        t:ok(same(readAll(getFileReader(c.path, false)), c.original), VOICE .. ".txt not restored")
    end)

    s.test("old sheet recorded in the fingerprint file (unmodified since its copy) replaced", function(t)
        local c = setup(t)
        local after = play(t, c, c.old, c.P.fingerprint(c.old))
        t:ok(same(after, c.delivered), VOICE .. ".txt not replaced by the delivered version")
    end)

    s.test("sheet changed by the admin kept, never overwritten", function(t)
        local c = setup(t)
        local changed = {}
        for i, line in ipairs(c.delivered) do changed[i] = line end
        changed[#changed + 1] = "# rst admin line"
        local after = play(t, c, changed, c.P.fingerprint(c.delivered))
        t:ok(same(after, changed), VOICE .. ".txt of the admin overwritten")
        local old = {}
        for i, line in ipairs(c.old) do old[i] = line end
        old[#old + 1] = "# rst admin line"
        after = play(t, c, old, nil)
        t:ok(same(after, old), "old sheet changed by the admin overwritten")
    end)
end)
