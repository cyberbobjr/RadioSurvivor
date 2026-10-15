"""Tests hors jeu de la simulation abstraite hors écran (LK09-T01), des expéditions (LK09-T02) et des événements de groupe (LK09-T05) : LK_Simulation.lua.

    python RadioSurvivor/tests/test_lk_simulation.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Doublures : getWorld (mode et nom de la partie),
getGameTime():getWorldAgeHours() de l'horloge du banc (0 à 7 h le premier jour), fichiers getFileWriter /
getFileReader du banc. EveryHours est déclenché par le test (le banc n'émule pas GameTime.update) : il NE PROUVE PAS
l'accroche réelle, seulement la logique du mod (heures simulées, rattrapage, tirages, persistance).
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SIM_FILE = (ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / 'server' / 'LivingKnox'
            / 'LK_Simulation.lua')
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'

WORLD = r'''
WORLD_NAME, GAME_MODE = 'rstest_simulation', 'Multiplayer'
getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end }
end
'''

CANON = ('require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes('
         'LivingKnox.Groups.state.data))')
SIM = 'LivingKnox.Simulation'
G = 'LivingKnox.Groups'


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

    def ev(self, code):
        return self.h.eval(self.srv, code)

    def run_lua(self, code):
        return self.h.load(self.srv, code)

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]

    def hour(self):
        return self.ev(f'{SIM}.currentHour()')

    def restart(self):
        """Arrêt puis redémarrage : fichiers et âge du monde conservés, état Lua perdu."""
        self.h.load(self.srv, 'if LivingKnox.Groups and LivingKnox.Groups.flush then LivingKnox.Groups.flush() end')  # arrêt propre : écriture différée faite (LK13-T06)
        root, age = self.h.root, self.h.age_minutes
        self.h._tmp = None
        self.h.close()
        self.h = self.make(root=root)
        self.h.age_minutes = age
        self.h._push_clock()
        self.addCleanup(shutil.rmtree, root, True)

    def setup_world(self):
        """Registre neuf, deux groupes peuplés, blessés, simulation démarrée à l'heure courante."""
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'''
            local G = {G}
            local a = G.create({{ type = "settlers", name = "Mill", day = 1 }}).id
            local b = G.create({{ type = "raiders", name = "Crows", day = 1 }}).id
            for _, role in ipairs({{ "worker", "fighter", "medic", "scout", "worker", "deputy" }}) do
                G.addMember(a, {{ role = role }})
            end
            for _, role in ipairs({{ "fighter", "fighter", "breaker", "scout" }}) do G.addMember(b, {{ role = role }}) end
            G.setLeader(a, "m-1", 1)
            G.setLeader(b, "m-1", 1)
            G.setNeed(a, "food", 35)
            G.setNeed(b, "medical", 5)
            local d = G.state.data
            d.groups[a].members["m-2"].wound = 45
            d.groups[a].members["m-4"].wound = 12
            d.groups[b].members["m-2"].wound = 70
            G.save()
        ''')
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)   # premier pas : départ sans rattrapage
        self.assertEqual(self.ev('LivingKnox.Groups.state.data.simHour'), self.hour())

    def every_hour(self, hours):
        for _ in range(hours):
            self.h.advance(60)
            self.h.fire(self.srv, 'EveryHours')
            self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite


class ReproducibilityTests(Base):
    def test_24_single_hours_equal_one_24h_catch_up_after_restart(self):
        self.setup_world()
        start = self.ev(CANON)
        self.every_hour(24)
        stepwise = self.ev(CANON)
        self.assertNotEqual(stepwise, start)
        # Le découpage couvre aussi une expédition partie et revenue (LK09-T02).
        kinds = [e.kind for e in self.ev(f'{G}.get("grp-1")').log.values()]
        self.assertIn('expedition', kinds)
        self.assertIn('return', kinds)
        self.assertEqual(self.ev('LivingKnox.Groups.state.data.simHour'), self.hour())

        other = self.make()
        try:
            self.h, first = other, self.h
            self.setup_world()
            self.assertEqual(self.ev(CANON), start)             # même état de départ, même graine
            self.h.advance(24 * 60)                            # aucun EveryHours : 24 h manquées
            self.restart()                                     # arrêt du serveur, puis démarrage
            self.h.fire(self.srv, 'OnInitGlobalModData', False)
            self.h.fire(self.srv, 'OnServerStarted')           # rattrapage borné au démarrage
            self.assertEqual(self.ev(CANON), stepwise)
            self.assertTrue(any('caught up 24 hour(s) for 2 group(s)' in line for line in self.lk()))
            # Autre découpage : 5 h puis 19 h, même résultat.
            third = self.make()
            self.h = third
            self.setup_world()
            self.h.advance(5 * 60)
            self.assertEqual(self.ev(f'{SIM}.step()'), 5)
            self.h.advance(19 * 60)
            self.assertEqual(self.ev(f'{SIM}.step()'), 19)
            self.assertEqual(self.ev(CANON), stepwise)
            third.close()
        finally:
            self.h = first
            other.close()
        self.assertEqual(self.h.errors(self.srv), [])

    def test_state_evolves_consistently(self):
        self.setup_world()
        # Règles de LK09-T01 seules : aucune expédition (voir ExpeditionTests).
        self.run_lua('LivingKnox.Config.SIMULATION.EXPEDITIONS.DEPART_CHANCE = 0')
        self.every_hour(24)
        a = self.ev(f'{G}.get("grp-1")')
        b = self.ev(f'{G}.get("grp-2")')
        # Consommation : 6 membres x 0.08 x 24 h ~ 11.5 de nourriture ; la fouille en rend une partie.
        self.assertLess(a.needs.ammo, 50)
        self.assertTrue(0 <= a.needs.food <= 100 and 0 <= a.morale <= 100 and 0 <= a.rest <= 100)
        # Blessé grave avec des soins : il guérit, les soins baissent.
        self.assertLess(a.members['m-2'].wound or 0, 45)
        self.assertLess(a.needs.medical, 50)
        # Petite blessure : guérit seule.
        self.assertLess(a.members['m-4'].wound or 0, 12)
        # Tâches journalisées quand elles changent, avec leur raison.
        tasks = [e.text for e in a.log.values() if e.kind == 'task']
        self.assertTrue(tasks)
        for text in tasks:
            self.assertRegex(text, r'^(heal|rest|scavenge): [a-z]+$')
        self.assertIn(b.task, ('heal', 'rest', 'scavenge'))
        # Relecture : les champs ajoutés passent la validation du schéma 1.
        before = self.ev(CANON)
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.ev(CANON), before)
        self.assertTrue(any('groups loaded: 2 group(s), 0 dropped' in line for line in self.lk()))

    def test_seed_changes_results_and_fixed_seed_reproduces(self):
        self.setup_world()
        start = self.run_lua(f'local d = {G}.copy({G}.state.data) return d')
        self.assertIsNotNone(start)
        script = (f'local d = {G}.copy(_SNAP) LivingKnox.Config.SIMULATION.SEED = %s '
                  f'{SIM}.advance(d, d.simHour + 48) LivingKnox.Config.SIMULATION.SEED = nil '
                  'return require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes(d))')
        self.run_lua(f'_SNAP = {G}.copy({G}.state.data)')
        r1, r1b, r2 = (self.run_lua(script % s) for s in ('1234', '1234', '98765'))
        self.assertEqual(r1, r1b)
        self.assertNotEqual(r1, r2)


class CatchUpTests(Base):
    def test_catch_up_is_bounded_and_skipped_hours_logged(self):
        self.setup_world()
        self.run_lua(f'_SNAP = {G}.copy({G}.state.data)')
        start = self.hour()
        self.h.advance(100 * 60)
        now = self.hour()
        self.assertEqual(now - start, 100)
        self.assertEqual(self.ev(f'{SIM}.step()'), 72)
        self.assertTrue(any('100 hour(s) missed, 72 simulated, 28 skipped' in line for line in self.lk()))
        self.assertEqual(self.ev('LivingKnox.Groups.state.data.simHour'), now)
        # Les 72 heures simulées sont les plus récentes : même résultat qu'un registre parti de now - 72.
        expected = self.run_lua(f'local d = {G}.copy(_SNAP) d.simHour = {now - 72} {SIM}.advance(d, {now}, nil, '
                                'LivingKnox.Needs.advanceGroup) '
                                'return require("RadioSurvivor/RS_Codec").hexBytes('
                                'require("RadioSurvivor/RS_Codec").encodeBytes(d))')
        self.assertEqual(self.ev(CANON), expected)
        # Configurable.
        self.run_lua('LivingKnox.Config.SIMULATION.MAX_CATCHUP_HOURS = 3')
        self.h.advance(10 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 3)
        self.run_lua('LivingKnox.Config.SIMULATION.MAX_CATCHUP_HOURS = 72')

    def test_same_hour_twice_writes_nothing(self):
        self.setup_world()
        self.every_hour(1)
        seq = self.ev(f'{G}.state.seq')
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.ev(f'{G}.state.seq'), seq)

    def test_one_write_per_step(self):
        self.setup_world()
        self.run_lua(f'{G}.flush()')   # LK13-T06 : écriture différée, faite ici pour compter
        seq = self.ev(f'{G}.state.seq')
        self.h.advance(30 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 30)
        self.run_lua(f'{G}.flush()')
        self.assertEqual(self.ev(f'{G}.state.seq'), seq + 1)

    def test_clock_behind_the_group_file_waits(self):
        self.setup_world()
        self.run_lua(f'{G}.state.data.simHour = {G}.state.data.simHour + 5')
        before = self.ev(CANON)
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.assertEqual(self.ev(CANON), before)
        waits = [line for line in self.lk() if 'is behind the last simulated hour' in line]
        self.assertEqual(len(waits), 1)      # journalisé une fois
        self.h.advance(6 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 1)

    def test_registry_without_sim_hour_starts_without_catch_up(self):
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'{G}.create({{ type = "settlers", name = "Old" }}) {G}.addMember("grp-1", {{ role = "worker" }})')
        self.assertIsNone(self.ev(f'{G}.state.data.simHour'))
        self.h.advance(40 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.assertEqual(self.ev(f'{G}.state.data.simHour'), self.hour())
        self.assertTrue(any('simulation: starts at world hour' in line for line in self.lk()))

    def test_disabled_engine_simulates_nothing_then_catches_up(self):
        self.setup_world()
        before = self.ev(CANON)
        self.run_lua('_ENABLED = LivingKnox.Config.isEnabled; LivingKnox.Config.isEnabled = function() return false end')
        self.every_hour(4)
        self.assertEqual(self.ev(CANON), before)
        self.run_lua('LivingKnox.Config.isEnabled = _ENABLED')
        self.assertEqual(self.ev(f'{SIM}.step()'), 4)

    def test_blocked_registry_refuses(self):
        self.setup_world()
        self.run_lua(f'{G}.state.blocked = true')
        self.h.advance(60)
        self.assertEqual(self.run_lua(f'return {SIM}.step()'), (None, 'group registry not ready'))


class RulesTests(Base):
    def group(self, members, **fields):
        """Groupe neuf grp-1 dans un registre vide ; members = liste de (rôle, blessure)."""
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'{G}.create({{ type = "settlers", name = "S", day = 1 }})')
        for role, wound in members:
            self.run_lua(f'local mid = {G}.addMember("grp-1", {{ role = "{role}" }}) '
                         f'{G}.state.data.groups["grp-1"].members[mid].wound = {wound or "nil"}')
        for key, value in fields.items():
            if key in ('food', 'medical', 'ammo'):
                self.run_lua(f'{G}.state.data.groups["grp-1"].needs.{key} = {value}')
            else:
                self.run_lua(f'{G}.state.data.groups["grp-1"].{key} = {value}')

    def task(self, hour_of_day):
        # Heure simulée k : début à (k + 6) % 24.
        k = (hour_of_day - 6) % 24 + 24
        return self.run_lua(f'local g = {G}.state.data.groups["grp-1"] local living = {{}} '
                            'for mid, m in pairs(g.members) do if m.alive then living[#living + 1] = mid end end '
                            f'table.sort(living) return {SIM}.chooseTask(g, living, '
                            f'{SIM}.isNight(({k} + 6) % 24))')

    def test_task_priorities(self):
        self.group([('worker', None), ('fighter', 50)], medical=10, food=80, ammo=80, rest=60)
        self.assertEqual(self.task(14), ('heal', 'wounded'))
        self.run_lua(f'{G}.state.data.groups["grp-1"].needs.medical = 0')
        self.assertEqual(self.task(14), ('scavenge', 'medical'))   # blessé sans soins : aller en chercher
        self.assertEqual(self.task(23), ('rest', 'night'))
        self.assertEqual(self.task(3), ('rest', 'night'))
        self.run_lua(f'{G}.state.data.groups["grp-1"].rest = 10')
        self.assertEqual(self.task(14), ('rest', 'tired'))
        self.run_lua(f'local g = {G}.state.data.groups["grp-1"] g.rest = 60 g.needs.medical = 70')
        self.assertEqual(self.task(14), ('heal', 'wounded'))
        self.run_lua(f'{G}.state.data.groups["grp-1"].members["m-2"].wound = 10')
        self.assertEqual(self.task(14), ('rest', 'idle'))
        self.run_lua(f'{G}.state.data.groups["grp-1"].needs.ammo = 30')
        self.assertEqual(self.task(14), ('scavenge', 'ammo'))

    def test_wound_without_care_kills_and_leader_succession(self):
        self.group([('fighter', 95), ('worker', None), ('deputy', None)], medical=0, food=80, ammo=80)
        # Sans soins : aucune fouille ne rapporte de quoi soigner.
        self.run_lua(f'{G}.state.data.groups["grp-1"].leader = "m-1" {G}.state.data.simHour = 0 '
                     'LivingKnox.Config.SIMULATION.SCAVENGE_MAX = 0')
        morale = self.ev(f'{G}.state.data.groups["grp-1"].morale')
        self.run_lua(f'{SIM}.advance({G}.state.data, 20)')
        g = self.ev(f'{G}.get("grp-1")')
        self.assertFalse(g.members['m-1'].alive)
        self.assertEqual(g.leader, 'm-3')                # successeur : deputy d'abord
        kinds = [(e.kind, e.text) for e in g.log.values()]
        self.assertIn(('died', 'm-1'), kinds)
        self.assertIn(('leader', 'm-3'), kinds)
        self.assertLess(g.morale, morale)
        self.assertTrue(any('member m-1 died of wounds' in line for line in self.lk()))
        # Validation du registre après la mort.
        self.assertEqual(self.run_lua(f'local ok, why = {G}.validGroup({G}.state.data.groups["grp-1"], "grp-1", 2) '
                                      'return ok, why'), (True, None))

    def test_care_heals_and_consumes_medical(self):
        self.group([('worker', 60)], medical=80, food=90, ammo=90, rest=80)
        self.run_lua(f'{G}.state.data.simHour = 0')
        self.run_lua(f'{SIM}.advance({G}.state.data, 10)')
        g = self.ev(f'{G}.get("grp-1")')
        self.assertLess(g.members['m-1'].wound, 60)
        self.assertGreaterEqual(g.members['m-1'].wound, 60 - 2 * 10 - 1)
        self.assertLess(g.needs.medical, 80)

    def test_starvation_lowers_morale_and_wounds(self):
        self.group([('worker', None), ('worker', None)], food=0, medical=0, ammo=50, morale=60, rest=60)
        self.run_lua(f'{G}.state.data.simHour = 0 LivingKnox.Config.SIMULATION.SCAVENGE_MAX = 0')
        self.run_lua(f'{SIM}.advance({G}.state.data, 30)')
        self.run_lua('LivingKnox.Config.SIMULATION.SCAVENGE_MAX = 3')
        g = self.ev(f'{G}.get("grp-1")')
        self.assertLess(g.morale, 60)
        self.assertGreater(g.members['m-1'].wound or 0, 0)

    def test_dead_group_is_untouched(self):
        self.group([('worker', None)])
        self.run_lua(f'{G}.state.data.groups["grp-1"].members["m-1"].alive = false {G}.state.data.simHour = 0')
        before = self.run_lua('return require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec")'
                              f'.encodeBytes({G}.state.data.groups["grp-1"]))')
        self.run_lua(f'{SIM}.advance({G}.state.data, 50)')
        after = self.run_lua('return require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec")'
                             f'.encodeBytes({G}.state.data.groups["grp-1"]))')
        self.assertEqual(before, after)

    def test_amount_rounding_is_unbiased(self):
        total = self.run_lua(f'local rnd = {SIM}.stream(7, 1, 1) local s = 0 '
                             f'for i = 1, 10000 do s = s + {SIM}.amount(0.3, rnd) end return s')
        self.assertTrue(2800 <= total <= 3200, total)
        self.assertEqual(self.run_lua(f'return {SIM}.amount(-2, {SIM}.stream(7, 1, 1))'), -2)


class SchemaTests(Base):
    def test_invalid_new_fields_are_refused_or_forgotten(self):
        self.setup_world()
        self.every_hour(2)
        self.run_lua(f'local d = {G}.state.data d.groups["grp-1"].members["m-1"].wound = 140 '
                     'd.groups["grp-2"].rest = 2.5 d.simHour = -4 ' + f'{G}.save()')
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.ev(f'#{G}.list()'), 0)
        lines = self.lk()
        self.assertTrue(any('group grp-1 dropped at load' in line and 'bad wound' in line for line in lines))
        self.assertTrue(any('group grp-2 dropped at load' in line and 'bad rest' in line for line in lines))
        self.assertIsNone(self.ev(f'{G}.state.data.simHour'))

    def test_bad_task_refused(self):
        self.setup_world()
        self.run_lua(f'{G}.state.data.groups["grp-1"].task = "no way!" {G}.save()')
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertTrue(any('group grp-1 dropped at load' in line and 'bad task' in line for line in self.lk()))


class SidesAndBoundsTests(Base):
    def test_clients_do_not_load_the_simulation(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Simulation'))
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Simulation'))
        self.assertIsNotNone(self.ev('LivingKnox.Simulation'))

    def test_source_has_no_world_access_and_is_kahlua_safe(self):
        text = SIM_FILE.read_text(encoding='utf-8')
        code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
        for word in ('getCell', 'getGridSquare', 'getSquare', 'getChunk', 'getOnlinePlayers', 'getPlayer',
                     'getNumActivePlayers', 'IsoWorld', 'LoadChunk', 'getZombieList'):
            self.assertNotIn(word, code, word)
        for pattern in (r'\bnext\b', r'\bgoto\b', r'coroutine', r'<<', r'>>', r'~[^=]', r'\bbit32\b', r'//'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertTrue(code.isascii())

    def test_work_is_proportional_to_groups_and_hours(self):
        # 64 groupes de 32 membres, 72 heures : pas complet sans erreur, une seule écriture.
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'''
            local G = {G}
            for i = 1, G.MAX_GROUPS do
                local id = G.create({{ type = "neutrals", name = "N" .. i }}).id
                local g = G.state.data.groups[id]
                for k = 1, G.MAX_MEMBERS do
                    g.members["m-" .. k] = {{ id = "m-" .. k, role = "worker", alive = true }}
                end
                g.nextMember = G.MAX_MEMBERS + 1
            end
            G.save()
        ''')
        self.ev(f'{SIM}.step()')
        self.run_lua(f'{G}.flush()')   # LK13-T06 : écriture différée, faite ici pour compter
        seq = self.ev(f'{G}.state.seq')
        self.h.advance(72 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 72)
        self.run_lua(f'{G}.flush()')
        self.assertEqual(self.ev(f'{G}.state.seq'), seq + 1)
        self.assertEqual(self.h.errors(self.srv), [])


EXP = 'LivingKnox.Config.SIMULATION.EXPEDITIONS'
RETURN_RE = r'^[a-z_]+: \d+ back, \d+ lost, \d+ wounded, food \+\d+ medical \+\d+ ammo \+\d+$'

# Une expédition tirée N fois (heures 1..N, même graine) sur une copie du groupe grp-1 : rend les fréquences
# observées. %(place)s = lieu Lua, %(share)s = DEATH_SHARE, %(team)s = équipe, %(n)s = tirages.
DIST = '''
local S, G = LivingKnox.Simulation, LivingKnox.Groups
local s = S.expeditionSettings()
s.places = { %(place)s }
s.deathShare = %(share)s
local proto = G.state.data.groups["grp-1"]
local N, dead, wounded, recruits, survivors, food, maxWound, members = %(n)s, 0, 0, 0, 0, 0, 0, 0
local team = { %(team)s }
for i = 1, N do
    local g = G.copy(proto)
    g.needs.food = 0
    g.expedition = { place = s.places[1].id, team = team, departed = 0, returns = 1 }
    local r = S.resolveExpedition(g, "grp-1", i, s, S.stream(99, 1, i, S.EXPEDITION_SALT), 1)
    dead, wounded, survivors = dead + #r.lost, wounded + #r.wounded, survivors + r.back
    if r.recruit then recruits = recruits + 1 end
    food = food + r.gains.food
    for _, mid in ipairs(team) do
        local w = g.members[mid].wound or 0
        if g.members[mid].alive and w > maxWound then maxWound = w end
    end
    local n = 0
    for _ in pairs(g.members) do n = n + 1 end
    if n > members then members = n end
    if g.expedition ~= nil or not G.validGroup(g, "grp-1", 2) then return "invalid at " .. i end
end
local per = 0
if survivors > 0 then per = food / survivors end
return dead / (#team * N), wounded / (#team * N), recruits / N, per, maxWound, members
'''


class ExpeditionTests(Base):
    def group(self, roles, leader='m-1', **needs):
        """Groupe de colons grp-1 dans un registre vide, chef leader, réserves needs, simulation à l'heure 0."""
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'{G}.create({{ type = "settlers", name = "S", day = 1 }})')
        for role in roles:
            self.run_lua(f'{G}.addMember("grp-1", {{ role = "{role}" }})')
        if leader:
            self.run_lua(f'{G}.state.data.groups["grp-1"].leader = "{leader}"')
        values = {'food': 80, 'medical': 80, 'ammo': 80}
        values.update(needs)
        for key, value in values.items():
            self.run_lua(f'{G}.state.data.groups["grp-1"].needs.{key} = {value}')
        self.run_lua(f'local g = {G}.state.data.groups["grp-1"] g.rest = 80 {G}.state.data.simHour = 0 '
                     'LivingKnox.Config.SIMULATION.SEED = 4242')

    def g(self):
        return self.ev(f'{G}.get("grp-1")')

    def log_tail(self, start):
        g = self.g()
        return [(g.log[i].kind, g.log[i].text) for i in range(start + 1, len(g.log) + 1)]

    def test_departure_when_reserve_low_and_team_available(self):
        self.group(['worker', 'fighter', 'medic', 'scout', 'worker', 'deputy'], food=20)
        self.run_lua(f'{EXP}.DEPART_CHANCE = 1 {G}.state.data.groups["grp-1"].members["m-2"].wound = 30')
        start = len(self.g().log)
        self.run_lua(f'{SIM}.advance({G}.state.data, 1)')     # heure 1 = 7 h - 8 h, de jour
        g = self.g()
        e = g.expedition
        # Équipe : TEAM_MAX = 4, ni le chef m-1 ni le blessé m-2 ; ordre scout, fighter, worker, ..., medic, deputy.
        self.assertEqual(list(e.team.values()), ['m-4', 'm-5', 'm-3', 'm-6'])
        self.assertEqual(e.departed, 1)
        places = {p.id: p for p in self.ev(f'{SIM}.expeditionSettings()').places.values()}
        p = places[e.place]
        self.assertGreater(p['yield'].food, 0)
        self.assertTrue(p.hoursMin <= e.returns - e.departed <= p.hoursMax)
        self.assertEqual(g.task, 'expedition')
        tail = self.log_tail(start)
        self.assertEqual(tail[-2], ('task', 'expedition: food'))
        self.assertEqual(tail[-1][0], 'expedition')
        self.assertRegex(tail[-1][1], r'^' + e.place + r': m-4 m-5 m-3 m-6, \d+ h$')

    def test_no_departure_when_reserves_fine_or_group_small_or_chance_zero(self):
        self.group(['worker', 'fighter', 'scout', 'worker', 'worker', 'worker'], food=50)
        self.run_lua(f'{EXP}.DEPART_CHANCE = 1 {SIM}.advance({G}.state.data, 12)')
        self.assertIsNone(self.g().expedition)            # 50 >= NEED_TRIGGER : simple fouille
        # Trois membres : MIN_HOME = 2 au foyer, équipe d'un seul < TEAM_MIN.
        self.group(['worker', 'scout', 'fighter'], food=10)
        self.run_lua(f'{EXP}.DEPART_CHANCE = 1 {SIM}.advance({G}.state.data, 200)')
        kinds = [e.kind for e in self.g().log.values()]
        self.assertNotIn('expedition', kinds)
        # DEPART_CHANCE = 0 : jamais, même sur 200 heures.
        self.group(['worker', 'fighter', 'scout', 'worker', 'worker', 'worker'], food=10)
        self.run_lua(f'{EXP}.DEPART_CHANCE = 0 {SIM}.advance({G}.state.data, 200)')
        self.assertNotIn('expedition', [e.kind for e in self.g().log.values()])
        # Aucun lieu ne rapporte la réserve qui manque : pas de départ.
        self.group(['worker', 'fighter', 'scout', 'worker', 'worker', 'worker'], food=10)
        self.run_lua(f'{EXP}.DEPART_CHANCE = 1 for _, p in ipairs({EXP}.PLACES) do p.yield.food = 0 end '
                     f'{SIM}.advance({G}.state.data, 30)')
        self.assertNotIn('expedition', [e.kind for e in self.g().log.values()])

    def test_members_away_do_not_consume_rest_or_heal(self):
        self.group(['worker', 'worker', 'scout', 'scout', 'fighter', 'fighter'], food=90)
        self.run_lua('local c = LivingKnox.Config.SIMULATION c.FOOD_PER_MEMBER = 1 c.AMMO_PER_MEMBER = 0 '
                     'c.WOUND_CHANCE = 0 '
                     f'local g = {G}.state.data.groups["grp-1"] g.members["m-3"].wound = 10 '
                     'g.expedition = { place = "houses", team = { "m-3", "m-4", "m-5", "m-6" }, departed = 0, '
                     'returns = 100 }')
        self.run_lua(f'{SIM}.advance({G}.state.data, 10)')
        g = self.g()
        self.assertEqual(g.needs.food, 90 - 2 * 10)          # deux membres au foyer, 1 par heure chacun
        self.assertEqual(g.members['m-3'].wound, 10)         # blessure figée pendant l'absence
        self.assertIsNotNone(g.expedition)
        # Tout le monde dehors : rien ne bouge au foyer.
        self.run_lua(f'local g = {G}.state.data.groups["grp-1"] g.expedition.team = '
                     '{ "m-1", "m-2", "m-3", "m-4", "m-5", "m-6" }')
        before = self.ev(CANON)
        self.run_lua(f'{SIM}.advance({G}.state.data, 20)')
        self.assertNotEqual(self.ev(CANON), before)          # seule l'heure simulée change
        self.run_lua(f'{G}.state.data.simHour = 10')
        self.assertEqual(self.ev(CANON), before)

    def test_return_journal_reads_in_order_and_is_bounded(self):
        self.group(['worker', 'medic', 'medic', 'worker', 'worker'])   # aucun rôle de sécurité : risque 1
        found = self.run_lua(f'''
            local S, G = {SIM}, {G}
            local s = S.expeditionSettings()
            s.places = {{ {{ id = "police", hoursMin = 1, hoursMax = 1, risk = 1, recruit = 1,
                yield = {{ food = 2, medical = 1, ammo = 6 }} }} }}
            s.deathShare = 0.5
            local proto = G.state.data.groups["grp-1"]
            for i = 1, 200 do
                local g = G.copy(proto)
                g.log = {{}}
                g.expedition = {{ place = "police", team = {{ "m-2", "m-3", "m-4", "m-5" }}, departed = 0,
                    returns = 1 }}
                local r = S.resolveExpedition(g, "grp-1", i, s, S.stream(5, 1, i, S.EXPEDITION_SALT), 3)
                if #r.lost > 0 and r.recruit then
                    local out = {{}}
                    for _, e in ipairs(g.log) do out[#out + 1] = e.kind .. "|" .. e.text end
                    return table.concat(out, "\\n") .. "\\n" .. tostring(G.validGroup(g, "grp-1", 2))
                end
            end
            return nil
        ''')
        self.assertIsNotNone(found)
        lines = found.split('\n')
        self.assertEqual(lines[-1], 'true')
        entries = [tuple(line.split('|', 1)) for line in lines[:-1]]
        kinds = [k for k, _ in entries]
        lost = kinds.count('died')
        self.assertGreaterEqual(lost, 1)
        self.assertEqual(kinds, ['return', 'loss'] + ['died'] * lost + ['recruit', 'joined'])
        self.assertRegex(entries[0][1], RETURN_RE)
        self.assertTrue(entries[0][1].startswith(f'police: {4 - lost} back, {lost} lost, {4 - lost} wounded'))
        dead = [t for k, t in entries if k == 'died']
        self.assertEqual(entries[1][1], 'police: ' + ' '.join(dead))
        self.assertRegex(entries[-2][1], r'^police: m-6 [a-z]+$')
        self.assertEqual(entries[-1][1], 'm-6')
        # Bornes : au plus 2 + 2 x équipe + 2 entrées par expédition ; textes <= TEXT_MAX.
        self.assertLessEqual(len(entries), 2 + 2 * 4 + 2)
        self.assertTrue(all(len(t) <= 200 for _, t in entries))

    def test_expedition_cycle_in_the_journal_over_days(self):
        self.group(['worker', 'fighter', 'medic', 'scout', 'worker', 'deputy'], food=20, medical=20, ammo=20)
        # Historique complet des entrées écrites par la simulation (le journal du groupe n'en garde que 32).
        self.run_lua(f'_ALL = {{}} local append = {G}.appendLog {G}.appendLog = function(g, kind, text, day) '
                     '_ALL[#_ALL + 1] = kind .. "|" .. text append(g, kind, text, day) end')
        # 30 jours par pas de 24 h : toutes les heures simulées.
        self.run_lua(f'{EXP}.DEPART_CHANCE = 1 for h = 24, 30 * 24, 24 do {SIM}.advance({G}.state.data, h) end')
        g = self.g()
        self.assertLessEqual(len(g.log), 32)                 # journal borné à LOG_SIZE
        self.assertEqual(self.run_lua(f'return {G}.validGroup({G}.state.data.groups["grp-1"], "grp-1", 2)'), True)
        entries = [tuple(x.split('|', 1)) for x in self.run_lua('return table.concat(_ALL, ";")').split(';')]
        # Chaque départ est suivi de son retour, sans départ pendant une absence.
        seq = [k for k, _ in entries if k in ('expedition', 'return')]
        self.assertGreaterEqual(seq.count('return'), 2)
        self.assertEqual(seq[0], 'expedition')
        for a, b in zip(seq, seq[1:]):
            self.assertNotEqual(a, b)
        for kind, text in entries:
            if kind == 'return':
                self.assertRegex(text, RETURN_RE)
            elif kind == 'expedition':
                self.assertRegex(text, r'^[a-z_]+: (m-\d+ ?)+, \d+ h$')
            elif kind == 'loss':
                self.assertRegex(text, r'^[a-z_]+: (m-\d+ ?)+$')
            elif kind == 'recruit':
                self.assertRegex(text, r'^[a-z_]+: m-\d+ [a-z]+$')

    def test_probabilities_follow_the_settings(self):
        self.group(['worker', 'medic', 'medic', 'medic', 'medic'])
        place = ('{ id = "test", hoursMin = 1, hoursMax = 1, risk = 0.3, recruit = 0.2, '
                 'yield = { food = 5, medical = 0, ammo = 0 } }')
        dead, wounded, recruit, per, max_wound, members = self.run_lua(DIST % {
            'place': place, 'share': 0.25, 'team': '"m-2", "m-3", "m-4", "m-5"', 'n': 2000})
        self.assertAlmostEqual(dead, 0.3 * 0.25, delta=0.012)
        self.assertAlmostEqual(wounded, 0.3 * 0.75, delta=0.02)
        self.assertAlmostEqual(recruit, 0.2, delta=0.03)
        self.assertAlmostEqual(per, 5, delta=0.4)            # gain moyen par survivant = yield (aucun bonus)
        self.assertLessEqual(max_wound, 99)
        self.assertLessEqual(members, 6)                     # une recrue au plus par retour

    def test_extreme_settings(self):
        self.group(['worker', 'medic', 'medic', 'medic', 'medic'])
        team = '"m-2", "m-3", "m-4", "m-5"'
        # Risque 0 : ni blessé ni perte ; recrue 1 : toujours (place dans le type et le registre).
        r = self.run_lua(DIST % {'place': '{ id = "safe", hoursMin = 1, hoursMax = 1, risk = 0, recruit = 1, '
                                          'yield = { food = 0, medical = 0, ammo = 0 } }',
                                 'share': 1, 'team': team, 'n': 300})
        self.assertEqual(r[:4], (0, 0, 1, 0))
        # Risque 1 et DEATH_SHARE 1 : tous perdus, aucun gain, aucune recrue.
        r = self.run_lua(DIST % {'place': '{ id = "doom", hoursMin = 1, hoursMax = 1, risk = 1, recruit = 1, '
                                          'yield = { food = 9, medical = 0, ammo = 0 } }',
                                 'share': 1, 'team': team, 'n': 300})
        self.assertEqual(r[:4], (1, 0, 0, 0))
        # Risque 1 et DEATH_SHARE 0 : tous blessés, jamais tués ; blessure bornée à WOUND_DEATH - 1.
        self.run_lua(f'for _, m in pairs({G}.state.data.groups["grp-1"].members) do m.wound = 18 end')
        r = self.run_lua(DIST % {'place': '{ id = "rough", hoursMin = 1, hoursMax = 1, risk = 1, recruit = 0, '
                                          'yield = { food = 1, medical = 0, ammo = 0 } }',
                                 'share': 0, 'team': team, 'n': 300})
        self.assertEqual(r[:3], (0, 1, 0))
        self.assertLessEqual(r[4], 99)
        self.run_lua(f'for _, m in pairs({G}.state.data.groups["grp-1"].members) do m.wound = 90 end')
        r = self.run_lua(DIST % {'place': '{ id = "rough", hoursMin = 1, hoursMax = 1, risk = 1, recruit = 0, '
                                          'yield = { food = 1, medical = 0, ammo = 0 } }',
                                 'share': 0, 'team': team, 'n': 50})
        self.assertEqual((r[0], r[4]), (0, 99))
        # Groupe plein (size.max du type = 8 vivants) : aucune recrue même à 1.
        for _ in range(3):
            self.run_lua(f'{G}.addMember("grp-1", {{ role = "worker" }})')
        r = self.run_lua(DIST % {'place': '{ id = "safe", hoursMin = 1, hoursMax = 1, risk = 0, recruit = 1, '
                                          'yield = { food = 0, medical = 0, ammo = 0 } }',
                                 'share': 1, 'team': team, 'n': 50})
        self.assertEqual(r[2], 0)

    def test_roles_change_risk_and_yield(self):
        self.group(['worker', 'fighter', 'fighter', 'fighter', 'fighter', 'scout', 'scout', 'scout'])
        place = ('{ id = "test", hoursMin = 1, hoursMax = 1, risk = 0.4, recruit = 0, '
                 'yield = { food = 4, medical = 0, ammo = 0 } }')
        fighters = self.run_lua(DIST % {'place': place, 'share': 0.5, 'team': '"m-2", "m-3", "m-4", "m-5"',
                                        'n': 2000})
        scouts = self.run_lua(DIST % {'place': place, 'share': 0.5, 'team': '"m-6", "m-7", "m-8"', 'n': 2000})
        # Quatre fighters : sécurité 0.6 plafonnée à SAFETY_MAX = 0.5, risque effectif 0.2.
        self.assertAlmostEqual(fighters[0] + fighters[1], 0.2, delta=0.02)
        # Trois scouts : sécurité 0.3 (risque 0.28), bonus de rendement 0.45 (gain moyen 4 x 1.45 par survivant).
        self.assertAlmostEqual(scouts[0] + scouts[1], 0.28, delta=0.025)
        self.assertAlmostEqual(scouts[3], 4 * 1.45, delta=0.45)
        self.assertAlmostEqual(fighters[3], 4, delta=0.35)

    def test_settings_are_bounded(self):
        self.run_lua(f'''
            local E = {EXP}
            E.DEPART_CHANCE, E.NEED_TRIGGER, E.TEAM_MIN, E.TEAM_MAX, E.MIN_HOME = 5, "x", 6, 2, -3
            E.DEATH_SHARE, E.SAFETY_MAX, E.WOUND_MIN, E.WOUND_MAX = -1, 9, 50, 10
            E.ROLE_SAFETY = {{ fighter = 4 }}
            E.PLACES = {{ {{ id = "Bad Id" }}, {{ id = "ok", hoursMin = 0, hoursMax = 500, risk = 3, recruit = -2,
                yield = {{ food = 400, ammo = "y" }} }}, {{ id = "ok" }}, "nope" }}
        ''')
        s = self.ev(f'{SIM}.expeditionSettings()')
        self.assertEqual((s.departChance, s.needTrigger, s.teamMin, s.teamMax, s.minHome), (1, 0, 6, 6, 1))
        self.assertEqual((s.deathShare, s.safetyMax, s.woundMin, s.woundMax), (0, 1, 50, 50))
        self.assertEqual(s.roleSafety.fighter, 1)
        self.assertEqual(len(s.places), 1)
        p = s.places[1]
        self.assertEqual((p.id, p.hoursMin, p.hoursMax, p.risk, p.recruit), ('ok', 1, 72, 1, 0))
        self.assertEqual((p['yield'].food, p['yield'].medical, p['yield'].ammo), (100, 0, 0))
        self.ev(f'{SIM}.expeditionSettings()')
        warns = [line for line in self.lk() if 'expedition place' in line]
        self.assertEqual(len(warns), 3)                      # #1, ok (doublon), #4 : une fois chacun
        # Sans table EXPEDITIONS : aucun lieu, aucun départ.
        self.run_lua('LivingKnox.Config.SIMULATION.EXPEDITIONS = nil')
        self.assertEqual(len(self.ev(f'{SIM}.expeditionSettings()').places), 0)

    def test_unknown_place_returns_without_result(self):
        self.group(['worker', 'scout', 'fighter', 'worker'])
        self.run_lua(f'{G}.state.data.groups["grp-1"].expedition = {{ place = "moon", team = {{ "m-2", "m-3" }}, '
                     'departed = 0, returns = 2 }')
        start = len(self.g().log)
        before = dict(self.g().needs)
        self.run_lua(f'{SIM}.advance({G}.state.data, 1)')
        self.assertIsNotNone(self.g().expedition)            # pas encore l'heure
        self.run_lua(f'{SIM}.advance({G}.state.data, 2)')
        g = self.g()
        self.assertIsNone(g.expedition)
        self.assertIn(('return', 'moon: unknown place, 2 back'), self.log_tail(start))
        self.assertLessEqual(g.needs.food, before['food'])

    def test_expedition_field_survives_reload_and_bad_values_are_refused(self):
        self.setup_world()
        self.run_lua(f'{G}.state.data.groups["grp-1"].expedition = {{ place = "farm", team = {{ "m-3", "m-5" }}, '
                     f'departed = 3, returns = 12 }} {G}.save()')
        before = self.ev(CANON)
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.ev(CANON), before)
        for bad, why in (('{ place = "farm", team = { "m-3" }, departed = 5, returns = 4 }', 'bad expedition hours'),
                         ('{ place = "farm", team = { "x" }, departed = 1, returns = 4 }', 'bad expedition team'),
                         ('{ place = "farm", team = { "m-3", "m-3" }, departed = 1, returns = 4 }',
                          'bad expedition team'),
                         ('{ place = "farm", team = { "m-99" }, departed = 1, returns = 4 }', 'bad expedition team'),
                         ('{ place = "farm", team = {}, departed = 1, returns = 4 }', 'bad expedition team'),
                         ('{ place = "Farm!", team = { "m-3" }, departed = 1, returns = 4 }', 'bad expedition place'),
                         ('"farm"', 'expedition is not a table')):
            ok = self.run_lua(f'local g = {G}.copy({G}.state.data.groups["grp-1"]) g.expedition = {bad} '
                              f'return {G}.validGroup(g, "grp-1", 3)')
            self.assertEqual(ok, (False, why), bad)
        # Membre retiré pendant l'absence : le groupe reste valide, le retour l'ignore.
        self.run_lua(f'{G}.removeMember("grp-1", "m-3", 1)')
        self.assertEqual(self.run_lua(f'return {G}.validGroup({G}.state.data.groups["grp-1"], "grp-1", 3)'), True)


EVENTS_CFG = 'LivingKnox.Config.SIMULATION.EVENTS'

# Fonctions Lua des tests d'événements (LK09-T05) : _FORCE applique un événement sur une copie du registre avec le
# flux d'une graine, _TAIL rend les entrées de journal ajoutées depuis n (kind|texte, séparées par ;).
EVENT_HELPERS = '''
local S, G = LivingKnox.Simulation, LivingKnox.Groups
function _IDS(d)
    local ids = {}
    for gid in pairs(d.groups) do ids[#ids + 1] = gid end
    table.sort(ids, function(a, b) return G.idNumber(a) < G.idNumber(b) end)
    return ids
end
function _CHANCES(gid, bases)
    local d = G.state.data
    local c, t = S.eventChances(d, _IDS(d), gid, S.eventSettings(), bases, {})
    return c.departure, c.recruit, c.conflict, c.illness, c.clash, #t
end
function _TAIL(g, n)
    local out = {}
    for i = n + 1, #g.log do out[#out + 1] = g.log[i].kind .. "|" .. g.log[i].text end
    return table.concat(out, ";")
end
function _FORCE(d, gid, kind, seed, bases)
    local s = S.eventSettings()
    local ids = _IDS(d)
    local _, targets = S.eventChances(d, ids, gid, s, bases, {})
    return S.applyEvent(d, gid, kind, s, S.stream(seed, 1, 1, S.EVENT_SALT), 3, targets)
end
'''


class EventTests(Base):
    def world(self, morale=60, **needs):
        """Registre neuf : grp-1 colons (6, foyer 1000,1000), grp-2 pillards (5, foyer 1500,1000), grp-3 neutres
        (4, foyer 9000,9000) ; chef m-1 partout ; réserves needs (défaut 60) ; simulation à l'heure 0."""
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'''
            local G = {G}
            local specs = {{ {{ "settlers", 1000, {{ "deputy", "worker", "fighter", "medic", "scout", "worker" }} }},
                {{ "raiders", 1500, {{ "deputy", "fighter", "fighter", "breaker", "scout" }} }},
                {{ "neutrals", 9000, {{ "deputy", "worker", "hunter_x", "worker" }} }} }}
            for _, sp in ipairs(specs) do
                local id = G.create({{ type = sp[1], name = sp[1], day = 1,
                    home = {{ x = sp[2], y = (sp[1] == "neutrals") and 9000 or 1000, z = 0 }} }}).id
                for _, role in ipairs(sp[3]) do
                    if role == "hunter_x" then role = "fighter" end
                    G.addMember(id, {{ role = role }})
                end
                local g = G.state.data.groups[id]
                g.leader = "m-1"
                g.morale = {morale}
                g.rest = 80
                for _, key in ipairs(G.NEEDS) do g.needs[key] = 60 end
            end
            G.state.data.simHour = 0
            LivingKnox.Config.SIMULATION.SEED = 777
        ''')
        for key, value in needs.items():
            self.run_lua(f'{G}.state.data.groups["grp-1"].needs.{key} = {value}')
        self.run_lua(EVENT_HELPERS)

    def set(self, gid, field, value):
        self.run_lua(f'{G}.state.data.groups["{gid}"].{field} = {value}')

    def chances(self, gid='grp-1', bases='{}'):
        return self.run_lua(f'return _CHANCES("{gid}", {bases})')

    def test_departure_low_morale_never_the_leader(self):
        self.world(morale=10)
        dep = self.chances()[0]
        self.assertAlmostEqual(dep, 0.2 * (30 - 10) / 30, places=9)
        self.set('grp-1', 'morale', 40)
        self.assertEqual(self.chances()[0], 0)                # moral correct : aucun départ
        self.set('grp-1', 'morale', 10)
        # Membre lié à un PNJ : jamais candidat ; chef jamais ; effets et journal.
        self.run_lua(f'{G}.state.data.groups["grp-1"].members["m-2"].npc = "lk-5"')
        out = self.run_lua(f'''
            local seen = {{}}
            for seed = 1, 200 do
                local d = {G}.copy({G}.state.data)
                local g = d.groups["grp-1"]
                local n = #g.log
                local r = _FORCE(d, "grp-1", "departure", seed)
                if not r or g.members[r.member] ~= nil or g.leader ~= "m-1" or g.morale ~= 6 then
                    return "bad " .. seed
                end
                if not {G}.validGroup(g, "grp-1", d.nextId) then return "invalid " .. seed end
                seen[r.member] = true
                if seed == 1 then _T = _TAIL(g, n) end
            end
            local list = {{}}
            for mid in pairs(seen) do list[#list + 1] = mid end
            table.sort(list)
            return table.concat(list, " ")
        ''')
        self.assertEqual(out, 'm-3 m-4 m-5 m-6')             # ni m-1 (chef) ni m-2 (PNJ lié)
        tail = self.ev('_T').split(';')
        self.assertEqual(len(tail), 2)
        self.assertRegex(tail[0], r'^departure\|m-\d+ [a-z]+: low morale$')
        mid = tail[0].split('|')[1].split(' ')[0]
        self.assertEqual(tail[1], 'left|' + mid)
        # Au moins MIN_LEFT = 2 vivants restent : deux vivants, aucun départ.
        self.run_lua(f'for k = 3, 6 do {G}.state.data.groups["grp-1"].members["m-" .. k].alive = false end '
                     f'{G}.state.data.groups["grp-1"].members["m-2"].npc = nil')
        self.assertEqual(self.chances()[0], 0)

    def test_recruit_joins_within_type_bounds(self):
        self.world(morale=50, food=60)
        self.assertEqual(self.chances()[1], 0.03)
        self.set('grp-1', 'needs.food', 30)
        self.assertEqual(self.chances()[1], 0)                # réserve de nourriture trop basse
        self.set('grp-1', 'needs.food', 60)
        self.set('grp-1', 'morale', 30)
        self.assertEqual(self.chances()[1], 0)                # moral trop bas
        self.set('grp-1', 'morale', 50)
        out = self.run_lua(f'''
            local d = {G}.copy({G}.state.data)
            local g = d.groups["grp-1"]
            local n = #g.log
            local r = _FORCE(d, "grp-1", "recruit", 3)
            local m = g.members[r.member]
            return r.member, m.role, tostring(m.profile ~= nil), g.morale, _TAIL(g, n),
                tostring({G}.validGroup(g, "grp-1", d.nextId))
        ''')
        mid, role, has_profile, morale, tail, valid = out
        self.assertEqual(mid, 'm-7')
        self.assertEqual(has_profile, 'true')
        self.assertEqual(morale, 52)
        self.assertEqual(tail, f'recruit|wanderer: m-7 {role};joined|m-7')
        self.assertEqual(valid, 'true')
        # Groupe plein (size.max = 8 vivants des colons) : aucune chance, aucune recrue forcée.
        self.run_lua(f'{G}.addMember("grp-1", {{ role = "worker" }}) {G}.addMember("grp-1", {{ role = "worker" }})')
        self.assertEqual(self.chances()[1], 0)
        self.assertIsNone(self.run_lua(f'return _FORCE({G}.copy({G}.state.data), "grp-1", "recruit", 3)'))

    def test_conflict_lowers_morale_and_never_changes_leader(self):
        self.world(morale=60)
        self.assertEqual(self.chances()[2], 0)                # moral correct, réserves correctes
        self.set('grp-1', 'morale', 40)
        self.assertAlmostEqual(self.chances()[2], 0.02, places=9)
        self.run_lua(f'local g = {G}.state.data.groups["grp-1"] g.needs.food = 10 g.needs.ammo = 5 g.morale = 70')
        self.assertAlmostEqual(self.chances()[2], 0.02 + 2 * 0.03, places=9)   # deux réserves basses
        out = self.run_lua(f'''
            local contested, wounded, texts = 0, 0, {{}}
            for seed = 1, 400 do
                local d = {G}.copy({G}.state.data)
                local g = d.groups["grp-1"]
                local n = #g.log
                local r = _FORCE(d, "grp-1", "conflict", seed)
                if g.leader ~= "m-1" or g.morale ~= 64 or r.a == "m-1" or r.a == r.b then return "bad " .. seed end
                if r.contested then
                    contested = contested + 1
                    if r.b ~= "m-1" then return "contest " .. seed end
                end
                if r.wounded then
                    wounded = wounded + 1
                    local w = g.members[r.wounded].wound or 0
                    if w < 5 or w > 15 then return "wound " .. seed .. " " .. w end
                end
                if #g.log ~= n + 1 or g.log[n + 1].kind ~= "conflict" then return "log " .. seed end
                texts[#texts + 1] = g.log[n + 1].text
            end
            return contested / 400, wounded / 400, table.concat(texts, ";")
        ''')
        contested, wounded, texts = out
        self.assertAlmostEqual(contested, 0.25, delta=0.06)
        self.assertAlmostEqual(wounded, 0.3, delta=0.06)
        for text in texts.split(';'):
            self.assertRegex(text, r'^m-\d+ vs m-\d+(, leader contested)?(, m-\d+ wounded)?$')
        self.assertIn('leader contested', texts)

    def test_illness_wounds_and_consumes_medical(self):
        self.world(medical=80)
        self.assertAlmostEqual(self.chances()[3], 0.02, places=9)
        self.set('grp-1', 'needs.food', 10)
        self.assertAlmostEqual(self.chances()[3], 0.06, places=9)     # faim : chance augmentée
        out = self.run_lua(f'''
            local maxSick = 0
            for _, medical in ipairs({{ 80, 0 }}) do
                for seed = 1, 300 do
                    local d = {G}.copy({G}.state.data)
                    local g = d.groups["grp-1"]
                    g.needs.medical = medical
                    local n = #g.log
                    local r = _FORCE(d, "grp-1", "illness", seed)
                    if #r.sick > maxSick then maxSick = #r.sick end
                    for _, mid in ipairs(r.sick) do
                        local w = g.members[mid].wound or 0
                        if medical > 0 and (w < 5 or w > 12) then return "treated wound " .. w end
                        if medical == 0 and (w < 10 or w > 25) then return "untreated wound " .. w end
                    end
                    if medical > 0 and (r.treated ~= #r.sick or g.needs.medical ~= 80 - 3 * #r.sick) then
                        return "medical " .. seed
                    end
                    if medical == 0 and (r.treated ~= 0 or g.needs.medical ~= 0) then return "no medical " .. seed end
                    if g.morale ~= 57 or g.log[n + 1].kind ~= "illness" then return "log " .. seed end
                    _TEXT = g.log[n + 1].text
                end
            end
            return maxSick, _TEXT
        ''')
        max_sick, text = out
        self.assertEqual(max_sick, 3)                         # MAX_SICK atteint, jamais dépassé
        self.assertRegex(text, r'^(m-\d+ ?)+ sick, 0 treated, medical -0$')
        # Soins partiels : 4 de réserve pour 3 par malade -> un seul soigné.
        self.run_lua(f'{EVENTS_CFG}.ILLNESS.SPREAD = 1')
        r = self.run_lua(f'local d = {G}.copy({G}.state.data) d.groups["grp-1"].needs.medical = 4 '
                         'local r = _FORCE(d, "grp-1", "illness", 2) '
                         'return #r.sick, r.treated, d.groups["grp-1"].needs.medical, '
                         'd.groups["grp-1"].log[#d.groups["grp-1"].log].text')
        self.assertEqual(r[:3], (3, 1, 1))
        self.assertTrue(r[3].endswith(' sick, 1 treated, medical -3'), r[3])

    def test_clash_conditions(self):
        self.world()
        # Pillards (grp-2) : cible grp-1 (500 cases), pas grp-3 (trop loin) ; bases vides.
        c = self.chances('grp-2')
        self.assertEqual((c[4], c[5]), (0.05, 1))
        self.assertEqual(self.chances('grp-1')[4], 0)        # colons : jamais attaquants
        self.assertEqual(self.chances('grp-2', 'nil')[4], 0)  # bases inconnues : aucun combat
        # Joueur à moins de 300 cases du foyer de la cible, ou de l'attaquant : aucun combat.
        self.assertEqual(self.chances('grp-2', '{ { x1 = 1100, y1 = 1000, x2 = 1101, y2 = 1001 } }')[4], 0)
        self.assertEqual(self.chances('grp-2', '{ { x1 = 1500, y1 = 1250, x2 = 1501, y2 = 1251 } }')[4], 0)
        self.assertEqual(self.chances('grp-2', '{ { x1 = 1250, y1 = 1500, x2 = 1251, y2 = 1501 } }')[4], 0.05)
        # Réserve basse des pillards : chance augmentée.
        self.set('grp-2', 'needs.food', 10)
        self.assertAlmostEqual(self.chances('grp-2')[4], 0.1, places=9)
        # Distance bornée : 2 500 cases, aucun combat ; cible sans foyer non plus.
        self.set('grp-1', 'home.x', 4000)
        self.assertEqual(self.chances('grp-2')[5], 0)
        self.set('grp-1', 'home.x', 1000)
        self.set('grp-1', 'home', 'nil')
        self.assertEqual(self.chances('grp-2')[5], 0)
        self.set('grp-1', 'home', '{ x = 1000, y = 1000, z = 0 }')
        # Deux pillards : pas l'un contre l'autre ; attaquant sans force suffisante (MIN_FORCE = 2 au foyer).
        self.set('grp-1', 'type', '"raiders"')
        self.assertEqual(self.chances('grp-2')[5], 0)
        self.set('grp-1', 'type', '"settlers"')
        self.run_lua(f'for k = 2, 5 do {G}.state.data.groups["grp-2"].members["m-" .. k].alive = false end')
        self.assertEqual(self.chances('grp-2')[5], 0)

    def test_clash_outcome_losses_loot_and_journals(self):
        self.world()
        out = self.run_lua(f'''
            local wins, N = 0, 600
            for seed = 1, N do
                local d = {G}.copy({G}.state.data)
                local a, t = d.groups["grp-2"], d.groups["grp-1"]
                local na, nt = #a.log, #t.log
                local beforeA, beforeT = {G}.copy(a.needs), {G}.copy(t.needs)
                local r = _FORCE(d, "grp-2", "clash", seed, {{}})
                if r.target ~= "grp-1" then return "target " .. seed end
                if r.won then wins = wins + 1 end
                if #r.deadA > 3 or #r.deadD > 3 then return "deaths " .. seed end
                for _, key in ipairs({G}.NEEDS) do
                    local ga, gt = a.needs[key] - beforeA[key], t.needs[key] - beforeT[key]
                    if r.deltaA[key] ~= ga or r.deltaD[key] ~= gt then return "delta " .. seed end
                    local cost = 0
                    if key == "ammo" then cost = 4 end
                    if ga + gt ~= -2 * cost then return "not conserved " .. key .. " " .. seed end
                    if not r.won and ga ~= -cost then return "loot on defeat " .. seed end
                    if ga + cost > 20 then return "loot max " .. seed end
                end
                for _, w in ipairs({{ {{ a, r.woundedA }}, {{ t, r.woundedD }} }}) do
                    for _, mid in ipairs(w[2]) do
                        local wound = w[1].members[mid].wound or 0
                        if wound < 15 or wound > 99 then return "wound " .. seed end
                    end
                end
                for _, side in ipairs({{ {{ a, na, r.deadA, "attack grp%-1 " }}, {{ t, nt, r.deadD, "defend grp%-2 " }} }}) do
                    local g, n, dead = side[1], side[2], side[3]
                    if g.log[n + 1].kind ~= "clash" or not string.find(g.log[n + 1].text, "^" .. side[4]) then
                        return "clash log " .. seed
                    end
                    local died = 0
                    for i = n + 2, #g.log do
                        if g.log[i].kind == "died" then died = died + 1 end
                    end
                    if died ~= #dead then return "died log " .. seed end
                    if #dead > 0 then
                        local last = g.log[#g.log]
                        if last.kind ~= "remains" or last.text ~= table.concat(dead, " ") .. " at 1000,1000,0" then
                            return "remains " .. seed .. " " .. last.kind .. " " .. last.text
                        end
                    end
                    if not {G}.validGroup(g, g.id, d.nextId) or not g.members[g.leader or "m-1"] then
                        return "invalid " .. seed
                    end
                    if g.leader and not g.members[g.leader].alive then return "dead leader " .. seed end
                end
                if seed == 7 then _A, _D = a.log[na + 1].text, t.log[nt + 1].text end
            end
            return wins / N
        ''')
        # Forces : pillards 5, colons 6 x 1.25 = 7.5 : victoire de l'attaquant 5 / 12.5 = 0.4.
        self.assertAlmostEqual(out, 0.4, delta=0.05)
        clash_re = r' (won|lost): \d+ lost, \d+ wounded, food [+-]\d+ medical [+-]\d+ ammo [+-]\d+$'
        self.assertRegex(self.ev('_A'), r'^attack grp-1' + clash_re)
        self.assertRegex(self.ev('_D'), r'^defend grp-2' + clash_re)

    def test_one_event_per_group_per_day_in_the_simulation(self):
        self.world(morale=20, food=20)
        self.run_lua(f'''
            local E = {EVENTS_CFG}
            E.MAX_DAILY = 1
            E.DEPARTURE.CHANCE, E.RECRUIT.CHANCE, E.CONFLICT.CHANCE, E.ILLNESS.CHANCE, E.CLASH.CHANCE =
                0.3, 0.3, 0.3, 0.3, 0.6
            E.RECRUIT.MORALE_MIN, E.RECRUIT.FOOD_MIN = 0, 0
            LivingKnox.Config.SIMULATION.EXPEDITIONS.DEPART_CHANCE = 0
            _ALL = {{}}
            local append = {G}.appendLog
            {G}.appendLog = function(g, kind, text, day)
                _ALL[#_ALL + 1] = g.id .. "|" .. day .. "|" .. kind .. "|" .. text
                append(g, kind, text, day)
            end
        ''')
        self.run_lua(f'for h = 24, 20 * 24, 24 do {SIM}.advance({G}.state.data, h, {{}}) end')
        rows = [x.split('|', 3) for x in self.run_lua('return table.concat(_ALL, ";")').split(';') if x]
        events = ('departure', 'recruit', 'conflict', 'illness', 'clash')
        per_day = {}
        for gid, day, kind, _ in rows:
            if kind in events:
                per_day.setdefault((gid, day), []).append(kind)
        self.assertTrue(per_day)
        for key, kinds in per_day.items():
            self.assertEqual(len(kinds), 1, (key, kinds))
        seen = {k for kinds in per_day.values() for k in kinds}
        self.assertEqual(seen, set(events))                  # chaque événement est arrivé au moins une fois
        for gid in ('grp-1', 'grp-2', 'grp-3'):
            self.assertEqual(self.run_lua(f'return {G}.validGroup({G}.state.data.groups["{gid}"], "{gid}", 4)'),
                             True)
            self.assertLessEqual(len(self.ev(f'{G}.get("{gid}")').log), 32)
        # Aucun événement sans table EVENTS.
        self.run_lua(f'{EVENTS_CFG} = nil _ALL = {{}}')
        self.run_lua(f'{SIM}.advance({G}.state.data, 40 * 24, {{}})')
        kinds = [x.split('|')[2] for x in self.run_lua('return table.concat(_ALL, ";")').split(';') if x]
        self.assertFalse(set(kinds) & set(events))

    def test_events_are_reproducible_whatever_the_catch_up_split(self):
        self.world(morale=20, food=20)
        self.run_lua(f'''
            local E = {EVENTS_CFG}
            E.MAX_DAILY = 1
            E.DEPARTURE.CHANCE, E.CONFLICT.CHANCE, E.ILLNESS.CHANCE, E.CLASH.CHANCE = 0.2, 0.2, 0.2, 0.8
            _SNAP = {G}.copy({G}.state.data)
        ''')
        out = self.run_lua(f'''
            local C = require("RadioSurvivor/RS_Codec")
            local a, b, c = {G}.copy(_SNAP), {G}.copy(_SNAP), {G}.copy(_SNAP)
            local clashes, append = 0, {G}.appendLog
            {G}.appendLog = function(g, kind, text, day)
                if kind == "clash" then clashes = clashes + 1 end
                append(g, kind, text, day)
            end
            for h = 1, 240 do {SIM}.advance(a, h, {{}}) end
            {G}.appendLog = append
            for h = 72, 240, 72 do {SIM}.advance(b, h, {{}}) end
            {SIM}.advance(b, 240, {{}})
            {SIM}.advance(c, 31, {{}}) {SIM}.advance(c, 100, {{}}) {SIM}.advance(c, 172, {{}})
            {SIM}.advance(c, 240, {{}})
            local ha, hb, hc = C.hexBytes(C.encodeBytes(a)), C.hexBytes(C.encodeBytes(b)), C.hexBytes(C.encodeBytes(c))
            return tostring(ha == hb and hb == hc), clashes
        ''')
        self.assertEqual(out[0], 'true')
        self.assertGreater(out[1], 0)

    def test_event_settings_are_bounded(self):
        self.run_lua(f'''
            local E = {EVENTS_CFG}
            E.HOUR, E.MAX_DAILY = 40, "x"
            E.DEPARTURE = {{ CHANCE = 3, MORALE_MAX = 250, MIN_LEFT = 0, MORALE = -400 }}
            E.CONFLICT.WOUND_MIN, E.CONFLICT.WOUND_MAX = 30, 10
            E.CLASH.PLAYER_DISTANCE, E.CLASH.ATTACKERS = 5, {{ "raiders", 7 }}
            E.ILLNESS = nil
        ''')
        s = self.ev(f'{SIM}.eventSettings()')
        self.assertEqual((s.hour, s.maxDaily), (23, 0))
        d = s.departure
        self.assertEqual((d.CHANCE, d.MORALE_MAX, d.MIN_LEFT, d.MORALE), (1, 100, 1, -100))
        self.assertEqual((s.conflict.WOUND_MIN, s.conflict.WOUND_MAX), (30, 30))
        self.assertEqual(s.clash.PLAYER_DISTANCE, 80)        # jamais à portée de la zone chargée
        self.assertEqual(dict(s.clash.ATTACKERS), {'raiders': True})
        self.assertIsNone(s.illness)                          # sous-table absente : événement désactivé
        self.assertIsNotNone(s.recruit)
        self.run_lua(f'{EVENTS_CFG} = nil')
        self.assertIsNone(self.ev(f'{SIM}.eventSettings()'))

    def test_step_reads_the_known_bases(self):
        self.run_lua(f'_KB = 0 local R = require("RadioSurvivor/RS_Rescue") local kb = R.knownBases '
                     'R.knownBases = function(o) _KB = _KB + 1 return kb(o) end')
        self.setup_world()
        self.h.advance(3 * 60)
        self.assertEqual(self.ev(f'{SIM}.step()'), 3)
        self.assertEqual(self.ev('_KB'), 2)                    # une lecture par pas
        self.assertEqual(self.run_lua(f'return type({SIM}.knownBases())'), 'table')


class CrossVmTests(Base):
    def test_same_values_as_the_kahlua_bench(self):
        """Même code que l'évaluation KR-SIM de tests/test_kahlua.py : lupa et Kahlua donnent les mêmes valeurs."""
        import test_kahlua
        code = next(e for e in test_kahlua.EXCHANGE_EVALS if '"KR-SIM "' in e)[len('eval:'):]
        self.assertEqual(self.run_lua(code), 'KR-SIM true 34 43 2 84 43 62 m-2 true 20 497 1')


    def test_same_event_values_as_the_kahlua_bench(self):
        """LK09-T05 : même code que l'évaluation KR-EVT de tests/test_kahlua.py (événements, combat compris)."""
        import test_kahlua
        code = next(e for e in test_kahlua.EXCHANGE_EVALS if '"KR-EVT "' in e)[len('eval:'):]
        self.assertEqual(self.run_lua(code), 'KR-EVT true 8 0 47 32 58 7 6 nil m-1')


class SoloTests(Base):
    mode = 'solo'

    def test_solo_catch_up_on_game_start(self):
        self.setup_world()
        self.h.advance(6 * 60)
        self.h.fire(self.srv, 'OnGameStart')
        self.assertEqual(self.ev(f'{G}.state.data.simHour'), self.hour())
        self.assertTrue(any('caught up 6 hour(s)' in line for line in self.lk()))
        self.assertEqual(self.h.errors(self.srv), [])


if __name__ == '__main__':
    unittest.main()
