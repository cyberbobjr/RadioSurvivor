"""Agreements kept by Living Knox, team ids kept by the core mod (E18-T20, decision of 2026-11-06).

    python tests/livingknox/test_lk_agreements.py

Living Knox alone (core mod and Living Knox only on the module path): a truce concluded for the team of a player (CA_Teams of the core
mod: personal team in solo) with one of its groups makes the character covered by the hook of Living Knox
(LivingKnox.Hooks.covered), is written in the private file of Living Knox (agreements-*.txt, header LKAGR1) and read
back after a restart; the team id is written in the private file of the core mod (teams-*.txt, header RCTEAMS1) and
the same after the restart. Bench tests/commun/harness.py (solo authority), real LK_Store, LK_Groups, LK_Hostility, LK_API,
LK_Agreements, CA_Teams, CA_Identity; doubles only for the Java API.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_lk_personal_relation as relation_bench  # noqa: E402  (module import: its tests are not collected here)

LivingKnoxAloneTests = relation_bench.LivingKnoxAloneTests
LOAD = 'require "LivingKnox/LK_Agreements" require "CoreAI/CA_Teams"'


class LivingKnoxAgreementsTests(LivingKnoxAloneTests):
    locals().update({name: None for name in dir(LivingKnoxAloneTests) if name.startswith('test_')})

    def setUp(self):
        super().setUp()
        self.boot_agreements(True)

    def boot_agreements(self, new_world):
        flag = str(new_world).lower()
        self.run_lua(LOAD)
        self.run_lua(f'assert(require("CoreAI/CA_Teams").init({flag})) '
                     f'assert(LivingKnox.Agreements.init({flag})) LivingKnox.Agreements.installHook() '
                     'PLAYER = {getUsername = function() return "ann" end}')

    def test_truce_covered_and_kept_after_a_restart(self):
        team = self.ev('require("CoreAI/CA_Teams").idOf(PLAYER)')
        self.assertRegex(team, r'^fac-\d+$')
        self.assertFalse(self.ev('LivingKnox.Hooks.covered(GID, "c-ann")'))
        out = self.ev('(function() local A = LivingKnox.Agreements local neg = assert(A.negotiation(PLAYER, GID)) '
                      'local ok, why, a = A.conclude(PLAYER, GID, "truce", {team = neg.team, revision = neg.revision}, '
                      '{character = "c-ann"}) return tostring(ok) .. "|" .. tostring(why) .. "|" .. a.state end)()')
        self.assertEqual(out, 'true|ok|pending')
        self.assertTrue(self.ev('LivingKnox.Hooks.covered(GID, "c-ann")'))
        self.assertTrue(self.ev('LivingKnox.Agreements.save()'))
        root = self.h.file_root('solo')
        self.assertTrue(sorted((root / 'batman_LivingKnox').glob('agreements-*.txt'))[-1].read_text(
            encoding='utf-8').startswith('LKAGR1='))
        self.assertTrue(sorted((root / 'batman_CoreAI').glob('teams-*.txt'))[-1].read_text(
            encoding='utf-8').startswith('RCTEAMS1='))
        self.run_lua('LivingKnox.Store.flush() LivingKnox.Groups.flush() LivingKnox.Hostility.save()')
        # Restart: new Lua state on the same files.
        self.h.close()
        self.h = self.make(root=Path(self.tmp.name))
        self.boot(self.h)
        self.init_all(False)
        self.run_lua(f'GID = "{self.gid}"')
        self.boot_agreements(False)
        self.assertEqual(self.ev('require("CoreAI/CA_Teams").idOf(PLAYER)'), team)
        self.assertEqual(self.ev(f'LivingKnox.Agreements.agreementOf(GID, "{team}").kind'), 'truce')
        self.assertTrue(self.ev('LivingKnox.Hooks.covered(GID, "c-ann")'), 'truce lost by the restart')


# Client doubles of the notice view: halos and translated text "key|arg1|arg2" (vanilla getText formatting not needed).
NOTICE_CLIENT = r"""
HALOS = {}
HaloTextHelper = {addGoodText = function(p, t) HALOS[#HALOS + 1] = 'good:' .. t end,
    addBadText = function(p, t) HALOS[#HALOS + 1] = 'bad:' .. t end}
getText = function(key, ...) local out = key for _, a in ipairs({...}) do out = out .. '|' .. tostring(a) end return out end
"""


class AgreementNoticesTests(relation_bench.Base):
    """E21-T04: the agreements that became applicable and the decisions of a leader on an incident are announced by
    Living Knox itself (LK_AgreementNotices, network module LivingKnox) to the connected players of the team, with
    no module of RadioSurvivor loaded (dedicated server and two MP clients of the harness)."""
    mode = 'mp'
    debug = False

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-agreement-notices-')
        self.h = self.make(root=Path(self.tmp.name))
        self.h.load('server', 'require "LivingKnox/LK_GroupTypes" require "LivingKnox/Data/LK_Type_settlers"')
        for path in relation_bench.MODULES:
            self.h.load('server', path)
        self.init(True)
        self.run_lua('assert(LivingKnox.Groups.init(true)) ' + LOAD + ' require "LivingKnox/LK_AgreementNotices" '
                     'assert(require("CoreAI/CA_Teams").init(true)) assert(LivingKnox.Agreements.init(true)) '
                     'local g = assert(LivingKnox.Groups.create({type = "settlers", name = "Farm", '
                     'home = {x = 100, y = 100, z = 0}, day = 2})) GID = g.id '
                     'TEAM = require("CoreAI/CA_Teams").idOf(HARNESS.players.A)')
        for client in ('A', 'B'):
            self.h.load(client, NOTICE_CLIENT)
            self.h.load(client, 'client/LivingKnox/LK_AgreementNoticesView.lua')

    def tearDown(self):
        super().tearDown()
        self.tmp.cleanup()

    def halos(self, client):
        return list(self.h.eval(client, 'HALOS').values())

    def test_agreement_and_incident_reach_the_team_only(self):
        agreement = '{id = "agr-1", revision = 1, kind = "truce", state = "applicable", group = GID, team = TEAM}'
        self.run_lua(f'for _, fn in ipairs(LivingKnox.Agreements.appliedListeners) do fn({agreement}) end')
        self.h.pump()
        self.assertEqual(self.halos('A'), ['good:IGUI_LK_Agreement_truce|Farm'])
        self.assertEqual(self.halos('B'), [], 'announced to a player of another team')
        # Same revision again: shown once.
        self.run_lua(f'for _, fn in ipairs(LivingKnox.Agreements.appliedListeners) do fn({agreement}) end')
        self.h.pump()
        self.assertEqual(len(self.halos('A')), 1)
        self.run_lua('LivingKnox.AgreementNotices.incident({revision = 2, team = TEAM}, '
                     '{id = "inc-1", decision = "repair", category = "food"}, {groupName = "Farm"}) '
                     'LivingKnox.AgreementNotices.incident({revision = 3, team = TEAM}, '
                     '{id = "inc-2", decision = "break"}, {groupName = ""})')
        self.h.pump()
        self.assertEqual(self.halos('A')[1:], ['good:IGUI_LK_Incident_repair|Farm|IGUI_LK_RepairCategory_food',
                                               'bad:IGUI_LK_Incident_break|IGUI_LK_IncidentGroup'])
        self.assertEqual(self.halos('B'), [])


del LivingKnoxAloneTests  # base bench: collected by its own file only


if __name__ == '__main__':
    unittest.main()
