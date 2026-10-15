"""Issue « à temps » d'un secours (E12-T04) : RS_RescueVisit (départ des aidants), RS_Rescue (aidants, issue) et
RS_RescueScene (cache, note, nouvel endroit de la voix, mémoire) dans lupa.

    python RadioSurvivor/tests/test_rescue_scene.py

Vrai Lua du mod (RS_Rescue, RS_RescueVisit, RS_RescueScene, RS_Caches, RS_Memory, RS_PersonaState, RS_RadioLog,
RS_Config, RS_Codec, RS_State ; `next` retiré comme dans Kahlua) sur la métagrille et les doublures de
tests/test_rescue.py et tests/test_rescue_visit.py, plus : cases de sol pour la pose (isFree, HasStairs,
getWorldObjects, AddWorldInventoryItem), instanceItem (sac à ModData et conteneur, feuille de papier Literature :
addPage, setLockedBy, setName, setCustomName), descripteurs de joueurs, RS_CarnetServer.bound ; RS_Actions,
RS_MissionVoice et RS_LifeLog remplacés par des doublures (enregistrement d'action, relevé de vie noté).
Couvre : issue « saved » seulement après un dépôt réel puis le départ de tous les membres proches ; aidants notés
(nom, appelant, personnage) et participants du fait du jour ; cache tirée dans la liste fermée avec une note (noms,
signature, anglais sans traduction ou traduite, ni chiffre ni fréquence) ; nouveau bâtiment loin des bases et du
site, mots de lieu bornés sans chiffre ; état de la voix (lieu, moral) et souvenirs sur chaque aidant ; relevé de vie
hors magasin de travail ; scène posée seulement quand la case du site est chargée, une seule fois, même après un
redémarrage (sac retrouvé et adopté) ; issue « missed » sans cache (E12-T05) ; la suite rs.rescue.saved jouée
par le vrai moteur RST (réussite, nettoyage, scène jamais close détectée).
Ne prouve pas l'API Java réelle ni le transfert MP : suite en jeu rs.rescue.saved.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

import test_rescue as base
import test_rescue_visit as visit

MODULE = base.MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_RescueScene.lua'
lua_list = base.lua_list

SCENE_DOUBLES = r"""
package.loaded["RadioSurvivor/RS_Actions"] = { register = function() return true end }
package.loaded["RadioSurvivor/RS_MissionVoice"] = {}
LIFE = {}
package.loaded["RadioSurvivor/RS_LifeLog"] = { rescue = function(cid, outcome, label)
    LIFE[#LIFE + 1] = { cid = cid, outcome = outcome, label = label } return true end }
FACTS = {}
RS_Facts = { record = function(kind, fields, key) FACTS[#FACTS + 1] = { kind = kind, fields = fields, key = key } end }
STATE.data.characters = { c1 = { name = "Kate Smith" } }
STATE.save = function() SAVES = (SAVES or 0) + 1 return true end
RS_CarnetServer = { bound = {} }

instanceof = (function(prev)
    return function(o, cls)
        if cls == "Literature" then return type(o) == "table" and o._literature == true end
        return prev(o, cls)
    end
end)(instanceof)

NEXT_NEW = 9000
function instanceItem(full)
    NEXT_NEW = NEXT_NEW + 1
    local it = { id = NEXT_NEW, full = full, md = {} }
    function it:getID() return self.id end
    function it:getModData() return self.md end
    function it:hasModData() return true end
    if full == "Base.Bag_DuffelBag" then
        it._bag = Container({})
        function it._bag:AddItem(x) return self:add(x) end
    end
    function it:getItemContainer() return self._bag end
    if full == "Base.SheetPaper2" then
        it._literature, it.pages = true, {}
        function it:addPage(i, text) self.pages[i] = text end
        function it:setLockedBy(who) self.locked = who end
        function it:setName(n) self.name = n end
        function it:setCustomName(v) self.custom = v end
    end
    return it
end

-- Floor squares for the placement (SCELL): free, no stairs, world objects, AddWorldInventoryItem.
FLOOR = {}
SITE_LOADED = true
function Floor(x, y, z)
    local key = x .. "," .. y .. "," .. z
    if FLOOR[key] then return FLOOR[key] end
    local sq = { x = x, y = y, z = z, world = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getBuilding() return nil end
    function sq:isFree() return true end
    function sq:HasStairs() return false end
    function sq:getObjects() return JList({}) end
    function sq:getWorldObjects()
        local out = {}
        for _, item in ipairs(self.world) do out[#out + 1] = { getItem = function() return item end } end
        return JList(out)
    end
    function sq:AddWorldInventoryItem(item) self.world[#self.world + 1] = item return item end
    FLOOR[key] = sq
    return sq
end
SCELL = {}
function SCELL:getGridSquare(x, y, z)
    if not SITE_LOADED then return nil end
    return Floor(x, y, z)
end
function floorItems()
    local out = {}
    for _, sq in pairs(FLOOR) do for _, it in ipairs(sq.world) do out[#out + 1] = it end end
    return out
end

Scene = require("RadioSurvivor/RS_RescueScene")
Memory = require("RadioSurvivor/RS_Memory")
PersonaState = require("RadioSurvivor/RS_PersonaState")
Caches = require("RadioSurvivor/RS_Caches")
"""


class SceneHarness(visit.VisitHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(SCENE_DOUBLES)
        # Kate (solo key) near the building with beans, 10 tiles north.
        self.rt.execute('ME = Member(5003, 4990); BEANS = ME.inv:add(Item("food"))'
                        '; FRIDGE = Furniture(5004, 5004, 0, {})')

    def deliver(self):
        self.ev('poll()')                                    # outside: beans remembered, approach
        self.rt.execute('ME.x, ME.y = 5003, 5003; ME.inv:DoRemoveItem(BEANS); FRIDGE:add(BEANS)')
        self.ev('poll()')                                    # inside: delivery

    def leave(self, who='ME'):
        self.rt.execute(f'{who}.x, {who}.y = 5003, 4900')    # 100 tiles north

    def raw(self, rid='rsc-1'):
        return self.ev(f'return STATE.data.rescues.rescues["{rid}"]')

    def scene_poll(self):
        self.rt.execute('getCell = function() return SCELL end')
        return self.ev('return Scene.poll(true)')


class OutcomeTests(SceneHarness):

    def test_saved_only_after_a_delivery_then_the_departure_of_the_members(self):
        self.start()
        self.deliver()
        rec = self.rec()
        self.assertEqual(rec.state, 'active')
        self.assertTrue(rec.helped)
        self.assertEqual([(h.name, h.caller, h.cid) for h in lua_list(rec.helpers)], [('Kate Smith', 'solo', None)])
        self.ev('poll()')                                    # still inside: nothing
        self.assertEqual(self.rec().state, 'active')
        self.leave()
        self.assertTrue(self.ev('poll()'))
        rec = self.rec()
        self.assertEqual((rec.state, rec.scene), ('saved', 'pending'))
        self.assertIsNone(self.ev('return R.activeFor(R.teamOf(ME))'))
        fact = lua_list(self.g.FACTS)[0]
        self.assertEqual((fact.fields.result, lua_list(fact.fields.participants)), ('saved', ['Kate Smith']))
        self.assertIn('[RadioSurvivor] rescue: rsc-1: the helpers left, the survivors leave too (saved, 1 helper(s))',
                      self.logs())

    def test_a_visit_without_delivery_saves_nobody(self):
        self.start()
        self.ev('poll()')
        self.rt.execute('ME.x, ME.y = 5003, 5003')            # inside, keeps the beans
        self.ev('poll()')
        self.leave()
        self.assertFalse(self.ev('poll()'))
        rec = self.rec()
        self.assertEqual(rec.state, 'active')
        self.assertIsNone(rec.helped)
        self.assertEqual(len(lua_list(self.g.FACTS)), 0)

    def test_a_dead_or_disconnected_member_counts_as_gone(self):
        self.start()
        self.deliver()
        self.rt.execute('ME.dead = true')
        self.ev('poll()')
        self.assertEqual(self.rec().state, 'saved')

    def test_every_member_near_after_the_delivery_is_a_helper(self):
        self.g.SIDE = 'server'
        self.rt.execute('ME.getUsername = function() return "kate" end; RS_CarnetServer.bound[ME] = "c1"'
                        '; BOB = Member(5003, 4995, "bob")')
        self.rt.execute('R.teamOf = function() return "fac-1" end; package.loaded["RadioSurvivor/RS_Factions"].idOf'
                        ' = function() return "fac-1" end')
        self.start()
        self.deliver()
        self.leave()                                          # Kate gone, Bob still near
        self.ev('poll()')
        self.assertEqual(self.rec().state, 'active')
        self.assertEqual([(h.name, h.caller, h.cid) for h in lua_list(self.rec().helpers)],
                         [('Kate Smith', 'kate', 'c1'), ('bob Smith', 'bob', None)])
        self.leave('BOB')
        self.ev('poll()')
        self.assertEqual(self.rec().state, 'saved')
        self.assertEqual(lua_list(lua_list(self.g.FACTS)[0].fields.participants), ['Kate Smith', 'bob Smith'])
        # Each helper is remembered with the other one; only the character bound to the notebook gets a life log.
        self.assertEqual(lua_list(self.ev('return Memory.facts("darlene", "kate", "c1")')),
                         ['Came in time with supplies; we got out thanks to them', 'Came with bob Smith'])
        self.assertEqual(lua_list(self.ev('return Memory.facts("darlene", "bob", nil)')),
                         ['Came in time with supplies; we got out thanks to them', 'Came with Kate Smith'])
        self.assertEqual([(e.cid, e.outcome, e.label) for e in lua_list(self.g.LIFE)], [('c1', 'saved', 'Darlene')])

    def test_helpers_are_bounded_and_not_repeated(self):
        self.start()
        self.rt.execute('R.RUN.MAX_HELPERS = 2')
        self.assertEqual(self.ev('return R.noteHelpers("rsc-1", { { name = "A", caller = "a" },'
                                 ' { name = "A", caller = "a" }, { name = "B", caller = "b", cid = "c9" },'
                                 ' { name = "C", caller = "c" }, { caller = "x" }, "junk" })'), 2)
        self.assertEqual([h.name for h in lua_list(self.rec().helpers)], ['A', 'B'])
        self.assertTrue(self.ev('return STATE.dirty'))
        self.rt.execute('R.finish("rsc-1", "abandoned")')
        self.assertIsNone(self.ev('return R.noteHelpers("rsc-1", {})'))


class PrepareTests(SceneHarness):

    def saved(self):
        self.start()
        self.deliver()
        self.leave()
        self.ev('poll()')
        return self.raw()

    def test_cache_with_a_note_in_english_without_translations(self):
        raw = self.saved()
        order = lua_list(self.ev('return require("RadioSurvivor/RS_Config").Caches.order'))
        self.assertIn(raw.cache.table, order)
        self.assertEqual((raw.cache.key, raw.cache.placed, raw.cache.placing), ('rsc-1', False, False))
        self.assertEqual((raw.cache.spot.x, raw.cache.spot.y), (raw.site.x, raw.site.y))
        self.assertEqual(raw.cache.note.name, 'A note from Darlene')
        text = raw.cache.note.text
        self.assertTrue(text.startswith('To Kate Smith,'))
        self.assertTrue(text.rstrip().endswith('Darlene'))
        self.assertIsNone(re.search(r'\d', text))
        self.assertNotIn('IGUI_', text)
        # Same table for the same rescue id (drawn from the id).
        self.assertEqual(self.ev('return require("RadioSurvivor/RS_Caches").drawTable(R.drawer("rsc-1"))'),
                         raw.cache.table)

    def test_note_in_the_language_of_the_authority(self):
        self.rt.execute('TEXTS = { IGUI_RS_RescueNote_Item = "Un mot de %1", IGUI_RS_RescueNote_Text = "Pour %1 -- %2",'
                        ' IGUI_RS_RescueNote_Friends = "nos amis", IGUI_RS_RescueNote_Signer = "ceux que vous avez sauves" }'
                        '; getTextOrNull = function(key, a, b) local t = TEXTS[key] if t == nil then return nil end'
                        ' t = string.gsub(t, "%%1", a or "") return (string.gsub(t, "%%2", b or "")) end')
        raw = self.saved()
        self.assertEqual((raw.cache.note.name, raw.cache.note.text), ('Un mot de Darlene', 'Pour Kate Smith -- Darlene'))
        rec = self.ev('return STATE.data.rescues.rescues["rsc-1"]')
        rec.requester, rec.helpers = None, self.ev('return {}')
        self.assertEqual(self.ev('return Scene.note(STATE.data.rescues.rescues["rsc-1"]).text'),
                         'Pour nos amis -- ceux que vous avez sauves')

    def test_the_voice_moves_far_away_and_remembers_the_helpers(self):
        raw = self.saved()
        moved = raw.moved
        self.assertIsNotNone(moved.key)
        self.assertNotEqual(moved.key, raw.site.key)
        self.assertLessEqual(len(moved.place), self.ev('return require("RadioSurvivor/RadioSurvivor_Const").PERSONA_PLACE_CHARS'))
        self.assertIsNone(re.search(r'\d', moved.place))
        state = self.ev('return PersonaState.get("darlene")')
        self.assertEqual((state.place, state.morale), (moved.place, 7))
        self.assertEqual(lua_list(self.ev('return Memory.facts("darlene", "solo", nil)')),
                         ['Came in time with supplies; we got out thanks to them'])
        # The new place is never near a known base (the player stands 100 tiles from the old site).
        gap = self.ev(f'local g = nil for _, b in ipairs(BUILDINGS) do if "b" .. b:getIDString() == "{moved.key}" then'
                      ' return R.gap({ x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2() },'
                      ' { x1 = ME.x, y1 = ME.y, x2 = ME.x + 1, y2 = ME.y + 1 }) end end')
        self.assertGreaterEqual(gap, 600)
        self.assertEqual(lua_list(self.g.LIFE), [])          # no notebook character bound: no life log

    def test_a_rescue_without_voice_gets_the_cache_only(self):
        self.start(opts='days = 1')
        self.deliver()
        self.leave()
        self.ev('poll()')
        raw = self.raw()
        self.assertIsNotNone(raw.cache)
        self.assertIsNone(self.ev('return STATE.data.personaState'))
        self.assertTrue(raw.cache.note.name.startswith('A note from the people you saved'))

    def test_place_words(self):
        cases = [('house', 'TownIn', 'Rosewood', 'a house in Rosewood'),
                 ('apartment building', 'TownOutskirts', 'Valley Station', 'a place outside Valley Station'),
                 ('farmhouse', 'TownCountry', 'Muldraugh', 'a farmhouse out past Muldraugh'),
                 ('church', 'TownFar', None, 'a church out in the country'),
                 ('apartment building', None, None, 'an apartment building out in the country')]
        for label, key, town, expected in cases:
            with self.subTest(label=label, key=key):
                args = ', '.join(f'"{v}"' if v else 'nil' for v in (label, key, town))
                words = self.ev(f'return Scene.placeWords({args})')
                self.assertEqual(words, expected)
                self.assertLessEqual(len(words), 40)

    def test_no_building_left_keeps_a_place_in_words(self):
        self.rt.execute('R.pick = function() return nil, "none" end')
        raw = self.saved()
        self.assertEqual(raw.moved.place, 'somewhere safer, far from the old place')
        self.assertEqual(self.ev('return PersonaState.get("darlene").place'), raw.moved.place)

    def test_missed_and_abandoned_prepare_no_cache(self):
        self.start()
        self.rt.execute('R.consume(100)')
        raw = self.raw()
        self.assertEqual((raw.state, raw.scene, raw.cache), ('missed', 'pending', None))
        self.assertIsNone(self.ev('return PersonaState.get("darlene")'))

    def test_work_store_keeps_the_life_log_and_facts_alone(self):
        self.rt.execute('R.useStore(R.newStore()); RS_CarnetServer.bound[ME] = "c1"')
        self.start()
        self.deliver()
        self.leave()
        self.ev('poll()')
        self.assertEqual(self.rec().state, 'saved')
        self.assertEqual(lua_list(self.g.LIFE), [])
        self.assertEqual(lua_list(self.g.FACTS), [])
        self.assertIsNone(self.ev('return STATE.data.rescues'))


class PlacementTests(SceneHarness):

    def setUp(self):
        super().setUp()
        self.start()
        self.deliver()
        self.leave()
        self.ev('poll()')

    def bags(self):
        return [it for it in lua_list(self.ev('return floorItems()')) if it.full == 'Base.Bag_DuffelBag']

    def test_placed_only_when_the_site_is_loaded_and_only_once(self):
        self.g.SITE_LOADED = False
        self.assertFalse(self.scene_poll())
        self.assertEqual(self.raw().scene, 'pending')
        self.assertEqual(self.bags(), [])
        self.g.SITE_LOADED = True
        self.g.CLOCK = self.g.CLOCK + 10000                   # past the cache retry delay
        self.assertTrue(self.scene_poll())
        raw = self.raw()
        self.assertEqual((raw.scene, raw.cache.placed), ('placed', True))
        bags = self.bags()
        self.assertEqual(len(bags), 1)
        bag = bags[0]
        self.assertEqual(bag.md.RS_Cache, 'rsc-1')
        inside = lua_list(bag._bag['items'])
        notes = [it for it in inside if it.full == 'Base.SheetPaper2']
        self.assertEqual(len(notes), 1)
        note = notes[0]
        self.assertEqual((note.locked, note.custom, note.name), ('RadioSurvivor', True, 'A note from Darlene'))
        self.assertEqual(note.pages[1], raw.cache.note.text)
        self.assertGreater(len(inside), 1)                    # the table contents too
        self.assertEqual(raw.cache.itemId, bag.id)
        self.assertIn('[RadioSurvivor] rescue: rsc-1: scene of the saved survivors placed (cache '
                      f'{bag.id})', self.logs())
        # Later polls and a restart (module memory reset): no second bag.
        self.g.CLOCK = self.g.CLOCK + 10000
        self.rt.execute('Scene.resetForTests(); Caches.resetForTests(); R.resetSession()')
        self.assertFalse(self.scene_poll())
        self.assertEqual(len(self.bags()), 1)

    def test_a_stop_between_placing_and_placed_adopts_the_bag(self):
        self.g.CLOCK = self.g.CLOCK + 10000
        self.scene_poll()
        # Simulated stop: the state on disk still says placing, not placed, while the bag is on the floor.
        self.rt.execute('local c = STATE.data.rescues.rescues["rsc-1"].cache; c.placed, c.placing = false, true'
                        '; STATE.data.rescues.rescues["rsc-1"].scene = "pending"; Caches.resetForTests()')
        self.g.CLOCK = self.g.CLOCK + 10000
        self.assertTrue(self.scene_poll())
        self.assertEqual(len(self.bags()), 1)
        self.assertEqual(self.raw().scene, 'placed')


class SuiteTests(SceneHarness):
    """La suite en jeu rs.rescue.saved jouée par le vrai moteur RST sur les doublures (joueur dans le bâtiment)."""

    SUITE_DOUBLES = r"""
    getCell = function() return SCELL end
    ME.x, ME.y = 5003, 5003
    local make = instanceItem
    instanceItem = function(full)
        local it = make(full)
        function it:getFullType() return self.full end
        function it:getLockedBy() return self.locked end
        function it:getName() return self.name end
        if it._bag then function it._bag:getItems() return JList(self.items) end end
        return it
    end
    local floor = Floor
    Floor = function(x, y, z)
        local sq = floor(x, y, z)
        function sq:transmitRemoveItemFromSquare(wo)
            for i = #self.world, 1, -1 do if self.world[i] == wo:getItem() then table.remove(self.world, i) end end
        end
        return sq
    end
    """

    def run_suite(self):
        self.rt.execute(self.SUITE_DOUBLES)
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{base.SUITE.as_posix()}]])')
        self.assertTrue(self.ev('RST.start("rs.rescue.saved", { attach = false, ctx = { player = ME } })'))
        for _ in range(300):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(len(results), 3)
        self.assertEqual([it for it in lua_list(self.ev('return floorItems()')) if it.full == 'Base.Bag_DuffelBag'], [])
        self.assertIsNone(self.ev('return STATE.data.personaState and STATE.data.personaState["rst-rescue-voice"]'))
        self.assertIsNone(self.ev('return STATE.data.memory and STATE.data.memory["rst-rescue-voice"]'))
        self.assertIsNone(self.ev('return STATE.data.rescues'))
        self.assertEqual(lua_list(self.g.LIFE), [])

    def test_suite_detects_a_scene_never_closed(self):
        self.rt.execute('R.scenePlaced = function() return true end')   # the scene stays pending
        results = self.run_suite()
        self.assertEqual(results['the scene is placed once, when the site is loaded'][0], 'FAIL')


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
        self.assertNotIn('getGridSquare', body)              # squares are read by RS_Caches.place only


if __name__ == '__main__':
    unittest.main(verbosity=1)
