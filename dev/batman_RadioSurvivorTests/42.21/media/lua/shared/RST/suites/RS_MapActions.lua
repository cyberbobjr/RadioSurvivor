--[[
rs.actions.map - action mark_map of the radio voices (E07-T04): a place of the voice sheet marked on the map of the
caller. Solo: the executor (server/RadioSurvivor/RS_MapMarks.lua) and the map of the player
(client/RadioSurvivor/RS_MapActions.lua) live in the same Lua state. Dedicated server (E01-T19, tags "world" and
"server", campaign mp): the server decides and executes, and the REQUESTER client (the caller) checks its own map and
radio history through RST.Steps (RST_ViewSteps.lua: map.symbols, map.known, radio.history; the symbols and blocks of
the test are removed there by the same steps); the notebook character of the caller is bound when missing
("hello", RST.RSHelpers.character). On an MP client the suites are skipped. The manual before/after-reload steps stay
solo only.

rs.actions.map (tag "world": solo save named rstest*)
    - a test sheet read by the real parser (RS_Persona.parseLines) with one place= line, a few squares from the
      player; RS_Actions.decide accepts mark_map for that place (reason ok): the map of the player gets the vanilla
      icon (RS_MapActions.ICON) and the label at the centre of the square, once;
    - a second mark of the same place adds nothing (RS_MapActions.mark gives "present"); a second decision within
      the delay of the voice is refused "cooldown";
    - an id that is not a place of the sheet is refused "bad_params", a sheet without mark_map "not_allowed": no
      symbol added;
    - the accepted mark is noted in the radio history of the caller (E07-T08, no floating text): one line of kind
      "mark" with the label only, on the frequency of the answer (TEST_KHZ) and not on another one, in the private
      state of the server (RS_RadioLog) and in the copy of the client (RS_RadioHistory), with a translated notebook
      line (IGUI_RS_Radio_mark). Skipped when no notebook character is bound to the player (open the notebook once).
    Cleanup: the symbols of the test are removed from the map, the action counters of the test voice (unique id
    per run) are removed from the private state, the radio history of the character is restored as it was before
    the test (then sent again to the client). The decisions stay in the admin action log (voice rstest_map_*).

rs.actions.map.before / rs.actions.map.after-reload (tags "world" and "manual": run by their exact name only)
    Persistence of a mark across a reload, as for the vanilla annotations of the player (map_symbols.bin of the save,
    written when the game saves, read when the world loads):
    1. RST.run({ suite = "rs.actions.map.before" }): marks the place PERSIST (label "RST persist") through the real
       executor and writes Zomboid/Lua/batman_RadioSurvivor/rstest_map_mark.txt (the identity of the MapItem of
       this session);
    2. save and quit to the main menu (a Lua reload is not enough: the symbols stay in memory), load the save;
    3. RST.run({ suite = "rs.actions.map.after-reload" }): the MapItem is a new one (the session really changed),
       the icon and the label are still at PERSIST, exactly once; then they are removed and the file emptied.

Solo: RST.run({ suite = "rs.actions.map", tags = { "world" } })
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_ViewSteps"
require "RST/RST_RSHelpers"

local PLACE_ID = "rstest_spot"
local LABEL = "RST map test"
local PERSIST = { x = 10612, y = 9318, label = "RST persist" }
local PERSIST_FILE = "batman_RadioSurvivor/rstest_map_mark.txt"
-- Frequency of the answer given to the decision (199.8 MHz, the one of the test sheet) and a neighbour.
local TEST_KHZ = 199800
local ASK_MS = 15000

local function onServer() return type(isServer) == "function" and isServer() end

-- E01-T19: dedicated server: the executor here, the map and the history on the requester client.
local function server(t)
    local Actions = require "RadioSurvivor/RS_Actions"
    local MapMarks = require "RadioSurvivor/RS_MapMarks"
    local player = RST.Fixtures.player(t)
    t:ok(player ~= nil, "no target player (t.ctx.player)")
    return Actions, MapMarks, player
end

-- A check of the requester client (RST_ViewSteps.lua), then after(t2, answer) (answer: { status, message, data }).
local function ask(t, step, args, after)
    RST.Steps.ask(t, step, args, { target = "requester", timeoutMs = ASK_MS, none = "skip" }, function(t2, res)
        if after then return after(t2, res.list[1] or {}) end
    end)
end

-- E07-T05 (E01-T16): known blocks of every other connected client (account -> "1001..."), then after(t2, states).
local function othersKnown(t, blocks, after)
    local users = RST.Steps.others(t)
    if #users == 0 then return after(t, {}) end
    RST.Steps.ask(t, "map.known", { blocks = blocks }, { target = users, timeoutMs = ASK_MS }, function(t2, res)
        local states = {}
        for _, e in ipairs(res.list or {}) do
            if e.data and type(e.data.known) == "string" then states[e.user] = e.data.known end
        end
        after(t2, states)
    end)
end

-- E07-T05: the known blocks of each other client are the ones read before the reveal (the area is revealed on the
-- map of the caller only, WorldMapVisitedServer not broadcast); one ask per client (each has its own expected state).
local function othersUnchanged(t, blocks, states)
    local users = {}
    for _, u in ipairs(RST.Steps.others(t)) do
        if states[u] ~= nil then users[#users + 1] = u end
    end
    local function step(tc, i)
        local u = users[i]
        if u == nil then return end
        if not string.find(states[u], "0", 1, true) then
            tc:note("client " .. u .. " already knew every block of the test: absence of the reveal not measurable")
        end
        RST.Steps.ask(tc, "map.known", { blocks = blocks, expect = states[u] }, { target = { u }, timeoutMs = ASK_MS },
            function(t2) step(t2, i + 1) end)
    end
    step(t, 1)
end

local function solo(t)
    if type(isServer) == "function" and isServer() then
        t:skip("solo only: the map of the caller is on its client (MP: final MP session)")
    end
    if type(isClient) == "function" and isClient() then
        t:skip("solo only: the executor runs on the server (MP: final MP session)")
    end
    local ok, MapActions = pcall(require, "RadioSurvivor/RS_MapActions")
    t:ok(ok and type(MapActions) == "table", "RadioSurvivor/RS_MapActions is not loaded")
    local Actions = require "RadioSurvivor/RS_Actions"
    require "RadioSurvivor/RS_MapMarks"
    local player = getPlayer()
    t:ok(player ~= nil, "no player")
    return MapActions, Actions, player
end

-- Test sheet read by the real parser; voice id unique per run (the delay of a voice is kept for the session).
local function testSheet(t, x, y, label, actions)
    local Persona = require "RadioSurvivor/RS_Persona"
    local id = "rstest_map_" .. string.format("%.0f", getTimestampMs())
    local lines = { "format=1", "id=" .. id, "name=RST Map", "frequencies=199.8", "actions=" .. (actions or "say,mark_map"),
        "place=" .. PLACE_ID .. " " .. tostring(x) .. "," .. tostring(y) .. ",0 " .. label, "[prompt]",
        "Test voice of rs.actions.map." }
    local sheet, why = Persona.parseLines(lines, id)
    t:ok(sheet ~= nil, "test sheet refused: " .. tostring(why))
    t:defer(function()
        local S = require "RadioSurvivor/RS_State"
        if S.data and type(S.data.actionCounters) == "table" and S.data.actionCounters[id] ~= nil then
            S.data.actionCounters[id] = nil
            S.dirty = true
        end
    end, "action counters of " .. id)
    return sheet
end

local function decide(Actions, sheet, place, player, khz, cid)
    local decisions = Actions.decide(sheet, "solo", { { type = "mark_map", place = place } }, getTimestampMs(),
        { player = player, khz = khz, cid = cid })
    local d = decisions[1]
    return d and d.reason or "none"
end

-- Indexes (0-based) of the icons and texts of the map at the centre of square (x, y).
local function symbolsAt(MapActions, x, y)
    local api = MapActions.symbolsAPI()
    local icons, texts = {}, {}
    if api == nil then return icons, texts end
    local wx, wy = math.floor(x) + 0.5, math.floor(y) + 0.5
    for i = 0, api:getSymbolCount() - 1 do
        local s = api:getSymbolByIndex(i)
        if math.abs(s:getWorldX() - wx) < MapActions.EPSILON and math.abs(s:getWorldY() - wy) < MapActions.EPSILON then
            if s:isTexture() and s:getSymbolID() == MapActions.ICON then icons[#icons + 1] = i end
            if s:isText() then texts[#texts + 1] = i end
        end
    end
    return icons, texts
end

-- Removes the icons and texts at the centre of square (x, y), highest index first. Returns the count removed.
local function removeAt(MapActions, x, y)
    local icons, texts = symbolsAt(MapActions, x, y)
    local all = {}
    for _, i in ipairs(icons) do all[#all + 1] = i end
    for _, i in ipairs(texts) do all[#all + 1] = i end
    table.sort(all, function(a, b) return a > b end)
    local api = MapActions.symbolsAPI()
    for _, i in ipairs(all) do api:removeSymbolByIndex(i) end
    return #all
end

-- Copy of a table of plain values (radio history of a character).
local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end

-- Lines of kind "mark" with the test label.
local function markLines(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        if l.kind == "mark" and l.text == LABEL then out[#out + 1] = l end
    end
    return out
end

local function spot(player, dx, dy)
    return math.floor(player:getX()) + dx, math.floor(player:getY()) + dy
end

RST.suite("rs.actions.map", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("accepted place marked once on the map of the caller", function(t)
        if onServer() then
            local Actions, _, player = server(t)
            local x, y = spot(player, 4, 3)
            local sheet = testSheet(t, x, y, LABEL)
            t:eq("ok", decide(Actions, sheet, PLACE_ID, player), "mark_map decision")
            t:eq("cooldown", decide(Actions, sheet, PLACE_ID, player), "second decision within the delay")
            ask(t, "map.symbols", { x = x, y = y, label = LABEL, icons = 1, texts = 1, markAgain = true,
                remove = true })
            return
        end
        local MapActions, Actions, player = solo(t)
        local x, y = spot(player, 4, 3)
        local icons, texts = symbolsAt(MapActions, x, y)
        t:eq(0, #icons + #texts, "symbols already at the test square " .. x .. "," .. y)
        t:defer(function() removeAt(MapActions, x, y) end, "symbols of the test")
        local sheet = testSheet(t, x, y, LABEL)
        t:eq("ok", decide(Actions, sheet, PLACE_ID, player), "mark_map decision")
        icons, texts = symbolsAt(MapActions, x, y)
        t:eq(1, #icons, "icons " .. MapActions.ICON .. " at the place")
        t:eq(1, #texts, "labels at the place")
        local text = MapActions.symbolsAPI():getSymbolByIndex(texts[1])
        if player:hasTrait(CharacterTrait.ILLITERATE) then
            t:note("illiterate character: label shown as ?")
        else
            t:eq(LABEL, text:getTranslatedText(), "label")
        end
        t:eq("present", MapActions.mark(x, y, LABEL), "second mark of the same place")
        t:eq("cooldown", decide(Actions, sheet, PLACE_ID, player), "second decision within the delay")
        icons, texts = symbolsAt(MapActions, x, y)
        t:eq(2, #icons + #texts, "no duplicate")
        t:note("marked " .. x .. "," .. y .. " (open the map during the run to see it; removed by the cleanup)")
    end)

    s.test("place not listed by the sheet refused, nothing marked", function(t)
        if onServer() then
            local Actions, _, player = server(t)
            local x, y = spot(player, -4, 3)
            local sheet = testSheet(t, x, y, LABEL)
            t:eq("bad_params", decide(Actions, sheet, "nowhere", player), "unknown place id")
            local without = testSheet(t, x, y, LABEL, "say,remember")
            t:eq("not_allowed", decide(Actions, without, PLACE_ID, player), "sheet without mark_map")
            ask(t, "map.symbols", { x = x, y = y, icons = 0, texts = 0, settleMs = 2000, remove = true })
            return
        end
        local MapActions, Actions, player = solo(t)
        local x, y = spot(player, -4, 3)
        t:defer(function() removeAt(MapActions, x, y) end, "symbols of the test")
        local sheet = testSheet(t, x, y, LABEL)
        t:eq("bad_params", decide(Actions, sheet, "nowhere", player), "unknown place id")
        local without = testSheet(t, x, y, LABEL, "say,remember")
        t:eq("not_allowed", decide(Actions, without, PLACE_ID, player), "sheet without mark_map")
        local icons, texts = symbolsAt(MapActions, x, y)
        t:eq(0, #icons + #texts, "symbols at the place")
    end)

    s.test("mark received noted in the radio history of the caller, on that frequency only", function(t)
        if onServer() then
            local Actions, _, player = server(t)
            local Log = require "RadioSurvivor/RS_RadioLog"
            local S = require "RadioSurvivor/RS_State"
            RST.RSHelpers.character(t, player)
            local cid, record = Log.characterOf(player)
            t:ok(cid ~= nil, "no notebook character bound to the player")
            local x, y = spot(player, -3, -4)
            local saved = deepCopy(record.radio)
            t:defer(function()
                record.radio = saved
                S.dirty = true
                Log.sendAll(player)
            end, "radio history of " .. tostring(cid))
            local sheet = testSheet(t, x, y, LABEL)
            t:eq("ok", decide(Actions, sheet, PLACE_ID, player, TEST_KHZ, cid), "mark_map decision")
            local stored = {}
            for _, f in ipairs(record.radio and record.radio.frequencies or {}) do
                if f.khz == TEST_KHZ then stored = markLines(f.lines) end
            end
            t:eq(1, #stored, "mark lines on " .. TEST_KHZ .. " kHz (server)")
            ask(t, "radio.history", { khz = TEST_KHZ, other = TEST_KHZ + 200, kind = "mark", label = LABEL, cid = cid,
                x = x, key = "IGUI_RS_Radio_mark" }, function(t2)
                ask(t2, "map.symbols", { x = x, y = y, label = LABEL, icons = 1, texts = 1, remove = true })
            end)
            return
        end
        local MapActions, Actions, player = solo(t)
        local Log = require "RadioSurvivor/RS_RadioLog"
        local History = require "RadioSurvivor/RS_RadioHistory"
        local S = require "RadioSurvivor/RS_State"
        local cid, record = Log.characterOf(player)
        if not cid then t:skip("no notebook character bound to the player: open the notebook once, then run again") end
        local x, y = spot(player, -3, -4)
        local icons, texts = symbolsAt(MapActions, x, y)
        t:eq(0, #icons + #texts, "symbols already at the test square " .. x .. "," .. y)
        t:defer(function() removeAt(MapActions, x, y) end, "symbols of the test")
        local saved = deepCopy(record.radio)
        t:defer(function()
            record.radio = saved
            S.dirty = true
            History.request()
        end, "radio history of " .. tostring(cid))
        t:eq(0, #markLines(History.lines(TEST_KHZ)), "mark lines already on the test frequency")
        local sheet = testSheet(t, x, y, LABEL)
        t:eq("ok", decide(Actions, sheet, PLACE_ID, player, TEST_KHZ, cid), "mark_map decision")
        -- Client copy (sent by the server, direct call in solo).
        local marks = markLines(History.lines(TEST_KHZ))
        t:eq(1, #marks, "mark lines on " .. TEST_KHZ .. " kHz (client)")
        t:eq(0, #markLines(History.lines(TEST_KHZ + 200)), "mark lines on another frequency (client)")
        t:eq(cid, History.character, "character of the client history")
        t:ok(string.find(marks[1].text, tostring(x), 1, true) == nil, "coordinates in the history line")
        local shown = getText("IGUI_RS_Radio_mark", marks[1].when, marks[1].text)
        t:ok(shown ~= "IGUI_RS_Radio_mark" and string.find(shown, LABEL, 1, true) ~= nil,
            "notebook line not translated: " .. tostring(shown))
        -- Private state of the server.
        local stored = {}
        for _, f in ipairs(record.radio and record.radio.frequencies or {}) do
            if f.khz == TEST_KHZ then stored = markLines(f.lines) end
        end
        t:eq(1, #stored, "mark lines on " .. TEST_KHZ .. " kHz (server)")
        t:note("history line: " .. shown .. " (open the Radio tab of the notebook during the run to see it)")
    end)
end)

-- ------------------------------------------------------------------------------------------------ manual steps

local function writeMarker(text)
    local writer = getFileWriter(PERSIST_FILE, true, false)
    if not writer then return false end
    writer:write(text)
    writer:close()
    return true
end

local function readMarker()
    local reader = getFileReader(PERSIST_FILE, false)
    if not reader then return nil end
    local line = reader:readLine()
    reader:close()
    return line
end

RST.suite("rs.actions.map.before", { tags = { "world", "manual" } }, function(s)
    s.test("persistent mark placed through the executor", function(t)
        local MapActions, Actions, player = solo(t)
        local icons, texts = symbolsAt(MapActions, PERSIST.x, PERSIST.y)
        if #icons + #texts == 0 then
            local sheet = testSheet(t, PERSIST.x, PERSIST.y, PERSIST.label)
            t:eq("ok", decide(Actions, sheet, PLACE_ID, player), "mark_map decision")
        end
        icons, texts = symbolsAt(MapActions, PERSIST.x, PERSIST.y)
        t:eq(1, #icons, "icon at " .. PERSIST.x .. "," .. PERSIST.y)
        t:eq(1, #texts, "label at " .. PERSIST.x .. "," .. PERSIST.y)
        t:ok(writeMarker(tostring(MapItem.getSingleton())), "cannot write Zomboid/Lua/" .. PERSIST_FILE)
        t:note("now save and quit to the main menu, load this save, then run rs.actions.map.after-reload")
    end)
end)

RST.suite("rs.actions.map.after-reload", { tags = { "world", "manual" } }, function(s)
    s.test("mark still there after the reload, once", function(t)
        local MapActions = solo(t)
        local before = readMarker()
        if before == nil or before == "" then t:skip("run rs.actions.map.before first") end
        t:defer(function()
            removeAt(MapActions, PERSIST.x, PERSIST.y)
            writeMarker("")
        end, "persistent mark")
        t:ok(tostring(MapItem.getSingleton()) ~= before,
            "same MapItem as rs.actions.map.before: quit to the main menu and load the save (not a Lua reload)")
        local icons, texts = symbolsAt(MapActions, PERSIST.x, PERSIST.y)
        t:eq(1, #icons, "icon at " .. PERSIST.x .. "," .. PERSIST.y .. " after the reload")
        t:eq(1, #texts, "label at " .. PERSIST.x .. "," .. PERSIST.y .. " after the reload")
    end)
end)

-- ======================================================================================== rs.actions.reveal

--[[
rs.actions.reveal - action reveal_area of the radio voices (E07-T05): the neighbourhood of a place of the voice sheet
becomes "known" on the world map of the caller (WorldMapVisited, one bit per block of 32 x 32 squares). Solo, and on
a dedicated server like rs.actions.map (E01-T19): the requester client reads its blocks before and after the decision
(step map.known) and clears the blocks of the test afterwards; the account map kept by the server
(WorldMapVisitedServer) keeps them (no targeted forget in the game: test world only). E01-T16 (E07-T05): the known
blocks of every other connected client are read before the reveal and must be the same at the end (map.known asked
to each of them: the area is revealed on the map of the caller only).

rs.actions.reveal (tag "world": solo save named rstest*)
    - a test place far from the player (about 1200 squares, centred in its group of 32 blocks so that no block of
      the area nor of the ring around it has an index multiple of 32: the vanilla coordToUnit quirk never applies,
      and one block can be cleared exactly), whose 5 x 5 blocks are all unknown before the test;
    - RS_Actions.decide accepts reveal_area (reason ok): the 25 blocks of MapMarks.revealRect are known, the rectangle
      is aligned on 32 and at most Const.MAP_REVEAL_MAX_SIDE wide, the ring of blocks around it is unchanged; a second
      decision within the delay is refused "cooldown";
    - an id that is not a place of the sheet is refused "bad_params", a sheet without reveal_area "not_allowed":
      nothing revealed;
    - with a notebook character bound to the player: one radio history line of kind "reveal" with the label only, on
      TEST_KHZ (client copy and private state of the server), translated (IGUI_RS_Radio_reveal); otherwise a note.
    Cleanup: the blocks revealed by the test (unknown before) are cleared again (clearKnownInSquares, block by
    block), the action counters of the test voice are removed, the radio history is restored.

rs.actions.reveal.before / rs.actions.reveal.after-reload (tags "world" and "manual": run by their exact name only)
    Persistence across a reload, vanilla mechanism (solo: map_visited.bin of the save):
    1. RST.run({ suite = "rs.actions.reveal.before" }): reveals a far test area through the real executor and writes
       Zomboid/Lua/batman_RadioSurvivor/rstest_map_reveal.txt (identity of the WorldMapVisited of this session and
       the rectangle);
    2. save and quit to the main menu, load the save;
    3. RST.run({ suite = "rs.actions.reveal.after-reload" }): the WorldMapVisited is a new one, the 25 blocks are still
       known; then they are cleared and the file emptied.

Solo: RST.run({ suite = "rs.actions.reveal", tags = { "world" } })
]]

local REVEAL_FILE = "batman_RadioSurvivor/rstest_map_reveal.txt"
local REVEAL_LABEL = "RST reveal test"
local BLOCK = 32

local function revealDecide(Actions, sheet, place, player, khz, cid)
    local decisions = Actions.decide(sheet, "solo", { { type = "reveal_area", place = place } }, getTimestampMs(),
        { player = player, khz = khz, cid = cid })
    local d = decisions[1]
    return d and d.reason or "none"
end

-- Is block (bx, by) (absolute block indexes, 32 squares) known? isKnown(x, y) looks at x-1..x+1: the centre of the
-- block stays inside it.
local function blockKnown(visited, bx, by)
    return visited:isKnown(bx * BLOCK + 16, by * BLOCK + 16) == true
end

-- Blocks of rect, then of the ring of one block around it: { { bx, by }, ... }.
local function blocksOf(rect, ring)
    local out = {}
    local d = ring and 1 or 0
    for by = rect.y1 / BLOCK - d, rect.y2 / BLOCK - 1 + d do
        for bx = rect.x1 / BLOCK - d, rect.x2 / BLOCK - 1 + d do
            local inside = bx >= rect.x1 / BLOCK and bx < rect.x2 / BLOCK and by >= rect.y1 / BLOCK
                and by < rect.y2 / BLOCK
            if inside ~= (ring == true) then out[#out + 1] = { bx, by } end
        end
    end
    return out
end

local function knownStates(visited, blocks)
    local out = {}
    for i, b in ipairs(blocks) do out[i] = blockKnown(visited, b[1], b[2]) end
    return out
end

-- Clears block (bx, by) exactly (its relative index is never a multiple of 32 here, see chooseArea).
local function clearBlock(visited, bx, by)
    visited:clearKnownInSquares(bx * BLOCK, by * BLOCK, bx * BLOCK + BLOCK - 1, by * BLOCK + BLOCK - 1)
end

-- A far test place: x, y, rect, or nil and the reason. The place is put in the middle of its group of 32 blocks
-- (1024 squares, relative to the map): every block of the area and of its ring has a relative index from 13 to 19.
-- visited nil (dedicated server: the map is on the client): the first area inside the map, its blocks read on the
-- client afterwards.
local function chooseArea(player, MapMarks, visited)
    local bounds = MapMarks.mapBounds()
    if bounds == nil then return nil, "no map bounds (getWorld():getMetaGrid())" end
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local offsets = { { 1200, 0 }, { -1200, 0 }, { 0, 1200 }, { 0, -1200 }, { 1700, 1700 }, { -1700, -1700 },
        { 1700, -1700 }, { -1700, 1700 }, { 2600, 0 }, { -2600, 0 } }
    for _, o in ipairs(offsets) do
        local x = bounds.x1 + math.floor((px + o[1] - bounds.x1) / 1024) * 1024 + 512 + 16
        local y = bounds.y1 + math.floor((py + o[2] - bounds.y1) / 1024) * 1024 + 512 + 16
        local rect = MapMarks.revealRect(x, y, bounds)
        local blocks = MapMarks.revealBlocks()
        if rect and rect.x1 - BLOCK >= bounds.x1 and rect.y1 - BLOCK >= bounds.y1 and rect.x2 + BLOCK <= bounds.x2
                and rect.y2 + BLOCK <= bounds.y2 and rect.x2 - rect.x1 == blocks * BLOCK
                and rect.y2 - rect.y1 == blocks * BLOCK then
            local unknown = true
            if visited ~= nil then
                for _, state in ipairs(knownStates(visited, blocksOf(rect, false))) do
                    if state then unknown = false end
                end
            end
            if unknown then return x, y, rect end
        end
    end
    return nil, "no far test area whose blocks are all unknown (new rstest* save advised)"
end

local function reveal(t)
    local MapActions, Actions, player = solo(t)
    local MapMarks = require "RadioSurvivor/RS_MapMarks"
    t:ok(WorldMapVisited ~= nil, "WorldMapVisited is not exposed")
    local visited = WorldMapVisited.getInstance()
    t:ok(visited ~= nil, "no WorldMapVisited")
    return MapActions, Actions, MapMarks, player, visited
end

-- E01-T19 (dedicated server): blocks a then b in one list.
local function joined(a, b)
    local out = {}
    for _, x in ipairs(a) do out[#out + 1] = x end
    for _, x in ipairs(b) do out[#out + 1] = x end
    return out
end

-- Blocks of list whose character in known (string of "1" / "0") is "0".
local function unknownOf(list, known)
    local out = {}
    for i, b in ipairs(list) do
        if string.sub(known, i, i) == "0" then out[#out + 1] = b end
    end
    return out
end

local function revealLines(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        if l.kind == "reveal" and l.text == REVEAL_LABEL then out[#out + 1] = l end
    end
    return out
end

RST.suite("rs.actions.reveal", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("accepted place revealed on the map of the caller, bounded, nothing around", function(t)
        if onServer() then
            local Actions, MapMarks, player = server(t)
            local Log = require "RadioSurvivor/RS_RadioLog"
            local S = require "RadioSurvivor/RS_State"
            RST.RSHelpers.character(t, player)
            local cid, record = Log.characterOf(player)
            t:ok(cid ~= nil, "no notebook character bound to the player")
            local x, y, rect = chooseArea(player, MapMarks, nil)
            if x == nil then t:skip(y) end
            local inside, ring = blocksOf(rect, false), blocksOf(rect, true)
            local all = joined(inside, ring)
            -- E07-T05 (E01-T16): known blocks of the other clients read first, unchanged at the end.
            othersKnown(t, all, function(t1, states)
                ask(t1, "map.known", { blocks = all }, function(t2, before)
                    local known = before.data and before.data.known
                    t2:ok(type(known) == "string" and string.len(known) == #all, "known blocks not read on the client")
                    if string.find(string.sub(known, 1, #inside), "1", 1, true) then
                        t2:skip("part of the test area is already known on the client (new rstest* world advised)")
                    end
                    local saved = deepCopy(record.radio)
                    t2:defer(function()
                        record.radio = saved
                        S.dirty = true
                        Log.sendAll(player)
                    end, "radio history of " .. tostring(cid))
                    local sheet = testSheet(t2, x, y, REVEAL_LABEL, "say,reveal_area")
                    t2:eq("ok", revealDecide(Actions, sheet, PLACE_ID, player, TEST_KHZ, cid), "reveal_area decision")
                    t2:eq(0, rect.x1 % BLOCK + rect.y1 % BLOCK + rect.x2 % BLOCK + rect.y2 % BLOCK,
                        "rectangle aligned on 32")
                    local maxSide = require("RadioSurvivor/RadioSurvivor_Const").MAP_REVEAL_MAX_SIDE
                    t2:ok(rect.x2 - rect.x1 <= maxSide and rect.y2 - rect.y1 <= maxSide, "rectangle capped")
                    t2:eq("cooldown", revealDecide(Actions, sheet, PLACE_ID, player), "second decision within the delay")
                    local stored = {}
                    for _, f in ipairs(record.radio and record.radio.frequencies or {}) do
                        if f.khz == TEST_KHZ then stored = revealLines(f.lines) end
                    end
                    t2:eq(1, #stored, "reveal lines on " .. TEST_KHZ .. " kHz (server)")
                    t2:note("revealed " .. rect.x1 .. "," .. rect.y1 .. " - " .. rect.x2 .. "," .. rect.y2 .. " (the client"
                        .. " clears its blocks at the end; the account map of the server keeps them: no targeted forget)")
                    -- Area known on the client, ring of blocks unchanged; the blocks of the area cleared there afterwards.
                    local expect = string.rep("1", #inside) .. string.sub(known, #inside + 1)
                    ask(t2, "map.known", { blocks = all, expect = expect, clear = inside }, function(t3)
                        ask(t3, "radio.history", { khz = TEST_KHZ, other = TEST_KHZ + 200, kind = "reveal",
                            label = REVEAL_LABEL, cid = cid, x = x, key = "IGUI_RS_Radio_reveal" }, function(t4)
                            othersUnchanged(t4, all, states)   -- E07-T05: nothing revealed on the other clients
                        end)
                    end)
                end)
            end)
            return
        end
        local _, Actions, MapMarks, player, visited = reveal(t)
        local x, y, rect = chooseArea(player, MapMarks, visited)
        if x == nil then t:skip(y) end
        local inside, ring = blocksOf(rect, false), blocksOf(rect, true)
        local ringBefore = knownStates(visited, ring)
        t:defer(function()
            for _, b in ipairs(inside) do clearBlock(visited, b[1], b[2]) end
        end, "blocks revealed by the test")
        -- Radio history: restored after the test when a notebook character is bound.
        local Log = require "RadioSurvivor/RS_RadioLog"
        local History = require "RadioSurvivor/RS_RadioHistory"
        local S = require "RadioSurvivor/RS_State"
        local cid, record = Log.characterOf(player)
        if cid then
            local saved = deepCopy(record.radio)
            t:defer(function()
                record.radio = saved
                S.dirty = true
                History.request()
            end, "radio history of " .. tostring(cid))
        end
        local sheet = testSheet(t, x, y, REVEAL_LABEL, "say,reveal_area")
        t:eq("ok", revealDecide(Actions, sheet, PLACE_ID, player, TEST_KHZ, cid), "reveal_area decision")
        t:eq(0, rect.x1 % BLOCK + rect.y1 % BLOCK + rect.x2 % BLOCK + rect.y2 % BLOCK, "rectangle aligned on 32")
        local maxSide = require("RadioSurvivor/RadioSurvivor_Const").MAP_REVEAL_MAX_SIDE
        t:ok(rect.x2 - rect.x1 <= maxSide and rect.y2 - rect.y1 <= maxSide, "rectangle capped")
        local unknown = 0
        for _, state in ipairs(knownStates(visited, inside)) do
            if not state then unknown = unknown + 1 end
        end
        t:eq(0, unknown, "blocks of the area still unknown (of " .. #inside .. ")")
        t:eq(ringBefore, knownStates(visited, ring), "ring of blocks around the area changed")
        t:eq("cooldown", revealDecide(Actions, sheet, PLACE_ID, player), "second decision within the delay")
        if cid then
            local lines = revealLines(History.lines(TEST_KHZ))
            t:eq(1, #lines, "reveal lines on " .. TEST_KHZ .. " kHz (client)")
            t:eq(0, #revealLines(History.lines(TEST_KHZ + 200)), "reveal lines on another frequency (client)")
            t:ok(string.find(lines[1].text, tostring(x), 1, true) == nil, "coordinates in the history line")
            local shown = getText("IGUI_RS_Radio_reveal", lines[1].when, lines[1].text)
            t:ok(shown ~= "IGUI_RS_Radio_reveal" and string.find(shown, REVEAL_LABEL, 1, true) ~= nil,
                "notebook line not translated: " .. tostring(shown))
            local stored = {}
            for _, f in ipairs(record.radio and record.radio.frequencies or {}) do
                if f.khz == TEST_KHZ then stored = revealLines(f.lines) end
            end
            t:eq(1, #stored, "reveal lines on " .. TEST_KHZ .. " kHz (server)")
        else
            t:note("no notebook character bound to the player: history line not checked (open the notebook once)")
        end
        t:note("revealed " .. rect.x1 .. "," .. rect.y1 .. " - " .. rect.x2 .. "," .. rect.y2
            .. " (open the map during the run to see it; cleared by the cleanup)")
    end)

    s.test("place not listed by the sheet refused, nothing revealed", function(t)
        if onServer() then
            local Actions, MapMarks, player = server(t)
            local x, y, rect = chooseArea(player, MapMarks, nil)
            if x == nil then t:skip(y) end
            local inside = blocksOf(rect, false)
            ask(t, "map.known", { blocks = inside }, function(t2, before)
                local known = before.data and before.data.known
                t2:ok(type(known) == "string" and string.len(known) == #inside, "known blocks not read on the client")
                local sheet = testSheet(t2, x, y, REVEAL_LABEL, "say,reveal_area")
                t2:eq("bad_params", revealDecide(Actions, sheet, "nowhere", player), "unknown place id")
                local without = testSheet(t2, x, y, REVEAL_LABEL, "say,mark_map")
                t2:eq("not_allowed", revealDecide(Actions, without, PLACE_ID, player), "sheet without reveal_area")
                ask(t2, "map.known", { blocks = inside, expect = known, clear = unknownOf(inside, known) })
            end)
            return
        end
        local _, Actions, MapMarks, player, visited = reveal(t)
        local x, y, rect = chooseArea(player, MapMarks, visited)
        if x == nil then t:skip(y) end
        local inside = blocksOf(rect, false)
        t:defer(function()
            for _, b in ipairs(inside) do clearBlock(visited, b[1], b[2]) end
        end, "blocks of the test area")
        local sheet = testSheet(t, x, y, REVEAL_LABEL, "say,reveal_area")
        t:eq("bad_params", revealDecide(Actions, sheet, "nowhere", player), "unknown place id")
        local without = testSheet(t, x, y, REVEAL_LABEL, "say,mark_map")
        t:eq("not_allowed", revealDecide(Actions, without, PLACE_ID, player), "sheet without reveal_area")
        local known = 0
        for _, state in ipairs(knownStates(visited, inside)) do
            if state then known = known + 1 end
        end
        t:eq(0, known, "blocks of the area known")
    end)
end)

RST.suite("rs.actions.reveal.before", { tags = { "world", "manual" } }, function(s)
    s.test("far area revealed through the executor", function(t)
        local _, Actions, MapMarks, player, visited = reveal(t)
        local x, y, rect = chooseArea(player, MapMarks, visited)
        if x == nil then t:skip(y) end
        local sheet = testSheet(t, x, y, REVEAL_LABEL, "say,reveal_area")
        t:eq("ok", revealDecide(Actions, sheet, PLACE_ID, player), "reveal_area decision")
        local writer = getFileWriter(REVEAL_FILE, true, false)
        t:ok(writer ~= nil, "cannot write Zomboid/Lua/" .. REVEAL_FILE)
        writer:write(tostring(visited) .. "|" .. rect.x1 .. "," .. rect.y1 .. "," .. rect.x2 .. "," .. rect.y2)
        writer:close()
        t:note("revealed " .. rect.x1 .. "," .. rect.y1 .. " - " .. rect.x2 .. "," .. rect.y2
            .. "; now save and quit to the main menu, load this save, then run rs.actions.reveal.after-reload")
    end)
end)

RST.suite("rs.actions.reveal.after-reload", { tags = { "world", "manual" } }, function(s)
    s.test("area still known after the reload", function(t)
        local _, _, _, _, visited = reveal(t)
        local reader = getFileReader(REVEAL_FILE, false)
        local line = reader and reader:readLine() or nil
        if reader then reader:close() end
        if line == nil or line == "" then t:skip("run rs.actions.reveal.before first") end
        local before, x1, y1, x2, y2 = string.match(line, "^(.*)|(%d+),(%d+),(%d+),(%d+)$")
        t:ok(before ~= nil, "unreadable " .. REVEAL_FILE .. ": " .. tostring(line))
        local rect = { x1 = tonumber(x1), y1 = tonumber(y1), x2 = tonumber(x2), y2 = tonumber(y2) }
        local inside = blocksOf(rect, false)
        t:defer(function()
            for _, b in ipairs(inside) do clearBlock(visited, b[1], b[2]) end
            local writer = getFileWriter(REVEAL_FILE, true, false)
            if writer then
                writer:write("")
                writer:close()
            end
        end, "revealed test area")
        t:ok(tostring(visited) ~= before,
            "same WorldMapVisited as rs.actions.reveal.before: quit to the main menu and load the save")
        local unknown = 0
        for _, state in ipairs(knownStates(visited, inside)) do
            if not state then unknown = unknown + 1 end
        end
        t:eq(0, unknown, "blocks of the area unknown after the reload (of " .. #inside .. ")")
    end)
end)
