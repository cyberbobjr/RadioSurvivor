--[[
lk.missions.alone - lot of a mission of an NPC claimed from the journal of the core mod with Living Knox alone
(E18-T29: RC_MissionJournal "mission", giver "npc" of LK_TalkAlone, LK_MissionRewards).
Tags "world" and "server": a save named rstest*, with a target player. SKIP when RadioSurvivor is active: its notebook
holds the buttons then. Run:
    python tools/autoclient/autoclient.py --mods lk --mp --clients 1 --server-suite lk.missions.alone --server-tags world
    python tools/autoclient/autoclient.py --mods lk --suite lk.missions.alone --tags world

The mission of a member of a test group (RST.LKGroup) is created from the offers of that member, accepted and closed in
success by the engine (the offer by speech is lk.talk.alone). The claim goes through the journal: in multiplayer the
requester client sends the gesture of the Claim button (step core.journal.act), in solo the same command reaches the
authority directly. The test group has no household stock: the lot is the common lot of the engine (rewardType x
rewardCount), checked in the player's inventory; a second claim is refused.
]]
require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_ViewSteps"

local CLAIM_MS = 20000

local function multiplayer() return type(isServer) == "function" and isServer() end
local function Alone() return LivingKnox and LivingKnox.TalkAlone end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    if LivingKnox.radioSurvivorActive() then t:skip("RadioSurvivor active: its notebook holds the mission buttons") end
    t:ok(Alone() ~= nil and Alone().started, "speech of Living Knox alone not started")
end

-- A mission of npc id for the character, accepted and closed in success; a template with a common lot.
local function successfulMission(t, id, character, name)
    local M = require "RadioSurvivorCore/RC_Missions"
    local Store = require "RadioSurvivorCore/RC_MissionStore"
    local npc = LivingKnox.Talk.host.ensure(id)
    t:ok(npc ~= nil, "no speaker record for " .. tostring(id))
    npc.mission, npc.nextOfferHour = nil, nil
    local offers = M.offers(npc, Alone().provider.npc(id), Alone().provider.objects()[id], character)
    local m
    for offerId, terms in pairs(offers) do
        if m == nil and type(terms) == "table" and terms.kind ~= "supply" then
            m = M.create(Store.data, npc, character, offerId, terms)
        end
    end
    t:ok(m ~= nil, "no mission with a common lot offered by " .. tostring(id))
    t:ok((m.rewardCount or 0) > 0, "mission " .. m.id .. " without a common lot")
    t:defer(function()
        Store.data.missions[m.id] = nil
        npc.mission = nil
        Store.save()
    end, "forget " .. m.id)
    t:ok(M.accept(Store.data, m, character, name), "acceptance refused")
    t:ok(M.finish(Store.data, m, "success"), "success refused")
    local known = LivingKnox.Talk.data.known
    known[character] = known[character] or {}
    known[character][m.id] = true
    t:ok(Store.save(), "mission state not written")
    return m
end

RST.suite("lk.missions.alone", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 180000 },
    function(s)
    s.test("the lot of a successful mission is claimed from the journal next to the requester", function(t)
        setup(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, _, id)
            local Identity = require "RadioSurvivorCore/RC_Identity"
            local Journal = require "RadioSurvivorCore/RC_MissionJournal"
            local MissionConfig = require "RadioSurvivorCore/RC_MissionConfig"
            local Hearing = require "RadioSurvivorCore/RC_Hearing"
            local character = Identity.bind(p)
            t2:ok(character ~= nil, "player without an identity")
            local m = successfulMission(t2, id, character, "RST")
            local listed = false
            for _, row in ipairs(Journal.rows(character)) do
                if row.id == m.id then listed = row.toClaim == true end
            end
            t2:ok(listed, "mission " .. m.id .. " not listed to claim in the journal")
            local before = p:getInventory():getCountTypeRecurse(m.rewardType)
            t2:waitUntil(function()
                return Hearing.near(p, Alone().provider.objects()[id], MissionConfig.DELIVERY_RANGE)
            end, 60000, function(t3)
                local function claimed(t4)
                    t4:waitUntil(function() return m.claimedBy == character end, CLAIM_MS, function(t5)
                        t5:eq(before + m.rewardCount, p:getInventory():getCountTypeRecurse(m.rewardType),
                            "items of the lot in the inventory")
                        local ok, why = Journal.act(p, character, { action = "claim", mission = m.id,
                            revision = m.revision })
                        t5:ok(not ok and why == "State", "second claim: " .. tostring(ok) .. " " .. tostring(why))
                    end, "lot never claimed")
                end
                if multiplayer() then
                    RST.Steps.ask(t3, "core.journal.act", { action = "claim", mission = m.id, revision = m.revision },
                        { target = "requester", timeoutMs = 10000 }, claimed)
                else
                    Journal.onClientCommand(Journal.MODULE, "mission", p,
                        { action = "claim", mission = m.id, revision = m.revision })
                    claimed(t3)
                end
            end, "member " .. tostring(id) .. " never within reach of the player")
        end)
    end)
end)
