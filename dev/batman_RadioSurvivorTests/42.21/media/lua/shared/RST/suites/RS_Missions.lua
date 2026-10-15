--[[
rs.missions — pure logic of RadioSurvivor/RS_Missions (server/RadioSurvivor/RS_Missions.lua): creation, offer expiry,
delay before the next offer, closing (success, failure, death), pruning, projection, item checks.
Tag "server": RS_Missions starts with "if isClient() then return end" (authority only: dedicated server or solo).
Run it with RST.server("rs.missions") or the dedicated server autorun; outside the game: tests/test_rs_suites.py.

Everything works on an in-memory state built by each test ({ missions, npcs, characters, outcomes }): no persistent
state of the mod, no global ModData, no real inventory. The module is required lazily inside the tests (server files
load after this shared file). Not tested: M.deliver and M.claim past their first refusals (they move real items
through sendRemoveItemFromContainer / instanceItem / sendAddItemToContainer); item checks use a fake Lua
inventory.
Times: release() stamps closedAt with the real getTimestampMs(); tests compare differences, never absolute times.
]]

require "RST/RST"

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Missions is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    if type(M) ~= "table" then t:skip("RS_Missions did not return its table here") end
    return M, require "RadioSurvivor/RS_Config"
end

local function newState()
    return { missions = {}, npcs = {}, characters = {}, outcomes = {} }
end

local function addNpc(state, id)
    local npc = { id = id }
    state.npcs[id] = npc
    return npc
end

local function addCharacter(state, key, name, npcId)
    local record = { name = name, contacts = {}, knownMissions = {} }
    if npcId then record.contacts[npcId] = { trust = "Neutral", trend = "Stable" } end
    state.characters[key] = record
    return record
end

local function count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- Fake inventory: items by id, each answering the methods M.eligible uses.
local function fakeItem(id, fullType, opts)
    opts = opts or {}
    return {
        id = id,
        getFullType = function() return fullType end,
        getCondition = function() return opts.condition or 10 end,
        isFavorite = function() return opts.favorite == true end,
        isEquipped = function() return opts.equipped == true end,
    }
end

local function fakePlayer(items)
    local byId = {}
    for _, item in ipairs(items) do byId[item.id] = item end
    local inv = { getItemWithIDRecursiv = function(_, id) return byId[id] end }
    return { getInventory = function() return inv end }
end

RST.suite("rs.missions", { tags = { "server" } }, function(s)
    s.test("module exports", function(t)
        local M = modules(t)
        for _, name in ipairs({ "create", "finish", "advance", "prune", "accept", "eligible", "checkItems", "deliver",
            "claim", "projection" }) do
            t:eq("function", type(M[name]), "RS_Missions." .. name)
        end
    end)

    s.test("create builds an offer from RS_Config.Delivery", function(t)
        local M, Config = modules(t)
        local state = newState()
        local npc = addNpc(state, "npc1")
        local m = M.create(state, npc, "char1")
        local c = Config.Delivery
        t:eq("npc1-delivery1", m.id)
        t:eq(m, state.missions[m.id])
        t:eq(m.id, npc.mission)
        t:eq(1, npc.missionCount)
        t:eq("offer", m.state)
        t:eq(1, m.revision)
        t:eq(c.id, m.offer)
        t:eq(c.quantity, m.quantity)
        t:eq(0, m.delivered)
        t:eq(c.durationMs, m.remainingMs)
        t:eq(Config.OFFER_TTL_MS, m.offerRemainingMs)
        t:eq({ char1 = true }, m.invited)
        t:eq({}, m.participants)
        t:eq(c.accepted, m.accepted)
        t:ok(m.accepted ~= c.accepted, "accepted types must be a copy of the configuration")
        t:eq("", m.claimedBy)
    end)

    s.test("create returns the open mission of the NPC", function(t)
        local M = modules(t)
        local state = newState()
        local npc = addNpc(state, "npc1")
        local m = M.create(state, npc, "char1")
        t:eq(m, M.create(state, npc, "char2"))
        t:eq(1, npc.missionCount)
        t:eq(nil, m.invited.char2, "second caller invited to the open mission")
        t:eq(1, count(state.missions))
    end)

    s.test("accept: invited only, offer becomes active once", function(t)
        local M = modules(t)
        local state = newState()
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        t:eq(false, M.accept(state, m, "stranger", "Stranger"))
        t:eq(false, M.accept(state, nil, "char1", "Alice"))
        t:eq(true, M.accept(state, m, "char1", "Alice"))
        t:eq("active", m.state)
        t:eq(2, m.revision)
        t:eq({ name = "Alice" }, m.participants.char1)
        t:eq(true, M.accept(state, m, "char1", "Alice"), "accepting again")
        t:eq(2, m.revision, "no new revision for a repeated accept")
        m.transaction = { kind = "delivery" }
        t:eq(false, M.accept(state, m, "char1", "Alice"), "refused during a transaction")
    end)

    s.test("offer expires after OFFER_TTL_MS and starts the cooldown", function(t)
        local M, Config = modules(t)
        local state = newState()
        local npc = addNpc(state, "npc1")
        local m = M.create(state, npc, "char1")
        t:eq(false, M.advance(state, Config.OFFER_TTL_MS - 1))
        t:eq("offer", m.state)
        t:eq(1, m.offerRemainingMs)
        local before = getTimestampMs()
        t:eq(true, M.advance(state, 1))
        t:eq("expired", m.state)
        t:eq(2, m.revision)
        t:eq(0, m.offerRemainingMs)
        t:eq(nil, npc.mission, "NPC freed")
        t:ok(m.closedAt >= before and m.closedAt <= getTimestampMs(), "closedAt from getTimestampMs")
        t:eq(m.closedAt + Config.OFFER_COOLDOWN_MS, npc.nextOfferAt)
        t:eq(false, M.advance(state, 1000000), "an expired offer does not change again")
        t:eq({}, state.outcomes, "an expired offer records no reputation event")
    end)

    s.test("offer under transaction and legacy offer", function(t)
        local M, Config = modules(t)
        local state = newState()
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        m.transaction = { kind = "delivery" }
        t:eq(false, M.advance(state, Config.OFFER_TTL_MS))
        t:eq("offer", m.state, "an offer under transaction never expires")
        local legacy = M.create(state, addNpc(state, "npc2"), "char1")
        legacy.offerRemainingMs = nil
        M.advance(state, 1000)
        t:eq(Config.OFFER_TTL_MS - 1000, legacy.offerRemainingMs, "saved offer without delay gets a full one")
        M.advance(state, -5000)
        t:eq(Config.OFFER_TTL_MS - 1000, legacy.offerRemainingMs, "negative elapsed time ignored")
    end)

    s.test("a new offer after closing gets a new id", function(t)
        local M = modules(t)
        local state = newState()
        local npc = addNpc(state, "npc1")
        local first = M.create(state, npc, "char1")
        M.accept(state, first, "char1", "Alice")
        t:eq(true, M.finish(state, first, "success"))
        t:eq(nil, npc.mission)
        t:ok(npc.nextOfferAt ~= nil, "cooldown set")
        local second = M.create(state, npc, "char1")
        t:eq("npc1-delivery2", second.id)
        t:ok(second ~= first, "new mission")
        t:eq("success", state.missions[first.id].state, "closed mission kept")
    end)

    s.test("active mission fails when its time runs out", function(t)
        local M, Config = modules(t)
        local state = newState()
        local npc = addNpc(state, "npc1")
        addCharacter(state, "char1", "Alice", "npc1")
        local m = M.create(state, npc, "char1")
        M.accept(state, m, "char1", "Alice")
        local duration = Config.Delivery.durationMs
        t:eq(false, M.advance(state, duration - 10))
        t:eq(10, m.remainingMs)
        t:eq(true, M.advance(state, 10))
        t:eq("failed", m.state)
        t:eq(0, m.remainingMs)
        t:eq(nil, npc.mission)
        local known = state.characters.char1.contacts.npc1
        t:eq("Cautious", known.trust)
        t:eq("Falling", known.trend)
        local outcome = state.outcomes[m.id .. "-char1-result"]
        t:ok(outcome ~= nil, "failure outcome recorded")
        t:eq("mission.failed", outcome.action)
        t:eq(Config.Reputation.failure, outcome.proposedDelta)
        t:eq(false, outcome.applied)
    end)

    s.test("finish success and death, only from active", function(t)
        local M, Config = modules(t)
        local state = newState()
        addCharacter(state, "char1", "Alice", "npc1")
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        t:eq(false, M.finish(state, m, "success"), "an offer cannot be finished")
        M.accept(state, m, "char1", "Alice")
        local revision = m.revision
        t:eq(true, M.finish(state, m, "success"))
        t:eq(revision + 1, m.revision)
        t:eq("Favourable", state.characters.char1.contacts.npc1.trust)
        t:eq("Rising", state.characters.char1.contacts.npc1.trend)
        t:eq(Config.Reputation.success, state.outcomes[m.id .. "-char1-result"].proposedDelta)
        t:eq(false, M.finish(state, m, "failed"), "finished twice")

        local dead = M.create(state, addNpc(state, "npc2"), "char1")
        M.accept(state, dead, "char1", "Alice")
        t:eq(true, M.finish(state, dead, "cancelled_dead"))
        t:eq(nil, state.outcomes[dead.id .. "-char1-result"], "no reputation event when the requester died")
        t:eq(nil, state.npcs.npc2.mission)
    end)

    s.test("participant without a contact record", function(t)
        local M = modules(t)
        local state = newState()
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        M.accept(state, m, "char1", "Alice")
        t:eq(true, M.finish(state, m, "failed"))
        t:ok(state.outcomes[m.id .. "-char1-result"] ~= nil, "outcome recorded without a character record")
    end)

    s.test("prune keeps open missions and drops old closed ones", function(t)
        local M, Config = modules(t)
        local state = newState()
        local rec = addCharacter(state, "char1", "Alice")
        local open = M.create(state, addNpc(state, "npc1"), "char1")
        local failed = M.create(state, addNpc(state, "npc2"), "char1")
        failed.state, failed.closedAt = "failed", 1000
        local unclaimed = M.create(state, addNpc(state, "npc3"), "char1")
        unclaimed.state, unclaimed.closedAt = "success", 1000
        local locked = M.create(state, addNpc(state, "npc4"), "char1")
        locked.state, locked.closedAt, locked.transaction = "failed", 1000, { kind = "reward" }
        local noStamp = M.create(state, addNpc(state, "npc5"), "char1")
        noStamp.state = "expired"
        rec.knownMissions[failed.id] = true
        rec.knownMissions[open.id] = true

        t:eq(false, M.prune(state, 1000 + Config.MISSION_RETENTION_MS))
        t:eq(1000 + Config.MISSION_RETENTION_MS, noStamp.closedAt, "closedAt stamped by prune")

        local now = 1001 + Config.MISSION_RETENTION_MS
        t:eq(true, M.prune(state, now))
        t:eq(nil, state.missions[failed.id], "old failed mission dropped")
        t:eq(nil, rec.knownMissions[failed.id], "dropped from the notebook record")
        t:eq(true, rec.knownMissions[open.id])
        t:eq(open, state.missions[open.id], "offer kept")
        t:eq(unclaimed, state.missions[unclaimed.id], "unclaimed success kept longer")
        t:eq(locked, state.missions[locked.id], "mission under transaction kept")
        t:eq(noStamp, state.missions[noStamp.id], "recently stamped mission kept")

        t:eq(true, M.prune(state, 1001 + Config.UNCLAIMED_RETENTION_MS))
        t:eq(nil, state.missions[unclaimed.id], "unclaimed success dropped after its retention")
    end)

    s.test("projection hides private data", function(t)
        local M = modules(t)
        local state = newState()
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        m.invited.char2 = true
        M.accept(state, m, "char2", "Zoe")
        M.accept(state, m, "char1", "Alice")
        m.receipts.token1 = { character = "char1", count = 2 }
        local p = M.projection(m, "char1")
        t:eq({ "Alice", "Zoe" }, p.participants)
        t:eq(true, p.engaged)
        t:eq(true, p.invited)
        t:eq(false, p.recovery)
        t:eq(nil, p.receipts)
        t:eq(nil, p.transaction)
        t:eq("", p.claimedName)
        t:eq(m.accepted, p.accepted)
        t:ok(p.accepted ~= m.accepted, "accepted is a copy")
        local other = M.projection(m, "stranger")
        t:eq(false, other.engaged)
        t:eq(false, other.invited)
        m.transaction = { kind = "delivery" }
        t:eq(true, M.projection(m, "char1").recovery)
    end)

    s.test("checkItems with a fake inventory", function(t)
        local M, Config = modules(t)
        local state = newState()
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        local okType = "Base.Bandage"
        t:eq(true, Config.Delivery.accepted[okType], "configuration accepts " .. okType)
        local player = fakePlayer({
            fakeItem(1, okType), fakeItem(2, okType), fakeItem(3, "Base.Pencil"),
            fakeItem(4, okType, { favorite = true }), fakeItem(5, okType, { equipped = true }),
            fakeItem(6, okType, { condition = 0 }),
        })
        local found = M.checkItems(player, m, { 1, 2 })
        t:ok(found ~= nil and #found == 2, "two valid items")
        t:eq(1, found and found[1].id)
        t:eq(nil, M.checkItems(player, m, {}), "empty list")
        t:eq(nil, M.checkItems(player, m, "1"), "not a list")
        t:eq(nil, M.checkItems(player, m, { 1, 1 }), "duplicate id")
        t:eq(nil, M.checkItems(player, m, { 1.5 }), "fractional id")
        t:eq(nil, M.checkItems(player, m, { "1" }), "string id")
        t:eq(nil, M.checkItems(player, m, { 99 }), "unknown id")
        t:eq(nil, M.checkItems(player, m, { 1, 3 }), "type not accepted")
        t:eq(nil, M.checkItems(player, m, { 4 }), "favourite item")
        t:eq(nil, M.checkItems(player, m, { 5 }), "equipped item")
        t:eq(nil, M.checkItems(player, m, { 6 }), "broken item")
        m.delivered = m.quantity - 1
        t:eq(nil, M.checkItems(player, m, { 1, 2 }), "more items than still needed")
        t:ok(M.checkItems(player, m, { 2 }) ~= nil, "the last needed item")
    end)

    s.test("deliver and claim refusals before any inventory change", function(t)
        local M = modules(t)
        local state = newState()
        local saves = 0
        local store = { data = state, save = function() saves = saves + 1; return true end }
        local m = M.create(state, addNpc(state, "npc1"), "char1")
        local player = fakePlayer({ fakeItem(1, "Base.Pencil") })
        t:eq({ false, "State" }, { M.deliver(store, m, player, "char1", { 1 }, "tok") }, "offer not accepted")
        M.accept(state, m, "char1", "Alice")
        t:eq({ false, "State" }, { M.deliver(store, m, player, "stranger", { 1 }, "tok") }, "not a participant")
        t:eq({ false, "Items" }, { M.deliver(store, m, player, "char1", { 1 }, "tok") }, "item not accepted")
        m.receipts.done = { character = "char1", count = 1 }
        t:eq({ true }, { M.deliver(store, m, player, "char1", { 1 }, "done") }, "replayed token")
        t:eq(0, saves, "nothing saved")
        t:eq(nil, m.transaction)
        t:eq({ false, "State" }, { M.claim(store, m, player, "char1", "tok") }, "claim before success")
        m.state, m.claimedBy = "success", "char2"
        t:eq({ false, "State" }, { M.claim(store, m, player, "char1", "tok") }, "lot already claimed")
        t:eq(0, saves, "nothing saved")
    end)
end)
