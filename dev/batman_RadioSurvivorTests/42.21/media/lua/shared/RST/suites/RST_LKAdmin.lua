--[[
lk.admin - administration tools of Living Knox (LK13-T01, server/LivingKnox/LK_Admin.lua): every request goes
through LivingKnox.Admin.request(player, args) on the authority, which checks the right of the player FIRST
(dedicated server: checkPermissions(player, Capability.PopmanManage); solo: the local player) and answers a refusal
without any data. Checked here: refusal of a request without player (no data, counted), group list with the exact
home, detail and log of a group, home moved to a controlled square (outside the map and too close to another home
refused, valid square accepted with an "admin" log entry), relief forced for a wiped-out group (relief group
installed by the population path, only once).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player, the
administrator). Solo: RST.run({ suite = "lk.admin", tags = "world" }). Dedicated server: RST.server({ suite =
"lk.admin", tags = "world" }) from an admin client (moderator or admin role).
The test groups get homes about 300 squares away from the player: never loaded during the test, so never furnished.
Cleanup (t:defer): the test groups and the relief group are removed from the registry.
E01-T16: refusal of a REAL client with the access level "user" (second client of the MP campaign, set to "user" by
the requester for the test, RST.PeerChecks.refusedForUser; SKIP in solo). Not checked here: the window itself
(docs/annexes/tests/tests-en-jeu.md protocol of LK13-T01). Outside the game: tests/test_lk_admin.py.
Solo window (2026-10-15, solo client only, skipped elsewhere): the button "Living Knox - Admin" of the vanilla debug
menu (wrapper of ISDebugMenu.setupButtons, LK_DebugView.lua) opens the window client/LivingKnox/LK_AdminView.lua; the
list shows the test group, its detail shows members, story and log; screenshot lk_admin_window_*.png (Zomboid/
Screenshots); the home is moved and the relief forced through the window controls (entries + buttons), checked in
the registry.
]]

require "RST/RST"
require "RST/RST_PeerChecks"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Admin is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Admin) ~= "table" or type(E.Admin.request) ~= "function" or type(E.Groups) ~= "table"
        or type(E.Population) ~= "table" then
        t:skip("LivingKnox.Admin (LK13-T01) is not loaded here")
    end
    if not E.Config.isEnabled() then t:skip("Living Knox is disabled (sandbox option LivingKnox.Enabled)") end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function far(p, offset)
    local x, y = math.floor(p:getX()), math.floor(p:getY())
    local sx = x > 7000 and -1 or 1
    local sy = y > 7000 and -1 or 1
    return { x = x + sx * offset, y = y + sy * offset, z = 0 }
end

local function hasLog(g, kind, needle)
    for _, e in ipairs(g.log or {}) do
        if e.kind == kind and (needle == nil or string.find(e.text, needle, 1, true)) then return true end
    end
    return false
end

RST.suite("lk.admin", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local E = module(t)
        for _, name in ipairs({ "request", "isAllowed", "list", "group", "forceRelief", "moveHome", "checkHome" }) do
            t:eq("function", type(E.Admin[name]), "LivingKnox.Admin." .. name)
        end
        t:eq("adminRequest", E.Admin.CMD_REQUEST, "request command")
        t:eq("adminReply", E.Admin.CMD_REPLY, "reply command")
    end)

    s.test("a request without an allowed player is refused without data", function(t)
        local E = module(t)
        local before = E.Admin.stats.refused or 0
        for _, op in ipairs({ "list", "group", "relief", "home" }) do
            local r = E.Admin.request(nil, { op = op, n = 7, gid = "grp-1", x = 1, y = 1, z = 0 })
            t:eq(false, r.ok, op .. " accepted")
            t:eq("denied", r.err, op .. " error")
            t:eq(7, r.n, op .. " request number")
            for k in pairs(r) do
                t:ok(k == "n" or k == "op" or k == "ok" or k == "err", op .. " refusal carries the field " .. k)
            end
        end
        t:eq(before + 4, E.Admin.stats.refused, "refusals counted")
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:ok(E.Admin.isAllowed(p), "the target player is not allowed (admin or moderator role needed on a server)")
    end)

    -- E01-T16: a real second client with the access level "user" (MP campaign, autoclient.py --mp --clients 2).
    s.test("a real client with the user role is refused without data (E01-T16)", function(t)
        local E = module(t)
        RST.PeerChecks.refusedForUser(t, RST.PeerChecks.adminSpecs({ "list", "group", "relief", "home" }, 700),
            function() return E.Admin.stats.refused or 0 end)
    end)

    s.test("solo window: debug menu button, list, detail, journal, home move, forced relief", function(t)
        local E = module(t)
        if type(isServer) == "function" and isServer() then t:skip("solo client window (not on a server)") end
        local V, D = E.AdminView, E.DebugView
        if type(V) ~= "table" or V.open == nil or type(D) ~= "table" or ISDebugMenu == nil then
            t:skip("admin window or debug menu not loaded here (solo client only)")
        end
        t:ok(D.canUse(), "debug mode off: the debug menu button is hidden")
        local G = E.Groups
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        -- Button of the vanilla debug menu (MAIN tab), built by the real setupButtons on a stand-in panel.
        local menu = { addButtonInfo = ISDebugMenu.addButtonInfo, bringToTop = ISDebugMenu.bringToTop }
        ISDebugMenu.setupButtons(menu)
        local title = getText("IGUI_LK_Admin_DebugButton")
        local btn
        for _, b in ipairs(menu.buttons or {}) do
            if b.title == title then btn = b end
        end
        t:ok(btn ~= nil and btn.tab == "MAIN" and type(btn.func) == "function", "no '" .. title .. "' debug menu button")
        local home = far(p, 300)
        local g = assert(G.create({ type = "settlers", name = "RST admin window", day = G.today(), home = home }))
        local gid, relief = g.id, nil
        local mids = {}
        for _, role in ipairs({ "worker", "fighter" }) do
            mids[#mids + 1] = assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        t:defer(function()
            if V.state.window ~= nil then V.state.window:close() end
            G.remove(gid)
            if relief then G.remove(relief) end
        end, "close the window, remove the test group and its relief")
        if V.state.window ~= nil then V.state.window:close() end
        btn.func()
        local win = V.state.window
        t:ok(win ~= nil and win:isVisible(), "admin window not opened by the debug menu button")
        t:ok(win:getY() >= 0 and win:getY() + win:getHeight() <= getCore():getScreenHeight() and win:getX() >= 0
            and win:getX() + win:getWidth() <= getCore():getScreenWidth(), "admin window outside the screen")
        local listed = false
        for _, it in ipairs(win.list.items or {}) do
            if type(it.item) == "table" and it.item.id == gid then listed = true end
        end
        t:ok(listed, "test group missing from the window list")
        V.select(gid)
        local text = tostring(win.detail.text)
        for _, needle in ipairs({ "RST admin window", getText("IGUI_LK_Admin_Members"), getText("IGUI_LK_Admin_Journal"),
            getText("IGUI_LK_Admin_Log"), mids[1], mids[2] }) do
            t:ok(string.find(text, needle, 1, true) ~= nil, "detail without '" .. tostring(needle) .. "'")
        end
        t:ok(V.state.detail ~= nil and #(V.state.detail.log or {}) > 0, "detail without log entry")
        t:sleep(1500, function(t2)
            local shot = "lk_admin_window_" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight() .. ".png"
            local okShot, err = pcall(takeScreenshot, shot)
            t2:ok(okShot, "screenshot failed: " .. tostring(err))
            t:note("screenshot " .. shot)
            -- Home moved through the window controls.
            local target = far(p, 260)
            win.xEntry:setText(tostring(target.x))
            win.yEntry:setText(tostring(target.y))
            win.zEntry:setText("0")
            t2:ok(win.homeBtn.enable ~= false, "move home button disabled with a group selected")
            win:onMoveHome()
            local moved = G.get(gid).home
            t2:eq(target.x .. "," .. target.y .. ",0", moved.x .. "," .. moved.y .. "," .. moved.z, "home moved by the window")
            t2:ok(hasLog(G.get(gid), "admin", "home "), "no admin log entry for the move")
            t2:eq(false, win.reliefBtn.enable, "relief button enabled for a living group")
            -- Forced relief through the window once every member is dead.
            for _, mid in ipairs(mids) do assert(G.markDead(gid, mid)) end
            V.refresh()
            t2:ok(win.reliefBtn.enable == true, "relief button disabled for a group without living member")
            win:onRelief()
            local after = G.get(gid)
            relief = after.gone and after.gone.relief or nil
            t2:ok(relief ~= nil, "relief not installed by the window: " .. tostring(V.state.status))
            t2:ok(hasLog(after, "admin", "relief forced"), "no admin log entry for the relief")
            t:note("window status: " .. tostring(V.state.status))
            local listedRelief = false
            for _, it in ipairs(win.list.items or {}) do
                if type(it.item) == "table" and it.item.id == relief then listedRelief = true end
            end
            t2:ok(listedRelief, "relief group missing from the refreshed list")
        end)
    end)

    s.test("list, detail, home move and forced relief", function(t)
        local E = module(t)
        local G, A = E.Groups, E.Admin
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = far(p, 300)
        local g = assert(G.create({ type = "settlers", name = "RST admin", day = G.today(), home = home }))
        local gid, relief = g.id, nil
        local mids = {}
        for _, role in ipairs({ "worker", "fighter", "medic" }) do
            mids[#mids + 1] = assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        local other = far(p, 340)
        local g2 = assert(G.create({ type = "settlers", name = "RST admin 2", day = G.today(), home = other }))
        t:defer(function()
            G.remove(gid)
            G.remove(g2.id)
            if relief then G.remove(relief) end
        end, "remove the test groups and the relief group")

        local r = A.request(p, { op = "list", n = 1 })
        t:ok(r.ok, "list refused: " .. tostring(r.err))
        local row
        for _, x in ipairs(r.groups or {}) do
            if x.id == gid then row = x end
        end
        t:ok(row ~= nil, "test group missing from the list")
        if row then
            t:eq(3, row.alive, "living members")
            t:eq(home.x .. "," .. home.y, row.home.x .. "," .. row.home.y, "exact home in the list")
        end

        r = A.request(p, { op = "group", n = 2, gid = gid })
        t:ok(r.ok and r.group ~= nil, "detail refused: " .. tostring(r.err))
        if r.group then
            t:eq(3, #r.group.members, "members in the detail")
            t:ok(hasLog(r.group, "founded"), "log without the founded entry")
        end

        r = A.request(p, { op = "home", n = 3, gid = gid, x = 999999, y = 999999, z = 0 })
        t:eq("outside the map", r.err, "home outside the map")
        r = A.request(p, { op = "home", n = 4, gid = gid, x = other.x + 3, y = other.y, z = 0 })
        t:eq("too close to the home of " .. g2.id, r.err, "home next to another group")
        local target = far(p, 260)
        r = A.request(p, { op = "home", n = 5, gid = gid, x = target.x, y = target.y, z = 0 })
        t:ok(r.ok, "home move refused: " .. tostring(r.err))
        local moved = G.get(gid)
        t:eq(target.x .. "," .. target.y .. ",0", moved.home.x .. "," .. moved.home.y .. "," .. moved.home.z, "new home")
        t:ok(hasLog(moved, "admin", "home "), "no admin log entry for the move")

        r = A.request(p, { op = "relief", n = 6, gid = gid })
        t:eq(false, r.ok, "relief of a living group accepted")
        for _, mid in ipairs(mids) do assert(G.markDead(gid, mid)) end
        r = A.request(p, { op = "relief", n = 7, gid = gid })
        t:ok(r.ok, "forced relief refused: " .. tostring(r.err) .. " (see the WARN relief line of console.txt)")
        relief = G.get(gid).gone and G.get(gid).gone.relief or nil
        t:ok(relief ~= nil and relief == r.relief, "gone.relief not set to the answered group")
        t:ok(hasLog(G.get(gid), "admin", "relief forced"), "no admin log entry for the relief")
        if relief then
            local ng = G.get(relief)
            t:ok(ng ~= nil and ng.home ~= nil and G.livingCount(ng) >= 1, "relief group without home or member")
            t:note("relief " .. relief .. " installed for " .. gid)
        end
        r = A.request(p, { op = "relief", n = 8, gid = gid })
        t:eq("already relieved by " .. tostring(relief), r.err, "second relief")
    end)
end)
