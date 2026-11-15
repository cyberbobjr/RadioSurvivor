-- ID card of a voice `retrieve` mission left at a dead drop (E20-T06, ADR D06). Real start path of a voice
-- (RS_MissionVoice.start, sheet with one [mission] of type retrieve and one place use=drop on the player's square,
-- next to a real crate), real engine poll (RC_Missions.observe: drop hooks of the voice giver, RS_DeadDrops), real
-- radio report (RS_MissionVoice.report). The body is not placed (its building is far away): the card is given to the
-- player and recorded as the card of the mission (m.cardId), as Retrieve.place does; a second ID card is the decoy.
-- Steps: report while holding the card refused (card kept); both cards left in the crate; every online player leaves
-- (beyond RS_OutOfSight.VIEW_TILES), the game clock moves past the mission delay (GameTime.setTimeOfDay, world age =
-- nights * 24 + hours since 7:00, GameTime.java:824-827); back at the drop: the card is gone, the decoy stays, the
-- objective is met and the radio report succeeds. In-memory state (store whose save does nothing): no notebook state.
require 'RST/RST'
require 'RST/RST_Fixtures'
require 'RST/RST_RSHelpers'
local F = RST.Fixtures

local AWAY = 150       -- tiles: beyond RS_OutOfSight.VIEW_TILES (100) on the x axis
local DELAY = 1        -- game hours of the test mission (collect_hours)
local KHZ = 199700

-- Moves the game clock forward by `hours` without crossing 7:00 (the world age would go back).
local function advance(hours)
    local gt = getGameTime()
    gt:setTimeOfDay(gt:getTimeOfDay() + hours)
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

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'RadioSurvivorCore/RC_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    require('RadioSurvivorCore/RC_MissionRetrieve').resetForTests()
    local gt = getGameTime()
    if (gt:getTimeOfDay() - 7) % 24 > 20 then
        gt:setTimeOfDay(8)
        t:note('game clock set to 8:00 so that it can be moved forward by a few hours')
    end
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local sq = p:getSquare()
    t:ok(sq ~= nil, 'player square unavailable')
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local crate = IsoObject.new(getCell(), sq, 'location_military_generic_01_0')
    crate:createContainersFromSpriteProperties()
    sq:transmitAddObjectToSquare(crate, -1)
    local sheet = {id = 'rst-voice-retrieve-drop', name = 'RST Voice', actions = {'say', 'start_mission'},
        budgets = {}, missions = {{id = 'retrieve', type = 'retrieve', params = {collect_hours = DELAY}}},
        places = {{id = 'drop', label = 'RST drop', x = x, y = y, z = z, uses = {'drop'}, use = {drop = true}}}}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local inv = p:getInventory()
    local card, decoy, m
    t:defer(function()
        local box = m and m.drops and m.drops[1] and crateOf(m.drops[1])
        removeItem(box, card); removeItem(box, decoy); removeItem(inv, card); removeItem(inv, decoy)
        if m and m.drops and m.drops[1] and m.drops[1].box then
            local b = m.drops[1].box
            local here = getCell():getGridSquare(b.x, b.y, z)
            local o = here and b.object < here:getObjects():size() and here:getObjects():get(b.object) or nil
            local md = o and o:getModData()
            if md and type(md.RS_DeadDrop) == 'table' then md.RS_DeadDrop[b.key] = nil end
        end
        if crate:getSquare() then crate:getSquare():transmitRemoveItemFromSquare(crate) end
    end, 'remove the cards, the crate and the dead drop key')
    local why
    m, why = V.start(store, sheet, 'char1', p, KHZ, 'retrieve')
    if not m and why == 'no_place' then
        t:skip('no building for a retrieve mission around the player: move to a town and run again')
    end
    t:ok(m ~= nil, 'retrieve mission not created: ' .. tostring(why))
    local d = m.drops and m.drops[1]
    t:eq({'retrieve_id', 1, DELAY}, {m.template, m.drops and #m.drops, m.collectHours}, 'mission and its drop')
    t:eq('box', d and d.mode, 'the crate next to the drop was not designated')
    card = inv:AddItem('Base.IDcard')
    decoy = inv:AddItem('Base.IDcard')
    t:ok(card ~= nil and decoy ~= nil, 'ID card script unavailable')
    if isServer() then sendAddItemToContainer(inv, card); sendAddItemToContainer(inv, decoy) end
    -- The card of the mission, as Retrieve.place records it for the card put in the body.
    m.cardId, m.placed = card:getID(), true
    local function poll() return M.observe(state, {{player = p, character = 'char1'}}, store) end
    poll()
    t:eq(true, m.found, 'card in the inventory not observed')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report while holding the card')
    t:ok(inv:getItemWithIDRecursiv(card:getID()) ~= nil, 'the refused report removed the card')
    local box = crateOf(d)
    t:ok(box ~= nil, 'designated crate not found')
    moveItem(inv, box, card)
    moveItem(inv, box, decoy)
    poll()
    t:eq(0, m.delivered, 'collected in front of the player')
    F.movePlayers(t, p, x + AWAY, y, z, function(t2, origin)
        poll()
        advance(DELAY * 1.5)
        t2:waitUntil(function()
            poll()
            return m.delivered == 1 or d.due == true
        end, 20000, function(t3)
            t3:note('away: delivered ' .. m.delivered .. ', due ' .. tostring(d.due))
            F.movePlayers(t3, p, origin.x, origin.y, origin.z, function(t4)
                t4:waitUntil(function() poll() return m.delivered == 1 end, 20000, function(t5)
                    local here = crateOf(d)
                    t5:eq(nil, here and here:getItemWithIDRecursiv(card:getID()), 'card still in the crate')
                    t5:ok(here ~= nil and here:getItemWithIDRecursiv(decoy:getID()) ~= nil, 'the decoy card was taken')
                    t5:eq(true, M.reportReady(m), 'objective not met after the collection')
                    t5:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused after collection')
                    t5:eq('success', m.state)
                    t5:eq(nil, inv:getItemWithIDRecursiv(card:getID()), 'card back in the inventory')
                end, function()
                    return 'card not collected once back: delivered ' .. m.delivered .. ', due ' .. tostring(d.due)
                end)
            end)
        end, function()
            return 'card neither collected nor due after the delay: hidden since ' .. tostring(d.hiddenSince)
                .. ', world age ' .. tostring(gt:getWorldAgeHours())
        end)
    end)
end

RST.suite("rs.voiceretrieve", {tags = {"server", "world"}, testTimeoutMs = 120000}, function(s)
    s.test('ID card left at a dead drop, collected out of view after the delay, then the radio report', run)
end)
