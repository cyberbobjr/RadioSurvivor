--[[
wiki.shots - screenshots of the player wiki (docs/wiki/images), staged in a solo test game. Development mod only.
Not part of any campaign: run it on purpose, solo, on a save named rstest*, with the bridge program and its real model:
    python tools/autoclient/autoclient.py --suite wiki.shots --tags world --bridge on --timeout 2400
The screenshots land in Zomboid/Screenshots of the cache (copied to the run folder by the launcher):
wiki_<LANG>_<view>.png, LANG = EN then FR (game language switched by Translator.setLanguage + Translator.loadFiles for
each pass, the language of origin given back at the end). Views of each pass:
    radio_transmit   walkie-talkie in hand, vanilla radio window with the "Transmit" section, a sentence sent to Walt
                     and his real answer (bridge) in the last lines;
    walkie_in_hand   game view zoomed on the player holding the walkie-talkie;
    frequency_note   frequency note of Walt opened in the vanilla document window;
    group_home       Living Knox test group (four members, two fighters) materialized at its home (the player's
                     square), game view zoomed;
    npc_bubble       one member selected with the notebook and spoken to (Say line): its real answer in a bubble;
    admin_window     Living Knox administration window (debug mode) on the test group;
    npc_sheet        sheet of one member (debug mode);
    notebook_contacts, notebook_missions, notebook_report, notebook_radio, notebook_reputation
                     the notebook filled with a fixed, translated snapshot and radio history (the server snapshots are
                     ignored while it runs, then asked again);
    map_zone         world map centred on the circle of an engaged scouting mission of that snapshot;
    sandbox_rs, sandbox_lk
                     sandbox options pages "Radio Survivor" and "Living Knox" (vanilla debug sandbox window).
Display: windowed at the largest mode up to 1920x1080 (else 1280x720), Lua debugger and debug console hidden, game
view zoomed in for the world views; everything restored at the end (display, zoom, language, notebook, map symbols,
test group, items).
Tags "world" (solo only: every test is SKIP on a server or an MP client).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"

local F, R = RST.Fixtures, RST.RSHelpers

local W = {}
RST.WikiShots = W

W.LANGS = { "EN", "FR" }
W.SHOW_MS = 1200
W.ZOOM_STEPS = 2
W.BODIES_MS = 60000
W.WALT_MS = 120000

-- ------------------------------------------------------------------------------------------------- helpers

local function solo(t)
    if (type(isServer) == "function" and isServer()) or (type(isClient) == "function" and isClient()) then
        t:skip("wiki screenshots: solo only")
    end
end

local function hideDebug()
    pcall(function() UIManager.setShowLuaDebuggerOnError(false) end)
    pcall(function()
        local c = UIManager.getDebugConsole()
        if c ~= nil then c:setVisible(false) end
    end)
end

local function shot(t, lang, view)
    W.cleanScreen()
    local name = "wiki_" .. lang .. "_" .. view .. ".png"
    local ok, err = pcall(takeScreenshot, name)
    t:ok(ok, view .. ": screenshot failed: " .. tostring(err))
    t:note("screenshot " .. name .. " (" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight() .. ")")
    return name
end

-- Chain of steps: each step(t, nextStep) registers its own wait.
local function chain(t, steps, i, finish)
    if i > #steps then return finish and finish(t) or nil end
    return steps[i](t, function(t2) return chain(t2, steps, i + 1, finish) end)
end

-- Notebook button of the left bar: its title is read once when the bar is built.
function W.refreshSidebar()
    local bar = ISEquippedItem and ISEquippedItem.instance
    local b = bar and bar.rsCarnet
    if b ~= nil then
        pcall(function() b:setTitle(getText("IGUI_RS_Notebook")) end)
    end
end

-- Clean screen: inventory, loot and character windows hidden, corner watermark (coordinates, cheats) not drawn.
function W.cleanScreen()
    hideDebug()
    local st = W.state
    if st.panels == nil then
        st.panels = {}
        for _, get in ipairs({ getPlayerInventory, getPlayerLoot, getPlayerInfoPanel }) do
            local ok, e = pcall(get, 0)
            if ok and e ~= nil then st.panels[#st.panels + 1] = { e = e, visible = e:isVisible() } end
        end
    end
    for _, it in ipairs(st.panels) do it.e:setVisible(false) end
    if WaterMarkUI ~= nil and st.waterMark == nil then
        st.waterMark = WaterMarkUI.render
        WaterMarkUI.render = function(self)
            st.waterPanel = self
            self:setVisible(false)
        end
    end
end

function W.restoreScreen()
    local st = W.state
    for _, it in ipairs(st.panels or {}) do it.e:setVisible(it.visible) end
    if st.waterMark ~= nil then
        WaterMarkUI.render = st.waterMark
        if st.waterPanel ~= nil then st.waterPanel:setVisible(true) end
    end
end

-- God mode only (invisibility hides nothing useful here and shows in the cheat list).
local function god(t, p)
    local was = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(was) end, "god mode given back")
end

-- Corpses within r squares of the player removed (clean scenes; test save only).
local function clearCorpses(t, p, r)
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local n = 0
    for dy = -r, r do
        for dx = -r, r do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            local bodies = sq and sq:getDeadBodys()
            if bodies ~= nil then
                for i = bodies:size() - 1, 0, -1 do
                    sq:removeCorpse(bodies:get(i), false)
                    n = n + 1
                end
            end
        end
    end
    if n > 0 then t:note(n .. " corpse(s) removed around the player") end
end

local function setLanguage(code)
    local list = Translator.getAvailableLanguage()
    for i = 0, list:size() - 1 do
        local l = list:get(i)
        if tostring(l:name()) == code then
            getCore():setOptionLanguageName(code)
            Translator.setLanguage(l)
            Translator.loadFiles()
            W.refreshSidebar()
            return true
        end
    end
    return false
end

local function zoomIn(t, steps)
    for _ = 1, steps do getCore():doZoomScroll(0, -1) end
    t:defer(function()
        for _ = 1, steps do getCore():doZoomScroll(0, 1) end
    end, "camera zoom given back")
end

local function clearZombies(t, p, radius)
    local I = LivingKnox and LivingKnox.Identity
    local list = getCell():getZombieList()
    local px, py = p:getX(), p:getY()
    local removed = 0
    for i = list:size() - 1, 0, -1 do
        local z = list:get(i)
        if z ~= nil and not z:isDead() and math.abs(z:getX() - px) <= radius and math.abs(z:getY() - py) <= radius
            and not (z:hasModData() and I ~= nil and I.readTag(z:getModData()) ~= nil) then
            z:removeFromWorld()
            z:removeFromSquare()
            removed = removed + 1
        end
    end
    if removed > 0 then t:note(removed .. " zombie(s) removed around the player") end
end

local function player(t)
    local p = F.player(t)
    t:ok(p ~= nil, "no player")
    return p
end

-- ------------------------------------------------------------------------------------------------- display

-- Shared by every test of a run: the display is set once (first test) and given back by the last test.
W.state = W.state or {}

local function largest()
    local best = { 1280, 720 }
    local ok, list = pcall(function() return getCore():getScreenModes() end)
    if not ok or list == nil then return best end
    local full = false
    for _, s in ipairs(list) do
        local w, h = string.match(tostring(s), "(%d+)%s*x%s*(%d+)")
        w, h = tonumber(w), tonumber(h)
        if w and h then
            if w >= 1920 and h >= 1080 then full = true end
            if w <= 1920 and h <= 1080 and w * h > best[1] * best[2] then best = { w, h } end
        end
    end
    if full then best = { 1920, 1080 } end
    return best
end

-- ------------------------------------------------------------------------------------------------- texts

-- Texts of the fixture (the notebook shows them as they are: written per language).
-- luacheck: push no max line length
local TEXT = {
    EN = {
        walt = "Walt, do you copy? This is a survivor near the river, I have a radio now.",
        npc = "Hello there! I come in peace. Is this your place?",
        group = "Riverside Survivors",
        contacts = {
            { name = "Lena Moreau", style = "Helpful", bg = "Former paramedic from Muldraugh, keeps the first aid kit of the old station.",
                note = "Needs bandages. Trusts me since the pharmacy run.",
                talk = { { "Lena Moreau", "You again. The bandages helped, thank you." }, { "You", "Anything else you need?" },
                    { "Lena Moreau", "Someone should look at the church on the hill. Nobody came back from there." } } },
            { name = "Bill Harper", style = "Direct", bg = "Truck driver, knows every road between Muldraugh and West Point.",
                note = "", talk = { { "Bill Harper", "Keep your distance until I know you." } } },
            { name = "Rosa Delgado", style = "Prudent", bg = "Gardener, grows beans behind the school.", note = "",
                talk = { { "Rosa Delgado", "We trade seeds for batteries, if you have some." } } },
        },
        radio = {
            { "said", "Walt, do you copy? Anyone on this frequency?" },
            { "reply", "Copy that, stranger. Keep your voice down, they hear more than you think." },
            { "said", "Where is it safe around here?" },
            { "reply", "Nowhere is safe. The river bank north of town was quiet yesterday." },
            { "heard", "Static, then a voice counting numbers." },
        },
    },
    FR = {
        walt = "Walt, tu me re\195\167ois ? Ici un survivant pr\195\168s de la rivi\195\168re, j'ai trouv\195\169 une radio.",
        npc = "Bonjour ! Je viens en paix. C'est chez vous, ici ?",
        group = "Survivants de la rivi\195\168re",
        contacts = {
            { name = "Lena Moreau", style = "Helpful", bg = "Ancienne ambulanci\195\168re de Muldraugh, garde la trousse de l'ancienne caserne.",
                note = "Manque de pansements. Me fait confiance depuis la pharmacie.",
                talk = { { "Lena Moreau", "Encore toi. Les pansements ont aid\195\169, merci." }, { "Vous", "Il te faut autre chose ?" },
                    { "Lena Moreau", "Il faudrait voir l'\195\169glise sur la colline. Personne n'en est revenu." } } },
            { name = "Bill Harper", style = "Direct", bg = "Routier, conna\195\174t toutes les routes entre Muldraugh et West Point.",
                note = "", talk = { { "Bill Harper", "Garde tes distances tant que je ne te connais pas." } } },
            { name = "Rosa Delgado", style = "Prudent", bg = "Jardini\195\168re, cultive des haricots derri\195\168re l'\195\169cole.", note = "",
                talk = { { "Rosa Delgado", "On \195\169change des graines contre des piles, si tu en as." } } },
        },
        radio = {
            { "said", "Walt, tu me re\195\167ois ? Quelqu'un sur cette fr\195\169quence ?" },
            { "reply", "Re\195\167u, l'inconnu. Parle moins fort, ils entendent plus que tu ne crois." },
            { "said", "O\195\185 est-ce qu'on est \195\160 l'abri par ici ?" },
            { "reply", "Nulle part. La berge au nord de la ville \195\169tait calme hier." },
            { "heard", "Des parasites, puis une voix qui compte des chiffres." },
        },
    },
}
-- luacheck: pop

local function relationOf(i)
    if i == 1 then
        return { level = "trusting", trend = "up", group = "favorable", today = 12, suspended = false,
            agreements = { { kind = "truce", state = "applicable",
                scope = { group = "all_members", team = "current_members" } } },
            facts = { { fact = "gift", nature = "good", source = "personal", day = 11 },
                { fact = "delivery", nature = "good", source = "group", day = 9 } } }
    elseif i == 2 then
        return { level = "wary", trend = "stable", group = "cautious", today = 12, suspended = false, agreements = {},
            facts = { { fact = "theft", nature = "bad", source = "group", day = 6 } } }
    end
    return { level = "cautious", trend = "up", group = "cautious", today = 12, suspended = false, agreements = {}, facts = {} }
end

function W.fixture(Client, p, lang, zone)
    local T = TEXT[lang]
    local desc = p:getDescriptor()
    local me = desc and (desc:getForename() .. " " .. desc:getSurname()) or "Survivor"
    local contacts = {}
    for i, c in ipairs(T.contacts) do
        local history = {}
        for k, line in ipairs(c.talk) do history[k] = { author = line[1], text = line[2] } end
        contacts[i] = { id = "wiki_c" .. i, name = c.name, alive = true, near = i == 1, groupName = T.group,
            personality = { style = c.style, courage = 3 + (i % 2), sociability = 4 - (i % 2), generosity = 3 },
            background = c.bg, revision = 1, history = history, note = c.note, relation = relationOf(i) }
    end
    local missions = {
        { id = "wiki_m1", npc = "wiki_c1", titleKey = "IGUI_RS_Scout", state = "active", revision = 2,
            template = "scout", placeKind = "church", mapZone = zone, zoneReached = false,
            clues = { { key = "Kind", args = { "church", "medium", "1" } } },
            remainingMs = 5400000, durationMs = 7200000, rewardType = "Base.Bullets9mm", rewardCount = 12,
            claimedName = "", engaged = true, invited = true, recovery = false, participants = { me },
            requester = T.contacts[1].name, near = true },
        { id = "wiki_m2", npc = "wiki_c3", titleKey = "IGUI_RS_Scout", state = "active", revision = 3,
            template = "scout", placeKind = "school", zoneReached = true, reachedBy = me, toReport = true,
            remainingMs = 2400000, durationMs = 7200000, rewardType = "Base.Battery", rewardCount = 4,
            claimedName = "", engaged = true, invited = true, recovery = false, participants = { me },
            requester = T.contacts[3].name, near = false },
    }
    local reputation = { available = true, level = "good", trend = "up", today = 12,
        change = { day = 9, from = "neutral", to = "good" },
        reasons = { { reasonKey = "IGUI_RS_RepReason_MissionSuccess", reasonArgs = { T.contacts[1].name }, day = 11, sign = 1 },
            { reasonKey = "IGUI_RS_RepReason_RescueSuccess", reasonArgs = {}, day = 9, sign = 1 },
            { reasonKey = "IGUI_RS_RepReason_MissionAbandoned", reasonArgs = { T.contacts[2].name }, day = 4, sign = -1 } } }
    return { world = Client.world, run = Client.run, selected = "wiki_c1", npcProvider = true, storage = true,
        contacts = contacts, missions = missions, reputation = reputation,
        inviteTargets = { { id = "wiki_p2", name = "Alice Brennan" } }, events = {}, team = nil }
end

function W.radioHistory(lang, khz)
    local lines = {}
    for i, l in ipairs(TEXT[lang].radio) do
        lines[i] = { kind = l[1], text = l[2], when = "12/07 14:" .. (10 + i * 3), seq = i }
    end
    return { { khz = khz, last = #lines, lines = lines } }
end

-- Fixed snapshot and history in the real client (server snapshots and history answers ignored until the cleanup).
local function installNotebook(t, p, lang, khz, zone)
    local Notebook = require "RadioSurvivor/RS_Notebook"
    local Client = RS_CarnetClient
    t:ok(Notebook ~= nil and Client ~= nil, "notebook client not loaded")
    local History = require "RadioSurvivor/RS_RadioHistory"
    local Const = require "RadioSurvivor/RadioSurvivor_Const"
    local saved = { snapshot = Client.snapshot, receive = Client.receive, window = Client.window,
        open = Client.window ~= nil and Client.window:isVisible(), frequencies = History.frequencies,
        unread = History.unread, hreceive = History.receive, hrequest = History.request }
    local fixture = W.fixture(Client, p, lang, zone)
    Client.snapshot = fixture
    Client.receive = function(command, args)
        if command == "snapshot" then return end
        return saved.receive(command, args)
    end
    local cmd = Const.CMD
    History.receive = function(command, args)
        if command == cmd.HISTORY or command == cmd.HISTORY_LINES or command == cmd.HISTORY_ADD then return true end
        return saved.hreceive(command, args)
    end
    History.request = function() return true end
    History.frequencies, History.unread = W.radioHistory(lang, khz), false
    if saved.window then saved.window:close() end
    Client.window = nil
    t:defer(function()
        if Client.window and Client.window ~= saved.window then
            Client.window:releaseFocus()
            Client.window:setVisible(false)
            Client.window:removeFromUIManager()
        end
        Client.receive, History.receive, History.request = saved.receive, saved.hreceive, saved.hrequest
        Client.snapshot, Client.window = saved.snapshot, saved.window
        History.frequencies, History.unread = saved.frequencies, saved.unread
        if saved.window and saved.open then
            saved.window:setVisible(true)
            saved.window:refresh()
        end
        Client.send("snapshot")
        History.request()
    end, "notebook, snapshot and radio history restored")
    Notebook.toggle()
    return Client.window, fixture
end

local function showPage(w, tab, id)
    w:changeTab(tab)
    if id ~= nil then
        w.selectedId = id
        w:refresh()
    end
    w:layout()
end

-- ------------------------------------------------------------------------------------------------- tests

local function waltKhz()
    local P = require "RadioSurvivor/RS_Personas"
    local khz = P.served("walt")[1]
    if khz == nil or P.get("walt").state ~= "active" then return nil end
    return khz
end

local function memberNpcs(gid)
    local g = LivingKnox.Groups.get(gid)
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
        if LivingKnox.Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

local function radioTest(lang)
    return function(t)
        solo(t)
        W.cleanScreen()
        local p = player(t)
        god(t, p)
        clearCorpses(t, p, 15)
        local khz = waltKhz()
        if khz == nil then t:skip("walt is not an active voice") end
        local Module = require "RadioSurvivor/RS_RadioModule"
        local Talk = Module.Talk
        local item = R.radioInHand(t, p, "Base.WalkieTalkie5", khz)
        pcall(function() p:resetEquippedHandsModels() end)
        local heard = R.hear(t)
        -- The vanilla radio window is kept per player (ISRadioWindow.instances) with the texts of its first opening:
        -- a new one is built so that its sections are in the language of this pass.
        local pn = p:getPlayerNum()
        for _, list in ipairs({ ISRadioWindow.instances, ISRadioWindow.instancesIso }) do
            if list ~= nil and list[pn] ~= nil then
                list[pn]:removeFromUIManager()
                list[pn] = nil
            end
        end
        local w = ISRadioWindow.activate(p, item)
        t:defer(function() if w:isVisible() then w:close() end end, "close the radio window")
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        w:setX(math.floor(sw * 0.62)); w:setY(math.floor(sh * 0.12))
        local record = w.rsTalkRecord
        local entry = record.element.subpanel.entry
        local phrase = TEXT[lang].walt
        t:waitUntil(function() return record.enabled and record.element:isVisible() and Talk.busyReason() == nil end,
            30000, function(t2)
            entry:focus()
            entry:setText(phrase)
            local sentAt = getTimestampMs()
            entry.onCommandEntered()
            t2:waitUntil(function()
                for _, line in ipairs(R.words(heard, khz, sentAt)) do
                    if line ~= phrase then return line end
                end
                return nil
            end, W.WALT_MS, function(t3, line)
                t3:note("Walt answered: " .. line)
                t3:waitQuiet(function() return Talk.busyReason() == nil end, 30000, function(t3b)
                  t3b:sleep(1500, function(t4)
                    shot(t4, lang, "radio_transmit")
                    w:close()
                    pcall(function() p:resetEquippedHandsModels() end)
                    pcall(function() p:resetModelNextFrame() end)
                    zoomIn(t4, W.ZOOM_STEPS)
                    t4:sleep(2500, function(t5)
                        shot(t5, lang, "walkie_in_hand")
                        -- Frequency note of Walt in the vanilla document window.
                        local Notes = require "RadioSurvivor/RS_Notes"
                        local def = Notes.forVoice("walt")
                        t5:ok(def ~= nil, "no note for walt")
                        require "TimedActions/ISReadABook"
                        local original = PZAPI.UI.PrintMedia
                        local opened = {}
                        PZAPI.UI.PrintMedia = function(args)
                            local win = original(args)
                            opened[#opened + 1] = win
                            return win
                        end
                        t5:defer(function()
                            PZAPI.UI.PrintMedia = original
                            for _, win in ipairs(opened) do
                                if win.javaObj then UIManager.RemoveElement(win.javaObj) end
                            end
                        end, "close the note")
                        ISReadABook:new(p, instanceItem(def.fullType)):displayPrintMedia()
                        t5:ok(#opened == 1, "note window not opened")
                        t5:sleep(W.SHOW_MS, function(t6) shot(t6, lang, "frequency_note") end)
                    end)
                  end)
                end, "input still greyed 30 s after the answer")
            end, "no answer of Walt (is the bridge running?)")
        end, "Transmit section not shown")
    end
end

local function livingKnoxTest(lang)
    return function(t)
        solo(t)
        W.cleanScreen()
        local E = LivingKnox
        if E == nil or not E.Config.isEnabled() then t:skip("Living Knox disabled") end
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = player(t)
        god(t, p)
        local Server = R.notebook(t)
        local cid = R.character(t, p)
        local spot, home = W.outdoorSpot(p)
        if spot == nil then
            home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
            t:note("no open outdoor place around the player: group at the player's square")
            return W.groupScene(t, lang, E, p, Server, cid, home)
        end
        F.movePlayer(t, p, spot.x + 0.5, spot.y + 0.5, 0, function(t2)
            t2:sleep(1500, function(t3) return W.groupScene(t3, lang, E, p, Server, cid, home) end)
        end)
    end
end

-- Open outdoor square near the player (itself and its 8 neighbours outside and free) and a home square 4 squares
-- east or south of it, also open; nil when none within 25 squares.
local function open(cell, x, y)
    local Bodies = LivingKnox.Bodies
    for dy = -1, 1 do
        for dx = -1, 1 do
            local sq = cell:getGridSquare(x + dx, y + dy, 0)
            if sq == nil or not sq:isOutside() or not Bodies.freeSquare(sq) then return false end
        end
    end
    return true
end

function W.outdoorSpot(p)
    local cell = getCell()
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    for r = 2, 25 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r and open(cell, px + dx, py + dy) then
                    local x, y = px + dx, py + dy
                    for _, d in ipairs({ { 4, 0 }, { 0, 4 }, { -4, 0 }, { 0, -4 } }) do
                        if open(cell, x + d[1], y + d[2]) then
                            return { x = x, y = y }, { x = x + d[1], y = y + d[2], z = 0 }
                        end
                    end
                end
            end
        end
    end
    return nil
end

function W.groupScene(t, lang, E, p, Server, cid, home)
        local G = E.Groups
        local K = RST.LKHelpers
        clearCorpses(t, p, 15)
        clearZombies(t, p, 25)
        local g = assert(G.create({ type = "settlers", name = TEXT[lang].group, day = G.today(), home = home }))
        local gid = g.id
        if E.Homes ~= nil and E.Homes.skip ~= nil then E.Homes.skip(gid) end
        K.hidePlayersFrom(t, gid)
        t:defer(function()
            if E.AdminView and E.AdminView.state.window then E.AdminView.state.window:close() end
            if E.NpcSheet and E.NpcSheet.state.window then E.NpcSheet.state.window:close() end
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove the test group and its bodies")
        for _, spec in ipairs({ { "worker", "handyman", false }, { "fighter", nil, false }, { "fighter", nil, true },
            { "worker", "farmer", true } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = spec[3], day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        zoomIn(t, 1)
        t:waitUntil(function() return bodyCount(gid) == 4 end, W.BODIES_MS, function(t2)
            t2:sleep(4000, function(t3)
                shot(t3, lang, "group_home")
                -- Nearest member the notebook can select.
                local P = require "RadioSurvivor/RS_NPCProvider"
                local C = require "RadioSurvivor/RS_Config"
                local best, bestD
                for _, npc in pairs(memberNpcs(gid)) do
                    local z = E.Bodies.find(npc)
                    if z ~= nil and P.near(p, z, C.SELECT_RANGE) then
                        local d = (z:getX() - p:getX()) ^ 2 + (z:getY() - p:getY()) ^ 2
                        if bestD == nil or d < bestD then best, bestD = npc, d end
                    end
                end
                t3:ok(best ~= nil, "no member near enough to be selected")
                local fiche = Server.ensure(best)
                t3:ok(fiche ~= nil, "no notebook fiche for " .. tostring(best))
                t3:waitQuiet(function() return Server.objects[fiche.id] ~= nil end, 10000, function(t4)
                    local c = { Server = Server, C = C, p = p, cid = cid, id = best, fiche = fiche }
                    R.select(t4, c, function(t5)
                        local contact = Server.store.data.characters[cid].contacts[fiche.id]
                        R.talk(t5, c, TEXT[lang].npc, function(t6, req)
                            local View = E.SpeechView
                            local since = View.stats.drawn or 0
                            t6:waitUntil(function()
                                contact = contact or Server.store.data.characters[cid].contacts[fiche.id]
                                local answered = false
                                for _, h in ipairs(contact and contact.history or {}) do
                                    if h.id == req.id then answered = h.text end
                                end
                                local body = E.Bodies.find(best)
                                if answered and body ~= nil then
                                    for _, bb in ipairs(View.bubbles or {}) do
                                        if bb.z == body and (View.stats.drawn or 0) > since then return answered end
                                    end
                                end
                                return nil
                            end, C.REQUEST_TIMEOUT_MS + 10000, function(t7, answer)
                                t7:note("bubbles " .. #(View.bubbles or {}))
                                t7:note("npc answered: " .. tostring(answer))
                                t7:sleep(600, function(t8)
                                    shot(t8, lang, "npc_bubble")
                                    -- Administration window and sheet (debug mode).
                                    if not isDebugEnabled() then return t8:note("debug mode off: no admin window") end
                                    E.AdminView.open()
                                    E.AdminView.select(gid)
                                    t8:sleep(2000, function(t9)
                                        shot(t9, lang, "admin_window")
                                        E.AdminView.state.window:close()
                                        E.NpcSheet.open(best)
                                        t9:waitUntil(function() return E.NpcSheet.state.data ~= nil end, 10000, function(t10)
                                            t10:sleep(1500, function(t11) shot(t11, lang, "npc_sheet") end)
                                        end, "npc sheet data not received")
                                    end)
                                end)
                            end, function()
                                local n = 0
                                for _, h in ipairs(contact and contact.history or {}) do
                                    n = n + 1
                                    t6:note("history " .. tostring(h.id) .. " " .. tostring(h.author) .. ": " .. tostring(h.text))
                                end
                                return "no answer bubble of the npc (req " .. tostring(req.id) .. ", history " .. n
                                    .. ", bubbles " .. #(View.bubbles or {}) .. "): " .. R.bridgeCause(Server, req.sent)
                            end)
                        end)
                    end)
                end, "body never mapped by the notebook")
            end)
        end, "the four members never got bodies")
end

local function notebookTest(lang)
    return function(t)
        solo(t)
        W.cleanScreen()
        local p = player(t)
        local khz = waltKhz() or 145000
        local zone = { x = math.floor(p:getX()) + 70, y = math.floor(p:getY()) - 50, r = 45 }
        local w, fixture = installNotebook(t, p, lang, khz, zone)
        t:ok(w ~= nil, "notebook not opened")
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local ww, wh = math.min(1180, sw - 80), math.min(760, sh - 120)
        w:setX(math.floor((sw - ww) / 2)); w:setY(math.floor((sh - wh) / 2)); w:setWidth(ww); w:setHeight(wh)
        local pages = {
            { "Contacts", "wiki_c1", "notebook_contacts" },
            { "Missions", "wiki_m1", "notebook_missions" },
            { "Missions", "wiki_m2", "notebook_report" },
            { "Radio", khz, "notebook_radio" },
            { "Reputation", nil, "notebook_reputation" },
        }
        local steps = {}
        for _, pg in ipairs(pages) do
            steps[#steps + 1] = function(t2, nextStep)
                showPage(w, pg[1], pg[2])
                t2:sleep(W.SHOW_MS, function(t3)
                    shot(t3, lang, pg[3])
                    return nextStep(t3)
                end)
            end
        end
        -- Circle of the engaged scouting mission on the world map.
        steps[#steps + 1] = function(t2, nextStep)
            w:setVisible(false)
            local MapActions = require "RadioSurvivor/RS_MapActions"
            MapActions.resetZonesForTests()
            local res = MapActions.zones(fixture.missions)
            t2:ok(res ~= nil, "map zones not drawn")
            t2:defer(function()
                MapActions.resetZonesForTests()
                local Client = RS_CarnetClient
                MapActions.zones(Client.snapshot and Client.snapshot.missions or {})
            end, "map circles of the real snapshot drawn again")
            -- The world map pauses a solo game (no OnTick, so no RST wait): the screenshot is taken by an
            -- OnTickEvenPaused listener, then the map is closed and the game resumes.
            local done, startMs = false, getTimestampMs()
            local function onPaused()
                if getTimestampMs() - startMs < 2500 then return end
                Events.OnTickEvenPaused.Remove(onPaused)
                W.cleanScreen()
                local ok = pcall(takeScreenshot, "wiki_" .. lang .. "_map_zone.png")
                done = ok and "ok" or "failed"
                ISWorldMap.HideWorldMap(0)
            end
            t2:defer(function()
                Events.OnTickEvenPaused.Remove(onPaused)
                ISWorldMap.HideWorldMap(0)
            end, "world map closed")
            Events.OnTickEvenPaused.Add(onPaused)
            ISWorldMap.ShowWorldMap(0, zone.x, zone.y, 16.5)
            t2:waitUntil(function() return done end, 20000, function(t3, result)
                t3:note("screenshot wiki_" .. lang .. "_map_zone.png: " .. tostring(result))
                return nextStep(t3)
            end, "world map screenshot not taken")
        end
        chain(t, steps, 1)
    end
end

local function sandboxTest(lang)
    return function(t)
        solo(t)
        W.cleanScreen()
        if ISServerSandboxOptionsUI == nil then t:skip("vanilla sandbox window not loaded") end
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local ui = ISServerSandboxOptionsUI:new(150, 150, 800, 600)
        ui:initialise()
        ui:addToUIManager()
        t:defer(function()
            ui:setVisible(false)
            ui:removeFromUIManager()
        end, "sandbox window closed")
        ui:setX(math.max(0, math.floor((sw - ui:getWidth()) / 2)))
        ui:setY(math.max(0, math.floor((sh - ui:getHeight()) / 2)))
        local steps = {}
        for _, pg in ipairs({ { "Sandbox_RadioSurvivor", "sandbox_rs" }, { "Sandbox_LivingKnox", "sandbox_lk" } }) do
            steps[#steps + 1] = function(t2, nextStep)
                local title = getText(pg[1])
                local found = nil
                for i, it in ipairs(ui.listbox.items) do
                    if it.text == title then found = i end
                end
                t2:ok(found ~= nil, "no sandbox page " .. title)
                ui.listbox.selected = found
                pcall(function() ui.listbox:ensureVisible(found) end)
                ui:onMouseDownListbox(ui.listbox.items[found].item)
                t2:sleep(W.SHOW_MS, function(t3)
                    shot(t3, lang, pg[2])
                    return nextStep(t3)
                end)
            end
        end
        chain(t, steps, 1)
    end
end

RST.suite("wiki.shots", { tags = { "world" }, testTimeoutMs = 420000, timeoutMs = 2700000 }, function(s)
    s.test("display: windowed at the largest mode, debug windows hidden", function(t)
        solo(t)
        local core = getCore()
        if W.state.mode == nil then
            W.state.mode = { w = core:getScreenWidth(), h = core:getScreenHeight(), full = core:isFullScreen(),
                borderless = core:getOptionBorderlessWindow() }
            W.state.lang = Translator.getLanguage()
        end
        local size = largest()
        -- Borderless: the window covers the whole monitor (a framed 1920x1080 window loses the taskbar height).
        core:setOptionBorderlessWindow(size[1] >= 1920)
        core:setResolutionAndFullScreen(size[1], size[2], false)
        W.cleanScreen()
        t:ok(core:getScreenWidth() >= 1280, "display too small")
        t:note("asked " .. size[1] .. "x" .. size[2] .. ", got " .. core:getScreenWidth() .. "x" .. core:getScreenHeight())
        local hour = getGameTime():getHour()
        t:note("game hour " .. tostring(hour))
    end)

    for _, lang in ipairs(W.LANGS) do
        s.test("[" .. lang .. "] game language", function(t)
            solo(t)
            t:ok(setLanguage(lang), "language " .. lang .. " not available")
            t:eq(lang, tostring(Translator.getLanguage():name()), "language switched")
            t:note(lang .. ": " .. getText("IGUI_RadioSurvivor_Module"))
        end)
        s.test("[" .. lang .. "] radio, walkie-talkie and frequency note", radioTest(lang))
        s.test("[" .. lang .. "] Living Knox group, bubble, admin window and sheet", livingKnoxTest(lang))
        s.test("[" .. lang .. "] notebook pages and map circle", notebookTest(lang))
        s.test("[" .. lang .. "] sandbox pages", sandboxTest(lang))
    end

    s.test("restore language and display", function(t)
        solo(t)
        if W.state.lang ~= nil then
            getCore():setOptionLanguageName(tostring(W.state.lang:name()))
            Translator.setLanguage(W.state.lang)
            Translator.loadFiles()
            W.refreshSidebar()
        end
        W.restoreScreen()
        local m = W.state.mode
        if m ~= nil then
            local core = getCore()
            core:setOptionBorderlessWindow(m.borderless)
            core:setResolutionAndFullScreen(m.w, m.h, m.full)
        end
        W.state = {}
        t:ok(Translator.getLanguage() ~= nil, "no game language after the restore")
        t:note("language " .. tostring(Translator.getLanguage():name()) .. ", display "
            .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight())
    end)
end)

return W
