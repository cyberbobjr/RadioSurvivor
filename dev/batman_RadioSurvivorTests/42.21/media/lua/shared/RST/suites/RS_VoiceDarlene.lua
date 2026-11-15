-- Darlene wants to go back to her clinic (E20-T10, ADR D09): her whole mission chain with the REAL shipped sheet
-- (RS_Personas.get('darlene')), at the real West Point clinic of the 42.22 map, through the real start path of a
-- voice (RS_MissionVoice.start: section ids, after=, target=) and the real radio report (RS_MissionVoice.report).
-- Every player is moved in front of the clinic (front door, outside: 11884,6888,0) and brought back at the end.
-- Steps, each one refused before its predecessor succeeded (locked), then started, met and reported:
--   1. scout_clinic: the zone of the clinic building, reached by the server poll (CA_Missions.observe);
--   2. clear_clinic: one real zombie next to the player, lethal bat hit, counted by the template inside the real
--      circle around the clinic (Clear.noteHit / Clear.count on test subscribers, as rs.missions.voicetemplates); the
--      kills asked by the density are lowered to 1 (noted);
--   3. secure_clinic: free outside openings of the clinic building barricaded on the player's side as the server part
--      of the vanilla gesture does (IsoBarricade.AddBarricadeToObject, addPlank, transmitCompleteItemToClients, as
--      rs.voicebarricade), counted by the server; the count of the sheet (4) is lowered to the free openings found
--      near the front door when fewer (noted);
--   4. meds: first-aid goods left at one of the two dead drops of the sheet (marked container, or a bag on the ground),
--      collected only once every online player is out of sight and the mission delay passed (game clock moved
--      forward, collect delay lowered to 1 game hour as rs.voicedelivery), then the report sets the story state
--      `returned` in the state of the test.
-- In-memory state (store whose save does nothing): no notebook state, no global story state; the clinic is marked as
-- already given to the test character (no map mark) and the reward pool is left out of the test copy of the sheet
-- (rewards: rs.missionrewards). The wait between two missions of a voice (play time) is cleared before each start.
-- Cleanup: zombie and corpse, barricades, drop goods, players back.
require 'RST/RST'
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local KHZ = 199800
local FRONT = {x = 11884, y = 6888, z = 0} -- outside the front door of the clinic (fixtures_doors_01_49, y 6887)
local MARK = 'RST_DarleneZombie'
local LETHAL = 100.0
local DEATH_MS = 5000
local RADIUS = 12      -- tiles around the player searched for free outside openings of the clinic building
local AWAY = 150       -- tiles: beyond RS_OutOfSight.VIEW_TILES (100)
local DELAY = 1        -- game hours of the drop collection in the test

-- Moves the game clock forward by `hours` without crossing 7:00 (the world age would go back).
local function advance(hours)
    local gt = getGameTime()
    gt:setTimeOfDay(gt:getTimeOfDay() + hours)
end

local function defKey(def)
    return def and (def:getX() .. ',' .. def:getY() .. ',' .. def:getX2() .. ',' .. def:getY2()) or nil
end

-- Free outside openings of the building with these bounds within RADIUS of the player.
local function freeOpenings(p, site)
    local key = site.x1 .. ',' .. site.y1 .. ',' .. site.x2 .. ',' .. site.y2
    local cell, px, py, pz = getCell(), math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local out = {}
    for x = px - RADIUS, px + RADIUS do
        for y = py - RADIUS, py + RADIUS do
            local sq = cell:getGridSquare(x, y, pz)
            local objects = sq and sq:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local o = objects:get(i)
                if instanceof(o, 'BarricadeAble') and o:isBarricadeAllowed() and not o:isBarricaded() then
                    local other = o:getOppositeSquare()
                    local a, b = defKey(sq:getBuildingDef()), defKey(other and other:getBuildingDef() or nil)
                    if a ~= b and (a == key or b == key) then out[#out + 1] = o end
                end
            end
        end
    end
    return out
end

local function nail(o, p, made)
    local b = IsoBarricade.AddBarricadeToObject(o, p)
    if not b then return nil end
    b:addPlank(p, instanceItem('Base.Plank'))
    if isServer() then b:transmitCompleteItemToClients() end
    made[#made + 1] = b
    return b
end

-- Test copy of the real sheet without its reward pool (same places, missions and identity).
local function testSheet(real)
    local copy = {}
    for k, v in pairs(real) do copy[k] = v end
    copy.rewards = {}
    return copy
end

-- Squares the suite reads, all loaded before it starts: the front of the clinic and the corners of the search area of
-- both drops (radius 3 around 11874,6870 and 11894,6870). In solo the drops are 17 tiles from the front and their
-- chunks load a little after it; on a dedicated server they were already loaded.
local AREA = {{11880, 6887}, {11871, 6867}, {11877, 6873}, {11891, 6867}, {11897, 6873}}

local function waitSquares(t, list, i, done)
    if i > #list then return done(t) end
    F.waitSquare(t, list[i][1], list[i][2], 0, nil, function(t2) waitSquares(t2, list, i + 1, done) end)
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local B = require 'CoreAI/CA_MissionBarricade'
    local Clear = require 'CoreAI/CA_MissionClear'
    local real = require('RadioSurvivor/RS_Personas').get('darlene')
    if not real then t:skip('darlene.txt not loaded by the server (modified or refused: see the server log)') end
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local gt = getGameTime()
    if (gt:getTimeOfDay() - 7) % 24 > 20 then
        gt:setTimeOfDay(8)
        t:note('game clock set to 8:00 so that it can be moved forward by a few hours')
    end
    local sheet = testSheet(real)
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local d = V.donor(state, sheet.id, 'char1', true)
    d.given = {clinic = true}
    local present = {{player = p, character = 'char1'}}
    local function poll()
        B.resetForTests()
        return M.observe(state, present, store)
    end
    local function start(name)
        d.nextOfferHour, d.nextOfferAt = nil, nil
        Clear.resetForTests()
        require('CoreAI/CA_MissionScout').resetForTests()
        return V.start(store, sheet, 'char1', p, KHZ, name)
    end
    -- place: label of the sheet place the mission aims at, or nil (deliver: the drops of the section).
    local function step(tt, name, template, place)
        local m, why = start(name)
        if not m and why == 'no_place' and template == 'clear' then
            -- Same rule as rs.missions.voicetemplates: below minDensity around the clinic, start again without a
            -- minimum density (the suite brings its own zombie).
            local c = require('RadioSurvivor/RS_Config').Missions.clear
            local minDensity = c.minDensity
            c.minDensity = 0
            m, why = start(name)
            c.minDensity = minDensity
            tt:note('clear: density around the clinic below ' .. tostring(minDensity) .. ', started without minimum')
        end
        tt:ok(m ~= nil, name .. ' not started: ' .. tostring(why))
        tt:eq({template, name}, {m.template, m.section}, name .. ': template or section')
        if place then tt:eq(place, m.place, name .. ': not aimed at the place of the sheet') end
        tt:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, name .. ': report before the objective')
        return m
    end
    local function reported(tt, m, name)
        tt:eq(true, M.reportReady(m), name .. ': objective not met')
        tt:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, name .. ': radio report refused')
        tt:eq('success', m.state, name .. ': not a success')
    end
    local made, mine, credited, goods = {}, {}, {}, {}
    local function resolve(player) if rawequal(player, p) then return 'char1' end end
    local function onHit(z, wielder, _, weapon) if mine[z] then Clear.noteHit(z, wielder, weapon) end end
    local function onDead(z) if mine[z] then credited[#credited + 1] = Clear.count(state, z, resolve) ~= nil end end
    Events.OnHitZombie.Add(onHit)
    Events.OnZombieDead.Add(onDead)
    t:defer(function() Events.OnHitZombie.Remove(onHit); Events.OnZombieDead.Remove(onDead) end,
        'remove the test subscribers')
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, 'restore the god mode of the target player')
    t:defer(function()
        for _, b in ipairs(made) do
            local sq = b:getSquare()
            if sq then sq:transmitRemoveItemFromSquare(b) end
        end
        for _, g in ipairs(goods) do
            local inv = g.container
            local left = inv and inv:getItemWithIDRecursiv(g.item:getID())
            if left then
                inv:DoRemoveItem(left)
                if isServer() then sendRemoveItemFromContainer(inv, left) end
            end
            local w = g.bag and g.bag:getWorldItem()
            if w and w:getSquare() then w:getSquare():transmitRemoveItemFromSquare(w) end
        end
    end, 'remove the barricades and the goods of the suite')

    F.movePlayers(t, p, FRONT.x, FRONT.y, FRONT.z, function(t1)
      waitSquares(t1, AREA, 1, function(t2)
        -- Only the first step is offered before anything was done.
        for _, locked in ipairs({'clear_clinic', 'secure_clinic', 'meds', 'barricade', 'deliver'}) do
            t2:eq({nil, 'locked'}, {start(locked)}, locked .. ' offered before its predecessor')
        end
        -- 1. Look at the clinic: the player stands in the zone of the clinic building.
        local scout = step(t2, 'scout_clinic', 'scout', 'West Point clinic')
        poll()
        reported(t2, scout, 'scout_clinic')
        -- 2. Clear around the clinic.
        local clear = step(t2, 'clear_clinic', 'clear', 'West Point clinic')
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        t2:note('clear: ' .. tostring(clear.target) .. ' kills asked by the density, lowered to 1')
        clear.target = 1
        local list = addZombiesInOutfit(px + 2, py, pz, 1, nil, 50)
        t2:ok(list ~= nil and list:size() == 1, 'zombie not created')
        local z = list:get(0)
        z:getModData()[MARK] = true
        mine[z] = true
        t2:defer(function()
            if not z:isDead() then z:removeFromWorld(); z:removeFromSquare() end
            local sq = getCell() and getCell():getGridSquare(px + 2, py, pz)
            local objects = sq and sq:getStaticMovingObjects()
            for i = (objects and objects:size() or 0) - 1, 0, -1 do
                local o = objects:get(i)
                if instanceof(o, 'IsoDeadBody') and o:hasModData() and o:getModData()[MARK] then sq:removeCorpse(o, false) end
            end
        end, 'remove the zombie and corpse of the test')
        z:Hit(instanceItem('Base.BaseballBat'), p, LETHAL, false, 1.0)
        t2:waitUntil(function() return z:isDead() and #credited >= 1 end, DEATH_MS, function(t3)
            t3:eq({true, 1}, {credited[1], clear.kills}, 'kill of the caller in the circle around the clinic')
            reported(t3, clear, 'clear_clinic')
            -- 3. Barricade the clinic.
            local secure = step(t3, 'secure_clinic', 'barricade', 'West Point clinic')
            poll()
            local openings = freeOpenings(p, secure.site)
            t3:ok(#openings >= 1, 'no free outside opening of the clinic building near the front door')
            if #openings < secure.count then
                t3:note('barricade: ' .. #openings .. ' free openings near the front door, count lowered from '
                    .. secure.count)
                secure.count = #openings
            end
            for i = 1, secure.count do t3:ok(nail(openings[i], p, made) ~= nil, 'barricade not put up') end
            poll()
            t3:eq(secure.count, secure.barricaded, 'barricades of the clinic not counted')
            reported(t3, secure, 'secure_clinic')
            -- 4. Medicine at a dead drop near the clinic.
            local meds = step(t3, 'meds', 'deliver')
            t3:eq({'drop_dumpsters', 'drop_bookstore'}, {meds.drops[1].id, meds.drops[2].id}, 'drops of the sheet')
            t3:eq('returned', meds.setsState, 'meds does not set the story state')
            meds.collectHours = DELAY
            poll()
            local drop = meds.drops[1]
            t3:ok(drop.ready == true, 'first drop not prepared at ' .. drop.x .. ',' .. drop.y)
            local needed = meds.quantity - meds.delivered
            if drop.box then
                local b = drop.box
                local inv = getCell():getGridSquare(b.x, b.y, drop.z):getObjects():get(b.object)
                    :getContainerByIndex(b.container)
                for _ = 1, needed do
                    local item = inv:AddItem('Base.Bandage')
                    if isServer() then sendAddItemToContainer(inv, item) end
                    goods[#goods + 1] = {container = inv, item = item}
                end
                t3:note('meds: ' .. needed .. ' bandages in the marked container of ' .. drop.label)
            else
                local bag = instanceItem('Base.Bag_Schoolbag')
                for _ = 1, needed do
                    goods[#goods + 1] = {container = bag:getItemContainer(),
                        item = bag:getItemContainer():AddItem('Base.Bandage'), bag = bag}
                end
                getCell():getGridSquare(drop.x, drop.y, drop.z):AddWorldInventoryItem(bag, 0.5, 0.5, 0, true)
                t3:note('meds: a bag of ' .. needed .. ' bandages on the ground at ' .. drop.label)
            end
            poll()
            t3:eq(0, meds.delivered, 'collected in front of the player')
            F.movePlayers(t3, p, FRONT.x + AWAY, FRONT.y, FRONT.z, function(t4, origin)
                poll()
                advance(DELAY * 1.5)
                t4:waitUntil(function()
                    poll()
                    return drop.due == true or meds.delivered >= meds.quantity
                end, 20000, function(t5)
                    F.movePlayers(t5, p, origin.x, origin.y, origin.z, function(t6)
                        t6:waitUntil(function() poll() return meds.delivered >= meds.quantity end, 20000,
                            function(t7)
                                t7:eq(nil, state.voiceStory and state.voiceStory.darlene, 'state set before the report')
                                reported(t7, meds, 'meds')
                                t7:eq('returned', state.voiceStory and state.voiceStory.darlene,
                                    'story state not returned after the last mission')
                            end, function()
                                return 'goods not collected once back: delivered ' .. meds.delivered .. ' of '
                                    .. meds.quantity
                            end)
                    end)
                end, function()
                    return 'drop neither collected nor due after the delay: delivered ' .. meds.delivered
                end)
            end)
        end, 'zombie not dead after a lethal hit')
      end)
    end)
end

RST.suite("rs.voicedarlene", {tags = {"server", "world"}, testTimeoutMs = 300000}, function(s)
    s.test("Darlene's chain with her real sheet at the West Point clinic, up to the story state returned", run)
end)
