--[[
rs.npcrewards (E11-T18, tags "server" and "world"): the reward of a mission given by a Living Knox NPC, taken from the
real household stock of its group (RS_NPCRewards through the "npc" giver of RS_MissionHooks, RS_Rewards,
LivingKnox.MissionRewards.take, LivingKnox.Stock.takeItem).
The authority only, on a save named rstest*, with a target player (t.ctx.player) standing INSIDE a house (as lk.aid:
the test group gets its home on the player's square). A one-member "settlers" test group is created (home furnished
and stock filled by the engine: LivingKnox.Homes.check, LivingKnox.Stock.check); its member is a Living Knox NPC
identity of the registry (no body is needed: the reward reads the registry, never a body). The mission lives in an
in-memory state built by the test (NPC fiche bound to the member, characters char1 and char2, store whose save does
nothing): no notebook state, no ModData of the notebook.
What is checked:
    - the reward source of the member: closed table of its group type (RS_Config.NPC_REWARD_TABLES), the home as the
      place, the lesson of its role only with a trusted relation (RS_Config.NPC_REWARD_TEACHES), a household item;
    - the claim of char1 (RC_Missions.claim): one item leaves the home stock (its id gone from the reference and from
      the home containers, its category count down by exactly one) and lands in the recipient's inventory (same id);
      the shared withdrawal is recorded once (claimedBy char1, reward record applied, item in hand);
    - a second claim (char2, or char1 again) is refused and takes nothing more from the stock;
    - the second client's player (server copy) never holds the item; each client checks its OWN inventory through
      RST.Steps (step "npcrewards.held": the requester holds it, the second client does not);
    - the member dead (LivingKnox.Groups.markDead): the claim of another successful mission is refused, nothing
      leaves the stock.
Cleanup (t:defer): the reward item removed from the player's inventory, the stock reference erased, the furnishing
removed (LivingKnox.Homes.clear), the group removed, the NPC identity forgotten (directives, body, registry).
Outside the game: tests/test_rs_e11_voice_npc_suites.py (Living Knox harness of tests/test_lk_aid.py, real reward
chain of RadioSurvivor).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"

local Steps = RST.Steps
local NPC_KEY = "rst-npcreward"

-- Does the local player hold the item of id args.id (bags included)? Each client reads its OWN inventory.
Steps.on("npcrewards.held", function(args)
    local p = getSpecificPlayer(0)
    if not p then return Steps.fail("no local player") end
    return function(ctx)
        local held = p:getInventory():getItemWithIDRecursiv(args.id) ~= nil
        if held == args.held or ctx.final then
            return Steps.pass("item " .. tostring(args.id) .. " held=" .. tostring(held), { held = held })
        end
    end
end)

local function engine(t)
    if type(isClient) == "function" and isClient() then
        t:skip("Living Knox groups and the rewards are kept on the authority (not on an MP client)")
    end
    local E = LivingKnox
    if type(E) ~= "table" or type(E.Config) ~= "table" or not E.Config.isEnabled() then
        t:skip("Living Knox is disabled (sandbox LivingKnox.Enabled)")
    end
    if type(E.Groups) ~= "table" or type(E.Stock) ~= "table" or type(E.Homes) ~= "table"
            or type(E.MissionRewards) ~= "table" or type(E.Identity) ~= "table" or type(E.Store) ~= "table" then
        t:skip("Living Knox server part not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

-- Ids of the items in the home containers of group gid.
local function homeIds(E, gid, home)
    local style, def = E.Homes.ready(home)
    local cts = style and E.Stock.containers(gid, home, style, def and def:getIDString() or nil)
    local out = {}
    for _, e in ipairs(cts and E.Stock.read(cts) or {}) do out[e.i] = true end
    return out
end

-- Ids of the stock reference of group gid: { [id] = category }, count.
local function refIds(E, gid)
    local ref, out, n = E.Stock.reference(gid), {}, 0
    for _, e in ipairs(ref and ref.items or {}) do out[e.i], n = e.c, n + 1 end
    return out, n
end

-- Successful mission of the NPC fiche for char1 and char2, in the test state.
local function successfulMission(state, n)
    local m = { id = "rst-npcreward-" .. n .. "-" .. tostring(RST.now()), npc = NPC_KEY, state = "success",
        participants = { char1 = { name = "Tester" }, char2 = { name = "Mate" } }, invited = {}, claimedBy = "",
        revision = 1, rewardType = "", rewardCount = 0 }
    state.missions[m.id] = m
    return m
end

RST.suite("rs.npcrewards", { mods = { "rs", "lk" }, tags = { "server", "world" }, testTimeoutMs = 60000 },
        function(s)
    s.test("household reward taken once for the recipient only, never from a dead NPC", function(t)
        local E = engine(t)
        local G, S = E.Groups, E.Stock
        local M = require "RadioSurvivorCore/RC_Missions"
        local N = require "RadioSurvivor/RS_NPCRewards"
        local Config = require "RadioSurvivor/RS_Config"
        local p = RST.Fixtures.player(t)
        if p == nil then t:skip("no target player") end
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local g = G.create({ type = "settlers", name = "RST npc rewards", day = G.today(), home = home })
        t:ok(g ~= nil, "test group not created")
        local gid = g.id
        local registry = E.Store.data()
        local npc = E.Identity.create(registry, { female = false }, home.x, home.y, home.z)
        t:ok(npc ~= nil and E.Store.save() ~= false, "NPC identity not created")
        local mid = G.addMember(gid, { role = "worker", npc = npc.id, day = G.today() })
        t:ok(mid ~= nil, "member not added to " .. gid)
        local given
        t:defer(function()
            if given ~= nil then
                local inv = p:getInventory()
                local it = inv:getItemWithIDRecursiv(given)
                if it ~= nil then
                    inv:Remove(it)
                    if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(inv, it) end
                end
            end
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
            if E.Directives and E.Directives.forget then E.Directives.forget(npc.id) end
            if E.Bodies and E.Bodies.despawn then E.Bodies.despawn(npc.id, true) end
            E.Identity.forget(E.Store.data(), npc.id)
            E.Store.save()
        end, "remove the reward item, the stock, the furnishing, group " .. gid .. " and its NPC")
        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table" or mark == "done", "home not furnished: " .. tostring(why))
        local r
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        local before = S.needs(gid)
        t:ok(before ~= nil, "no stock assessment")
        t:eq({ 0, 0 }, { before.ration, before.next }, "the test group rations its stock")

        -- Reward source of the member: table of its group type, home, lesson of its role only when trusted.
        local fiche = { id = NPC_KEY, incarnation = npc.id }
        local state = { missions = {}, npcs = { [NPC_KEY] = fiche }, characters = {}, outcomes = {} }
        state.characters.char1 = { name = "Tester", contacts = {}, knownMissions = {} }
        state.characters.char2 = { name = "Mate", contacts = {}, knownMissions = {} }
        local store = { data = state, save = function() return true end }
        local source = N.describe(fiche, "char1")
        t:ok(source ~= nil, "no reward source for a living member")
        t:eq({ Config.NPC_REWARD_TABLES.settlers, home.x, home.y }, { source.cache_table,
            source.places[1] and source.places[1].x, source.places[1] and source.places[1].y }, "reward source")
        local trusted = false
        for _, kind in ipairs(source.rewards) do if kind == "frequency" then trusted = true end end
        t:eq(trusted and Config.NPC_REWARD_TEACHES.worker or nil, source.teaches, "lesson of the worker")
        t:ok(type(source.material) == "function", "no household item in the source")
        t:note("relation " .. (trusted and "trusted" or "not trusted") .. ", rewards " .. table.concat(source.rewards, ","))

        -- Claim of char1: one household item, in the recipient's inventory, once.
        local ids, count = refIds(E, gid)
        local m = successfulMission(state, 1)
        local inv = p:getInventory()
        local held = inv:getItems():size()
        t:eq({ true }, { M.claim(store, m, p, "char1", "rst-claim-1") }, "claim of the recipient")
        local rec = m.extendedReward
        t:eq({ "char1", "cache", "applied", true }, { m.claimedBy, rec and rec.kind, rec and rec.status,
            rec and rec.inHand }, "shared withdrawal of the recipient")
        local after, left = refIds(E, gid)
        t:eq(count - 1, left, "items of the stock reference after the claim")
        for id, cat in pairs(ids) do
            if after[id] == nil then given = id; t:note("reward " .. tostring(id) .. " (" .. tostring(cat) .. ")") end
        end
        t:ok(given ~= nil, "no item left the stock reference")
        t:ok(inv:getItemWithIDRecursiv(given) ~= nil, "reward not in the recipient's inventory")
        t:eq(held + 1, inv:getItems():size(), "items added to the recipient's inventory")
        t:ok(not homeIds(E, gid, home)[given], "reward still in a home container")
        local cat = ids[given]
        t:eq(before.have[cat] - 1, S.needs(gid).have[cat], "count of " .. tostring(cat) .. " in the stock")

        -- No second withdrawal: another participant, or the recipient again.
        t:eq({ false, "State" }, { M.claim(store, m, p, "char2", "rst-claim-2") }, "claim of the second participant")
        t:eq({ false, "State" }, { M.claim(store, m, p, "char1", "rst-claim-3") }, "second claim of the recipient")
        t:eq(left, select(2, refIds(E, gid)), "items taken by a second claim")
        t:eq(held + 1, inv:getItems():size(), "items added by a second claim")

        -- The dead member gives nothing more.
        t:ok(G.markDead(gid, mid, G.today()) ~= nil, "member not marked dead")
        local dead = successfulMission(state, 2)
        t:eq({ false, "State" }, { M.claim(store, dead, p, "char1", "rst-claim-dead") }, "claim from a dead NPC")
        t:eq({ "", nil }, { dead.claimedBy, dead.extendedReward }, "withdrawal recorded for a dead NPC")
        t:eq(left, select(2, refIds(E, gid)), "items taken for a dead NPC")
        t:eq(held + 1, inv:getItems():size(), "items given for a dead NPC")

        -- Privacy: the second client's player never holds the reward; each client reads its own inventory.
        local other = Steps.others(t)[1]
        local mate = other and Steps.playerOf(other)
        if mate then
            t:ok(mate:getInventory():getItemWithIDRecursiv(given) == nil, "reward in the second client's inventory")
        else
            t:note("no second client online: privacy checked for the requester only")
        end
        Steps.ask(t, "npcrewards.held", { id = given, held = true }, { target = "requester", timeoutMs = 10000 },
            function(t2, res)
                for _, row in ipairs(res.list) do t2:eq(true, row.data and row.data.held, "requester view") end
                Steps.ask(t2, "npcrewards.held", { id = given, held = false }, { target = "others", timeoutMs = 5000 },
                    function(t3, peers)
                        for _, row in ipairs(peers.list) do
                            t3:eq(false, row.data and row.data.held, "reward seen in the inventory of " .. row.user)
                        end
                    end)
            end)
    end)
end)
