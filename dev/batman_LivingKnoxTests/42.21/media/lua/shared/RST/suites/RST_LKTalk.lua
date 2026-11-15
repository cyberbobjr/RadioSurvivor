--[[
lk.talk - speech of an NPC of Living Knox (E18-T18, E21-T05: one speech path, hosted by the notebook server of
the core mod, CoreAI.notebookServer; with or without the other mods).
Tags "world" and "server": a save named rstest*, with a target player; the bridge running (fake model of autoclient.py
--llm fake). Run:
    python tools/autoclient/autoclient.py --mods lk --mp --clients 1 --server-suite lk.talk --server-tags world
        --bridge on --llm fake
    python tools/autoclient/autoclient.py --mods lk --suite lk.talk --tags world --bridge on --llm fake

Multiplayer: the requester client says the sentence in the say chat (step lk.talk.say: no selected target, the nearest
NPC) and checks the bubble (lk.talk.bubble). Solo has no chat: the sentence is the command "talk" of the world menu
(the NPC selected by its id, then spoken to).
Every test removes its NPC with t:defer.
]]
require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_LKViewSteps"

local TALK_MS, REPLY_MS = 20000, 60000

local function B() return LivingKnox and LivingKnox.Bodies end
local function Server() return CoreAI and CoreAI.notebookServer end
local function multiplayer() return type(isServer) == "function" and isServer() end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    t:ok(Server() ~= nil and Server().talk ~= nil, "speech of the NPCs not hosted by the notebook server")
end

-- Notebook command "talk" of the world menu on the NPC id (solo: same server entry as a client command).
local function menuTalk(p, id, text)
    local S = Server()
    S.command("CoreAI", "talk", p, { text = text, channel = "say", language = "EN", incarnation = id,
        world = S.store.data.world, run = S.store.run })
end

-- Fiche of the notebook of the NPC id (nil before its first contact).
local function fiche(id) return Server().find(id) end

-- npc_talk request of the NPC id with this text in the queue, or nil.
local function request(id, text)
    local f = fiche(id)
    for _, r in ipairs(LivingKnox.Talk.pending) do
        if f ~= nil and r.npc == f.id and r.kind == "npc_talk" and (text == nil or r.text == text) then return r end
    end
    return nil
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
    local Hearing = require "CoreAI/CA_Hearing"
    local Speech = require "CoreAI/CA_SpeechConfig"
    t:waitUntil(function() return Hearing.near(p, body, Speech.SELECT_RANGE) end, 8000,
        function(t2) after(t2, id, p) end, "body of the npc never near the player")
end

-- The player says text; continues when the request of this NPC is in the queue.
local function say(t, id, p, text, after)
    local function waitRequest(t1)
        t1:waitUntil(function() return request(id, text) ~= nil end, TALK_MS, after, "sentence never queued for " .. id)
    end
    if multiplayer() then
        RST.Steps.ask(t, "lk.talk.say", { text = text }, { target = "requester", timeoutMs = 10000 }, waitRequest)
    else
        menuTalk(p, id, text)
        waitRequest(t)
    end
end

local function answered(id) return request(id) == nil end

-- Contact of the character with the NPC id in the notebook (exchanges, history), or nil.
local function contactOf(id, character)
    local f = fiche(id)
    local record = f and Server().store.data.characters[character]
    return record and record.contacts[f.id] or nil
end

local function exchanges(id, character)
    local c = contactOf(id, character)
    return c and c.exchanges or 0
end

RST.suite("lk.talk", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 320000 },
    function(s)
    s.test("a sentence said near an npc comes back as a bubble and stays in the history", function(t)
        setup(t)
        spawnNear(t, function(t2, id, p)
            local character = Server().bound[p]
            t2:ok(character ~= nil, "player without a notebook character")
            say(t2, id, p, "RST hello " .. tostring(getTimestampMs() % 100000), function(t3)
                t3:waitUntil(function() return answered(id) end, REPLY_MS, function(t4)
                    t4:eq(1, exchanges(id, character), "answered exchanges")
                    local c = contactOf(id, character)
                    local lines = c and c.history
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
            local Journal = require "CoreAI/CA_MissionJournal"
            local S = Server()
            local character = S.bound[p]
            t2:ok(character ~= nil, "player without a notebook character")
            local known = S.contact(character, S.ensure(id))
            known.stage, known.exchanges = "acquainted", 4
            LivingKnox.Talk.lastTalk[character] = nil -- cooldown of the previous test
            local before = #Journal.rows(character)
            local Hearing = require "CoreAI/CA_Hearing"
            local Speech = require "CoreAI/CA_SpeechConfig"
            -- The member goes about its routine: asked once it stands in sight (MP campaign of 2026-11-07, "Range").
            t2:waitUntil(function() return Hearing.near(p, B().find(id), Speech.SELECT_RANGE) end, TALK_MS, function(t2b)
                -- The menu entry: this NPC, whoever stands nearer.
                menuTalk(p, id, "RST any work")
                local req = request(id, "RST any work")
                t2b:ok(req ~= nil, "sentence refused by the notebook server")
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
