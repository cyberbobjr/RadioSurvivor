--[[
RST_LKViewSteps - client checks of the Living Knox suites asked by the authority through RST.Steps (E01-T19:
lk.equipment, lk.speech, lk.ranged, lk.talk; E21-T07: moved out of RST_ViewSteps.lua of batman_CoreAITests, same
table RST.ViewSteps). Development mod only (batman_LivingKnoxTests). Load with: require "RST/RST_LKViewSteps"
(shared: the handlers are registered on every side; they run on the clients and, in solo, in the same Lua state).

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
    lk.talk.say       { text }: the sentence said in the say chat of this client and sent by the notebook client of
                      the core mod (no selected target: the nearest NPC).
    lk.talk.bubble    { text }: the last bubble shown by LivingKnox.SpeechView has that text (polled).
]]

require "RST/RST"
require "RST/RST_ViewSteps"

local VS = RST.ViewSteps
local Steps = RST.Steps

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

-- ---------------------------------------------------------------- lk.talk.say, lk.talk.bubble (E18-T18)

-- A sentence of the say chat of this client (E21-T05): said by the vanilla say chat, then sent by the notebook client
-- of the core mod as its chat wrapper does (no selected target: the nearest NPC).
Steps.on("lk.talk.say", function(args)
    local Client = CoreAI and CoreAI.notebookClient
    if Client == nil or Client.talk == nil then return Steps.fail("notebook client of the core mod not loaded here") end
    if type(processSayMessage) ~= "function" then return Steps.fail("no say chat here") end
    processSayMessage(tostring(args.text))
    if not Client.talk(tostring(args.text), false, true) then return Steps.fail("sentence not sent") end
    return Steps.pass("said")
end)

Steps.on("lk.talk.bubble", function(args)
    local V = LivingKnox and LivingKnox.SpeechView
    if V == nil then return Steps.fail("LivingKnox.SpeechView is not loaded on this client") end
    return function(ctx)
        local last = V.lastPieces
        if last ~= nil and last.text == args.text then return Steps.pass("bubble of " .. tostring(last.npc)) end
        if ctx.final then return Steps.fail("no bubble with '" .. tostring(args.text) .. "' here") end
        return nil
    end
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

return VS
