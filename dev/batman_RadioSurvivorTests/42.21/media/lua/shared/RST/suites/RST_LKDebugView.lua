--[[
lk.debugview - npc debug panel (LK13-T14): in-memory activity log of the authority (server/LivingKnox/LK_Activity.lua,
200 lines per group, never saved) and operation "activity" of server/LivingKnox/LK_Admin.lua (list of all groups,
live activity of each member of the chosen group, saved group log and activity lines after a number), read by the
panel client/LivingKnox/LK_DebugView.lua. Same rights as the npc sheet (LK13-T13): solo = debug mode, server =
capability PopmanManage, checked on EVERY request.
Checked here: refusal without an allowed player (no data); a test group "settlers" (two workers) materialized at the
player's square; the activity answer lists the group and its two members (embodied, behaviour, needs); hunger of m-2
set to 95 through "npcSet" -> a "behaviour" line of m-2 with "rule hunger" appears in the activity log (the next
decision of the member changes its behaviour), and in the next "activity" answer after the previous last number.
LK13-T16: a second test group "settlers" FAR squares away (never embodied): each member has a position with source
"home" at the group home; homeGoto with a stand-in player leads next to that home (the real player is not moved).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player).
Solo (debug mode): RST.run({ suite = "lk.debugview", tags = "world" }). Dedicated server: RST.server({ suite =
"lk.debugview", tags = "world" }) from an admin client. Asynchronous run (about 30 s).
Cleanup (t:defer): bodies removed, test group removed (its activity lines forgotten).
Not checked here: the debug menu button and the window (docs/annexes/tests/tests-en-jeu.md, section of LK13-T14), refusal of a
real MP client without the capability. Outside the game: tests/test_lk_debugview.py.
Solo window (2026-10-15, solo client only, skipped elsewhere): the button "Living Knox - NPCs" of the vanilla debug
menu (wrapper of ISDebugMenu.setupButtons) opens the panel; its tables show the test group, its two members (live
activity) and the activity log, which receives the hunger change by the panel's own refresh (every 2 s); screenshot
lk_debugview_window_*.png (Zomboid/Screenshots); the panel button "Groups (admin)" opens the admin window on the
chosen group.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers

local BODIES_MS = 60000     -- materialization of the two members
local DECIDE_MS = 30000     -- behaviour change of the member after the setting
local FAR = 200             -- squares between the player and the home of the far test group (LK13-T16)

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then t:skip("LK_Activity is not loaded on an MP client") end
    local E = LK()
    if E == nil or type(E.Activity) ~= "table" or type(E.Admin) ~= "table" or type(E.Admin.activity) ~= "function"
            or type(E.Groups) ~= "table" then
        t:skip("LivingKnox.Activity and the activity operation (LK13-T14) are not loaded here")
    end
    if not E.Config.isEnabled() then t:skip("Living Knox is disabled (sandbox option LivingKnox.Enabled)") end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function bodyCount(gid)
    local n = 0
    for _, npc in pairs(memberNpcs(gid)) do
        if LK().Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

-- Activity line of npc of kind "behaviour" containing "rule hunger", numbered after `after`, or nil.
local function hungerLine(gid, npc, after)
    for _, e in ipairs(LK().Activity.entries(gid, after)) do
        if e.k == "behaviour" and e.npc == npc and string.find(e.t, "rule hunger", 1, true) then return e end
    end
    return nil
end

RST.suite("lk.debugview", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 180000 }, function(s)
    s.test("module exports", function(t)
        local E = module(t)
        for _, name in ipairs({ "note", "noteNpc", "entries", "count", "groupView", "behaviour", "hookAlert" }) do
            t:eq("function", type(E.Activity[name]), "LivingKnox.Activity." .. name)
        end
        t:eq(200, E.Activity.MAX, "lines kept per group")
        t:ok(E.Admin.OPS.activity and E.Admin.DEBUG_OPS.activity, "operation activity not declared as a debug operation")
    end)

    s.test("an activity request without an allowed player is refused without data", function(t)
        local E = module(t)
        local r = E.Admin.request(nil, { op = "activity", n = 3, gid = "grp-1", after = 0 })
        t:eq(false, r.ok, "activity accepted")
        t:eq("denied", r.err, "activity error")
        for k in pairs(r) do
            t:ok(k == "n" or k == "op" or k == "ok" or k == "err", "refusal carries the field " .. k)
        end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:ok(E.Admin.isAllowed(p, "activity"), "the target player is not allowed (debug mode in solo, admin role on a server)")
    end)

    -- E01-T16: a real second client with the access level "user" (MP campaign, autoclient.py --mp --clients 2).
    s.test("a real client with the user role is refused without data (E01-T16)", function(t)
        local E = module(t)
        RST.PeerChecks.refusedForUser(t, RST.PeerChecks.adminSpecs({ "activity", "homeGoto" }, 720),
            function() return E.Admin.stats.refused or 0 end)
    end)

    s.test("live activity of a materialized group, hunger change in the activity log", function(t)
        local E = module(t)
        local G, A, Ac = E.Groups, E.Admin, E.Activity
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST debug", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)   -- the player at the home would be an intruder (alert before hunger)
        t:defer(function()
            local npcs = memberNpcs(gid)
            G.remove(gid)
            Ac.forget(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove the bodies and group " .. gid)
        for _, spec in ipairs({ { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        t:waitUntil(function() return bodyCount(gid) == 2 end, BODIES_MS, function(t2)
            local npc = memberNpcs(gid)["m-2"]
            local r = A.request(p, { op = "activity", n = 1, gid = gid, after = 0 })
            t2:ok(r.ok, "activity refused: " .. tostring(r.err))
            local listed = false
            for _, row in ipairs(r.groups or {}) do
                if row.id == gid then listed = true end
            end
            t2:ok(listed, "test group missing from the group list")
            local v = r.group
            t2:ok(type(v) == "table" and v.id == gid, "no activity view of the test group")
            t2:eq(2, #v.members, "members in the view")
            local m2 = v.members[2]
            t2:eq("m-2", m2.id, "second member")
            t2:eq(true, m2.embodied, "m-2 embodied")
            t2:ok(type(m2.needs) == "table" and type(m2.needs.hunger) == "number", "needs missing")
            -- LK13-T15: displayed name of each member and table cells of the panel (client module, solo only).
            if RS_LivingKnox ~= nil then t2:ok(type(m2.name) == "string", "displayed name of m-2 missing") end
            local V = E.DebugView
            if V ~= nil and V.memberCells ~= nil then
                local cells = V.memberCells(m2)
                t2:ok(type(cells.member) == "string" and string.find(cells.member, "m-2", 1, true) == 1,
                    "member cell of m-2")
                t2:ok(type(cells.health) == "string" and type(cells.needs) == "string", "health and needs cells")
            end
            t:note(string.format("m-2 %s: behaviour %s rule %s, gesture %s, %d activity line(s)", npc, tostring(m2.b),
                tostring(m2.rule), tostring(m2.gesture), #(v.activity or {})))
            local after = v.seq or 0
            r = A.request(p, { op = "npcSet", n = 2, npc = npc, field = "hunger", value = 95 })
            t2:ok(r.ok, "hunger setting refused: " .. tostring(r.err))
            t2:waitUntil(function() return hungerLine(gid, npc, after) ~= nil end, DECIDE_MS, function(t3)
                local e = hungerLine(gid, npc, after)
                t:note("activity line: " .. tostring(e.t))
                t3:eq("m-2", e.mid, "member of the line")
                t3:ok(type(e.m) == "number", "game minute of the line")
                local r2 = A.request(p, { op = "activity", n = 3, gid = gid, after = after })
                t3:ok(r2.ok, "second activity request refused: " .. tostring(r2.err))
                local found = false
                for _, x in ipairs(r2.group and r2.group.activity or {}) do
                    t3:ok(x.s > after, "line " .. tostring(x.s) .. " sent again")
                    if x.s == e.s then found = true end
                end
                t3:ok(found, "hunger line missing from the incremental answer")
                t3:ok(Ac.count(gid) <= Ac.MAX, "activity log over its bound")
            end, "hunger change in the activity log not seen (rule hunger expected for m-2)")
        end, "group members not materialized")
    end)

    s.test("solo window: debug menu button, live activity and activity log in the panel, admin button", function(t)
        local E = module(t)
        if type(isServer) == "function" and isServer() then t:skip("solo client window (not on a server)") end
        local V = E.DebugView
        if type(V) ~= "table" or V.open == nil or ISDebugMenu == nil then
            t:skip("npc debug panel not loaded here (solo client only)")
        end
        t:ok(V.canUse(), "debug mode off: the debug menu button is hidden")
        local G, A, Ac = E.Groups, E.Admin, E.Activity
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local menu = { addButtonInfo = ISDebugMenu.addButtonInfo, bringToTop = ISDebugMenu.bringToTop }
        ISDebugMenu.setupButtons(menu)
        local title = getText("IGUI_LK_Debug_Button")
        local btn
        for _, b in ipairs(menu.buttons or {}) do
            if b.title == title then btn = b end
        end
        t:ok(btn ~= nil and btn.tab == "MAIN" and type(btn.func) == "function", "no '" .. title .. "' debug menu button")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST debug window", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)
        t:defer(function()
            if V.state.window ~= nil then V.state.window:close() end
            local AV = E.AdminView
            if AV ~= nil and AV.state ~= nil and AV.state.window ~= nil then AV.state.window:close() end
            local npcs = memberNpcs(gid)
            G.remove(gid)
            Ac.forget(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "close the windows, remove the bodies and group " .. gid)
        for _, spec in ipairs({ { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:waitUntil(function() return bodyCount(gid) == 2 end, BODIES_MS, function(t2)
            if V.state.window ~= nil then V.state.window:close() end
            btn.func()
            local win = V.state.window
            t2:ok(win ~= nil and win:isVisible(), "panel not opened by the debug menu button")
            t2:ok(win:getY() >= 0 and win:getY() + win:getHeight() <= getCore():getScreenHeight() and win:getX() >= 0
                and win:getX() + win:getWidth() <= getCore():getScreenWidth(), "debug panel window outside the screen")
            V.select(gid)
            local listed = false
            for _, r in ipairs(win.groups.rows or {}) do
                if r.id == gid then listed = true end
            end
            t2:ok(listed, "test group missing from the groups table")
            t2:eq(2, #(win.members.rows or {}), "members in the members table")
            local npc = memberNpcs(gid)["m-2"]
            local after = V.state.after or 0
            local r = A.request(p, { op = "npcSet", n = 31, npc = npc, field = "hunger", value = 95 })
            t2:ok(r.ok, "hunger setting refused: " .. tostring(r.err))
            local function shownLine()
                for _, e in ipairs(win.activity.rows or {}) do
                    if e.k == "behaviour" and e.npc == npc and e.s > after
                        and string.find(tostring(e.t), "rule hunger", 1, true) then return e end
                end
                return nil
            end
            -- The panel refreshes itself (Window:update -> DebugView.poll every 2 s): no request sent by the test.
            t2:waitUntil(function() return shownLine() ~= nil end, DECIDE_MS + 10000, function(t3)
                local e = shownLine()
                t:note("activity line shown by the panel: " .. tostring(e.t))
                local m2
                for _, m in ipairs(win.members.rows or {}) do
                    if m.id == "m-2" then m2 = m end
                end
                t3:ok(m2 ~= nil and m2.embodied == true, "live activity of m-2 missing from the members table")
                t3:ok(m2 ~= nil and type(m2.needs) == "table" and (m2.needs.hunger or 0) >= 90,
                    "hunger of m-2 not refreshed in the members table")
                t3:sleep(1000, function(t4)
                    local shot = "lk_debugview_window_" .. getCore():getScreenWidth() .. "x"
                        .. getCore():getScreenHeight() .. ".png"
                    local okShot, err = pcall(takeScreenshot, shot)
                    t4:ok(okShot, "screenshot failed: " .. tostring(err))
                    t:note("screenshot " .. shot)
                    t4:ok(win.adminBtn ~= nil, "no admin button in the panel")
                    win.adminBtn.onclick(win.adminBtn.target, win.adminBtn)
                    local AV = E.AdminView
                    t4:ok(AV ~= nil and AV.state.window ~= nil and AV.state.window:isVisible(),
                        "admin window not opened by the panel button")
                    t4:eq(gid, AV.state.selected, "admin window not on the chosen group")
                end)
            end, "hunger change not shown by the panel (rule hunger expected for m-2)")
        end, "group members not materialized")
    end)

    -- LK13-T16: every living member has a position and its source; teleport to the home of a far group.
    s.test("positions of a far group and teleport to its home", function(t)
        local E = module(t)
        local G, A = E.Groups, E.Admin
        t:ok(type(A.positionOf) == "function" and type(A.homeGoto) == "function"
            and A.OPS.homeGoto and A.DEBUG_OPS.homeGoto, "positions and homeGoto (LK13-T16) are not loaded here")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()) + FAR, y = math.floor(p:getY()), z = 0 }
        local g = assert(G.create({ type = "settlers", name = "RST far", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        t:defer(function()
            G.remove(gid)
            E.Activity.forget(gid)
        end, "remove group " .. gid)
        for _, profile in ipairs({ "handyman", "farmer" }) do
            assert(G.addMember(gid, { role = "worker", profile = profile, female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        local r, err = A.activity(gid, 0)
        t:ok(r ~= nil and r.group ~= nil, "activity of the far group: " .. tostring(err))
        t:eq(2, #r.group.members, "members in the view")
        for _, m in ipairs(r.group.members) do
            t:ok(type(m.pos) == "table", "no position for " .. tostring(m.id))
            t:eq("home", m.pos.src, "source of " .. tostring(m.id) .. " (never embodied)")
            t:eq(home.x, m.pos.x, "x of " .. tostring(m.id))
            t:eq(home.y, m.pos.y, "y of " .. tostring(m.id))
        end
        local V = E.DebugView
        if V ~= nil and V.memberCells ~= nil then
            local cell = V.memberCells(r.group.members[1]).pos
            t:ok(string.find(cell, home.x .. "," .. home.y .. ",0", 1, true) ~= nil, "position cell " .. tostring(cell))
        end
        -- Teleport with a stand-in player: the real player is never moved by this test.
        local moved = nil
        local standIn = { teleportTo = function(_, x, y, z) moved = { x = x, y = y, z = z } end }
        local out, why = A.homeGoto(gid, "rst", standIn)
        t:ok(out ~= nil, "homeGoto refused: " .. tostring(why))
        t:eq("home", out.dest.src, "destination source")
        t:ok(math.abs(out.dest.x - home.x) <= 1 and math.abs(out.dest.y - home.y) <= 1, "destination far from the home")
        if type(isServer) == "function" and isServer() then
            t:eq(false, out.moved, "a server never moves the player itself")
        else
            t:ok(moved ~= nil and moved.x == out.dest.x and moved.y == out.dest.y, "player not moved next to the home")
        end
        t:note(string.format("group %s home %d,%d,0 -> destination %d,%d,%d", gid, home.x, home.y, out.dest.x,
            out.dest.y, out.dest.z))
    end)
end)
