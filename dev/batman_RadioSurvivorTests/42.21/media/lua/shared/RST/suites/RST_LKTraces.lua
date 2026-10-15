--[[
lk.traces - readable traces of a Living Knox group (LK10-T04, server/LivingKnox/LK_Traces.lua): a vanilla notebook
(Base.Notebook, read-only: pages written then setLockedBy) left ONCE at the home of a group that is gone, and a sheet
of notes (Base.SheetPaper2) put ONCE in the inventory of the leader's body at his death. Text composed on the
authority from the story journal (LK_Journal) and the public story (LK_Stories), in the authority language.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
where the test home can be (his own square; a house with a container nearby shows the container case, elsewhere the
notebook is left on the floor). Solo: RST.run({ suite = "lk.traces", tags = "world" }).
Dedicated server: RST.server({ suite = "lk.traces", tags = "world" }) from an admin client.
Cleanup (t:defer): the documents are removed (LivingKnox.Traces.clear) and the test groups are removed.

What is checked (nominal path):
    - home: a test group (home on the player's square, no furnishing: Homes.skip) whose members all die and which is
      marked gone gets one notebook from LivingKnox.Traces.checkHome(gid, { force = true }): mark state "done",
      document found around the home with the group tag, a Literature, locked, not empty, page 1 naming the group;
      a second check answers "done"; after LivingKnox.Traces.reset() (memory lost, as after a restart) the mark read
      from the registry still answers "done"; with the mark erased, the tagged notebook restores it ("found") and no
      second notebook is left;
    - leader: LivingKnox.Traces.giveChiefNote(gid, leader, inventory, body) puts one locked, non-empty sheet in the
      inventory (a free ItemContainer stands for the body inventory; the real call comes from the memberDied fact of
      LK_Bodies, whose listener "Traces.chief" is checked to be registered); a second call, a call for a member who is
      not the leader and a call after a memory reset put nothing.
The first page of each document is printed as a note (read it in game too: right click, "Read").
Outside the game: tests/test_lk_traces.py (the suite also runs there against doubles).
]]

require "RST/RST"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Traces is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Traces) ~= "table" or type(E.Groups) ~= "table" or type(E.Homes) ~= "table" then
        t:skip("LivingKnox.Traces is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function newGroup(t, E, name, home, n)
    local G = E.Groups
    local g = assert(G.create({ type = "settlers", name = name, day = G.today(), home = home }))
    local roles = { "worker", "fighter", "medic" }
    local first
    for i = 1, n do
        local mid = assert(G.addMember(g.id, { role = roles[i], day = G.today() }))
        first = first or mid
    end
    assert(G.setLeader(g.id, first, G.today()))
    E.Homes.skip(g.id)
    t:defer(function()
        E.Traces.clear(g.id)
        E.Groups.remove(g.id)
    end, "remove the documents and the group " .. g.id)
    return g.id, first
end

local function homeOf(t)
    local p = t.ctx and t.ctx.player
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local sq = p:getCurrentSquare()
    t:ok(sq ~= nil, "player square not loaded")
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
end

local function checkDocument(t, E, item, name)
    t:ok(instanceof(item, "Literature"), "document is not a Literature item")
    t:eq(E.Traces.LOCK, item:getLockedBy(), "document lock")
    t:ok(not item:isEmptyPages(), "document has no text")
    local page = item:seePage(1)
    t:ok(type(page) == "string" and string.find(page, name, 1, true) ~= nil, "page 1 does not name the group")
    t:note("page 1: " .. tostring(page))
end

local function tracesIn(inv, gid)
    local out = {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData()[LK().Traces.TAG] == gid then out[#out + 1] = it end
    end
    return out
end

RST.suite("lk.traces", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("home notebook left once when the group is gone", function(t)
        local E = module(t)
        local G, T = E.Groups, E.Traces
        local home = homeOf(t)
        if E.Homes.ready(home) == nil then t:skip("the area around the player is not fully loaded") end
        local gid = newGroup(t, E, "RST traces", home, 2)
        t:eq(nil, (T.checkHome(gid, { force = true })), "a living group gets no notebook")
        for mid, m in pairs(G.get(gid).members) do
            if m.alive then assert(G.markDead(gid, mid, G.today())) end
        end
        t:ok(G.update(function(d)
            G.applyGone(d.groups[gid], "wiped", G.today(), 0, 0)
            return true, true
        end), "group not marked gone")
        local mark, why = T.checkHome(gid, { force = true })
        t:ok(type(mark) == "table", "notebook not left: " .. tostring(why))
        t:eq("done", mark.state, "mark state")
        t:note("notebook left in: " .. tostring(mark.where))
        local docs = T.findDocuments(gid, home, "home")
        t:eq(1, #docs, "notebooks of the group around the home")
        checkDocument(t, E, docs[1].item, "RST traces")
        t:eq("done", T.checkHome(gid, { force = true }), "second check")
        T.reset()
        t:eq("done", T.checkHome(gid, { force = true }), "check after a memory reset (restart)")
        t:ok(G.update(function(d)
            d.groups[gid].traces = nil
            return true, true
        end), "mark not erased")
        T.reset()
        local restored = T.checkHome(gid, { force = true })
        t:ok(type(restored) == "table" and restored.where == "found", "mark not restored from the notebook")
        t:eq(1, #T.findDocuments(gid, home, "home"), "notebooks after the restart and the lost mark")
    end)

    s.test("leader notes put once in the body inventory", function(t)
        local E = module(t)
        local T = E.Traces
        local found = false
        for _, entry in ipairs((E.listeners or {}).memberDied or {}) do
            if entry.key == "Traces.chief" then found = true end
        end
        t:ok(found, "memberDied listener Traces.chief not registered")
        local gid, leader = newGroup(t, E, "RST notes", homeOf(t), 2)
        local inv = ItemContainer.new()
        local body = { md = {} }
        function body:getModData() return self.md end
        function body:getInventory() return inv end
        t:ok(T.giveChiefNote(gid, leader, inv, body), "notes not given")
        local notes = tracesIn(inv, gid)
        t:eq(1, #notes, "notes in the inventory")
        checkDocument(t, E, notes[1], "RST notes")
        t:ok(not T.giveChiefNote(gid, leader, inv, body), "notes given twice to the same body")
        local other
        for mid in pairs(E.Groups.get(gid).members) do
            if mid ~= leader then other = mid end
        end
        local inv2 = ItemContainer.new()
        t:ok(not T.giveChiefNote(gid, other, inv2, nil), "notes given to a member who is not the leader")
        T.reset()
        t:ok(not T.giveChiefNote(gid, leader, inv2, nil), "notes given again after a memory reset")
        t:eq(0, #tracesIn(inv2, gid), "notes in the second inventory")
        t:eq(1, #tracesIn(inv, gid), "notes in the first inventory")
    end)
end)
