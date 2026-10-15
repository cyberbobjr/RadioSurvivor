--[[
rs.mission.clear - mission template "clear" (E11-T04, server/RadioSurvivor/RS_MissionClear.lua) on the real metagrid
and the real world: a building drawn around the player, a number of kills from the zombie density of the lot headers,
a counting circle centred on the building; three real zombies spawned in the circle next to the player: a lethal bat
hit of the player counts once (a second count of the same zombie changes nothing), a death without an attributed
killer (Kill(nil)) does not count, the second lethal hit reaches the shortened target: the mission stays active "to
report" (E11-T13; a report before was refused) until the report to the requester (RS_Missions.spoken), then the
common engine closes it in success.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
player is moved, zombies are created and killed: test saves "rstest*" only). Asynchronous run (RST.start /
RST.server). The mission lives in an in-memory state built by the test (requester fiche, character): no notebook
state, no reward item; its target is lowered to 2 after creation. The real event subscribers of the template only
watch the notebook state, so this suite adds its own OnHitZombie / OnZombieDead subscribers on the template functions
(Clear.noteHit, Clear.count) for its state, removed at the end. The player is in god mode during the test.
Cleanup: subscribers removed, zombies still alive removed, corpses of the test removed, player back.
Site of the test (never a SKIP for want of a populated building): the real draw of the template (Clear.offer, a
building around the player) is tried SITE_DRAWS times (new seed each time); when every drawn building is under
minDensity (the spawn point of the test server lies in a quiet part of Muldraugh), the same draw is made once more
with a test copy of the catalogue entry whose minDensity is 0 (noted: N then comes from the measured density). The
suite spawns its own zombies in the circle, so the density only sets N. No building at all: FAIL.
Outside the game: tests/test_mission_clear.py (metagrid density, zombie and player doubles).
Solo only (SKIP elsewhere), first test of the suite: the player's own actions on a real clear mission of a Living Knox
npc fiche in the real notebook state, counted by the real subscribers of the template: lethal bat hit (melee), lethal
pistol hit (firearm), a zombie run over with the player at the wheel (engine path IsoGameCharacter.Hit(BaseVehicle..)),
a zombie burnt without attacker (not counted); then the notebook shows "to report" and the Report button, the Report
command closes the mission in success, the Claim button appears and the Claim command puts the reward in the
inventory. The counting circle is moved onto the player so that the requester stays at hand (tags server, world).

rs.mission.clearcount - E11-T04 "decompte coherent entre deux participants ; aucun double compte" with the second
client of the MP campaign (E01-T16): the same in-memory clear mission accepted by the requester (char1) and by the
server copy of the second client (char2); a lethal hit of the requester in the circle counts for char1, a lethal hit
of the requester on a zombie OUTSIDE the circle (spawned beyond its radius, on a loaded square) counts for nobody, a
lethal hit of the second client counts for char2 and reaches the target, a kill after the target counts no more; the
notebook projections of both participants show the same k / N and the same parts. Tags "server" and "world". Selected
by the campaign entry "rs.mission" (not by the filter "rs.mission.clear"). No second client online (solo, one
client): SKIP with the reason; no loaded square outside the circle: FAIL.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_RSHelpers"

local F = RST.Fixtures
local MARK = "RST_ClearZombie"
local LETHAL = 100.0
local SITE_DRAWS = 12
local DEATH_MS = 5000

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionClear is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local Clear = require "RadioSurvivor/RS_MissionClear"
    if type(M) ~= "table" or type(Clear) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    return M, Clear, require "RadioSurvivor/RS_Config"
end

-- Offer of the template for npc around body: SITE_DRAWS real draws (a new seed each: missionCount), then one with a
-- test copy of the catalogue entry without minimum density. Returns offer (nil: FAIL already asserted), how.
local function drawSite(t, Clear, c, npc, body)
    for i = 1, SITE_DRAWS do
        Clear.resetForTests()
        npc.missionCount = i - 1
        local offer = Clear.offer(c, npc, nil, body)
        if offer then return offer, "drawn building (draw " .. i .. ")" end
    end
    local relaxed = {}
    for k, v in pairs(c) do relaxed[k] = v end
    relaxed.minDensity = 0
    Clear.resetForTests()
    npc.missionCount = SITE_DRAWS
    local offer = Clear.offer(relaxed, npc, nil, body)
    t:ok(offer ~= nil, "no building at all around the player (" .. c.minDistance .. "-" .. c.maxDistance
        .. " tiles, metagrid): the clear template has no place here")
    t:note("every one of " .. SITE_DRAWS .. " drawn buildings was under minDensity " .. c.minDensity
        .. ": site drawn again without minimum density (the suite spawns its own zombies)")
    return offer, "drawn building without minimum density"
end

-- Clear mission accepted by char1 (the requester) in an in-memory state: { M, Clear, c, p, state, npc, m, store }.
local function acceptedMission(t)
    local M, Clear, Config = modules(t)
    local c = Config.Missions.clear
    local p = F.player(t)
    if not p then t:skip("no target player") end
    local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
    local npc = { id = "rst-clear", incarnation = "rst-clear" }
    state.npcs[npc.id] = npc
    state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
    local ox, oy = p:getX(), p:getY()
    local body = { getX = function() return ox end, getY = function() return oy end }
    local offer, how = drawSite(t, Clear, c, npc, body)
    t:eq("clear", offer.kind)
    t:ok(offer.kills >= c.minKills and offer.kills <= c.maxKills, "target out of bounds: " .. tostring(offer.kills))
    for _, clue in ipairs(offer.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
    local m = M.create(state, npc, "char1", c.id)
    t:ok(m ~= nil and m.template == "clear", "clear mission not created")
    t:eq(offer.kills, m.target, "target of the offer")
    t:eq(true, M.accept(state, m, "char1", "Tester"))
    t:note("site: " .. how)
    return { M = M, Clear = Clear, c = c, p = p, state = state, npc = npc, m = m,
        store = { data = state, save = function() return true end } }
end

-- Test subscribers on the template functions for an in-memory state (the real ones watch the notebook state only).
local function subscribe(t, Clear, state, mine, resolve, credited)
    local function onHit(z, wielder, _, weapon) if mine[z] then Clear.noteHit(z, wielder, weapon) end end
    local function onDead(z)
        if mine[z] then credited[#credited + 1] = Clear.count(state, z, resolve) ~= nil end
    end
    Events.OnHitZombie.Add(onHit)
    Events.OnZombieDead.Add(onDead)
    t:defer(function() Events.OnHitZombie.Remove(onHit); Events.OnZombieDead.Remove(onDead) end,
        "remove the test subscribers")
end

-- Corpses of the test (ModData copied from the zombie to its body) around (x, y, z).
local function removeCorpses(x, y, z)
    local cell = getCell()
    for dy = -4, 4 do
        for dx = -4, 4 do
            local sq = cell and cell:getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            for i = (list and list:size() or 0) - 1, 0, -1 do
                local o = list:get(i)
                if instanceof(o, "IsoDeadBody") and o:hasModData() and o:getModData()[MARK] then
                    sq:removeCorpse(o, false)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- solo: real notebook, player actions (E11-T04)

local PISTOL, CAR = "Base.Pistol", "Base.CarNormal"
local BURN_MS = 60000

local function shownRow(id)
    for _, row in ipairs(RS_CarnetClient and RS_CarnetClient.snapshot.missions or {}) do
        if row.id == id then return row end
    end
    return nil
end

local function countOf(inv, fullType)
    return inv:getItemsFromFullType(fullType):size()
end

-- Free outdoor square for a car, 3 to 10 squares from the player (the car is removed at the end), or nil.
local function spawnCar(t, p)
    for r = 3, 10 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = getCell():getGridSquare(math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, 0)
                    if sq ~= nil and sq:isOutside() and sq:isFree(false) and sq:getBuilding() == nil then
                        local v = addVehicleDebug(CAR, IsoDirections.E, nil, sq)
                        if v ~= nil and v:getSqlId() ~= -1 then
                            t:defer(function() v:permanentlyRemove() end, "remove the test car")
                            return v, sq
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Notebook window on the Missions page, mission id selected and refreshed; closed at the end if it was closed.
local function missionPage(t, id)
    local Notebook = require "RadioSurvivor/RS_Notebook"
    local Client = RS_CarnetClient
    local wasOpen = Client.window ~= nil and Client.window:isVisible()
    if not wasOpen then
        Notebook.toggle()
        t:defer(function()
            if Client.window and Client.window:isVisible() then Notebook.toggle() end
        end, "close the notebook")
    end
    local w = Client.window
    w:changeTab("Missions")
    w.selectedId = id
    w:refresh()
    return w
end

-- Solo E11-T04: a real clear mission of a Living Knox npc fiche in the real notebook state, counted by the real
-- subscribers of the template (Clear.onHitZombie / Clear.onZombieDead, binding RS_CarnetServer.bound), accepted,
-- reported and claimed through the real notebook commands (RS_CarnetClient.send). The counting circle is moved onto the
-- player (radius zoneRadius) so that the requester stays next to the player for the report and the claim: the place
-- draw and the circle of the building are covered by the first test. Kills: lethal bat hit (melee), lethal pistol hit
-- (firearm), a zombie run over through the engine path of a car hit (IsoGameCharacter.Hit(BaseVehicle, ...) with the
-- player at the wheel: onHitByVehicle sets the driver as attacker and Kill(driver), IsoGameCharacter.java:11662-11720,
-- no OnHitZombie), and a zombie set on fire without attacker (not counted).
local function soloPlay(t)
    local R = RST.RSHelpers
    R.solo(t)
    local M, Clear, Config = modules(t)
    local Server = R.notebook(t)
    local p = F.player(t)
    t:ok(p ~= nil, "no target player")
    local cid = R.character(t, p)
    local c = Config.Missions.clear
    R.god(t, p)
    R.npcWithFiche(t, p, 2, function(t2, id, fiche, body)
        local data = Server.store.data
        for _, other in pairs(data.missions) do
            if other.template == "clear" and other.state == "active" and other.participants[cid] then
                t2:note("another active clear mission of the character: " .. tostring(other.id))
            end
        end
        local relaxed = {}
        for k, v in pairs(c) do relaxed[k] = v end
        relaxed.minDensity = 0
        Clear.resetForTests()
        local terms = Clear.offer(relaxed, fiche, nil, body)
        t2:ok(terms ~= nil, "no clear offer for " .. id .. " (no building around the player)")
        local m = M.create(data, fiche, cid, c.id, terms)
        t2:ok(m ~= nil and m.template == "clear", "clear mission not created")
        local record = data.characters[cid]
        local hadContact = record.contacts[fiche.id] ~= nil
        if not hadContact then
            record.contacts[fiche.id] = { history = {}, note = "", trust = "Cautious", trend = "Stable",
                stage = "stranger", exchanges = 0 }
        end
        record.knownMissions[m.id] = true
        local inv = p:getInventory()
        local rewardBefore = countOf(inv, m.rewardType)
        t2:defer(function()
            data.missions[m.id] = nil
            data.outcomes[m.id .. "-" .. cid .. "-result"] = nil
            for _, rec in pairs(data.characters) do rec.knownMissions[m.id] = nil end
            if not hadContact then record.contacts[fiche.id] = nil end
            if fiche.mission == m.id then fiche.mission = nil end
            local list = inv:getItemsFromFullType(m.rewardType)
            for i = list:size() - 1, rewardBefore, -1 do inv:Remove(list:get(i)) end
            Server.publish()
        end, "remove mission " .. m.id .. " and its reward")
        local px, py = math.floor(p:getX()), math.floor(p:getY())
        m.mapZone = { x = px, y = py, r = c.zoneRadius }
        m.target = 3
        t2:note("requester " .. id .. ", circle moved onto the player " .. px .. "," .. py .. " r " .. c.zoneRadius
            .. ", target lowered to 3")
        Server.publish()
        RS_CarnetClient.send("accept", { mission = m.id, revision = m.revision })
        t2:waitUntil(function()
            local r = shownRow(m.id)
            return r ~= nil and r.state == "active" and r.engaged
        end, 5000, function(t3)
            local zs = {}
            local function spawn(x, y)
                local list = addZombiesInOutfit(x, y, 0, 1, nil, 50)
                t3:ok(list ~= nil and list:size() == 1, "zombie not created at " .. x .. "," .. y)
                local z = list:get(0)
                z:getModData()[MARK] = true
                zs[#zs + 1] = { z = z, x = x, y = y }
                return z
            end
            t3:defer(function()
                for _, e in ipairs(zs) do
                    if not e.z:isDead() then e.z:removeFromWorld(); e.z:removeFromSquare() end
                    removeCorpses(e.x, e.y, 0)
                end
            end, "remove the zombies and corpses of the test")
            -- 1. Melee: lethal bat hit of the player.
            local melee = spawn(px - 3, py)
            melee:Hit(instanceItem("Base.BaseballBat"), p, LETHAL, false, 1.0)
            t3:waitUntil(function() return melee:isDead() end, DEATH_MS, function(t4)
                t4:eq({ 1, 1 }, { m.kills, m.tally[cid] }, "melee kill (bat) counted")
                -- 2. Firearm: lethal pistol hit of the player.
                local shot = spawn(px - 3, py + 1)
                shot:Hit(instanceItem(PISTOL), p, LETHAL, false, 1.0)
                t4:waitUntil(function() return shot:isDead() end, DEATH_MS, function(t5)
                    t5:eq({ 2, 2 }, { m.kills, m.tally[cid] }, "firearm kill (pistol) counted")
                    -- 3. Fire: a weakened zombie set on fire dies without an attacker: not counted.
                    local burnt = spawn(px - 4, py - 2)
                    burnt:setHealth(0.05)
                    burnt:SetOnFire()
                    t5:waitUntil(function() return burnt:isDead() end, BURN_MS, function(t6)
                        t6:sleep(1500, function(t7)
                            t7:note("burnt zombie dead, attacked by " .. tostring(burnt:getAttackedBy()))
                            t7:eq(2, m.kills, "burnt zombie without attacker counted")
                            t7:eq(nil, burnt:getModData()[Clear.MARK], "burnt zombie marked as counted")
                            -- 4. Car: the player at the wheel runs a zombie over (engine path of a car hit).
                            local v = spawnCar(t7, p)
                            t7:ok(v ~= nil, "no free outdoor square for a car within 10 squares of the player")
                            t7:ok(v:enter(0, p), "the player could not take the wheel")
                            t7:defer(function() if p:getVehicle() ~= nil then v:exit(p) end end, "leave the car")
                            t7:ok(rawequal(v:getDriver(), p), "the player is not the driver")
                            local vx, vy = math.floor(v:getX()), math.floor(v:getY())
                            local run = spawn(vx + 3, vy)
                            run:setHealth(0.01)
                            local dealt = run:Hit(v, 60.0, false, -1.0, 0.0, false, 0.0, 0.0)
                            t7:waitUntil(function() return run:isDead() end, DEATH_MS, function(t8)
                                t8:note("car hit: damage " .. tostring(dealt) .. ", attacked by the player "
                                    .. tostring(rawequal(run:getAttackedBy(), p)))
                                t8:eq({ 3, 3 }, { m.kills, m.tally[cid] }, "car kill of the driver counted")
                                v:exit(p)
                                local bx, by = body:getX(), body:getY()
                                F.movePlayer(t8, p, bx - 1, by, 0, function(t9)
                                    t9:waitUntil(function()
                                        local r = shownRow(m.id)
                                        return r ~= nil and r.toReport == true and r.near == true
                                    end, 5000, function(t10)
                                        local r = shownRow(m.id)
                                        t10:eq({ "active", 3, 3 }, { r.state, r.kills, r.target }, "notebook row")
                                        local w = missionPage(t10, m.id)
                                        local toReport = getText("IGUI_RS_State_toReport")
                                        t10:ok(string.find(w.detail.text or "", toReport, 1, true) ~= nil,
                                            "Missions page without '" .. toReport .. "'")
                                        t10:eq(true, w.report:isVisible(), "Report button shown")
                                        t10:eq(false, w.claim:isVisible(), "Claim button before the report")
                                        RS_CarnetClient.send("report", { mission = m.id, revision = r.revision })
                                        t10:waitUntil(function()
                                            local r2 = shownRow(m.id)
                                            return r2 ~= nil and r2.state == "success"
                                        end, 5000, function(t11)
                                            w:refresh()
                                            local success = getText("IGUI_RS_State_success")
                                            t11:ok(string.find(w.detail.text or "", success, 1, true) ~= nil,
                                                "Missions page without '" .. success .. "'")
                                            t11:eq(true, w.claim:isVisible(), "Claim button after the success")
                                            t11:eq("mission.success", data.outcomes[m.id .. "-" .. cid .. "-result"]
                                                and data.outcomes[m.id .. "-" .. cid .. "-result"].action)
                                            RS_CarnetClient.send("claim",
                                                { mission = m.id, revision = shownRow(m.id).revision })
                                            t11:waitUntil(function()
                                                local r3 = shownRow(m.id)
                                                return r3 ~= nil and r3.claimedName ~= ""
                                            end, 5000, function(t12)
                                                t12:eq(m.rewardCount, countOf(inv, m.rewardType) - rewardBefore,
                                                    m.rewardType .. " claimed into the inventory")
                                                t12:note("notebook: to report, Report, success, Claim, "
                                                    .. m.rewardCount .. " x " .. m.rewardType)
                                                t12:sleep(2000, function() end)
                                            end, "reward not claimed through the notebook command")
                                        end, "mission not in success after the notebook Report command")
                                    end, "notebook row never 'to report' near the requester")
                                end)
                            end, "zombie not dead after the car hit")
                        end)
                    end, "burning zombie not dead")
                end, "zombie not dead after a lethal pistol hit")
            end, "zombie not dead after a lethal bat hit")
        end, "mission not accepted through the notebook command")
    end)
end

RST.suite("rs.mission.clear", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 400000 }, function(s)
    s.test("solo: melee, firearm and car kills counted, burnt zombie not, report and claim in the notebook", soloPlay,
        { timeoutMs = 180000 })

    s.test("kills of a participant in the circle counted once, an unattributed death ignored, report after the target",
            function(t)
        local a = acceptedMission(t)
        local M, Clear, p, state, m, store = a.M, a.Clear, a.p, a.state, a.m, a.store
        t:eq({ false, "Zone" }, { M.spoken(store, m, p, "char1") }, "E11-T13: report before the target accepted")
        t:note("place " .. m.place .. " " .. m.siteKey .. ", circle " .. m.mapZone.x .. "," .. m.mapZone.y .. " r "
            .. m.mapZone.r .. ", target " .. m.target .. " (lowered to 2 for the test)")
        m.target = 2
        local function resolve(player) if rawequal(player, p) then return "char1" end end
        local mine, credited = {}, {}
        subscribe(t, Clear, state, mine, resolve, credited)
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local cx, cy = m.mapZone.x, m.mapZone.y
        -- Solo: the move does not wait for the squares (RST.Fixtures waits on a server only): wait for the spawn square.
        local function loaded(tt, cont)
            if not F.WAIT_LOADED then return cont(tt) end
            F.waitSquare(tt, cx + 2, cy, 0, nil, cont)
        end
        F.movePlayer(t, p, cx + 0.5, cy + 0.5, 0, function(t1) loaded(t1, function(t2)
            local list = addZombiesInOutfit(cx + 2, cy, 0, 3, nil, 50)
            t2:ok(list ~= nil and list:size() == 3, "zombies not created")
            local zs = {}
            for i = 0, list:size() - 1 do
                local z = list:get(i)
                z:getModData()[MARK] = true
                mine[z], zs[#zs + 1] = true, z
            end
            t2:defer(function()
                for _, z in ipairs(zs) do
                    if not z:isDead() then z:removeFromWorld(); z:removeFromSquare() end
                end
                removeCorpses(cx + 2, cy, 0)
            end, "remove the zombies and corpses of the test")
            local bat = instanceItem("Base.BaseballBat")
            -- 1. Lethal hit of the participant: counted once.
            zs[1]:Hit(bat, p, LETHAL, false, 1.0)
            t2:waitUntil(function() return zs[1]:isDead() and #credited >= 1 end, 5000, function(t3)
                t3:eq(1, m.kills, "first kill")
                t3:eq(1, m.tally.char1, "part of the participant")
                t3:eq(nil, Clear.count(state, zs[1], resolve), "same zombie counted again")
                t3:eq(1, m.kills, "count after a second death event")
                -- 2. Death without an attributed killer.
                zs[2]:Kill(nil)
                t3:waitUntil(function() return zs[2]:isDead() and #credited >= 2 end, 5000, function(t4)
                    t4:eq(false, credited[2], "unattributed death counted")
                    t4:eq(1, m.kills, "count after an unattributed death")
                    -- 3. Second lethal hit: target reached, success by the common engine.
                    zs[3]:Hit(bat, p, LETHAL, false, 1.0)
                    t4:waitUntil(function() return zs[3]:isDead() and #credited >= 3 end, 5000, function(t5)
                        t5:eq(2, m.kills, "second kill")
                        t5:eq({ "active", true }, { m.state, M.reportReady(m) }, "E11-T13: target met, report expected")
                        t5:eq({ true }, { M.spoken(store, m, p, "char1") }, "report to the requester")
                        t5:eq("success", m.state)
                        t5:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
                    end, "third zombie not dead")
                end, "second zombie not dead")
            end, "first zombie not dead after a lethal hit")
        end) end)
    end)
end)

-- A loaded square just outside the circle of m (radius + 2 .. radius + 8, four directions), or nil.
local function outsideSquare(m, z)
    local zone = m.mapZone
    for extra = 2, 8 do
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local x, y = zone.x + d[1] * (zone.r + extra), zone.y + d[2] * (zone.r + extra)
            local sq = getCell():getGridSquare(x, y, z)
            if sq ~= nil then return x, y end
        end
    end
    return nil
end

local function zombiesAt(t, mine, x, y, n)
    local list = addZombiesInOutfit(x, y, 0, n, nil, 50)
    t:ok(list ~= nil and list:size() == n, "zombies not created at " .. x .. "," .. y)
    local out = {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        z:getModData()[MARK] = true
        mine[z], out[#out + 1] = true, z
    end
    t:defer(function()
        for _, z in ipairs(out) do
            if not z:isDead() then z:removeFromWorld(); z:removeFromSquare() end
        end
        removeCorpses(x, y, 0)
    end, "remove the zombies and corpses at " .. x .. "," .. y)
    return out
end

-- k / N and parts as the notebook shows them to a participant.
local function shown(M, m, character)
    local row = M.projection(m, character)
    return { engaged = row.engaged, kills = row.kills, target = row.target, tally = row.tally }
end

RST.suite("rs.mission.clearcount", { tags = { "server", "world" }, testTimeoutMs = 90000 }, function(s)
    s.test("two participants share one count k / N, a kill outside the circle counts for nobody (E11-T04)", function(t)
        local others = RST.Steps.others(t)
        local peer = others[1] and RST.Steps.playerOf(others[1]) or nil
        if peer == nil then
            t:skip("no second client online (solo or one client): two participants need autoclient.py --mp --clients 2")
        end
        local a = acceptedMission(t)
        local M, Clear, p, state, m = a.M, a.Clear, a.p, a.state, a.m
        local peerName = others[1]
        state.characters.char2 = { name = peerName, contacts = {}, knownMissions = {} }
        m.invited.char2 = true
        t:eq(true, M.accept(state, m, "char2", peerName), "second participant not accepted")
        m.target = 2
        local function resolve(player)
            if rawequal(player, p) then return "char1" end
            if rawequal(player, peer) then return "char2" end
        end
        local mine, credited = {}, {}
        subscribe(t, Clear, state, mine, resolve, credited)
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local cx, cy = m.mapZone.x, m.mapZone.y
        F.movePlayer(t, p, cx + 0.5, cy + 0.5, 0, function(t2)
            local ox, oy = outsideSquare(m, 0)
            t2:ok(ox ~= nil, "no loaded square just outside the circle (radius " .. m.mapZone.r .. ") around "
                .. cx .. "," .. cy)
            local inside = zombiesAt(t2, mine, cx + 2, cy, 2)
            local outside = zombiesAt(t2, mine, ox, oy, 1)[1]
            local late = zombiesAt(t2, mine, cx - 2, cy, 1)[1]
            t2:note("circle " .. cx .. "," .. cy .. " r " .. m.mapZone.r .. ", zombie outside at " .. ox .. "," .. oy
                .. ", second participant " .. peerName)
            local bat = instanceItem("Base.BaseballBat")
            local function dies(z, n) return function() return z:isDead() and #credited >= n end end
            -- 1. Requester in the circle: counted for char1.
            inside[1]:Hit(bat, p, LETHAL, false, 1.0)
            t2:waitUntil(dies(inside[1], 1), DEATH_MS, function(t3)
                t3:eq({ 1, 1 }, { m.kills, m.tally.char1 }, "kill of the requester in the circle")
                -- 2. Requester outside the circle: nobody.
                outside:Hit(bat, p, LETHAL, false, 1.0)
                t3:waitUntil(dies(outside, 2), DEATH_MS, function(t4)
                    t4:eq(false, credited[2], "kill outside the circle counted")
                    t4:eq(1, m.kills, "count after a kill outside the circle")
                    -- 3. Second client in the circle: counted for char2, target reached.
                    inside[2]:Hit(bat, peer, LETHAL, false, 1.0)
                    t4:waitUntil(dies(inside[2], 3), DEATH_MS, function(t5)
                        t5:eq({ 2, 1, 1 }, { m.kills, m.tally.char1, m.tally.char2 }, "kills and parts after the "
                            .. "kill of the second participant")
                        t5:eq(true, M.reportReady(m), "target met")
                        local one, two = shown(M, m, "char1"), shown(M, m, "char2")
                        t5:eq(true, one.engaged and two.engaged, "both participants engaged in their projection")
                        two.engaged = one.engaged
                        t5:eq(one, two, "k / N and parts differ between the two participants")
                        t5:eq({ 2, 2 }, { one.kills, one.target }, "k / N shown")
                        -- 4. A kill after the target counts no more (no double count).
                        late:Hit(bat, p, LETHAL, false, 1.0)
                        t5:waitUntil(dies(late, 4), DEATH_MS, function(t6)
                            t6:eq(false, credited[4], "kill after the target counted")
                            t6:eq({ 2, 1, 1 }, { m.kills, m.tally.char1, m.tally.char2 }, "count after the target")
                        end, "late zombie not dead")
                    end, "zombie hit by the second participant not dead")
                end, "zombie outside the circle not dead")
            end, "first zombie not dead after a lethal hit")
        end)
    end)
end)
