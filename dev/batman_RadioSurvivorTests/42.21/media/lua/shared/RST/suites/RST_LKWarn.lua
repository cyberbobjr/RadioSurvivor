--[[
lk.warn - warnings of Living Knox npcs to a player who comes near their home (LK11-T02,
server/LivingKnox/LK_Encounters.lua, behaviour "warn" of LK_Decisions.lua). Tags "world" and "server": the authority
only, on a save named rstest*, with a target player (t.ctx.player) standing INSIDE a house (the test groups get their
home on the player's square), a notebook character bound to the player (its attitude is set by the suite), the Living
Knox option Enabled on. Solo: RST.run({ suite = "lk.warn", tags = "world" }). Asynchronous run only (about 2 to 4
minutes). Multiplayer: final session.

What is done (the player is protected by god mode; once the fighter is armed, the suite moves the player to a free
square in view of it, 2 to 5 squares away, house squares first: the fighter warns only a player it SEES; stay still
until the suite moves you; every 10 s without progress, a "[LKW] measure waiting" line tells whether the fighter
perceives the player):
    - neutral group: a test group "neutrals" (one fighter; neutrals never strike first) with its home on the player's
      square; two thefts are recorded against the player (attitude "wary"); the fighter gets a loaded pistol. It
      warns the player (stage 1: line, weapon in hand), then gives the last warning (stage 2: weapon aimed), then
      holds (stage 3) WITHOUT ANY SHOT, for HOLD_MS; the suite moves the player 20 squares away: the fighter stands
      down ("Good. Keep your distance."); the player is moved back: the warning resumes at stage 3 ("You again?");
    - first-strike group: a test group "raiders" (one fighter) made "wary" by three gifts, loaded pistol: after the
      two warnings, ONE warning shot (one round taken out of the pistol, no damage, no combat order).
Every phase prints "[LKW] measure ..." lines; the user checks the speech bubbles, the gestures (weapon in hand, then
aimed) and hears the warning shot. Cleanup (t:defer): bodies removed, test groups removed, god mode restored, player
moved back.
E01-T16 (LK11-T02): the other clients show the warning lines they heard (lk.speech.seen through
RST.PeerChecks.checkSpeech, each other client among the listeners) and, on a dedicated server, every client plays the
warning shot once (lk.combat.view, RST_ViewSteps.lua); every client also shows the pistol of the fighter in hand at the
first warning and aimed (node LKActorAimHandgun) at the last one (lk.weapon.state, RST_ViewSteps.lua).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecks"
require "RST/RST_ViewSteps"

local K = RST.LKHelpers
local measure = K.measurer("[LKW]")

local BODIES_MS = 60000     -- materialization of the fighter
local STAGE_MS = 40000      -- each stage of the warning
local HOLD_MS = 12000       -- stage 3 held this long: no shot from a neutral group
local AWAY = 20             -- squares: the player is moved this far (out of the home zone and of the fighter's)
local GUN = "Base.Pistol"

local function LK() return LivingKnox end

-- LK11-T02 (E01-T16): shots played by every connected client (RST_ViewSteps.lua: lk.combat.view); a dedicated server
-- only (solo: the warning shot is checked on the authority), then after(t2).
local function viewStep(t, args, after)
    if not (type(isServer) == "function" and isServer()) then return after(t) end
    RST.Steps.ask(t, "lk.combat.view", args, { target = "all", timeoutMs = 10000 }, after)
end
local function En() return LivingKnox.Encounters end

local function memberNpc(gid, mid)
    local g = LK().Groups.get(gid)
    local m = g and g.members[mid] or nil
    return m and m.npc or nil
end

local function encOf(gid, name)
    return En().get(gid, name)
end

local function describe(gid, name, npc)
    local e = encOf(gid, name)
    local st = LK().Decisions.get(npc)
    local seen = LK().Senses.perceivedPlayer(npc, name)
    return string.format("stage %s (peak %s, told %s/%s, shot %s), behaviour %s, gesture %s, rounds %d, player %s",
        tostring(e and e.stage), tostring(e and e.peak), tostring(e and e.told1), tostring(e and e.told2),
        tostring(e and e.shot), tostring(st and st.b), tostring(LK().Anim.gestureOf(npc)),
        LK().Ammo.loaded(LK().Bodies.find(npc), GUN),
        seen and string.format("perceived (seen %s, %.1f squares)", tostring(seen.s), seen.d or -1) or "not perceived")
end

-- Condition cond wrapped: a "waiting" measure every 10 s while it is false (what the fighter perceives).
local function watched(gid, name, npc, cond)
    local last = getTimestampMs()
    return function()
        if cond() then return true end
        if getTimestampMs() - last >= 10000 then
            last = getTimestampMs()
            measure("waiting: " .. describe(gid, name, npc))
        end
        return false
    end
end

-- Test group of type gtype with its home on the player's square, one fighter of profile; facts recorded against the
-- player (attitude). Returns the group id, or nil and a reason.
local function makeGroup(t, p, gtype, profile, fact, times)
    local E = LK()
    local G = E.Groups
    local sq = p:getCurrentSquare()
    if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
    local key = E.Hostility.keyOf(p)
    if key == nil then t:skip("no notebook character bound to the player (attitude needs it)") end
    -- An invisible or ghost player is never perceived (LK_Senses, like the engine): no warning can start.
    if p:isInvisible() or p:isGhostMode() then
        t:skip("the player is invisible or in ghost mode (debug cheats): npcs cannot see him")
    end
    local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    local g = assert(G.create({ type = gtype, name = "RST warn " .. gtype, day = G.today(), home = home }))
    local gid = g.id
    if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
    K.hideOtherPlayersFrom(t, gid, p:getUsername())   -- a second MP client in the house is not the warned player
    assert(G.addMember(gid, { role = "fighter", profile = profile, female = false, day = G.today() }))
    assert(G.setLeader(gid, "m-1", G.today()))
    t:defer(function()
        local npc = memberNpc(gid, "m-1")
        if E.Alert then E.Alert.forget(gid) end
        En().forgetGroup(gid)
        if npc ~= nil then E.Combat.disengage(npc, "suite lk.warn over") end
        G.remove(gid)
        if npc ~= nil then
            E.Directives.forget(npc)
            E.Bodies.despawn(npc, true)
        end
    end, "remove group " .. gid)
    for _ = 1, times do
        local res, why = E.Hostility.record(gid, key, fact, { witnessed = true })
        t:ok(res ~= nil, "fact " .. fact .. " not recorded: " .. tostring(why))
    end
    t:eq("wary", E.Hostility.get(gid, key).level, "attitude of the test group")
    t:note("group " .. gid .. " (" .. gtype .. ") home " .. home.x .. "," .. home.y .. "," .. home.z)
    return gid
end

-- Fighter materialized and standing, armed with a loaded pistol; then suite(t2, npc).
local function armedFighter(t, gid, suite)
    local E = LK()
    local npc
    t:waitUntil(function()
        npc = memberNpc(gid, "m-1")
        return npc ~= nil and E.Bodies.find(npc) ~= nil and K.standing(npc)()
    end, BODIES_MS, function(t2)
        local body = E.Bodies.find(npc)
        t2:ok(E.Equipment.setWeapon(npc, GUN), "pistol not given to the fighter")
        E.Ammo.give(npc, GUN, 15, 0)
        E.Ammo.reload(npc, body, GUN)
        measure("fighter " .. npc .. " armed: " .. E.Ammo.loaded(body, GUN) .. " round(s) in the pistol")
        -- The fighter warns only a player it sees: the player is moved in its view (it may have gone behind a door).
        local dx, dy = K.squareInView(body, 2, 5)
        if dx == nil then t2:skip("no free square in view of the fighter at 2 to 5 squares") end
        local x, y, z = math.floor(body:getX()) + dx, math.floor(body:getY()) + dy, math.floor(body:getZ())
        measure(string.format("player moved in view of the fighter: %d,%d,%d", x, y, z))
        RST.Fixtures.movePlayer(t2, RST.Fixtures.player(t2), x + 0.5, y + 0.5, z, function(t3)
            suite(t3, npc)
        end)
    end, "fighter not materialized and standing")
end

RST.suite("lk.warn", { tags = { "world", "server" }, testTimeoutMs = 400000, timeoutMs = 900000 }, function(s)
    s.test("neutral group: two warnings, weapon aimed, no shot; stands down and resumes", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Encounters ~= nil and E.Decisions ~= nil, "LivingKnox.Encounters (LK11-T02) is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local name = p:getUsername()
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "god mode restored")
        local gid = makeGroup(t, p, "neutrals", "hunter", "theft", 2)
        local said = RST.PeerChecks.recordSpeech(t)   -- LK11-T02: the warnings heard by the other clients
        local shots0, cshots0 = En().stats.shots, E.Combat.stats.shots
        armedFighter(t, gid, function(t2, npc)
            local rounds = E.Ammo.loaded(E.Bodies.find(npc), GUN)
            t2:waitUntil(watched(gid, name, npc, function()
                local e = encOf(gid, name)
                return e ~= nil and e.stage >= 1 and e.told1 and E.Anim.gestureOf(npc) == "guard"
            end), STAGE_MS, function(t3)
                measure("stage 1: " .. describe(gid, name, npc))
                -- LK11-T02 (E01-T16): the weapon in hand at the first warning, seen by every client.
                local weaponStep = function(tw, extra, after)
                    if not isServer() then return after(tw) end
                    local spec = E.Equipment.spec(GUN)
                    local a = { npc = npc, slot = spec and spec.l or "Holster Right", item = GUN, mode = "hand" }
                    for k, v in pairs(extra) do a[k] = v end
                    RST.Steps.ask(tw, "lk.weapon.state", a, { target = "all", timeoutMs = 5000 }, after)
                end
                weaponStep(t3, { label = "first warning" }, function(t3b) t3 = t3b
                t3:waitUntil(function()
                    local e = encOf(gid, name)
                    return e ~= nil and e.stage == 3 and e.told2 and E.Anim.gestureOf(npc) == "aim"
                end, STAGE_MS, function(t4)
                    measure("stage 3: " .. describe(gid, name, npc))
                    -- LK11-T02 (E01-T16): the pistol aimed at the last warning, seen by every client.
                    weaponStep(t4, { label = "last warning", weapon = "handgun", node = "LKActorAimHandgun" },
                        function(t4b) t4 = t4b
                    local since = getTimestampMs()
                    t4:waitUntil(function() return getTimestampMs() - since >= HOLD_MS end, HOLD_MS + 5000,
                        function(t5)
                            measure("held: " .. describe(gid, name, npc) .. string.format(", shots %d, combat shots %d",
                                En().stats.shots - shots0, E.Combat.stats.shots - cshots0))
                            t5:eq(0, En().stats.shots - shots0, "warning shot from a neutral group")
                            t5:eq(0, E.Combat.stats.shots - cshots0, "combat shot from a neutral group")
                            t5:ok(E.Combat.get(npc) == nil, "neutral fighter engaged without provocation")
                            t5:eq(rounds, E.Ammo.loaded(E.Bodies.find(npc), GUN), "round taken out of the pistol")
                            local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
                            local down0, again0 = En().stats.stoodDown, En().stats.resumed
                            RST.Fixtures.movePlayer(t5, p, x + AWAY + 0.5, y + 0.5, z, function(t6)
                                t6:waitUntil(function()
                                    local e = encOf(gid, name)
                                    return e ~= nil and e.stage == 0 and En().stats.stoodDown > down0
                                end, STAGE_MS, function(t7)
                                    measure("stood down: " .. describe(gid, name, npc))
                                    RST.Fixtures.movePlayer(t7, p, x + 0.5, y + 0.5, z, function(t8)
                                        t8:waitUntil(function()
                                            local e = encOf(gid, name)
                                            return e ~= nil and e.stage == 3 and En().stats.resumed > again0
                                        end, STAGE_MS, function(t9)
                                            measure("resumed: " .. describe(gid, name, npc))
                                            t9:eq(0, En().stats.shots - shots0, "warning shot after the resume")
                                            -- LK11-T02 (E01-T16): the same warning lines reached the other clients.
                                            RST.PeerChecks.checkSpeech(t9, said)
                                        end, "warning did not resume at stage 3")
                                    end)
                                end, "fighter did not stand down")
                            end)
                        end, "hold not measured")
                    end)
                end, "no last warning with the weapon aimed")
                end)
            end, "no first warning with the weapon in hand")
        end)
    end)

    s.test("first-strike group: one warning shot after two warnings, no damage", function(t)
        local E = LK()
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local name = p:getUsername()
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "god mode restored")
        local gid = makeGroup(t, p, "raiders", "gunman", "gift", 3)
        local said = RST.PeerChecks.recordSpeech(t)   -- LK11-T02: the warnings heard by the other clients
        local shots0, cshots0 = En().stats.shots, E.Combat.stats.shots
        local health0 = p:getBodyDamage():getHealth()
        armedFighter(t, gid, function(t2a, npc)
            local rounds = E.Ammo.loaded(E.Bodies.find(npc), GUN)
            local viewKey = gid .. "-" .. tostring(getTimestampMs())
            -- LK11-T02 (E01-T16): shots played by every client counted from here (dedicated server only).
            viewStep(t2a, { phase = "begin", key = viewKey }, function(t2)
                t2:waitUntil(watched(gid, name, npc, function()
                    local e = encOf(gid, name)
                    return e ~= nil and e.shot
                end), 3 * STAGE_MS, function(t3)
                    measure("warning shot: " .. describe(gid, name, npc)
                        .. string.format(", shots %d, health %.1f -> %.1f", En().stats.shots - shots0, health0,
                        p:getBodyDamage():getHealth()))
                    local e = encOf(gid, name)
                    t3:ok(e.told1 and e.told2, "warning shot before the two warnings were heard")
                    t3:eq(1, En().stats.shots - shots0, "warning shots")
                    t3:eq(0, E.Combat.stats.shots - cshots0, "combat shots")
                    t3:eq(rounds - 1, E.Ammo.loaded(E.Bodies.find(npc), GUN), "rounds after the warning shot")
                    t3:ok(E.Combat.get(npc) == nil, "fighter engaged without provocation")
                    t3:ok(p:getBodyDamage():getHealth() >= health0, "player hurt by a warning shot")
                    -- LK11-T02 (E01-T16): the warning shot played once (sound and flash) and the same warning lines
                    -- shown by the other clients.
                    viewStep(t3, { phase = "end", key = viewKey, shots = 1 }, function(t4)
                        RST.PeerChecks.checkSpeech(t4, said)
                    end)
                end, "no warning shot")
            end)
        end)
    end)
end)
