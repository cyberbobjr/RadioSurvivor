"""Tests hors jeu des corvées des PNJ Living Knox au foyer (LK05-T04) : server/LivingKnox/LK_Routines.lua (section
« corvées »), comportement « chore » de LK_Decisions.lua, gestes de LK_Anim.lua.

    python RadioSurvivor/tests/test_lk_chores.py

Bancs :
- logique pure : poids des corvées selon poste, rôle et traits (liste fermée CHORES), tirage déterministe par identité et
  créneau de temps de jeu, créneau décalé par membre, cascade (poste puis routine, de jour ; menace d'abord) ;
- relevé des places de corvée dans un monde doublé (maison HOUSE de test_lk_routines.py) : cheminée (IsoFireplace),
  cuisinière (conteneur « stove »), meubles à conteneur, micro-ondes écarté (CellLoader.java:115, 197-231), mur entre la
  place et l'objet (isBlockedTo, IsoGridSquare.java:935-941) ; conteneurs doublés qui n'ont que getType et getItems :
  tout autre appel serait une erreur (aucune modification) ;
- pile complète (groupe « deciders ») : solo (marche simulée) et serveur dédié + deux clients.
Les doublures NE PROUVENT PAS l'API réelle ni le rendu des clips : seulement la logique (choix, places, interruption,
mêmes choix pour deux observateurs). Le rendu se vérifie en jeu (suite lk.chores).
"""
from __future__ import annotations

import sys
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_routines import POSTS, TIME_OF_DAY, RoutineStack  # noqa: E402

R = 'LivingKnox.Routines'
D = 'LivingKnox.Decisions'
CHORES = ['fire', 'warm', 'tidy', 'lookout', 'repair', 'smoke', 'care', 'rest']

# Objets de corvée doublés : cheminée, conteneurs typés (lecture seule : getType, getItems), murs entre deux cases.
OBJECTS = r'''
local H = HARNESS
local C = H.classes
local Fire = H.class('IsoFireplace', C.IsoObject)
function Fire:isLit() return false end
local Cont = H.class('ItemContainer')
function Cont:getType() return self.type end
function Cont:getItems() return H.list({ "item", "item" }) end
local Furn = H.class('IsoObject_Furniture', C.IsoObject)
-- IsoObject.getSprite : sprite sans drapeau « bed » (les doublures n'en ont pas).
function Fire:getSprite() return nil end
function Furn:getSprite() return nil end
WALLS = {}
function C.IsoGridSquare:isBlockedTo(o)
    return WALLS[self.x .. "," .. self.y .. "|" .. o.x .. "," .. o.y] == true
end
function ADD_WALL(x, y, x2, y2)
    WALLS[x .. "," .. y .. "|" .. x2 .. "," .. y2] = true
    WALLS[x2 .. "," .. y2 .. "|" .. x .. "," .. y] = true
end
function ADD_FIRE(x, y)
    local o = setmetatable({}, Fire)
    H.addObject(x, y, 0, o)
    H.square(x, y, 0).blocked = true
    return o
end
function ADD_CONTAINER(x, y, kind)
    local o = setmetatable({ container = setmetatable({ type = kind }, Cont) }, Furn)
    H.addObject(x, y, 0, o)
    H.square(x, y, 0).blocked = true
    return o
end
-- Maison de test_lk_routines + cheminée, cuisinière, micro-ondes, caisse, meuble muré sur deux côtés, réfrigérateur.
function FURNISH()
    ADD_FIRE(108, 112)
    ADD_CONTAINER(106, 113, "stove")
    ADD_CONTAINER(114, 106, "microwave")
    ADD_CONTAINER(112, 112, "crate")
    ADD_CONTAINER(109, 106, "wardrobe")
    ADD_WALL(109, 106, 109, 105)
    ADD_WALL(109, 106, 110, 106)
    ADD_CONTAINER(114, 114, "fridge")
end
-- Etat brut de tous les objets doublés (aucune modification attendue).
function OBJECTS_STATE()
    local out = {}
    for _, xy in ipairs({ { 108, 112 }, { 106, 113 }, { 114, 106 }, { 112, 112 }, { 109, 106 }, { 114, 114 } }) do
        local objs = H.square(xy[1], xy[2], 0).objects
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local keys = {}
            for k, v in pairs(o) do
                if k ~= "square" and k ~= "container" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
            end
            if o.container then
                for k, v in pairs(o.container) do keys[#keys + 1] = "c." .. tostring(k) .. "=" .. tostring(v) end
            end
            table.sort(keys)
            out[#out + 1] = xy[1] .. "," .. xy[2] .. ":" .. table.concat(keys, ";")
        end
    end
    return table.concat(out, "|")
end
'''


class PureChoreTests(PureBase):
    def setUp(self):
        super().setUp()
        self.run_lua(POSTS)

    def weights(self, duty, allowed='{}', traits='{}', avail=None):
        avail = avail or '{ fire = true, warm = true, tidy = true, lookout = true, repair = true, smoke = true, ' \
                         'care = true, rest = true }'
        out = self.run_lua(f'local w = {R}.choreWeights("{duty}", {allowed}, {traits}, {avail}) local out = {{}} '
                           f'for _, c in ipairs({R}.CHORES) do out[#out + 1] = c .. "=" .. w[c] end '
                           'return table.concat(out, ",")')
        return {k: int(v) for k, v in (x.split('=') for x in out.split(','))}

    def test_closed_list_and_gestures(self):
        import json
        import re
        root = Path(__file__).resolve().parents[1]
        table = json.loads((root / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        anim = (root / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / 'shared' / 'LivingKnox'
                / 'LK_Anim.lua').read_text(encoding='utf-8')
        known = set(re.findall(r'(\w+) = true', anim.split('Anim.GESTURES = {')[1].split('}')[0]))
        self.assertEqual(lua_list(self.ev(f'{R}.CHORES')), CHORES)
        for chore in CHORES:
            g = self.ev(f'{R}.CHORE_GESTURE.{chore}')
            if chore == 'lookout':
                self.assertIsNone(g)                                         # debout, regard seul
            else:
                self.assertIn(g, known, chore)                                   # geste de LK_Anim
                self.assertIn(g, table['gestures'], chore)                       # nœud généré (gen_animsets)
                self.assertTrue(any(['LKGesture', 'STRING', g] in n['conditions'] for n in table['nodes']), chore)
                self.assertTrue(self.ev(f'{R}.GESTURES["{g}"]'), chore)     # remis au repos par leave
        self.assertTrue(self.ev(f'{R}.handles("chore")'))
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.chore.vigil'), 'rest')

    def test_weights_follow_duty_role_and_traits(self):
        keeper = self.weights('keeper', '{ chores = true, cook = true }')
        self.assertEqual(keeper, {'fire': 6, 'warm': 1, 'tidy': 4, 'lookout': 2, 'repair': 1, 'smoke': 0, 'care': 1,
                                  'rest': 2})
        carer = self.weights('carer', '{ heal = true, chores = true }')
        self.assertEqual(max(carer, key=carer.get), 'care')
        builder = self.weights('builder', '{ maintain = true, fortify = true }', '{ strong = true }')
        self.assertEqual(max(builder, key=builder.get), 'repair')
        self.assertEqual(self.weights('keeper')['smoke'], 0)                  # fumer : trait seulement
        self.assertEqual(self.weights('keeper', traits='{ smoker = true }')['smoke'], 4)
        self.assertEqual(self.weights('keeper', traits='{ nervous = true }')['lookout'], 5)
        self.assertEqual(self.weights('keeper', traits='{ tidy = true }')['tidy'], 6)
        self.assertEqual(self.weights('unknown'), self.weights('routine'))  # sans poste à corvées : routine
        # Corvée sans place au foyer : poids nul.
        no_fire = self.weights('keeper', avail='{ tidy = true, rest = true }')
        self.assertEqual({k for k, v in no_fire.items() if v}, {'tidy', 'rest'})

    def test_pick_is_deterministic_and_follows_the_weights(self):
        code = (f'local w = {R}.choreWeights("keeper", {{ chores = true }}, {{ tidy = true }}, {{ fire = true, '
                'tidy = true, rest = true }) local out = {} '
                f'for slot = 1, 600 do out[#out + 1] = {R}.pickChore("lk-3", slot, w) end return table.concat(out, ",")')
        first = self.run_lua(code).split(',')
        self.assertEqual(first, self.run_lua(code).split(','))               # mêmes entrées, mêmes choix
        count = Counter(first)
        self.assertEqual(set(count), {'fire', 'tidy', 'rest'})               # rien hors des corvées possibles
        self.assertGreater(count['tidy'], count['fire'])                      # tidy 3+1+3 = 7 > fire 3+1 = 4
        self.assertGreater(count['fire'], count['rest'])                      # rest 2
        other = self.run_lua(code.replace('"lk-3"', '"lk-4"')).split(',')
        self.assertNotEqual(first, other)                                     # autre identité, autre suite
        self.assertEqual(self.ev(f'{R}.pickChore("lk-3", 5, {{}})'), 'rest')  # aucun poids : repos

    def test_slot_lasts_the_chore_minutes_and_is_shifted_per_member(self):
        span = self.ev(f'{R}.CFG.CHORE_MINUTES')
        changes = {}
        for npc in ('lk-1', 'lk-2', 'lk-3', 'lk-4'):
            slots = [self.ev(f'{R}.choreSlot("{npc}", {m})') for m in range(600, 600 + 4 * span)]
            steps = [i for i in range(1, len(slots)) if slots[i] != slots[i - 1]]
            self.assertEqual(len(steps), 4, npc)
            self.assertTrue(all(slots[i] == slots[i - 1] + 1 for i in steps), npc)
            changes[npc] = steps[0] % span
        self.assertGreater(len(set(changes.values())), 1, changes)           # pas tous à la même minute

    def test_cascade_gives_chores_by_day_and_threat_first(self):
        on = 'chores = true'
        self.assertEqual(self.decide(on)[:2], ('duty', 'chore'))               # keeper de jour
        for duty in ('carer', 'forager', 'builder'):
            self.assertEqual(self.decide(on + f', duty = "{duty}"')[:2], ('duty', 'chore'), duty)
        self.assertEqual(self.decide(on + ', night = true')[:2], ('duty', 'home'))
        self.assertEqual(self.decide(on + ', duty = false')[:2], ('routine', 'chore'))
        self.assertEqual(self.decide(on + ', duty = false, night = true')[:2], ('routine', 'rest'))
        self.assertEqual(self.decide(on + ', duty = "rest"')[:2], ('duty', 'rest'))
        self.assertEqual(self.decide(on + ', threat = ZOMBIE(3)')[:2], ('threat', 'watch'))   # LK06-T07 : membre valide, il tient
        self.assertEqual(self.decide(on + ', threat = ZOMBIE(9)')[:2], ('threat', 'watch'))
        # Loin du foyer : même état (comme « home »), le retour se fait dans Decisions.apply.
        self.assertEqual(self.decide(on + ', atHome = false')[:2], ('duty', 'chore'))
        # Corvées non chargées : comportement d'avant (au foyer).
        self.assertEqual(self.decide()[:2], ('duty', 'home'))


class ChoreStack(RoutineStack):
    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, OBJECTS)
        h.load(srv, 'FURNISH()')
        return h

    def chore_of(self, gid, mid):
        return self.run_lua(f'local m = {R}.get(MEMBER_NPC("{gid}", "{mid}")) if m == nil then return nil end '
                            'return m.chore, m.key')


class SpotSurveyTests(ChoreStack):
    mode = 'solo'

    def test_places_beside_fires_and_furniture_read_only(self):
        before = self.ev('OBJECTS_STATE()')
        out = self.run_lua(f'local s = assert({R}.surveySpots({{ x = 110, y = 110, z = 0 }})) local out = {{}} '
                           'for _, k in ipairs({ "fire", "furniture" }) do for _, p in ipairs(s[k]) do '
                           'out[#out + 1] = k .. ":" .. p.ox .. "," .. p.oy .. ">" .. p.x .. "," .. p.y .. "@" .. p.a '
                           'end end return table.concat(out, " ")')
        # Cheminée d'abord, puis cuisinière ; micro-ondes écarté ; meuble muré au nord et à l'est : place au sud,
        # regard vers le nord (270) ; caisse et réfrigérateur : place au nord, regard vers le sud (90).
        self.assertEqual(out.split(' '), ['fire:108,112>108,111@90', 'fire:106,113>106,112@90',
                                          'furniture:112,112>112,111@90', 'furniture:109,106>109,107@270',
                                          'furniture:114,114>114,113@90'])
        self.assertEqual(self.ev('OBJECTS_STATE()'), before)
        camp = self.run_lua(f'local s = {R}.surveySpots({{ x = 140, y = 140, z = 0 }}) return #s.fire, #s.furniture')
        self.assertEqual(camp, (0, 0))
        self.run_lua('UNLOADED_X = 118')
        self.assertEqual(self.run_lua(f'return {R}.surveySpots({{ x = 110, y = 110, z = 0 }})'),
                         (None, 'home area not loaded'))
        self.assertEqual(self.h.errors('solo'), [])


class SoloChoreTests(ChoreStack):
    mode = 'solo'

    def reach_chore(self, gid, mid, passes=60):
        npc = self.npc_of(gid, mid)
        for _ in range(passes):
            self.dpass(1, walk=1.0)
            if self.ev(f'(function() local m = {R}.get("{npc}") if m == nil or m.chore == nil then return false end '
                       f'local want = {R}.CHORE_GESTURE[m.chore] '
                       f'if want ~= nil then return LivingKnox.Anim.gestureOf("{npc}") == want end '
                       f'local e = LivingKnox.Directives.get("{npc}") return m.faceV ~= nil and e ~= nil '
                       'and e.v == m.faceV and e.done end)()'):
                return True
        return False

    def test_keeper_does_a_visible_chore_and_a_threat_interrupts_it(self):
        gid = self.mk()
        before = self.ev('OBJECTS_STATE()')
        self.jump_to(11)
        self.dpass(2)
        self.assertEqual(self.member(gid, 'm-2', 'duty'), 'keeper')
        self.assertEqual(self.b(gid, 'm-2'), 'chore')
        self.assertTrue(self.reach_chore(gid, 'm-2'), self.chore_of(gid, 'm-2'))
        npc = self.npc_of(gid, 'm-2')
        chore, key = self.chore_of(gid, 'm-2')
        self.assertIn(chore, CHORES)
        self.assertTrue(key.startswith('chore ' + chore), key)
        if key.count(',') == 2 and chore != 'care':                           # place : corps arrivé, regard posé
            x, y = (int(v) for v in key.split(' ')[2].split(',')[:2])
            bx, by = self.body_xy(gid, 'm-2')
            self.assertLessEqual(((bx - x - 0.5) ** 2 + (by - y - 0.5) ** 2) ** 0.5, 1.0, key)
        self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf("{npc}")'), 'rest')
        self.assertGreaterEqual(self.ev(f'{R}.stats.chores'), 1)
        self.assertEqual(self.ev('OBJECTS_STATE()'), before)                  # aucune modification d'objet
        # Menace : corvée interrompue (geste remis au repos, mémoire oubliée), fuite ; menace partie : reprise.
        x, y = self.body_xy(gid, 'm-2')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 960)')
        self.dpass(2)
        self.assertIn(self.b(gid, 'm-2'), ('flee', 'watch'))
        self.assertFalse(self.ev(f'{R}.GESTURES[LivingKnox.Anim.gestureOf("{npc}")] == true'))
        self.assertIsNone(self.ev(f'{R}.get("{npc}")'))
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)                                                    # LK05-T08 : alerte retombée d'abord
        self.dpass(2)
        self.assertEqual(self.b(gid, 'm-2'), 'chore')
        self.assertIsNotNone(self.chore_of(gid, 'm-2'))
        self.assertEqual(self.ev('OBJECTS_STATE()'), before)
        self.assertEqual(self.h.errors('solo'), [])

    def test_chores_change_with_the_slot_and_stop_at_night(self):
        gid = self.mk()
        self.jump_to(9)
        self.dpass(2)
        seen = []
        for _ in range(8):
            c = self.chore_of(gid, 'm-2')
            if c is not None:
                seen.append(c[0])
            self.h.advance(self.ev(f'{R}.CFG.CHORE_MINUTES'))
            self.dpass(2)
        self.assertGreaterEqual(len(seen), 6, seen)
        self.assertTrue(set(seen) <= set(CHORES), seen)
        self.jump_to(23)
        self.dpass(3)
        self.assertNotEqual(self.b(gid, 'm-2'), 'chore')
        self.assertIsNone(self.chore_of(gid, 'm-2') if self.b(gid, 'm-2') != 'sleep' else None)
        self.assertEqual(self.h.errors('solo'), [])

    def test_care_goes_beside_the_most_wounded_member(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        wounded = self.npc_of(gid, 'm-3')
        # Plans de corvée de m-2 sur 40 créneaux, sans puis avec un blessé (santé 30 %) : soins seulement avec lui.
        code = (f'local g = LivingKnox.Groups.get("{gid}") local m = g.members["m-2"] '
                f'local z = MAT_BODY("{gid}", "m-2") local out = {{}} '
                'for i = 0, 39 do '
                f'local ctx = {D}.context("{gid}", g, "m-2", m, z, {{}}, {D}.currentMinute() + i * 30) '
                f'local p = {R}.chorePlan(m.npc, ctx, g, g.posts) '
                'out[#out + 1] = p.chore .. "@" .. tostring(p.x) .. "," .. tostring(p.y) .. "@" .. tostring(p.a) end '
                'return table.concat(out, " ")')
        healthy = self.run_lua(code).split(' ')
        self.assertFalse(any(p.startswith('care@') for p in healthy), healthy)
        self.assertIsNotNone(wounded)
        self.update(gid, 'g.members["m-3"].wound = 70')                      # santé 30 % (Decisions.healthOf)
        hurt = self.run_lua(code).split(' ')
        care = [p for p in hurt if p.startswith('care@')]
        self.assertTrue(care, hurt)
        wx, wy = self.body_xy(gid, 'm-3')
        for p in care:
            _, xy, a = p.split('@')
            x, y = (int(v) for v in xy.split(','))
            self.assertLessEqual(max(abs(x - int(wx)), abs(y - int(wy))), 1, p)   # à côté du blessé
            ang = {(0, -1): 270, (1, 0): 0, (0, 1): 90, (-1, 0): 180}[(int(wx) - x, int(wy) - y)]
            self.assertEqual(int(a), ang, p)                                     # tourné vers lui
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerChoreTests(ChoreStack):
    """Serveur dédié + deux clients : aucune corvée chez un client ; même consigne et même geste chez les deux."""

    observed = None

    def view(self, gid):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        for c in ('A', 'B'):
            rows = []
            for m in ('m-1', 'm-2', 'm-3'):
                npc = self.npc_of(gid, m)
                rows.append(self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                           'local d = e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. "@" '
                                           '.. tostring(e.a) .. ":" .. tostring(e.v)) or "none" '
                                           f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") end)()'))
            out[c] = rows
        return out

    def scenario(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Routines'))
        self.jump_to(11)
        out = []
        for _ in range(4):
            self.dpass(4)
            v = self.view(gid)
            self.assertEqual(v['A'], v['B'])
            out.append(v['A'])
            out.append(self.chore_of(gid, 'm-2'))
            self.h.advance(self.ev(f'{R}.CFG.CHORE_MINUTES'))
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])
        return out

    def test_two_observers_same_chores_and_same_world_twice(self):
        first = self.scenario()
        self.assertTrue(any(isinstance(x, tuple) and x[0] in CHORES for x in first), first)
        self.h.close()
        self.h = self.make()
        self.init()
        self.away()
        second = self.scenario()
        self.assertEqual(first, second)


SUITE = 'shared/RST/suites/RST_LKChores.lua'
SUITE_FILE = Path(__file__).resolve().parents[1] / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE


class SuiteTests(ChoreStack):
    mode = 'solo'

    def test_suite_lk_chores_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.chores", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.chores')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.chores", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(6000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKC' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKC] measure places: 2 fire(s), 3 furniture', '[LKC] measure chore: ',
                     '[LKC] measure threat: ', '[LKC] measure resumed: ', '[LKC] measure objects after: '):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        import re
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main(verbosity=1)
