"""Suites de persistance de l'état privé du carnet (E16-T08, C17-C20, base rs.state de la campagne mp-persist) :
rs.state.before puis rs.state.after-restart joués par le vrai moteur RST sur le vrai CA_NotebookStore et le vrai
CA_NotebookPurge (E21-T04 : état du carnet dans le mod commun).

    python RadioSurvivor/tests/test_rs_state_persist_suite.py

Redémarrage simulé : nouvel état Lua sur les mêmes fichiers (emplacements d'état, fichiers du mod commun, instantané
RST_Persist), S.init(false) comme au démarrage du serveur, puis l'étape after-restart. Doublures d'API reprises de
tests/test_rs_state.py (fichiers, monde, horloge CA_Reputation.today). Ne prouve rien sur le Java du jeu : le vrai
redémarrage du serveur dédié reste la campagne MP (autoclient.py --phases restart --server-campaign mp-persist).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rs_state import runtime  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
RST_SHARED = tests_lua() / 'shared'
SUITE = RST_SHARED / 'RST' / 'suites' / 'RS_StatePersist.lua'

# Server of the bench: RST engine over the real modules of tests/test_rs_state.py, RST_Persist writes lines.
SERVER = r'''
isServer = function() return true end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
local world = getWorld()
getWorld = function()   -- a test save (rstest*): RST refuses "world" suites elsewhere
    return {getGameMode = function() return world:getGameMode() end, getWorld = function() return 'rstest_state' end}
end
local open = getFileWriter
getFileWriter = function(path, create, append)
    local w = open(path, create, append)
    if w then w.writeln = function(self, line) self:write(line .. '\n') end end
    return w
end
local S = require('CoreAI/CA_NotebookStore')
STARTED = S.init(false)
CoreAI = CoreAI or {}; CoreAI.notebookServer = {store = S, bound = {}}
require "RST/RST"
'''


def server(files=None):
    """A dedicated server started on `files` (dict path -> text of the previous session), suite loaded."""
    rt = runtime()
    rt.execute(f'package.path = [[{RST_SHARED.as_posix()}/?.lua;]] .. package.path')
    for path, text in (files or {}).items():
        rt.globals().FILES[path] = text
    rt.execute(SERVER)
    rt.execute(f'dofile([[{SUITE.as_posix()}]])')
    return rt


def files_of(rt):
    return {k: v for k, v in rt.globals().FILES.items()}


def run(rt, name):
    assert rt.eval(f'RST.start("{name}", {{ attach = false, ctx = {{}} }})'), name
    for _ in range(1000):
        if not rt.eval('RST.step()'):
            break
        rt.execute('CLOCK = CLOCK + 100')
    assert not rt.eval('RST.running()'), f'{name}: run not finished'
    return [(r.status, r.message) for r in rt.eval('RST.last()').results.values()]


def test_ids(rt):
    """Test character ids (RST.StatePersist.PREFIX) of the notebook state in memory, sorted."""
    listed = rt.eval('(function() local out = {} local P = RST.StatePersist.PREFIX '
                     'for cid in pairs(require("CoreAI/CA_NotebookStore").data.characters) do '
                     'if string.sub(cid, 1, #P) == P then out[#out + 1] = cid end end '
                     'return table.concat(out, ",") end)()')
    return sorted(c for c in listed.split(',') if c)


class StatePersistSuiteTests(unittest.TestCase):

    def before(self):
        rt = server()
        self.assertTrue(rt.eval('STARTED'))
        self.assertEqual(run(rt, 'rs.state.before'), [('PASS', None)])
        return rt

    def restart(self, rt):
        rt2 = server(files_of(rt))
        self.assertTrue(rt2.eval('STARTED'), 'state not loaded after the restart')
        return rt2

    def test_before_then_after_restart(self):
        rt = self.before()
        ids = test_ids(rt)
        self.assertEqual([c.rsplit('-', 1)[1] for c in ids], ['alive2', 'busy', 'living', 'recent'])
        self.assertEqual(rt.eval('DAY'), rt.eval('require("CoreAI/CA_Reputation").today()'),
                         'purge clock not restored')
        self.assertIsNone(rt.eval('REP_DATA.reputation'), 'reputation entry of the in-use record left behind')
        rt2 = self.restart(rt)
        self.assertEqual(test_ids(rt2), ids)
        self.assertEqual(run(rt2, 'rs.state.after-restart'), [('PASS', None)])
        self.assertEqual(test_ids(rt2), [], 'test records not removed')
        rt3 = self.restart(rt2)
        self.assertEqual(test_ids(rt3), [], 'removal not saved')
        self.assertIn('already used', rt3.eval('select(2, RST.Persist.read(RST.StatePersist.FILE, '
                                               'RST.StatePersist.HEADER))'))

    def test_purged_record_still_present_after_restart_fails(self):
        rt = self.before()
        rt.execute('local S = require("CoreAI/CA_NotebookStore") '
                   'local cid = RST.Persist.read(RST.StatePersist.FILE, RST.StatePersist.HEADER).purged[1] '
                   'S.data.characters[cid] = {id = cid, retired = true, retiredDay = DAY, contacts = {}, '
                   'knownMissions = {}} assert(S.save())')
        (status, message), = run(self.restart(rt), 'rs.state.after-restart')
        self.assertEqual(status, 'FAIL')
        self.assertIn('purged record', message)

    def test_kept_record_lost_fails(self):
        rt = self.before()
        rt.execute('local S = require("CoreAI/CA_NotebookStore") '
                   'for cid in pairs(S.data.characters) do if string.find(cid, "-busy$") then '
                   'S.data.characters[cid] = nil end end assert(S.save())')
        (status, message), = run(self.restart(rt), 'rs.state.after-restart')
        self.assertEqual(status, 'FAIL')
        self.assertIn('lost', message)

    def test_kept_record_changed_fails(self):
        rt = self.before()
        rt.execute('local S = require("CoreAI/CA_NotebookStore") '
                   'for cid, r in pairs(S.data.characters) do if string.find(cid, "-living$") then '
                   'r.contacts = {} end end assert(S.save())')
        (status, message), = run(self.restart(rt), 'rs.state.after-restart')
        self.assertEqual(status, 'FAIL')
        self.assertIn('contacts', message)

    def test_last_write_lost_fails(self):
        """The newest slot corrupt: S.init falls back to the older slot, saved before the purge."""
        rt = self.before()
        files = files_of(rt)
        gen = rt.eval('require("CoreAI/CA_NotebookStore").seq')
        path = rt.eval('require("CoreAI/CA_NotebookStore").base') + f'-{gen % 2}.txt'
        files[path] = files[path].replace('\nend\n', '\nbroken\n')
        rt2 = server(files)
        self.assertTrue(rt2.eval('STARTED'))
        (status, message), = run(rt2, 'rs.state.after-restart')
        self.assertEqual(status, 'FAIL')
        self.assertIn('state after the restart', message)

    def test_after_without_snapshot_fails(self):
        (status, message), = run(server(), 'rs.state.after-restart')
        self.assertEqual(status, 'FAIL')
        self.assertIn('run the .before suite', message)

    def test_rerun_of_before_replaces_previous_test_records(self):
        rt = self.before()
        rt.execute('CLOCK = CLOCK + 5000')
        self.assertEqual(run(rt, 'rs.state.before'), [('PASS', None)])
        self.assertEqual(len(test_ids(rt)), 4)


if __name__ == '__main__':
    unittest.main(verbosity=1)
