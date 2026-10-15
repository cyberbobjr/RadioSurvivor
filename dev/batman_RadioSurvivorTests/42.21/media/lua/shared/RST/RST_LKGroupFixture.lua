--[[
RST_LKGroupFixture - a Living Knox group loaded near the target player, for the suites that need "a group whose body
is loaded near the player" (rs.carnet.lk, rs.carnet.lk.supply, rs.groupradio, rs.factions.accord,
rs.factions.incident) and used to SKIP away from the initial population (E01-T19). Development mod only.
Load with: require "RST/RST_LKGroupFixture". No side effect at load time (definitions only).

    local LG = RST.LKGroup
    LG.loaded()                  first loaded body of a Living Knox group on the authority (RS_NPCProvider.objects(),
                                 ids sorted): gid, npc id; nil when there is none.
    LG.ensure(t, player, suite[, opts])
                                 suite(t, gid, npcId, created) runs once a body of a group is loaded near the player:
        - opts.ready() true at once (default: LG.loaded() finds a group body): the world is used as it is, created is
          false and gid, npcId are those of LG.loaded() (nil when opts.ready does not need a body);
        - otherwise, on a world run only (RST.worldGuard: save rstest*), a test group is created: type opts.type
          (default "settlers"; settlers and raiders hold a transmitter at home, homeRadio, so the group is a voice of
          RS_GroupRadio), named LG.NAME, home on the player's square (no furnishing: LivingKnox.Homes.skip), worker
          leader m-1 and fighter m-2; the players are hidden from its perception (RST.LKHelpers.hidePlayersFrom: a
          player standing in its home would be an intruder and raise an alert); the next step waits (t:waitQuiet,
          LG.BODIES_MS) until both bodies are mapped by the provider and standing, and opts.ready() is true; then
          suite(t, gid, npc of m-1, true);
        - SKIP: on an MP client (authority only), Living Knox disabled or its server part missing, outside a world
          run (the former reason kept: "go next to a group and run again"), no target player or square.
        Cleanup (t:defer): group removed, its npcs forgotten (directives, bodies), the group radio refreshed (its
        voice and channel gone). The players are visible again to the group before its removal.
    LG.memberNpc(gid, mid)       npc id of member mid of group gid, or nil.
Works the same in solo and on a dedicated server (RST.server: the group is created around the requester).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

RST.LKGroup = RST.LKGroup or {}
local LG = RST.LKGroup

LG.BODIES_MS = 60000
LG.NAME = "RST fixture group"
LG.MEMBERS = { "m-1", "m-2" }

local function provider()
    local ok, P = pcall(require, "RadioSurvivor/RS_NPCProvider")
    if ok and type(P) == "table" then return P end
    return nil
end

local function refreshRadio()
    local ok, R = pcall(require, "RadioSurvivor/RS_GroupRadio")
    if ok and type(R) == "table" and type(R.refresh) == "function" then pcall(R.refresh) end
end

function LG.memberNpc(gid, mid)
    local G = LivingKnox and LivingKnox.Groups
    local g = G and G.get(gid) or nil
    local m = g and g.members and g.members[mid] or nil
    return m and m.npc or nil
end

function LG.loaded()
    local E, P = LivingKnox, provider()
    if type(E) ~= "table" or type(E.Groups) ~= "table" or P == nil then return nil end
    local ids = {}
    for id in pairs(P.objects()) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local gid = E.Groups.findNpc(id)
        if gid then return gid, id end
    end
    return nil
end

-- Both members of group gid mapped by the provider (body loaded here) and standing.
local function bodiesUp(gid)
    local P = provider()
    local objects = P and P.objects() or {}
    for _, mid in ipairs(LG.MEMBERS) do
        local npc = LG.memberNpc(gid, mid)
        if npc == nil or objects[npc] == nil or not RST.LKHelpers.standing(npc)() then return false end
    end
    return true
end

function LG.ensure(t, player, suite, opts)
    opts = opts or {}
    if type(isClient) == "function" and isClient() then
        t:skip("Living Knox groups are kept on the authority (not on an MP client)")
    end
    local E = LivingKnox
    if type(E) ~= "table" or type(E.Config) ~= "table" or not E.Config.isEnabled() then
        t:skip("Living Knox is disabled (sandbox LivingKnox.Enabled)")
    end
    if type(E.Groups) ~= "table" then t:skip("Living Knox server part not loaded here") end
    local ready = opts.ready or function() return LG.loaded() ~= nil end
    if ready() then
        local gid, id = LG.loaded()
        return suite(t, gid, id, false)
    end
    if type(E.Bodies) ~= "table" or type(E.Senses) ~= "table" then
        t:skip("Living Knox server part not loaded here (no test group without Bodies and Senses)")
    end
    local allowed, why = RST.worldGuard()
    if not allowed then
        t:skip("no body of a Living Knox group loaded near the player: go next to a group and run again (no test "
            .. "group outside a world run: " .. tostring(why) .. ")")
    end
    local p = player or RST.Fixtures.player(t)
    if p == nil then t:skip("no target player") end
    local sq = p:getCurrentSquare()
    if sq == nil then t:skip("player square not loaded") end
    local G = E.Groups
    t:ok(G.ensure(), "group registry not ready")
    local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    local g, bad = G.create({ type = opts.type or "settlers", name = LG.NAME, day = G.today(), home = home })
    t:ok(g ~= nil, "fixture group not created: " .. tostring(bad))
    local gid = g.id
    if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
    t:defer(function()
        local npcs = {}
        for _, mid in ipairs(LG.MEMBERS) do npcs[#npcs + 1] = LG.memberNpc(gid, mid) end
        G.remove(gid)
        for _, npc in ipairs(npcs) do
            if E.Directives and E.Directives.forget then E.Directives.forget(npc) end
            E.Bodies.despawn(npc, true)
        end
        refreshRadio()
    end, "remove the fixture group " .. gid)
    t:ok(G.addMember(gid, { role = "worker", day = G.today() }) ~= nil, "worker not added to " .. gid)
    t:ok(G.addMember(gid, { role = "fighter", day = G.today() }) ~= nil, "fighter not added to " .. gid)
    t:ok(G.setLeader(gid, "m-1", G.today()) ~= nil, "leader of " .. gid .. " not set")
    RST.LKHelpers.hidePlayersFrom(t, gid)
    refreshRadio()
    t:note("fixture group " .. gid .. " (" .. tostring(opts.type or "settlers") .. ") created at " .. home.x .. ","
        .. home.y .. "," .. home.z)
    t:waitQuiet(function()
        if not bodiesUp(gid) then return false end
        refreshRadio()
        return ready() and true or false
    end, LG.BODIES_MS, function(t2)
        return suite(t2, gid, LG.memberNpc(gid, "m-1"), true)
    end, "bodies of the fixture group " .. gid .. " not loaded and standing near the player")
end

return LG
