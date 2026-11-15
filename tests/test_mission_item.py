"""Type de mission `item` (E20-T15, ADR D10) : un objet personnel vanilla nommé dans la fiche (`item=`, `label=`),
posé par le serveur dans le lieu `target` au début de la mission et marqué par son identifiant ; le joueur le trouve et
le dépose à une planque de la mission (règle de E20-T05 : ramassage hors de vue après un délai en heures de jeu) ;
seul l'objet marqué compte, un objet du même type non marqué est laissé ; compte rendu à la radio.

    python RadioSurvivor/tests/test_mission_item.py

Vrai RadioSurvivor_Server, vrai RS_Carnet_Server (gabarit CA_MissionItem inscrit au chargement), vrai RS_MissionVoice
(départ et compte rendu d'une voix), vrais RS_MissionTarget (lieu target) et RS_DeadDrops (planques), vraie pose
différée de CA_Caches, vrai RS_Persona (lecture de la fiche), vrai client du carnet ; doublures du monde rattachées à
leur classe Java et fidèles au Java 42.22 relevé (ITEM_WORLD). Preuve de la logique Lua, pas de l'API Java réelle ni du
réseau : la suite en jeu rs.voiceitem le confirme sur un serveur dédié.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, bridge_module, convert
from test_personas import LuaPersona
from test_persona_sections import BASE, PROMPT
import npc_protocol as protocol

# Doublures du monde, fidèles au Java 42.22 (E:\pz-source-42.22\java\zombie, relevé du 2026-11-15) :
# - IsoWorld.getMetaGrid (IsoWorld.java:474), getGameMode (:585), getWorld (:3011) ; IsoMetaGrid.getBuildingAt(x, y, z)
#   (IsoMetaGrid.java:271-280 : bâtiment de la pièce de la case, nil hors de toute pièce) ; BuildingDef getX/getY,
#   getX2/getY2 exclusifs, getRooms (:106), isFullyStreamedIn (:389) ; IsoBuilding.getDef (IsoBuilding.java:119).
# - IsoCell.getGridSquare(x, y, z) : nil pour une case non chargée ; IsoGridSquare getObjects, getWorldObjects (listes
#   Java depuis 0), getBuilding, isFree(boolean) (:2890), HasStairs (:2169), AddWorldInventoryItem(item, x, y, h,
#   transmit) (:5201 : l'objet posé au sol, envoyé aux clients si transmit), transmitRemoveItemFromSquare (:5073).
# - ItemContainer getItems (liste vivante), getType, AddItem, DoRemoveItem, getItemWithIDRecursiv ; IsoObject
#   getModData, getSprite, getContainerCount, getContainerByIndex ; InventoryItem getID (aléatoire, gardé par les
#   transferts), getFullType, getModData, hasModData (table non vide), getWorldItem, getContainer.
# - ScriptManager.FindItem(String) (ScriptManager.java:1325 : nil pour un type inconnu) ; Item.getDisplayName.
# - Objets personnels vanilla (media/scripts/generated/items, 42.22) : Base.Locket (clothing.txt:6937, DisplayCategory
#   Memento), Base.Photo (literature.txt:4041, Memento), Base.Pocketwatch (alarmclock.txt:3, Memento).
ITEM_WORLD = r'''
-- Game clock stopped (paused) and moved only by the tests; vanilla day of 90 real minutes.
WORLD_AGE_HOURS, MINUTES_PER_DAY = getGameTime():getWorldAgeHours(), 90
-- Test classes named after their Java class (checked by tests/test_doubles_api.py); instanceof reads __javaName.
local SUPER = {IsoWorldInventoryObject = {IsoObject = true}}
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local List = class('ArrayList')
function List:size() return #self.items end
function List:get(i) local v = self.items[i + 1]; if v == nil then error('IndexOutOfBounds ' .. i) end; return v end
local function jlist(items) return setmetatable({items = items}, List) end
-- Item scripts of the game (personal items of 42.22 and a decoy-free plain item).
local Script = class('Item')
function Script:getDisplayName() return self.displayName end
local Scripts = class('ScriptManager')
SCRIPT_ITEMS = {['Base.Locket'] = 'Locket', ['Base.Photo'] = 'Photo', ['Base.Pocketwatch'] = 'Pocket Watch'}
function Scripts:FindItem(name)
    local shown = SCRIPT_ITEMS[name]
    if shown == nil then return nil end
    return setmetatable({displayName = shown}, Script)
end
local SCRIPTS = setmetatable({}, Scripts)
getScriptManager = function() return SCRIPTS end
-- Inventory items: random id kept by every transfer (InventoryItem.id), mod data created on demand.
local Thing = class('InventoryItem')
function Thing:getID() return self.id end
function Thing:getFullType() return self.fullType end
function Thing:getModData() return self.md end
function Thing:hasModData()
    for _ in pairs(self.md) do return true end
    return false
end
function Thing:getWorldItem() return self.worldItem end
function Thing:getContainer() return self.container end
function Thing:isFavorite() return false end
local ids = 7000
local baseInstanceItem = instanceItem
instanceItem = function(fullType)
    if SCRIPT_ITEMS[fullType] == nil then return baseInstanceItem(fullType) end
    ids = ids + 13
    return setmetatable({id = ids, fullType = fullType, md = {}}, Thing)
end
-- Containers of the world (a crate) and of the bench.
local Container = class('ItemContainer')
function Container:getType() return self.kind end
function Container:getItems() return jlist(self.items) end
function Container:getItemWithIDRecursiv(id)
    for _, it in ipairs(self.items) do if it:getID() == id then return it end end
    return nil
end
function Container:AddItem(it) self.items[#self.items + 1] = it; it.container = self; return it end
function Container:DoRemoveItem(it)
    for i, v in ipairs(self.items) do if v == it then table.remove(self.items, i); it.container = nil; return end end
end
local Sprite = class('IsoSprite')
function Sprite:getName() return self.name end
local Furniture = class('IsoObject')
function Furniture:getModData() return self.md end
function Furniture:getSprite() return self.sprite end
function Furniture:getContainerCount() return 1 end
function Furniture:getContainerByIndex(i) if i == 0 then return self.container end return nil end
function Furniture:getSquare() return self.square end
local WorldItem = class('IsoWorldInventoryObject')
function WorldItem:getItem() return self.item end
function WorldItem:getSquare() return self.square end
-- Farmhouse x 300..309, y 300..307, ground floor; its squares load with HOUSE_LOADED, the rest of the world is loaded.
local Def = class('BuildingDef')
function Def:getX() return self.x1 end
function Def:getY() return self.y1 end
function Def:getX2() return self.x2 end
function Def:getY2() return self.y2 end
function Def:isFullyStreamedIn() return true end
function Def:getRooms() return jlist({}) end
HOUSE = setmetatable({x1 = 300, y1 = 300, x2 = 310, y2 = 308}, Def)
local Building = class('IsoBuilding')
function Building:getDef() return self.def end
local BUILDING = setmetatable({def = HOUSE}, Building)
local function inHouse(x, y, z)
    return z == 0 and x >= HOUSE.x1 and x < HOUSE.x2 and y >= HOUSE.y1 and y < HOUSE.y2
end
HOUSE_LOADED, BLOCKED, TRANSMITTED = true, {}, 0
local Sq = class('IsoGridSquare')
function Sq:getX() return self.x end
function Sq:getY() return self.y end
function Sq:getZ() return self.z end
function Sq:getObjects() return jlist(self.objects) end
function Sq:getWorldObjects() return jlist(self.world) end
function Sq:getBuilding() if inHouse(self.x, self.y, self.z) then return BUILDING end return nil end
function Sq:isFree(countCharacters) return not BLOCKED[self.x .. ',' .. self.y] end
function Sq:HasStairs() return false end
function Sq:AddWorldInventoryItem(item, x, y, height, transmit)
    local w = setmetatable({item = item, square = self}, WorldItem)
    self.world[#self.world + 1] = w
    item.worldItem = w
    if transmit then TRANSMITTED = TRANSMITTED + 1 end
    return item
end
function Sq:transmitRemoveItemFromSquare(obj)
    for i = #self.world, 1, -1 do
        if self.world[i] == obj then table.remove(self.world, i); obj.item.worldItem = nil; return i - 1 end
    end
    for i = #self.objects, 1, -1 do
        if self.objects[i] == obj then table.remove(self.objects, i); return i - 1 end
    end
    return -1
end
local squares = {}
function square(x, y, z)
    if inHouse(x, y, z) and not HOUSE_LOADED then return nil end
    local k = x .. ',' .. y .. ',' .. z
    squares[k] = squares[k] or setmetatable({x = x, y = y, z = z, objects = {}, world = {}}, Sq)
    return squares[k]
end
local Cell = class('IsoCell')
function Cell:getGridSquare(x, y, z) return square(x, y, z) end
function Cell:getZombieList() return jlist(ZOMBIES) end
local CELL = setmetatable({}, Cell)
getCell = function() return CELL end
local Grid = class('IsoMetaGrid')
function Grid:getBuildingAt(x, y, z)
    if z == nil then error('getBuildingAt(x, y) reads the bounds only: use the room variant (x, y, z)') end
    if inHouse(math.floor(x), math.floor(y), math.floor(z)) then return HOUSE end
    return nil
end
local GRID = setmetatable({}, Grid)
local World = class('IsoWorld')
local baseWorld = getWorld
function World:getGameMode() return baseWorld():getGameMode() end
function World:getWorld() return baseWorld():getWorld() end
function World:getMetaGrid() return GRID end
local WORLD = setmetatable({}, World)
getWorld = function() return WORLD end
local baseInstanceof = instanceof
instanceof = function(o, c)
    local mt = type(o) == 'table' and getmetatable(o) or nil
    local k = type(mt) == 'table' and rawget(mt, '__javaName') or nil
    if k == nil then return baseInstanceof(o, c) end
    return k == c or (SUPER[k] or {})[c] == true
end
-- A crate (vanilla furniture with one container) on a square of the world: { object, container }.
function crate(x, y, z)
    local sq = square(x, y, z)
    local box = setmetatable({kind = 'crate', items = {}}, Container)
    local o = setmetatable({md = {}, sprite = setmetatable({name = 'carpentry_01_16'}, Sprite), container = box,
        square = sq}, Furniture)
    sq.objects[#sq.objects + 1] = o
    return box
end
-- Floor items of the world of this type: list of { item, square }.
function floorItems(fullType)
    local out = {}
    for _, sq in pairs(squares) do
        for _, w in ipairs(sq.world) do
            if w.item:getFullType() == fullType then out[#out + 1] = {item = w.item, square = sq} end
        end
    end
    return out
end
-- Same, as plain records { id, mark (mod data CA_Cache), x, y, z } for the Python side.
function floorList(fullType)
    local out = {}
    for i, e in ipairs(floorItems(fullType)) do
        out[i] = {id = e.item.id, mark = e.item.md.CA_Cache, x = e.square.x, y = e.square.y, z = e.square.z}
    end
    return out
end
-- Picked up from the floor into a player's inventory (server side of the vanilla transfer).
function pickUp(item, player)
    item.worldItem.square:transmitRemoveItemFromSquare(item.worldItem)
    player:getInventory():AddItem(item)
end
function moveTo(item, container)
    local from = item:getContainer()
    if from then
        if from.Remove then from:Remove(item) else from:DoRemoveItem(item) end
    end
    container:AddItem(item)
end
'''

# Fiche d'une voix qui donne la mission item : la ferme (lieu target), la planque près du chemin (use=drop).
SHEET_PLACES = [
    {'id': 'farm', 'x': 304, 'y': 303, 'z': 0, 'label': 'Old farmhouse', 'uses': ['target'], 'use': {'target': True}},
    {'id': 'stump', 'x': 320, 'y': 300, 'z': 0, 'label': 'Hollow stump', 'uses': ['drop'], 'use': {'drop': True}},
]
DROP = (320, 300)
AWAY = 700        # x of a player out of view of the farm and the drop (RS_OutOfSight.VIEW_TILES = 100)
COLLECT_HOURS = 6


class ItemMissionTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(ITEM_WORLD)
        # The game loads every server file of the mod: the set-up of the target place registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        rt.eval("require('CoreAI/CA_Caches')").resetForTests()
        self.box = rt.eval(f'crate({DROP[0]}, {DROP[1]}, 0)')
        g = sim.server.g
        for who in ('alice', 'bob'):
            g.PLAYERS[who].x, g.PLAYERS[who].y = 305, 309
        return sim, rt.eval("require('RadioSurvivor/RS_MissionVoice')"), rt.eval("require('RadioSurvivor/RS_State')")

    def sheet(self, sim, params=None, **section):
        rt = sim.server.rt
        places = [rt.table_from({**p, 'uses': rt.table_from(p['uses']), 'use': rt.table_from(p['use'])})
                  for p in SHEET_PLACES]
        fields = {'type': 'item', 'id': 'locket', 'target': 'farm', **section}
        if params is None:
            params = {'item': 'Base.Locket', 'label': "Ellen's locket", 'collect_hours': COLLECT_HOURS}
        fields['params'] = rt.table_from(params)
        fields['drops'] = rt.table_from(fields.get('drops', ['stump']))
        return rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([rt.table_from(fields)]),
                              'places': rt.table_from(places)})

    def start(self, sim, voice, store, sheet):
        return voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'locket')

    def poll(self, sim, store):
        """Server poll of the engine (CA_Missions.observe) with the server copy of alice, after the retry delay."""
        sim.clock.offset += 6000
        present = sim.server.rt.table_from([sim.server.rt.table_from(
            {'player': sim.server.g.PLAYERS.alice, 'character': sim.character('alice')})])
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").observe(store.data, present, store)

    def report(self, sim, voice, store, sheet):
        return voice.report(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)

    def ready(self, sim, m):
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").reportReady(m)

    def started(self, name, **section):
        sim, voice, store = self.world(name)
        sheet = self.sheet(sim, **section)
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        return sim, voice, store, sheet, m

    def floor(self, sim, full_type='Base.Locket'):
        return [convert(e) for e in carnet_helpers.lua_list(sim.server.g.floorList(full_type))]

    def placed(self, name):
        """Mission started, the item placed by the first poll: (sim, voice, store, sheet, m, item)."""
        sim, voice, store, sheet, m = self.started(name)
        self.poll(sim, store)
        found = sim.server.g.floorItems('Base.Locket')
        self.assertEqual(len(found), 1)
        return sim, voice, store, sheet, m, found[1].item

    def walk_away_and_wait(self, sim, store, hours=COLLECT_HOURS + 0.01):
        g = sim.server.g
        for who in ('alice', 'bob'):
            g.PLAYERS[who].x = AWAY
        self.poll(sim, store)
        g.WORLD_AGE_HOURS += hours
        self.poll(sim, store)

    def in_box(self, item):
        return self.box.getItemWithIDRecursiv(self.box, item.getID(item)) is not None

    def test_mission_is_given_by_a_voice_on_the_target_place(self):
        sim, voice, store, sheet, m = self.started('item-start')
        self.assertEqual((m.template, m.donor, m.report, m.state), ('item', 'voice', 'radio', 'active'))
        self.assertEqual((m.place, m.itemType, m.itemLabel, m.itemName), ('Old farmhouse', 'Base.Locket',
                                                                          "Ellen's locket", 'Locket'))
        self.assertEqual((m.bounds.x1, m.bounds.y1, m.bounds.x2, m.bounds.y2), (300, 300, 310, 308))
        self.assertEqual((m.quantity, m.delivered, m.collectHours), (1, 0, COLLECT_HOURS))
        self.assertEqual([d.label for d in carnet_helpers.lua_list(m.drops)], ['Hollow stump'])
        self.assertFalse(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_item_placed_once_in_the_target_building_when_loaded_and_marked(self):
        sim, voice, store = self.world('item-placed')
        g = sim.server.g
        g.HOUSE_LOADED = False
        m = self.start(sim, voice, store, self.sheet(sim))
        self.assertFalse(isinstance(m, tuple), str(m))
        self.poll(sim, store)
        self.assertEqual((self.floor(sim), m.itemId, m.personal.placed), ([], None, False), 'house not loaded')
        g.HOUSE_LOADED = True
        self.assertTrue(self.poll(sim, store))
        floor = self.floor(sim)
        self.assertEqual(len(floor), 1)
        item = floor[0]
        self.assertTrue(300 <= item['x'] < 310 and 300 <= item['y'] < 308 and item['z'] == 0, item)
        self.assertEqual(m.itemId, item['id'])
        self.assertEqual(item['mark'], m.personal.key, 'marked in its mod data')
        self.assertEqual(g.TRANSMITTED, 1, 'sent to the clients')
        saved = store.data.missions[m.id]
        self.assertEqual((saved.itemId, saved.personal.placed), (m.itemId, True))
        for _ in range(3):
            self.poll(sim, store)
        self.assertEqual(len(self.floor(sim)), 1, 'placed once')

    def test_found_deposited_collected_out_of_sight_then_report_accepted(self):
        sim, voice, store, sheet, m, item = self.placed('item-collected')
        g = sim.server.g
        g.pickUp(item, g.PLAYERS.alice)
        self.poll(sim, store)
        self.assertEqual((m.found, m.foundBy), (True, 'alice Doe'))
        self.assertFalse(self.ready(sim, m), 'holding the item is not the objective')
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))
        g.moveTo(item, self.box)
        g.PLAYERS.alice.x, g.PLAYERS.alice.y = DROP
        self.poll(sim, store)
        g.WORLD_AGE_HOURS += 30
        self.poll(sim, store)
        self.assertEqual(m.delivered, 0, 'never collected in front of a player')
        self.assertTrue(self.in_box(item))
        self.walk_away_and_wait(sim, store)
        self.assertEqual(m.delivered, 1)
        self.assertFalse(self.in_box(item), 'collected out of sight after the delay')
        self.assertTrue(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        self.assertEqual(m.state, 'success')

    def test_unmarked_item_of_the_same_type_is_refused_and_left(self):
        sim, voice, store, sheet, m, item = self.placed('item-decoy')
        g = sim.server.g
        decoy = g.instanceItem('Base.Locket')
        g.moveTo(decoy, self.box)
        self.walk_away_and_wait(sim, store)
        self.assertEqual(m.delivered, 0)
        self.assertTrue(self.in_box(decoy), 'an unmarked locket is never taken')
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))
        g.pickUp(item, g.PLAYERS.alice)
        g.moveTo(item, self.box)
        self.walk_away_and_wait(sim, store)
        self.assertEqual(m.delivered, 1)
        self.assertFalse(self.in_box(item))
        self.assertTrue(self.in_box(decoy), 'only the marked item is taken')

    def test_restart_neither_places_twice_nor_credits_twice(self):
        sim, voice, store, sheet, m, item = self.placed('item-restart')
        rt, g = sim.server.rt, sim.server.g
        # Stopped between the saved placing flag and the saved placement: the item lies on the floor already.
        rt.eval('function(m) m.personal.placing, m.personal.placed, m.personal.itemId, m.itemId = true, false, nil, '
                'nil end')(m)
        self.assertTrue(store.save())
        caches = rt.eval("require('CoreAI/CA_Caches')")
        caches.resetForTests()
        self.assertTrue(store.init(False))
        again = store.data.missions[m.id]
        self.poll(sim, store)
        self.assertEqual(len(self.floor(sim)), 1, 'adopted, never placed a second time')
        self.assertEqual(again.itemId, item.getID(item))
        g.pickUp(item, g.PLAYERS.alice)
        g.moveTo(item, self.box)
        self.walk_away_and_wait(sim, store)
        self.assertEqual(again.delivered, 1)
        caches.resetForTests()
        self.assertTrue(store.init(False))
        after = store.data.missions[m.id]
        # The world was not saved after the pickup: the same item is back in the box.
        g.moveTo(item, self.box)
        rt.eval('function(m) m.delivered = 0 end')(after)
        g.PLAYERS.alice.x = DROP[0]
        self.poll(sim, store)
        self.walk_away_and_wait(sim, store)
        self.assertEqual(after.delivered, 0, 'a credited item id is never counted again')
        self.assertTrue(self.in_box(item))

    def test_start_refused_without_item_target_drop_or_with_an_unknown_item(self):
        for case, (params, section, why) in {
                'no item': ({'label': 'Locket'}, {}, 'no_item'),
                'unknown item': ({'item': 'Base.Spaceship'}, {}, 'no_item'),
                'no target': (None, {'target': None}, 'no_target'),
                'no drop': (None, {'drops': ['farm']}, 'no_place')}.items():
            with self.subTest(case=case):
                sim, voice, store = self.world('item-refused-' + case.replace(' ', '-'))
                sheet = self.sheet(sim, params, **section)
                self.assertEqual(self.start(sim, voice, store, sheet), (None, why))
                self.assertEqual([x for x in sim.state().missions.values() if x.donor == 'voice'], [])

    def test_npc_fiches_are_never_offered_an_item_mission(self):
        sim, _, _ = self.world('item-npc')
        offer = sim.server.rt.eval("""(function()
            local c = require('CoreAI/CA_MissionConfig').Missions.item
            return require('CoreAI/CA_MissionItem').offer(c, {id = 'npc1', incarnation = 1}, {}, nil)
        end)()""")
        self.assertIsNone(offer)

    def test_projection_never_leaks_the_item_id(self):
        sim, voice, store, sheet, m, item = self.placed('item-projection')
        p = sim.server.rt.eval("require('CoreAI/CA_Missions')").projection(m, sim.character('alice'))
        values = {k: convert(v) for k, v in p.items()}
        self.assertEqual((values['template'], values['itemType'], values['itemLabel']),
                         ('item', 'Base.Locket', "Ellen's locket"))
        self.assertNotIn(item.getID(item), [v for v in values.values() if isinstance(v, (int, float))])
        self.assertNotIn('itemId', values)

    def test_notebook_page_and_map_circle(self):
        sim, voice, store, sheet, m = self.started('item-page')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute(CLIENT_SCRIPTS)
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        drawn = [convert(s) for s in carnet_helpers.lua_list(c.rt.eval('mapSymbols()'))]
        texts = [s['text'] for s in drawn if s['kind'] == 'text']
        self.assertIn('IGUI_CA_MapZoneItem|Custom', texts)
        self.assertIn('IGUI_CA_MapZoneDepot|Hollow stump', texts)
        c.g.RS_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ("IGUI_CA_ItemWhat|Ellen's locket", 'IGUI_CA_ItemPlace|Old farmhouse', 'IGUI_CA_ItemMapZone',
                    'IGUI_CA_ItemNotFound', 'IGUI_CA_ItemDropIt', 'IGUI_RS_DeadDropPoints|Hollow stump',
                    'IGUI_CA_ItemOnlyThis'):
            self.assertIn(key, text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for an item mission')
        self.poll(sim, store)
        found = sim.server.g.floorItems('Base.Locket')
        sim.server.g.pickUp(found[1].item, sim.server.g.PLAYERS.alice)
        self.poll(sim, store)
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_ItemFound|alice Doe', window.detail.text)

    def test_item_name_from_the_scripts_without_label(self):
        sim, voice, store = self.world('item-unlabelled')
        m = self.start(sim, voice, store, self.sheet(sim, {'item': 'Base.Photo'}))
        self.assertEqual((m.itemType, m.itemLabel, m.itemName), ('Base.Photo', '', 'Photo'))
        brief = sim.server.rt.eval("require('CoreAI/CA_Missions')").voiceBrief(m)
        self.assertIn('Find the Photo at Old farmhouse', brief.job)


# Client: item scripts of the notebook (ScriptManager.FindItem, Item.getDisplayName), same classes as the server.
CLIENT_SCRIPTS = r'''
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local Script = class('Item')
function Script:getDisplayName() return self.displayName end
local Scripts = class('ScriptManager')
function Scripts:FindItem(name) if name == 'Base.Locket' then return setmetatable({displayName = 'Locket'}, Script) end end
local SCRIPTS = setmetatable({}, Scripts)
getScriptManager = function() return SCRIPTS end
'''

# E20-T02: fields of mission= (RS_MissionVoice.context); per-template facts come as job and facts only.
GENERIC_FIELDS = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}


class ItemBriefTests(unittest.TestCase):
    setUp, tearDown = ItemMissionTests.setUp, ItemMissionTests.tearDown
    voice_sim, world, sheet, start, poll = (ItemMissionTests.voice_sim, ItemMissionTests.world, ItemMissionTests.sheet,
                                            ItemMissionTests.start, ItemMissionTests.poll)
    started, placed, walk_away_and_wait = (ItemMissionTests.started, ItemMissionTests.placed,
                                           ItemMissionTests.walk_away_and_wait)

    def told(self, voice, ctx):
        field = voice.field(ctx)
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), GENERIC_FIELDS)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(secrets=[], places=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_job_and_verified_facts_told_to_the_voice(self):
        sim, voice, store, sheet, m, item = self.placed('item-brief')
        mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
        self.assertEqual((mission['kind'], mission['place']), ('item', 'Old farmhouse'))
        self.assertIn("Find Ellen's locket at Old farmhouse", mission['job'])
        self.assertIn('drop points (Hollow stump)', mission['job'])
        self.assertNotIn(str(item.getID(item)), mission['job'] + prompt)
        self.assertIn('Item found by a participant (checked by the server): no.', prompt)
        self.assertIn('Item collected at a drop point: no.', prompt)
        self.assertIn('out of sight of everyone', prompt)
        g = sim.server.g
        g.pickUp(item, g.PLAYERS.alice)
        self.poll(sim, store)
        g.moveTo(item, self.box)
        self.walk_away_and_wait(sim, store)
        heard = voice.heard(sheet, g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('report_due', True))
        _, prompt = self.told(voice, heard)
        self.assertIn('Item found by a participant (checked by the server): yes.', prompt)
        self.assertIn('Item collected at a drop point: yes.', prompt)

    in_box = ItemMissionTests.in_box


class ItemSheetTests(unittest.TestCase):
    """The sheet reader accepts an item section with a target place, a real item type and a label, and refuses a bad
    or unknown item type and any other key, with the real RS_Persona and the template registered as at game load."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        cls.lua = LuaPersona(cls.folder)
        cls.lua.rt.eval('require("CoreAI/CA_MissionItem")')
        cls.lua.rt.execute(SHEET_SCRIPTS)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, body: str):
        (self.folder / 'case.txt').write_bytes((BASE + '[mission m]\n' + body + PROMPT).encode('utf-8'))
        return self.lua.read('case.txt')

    def test_valid_section(self):
        p = self.read('type=item\ntarget=clinic\nitem=Base.Locket\nlabel=Her mother\'s locket\ndrops=church\n'
                      'collect_hours=4\n')
        self.assertFalse(isinstance(p, tuple), p)
        m = p.missions[1]
        self.assertEqual((m.type, m.target, m.params.item, m.params.label, m.params.collect_hours),
                         ('item', 'clinic', 'Base.Locket', "Her mother's locket", 4))

    def test_syntax_only_without_the_item_scripts(self):
        self.lua.rt.execute('local keep = getScriptManager; getScriptManager = nil; RS_KEEP_SCRIPTS = keep')
        try:
            p = self.read('type=item\ntarget=clinic\nitem=Base.Spaceship\n')
            self.assertFalse(isinstance(p, tuple), p)
        finally:
            self.lua.rt.execute('getScriptManager = RS_KEEP_SCRIPTS')

    def test_refusals(self):
        for body, why in (
                ('type=item\ntarget=clinic\nitem=Locket\n',
                 "line 16: bad item 'Locket' (Module.Type of an item script, e.g. Base.Locket)"),
                ('type=item\ntarget=clinic\nitem=Base.Spaceship\n', "line 16: unknown item 'Base.Spaceship'"),
                ('type=item\ntarget=church\nitem=Base.Locket\n', "line 15: place 'church' has no use=target"),
                ('type=item\ntarget=clinic\nitem=Base.Locket\ncount=2\n',
                 "line 17: unknown key 'count' for mission type 'item'")):
            with self.subTest(body=body):
                self.assertEqual(self.read(body), (None, why))


# Item scripts read by the sheet reader on the server (ScriptManager.FindItem).
SHEET_SCRIPTS = r'''
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local Script = class('Item')
local Scripts = class('ScriptManager')
function Scripts:FindItem(name) if name == 'Base.Locket' then return setmetatable({}, Script) end end
local SCRIPTS = setmetatable({}, Scripts)
getScriptManager = function() return SCRIPTS end
'''


if __name__ == '__main__':
    unittest.main()
