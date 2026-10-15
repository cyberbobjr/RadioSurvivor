--[[
rs.notebook.visual - visual protocol of the notebook, scripted (E03-T02, client/RadioSurvivor/RS_Notebook.lua).
No gesture needed: the suite fills the REAL notebook with a fixed client snapshot and radio history (no server data
changed: the server snapshots and history answers are ignored while it runs, then asked again), opens it, shows
every page and dialog, checks by script what can be checked and takes one screenshot per view
(Zomboid/Screenshots/rs_notebook_<view>_<w>x<h>_fs<n>.png, n = getOptionFontSizeReal).
Checks of every view: every visible control inside its window (and the window inside the screen), no button text
wider than its button, no bookmark label cut, no fixed label (list header, target footer, second line of a row,
Reputation title) wider than its place, at most two lines for a status, no page line wider than the page, page
written in dark ink, no raw IGUI_ key, controls above the resize strip and never on top of each other.
Delivery window (E03-T07): an item with a very long name is added to the inventory for the run; every row as drawn
stays left of the scroll bar, a name too long ends with "..."; the window opens over the notebook (centre inside it),
never on the sidebar, and stays whole on the screen even for a notebook pushed past a corner.
Tests:
  1. "translation tables" (synchronous): EN and FR tables of the mod (media/lua/shared/Translate/<L>/IG_UI.json,
     read by getModFileReader) given to getText while an off-screen notebook is laid out at its minimum size, with the
     current font and with a larger one (Small measured as Medium, Medium as Large: the font size option needs a
     restart in game, UI_optionscreen_needreboot); every page, the delivery window and the four confirmations are
     checked, then every notebook string of the table is measured against the width of its place.
  2. "views at 1280x720 and the largest screen": windowed mode (borderless off), 1280x720 then 1920x1080 or the
     largest mode under it; every page, the delivery window, two confirmations, minimum and large window size (the
     controls follow the window), a screenshot each. The display mode of origin is restored afterwards.
  3. "scroll, refresh, collapse, close, sidebar button and shortcut" at the current resolution.
Tags "client" and "ui". RST.run({ suite = "rs.notebook.visual" }) (any save, solo or MP client, debug mode).
Cleanup: test windows and dialogs removed, display mode, snapshot, history, receive hooks and the player's own
notebook window (hidden during the run) restored; a real snapshot and the real history are asked again.
Left to the eye on the captures: docs/carnet-validation-04221.md ("E03-T02").
]]

require "RST/RST"

local V = {}
RST.NotebookVisual = V -- read by tests/test_notebook_visual.py

V.MOD_ID = "batman_RadioSurvivor"
V.LANGS = { "EN", "FR" }
V.SHOW_MS = 450
V.AFTER_MS = 150
V.DARK = 1.5
V.MAX_NOTES = 80
V.LONG_ITEM = "Sterilized Bandage of the Riverside Survivors Collective, kept dry in its original wrapping since July"
V.PAGES = {
    { name = "radio", tab = "Radio", id = 145000 },
    { name = "contacts", tab = "Contacts", id = "rsv_c01" },
    { name = "missions", tab = "Missions", id = "rsv_m1" },
    { name = "offer", tab = "Missions", id = "rsv_m2" },
    { name = "reputation", tab = "Reputation" },
    { name = "team", tab = "Team", id = "rsv_t2" },
}

local function measure(text, font) return getTextManager():MeasureStringX(font or UIFont.Small, tostring(text or "")) end
local function hasKey(s) return type(s) == "string" and string.find(s, "IGUI_", 1, true) ~= nil end
local function rtr(key, ...) return getText("IGUI_RS_" .. key, ...) end
local function int(v) return math.floor((tonumber(v) or 0) + 0.5) end

-- %1..%9 of a translated text replaced like Translator.getText.
local function subst(s, ...)
    local args = { ... }
    return (string.gsub(s, "%%(%d)", function(i)
        local v = args[tonumber(i)]
        if v == nil then return "%" .. i end
        return tostring(v)
    end))
end

-- ------------------------------------------------------------------------------------------------ fonts and tables

local function larger(font)
    if font == nil or font == UIFont.Small then return UIFont.Medium end
    if font == UIFont.Medium then return UIFont.Large end
    return font
end

-- Runs fn with every text measure of the Lua code one font size larger (getTextManager is read at each call by the
-- notebook and the vanilla widgets). Synchronous only: nothing is drawn while the proxy is in place.
function V.withLargeFont(fn)
    local realGet = getTextManager
    local real = realGet()
    local proxy = {
        MeasureStringX = function(_, f, s) return real:MeasureStringX(larger(f), s) end,
        MeasureStringY = function(_, f, s) return real:MeasureStringY(larger(f), s) end,
        getFontHeight = function(_, f) return real:getFontHeight(larger(f)) end,
        getFontFromEnum = function(_, f) return real:getFontFromEnum(larger(f)) end,
    }
    getTextManager = function() return proxy end
    local ok, err = pcall(fn)
    getTextManager = realGet
    if not ok then error(err, 0) end
end

-- Runs fn with getText / getTextOrNull answering from table T (other keys: the real translator).
function V.withTable(T, fn)
    local realText, realOrNull = getText, getTextOrNull
    getText = function(key, ...)
        local s = T[key]
        if s == nil then return realText(key, ...) end
        return subst(s, ...)
    end
    getTextOrNull = function(key, ...)
        local s = T[key]
        if s == nil then return realOrNull(key, ...) end
        return subst(s, ...)
    end
    local ok, err = pcall(fn)
    getText, getTextOrNull = realText, realOrNull
    if not ok then error(err, 0) end
end

-- JSON escapes of the tables: \n, \" and \\ (each escaped character read once, left to right).
local function unescape(s)
    return (string.gsub(s, "\\(.)", function(c)
        if c == "n" then return "\n" end
        return c
    end))
end

-- Translation table of the mod for lang (flat JSON, one "key": "value" per line): table, count; nil when unreadable.
function V.readTable(lang)
    local reader = getModFileReader(V.MOD_ID, "media/lua/shared/Translate/" .. lang .. "/IG_UI.json", false)
    if not reader then return nil, 0 end
    local T, n = {}, 0
    local line = reader:readLine()
    while line do
        local k, v = string.match(line, '^%s*"([^"]+)"%s*:%s*"(.*)"%s*,?%s*$')
        if k then T[k] = unescape(v); n = n + 1 end
        line = reader:readLine()
    end
    reader:close()
    return T, n
end

-- ------------------------------------------------------------------------------------------------------- fixture

local NAMES = { "Margaret Delacroix", "Jonathan Whitaker-Brooks", "Lena", "Bartholomew Okonkwo", "Ruth", "Samuel Price",
    "Ida", "Tobias Fairweather", "Nora", "Elijah Mendez", "Christopher Abernathy", "Wes" }
local STYLES = { "Prudent", "Direct", "Reserved", "Helpful" }
local LONG = "We kept the radio on all night and heard the convoy pass twice, far to the north, without stopping near "
    .. "the river bridge where the old checkpoint still stands."
local LONG_RADIO = "Anyone on this frequency, we have water and two beds left at the church, come by daylight and keep "
    .. "your hands where we can see them."

local function relation()
    return { level = "favorable", trend = "up", group = "cautious", today = 30, suspended = false,
        agreements = { { kind = "truce", state = "applicable", scope = { group = "all_members", team = "current_members" } } },
        facts = { { fact = "gift", nature = "good", source = "personal", day = 30 },
            { fact = "theft", nature = "bad", source = "group", day = 26 },
            { fact = "delivery", nature = "good", source = "group", day = 10 } } }
end

-- Item types of the player's own inventory (the delivery window lists real items), plus a bandage.
local function ownTypes(player)
    local out, n = { ["Base.Bandage"] = true }, 0
    local inv = player and player:getInventory()
    local items = inv and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if n < 6 and item and not item:isEquipped() and not item:isFavorite() then
            out[item:getFullType()] = true
            n = n + 1
        end
    end
    return out
end

function V.fixture(Client, player)
    local contacts = {}
    for i = 1, #NAMES do
        local history = {}
        local count = (i == 1 or i == 11) and 14 or 1
        for k = 1, count do
            history[k] = { author = (k % 2 == 0) and "You" or NAMES[i], text = LONG }
        end
        contacts[i] = { id = "rsv_c" .. (i < 10 and "0" or "") .. i, name = NAMES[i], alive = i ~= 5,
            near = i == 1 or i == 11, groupName = i <= 6 and "Riverside Survivors Collective" or "",
            personality = { style = STYLES[(i - 1) % 4 + 1], courage = 3, sociability = 4, generosity = 2 },
            background = "Former paramedic from Muldraugh who still keeps the first aid kit of the old station.",
            revision = 1, history = history, note = i == 1 and "Asked for bandages twice." or "", relation = relation() }
    end
    local missions = {
        { id = "rsv_m1", npc = "rsv_c01", titleKey = "IGUI_RS_FirstAid", state = "active", revision = 3,
            remainingMs = 5400000, durationMs = 7200000, rewardType = "Base.Bullets9mm", rewardCount = 20,
            claimedName = "", engaged = true, invited = true, recovery = false, participants = { "Alice", "Bartholomew" },
            requester = NAMES[1], near = true, quantity = 10, delivered = 3, accepted = ownTypes(player) },
        { id = "rsv_m2", npc = "rsv_c02", titleKey = "IGUI_RS_FirstAid", state = "offer", revision = 1,
            remainingMs = 3600000, durationMs = 3600000, rewardType = "", rewardCount = 0, claimedName = "",
            engaged = false, invited = true, recovery = false, participants = {}, requester = NAMES[2], near = false,
            quantity = 40, delivered = 12, unit = "value",
            accepted = { ["Base.TinnedBeans"] = true, ["Base.WaterBottle"] = true, ["Base.Bandage"] = true },
            values = { ["Base.TinnedBeans"] = 4, ["Base.WaterBottle"] = 3, ["Base.Bandage"] = 2 } },
    }
    local me = player and player:getUsername() or "You"
    return { world = Client.world, run = Client.run, selected = "rsv_c01", npcProvider = true, storage = true,
        contacts = contacts, missions = missions,
        inviteTargets = { { id = "rsv_p2", name = "Alice" }, { id = "rsv_p3", name = "Bartholomew" } },
        events = { { action = "mission.success" }, { action = "mission.failed" }, { action = "trade.cheated" } },
        team = { kind = "faction", name = "Riverside Survivors Collective", role = "owner", isOwner = true,
            negotiators = 1, maxNegotiators = 2,
            members = { { id = "rsv_t1", name = me, role = "owner" }, { id = "rsv_t2", name = NAMES[2], role = "member" },
                { id = "rsv_t3", name = NAMES[3], role = "negotiator" } } } }
end

function V.radioHistory()
    local kinds = { "said", "reply", "heard", "mark", "reply" }
    local lines = {}
    for i = 1, 12 do
        lines[i] = { kind = kinds[(i - 1) % 5 + 1], text = LONG_RADIO, when = "12/07 14:" .. (10 + i), seq = i }
    end
    return { { khz = 145000, last = 200, lines = lines },
        { khz = 96600, last = 100, unread = true,
            lines = { { kind = "heard", text = "Static, then a voice counting numbers.", when = "11/07 09:02", seq = 1 } } } }
end

V.QUOTE = { mission = "rsv_m2", revision = 1, token = "rsv", count = 3, requester = NAMES[2], remaining = 25,
    unit = "value", value = 9 }

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
V.copy = copy

-- ------------------------------------------------------------------------------------------------------ audits

-- Geometry read on the Java object (ISUIElement:getX...): the Java anchors move a child when its parent is resized
-- without updating its Lua fields x, y, width, height.
local function box(e) return e:getX(), e:getY(), e:getWidth(), e:getHeight() end
local function inside(e, W, H)
    local x, y, w, h = box(e)
    return x >= -0.5 and y >= -0.5 and x + w <= W + 0.5 and y + h <= H + 0.5
end
local function rect(e)
    local x, y, w, h = box(e)
    return int(x) .. "," .. int(y) .. " " .. int(w) .. "x" .. int(h)
end
local function overlap(a, b)
    local ax, ay, aw, ah = box(a)
    local bx, by, bw, bh = box(b)
    return ax < bx + bw - 0.5 and bx < ax + aw - 0.5 and ay < by + bh - 0.5 and by < ay + ah - 0.5
end
local function bottom(e) return e:getY() + e:getHeight() end

-- Lines the greedy word wrap of the notebook needs (RS_Notebook wrap); 99 when a single word is wider than the line.
local function linesNeeded(text, maxWidth, font)
    local n, current = 0, ""
    for word in string.gmatch(tostring(text or ""), "%S+") do
        if measure(word, font) > maxWidth then return 99 end
        local candidate = current == "" and word or current .. " " .. word
        if current ~= "" and measure(candidate, font) > maxWidth then
            n = n + 1
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then n = n + 1 end
    return n
end
V.linesNeeded = linesNeeded

-- Second line of a list row, as drawn (RS_Notebook.rowSecondLine; same rule before it existed).
local function secondLine(w, row)
    if w.rowSecondLine then return w.rowSecondLine(row) end
    if row.khz then return rtr("RadioLast", row.when ~= "" and row.when or "-") end
    if row.role then return rtr("Role_" .. row.role) end
    if row.state then return rtr("State_" .. row.state) end
    return row.alive and rtr("Contact") or rtr("Dead")
end

local function nameOf(w, c)
    if c.rsTab then return "bookmark " .. c.rsTab.name end
    for k, v in pairs(w) do
        if v == c and type(k) == "string" then return k end
    end
    return tostring(c.Type or "child")
end

-- Problems of the laid out notebook window w, appended to out as "<label>: <problem>". screen: the window is shown.
function V.auditNotebook(w, label, out, screen)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local W, H, g = w:getWidth(), w:getHeight(), w.geo
    if not g then bad("window not laid out"); return out end
    if screen then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        if not inside(w, sw, sh) then bad("window " .. rect(w) .. " outside the screen " .. sw .. "x" .. sh) end
    end
    local th = w:titleBarHeight()
    if w.title and measure(w.title) > W - 2 * (th + 4) then bad("window title cut: " .. w.title) end
    -- Every visible child inside the window; texts of buttons and bookmarks inside their button.
    for _, c in pairs(w.children or {}) do
        if c:isVisible() then
            if not inside(c, W, H) then
                bad(nameOf(w, c) .. " " .. rect(c) .. " outside the window " .. int(W) .. "x" .. int(H))
            end
            if c.rsTab then
                if c.rsOver + 8 + measure(c.rsLabel) > c:getWidth() + 0.5 then bad("bookmark label cut: " .. c.rsLabel) end
                if hasKey(c.rsLabel) then bad("raw key on a bookmark: " .. c.rsLabel) end
            elseif type(c.title) == "string" and c.title ~= "" and c.onclick then
                local tw = measure(c.title, c.font)
                if tw > c:getWidth() - 4 then
                    bad("text wider than its button: '" .. c.title .. "' " .. int(tw) .. " px in " .. int(c:getWidth()) .. " px")
                end
                if hasKey(c.title) then bad("raw key on a button: " .. c.title) end
            end
        end
    end
    -- Notebook controls: above the resize strip, never on top of each other.
    local controls = {}
    for _, c in ipairs({ w.list, w.detail, w.tune, w.say, w.sendRadio, w.speak, w.speakSend, w.note, w.inviteChoice }) do
        if c and c:isVisible() then controls[#controls + 1] = c end
    end
    for _, c in ipairs(w.actions or {}) do if c:isVisible() then controls[#controls + 1] = c end end
    local strip = H - w:resizeWidgetHeight()
    for i, a in ipairs(controls) do
        if a ~= w.list and a ~= w.detail and bottom(a) > strip + 0.5 then
            bad(nameOf(w, a) .. " " .. rect(a) .. " under the resize strip (y > " .. int(strip) .. ")")
        end
        for j = i + 1, #controls do
            local b = controls[j]
            if overlap(a, b) then bad(nameOf(w, a) .. " " .. rect(a) .. " on top of " .. nameOf(w, b) .. " " .. rect(b)) end
        end
    end
    -- Fixed labels drawn by the notebook (drawPaper, drawRow).
    if g.showList then
        local header = w.tab == "Radio" and rtr("RadioHeardList") or rtr(w.tab)
        if measure(header) > g.colW then bad("list header cut: " .. header) end
        local footer = rtr("Target", rtr("None"))
        if measure(footer) > g.colW then bad("target footer cut: " .. footer) end
        for _, item in ipairs(w.list.items or {}) do
            local s = secondLine(w, item.item)
            if measure(s) > w.list:getWidth() - 20 then bad("second line of a row cut: " .. s) end
            if hasKey(s) or hasKey(item.text) then bad("raw key in the list: " .. tostring(item.text) .. " / " .. s) end
        end
    elseif measure(rtr("Reputation"), UIFont.Large) > g.rightW then
        bad("page title cut: " .. rtr("Reputation"))
    end
    -- Status above the Say line: at most two lines (the second one is cut with an ellipsis).
    if w.tab == "Contacts" and w.speak and w.speak:isVisible() then w:syncTalk() end
    if w.tab == "Radio" and w.say and w.say:isVisible() then w:syncSay() end
    local status = (w.tab == "Contacts" and w.talkStatus) or (w.tab == "Radio" and w.sayStatus) or nil
    if status then
        if linesNeeded(status, g.rightW) > 2 then bad("status cut (more than two lines): " .. status) end
        if hasKey(status) then bad("raw key in the status: " .. status) end
    end
    -- Page text: lines inside the page, dark ink, no raw key.
    local d = w.detail
    if d and d:isVisible() then
        local text = d.text or ""
        if hasKey(text) then bad("raw translation key in the page text") end
        if string.sub(text, 1, 5) ~= "<RGB:" then bad("page text does not start with a colour tag") end
        local scroll = d:getYScroll()
        d:paginate()
        if d.setYScroll then d:setYScroll(scroll) end
        local maxW = d.width - (d.marginLeft or 0) - (d.marginRight or 0)
        local font = d.defaultFont
        for i, s in ipairs(d.lines or {}) do
            if d.fonts and d.fonts[i] then font = d.fonts[i] end
            local x = d.lineX and d.lineX[i] or 0
            if x + measure(s, font) > maxW + 1 then bad("page line wider than the page: '" .. s .. "'") end
        end
        local lines, light = 0, 0
        for _, c in pairs(d.rgb or {}) do
            lines = lines + 1
            if c.r + c.g + c.b >= V.DARK then light = light + 1 end
        end
        if lines == 0 then bad("page without ink colour")
        elseif light > 0 then bad(light .. " light (white or grey) line(s) on the page") end
    end
    return out
end

-- The controls follow the window size: page text up to the right margin, bookmarks on the right edge, the last row of
-- controls on the bottom margin.
function V.auditFollow(w, label, out)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local g = w.geo
    local d = w.detail
    local right = d:getX() + d:getWidth()
    if math.abs(right - (g.paperRight - 18)) > 1 then
        bad("page text does not reach the right margin (" .. int(right) .. " vs " .. int(g.paperRight - 18) .. ")")
    end
    for _, tab in ipairs(w.tabs or {}) do
        if math.abs(tab:getX() + tab:getWidth() - w:getWidth()) > 1 then
            bad("bookmark " .. tab.rsTab.name .. " not on the right edge")
        end
    end
    local lowest = 0
    for _, c in ipairs({ w.speak, w.speakSend, w.note, w.inviteChoice, w.say, w.sendRadio }) do
        if c and c:isVisible() then lowest = math.max(lowest, bottom(c)) end
    end
    for _, c in ipairs(w.actions or {}) do if c:isVisible() then lowest = math.max(lowest, bottom(c)) end end
    if lowest > 0 and math.abs(lowest - g.bottom) > 2 then
        bad("bottom controls do not follow the window (" .. int(lowest) .. " vs bottom margin " .. int(g.bottom) .. ")")
    end
    return out
end

function V.auditDelivery(dw, label, out, screen)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local W, H = dw:getWidth(), dw:getHeight()
    if screen then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        if not inside(dw, sw, sh) then bad("delivery window " .. rect(dw) .. " outside the screen") end
    end
    local th = dw:titleBarHeight()
    if measure(dw.title) > W - 2 * (th + 4) then bad("delivery title cut: " .. tostring(dw.title)) end
    if hasKey(dw.title) then bad("raw key in the delivery title") end
    for _, c in pairs(dw.children or {}) do
        if c:isVisible() then
            if not inside(c, W, H) then bad(nameOf(dw, c) .. " " .. rect(c) .. " outside the delivery window") end
            if type(c.title) == "string" and c.title ~= "" and c.onclick then
                if measure(c.title, c.font) > c:getWidth() - 4 then bad("text wider than its button: " .. c.title) end
                if hasKey(c.title) then bad("raw key on a button: " .. c.title) end
            end
        end
    end
    -- Rows as drawn (doDrawItem, drawText recorded on the list instance), each one chosen and not chosen: inside the
    -- row left of the vanilla scroll bar (rows cut at vscroll.x + 3), a name cut with an ellipsis (E03-T07).
    local list = dw.items
    if list and list.doDrawItem then
        local right = list:getWidth() - 13
        local drawn
        list.drawText = function(_, s, x) drawn[#drawn + 1] = { s = tostring(s), x = x or 0 } end
        local ok, err = pcall(function()
            for _, item in ipairs(list.items or {}) do
                for _, chosen in ipairs({ false, true }) do
                    dw.chosen[item.item.id] = chosen or nil
                    drawn = {}
                    list:doDrawItem(0, item, false)
                    for _, d in ipairs(drawn) do
                        if d.x + measure(d.s) > right + 0.5 then
                            bad("item row wider than the list: '" .. d.s .. "' " .. int(d.x + measure(d.s)) .. " px > "
                                .. int(right) .. " px")
                        end
                    end
                    local full = tostring(item.text)
                    local s = drawn[1] and drawn[1].s or ""
                    if not string.find(s, full, 1, true) and string.sub(s, -3) ~= "..." then
                        bad("item name cut without an ellipsis: '" .. s .. "'")
                    end
                end
                dw.chosen[item.item.id] = nil
            end
        end)
        list.drawText = nil
        if not ok then bad("item rows not drawn: " .. tostring(err)) end
    end
    return out
end

-- E03-T07: the delivery window opened over the notebook w (its centre inside the notebook), never on the sidebar.
function V.auditDeliveryPlace(dw, w, label, out)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local x, y, ww, hh = box(dw)
    local cx, cy = x + ww / 2, y + hh / 2
    local nx, ny, nw, nh = box(w)
    if cx < nx or cx > nx + nw or cy < ny or cy > ny + nh then
        bad("delivery window " .. rect(dw) .. " not over the notebook " .. rect(w))
    end
    local bar = ISEquippedItem and ISEquippedItem.instance
    if bar and bar:isVisible() and overlap(dw, bar) then
        bad("delivery window " .. rect(dw) .. " on the sidebar " .. rect(bar))
    end
    return out
end

-- E03-T07: delivery windows created over a notebook pushed past every corner of the screen stay whole on the screen.
function V.auditDeliveryCorners(Notebook, mission, label, out)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local corners = { { -400, -300 }, { sw - 120, -300 }, { -400, sh - 40 }, { sw - 120, sh - 40 } }
    for _, c in ipairs(corners) do
        local anchor = { getX = function() return c[1] end, getY = function() return c[2] end,
            getWidth = function() return 900 end, getHeight = function() return 650 end }
        local dw = Notebook.newDelivery(mission, anchor)
        if not inside(dw, sw, sh) then
            out[#out + 1] = label .. ": delivery window " .. rect(dw) .. " of a notebook at " .. c[1] .. "," .. c[2]
                .. " outside the screen " .. sw .. "x" .. sh
        end
    end
    return out
end

function V.auditModal(m, label, out)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if not inside(m, sw, sh) then bad("dialog " .. rect(m) .. " outside the screen " .. sw .. "x" .. sh) end
    local text = tostring(m.text or "")
    if hasKey(text) then bad("raw key in the dialog: " .. text) end
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        if measure(line) > m:getWidth() - 10 + 0.5 then bad("dialog line wider than the dialog: " .. line) end
    end
    for _, b in ipairs({ m.yes, m.no, m.ok }) do
        if b then
            if not inside(b, m:getWidth(), m:getHeight()) then bad("dialog button " .. rect(b) .. " outside the dialog") end
            if measure(b.title, b.font) > b:getWidth() - 4 then bad("text wider than its button: " .. tostring(b.title)) end
        end
    end
    return out
end

-- ----------------------------------------------------------------------------------------------- notebook driving

function V.showPage(w, page)
    w:changeTab(page.tab)
    if page.id ~= nil then
        w.selectedId = page.id
        w:refresh()
    end
    w:layout()
end

-- Notebook laid out off screen (never added to the UI manager, never drawn) at its minimum size. The size is set
-- before its children exist: an off-screen window gets no Java update, which moves the anchored vanilla children
-- (resize strip, title buttons) when the size changes later.
function V.offscreen(Notebook)
    local w = Notebook:new()
    w.width, w.height = w.minimumWidth, w.minimumHeight
    w:initialise()
    w:instantiate()
    w:layout()
    return w
end

-- Width of the places of the notebook strings, from an off-screen notebook at its minimum size.
local function containers(w)
    V.showPage(w, V.PAGES[2])
    local g = w.geo
    local d = w.detail
    local sw = getCore():getScreenWidth()
    local c = { rightW = g.rightW, colW = g.colW, minW = w.width, th = w:titleBarHeight(), screenW = sw,
        detailW = d.width - (d.marginLeft or 0) - (d.marginRight or 0), deliveryW = math.min(560, sw - 60),
        speakW = w.speak:isVisible() and w.speak.width or g.rightW, sendW = math.floor(g.rightW / 3) }
    V.showPage(w, V.PAGES[1])
    c.sayW, c.colW = w.say.width, math.min(c.colW, w.geo.colW)
    return c
end

local BUTTONS = { SaveNote = true, Talk = true, ClearTarget = true, Accept = true, Deliver = true, Claim = true,
    Abandon = true, Invite = true, MandateGrant = true, MandateRevoke = true }
local HEADERS = { Radio = true, Contacts = true, Missions = true, Team = true, RadioHeardList = true }
local SECOND = { Contact = true, Dead = true, RadioLast = true }
local STATUS = { TalkSelectFirst = true, TalkOutOfRange = true, TalkWaiting = true, TalkDead = true,
    RadioTunedElsewhere = true, Error_Cooldown = true }
-- Radio status of the Say line (RS_Notebook syncSay: Talk.busyReason, Talk.problem in RS_RadioTalk.lua).
local RADIO_STATUS = { NotEquipped = true, NotTwoWay = true, Off = true, MicMuted = true, Reject_Disabled = true,
    Reject_NoRadio = true, Reject_TooFar = true, Reject_NotInVehicle = true, Reject_Waiting = true, Reject_Spam = true }
local DIALOGS = { ConfirmAccept = true, ConfirmAbandon = true, ConfirmDelivery = true, ConfirmSupply = true }

-- Place of a notebook string: kind ("line": one line, "lines2": two wrapped lines, "dialog": each line of a
-- dialog, "words": wrapped page text, its longest word), width, font. nil: not a notebook string.
local function place(key, c)
    if key == "IGUI_RadioSurvivor_Send" then return "line", c.sendW - 4 end
    if key == "IGUI_RadioSurvivor_Talk" then return "line", c.sayW - 8 end
    local r = string.match(key, "^IGUI_RadioSurvivor_(.+)$")
    if r and RADIO_STATUS[r] then return "lines2", c.rightW end
    local k = string.match(key, "^IGUI_RS_(.+)$")
    if not k then return nil end
    if BUTTONS[k] then return "line", c.rightW - 4 end
    if k == "TalkSend" then return "line", c.sendW - 4 end
    if k == "RadioTune" then return "line", c.colW - 4 end
    if k == "ReviewDelivery" then return "line", c.deliveryW - 36 end
    if k == "Notebook" then return "line", c.minW - 2 * (c.th + 4) end
    if k == "Delivery" then return "line", c.deliveryW - 2 * (c.th + 4) end
    if k == "Reputation" or k == "RadioFrequency" then return "line", c.rightW, UIFont.Large end
    if HEADERS[k] or k == "Target" then return "line", c.colW end
    if SECOND[k] or string.match(k, "^Role_") or string.match(k, "^StateShort_") then return "line", c.colW - 20 end
    if STATUS[k] then return "lines2", c.rightW end
    -- A dialog line is never cut (ISModalDialog.CalcSize): it must fit the smallest target screen, 1280 px.
    if DIALOGS[k] then return "dialog", math.min(c.screenW, 1280) - 10 end
    if k == "TalkPlaceholder" then return "line", c.speakW - 8 end
    if string.match(k, "^Radio_") or k == "Empty_Radio" then return "words", c.detailW, UIFont.Medium end
    return "words", c.detailW
end

local function sample(key, T)
    if key == "IGUI_RS_RadioLast" then return { "00/00 00:00" } end
    if key == "IGUI_RS_RadioFrequency" or key == "IGUI_RadioSurvivor_Talk" then return { "999.9" } end
    if key == "IGUI_RS_RadioTunedElsewhere" then return { "999.9", "999.9" } end
    if key == "IGUI_RS_Target" then return { T["IGUI_RS_None"] or "None" } end
    return { "Abcdefgh", "Abcdefgh", "Abcdefgh", "Abcdefgh", "Abcdefgh", "Abcdefgh" }
end

-- Every notebook string of T measured against its place; returns the count of strings measured.
function V.auditStrings(T, c, label, out)
    local function bad(what) out[#out + 1] = label .. ": " .. what end
    local keys = {}
    for key in pairs(T) do keys[#keys + 1] = key end
    table.sort(keys)
    local measured = 0
    for _, key in ipairs(keys) do
        local kind, width, font = place(key, c)
        if kind then
            measured = measured + 1
            local text = subst(T[key], unpack(sample(key, T)))
            if kind == "line" then
                local tw = measure(text, font)
                if tw > width then bad(key .. " " .. int(tw) .. " px > " .. int(width) .. " px: " .. text) end
            elseif kind == "lines2" then
                local n = linesNeeded(text, width, font)
                if n > 2 then bad(key .. " needs " .. n .. " lines of " .. int(width) .. " px (2 shown): " .. text) end
            elseif kind == "dialog" then
                for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
                    local tw = measure(line, font)
                    if tw > width then bad(key .. " dialog line " .. int(tw) .. " px > screen " .. int(width) .. " px") end
                end
            else
                for word in string.gmatch(text, "%S+") do
                    local tw = measure(word, font)
                    if tw > width then
                        bad(key .. " word '" .. word .. "' " .. int(tw) .. " px > page " .. int(width) .. " px")
                    end
                end
            end
        end
    end
    return measured
end

-- One language and font: off-screen notebook at its minimum size, every page, the delivery window, the four
-- confirmations and every string. Returns the count of strings measured.
function V.auditLanguage(Notebook, Client, T, label, out)
    local w = V.offscreen(Notebook)
    for _, page in ipairs(V.PAGES) do
        V.showPage(w, page)
        V.auditNotebook(w, label .. " " .. page.name, out, false)
    end
    local dw = Notebook.newDelivery(Client.snapshot.missions[1])
    dw:instantiate()
    V.auditDelivery(dw, label .. " delivery", out, false)
    local q = V.QUOTE
    local texts = { ConfirmAccept = rtr("ConfirmAccept"), ConfirmAbandon = rtr("ConfirmAbandon"),
        ConfirmDelivery = rtr("ConfirmDelivery", q.count, q.requester, q.remaining),
        ConfirmSupply = rtr("ConfirmSupply", q.count, q.requester, q.remaining, q.value) }
    for name, text in pairs(texts) do
        V.auditModal(Notebook.newConfirm(text, function() end), label .. " " .. name, out)
    end
    return V.auditStrings(T, containers(w), label .. " string", out)
end

-- ---------------------------------------------------------------------------------------------- display modes

local function modes()
    local out = {}
    local ok, list = pcall(function() return getCore():getScreenModes() end)
    if not ok or list == nil then return out end
    for _, s in ipairs(list) do
        local w, h = string.match(tostring(s), "(%d+)%s*x%s*(%d+)")
        if w then out[#out + 1] = { tonumber(w), tonumber(h) } end
    end
    return out
end

-- 1280x720, then 1920x1080 when a mode at least as large exists, else the largest mode above 1280x720.
function V.resolutions()
    local out = { { 1280, 720 } }
    local best, full = nil, false
    for _, m in ipairs(modes()) do
        if m[1] >= 1920 and m[2] >= 1080 then full = true end
        if m[1] <= 1920 and m[2] <= 1080 and (best == nil or m[1] * m[2] > best[1] * best[2]) then best = m end
    end
    if full then best = { 1920, 1080 } end
    if best and best[1] * best[2] > 1280 * 720 then out[2] = best end
    return out
end

function V.displayMode()
    local core = getCore()
    return { w = core:getScreenWidth(), h = core:getScreenHeight(), full = core:isFullScreen(),
        borderless = core:getOptionBorderlessWindow() }
end

function V.setWindowed(w, h)
    local core = getCore()
    core:setOptionBorderlessWindow(false)
    core:setResolutionAndFullScreen(w, h, false)
    return core:getScreenWidth(), core:getScreenHeight()
end

function V.restoreDisplay(mode)
    local core = getCore()
    core:setOptionBorderlessWindow(mode.borderless)
    core:setResolutionAndFullScreen(mode.w, mode.h, mode.full)
    return core:getScreenWidth() == mode.w and core:getScreenHeight() == mode.h
end

function V.captureName(view)
    local core = getCore()
    return "rs_notebook_" .. view .. "_" .. core:getScreenWidth() .. "x" .. core:getScreenHeight() .. "_fs"
        .. core:getOptionFontSizeReal() .. ".png"
end

-- ------------------------------------------------------------------------------------------------ test context

-- Fixed snapshot and history in the real client; server snapshots and history answers ignored until the cleanup.
local function install(t)
    if type(isServer) == "function" and isServer() then t:skip("client UI (not on a server)") end
    local Notebook = require "RadioSurvivor/RS_Notebook"
    local Client = RS_CarnetClient
    t:ok(Notebook ~= nil and Client ~= nil, "notebook client not loaded")
    local History = require "RadioSurvivor/RS_RadioHistory"
    local MapActions = require "RadioSurvivor/RS_MapActions"
    local Const = require "RadioSurvivor/RadioSurvivor_Const"
    local player = getSpecificPlayer(0)
    local ctx = { Notebook = Notebook, Client = Client, History = History, MapActions = MapActions, out = {},
        captures = {}, player = player }
    local saved = { snapshot = Client.snapshot, receive = Client.receive, window = Client.window,
        open = Client.window ~= nil and Client.window:isVisible(), delivery = Client.deliveryWindow,
        frequencies = History.frequencies, unread = History.unread, hreceive = History.receive,
        hrequest = History.request }
    ctx.saved = saved
    ctx.fixture = V.fixture(Client, player)
    Client.snapshot = copy(ctx.fixture)
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
    History.frequencies, History.unread = V.radioHistory(), false
    -- E03-T07: a bandage with a very long name in the inventory (the delivery window lists it, cut in its row).
    local inv = player and player:getInventory()
    local long = inv and instanceItem("Base.Bandage")
    if long then
        long:setName(V.LONG_ITEM)
        inv:AddItem(long)
        t:defer(function() inv:Remove(long) end, "long named test item removed from the inventory")
    end
    if saved.window then saved.window:close() end
    Client.window, Client.deliveryWindow = nil, nil
    t:defer(function()
        for _, e in ipairs(ctx.dialogs or {}) do e:setVisible(false); e:removeFromUIManager() end
        if Client.deliveryWindow then Client.deliveryWindow:setVisible(false); Client.deliveryWindow:removeFromUIManager() end
        if Client.window and Client.window ~= saved.window then
            Client.window:releaseFocus()
            Client.window:setVisible(false)
            Client.window:removeFromUIManager()
        end
        Client.receive, History.receive, History.request = saved.receive, saved.hreceive, saved.hrequest
        Client.snapshot, Client.window, Client.deliveryWindow = saved.snapshot, saved.window, saved.delivery
        History.frequencies, History.unread = saved.frequencies, saved.unread
        if saved.window and saved.open then
            saved.window:setVisible(true)
            saved.window:refresh()
        end
        Client.send("snapshot")
        History.request()
    end, "notebook, snapshot and radio history restored")
    return ctx
end

-- A fresh notebook opened like the sidebar button does (Notebook.toggle creates it when there is none).
local function freshWindow(ctx)
    local Client = ctx.Client
    if Client.window then
        Client.window:releaseFocus()
        Client.window:setVisible(false)
        Client.window:removeFromUIManager()
        Client.window = nil
    end
    ctx.Notebook.toggle()
    return Client.window
end

local function dialog(ctx, e)
    ctx.dialogs = ctx.dialogs or {}
    ctx.dialogs[#ctx.dialogs + 1] = e
    return e
end

local function drop(e)
    if e then
        e:setVisible(false)
        e:removeFromUIManager()
    end
end

local function capture(t, ctx, view, before)
    local name = V.captureName(view)
    local ok, err = pcall(takeScreenshot, name)
    if not ok then ctx.out[#ctx.out + 1] = view .. ": screenshot failed: " .. tostring(err) end
    ctx.captures[#ctx.captures + 1] = name
    local found = #ctx.out - before
    t:note(view .. ": " .. (found == 0 and "ok" or (found .. " problem(s)")) .. ", " .. name)
end

local function report(t, ctx)
    local shown = 0
    for _, line in ipairs(ctx.out) do
        if shown < V.MAX_NOTES then t:note(line) end
        shown = shown + 1
    end
    if shown > V.MAX_NOTES then t:note("... " .. (shown - V.MAX_NOTES) .. " more problem(s)") end
end

-- Chain of steps: each step(t, nextStep) registers its own wait; finish(t) last.
local function chain(t, steps, i, finish)
    if i > #steps then return finish(t) end
    return steps[i](t, function(t2) return chain(t2, steps, i + 1, finish) end)
end

-- Steps showing one view (setup), waiting for it on screen, auditing it and taking its screenshot.
local function viewStep(ctx, view, setup, audit, teardown)
    return function(t, nextStep)
        local before = #ctx.out
        local subject = setup()
        t:sleep(V.SHOW_MS, function(t2)
            audit(subject, view .. " " .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight())
            capture(t2, ctx, view, before)
            t2:sleep(V.AFTER_MS, function(t3)
                if teardown then teardown(subject) end
                return nextStep(t3)
            end)
        end)
    end
end

local function resolutionSteps(ctx, res)
    local steps = {}
    local Client = ctx.Client
    steps[#steps + 1] = function(t, nextStep)
        local w, h = V.setWindowed(res[1], res[2])
        if w ~= res[1] or h ~= res[2] then t:note("asked " .. res[1] .. "x" .. res[2] .. ", got " .. w .. "x" .. h) end
        t:sleep(800, function(t2)
            ctx.w = freshWindow(ctx)
            return t2:sleep(V.AFTER_MS, nextStep)
        end)
    end
    for _, page in ipairs(V.PAGES) do
        steps[#steps + 1] = viewStep(ctx, page.name,
            function() V.showPage(ctx.w, page); return ctx.w end,
            function(w, label) V.auditNotebook(w, label, ctx.out, true) end)
    end
    steps[#steps + 1] = viewStep(ctx, "delivery",
        function() return ctx.w:openDelivery(Client.snapshot.missions[1]) end,
        function(dw, label)
            V.auditDelivery(dw, label, ctx.out, true)
            V.auditDeliveryPlace(dw, ctx.w, label, ctx.out)
            V.auditDeliveryCorners(ctx.Notebook, Client.snapshot.missions[1], label, ctx.out)
        end,
        function(dw) drop(dw); Client.deliveryWindow = nil end)
    steps[#steps + 1] = viewStep(ctx, "confirm",
        function()
            V.showPage(ctx.w, V.PAGES[3])
            return dialog(ctx, ctx.w:confirm(getText("IGUI_RS_ConfirmAbandon"), function() end))
        end,
        function(m, label) V.auditModal(m, label, ctx.out) end, drop)
    steps[#steps + 1] = viewStep(ctx, "quote",
        function() return dialog(ctx, Client.confirmQuote(V.QUOTE)) end,
        function(m, label) V.auditModal(m, label, ctx.out) end, drop)
    steps[#steps + 1] = viewStep(ctx, "contacts_min",
        function()
            local w = ctx.w
            w:setWidth(w.minimumWidth); w:setHeight(w.minimumHeight)
            V.showPage(w, V.PAGES[2])
            return w
        end,
        function(w, label)
            V.auditNotebook(w, label .. " min", ctx.out, true)
            V.auditFollow(w, label .. " min", ctx.out)
        end)
    steps[#steps + 1] = viewStep(ctx, "contacts_large",
        function()
            local w = ctx.w
            local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
            w:setX(20); w:setY(20); w:setWidth(sw - 40); w:setHeight(sh - 40)
            V.showPage(w, V.PAGES[2])
            return w
        end,
        function(w, label)
            V.auditNotebook(w, label .. " large", ctx.out, true)
            V.auditFollow(w, label .. " large", ctx.out)
        end)
    return steps
end

-- ----------------------------------------------------------------------------------------------------- suite

RST.suite("rs.notebook.visual", { tags = { "client", "ui" }, testTimeoutMs = 120000, timeoutMs = 400000 }, function(s)
    s.test("translation tables: every notebook string fits its place (EN, FR, current and larger font)", function(t)
        local ctx = install(t)
        local total = 0
        for _, lang in ipairs(V.LANGS) do
            local T, n = V.readTable(lang)
            t:ok(T ~= nil and n > 0, "translation table " .. lang .. " unreadable")
            for _, large in ipairs({ false, true }) do
                local label = lang .. (large and " larger font" or " current font")
                local before = #ctx.out
                local measured = 0
                local function run()
                    V.withTable(T, function() measured = V.auditLanguage(ctx.Notebook, ctx.Client, T, label, ctx.out) end)
                end
                if large then V.withLargeFont(run) else run() end
                total = total + measured
                t:note(label .. ": " .. n .. " keys, " .. measured .. " notebook strings measured, "
                    .. (#ctx.out - before) .. " problem(s)")
            end
        end
        t:note("larger font: Small measured as Medium, Medium as Large (font size option: restart needed in game)")
        report(t, ctx)
        t:ok(total > 0, "no string measured")
        t:eq(0, #ctx.out, "layout problems with the translation tables (see the notes)")
    end)

    s.test("views at 1280x720 and the largest screen: pages, delivery, confirmations, min and large size", function(t)
        local ctx = install(t)
        local mode = V.displayMode()
        t:defer(function(t2)
            local ok = V.restoreDisplay(mode)
            t2:note("display restored to " .. mode.w .. "x" .. mode.h .. (mode.full and " full screen" or "")
                .. (mode.borderless and " borderless" or "") .. (ok and "" or " (size differs, check the options)"))
        end, "display mode restored")
        local steps = {}
        for _, res in ipairs(V.resolutions()) do
            for _, step in ipairs(resolutionSteps(ctx, res)) do steps[#steps + 1] = step end
        end
        chain(t, steps, 1, function(t2)
            t2:note(#ctx.captures .. " screenshot(s) in Zomboid/Screenshots")
            report(t2, ctx)
            t2:eq(0, #ctx.out, "layout problems on screen (see the notes)")
        end)
    end)

    s.test("scroll, refresh, collapse, close, sidebar button and shortcut", function(t)
        local ctx = install(t)
        local Client, out = ctx.Client, ctx.out
        local function bad(what) out[#out + 1] = what end
        local sidebar = ISEquippedItem and ISEquippedItem.instance and ISEquippedItem.instance.rsCarnet
        local function click()
            if sidebar then return sidebar.onclick(sidebar.target, sidebar) end
            return ctx.Notebook.toggle()
        end
        if sidebar then
            local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
            local x, y = sidebar:getAbsoluteX(), sidebar:getAbsoluteY()
            if x < 0 or y < 0 or x + sidebar.width > sw or y + sidebar.height > sh then
                bad("sidebar button outside the screen")
            end
            if measure(sidebar.title) > sidebar.width - 4 then bad("sidebar button text cut: " .. sidebar.title) end
        else
            t:note("no sidebar button (ISEquippedItem.instance): opened by Notebook.toggle, its action")
        end
        click()
        local w = Client.window
        t:ok(w ~= nil and w:isVisible(), "the sidebar button did not open the notebook")
        local d, list = w.detail, w.list
        V.showPage(w, V.PAGES[2])
        t:sleep(V.SHOW_MS, function(t2)
            -- Scroll: the page and the list move and come back.
            if d:getScrollHeight() <= d.height + 60 then bad("contact page too short to scroll") end
            d:setYScroll(-60)
            list:setYScroll(-list.itemheight)
            t2:sleep(V.SHOW_MS, function(t3)
                if d:getYScroll() ~= -60 then bad("page did not scroll: " .. tostring(d:getYScroll())) end
                if list:getYScroll() ~= -list.itemheight then bad("list did not scroll: " .. tostring(list:getYScroll())) end
                local bar = w:scrollBar(d)
                if not bar or bar.thumbY <= d.y then bad("page scroll bar thumb did not move") end
                capture(t3, ctx, "scrolled", #out)
                d:setYScroll(0); list:setYScroll(0)
                t3:sleep(V.AFTER_MS, function(t4)
                    if d:getYScroll() ~= 0 or list:getYScroll() ~= 0 then bad("scroll did not come back to the top") end
                    -- Refresh: contact 11 selected near the bottom of the list, page scrolled, then a forced snapshot.
                    w.selectedId = "rsv_c11"
                    w:refresh()
                    t4:sleep(V.AFTER_MS, function(t5)
                        list:setYScroll(-(list:getScrollHeight() - list.height))
                        d:setYScroll(-40)
                        t5:sleep(V.SHOW_MS, function(t6)
                            local before = { id = w.selectedId, index = list.selected, list = list:getYScroll(),
                                page = d:getYScroll() }
                            local snap = copy(ctx.fixture)
                            table.insert(snap.contacts[11].history, { author = "You", text = "One more line." })
                            snap.contacts[3].name = "Lena Moreau"
                            local zones = ctx.MapActions.zones
                            ctx.MapActions.zones = function() return nil, "test" end
                            local ok, err = pcall(ctx.saved.receive, "snapshot", snap)
                            ctx.MapActions.zones = zones
                            if not ok then bad("forced snapshot raised: " .. tostring(err)) end
                            t6:sleep(V.SHOW_MS, function(t7)
                                local after = { id = w.selectedId, index = list.selected, list = list:getYScroll(),
                                    page = d:getYScroll() }
                                for _, k in ipairs({ "id", "index", "list", "page" }) do
                                    if before[k] ~= after[k] then
                                        bad("refresh moved " .. k .. ": " .. tostring(before[k]) .. " -> " .. tostring(after[k]))
                                    end
                                end
                                if not (w.row and w.row.id == "rsv_c11") then bad("refresh lost the selected contact") end
                                t7:note("refresh: selection " .. tostring(after.id) .. " row " .. tostring(after.index)
                                    .. ", list scroll " .. tostring(after.list) .. ", page scroll " .. tostring(after.page))
                                -- Collapse: Radio page with the Say line focused, then the title bar only.
                                V.showPage(w, V.PAGES[1])
                                w.say:focus()
                                -- Class functions: the field pin = true of ISCollapsableWindow:new hides the method
                                -- pin on the instance (the vanilla pin button calls ISCollapsableWindow.pin too).
                                ISCollapsableWindow.collapse(w)
                                w.isCollapsed = true
                                w:setMaxDrawHeight(w:titleBarHeight())
                                w:update()
                                if w.say:isFocused() then bad("collapsed notebook kept the keyboard") end
                                if w:viewingRadio() then bad("collapsed notebook still reads the Radio page") end
                                t7:sleep(V.SHOW_MS, function(t8)
                                    capture(t8, ctx, "collapsed", #out)
                                    w.isCollapsed = false
                                    w:clearMaxDrawHeight()
                                    ISCollapsableWindow.pin(w)
                                    t8:sleep(V.SHOW_MS, function(t9)
                                        if not w:viewingRadio() then bad("expanded notebook does not read the Radio page") end
                                        V.auditNotebook(w, "expanded again", out, true)
                                        -- Close: focus released, then the sidebar button opens and closes it.
                                        V.showPage(w, V.PAGES[2])
                                        w.speak:focus()
                                        w:close()
                                        if w:isVisible() then bad("close left the notebook visible") end
                                        if w.speak:isFocused() then bad("closed notebook kept the keyboard") end
                                        click()
                                        if Client.window ~= w or not w:isVisible() then
                                            bad("sidebar button did not reopen the same notebook")
                                        end
                                        click()
                                        if w:isVisible() then bad("sidebar button did not close the notebook") end
                                        click()
                                        -- Shortcut: the function of the key binding, commands captured (nothing sent).
                                        local key = getCore():getKey("RadioSurvivorSelect")
                                        if not key or key == 0 then bad("shortcut RadioSurvivorSelect not bound") end
                                        local sent, send = {}, Client.send
                                        Client.send = function(command) sent[#sent + 1] = command end
                                        local okKey, errKey = pcall(Client.selectNearest)
                                        Client.send = send
                                        if not okKey then bad("shortcut function raised: " .. tostring(errKey)) end
                                        if sent[1] ~= "select" and sent[1] ~= "deselect" then
                                            bad("shortcut sent " .. tostring(sent[1]) .. " instead of select or deselect")
                                        end
                                        t9:note("shortcut key " .. tostring(key) .. " (Ctrl): " .. tostring(sent[1]))
                                        report(t9, ctx)
                                        t9:eq(0, #out, "scroll, refresh, collapse, close or shortcut problems (see the notes)")
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
