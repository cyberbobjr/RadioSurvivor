--[[
lk.leave - individual departure of an embodied Living Knox member (E10-T04, shared/RadioSurvivor/RS_LivingKnox.lua:
LK.leave, LK.canLeave; server/RadioSurvivor/RS_Factions.lua: keepTruces, covered). Tags "world" and "server": the
authority only, on a save named rstest*, with a target player (t.ctx.player), the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.leave", tags = "world" }); dedicated server: RST.server({ suite = "lk.leave",
tags = "world" }) from an admin client. Asynchronous run only (about 1 minute).

What is done (stay next to the two members, in their sight):
    - a test group "settlers" (worker leader m-1, fighter m-2) gets its home on the player's square; its members get
      bodies near the player;
    - when the player has a notebook character (Ctrl+G once on any NPC), a truce is concluded between the group and
      the player's team (RS_Factions.conclude, as the leader would);
    - m-2 leaves its group (RS_LivingKnox.leave with the composition read now, as the notebook does after a model
      reply leave_group): one group "loners" of one member linked to the same NPC, home in the ring around the old
      one (E10-T05: real LivingKnox.Sites.pick with LivingKnox.Config.LEAVE HOME_MIN..HOME_MAX squares, or a widened
      tier of Sites.CONFIG.NEAR_WIDEN; the measured distance and the tier are printed), written at once; the old
      group keeps its leader; m-2 walks away toward its new home (one LK03 directive: watch the body leave; it may
      fail without undoing the departure);
    - the same departure asked again on the old composition is refused; the truce of the old group covers the NPC in
      its new group (personal truce); the population never draws the loners type.
No bridge, no LLM: the model decision is replaced by the direct call (the bridge path is in tests/test_lk_leave.py).
E01-T16 (E10-T04): on a dedicated server with a second client bound to a notebook character, the departing member
gets a notebook fiche and a contact of that character (removed at the end); the second client asks its notebook
snapshot as the notebook does (RST.Steps "carnet.contact", RST_PeerChecks2.lua) and shows the old group name before
the departure, the name of the new loner group after it.
Every phase prints "[LKL] measure ..." lines. Cleanup (t:defer): bodies removed, both groups removed, truce removed.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecks2"

local K = RST.LKHelpers
local measure = K.measurer("[LKL]")

local BODIES_MS = 60000

local function LK() return LivingKnox end

-- E10-T05: tier of a distance from the old home: 1 = ring HOME_MIN..HOME_MAX, 2.. = widened tiers (NEAR_WIDEN), 0 =
-- beyond every tier (whole map), with the upper bound of that tier (nil for the whole map).
local function ringTier(E, d)
    local cfg = E.Config.LEAVE
    if d <= cfg.HOME_MAX then return 1, cfg.HOME_MAX end
    for i, k in ipairs(E.Sites.CONFIG.NEAR_WIDEN or {}) do
        local maxR = math.floor(cfg.HOME_MAX * k)
        if d <= maxR then return i + 1, maxR end
    end
    return 0, nil
end

-- E10-T04 (E01-T16): notebook of the second client. prepare(t, npc) gives the npc a fiche and a contact of the
-- second client's notebook character (removed at the end) and returns the check: check(t, groupName, after, final)
-- asks the second client its snapshot until the contact shows groupName, then after(t). Without a second client bound
-- to a character: on a dedicated server with another client online the check FAILS (that client should be bound);
-- in solo or with the requester alone the first checks note it and go on, the final one (after every other
-- assertion of the test) is an explicit SKIP (RST.PeerChecks2.unchecked).
local function notebookOfPeer(t, npc)
    local PC2 = RST.PeerChecks2
    local Server = PC2.notebook()
    local others = RST.Steps.others(t)
    local peer = others[1] and RST.Steps.playerOf(others[1]) or nil
    local cid = PC2.boundOf(peer)
    if Server == nil or cid == nil then
        local why = "notebook of a second client not checked: "
            .. (Server == nil and "notebook server state not ready" or "no second client bound to a notebook character")
        return function(tc, _, after, final)
            if final or (type(isServer) == "function" and isServer() and #others > 0) then PC2.unchecked(tc, why) end
            tc:note(why)
            return after(tc)
        end
    end
    local fiche = Server.ensure(npc)
    t:ok(fiche ~= nil, "no notebook fiche for " .. tostring(npc))
    local record = Server.store.data.characters[cid]
    local added = record.contacts[fiche.id] == nil
    if added then
        record.contacts[fiche.id] = { history = {}, note = "", trust = "Unassessed", trend = "Stable", stage = "stranger",
            exchanges = 0 }
        t:defer(function()
            record.contacts[fiche.id] = nil
            Server.store.dirty = true
        end, "contact of " .. cid .. " with " .. tostring(npc) .. " removed")
    end
    return function(tc, groupName, after, _)
        RST.Steps.ask(tc, "carnet.contact", { id = fiche.id, groupName = groupName }, { target = { others[1] },
            timeoutMs = 10000 }, after)
    end
end

local function memberNpc(gid, mid)
    local g = LK().Groups.get(gid)
    local m = g and g.members[mid] or nil
    return m and m.npc or nil
end

RST.suite("lk.leave", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(s)
    s.test("a member leaves its group: one loner group, home far away, walk away, truce kept", function(t)
        local E = LK()
        local P = RS_LivingKnox
        t:ok(E ~= nil and E.Groups ~= nil and E.Sites ~= nil, "Living Knox server part is not loaded on this side")
        t:ok(P ~= nil and P.leave ~= nil, "RS_LivingKnox.leave (E10-T04) is not loaded")
        t:ok(E.GroupTypes.isKnown(P.LONER_TYPE), "group type loners not registered")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local F = require "RadioSurvivor/RS_Factions"
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        t:ok(sq ~= nil, "player square not loaded")
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST leave", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
        assert(G.addMember(gid, { role = "worker", profile = "farmer", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = true, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        local npcs = {}
        local cleanup = { loner = nil, team = nil }
        t:defer(function()
            G.remove(gid)
            if cleanup.loner then G.remove(cleanup.loner) end
            if cleanup.team then F.cancelAgreement(gid, cleanup.team) end
            for _, npc in ipairs(npcs) do
                F.dropTruces(npc)
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove groups " .. gid)
        t:waitUntil(function()
            for _, mid in ipairs({ "m-1", "m-2" }) do
                local npc = memberNpc(gid, mid)
                if npc == nil or E.Bodies.find(npc) == nil or not K.standing(npc)() then return false end
            end
            return true
        end, BODIES_MS, function(t2)
            local leader, mate = memberNpc(gid, "m-1"), memberNpc(gid, "m-2")
            npcs = { leader, mate }
            -- Truce of the old group with the player's team (needs a notebook character: Ctrl+G once).
            local key = E.Hostility and E.Hostility.keyOf(p) or nil
            if key then
                local neg = F.negotiation(p, gid)
                local ok, why = false, "no agreement offered"
                if neg then ok, why = F.conclude(p, gid, "truce", { team = neg.team, revision = neg.revision }) end
                measure(string.format("truce with team %s: %s (%s)", tostring(neg and neg.team), tostring(ok),
                    tostring(why)))
                if ok then cleanup.team = neg.team end
            else
                measure("no notebook character bound to the player: truce part skipped")
            end
            -- The departure itself (E10-T04), then the notebook of the second client shows the new group name.
            local function leave(t3, c, notebookCheck)
                local t0 = getTimestampMs()
                local out, why = P.leave(mate, { ref = c.ref, key = c.key })
                t3:ok(out ~= nil, "departure refused: " .. tostring(why))
                cleanup.loner = out.ref
                local ng = G.get(out.ref)
                local old = G.get(gid)
                local dx, dy = ng.home.x - home.x, ng.home.y - home.y
                local far = math.floor(math.sqrt(dx * dx + dy * dy))
                measure(string.format("left %s for %s (%s) in %d ms, home %d squares away, walk %s", gid, out.ref,
                    ng.type, getTimestampMs() - t0, far,
                    out.walk and ("#" .. out.walk) or ("failed: " .. tostring(out.walkWhy))))
                t3:eq("loners", ng.type, "type of the new group")
                t3:eq(out.ref, (G.findNpc(mate)), "group of the NPC")
                t3:eq(1, G.livingCount(ng), "members of the loner group")
                t3:ok(old.members["m-2"] == nil, "member still in the old group")
                t3:eq("m-1", old.leader, "leader of the old group")
                t3:ok(far >= E.Sites.CONFIG.GROUP_DISTANCE, "new home too close to the old one: " .. far)
                local cfg = E.Config.LEAVE
                local tier, maxR = ringTier(E, far)
                local where = "whole map (no tier)"
                if tier == 1 then
                    where = "in the ring"
                elseif tier > 1 then
                    where = "widened tier " .. tier .. ", up to " .. maxR .. " squares"
                end
                measure(string.format("new home %d squares from the old one: %s (ring %d-%d squares)", far, where,
                    cfg.HOME_MIN, cfg.HOME_MAX))
                t3:ok(far >= cfg.HOME_MIN, "new home inside the minimum distance: " .. far)
                t3:ok(tier ~= 0, "new home beyond every tier of the ring: " .. far)
                t3:ok(not G.isDirty(), "departure not written at once")
                local again, refused = P.leave(mate, { ref = c.ref, key = c.key })
                t3:eq(nil, again, "same departure applied twice")
                measure("second departure on the old composition: " .. tostring(refused))
                local weights = E.Population.typeWeights(E.Config.population())
                for _, w in ipairs(weights) do t3:ne("loners", w.id, "loners drawn by the population") end
                if cleanup.team then
                    local kept = F.keepTruces(mate, gid)
                    measure(string.format("truces kept: %d; covered in the new group: %s", kept,
                        tostring(F.covered(out.ref, key, mate))))
                    t3:eq(1, kept, "truces copied")
                    t3:ok(F.covered(out.ref, key, mate), "the NPC who left lost the truce")
                    t3:ok(not F.covered(out.ref, key, leader), "another NPC covered by a personal truce")
                end
                notebookCheck(t3, ng.name, function() end, true)
            end
            local c = P.composition(mate)
            t2:ok(c ~= nil and c.canLeave == true, "m-2 may not leave its group")
            local notebookCheck = notebookOfPeer(t2, mate)
            notebookCheck(t2, g.name, function(t2b) return leave(t2b, c, notebookCheck) end)
        end, "group members not materialized and standing")
    end)
end)
