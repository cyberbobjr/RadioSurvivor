--[[
lk.talk.alone - speech of an NPC with Living Knox alone (E18-T18, LivingKnox.TalkAlone, client LivingKnox.TalkView).
Tags "world" and "server": a save named rstest*, with a target player; the bridge running (fake model of autoclient.py
--llm fake). SKIP when RadioSurvivor is active: its notebook hosts the speech then. Run:
    python tools/autoclient/autoclient.py --mods lk --mp --clients 1 --server-suite lk.talk.alone --server-tags world
        --bridge on --llm fake
    python tools/autoclient/autoclient.py --mods lk --suite lk.talk.alone --tags world --bridge on --llm fake

Multiplayer: the requester client says the sentence in the real say chat (step lk.talk.say) and checks the bubble
(lk.talk.bubble). Solo has no chat: the sentence goes through the same server entry as the world menu.
Every test removes its NPC with t:defer.
]]
require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_ViewSteps"

local TALK_MS, REPLY_MS = 20000, 60000

local function B() return LivingKnox and LivingKnox.Bodies end
local function Alone() return LivingKnox and LivingKnox.TalkAlone end
local function multiplayer() return type(isServer) == "function" and isServer() end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    if LivingKnox.radioSurvivorActive() then t:skip("RadioSurvivor active: its notebook hosts the speech") end
    t:ok(Alone() ~= nil and Alone().started, "speech of Living Knox alone not started")
end

-- Free square 1 to 3 squares from the player, in the same room (or outdoors with him): a wall between them hides the
-- npc (MP campaign of 2026-11-07: player in the home of a group, npc spawned behind its wall).
local function spotNear(p)
    local psq = p:getSquare()
    local px, py, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local cell = getCell()
    -- isFree refused every square around the player on a dedicated server (MP campaign of 2026-11-07): floor and
    -- solidity are read instead.
    for r = 1, 3 do
        for _, d in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }) do
            local sq = cell:getGridSquare(px + d[1], py + d[2], z)
            if sq ~= nil and psq ~= nil and sq:TreatAsSolidFloor() and not sq:isSolid() and not sq:isSolidTrans()
                and sq:getRoom() == psq:getRoom() then
                return sq:getX(), sq:getY(), z
            end
        end
    end
    return nil
end

local function spawnNear(t, after)
    local F = RST.Fixtures
    local p = F.player(t)
    t:ok(p ~= nil, "no target player")
    local x, y, z = spotNear(p)
    t:ok(x ~= nil, "no free square in sight 1 to 3 squares from the player")
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function()
        local Talk = LivingKnox.Talk
        local kept = {}
        for _, r in ipairs(Talk.pending) do if r.npc ~= id then kept[#kept + 1] = r end end
        Talk.pending = kept
        B().despawn(id, true)
    end, "forget " .. id)
    local Hearing = require "RadioSurvivorCore/RC_Hearing"
    local Speech = require "RadioSurvivorCore/RC_SpeechConfig"
    t:waitUntil(function() return Hearing.near(p, body, Speech.SELECT_RANGE) end, 8000,
        function(t2) after(t2, id, p) end, "body of the npc never near the player")
end

-- The player says text; continues when the request of this NPC is in the queue.
local function say(t, id, p, text, after)
    local function waitRequest(t1)
        t1:waitUntil(function()
            for _, r in ipairs(LivingKnox.Talk.pending) do
                if r.npc == id and r.kind == "npc_talk" and r.text == text then return true end
            end
            return false
        end, TALK_MS, after, "sentence never queued for " .. id)
    end
    if multiplayer() then
        RST.Steps.ask(t, "lk.talk.say", { text = text }, { target = "requester", timeoutMs = 10000 }, waitRequest)
    else
        local req, why = Alone().say(p, { text = text, channel = "say", language = "EN", npc = id })
        t:ok(req ~= nil, "sentence refused: " .. tostring(why))
        waitRequest(t)
    end
end

local function answered(id)
    for _, r in ipairs(LivingKnox.Talk.pending) do
        if r.npc == id and r.kind == "npc_talk" then return false end
    end
    return true
end

local function exchanges(id, character)
    local c = LivingKnox.Talk.data.contacts[character]
    return c and c[id] and c[id].exchanges or 0
end

RST.suite("lk.talk.alone", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 320000 },
    function(s)
    s.test("a sentence said near an npc comes back as a bubble and stays in the history", function(t)
        setup(t)
        spawnNear(t, function(t2, id, p)
            local Identity = require "RadioSurvivorCore/RC_Identity"
            local character = Identity.bind(p)
            t2:ok(character ~= nil, "player without an identity")
            say(t2, id, p, "RST hello " .. tostring(getTimestampMs() % 100000), function(t3)
                t3:waitUntil(function() return answered(id) end, REPLY_MS, function(t4)
                    t4:eq(1, exchanges(id, character), "answered exchanges")
                    local History = require "RadioSurvivorCore/RC_History"
                    local lines = History.find(character, "lk:" .. id)
                    t4:ok(lines ~= nil and #lines == 2, "history of the exchange: " .. tostring(lines and #lines))
                    if multiplayer() then
                        RST.Steps.ask(t4, "lk.talk.bubble", { npc = id, text = lines[2].text },
                            { target = "requester", timeoutMs = 10000 })
                    else
                        t4:eq(lines[2].text, LivingKnox.SpeechView.lastPieces.text, "bubble")
                    end
                end, "no answer of the bridge")
            end)
        end)
    end)

    s.test("an acquainted npc offers a mission listed in the journal of the core mod", function(t)
        setup(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, _, id)
            local Identity = require "RadioSurvivorCore/RC_Identity"
            local Journal = require "RadioSurvivorCore/RC_MissionJournal"
            local character = Identity.bind(p)
            local Talk = LivingKnox.Talk
            Talk.data.contacts[character] = Talk.data.contacts[character] or {}
            Talk.data.contacts[character][id] = { stage = "acquainted", exchanges = 4 }
            Talk.lastTalk[character] = nil -- cooldown of the previous test
            local before = #Journal.rows(character)
            local Hearing = require "RadioSurvivorCore/RC_Hearing"
            local Speech = require "RadioSurvivorCore/RC_SpeechConfig"
            -- The member goes about its routine: asked once it stands in sight (MP campaign of 2026-11-07, "Range").
            t2:waitUntil(function() return Hearing.near(p, B().find(id), Speech.SELECT_RANGE) end, TALK_MS, function(t2b)
                -- The menu entry: this NPC, whoever stands nearer.
                local req, why = Alone().say(p, { text = "RST any work", channel = "say", language = "EN", npc = id })
                t2b:ok(req ~= nil, "sentence refused: " .. tostring(why))
                t2b:eq("acquainted", req.context.stage, "stage")
                local offered = false
                for _ in pairs(req.offers) do offered = true end
                t2b:ok(offered, "no offer in the request")
                t2b:waitUntil(function() return answered(id) end, REPLY_MS, function(t3)
                    t3:eq(before + 1, #Journal.rows(character), "missions in the journal")
                end, "no answer of the bridge")
            end, "member " .. tostring(id) .. " never in sight of the player")
        end)
    end)
end)
