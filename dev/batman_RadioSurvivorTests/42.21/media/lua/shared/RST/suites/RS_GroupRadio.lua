--[[
rs.groupradio - radio of the equipped groups (E08-T06, server/RadioSurvivor/RS_GroupRadio.lua): every Living Knox group
that holds a transmitter a living member can use (type format 2: settlers and, since E08-T10, raiders have a station at
home) is a radio voice with a frequency drawn for the game in 75.0-149.8 MHz; a group without transmitter is none; a
call on the frequency becomes an npc_talk request of the group speaker in the notebook queue (no offer, no home
position); with the bridge running, the reply goes on the air of the group frequency. Tags "world" and "server": a
save named rstest*, with a target player (t.ctx.player); Living Knox enabled. Solo: RST.run({ suite = "rs.groupradio",
tags = "world" }); dedicated server (campaign mp, E01-T19): RST.server({ suite = "rs.groupradio", tags = "world" })
from an admin client. When no group holds a transmitter in this world, the tests that need one create a settlers
group near the player (RST.LKGroup, RST_LKGroupFixture.lua, removed at the end) instead of a SKIP. The call test binds
the notebook character of the player when missing (RST.RSHelpers.character: "hello" asked directly) and uses the
caller key of RadioSurvivor_Server (account name on a server, "solo" in solo).
The last test needs the bridge program running (bridge/radio_bridge.py); without it it fails after 60 s (no answer:
static and NoAnswer, covered by tests/test_group_radio.py). Every test removes its request with t:defer.
E17-T12: the first test cuts a long reply (accents, ellipsis, decimal) into radio lines in the real Kahlua VM (each line
shown alone by the receiver, one after the other): cut at a sentence end, then a comma, never inside a word; the last
test measures the lines really aired for the bridge reply (no line cut mid-sentence when a sentence end was possible).
E08-T10 (decision of 2026-10-14): raiders hold a station at their camp too (type format 2, homeRadio). A test creates a
raiders group and a neutrals group, each with one npc member (registry only, no body: homes 400 squares east of the
player, out of the loaded area), and checks that the raiders are a voice with a frequency of the range and the
neutrals none; both groups, their npcs and the voices are removed afterwards (t:defer). Needs Living Knox only (no
settlers group in the world needed for this test).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_RSHelpers"

RST.RSGroupRadio = RST.RSGroupRadio or {}

-- Next step after(t2, Server, R, Personas, radios) once a group holds a transmitter (the fixture group of
-- RST_LKGroupFixture.lua when none does: E01-T19).
local function setup(t, after)
    if isClient() then t:skip("authority only (solo, or RST.server in MP)") end
    local Server = RS_CarnetServer
    t:ok(Server ~= nil and Server.store.data ~= nil, "notebook server not ready")
    local P = require "RadioSurvivor/RS_NPCProvider"
    if not P.available() then t:skip("Living Knox is not the active NPC provider") end
    local R = require "RadioSurvivor/RS_GroupRadio"
    local Personas = require "RadioSurvivor/RS_Personas"
    local function equipped()
        R.refresh()
        return #P.radios() > 0
    end
    RST.LKGroup.ensure(t, nil, function(t2)
        R.refresh()
        local radios = P.radios()
        if #radios == 0 then t2:skip("no group holds a transmitter in this world (settlers or raiders needed)") end
        return after(t2, Server, R, Personas, radios)
    end, { ready = equipped })
end

-- true when a number of value equals x or y (home of the group), at any depth.
local function holds(value, x, y, depth)
    if type(value) == "number" then return value == x or value == y end
    if type(value) == "string" then
        return string.find(value, tostring(x), 1, true) ~= nil or string.find(value, tostring(y), 1, true) ~= nil
    end
    if type(value) ~= "table" or depth > 6 then return false end
    for _, v in pairs(value) do
        if holds(v, x, y, depth + 1) then return true end
    end
    return false
end

-- E17-T12 : lignes d'une réplique (morceaux affichés l'un après l'autre par le récepteur). Rend nil si chaque ligne
-- se lit seule : longueur bornée, et une ligne qui ne finit pas une phrase n'en contient aucune fin (sinon la coupe
-- aurait dû s'y faire) ; sinon la raison.
local function badCut(lines, max, TextCut)
    for i, line in ipairs(lines) do
        if string.len(line) > max then return "line " .. i .. " longer than " .. max .. ": " .. line end
        if i < #lines and not TextCut.endsSentence(line) then
            local pieces = TextCut.pieces(line, string.len(line) - 1)
            if #pieces > 1 and TextCut.endsSentence(pieces[1]) then
                return "line " .. i .. " cut mid-sentence after a possible sentence end: " .. line
            end
        end
    end
    return nil
end

RST.suite("rs.groupradio", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 480000 }, function(s)
    s.test("a long reply is aired in lines cut at sentence ends, then commas, never inside a word (E17-T12)",
        function(t)
        if isClient() then t:skip("authority only (solo, or RST.server in MP)") end
        local R = require "RadioSurvivor/RS_GroupRadio"
        local TextCut = require "RadioSurvivor/RS_TextCut"
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        -- Accents et points de suspension en échappements d'octets UTF-8 (lexeur Kahlua, base kahlua-lua.md).
        local text = "Oui, j'ai du travail pour toi. Il s'agit d'aller rep\195\169rer une maison \195\160 West Point,"
            .. " une exp\195\169dition de deux heures, avec 9.5 litres d'essence et un sac de toile bien rempli"
            .. "\226\128\166 Le rapport se fait en personne et la r\195\169compense est de vingt cartouches de 9 mm."
            .. " Est-ce que \195\167a t'int\195\169resse ?"
        local lines = R.lines(text)
        t:ok(#lines >= 2, "the reply should need two lines at least, got " .. #lines)
        t:eq(nil, badCut(lines, Const.MAX_LINE_CHARS, TextCut), "bad cut")
        t:ok(TextCut.endsSentence(lines[1]), "first line does not end a sentence: " .. tostring(lines[1]))
        t:eq(text, table.concat(lines, " "), "words cut or lost")
        local commas = R.lines(string.rep("nous avons march\195\169 longtemps, ", 12))
        for i = 1, #commas - 1 do
            t:ok(string.sub(commas[i], -1) == ",", "line " .. i .. " not cut at a comma: " .. commas[i])
        end
        for i, line in ipairs(lines) do t:note(i .. " (" .. string.len(line) .. "): " .. line) end
    end)


    s.test("each equipped group is a voice with a frequency of its range", function(t0)
        setup(t0, function(t, _, R, Personas, radios)
            for _, entry in ipairs(radios) do
                local id = R.voiceId(entry.ref)
                local khz = Personas.served(id)[1]
                t:ok(khz ~= nil, "no channel for the group voice " .. tostring(id))
                t:ok(khz >= 75000 and khz <= 149800, "frequency " .. tostring(khz) .. " out of 75.0-149.8")
                t:ok(Personas.channel(khz) ~= nil, "channel missing in the radio manager")
                t:eq(id, Personas.voiceAt(khz), "frequency held by another voice")
                t:note(entry.ref .. " (" .. entry.name .. ") on " .. string.format("%.1f", khz / 1000) .. " MHz")
            end
        end)
    end)

    s.test("a group without transmitter is no voice", function(t0)
        setup(t0, function(t, _, R, Personas, radios)
            local equipped = {}
            for _, entry in ipairs(radios) do equipped[entry.ref] = true end
            for _, g in ipairs(LivingKnox.API.listGroups()) do
                if not equipped[g.id] then
                    t:eq(nil, Personas.get(R.voiceId(g.id)), "voice for " .. g.id .. " without transmitter")
                end
            end
        end)
    end)

    s.test("a raiders camp is a voice, a neutrals group is none (E08-T10)", function(t)
        if isClient() then t:skip("authority only (solo, or RST.server in MP)") end
        local P = require "RadioSurvivor/RS_NPCProvider"
        if not P.available() then t:skip("Living Knox is not the active NPC provider") end
        local R = require "RadioSurvivor/RS_GroupRadio"
        local Personas = require "RadioSurvivor/RS_Personas"
        local G, I, Store = LivingKnox.Groups, LivingKnox.Identity, LivingKnox.Store
        t:ok(G ~= nil and G.isReady() and I ~= nil and Store ~= nil, "Living Knox groups or registry not ready")
        local raidersType = LivingKnox.GroupTypes.get("raiders")
        t:ok(raidersType ~= nil and raidersType.homeRadio == true, "raiders type without a camp station (homeRadio)")
        local player = RST.Fixtures.player(t)
        t:ok(player ~= nil, "no target player (t.ctx.player)")
        local x, y = math.floor(player:getX()) + 400, math.floor(player:getY())
        local made = {}
        local function group(gtype, name, dx, role)
            local g, why = G.create({ type = gtype, name = name, home = { x = x + dx, y = y, z = 0 } })
            t:ok(g ~= nil, gtype .. " group not created: " .. tostring(why))
            local H = LivingKnox.Homes
            if H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04)
            local npc = I.create(Store.data(), {}, x + dx, y, 0)
            t:ok(npc ~= nil, "npc not created")
            made[#made + 1] = { gid = g.id, npc = npc.id }
            local mid, bad = G.addMember(g.id, { role = role, npc = npc.id })
            t:ok(mid ~= nil, "member not added: " .. tostring(bad))
            t:ok(G.setLeader(g.id, mid) ~= nil, "leader not set")
            return g.id, npc.id
        end
        t:defer(function()
            for _, m in ipairs(made) do
                G.remove(m.gid)
                I.forget(Store.data(), m.npc)
            end
            R.refresh()
        end, "remove the test groups, their npcs and voices")
        local camp, boss = group("raiders", "RST Wolves", 0, "fighter")
        local drifters = group("neutrals", "RST Drifters", 10, "worker")
        R.refresh()
        local entry = R.equipped(camp)
        t:ok(entry ~= nil, "raiders camp not equipped")
        t:eq(boss, entry and entry.speaker, "the raider leader does not answer")
        local id = R.voiceId(camp)
        local khz = Personas.served(id)[1]
        t:ok(khz ~= nil, "no channel for the raiders voice " .. tostring(id))
        t:ok(khz >= 75000 and khz <= 149800, "frequency " .. tostring(khz) .. " out of 75.0-149.8")
        t:eq(id, Personas.voiceAt(khz), "frequency held by another voice")
        t:eq(nil, R.equipped(drifters), "neutrals equipped")
        t:eq(nil, Personas.get(R.voiceId(drifters)), "voice for the neutrals")
        t:note(camp .. " on " .. string.format("%.1f", khz / 1000) .. " MHz")
    end)

    s.test("a call is an npc_talk of the speaker, answered on the group frequency", function(t0)
        setup(t0, function(t, Server, R, Personas, radios)
            local player = RST.Fixtures.player(t)
            t:ok(player ~= nil, "no target player (t.ctx.player)")
            local character = RST.RSHelpers.character(t, player)
            local entry = radios[1]
            local id = R.voiceId(entry.ref)
            local sheet = Personas.get(id)
            local khz = Personas.served(id)[1]
            Server.lastTalk[character] = nil
            local aired = R.stats.aired
            local key = (type(isServer) == "function" and isServer()) and player:getUsername() or "solo"
            local req, why = R.talk(player, key, sheet, khz, "Radio check, anyone hear me?", "EN", nil)
            t:ok(req ~= nil, "call refused: " .. tostring(why))
            t:defer(function()
                local kept = {}
                for _, r in ipairs(Server.pending) do if r.id ~= req.id then kept[#kept + 1] = r end end
                Server.pending = kept
                R.state.outstanding[req.id] = nil
            end, "forget " .. tostring(req and req.id))
            t:eq("npc_talk", req.kind, "request kind")
            t:eq(entry.speaker, Server.store.data.npcs[req.npc].incarnation, "request not from the group speaker")
            local count = 0
            for _ in pairs(req.offers) do count = count + 1 end
            t:eq(0, count, "offer sent over the radio")
            local home = LivingKnox.Groups.state.data.groups[entry.ref].home
            if home then t:ok(not holds(req.context, home.x, home.y, 0), "home position in the request context") end
            -- E17-T12 : lignes réellement diffusées (file de diffusion enveloppée le temps du test), mesurées.
            local air, heard = R.state.air, nil
            R.state.air = function(k, lines, cid)
                if k == khz then heard = lines end
                return air(k, lines, cid)
            end
            t:defer(function() R.state.air = air end, "restore the air queue")
            local since = getTimestampMs()   -- E17-T15: cause of a missing reply named by the failure message
            t:waitUntil(function() return R.stats.aired > aired end, 60000, function(t2)
                t2:note("reply aired on " .. string.format("%.1f", khz / 1000) .. " MHz")
                t2:ok(heard ~= nil, "aired lines not seen")
                local spoken = {}
                for i = 2, #heard do spoken[#spoken + 1] = heard[i] end   -- la première ligne est un parasite
                local Const = require "RadioSurvivor/RadioSurvivor_Const"
                t2:eq(nil, badCut(spoken, Const.MAX_LINE_CHARS, require "RadioSurvivor/RS_TextCut"), "bad cut")
                for i, line in ipairs(spoken) do t2:note("line " .. i .. " (" .. string.len(line) .. "): " .. line) end
            end, function() return "no reply within 60 s: " .. RST.RSHelpers.bridgeCause(Server, since) end)
        end)
    end)
end)

return RST.RSGroupRadio
