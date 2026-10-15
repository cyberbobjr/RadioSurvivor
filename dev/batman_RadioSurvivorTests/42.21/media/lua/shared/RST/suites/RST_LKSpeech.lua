--[[
lk.speech - Living Knox proximity speech of npc bodies (LK11-T04, LivingKnox.Speech on the authority and
LivingKnox.SpeechView for the display). Tags "world" and "server": a save named rstest*, with a target player
(t.ctx.player); the Living Knox option Enabled on. Solo: the authority chooses the line and the same machine shows the
bubble. Run: RST.run({ suite = "lk.speech", tags = "world" }). Dedicated server (E01-T19, campaign mp): the view is a
client file, absent from the server: the server makes the npc speak and the REQUESTER client checks its bubble with the
same checks through RST.Steps (RST_ViewSteps.lua: lk.speech.bubble, text translated on the client; the repeated
delivery is refused there), then every other connected client (LK11-T04: listener of the line, same bubble drawn).
On an MP client every test is SKIP.

What is read here (LK11-T09): the bubble is drawn by LivingKnox.SpeechView at each UI frame (OnPreUIDraw): its list
View.bubbles (body, text) and its draw trace (stats.drawn, lastDraw = { npc, text, x, y, player }, screen
coordinates). The tests wait until the bubble of the npc was drawn at least once and check that the point lies on the
screen; the look of the bubble (above the head, colour, fade) stays a visual check.
Every test removes its npc with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_ViewSteps"

RST.LKSpeech = RST.LKSpeech or {}

local function B() return LivingKnox and LivingKnox.Bodies end
local function S() return LivingKnox and LivingKnox.Speech end
local function V() return LivingKnox and LivingKnox.SpeechView end

local function measure(text)
    print("[LKS] measure " .. tostring(text))
end

local function onServer() return type(isServer) == "function" and isServer() end

local function needSolo(t)
    if onServer() then return end   -- E01-T19: the requester client checks the bubble
    if not (LivingKnox and LivingKnox.isAuthority() and LivingKnox.hasLocalPlayer()) then
        t:skip("solo or dedicated server only: the authority must display the bubble, or ask its requester client")
    end
end

local function onlinePlayer(user)
    local list = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p ~= nil and p:getUsername() == user then return p end
    end
    return nil
end

-- E01-T19: the bubble of npc id checked by the requester client (dedicated server). LK11-T04: then by the other
-- connected clients (second client of the launcher): each is among the listeners of the line (out.names,
-- LivingKnox.Speech.say) exactly when the hearing rule LivingKnox.Speech.hears holds for it at its place (MP campaign
-- of 2026-10-15: the second client stood inside the house, the npc outside, so the rule said "not heard" and the old
-- check, which assumed both clients within hearing, failed); every listening client must show the bubble. The
-- repeated delivery is checked by the requester only.
local function askBubble(t, args, names)
    RST.Steps.ask(t, "lk.speech.bubble", args, { target = "requester", timeoutMs = 10000, none = "skip" }, function(t2)
        local others = RST.Steps.others(t2)
        if #others == 0 then return end
        local z = B().find(args.npc)
        local listening = {}
        for _, user in ipairs(others) do
            local heard = false
            for _, n in ipairs(names or {}) do if n == user then heard = true end end
            local p = onlinePlayer(user)
            local rule = z ~= nil and p ~= nil and S().hears(z, p, args.range or S().RANGE) or false
            t2:eq(rule, heard, "client " .. user .. " among the listeners of " .. tostring(args.id)
                .. " as the hearing rule says")
            if heard then
                listening[#listening + 1] = user
            else
                t2:note("client " .. user .. " out of hearing of " .. tostring(args.npc) .. " (rule of Speech.hears)")
            end
        end
        if #listening == 0 then return end
        local copy = { npc = args.npc, id = args.id, line = args.line, text = args.text }
        RST.Steps.ask(t2, "lk.speech.bubble", copy, { target = listening, timeoutMs = 10000 })
    end)
end

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and S() ~= nil and (V() ~= nil or onServer()), "LivingKnox.Bodies, Speech or SpeechView is not loaded")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            S().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id, p
end

-- Text of the bubble currently posed over this body, or nil.
local function bubbleText(z)
    for _, b in ipairs(V().bubbles) do
        if b.z == z then return b.text end
    end
    return nil
end

-- Next step: the bubble of npc id was drawn at least once (OnPreUIDraw) at a point of the screen.
local function waitDrawn(t, id, text)
    local before = V().stats.drawn
    t:waitUntil(function()
        local d = V().lastDraw
        return V().stats.drawn > before and d ~= nil and d.npc == id and d.text == text
    end, 3000, function(t2)
        local d = V().lastDraw
        measure("drawn " .. tostring(d.text) .. " at " .. tostring(d.x) .. "," .. tostring(d.y))
        local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
        t2:ok(d.x >= 0 and d.x <= w and d.y >= 0 and d.y <= h,
            "bubble drawn off screen: " .. tostring(d.x) .. "," .. tostring(d.y) .. " (screen " .. w .. "x" .. h .. ")")
    end, "bubble never drawn")
end

RST.suite("lk.speech", { tags = { "world", "server" }, testTimeoutMs = 45000, timeoutMs = 150000 }, function(s)
    s.test("a bark shows a bubble over a created npc, once", function(t)
        needSolo(t)
        local id, p = spawnNpc(t, 2, 0)
        if onServer() then
            t:waitUntil(RST.LKHelpers.standing(id), RST.LKHelpers.STAND_MS, function(t2)
                local out, why = S().bark(id, "greet", { player = p })
                t2:ok(out ~= nil, "bark refused: " .. tostring(why))
                local again, why2 = S().bark(id, "greet", { player = p })
                t2:eq(nil, again, "second bark inside the gap")
                t2:eq("cooldown", why2)
                askBubble(t2, { npc = id, id = out.id, line = out.line, again = true }, out.names)
            end, "npc still on the floor")
            return
        end
        local shown = V().stats.shown
        local out, why = S().bark(id, "greet", { player = p })
        t:ok(out ~= nil, "bark refused: " .. tostring(why))
        local want = getText(LivingKnox.SpeechData.KEY_PREFIX .. out.line)
        local z = B().find(id)
        t:ok(z ~= nil, "npc body lost")
        t:eq(want, bubbleText(z), "bubble text of the npc body")
        t:eq(shown + 1, V().stats.shown, "bubbles shown")
        t:eq(false, V().receive({ id = out.id, npc = id, t = "again" }), "repeated delivery accepted")
        t:eq(shown + 1, V().stats.shown, "bubbles shown after a repeated delivery")
        local again, why2 = S().bark(id, "greet", { player = p })
        t:eq(nil, again, "second bark inside the gap")
        t:eq("cooldown", why2)
        waitDrawn(t, id, want)
    end)

    s.test("a written line (entry point of the notebook dialogue) shows on the npc", function(t)
        needSolo(t)
        local id = spawnNpc(t, 0, 2)
        local text = "Testing, one, two."
        if onServer() then
            t:waitUntil(RST.LKHelpers.standing(id), RST.LKHelpers.STAND_MS, function(t2)
                local out, why = S().say(id, text, { name = "Test" })
                t2:ok(out ~= nil, "say refused: " .. tostring(why))
                askBubble(t2, { npc = id, id = out.id, text = text }, out.names)
            end, "npc still on the floor")
            return
        end
        local out, why = S().say(id, text, { name = "Test" })
        t:ok(out ~= nil, "say refused: " .. tostring(why))
        local z = B().find(id)
        t:ok(z ~= nil, "npc body lost")
        t:eq(text, bubbleText(z), "bubble text of the npc body")
        waitDrawn(t, id, text)
    end)

    s.test("an npc too far away is heard by nobody", function(t)
        needSolo(t)
        local id = spawnNpc(t, 30, 0)
        local out, why = S().say(id, "Can anyone hear me?")
        t:eq(nil, out, "line sent to a player 30 squares away")
        t:eq("nobody hears", why)
    end)
end)

return RST.LKSpeech
