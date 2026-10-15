"""Issue « trop tard » d'un secours (E12-T05) : RS_Rescue (survivants et tenues décrites) et RS_RescueLost
(cadavres en tenue, dernières pages, pose unique) dans lupa.

    python RadioSurvivor/tests/test_rescue_lost.py

Vrai Lua du mod (RS_Rescue, RS_RescueVisit, RS_RescueScene, RS_RescueLost, RS_LastPages pour la mise en page et
l'objet, RS_Caches, RS_Memory, RS_PersonaState, RS_State ; `next` retiré comme dans Kahlua) sur les doublures de
tests/test_rescue_scene.py, plus la chaîne du « joueur réanimé » (E12-T07), relevée dans le Java 42.21.0 :
addZombiesInOutfit à 6 arguments (LuaManager.java:8355-8371 ; zombie ordinaire dans la liste des zombies),
IsoZombie.DoZombieInventory (vide l'inventaire d'un zombie ordinaire et y recrée ses vêtements, ne fait rien pour un
joueur réanimé : IsoZombie.java:3129-3165), IsoGridSquare.createCorpse (nil pour un argument qui n'est pas un zombie,
IsoGridSquare.java:10100-10124 ; le cadavre prend l'inventaire et une copie des ModData, le zombie quitte la liste :
IsoDeadBody.java:327-332, 378-380), IsoDeadBody.reanimate (joueur réanimé avec l'inventaire et les ModData du
cadavre, IsoDeadBody.java:1832-1946), mort sur l'autorité (die : DoZombieInventory puis cadavre avec l'inventaire du
mort), getZombieList de la cellule ; cases à objets statiques (getStaticMovingObjects), cahier Base.Notebook
(Literature : addPage, setLockedBy, setName, setCustomName).
Couvre : 2 ou 3 survivants aux tenues distinctes de la liste fermée, tirage stable, description anglaise sans chiffre
(le demandeur d'abord) ; issue « missed » préparée (dernières pages composées des faits seulement, anglais sans
traduction ou traduites, option LastPages coupée = aucune page, relevé de vie des aidants hors magasin de travail) ;
issue « saved » toujours confiée à RS_RescueScene ; pose seulement quand la case du site est chargée et le bâtiment
prêt : un zombie (joueur réanimé) par survivant dans sa tenue, aucun cadavre posé, sur des cases distinctes, cahier
verrouillé dans l'INVENTAIRE du seul demandeur et retrouvé dans son cadavre quand il est tué (serveur : rien envoyé
pour le zombie vivant) ; une seule fois, même après un redémarrage, et adoption des zombies (et d'un cadavre déjà
tué) avec le cahier après un arrêt entre « placing » et « placed » ; LastPages coupée : zombies sans cahier ; ancien
secours sans survivants préparé à la pose ; suite rs.rescue.missed jouée par le vrai moteur RST.
Ne prouve pas l'API Java réelle (surcharges Kahlua, tenue et cadavre vus par un client MP) : suite en jeu.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

import test_rescue as base
import test_rescue_scene as scene

MODULE = base.MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_RescueLost.lua'
lua_list = base.lua_list

LOST_DOUBLES = r"""
STREAMED = STREAMED or {}
ZOMBIES = {}          -- zombie list of the cell (living)
MADE = {}             -- zombies that survived the chain (reanimated players), in order
TEMPS = {}            -- temporary zombies of addZombiesInOutfit
NEXT_Z = 100
ADD_CALLS = 0
instanceof = (function(prev)
    return function(o, cls)
        if cls == "IsoDeadBody" then return type(o) == "table" and o._body == true end
        if cls == "IsoZombie" then return type(o) == "table" and o._zombie == true end
        if cls == "Literature" and type(o) == "table" and o._notebook then return true end
        return prev(o, cls)
    end
end)(instanceof)
instanceItem = (function(prev)
    return function(full)
        local it = prev(full)
        if full == "Base.Notebook" then
            it._literature, it._notebook, it.pages = true, true, {}
            function it:addPage(i, text) self.pages[i] = text end
            function it:setLockedBy(who) self.locked = who end
            function it:setName(n) self.name = n end
            function it:setCustomName(v) self.custom = v end
        end
        function it:getFullType() return self.full end
        function it:getLockedBy() return self.locked end
        function it:getName() return self.name end
        return it
    end
end)(instanceItem)
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
local function remove(list, v)
    for i = #list, 1, -1 do if list[i] == v then table.remove(list, i) return true end end
    return false
end
local function inventory(items)
    local c = Container(items or {})
    function c:AddItem(it) return self:add(it) end
    function c:contains(it) return self:has(it) end
    return c
end
local newZombie
-- Corpse of zombie zed on its square (IsoDeadBody constructor: inventory taken, ModData copied, zombie out of the list).
local function corpseOf(zed)
    local sq = zed.sq
    local b = { _body = true, sq = sq, outfit = zed.outfit, female = zed.female, md = copy(zed.md), c = zed.inv,
                fake = false, wasReanimated = zed.reanimated }
    zed.inv = inventory()
    remove(ZOMBIES, zed)
    function b:getOutfitName() return self.outfit end
    function b:isFakeDead() return self.fake end
    function b:getModData() return self.md end
    function b:hasModData() for _ in pairs(self.md) do return true end return false end
    function b:getContainer() return self.c end
    function b:getSquare() return self.sq end
    function b:reanimate()
        remove(self.sq.static, self)
        local z = newZombie(self.sq, self.outfit, self.female, not self.fake)
        z.md, z.inv = copy(self.md), self.c
        return z
    end
    sq.static[#sq.static + 1] = b
    return b
end
newZombie = function(sq, outfit, female, reanimated)
    NEXT_Z = NEXT_Z + 1
    local z = { _zombie = true, id = NEXT_Z, sq = sq, outfit = outfit, female = female, md = {}, inv = inventory(),
                reanimated = reanimated, dead = false, health = 1 }
    function z:getModData() return self.md end
    function z:hasModData() for _ in pairs(self.md) do return true end return false end
    function z:getInventory() return self.inv end
    function z:getOutfitName() return self.outfit end
    function z:isDead() return self.dead end
    function z:isReanimatedPlayer() return self.reanimated end
    function z:getSquare() return self.sq end
    function z:getCurrentSquare() return self.sq end
    function z:getX() return self.sq.x + 0.5 end
    function z:getY() return self.sq.y + 0.5 end
    function z:getZ() return self.sq.z end
    function z:DoZombieInventory()
        if self.reanimated then return end   -- IsoZombie.java:3129-3165
        self.inv.items = { instanceItem("Base.Clothes_" .. tostring(self.outfit)) }
    end
    function z:setHealth(h) self.health = h end
    function z:setAttackedBy(who) self.attacker = who end
    function z:removeFromWorld() remove(ZOMBIES, self) self.removed = true end
    function z:removeFromSquare() end
    -- Death on the authority: onKilled (DoZombieInventory) then the corpse with the inventory of the dead.
    function z:die()
        if self.dead then return end
        self.dead = true
        self:DoZombieInventory()
        self.corpse = corpseOf(self)
    end
    ZOMBIES[#ZOMBIES + 1] = z
    if reanimated then MADE[#MADE + 1] = z end
    return z
end
addZombiesInOutfit = function(x, y, z, n, outfit, femaleChance, ...)
    if select("#", ...) > 0 or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
        or type(n) ~= "number" or type(outfit) ~= "string" or type(femaleChance) ~= "number" then
        error("No implementation found for addZombiesInOutfit")
    end
    ADD_CALLS = ADD_CALLS + 1
    if NO_ZOMBIE then return JList({}) end
    local zed = newZombie(SCELL:getGridSquare(x, y, z), outfit, femaleChance >= 100, false)
    TEMPS[#TEMPS + 1] = zed
    return JList({ zed })
end
Floor = (function(prev)
    return function(x, y, z)
        local sq = prev(x, y, z)
        sq.static = sq.static or {}
        function sq:getStaticMovingObjects() return JList(self.static) end
        -- IsoGridSquare.createCorpse(IsoZombie): nil for anything else (createCorpse(false) draws from an empty list).
        function sq:createCorpse(zed)
            if type(zed) ~= "table" or not zed._zombie then return nil end
            return corpseOf(zed)
        end
        function sq:removeCorpse(body) remove(self.static, body) body.removed = true end
        return sq
    end
end)(Floor)
function SCELL:getZombieList() return JList(ZOMBIES) end
function corpses()
    local out = {}
    for _, sq in pairs(FLOOR) do for _, b in ipairs(sq.static or {}) do out[#out + 1] = b end end
    return out
end
function notebooks(c)
    local n = 0
    for _, it in ipairs(c.items) do if it.full == "Base.Notebook" then n = n + 1 end end
    return n
end
ADDED = {}
sendAddItemToContainer = function(c, it) ADDED[#ADDED + 1] = it end
LastPages = require("RadioSurvivor/RS_LastPages")
Lost = require("RadioSurvivor/RS_RescueLost")
function lostPoll() getCell = function() return SCELL end return Lost.poll(true) end
"""


class LostHarness(scene.SceneHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(LOST_DOUBLES)

    def missed(self, opts='days = 1, voice = "darlene", requester = "Darlene"'):
        self.start(opts=opts)
        self.rt.execute('R.consume(100)')
        return self.raw()

    def zombies(self):
        return lua_list(self.g.MADE)

    def corpses(self):
        return lua_list(self.ev('return corpses()'))

    def notes(self, container):
        return [it for it in lua_list(container['items']) if it.full == 'Base.Notebook']

    def place(self):
        self.g.CLOCK = self.g.CLOCK + 20000
        return self.ev('return lostPoll()')


class SurvivorTests(LostHarness):

    def test_two_or_three_distinct_outfits_of_the_closed_list(self):
        outfits = {o.outfit: o.look for o in lua_list(self.ev('return R.OUTFITS'))}
        counts = set()
        for i in range(1, 30):
            got = lua_list(self.ev(f'return R.drawSurvivors({{ id = "rsc-{i}", site = {{ key = "b{i * 7}" }} }})'))
            counts.add(len(got))
            names = [s.outfit for s in got]
            self.assertEqual(len(set(names)), len(names))
            for s in got:
                self.assertEqual(outfits[s.outfit], s.look)
            self.assertEqual([bool(s.requester) for s in got], [True] + [False] * (len(got) - 1))
        self.assertEqual(counts, {2, 3})

    def test_draw_is_stable_for_a_rescue(self):
        a = [s.outfit for s in lua_list(self.ev('return R.drawSurvivors({ id = "rsc-4", site = { key = "b9" } })'))]
        b = [s.outfit for s in lua_list(self.ev('return R.drawSurvivors({ id = "rsc-4", site = { key = "b9" } })'))]
        self.assertEqual(a, b)

    def test_start_keeps_survivors_and_their_description(self):
        self.start()
        rec = self.rec()
        survivors = lua_list(rec.survivors)
        looks = lua_list(rec.looks)
        self.assertEqual(len(looks), len(survivors))
        self.assertEqual(looks[0], f'I am wearing {survivors[0].look}.')
        for s, line in zip(survivors[1:], looks[1:]):
            self.assertEqual(line, f'One of the others is wearing {s.look}.')
        for line in looks:
            self.assertIsNone(re.search(r'\d', line))
        self.assertEqual([s.outfit for s in lua_list(self.raw().survivors)], [s.outfit for s in survivors])

    def test_every_outfit_exists_for_both_sexes_in_vanilla(self):
        path = pz_paths.media_dir() / 'clothing/clothing.xml'
        if not path.exists():
            self.skipTest('vanilla clothing.xml not installed here')
        found = {'Female': set(), 'Male': set()}
        sex = None
        for part in re.split(r'(<m_(?:Female|Male)Outfits>)', path.read_text(encoding='utf-8', errors='replace')):
            m = re.match(r'<m_(Female|Male)Outfits>', part)
            if m:
                sex = m.group(1)
                continue
            name = re.search(r'<m_Name>([^<]+)</m_Name>', part)
            if sex and name:
                found[sex].add(name.group(1))
        for o in lua_list(self.ev('return R.OUTFITS')):
            self.assertIn(o.outfit, found['Female'])
            self.assertIn(o.outfit, found['Male'])
            self.assertFalse(o.outfit.startswith(('Bandit', 'Survivalist')))


class PrepareTests(LostHarness):

    def test_missed_prepares_bodies_and_last_pages_in_english(self):
        raw = self.missed()
        self.assertEqual((raw.state, raw.scene, raw.cache), ('missed', 'pending', None))
        lost = raw.lost
        self.assertEqual((lost.placing, lost.placed, lost.bodies), (False, False, len(lua_list(raw.survivors))))
        self.assertEqual(lost.pages.name, 'Last pages of Darlene')
        text = lost.pages.text
        self.assertTrue(text.startswith('We called for help on the radio. We waited a whole day.'))
        self.assertIn(f'There were {len(lua_list(raw.survivors))} of us in here.', text)
        self.assertNotIn('IGUI_', text)
        self.assertTrue(text.rstrip().endswith('- Darlene'))
        self.assertIsNone(self.ev('return PersonaState.get("darlene")'))
        self.assertIn('[RadioSurvivor] rescue: rsc-1: too late, ', ' '.join(self.logs()))

    def test_pages_tell_only_the_facts(self):
        self.start(opts='days = 3, requester = "Darlene"')
        self.rt.execute('local r = STATE.data.rescues.rescues["rsc-1"]; r.approaches = 1')
        self.rt.execute('R.consume(1000)')
        text = self.raw().lost.pages.text
        self.assertIn('We waited 3 days.', text)
        self.assertIn('Once we saw someone come close. They did not stay.', text)
        self.assertNotIn('Someone left us food', text)
        self.assertNotIn('5000', text)
        # A delivery: no "came close" line (they helped), the food line instead; no requester: signer.
        self.rt.execute('local r = STATE.data.rescues.rescues["rsc-1"]; r.delivered, r.helped, r.requester = 8, true, nil')
        text = self.ev('return Lost.pages(STATE.data.rescues.rescues["rsc-1"]).text')
        self.assertIn('Someone left us food.', text)
        self.assertNotIn('came close', text)
        self.assertTrue(text.endswith('- the people who waited'))

    def test_translated_pages(self):
        self.rt.execute('TEXTS = { IGUI_RS_RescueLast_Item = "Dernieres pages de %1",'
                        ' IGUI_RS_RescueLast_WaitedOne = "Une journee.", IGUI_RS_RescueLast_Group = "Nous etions %1.",'
                        ' IGUI_RS_RescueLast_End = "Fin." }')
        raw = self.missed()
        self.assertEqual(raw.lost.pages.name, 'Dernieres pages de Darlene')
        self.assertTrue(raw.lost.pages.text.startswith('Une journee.\n\nNous etions '))

    def test_option_off_means_no_pages(self):
        self.rt.execute('require("RadioSurvivor/RadioSurvivor_Const").lastPages = function() return false end')
        raw = self.missed()
        self.assertIsNone(raw.lost.pages)
        self.assertIn('option LastPages off', ' '.join(self.logs()))

    def test_saved_stays_with_the_scene_of_e12_t04(self):
        self.start()
        self.deliver()
        self.leave()
        self.ev('poll()')
        raw = self.raw()
        self.assertEqual(raw.state, 'saved')
        self.assertIsNotNone(raw.cache)
        self.assertIsNone(raw.lost)

    def test_life_log_of_the_helpers_outside_the_work_store(self):
        self.start()
        self.ev('R.noteHelpers("rsc-1", { { name = "Kate Smith", caller = "kate", cid = "c1" },'
                ' { name = "Bob", caller = "bob" } })')
        self.rt.execute('R.consume(100)')
        self.assertEqual([(e.cid, e.outcome, e.label) for e in lua_list(self.g.LIFE)], [('c1', 'missed', 'Darlene')])

    def test_work_store_keeps_the_life_log_alone(self):
        self.rt.execute('R.useStore(R.newStore())')
        self.start()
        self.ev('R.noteHelpers("rsc-1", { { name = "Kate Smith", caller = "kate", cid = "c1" } })')
        self.rt.execute('R.consume(100)')
        self.assertEqual(lua_list(self.g.LIFE), [])
        self.assertIsNotNone(self.ev('return R.get("rsc-1").lost'))


class PlacementTests(LostHarness):

    def test_placed_when_the_site_is_loaded_one_zombie_per_outfit(self):
        raw = self.missed()
        self.g.SITE_LOADED = False
        self.assertFalse(self.place())
        self.assertEqual(self.zombies(), [])
        self.g.SITE_LOADED = True
        self.assertTrue(self.place())
        raw = self.raw()
        self.assertEqual((raw.scene, raw.lost.placed, raw.lost.placing), ('placed', True, False))
        survivors = lua_list(raw.survivors)
        zombies = self.zombies()
        self.assertEqual([z.outfit for z in zombies], [s.outfit for s in survivors])
        self.assertEqual(lua_list(raw.lost.outfits), [s.outfit for s in survivors])
        self.assertTrue(all(z.reanimated and not z.dead for z in zombies))
        self.assertEqual(len(lua_list(self.g.ZOMBIES)), len(zombies))        # temporary zombies gone
        self.assertEqual(self.corpses(), [])                                 # no corpse placed
        self.assertEqual([z.md.RS_RescueBody for z in zombies], [f'rsc-1#{i}' for i in range(1, len(zombies) + 1)])
        self.assertEqual(len({(z.sq.x, z.sq.y) for z in zombies}), len(zombies))
        b = raw.site.bounds
        for z in zombies:
            self.assertTrue(b.x1 <= z.sq.x < b.x2 and b.y1 <= z.sq.y < b.y2)
            self.assertEqual(z.sq.z, raw.site.z)
        notes = self.notes(zombies[0].inv)
        self.assertEqual(len(notes), 1)
        note = notes[0]
        self.assertEqual((note.full, note.locked, note.custom, note.name),
                         ('Base.Notebook', 'RadioSurvivor', True, 'Last pages of Darlene'))
        self.assertEqual(note.md.RS_RescuePages, 'rsc-1')
        self.assertIn('There were', note.pages[1])
        for other in zombies[1:]:
            self.assertEqual(self.notes(other.inv), [])
            self.assertEqual(len(lua_list(other.inv['items'])), 1)          # its clothes only
        self.assertIn('rsc-1: scene of the lost survivors placed', ' '.join(self.logs()))
        self.assertIn('last pages: zombie', ' '.join(self.logs()))

    def test_requester_killed_leaves_the_notebook_in_its_corpse(self):
        self.missed()
        self.g.SIDE = 'server'
        self.assertTrue(self.place())
        self.assertEqual(lua_list(self.g.ADDED), [])                         # living zombie: nothing sent
        zombies = self.zombies()
        self.rt.execute('MADE[1]:setAttackedBy(ME); MADE[1]:die(); MADE[2]:die()')
        first, second = self.g.MADE[1].corpse, self.g.MADE[2].corpse
        self.assertEqual(len(self.notes(first.c)), 1)
        self.assertEqual(self.notes(first.c)[0].md.RS_RescuePages, 'rsc-1')
        self.assertEqual(self.notes(second.c), [])
        self.assertEqual(first.getOutfitName(first), zombies[0].outfit)
        self.assertEqual(first.md.RS_RescueBody, 'rsc-1#1')

    def test_only_once_even_after_a_restart(self):
        self.missed()
        self.assertTrue(self.place())
        n = len(self.zombies())
        self.rt.execute('Lost.resetForTests(); R.resetSession()')
        self.assertFalse(self.place())
        self.assertEqual(len(self.zombies()), n)
        self.assertEqual(self.g.ADD_CALLS, n)

    def test_a_stop_between_placing_and_placed_adopts_zombies_and_pages(self):
        self.missed()
        self.assertTrue(self.place())
        n = len(self.zombies())
        # Simulated stop: the state on disk still says placing; the requester walks away (still in the zombie list),
        # the others are lost.
        self.rt.execute('local r = STATE.data.rescues.rescues["rsc-1"]; r.lost.placed, r.lost.placing = false, true'
                        '; r.scene = "pending"; Lost.resetForTests(); MADE[1].sq = Floor(4000, 4000, 0)'
                        '; for i = 2, #MADE do MADE[i]:removeFromWorld() end')
        self.assertTrue(self.place())
        self.assertEqual(self.g.ADD_CALLS, n + (n - 1))
        self.assertEqual(len(self.notes(self.zombies()[0].inv)), 1)
        self.assertEqual(self.raw().scene, 'placed')
        self.assertIn('1 adopted', ' '.join(self.logs()))
        self.assertIn('last pages: kept', ' '.join(self.logs()))

    def test_a_stop_after_the_requester_was_killed_adopts_its_corpse(self):
        self.missed()
        self.g.SIDE = 'server'
        self.assertTrue(self.place())
        n = len(self.zombies())
        # Killed before the stop, its notebook taken by a player; the state on disk still says placing.
        self.rt.execute('MADE[1]:die(); local c = MADE[1].corpse.c; c.items = {}'
                        '; local r = STATE.data.rescues.rescues["rsc-1"]; r.lost.placed, r.lost.placing = false, true'
                        '; r.scene = "pending"; Lost.resetForTests()')
        self.assertTrue(self.place())
        self.assertEqual(self.g.ADD_CALLS, n)                                # nothing made again
        corpse = self.g.MADE[1].corpse
        self.assertEqual(len(self.notes(corpse.c)), 1)
        self.assertEqual(len(lua_list(self.g.ADDED)), 1)                    # corpse container sent
        self.assertIn(f'{n} adopted', ' '.join(self.logs()))
        self.assertIn('last pages: corpse', ' '.join(self.logs()))

    def test_no_zombie_made(self):
        self.missed()
        self.g.NO_ZOMBIE = True
        self.assertTrue(self.place())                       # placed without zombies (game made none): logged
        self.assertIn('the game made no zombie for survivor 1: addZombiesInOutfit made no zombie',
                      ' '.join(self.logs()))
        raw = self.raw()
        self.assertEqual(lua_list(raw.lost.outfits), [])

    def test_a_chain_failure_leaves_no_debris(self):
        self.missed()
        self.rt.execute('local create = Floor; Floor = function(x, y, z) local sq = create(x, y, z)'
                        '; function sq:createCorpse() return nil end; return sq end')
        self.assertTrue(self.place())
        self.assertIn('createCorpse made no corpse', ' '.join(self.logs()))
        self.assertEqual(lua_list(self.g.ZOMBIES), [])                       # temporary zombies removed
        self.assertEqual(self.zombies(), [])

    def test_pages_on_the_floor_without_the_requester(self):
        self.missed()
        self.g.NO_ZOMBIE = True
        self.place()
        notebooks = [it for it in lua_list(self.ev('return floorItems()')) if it.full == 'Base.Notebook']
        self.assertEqual(len(notebooks), 1)

    def test_option_off_at_placement_places_no_pages(self):
        self.missed()
        self.rt.execute('require("RadioSurvivor/RadioSurvivor_Const").lastPages = function() return false end')
        self.place()
        self.assertGreaterEqual(len(self.zombies()), 2)
        for z in self.zombies():
            self.assertEqual(self.notes(z.inv), [])

    def test_older_missed_record_is_prepared_at_placement(self):
        self.start()
        self.rt.execute('local r = STATE.data.rescues.rescues["rsc-1"]; r.survivors, r.looks = nil, nil'
                        '; local hook = R.sceneHook; R.sceneHook = nil; R.consume(100); R.sceneHook = hook')
        self.assertIsNone(self.raw().lost)
        self.assertTrue(self.place())
        raw = self.raw()
        self.assertEqual(raw.scene, 'placed')
        self.assertGreaterEqual(len(lua_list(raw.survivors)), 2)
        self.assertEqual(len(self.zombies()), len(lua_list(raw.survivors)))

    def test_saved_scenes_are_left_to_rs_rescue_scene(self):
        self.start()
        self.deliver()
        self.leave()
        self.ev('poll()')
        self.assertFalse(self.place())
        self.assertEqual(self.zombies(), [])


SUITE_TEST = 'too late: survivors are zombies in the described outfits, the requester carries the last pages'

class SuiteTests(LostHarness):
    """La suite en jeu rs.rescue.missed jouée par le vrai moteur RST sur les doublures (joueur dans le bâtiment)."""

    SUITE_DOUBLES = r"""
    getCell = function() return SCELL end
    ME.x, ME.y = 5003, 5003
    """

    def run_suite(self):
        self.rt.execute(self.SUITE_DOUBLES)
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{base.SUITE.as_posix()}]])')
        self.assertTrue(self.ev('RST.start("rs.rescue.missed", { attach = false, ctx = { player = ME } })'))
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
        self.assertTrue(all(z.removed for z in self.zombies() if not z.dead))
        self.assertEqual(self.corpses(), [])                                 # killed requester's corpse removed
        self.assertEqual(lua_list(self.g.ZOMBIES), [])
        self.assertIsNone(self.ev('return STATE.data.rescues'))
        self.assertEqual(lua_list(self.g.LIFE), [])

    def test_suite_detects_a_wrong_outfit(self):
        self.rt.execute('local add = addZombiesInOutfit'
                        '; addZombiesInOutfit = function(x, y, z, n, o, f) return add(x, y, z, n, "Naked", f) end')
        results = self.run_suite()
        self.assertEqual(results[SUITE_TEST][0], 'FAIL')

    def test_suite_detects_a_notebook_lost_at_death(self):
        # An ordinary zombie (not a reanimated player) empties its inventory at death: the notebook is lost.
        self.rt.execute('local wrap = Floor; Floor = function(x, y, z) local sq = wrap(x, y, z)'
                        '; local c = sq.createCorpse; function sq:createCorpse(zed) local b = c(self, zed)'
                        ' if b then b.fake = true end return b end return sq end')
        results = self.run_suite()
        self.assertEqual(results[SUITE_TEST][0], 'FAIL')


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

    def test_translations_en_fr(self):
        import json
        keys = set(re.findall(r'"(IGUI_RS_RescueLast_\w+)"', MODULE.read_text(encoding='utf-8')))
        self.assertGreaterEqual(len(keys), 8)
        for lang in ('EN', 'FR'):
            path = base.MOD_LUA / 'shared' / 'Translate' / lang / 'IG_UI.json'
            data = json.loads(path.read_text(encoding='utf-8'))
            for key in keys:
                self.assertIn(key, data, f'{lang} {key}')


if __name__ == '__main__':
    unittest.main(verbosity=1)
