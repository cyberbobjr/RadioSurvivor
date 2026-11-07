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
E18-T33: the same mission without an announced lot (rewardCount 0): the lot created by the type of the member's group
(RC_MissionConfig.NPC_REWARD_TABLES -> Caches.tables), announced by the journal row (rewardTable), every item of the
table in the inventory.
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

-- A mission of npc id for the character, accepted and closed in success; a template with a common lot, removed when
-- noLot (E18-T33: the giver then creates the lot of its group).
local function successfulMission(t, id, character, name, noLot)
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
    if noLot then m.rewardCount = 0 end
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

RST.suite("lk.missions.alone", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 },
    function(s)
    -- Count of every item type of the lot: { [fullType] = count }.
    local function counts(p, lot)
        local out = {}
        for fullType in pairs(lot) do out[fullType] = p:getInventory():getCountTypeRecurse(fullType) end
        return out
    end

    -- The claim of mission m by the journal gesture, then check(t) once the lot is claimed.
    local function claimFromJournal(t, p, id, character, m, check)
        local Journal = require "RadioSurvivorCore/RC_MissionJournal"
        local MissionConfig = require "RadioSurvivorCore/RC_MissionConfig"
        local Hearing = require "RadioSurvivorCore/RC_Hearing"
        t:waitUntil(function()
            return Hearing.near(p, Alone().provider.objects()[id], MissionConfig.DELIVERY_RANGE)
        end, 60000, function(t3)
            local function claimed(t4)
                t4:waitUntil(function() return m.claimedBy == character end, CLAIM_MS, function(t5)
                    check(t5)
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
    end

    -- Journal row of mission m for the character (nil when not listed).
    local function row(character, m)
        for _, r in ipairs((require "RadioSurvivorCore/RC_MissionJournal").rows(character)) do
            if r.id == m.id then return r end
        end
    end

    s.test("the lot of a successful mission is claimed from the journal next to the requester", function(t)
        setup(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, _, id)
            local character = (require "RadioSurvivorCore/RC_Identity").bind(p)
            t2:ok(character ~= nil, "player without an identity")
            local m = successfulMission(t2, id, character, "RST")
            local r = row(character, m)
            t2:ok(r ~= nil and r.toClaim == true, "mission " .. m.id .. " not listed to claim in the journal")
            local before = p:getInventory():getCountTypeRecurse(m.rewardType)
            claimFromJournal(t2, p, id, character, m, function(t5)
                t5:eq(before + m.rewardCount, p:getInventory():getCountTypeRecurse(m.rewardType),
                    "items of the lot in the inventory")
            end)
        end)
    end)

    s.test("without an announced lot, the lot of the group's type is created and claimed", function(t)
        setup(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, _, id)
            local MissionConfig = require "RadioSurvivorCore/RC_MissionConfig"
            local character = (require "RadioSurvivorCore/RC_Identity").bind(p)
            t2:ok(character ~= nil, "player without an identity")
            local m = successfulMission(t2, id, character, "RST", true)
            local Groups = LivingKnox.Groups
            local g = Groups.get(Groups.findNpc(id))
            local name = MissionConfig.NPC_REWARD_TABLES[g.type] or "food"
            local r = row(character, m)
            t2:ok(r ~= nil and r.toClaim == true, "mission " .. m.id .. " not listed to claim in the journal")
            t2:eq(name, r.rewardTable, "lot announced by the journal row")
            local lot = {}
            for _, entry in ipairs(MissionConfig.Caches.tables[name]) do
                lot[entry[1]] = (lot[entry[1]] or 0) + entry[2]
            end
            local before = counts(p, lot)
            claimFromJournal(t2, p, id, character, m, function(t5)
                local after = counts(p, lot)
                -- The test group has no household stock: never a surplus item here.
                t5:ok(m.householdItem == nil, "household item given: " .. tostring(m.householdItem))
                t5:eq(name, m.createdLot, "created lot recorded on the mission")
                for fullType, n in pairs(lot) do
                    t5:eq(before[fullType] + n, after[fullType], "items " .. fullType .. " in the inventory")
                end
            end)
        end)
    end)
end)
