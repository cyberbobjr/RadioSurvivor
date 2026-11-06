"""Agreements kept by Living Knox, team ids kept by the core mod (E18-T20, decision of 2026-11-06).

    python RadioSurvivor/tests/test_lk_agreements.py

Living Knox alone (no module of RadioSurvivor loaded): a truce concluded for the team of a player (RC_Teams of the core
mod: personal team in solo) with one of its groups makes the character covered by the hook of Living Knox
(LivingKnox.Hooks.covered), is written in the private file of Living Knox (agreements-*.txt, header LKAGR1) and read
back after a restart; the team id is written in the private file of the core mod (teams-*.txt, header RCTEAMS1) and
the same after the restart. Bench tests/harness.py (solo authority), real LK_Store, LK_Groups, LK_Hostility, LK_API,
LK_Agreements, RC_Teams, RC_Identity; doubles only for the Java API.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_personal_relation as relation_bench  # noqa: E402  (module import: its tests are not collected here)

LivingKnoxAloneTests = relation_bench.LivingKnoxAloneTests
LOAD = 'require "LivingKnox/LK_Agreements" require "RadioSurvivorCore/RC_Teams"'


class LivingKnoxAgreementsTests(LivingKnoxAloneTests):
    locals().update({name: None for name in dir(LivingKnoxAloneTests) if name.startswith('test_')})

    def setUp(self):
        super().setUp()
        self.boot_agreements(True)

    def boot_agreements(self, new_world):
        flag = str(new_world).lower()
        self.run_lua(LOAD)
        self.run_lua(f'assert(require("RadioSurvivorCore/RC_Teams").init({flag})) '
                     f'assert(LivingKnox.Agreements.init({flag})) LivingKnox.Agreements.installHook() '
                     'PLAYER = {getUsername = function() return "ann" end}')

    def test_truce_covered_and_kept_after_a_restart(self):
        self.no_radiosurvivor()
        team = self.ev('require("RadioSurvivorCore/RC_Teams").idOf(PLAYER)')
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
        self.assertTrue(sorted((root / 'batman_RadioSurvivorCore').glob('teams-*.txt'))[-1].read_text(
            encoding='utf-8').startswith('RCTEAMS1='))
        self.run_lua('LivingKnox.Store.flush() LivingKnox.Groups.flush() LivingKnox.Hostility.save()')
        # Restart: new Lua state on the same files.
        self.h.close()
        self.h = self.make(root=Path(self.tmp.name))
        self.boot(self.h)
        self.init_all(False)
        self.run_lua(f'GID = "{self.gid}"')
        self.boot_agreements(False)
        self.assertEqual(self.ev('require("RadioSurvivorCore/RC_Teams").idOf(PLAYER)'), team)
        self.assertEqual(self.ev(f'LivingKnox.Agreements.agreementOf(GID, "{team}").kind'), 'truce')
        self.assertTrue(self.ev('LivingKnox.Hooks.covered(GID, "c-ann")'), 'truce lost by the restart')
        self.no_radiosurvivor()


del LivingKnoxAloneTests  # base bench: collected by its own file only


if __name__ == '__main__':
    unittest.main()
