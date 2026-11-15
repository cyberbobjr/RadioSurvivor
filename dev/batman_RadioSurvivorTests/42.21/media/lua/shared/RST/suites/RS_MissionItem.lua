-- Voice mission `item` (E20-T15, ADR D06, D10) on a real building near the player. Real start path of a voice
-- (RS_MissionVoice.start, sheet with one [mission] of type item, a place use=target in the nearest building and a
-- place use=drop on the player's square, next to a real crate), real set-ups (RS_MissionTarget, RS_DeadDrops), real
-- engine poll (CA_Missions.observe: the template places the item through CA_Caches, then the drop hooks collect it),
-- real radio report (RS_MissionVoice.report).
-- The personal item (Base.Locket, media/scripts/generated/items/clothing.txt:6937 in 42.22) is spawned by the server
-- on the floor of the building; the suite picks it up as the server part of a transfer does (removed from the square
-- for every client, added to the server copy of the inventory and sent: transmitRemoveItemFromSquare, AddItem,
-- sendAddItemToContainer), adds a second locket (the decoy, unmarked) and leaves both in the crate.
-- Steps: placed once and marked; found once held; report while holding it refused; both lockets in the crate; every
-- online player leaves (beyond RS_OutOfSight.VIEW_TILES), the game clock moves past the delay of the mission
-- (GameTime.setTimeOfDay, world age = nights * 24 + hours since 7:00, GameTime.java:824-827); back at the drop: the
-- marked locket is gone, the decoy stays, the objective is met and the radio report succeeds. In-memory state (store
-- whose save does nothing): no notebook state.
require 'RST/RST'
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local AWAY = 150       -- tiles: beyond RS_OutOfSight.VIEW_TILES (100) on the x axis
local DELAY = 1        -- game hours of the test mission (collect_hours)
local RADIUS = 40      -- tiles around the player searched for a building
local KHZ = 199600
local ITEM = 'Base.Locket'

-- Moves the game clock forward by `hours` without crossing 7:00 (the world age would go back).
local function advance(hours)
    local gt = getGameTime()
    gt:setTimeOfDay(gt:getTimeOfDay() + hours)
end

-- Square of a room on the ground floor of the nearest building around the player, or nil.
local function findBuilding(p)
    local cell, px, py = getCell(), math.floor(p:getX()), math.floor(p:getY())
    for d = 0, RADIUS do
        for x = px - d, px + d do
            for y = py - d, py + d do
                if math.max(math.abs(x - px), math.abs(y - py)) == d then
                    local sq = cell:getGridSquare(x, y, 0)
                    if sq and sq:getRoom() ~= nil and sq:getBuildingDef() ~= nil then return sq end
                end
            end
        end
    end
    return nil
end

local function removeItem(container, item)
    if not container or not item then return end
    local left = container:getItemWithIDRecursiv(item:getID())
    if not left then return end
    container:DoRemoveItem(left)
    if isServer() then sendRemoveItemFromContainer(container, left) end
end

local function moveItem(from, to, item)
    removeItem(from, item)
    to:AddItem(item)
    if isServer() then sendAddItemToContainer(to, item) end
end

local function crateOf(d)
    local b = d.box
    local sq = b and getCell():getGridSquare(b.x, b.y, d.z)
    local objects = sq and sq:getObjects()
    local o = objects and b.object < objects:size() and objects:get(b.object) or nil
    return o and o:getContainerByIndex(b.container) or nil
end

-- Floor object of the placed item (record m.personal.at), or nil.
local function floorObject(m)
    local at = type(m.personal) == 'table' and m.personal.at
    local sq = at and getCell():getGridSquare(at.x, at.y, at.z)
    local objects = sq and sq:getWorldObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local w = objects:get(i)
        if w:getItem() and w:getItem():getID() == m.itemId then return w, sq end
    end
    return nil
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local Caches = require 'CoreAI/CA_Caches'
    local gt = getGameTime()
    if (gt:getTimeOfDay() - 7) % 24 > 20 then
        gt:setTimeOfDay(8)
        t:note('game clock set to 8:00 so that it can be moved forward by a few hours')
    end
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local sq = p:getSquare()
    t:ok(sq ~= nil, 'player square unavailable')
    local site = findBuilding(p)
    if not site then t:skip('no building with a loaded ground floor within ' .. RADIUS .. ' tiles') end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    t:note('building at ' .. site:getX() .. ',' .. site:getY() .. ', drop at ' .. x .. ',' .. y .. ',' .. z)
    local crate = IsoObject.new(getCell(), sq, 'location_military_generic_01_0')
    crate:createContainersFromSpriteProperties()
    sq:transmitAddObjectToSquare(crate, -1)
    local sheet = {id = 'rst-voice-item', name = 'RST Voice', actions = {'say', 'start_mission'}, budgets = {},
        missions = {{id = 'locket', type = 'item', target = 'site', drops = {'drop'},
            params = {item = ITEM, label = 'RST locket', collect_hours = DELAY}}},
        places = {{id = 'site', label = 'RST building', x = site:getX(), y = site:getY(), z = 0, uses = {'target'},
            use = {target = true}},
            {id = 'drop', label = 'RST drop', x = x, y = y, z = z, uses = {'drop'}, use = {drop = true}}}}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local inv = p:getInventory()
    local item, decoy, m
    t:defer(function()
        local d = m and m.drops and m.drops[1]
        local box = d and crateOf(d)
        removeItem(box, item); removeItem(box, decoy); removeItem(inv, item); removeItem(inv, decoy)
        if m and m.itemId then
            local w, square = floorObject(m)
            if w then square:transmitRemoveItemFromSquare(w) end
        end
        if d and d.box then
            local b = d.box
            local at = getCell():getGridSquare(b.x, b.y, z)
            local o = at and b.object < at:getObjects():size() and at:getObjects():get(b.object) or nil
            local md = o and o:getModData()
            if md and type(md.RS_DeadDrop) == 'table' then md.RS_DeadDrop[b.key] = nil end
        end
        if crate:getSquare() then crate:getSquare():transmitRemoveItemFromSquare(crate) end
    end, 'remove the lockets, the crate and the dead drop key')
    local why
    m, why = V.start(store, sheet, 'char1', p, KHZ, 'locket')
    t:ok(m ~= nil, 'item mission not created: ' .. tostring(why))
    local d = m.drops and m.drops[1]
    t:eq({'item', 1, DELAY, ITEM}, {m.template, m.drops and #m.drops, m.collectHours, m.itemType}, 'mission and drop')
    t:eq('box', d and d.mode, 'the crate next to the drop was not designated')
    local function poll()
        Caches.resetForTests() -- no wait between two placement attempts of the suite
        return M.observe(state, {{player = p, character = 'char1'}}, store)
    end
    t:waitUntil(function() poll() return m.personal.placed == true end, 20000, function(t2)
        local w, square = floorObject(m)
        t2:ok(w ~= nil, 'placed item not on the floor at ' .. tostring(m.personal.at and m.personal.at.x))
        item = w:getItem()
        t2:eq(m.personal.key, item:getModData().CA_Cache, 'placed item not marked')
        poll()
        t2:eq(true, m.personal.placed and floorObject(m) == w, 'placed twice')
        square:transmitRemoveItemFromSquare(w)
        inv:AddItem(item)
        if isServer() then sendAddItemToContainer(inv, item) end
        poll()
        t2:eq(true, m.found, 'item in the inventory not observed')
        t2:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report while holding the item')
        decoy = inv:AddItem(ITEM)
        t2:ok(decoy ~= nil, 'locket script unavailable')
        if isServer() then sendAddItemToContainer(inv, decoy) end
        local box = crateOf(d)
        t2:ok(box ~= nil, 'designated crate not found')
        moveItem(inv, box, item)
        moveItem(inv, box, decoy)
        poll()
        t2:eq(0, m.delivered, 'collected in front of the player')
        F.movePlayers(t2, p, x + AWAY, y, z, function(t3, origin)
            poll()
            advance(DELAY * 1.5)
            t3:waitUntil(function()
                poll()
                return m.delivered == 1 or d.due == true
            end, 20000, function(t4)
                t4:note('away: delivered ' .. m.delivered .. ', due ' .. tostring(d.due))
                F.movePlayers(t4, p, origin.x, origin.y, origin.z, function(t5)
                    t5:waitUntil(function() poll() return m.delivered == 1 end, 20000, function(t6)
                        local here = crateOf(d)
                        t6:eq(nil, here and here:getItemWithIDRecursiv(item:getID()), 'marked locket still there')
                        t6:ok(here ~= nil and here:getItemWithIDRecursiv(decoy:getID()) ~= nil, 'decoy taken')
                        t6:eq(true, M.reportReady(m), 'objective not met after the collection')
                        t6:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused')
                        t6:eq('success', m.state)
                    end, function()
                        return 'locket not collected once back: delivered ' .. m.delivered .. ', due ' .. tostring(d.due)
                    end)
                end)
            end, function()
                return 'locket neither collected nor due after the delay: hidden since ' .. tostring(d.hiddenSince)
                    .. ', world age ' .. tostring(gt:getWorldAgeHours())
            end)
        end)
    end, function()
        return 'item not placed: building of the place not loaded or not ready'
    end)
end

RST.suite("rs.voiceitem", {tags = {"server", "world"}, testTimeoutMs = 120000}, function(s)
    s.test('personal item placed by the server, found, left at a drop with a decoy, only it collected, then the report',
        run)
end)
