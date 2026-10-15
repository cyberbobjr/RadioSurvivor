--[[
rs.notebook.relation - relation panel of a contact in the notebook (E09-T07, client/RadioSurvivor/RS_Notebook.lua,
server/RadioSurvivor/RS_Relations.lua panel). Two test npcs are created next to the player and bound to two living
members of the same Living Knox group of the save (the leader and another member without body), each with its
notebook fiche, selected by the notebook. Two REAL facts are recorded through the engine (LivingKnox.Hostility.record,
seen by the group: a gift and a theft), then the personal relations are changed through the API of E09-T04
(Relations.offer then Relations.apply): the first npc thinks better of the character (gift), the second worse (theft).
The real notebook is opened on the Contacts page and each npc stays selected 3 s for the eye of the tester. The
displayed text is read back: the page starts with an ink colour tag and every laid out line is dark, the panel lines
are on the page, the level label is the translated label of the level computed by the server, the two members show
different levels, no raw translation key (IGUI_) and no number in the panel.
Tags "world" (test saves rstest*), solo only, no bridge needed.
RST.run({ suite = "rs.notebook.relation", tags = "world" }). Cleanup: the attitude pair of the group toward the
character is restored, the relations of the two test npcs removed, npcs and bindings removed by the fixtures, the
notebook closed again (or back on its former bookmark).
Outside the game: tests/test_relation_panel.py.
Look at by eye (campaign report): labels in the player's language, the level and its trend on one line, the group
line only when it differs, the truce line if the save holds one, the remembered facts (today, a gift / a theft).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"

local F, R = RST.Fixtures, RST.RSHelpers
local SHOW_MS = 3000
local DARK = 1.5

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

-- Living group of the save with a leader and another living member, both without body: gid, leader id, mate id, group.
local function freeMembers()
    local G = LivingKnox and LivingKnox.Groups
    if not G then return nil end
    local ids = G.list()
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = G.get(gid)
        local leader = g and g.leader and g.members[g.leader]
        if leader and leader.alive and leader.npc == nil then
            local mates = {}
            for mid, m in pairs(g.members) do
                if mid ~= g.leader and m.alive and m.npc == nil then mates[#mates + 1] = mid end
            end
            table.sort(mates)
            if mates[1] then return gid, g.leader, mates[1], g end
        end
    end
    return nil
end

local function keepAttitude(t, gid, cid)
    local H = LivingKnox.Hostility
    local before = H.debugPair(gid, cid)
    t:defer(function()
        local data = H.state.data
        if data and data.groups[gid] then
            data.groups[gid][cid] = deepCopy(before)
            H.save()
        end
    end, "attitude of " .. gid .. " toward the character restored")
end

-- npc next to the player, bound to member mid of gid, its fiche selected by the notebook; after(t, id, fiche).
local function boundNpc(t, c, dx, mid, after)
    R.npcWithFiche(t, c.p, dx, function(t2, id, fiche)
        local ok, why = LivingKnox.Groups.setNpc(c.gid, mid, id)
        t2:ok(ok, "npc not bound to " .. mid .. " of " .. c.gid .. ": " .. tostring(why))
        t2:defer(function() LivingKnox.Groups.setNpc(c.gid, mid, nil) end, "unbind " .. mid .. " of " .. c.gid)
        t2:defer(function()
            local rel = c.Server.store.data.relations
            if type(rel) == "table" then rel[fiche.id] = nil end
            c.Server.store.dirty = true
        end, "relation of the test npc " .. id .. " removed")
        RS_CarnetClient.send("select", { incarnation = id })
        t2:waitUntil(function() return c.Server.selected[c.cid] == fiche.id end, 5000, function(t3)
            return after(t3, id, fiche)
        end, "npc " .. id .. " not selected by the notebook")
    end)
end

-- Personal change of the npc toward the character citing the last offered fact of this kind (E09-T04 API).
local function change(t, c, fiche, fact, dir)
    local context, binding = c.Rel.offer(fiche, c.cid)
    local id = nil
    for _, f in ipairs(context.facts or {}) do if f.fact == fact then id = f.id end end
    t:ok(id ~= nil and binding ~= nil, fact .. " not offered as a citable fact to " .. fiche.id)
    local view, why = c.Rel.apply(fiche, c.cid, binding, dir, id)
    t:ok(view ~= nil, "relation of " .. fiche.id .. " not changed: " .. tostring(why))
end

local function rowOf(fiche)
    for _, row in ipairs(RS_CarnetClient.snapshot.contacts or {}) do
        if row.id == fiche.id then return row end
    end
    return nil
end

-- The page of one contact: selected, shown SHOW_MS, then read back. after(t) next.
local function show(t, c, w, fiche, expected, after)
    w.selectedId = fiche.id
    w:refresh()
    t:sleep(SHOW_MS, function(t2)
        local row = rowOf(fiche)
        t2:ok(row ~= nil and w.row == row, "contact " .. fiche.id .. " not selected on the page")
        local text = w.detail.text or ""
        t2:eq("<RGB:", string.sub(text, 1, 5), "page text does not start with a colour tag")
        w.detail:paginate()
        local light = 0
        for _, col in pairs(w.detail.rgb or {}) do
            if col.r + col.g + col.b >= DARK then light = light + 1 end
        end
        t2:eq(0, light, "light (white or grey) lines on the page")
        local lines = c.Notebook.relationLines(row.relation)
        t2:eq(expected, row.relation.level, "level sent for " .. fiche.id)
        t2:ok(string.find(lines[1], getText("IGUI_RS_RelLevel_" .. expected), 1, true) ~= nil,
            "translated level label absent: " .. lines[1])
        for _, s in ipairs(lines) do
            t2:ok(string.find(text, s, 1, true) ~= nil, "panel line not on the page: " .. s)
            t2:ok(string.find(s, "IGUI_", 1, true) == nil, "raw translation key shown: " .. s)
            t2:ok(string.find(s, "%d") == nil, "number shown in the relation panel: " .. s)
        end
        t2:note(fiche.id .. ": " .. table.concat(lines, " / "))
        return after(t2)
    end)
end

RST.suite("rs.notebook.relation", { tags = { "world" }, testTimeoutMs = 120000, timeoutMs = 150000 }, function(s)
    s.test("two members of a group, different relations, shown translated in the notebook (E09-T07)", function(t)
        R.solo(t)
        local Server = R.notebook(t)
        local p = F.player(t)
        t:ok(p ~= nil, "no target player")
        local cid = R.character(t, p)
        local gid, leader, mate, g = freeMembers()
        if gid == nil then t:skip("no living group with a leader and a member without body in this save") end
        R.god(t, p)
        keepAttitude(t, gid, cid)
        local c = { Server = Server, p = p, cid = cid, gid = gid, Rel = require "RadioSurvivor/RS_Relations",
            Notebook = require "RadioSurvivor/RS_Notebook" }
        t:note("group " .. gid .. " '" .. tostring(g.name) .. "': leader " .. leader .. ", member " .. mate)
        boundNpc(t, c, 2, leader, function(t2, _, first)
            boundNpc(t2, c, 3, mate, function(t3, _, second)
                local H = LivingKnox.Hostility
                t3:ok(H.record(gid, cid, "gift", { witnessed = true }) ~= nil, "gift not recorded by the engine")
                t3:ok(H.record(gid, cid, "theft", { witnessed = true }) ~= nil, "theft not recorded by the engine")
                change(t3, c, first, "gift", "up")
                change(t3, c, second, "theft", "down")
                local up, down = c.Rel.view(first, cid).level, c.Rel.view(second, cid).level
                t3:ok(up ~= down, "the two members show the same level: " .. up)
                local Client = RS_CarnetClient
                local wasOpen = Client.window ~= nil and Client.window:isVisible()
                if not wasOpen then c.Notebook.toggle() end
                local w = Client.window
                local formerTab = w.tab
                t3:defer(function()
                    if Client.window then
                        Client.window:changeTab(formerTab)
                        if not wasOpen and Client.window:isVisible() then c.Notebook.toggle() end
                    end
                end, "close the notebook")
                w:changeTab("Contacts")
                Client.send("snapshot")
                t3:waitUntil(function()
                    local a, b = rowOf(first), rowOf(second)
                    return a and b and a.relation and b.relation and a.relation.level == up
                        and b.relation.level == down
                end, 10000, function(t4)
                    return show(t4, c, w, first, up, function(t5)
                        return show(t5, c, w, second, down, function(t6) t6:ok(true, "both pages read") end)
                    end)
                end, "snapshot with the two relations never received")
            end)
        end)
    end)
end)
