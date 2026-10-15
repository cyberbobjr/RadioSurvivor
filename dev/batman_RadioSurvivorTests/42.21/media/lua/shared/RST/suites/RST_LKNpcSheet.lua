--[[
lk.npcsheet - sheet of a Living Knox npc opened by right click (LK13-T13, operations "npc" and "npcSet" of
server/LivingKnox/LK_Admin.lua, window client/LivingKnox/LK_NpcSheet.lua): the authority answers the whole known
state of one npc (group, member, role, needs, health, decision, gesture, perception, weapon, position, home) and
applies a bounded setting of a need or of the health, noted in the group log ("... set by admin <account>"). The
right is checked on EVERY request (solo: debug mode; server: capability PopmanManage).
Checked here: refusal without an allowed player (no data); a test group "settlers" (two workers) materialized at the
player's square; sheet of member m-2 (group, member, embodied, needs, health 100, position near its body); hunger set
to 150 -> kept at 100 (bound), admin log entry; the next decision of the member reads hunger 100 (its first
evaluation after the setting is recorded: rule "hunger" unless a rule of higher priority - threat, fear, wound -
applies); health set to 0 -> kept at 1 (never a death). LK13-T15: refusal of the three actions without a player;
role of m-2 changed to fighter (a role of the type), breaker refused; first and last name "Jane Doe" (read by the
notebook provider when loaded), a name with a digit refused; teleport next to the body (solo: player moved by the
authority; server: destination only, the client sends /teleportto); each action noted in the group log.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player).
Solo (debug mode): RST.run({ suite = "lk.npcsheet", tags = "world" }). Dedicated server: RST.server({ suite =
"lk.npcsheet", tags = "world" }) from an admin client. Asynchronous run (about 30 s).
Cleanup (t:defer): decision tap removed, bodies removed, test group removed.
E01-T16: refusal of a real client with the access level "user" (second client of the MP campaign; SKIP in solo).
Not checked here: the right-click option and the window (docs/tests-en-jeu.md, section of LK13-T13).
Outside the game: tests/test_lk_npcsheet.py.
Solo window (2026-10-15, solo client only, skipped elsewhere): the real world context menu
(ISWorldObjectContextMenu.createMenu on the objects of the square of a materialized member) offers the sheet option,
choosing it opens the window client/LivingKnox/LK_NpcSheet.lua on that npc (group, member, needs, health shown);
hunger and health are set through the window entries and buttons and read back from the authority; screenshot
lk_npcsheet_window_*.png (Zomboid/Screenshots).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers

local BODIES_MS = 60000     -- materialization of the two members
local DECIDE_MS = 30000     -- next evaluation of the member after the setting

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then t:skip("LK_Admin is not loaded on an MP client") end
    local E = LK()
    if E == nil or type(E.Admin) ~= "table" or type(E.Admin.npcView) ~= "function" or type(E.Groups) ~= "table" then
        t:skip("LivingKnox.Admin npc sheet (LK13-T13) is not loaded here")
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

local function adminLog(gid, needle)
    for _, e in ipairs(LK().Groups.get(gid).log or {}) do
        if e.kind == "admin" and string.find(e.text, needle, 1, true) then return true end
    end
    return false
end

RST.suite("lk.npcsheet", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 180000 }, function(s)
    s.test("module exports", function(t)
        local E = module(t)
        for _, name in ipairs({ "npcView", "npcSet", "request", "isAllowed" }) do
            t:eq("function", type(E.Admin[name]), "LivingKnox.Admin." .. name)
        end
        t:ok(E.Admin.OPS.npc and E.Admin.OPS.npcSet, "operations npc and npcSet not declared")
        t:eq("function", type(E.Health.setByAdmin), "LivingKnox.Health.setByAdmin")
    end)

    s.test("a sheet request without an allowed player is refused without data", function(t)
        local E = module(t)
        for _, op in ipairs({ "npc", "npcSet" }) do
            local r = E.Admin.request(nil, { op = op, n = 3, npc = "lk-1", field = "hunger", value = 90 })
            t:eq(false, r.ok, op .. " accepted")
            t:eq("denied", r.err, op .. " error")
            for k in pairs(r) do
                t:ok(k == "n" or k == "op" or k == "ok" or k == "err", op .. " refusal carries the field " .. k)
            end
        end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:ok(E.Admin.isAllowed(p, "npc"), "the target player is not allowed (debug mode in solo, admin role on a server)")
    end)

    -- E01-T16: a real second client with the access level "user" (MP campaign, autoclient.py --mp --clients 2).
    s.test("a real client with the user role is refused without data (E01-T16)", function(t)
        local E = module(t)
        RST.PeerChecks.refusedForUser(t, RST.PeerChecks.adminSpecs({ "npc", "npcSet", "npcRole", "npcName", "npcGoto" },
            710), function() return E.Admin.stats.refused or 0 end)
    end)

    s.test("sheet of a materialized member, bounded hunger read by the next decision", function(t)
        local E = module(t)
        local G, A = E.Groups, E.Admin
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST sheet", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)   -- the player at the home would be an intruder (alert before hunger)
        local decide = E.Decisions.decide
        local seen = {}
        t:defer(function()
            E.Decisions.decide = decide
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove the decision tap, the bodies and group " .. gid)
        for _, spec in ipairs({ { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        t:waitUntil(function() return bodyCount(gid) == 2 end, BODIES_MS, function(t2)
            local npc = memberNpcs(gid)["m-2"]
            local r = A.request(p, { op = "npc", n = 1, npc = npc })
            t2:ok(r.ok, "sheet refused: " .. tostring(r.err))
            local d = r.npc
            t2:ok(type(d) == "table", "no sheet in the answer")
            t2:eq(gid, d.gid, "group of the sheet")
            t2:eq("m-2", d.mid, "member of the sheet")
            t2:eq("worker", d.role, "role")
            t2:eq(true, d.embodied, "embodied")
            t2:ok(type(d.needs) == "table" and type(d.needs.hunger) == "number", "needs missing")
            t2:ok(type(d.health) == "table" and d.health.pct ~= nil, "health missing")
            t2:ok(d.home ~= nil and d.home.x == home.x and d.home.y == home.y, "home of the sheet")
            local z = E.Bodies.find(npc)
            t2:ok(d.pos ~= nil and math.abs(d.pos.x - z:getX()) < 1 and math.abs(d.pos.y - z:getY()) < 1,
                "position of the sheet far from the body")
            t:note(string.format("sheet %s: behaviour %s rule %s, gesture %s, vigilance %s, weapon %s",
                npc, tostring(d.decision and d.decision.b), tostring(d.decision and d.decision.rule),
                tostring(d.gesture), tostring(d.vigilance), tostring(d.weapon and d.weapon.t)))

            -- Decision tap: first evaluation of the member after the setting.
            E.Decisions.decide = function(ctx)
                local out = decide(ctx)
                if ctx ~= nil and ctx.id == npc and seen.rule == nil and seen.armed then
                    seen.rule = out and out.rule or "none"
                    seen.hunger = ctx.needs and ctx.needs.hunger
                end
                return out
            end
            seen.armed = true
            r = A.request(p, { op = "npcSet", n = 2, npc = npc, field = "hunger", value = 150 })
            t2:ok(r.ok, "hunger setting refused: " .. tostring(r.err))
            t2:eq(100, r.value, "hunger kept within its bound")
            t2:eq(100, E.Needs.get(gid, "m-2").hunger, "hunger in the registry")
            t2:ok(adminLog(gid, "hunger m-2"), "no admin log entry for the hunger")
            r = A.request(p, { op = "npcSet", n = 3, npc = npc, field = "health", value = 0 })
            t2:ok(r.ok, "health setting refused: " .. tostring(r.err))
            t2:eq(1, r.value, "health kept within its bound (never a death)")
            t2:ok(not z:isDead() and E.Bodies.find(npc) ~= nil, "body dead after the health setting")
            r = A.request(p, { op = "npcSet", n = 4, npc = npc, field = "health", value = 100 })
            t2:ok(r.ok, "health reset refused: " .. tostring(r.err))
            t2:waitUntil(function() return seen.rule ~= nil end, DECIDE_MS, function(t3)
                t:note("first decision after the setting: rule " .. tostring(seen.rule) .. ", hunger "
                    .. tostring(seen.hunger))
                t3:eq(100, seen.hunger, "hunger read by the next decision")
                t3:ok(seen.rule == "hunger" or seen.rule == "threat" or seen.rule == "fear" or seen.rule == "wound",
                    "rule of the next decision: " .. tostring(seen.rule))
            end, "member not evaluated after the setting")
        end, "group members not materialized")
    end)

    s.test("solo window: sheet opened by the right-click menu, hunger and health set from the window", function(t)
        local E = module(t)
        if type(isServer) == "function" and isServer() then t:skip("solo client window (not on a server)") end
        local S = E.NpcSheet
        if type(S) ~= "table" or S.open == nil or ISWorldObjectContextMenu == nil then
            t:skip("npc sheet window not loaded here (solo client only)")
        end
        t:ok(S.canUse(), "debug mode off: the right-click option is hidden")
        local G, A = E.Groups, E.Admin
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST sheet window", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)
        local context = nil
        t:defer(function()
            if context ~= nil then context:setVisible(false) end
            if S.state.window ~= nil then S.state.window:close() end
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "close the menu and the sheet, remove the bodies and group " .. gid)
        for _, spec in ipairs({ { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:waitUntil(function() return bodyCount(gid) == 2 end, BODIES_MS, function(t2)
            local z = E.Bodies.find(memberNpcs(gid)["m-2"])
            local sq = z:getCurrentSquare()
            t2:ok(sq ~= nil, "body of m-2 without square")
            local objs = {}
            local list = sq:getObjects()
            for i = 0, list:size() - 1 do objs[#objs + 1] = list:get(i) end
            t2:ok(#objs > 0, "no object on the square of m-2")
            local sx = isoToScreenX(0, z:getX(), z:getY(), z:getZ())
            local sy = isoToScreenY(0, z:getX(), z:getY(), z:getZ())
            local offered = S.stats.offered or 0
            context = ISWorldObjectContextMenu.createMenu(0, objs, sx, sy)
            t2:ok(type(context) == "table", "no world context menu (game paused?)")
            local option = context:getOptionFromName(getText("IGUI_LK_Sheet_Menu"))
            t2:ok(option ~= nil, "no sheet option in the right-click menu")
            t2:eq(offered + 1, S.stats.offered, "option counted as offered")
            local npc = option.param1
            local mid = nil
            for m, id in pairs(memberNpcs(gid)) do
                if id == npc then mid = m end
            end
            t2:ok(mid ~= nil, "option for an npc outside the test group: " .. tostring(npc))
            option.onSelect(option.target, option.param1)
            context:setVisible(false)
            local win = S.state.window
            t2:ok(win ~= nil and win:isVisible(), "sheet window not opened by the menu option")
            t2:ok(win:getY() >= 0 and win:getY() + win:getHeight() <= getCore():getScreenHeight() and win:getX() >= 0
                and win:getX() + win:getWidth() <= getCore():getScreenWidth(), "sheet window outside the screen")
            t2:ok(type(win.statusY) == "number" and win.statusY + getTextManager():getFontHeight(UIFont.Small) <= win:getHeight(),
                "sheet controls cut at the bottom of the window (status line at " .. tostring(win.statusY) .. ", height "
                .. tostring(win:getHeight()) .. ")")
            t2:eq(npc, S.state.npc, "npc of the sheet")
            local d = S.state.data
            t2:ok(type(d) == "table" and d.id == npc, "sheet data not received")
            t2:eq(gid, d.gid, "group shown")
            t2:eq(mid, d.mid, "member shown")
            t2:ok(type(d.needs) == "table" and type(d.health) == "table", "needs or health missing from the sheet")
            t2:ok(win.rows.hunger.entry:getText() ~= "", "hunger entry not prefilled")
            -- Hunger and health set through the window controls.
            win.rows.hunger.entry:setText("80")
            win:onSet("hunger")
            t2:eq(80, E.Needs.get(gid, mid).hunger, "hunger set by the window")
            win.rows.health.entry:setText("55")
            win:onSet("health")
            local v = (A.npcView(npc) or {}).npc
            t2:ok(v ~= nil and type(v.health) == "table" and math.abs((v.health.pct or 0) - 55) <= 1, "health set by the window: "
                .. tostring(v and v.health.pct))
            t:note(string.format("sheet of %s (%s %s): hunger 80, health %s", npc, gid, mid,
                tostring(v and v.health and v.health.pct)))
            t2:sleep(1500, function(t3)
                S.refresh()
                local shot = "lk_npcsheet_window_" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
                    .. ".png"
                local okShot, err = pcall(takeScreenshot, shot)
                t3:ok(okShot, "screenshot failed: " .. tostring(err))
                t:note("screenshot " .. shot)
                local shown = tonumber(win.rows.hunger.entry:getText())
                t3:ok(shown ~= nil and math.abs(shown - 80) <= 2, "hunger shown after the refresh: "
                    .. tostring(win.rows.hunger.entry:getText()))
                win.rows.health.entry:setText("100")
                win:onSet("health")
                local v2 = (A.npcView(npc) or {}).npc
                t3:ok(v2 ~= nil and type(v2.health) == "table" and (v2.health.pct or 0) >= 99, "health reset by the window")
            end)
        end, "group members not materialized")
    end)

    -- LK13-T15: admin actions (role within the roles of the type, first and last name, teleport next to the npc).
    s.test("role, name and teleport of a member, done by the authority and noted in the group log", function(t)
        local E = module(t)
        local G, A = E.Groups, E.Admin
        t:ok(type(A.npcRole) == "function" and type(A.npcName) == "function" and type(A.npcGoto) == "function",
            "actions of LK13-T15 not loaded")
        for _, op in ipairs({ "npcRole", "npcName", "npcGoto" }) do
            local r = A.request(nil, { op = op, n = 9, npc = "lk-1", role = "fighter", first = "A", last = "B" })
            t:eq("denied", r.err, op .. " without a player")
        end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST actions", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)
        t:defer(function()
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove the bodies and group " .. gid)
        for _, spec in ipairs({ { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:waitUntil(function() return bodyCount(gid) == 2 end, BODIES_MS, function(t2)
            local npc = memberNpcs(gid)["m-2"]
            local r = A.request(p, { op = "npcRole", n = 1, npc = npc, role = "fighter" })
            t2:ok(r.ok, "role change refused: " .. tostring(r.err))
            t2:eq("fighter", G.get(gid).members["m-2"].role, "role in the registry")
            t2:ok(adminLog(gid, "role m-2"), "no admin log entry for the role")
            r = A.request(p, { op = "npcRole", n = 2, npc = npc, role = "breaker" })
            t2:eq(false, r.ok, "role outside the roles of the type accepted")
            r = A.request(p, { op = "npcName", n = 3, npc = npc, first = "Jane", last = "Doe" })
            t2:ok(r.ok, "renaming refused: " .. tostring(r.err))
            t2:eq("Jane Doe", r.npc.name, "name of the sheet")
            t2:ok(adminLog(gid, "name m-2"), "no admin log entry for the name")
            if RS_LivingKnox ~= nil then
                t2:eq("Jane Doe", RS_LivingKnox.npc(npc).name, "name read by the notebook provider")
            end
            r = A.request(p, { op = "npcName", n = 4, npc = npc, first = "J4ne", last = "Doe" })
            t2:eq("bad name", r.err, "name with a digit accepted")
            r = A.request(p, { op = "npcGoto", n = 5, npc = npc })
            t2:ok(r.ok, "teleport refused: " .. tostring(r.err))
            local z = E.Bodies.find(npc)
            t2:ok(math.abs(r.dest.x - math.floor(z:getX())) <= 1 and math.abs(r.dest.y - math.floor(z:getY())) <= 1,
                "teleport destination far from the body")
            t:note(string.format("teleport destination %d,%d,%d, moved by the authority: %s", r.dest.x, r.dest.y,
                r.dest.z, tostring(r.moved)))
            local onServer = type(isServer) == "function" and isServer()
            t2:eq(not onServer, r.moved, "player moved by the authority (solo only)")
            t2:ok(adminLog(gid, "teleport of admin"), "no admin log entry for the teleport")
        end, "group members not materialized")
    end)
end)
