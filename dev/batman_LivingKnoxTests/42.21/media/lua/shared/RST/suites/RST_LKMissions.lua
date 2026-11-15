--[[
lk.missions - lot of a mission of an NPC of Living Knox claimed from the notebook of the core mod (E18-T29,
E21-T04, E21-T05: command "claim" of the notebook server, giver "npc" of CA_NotebookGiver, reward source
LK_MissionRewards; with or without the other mods).
Tags "world" and "server": a save named rstest*, with a target player. Run:
    python tools/autoclient/autoclient.py --mods lk --mp --clients 1 --server-suite lk.missions --server-tags world
    python tools/autoclient/autoclient.py --mods lk --suite lk.missions --tags world

The mission of a member of a test group (RST.LKGroup) is created from the offers of that member, accepted and closed in
success by the engine (the offer by speech is lk.talk). The claim goes through the journal: in multiplayer the
requester client sends the gesture of the Claim button (step core.journal.act), in solo the same command reaches the
authority directly. The test group has no household stock: the lot is the common lot of the engine (rewardType x
rewardCount), checked in the player's inventory; a second claim is refused.
E18-T33: the same mission without an announced lot (rewardCount 0): the lot created by the type of the member's group
(CA_MissionConfig.NPC_REWARD_TABLES -> Caches.tables), announced by the journal row (rewardTable), every item of the
table in the inventory.
]]
require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_LKViewSteps"

local CLAIM_MS = 20000

local function multiplayer() return type(isServer) == "function" and isServer() end
local function Notebook() return CoreAI and CoreAI.notebookServer end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    t:ok(Notebook() ~= nil and Notebook().store.data ~= nil, "notebook server of the core mod not started")
end

-- A mission of npc id for the character, accepted and closed in success; a template with a common lot, removed when
-- noLot (E18-T33: the giver then creates the lot of its group).
local function successfulMission(t, id, character, name, noLot)
    local M = require "CoreAI/CA_Missions"
    local Store = M.store()
    local P = LivingKnox.NpcProvider
    local npc = Notebook().ensure(id)
    t:ok(npc ~= nil, "no notebook fiche for " .. tostring(id))
    npc.mission, npc.nextOfferHour = nil, nil
    local offers = M.offers(npc, P.npc(id), P.objects()[id], character)
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
    Notebook().store.data.characters[character].knownMissions[m.id] = true
    t:ok(Store.save(), "mission state not written")
    return m
end

RST.suite("lk.missions", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 },
    function(s)
    -- Count of every item type of the lot: { [fullType] = count }.
    local function counts(p, lot)
        local out = {}
        for fullType in pairs(lot) do out[fullType] = p:getInventory():getCountTypeRecurse(fullType) end
        return out
    end

    -- Claim of mission m by the notebook server (E21-T04: command "claim" of the Missions tab).
    local function claim(p, m)
        local Server = CoreAI.notebookServer
        Server.command("CoreAI", "claim", p, { mission = m.id, revision = m.revision,
            world = Server.store.data.world, run = Server.store.run })
    end

    -- The claim of mission m by the notebook gesture, then check(t) once the lot is claimed.
    local function claimFromJournal(t, p, id, character, m, check)
        local MissionConfig = require "CoreAI/CA_MissionConfig"
        local Hearing = require "CoreAI/CA_Hearing"
        t:waitUntil(function()
            return Hearing.near(p, LivingKnox.NpcProvider.objects()[id], MissionConfig.DELIVERY_RANGE)
        end, 60000, function(t3)
            local function claimed(t4)
                t4:waitUntil(function() return m.claimedBy == character end, CLAIM_MS, function(t5)
                    check(t5)
                    local revision = m.revision
                    claim(p, m)
                    t5:eq({ character, revision }, { m.claimedBy, m.revision }, "second claim changed the mission")
                end, "lot never claimed")
            end
            if multiplayer() then
                RST.Steps.ask(t3, "core.journal.act", { action = "claim", mission = m.id, revision = m.revision },
                    { target = "requester", timeoutMs = 10000 }, claimed)
            else
                claim(p, m)
                claimed(t3)
            end
        end, "member " .. tostring(id) .. " never within reach of the player")
    end

    -- Journal row of mission m for the character (nil when not listed).
    local function row(character, m)
        for _, r in ipairs((require "CoreAI/CA_MissionJournal").rows(character)) do
            if r.id == m.id then return r end
        end
    end

    s.test("the lot of a successful mission is claimed from the journal next to the requester", function(t)
        setup(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, _, id)
            local character = Notebook().bound[p]
            t2:ok(character ~= nil, "player without a notebook character")
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
            local MissionConfig = require "CoreAI/CA_MissionConfig"
            local character = Notebook().bound[p]
            t2:ok(character ~= nil, "player without a notebook character")
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
