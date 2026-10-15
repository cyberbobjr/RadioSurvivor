--[[
rs.radiotab persistence steps (E06-T05: "historique conserve apres reconnexion", E06-T01; server/RadioSurvivor/
RS_RadioLog.lua on the authority, client/RadioSurvivor/RS_RadioHistory.lua on each client). Base "rs.radiotab" of the
phased MP run (autoclient.py --mp --clients 2 --phases reconnect2,reconnect,restart --server-campaign mp-persist):
    rs.radiotab.before            (opt-in "manual") the requester and the second client each hold a walkie-talkie
                                  (server side, main hand) and speak with the REAL radio command "talk" (RST.Steps
                                  "rs.talk"): both on one free frequency, then the second client alone on another one.
                                  The sentences, the frequencies and the notebook character of each account are written
                                  to the snapshot. The lines stay in the private histories (no cleanup of them here).
    rs.radiotab.after-reconnect   both clients left and joined again: every account of the snapshot, once bound
                                  again to its notebook character, reads its Radio tab (RST.Steps "rs.history",
                                  history asked to the server as the notebook does): same character as before, exactly
                                  the lines its server history held at the snapshot (own sentences "said" on their
                                  frequency, the other player's shared sentence at most "heard", nothing of the other
                                  player's private frequency: checked at the snapshot), the server history unchanged,
                                  and every history command it received named its own character only. Then the test
                                  lines are removed from the histories and the snapshot is consumed.
Every radio is tuned to the shared frequency before anyone speaks; the snapshot is taken after the three sentences.
No step after reconnect2: its .before would run in the last run of step 0, with lk.rejoin.before (requester sent away).
Run again, .before first removes the lines of an earlier run (prefix MARK). Without a second client the requester is
checked alone (noted); solo: SKIP (no reconnection without the launcher).
Tags "server", "world", "manual": authority only, test saves rstest*, exact names only. Snapshot:
Zomboid/Lua/batman_RadioSurvivor/tests/radiotab-persist.txt of the server (RST_Persist).
Outside the game: tests/test_persist_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_Persist"
require "RST/RST_PeerChecksRadio"

RST.RadioPersist = RST.RadioPersist or {}
local RPx = RST.RadioPersist
local PR = RST.PeerRadio
local Steps = RST.Steps

RPx.FILE = "radiotab-persist.txt"
RPx.HEADER = "RSRADIOTAB1"
RPx.MARK = "RST radiopersist "
RPx.WALKIE = "Base.WalkieTalkie5"
RPx.BOUND_MS = 30000   -- each account bound again to its notebook character after the reconnection

local function isServerSide() return type(isServer) == "function" and isServer() end

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the radio history lives on the authority (dedicated server), not on an MP client")
    end
    if not isServerSide() then
        t:skip("persistence across a reconnection: phased MP run only (autoclient.py --phases, base rs.radiotab)")
    end
    local okC, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    t:ok(okC and type(Const) == "table" and Const.CMD ~= nil and Const.CMD.HISTORY ~= nil,
        "RadioSurvivor_Const (E06-T04) not loaded")
    local okP, Personas = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(okP and type(Personas) == "table", "RadioSurvivor/RS_Personas not loaded on this side")
    local Server = RS_CarnetServer
    t:ok(type(Server) == "table" and type(Server.store) == "table" and Server.store.data ~= nil,
        "notebook server state not ready (RS_CarnetServer)")
    t:ok(Const.isEnabled(), "sandbox option RadioSurvivor.Enabled is off")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    return { Const = Const, P = Personas, Server = Server, S = Server.store, p = p }
end

local function freeKhz(P, except)
    local k = 91400
    while k <= 1000000 do
        if k ~= except and P.voiceAt(k) == nil and P.channel(k) == nil then return k end
        k = k + 200
    end
    return nil
end

-- Walkie-talkie given to the player and held in its main hand on the server, on, battery full (as rs.radio).
local function walkieInHand(t, player)
    local item = RST.Fixtures.giveItem(t, player, RPx.WALKIE)[1]
    local previous = player:getPrimaryHandItem()
    player:setPrimaryHandItem(item)
    t:defer(function()
        if player:getPrimaryHandItem() == item then player:setPrimaryHandItem(previous) end
    end, "former main hand item held again")
    local data = item:getDeviceData()
    data:setHasBattery(true)
    data:setPower(1.0)
    data:setTurnedOnRaw(true)
    data:setMicIsMuted(false)
    return item
end

local function say(t, who, khz, text, after)
    who.data:setChannelRaw(khz)
    Steps.ask(t, "rs.talk", { args = { text = text, channel = khz, itemId = who.item:getID() } },
        { target = { who.name }, timeoutMs = PR.TALK_MS }, function(t2, res)
            local e = res.by[who.name]
            t2:eq("accepted", e and e.data and e.data.command, who.name .. " on " .. khz .. " kHz")
            return after(t2)
        end)
end

-- Kinds of the lines of text in the private history of a character, sorted: { "khz:kind", ... }.
function RPx.serverLines(S, cid, text)
    local out = {}
    local record = cid and S.data.characters[cid]
    for _, f in ipairs(record and record.radio and record.radio.frequencies or {}) do
        for _, line in ipairs(f.lines or {}) do
            if line.text == text then out[#out + 1] = tostring(f.khz) .. ":" .. tostring(line.kind) end
        end
    end
    table.sort(out)
    return out
end

-- Privacy of one account's history at the snapshot: its own sentences once as "said" on their frequency; a sentence
-- of the other player never "said", and its private frequency never at all.
function RPx.checkPrivate(t, snap, u, lines)
    for _, v in ipairs(snap.users) do
        for _, sd in ipairs(v.said) do
            local got = lines[sd.text] or {}
            if v.name == u.name then
                t:eq({ sd.khz .. ":said" }, got, u.name .. ": own line '" .. sd.text .. "'")
            else
                for _, e in ipairs(got) do
                    t:eq(snap.khz1 .. ":heard", e, u.name .. ": line of the other player '" .. sd.text .. "'")
                end
            end
        end
    end
end

-- Assertions on one Radio tab answer (data of rs.history) for the account u of the snapshot: the same lines as the
-- server history held at the snapshot, same character, no history command of another character.
function RPx.checkTab(t, snap, u, d)
    d = d or {}
    t:eq(u.cid, d.character, u.name .. ": character of the Radio tab after the reconnection")
    t:eq({ u.cid }, d.characters, u.name .. ": history commands of another character received")
    local found = d.found or {}
    for _, v in ipairs(snap.users) do
        for _, sd in ipairs(v.said) do
            local got = {}
            for i, e in ipairs(found[sd.text] or {}) do got[i] = e end
            table.sort(got)
            t:eq(u.lines[sd.text] or {}, got, u.name .. ": line '" .. sd.text .. "' after the reconnection")
        end
    end
end

RST.suite("rs.radiotab.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 90000 }, function(s)
    s.test("two players speak on one then two frequencies, lines written to the snapshot (E06-T05)", function(t)
        local c = authority(t)
        local removed = PR.stripHistory(RPx.MARK)
        if removed > 0 then t:note(removed .. " line(s) of an earlier run removed from the histories") end
        local me = { name = c.p:getUsername(), player = c.p }
        local peers = { me }
        local others = Steps.others(t)
        if others[1] ~= nil and Steps.playerOf(others[1]) ~= nil then
            peers[2] = { name = others[1], player = Steps.playerOf(others[1]) }
        else
            t:note("no second client online: the requester alone is checked after the reconnection")
        end
        for _, who in ipairs(peers) do
            who.cid = c.Server.bound[who.player]
            t:ok(type(who.cid) == "string", "no notebook character bound to " .. who.name .. " (hello not received)")
            who.item = walkieInHand(t, who.player)
            who.data = who.item:getDeviceData()
        end
        local khz1 = freeKhz(c.P)
        local khz2 = freeKhz(c.P, khz1)
        t:ok(khz1 ~= nil and khz2 ~= nil, "no free frequency")
        local stamp = tostring(math.floor(RST.now()))
        local snap = { khz1 = khz1, khz2 = khz2, users = {} }
        for i, who in ipairs(peers) do
            local u = { name = who.name, cid = who.cid, said = { { khz = khz1, text = RPx.MARK .. stamp .. " " .. i
                .. "-shared" } } }
            if i == 2 then u.said[2] = { khz = khz2, text = RPx.MARK .. stamp .. " " .. i .. "-private" } end
            snap.users[i] = u
            who.u = u
        end
        local function written(t3)
            for _, u in ipairs(snap.users) do
                u.lines = {}
                for _, v in ipairs(snap.users) do
                    for _, sd in ipairs(v.said) do u.lines[sd.text] = RPx.serverLines(c.S, u.cid, sd.text) end
                end
                RPx.checkPrivate(t3, snap, u, u.lines)
            end
            local ok, why = RST.Persist.write(RPx.FILE, RPx.HEADER, snap)
            t3:ok(ok, "snapshot not written: " .. tostring(why))
            t3:note("snapshot: " .. #snap.users .. " account(s), frequencies " .. khz1 .. " and " .. khz2)
        end
        for _, who in ipairs(peers) do who.data:setChannelRaw(khz1) end
        local other = peers[2]
        say(t, me, khz1, me.u.said[1].text, function(t1)
            if other == nil then return written(t1) end
            say(t1, other, khz1, other.u.said[1].text, function(t2)
                say(t2, other, khz2, other.u.said[2].text, written)
            end)
        end)
    end)
end)

-- Declared with a literal name: autoclient.py (declared_suite_names) finds the steps of a base in the sources.
RST.suite("rs.radiotab.after-reconnect", { tags = { "server", "world", "manual" }, testTimeoutMs = 90000 }, function(s)
    s.test("Radio tab of each player kept after the reconnection of both clients, nothing of the other player "
        .. "(E06-T05)", function(t)
            local c = authority(t)
            local snap, why = RST.Persist.read(RPx.FILE, RPx.HEADER)
            t:ok(snap ~= nil, tostring(why))
            t:defer(function()
                PR.stripHistory(RPx.MARK)
                RST.Persist.consume(RPx.FILE)
            end, "test lines removed from the radio histories, snapshot consumed")
            local names = {}
            for i, u in ipairs(snap.users) do names[i] = u.name end
            t:ok(type(snap.users) == "table" and #snap.users >= 1, "snapshot without account")
            t:waitUntil(function()
                for _, u in ipairs(snap.users) do
                    local player = Steps.playerOf(u.name)
                    if player == nil or c.Server.bound[player] == nil then return false end
                end
                return true
            end, RPx.BOUND_MS, function(t2)
                local texts = {}
                for _, u in ipairs(snap.users) do
                    for _, sd in ipairs(u.said) do texts[#texts + 1] = sd.text end
                end
                Steps.ask(t2, "rs.history", { texts = texts }, { target = names, timeoutMs = PR.HISTORY_MS },
                    function(t3, res)
                        for _, u in ipairs(snap.users) do
                            local e = res.by[u.name]
                            RPx.checkTab(t3, snap, u, e and e.data)
                            t3:eq(u.cid, c.Server.bound[Steps.playerOf(u.name)],
                                u.name .. ": notebook character after the reconnection")
                            local lines = {}
                            for _, text in ipairs(texts) do lines[text] = RPx.serverLines(c.S, u.cid, text) end
                            t3:eq(u.lines, lines, u.name .. ": server history after the reconnection")
                        end
                    end)
            end, function()
                return "accounts of the snapshot not back and bound to their notebook character: "
                    .. table.concat(names, ", ")
            end)
        end)
end)
