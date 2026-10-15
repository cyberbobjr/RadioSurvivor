"""Tests hors jeu de l'attitude d'un groupe envers un joueur (LK11-T03) : LK_Hostility.lua (autorité).

    python RadioSurvivor/tests/test_lk_hostility.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Doublures : getFileWriter / getFileReader du banc,
getWorld (mode et nom de la partie), horloge du banc (getWorldAgeHours). Elles NE PROUVENT PAS l'API réelle,
seulement la logique du mod : deux joueurs, attitudes distinctes, niveaux, tendance sur trois faits, témoins, bornes,
déclin, persistance à deux emplacements et contrôle au chargement.
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402

HOSTILITY_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Hostility.lua'
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'

WORLD = r'''
getWorld = function()
    return { getWorld = function() return 'rstest_attitude' end, getGameMode = function() return 'Multiplayer' end }
end
'''

H = 'LivingKnox.Hostility'
# Clés de joueur : identités de personnage du carnet (forme de RS_State.uid).
P1, P2 = 'character-1700000000000-1-123456', 'character-1700000000000-2-654321'
SEEN = '{ witnessed = true }'


# LK13-T09 : les passes horaires partent une par image (LK_Simulation.defer) ; ce banc les vide aussitôt.
FINISH_HOUR = 'if LivingKnox.Simulation and LivingKnox.Simulation.finishHour then LivingKnox.Simulation.finishHour() end'

class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = self.make()

    def tearDown(self):
        self.h.close()

    def make(self, root=None):
        h = Harness(mode=self.mode, root=root)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            h.load(m, WORLD)
            for path in SHARED:
                h.load(m, path)
            h.load(m, SERVER)
        return h

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def init(self, new_world=False):
        self.h.fire(self.srv, 'OnInitGlobalModData', new_world)

    def groups(self):
        a = self.ev('LivingKnox.Groups.create({ type = "settlers", name = "Mill Folk", day = 1 }).id')
        b = self.ev('LivingKnox.Groups.create({ type = "raiders", name = "Crows", day = 1 }).id')
        c = self.ev('LivingKnox.Groups.create({ type = "neutrals", name = "Traders", day = 1 }).id')
        return a, b, c

    def record(self, gid, key, fact, opts=SEEN):
        """Résultats de record en tuple : (vue,) ou (None, raison)."""
        res = self.run_lua(f'return {H}.record("{gid}", "{key}", "{fact}", {opts})')
        return res if isinstance(res, tuple) else (res,)

    def get(self, gid, key):
        a = self.ev(f'{H}.get("{gid}", "{key}")')
        return (a.level, a.trend)

    def value(self, gid, key):
        return self.ev(f'{H}.debugPair("{gid}", "{key}").value')

    def file(self, slot):
        return self.h.machine(self.srv).files / self.ev(f'{H}.slotPath({slot})')

    def restart(self):
        self.h.load(self.srv, 'if LivingKnox.Groups and LivingKnox.Groups.flush then LivingKnox.Groups.flush() end')  # arrêt propre : écriture différée faite (LK13-T06)
        root = self.h.root
        self.h._tmp = None  # le dossier de fichiers survit au « redémarrage »
        self.h.close()
        self.h = self.make(root=root)
        self.addCleanup(shutil.rmtree, root, True)

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]


class LevelTests(Base):
    def test_start_levels_by_group_type(self):
        self.init()
        a, b, c = self.groups()
        self.assertEqual(self.get(a, P1), ('favorable', 'stable'))
        self.assertEqual(self.get(b, P1), ('hostile', 'stable'))
        self.assertEqual(self.get(c, P1), ('cautious', 'stable'))
        self.assertEqual([self.ev(f'{H}.startFor("{t}")') for t in ('settlers', 'neutrals', 'raiders')], [50, 6, -50])
        # Lecture sans fait : rien n'est créé.
        self.assertIsNone(self.ev(f'{H}.debugPair("{a}", "{P1}")'))

    def test_level_thresholds(self):
        self.init()
        cases = {-100: 'hostile', -45: 'hostile', -44: 'wary', -15: 'wary', -14: 'cautious', 14: 'cautious',
                 15: 'favorable', 59: 'favorable', 60: 'trusting', 100: 'trusting'}
        for v, level in cases.items():
            self.assertEqual(self.ev(f'{H}.levelOf({v})'), level, v)
        self.assertEqual(list(self.ev(f'{H}.LEVELS').values()),
                         ['hostile', 'wary', 'cautious', 'favorable', 'trusting'])
        # Seuils de configuration non croissants : seuils de repli.
        self.run_lua('LivingKnox.Config.ATTITUDE.LEVEL_MIN = { wary = 10, cautious = 5, favorable = 15, trusting = 60 }')
        self.assertEqual(self.ev(f'{H}.levelOf(-20)'), 'wary')
        self.run_lua('LivingKnox.Config.ATTITUDE.LEVEL_MIN = { wary = -80, cautious = -50, favorable = 0, trusting = 30 }')
        self.assertEqual(self.ev(f'{H}.levelOf(-20)'), 'cautious')


class FactTests(Base):
    def test_two_players_differ_with_the_same_group(self):
        """Critère d'acceptation : deux joueurs, attitudes différentes envers le même groupe."""
        self.init()
        a, _, _ = self.groups()
        for fact in ('shot', 'theft', 'hit'):
            self.assertIsNotNone(self.record(a, P1, fact)[0], fact)
        for fact in ('gift', 'heal'):
            self.assertIsNotNone(self.record(a, P2, fact)[0], fact)
        self.assertEqual(self.get(a, P1), ('cautious', 'down'))   # 50 - 25 - 20 - 15 = -10
        self.assertEqual(self.value(a, P1), -10)
        self.assertEqual(self.get(a, P2), ('trusting', 'up'))     # 50 + 8 + 12 = 70
        self.assertEqual(self.value(a, P2), 70)
        rows = [(r.player, r.level, r.trend) for r in self.ev(f'{H}.forGroup("{a}")').values()]
        self.assertEqual(rows, [(P1, 'cautious', 'down'), (P2, 'trusting', 'up')])
        # La sortie ne contient aucune valeur numérique.
        self.assertIsNone(self.ev(f'{H}.get("{a}", "{P1}").value'))
        self.assertIsNone(self.ev(f'{H}.forGroup("{a}")[1].value'))
        self.assertEqual(self.h.errors(self.srv), [])

    def test_only_the_aggressor_is_targeted(self):
        self.init()
        a, b, _ = self.groups()
        self.record(a, P1, 'kill')
        self.assertEqual(self.get(a, P2), ('favorable', 'stable'))   # l'équipier n'est pas visé
        self.assertEqual(self.get(b, P1), ('hostile', 'stable'))     # ni un autre groupe
        self.assertIsNone(self.ev(f'{H}.debugPair("{a}", "{P2}")'))
        self.assertTrue(self.ev(f'{H}.debugPair("{a}", "{P1}").murder'))

    def test_witness_or_attribution_required(self):
        self.init()
        a, _, _ = self.groups()
        for opts in ('nil', '{}', '{ witnessed = false }', '{ witnessed = 1 }'):
            self.assertEqual(self.record(a, P1, 'hit', opts), (None, 'fact neither witnessed nor attributable'), opts)
        self.assertIsNone(self.ev(f'{H}.debugPair("{a}", "{P1}")'))
        self.assertEqual(self.record(a, P1, 'hit', '{ attributable = true }')[0].level, 'favorable')
        self.assertEqual(self.value(a, P1), 35)

    def test_witnessed_assault_is_published_with_its_witnesses(self):
        """E08-T07 : hit, shot ou kill vus = fait assaultSeen (témoins nommés par l'appelant, lieu facultatif)."""
        self.init()
        a, _, _ = self.groups()
        self.run_lua('PUB = {}; LivingKnox.listen("assaultSeen", "test", function(i) PUB[#PUB + 1] = i end)')
        self.record(a, P1, 'shot', '{ witnessed = true, day = 4, witnesses = { "lk-1", 7, "lk-2" }, x = 10.5, y = 20 }')
        self.record(a, P1, 'hit', '{ attributable = true, witnesses = { "lk-1" } }')   # attribuable, pas vu
        self.record(a, P1, 'gift', '{ witnessed = true, witnesses = { "lk-1" } }')     # pas une agression
        self.record(a, P1, 'kill', '{ witnessed = true, day = 5 }')                    # vu, aucun témoin nommé
        self.assertEqual(self.ev('#PUB'), 2)
        shot, kill = self.ev('PUB[1]'), self.ev('PUB[2]')
        self.assertEqual((shot.group, shot.player, shot.fact, shot.day, shot.x, shot.y), (a, P1, 'shot', 4, 10.5, 20))
        self.assertEqual(list(shot.witnesses.values()), ['lk-1', 'lk-2'])
        self.assertEqual((kill.fact, kill.day, kill.x, list(kill.witnesses.values())), ('kill', 5, None, []))
        # Groupe inconnu : rien n'est enregistré ni publié.
        self.record('grp-9', P1, 'hit', '{ witnessed = true, witnesses = { "lk-1" } }')
        self.assertEqual(self.ev('#PUB'), 2)

    def test_trend_uses_the_last_three_facts(self):
        self.init()
        _, _, c = self.groups()
        self.record(c, P1, 'gift')
        self.assertEqual(self.get(c, P1)[1], 'up')
        self.record(c, P1, 'hit')
        self.assertEqual(self.get(c, P1)[1], 'stable')   # +1 -1
        self.record(c, P1, 'theft')
        self.assertEqual(self.get(c, P1)[1], 'down')     # +1 -1 -1
        self.record(c, P1, 'delivery')
        self.record(c, P1, 'mission_success')
        self.assertEqual(self.get(c, P1)[1], 'up')       # -1 +1 +1 (le don initial est sorti de la fenêtre)
        facts = [f.fact for f in self.ev(f'{H}.debugPair("{c}", "{P1}").facts').values()]
        self.assertEqual(facts, ['theft', 'delivery', 'mission_success'])

    def test_value_and_effects_are_bounded(self):
        self.init()
        a, b, _ = self.groups()
        for _ in range(10):
            self.record(a, P1, 'heal')
        self.assertEqual(self.value(a, P1), 100)
        self.assertEqual(self.get(a, P1), ('trusting', 'up'))
        for _ in range(5):
            self.record(b, P1, 'kill')
        self.assertEqual(self.value(b, P1), -100)
        self.run_lua('LivingKnox.Config.ATTITUDE.EFFECTS.gift = 999')
        self.assertEqual(self.ev(f'{H}.effect("gift")'), 60)
        self.run_lua('LivingKnox.Config.ATTITUDE.EFFECTS.gift = "x"')
        self.assertEqual(self.ev(f'{H}.effect("gift")'), 8)

    def test_refusals(self):
        self.init()
        a, _, _ = self.groups()
        cases = {
            f'{H}.record("{a}", "{P1}", "hug", {SEEN})': 'unknown fact hug',
            f'{H}.record("{a}", "bad key!", "hit", {SEEN})': 'bad player key',
            f'{H}.record("{a}", "{"x" * 97}", "hit", {SEEN})': 'bad player key',
            f'{H}.record("{a}", "{P1}", "hit", {{ witnessed = true, day = -1 }})': 'bad day',
            f'{H}.record("grp-9", "{P1}", "hit", {SEEN})': 'unknown group grp-9',
            f'{H}.get("grp-9", "{P1}")': 'unknown group grp-9',
            f'{H}.get("{a}", 12)': 'bad player key',
            f'{H}.forGroup("grp-9")': 'unknown group grp-9',
        }
        for call, why in cases.items():
            self.assertEqual(self.run_lua(f'return {call}'), (None, why), call)
        self.run_lua(f'{H}.state.blocked = true')
        self.assertEqual(self.record(a, P1, 'hit'), (None, 'attitude registry not ready'))

    def test_players_per_group_are_bounded(self):
        self.init()
        a, _, _ = self.groups()
        limit = self.ev(f'{H}.MAX_PLAYERS')
        self.record(a, 'p-0', 'kill', '{ witnessed = true, day = 1 }')   # meurtre : gardé en mémoire
        self.run_lua(f'for i = 1, {limit - 1} do assert({H}.record("{a}", "p-" .. i, "gift", '
                     '{ witnessed = true, day = 1 + i })) end')
        self.assertEqual(self.ev(f'#{H}.forGroup("{a}")'), limit)
        self.record(a, 'p-new', 'gift', '{ witnessed = true, day = 500 }')
        keys = [r.player for r in self.ev(f'{H}.forGroup("{a}")').values()]
        self.assertEqual(len(keys), limit)
        self.assertIn('p-0', keys)        # le meurtre n'est pas oublié
        self.assertNotIn('p-1', keys)     # la plus ancienne sans meurtre l'est
        self.assertIn('p-new', keys)


class DecayTests(Base):
    def test_slow_return_to_start(self):
        self.init()
        a, b, _ = self.groups()
        self.record(a, P1, 'shot', '{ witnessed = true, day = 1 }')      # 25
        self.record(b, P1, 'gift', '{ witnessed = true, day = 1 }')      # -42
        self.assertEqual(self.ev(f'{H}.decay(4)'), 2)
        self.assertEqual((self.value(a, P1), self.value(b, P1)), (31, -48))
        self.assertEqual(self.ev(f'{H}.decay(4)'), 0)                    # même jour : rien
        self.assertEqual(self.ev(f'{H}.decay(100)'), 2)                  # 30 jours au plus, sans dépasser la cible
        self.assertEqual((self.value(a, P1), self.value(b, P1)), (50, -50))
        self.assertEqual(self.get(a, P1)[1], 'down')                     # le déclin n'est pas un fait

    def test_murder_caps_the_decay(self):
        self.init()
        a, _, _ = self.groups()
        self.record(a, P1, 'kill', '{ witnessed = true, day = 1 }')      # 50 - 60 = -10
        self.ev(f'{H}.decay(200)')
        self.assertEqual(self.value(a, P1), -15)                         # vers min(départ 50, plafond -15)
        self.assertEqual(self.get(a, P1)[0], 'wary')
        # Les actes peuvent encore améliorer l'attitude ; le déclin la ramène au plafond.
        for _ in range(4):
            self.record(a, P1, 'mission_success', '{ witnessed = true, day = 200 }')
        self.assertEqual(self.value(a, P1), 45)
        self.ev(f'{H}.decay(400)')
        self.assertEqual(self.value(a, P1), -15)

    def test_hourly_decay_and_orphans(self):
        self.init()
        a, b, _ = self.groups()
        self.record(a, P1, 'theft', '{ witnessed = true, day = 1 }')     # 30
        self.record(b, P1, 'theft', '{ witnessed = true, day = 1 }')
        self.run_lua('HARNESS.clock.ageHours = 24 * 5 + 1')               # jour 6
        self.run_lua(f'LivingKnox.Groups.remove("{b}")')
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.value(a, P1), 40)
        self.assertIsNone(self.ev(f'{H}.state.data.groups["{b}"]'))       # groupe disparu : attitudes retirées
        self.assertEqual(self.ev(f'{H}.state.data.decayDay'), 6)
        self.assertEqual(self.h.errors(self.srv), [])


class PersistenceTests(Base):
    def test_survives_restart_with_alternating_slots(self):
        self.init()
        a, _, _ = self.groups()
        self.record(a, P1, 'hit', '{ witnessed = true, day = 2 }')
        self.record(a, P2, 'gift', '{ witnessed = true, day = 2 }')
        seq = self.ev(f'{H}.state.seq')
        self.assertTrue(self.file(seq % 2).is_file())
        self.assertTrue(self.file((seq - 1) % 2).is_file())
        self.assertTrue(self.file(0).read_text(encoding='utf-8').startswith('LKATT1='))
        self.restart()
        self.init()
        self.assertEqual(self.get(a, P1), ('favorable', 'down'))
        self.assertEqual(self.get(a, P2), ('favorable', 'up'))
        self.assertEqual((self.value(a, P1), self.value(a, P2)), (35, 58))
        self.assertEqual(self.ev(f'{H}.state.seq'), seq)

    def test_new_world_starts_empty_and_newer_slot_wins(self):
        self.init()
        a, _, _ = self.groups()
        self.record(a, P1, 'kill')
        seq = self.ev(f'{H}.state.seq')
        self.init(new_world=True)
        self.assertEqual(self.ev(f'{H}.state.seq'), seq + 1)
        self.restart()
        self.init()
        self.assertIsNone(self.ev(f'{H}.debugPair("{a}", "{P1}")'))

    def test_unknown_schema_blocks(self):
        self.init()
        self.run_lua(f'return LivingKnox.Store.writeSlotFile({H}.slotPath(1), "LKATT1", 99, '
                     '{ schema = 2, groups = {} })')
        self.restart()
        self.init()
        self.assertTrue(self.ev(f'{H}.isBlocked()'))
        self.assertIn('unknown attitude schema 2', self.ev(f'{H}.state.reason'))
        self.assertTrue(any('attitude registry BLOCKED' in line for line in self.lk()))
        before = self.file(1).read_text(encoding='utf-8')
        a = self.ev('LivingKnox.Groups.create({ type = "settlers", name = "S" }).id')
        self.assertEqual(self.record(a, P1, 'hit'), (None, 'attitude registry not ready'))
        self.assertEqual(self.file(1).read_text(encoding='utf-8'), before)

    def test_invalid_pairs_are_dropped(self):
        self.init()
        a, _, _ = self.groups()
        self.record(a, P1, 'hit')
        self.record(a, P2, 'gift')
        self.run_lua(f'''
            local d = LivingKnox.Groups.copy({H}.state.data)
            d.groups["{a}"]["{P2}"].value = 400
            d.groups["{a}"]["bad key!"] = LivingKnox.Groups.copy(d.groups["{a}"]["{P1}"])
            d.groups["oops"] = {{}}
            assert(LivingKnox.Store.writeSlotFile({H}.slotPath(0), "LKATT1", 50, d))
        ''')
        self.restart()
        self.init()
        self.assertTrue(self.ev(f'{H}.isReady()'))
        self.assertEqual(self.ev(f'{H}.state.dropped'), 3)
        self.assertEqual(self.value(a, P1), 35)
        self.assertIsNone(self.ev(f'{H}.debugPair("{a}", "{P2}")'))
        dropped = [line for line in self.lk() if 'dropped at load' in line]
        self.assertEqual(len(dropped), 3)
        self.assertTrue(any('bad value' in line for line in dropped))


class ReputationWelcomeTests(Base):
    """E04-T11 (Q14) : premier contact d'un groupe inconnu un cran mieux ou moins bien selon la réputation interne du
    personnage (crochet LivingKnox.Hooks.reputation), ensuite seuls les faits envers ce groupe comptent."""

    def hook(self, levels):
        table = ', '.join(f'["{k}"] = "{v}"' for k, v in levels.items())
        self.run_lua('REP_LEVELS = { ' + table + ' }; LivingKnox.Hooks = LivingKnox.Hooks or {}; '
                     'LivingKnox.Hooks.reputation = function(key) return REP_LEVELS[key] end')

    def test_one_step_better_or_worse_at_first_contact_only(self):
        self.init()
        a, b, c = self.groups()   # settlers favorable (50), raiders hostile (-50), neutrals cautious (6)
        self.hook({P1: 'good', P2: 'bad'})
        self.assertEqual(self.get(c, P1), ('favorable', 'stable'))
        self.assertEqual(self.get(c, P2), ('wary', 'stable'))
        self.assertEqual(self.get(a, P1), ('trusting', 'stable'))
        self.assertEqual(self.get(a, P2), ('cautious', 'stable'))
        self.assertEqual(self.get(b, P1), ('wary', 'stable'))
        self.assertEqual(self.get(b, P2), ('hostile', 'stable'), 'already the lowest level')
        self.assertEqual(self.ev(f'{H}.startForPlayer("neutrals", "{P1}")'), 15)
        self.assertEqual(self.ev(f'{H}.startForPlayer("neutrals", "{P2}")'), -15)
        self.assertEqual(self.ev(f'{H}.startForPlayer("settlers", "{P1}")'), 60)
        # First fact: the pair keeps the shifted start; a later change of reputation no longer moves it.
        self.record(c, P1, 'gift')
        start = self.ev(f'{H}.debugPair("{c}", "{P1}").start')
        self.assertEqual(start, 15)
        self.hook({P1: 'bad'})
        self.assertEqual(self.ev(f'{H}.debugPair("{c}", "{P1}").start'), 15)
        self.assertEqual(self.get(c, P1)[0], 'favorable')

    def test_neutral_unknown_or_failing_hook_changes_nothing(self):
        self.init()
        _, _, c = self.groups()
        self.hook({P1: 'neutral', P2: 'excellent'})
        self.assertEqual(self.get(c, P1), ('cautious', 'stable'))
        self.assertEqual(self.get(c, P2), ('cautious', 'stable'))
        self.run_lua('LivingKnox.Hooks.reputation = function() error("boom") end')
        self.assertEqual(self.get(c, P1), ('cautious', 'stable'))
        self.assertEqual(self.ev(f'{H}.hookStats.reputationErrors'), 1)
        self.run_lua('LivingKnox.Hooks.reputation = nil')
        self.assertEqual(self.ev(f'{H}.startForPlayer("neutrals", "{P1}")'), 6)


class SideTests(Base):
    def test_no_module_on_mp_clients(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Hostility'))
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Hostility'))

    def test_key_of_player_uses_the_notebook_identity(self):
        self.init()
        self.run_lua(f'RS_CarnetServer = {{ bound = {{ [HARNESS.players.A] = "{P1}" }} }}')
        self.assertEqual(self.ev(f'{H}.keyOf(HARNESS.players.A)'), P1)
        self.assertEqual(self.run_lua(f'return {H}.keyOf(HARNESS.players.B)'), (None, 'no notebook character bound'))
        self.run_lua('RS_CarnetServer = nil')
        self.assertEqual(self.run_lua(f'return {H}.keyOf(HARNESS.players.A)'), (None, 'no notebook character bound'))


class SoloTests(Base):
    mode = 'solo'

    def test_solo(self):
        self.init()
        a, _, _ = self.groups()
        self.record(a, P1, 'shot')
        self.assertEqual(self.get(a, P1), ('favorable', 'down'))
        self.assertEqual(self.get(a, P2), ('favorable', 'stable'))


LEVEL_VALUES = {'hostile': -80, 'wary': -30, 'cautious': 0, 'favorable': 30, 'trusting': 80}


class TargetTests(Base):
    """LK06-T01 : choix de cible fondé sur l'attitude, crochets covered / incident, décision identique pour tous."""

    def setUp(self):
        super().setUp()
        self.init()
        self.settlers, self.raiders, self.neutrals = self.groups()

    def choose(self, gid, cands, day, npc='lk-1'):
        """cands = [(compte, clé ou None, distance)] -> [(compte, action, raison)] et cible (compte ou None)."""
        rows = ', '.join(f'{{ u = "{u}", key = {f"{k!r}".replace(chr(39), chr(34)) if k else "nil"}, d = {d} }}'
                         for u, k, d in cands)
        res = self.ev(f'{H}.chooseTarget("{gid}", "{npc}", {{ {rows} }}, {day})')
        lst = [(r.u, r.action, r.reason) for r in res.list.values()]
        return lst, (res.target.u if res.target else None)

    def set_value(self, gid, key, value, day=1):
        """Paire posée à une valeur sans fait d'agression (faits neutres de mission)."""
        self.record(gid, key, 'mission_success', f'{{ witnessed = true, day = {day} }}')
        self.run_lua(f'local p = {H}.state.data.groups["{gid}"]["{key}"]; p.value = {value}; '
                     'p.facts = { { fact = "mission_failure", sign = -1, day = ' + str(day) + ' } }')

    def test_rule_never_attacks_without_provocation_unless_first_strike(self):
        """Table de vérité complète de la règle pure : sans incident ni provocation, attaque seulement si le type
        tire le premier ET le niveau est hostile."""
        for level in LEVEL_VALUES:
            for covered in ('true', 'false'):
                for first in ('true', 'false'):
                    action, reason = self.run_lua(
                        f'return {H}.targetRule({{ level = "{level}", covered = {covered}, incident = false, '
                        f'provoked = false, firstStrike = {first} }})')
                    expect_attack = first == 'true' and covered == 'false' and level == 'hostile'
                    self.assertEqual(action == 'attack', expect_attack, (level, covered, first))
                    if covered == 'true':
                        self.assertEqual((action, reason), (None, 'covered'))
        self.assertEqual(self.run_lua(f'return {H}.targetRule({{ level = "trusting", covered = true, incident = true }})'),
                         ('attack', 'incident'))
        self.assertEqual(self.run_lua(f'return {H}.targetRule({{ level = "trusting", provoked = true }})'),
                         ('attack', 'provoked'))

    def test_neutral_group_never_fires_without_provocation(self):
        """Critère d'acceptation : colons et neutres, tous niveaux, faits non agressifs ou agression ancienne :
        aucune attaque ; avertissement pour méfiant et hostile."""
        self.assertFalse(self.ev(f'{H}.firstStrike("neutrals")'))
        self.assertFalse(self.ev(f'{H}.firstStrike("settlers")'))
        self.assertTrue(self.ev(f'{H}.firstStrike("raiders")'))
        for gid in (self.settlers, self.neutrals):
            for i, (level, value) in enumerate(LEVEL_VALUES.items()):
                key = f'character-1-{i}-9'
                self.set_value(gid, key, value)
                self.assertEqual(self.get(gid, key)[0], level)
                lst, _ = self.choose(gid, [('U', key, 3)], 2)
                expect = [('U', 'warn', level)] if level in ('hostile', 'wary') else []
                self.assertEqual(lst, expect, (gid, level))
            # Vol (pas une agression) jusqu'au niveau hostile : avertissement, jamais d'attaque.
            for _ in range(5):
                self.record(gid, P1, 'theft', '{ witnessed = true, day = 2 }')
            self.assertEqual(self.get(gid, P1)[0], 'hostile')
            self.assertEqual(self.choose(gid, [('U', P1, 3)], 2)[0], [('U', 'warn', 'hostile')])
            # Joueur sans identité de personnage : niveau de départ, aucune attaque.
            self.assertEqual(self.choose(gid, [('X', None, 1)], 2)[0], [])

    def test_provocation_window(self):
        self.record(self.neutrals, P1, 'hit', '{ witnessed = true, day = 3 }')
        self.assertEqual(self.choose(self.neutrals, [('U', P1, 3)], 3)[0], [('U', 'attack', 'provoked')])
        self.assertEqual(self.choose(self.neutrals, [('U', P1, 3)], 4)[0], [('U', 'attack', 'provoked')])
        # Au-delà de PROVOKE_DAYS : plus de provocation ; niveau -9 (prudent) : rien.
        self.assertEqual(self.choose(self.neutrals, [('U', P1, 3)], 5)[0], [])
        self.assertTrue(self.ev(f'{H}.provoked("{self.neutrals}", "{P1}", 4)'))
        self.assertFalse(self.ev(f'{H}.provoked("{self.neutrals}", "{P1}", 2)'))   # fait postérieur au jour
        # Agression attribuable (non vue) : provocation aussi ; seul l'agresseur est visé.
        self.record(self.settlers, P1, 'shot', '{ attributable = true, day = 6 }')
        lst, target = self.choose(self.settlers, [('U', P1, 9), ('V', P2, 1)], 6)
        self.assertEqual((lst, target), ([('U', 'attack', 'provoked')], 'U'))
        # Des actes positifs ensuite font sortir l'agression des trois derniers faits : plus de provocation.
        for fact in ('gift', 'heal', 'delivery'):
            self.record(self.settlers, P1, fact, '{ witnessed = true, day = 6 }')
        self.assertEqual(self.choose(self.settlers, [('U', P1, 9)], 6)[0], [])

    def test_first_strike_group_attacks_hostile_players(self):
        lst, target = self.choose(self.raiders, [('U', P1, 8), ('V', None, 4)], 2)
        self.assertEqual(lst, [('V', 'attack', 'hostile'), ('U', 'attack', 'hostile')])
        self.assertEqual(target, 'V')
        # Un pillard méfiant (actes positifs) avertit seulement.
        self.set_value(self.raiders, P2, -30)
        self.assertEqual(self.choose(self.raiders, [('W', P2, 1)], 2)[0], [('W', 'warn', 'wary')])

    def test_covered_hook(self):
        """Crochet covered : couvert = jamais une cible ; absent = personne couvert ; erreur = couvert (prudence)."""
        self.assertEqual(self.choose(self.raiders, [('U', P1, 2)], 2)[0], [('U', 'attack', 'hostile')])
        self.run_lua('LK_SEEN = {}; LivingKnox.Hooks = { covered = function(gid, key, npc) '
                     'LK_SEEN[#LK_SEEN + 1] = gid .. "|" .. key .. "|" .. tostring(npc); return key == "' + P1 + '" end }')
        lst, target = self.choose(self.raiders, [('U', P1, 2), ('V', P2, 5)], 2, npc='lk-7')
        self.assertEqual((lst, target), ([('V', 'attack', 'hostile')], 'V'))
        self.assertIn(f'{self.raiders}|{P1}|lk-7', list(self.ev('LK_SEEN').values()))
        # Valeur non booléenne : non couvert.
        self.run_lua('LivingKnox.Hooks.covered = function() return 1 end')
        self.assertEqual(self.choose(self.raiders, [('U', P1, 2)], 2)[1], 'U')
        # Erreur : couvert, journalisée et comptée, sans erreur Lua remontée.
        self.run_lua('LivingKnox.Hooks.covered = function() error("boom") end')
        self.assertEqual(self.choose(self.raiders, [('U', P1, 2)], 2), ([], None))
        self.assertEqual(self.ev(f'{H}.hookStats.coveredErrors'), 1)
        self.assertTrue(any('hook covered failed' in line for line in self.lk()))
        # Joueur sans clé : le crochet n'est pas appelé, il ne peut pas être couvert.
        self.assertEqual(self.choose(self.raiders, [('X', None, 2)], 2)[1], 'X')

    def test_incident_author_loses_cover(self):
        """Auteur d'un incident ouvert (E09-T06) : cible même couvert, même pour un groupe neutre ; les autres
        joueurs couverts restent protégés."""
        self.run_lua('LivingKnox.Hooks = { covered = function() return true end, '
                     'incident = function(gid, key) return key == "' + P1 + '" end }')
        lst, target = self.choose(self.neutrals, [('V', P2, 1), ('U', P1, 6)], 2)
        self.assertEqual((lst, target), ([('U', 'attack', 'incident')], 'U'))
        self.run_lua('LivingKnox.Hooks.incident = function() error("boom") end')
        self.assertEqual(self.choose(self.neutrals, [('U', P1, 6)], 2), ([], None))
        self.assertEqual(self.ev(f'{H}.hookStats.incidentErrors'), 1)

    def test_decision_is_deterministic_and_ordered(self):
        """Même entrée dans n'importe quel ordre -> même liste ; attaque avant avertissement, puis raison, distance,
        compte ; un compte en double n'est compté qu'une fois."""
        self.record(self.neutrals, P1, 'shot', '{ witnessed = true, day = 2 }')
        self.set_value(self.neutrals, P2, -80)
        k3 = 'character-1-3-3'
        self.set_value(self.neutrals, k3, -30)
        cands = [('U', P1, 9), ('V', P2, 2), ('W', k3, 1), ('Z', None, 0.5)]
        ref = self.choose(self.neutrals, cands, 2)
        self.assertEqual(ref, ([('U', 'attack', 'provoked'), ('V', 'warn', 'hostile'), ('W', 'warn', 'wary')], 'U'))
        for order in ([3, 2, 1, 0], [1, 3, 0, 2], [2, 0, 3, 1]):
            self.assertEqual(self.choose(self.neutrals, [cands[i] for i in order], 2), ref)
        self.assertEqual(self.choose(self.neutrals, cands + [('U', P1, 0.1)], 2), ref)
        # Lecture seule : aucune paire créée pour un candidat inconnu.
        self.assertIsNone(self.ev(f'{H}.debugPair("{self.neutrals}", "character-9-9-9")'))
        self.choose(self.neutrals, [('Q', 'character-9-9-9', 1)], 2)
        self.assertIsNone(self.ev(f'{H}.debugPair("{self.neutrals}", "character-9-9-9")'))

    def test_refusals(self):
        self.assertEqual(self.run_lua(f'return {H}.chooseTarget("grp-999", "lk-1", {{}}, 2)'),
                         (None, 'unknown group grp-999'))
        self.assertEqual(self.run_lua(f'return {H}.chooseTarget("{self.raiders}", "lk-1", {{}}, -1)'),
                         (None, 'bad day'))
        res = self.ev(f'{H}.chooseTarget("{self.raiders}", "lk-1", {{ 1, {{ d = 2 }}, {{ u = 5 }} }}, 2)')
        self.assertIsNone(res.target)

    def test_candidates_of_perception(self):
        """Joueurs VUS seulement, vivants, connus du serveur, avec la clé du carnet ; perception périmée : aucun."""
        self.run_lua(f'RS_CarnetServer = {{ bound = {{ [HARNESS.players.A] = "{P1}" }} }}')
        per = ('{ stale = false, p = { { u = "A", s = true, d = 4 }, { u = "B", s = true, d = 2 }, '
               '{ u = "C", s = true, d = 1 }, { u = "B", h = true, d = 2 } } }')
        rows = self.ev(f'{H}.candidatesOf({per}, {{ HARNESS.players.A, HARNESS.players.B }})')
        self.assertEqual([(r.u, r.key, r.d) for r in rows.values()], [('A', P1, 4), ('B', None, 2)])
        heard = '{ p = { { u = "A", h = true, d = 4 } } }'
        self.assertEqual(len(self.ev(f'{H}.candidatesOf({heard}, {{ HARNESS.players.A }})')), 0)
        stale = '{ stale = true, p = { { u = "A", s = true, d = 4 } } }'
        self.assertEqual(len(self.ev(f'{H}.candidatesOf({stale}, {{ HARNESS.players.A }})')), 0)
        self.run_lua('HARNESS.players.A.dead = true')
        self.assertEqual(len(self.ev(f'{H}.candidatesOf({per}, {{ HARNESS.players.A }})')), 0)
        # Bout à bout : perception -> candidats -> choix (pillards : A visé).
        self.run_lua('HARNESS.players.A.dead = false')
        res = self.ev(f'{H}.chooseTarget("{self.raiders}", "lk-1", '
                      f'{H}.candidatesOf({per}, {{ HARNESS.players.A }}), 2)')
        self.assertEqual((res.target.u, res.target.action), ('A', 'attack'))


class SoloTargetTests(TargetTests):
    """Même décision en solo que sur le serveur dédié."""
    mode = 'solo'

    def test_candidates_of_perception(self):
        self.skipTest('joueurs A et B du banc MP')


class SourceTests(unittest.TestCase):
    def test_source_is_kahlua_safe(self):
        src = HOSTILITY_FILE.read_text(encoding='utf-8')
        code = '\n'.join(re.sub(r'--.*$', '', line) for line in src.splitlines())
        self.assertTrue(code.isascii())
        self.assertTrue(src.splitlines()[next(i for i, l in enumerate(src.splitlines()) if 'isClient' in l)]
                        .startswith('if isClient() then return end'))
        for word in (r'\bnext\s*\(', r'\bgoto\b', r'coroutine', r'ModData', r'[&|~]\s*\d', r'<<|>>'):
            self.assertIsNone(re.search(word, code), word)
        # Tout message de journal en anglais ASCII.
        for msg in re.findall(r'log\(\)\.\w+\("([^"]*)"', code):
            self.assertTrue(msg.isascii(), msg)


if __name__ == '__main__':
    unittest.main()
