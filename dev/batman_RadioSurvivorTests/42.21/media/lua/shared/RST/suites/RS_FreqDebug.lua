--[[
rs.freqdebug - frequencies of the game for the debug panel (E05-T14): server/RadioSurvivor/RS_FreqDebug.lua answers
the window client/RadioSurvivor/RS_FreqDebugView.lua (button "Radio Survivor - Frequencies" of the vanilla debug
panel) with every voice of RadioSurvivor (id, name, state, frequencies of this game, served frequencies, ranges, radio
needed, listening hours) and the other frequencies of the mod (evening bulletin of the chronicler). Same rights as
the Living Knox debug tools: solo = debug mode, server = capability PopmanManage, checked on EVERY request.
Checked here: refusal without an allowed player (no data); the answer for the target player (t.ctx.player, or the
local player in solo) is faithful to RS_Personas (ids in load order, frequencies, served frequencies backed by a
real channel of the voice, state, name, radio, ranges, listening hours) and to the bulletin of RS_Facts; the cells of
the window (solo only, where the client module is loaded).
Tag "server": the authority only (dedicated server or solo); read only, any save. Solo (debug mode):
RST.run({ suite = "rs.freqdebug" }). Dedicated server: RST.server({ suite = "rs.freqdebug" }) from an admin client.
E01-T16: refusal of a real client with the access level "user" (second client of the MP campaign; SKIP in solo).
Not checked here: the debug menu button and the window itself (docs/tests-en-jeu.md, section of E05-T14).
Outside the game: tests/test_rs_freqdebug.py.
]]

require "RST/RST"
require "RST/RST_PeerChecks"

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("frequencies live on the authority (RS_FreqDebug is not loaded on an MP client)")
    end
    local F = RS_FreqDebug
    t:ok(type(F) == "table" and type(F.request) == "function", "RS_FreqDebug is not loaded on this side")
    local ok, P = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(ok and type(P) == "table", "RadioSurvivor/RS_Personas is not loaded on this side")
    return F, P
end

local function target(t)
    local p = t.ctx and t.ctx.player or nil
    if p == nil and not isServer() and getPlayer ~= nil then p = getPlayer() end
    if p == nil then t:skip("no target player (t.ctx.player)") end
    return p
end

local function sameList(t, want, got, what)
    t:eq(#want, #(got or {}), what .. " (count)")
    for i, v in ipairs(want) do t:eq(v, got[i], what .. " #" .. i) end
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

RST.suite("rs.freqdebug", { tags = { "server" } }, function(s)
    s.test("module exports", function(t)
        local F = module(t)
        for _, name in ipairs({ "isAllowed", "view", "request", "onClientCommand" }) do
            t:eq("function", type(F[name]), "RS_FreqDebug." .. name)
        end
        t:eq("RadioSurvivorDebug", F.MODULE, "command module")
        t:eq("PopmanManage", F.CAPABILITY, "capability")
    end)

    s.test("a request without an allowed player is refused without data", function(t)
        local F = module(t)
        local r = F.request(nil, { op = F.OP, n = 5 })
        t:eq(false, r.ok, "request accepted")
        t:eq("denied", r.err, "error")
        t:eq(5, r.n, "request number")
        for k in pairs(r) do
            t:ok(k == "n" or k == "op" or k == "ok" or k == "err", "refusal carries the field " .. k)
        end
    end)

    -- E01-T16: a real second client with the access level "user" (MP campaign, autoclient.py --mp --clients 2).
    s.test("a real client with the user role is refused without data (E01-T16)", function(t)
        local F = module(t)
        RST.PeerChecks.refusedForUser(t, { { label = "frequencies", spec = { module = F.MODULE,
            command = F.CMD_REQUEST, args = { op = F.OP, n = 730 } } } },
            function() return F.stats.refused or 0 end)
    end)

    s.test("answer faithful to the voices of the game", function(t)
        local F, P = module(t)
        local p = target(t)
        if not F.isAllowed(p) then t:skip("target player not allowed (debug mode in solo, admin role on a server)") end
        local r = F.request(p, { op = F.OP, n = 9 })
        t:ok(r.ok, "request refused: " .. tostring(r.err))
        t:eq(9, r.n, "request number")
        local ids = P.ids()
        t:ok(#ids > 0, "no voice loaded")
        t:eq(#ids, #r.voices, "voices in the answer")
        for i, id in ipairs(ids) do
            local v, sheet = r.voices[i], P.get(id)
            t:eq(id, v.id, "voice #" .. i)
            t:eq(sheet.name, v.name, id .. " name")
            t:eq(sheet.state, v.state, id .. " state")
            t:eq(sheet.radio, v.radio, id .. " radio")
            sameList(t, P.frequencies(id), v.frequencies, id .. " frequencies")
            sameList(t, P.served(id), v.served, id .. " served frequencies")
            t:eq(#sheet.frequency_ranges, #v.ranges, id .. " ranges")
            t:eq(#sheet.listen, #v.listen, id .. " listening ranges")
            for _, khz in ipairs(v.served) do
                t:ok(contains(v.frequencies, khz), id .. " serves " .. khz .. " outside its frequencies")
                t:eq(id, P.voiceAt(khz), "voice of " .. khz)
                t:ok(P.channel(khz) ~= nil, "no channel of " .. id .. " on " .. khz)
            end
            t:note(id .. " " .. tostring(v.state) .. ": " .. table.concat(v.frequencies, ", "))
        end
        local F2 = RS_Facts
        if type(F2) == "table" and type(F2.CHRONICLER) == "string" then
            local o = r.others[1]
            t:ok(o ~= nil and o.kind == "bulletin", "evening bulletin missing from the other frequencies")
            t:eq(F2.CHRONICLER, o.voice, "voice of the bulletin")
            t:eq(RS_RadioServer.frequency(F2.CHRONICLER), o.khz, "frequency of the bulletin")
        end
        local V = RS_FreqDebugView
        if V ~= nil and V.voiceCells ~= nil and r.voices[1] ~= nil then
            local cells = V.voiceCells(r.voices[1])
            t:eq(r.voices[1].id, cells.id, "id cell")
            t:ok(type(cells.freqs) == "string" and type(cells.listen) == "string", "frequency and listening cells")
        end
    end)
end)
