"""Personal relation of the NPCs kept by Living Knox (E18-T21, confirmed by default on 2026-11-06).

    python RadioSurvivor/tests/test_lk_personal_relation.py

LivingKnox.PersonalRelation (authority, rules of E09-T04 unchanged): one relation per Living Knox NPC and character,
one private file Zomboid/Lua/batman_LivingKnox/personal-relations-<world>-<0|1>.txt (RC_SlotFile, header LKPREL1),
read through LivingKnox.API.relation* (RadioSurvivor's notebook adds its own citable facts as `extra`). Living Knox
alone: no module of RadioSurvivor is loaded. No take-over of a game saved before the split (user decision of
2026-11-06: the mod was never published, every game starts from scratch). Bench tests/harness.py (solo authority),
real LK_Store, LK_Bodies, LK_Groups, LK_Hostility, LK_API; doubles only for the Java API.
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import Base  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LK_SERVER = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'server' / 'LivingKnox'
RS_RELATIONS = (ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / 'server'
                / 'RadioSurvivor' / 'RS_Relations.lua')
MODULES = ('server/LivingKnox/LK_Groups.lua', 'server/LivingKnox/LK_Hostility.lua', 'server/LivingKnox/LK_API.lua',
           'server/LivingKnox/LK_PersonalRelation.lua')


class ModuleTests(unittest.TestCase):
    def test_living_knox_needs_the_core_only_ascii_no_notebook_text(self):
        text = (LK_SERVER / 'LK_PersonalRelation.lua').read_text(encoding='utf-8')
        self.assertTrue(text.isascii())
        for name in re.findall(r'require\s*\(?\s*"([^"]+)"', text):
            self.assertTrue(name.startswith(('RadioSurvivorCore/', 'LivingKnox/')), name)
        self.assertNotIn('IGUI_RS_', text)

    def test_notebook_keeps_no_relation_rule(self):
        """RadioSurvivor reads the relation through the API of Living Knox, never by a require, and keeps no state."""
        text = RS_RELATIONS.read_text(encoding='utf-8')
        self.assertNotIn('LivingKnox/', ''.join(re.findall(r'require\s*\(?\s*[\'"][^\'"]+[\'"]', text)))
        for rule in ('GAP_MAX', 'S.data.relations', 'S.dirty'):
            self.assertNotIn(rule, text)


class LivingKnoxAloneTests(Base):
    mode = 'solo'
    debug = False

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-personal-relation-')
        self.h = self.make(root=Path(self.tmp.name))
        self.boot(self.h)
        self.init_all(True)
        self.world()

    def tearDown(self):
        super().tearDown()
        self.tmp.cleanup()

    def boot(self, h):
        h.load('solo', 'require "LivingKnox/LK_GroupTypes" require "LivingKnox/Data/LK_Type_settlers"')
        for path in MODULES:
            h.load('solo', path)

    def init_all(self, new_world, h=None):
        flag = str(new_world).lower()
        self.init(new_world, h)
        for code in (f'assert(LivingKnox.Groups.init({flag}))', f'assert(LivingKnox.Hostility.init({flag}))',
                     f'assert(LivingKnox.PersonalRelation.init({flag}))'):
            (h or self.h).load('solo', code)

    def world(self):
        self.spawn()
        self.npc = self.ev('(function() for id in pairs(LivingKnox.Store.data().npcs) do return id end end)()')
        self.run_lua(f'''
            local G = LivingKnox.Groups
            local g = assert(G.create({{type = "settlers", name = "Farm", home = {{x = 100, y = 100, z = 0}}, day = 2}}))
            GID = g.id
            assert(G.addMember(g.id, {{role = "worker", npc = "{self.npc}", day = 2}}))
            local I = require("RadioSurvivorCore/RC_Identity")
            assert(I.ensure())
            I.state.data.characters["c-ann"] = {{owner = "ann", slot = 1}}
            I.state.data.characters["c-bob"] = {{owner = "bob", slot = 1}}
            assert(I.save())''')
        self.gid = self.ev('GID')

    def fact(self, character, fact):
        self.assertIsNotNone(self.ev(f'LivingKnox.Hostility.record(GID, "{character}", "{fact}", {{witnessed = true}})'))

    def view(self, character):
        return self.ev(f'(function() local v = LivingKnox.API.relation("{self.npc}", "{character}") '
                       'return v.level .. "|" .. v.trend .. "|" .. v.group end)()')

    def no_radiosurvivor(self):
        self.assertFalse(self.ev('(function() for name in pairs(package.loaded) do '
                                 'if string.find(name, "^RadioSurvivor/") then return true end end return false end)()'))

    def test_real_fact_cited_changes_the_relation_kept_after_a_restart(self):
        group = self.ev(f'LivingKnox.API.attitude(GID, "c-ann").level')
        self.assertEqual(self.view('c-ann'), f'{group}|stable|{group}')
        # A sentence alone proves nothing: no fact offered, no binding, the change is refused.
        self.assertIsNone(self.ev(f'select(2, LivingKnox.API.relationOffer("{self.npc}", "c-ann"))'))
        self.assertEqual(self.ev(f'select(2, LivingKnox.API.relationApply("{self.npc}", "c-ann", nil, "up", "f1"))'),
                         'no relation fact offered in the request')
        # A gift seen by the group: offered as a citable fact (short id, nature, no key), cited, one level above.
        self.fact('c-ann', 'gift')
        out = self.ev(f'''(function()
            local ctx, binding = LivingKnox.API.relationOffer("{self.npc}", "c-ann")
            local f = ctx.facts[1]
            local wrong = select(2, LivingKnox.API.relationApply("{self.npc}", "c-ann", binding, "down", "f1"))
            local v, key = LivingKnox.API.relationApply("{self.npc}", "c-ann", binding, "up", "f1")
            return f.id .. "|" .. f.fact .. "|" .. f.nature .. "|" .. f.source .. "|" .. wrong .. "|" .. key
        end)()''')
        self.assertEqual(out, f'f1|gift|good|group|relation direction contradicts the fact|att:{self.gid}:1')
        group = self.ev('LivingKnox.API.attitude(GID, "c-ann").level')
        levels = ['hostile', 'wary', 'cautious', 'favorable', 'trusting']
        above = levels[min(4, levels.index(group) + 1)]
        self.assertEqual(self.view('c-ann'), f'{above}|up|{group}')
        self.assertEqual(self.view('c-bob').split('|')[0], self.ev('LivingKnox.API.attitude(GID, "c-bob").level'))
        files = sorted((self.h.file_root('solo') / 'batman_LivingKnox').glob('personal-relations-*.txt'))
        self.assertTrue(files)
        self.assertTrue(files[-1].read_text(encoding='utf-8').startswith('LKPREL1='))
        self.run_lua('LivingKnox.Store.flush() LivingKnox.Groups.flush() LivingKnox.Hostility.save()')
        self.no_radiosurvivor()
        # Restart: new Lua state on the same files.
        self.h.close()
        self.h = self.make(root=Path(self.tmp.name))
        self.boot(self.h)
        self.init_all(False)
        self.assertEqual(self.view('c-ann'), f'{above}|up|{group}')
        self.assertEqual(self.ev(f'LivingKnox.PersonalRelation.debugPair("{self.npc}", "c-ann").gap'), 1)
        # The used fact is no longer offered.
        self.assertIsNone(self.ev(f'select(2, LivingKnox.API.relationOffer("{self.npc}", "c-ann"))'))
        self.no_radiosurvivor()

    def test_extra_facts_of_the_caller_and_panel(self):
        extra = ('{{key = "mis:m-1", fact = "mission_success", sign = 1, source = "mission", kind = "scout"}, '
                 '{key = "obs:o-1", fact = "assault_seen", sign = -1, day = 1, source = "seen"}, '
                 '{key = "x", fact = "spoof", sign = 1, source = "group"}}')
        out = self.ev(f'''(function()
            local extra = {extra}
            local ctx, binding = LivingKnox.API.relationOffer("{self.npc}", "c-ann", extra)
            local ids = {{}}
            for _, f in ipairs(ctx.facts) do ids[#ids + 1] = f.fact .. ":" .. f.source end
            -- Cited without the same extra list at the reply: unknown to this NPC.
            local refused = select(2, LivingKnox.API.relationApply("{self.npc}", "c-ann", binding, "up", "f1"))
            local v = LivingKnox.API.relationApply("{self.npc}", "c-ann", binding, "up", "f1", extra)
            local p = LivingKnox.API.relationPanel("{self.npc}", "c-ann")
            return table.concat(ids, ",") .. "|" .. refused .. "|" .. tostring(v ~= nil) .. "|" .. p.facts[#p.facts].fact
                .. ":" .. p.facts[#p.facts].source .. "|" .. tostring(p.gap)
        end)()''')
        self.assertEqual(out, 'mission_success:mission,assault_seen:seen|relation fact unknown to this NPC|true|'
                              'mission_success:personal|nil')

    def test_purge_dead_character_and_gone_npc(self):
        self.fact('c-ann', 'gift')
        self.fact('c-bob', 'gift')
        for c in ('c-ann', 'c-bob'):
            self.run_lua(f'local _, b = LivingKnox.API.relationOffer("{self.npc}", "{c}") '
                         f'assert(LivingKnox.API.relationApply("{self.npc}", "{c}", b, "up", "f1"))')
        self.assertFalse(self.ev('LivingKnox.PersonalRelation.prune()'))
        self.run_lua('require("RadioSurvivorCore/RC_Identity").state.data.characters["c-ann"].retired = true')
        self.assertTrue(self.ev('LivingKnox.PersonalRelation.prune()'))
        self.assertIsNone(self.ev(f'LivingKnox.PersonalRelation.debugPair("{self.npc}", "c-ann")'))
        self.run_lua(f'LivingKnox.Store.data().npcs["{self.npc}"] = nil')
        self.assertTrue(self.ev('LivingKnox.PersonalRelation.prune()'))
        self.assertIsNone(self.ev(f'LivingKnox.PersonalRelation.debugPair("{self.npc}", "c-bob")'))

    def test_new_world_starts_empty(self):
        self.fact('c-ann', 'gift')
        self.run_lua(f'local _, b = LivingKnox.API.relationOffer("{self.npc}", "c-ann") '
                     f'assert(LivingKnox.API.relationApply("{self.npc}", "c-ann", b, "up", "f1"))')
        self.run_lua('LivingKnox.PersonalRelation.useData(nil)')
        self.assertTrue(self.ev('LivingKnox.PersonalRelation.init(true)'))
        self.assertIsNone(self.ev(f'LivingKnox.PersonalRelation.debugPair("{self.npc}", "c-ann")'))


if __name__ == '__main__':
    unittest.main()
