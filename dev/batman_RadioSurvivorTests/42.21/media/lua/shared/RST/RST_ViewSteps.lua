--[[
RST_ViewSteps - client checks asked by the authority through RST.Steps for the suites that were "solo only" because
what they check is drawn or kept by the displaying client (E01-T19: lk.equipment, lk.speech, lk.ranged,
rs.actions.map, rs.actions.reveal). Development mod only. Load with: require "RST/RST_ViewSteps" (shared: the
handlers are registered on every side; they run on the clients and, in solo, in the same Lua state).
The suites keep their solo code path; on a dedicated server (RST.server, campaign mp) they act on the authority and
ask these steps to the requester client (target "requester"), which displays the npc bodies and owns the map.

Client handlers (RST.Steps.on); every body is found by its npc id in LivingKnox.Anim.knownBodies() (local copy):
    lk.weapon.state   { npc, slot, item, mode = "rest" | "hand" | "none", weapon, node, label }: the weapon of the
                      body as shown here (RST.LKEquipment.state, RST.LKAnims.info): at rest = item at slot, hands
                      empty, variable Weapon empty; in hand = item in the primary hand, slot emptied, variable
                      Weapon = weapon (when given), node live (when given); none = primary hand and slot empty
                      (weapon removed). Polled until true or the deadline.
    lk.weapon.count   { npc, phase = "begin" | "end", key }: begin = OnEquipPrimary counter for the body, fishing
                      calls skipped (LivingKnox.Equipment.stats.skipped) and Lua errors (getLuaDebuggerErrorCount)
                      noted; end = counter removed and checked: events > 0, skipped calls = events received while
                      the body was local here (the vanilla handler calls handleFishing for a local character only:
                      on its owner client in MP) when the vanilla fishing handler is loaded, no Lua error (data:
                      events, localEvents, skipped, errors).
    lk.speech.bubble  { npc, id, line | text, again }: the reply id reached the speech view (View.seen), one bubble
                      of the body shows the text (line = key suffix of LivingKnox.SpeechData.KEY_PREFIX, translated
                      HERE: a server has no mod translation), drawn at least once at a point of the screen; again =
                      the same reply delivered again is refused and shows nothing more.
    lk.combat.view    { phase = "begin" | "end", key, shots }: shots played here by LivingKnox.CombatView
                      (shotsPlayed, shotsDuplicate, flashes); end: played = shots, no duplicate (data: deltas).
    map.symbols       { x, y, label, icons, texts, settleMs, markAgain, remove }: icons RS_MapActions.ICON and texts
                      at the centre of square x, y on the map of this player equal to icons, texts (polled, at least
                      settleMs after the ask); label (when this character can read); markAgain = a second
                      RS_MapActions.mark gives "present" and adds nothing; remove = the symbols there are removed
                      at the end, PASS or FAIL.
    map.known         { blocks = { { bx, by }, ... }, expect = "1001..." | nil, clear = { { bx, by }, ... } }:
                      known state of blocks of 32 squares on the map of this player (WorldMapVisited, read at the
                      centre of each block), returned in data.known as a string of "1" / "0"; with expect, polled
                      until equal; clear = these blocks are cleared at the end (clearKnownInSquares), PASS or FAIL.
    radio.history     { khz, other, kind, label, cid, x, key }: client copy of the radio history
                      (RS_RadioHistory): exactly one line of that kind and label on khz, none on other, history of
                      character cid, no coordinate x in the line, notebook line key translated with the label.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.ViewSteps = RST.ViewSteps or {}
local VS = RST.ViewSteps
local Steps = RST.Steps

VS.BLOCK = 32
VS.counters = VS.counters or {}   -- key -> state of lk.weapon.count / lk.combat.view (clients, solo)

local function bodyOf(npc)
    local A = LivingKnox and LivingKnox.Anim
    if A == nil or type(A.knownBodies) ~= "function" or type(npc) ~= "string" then return nil end
    return A.knownBodies()[npc]
end

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- ---------------------------------------------------------------- lk.weapon.state

-- nil when the state is right, else the reason.
local function weaponGap(args, z)
    local Eq, An = RST.LKEquipment, RST.LKAnims
    local s = Eq.state(z, args.slot)
    local label = tostring(args.item) .. " " .. tostring(args.label or args.mode)
    local seen = Eq.describe(s)
    if args.mode == "hand" then
        if s.hand ~= args.item then return label .. ": primary hand (" .. seen .. ")" end
        if s.slot ~= "" then return label .. ": slot " .. tostring(args.slot) .. " not emptied (" .. seen .. ")" end
        if args.weapon ~= nil and s.weapon ~= args.weapon then
            return label .. ": variable Weapon " .. tostring(args.weapon) .. " expected (" .. seen .. ")"
        end
        if args.node ~= nil then
            local info = An.info(z)
            if not has(info.nodes, args.node) then
                return label .. ": node " .. args.node .. " not live (" .. An.describe(info) .. ")"
            end
        end
        return nil
    end
    if args.mode == "none" then
        if s.hand ~= "" or s.slot ~= "" then return label .. ": weapon still shown (" .. seen .. ")" end
        return nil
    end
    if s.slot ~= args.item then return label .. ": item at " .. tostring(args.slot) .. " (" .. seen .. ")" end
    if s.hand ~= "" or s.second ~= "" then return label .. ": hands not empty (" .. seen .. ")" end
    if s.weapon ~= "" then return label .. ": variable Weapon not empty (" .. seen .. ")" end
    return nil
end

Steps.on("lk.weapon.state", function(args)
    if RST.LKEquipment == nil or RST.LKEquipment.state == nil or RST.LKAnims == nil then
        return Steps.fail("suite files RST_LKEquipment / RST_LKAnims not loaded on this client")
    end
    local last = "body " .. tostring(args.npc) .. " not known here"
    return function(ctx)
        local z = bodyOf(args.npc)
        if z ~= nil then
            local gap = weaponGap(args, z)
            if gap == nil then
                return Steps.pass(tostring(args.item) .. " " .. tostring(args.label or args.mode) .. ": "
                    .. RST.LKEquipment.describe(RST.LKEquipment.state(z, args.slot)))
            end
            last = gap
        end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.weapon.count

Steps.on("lk.weapon.count", function(args)
    local key = tostring(args.key)
    local E = LivingKnox and LivingKnox.Equipment
    if E == nil then return Steps.fail("LivingKnox.Equipment is not loaded on this client") end
    if args.phase == "begin" then
        local c = { events = 0, localEvents = 0, allLocal = 0, skipped0 = E.stats.skipped,
            errors0 = type(getLuaDebuggerErrorCount) == "function" and getLuaDebuggerErrorCount() or nil }
        c.fn = function(chr)
            -- Every local non-player character (other npc bodies owned here too: MP campaign of 2026-10-15, 7 calls
            -- skipped for 4 events of the npc under test) goes through the guard of LivingKnox.Equipment.
            local player = type(instanceof) == "function" and instanceof(chr, "IsoPlayer")
            local okL, isLocal = pcall(function() return chr:isLocal() end)
            if chr ~= nil and not player and okL and isLocal then c.allLocal = c.allLocal + 1 end
            if chr ~= nil and chr == bodyOf(args.npc) then
                c.events = c.events + 1
                -- Fishing.Handler.onEquipPrimary calls handleFishing only for a local character
                -- (FishingHandler.lua:15-18): a zombie is local on its owner client only
                -- (NetworkComponent.isLocal, NetworkZombieComponent.isRemote = no auth owner here).
                if chr:isLocal() then c.localEvents = c.localEvents + 1 end
            end
        end
        Events.OnEquipPrimary.Add(c.fn)
        VS.counters[key] = c
        return Steps.pass("OnEquipPrimary counter set for " .. tostring(args.npc))
    end
    local c = VS.counters[key]
    if c == nil then return Steps.fail("no counter " .. key .. " on this client (begin missed)") end
    VS.counters[key] = nil
    Events.OnEquipPrimary.Remove(c.fn)
    local skipped = E.stats.skipped - c.skipped0
    local errors = c.errors0 ~= nil and (getLuaDebuggerErrorCount() - c.errors0) or nil
    local fishing = Fishing ~= nil and Fishing.Handler ~= nil
    local data = { events = c.events, localEvents = c.localEvents, allLocal = c.allLocal, skipped = skipped,
        errors = errors, fishing = fishing }
    local text = "OnEquipPrimary events " .. c.events .. " (body owned here: " .. c.localEvents
        .. "; all local non-players: " .. c.allLocal .. "), fishing handler calls skipped " .. skipped
        .. " (fishing handler loaded: " .. tostring(fishing) .. "), Lua errors " .. tostring(errors)
    if c.events == 0 then return Steps.fail("no OnEquipPrimary event for the npc: " .. text, data) end
    if fishing and (skipped ~= c.allLocal or skipped < c.localEvents) then
        return Steps.fail("fishing handler calls not skipped: " .. text, data)
    end
    if errors ~= nil and errors > 0 then
        local list, lines = getLuaDebuggerErrors(), {}
        for i = math.max(0, list:size() - math.min(errors, 3)), list:size() - 1 do
            lines[#lines + 1] = string.match(tostring(list:get(i)), "[^\n]*")
        end
        return Steps.fail("Lua errors while the npc took its weapons in hand: " .. text .. " ("
            .. table.concat(lines, " | ") .. ")", data)
    end
    return Steps.pass(text, data)
end)

-- ---------------------------------------------------------------- lk.speech.bubble

Steps.on("lk.speech.bubble", function(args)
    local V = LivingKnox and LivingKnox.SpeechView
    if V == nil then return Steps.fail("LivingKnox.SpeechView is not loaded on this client") end
    local want = args.text
    if want == nil and type(args.line) == "string" then want = getText(LivingKnox.SpeechData.KEY_PREFIX .. args.line) end
    if type(want) ~= "string" then return Steps.fail("no text to look for") end
    local drawn0 = V.stats.drawn
    local last = "reply " .. tostring(args.id) .. " not received here"
    return function(ctx)
        local z = bodyOf(args.npc)
        if args.id ~= nil and not V.seen[args.id] then
            last = "reply " .. tostring(args.id) .. " not received here"
        elseif z == nil then
            last = "body " .. tostring(args.npc) .. " not known here"
        else
            local n = 0
            for _, b in ipairs(V.bubbles) do
                if b.z == z and b.text == want then n = n + 1 end
            end
            local d = V.lastDraw
            if n ~= 1 then
                last = n .. " bubble(s) of the body with '" .. want .. "'"
            elseif V.stats.drawn <= drawn0 or d == nil or d.npc ~= args.npc or d.text ~= want then
                last = "bubble '" .. want .. "' never drawn"
            else
                local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
                if d.x < 0 or d.x > w or d.y < 0 or d.y > h then
                    return Steps.fail("bubble drawn off screen: " .. tostring(d.x) .. "," .. tostring(d.y)
                        .. " (screen " .. w .. "x" .. h .. ")")
                end
                local note = "'" .. want .. "' drawn at " .. tostring(d.x) .. "," .. tostring(d.y)
                if args.again then
                    local shown = V.stats.shown
                    if V.receive({ id = args.id, npc = args.npc, t = "again" }) ~= false then
                        return Steps.fail("repeated delivery accepted")
                    end
                    if V.stats.shown ~= shown then return Steps.fail("bubbles shown after a repeated delivery") end
                    note = note .. "; repeated delivery refused"
                end
                return Steps.pass(note)
            end
        end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- lk.combat.view

local COMBAT_KEYS = { "shotsPlayed", "shotsDuplicate", "flashes" }

Steps.on("lk.combat.view", function(args)
    local V = LivingKnox and LivingKnox.CombatView
    if V == nil then return Steps.fail("LivingKnox.CombatView is not loaded on this client") end
    local key = tostring(args.key)
    if args.phase == "begin" then
        local snap = {}
        for _, k in ipairs(COMBAT_KEYS) do snap[k] = V.stats[k] or 0 end
        VS.counters[key] = snap
        return Steps.pass("combat view counters noted")
    end
    local snap = VS.counters[key]
    if snap == nil then return Steps.fail("no snapshot " .. key .. " on this client (begin missed)") end
    VS.counters[key] = nil
    local d = {}
    for _, k in ipairs(COMBAT_KEYS) do d[k] = (V.stats[k] or 0) - snap[k] end
    local text = "played here: " .. d.shotsPlayed .. ", duplicates " .. d.shotsDuplicate .. ", flashes " .. d.flashes
    if d.shotsPlayed ~= args.shots then
        return Steps.fail("shots played here (sound and flash once each): " .. tostring(args.shots)
            .. " expected, " .. text, d)
    end
    if d.shotsDuplicate ~= 0 then return Steps.fail("duplicate shots: " .. text, d) end
    return Steps.pass(text, d)
end)

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
            return finish(Steps.pass(note))
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

return VS
