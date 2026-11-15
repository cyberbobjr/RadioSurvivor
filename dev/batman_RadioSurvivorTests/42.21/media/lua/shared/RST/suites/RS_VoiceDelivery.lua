-- Dead drops of a radio voice (E20-T05, ADR D06): two drops (a real crate, a bag on the ground) with one item each,
-- collected only out of everyone's view (100 tiles, RS_OutOfSight) and after the mission delay in game hours.
-- Every online player leaves, comes back before the delay (goods still there, wait reset), leaves again and comes back
-- after the delay (goods gone, quantity reached, report due). The game clock is moved forward with
-- GameTime.setTimeOfDay (world age = nights * 24 + hours since 7:00, GameTime.java:824-827).
require 'RST/RST'
require 'RST/RST_Fixtures'
require 'RST/RST_RSHelpers'
local F = RST.Fixtures

local AWAY = 150       -- tiles: beyond RS_OutOfSight.VIEW_TILES (100) on the x axis
local DELAY = 1        -- game hours of the test mission (collect_hours)

-- Moves the game clock forward by `hours` without crossing 7:00 (the world age would go back).
local function advance(hours)
    local gt = getGameTime()
    gt:setTimeOfDay(gt:getTimeOfDay() + hours)
end

local function bagGone(sq, id)
    local objects = sq and sq:getWorldObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        if objects:get(i):getItem():getID() == id then return false end
    end
    return true
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local D = require 'RadioSurvivor/RS_VoiceDelivery'
    local M = require 'RadioSurvivorCore/RC_Missions'
    local gt = getGameTime()
    if (gt:getTimeOfDay() - 7) % 24 > 20 then
        -- Close to 7:00: start the day again at 8:00 so the later moves never cross it.
        gt:setTimeOfDay(8)
        t:note('game clock set to 8:00 so that it can be moved forward by a few hours')
    end
    local p = F.player(t)
    local sq = p:getSquare()
    t:ok(sq ~= nil, 'requester square unavailable')
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local bagSquare = getCell():getGridSquare(x + 8, y, z)
    t:ok(bagSquare ~= nil, 'square of the second drop not loaded')
    local crate = IsoObject.new(getCell(), sq, 'location_military_generic_01_0')
    crate:createContainersFromSpriteProperties()
    sq:transmitAddObjectToSquare(crate, -1)
    local m = {id = 'rst-drops-' .. tostring(RST.now()), template = 'deliver', donor = 'voice', state = 'active',
        quantity = 2, delivered = 0, collectHours = DELAY, credited = {}, accepted = {['Base.Bandage'] = true},
        drops = {{id = 'crate', label = 'RST crate', x = x, y = y, z = z, mode = 'box'},
            {id = 'bag', label = 'RST bag', x = x + 8, y = y, z = z, mode = 'bag'}}}
    local store = {save = function() return true end}
    local inv, bandage, bag, inBag
    t:defer(function()
        local left = inv and bandage and inv:getItemWithIDRecursiv(bandage:getID())
        if left then
            inv:DoRemoveItem(left)
            if isServer() then sendRemoveItemFromContainer(inv, left) end
        end
        if bag and bag:getWorldItem() and bag:getWorldItem():getSquare() then
            bag:getWorldItem():getSquare():transmitRemoveItemFromSquare(bag:getWorldItem())
        end
        if crate:getSquare() then crate:getSquare():transmitRemoveItemFromSquare(crate) end
    end, 'remove the drop fixtures')
    t:eq({true, true}, {D.prepare(m, m.drops[1], store), D.prepare(m, m.drops[2], store)}, 'prepare both drops')
    t:eq({'box', 'bag'}, {m.drops[1].mode, m.drops[2].mode}, 'real crate not selected or bag drop not kept')
    local b = m.drops[1].box
    inv = getCell():getGridSquare(b.x, b.y, z):getObjects():get(b.object):getContainerByIndex(b.container)
    bandage = inv:AddItem('Base.Bandage')
    if isServer() then sendAddItemToContainer(inv, bandage) end
    bag = instanceItem('Base.Bag_Schoolbag')
    t:ok(bag ~= nil, 'bag script unavailable')
    inBag = bag:getItemContainer():AddItem('Base.Bandage')
    bagSquare:AddWorldInventoryItem(bag, 0.5, 0.5, 0, true)
    local function observe() return D.observe(m, p, 'Tester', {}, store) end
    -- A drop is settled once collected (its item credited) or due (delay passed while its square was unloaded).
    local function settled(i, item)
        return m.drops[i].due == true or m.credited[tostring(item:getID())] == true
    end
    local function present(tt, what)
        local here = getCell():getGridSquare(b.x, b.y, z)
        local box = here and here:getObjects():get(b.object):getContainerByIndex(b.container)
        tt:ok(box ~= nil and box:getItemWithIDRecursiv(bandage:getID()) ~= nil, what .. ': crate item gone')
        tt:ok(not bagGone(getCell():getGridSquare(x + 8, y, z), bag:getID()), what .. ': bag gone')
    end
    observe()
    t:eq(0, m.delivered, 'collected in front of the player')
    F.movePlayers(t, p, x + AWAY, y, z, function(t2, origin)
        observe()
        advance(DELAY / 2)
        observe()
        t2:eq(0, m.delivered, 'collected before the delay')
        F.movePlayers(t2, p, origin.x, origin.y, origin.z, function(t2b)
          -- Solo: the drop squares unloaded while away; read the goods once both are loaded again.
          F.waitSquare(t2b, x + 8, y, z, nil, function(t3)
            observe()
            t3:eq(0, m.delivered, 'collected in front of the returning player')
            present(t3, 'back before the delay')
            t3:eq(true, m.drops[1].hiddenSince == nil and m.drops[2].hiddenSince == nil, 'wait not reset by the return')
            F.movePlayers(t3, p, origin.x + AWAY, origin.y, origin.z, function(t4)
                observe()
                advance(DELAY * 1.5)
                t4:waitUntil(function()
                    observe()
                    return settled(1, bandage) and settled(2, inBag)
                end, 20000, function(t5)
                    t5:note('away: delivered ' .. m.delivered .. ', due ' .. tostring(m.drops[1].due) .. '/'
                        .. tostring(m.drops[2].due))
                    F.movePlayers(t5, p, origin.x, origin.y, origin.z, function(t6)
                        t6:waitUntil(function() observe() return m.delivered == 2 end, 20000, function(t7)
                            local here = getCell():getGridSquare(b.x, b.y, z)
                            local box = here and here:getObjects():get(b.object):getContainerByIndex(b.container)
                            t7:eq(nil, box and box:getItemWithIDRecursiv(bandage:getID()), 'crate item still there')
                            t7:ok(bagGone(getCell():getGridSquare(x + 8, y, z), bag:getID()), 'bag still there')
                            t7:eq(true, M.reportReady(m), 'mission not ready to report after the collection')
                            observe()
                            t7:eq(2, m.delivered, 'credited twice')
                        end, function()
                            return 'not collected once back: delivered ' .. m.delivered .. ', due '
                                .. tostring(m.drops[1].due) .. '/' .. tostring(m.drops[2].due)
                        end)
                    end)
                end, function()
                    return 'nothing collected nor due after the delay: delivered ' .. m.delivered .. ', hidden since '
                        .. tostring(m.drops[1].hiddenSince) .. ', world age ' .. tostring(gt:getWorldAgeHours())
                end)
            end)
          end)
        end)
    end)
end

RST.suite("rs.voicedelivery", {tags = {"server", "world"}, testTimeoutMs = 120000}, function(s)
    s.test('two drops collected only out of view after the game-hour delay, return resets it', run)
end)
