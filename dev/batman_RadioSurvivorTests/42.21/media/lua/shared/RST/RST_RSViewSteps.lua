--[[
RST_RSViewSteps - client checks of the RadioSurvivor suites asked by the authority through RST.Steps (E01-T19:
rs.actions.map, rs.actions.reveal; E21-T07: moved out of RST_ViewSteps.lua of batman_CoreAITests, same table
RST.ViewSteps). Development mod only (batman_RadioSurvivorTests). Load with: require "RST/RST_RSViewSteps" (shared:
the handlers are registered on every side; they run on the clients and, in solo, in the same Lua state).

Client handlers (RST.Steps.on):
    map.symbols       { x, y, label, icons, texts, settleMs, markAgain, remove }: icons RS_MapActions.ICON and texts
                      at the centre of square x, y on the map of this player equal to icons, texts (polled, at least
                      settleMs after the ask); label (when this character can read); markAgain = a second
                      RS_MapActions.mark gives "present" and adds nothing; remove = the symbols there are removed
                      at the end, PASS or FAIL. data.map: identity of the MapItem of this session (tostring of
                      MapItem.getSingleton(), nil without one; a new one after a reconnection).
    map.known         { blocks = { { bx, by }, ... }, expect = "1001..." | nil, clear = { { bx, by }, ... } }:
                      known state of blocks of 32 squares on the map of this player (WorldMapVisited, read at the
                      centre of each block), returned in data.known as a string of "1" / "0"; with expect, polled
                      until equal; clear = these blocks are cleared at the end (clearKnownInSquares), PASS or FAIL.
    radio.history     { khz, other, kind, label, cid, x, key }: client copy of the radio history
                      (RS_RadioHistory): exactly one line of that kind and label on khz, none on other, history of
                      character cid, no coordinate x in the line, notebook line key translated with the label.
    survey.menu       { x, y, z, choose }: E22-T08, the world context menu of this client on square x, y, z filled by
                      the real RS_PlaceSurveyMenu.onFill (objects of the square as the picked world objects); data.options
                      = number of "Voice workshop: record this place" options; with choose, the option is chosen (real
                      request sent to the authority, or direct call in solo). SKIP when the square is not loaded here.
]]

require "RST/RST"
require "RST/RST_ViewSteps"

local VS = RST.ViewSteps
local Steps = RST.Steps

VS.BLOCK = 32

-- ---------------------------------------------------------------- map.symbols

local function mapActions()
    local ok, M = pcall(require, "RadioSurvivor/RS_MapActions")
    if ok and type(M) == "table" then return M end
    return nil
end

-- Indexes (0-based) of the icons and texts at the centre of square (x, y).
function VS.symbolsAt(M, x, y)
    local api = M.symbolsAPI()
    local icons, texts = {}, {}
    if api == nil then return icons, texts end
    local wx, wy = math.floor(x) + 0.5, math.floor(y) + 0.5
    for i = 0, api:getSymbolCount() - 1 do
        local s = api:getSymbolByIndex(i)
        if math.abs(s:getWorldX() - wx) < M.EPSILON and math.abs(s:getWorldY() - wy) < M.EPSILON then
            if s:isTexture() and s:getSymbolID() == M.ICON then icons[#icons + 1] = i end
            if s:isText() then texts[#texts + 1] = i end
        end
    end
    return icons, texts
end

-- Identity of the world map object of this session (MapItem.getSingleton), or nil.
local function mapIdentity()
    if MapItem == nil or type(MapItem.getSingleton) ~= "function" then return nil end
    local map = MapItem.getSingleton()
    if map == nil then return nil end
    return tostring(map)
end

function VS.removeAt(M, x, y)
    local icons, texts = VS.symbolsAt(M, x, y)
    local all = {}
    for _, i in ipairs(icons) do all[#all + 1] = i end
    for _, i in ipairs(texts) do all[#all + 1] = i end
    table.sort(all, function(a, b) return a > b end)
    local api = M.symbolsAPI()
    for _, i in ipairs(all) do api:removeSymbolByIndex(i) end
    return #all
end

Steps.on("map.symbols", function(args)
    local M = mapActions()
    if M == nil then return Steps.fail("RadioSurvivor/RS_MapActions is not loaded on this client") end
    if M.symbolsAPI() == nil then return Steps.fail("no world map symbols API on this client") end
    local x, y = args.x, args.y
    local settle = RST.now() + (tonumber(args.settleMs) or 0)
    local last = "nothing read"
    local function finish(res)
        if args.remove then VS.removeAt(M, x, y) end
        return res
    end
    return function(ctx)
        local icons, texts = VS.symbolsAt(M, x, y)
        local counted = #icons == args.icons and #texts == args.texts
        last = #icons .. " icon(s) " .. M.ICON .. " and " .. #texts .. " text(s) at " .. x .. "," .. y .. " ("
            .. tostring(args.icons) .. " and " .. tostring(args.texts) .. " expected)"
        if counted and RST.now() >= settle then
            local note = last
            local p = getPlayer()
            if args.label ~= nil and #texts == 1 then
                if p ~= nil and p:hasTrait(CharacterTrait.ILLITERATE) then
                    note = note .. "; illiterate character: label shown as ?"
                else
                    local shown = M.symbolsAPI():getSymbolByIndex(texts[1]):getTranslatedText()
                    if shown ~= args.label then
                        return finish(Steps.fail("label '" .. tostring(shown) .. "', '" .. args.label .. "' expected"))
                    end
                end
            end
            if args.markAgain then
                local again = M.mark(x, y, args.label)
                if again ~= "present" then
                    return finish(Steps.fail("second mark of the same place: " .. tostring(again)))
                end
                local i2, t2 = VS.symbolsAt(M, x, y)
                if #i2 + #t2 ~= args.icons + args.texts then
                    return finish(Steps.fail("duplicate after a second mark: " .. #i2 .. " icon(s), " .. #t2
                        .. " text(s)"))
                end
                note = note .. "; second mark: present"
            end
            return finish(Steps.pass(note, { map = mapIdentity() }))
        end
        if ctx.final then return finish(Steps.fail(last)) end
        return nil
    end
end)

-- ---------------------------------------------------------------- map.known

local function knownString(visited, blocks)
    local out = {}
    for i, b in ipairs(blocks or {}) do
        out[i] = visited:isKnown(b[1] * VS.BLOCK + 16, b[2] * VS.BLOCK + 16) == true and "1" or "0"
    end
    return table.concat(out)
end

Steps.on("map.known", function(args)
    if WorldMapVisited == nil or WorldMapVisited.getInstance() == nil then
        return Steps.fail("no WorldMapVisited on this client")
    end
    local visited = WorldMapVisited.getInstance()
    local function finish(res)
        for _, b in ipairs(args.clear or {}) do
            visited:clearKnownInSquares(b[1] * VS.BLOCK, b[2] * VS.BLOCK, b[1] * VS.BLOCK + VS.BLOCK - 1,
                b[2] * VS.BLOCK + VS.BLOCK - 1)
        end
        return res
    end
    if args.expect == nil then
        return finish(Steps.pass(nil, { known = knownString(visited, args.blocks) }))
    end
    return function(ctx)
        local known = knownString(visited, args.blocks)
        if known == args.expect then return finish(Steps.pass(#(args.blocks or {}) .. " block(s) as expected",
            { known = known })) end
        if ctx.final then
            return finish(Steps.fail("known blocks " .. known .. ", " .. tostring(args.expect) .. " expected",
                { known = known }))
        end
        return nil
    end
end)

-- ---------------------------------------------------------------- radio.history

Steps.on("radio.history", function(args)
    local ok, History = pcall(require, "RadioSurvivor/RS_RadioHistory")
    if not ok or type(History) ~= "table" then return Steps.fail("RadioSurvivor/RS_RadioHistory is not loaded here") end
    local function lines(khz)
        local out = {}
        for _, l in ipairs(History.lines(khz) or {}) do
            if l.kind == args.kind and l.text == args.label then out[#out + 1] = l end
        end
        return out
    end
    local last = "nothing read"
    return function(ctx)
        local found = lines(args.khz)
        if #found ~= 1 then
            last = #found .. " " .. tostring(args.kind) .. " line(s) on " .. tostring(args.khz) .. " kHz (client), 1 expected"
        elseif #lines(args.other) ~= 0 then
            return Steps.fail(args.kind .. " lines on another frequency (client)")
        elseif History.character ~= args.cid then
            last = "character of the client history " .. tostring(History.character) .. ", " .. tostring(args.cid)
                .. " expected"
        else
            if args.x ~= nil and string.find(found[1].text, tostring(args.x), 1, true) ~= nil then
                return Steps.fail("coordinates in the history line")
            end
            local shown = getText(args.key, found[1].when, found[1].text)
            if shown == args.key or string.find(shown, args.label, 1, true) == nil then
                return Steps.fail("notebook line not translated: " .. tostring(shown))
            end
            return Steps.pass("history line: " .. shown)
        end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- survey.menu (E22-T08)

Steps.on("survey.menu", function(args)
    local ok, Menu = pcall(require, "RadioSurvivor/RS_PlaceSurveyMenu")
    if not ok or type(Menu) ~= "table" or type(Menu.onFill) ~= "function" then
        return Steps.fail("RadioSurvivor/RS_PlaceSurveyMenu is not loaded on this client")
    end
    local cell = getCell()
    local sq = cell and cell:getGridSquare(args.x, args.y, args.z)
    if sq == nil then return Steps.skip("square " .. tostring(args.x) .. "," .. tostring(args.y) .. " not loaded here") end
    local world = {}
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do world[#world + 1] = objects:get(i) end
    if #world == 0 then return Steps.skip("no object on the square to right click") end
    local label = getText("IGUI_RS_Survey_Menu")
    local found = {}
    local context = {}
    function context:addOption(name, target, fn, a, b, c)
        if name == label then found[#found + 1] = { target = target, fn = fn, a = a, b = b, c = c } end
    end
    Menu.onFill(0, context, world, false)
    local option = found[1]
    if args.choose and option ~= nil then option.fn(option.target, option.a, option.b, option.c) end
    return Steps.pass(#found .. " survey option(s)" .. ((args.choose and option) and ", chosen" or ""),
        { options = #found })
end)

return VS
