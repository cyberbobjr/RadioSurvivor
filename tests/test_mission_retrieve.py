"""Gabarit « retrouver » (E11-T05, CA_MissionRetrieve.lua) sur le banc du carnet : vrai Lua serveur et client,
pont absent, doublures de la métagrille, des cases chargées et des cadavres.

Doublures seulement (aucune API Java prouvée ici) : RandomizedWorldBase.createRandomDeadBody rend un cadavre dont le
conteneur est un inventaire du banc ; InventoryItem.nameAfterDescriptor écrit « <nom du script>: Prénom Nom »
(InventoryItem.java:4768-4775) ; getCell():getGridSquare rend nil hors des zones chargées par le test ;
BuildingDef.isFullyStreamedIn et RoomDef.isExplored sont des drapeaux du test.
python RadioSurvivor/tests/test_mission_retrieve.py
"""
from __future__ import annotations

import tempfile
import unittest
import unittest.mock
from pathlib import Path

from test_carnet import (MAP_DOUBLE, NOTEBOOK_UI, SCOUT_GRID, TESTS_SHARED, Simulation, convert, count)
from test_protocol import lua_list
from harness import SendZone
import npc_protocol as protocol

SUITE_TEST = "body placed once, another ID card refused, the body's card accepted by id"

# Cell, building and corpse doubles of the server machine (installed after the Simulation is built).
# House 5002 of SCOUT_GRID: 100..110 x 10..20, z 0; site point = centre of its room rect (104, 14).
RETRIEVE_WORLD = r"""
RETRIEVE = {loaded = {}, streamed = true, explored = false, occupied = {}, stairs = {}, bodies = {}, calls = 0}
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local def = {}
function def:isFullyStreamedIn() return RETRIEVE.streamed end
function def:getRooms() return list({{isExplored = function() return RETRIEVE.explored end}}) end
local building = {getDef = function() return def end}
local squares = {}
function retrieveSquare(x, y, z)
    local k = key(x, y, z)
    if not squares[k] then
        local sq = {x = x, y = y, z = z, bodies = {}}
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:getZ() return self.z end
        function sq:isFree(b) return not RETRIEVE.occupied[key(self.x, self.y, self.z)] end
        function sq:HasStairs() return RETRIEVE.stairs[key(self.x, self.y, self.z)] == true end
        function sq:getBuilding()
            if self.x >= 100 and self.x < 110 and self.y >= 10 and self.y < 20 then return building end
            return nil
        end
        function sq:getDeadBodys() return list(self.bodies) end
        -- E01-T16 (world.keys, RST_PeerChecks.squareKeys): static moving objects (the bodies) and no other object.
        function sq:getStaticMovingObjects() return list(self.bodies) end
        function sq:getObjects() return list({}) end
        squares[k] = sq
    end
    return squares[k]
end
function loadArea(x1, y1, x2, y2)
    RETRIEVE.loaded[#RETRIEVE.loaded + 1] = {x1, y1, x2, y2}
end
local function loaded(x, y)
    for _, a in ipairs(RETRIEVE.loaded) do
        if x >= a[1] and x < a[3] and y >= a[2] and y < a[4] then return true end
    end
    return false
end
local baseCell = getCell
getCell = function()
    local cell = baseCell()
    if not cell then return nil end
    cell.getGridSquare = function(_, x, y, z)
        if z == 0 and loaded(x, y) then return retrieveSquare(x, y, z) end
        return nil
    end
    return cell
end
IsoDirections = {getRandom = function() return 'S' end}
RandomizedWorldBase = {}
function RandomizedWorldBase.createRandomDeadBody(sq, dir, blood, crawlerChance, outfit)
    RETRIEVE.calls = RETRIEVE.calls + 1
    assert(dir ~= nil, 'direction nil')
    local n = #RETRIEVE.bodies + 1
    local desc = {getForename = function() return 'Jane' .. n end, getSurname = function() return 'Roe' end}
    local body = {square = sq, inv = inventory(), md = {}, fake = (n % 2 == 1), blood = blood, crawler = crawlerChance}
    function body:getContainer() return self.inv end
    function body:getModData() return self.md end
    function body:setFakeDead(v) self.fake = v end
    function body:isFakeDead() return self.fake end
    function body:getDescriptor() return desc end
    RETRIEVE.bodies[n] = body
    sq.bodies[#sq.bodies + 1] = body
    return body
end
local baseInstance = instanceItem
instanceItem = function(kind)
    local it = baseInstance(kind)
    it.name = kind
    it.getName = function(self) return self.name end
    it.getDisplayName = function(self) return self.name end
    it.setName = function(self, s) self.name = s end
    -- InventoryItem.nameAfterDescriptor: script display name + ": " + forename + " " + surname.
    it.nameAfterDescriptor = function(self, d) self.name = 'ID Card: ' .. d:getForename() .. ' ' .. d:getSurname() end
    return it
end
"""


class RetrieveMissionTests(unittest.TestCase):
    """Corps posé au chargement de la zone, carte d'identité vérifiée par identifiant d'objet, autre carte refusée."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-retrieve-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, sim):
        sim.server.rt.execute(SCOUT_GRID)
        sim.server.g.scoutHouse(5001, 20, 12, 8, 8)    # too close to the requester
        sim.server.g.scoutHouse(5002, 100, 10, 10, 10)  # reachable
        sim.server.rt.execute(RETRIEVE_WORLD)
        sim.server.rt.eval("require('CoreAI/CA_MissionRetrieve')").resetForTests()

    def retrieve_sim(self, name='retrieve'):
        sim = Simulation(self.path / name)
        self.world(sim)
        sim.add_client('alice'); sim.add_client('bob'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        record = sim.server.rt.eval("require('CoreAI/CA_NPCProvider')").npc(2001)
        missions = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        return sim, npc, record, missions

    def catalog(self, sim, npc, record):
        return convert(sim.server.g.CoreAI.notebookServer.offerCatalogFor(npc, record))

    def active(self, name='retrieve'):
        sim, npc, record, missions = self.retrieve_sim(name)
        self.assertIn('retrieve_id_v1', self.catalog(sim, npc, record))
        m = missions.create(sim.state(), npc, sim.character('alice'), 'retrieve_id_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        return sim, npc, m, missions

    def poll(self, sim, ms=1001):
        sim.clock.offset += ms; sim.tick()

    def place(self, sim, m):
        sim.server.g.loadArea(90, 0, 130, 40)
        self.poll(sim)
        self.assertTrue(m.placed)
        return sim.server.g.RETRIEVE.bodies[1]

    def take(self, sim, name, body, item_id):
        """The player takes the card from the body: the same item (same id) moves to the server inventory."""
        card = body.inv.getItemWithID(body.inv, item_id)
        body.inv.Remove(body.inv, card)
        p = sim.server.g.PLAYERS[name]
        p.inv.AddItem(p.inv, card)
        return card

    def test_offer_names_a_place_without_coordinates_only_where_a_corpse_can_be_made(self):
        sim, npc, record, missions = self.retrieve_sim('offer')
        catalog = self.catalog(sim, npc, record)
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'retrieve_id_v1', 'scout_v1', 'signal_v1'])  # signal_v1: required mod Signal Smoke (bench double), same places as scout
        offer = catalog['retrieve_id_v1']
        self.assertEqual(set(offer), {'kind', 'item', 'place', 'clues', 'report', 'durationMs', 'rewardType',
                                      'rewardCount'})
        self.assertEqual((offer['kind'], offer['item'], offer['place'], offer['report']),
                         ('retrieve_id', 'ID card', 'house', 'in_person'))
        self.assertEqual((offer['durationMs'], offer['rewardType'], offer['rewardCount']), (7200000, 'Base.Bullets9mm', 20))
        clues = [offer['clues'][i] for i in sorted(offer['clues'])]
        self.assertTrue(clues and clues[0].startswith('The place is '), clues)
        self.assertFalse(any(ch.isdigit() for line in clues for ch in line), 'a clue carries a number')
        self.assertEqual(self.catalog(sim, npc, record)['retrieve_id_v1'], offer, 'the kept place changed')
        # A radio voice donor (no fiche) and a machine without RandomizedWorldBase get no retrieve_id offer.
        retrieve = sim.server.rt.eval("require('CoreAI/CA_MissionRetrieve')")
        c = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Missions.retrieve_id")
        donor = sim.server.rt.table_from({'id': 'voice:walt:c1', 'missionCount': 0})
        self.assertIsNone(retrieve.offer(c, donor, None, sim.server.g.PLAYERS.alice))
        voice = sim.server.rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.assertFalse(voice.allowed('retrieve_id'))
        sim.server.g.RandomizedWorldBase = None
        self.assertNotIn('retrieve_id_v1', self.catalog(sim, npc, record))

    def test_mission_carries_the_area_and_never_a_coordinate_to_the_bridge(self):
        sim, npc, m, missions = self.active('create')
        self.assertEqual((m.id, m.template, m.offer, m.place, m.placed), (npc.id + '-retrieve1', 'retrieve_id',
                                                                        'retrieve_id_v1', 'house', False))
        self.assertEqual(convert(m.spot), {'x': 104, 'y': 14, 'z': 0})
        self.assertEqual((m.quantity, m.delivered), (1, 0))
        self.assertEqual(sorted(convert(m.accepted)), ['Base.IDcard', 'Base.IDcard_Female', 'Base.IDcard_Male',
                                                       'Base.IDcard_Stolen'])
        context = convert(missions.context(m))
        self.assertEqual((context['kind'], context['placed'], context['found'], context['item']),
                         ('retrieve_id', False, False, 'ID card'))
        for key in ('spot', 'bounds', 'mapZone', 'cardId', 'person', 'bodyAt'):
            self.assertNotIn(key, context)
        row = convert(sim.clients['alice'].g.CoreAI.notebookClient.snapshot.missions[1])
        self.assertEqual((row['template'], row['quantity'], row['delivered'], row['found']), ('retrieve_id', 1, 0, False))
        self.assertEqual(row['mapZone'], convert(m.mapZone))
        for key in ('spot', 'bounds', 'cardId', 'bodyAt', 'siteKey'):
            self.assertNotIn(key, row)
        zone = convert(m.mapZone)
        for px, py in ((100, 10), (110, 10), (100, 20), (110, 20)):
            self.assertLessEqual(((px - zone['x']) ** 2 + (py - zone['y']) ** 2) ** 0.5, zone['r'])

    def test_body_placed_once_when_its_building_is_loaded(self):
        sim, npc, m, missions = self.active('place')
        g = sim.server.g
        # Square not loaded: nothing, however long.
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertEqual((m.placed, g.RETRIEVE.calls), (False, 0))
        # Loaded, but the building has not passed its vanilla stories yet (not fully loaded, no room explored).
        g.RETRIEVE.streamed = False
        g.loadArea(90, 0, 130, 40)
        self.poll(sim, 6000)
        self.assertEqual((m.placed, g.RETRIEVE.calls), (False, 0))
        # A room explored is enough. The site square is taken: nearest free square of the same building.
        g.RETRIEVE.explored = True
        g.RETRIEVE.occupied['104,14,0'] = True
        revision = m.revision
        self.poll(sim, 6000)
        self.assertTrue(m.placed)
        self.assertEqual(m.revision, revision + 1)
        self.assertEqual(g.RETRIEVE.calls, 1)
        body = g.RETRIEVE.bodies[1]
        at = convert(m.bodyAt)
        self.assertEqual(max(abs(at['x'] - 104), abs(at['y'] - 14)), 1)
        self.assertEqual((body.square.x, body.square.y), (at['x'], at['y']))
        self.assertFalse(body.fake, 'fake dead body')
        self.assertEqual((body.crawler, body.md.CA_RetrieveMission), (0, m.id))
        [card] = list(lua_list(body.inv['items']))
        self.assertEqual((card.kind, card.name, m.cardId, m.person), ('Base.IDcard', 'ID Card: Jane1 Roe', card.id,
                                                                       'Jane1 Roe'))
        self.assertIn(card.id, list(lua_list(g.ADDITIONS)))
        # Saved at once; no second body, neither by the next polls nor after a restart.
        saved = (self.path / 'place')
        for _ in range(3):
            self.poll(sim, 6000)
        self.assertEqual(g.RETRIEVE.calls, 1)
        restart = Simulation(saved, sim.clock, saved_players=sim.saved())
        self.world(restart)
        restart.server.g.loadArea(90, 0, 130, 40)
        restart.add_client('alice')
        old = restart.mission()
        self.assertEqual((old.template, old.placed, old.cardId, old.person), ('retrieve_id', True, card.id, 'Jane1 Roe'))
        for _ in range(3):
            restart.clock.offset += 6000; restart.tick()
        self.assertEqual(restart.server.g.RETRIEVE.calls, 0)

    def test_another_id_card_is_refused_the_body_card_accepted_by_id(self):
        sim, npc, m, missions = self.active('handover')
        g, char = sim.server.g, sim.character('alice')
        body = self.place(sim, m)
        client = sim.clients['alice']
        # Another ID card, named exactly as the body's card: listed by the delivery window, refused at confirmation.
        [other] = sim.items('alice', 'Base.IDcard')
        g.PLAYERS.alice.inv['items'][1].name = 'ID Card: Jane1 Roe'
        quote = sim.quote('alice', [other])
        sim.confirm('alice', quote)
        self.assertEqual(client.g.CoreAI.notebookClient.lastError, 'WrongCard')
        self.assertEqual((m.state, m.delivered, count(m.receipts)), ('active', 0, 0))
        self.assertIsNone(m.transaction)
        self.assertIsNotNone(g.PLAYERS.alice.inv.getItemWithIDRecursiv(g.PLAYERS.alice.inv, other))
        self.assertEqual(list(lua_list(g.REMOVALS)), [])
        # The right id while the card is still in the body: no item of the player, refused.
        quote = convert(g.CoreAI.notebookServer.quotes[char]) if g.CoreAI.notebookServer.quotes[char] else None
        self.assertIsNone(quote)
        missions_mod = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        store = g.CoreAI.notebookServer.store
        ok, reason = missions_mod.report(store, m, g.PLAYERS.alice, char,
                                         sim.server.rt.table_from([m.cardId]), 'forged-token')
        self.assertEqual((ok, reason), (False, 'WrongCard'))
        # The card taken from the body: seen by the server poll, then handed over through the notebook.
        card = self.take(sim, 'alice', body, m.cardId)
        self.poll(sim)
        self.assertEqual((m.found, m.foundBy), (True, 'alice Doe'))
        quote = sim.quote('alice', [card.id])
        sim.confirm('alice', quote)
        self.assertEqual(m.state, 'success')
        self.assertEqual(list(lua_list(g.REMOVALS)), [card.id])
        self.assertIsNone(g.PLAYERS.alice.inv.getItemWithIDRecursiv(g.PLAYERS.alice.inv, card.id))
        self.assertIsNotNone(g.PLAYERS.alice.inv.getItemWithIDRecursiv(g.PLAYERS.alice.inv, other), 'other card taken')
        outcome = sim.reputation().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(npc.mission)
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, char)
        self.assertEqual(len(lua_list(g.ADDITIONS)), 1 + 20)

    def test_card_given_to_a_non_participant_or_out_of_range_is_refused(self):
        sim, npc, m, missions = self.active('others')
        g = sim.server.g
        body = self.place(sim, m)
        # Bob holds the right card but is not a participant: neither found nor accepted.
        card = self.take(sim, 'bob', body, m.cardId)
        self.poll(sim)
        self.assertFalse(m.found)
        sim.clock.offset += 11000
        sim.select('bob')
        sim.command('bob', 'prepare_delivery', mission=m.id, revision=m.revision, items=[card.id])
        self.assertIsNone(g.CoreAI.notebookServer.quotes[sim.character('bob')])
        # Alice gets it but stands away from the requester: no quote (DELIVERY_RANGE), mission open.
        g.PLAYERS.bob.inv.Remove(g.PLAYERS.bob.inv, card)
        g.PLAYERS.alice.inv.AddItem(g.PLAYERS.alice.inv, card)
        g.PLAYERS.alice.x = 30
        sim.request_mission('alice', 'prepare_delivery', items=[card.id])
        self.assertIsNone(g.CoreAI.notebookServer.quotes[sim.character('alice')])
        self.assertEqual(m.state, 'active')

    def test_expiry_leaves_the_body_and_closes_the_mission(self):
        sim, npc, m, missions = self.active('expiry')
        self.place(sim, m)
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual(m.state, 'failed')
        self.assertEqual(sim.server.g.RETRIEVE.calls, 1)
        row = convert(sim.clients['alice'].g.CoreAI.notebookClient.snapshot.missions[1])
        self.assertNotIn('mapZone', row)

    def test_notebook_page_and_search_area_label(self):
        sim, npc, m, missions = self.active('notebook')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        texts = [convert(s)['text'] for s in lua_list(c.rt.eval('mapSymbols()')) if convert(s)['kind'] == 'text']
        self.assertEqual(texts, ['IGUI_CA_MapZoneSearch|Real Bandit'])
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        label = c.rt.eval('CoreAI.notebookClient.window.list.items[1].text')
        self.assertTrue(label.startswith('IGUI_CA_Mission_Retrieve - '), label)
        for key in ('IGUI_CA_ScoutPlace', 'IGUI_CA_ScoutClues', 'IGUI_CA_RetrieveMapZone', 'IGUI_CA_RetrieveNotFound',
                    'IGUI_CA_RetrieveReport'):
            self.assertIn(key, window.detail.text)
        self.assertNotIn('IGUI_CA_Progress', window.detail.text)
        self.assertNotIn('IGUI_CA_ScoutReport', window.detail.text)
        self.assertTrue(window.deliver.isVisible(window.deliver), 'no delivery button for the card')
        body = self.place(sim, m)
        self.take(sim, 'alice', body, m.cardId)
        self.poll(sim)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_RetrievePerson|Jane1 Roe', window.detail.text)
        self.assertIn('IGUI_CA_RetrieveFound|alice Doe', window.detail.text)

    def test_offline_bridge_tells_the_offer(self):
        req = {'kind': 'npc_talk', 'language': 'EN', 'offers': {'retrieve_id_v1': {
            'kind': 'retrieve_id', 'item': 'ID card', 'place': 'house', 'clues': ['The place is a house.'],
            'report': 'in_person', 'durationMs': 7200000, 'rewardType': 'Base.Bullets9mm', 'rewardCount': 20}},
            'context': {}, 'character': 'c1', 'text': 'Work?', 'id': 'r1'}
        with unittest.mock.patch.object(protocol, 'bounded_reply', lambda r, reply: reply):
            reply = protocol.offline(req, intent='')
        self.assertEqual((reply['intent'], reply['offer']), ('offer', 'retrieve_id_v1'))
        self.assertIn('ID card', reply['text'])
        self.assertIn('120 minutes', reply['text'])

    def suite_sim(self, name):
        """Simulated server with the real RST engine and the suite ca.mission.retrieve loaded (dev mod); the server move
        of RST_Fixtures is played directly on the server copy of the player, which loads the house. Rend la simulation et
        le joueur demandeur (alice)."""
        sim, npc, record, missions = self.retrieve_sim(name)
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
            getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end,
                getWorld = function() return 'rstest-retrieve' end, getMetaGrid = function() return grid end} end
            local base = retrieveSquare
            retrieveSquare = function(x, y, z)
                local sq = base(x, y, z)
                sq.removeCorpse = function(self, body)
                    for i, b in ipairs(self.bodies) do if b == body then table.remove(self.bodies, i) end end
                end
                return sq
            end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- the server double has no current square: moves do not wait for it
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'CA_MissionRetrieveSuite.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        # F.giveItem: inv:AddItem("Module.Item") creates the item (ItemContainer.AddItem(String)).
        sim.server.rt.execute("""
            local p = PLAYERS.alice
            p.removeAttachedItem = function() end
            p.isEquipped = function() return false end
            local add = p.inv.AddItem
            p.inv.AddItem = function(self, it)
                if type(it) == 'string' then it = instanceItem(it) end
                return add(self, it)
            end
        """)
        return sim, alice

    def run_suite(self, sim, alice, each_step=None):
        """Runs the suite by RST.step every 100 ms (each_step() after each step); rend les résultats par test."""
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("ca.mission.retrieve", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(400):
            if not sim.server.rt.eval('RST.step()'):
                break
            if each_step:
                each_step()
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return {r.test: (r.status, r.message) for r in report.results.values()}

    def test_in_game_suite_on_the_simulated_server(self):
        sim, alice = self.suite_sim('suite')
        # E01-T16: the client checks (world.keys) are covered by test_rst_steps.py; here the suite asks them twice
        # (body with the card, then without it), recorded and answered at once.
        sim.server.rt.execute("""
            PEER_ASKS = {}
            LOADED_ASKS = {}
            -- MP campaign of 2026-11-05: every client holds the area of the spot before the body is placed.
            RST.PeerChecks.waitLoaded = function(t, squares, after)
                LOADED_ASKS[#LOADED_ASKS + 1] = { n = #squares, placed = RETRIEVE.bodies[1] ~= nil }
                if after then return after(t) end
            end
            RST.PeerChecks.checkSquares = function(t, squares, kinds, after, union)
                PEER_ASKS[#PEER_ASKS + 1] = { n = #squares, corpse = kinds and kinds.corpse, union = union }
                if after then return after(t) end
            end
        """)
        results = self.run_suite(sim, alice)
        self.assertEqual(results, {SUITE_TEST: ('PASS', None)})
        self.assertEqual((alice.x, alice.y), (10, 10), 'the fixture did not move the player back')
        self.assertEqual(sim.server.rt.eval('#PEER_ASKS'), 2, 'world.keys asks of the suite')
        self.assertTrue(sim.server.rt.eval('PEER_ASKS[1].corpse and PEER_ASKS[1].union and PEER_ASKS[1].n == 9'))
        self.assertEqual(sim.server.rt.eval('#LOADED_ASKS'), 1, 'world.loaded asks of the suite')
        self.assertTrue(sim.server.rt.eval('LOADED_ASKS[1].n == 5 and not LOADED_ASKS[1].placed'),
                        'clients asked to hold the area after the body was placed')
        bodies = sim.server.g.RETRIEVE.bodies[1].square.bodies
        self.assertEqual(len(lua_list(bodies)), 0, 'body not removed by the cleanup')

    def test_in_game_suite_under_the_send_zone(self):
        """E19-T06 (campagne MP du 2026-11-05, registre catégorie F) : zone d'envoi du serveur dédié (harness.SendZone,
        sources 42.22). createRandomDeadBody envoie le cadavre par GameServer.sendCorpse (RandomizedWorldBase.java:505,
        GameServer.java:1869-1883) aux seules connexions dont la position SIGNALÉE couvre la case ; un client téléporté
        signale sa nouvelle place par son paquet de position suivant (TeleportPacket.java:70-76, PlayerPacket.java:169),
        ici une étape (100 ms) après la copie du serveur. Un client qui a manqué le paquet n'a pas le cadavre (case déjà
        reçue : aucun renvoi). world.loaded (PC.waitLoaded) : les clients tiennent la zone settleMs (2 s) ; world.keys
        (PC.checkSquares) : chaque client compare ses cadavres à ceux du serveur. L'ancienne suite (a469d1f^, sans
        waitLoaded) échoue ici, l'actuelle passe."""
        sim, alice = self.suite_sim('zone')
        zone = SendZone()
        names = ('alice', 'bob')
        players = {n: sim.server.g.PLAYERS[n] for n in names}
        for n, p in players.items():
            zone.report(n, p.x, p.y, p.z or 0)
        sim.server.g.RELEVANT_CLIENTS = lambda x, y: sim.server.rt.table_from(zone.relevant_clients(x, y))
        sim.server.rt.execute("""
            ZONE = { asks = 0 }
            RST.clock = getTimestampMs   -- the GameTime double of the simulation does not move: real clock of the bench
            local create = RandomizedWorldBase.createRandomDeadBody
            RandomizedWorldBase.createRandomDeadBody = function(sq, ...)
                local body = create(sq, ...)
                body.receivers = {}   -- GameServer.sendCorpse : connexions dont la zone couvre la case
                for _, name in ipairs(RELEVANT_CLIENTS(sq:getX(), sq:getY())) do body.receivers[name] = true end
                return body
            end
            -- Every client holds the squares loaded (loaded at its teleport) for PC.SETTLE_MS, then after(t).
            RST.PeerChecks.waitLoaded = function(t, squares, after)
                local since = RST.now()
                t:waitQuiet(function() return RST.now() - since >= RST.PeerChecks.SETTLE_MS end, 30000,
                    after, "world.loaded")
            end
            -- Each client compares its corpses on the squares with the server's: a body never received differs.
            RST.PeerChecks.checkSquares = function(t, squares, kinds, after, union)
                ZONE.asks = ZONE.asks + 1
                for _, name in ipairs({ "alice", "bob" }) do
                    for _, b in ipairs(RETRIEVE.bodies) do
                        t:ok(b.receivers[name] == true, "client " .. name .. ": corpse of the spot not received")
                    end
                end
                if after then return after(t) end
            end
        """)
        lag = {}

        def player_packets():
            # Position received by the server one step after the client moved (packet of the next client frame).
            for n, pos in lag.items():
                zone.report(n, *pos)
            lag.clear()
            for n, p in players.items():
                pos = (p.x, p.y, p.z or 0)
                if pos != zone.reported[n]:
                    lag[n] = pos
        results = self.run_suite(sim, alice, player_packets)
        self.assertEqual(results, {SUITE_TEST: ('PASS', None)})
        self.assertEqual(sim.server.rt.eval('ZONE.asks'), 2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
