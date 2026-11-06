"""Living Knox's NPCs in the Contacts tab of the notebook of the core mod (E18-T26).

    python RadioSurvivor/tests/test_lk_contacts.py

Living Knox alone (no module of RadioSurvivor loaded): the source "lk" of RC_Contacts lists the NPCs a character knows
(personal relation or exchange history kept by the core mod), with their name (LivingKnox.Names), group, relation
panel and history; another character sees none of them; with RadioSurvivor active the source is not registered (its
fiches already list these NPCs). Bench tests/harness.py (solo authority), real LK_Store, LK_Groups, LK_Hostility,
LK_API, LK_PersonalRelation, RC_History, RC_Contacts; doubles only for the Java API.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_personal_relation as relation_bench  # noqa: E402  (module import: its tests are not collected here)
LivingKnoxAloneTests = relation_bench.LivingKnoxAloneTests
del relation_bench


def mods_double(*ids):
    body = ', '.join(f'"{i}"' for i in ids)
    return ('getActivatedMods = function() local l = {%s} return {size = function() return #l end, '
            'get = function(_, i) return l[i + 1] end} end' % body)


class LivingKnoxContactsTests(LivingKnoxAloneTests):
    # Same world as the relation bench; its own tests are not run again here.
    locals().update({name: None for name in dir(LivingKnoxAloneTests) if name.startswith('test_')})

    def setUp(self):
        super().setUp()
        self.run_lua(mods_double('batman_SignalSmoke', 'batman_RadioSurvivorCore', 'batman_LivingKnox'))
        self.run_lua('assert(require("RadioSurvivorCore/RC_History").init(true)) '
                     'LKC = require("LivingKnox/LK_Contacts") assert(LKC.registered)')

    def rows(self, character):
        return self.ev(f'(function() local out = {{}} for _, r in ipairs(require("RadioSurvivorCore/RC_Contacts")'
                       f'.rows("{character}", nil)) do out[#out + 1] = table.concat({{r.id, r.source, r.name, '
                       'tostring(r.alive), tostring(r.groupName), tostring(r.relation and r.relation.level), '
                       'tostring(#r.history)}, "|") end return table.concat(out, ";") end)()')

    def test_npcs_met_with_history_and_relation(self):
        self.assertEqual(self.rows('c-ann'), '')
        self.run_lua(f'require("RadioSurvivorCore/RC_History").append("c-ann", "lk:{self.npc}", '
                     '{id = "h1", author = "Ann", text = "Hello"})')
        name = self.ev(f'LivingKnox.Names.of("{self.npc}").name')
        group = self.ev('LivingKnox.API.attitude(GID, "c-ann").level')
        self.assertEqual(self.rows('c-ann'), f'lk:{self.npc}|lk|{name}|true|Farm|{group}|1')  # level of the group
        # A relation changed by a real fact: the panel carries its level.
        self.fact('c-ann', 'gift')
        self.run_lua(f'local ctx, b = LivingKnox.API.relationOffer("{self.npc}", "c-ann") '
                     f'assert(LivingKnox.API.relationApply("{self.npc}", "c-ann", b, "up", "f1"))')
        levels = ['hostile', 'wary', 'cautious', 'favorable', 'trusting']
        above = levels[min(4, levels.index(group) + 1)]
        self.assertEqual(self.rows('c-ann'), f'lk:{self.npc}|lk|{name}|true|Farm|{above}|1')
        self.assertEqual(self.rows('c-bob'), '')
        self.no_radiosurvivor()

    def test_not_registered_with_radiosurvivor(self):
        self.run_lua(mods_double('batman_RadioSurvivorCore', 'batman_LivingKnox', 'batman_RadioSurvivor'))
        self.run_lua('LKC.registered = false '
                     'local C = require("RadioSurvivorCore/RC_Contacts") C.sources.lk = nil C.order = {}')
        self.assertFalse(self.ev('LKC.register()'))
        self.assertIsNone(self.ev('require("RadioSurvivorCore/RC_Contacts").sources.lk'))


del LivingKnoxAloneTests  # base bench: collected by its own file only


if __name__ == '__main__':
    unittest.main()
