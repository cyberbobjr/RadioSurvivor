"""Livraison sur place et approche d'un secours (E12-T03) : RS_RescueVisit.lua dans lupa.

    python RadioSurvivor/tests/test_rescue_visit.py

Vrai Lua du mod (RS_Rescue, RS_Factions, RS_State, RS_RescueVisit ; `next` retiré comme dans Kahlua) sur la
métagrille simulée de tests/test_rescue.py, avec des doublures fidèles : cases chargées (IsoCell:getGridSquare nil
hors zone), objets à conteneurs (getContainerCount / getContainerByIndex), ItemContainer (getItems vivante,
DoRemoveItem), objets d'inventaire (getID, getDisplayCategory, getFluidContainer, Food : isRotten, isFrozen,
isbDangerousUncooked, isCooked ; InventoryContainer : getInventory), instanceof, Fluid, joueurs (inventaire, étage,
véhicule), traductions (getTextOrNull), RS_RadioServer (fréquence de la voix, diffusion) et le module public du mod
requis Signal Smoke (start, COLORS ; par défaut, une doublure qui refuse la fumée : la voix décrit).
Couvre : seul un objet apporté de l'extérieur par un membre de l'équipe et laissé dans un conteneur du bâtiment compte
(butin du bâtiment, objet inutilisable, conteneur hors du bâtiment ou hors zone, autre équipe : rien), valeurs par
catégorie, sacs imbriqués, retrait de l'objet ; approche une fois par venue et par délai, description (direction,
plusieurs, véhicule) en anglais sans traduction ou traduite, diffusion sur la fréquence de la voix ; fumée de Signal
Smoke côté du joueur, repli sur la description si la fumée est refusée, erreur au journal si le module du mod requis
est inutilisable (installation cassée) ; site imposé de startForTeam.
Ne prouve pas l'API Java réelle ni le transfert MP : suite en jeu rs.rescue.visit.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

import test_rescue as base

ROOT = Path(__file__).resolve().parents[1]
MODULE = base.MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_RescueVisit.lua'
lua_list = base.lua_list

VISIT_DOUBLES = r"""
AGE = 100.0
getGameTime = function() return { getWorldAgeHours = function() return AGE end } end
STATE = require("RadioSurvivor/RS_State")
STATE.data = { schema = 2, world = "w" }
R = require("RadioSurvivor/RS_Rescue")
Fluid = { Water = "FWater", Petrol = "FPetrol", TaintedWater = "FTainted" }
instanceof = function(o, cls)
    if type(o) ~= "table" then return false end
    if cls == "Food" then return o._food == true end
    if cls == "InventoryContainer" then return o._bag ~= nil end
    return false
end

function Container(items)
    local c = { items = items or {} }
    function c:getItems() return JList(self.items) end
    function c:DoRemoveItem(it)
        for i = #self.items, 1, -1 do if self.items[i] == it then table.remove(self.items, i) return end end
    end
    function c:has(it) for _, x in ipairs(self.items) do if x == it then return true end end return false end
    function c:add(it) self.items[#self.items + 1] = it return it end
    return c
end

NEXT_ITEM = 500
-- Item("food"|"medical"|"tool"|"bag", { rotten, frozen, raw, cooked, fluid = "Water", category = "Food" })
function Item(kind, o)
    o = o or {}
    NEXT_ITEM = NEXT_ITEM + 1
    local it = { id = NEXT_ITEM, kind = kind, _food = kind == "food" }
    local cats = { food = "Food", medical = "FirstAid", tool = "Tool", bag = "Bag", water = "Water", fuel = "Water" }
    it.category = o.category or cats[kind]
    if kind == "bag" then it._bag = Container({}) end
    if kind == "water" then it.fluid = "Water" elseif kind == "fuel" then it.fluid = "Petrol" end
    if o.fluid then it.fluid = o.fluid end
    function it:getID() return self.id end
    function it:getDisplayCategory() return self.category end
    function it:getFluidContainer()
        if not self.fluid then return nil end
        local f = self.fluid
        return { isEmpty = function() return f == "empty" end, getPrimaryFluid = function() return Fluid[f] end }
    end
    function it:isRotten() return o.rotten == true end
    function it:isFrozen() return o.frozen == true end
    function it:isbDangerousUncooked() return o.raw == true end
    function it:isCooked() return o.cooked == true end
    function it:getInventory() return self._bag end
    return it
end

SQUARES = {}
LOADED = nil -- nil: every square of SQUARES is loaded; table: only the listed keys
READS = 0
function Furniture(x, y, z, items)
    local c = Container(items)
    local obj = { c = c }
    function obj:getContainerCount() return 1 end
    function obj:getContainerByIndex(i) if i == 0 then return self.c end error("index") end
    local key = x .. "," .. y .. "," .. z
    local sq = SQUARES[key] or { objects = {} }
    sq.objects[#sq.objects + 1] = obj
    function sq:getObjects() return JList(self.objects) end
    SQUARES[key] = sq
    return c
end
VCELL = {}
function VCELL:getGridSquare(x, y, z)
    READS = READS + 1
    local key = x .. "," .. y .. "," .. z
    if LOADED and not LOADED[key] then return nil end
    return SQUARES[key] or { getObjects = function() return JList({}) end }
end
getCell = function() return VCELL end
SENT = {}
sendRemoveItemFromContainer = function(c, it) SENT[#SENT + 1] = it:getID() end

-- Player in the visit tests: inventory, floor, vehicle; dead flag.
function Member(x, y, name)
    local p = Player(x, y)
    p.inv = Container({})
    p.name = name
    function p:getZ() return 0 end
    function p:isDead() return self.dead == true end
    function p:getInventory() return self.inv end
    function p:getVehicle() return self.vehicle end
    function p:getDescriptor()
        local n = self.name or "Kate"
        return { getForename = function() return n end, getSurname = function() return "Smith" end }
    end
    if name then p.getUsername = function() return name end end
    return p
end

TEXTS = nil
getTextOrNull = function(key, a)
    if TEXTS == nil or TEXTS[key] == nil then return nil end
    return (string.gsub(TEXTS[key], "%%1", a or ""))
end
AIRED = {}
RS_RadioServer = { frequency = function(id) if id == "darlene" then return 91500 end return nil end,
                   air = function(khz, lines) AIRED[#AIRED + 1] = { khz = khz, lines = lines } end }
-- Required mod Signal Smoke: by default a double whose start refuses the smoke (the voice then describes).
SMOKES = {}
SS = { COLORS = { green = { r = 0.2, g = 0.9, b = 0.2 }, red = { r = 1, g = 0, b = 0 } } }
function SS.start(opts) SMOKES[#SMOKES + 1] = opts return nil, "refused by the bench" end
package.preload["SignalSmoke/SignalSmoke"] = function() return SS end
V = require("RadioSurvivor/RS_RescueVisit")
APPROACHES = {}
V.onApproach = function(rec, info, text) APPROACHES[#APPROACHES + 1] = { id = rec.id, info = info, text = text } end
-- FAR_HOUSE: bounds 5000..5008 x 5000..5008 (exclusive ends), floors 0 and 1.
SITE = R.check(FAR_HOUSE, {}, { minDistance = 0 }, GRID)
function poll() return V.poll(true) end
"""


class VisitHarness(base.RescueHarness):

    def setUp(self):
        super().setUp()
        self.world()
        self.rt.execute('PLAYERS = {}')
        self.rt.execute(VISIT_DOUBLES)

    def start(self, who='ME', opts='days = 1, voice = "darlene", requester = "Darlene"'):
        return self.rt.execute(f'local id, r, x = R.startForTeam(R.teamOf({who}), {{ site = SITE, {opts} }})'
                               ' return id, r, x')

    def rec(self, rid='rsc-1'):
        return self.ev(f'return R.get("{rid}")')

    def logs(self):
        return lua_list(self.g.LOGS)


class DeliveryTests(VisitHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute('ME = Member(5003, 4990)')     # 10 tiles north of the building
        self.start()
        self.rt.execute(r"""
        BEANS = ME.inv:add(Item("food"))
        BAG = ME.inv:add(Item("bag"))
        PILLS = BAG._bag:add(Item("medical"))
        WATER = ME.inv:add(Item("water"))
        HAMMER = ME.inv:add(Item("tool"))
        FUEL = ME.inv:add(Item("fuel"))
        LOOT = Item("food")
        FRIDGE = Furniture(5004, 5004, 0, { LOOT })
        """)

    def walk_in(self, x=5003, y=5003):
        self.rt.execute(f'ME.x, ME.y = {x}, {y}')

    def move(self, item, dest, src='ME.inv'):
        self.rt.execute(f'{src}:DoRemoveItem({item}); {dest}:add({item})')

    def test_items_carried_in_and_left_in_a_container_count(self):
        self.assertTrue(self.ev('poll()'))                     # approach (outside): items remembered
        self.assertTrue(self.ev('V.isCarried(R.teamOf(ME), BEANS.id) and V.isCarried(R.teamOf(ME), PILLS.id)'))
        self.assertFalse(self.ev('V.isCarried(R.teamOf(ME), HAMMER.id) or V.isCarried(R.teamOf(ME), FUEL.id)'))
        self.assertFalse(self.ev('V.isCarried(R.teamOf(ME), LOOT.id)'))
        self.walk_in()
        self.move('BEANS', 'FRIDGE')
        self.move('BAG', 'FRIDGE')                             # pills inside the bag, in the fridge
        self.move('WATER', 'FRIDGE')
        self.assertTrue(self.ev('poll()'))
        rec = self.rec()
        self.assertEqual((rec.reserves, rec.delivered), (24 + 8 + 6 + 4, 18))
        self.assertTrue(self.ev('FRIDGE:has(LOOT) and FRIDGE:has(BAG)'))
        self.assertFalse(self.ev('FRIDGE:has(BEANS) or FRIDGE:has(WATER) or BAG._bag:has(PILLS)'))
        self.assertEqual(sorted(lua_list(self.g.SENT)), sorted([self.ev('BEANS.id'), self.ev('PILLS.id'),
                                                                self.ev('WATER.id')]))
        self.assertIn('[RadioSurvivor] rescue: rsc-1: delivery of 1 food, 1 water, 1 medical item(s), +18 h, '
                      'reserves 42', self.logs())
        self.assertFalse(self.ev('poll()'))                    # building loot never counts
        self.assertEqual(self.rec().reserves, 42)

    def test_building_loot_moved_inside_does_not_count(self):
        self.ev('poll()')
        self.walk_in()
        self.rt.execute('SHELF = Furniture(5001, 5001, 0, {}); FRIDGE:DoRemoveItem(LOOT); SHELF:add(LOOT)')
        self.assertFalse(self.ev('poll()'))
        self.assertTrue(self.ev('SHELF:has(LOOT)'))
        self.assertEqual(self.rec().reserves, 24)

    def test_unusable_food_and_other_places_do_not_count(self):
        self.rt.execute('ROTTEN = ME.inv:add(Item("food", { rotten = true }));'
                        ' RAW = ME.inv:add(Item("food", { raw = true }));'
                        ' COOKED = ME.inv:add(Item("food", { raw = true, cooked = true }))')
        self.ev('poll()')
        self.walk_in()
        self.move('ROTTEN', 'FRIDGE')
        self.move('RAW', 'FRIDGE')
        self.move('COOKED', 'FRIDGE')
        # Container on a square outside the building bounds, and the floor of the player (no container): nothing.
        self.rt.execute('YARD = Furniture(5009, 5003, 0, {})')
        self.move('BEANS', 'YARD')
        self.assertTrue(self.ev('poll()'))
        self.assertEqual(self.rec().reserves, 24 + 8)          # the cooked one only
        self.assertTrue(self.ev('FRIDGE:has(ROTTEN) and FRIDGE:has(RAW) and YARD:has(BEANS)'))

    def test_unloaded_squares_and_scan_radius(self):
        self.ev('poll()')
        self.walk_in(5000, 5000)
        self.move('BEANS', 'FRIDGE')
        self.rt.execute('LOADED = {}')                         # nothing readable: nothing counted, no error
        self.assertFalse(self.ev('poll()'))
        self.rt.execute('LOADED = nil; READS = 0')
        self.assertTrue(self.ev('poll()'))
        # Building 8 x 8, radius 8: every square of floor 0 inside the bounds, none outside.
        self.assertEqual(self.g.READS, 64)

    def test_items_seen_only_inside_do_not_count(self):
        """A member who never stood outside near the building brings nothing that counts."""
        self.walk_in()
        self.ev('poll()')
        self.move('BEANS', 'FRIDGE')
        self.assertFalse(self.ev('poll()'))
        self.assertEqual(self.rec().reserves, 24)

    def test_far_or_dead_member_neither_remembers_nor_delivers(self):
        self.rt.execute('ME.x, ME.y = 5003, 4900')             # 100 tiles away
        self.assertFalse(self.ev('poll()'))
        self.assertFalse(self.ev('V.isCarried(R.teamOf(ME), BEANS.id)'))
        self.rt.execute('ME.x, ME.y = 5003, 4990; ME.dead = true')
        self.assertFalse(self.ev('poll()'))
        self.assertEqual(len(lua_list(self.g.APPROACHES)), 0)

    def test_closed_rescue_gets_nothing(self):
        self.ev('poll()')
        self.rt.execute('R.finish("rsc-1", "abandoned")')
        self.walk_in()
        self.move('BEANS', 'FRIDGE')
        self.assertFalse(self.ev('poll()'))
        self.assertTrue(self.ev('FRIDGE:has(BEANS)'))


class TeamTests(VisitHarness):

    def test_only_members_of_the_rescued_team(self):
        self.g.SIDE = 'server'
        self.rt.execute(r"""
        A = Member(5003, 4990, "alice")
        B = Member(4990, 5003, "bob")
        C = Member(5003, 5003, "carol")
        local f = { getOwner = function() return "alice" end, getName = function() return "Wolves" end,
            getPlayers = function() return JList({ "bob" }) end,
            isOwner = function(_, n) return n == "alice" end,
            isMember = function(_, n) return n == "alice" or n == "bob" end }
        Faction = { getFactions = function() return JList({ f }) end }
        require("RadioSurvivor/RS_Factions").reset()
        """)
        self.start('A')
        self.rt.execute('CB = C.inv:add(Item("food")); BB = B.inv:add(Item("food")); FR = Furniture(5004, 5004, 0, {})')
        self.assertTrue(self.ev('poll()'))
        approach = lua_list(self.g.APPROACHES)[0]
        self.assertEqual(approach.info.count, 2)                # alice and bob, not carol
        self.assertFalse(self.ev('V.isCarried(R.teamOf(A), CB.id)'))
        self.assertTrue(self.ev('V.isCarried(R.teamOf(A), BB.id)'))
        self.rt.execute('C.inv:DoRemoveItem(CB); FR:add(CB)')   # carol inside, her own food
        self.assertFalse(self.ev('poll()'))
        self.rt.execute('B.inv:DoRemoveItem(BB); FR:add(BB)')   # bob's food, carol inside: not a member
        self.assertFalse(self.ev('poll()'))
        self.rt.execute('B.x, B.y = 5002, 5002')                # bob walks in
        self.assertTrue(self.ev('poll()'))
        self.assertEqual(self.rec().reserves, 32)
        self.assertTrue(self.ev('FR:has(CB)'))


class ApproachTests(VisitHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute('ME = Member(5012, 4990)')             # north-east of the building
        self.start()

    def approaches(self):
        return lua_list(self.g.APPROACHES)

    def test_description_in_english_aired_on_the_voice(self):
        self.assertTrue(self.ev('poll()'))
        a = self.approaches()[0]
        self.assertEqual((a.info.dir, a.info.count, a.info.vehicle, a.info.smoke, a.info.aired),
                         ('north_east', 1, False, None, True))
        text = 'I can see you from the window! You are to the north-east. Come on, quickly!'
        self.assertEqual(a.text, text)
        aired = lua_list(self.g.AIRED)
        self.assertEqual((aired[0].khz, lua_list(aired[0].lines)), (91500, ['<fzzt>', text, '<szzt>']))
        rec = self.rec()
        self.assertEqual((rec.approach.dir, rec.approach.at, rec.approaches, rec.approach.aired), ('north_east', 100, 1, True))
        self.assertTrue(self.ev('STATE.dirty'))
        self.assertIn('[RadioSurvivor] rescue: rsc-1: approach of 1 member(s) from the north_east, description, aired',
                      self.logs())

    def test_translated_line(self):
        self.rt.execute('TEXTS = { IGUI_RS_Dir_north_east = "au nord-est",'
                        ' IGUI_RS_RescueSee = "Je vous vois ! Vous etes %1." }')
        self.ev('poll()')
        self.assertEqual(self.approaches()[0].text, 'Je vous vois ! Vous etes au nord-est.')

    def test_once_per_visit_and_per_cooldown(self):
        self.ev('poll()')
        self.assertFalse(self.ev('poll()'))                    # still near
        self.g.AGE = 99.0                                      # older world age (restored save): no new approach
        self.assertFalse(self.ev('poll()'))
        self.g.AGE = 100.0
        self.rt.execute('V.resetForTests(); poll()')           # new session, still near: blocked by the delay
        self.g.AGE = 120.0
        self.assertFalse(self.ev('poll()'))                    # staying near past the delay: same visit
        self.g.AGE = 100.0
        self.rt.execute('ME.x, ME.y = 5012, 4800')
        self.ev('poll()')                                      # gone
        self.rt.execute('ME.x, ME.y = 5012, 4990')
        self.g.AGE = 111.0
        self.assertFalse(self.ev('poll()'))                    # back within 12 game hours
        self.rt.execute('ME.x, ME.y = 5012, 4800')
        self.ev('poll()')
        self.rt.execute('ME.x, ME.y = 5012, 4990')
        self.g.AGE = 112.5
        self.assertTrue(self.ev('poll()'))
        self.assertEqual((len(self.approaches()), self.rec().approaches), (2, 2))

    def test_vehicle_and_no_voice_frequency(self):
        self.rt.execute('R.finish("rsc-1", "abandoned"); ME.vehicle = {}')
        self.start(opts='days = 1, voice = "nobody"')
        self.ev('poll()')
        a = self.approaches()[0]
        self.assertEqual(a.text, 'I can see a vehicle out there, to the north-east. Is that you?')
        self.assertFalse(a.info.aired)
        self.assertEqual(len(lua_list(self.g.AIRED)), 0)
        self.assertIn('no voice frequency', self.logs()[-1])

    def test_several_members(self):
        self.g.SIDE = 'server'
        self.rt.execute(r"""
        R.finish("rsc-1", "abandoned")                          -- same building for the new rescue
        PLAYERS = {}
        A = Member(5003, 4990, "alice")
        B = Member(5004, 4992, "bob")
        local f = { getOwner = function() return "alice" end, getName = function() return "Wolves" end,
            getPlayers = function() return JList({ "bob" }) end,
            isOwner = function(_, n) return n == "alice" end,
            isMember = function(_, n) return n == "alice" or n == "bob" end }
        Faction = { getFactions = function() return JList({ f }) end }
        require("RadioSurvivor/RS_Factions").reset()
        """)
        self.start('A', 'days = 1')
        self.ev('poll()')
        a = self.approaches()[-1]
        self.assertEqual(a.text, 'I can see several of you from the window, to the north. Come on, quickly!')

    def install_signal_smoke(self, start='return opts.id'):
        self.rt.execute(r"""
        SMOKES = {}
        SS = { COLORS = { green = { r = 0.2, g = 0.9, b = 0.2 }, red = { r = 1, g = 0, b = 0 } } }
        function SS.start(opts) SMOKES[#SMOKES + 1] = opts """ + start + r""" end
        package.preload["SignalSmoke/SignalSmoke"] = function() return SS end
        V.resetForTests()
        """)

    def test_signal_smoke_lights_a_smoke_on_the_player_side(self):
        self.install_signal_smoke()
        self.rt.execute('ME.x, ME.y = 5003, 4990')             # north
        self.ev('poll()')
        smoke = lua_list(self.g.SMOKES)[0]
        self.assertEqual((smoke.x, smoke.y, smoke.z, smoke.color, smoke.minutes, smoke.id),
                         (5003, 4998, 0, 'green', 30, 'rs:rescue:rsc-1'))
        self.assertIsNone(smoke.player)
        a = self.approaches()[0]
        self.assertEqual((a.info.smoke, a.text),
                         ('green', 'I can hear you out there! I am lighting a green smoke outside, follow it.'))
        self.assertEqual(self.rec().approach.smoke, 'green')

    def test_smoke_point_sides(self):
        pts = {}
        for name, (x, y) in {'west': (4990, 5003), 'east': (5020, 5003), 'south': (5003, 5020),
                             'corner': (4990, 4990), 'inside': (5003, 5003)}.items():
            pts[name] = tuple(self.rt.execute(f'ME.x, ME.y = {x}, {y} return V.smokePoint(R.get("rsc-1"), ME)'))
        self.assertEqual(pts, {'west': (4998, 5003), 'east': (5009, 5003), 'south': (5003, 5009),
                               'corner': (4998, 4998), 'inside': (5003, 5009)})

    def test_refused_smoke_falls_back_to_the_description(self):
        self.install_signal_smoke('return nil, "bad colour"')
        self.ev('poll()')
        a = self.approaches()[0]
        self.assertIsNone(a.info.smoke)
        self.assertTrue(a.text.startswith('I can see you from the window!'))
        self.assertIn('[RadioSurvivor] rescue: rsc-1: Signal Smoke refused the smoke (bad colour)', self.logs())

    def test_broken_module_of_the_required_mod_logs_an_error(self):
        self.rt.execute('package.loaded["SignalSmoke/SignalSmoke"] = { COLORS = {} }; V.resetForTests()')
        self.ev('poll()')
        a = self.approaches()[0]
        self.assertIsNone(a.info.smoke)
        self.assertTrue(a.text.startswith('I can see you from the window!'))
        self.assertIn('[RadioSurvivor] rescue: ERROR required mod batman_SignalSmoke is broken: module '
                      'SignalSmoke/SignalSmoke has no start or COLORS', self.logs())


class StartTests(VisitHarness):

    def test_imposed_site(self):
        self.rt.execute('ME = Member(100, 100)')
        rid, rec, _ = self.start()
        self.assertEqual((rid, rec.site.key, rec.voice), ('rsc-1', self.ev('return SITE.key'), 'darlene'))
        self.rt.execute('OTHER = Member(200, 200)')
        self.assertEqual(self.rt.execute('local a, b, c = R.startForTeam("fac-x", { site = SITE }) return a, b, c'),
                         (None, 'no_site', 'excluded'))
        self.assertEqual(self.rt.execute('local a, b, c = R.startForTeam("fac-y", { site = { key = "b1" } })'
                                         ' return a, b, c'), (None, 'no_site', 'bad site'))

    def test_hook_subscribed_once_and_client_skips(self):
        self.rt.execute('package.loaded["RadioSurvivor/RS_RescueVisit"] = nil; require("RadioSurvivor/RS_RescueVisit")')
        self.assertEqual(len(lua_list(self.g.Events.OnTickEvenPaused.list)), 2)  # RS_Rescue + RS_RescueVisit


class ClientTests(base.RescueHarness):

    def test_not_loaded_on_an_mp_client(self):
        self.g.SIDE = 'client'
        self.world()
        self.assertFalse(self.ev('return type(require("RadioSurvivor/RS_RescueVisit")) == "table"'))


class SourceTests(unittest.TestCase):

    def test_kahlua_constraints(self):
        code = MODULE.read_text(encoding='utf-8')
        body = re.sub(r'--\[\[.*?\]\]', '', code, flags=re.S)
        body = '\n'.join(line.split('--')[0] for line in body.splitlines())
        self.assertTrue(all(ord(ch) < 128 for ch in body), 'non-ASCII outside comments')
        self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', body))
        self.assertIsNone(re.search(r'\bgoto\b|coroutine\.|debug\.traceback|%q', body))
        self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', body.replace('~=', '')))
        self.assertTrue(body.lstrip().startswith('if isClient() then return end'))
        for forbidden in ('ModData', 'LoadChunk', 'getFileWriter', 'sendServerCommand'):
            self.assertNotIn(forbidden, body)

    def test_translations_en_fr(self):
        import json
        keys = ['IGUI_RS_RescueSee', 'IGUI_RS_RescueSeeGroup', 'IGUI_RS_RescueSeeVehicle'] + [
            f'IGUI_RS_RescueSmoke_{c}' for c in ('green', 'red', 'yellow', 'purple')]
        for lang in ('EN', 'FR'):
            data = json.loads((base.MOD_LUA / 'shared' / 'Translate' / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for key in keys:
                with self.subTest(lang=lang, key=key):
                    self.assertIn(key, data)
                    self.assertEqual('%1' in data[key], key in keys[:3])


if __name__ == '__main__':
    unittest.main(verbosity=1)
