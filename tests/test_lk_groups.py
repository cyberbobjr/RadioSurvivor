"""Tests hors jeu du registre des groupes Living Knox (LK08-T01) : LK_Groups.lua (autorité), persistance privée.

    python RadioSurvivor/tests/test_lk_groups.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Doublures : getFileWriter / getFileReader du banc
(fidèles au Java : extension admise, troncature à l'ouverture, lignes relues sans fin de ligne), getWorld (mode et
nom de la partie, comme test_lk_bodies.py), getGameTime():getWorldAgeHours() de l'horloge du banc. Elles NE PROUVENT
PAS l'API réelle, seulement la logique du mod.
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          # LK08-T02 : types de groupes en données, exécutés par le jeu avec les autres fichiers shared.
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'

WORLD = r'''
WORLD_NAME, GAME_MODE = 'rstest_groups', 'Multiplayer'
getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end }
end
'''

# Registre canonique (RSV2 trié par clé : deux registres égaux donnent les mêmes octets).
CANON = 'require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes(LivingKnox.Groups.state.data))'


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

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]

    def file(self, slot):
        rel = self.ev(f'LivingKnox.Groups.slotPath({slot})')
        return self.h.machine(self.srv).files / rel

    def restart(self, clean=True):
        """Arrêt puis redémarrage. clean : arrêt propre, une image passe d'abord (écriture différée, LK13-T06)."""
        if clean:
            self.h.tick(1)
        root = self.h.root
        self.h._tmp = None  # le dossier de fichiers survit au « redémarrage »
        self.h.close()
        self.h = self.make(root=root)
        self.addCleanup(shutil.rmtree, root, True)

    def write_raw(self, slot, seq, data_lua):
        """Écrit un emplacement valide (entête, somme de contrôle) contenant data_lua, comme une autre version."""
        ok = self.run_lua(f'return LivingKnox.Store.writeSlotFile(LivingKnox.Groups.slotPath({slot}), "LKGRP1", '
                          f'{seq}, {data_lua})')
        self.assertTrue(ok)

    def populate(self):
        """Deux groupes complets ; rend leurs identifiants."""
        a = self.run_lua('local g = LivingKnox.Groups.create({ type = "settlers", name = "Riverside", '
                         'story = "Farmers holding the old mill.", home = { x = 10600, y = 9400, z = 0 }, day = 3 }) '
                         'return g.id')
        b = self.run_lua('return LivingKnox.Groups.create({ type = "raiders", name = "Crows", day = 4 }).id')
        self.h.tick(1)  # LK13-T06 : une écriture par image (ici la première)
        self.run_lua(f'''
            local G = LivingKnox.Groups
            local m1 = G.addMember("{a}", {{ role = "worker", npc = "lk-1", day = 3 }})
            local m2 = G.addMember("{a}", {{ role = "fighter", npc = "lk-2", day = 3 }})
            local m3 = G.addMember("{a}", {{ role = "medic", day = 5 }})
            assert(G.setLeader("{a}", m1, 5))
            assert(G.setNeed("{a}", "food", 20) == 20)
            assert(G.addNeed("{a}", "ammo", -15) == 35)
            assert(G.setMorale("{a}", 72) == 72)
            assert(G.addLog("{a}", "raid", "Lost two crates of beans", 6))
            G.addMember("{b}", {{ role = "scout", npc = "lk-7" }})
        ''')
        self.h.tick(1)  # seconde écriture : tous les changements de l'image en une fois
        return a, b


class RegistryTests(Base):
    def test_create_members_leader_needs_and_log(self):
        self.init()
        a, b = self.populate()
        self.assertEqual((a, b), ('grp-1', 'grp-2'))
        self.assertEqual(list(self.ev('LivingKnox.Groups.list()').values()), ['grp-1', 'grp-2'])
        g = self.ev(f'LivingKnox.Groups.get("{a}")')
        self.assertEqual((g.type, g.name, g.leader, g.morale), ('settlers', 'Riverside', 'm-1', 72))
        self.assertEqual((g.needs.food, g.needs.medical, g.needs.ammo), (20, 50, 35))
        self.assertEqual((g.home.x, g.home.y, g.home.z), (10600, 9400, 0))
        self.assertEqual(g.members['m-2'].npc, 'lk-2')
        self.assertIsNone(g.members['m-3'].npc)
        kinds = [(e.day, e.kind, e.text) for e in g.log.values()]
        self.assertEqual(kinds, [(3, 'founded', ''), (3, 'joined', 'm-1'), (3, 'joined', 'm-2'), (5, 'joined', 'm-3'),
                                 (5, 'leader', 'm-1'), (6, 'raid', 'Lost two crates of beans')])
        # Lecture = copie : la modifier ne touche pas le registre.
        self.run_lua(f'LivingKnox.Groups.get("{a}").name = "X"')
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{a}").name'), 'Riverside')
        self.assertEqual(self.h.errors(self.srv), [])

    def test_bounds_and_refusals(self):
        self.init()
        a, _ = self.populate()
        G = 'LivingKnox.Groups'
        self.assertEqual(self.ev(f'{G}.setNeed("{a}", "medical", 140)'), 100)
        self.assertEqual(self.ev(f'{G}.setNeed("{a}", "medical", -3)'), 0)
        self.assertEqual(self.ev(f'{G}.setMorale("{a}", 41.6)'), 42)
        self.assertEqual(self.ev(f'{G}.addMorale("{a}", 500)'), 100)
        refusals = {
            f'{G}.create({{ type = "pirates", name = "P" }})': 'unknown type pirates',
            f'{G}.create({{ type = "settlers", name = "" }})': 'bad name',
            f'{G}.create({{ type = "settlers", name = "{"x" * 65}" }})': 'bad name',
            f'{G}.create({{ type = "settlers", name = "S", home = {{ x = 1.5, y = 2, z = 0 }} }})': 'bad home',
            f'{G}.create({{ type = "settlers", name = "S", home = {{ x = 1, y = 2, z = 40 }} }})': 'bad home',
            f'{G}.addMember("{a}", {{ role = "king" }})': 'unknown role king',
            f'{G}.addMember("{a}", {{ role = "worker", npc = "lk-1" }})': 'npc lk-1 already in group grp-1',
            f'{G}.addMember("{a}", {{ role = "worker", npc = "bob" }})': 'bad npc reference',
            f'{G}.addMember("grp-9", {{ role = "worker" }})': 'unknown group grp-9',
            f'{G}.setNeed("{a}", "water", 3)': 'unknown need water',
            f'{G}.setLeader("{a}", "m-9")': 'unknown member m-9 in grp-1',
            f'{G}.addLog("{a}", "bad kind!", "x")': 'bad log kind',
            f'{G}.setHome("{a}", 1, 2)': 'bad home',
        }
        for call, why in refusals.items():
            result = self.run_lua(f'return {call}')
            self.assertEqual(result, (None, why), call)
        self.assertEqual(self.ev(f'#{G}.list()'), 2)  # aucune création ratée n'a consommé de place

    def test_log_is_bounded_and_text_truncated(self):
        self.init()
        a = self.ev('LivingKnox.Groups.create({ type = "neutrals", name = "Traders", day = 1 }).id')
        size = self.ev('LivingKnox.Groups.LOG_SIZE')
        self.run_lua(f'for i = 1, {size + 5} do assert(LivingKnox.Groups.addLog("{a}", "tick", "entry " .. i, i)) end')
        log = list(self.ev(f'LivingKnox.Groups.get("{a}").log').values())
        self.assertEqual(len(log), size)
        self.assertEqual((log[0].text, log[-1].text), ('entry 6', f'entry {size + 5}'))
        self.run_lua(f'LivingKnox.Groups.addLog("{a}", "long", string.rep("y", 300))')
        self.assertEqual(self.ev(f'#LivingKnox.Groups.get("{a}").log[{size}].text'), 200)

    def test_day_from_world_age(self):
        self.init()
        self.run_lua('HARNESS.clock.ageHours = 2')
        self.assertEqual(self.ev('LivingKnox.Groups.today()'), 1)
        self.run_lua('HARNESS.clock.ageHours = 50')
        self.assertEqual(self.ev('LivingKnox.Groups.today()'), 3)
        a = self.ev('LivingKnox.Groups.create({ type = "settlers", name = "S" }).id')
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{a}").founded'), 3)

    def test_succession_rule(self):
        self.init()
        a = self.ev('LivingKnox.Groups.create({ type = "settlers", name = "S" }).id')
        G = 'LivingKnox.Groups'
        self.run_lua(f'''
            for _, role in ipairs({{ "worker", "medic", "fighter", "fighter", "deputy" }}) do
                {G}.addMember("{a}", {{ role = role }})
            end
            {G}.setLeader("{a}", "m-1")
        ''')
        # Rôle prioritaire (deputy) d'abord.
        self.assertEqual(self.ev(f'{G}.successor("{a}")'), 'm-5')
        self.assertEqual(self.ev(f'{G}.markDead("{a}", "m-1")'), True)
        self.assertIsNone(self.ev(f'{G}.get("{a}").leader'))  # chef mort : plus de chef, aucune succession seule
        self.assertEqual(self.ev(f'{G}.succeed("{a}")'), 'm-5')
        # Le chef n'est pas son propre successeur ; à rôle égal, le plus ancien (m-3 avant m-4).
        self.assertEqual(self.ev(f'{G}.successor("{a}")'), 'm-3')
        self.run_lua(f'{G}.markDead("{a}", "m-5"); {G}.markDead("{a}", "m-3")')
        self.assertEqual(self.ev(f'{G}.succeed("{a}")'), 'm-4')
        self.assertEqual(self.run_lua(f'return {G}.setLeader("{a}", "m-3")'), (None, 'member m-3 is dead'))
        self.run_lua(f'{G}.removeMember("{a}", "m-4"); {G}.markDead("{a}", "m-2")')
        self.assertIsNone(self.ev(f'{G}.get("{a}").leader'))
        self.assertEqual(self.run_lua(f'return {G}.succeed("{a}")'), (None, 'no living member'))
        log = [e.kind for e in self.ev(f'{G}.get("{a}").log').values()]
        self.assertIn('died', log)
        self.assertIn('left', log)

    def test_member_death_is_published_with_the_members_at_home(self):
        """E08-T07 : mort hors écran = fait memberDied, témoins = PNJ des membres vivants au foyer."""
        self.init()
        a, _ = self.populate()
        self.run_lua(f'''
            PUB = {{}}
            LivingKnox.listen("memberDied", "test", function(i) PUB[#PUB + 1] = i end)
            local G = LivingKnox.Groups
            G.addMember("{a}", {{ role = "scout", npc = "lk-3", day = 5 }})
            assert(G.markDead("{a}", "m-3", 7))
            assert(G.update(function(data)
                data.groups["{a}"].expedition = {{ place = "houses", team = {{ "m-2" }}, departed = 1, returns = 9 }}
                return true
            end))
            assert(G.markDead("{a}", "m-1", 8))
            assert(G.markDead("{a}", "m-1", 8))
        ''')
        pub = [self.ev(f'PUB[{i}]') for i in (1, 2)]
        self.assertEqual(self.ev('#PUB'), 2, 'a second markDead of a dead member is not a new death')
        first, second = pub
        self.assertEqual((first.group, first.member, first.npc, first.day, first.offscreen, first.x, first.y),
                         (a, 'm-3', None, 7, True, 10600, 9400))
        self.assertEqual(list(first.witnesses.values()), ['lk-1', 'lk-2', 'lk-3'])
        self.assertEqual((second.member, second.npc, second.day), ('m-1', 'lk-1', 8))
        self.assertEqual(list(second.witnesses.values()), ['lk-3'], 'expedition team and the dead are not witnesses')
        self.assertEqual(self.h.errors(self.srv), [])

    def test_remove_group_never_reuses_its_number(self):
        self.init()
        a, b = self.populate()
        self.assertTrue(self.ev(f'LivingKnox.Groups.remove("{a}")'))
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{a}")'), (None, 'unknown group grp-1'))
        self.assertEqual(self.ev('LivingKnox.Groups.create({ type = "settlers", name = "New" }).id'), 'grp-3')
        # Le PNJ du groupe supprimé redevient libre.
        self.assertEqual(self.ev('LivingKnox.Groups.addMember("grp-3", { role = "worker", npc = "lk-1" })'), 'm-1')
        self.assertEqual(self.run_lua('return LivingKnox.Groups.findNpc("lk-1")'), ('grp-3', 'm-1'))


class PersistenceTests(Base):
    def test_restart_without_loss(self):
        self.init()
        self.populate()
        before = self.ev(CANON)
        seq = self.ev('LivingKnox.Groups.state.seq')
        self.assertEqual(seq, 2)  # LK13-T06 : une écriture par image (deux images), plus une par changement
        self.restart()
        self.init()
        self.assertEqual(self.ev(CANON), before)
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq)
        self.assertEqual(self.ev('LivingKnox.Groups.create({ type = "neutrals", name = "N" }).id'), 'grp-3')
        self.assertTrue(any('groups loaded: 2 group(s), 0 dropped' in line for line in self.lk()))
        self.assertEqual(self.h.errors(self.srv), [])

    def test_lazy_load_after_a_lua_reset(self):
        self.init()
        self.populate()
        before = self.ev(CANON)
        self.restart()  # aucun OnInitGlobalModData : rattrapage au premier usage
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 2)
        self.assertEqual(self.ev(CANON), before)

    def test_invalid_groups_dropped_others_kept_and_file_kept(self):
        self.init()
        good = ('["grp-1"] = { id = "grp-1", type = "settlers", name = "Good", story = "", founded = 1, '
                'nextMember = 3, leader = "m-1", members = { ["m-1"] = { id = "m-1", role = "worker", alive = true, '
                'npc = "lk-4" }, ["m-2"] = { id = "m-2", role = "medic", alive = false } }, '
                'needs = { food = 1, medical = 2, ammo = 3 }, morale = 4, log = { { day = 1, kind = "founded", '
                'text = "" } } }')
        def variant(gid, **changes):
            text = good.replace('grp-1', gid)
            for old, new in changes.items():
                text = text.replace(old.replace('_', ' '), new)
            return text
        bad = {
            'grp-2': variant('grp-2', **{'leader = "m-1"': 'leader = "m-2"'}),           # chef mort
            'grp-3': variant('grp-3', **{'type = "settlers"': 'type = "pirates"'}),        # type inconnu
            'grp-4': variant('grp-4', **{'morale = 4': 'morale = 101'}),                   # borne
            'grp-5': variant('grp-5', **{'food = 1': 'food = 1.5'}),                       # entier
            'grp-6': variant('grp-6', **{'nextMember = 3': 'nextMember = 2'}),             # identifiant de membre
            'grp-7': variant('grp-7', **{'role = "medic"': 'role = "king"'}),              # rôle inconnu
            'grp-8': variant('grp-8', **{'kind = "founded"': 'kind = "bad kind"'}),        # journal
            'grp-9': variant('grp-9'),                                                     # PNJ lk-4 déjà dans grp-1
            'grp-10': variant('grp-10', **{'id = "grp-10"': 'id = "grp-11"'}),             # clé et id différents
        }
        ok2 = variant('grp-12', **{'npc = "lk-4"': 'npc = "lk-5"'})
        body = ', '.join([good, ok2] + list(bad.values()))
        self.write_raw(1, 7, f'{{ schema = 1, nextId = 20, groups = {{ {body} }} }}')
        raw = self.file(1).read_bytes()
        self.restart()
        self.init()
        self.assertTrue(self.ev('LivingKnox.Groups.isReady()'))
        self.assertEqual(list(self.ev('LivingKnox.Groups.list()').values()), ['grp-1', 'grp-12'])
        dropped = [line for line in self.lk() if 'dropped at load' in line]
        self.assertEqual(len(dropped), len(bad), dropped)
        for gid in bad:
            self.assertTrue(any(f'ERROR group {gid} dropped at load (file #7)' in line for line in dropped), gid)
        self.assertTrue(any('leader is dead' in line for line in dropped))
        self.assertTrue(any('npc lk-4 already in group grp-1' in line for line in dropped))
        self.assertEqual(self.file(1).read_bytes(), raw)  # rien réécrit au chargement
        # Écriture suivante : dans l'autre emplacement, le fichier d'origine reste lisible pour une récupération.
        self.assertEqual(self.ev('LivingKnox.Groups.create({ type = "settlers", name = "N" }).id'), 'grp-20')
        self.h.tick(1)
        self.assertEqual(self.file(1).read_bytes(), raw)
        self.assertTrue(self.file(0).read_text(encoding='utf-8').startswith('LKGRP1=8\n'))

    def test_future_schema_refused_without_overwrite(self):
        self.init()
        self.write_raw(0, 3, '{ schema = 2, nextId = 1, groups = {} }')
        raw = self.file(0).read_bytes()
        self.restart()
        self.init()
        self.assertFalse(self.ev('LivingKnox.Groups.isReady()'))
        self.assertEqual(self.run_lua('return LivingKnox.Groups.isBlocked()'),
                         (True, 'unknown group registry schema 2 (this version reads 1)'))
        self.assertEqual(self.run_lua('return LivingKnox.Groups.create({ type = "settlers", name = "S" })'),
                         (None, 'group registry not ready'))
        self.assertFalse(self.ev('LivingKnox.Groups.save()'))
        self.assertEqual(dict(self.ev('LivingKnox.Groups.list()')), {})
        self.assertEqual(self.file(0).read_bytes(), raw)
        self.assertFalse(self.file(1).exists())
        self.assertTrue(any('ERROR group registry BLOCKED: unknown group registry schema 2' in line
                            for line in self.lk()))

    def test_bad_structure_blocks(self):
        self.init()
        self.write_raw(0, 3, '{ schema = 1, nextId = 0, groups = {} }')
        self.restart()
        self.init()
        self.assertEqual(self.run_lua('return LivingKnox.Groups.isBlocked()'),
                         (True, 'group registry file #3 is invalid: bad nextId'))

    def test_corrupted_slots(self):
        self.init()
        self.populate()
        before = self.ev(CANON)
        seq = self.ev('LivingKnox.Groups.state.seq')
        newest = self.file(seq % 2)
        text = newest.read_text(encoding='utf-8').splitlines()
        text[2] = '0'  # mauvaise somme de contrôle
        newest.write_text('\n'.join(text) + '\n', encoding='utf-8')
        self.restart()
        self.init()
        # Emplacement le plus récent illisible : l'autre (une écriture plus tôt) est relu.
        self.assertTrue(self.ev('LivingKnox.Groups.isReady()'))
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq - 1)
        self.assertNotEqual(self.ev(CANON), before)
        other = self.file((seq - 1) % 2)
        other.write_text('LKGRP1=1\nzz\n0\nend\n', encoding='utf-8')
        self.restart()
        self.init()
        self.assertEqual(self.run_lua('return LivingKnox.Groups.isBlocked()'),
                         (True, 'both group registry files are unreadable'))

    def test_new_world_starts_empty_and_wins(self):
        self.init()
        self.populate()
        seq = self.ev('LivingKnox.Groups.state.seq')
        self.restart()
        self.init(new_world=True)
        self.assertEqual(dict(self.ev('LivingKnox.Groups.list()')), {})
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq + 1)
        self.restart()
        self.init()
        self.assertEqual(dict(self.ev('LivingKnox.Groups.list()')), {})
        self.assertEqual(self.ev('LivingKnox.Groups.create({ type = "settlers", name = "S" }).id'), 'grp-1')

    def test_registry_files_are_separate_and_no_global_moddata(self):
        # Toute lecture de la ModData globale est relevée (aucune n'est attendue).
        self.run_lua('MODDATA_USED = {}; ModData = setmetatable({}, { __index = function(_, k) '
                     'MODDATA_USED[#MODDATA_USED + 1] = k; return function() return nil end end })')
        self.init()
        self.populate()
        names = sorted(p.name for p in self.file(0).parent.iterdir())
        self.assertTrue(all(n.startswith('groups-') or n.startswith('registry-') for n in names), names)
        self.assertTrue(any(n.startswith('groups-') for n in names))
        self.assertEqual(self.ev('#MODDATA_USED'), 0)

    def test_dedicated_server_restart_keeps_the_registry(self):
        """Run 20261015-043927 : sur un serveur dédié, OnInitGlobalModData reçoit TOUJOURS vrai (WorldDictionary.isNewGame
        jamais posé hors GameLoadingState, WorldDictionary.java:526, GameLoadingState.java:253) ; le monde neuf se lit
        par le second argument d'OnLoadRadioScripts (ZomboidRadio.java:246), déclenché juste avant (IsoWorld.java:1905).
        Doublure fidèle : relance = OnLoadRadioScripts(_, false) puis OnInitGlobalModData(true)."""
        self.h.fire(self.srv, 'OnLoadRadioScripts', None, True)
        self.init(new_world=True)
        self.populate()
        before = self.ev(CANON)
        self.restart()
        self.h.fire(self.srv, 'OnLoadRadioScripts', None, False)
        self.init(new_world=True)
        self.assertEqual(self.ev(CANON), before)
        self.assertFalse(any('new world' in line for line in self.lk()))
        # Monde effacé puis recréé sous le même nom : la radio dit « neuf », registre vide.
        self.restart()
        self.h.fire(self.srv, 'OnLoadRadioScripts', None, True)
        self.init(new_world=True)
        self.assertEqual(dict(self.ev('LivingKnox.Groups.list()')), {})
        self.assertEqual(self.h.errors(self.srv), [])


class ClientTests(Base):
    def test_mp_client_has_no_group_registry(self):
        self.init()
        self.populate()
        for client in ('A', 'B'):
            self.assertIsNone(self.ev('LivingKnox.Groups', client))
            self.assertIsNone(self.ev('LivingKnox.handlers["OnInitGlobalModData/Groups.init"]', client))
            self.h.fire(client, 'OnInitGlobalModData', False)
            files = self.h.machine(client).files
            self.assertEqual([p for p in files.rglob('groups-*')], [], client)
            self.assertEqual(self.h.errors(client), [])


class SoloTests(Base):
    mode = 'solo'

    def test_solo_registry_survives_a_restart(self):
        self.init()
        self.populate()
        before = self.ev(CANON)
        self.restart()
        self.init()
        self.assertEqual(self.ev(CANON), before)
        self.assertEqual(self.h.errors(self.srv), [])


# LK13-T06 : écriture regroupée du registre des groupes.
READS = ('READS = 0 local orig = LivingKnox.Store.readSlotFile '
         'LivingKnox.Store.readSlotFile = function(...) READS = READS + 1 return orig(...) end')


class DeferredWriteTests(Base):
    def seq(self):
        return self.ev('LivingKnox.Groups.state.seq')

    def file_seq(self, slot):
        path = self.file(slot)
        if not path.exists():
            return None
        return int(path.read_text(encoding='utf-8').split('\n')[0].split('=')[1])

    def test_changes_of_a_frame_written_once_at_its_end(self):
        self.init()
        gid = self.run_lua('return LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }).id')
        self.run_lua(f'local G = LivingKnox.Groups for i = 1, 5 do assert(G.addMember("{gid}", {{ role = "worker" }})) end '
                     f'assert(G.setMorale("{gid}", 70)) assert(G.addLog("{gid}", "raid", "x"))')
        self.assertEqual(self.seq(), 0)                       # rien écrit avant la fin de l'image
        self.assertTrue(self.ev('LivingKnox.Groups.isDirty()'))
        self.assertFalse(self.file(0).exists() or self.file(1).exists())
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)                       # huit changements, une écriture
        self.assertFalse(self.ev('LivingKnox.Groups.isDirty()'))
        self.assertEqual(self.file_seq(1), 1)
        self.h.tick(3)
        self.assertEqual(self.seq(), 1)                       # rien de changé : rien écrit
        before = self.ev(CANON)
        self.restart()
        self.init()
        self.assertEqual(self.ev(CANON), before)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_changes_made_by_a_later_ontick_subscriber_written_in_the_same_frame(self):
        self.init()
        gid = self.run_lua('return LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }).id')
        # Abonné inscrit après LK_Groups, au chargement (comme LK_Bodies, LK_Decisions) : au premier
        # OnTickEvenPaused, l'écriture de fin d'image passe derrière lui.
        self.run_lua(f'N = 0 Events.OnTick.Add(function() N = N + 1 '
                     f'assert(LivingKnox.Groups.setMorale("{gid}", 10 + N)) end)')
        self.h.tick(1)
        self.assertEqual((self.seq(), self.ev('LivingKnox.Groups.isDirty()')), (1, False))
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").morale'), 11)
        self.h.tick(2)
        self.assertEqual(self.seq(), 3)                       # une écriture par image, jamais deux
        self.assertEqual(self.file_seq(1), 3)
        # Abonné ajouté plus tard (après le premier passage) : son changement part à l'image suivante, une seule fois.
        self.run_lua(f'Events.OnTick.Add(function() assert(LivingKnox.Groups.addLog("{gid}", "late", "x")) end)')
        self.h.tick(2)
        self.assertEqual(self.seq(), 5)
        self.assertTrue(self.ev('LivingKnox.Groups.isDirty()'))

    def test_paused_server_writes_at_the_next_frame_start(self):
        self.init()
        self.h.set_paused(self.srv, True)                     # serveur vide en pause : OnTickEvenPaused seul
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.h.tick(1)
        self.assertEqual(self.seq(), 0)                       # une image entière passe d'abord
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)
        self.assertFalse(self.ev('LivingKnox.Groups.isDirty()'))

    def test_flush_writes_now_and_is_idempotent(self):
        self.init()
        self.assertTrue(self.ev('LivingKnox.Groups.flush()'))         # rien en attente : à jour
        self.assertEqual(self.seq(), 0)
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.assertTrue(self.ev('LivingKnox.Groups.flush()'))
        self.assertEqual((self.seq(), self.file_seq(1)), (1, 1))
        self.assertTrue(self.ev('LivingKnox.Groups.flush()'))
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)

    def test_readback_only_at_the_first_write_of_the_session_and_on_demand(self):
        self.init()
        self.run_lua(READS)
        for i in range(3):
            self.run_lua(f'assert(LivingKnox.Groups.create({{ type = "settlers", name = "G{i}", day = 1 }}))')
            self.h.tick(1)
        self.assertEqual((self.seq(), self.ev('READS')), (3, 1))     # relue la première fois seulement
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "G9", day = 1 }))')
        self.assertTrue(self.ev('LivingKnox.Groups.flush({ verify = true })'))
        self.assertEqual(self.ev('READS'), 2)
        self.assertTrue(self.ev('LivingKnox.Groups.verifyFile()'))
        self.assertEqual(self.ev('READS'), 3)
        # Fichier changé derrière le moteur : la relecture demandée bloque le registre, comme une écriture fausse.
        self.file(self.seq() % 2).write_text('LKGRP1=1\nzz\n0\nend\n', encoding='utf-8')
        self.assertEqual(self.run_lua('return LivingKnox.Groups.verifyFile()'), (False, 'write verification failed'))
        self.assertTrue(self.ev('LivingKnox.Groups.isBlocked()'))
        self.assertTrue(any('BLOCKED: group registry write verification failed' in line for line in self.lk()))

    def test_a_refused_deferred_write_blocks_the_registry_and_keeps_the_files(self):
        self.init()
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.h.tick(1)
        raw = self.file(1).read_bytes()
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Hill", day = 1 })) '
                     'getFileWriter = function() return nil end')
        self.h.tick(1)
        self.assertEqual(self.run_lua('return LivingKnox.Groups.isBlocked()')[0], True)
        self.assertEqual(self.run_lua('return LivingKnox.Groups.create({ type = "settlers", name = "X" })'),
                         (None, 'group registry not ready'))
        self.assertEqual(self.file(1).read_bytes(), raw)
        self.assertFalse(self.file(0).exists())

    def test_reload_writes_the_pending_changes_first(self):
        self.init()
        gid = self.run_lua('return LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }).id')
        before = self.ev(CANON)
        self.run_lua('LivingKnox.Groups.state.data = nil')     # remise à zéro du Lua, comme les bancs
        self.assertTrue(self.ev('LivingKnox.Groups.ensure()'))
        self.assertEqual(self.ev(CANON), before)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").name'), 'Mill')
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Hill", day = 1 }))')
        self.init()                                           # OnInitGlobalModData de nouveau
        self.assertEqual(len(self.ev('LivingKnox.Groups.list()')), 2)

    def test_unclean_stop_loses_only_the_unfinished_frame(self):
        self.init()
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.h.tick(1)
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Hill", day = 1 }))')
        self.restart(clean=False)                             # arrêt brutal au milieu d'une image
        self.init()
        self.assertEqual(list(self.ev('LivingKnox.Groups.list()').values()), ['grp-1'])

    def test_fast_hex_and_checksum_equal_the_codec(self):
        same = self.run_lua(
            'local C = require("RadioSurvivor/RS_Codec") local St = LivingKnox.Store math.randomseed(3) '
            'local ok = St.hexOfBytes("") == "" and St.checksumOfBytes("") == C.checksumBytes("") '
            'for n = 1, 30 do local t = {} for i = 1, n * 700 do t[i] = string.char(math.random(0, 255)) end '
            'local s = table.concat(t) ok = ok and St.hexOfBytes(s) == C.hexBytes(s) '
            'and St.checksumOfBytes(s) == C.checksumBytes(s) end return ok')
        self.assertTrue(same)
        # Fichier écrit relu par le lecteur commun (Codec) : même entête, même somme.
        self.init()
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.h.tick(2)
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Hill", day = 1 }))')
        self.h.tick(1)                                        # écriture sans relecture
        back = self.run_lua('local r = LivingKnox.Store.readSlotFile(LivingKnox.Groups.slotPath(0), "LKGRP1") '
                            'return r and r.seq, r and r.data.nextId')
        self.assertEqual(back, (2, 3))

    def test_ontick_subscriber_stays_the_same_function(self):
        self.init()
        fn = self.ev('LivingKnox.handlers["OnTick/Groups.flush"]')
        self.assertIsNotNone(fn)
        self.h.tick(2)
        self.h.server.g.SAME_A = fn
        self.assertTrue(self.ev('rawequal(SAME_A, LivingKnox.handlers["OnTick/Groups.flush"])'))


class DeferredSoloTests(Base):
    mode = 'solo'

    def test_on_save_writes_the_pending_changes(self):
        self.init()
        self.run_lua('assert(LivingKnox.Groups.create({ type = "settlers", name = "Mill", day = 1 }))')
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), 0)
        self.h.fire(self.srv, 'OnSave')                       # GameWindow.save (solo) : sauvegarde du monde
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), 1)
        before = self.ev(CANON)
        self.restart(clean=False)
        self.init()
        self.assertEqual(self.ev(CANON), before)


ROOT = Path(__file__).resolve().parents[1]
GROUPS_FILE = 'LK_Groups.lua'
PEEK_CALL = re.compile(r'\.peek\(')
PEEK_LOCAL = re.compile(r'^\s*(?:local\s+)?(\w+)\s*=\s*.*\.peek\(')
ALIAS = re.compile(r'^\s*(?:local\s+)?(\w+)\s*=\s*(?:(\w+)\s+and\s+)?(\w+)[.\[]')
FUNC_END = re.compile(r'^(end\b|function\b|local\s+function\b)')


def peek_writes(text: str, name: str = '<lua>'):
    """Écritures par une vue Groups.peek (lecture du code) : rend la liste « fichier:ligne: texte ».

    Pour chaque appel peek hors de LK_Groups.lua : la variable qui reçoit la vue et ses alias (local h = g.home, local
    h = g and g.home) jusqu'à la fin de la fonction de premier niveau ; écriture d'un champ (v.x =, v[k] =, v.a.b =),
    table.insert/remove/sort sur la vue, vue rendue telle quelle (return ... peek(...)) ou appel non affecté."""
    lines = text.split('\n')
    found = []
    for i, line in enumerate(lines):
        code = line.split('--', 1)[0]
        if not PEEK_CALL.search(code):
            continue
        if re.match(r'^\s*function\s+\w+\.peek\(', code):
            continue
        if re.match(r'^\s*return\b', code):
            found.append(f'{name}:{i + 1}: view returned: {line.strip()}')
            continue
        m = PEEK_LOCAL.match(code)
        if not m:
            if not re.search(r'\bif\b|\band\b|\bor\b|==|~=', code):
                found.append(f'{name}:{i + 1}: view not assigned: {line.strip()}')
            continue
        views = {m.group(1)}
        for j in range(i + 1, len(lines)):
            body = lines[j].split('--', 1)[0]
            if FUNC_END.match(body):
                break
            a = ALIAS.match(body)
            if a and (a.group(3) in views):
                views.add(a.group(1))
            for v in views:
                if re.search(rf'\b{v}\s*(?:\.\w+|\[[^\]]*\])+\s*=(?!=)', body) or \
                        re.search(rf'\btable\.(?:insert|remove|sort)\(\s*{v}\b', body):
                    found.append(f'{name}:{j + 1}: write through view {v}: {lines[j].strip()}')
    return found


class PeekTests(Base):
    """LK13-T08 : lecture en place Groups.peek (aucune copie, lecture seule)."""

    def test_peek_returns_the_live_group_without_copy(self):
        self.init()
        a, _ = self.populate()
        self.assertTrue(self.ev(f'rawequal(LivingKnox.Groups.peek("{a}"), LivingKnox.Groups.state.data.groups["{a}"])'))
        self.assertFalse(self.ev(f'rawequal(LivingKnox.Groups.get("{a}"), LivingKnox.Groups.state.data.groups["{a}"])'))
        self.assertEqual(self.run_lua('return LivingKnox.Groups.peek("grp-9")'), (None, 'unknown group grp-9'))
        # La vue suit les changements enregistrés (aucune copie gardée).
        self.run_lua(f'V = LivingKnox.Groups.peek("{a}") assert(LivingKnox.Groups.setMorale("{a}", 12))')
        self.assertEqual(self.ev('V.morale'), 12)
        self.assertEqual(self.ev('LivingKnox.Groups.stats.peeks'), 2)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_peek_check_reports_a_write_through_the_view(self):
        self.init()
        a, b = self.populate()
        self.run_lua('LivingKnox.Groups.PEEK_CHECK = true')
        # Lectures puis changements enregistrés (API et Groups.update) : aucune faute.
        self.run_lua(f'local G = LivingKnox.Groups local g = G.peek("{a}") local n = g.morale '
                     f'assert(G.setMorale("{a}", n + 1)) G.peek("{b}") '
                     f'G.update(function(data) data.groups["{b}"].morale = 5 return true end)')
        self.h.tick(1)
        self.assertEqual(self.ev('LivingKnox.Groups.stats.peekViolations or 0'), 0)
        # Écriture par la vue, sans changement enregistré : vue à la fin de l'image.
        self.run_lua(f'local g = LivingKnox.Groups.peek("{a}") g.name = "Changed" g.home.x = 1')
        self.h.tick(1)
        self.assertEqual(self.ev('LivingKnox.Groups.stats.peekViolations'), 1)
        self.assertTrue(any('group grp-1 changed through Groups.peek' in line for line in self.lk()))
        # Signalée une fois ; une simple lecture ensuite ne signale plus rien.
        self.run_lua(f'local _ = LivingKnox.Groups.peek("{a}").name')
        self.h.tick(2)
        self.assertEqual(self.ev('LivingKnox.Groups.stats.peekViolations'), 1)
        # Sous-table (journal) changée par la vue : vue aussi, par Groups.checkPeeks() sur demande.
        self.run_lua(f'local g = LivingKnox.Groups.peek("{b}") table.insert(g.log, {{ day = 1, kind = "x", text = "" }})')
        self.assertEqual(self.ev('LivingKnox.Groups.checkPeeks()'), 1)

    def test_no_caller_writes_through_a_view(self):
        sources = sorted(p for d in ('Contents', 'dev') for p in (ROOT / d).rglob('*.lua'))
        self.assertTrue(sources)
        callers, found = [], []
        for path in sources:
            if path.name == GROUPS_FILE:
                continue
            text = path.read_text(encoding='utf-8')
            if PEEK_CALL.search(text):
                callers.append(path.name)
                found += peek_writes(text, path.name)
        self.assertEqual(found, [])
        self.assertIn('LK_Obstacles.lua', callers)
        # Le contrôle voit bien les écritures (exemples).
        bad = ('local function f(gid)\n    local g = G.peek(gid)\n    local h = g and g.home\n    h.x = 3\nend\n'
               'local function k(gid)\n    local v = G.peek(gid)\n    v.members["m-1"].alive = false\n'
               '    table.insert(v.log, {})\nend\n'
               'local function r(gid) return G.peek(gid) end\n'
               'local function ok(gid)\n    local g = G.peek(gid)\n    local n = g.morale == 3\nend\n'
               'local function later()\n    g.x = 1\nend\n')
        self.assertEqual([f.split(':')[1] for f in peek_writes(bad)], ['4', '8', '9', '11'])

    def test_load_bench_never_writes_through_a_view(self):
        """Banc de charge (5 groupes, 4 joueurs, tous les modules) sur 3 minutes de jeu, contrôle des vues actif."""
        sys.path.insert(0, str(ROOT / 'tools'))
        import load_bench
        bench = load_bench.LoadBench()
        try:
            bench.h.load('server', 'LivingKnox.Groups.PEEK_CHECK = true LivingKnox.Groups.stats.peeks = 0')
            bench.run_minutes(3)
            self.assertGreater(bench.h.eval('server', 'LivingKnox.Groups.stats.peeks'), 20)
            self.assertEqual(bench.h.eval('server', 'LivingKnox.Groups.stats.peekViolations or 0'), 0)
            self.assertEqual({m: len(v) for m, v in bench.errors().items() if v}, {})
        finally:
            bench.close()


if __name__ == '__main__':
    unittest.main()
