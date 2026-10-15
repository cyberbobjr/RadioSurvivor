--[[
rs.radio - radio tab of the notebook in multiplayer (E06-T05; history of E06-T01/E06-T04: server/RadioSurvivor/
RS_RadioLog.lua kept by the authority, client/RadioSurvivor/RS_RadioHistory.lua on each client). The clients send the
REAL radio command "talk" and read their own Radio tab (RST.Steps "rs.talk", "rs.history", RST_PeerChecksRadio.lua).
    no radio      every client whose server copy carries no two-way radio (hands, back) sends a sentence: refused
                  "NoRadio", and no history line is added to any character.
    two players   each player (requester, and the second client in MP) is given a walkie-talkie held in the main hand
                  on the server; the requester and the second client speak on one free frequency, then the second
                  client alone on another one (silence path: no voice listens there). Each client then reads its
                  Radio tab (history asked to the server like the notebook does): its own sentences are there as
                  "said" on the right frequency, a sentence of the other player only as "heard" (never "said"), the
                  other frequency of the second client never in the requester's tab, and every history command the
                  client ever received named its own character only. The server state agrees.
    reconnection  base rs.radiotab of the phased MP run (RS_RadioPersist.lua: rs.radiotab.before, .after-reconnect;
                  campaign mp-persist), not here: a plain run never reconnects a client.
Tags "server" and "world": the authority (solo, or RST.server from an admin client), save rstest*. Solo runs the same
code with the local player only (second-client parts noted). MP: autoclient.py --mp --clients 2 --server-suite
rs.radio --server-tags world. Cleanup: walkie-talkies taken back (RST.Fixtures.giveItem), former main hand items held
again, test sentences removed from the histories. Outside the game: tests/test_rs_mp_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

local PR = RST.PeerRadio
local Steps = RST.Steps
local MARK = "RST radiotab "
local WALKIE = "Base.WalkieTalkie5"

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the radio history lives on the authority (solo or dedicated server), not on an MP client")
    end
    local okC, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    t:ok(okC and type(Const) == "table" and Const.CMD ~= nil and Const.CMD.HISTORY ~= nil,
        "RadioSurvivor_Const (E06-T04) not loaded")
    local okP, Personas = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(okP and type(Personas) == "table", "RadioSurvivor/RS_Personas not loaded on this side")
    t:ok(type(RS_RadioServer) == "table", "RadioSurvivor_Server.lua (talk command) not loaded on this side")
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    if not Const.isEnabled() then t:skip("sandbox option RadioSurvivor.Enabled is off") end
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    t:defer(function() PR.stripHistory(MARK) end, "test sentences removed from the radio histories")
    return { Const = Const, P = Personas, Server = Server, S = Server.store, p = p }
end

local function freeKhz(P, except)
    local k = 90200
    while k <= 1000000 do
        if k ~= except and P.voiceAt(k) == nil and P.channel(k) == nil then return k end
        k = k + 200
    end
    return nil
end

local n = 0
local function sentence(tag)
    n = n + 1
    return MARK .. tag .. " " .. tostring(ZombRand(1000, 9999)) .. "-" .. n
end

-- A two-way radio held or worn where the server looks (RadioSurvivor_Server.carriedRadio).
local function carriesTransmitter(player)
    local items = { player:getPrimaryHandItem(), player:getSecondaryHandItem(), player:getClothingItem_Back() }
    for i = 1, 3 do
        local it = items[i]
        if it ~= nil and instanceof(it, "Radio") then
            local data = it:getDeviceData()
            if data ~= nil and data:getIsTwoWay() then return true end
        end
    end
    return false
end

local function lineCount(S, cid)
    local record = cid and S.data.characters[cid]
    local total = 0
    for _, f in ipairs(record and record.radio and record.radio.frequencies or {}) do total = total + #(f.lines or {}) end
    return total
end

-- Kinds of the lines of text in the private history of a character: { "khz:kind", ... }.
local function serverLines(S, cid, text)
    local out = {}
    local record = cid and S.data.characters[cid]
    for _, f in ipairs(record and record.radio and record.radio.frequencies or {}) do
        for _, line in ipairs(f.lines or {}) do
            if line.text == text then out[#out + 1] = tostring(f.khz) .. ":" .. tostring(line.kind) end
        end
    end
    return out
end

local function has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- Walkie-talkie given to the player and held in its main hand on the server, on, battery full.
local function walkieInHand(t, player)
    local item = RST.Fixtures.giveItem(t, player, WALKIE)[1]
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

-- One sentence of one client on khz with its walkie-talkie: accepted (silence path, no voice there).
local function say(t, who, khz, text, after)
    who.data:setChannelRaw(khz)
    Steps.ask(t, "rs.talk", { args = { text = text, channel = khz, itemId = who.item:getID() } },
        { target = { who.name }, timeoutMs = PR.TALK_MS }, function(t2, res)
            local e = res.by[who.name]
            t2:eq("accepted", e and e.data and e.data.command, who.label .. " on " .. khz .. " kHz")
            return after(t2)
        end)
end

RST.suite("rs.radio", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 240000 }, function(s)
    s.test("talk without a radio is refused (NoRadio) and adds no history line (E06-T05)", function(t)
        local c = authority(t)
        local expect, counts = {}, {}
        for _, e in ipairs(Steps.targets(t, "all")) do
            local player = PR.player(t, e.name)
            if player ~= nil and not carriesTransmitter(player) then expect[e.name] = true end
        end
        local requester = (type(isServer) == "function" and isServer()) and c.p:getUsername() or Steps.LOCAL
        if not expect[requester] then t:skip("the requester holds a two-way radio: remove it from the hands and back") end
        for player, cid in pairs(c.Server.bound) do counts[cid] = lineCount(c.S, cid) end
        local khz = freeKhz(c.P)
        Steps.ask(t, "rs.talk", { args = { text = sentence("noradio"), channel = khz } },
            { target = "all", timeoutMs = PR.TALK_MS }, function(t2, res)
                for _, e in ipairs(res.list) do
                    if expect[e.user] then
                        t2:eq("rejected NoRadio", tostring(e.data and e.data.command) .. " "
                            .. tostring(e.data and e.data.reason), "client " .. e.user)
                    else
                        t2:note("client " .. e.user .. " carries a two-way radio: not checked")
                    end
                end
                for cid, before in pairs(counts) do
                    t2:eq(before, lineCount(c.S, cid), "history lines of " .. cid .. " changed by a refused sentence")
                end
            end)
    end)

    s.test("two players, one then two frequencies: each Radio tab holds only its own lines (E06-T05)", function(t)
        local c = authority(t)
        local mp = type(isServer) == "function" and isServer()
        local me = { name = mp and c.p:getUsername() or Steps.LOCAL, player = c.p, label = "requester" }
        local peers = { me }
        local others = Steps.others(t)
        if others[1] ~= nil and Steps.playerOf(others[1]) ~= nil then
            peers[2] = { name = others[1], player = Steps.playerOf(others[1]), label = "client " .. others[1] }
        else
            t:note("no second client online: the requester alone (solo or one client)")
        end
        for _, who in ipairs(peers) do
            who.cid = c.Server.bound[who.player]
            t:ok(type(who.cid) == "string", "no notebook character bound to " .. who.label .. " (hello not received)")
            who.item = walkieInHand(t, who.player)
            who.data = who.item:getDeviceData()
        end
        local khz1 = freeKhz(c.P)
        local khz2 = freeKhz(c.P, khz1)
        t:ok(khz1 ~= nil and khz2 ~= nil, "no free frequency")
        local other = peers[2]
        me.texts = { sentence("A1") }
        local texts = { me.texts[1] }
        if other ~= nil then
            other.texts = { sentence("B1"), sentence("B2") }
            texts[2], texts[3] = other.texts[1], other.texts[2]
        end
        local function readTabs(t3)
            Steps.ask(t3, "rs.history", { texts = texts }, { target = "all", timeoutMs = PR.HISTORY_MS }, function(t4, res)
                for _, e in ipairs(res.list) do
                    local who = (PR.player(t4, e.user) == c.p) and me or other
                    local d = e.data or {}
                    if who ~= nil then
                        t4:eq(who.cid, d.character, who.label .. ": character of the Radio tab")
                        t4:eq({ who.cid }, d.characters, who.label .. ": history commands of another character received")
                        local found = d.found or {}
                        t4:ok(has(found[who.texts[1]], khz1 .. ":said"), who.label .. ": own sentence missing on " .. khz1)
                        if who == other then
                            t4:ok(has(found[who.texts[2]], khz2 .. ":said"), who.label .. ": own sentence missing on "
                                .. khz2)
                        end
                        for _, text in ipairs(texts) do
                            if not has(who.texts, text) then
                                for _, entry in ipairs(found[text] or {}) do
                                    t4:eq(khz1 .. ":heard", entry, who.label .. ": line of the other player '" .. text
                                        .. "'")
                                end
                            end
                        end
                    end
                end
                -- Private state of the authority agrees with the tabs.
                for _, who in ipairs(peers) do
                    for _, text in ipairs(texts) do
                        local lines = serverLines(c.S, who.cid, text)
                        if has(who.texts, text) then
                            t4:ok(#lines == 1 and string.find(lines[1], ":said$") ~= nil, who.label .. " server lines of '"
                                .. text .. "': " .. table.concat(lines, ", "))
                        else
                            t4:ok(not has(lines, khz1 .. ":said") and not has(lines, khz2 .. ":said")
                                and not has(lines, khz2 .. ":heard"), who.label .. " holds a line of the other player: "
                                .. table.concat(lines, ", "))
                        end
                    end
                end
            end)
        end
        say(t, me, khz1, me.texts[1], function(t1)
            if other == nil then return readTabs(t1) end
            say(t1, other, khz1, other.texts[1], function(t2)
                say(t2, other, khz2, other.texts[2], readTabs)
            end)
        end)
    end)

    s.skip("history kept across a reconnection (E06-T05)",
        "checked by the base rs.radiotab of the phased MP run (mp-persist: rs.radiotab.before, .after-reconnect)")
end)
