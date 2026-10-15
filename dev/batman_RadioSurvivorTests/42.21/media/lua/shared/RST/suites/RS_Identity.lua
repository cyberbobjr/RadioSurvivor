--[[
rs.identity - character identity of the notebook (E00-T01, E00-T02) checked on the authority during a real session
(E03-T04). Reads the live state of RS_CarnetServer (server/RS_Carnet_Server.lua); never changes it.

Suites (tag "server": RS_Carnet_Server.lua starts with "if isClient() then return end"):
    rs.identity                 invariants of the live state, any time (also run by "rs" and the dedicated-server
                                autorun): records well formed, each online player bound to a usable identity of
                                its own account, no identity shared, no retired identity in use, mission members
                                known. Tests about online players are SKIP without players.
    rs.identity.before          (opt-in tag "manual") snapshot of every online account: identity, notes, missions
                                where it is engaged or invited, their clocks, world, session, time. Written to
                                Zomboid/Lua/batman_RadioSurvivor/tests/identity-snapshot.txt of the server (a test
                                file, not the notebook state). Run it again before each manual action.
    rs.identity.after-reconnect same session: same identity (server modData and binding), notes, engagements; the
                                mission clock ran during the disconnection.
    rs.identity.after-restart   new session of the same world: same identity, notes, engagements; the mission
                                clock excludes the downtime (rs.identity.before run just before "quit").
    rs.identity.after-death     an account whose identity changed died: old identity retired and unused, new
                                identity of the same account without the old missions or notes; the other accounts
                                keep their identity and missions.
The death of an account is also automated without these snapshots by rs.death (RS_Death.lua: the second client of the
MP campaign really dies and respawns).
The "manual" suites only run when named exactly: RST.server("rs.identity.before"). Protocol: docs/tests-en-jeu.md, section 11
(two accounts: reconnection, restart, death).

Missions: on a world run (save rstest*, debug) with Living Knox, rs.identity.before first engages every online
account in one ACTIVE mission requested by a real test NPC (RST.Fixtures.spawnNpc + RS_CarnetServer.ensure +
RST.Fixtures.engagedMission, accepted through RS_Missions.accept), kept for the after-* steps and removed by
.after-restart and .after-death; rs.identity checks in the same way, live, that such a mission clock follows the real
time (solo proof of E00-T01, mission removed after the test). Without the Living Knox test API those tests SKIP and
the clock tests of the after-* steps are SKIP too. A restart needs autoclient.py --restart-pause (about 120 s) so that
the downtime exceeds RESTART_MARGIN_MS. Downtime check: the clock may lose at most RESTART_MARGIN_MS between the
snapshot and "quit", plus the server runtime since this file was loaded (RST_IdentityBootMs, set once per Lua state,
before the world loads: a looser bound, never a tighter one).
]]

require "RST/RST"
require "RST/RST_Fixtures"

RST.IdentitySuite = RST.IdentitySuite or {}
local I = RST.IdentitySuite
I.FILE = RST.FILE_DIR .. "identity-snapshot.txt"
I.HEADER = "RSIDENTITY1"
I.KEY = "RS_CarnetCharacter"
I.CLOCK_TOLERANCE_MS = 5000      -- tick lag and save interval around a reconnection
I.RESTART_MARGIN_MS = 120000     -- longest delay allowed between rs.identity.before and "quit"
I.MISSION_TAG = "rs.identity"    -- RST.Fixtures.engagedMission mark of the missions made by these suites
I.CLOCK_WAIT_MS = 3000           -- live clock check: real time waited
I.LIVE_TOLERANCE_MS = 1500       -- live clock check: tick lag (the notebook advances its clock on every tick)

-- Server Lua start (this file loads with the server Lua, before the world): bound of the runtime since the restart.
if type(RST_IdentityBootMs) ~= "number" then RST_IdentityBootMs = RST.now() end

local function serverSide()
    return type(isServer) == "function" and isServer() and true or false
end

-- RS_CarnetServer and its state, or a skip / failure.
local function carnet(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the notebook state lives on the server (not loaded on an MP client)")
    end
    local server = RS_CarnetServer
    t:ok(type(server) == "table", "RS_CarnetServer is not loaded on this side")
    local store = server.store
    t:ok(type(store) == "table" and type(store.data) == "table", "notebook state not initialised (store.data is nil)")
    t:ok(not store.blocked, "notebook storage is blocked (see [RS_Carnet] STORAGE BLOCKED in the log)")
    return server, store
end

local function onlinePlayers()
    local out = {}
    if serverSide() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    elseif type(getPlayer) == "function" and getPlayer() then
        out[1] = getPlayer()
    end
    return out
end

-- Same rule as RS_Carnet_Server.lua ownerOf.
local function ownerOf(player)
    return serverSide() and player:getUsername() or "solo"
end

local function accountKey(owner, slot)
    return tostring(owner) .. "/" .. tostring(slot)
end

local function count(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do n = n + 1 end
    return n
end

local function sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl or {}) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

-- Identity seen by the server for one online player: modData of the server IsoPlayer and runtime binding.
local function identityOf(server, player)
    local md = player:getModData()
    return md and md[I.KEY] or nil, server.bound[player]
end

-- Account view of one character: notes, missions where it is engaged or invited, known missions.
local function describe(data, owner, slot, character)
    local record = data.characters[character]
    local entry = { owner = owner, slot = slot, character = character, name = record and record.name or "",
        notes = {}, contacts = 0, engaged = {}, invited = {}, known = {} }
    if not record then return entry end
    for npc, known in pairs(record.contacts or {}) do
        entry.contacts = entry.contacts + 1
        if type(known.note) == "string" and known.note ~= "" then entry.notes[npc] = known.note end
    end
    for id in pairs(record.knownMissions or {}) do entry.known[id] = true end
    for id, m in pairs(data.missions) do
        if m.participants and m.participants[character] then
            local members = {}
            for cid in pairs(m.participants) do members[cid] = true end
            entry.engaged[id] = { state = m.state, remainingMs = m.remainingMs, members = members }
        elseif m.invited and m.invited[character] then
            entry.invited[id] = { state = m.state }
        end
    end
    return entry
end

-- Every online account with its identity; problems lists the players without a usable one.
local function accounts(server, data)
    local result, problems = {}, {}
    for _, player in ipairs(onlinePlayers()) do
        local owner, slot = ownerOf(player), player:getPlayerNum()
        local md, bound = identityOf(server, player)
        local id = md or bound
        local record = type(id) == "string" and data.characters[id] or nil
        local key = accountKey(owner, slot)
        if not id then
            problems[#problems + 1] = key .. " has no identity yet (the client sends hello at game start)"
        elseif not record then
            problems[#problems + 1] = key .. " carries unknown identity " .. tostring(id)
        else
            result[key] = describe(data, owner, slot, id)
            result[key].md, result[key].bound, result[key].retired = md, bound, record.retired == true
        end
    end
    return result, problems
end

local function writeSnapshot(snapshot)
    local Codec = require "RadioSurvivor/RS_Codec"
    local body = Codec.encodeBytes(snapshot)
    local ok, writer = pcall(getFileWriter, I.FILE, true, false)
    if not ok or not writer then return false, "getFileWriter refused " .. I.FILE end
    local wrote, err = pcall(function()
        writer:write(I.HEADER .. "\n" .. Codec.hexBytes(body) .. "\n" .. Codec.checksumBytes(body) .. "\nend\n")
    end)
    pcall(function() writer:close() end)
    if not wrote then return false, "write failed: " .. tostring(err) end
    return true
end

-- Returns the snapshot, or nil and a reason.
local function readSnapshot()
    local Codec = require "RadioSurvivor/RS_Codec"
    local ok, reader = pcall(getFileReader, I.FILE, false)
    if not ok or not reader then return nil, "no snapshot " .. I.FILE .. ": run RST.server('rs.identity.before') first" end
    local header, raw, checksum, finish = reader:readLine(), reader:readLine(), reader:readLine(), reader:readLine()
    pcall(function() reader:close() end)
    if header ~= I.HEADER or finish ~= "end" then return nil, "snapshot " .. I.FILE .. " is incomplete" end
    local body = Codec.unhexBytes(raw)
    if not body or Codec.checksumBytes(body) ~= checksum then return nil, "snapshot " .. I.FILE .. " is corrupt" end
    local snapshot = Codec.decodeBytes(body)
    if type(snapshot) ~= "table" or type(snapshot.accounts) ~= "table" then
        return nil, "snapshot " .. I.FILE .. " cannot be decoded"
    end
    return snapshot
end

local function snapshotOrFail(t)
    local snapshot, why = readSnapshot()
    t:ok(snapshot ~= nil, why)
    return snapshot
end

-- Snapshot accounts online now: list of { key, old, player, md, bound }, plus the keys of offline accounts.
local function pairUp(server, snapshot)
    local online = {}
    for _, player in ipairs(onlinePlayers()) do online[accountKey(ownerOf(player), player:getPlayerNum())] = player end
    local found, offline = {}, {}
    for _, key in ipairs(sortedKeys(snapshot.accounts)) do
        local player = online[key]
        if player then
            local md, bound = identityOf(server, player)
            found[#found + 1] = { key = key, old = snapshot.accounts[key], player = player, md = md, bound = bound }
        else
            offline[#offline + 1] = key
        end
    end
    return found, offline
end

local function requireOnline(t, found, offline)
    if #offline > 0 then t:note("offline, not checked: " .. table.concat(offline, ", ")) end
    t:ok(#found > 0, "no account of the snapshot is online")
end

local function report(t, problems, what)
    t:ok(#problems == 0, what .. ": " .. table.concat(problems, "; "))
end

-- Same identity: server modData, runtime binding, usable record of the same account.
local function checkSameIdentity(data, a, problems)
    local id = a.old.character
    local record = data.characters[id]
    if a.md ~= id then problems[#problems + 1] = a.key .. " modData identity " .. tostring(a.md) .. " ~= " .. id end
    if a.bound ~= id then
        problems[#problems + 1] = a.key .. " bound identity " .. tostring(a.bound) .. " ~= " .. id
            .. (a.bound == nil and " (no hello received yet)" or "")
    end
    if not record then
        problems[#problems + 1] = a.key .. " record " .. id .. " is missing"
    else
        if record.retired then problems[#problems + 1] = a.key .. " record " .. id .. " is retired" end
        if record.owner ~= a.old.owner or record.slot ~= a.old.slot then
            problems[#problems + 1] = a.key .. " record " .. id .. " belongs to " .. accountKey(record.owner, record.slot)
        end
    end
end

-- Notes, engagements and invitations of the snapshot still on the same character.
local function checkSameNotebook(data, a, problems)
    local id = a.old.character
    local record = data.characters[id] or { contacts = {}, knownMissions = {} }
    for _, npc in ipairs(sortedKeys(a.old.notes)) do
        local known = record.contacts[npc]
        if not known then problems[#problems + 1] = a.key .. " lost contact " .. npc
        elseif known.note ~= a.old.notes[npc] then problems[#problems + 1] = a.key .. " note on " .. npc .. " changed" end
    end
    for _, mid in ipairs(sortedKeys(a.old.engaged)) do
        local m = data.missions[mid]
        if not m then problems[#problems + 1] = a.key .. " mission " .. mid .. " disappeared"
        elseif not m.participants[id] then problems[#problems + 1] = a.key .. " no longer engaged in " .. mid end
    end
    for _, mid in ipairs(sortedKeys(a.old.invited)) do
        local m = data.missions[mid]
        if m and not (m.invited[id] or m.participants[id]) then
            problems[#problems + 1] = a.key .. " no longer invited to " .. mid
        end
    end
end

-- Active engaged missions of the snapshot still active now: list of { key, id, before, now }.
local function activeClocks(data, found)
    local out, seen = {}, {}
    for _, a in ipairs(found) do
        for _, mid in ipairs(sortedKeys(a.old.engaged)) do
            local old, m = a.old.engaged[mid], data.missions[mid]
            if not seen[mid] and old.state == "active" and type(old.remainingMs) == "number" then
                seen[mid] = true
                out[#out + 1] = { key = a.key, id = mid, before = old.remainingMs, m = m }
            end
        end
    end
    return out
end

local function ms(v)
    return string.format("%.0f", v) .. " ms"
end

-- A test NPC of Living Knox (RST.Fixtures.spawnNpc, removed after the test), its notebook fiche
-- (RS_CarnetServer.ensure) and an ACTIVE mission it requests with every character of members engaged
-- (RST.Fixtures.engagedMission, removed after the test unless keep); then after(t, m). SKIP outside a world run or
-- without the Living Knox test API (reason given).
local function engagedByNpc(t, server, store, members, keep, after)
    local allowed, refusal = RST.worldGuard()
    if not allowed then t:skip(refusal) end
    local ready, why = RST.Fixtures.npcReady()
    if not ready then t:skip("no test NPC: " .. tostring(why)) end
    local player = onlinePlayers()[1]
    if player == nil then t:skip("no online player") end
    RST.Fixtures.spawnNpc(t, player, function(t2, id)
        local npc = server.ensure(id)
        t2:ok(npc ~= nil, "no notebook fiche for the test npc " .. tostring(id))
        local m = RST.Fixtures.engagedMission(t2, store, npc, members, { tag = I.MISSION_TAG, keep = keep })
        t2:note("mission " .. m.id .. " of npc " .. id .. " (" .. tostring(npc.name) .. "), " .. count(m.participants)
            .. " participant(s), " .. ms(m.remainingMs) .. " left")
        return after(t2, m)
    end)
end

-- Missions made by these suites removed (kept from rs.identity.before for the after-* steps).
local function removeTestMissions(store)
    for _, m in ipairs(RST.Fixtures.testMissions(store.data, I.MISSION_TAG)) do RST.Fixtures.removeTestMission(store, m) end
end

-- ------------------------------------------------------------------------------------------------ live invariants

RST.suite("rs.identity", { tags = { "server" } }, function(s)
    s.test("notebook state ready", function(t)
        local _, store = carnet(t)
        t:ok(type(store.data.world) == "string" and type(store.run) == "string", "world or session id missing")
        t:note("world " .. store.data.world .. ", session " .. store.run .. ", " .. count(store.data.characters)
            .. " character record(s)")
    end)

    s.test("character records are well formed", function(t)
        local _, store = carnet(t)
        local problems = {}
        for _, id in ipairs(sortedKeys(store.data.characters)) do
            local r = store.data.characters[id]
            if r.id ~= id then problems[#problems + 1] = id .. " has id " .. tostring(r.id) end
            if type(r.owner) ~= "string" or r.owner == "" then problems[#problems + 1] = id .. " has no owner" end
            if type(r.slot) ~= "number" then problems[#problems + 1] = id .. " has no slot" end
            if type(r.contacts) ~= "table" or type(r.knownMissions) ~= "table" then
                problems[#problems + 1] = id .. " lacks contacts or knownMissions"
            end
        end
        report(t, problems, "malformed records")
    end)

    s.test("online players carry a usable identity of their own account", function(t)
        local server, store = carnet(t)
        local players = onlinePlayers()
        if #players == 0 then t:skip("no online player") end
        local problems, bound = {}, 0
        for _, player in ipairs(players) do
            local owner, slot = ownerOf(player), player:getPlayerNum()
            local key = accountKey(owner, slot)
            local md, b = identityOf(server, player)
            local id = md or b
            local r = id and store.data.characters[id]
            if not id then t:note(key .. ": no identity yet")
            elseif not r then problems[#problems + 1] = key .. " carries unknown identity " .. tostring(id)
            else
                if b then bound = bound + 1 end
                if md and b and md ~= b then problems[#problems + 1] = key .. " modData " .. md .. " ~= bound " .. b end
                if r.owner ~= owner or r.slot ~= slot then
                    problems[#problems + 1] = key .. " carries " .. id .. " of " .. accountKey(r.owner, r.slot)
                end
                if r.retired then problems[#problems + 1] = key .. " carries retired identity " .. id end
            end
        end
        t:note(#players .. " online player(s), " .. bound .. " bound")
        report(t, problems, "identity problems")
    end)

    s.test("no identity shared by two online players", function(t)
        local server = carnet(t)
        local players = onlinePlayers()
        if #players == 0 then t:skip("no online player") end
        local owners, problems = {}, {}
        for _, player in ipairs(players) do
            local md, b = identityOf(server, player)
            local key = accountKey(ownerOf(player), player:getPlayerNum())
            for _, id in ipairs({ md, b }) do
                if id and owners[id] and owners[id] ~= key then
                    problems[#problems + 1] = id .. " used by " .. owners[id] .. " and " .. key
                end
                if id then owners[id] = key end
            end
        end
        report(t, problems, "shared identities")
    end)

    s.test("no retired identity is bound", function(t)
        local server, store = carnet(t)
        local problems = {}
        for _, id in pairs(server.bound) do
            local r = store.data.characters[id]
            if not r then problems[#problems + 1] = "bound to unknown " .. tostring(id)
            elseif r.retired then problems[#problems + 1] = "bound to retired " .. id end
        end
        report(t, problems, "bindings")
    end)

    s.test("mission members are known characters", function(t)
        local _, store = carnet(t)
        local problems = {}
        for _, mid in ipairs(sortedKeys(store.data.missions)) do
            local m = store.data.missions[mid]
            for _, cid in ipairs(sortedKeys(m.participants)) do
                if not store.data.characters[cid] then problems[#problems + 1] = mid .. " participant " .. cid end
            end
            for _, cid in ipairs(sortedKeys(m.invited)) do
                if not store.data.characters[cid] then problems[#problems + 1] = mid .. " invited " .. cid end
            end
        end
        report(t, problems, "unknown members")
    end)

    -- E00-T01 in solo (no reconnection there): a mission really requested by a Living Knox NPC and engaged by the
    -- online account is in its account view and its clock follows the real time. Removed after the test.
    s.test("clock of a mission engaged with a real Living Knox NPC runs (world run)", function(t)
        local server, store = carnet(t)
        local found, problems = accounts(server, store.data)
        local keys = sortedKeys(found)
        if #keys == 0 then t:skip("no online account with an identity" .. (#problems > 0 and (": " .. problems[1]) or "")) end
        local a = found[keys[1]]
        engagedByNpc(t, server, store, { [a.character] = a.name ~= "" and a.name or a.owner }, false, function(t2, m)
            local view = describe(store.data, a.owner, a.slot, a.character)
            t2:ok(view.engaged[m.id] ~= nil and view.engaged[m.id].state == "active",
                keys[1] .. " does not see " .. m.id .. " as an active engaged mission")
            local before, at = m.remainingMs, RST.now()
            t2:sleep(I.CLOCK_WAIT_MS, function(t3)
                local used, elapsed = before - m.remainingMs, RST.now() - at
                t3:note(m.id .. ": " .. ms(used) .. " used for " .. ms(elapsed) .. " elapsed")
                t3:eq("active", m.state, "state of " .. m.id)
                t3:ok(math.abs(used - elapsed) <= I.LIVE_TOLERANCE_MS, m.id .. " used " .. ms(used) .. " for "
                    .. ms(elapsed) .. " elapsed")
            end)
        end)
    end)
end)

-- ------------------------------------------------------------------------------------------------ manual steps

RST.suite("rs.identity.before", { tags = { "server", "manual" } }, function(s)
    -- E00-T01 / E03-T04: the mission clock checks of the after-* steps need an active mission where the accounts
    -- are engaged. Kept for those steps (removed by rs.identity.after-restart and .after-death); reused when the
    -- step runs again before the next action.
    s.test("a mission of a real Living Knox NPC engages every online account", function(t)
        local server, store = carnet(t)
        local found = accounts(server, store.data)
        local members, missing = {}, 0
        for _, key in ipairs(sortedKeys(found)) do
            local a = found[key]
            local active = false
            for _, e in pairs(a.engaged) do if e.state == "active" then active = true end end
            members[a.character] = a.name ~= "" and a.name or a.owner
            if not active then missing = missing + 1 end
        end
        if count(members) == 0 then t:skip("no online account with an identity") end
        if missing == 0 then
            t:note("every online account is already engaged in an active mission")
            return
        end
        removeTestMissions(store)
        engagedByNpc(t, server, store, members, true, function(t2, m)
            t2:eq(count(members), count(m.participants), "participants of " .. m.id)
        end)
    end)

    s.test("snapshot of the online accounts written", function(t)
        local server, store = carnet(t)
        local found, problems = accounts(server, store.data)
        t:ok(#problems == 0, table.concat(problems, "; "))
        t:ok(count(found) > 0, "no online account with an identity: connect A and B first")
        for _, key in ipairs(sortedKeys(found)) do
            local a = found[key]
            t:ok(not a.retired, key .. " carries retired identity " .. a.character)
            t:ok(a.md == a.bound, key .. " modData " .. tostring(a.md) .. " ~= bound " .. tostring(a.bound))
            t:note(key .. ": " .. a.character .. ", " .. a.contacts .. " contact(s), " .. count(a.notes) .. " note(s), "
                .. count(a.engaged) .. " engaged, " .. count(a.invited) .. " invited")
        end
        local snapshot = { version = 1, world = store.data.world, run = store.run, savedAt = RST.now(),
            bootMs = RST_IdentityBootMs, accounts = found }
        local ok, why = writeSnapshot(snapshot)
        t:ok(ok, why)
        local back, reason = readSnapshot()
        t:ok(back ~= nil, reason)
        t:eq(snapshot, back, "snapshot read back")
        t:note("written " .. I.FILE)
    end)
end)

RST.suite("rs.identity.after-reconnect", { tags = { "server", "manual" } }, function(s)
    s.test("same world and session", function(t)
        local _, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        t:eq(snapshot.world, store.data.world, "world")
        t:eq(snapshot.run, store.run, "session changed: the server restarted, use rs.identity.after-restart")
    end)

    s.test("same identity for each account", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found, offline = pairUp(server, snapshot)
        requireOnline(t, found, offline)
        local problems = {}
        for _, a in ipairs(found) do checkSameIdentity(store.data, a, problems) end
        report(t, problems, "identity")
    end)

    s.test("notes and engagements kept", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found, offline = pairUp(server, snapshot)
        requireOnline(t, found, offline)
        local problems = {}
        for _, a in ipairs(found) do checkSameNotebook(store.data, a, problems) end
        report(t, problems, "notebook")
    end)

    s.test("mission clock ran during the disconnection", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found = pairUp(server, snapshot)
        local clocks = activeClocks(store.data, found)
        if #clocks == 0 then t:skip("no active engaged mission in the snapshot (needs an NPC provider, E17-T03)") end
        local elapsed = RST.now() - snapshot.savedAt
        local problems = {}
        for _, c in ipairs(clocks) do
            if c.m and c.m.state == "active" then
                local used = c.before - c.m.remainingMs
                t:note(c.id .. ": " .. ms(used) .. " used for " .. ms(elapsed) .. " elapsed")
                if math.abs(used - elapsed) > I.CLOCK_TOLERANCE_MS then
                    problems[#problems + 1] = c.id .. " used " .. ms(used) .. " for " .. ms(elapsed) .. " elapsed"
                end
            elseif c.before > elapsed + I.CLOCK_TOLERANCE_MS then
                problems[#problems + 1] = c.id .. " closed early (" .. tostring(c.m and c.m.state or "gone") .. ")"
            end
        end
        report(t, problems, "mission clock")
    end)
end)

RST.suite("rs.identity.after-restart", { tags = { "server", "manual" } }, function(s)
    s.test("new session of the same world", function(t)
        local _, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        t:eq(snapshot.world, store.data.world, "world")
        t:ok(snapshot.run ~= store.run, "same session " .. store.run .. ": the server did not restart")
        t:ok(RST_IdentityBootMs > snapshot.savedAt, "server Lua started before the snapshot")
        t:note("downtime at least " .. ms(RST_IdentityBootMs - snapshot.savedAt - I.RESTART_MARGIN_MS))
    end)

    s.test("same identity for each account", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found, offline = pairUp(server, snapshot)
        requireOnline(t, found, offline)
        local problems = {}
        for _, a in ipairs(found) do checkSameIdentity(store.data, a, problems) end
        report(t, problems, "identity")
    end)

    s.test("notes and engagements kept", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found, offline = pairUp(server, snapshot)
        requireOnline(t, found, offline)
        local problems = {}
        for _, a in ipairs(found) do checkSameNotebook(store.data, a, problems) end
        report(t, problems, "notebook")
    end)

    s.test("mission clock excludes the downtime", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local found = pairUp(server, snapshot)
        t:defer(function() removeTestMissions(store) end, "rs.identity test missions removed")
        local clocks = activeClocks(store.data, found)
        if #clocks == 0 then t:skip("no active engaged mission in the snapshot (needs an NPC provider, E17-T03)") end
        local downtime = RST_IdentityBootMs - snapshot.savedAt
        t:ok(downtime > I.RESTART_MARGIN_MS, "server down " .. ms(downtime) .. " after the snapshot: more than "
            .. ms(I.RESTART_MARGIN_MS) .. " needed to tell the downtime from the runtime")
        -- Runtime since the snapshot: at most the margin before quit plus the time since this Lua state started.
        local runtime = I.RESTART_MARGIN_MS + RST.now() - RST_IdentityBootMs
        local problems = {}
        for _, c in ipairs(clocks) do
            if c.m and c.m.state == "active" then
                local used = c.before - c.m.remainingMs
                t:note(c.id .. ": " .. ms(used) .. " used, runtime at most " .. ms(runtime) .. ", downtime "
                    .. ms(downtime))
                if used > runtime then problems[#problems + 1] = c.id .. " used " .. ms(used) .. " > " .. ms(runtime) end
                if used < -I.CLOCK_TOLERANCE_MS then problems[#problems + 1] = c.id .. " gained " .. ms(-used) end
            elseif c.before > runtime then
                problems[#problems + 1] = c.id .. " closed during the restart (" .. tostring(c.m and c.m.state or "gone")
                    .. ")"
            end
        end
        report(t, problems, "mission clock")
    end)
end)

-- Accounts of the snapshot split into dead (identity changed) and survivors.
local function splitByDeath(server, snapshot)
    local found, offline = pairUp(server, snapshot)
    local dead, alive = {}, {}
    for _, a in ipairs(found) do
        if (a.md or a.bound) == a.old.character then alive[#alive + 1] = a else dead[#dead + 1] = a end
    end
    return dead, alive, offline
end

RST.suite("rs.identity.after-death", { tags = { "server", "manual" } }, function(s)
    s.test("same world", function(t)
        local _, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        t:eq(snapshot.world, store.data.world, "world")
    end)

    s.test("dead account: old identity retired and unused", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local dead, _, offline = splitByDeath(server, snapshot)
        if #offline > 0 then t:note("offline, not checked: " .. table.concat(offline, ", ")) end
        t:ok(#dead > 0, "no online account changed identity: did A die and create a new character?")
        local problems = {}
        for _, a in ipairs(dead) do
            local old = a.old.character
            local r = store.data.characters[old]
            if not r then problems[#problems + 1] = a.key .. " old record " .. old .. " is missing"
            elseif not r.retired then problems[#problems + 1] = a.key .. " old identity " .. old .. " is not retired" end
            for player, id in pairs(server.bound) do
                if id == old then problems[#problems + 1] = old .. " still bound to " .. tostring(ownerOf(player)) end
            end
            for _, p in ipairs(onlinePlayers()) do
                if p:getModData()[I.KEY] == old then
                    problems[#problems + 1] = old .. " still in the modData of " .. tostring(ownerOf(p))
                end
            end
            t:note(a.key .. ": " .. old .. " -> " .. tostring(a.md or a.bound))
        end
        report(t, problems, "old identity")
    end)

    s.test("new character: new identity without the old missions or notes", function(t)
        local server, store = carnet(t)
        local snapshot = snapshotOrFail(t)
        local dead = splitByDeath(server, snapshot)
        t:ok(#dead > 0, "no online account changed identity: did A die and create a new character?")
        local problems = {}
        for _, a in ipairs(dead) do
            local id = a.md or a.bound
            local r = id and store.data.characters[id]
            if not id then problems[#problems + 1] = a.key .. " new character has no identity yet"
            elseif not r then problems[#problems + 1] = a.key .. " new identity " .. id .. " has no record"
            else
                if a.md ~= a.bound then problems[#problems + 1] = a.key .. " modData " .. tostring(a.md) .. " ~= bound "
                    .. tostring(a.bound) end
                if r.retired then problems[#problems + 1] = a.key .. " new identity " .. id .. " is retired" end
                if r.owner ~= a.old.owner or r.slot ~= a.old.slot then
                    problems[#problems + 1] = a.key .. " new identity " .. id .. " belongs to "
                        .. accountKey(r.owner, r.slot)
                end
                local old = {}
                for mid in pairs(a.old.engaged) do old[mid] = true end
                for mid in pairs(a.old.invited) do old[mid] = true end
                for mid in pairs(a.old.known) do old[mid] = true end
                for _, mid in ipairs(sortedKeys(old)) do
                    local m = store.data.missions[mid]
                    if m and (m.participants[id] or m.invited[id]) then
                        problems[#problems + 1] = a.key .. " new character resumed " .. mid
                    end
                    if r.knownMissions[mid] then problems[#problems + 1] = a.key .. " new character knows " .. mid end
                end
                for _, npc in ipairs(sortedKeys(a.old.notes)) do
                    local known = r.contacts[npc]
                    if known and known.note == a.old.notes[npc] then
                        problems[#problems + 1] = a.key .. " new character inherited the note on " .. npc
                    end
                end
            end
        end
        report(t, problems, "new character")
    end)

    s.test("other accounts keep their identity and missions", function(t)
        local server, store = carnet(t)
        t:defer(function() removeTestMissions(store) end, "rs.identity test missions removed")
        local snapshot = snapshotOrFail(t)
        local _, alive = splitByDeath(server, snapshot)
        if #alive == 0 then t:skip("no other account of the snapshot online (B)") end
        local problems = {}
        for _, a in ipairs(alive) do
            checkSameIdentity(store.data, a, problems)
            checkSameNotebook(store.data, a, problems)
            -- The death of a participant closes nothing: the mission state is only reported.
            for _, mid in ipairs(sortedKeys(a.old.engaged)) do
                local m = store.data.missions[mid]
                if m then t:note(a.key .. " " .. mid .. ": " .. tostring(a.old.engaged[mid].state) .. " -> " .. m.state) end
            end
        end
        report(t, problems, "other accounts")
    end)
end)
