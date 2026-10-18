"""Gabarit « récupérer » et caches (E11-T06, RS_MissionRecover.lua, RS_Caches.lua) sur le banc du carnet : vrai Lua
serveur et client, pont absent, doublures de la métagrille, des cases chargées, des objets au sol et des conteneurs.

Doublures seulement (aucune API Java prouvée ici) : IsoGridSquare.AddWorldInventoryItem(item, x, y, z, true) pose
l'objet donné (même identifiant) dans getWorldObjects() ; transmitRemoveItemFromSquare(wo) l'en retire
(IsoGridSquare.java:5072-5098, RemoveItemFromSquarePacket.java:101-142) ; InventoryContainer.getItemContainer rend un
inventaire du banc ; InventoryItem.hasModData / getModData ; getCell():getGridSquare rend nil hors des zones chargées
par le test ; BuildingDef.isFullyStreamedIn et RoomDef.isExplored sont des drapeaux du test ; le foyer du groupe du
demandeur vient de RS_NPCProvider.presence (doublure du moteur de PNJ).
python RadioSurvivor/tests/test_mission_recover.py
"""
from __future__ import annotations

import tempfile
import unittest
import unittest.mock
from pathlib import Path

from test_carnet import (MAP_DOUBLE, NOTEBOOK_UI, SCOUT_GRID, TESTS_SHARED, ReportCases, Simulation, convert, count,
                         report_turn)
from test_protocol import lua_list
import npc_protocol as protocol

# House 5002 of SCOUT_GRID: 100..110 x 10..20, z 0; site point = centre of its room rect (104, 14). Home of the
# requester's group (FAKE_PROVIDER.presence): (14, 10, 0), depot square 11..17 x 7..13.
RECOVER_WORLD = r"""
RECOVER = {loaded = {}, streamed = true, explored = false, occupied = {}, stairs = {}, placed = {}, floorRemovals = {},
    home = {away = false, x = 14, y = 10, z = 0}}
FAKE_PROVIDER.presence = function(id) return RECOVER.home end
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local function jlist(items)
    local l = {items = items}
    function l:size() return #self.items end
    function l:get(i) local v = self.items[i + 1]; if v == nil then error('IndexOutOfBounds ' .. i) end; return v end
    return l
end
local def = {}
function def:isFullyStreamedIn() return RECOVER.streamed end
function def:getRooms() return jlist({{isExplored = function() return RECOVER.explored end}}) end
local building = {getDef = function() return def end}
local squares = {}
function recoverSquare(x, y, z)
    local k = key(x, y, z)
    if not squares[k] then
        local sq = {x = x, y = y, z = z, floor = {}, objects = {}}
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:getZ() return self.z end
        function sq:isFree(b) return not RECOVER.occupied[key(self.x, self.y, self.z)] end
        function sq:HasStairs() return RECOVER.stairs[key(self.x, self.y, self.z)] == true end
        function sq:getBuilding()
            if self.x >= 100 and self.x < 110 and self.y >= 10 and self.y < 20 then return building end
            return nil
        end
        function sq:getWorldObjects() return jlist(self.floor) end
        function sq:getObjects() return jlist(self.objects) end
        -- AddWorldInventoryItem(InventoryItem, x, y, z, transmit): the given item, in an IsoWorldInventoryObject.
        function sq:AddWorldInventoryItem(it, ox, oy, oz, transmit)
            assert(type(it) == 'table' and it.id, 'AddWorldInventoryItem without an item')
            local wo = {item = it, square = self, transmit = transmit}
            function wo:getItem() return self.item end
            it.worldItem = wo
            self.floor[#self.floor + 1] = wo
            RECOVER.placed[#RECOVER.placed + 1] = it
            return it
        end
        function sq:transmitRemoveItemFromSquare(wo)
            for i, found in ipairs(self.floor) do
                if found == wo then
                    table.remove(self.floor, i)
                    RECOVER.floorRemovals[#RECOVER.floorRemovals + 1] = wo.item.id
                    return i - 1
                end
            end
            return -1
        end
        squares[k] = sq
    end
    return squares[k]
end
-- A crate with one container on a square.
function recoverCrate(x, y, z)
    local inv = inventory()
    local crate = {inv = inv}
    function crate:getContainerCount() return 1 end
    function crate:getContainerByIndex(i) return self.inv end
    local sq = recoverSquare(x, y, z)
    sq.objects[#sq.objects + 1] = crate
    return inv
end
-- The player puts an item on the floor of a square (same item, same id).
function recoverDrop(it, x, y, z)
    if it.container then it.container:Remove(it) end
    local sq = recoverSquare(x, y, z)
    local wo = {item = it, square = sq}
    function wo:getItem() return self.item end
    sq.floor[#sq.floor + 1] = wo
    return wo
end
-- The player picks an item up from the floor.
function recoverTake(it, inv)
    for _, sq in pairs(squares) do
        for i, wo in ipairs(sq.floor) do
            if wo.item == it then table.remove(sq.floor, i) end
        end
    end
    inv:AddItem(it)
end
function loadArea(x1, y1, x2, y2)
    RECOVER.loaded[#RECOVER.loaded + 1] = {x1, y1, x2, y2}
end
local function loaded(x, y)
    for _, a in ipairs(RECOVER.loaded) do
        if x >= a[1] and x < a[3] and y >= a[2] and y < a[4] then return true end
    end
    return false
end
local baseCell = getCell
getCell = function()
    local cell = baseCell()
    if not cell then return nil end
    cell.getGridSquare = function(_, x, y, z)
        if z == 0 and loaded(x, y) then return recoverSquare(x, y, z) end
        return nil
    end
    return cell
end
local baseInstance = instanceItem
instanceItem = function(kind)
    local it = baseInstance(kind)
    it.md = nil
    it.hasModData = function(self) return self.md ~= nil end
    it.getModData = function(self) self.md = self.md or {}; return self.md end
    it.setWorldItem = function(self, wo) self.worldItem = wo end
    it.getDisplayName = function(self) return self.kind end
    if kind == 'Base.Bag_DuffelBag' then
        it.bag = inventory()
        it.getItemContainer = function(self) return self.bag end
    end
    return it
end
"""


class RecoverMissionTests(unittest.TestCase):
    """Cache posée une seule fois au chargement du lieu, même après redémarrage ; dépôt qui vérifie le sac marqué par
    son identifiant ; plafond d'offres du pont ; action place_cache d'une voix."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-recover-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, sim):
        sim.server.rt.execute(SCOUT_GRID)
        sim.server.g.scoutHouse(5001, 20, 12, 8, 8)    # too close to the requester
        sim.server.g.scoutHouse(5002, 100, 10, 10, 10)  # reachable
        sim.server.rt.execute(RECOVER_WORLD)
        sim.server.rt.eval("require('RadioSurvivor/RS_MissionRecover')").resetForTests()
        sim.server.rt.eval("require('RadioSurvivor/RS_Caches')").resetForTests()

    def recover_sim(self, name='recover'):
        sim = Simulation(self.path / name)
        self.world(sim)
        sim.add_client('alice'); sim.add_client('bob'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        return sim, npc, record, missions

    def catalog(self, sim, npc, record):
        return convert(sim.server.g.RS_CarnetServer.offerCatalogFor(npc, record))

    def active(self, name='recover'):
        sim, npc, record, missions = self.recover_sim(name)
        self.assertIn('recover_v1', self.catalog(sim, npc, record))
        m = missions.create(sim.state(), npc, sim.character('alice'), 'recover_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        return sim, npc, m, missions

    def poll(self, sim, ms=1001):
        sim.clock.offset += ms; sim.tick()

    def place(self, sim, m):
        sim.server.g.loadArea(90, 0, 130, 40)
        self.poll(sim, 6000)
        self.assertTrue(m.cache.placed)
        return sim.server.g.RECOVER.placed[len(lua_list(sim.server.g.RECOVER.placed))]

    def test_offer_only_for_an_npc_whose_group_has_a_home(self):
        sim, npc, record, missions = self.recover_sim('offer')
        catalog = self.catalog(sim, npc, record)
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'recover_v1', 'scout_v1', 'signal_v1'])  # signal_v1: required mod Signal Smoke (bench double), same places as scout
        offer = catalog['recover_v1']
        self.assertEqual(set(offer), {'kind', 'item', 'cache', 'place', 'clues', 'report', 'durationMs', 'rewardType',
                                      'rewardCount'})
        self.assertEqual((offer['kind'], offer['item'], offer['place'], offer['report']),
                         ('recover', 'bag', 'house', 'in_person'))
        # Tables of RS_Config.Caches.order ('radio' added by E11: drawn one time in five).
        self.assertIn(offer['cache'], ('food', 'medical', 'ammo', 'tools', 'radio'))
        self.assertEqual((offer['durationMs'], offer['rewardType'], offer['rewardCount']), (7200000, 'Base.Bullets9mm', 20))
        clues = [offer['clues'][i] for i in sorted(offer['clues'])]
        self.assertTrue(clues and clues[0].startswith('The place is '), clues)
        self.assertFalse(any(ch.isdigit() for line in clues for ch in line), 'a clue carries a number')
        self.assertEqual(self.catalog(sim, npc, record)['recover_v1'], offer, 'the kept place changed')
        # A radio voice donor (no fiche), and an NPC whose provider knows no home, get no recover offer.
        recover = sim.server.rt.eval("require('RadioSurvivor/RS_MissionRecover')")
        c = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Missions.recover")
        donor = sim.server.rt.table_from({'id': 'voice:walt:c1', 'missionCount': 0})
        self.assertIsNone(recover.offer(c, donor, None, sim.server.g.PLAYERS.alice))
        self.assertIsNone(sim.server.rt.eval("require('RadioSurvivor/RS_MissionVoice')").TEMPLATES['recover'])
        sim.server.g.RECOVER.home = sim.server.rt.table_from({'away': False})
        self.assertNotIn('recover_v1', self.catalog(sim, npc, record))
        sim.server.g.RECOVER.home = None
        self.assertNotIn('recover_v1', self.catalog(sim, npc, record))

    def test_mission_carries_the_areas_and_never_a_coordinate_to_the_bridge(self):
        sim, npc, m, missions = self.active('create')
        self.assertEqual((m.id, m.template, m.offer, m.place), (npc.id + '-recover1', 'recover', 'recover_v1', 'house'))
        self.assertEqual(convert(m.spot), {'x': 104, 'y': 14, 'z': 0})
        self.assertEqual(convert(m.depot), {'x': 14, 'y': 10, 'z': 0, 'r': 3})
        cache = convert(m.cache)
        self.assertEqual((cache['key'], cache['placed'], cache['placing']), (m.id, False, False))
        self.assertEqual(cache['spot'], {'x': 104, 'y': 14, 'z': 0})
        context = convert(missions.context(m))
        self.assertEqual((context['kind'], context['placed'], context['found'], context['item'], context['report'],
                          context['toReport']), ('recover', False, False, 'bag', 'in_person', False))
        self.assertEqual(context['cache'], cache['table'])
        for key in ('spot', 'bounds', 'mapZone', 'depot', 'depotZone', 'itemId', 'at', 'x', 'y'):
            self.assertNotIn(key, context)
        row = convert(sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['template'], row['cache'], row['placed'], row['found']), ('recover', cache['table'],
                                                                                      False, False))
        self.assertEqual(row['mapZone'], convert(m.mapZone))
        self.assertEqual(row['depotZone'], {'x': 14, 'y': 10, 'r': 3})
        for key in ('spot', 'bounds', 'depot', 'siteKey', 'itemId'):
            self.assertNotIn(key, row)
        zone = convert(m.mapZone)
        for px, py in ((100, 10), (110, 10), (100, 20), (110, 20)):
            self.assertLessEqual(((px - zone['x']) ** 2 + (py - zone['y']) ** 2) ** 0.5, zone['r'])
        # Bob is no participant: neither area in his notebook.
        sim.command('bob', 'snapshot', world=sim.clients['bob'].g.RS_CarnetClient.world,
                    run=sim.clients['bob'].g.RS_CarnetClient.run)
        for p in lua_list(sim.clients['bob'].g.RS_CarnetClient.snapshot.missions or {}):
            self.assertNotIn('depotZone', convert(p))

    def test_cache_placed_once_when_its_building_is_loaded_even_after_a_restart(self):
        sim, npc, m, missions = self.active('place')
        g = sim.server.g
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertEqual((m.cache.placed, len(lua_list(g.RECOVER.placed))), (False, 0))
        # Loaded, but the building has not passed its vanilla stories yet.
        g.RECOVER.streamed = False
        g.loadArea(90, 0, 130, 40)
        self.poll(sim, 6000)
        self.assertEqual((m.cache.placed, len(lua_list(g.RECOVER.placed))), (False, 0))
        # A room explored is enough. The site square is taken: nearest free square of the same building.
        g.RECOVER.explored = True
        g.RECOVER.occupied['104,14,0'] = True
        revision = m.revision
        self.poll(sim, 6000)
        self.assertTrue(m.cache.placed)
        self.assertGreater(m.revision, revision)
        [bag] = list(lua_list(g.RECOVER.placed))
        at = convert(m.cache.at)
        self.assertEqual(max(abs(at['x'] - 104), abs(at['y'] - 14)), 1)
        self.assertEqual((bag.kind, bag.md.RS_Cache, m.cache.itemId), ('Base.Bag_DuffelBag', m.id, bag.id))
        self.assertTrue(bag.worldItem.transmit, 'not sent to the clients')
        table = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Caches.tables")[m.cache.table]
        expected = sorted(kind for line in lua_list(table) for kind in [lua_list(line)[0]] * lua_list(line)[1])
        self.assertEqual(sorted(it.kind for it in lua_list(bag.bag['items'])), expected)
        # No second bag by the next polls nor after a restart (placed saved at once).
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertEqual(len(lua_list(g.RECOVER.placed)), 1)
        saved = self.path / 'place'
        restart = Simulation(saved, sim.clock, saved_players=sim.saved())
        self.world(restart)
        restart.server.g.loadArea(90, 0, 130, 40)
        restart.add_client('alice')
        old = restart.mission()
        self.assertEqual((old.template, old.cache.placed, old.cache.itemId), ('recover', True, bag.id))
        for _ in range(3):
            restart.clock.offset += 6000; restart.tick()
        self.assertEqual(len(lua_list(restart.server.g.RECOVER.placed)), 0)

    def test_stop_between_registry_and_placement_adopts_the_marked_bag_or_places_it_again(self):
        sim, npc, m, missions = self.active('adopt')
        g = sim.server.g
        bag = self.place(sim, m)
        # Stop after the bag reached the floor but before `placed` was saved: the marked bag is adopted.
        m.cache.placed, m.cache.placing, m.cache.itemId = False, True, None
        self.poll(sim, 6000)
        self.assertEqual((m.cache.placed, m.cache.itemId, len(lua_list(g.RECOVER.placed))), (True, bag.id, 1))
        # A floor bag of the same type without this mark is not the cache; the chunk saved without the bag: again.
        g.recoverTake(bag, g.inventory())
        other = g.instanceItem('Base.Bag_DuffelBag')
        other.getModData(other).RS_Cache = 'another-mission'
        g.recoverDrop(other, 104, 14, 0)
        m.cache.placed, m.cache.placing, m.cache.itemId = False, True, None
        self.poll(sim, 6000)
        placed = list(lua_list(g.RECOVER.placed))
        self.assertEqual(len(placed), 2)
        self.assertEqual((m.cache.placed, m.cache.itemId), (True, placed[1].id))
        self.assertNotEqual(m.cache.itemId, other.id)
        # A failed save of `placing` places nothing.
        store = g.RS_CarnetServer.store
        m.cache.placed, m.cache.placing = False, False
        saved = store.save
        store.save = lambda *a: False
        try:
            self.poll(sim, 6000)
        finally:
            store.save = saved
        self.assertEqual((m.cache.placed, len(lua_list(g.RECOVER.placed))), (False, 2))

    def test_depot_accepts_only_the_marked_bag_by_id_in_a_container(self):
        sim, npc, m, missions = self.active('depot')
        g, char = sim.server.g, sim.character('alice')
        bag = self.place(sim, m)
        g.loadArea(0, 0, 40, 40)
        alice = g.PLAYERS.alice
        # Another bag, same type, same mark and same contents, left at the depot: not the cache.
        forged = g.instanceItem('Base.Bag_DuffelBag')
        forged.getModData(forged).RS_Cache = m.id
        g.recoverDrop(forged, 14, 10, 0)
        self.poll(sim)
        self.assertEqual((m.state, m.found), ('active', False))
        # Held by a non-participant: not found.
        g.recoverTake(bag, g.PLAYERS.bob.inv)
        self.poll(sim)
        self.assertFalse(m.found)
        # Alice takes it: found by the server poll; dropped outside the depot area: nothing.
        g.PLAYERS.bob.inv.Remove(g.PLAYERS.bob.inv, bag)
        alice.inv.AddItem(alice.inv, bag)
        self.poll(sim)
        self.assertEqual((m.found, m.foundBy), (True, 'alice Doe'))
        g.recoverDrop(bag, 18, 10, 0)
        self.poll(sim)
        self.assertEqual(m.state, 'active')
        # Into the crate of the depot: the bag leaves the world, the objective is met (E11-T13: still to report); the
        # report to the requester gives success, reputation and reward lot as M01.
        g.recoverTake(bag, alice.inv)
        crate = g.recoverCrate(12, 12, 0)
        alice.inv.Remove(alice.inv, bag)
        crate.AddItem(crate, bag)
        self.poll(sim)
        self.assertEqual((m.state, m.deposited), ('active', True))
        report_turn(sim, 'alice', 'Your bag is in the crate.', 'report_done')
        self.assertEqual((m.state, m.deposited), ('success', True))
        self.assertIn(bag.id, list(lua_list(g.REMOVALS)))
        self.assertIsNone(crate.getItemWithIDRecursiv(crate, bag.id))
        self.assertEqual(len(lua_list(sim.server.g.RECOVER.floorRemovals)), 0)
        outcome = sim.state().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(npc.mission)
        row = convert(sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1])
        self.assertNotIn('mapZone', row); self.assertNotIn('depotZone', row)
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, char)
        # The forged bag is still at the depot.
        floor = g.recoverSquare(14, 10, 0).floor
        self.assertEqual([wo.item.id for wo in lua_list(floor)], [forged.id])

    def test_depot_on_the_floor_and_no_notebook_contribution(self):
        sim, npc, m, missions = self.active('floor')
        g, char = sim.server.g, sim.character('alice')
        bag = self.place(sim, m)
        store = g.RS_CarnetServer.store
        # The notebook delivery commands are no way to finish it.
        ok, reason = missions.report(store, m, g.PLAYERS.alice, char, sim.server.rt.table_from([bag.id]), 'forged')
        self.assertEqual((ok, reason), (False, 'State'))
        g.recoverTake(bag, g.PLAYERS.alice.inv)
        # Depot square not loaded: nothing, even with the bag dropped there.
        g.recoverDrop(bag, 16, 8, 0)
        self.poll(sim)
        self.assertEqual(m.state, 'active')
        g.loadArea(0, 0, 40, 40)
        self.poll(sim)
        self.assertEqual((m.state, m.deposited), ('active', True))
        # E11-T13: the notebook button "Report" next to the requester (way without the bridge).
        sim.request_mission('alice', 'report')
        self.assertEqual(m.state, 'success')
        self.assertEqual(list(lua_list(g.RECOVER.floorRemovals)), [bag.id])
        self.assertEqual(len(lua_list(g.recoverSquare(16, 8, 0).floor)), 0)

    def test_expired_mission_places_no_cache(self):
        sim, npc, m, missions = self.active('expiry')
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual(m.state, 'failed')
        sim.server.g.loadArea(90, 0, 130, 40)
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertEqual((m.cache.placed, len(lua_list(sim.server.g.RECOVER.placed))), (False, 0))
        row = convert(sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1])
        self.assertNotIn('mapZone', row); self.assertNotIn('depotZone', row)

    def test_offer_cap_shared_by_the_server_and_the_bridge(self):
        sim, npc, record, missions = self.recover_sim('cap')
        config = sim.server.rt.eval("require('RadioSurvivor/RS_Config')")
        self.assertEqual(config.MAX_OFFERS, protocol.MAX_OFFERS)
        config.MAX_OFFERS = 2
        try:
            catalog = self.catalog(sim, npc, record)
        finally:
            config.MAX_OFFERS = protocol.MAX_OFFERS
        # Registration order: deliver, scout, clear, retrieve_id, recover (clear and retrieve_id not offered here).
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'scout_v1'])
        # The bridge accepts MAX_OFFERS offers and rejects one more.
        base = {'version': 2, 'kind': 'npc_talk', 'id': 'r-1-n', 'world': 'w', 'run': 'r', 'npc': 'n', 'order': 1,
                'revision': 1, 'sent': 1, 'channel': 'say', 'language': 'EN', 'character': 'c1', 'text': 'Work?',
                'personality': {}, 'context': {}}

        def record_of(n):
            value = dict(base, offers={f'o{i}_v1': {'kind': 'scout'} for i in range(n)})
            return {'id': 'r-1-n', 'kind': 'npc_talk', 'payload': protocol.encode(value).hex()}
        self.assertEqual(len(protocol.unpack_request(record_of(protocol.MAX_OFFERS))['offers']), protocol.MAX_OFFERS)
        with self.assertRaisesRegex(ValueError, 'offers size'):
            protocol.unpack_request(record_of(protocol.MAX_OFFERS + 1))

    def test_voice_action_place_cache_one_per_mission_at_its_place(self):
        sim, npc, record, missions = self.recover_sim('voice')
        g, rt = sim.server.g, sim.server.rt
        char = sim.character('alice')
        actions = rt.eval("require('RadioSurvivor/RS_Actions')")
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        store = g.RS_CarnetServer.store
        sheet = rt.eval("{id = 'walt', name = 'Walt', actions = {'say', 'place_cache', 'start_mission'}, budgets = {}}")
        ctx = lambda: rt.table_from({'player': g.PLAYERS.alice, 'cid': char, 'khz': 91200, 'day': '1993-07-12'})

        def decide(*proposed):
            listed = rt.eval('{}')
            for i, p in enumerate(proposed, 1):
                listed[i] = rt.table_from(dict(p))
            out = actions.decide(sheet, 'alice', listed, int(sim.clock()), ctx())
            return [(d.type, d.accepted, d.reason) for d in lua_list(out)]
        # No mission of this voice for the caller yet; a table outside the closed list.
        self.assertEqual(decide({'type': 'place_cache', 'table': 'food'}), [('place_cache', False, 'no_mission')])
        self.assertEqual(decide({'type': 'place_cache', 'table': 'gold'}), [('place_cache', False, 'bad_params')])
        self.assertEqual(decide({'type': 'place_cache', 'table': 'food', 'x': 3}), [('place_cache', False, 'bad_params')])
        m = voice.start(store, sheet, char, g.PLAYERS.alice, 91200, 'scout')
        self.assertIsNotNone(m)
        self.assertEqual(decide({'type': 'place_cache', 'table': 'food'}), [('place_cache', False, 'not_done')])
        m.state = 'success'
        self.assertEqual(decide({'type': 'place_cache', 'table': 'food'}), [('place_cache', False, 'no_reward')])
        # The action can only retry an already selected server reward, never choose its table or location.
        caches = rt.eval("require('RadioSurvivor/RS_Caches')")
        spot, bounds = caches.siteOf(m)
        caches.attach(m, 'food', spot, bounds)
        m.extendedReward = rt.table_from({'kind': 'cache', 'status': 'applied'})
        self.assertEqual(decide({'type': 'place_cache', 'table': 'food'}), [('place_cache', True, 'ok')])
        self.assertEqual(convert(m.cache)['table'], 'food')
        self.assertEqual(convert(m.cache)['spot'], {'x': 105, 'y': 15, 'z': 0})
        sim.clock.offset += 61000
        self.assertEqual(decide({'type': 'place_cache', 'table': 'ammo'}), [('place_cache', False, 'bad_table')])
        # Placed by the notebook loop once its building is loaded, once.
        g.loadArea(90, 0, 130, 40)
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertTrue(m.cache.placed)
        [bag] = list(lua_list(g.RECOVER.placed))
        self.assertEqual(bag.md.RS_Cache, m.id)
        at = convert(m.cache.at)
        self.assertTrue(100 <= at['x'] < 110 and 10 <= at['y'] < 20, at)

    def test_notebook_page_and_map_labels(self):
        sim, npc, m, missions = self.active('notebook')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        drawn = [convert(s) for s in lua_list(c.rt.eval('mapSymbols()'))]
        texts = sorted(s['text'] for s in drawn if s['kind'] == 'text')
        self.assertEqual(texts, ['IGUI_RS_MapZoneCache|Real Bandit', 'IGUI_RS_MapZoneDepot|Real Bandit'])
        rings = sorted((s['x'], s['y']) for s in drawn if s['kind'] == 'texture')
        self.assertIn((14, 10), rings)
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        label = c.rt.eval('RS_CarnetClient.window.list.items[1].text')
        self.assertTrue(label.startswith('IGUI_RS_Recover - '), label)
        for key in ('IGUI_RS_ScoutPlace', 'IGUI_RS_ScoutClues', 'IGUI_RS_RecoverMapZone', 'IGUI_RS_RecoverCache',
                    'IGUI_RS_Cache_' + m.cache.table, 'IGUI_RS_RecoverNotFound', 'IGUI_RS_RecoverDepotZone',
                    'IGUI_RS_RecoverReport'):
            self.assertIn(key, window.detail.text)
        self.assertNotIn('IGUI_RS_NoRefund', window.detail.text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a recover mission')
        bag = self.place(sim, m)
        sim.server.g.recoverTake(bag, sim.server.g.PLAYERS.alice.inv)
        self.poll(sim)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_RS_RecoverFound|alice Doe', window.detail.text)
        # Success: both circles removed from the map.
        sim.server.g.loadArea(0, 0, 40, 40)
        sim.server.g.recoverDrop(bag, 14, 10, 0)
        self.poll(sim)
        self.assertEqual(m.state, 'active')
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_RS_State_toReport', window.detail.text)
        report_turn(sim, 'alice', 'The bag is at your depot.', 'report_done')
        self.assertEqual(m.state, 'success')
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        self.assertEqual([s for s in (convert(x) for x in lua_list(c.rt.eval('mapSymbols()')))
                          if s['kind'] == 'text'], [])

    def test_offline_bridge_tells_the_offer(self):
        req = {'kind': 'npc_talk', 'language': 'EN', 'offers': {'recover_v1': {
            'kind': 'recover', 'item': 'bag', 'cache': 'medical', 'place': 'house',
            'clues': ['The place is a house.'], 'report': 'depot', 'durationMs': 7200000,
            'rewardType': 'Base.Bullets9mm', 'rewardCount': 20}},
            'context': {}, 'character': 'c1', 'text': 'Work?', 'id': 'r1'}
        with unittest.mock.patch.object(protocol, 'bounded_reply', lambda r, reply: reply):
            reply = protocol.offline(req, intent='')
            self.assertEqual((reply['intent'], reply['offer']), ('offer', 'recover_v1'))
            self.assertIn('bag of medical supplies', reply['text'])
            self.assertIn('120 minutes', reply['text'])
            fr = protocol.offline(dict(req, language='FR'), intent='')
            self.assertIn('sac de matériel de soin', fr['text'])

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.mission.recover (dev mod) run by the real RST engine on the server machine; the server move of
        RST_Fixtures is played directly on the server copy of the player, which loads the area around it."""
        sim, npc, record, missions = self.recover_sim('suite')
        shared = (TESTS_SHARED.as_posix() + '/?.lua')
        sim.server.rt.execute(f'package.path = [[{shared};]] .. package.path')
        sim.server.rt.execute("""
            local relay = sendServerCommand
            sendServerCommand = function(p, module, command, args)
                if module == 'RST' then
                    p.x, p.y, p.z = args.x, args.y, args.z
                    loadArea(math.floor(args.x) - 40, math.floor(args.y) - 40, math.floor(args.x) + 40, math.floor(args.y) + 40)
                    return
                end
                return relay(p, module, command, args)
            end
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-recover' end, getMetaGrid = function() return grid end} end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- the server double has no current square: moves do not wait for it
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionRecover.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("rs.mission.recover", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(400):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual(results, {'cache placed once, another bag refused, the cache accepted at the depot by id':
                                   ('PASS', None)})
        self.assertEqual((alice.x, alice.y), (10, 10), 'the fixture did not move the player back')
        self.assertEqual(count(sim.state().missions), 0, 'the suite touched the notebook state')


class RecoverReportTests(ReportCases, unittest.TestCase):
    """E11-T13 : compte rendu au PNJ demandeur d'une mission « récupérer » (cas communs de ReportCases)."""

    setUp, tearDown, world, recover_sim, catalog, poll, place = (
        RecoverMissionTests.setUp, RecoverMissionTests.tearDown, RecoverMissionTests.world,
        RecoverMissionTests.recover_sim, RecoverMissionTests.catalog, RecoverMissionTests.poll,
        RecoverMissionTests.place)

    def active(self, name):
        return RecoverMissionTests.active(self, name)

    def fulfil(self, sim, m):
        g = sim.server.g
        bag = self.place(sim, m)
        g.recoverTake(bag, g.PLAYERS.alice.inv)
        self.poll(sim)
        g.loadArea(0, 0, 40, 40)
        g.recoverDrop(bag, 14, 10, 0)
        self.poll(sim)
        self.assertTrue(m.deposited)


if __name__ == '__main__':
    unittest.main(verbosity=2)
