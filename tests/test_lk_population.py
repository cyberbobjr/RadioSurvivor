"""Population initiale des groupes et réglages (LK08-T05) : LK_Population.lua, options de LK_Config.lua,
sandbox-options.txt et leurs traductions.

    python RadioSurvivor/tests/test_lk_population.py

Deux bancs :
- lupa direct (Lua 5.1, `next` retiré comme dans Kahlua) avec les doublures de la métagrille de tests/test_rescue.py et
  tests/test_lk_sites.py (bâtiments, zones de forêt des cellules approchées, refuges, joueurs), le vrai registre
  LK_Groups (fichiers getFileReader / getFileWriter en mémoire), les vrais types, histoires (LK_Stories) et sites
  (LK_Sites) ; un « redémarrage » = nouvelle VM, mêmes fichiers ;
- tests/harness.py (serveur dédié + deux clients, ou solo) pour les accroches de LK_Server.lua (OnInitGlobalModData,
  OnServerStarted / OnGameStart, EveryHours), sans métagrille (getMetaGrid rend nil : groupes sans foyer).
Options sandbox : getSandboxOptions():getOptionByName(nom) rend nil pour une option inconnue (SandboxOptions.java),
sinon un objet dont getValue() rend la valeur (nombre pour une option integer). Ne prouve pas l'API Java réelle ni le
moment réel des événements (voir docs/annexes/conception/groupes.md, section « Population »).
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_sites import EXTRA, FORESTS  # noqa: E402
from test_rescue import DOUBLES, WORLD  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media'
MOD_LUA = MEDIA / 'lua'
MODULE = MOD_LUA / 'server' / 'LivingKnox' / 'LK_Population.lua'
SANDBOX_FILE = MEDIA / 'sandbox-options.txt'
SHARED = ['LivingKnox/LK_Core', 'LivingKnox/LK_Config', 'LivingKnox/LK_Log', 'LivingKnox/LK_GroupTypes',
          'LivingKnox/Data/LK_Type_neutrals', 'LivingKnox/Data/LK_Type_raiders', 'LivingKnox/Data/LK_Type_settlers']

OPTIONS = {'GroupCount': (3, 5, 4), 'WeightSettlers': (0, 100, 40), 'WeightRaiders': (0, 100, 35),
           'WeightNeutrals': (0, 100, 25), 'GroupSizeMin': (4, 8, 4), 'GroupSizeMax': (4, 8, 8),
           'ReliefDaysMin': (2, 5, 2), 'ReliefDaysMax': (2, 5, 5)}

SANDBOX = r'''
JAVA_OPTIONS = {}
local stub = {}
function stub:getOptionByName(name)
    if JAVA_OPTIONS[name] == nil then return nil end
    return { getValue = function() return JAVA_OPTIONS[name] end }
end
getSandboxOptions = function() return stub end
'''

CANON = ('return require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes('
         'LivingKnox.Groups.state.data))')
POP = 'LivingKnox.Population'


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def option_defaults() -> str:
    return ''.join(f'JAVA_OPTIONS["LivingKnox.{n}"] = {d}\n' for n, (_, _, d) in OPTIONS.items())


# LK13-T09 : les passes horaires partent une par image (LK_Simulation.defer) ; ce banc les vide aussitôt.
FINISH_HOUR = 'if LivingKnox.Simulation and LivingKnox.Simulation.finishHour then LivingKnox.Simulation.finishHour() end'

class Bench(unittest.TestCase):
    """VM lupa : carte de test, vrai registre, vrais modules ; fichiers gardés d'un « redémarrage » à l'autre."""

    def setUp(self):
        self.files = {}
        self.boot(new_world=True)

    def boot(self, new_world=False, forests=True, before=''):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent de Kahlua
        self.rt.execute(DOUBLES)
        self.rt.execute(EXTRA)
        self.rt.execute(SANDBOX + option_defaults())
        paths = [MOD_LUA / 'shared', MOD_LUA / 'server']
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
        self.rt.execute(WORLD + (FORESTS if forests else ''))
        for path, text in self.files.items():
            self.g.FILES[path] = text
        if before:
            self.rt.execute(before)
        for name in SHARED:
            self.rt.execute(f'require "{name}"')
        self.rt.execute('require "LivingKnox/LK_Population"')
        self.rt.execute(f'LivingKnox.Groups.init({"true" if new_world else "false"})')

    def restart(self, **kw):
        self.ev('LivingKnox.Groups.flush()')  # arrêt propre : écriture différée faite (LK13-T06)
        self.files = {k: v for k, v in self.g.FILES.items()}
        self.boot(**kw)

    def ev(self, code):
        return self.rt.execute(code if code.lstrip().startswith(('return', 'local')) else 'return ' + code)

    def run_pop(self, seed=1234):
        return self.ev(f'local r, why = {POP}.run({{ seed = {seed} }}) return r, why')

    def opt(self, name, value):
        self.rt.execute(f'JAVA_OPTIONS["LivingKnox.{name}"] = {value}')

    def data(self):
        return self.g.LivingKnox.Groups.state.data

    def groups(self):
        d = self.data()
        ids = lua_list(self.g.LivingKnox.Groups.list())
        return [d.groups[i] for i in ids]

    def members(self, g):
        return [g.members[f'm-{k}'] for k in range(1, g.nextMember)]

    def logs(self, level=None):
        lines = [line for line in lua_list(self.g.LOGS) if line.startswith('[LivingKnox]')]
        return [line for line in lines if level is None or f'] {level} ' in line]

    def type_def(self, t):
        return self.g.LivingKnox.GroupTypes.state.types[t]


class DefaultPopulationTests(Bench):
    def test_default_population_types_sizes_members_leader_story_home(self):
        ids, why = self.run_pop()
        self.assertIsNone(why)
        self.assertEqual(lua_list(ids), ['grp-1', 'grp-2', 'grp-3', 'grp-4'])
        groups = self.groups()
        self.assertEqual(len(groups), 4)
        self.assertIs(self.data().populated, True)
        homes = set()
        for g in groups:
            with self.subTest(group=g.id):
                d = self.type_def(g.type)
                self.assertIn(g.type, ('settlers', 'raiders', 'neutrals'))
                members = self.members(g)
                self.assertGreaterEqual(len(members), max(4, d.size.min))
                self.assertLessEqual(len(members), min(8, d.size.max))
                counts = {}
                for m in members:
                    self.assertTrue(m.alive)
                    self.assertIsNotNone(d.roles[m.role])
                    prof = next(p for p in lua_list(d.profiles) if p.id == m.profile)
                    self.assertEqual(prof.role, m.role)
                    counts[m.profile] = counts.get(m.profile, 0) + 1
                    self.assertIsInstance(m.female, bool)
                    allowed = {t.id for t in lua_list(prof.traits)}
                    self.assertTrue(set(lua_list(m.traits)) <= allowed)
                for p in lua_list(d.profiles):
                    if p.max is not None:
                        self.assertLessEqual(counts.get(p.id, 0), p.max)
                # Chef = règle de succession existante ; histoire recomposée depuis storySeed.
                self.assertEqual(g.leader, self.ev(f'LivingKnox.Groups.pickSuccessor({{ members = '
                                                   f'LivingKnox.Groups.state.data.groups["{g.id}"].members }})'))
                story = self.ev(f'LivingKnox.Stories.compose("{g.type}", {g.storySeed})')
                self.assertEqual(g.story, story.summary.en)
                self.assertLessEqual(len(g.story), 600)
                self.assertEqual(g.name, story.leader.name)
                self.assertEqual(g.members[g.leader].female, story.leader.female)
                # Secrets jamais stockés dans le registre.
                canon = self.ev('local function walk(v, out) if type(v) == "table" then for k, x in pairs(v) do '
                                'walk(k, out) walk(x, out) end else out[#out + 1] = tostring(v) end return out end '
                                f'return table.concat(walk(LivingKnox.Groups.state.data, {{}}), "|")')
                for s in lua_list(story.secrets):
                    self.assertNotIn(s.en, canon)
                    self.assertNotIn(s.fr, canon)
                # Réglages de départ du type.
                self.assertEqual((g.needs.food, g.needs.medical, g.needs.ammo, g.morale),
                                 (d.needs.food, d.needs.medical, d.needs.ammo, d.morale))
                self.assertEqual([e.kind for e in lua_list(g.log)][:2], ['founded', 'joined'])
                if g.home is not None:
                    homes.add((g.home.x, g.home.y, g.home.z))
        self.assertEqual(len(homes), sum(1 for g in groups if g.home is not None))   # foyers distincts
        self.assertGreaterEqual(len(homes), 1)
        self.assertTrue(any('population: 4 group(s) created (requested 4, seed 1234)' in line for line in self.logs()))
        self.assertEqual(self.logs('ERROR'), [])

    def test_homes_far_from_each_other_and_from_the_player(self):
        self.run_pop(seed=77)
        homes = [g.home for g in self.groups() if g.home is not None]
        for i, a in enumerate(homes):
            self.assertGreaterEqual(((a.x - 100) ** 2 + (a.y - 100) ** 2) ** 0.5, 600)
            for b in homes[i + 1:]:
                self.assertGreaterEqual(((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5, 399)

    def test_reproducible_with_the_same_seed(self):
        self.run_pop(seed=99)
        first = self.ev(CANON)
        self.files = {}
        self.boot(new_world=True)
        self.run_pop(seed=99)
        self.assertEqual(self.ev(CANON), first)
        self.files = {}
        self.boot(new_world=True)
        self.run_pop(seed=100)
        self.assertNotEqual(self.ev(CANON), first)

    def test_seed_derived_from_the_game(self):
        a = self.ev(f'{POP}.baseSeed()')
        self.rt.execute('getWorld = function() return { getMetaGrid = function() return GRID end, '
                        'getWorld = function() return "other-save" end, getGameMode = function() return "Sandbox" end } end')
        b = self.ev(f'{POP}.baseSeed()')
        self.assertNotEqual(a, b)
        self.assertEqual(b, self.ev(f'{POP}.baseSeed()'))
        self.assertTrue(0 < a < 2 ** 31 and 0 < b < 2 ** 31)


class OptionTests(Bench):
    def plan(self, seed):
        return lua_list(self.ev(f'{POP}.plan(LivingKnox.Config.population(), {seed})'))

    def test_group_count_bounds(self):
        for count in (3, 5):
            with self.subTest(count=count):
                self.files = {}
                self.boot(new_world=True)
                self.opt('GroupCount', count)
                ids, _ = self.run_pop()
                self.assertEqual(len(lua_list(ids)), count)

    def test_type_mix_weights_and_exclusion(self):
        self.opt('WeightSettlers', 0)
        self.opt('WeightNeutrals', 0)
        for seed in range(1, 21):
            self.assertEqual({p.type for p in self.plan(seed)}, {'raiders'})
        self.opt('WeightRaiders', 0)
        self.opt('WeightNeutrals', 7)
        self.assertEqual({p.type for s in range(1, 21) for p in self.plan(s)}, {'neutrals'})
        # Défauts 40 / 35 / 25 : proportions sur 4 x 300 groupes.
        for name in ('WeightSettlers', 'WeightRaiders', 'WeightNeutrals'):
            self.opt(name, OPTIONS[name][2])
        types = [p.type for s in range(1, 301) for p in self.plan(s)]
        share = {t: types.count(t) / len(types) for t in ('settlers', 'raiders', 'neutrals')}
        self.assertAlmostEqual(share['settlers'], 0.40, delta=0.05)
        self.assertAlmostEqual(share['raiders'], 0.35, delta=0.05)
        self.assertAlmostEqual(share['neutrals'], 0.25, delta=0.05)

    def test_all_weights_zero_falls_back_to_defaults(self):
        for name in ('WeightSettlers', 'WeightRaiders', 'WeightNeutrals'):
            self.opt(name, 0)
        self.assertEqual(len(self.plan(5)), 4)
        self.assertIn('[LivingKnox] WARN population: every group type weight is 0, default weights used',
                      self.logs('WARN'))

    def test_sizes_intersection_with_the_type(self):
        # Défauts 4..8 : toute la plage du type (neutres 4..6), extrêmes atteints.
        sizes = {}
        for s in range(1, 201):
            for p in self.plan(s):
                sizes.setdefault(p.type, set()).add(len(lua_list(p.members)))
        self.assertEqual(sizes['settlers'], set(range(4, 9)))
        self.assertEqual(sizes['raiders'], set(range(4, 9)))
        self.assertEqual(sizes['neutrals'], set(range(4, 7)))
        # 5..6 : intersection.
        self.opt('GroupSizeMin', 5)
        self.opt('GroupSizeMax', 6)
        self.assertEqual({len(lua_list(p.members)) for s in range(1, 81) for p in self.plan(s)}, {5, 6})
        # 7..8 avec des neutres seulement (4..6) : intersection vide -> 6 membres, avertissement.
        self.opt('GroupSizeMin', 7)
        self.opt('GroupSizeMax', 8)
        self.opt('WeightSettlers', 0)
        self.opt('WeightRaiders', 0)
        self.assertEqual({len(lua_list(p.members)) for p in self.plan(3)}, {6})
        self.assertTrue(any('group size options 7..8 outside the size 4..6 of type neutrals, 6 member(s)' in line
                            for line in self.logs('WARN')))

    def test_profile_max_and_role_weights_over_many_groups(self):
        roles, over = {}, []
        for s in range(1, 151):
            for p in self.plan(s):
                d = self.type_def(p.type)
                counts = {}
                for m in lua_list(p.members):
                    counts[m.profile] = counts.get(m.profile, 0) + 1
                    roles.setdefault(p.type, {}).setdefault(m.role, 0)
                    roles[p.type][m.role] += 1
                over += [(p.type, q.id) for q in lua_list(d.profiles) if q.max and counts.get(q.id, 0) > q.max]
        self.assertEqual(over, [])
        # Rôles fréquents d'abord (poids du type) : ouvriers et combattants chez les colons, combattants chez les
        # pillards, plus que les adjoints (poids 1, max 1).
        self.assertGreater(roles['settlers']['worker'], roles['settlers']['deputy'])
        self.assertGreater(roles['raiders']['fighter'], roles['raiders']['worker'])

    def test_bad_or_missing_options_use_defaults_with_a_warning(self):
        self.opt('GroupCount', 9)
        self.opt('GroupSizeMin', 4.5)
        self.rt.execute('JAVA_OPTIONS["LivingKnox.WeightRaiders"] = nil')
        s = self.ev('LivingKnox.Config.population()')
        self.assertEqual((s.count, s.sizeMin, s.weights.raiders), (4, 4, 35))
        warns = self.logs('WARN')
        self.assertIn('[LivingKnox] WARN option LivingKnox.GroupCount = 9 is not an integer from 3 to 5, '
                      'default 4 used', warns)
        self.assertIn('[LivingKnox] WARN option LivingKnox.GroupSizeMin = 4.5 is not an integer from 4 to 8, '
                      'default 4 used', warns)
        self.assertIn('[LivingKnox] WARN option LivingKnox.WeightRaiders missing, default 35 used', warns)
        # SandboxVars en repli (option Java absente).
        self.rt.execute('SandboxVars = { LivingKnox = { WeightRaiders = 12 } }')
        self.assertEqual(self.ev('LivingKnox.Config.population().weights.raiders'), 12)
        # min > max : les deux valeurs par défaut.
        self.opt('GroupSizeMin', 8)
        self.opt('GroupSizeMax', 5)
        s = self.ev('LivingKnox.Config.population()')
        self.assertEqual((s.sizeMin, s.sizeMax), (4, 8))
        self.assertIn('[LivingKnox] WARN options LivingKnox.GroupSizeMin = 8 > GroupSizeMax = 5, defaults 4..8 used',
                      self.logs('WARN'))

    def test_relief_delay_is_read_and_bounded_but_unused(self):
        s = self.ev('LivingKnox.Config.population()')
        self.assertEqual((s.reliefMin, s.reliefMax), (2, 5))
        self.opt('ReliefDaysMin', 3)
        self.opt('ReliefDaysMax', 4)
        s = self.ev('LivingKnox.Config.population()')
        self.assertEqual((s.reliefMin, s.reliefMax), (3, 4))
        self.opt('ReliefDaysMax', 6)
        self.assertEqual(self.ev('LivingKnox.Config.population().reliefMax'), 5)
        # Stocké seulement : la population n'en dépend pas (relève LK09-T04).
        self.opt('ReliefDaysMax', 5)
        a = [p.type for p in self.plan(8)]
        self.opt('ReliefDaysMin', 5)
        self.assertEqual([p.type for p in self.plan(8)], a)

    def test_unregistered_type_weight_and_no_drawable_type(self):
        self.rt.execute('LivingKnox.GroupTypes.state.types.neutrals = nil')
        self.opt('WeightSettlers', 0)
        self.opt('WeightRaiders', 0)
        ids, why = self.run_pop()
        self.assertIsNone(ids)
        self.assertEqual(why, 'no group type can be drawn')
        self.assertIn('[LivingKnox] WARN population: group type neutrals has a weight but is not registered: '
                      'never drawn', self.logs('WARN'))
        self.assertIn('[LivingKnox] ERROR population: no group type can be drawn; no group created', self.logs('ERROR'))
        self.assertEqual(self.groups(), [])
        self.assertIsNone(self.data().populated)   # rien créé : nouvelle tentative au prochain démarrage


class OnceTests(Bench):
    def test_no_second_population_after_restart(self):
        self.run_pop()
        first = self.ev(CANON)
        self.restart()
        ids, _ = self.run_pop(seed=4321)
        self.assertEqual(lua_list(ids), [])
        self.assertEqual(self.ev(CANON), first)
        self.assertIn('[LivingKnox] INFO population: group registry already populated, nothing created', self.logs())

    def test_never_repopulated_even_when_every_group_is_gone(self):
        self.run_pop()
        for gid in lua_list(self.g.LivingKnox.Groups.list()):
            self.ev(f'LivingKnox.Groups.remove("{gid}")')
        self.restart()
        self.assertEqual(lua_list(self.run_pop()[0]), [])
        self.assertEqual(self.groups(), [])

    def test_legacy_registry_with_groups_is_left_alone(self):
        # Registre d'avant LK08-T05 (sans drapeau) qui a déjà eu un groupe : jamais peuplé, rien écrit.
        self.ev('LivingKnox.Groups.create({ type = "settlers", name = "Old" })')
        self.rt.execute('LivingKnox.Groups.state.data.populated = nil')
        self.ev('LivingKnox.Groups.save()')
        seq = self.ev('LivingKnox.Groups.state.seq')
        self.restart()
        self.assertEqual(lua_list(self.run_pop()[0]), [])
        self.assertEqual(len(self.groups()), 1)
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq)

    def test_populated_flag_survives_and_bad_flag_counts_as_done(self):
        self.rt.execute('LivingKnox.Groups.state.data.populated = 1')
        data, _ = self.ev('return LivingKnox.Groups.validate(LivingKnox.Groups.state.data)')
        self.assertIs(data.populated, True)
        self.assertEqual(lua_list(self.run_pop()[0]), [])

    def test_new_world_gets_a_new_population(self):
        self.run_pop()
        self.restart(new_world=True)            # ancien fichier du même nom, monde neuf
        ids, _ = self.run_pop(seed=5)
        self.assertEqual(lua_list(ids), ['grp-1', 'grp-2', 'grp-3', 'grp-4'])

    def test_blocked_registry_creates_nothing(self):
        self.rt.execute('LivingKnox.Groups.state.blocked = true')
        self.assertEqual(self.run_pop(), (None, 'group registry not ready'))

    def test_site_failure_leaves_the_group_without_home(self):
        self.rt.execute('getWorld = function() return { getMetaGrid = function() return nil end, '
                        'getWorld = function() return "rstest-sites" end, getGameMode = function() return "Sandbox" end } end')
        ids, _ = self.run_pop()
        self.assertEqual(len(lua_list(ids)), 4)
        self.assertTrue(all(g.home is None for g in self.groups()))
        self.assertEqual(sum('has no home: no metagrid' in line for line in self.logs('WARN')), 4)
        self.assertTrue(any('home none' in line for line in self.logs('INFO')))

    def test_member_extras_validated_at_load(self):
        self.run_pop()
        gid = self.groups()[0].id
        for field, value in (('profile', '"Bad-Id"'), ('female', '"yes"'), ('traits', '{}'), ('traits', '{ 3 }')):
            with self.subTest(field=field, value=value):
                code = (f'local d = LivingKnox.Groups.copy(LivingKnox.Groups.state.data) '
                        f'd.groups["{gid}"].members["m-1"].{field} = {value} '
                        f'local out, dropped = LivingKnox.Groups.validate(d) return #dropped, dropped[1] and dropped[1].why')
                n, why = self.ev(code)
                self.assertEqual(n, 1)
                self.assertTrue(why.startswith('member m-1: bad '), why)
        n = self.ev(f'local d = LivingKnox.Groups.copy(LivingKnox.Groups.state.data) '
                    f'd.groups["{gid}"].storySeed = -1 local _, dropped = LivingKnox.Groups.validate(d) '
                    f'return dropped[1].why')
        self.assertEqual(n, 'bad story seed')


class ClientTests(unittest.TestCase):
    def test_client_never_populates(self):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.globals().next = None
        rt.execute(DOUBLES)
        rt.execute(SANDBOX + option_defaults())
        rt.execute('SIDE = "client"')
        paths = [MOD_LUA / 'shared', MOD_LUA / 'server']
        rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
        for name in SHARED:
            rt.execute(f'require "{name}"')
        rt.execute('require "LivingKnox/LK_Population"')
        self.assertIsNone(rt.eval('LivingKnox.Population'))
        self.assertIsNone(rt.eval('LivingKnox.Groups'))


# Accroches de LK_Server.lua dans le banc tests/harness.py ---------------------------------------------------------

HWORLD = r'''
WORLD_NAME, GAME_MODE = 'rstest_population', 'Multiplayer'
getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end,
             getMetaGrid = function() return nil end }
end
'''
HSHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
           'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
           'shared/LivingKnox/Data/LK_Type_settlers.lua')
HSERVER = 'server/LivingKnox/LK_Server.lua'
HCANON = CANON[len('return '):]


class EventTests(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = self.make()

    def tearDown(self):
        self.h.close()

    def make(self, root=None):
        h = Harness(mode=self.mode, root=root)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        self.machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in self.machines:
            h.load(m, HWORLD)
            h.load(m, SANDBOX + option_defaults())
            for path in HSHARED:
                h.load(m, path)
            h.load(m, HSERVER)
        return h

    def restart(self):
        self.h.load(self.srv, 'if LivingKnox.Groups and LivingKnox.Groups.flush then LivingKnox.Groups.flush() end')  # arrêt propre : écriture différée faite (LK13-T06)
        root, age = self.h.root, self.h.age_minutes
        self.h._tmp = None
        self.h.close()
        self.h = self.make(root=root)
        self.h.age_minutes = age
        self.h._push_clock()
        self.addCleanup(shutil.rmtree, root, True)

    def start_event(self):
        return 'OnGameStart' if self.mode == 'solo' else 'OnServerStarted'

    def count(self):
        return self.h.eval(self.srv, '#LivingKnox.Groups.list()')

    def test_population_at_start_once_and_never_on_clients(self):
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.assertEqual(self.count(), 0)
        self.h.fire(self.srv, 'EveryHours')                  # avant le démarrage : rien
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.count(), 0)
        self.h.fire(self.srv, self.start_event())
        self.assertEqual(self.count(), 4)
        canon = self.h.eval(self.srv, HCANON)
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.h.fire(self.srv, self.start_event())
        self.assertEqual(self.h.eval(self.srv, HCANON), canon)
        if self.mode == 'mp':
            for c in ('A', 'B'):
                self.h.fire(c, 'OnInitGlobalModData', True)
                self.h.fire(c, 'OnGameStart')
                self.h.fire(c, 'EveryHours')
                self.h.load(c, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
                self.assertIsNone(self.h.eval(c, 'LivingKnox.Population'))
                self.assertIsNone(self.h.eval(c, 'LivingKnox.Groups'))
        # Redémarrage : même registre, aucune seconde population.
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.h.fire(self.srv, self.start_event())
        self.h.advance(60)
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.count(), 4)
        self.assertEqual(self.h.eval(self.srv, 'LivingKnox.Groups.state.data.populated'), True)
        self.assertTrue(any('population: group registry already populated, nothing created' in line
                            for line in self.h.logs(self.srv)))
        self.assertEqual(self.h.errors(self.srv), [])

    def test_disabled_engine_waits_then_populates_at_the_next_hour(self):
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.h.load(self.srv, 'JAVA_OPTIONS["LivingKnox.Enabled"] = false')
        self.h.fire(self.srv, self.start_event())
        self.assertEqual(self.count(), 0)
        self.h.load(self.srv, 'JAVA_OPTIONS["LivingKnox.Enabled"] = true')
        self.h.advance(60)
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.count(), 4)

    def test_lazy_registry_after_a_lua_reset(self):
        # Démarrage sans OnInitGlobalModData (rechargement Lua) : rien au démarrage, population au premier EveryHours.
        self.h.fire(self.srv, self.start_event())
        self.assertEqual(self.count(), 0)
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.count(), 4)


class SoloEventTests(EventTests):
    mode = 'solo'


# Fichiers ---------------------------------------------------------------------------------------------------------

def parse_options(text: str) -> dict[str, dict[str, str]]:
    out = {}
    for name, body in re.findall(r'option\s+(\S+)\s*\{(.*?)\}', text, flags=re.S):
        out[name] = dict(re.findall(r'(\w+)\s*=\s*([^,\n]+),', body))
    return out


class FileTests(unittest.TestCase):
    def test_sandbox_options_match_config_and_translations(self):
        text = SANDBOX_FILE.read_text(encoding='utf-8')
        self.assertTrue(text.startswith('VERSION = 1,'))
        options = parse_options(text)
        en = json.loads((MOD_LUA / 'shared/Translate/EN/Sandbox.json').read_text(encoding='utf-8'))
        fr = json.loads((MOD_LUA / 'shared/Translate/FR/Sandbox.json').read_text(encoding='utf-8'))
        config = (MOD_LUA / 'shared/LivingKnox/LK_Config.lua').read_text(encoding='utf-8')
        for name, (lo, hi, default) in OPTIONS.items():
            with self.subTest(option=name):
                o = options[f'LivingKnox.{name}']
                self.assertEqual(o, {'type': 'integer', 'min': str(lo), 'max': str(hi), 'default': str(default),
                                     'page': 'LivingKnox', 'translation': f'LivingKnox_{name}'})
                self.assertRegex(config, rf'\n    {name} = {default},\n')
                self.assertRegex(config, rf'\n    {name} = {{ {lo}, {hi} }},\n')
                for lang in (en, fr):
                    self.assertTrue(lang[f'Sandbox_LivingKnox_{name}'].strip())
                    self.assertTrue(lang[f'Sandbox_LivingKnox_{name}_tooltip'].strip())
                    self.assertNotIn('%', lang[f'Sandbox_LivingKnox_{name}_tooltip'])
        # Aucune option enum dans la page Living Knox.
        self.assertFalse([n for n, o in options.items() if n.startswith('LivingKnox.') and o.get('type') == 'enum'])

    def test_kahlua_constraints(self):
        code = MODULE.read_text(encoding='utf-8')
        body = '\n'.join(line.split('--')[0] for line in code.splitlines())
        self.assertTrue(all(ord(ch) < 128 for ch in body), 'non-ASCII outside comments')
        self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', body))
        self.assertIsNone(re.search(r'\bgoto\b|coroutine\.|%q', body))
        self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', body.replace('~=', '')))
        self.assertTrue(body.lstrip().startswith('if isClient() then return end'))
        for forbidden in ('ModData', 'sendServerCommand', 'getGridSquare', 'ZombRand', 'secrets'):
            self.assertNotIn(forbidden, body)

    def test_no_other_code_creates_groups(self):
        """Aucune apparition hors de la population : seul LK_Population crée des groupes de lui-même. LK_Groups
        (registre) et LK_API (API publique, appelée explicitement par un autre code) sont hors de ce contrôle."""
        callers = set()
        for path in (ROOT / 'Contents').rglob('*.lua'):
            if path.name in ('LK_Groups.lua', 'LK_API.lua'):
                continue
            body = '\n'.join(line.split('--')[0] for line in path.read_text(encoding='utf-8').splitlines())
            if re.search(r'Groups\(?\)?\.(create|applyCreate)\s*\(|\bG\.applyCreate\s*\(', body):
                callers.add(path.name)
        # E10-T04 : RS_LivingKnox.leave crée le groupe « loners » d'un PNJ qui quitte le sien (décision du LLM revalidée
        # par le serveur, jamais une apparition : aucun nouveau PNJ, aucun tirage de la population).
        self.assertEqual(callers, {'LK_Population.lua', 'RS_LivingKnox.lua'})


if __name__ == '__main__':
    unittest.main(verbosity=1)
