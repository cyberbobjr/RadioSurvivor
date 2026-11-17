"""NPC provider interface of the notebook in the core mod batman_CoreAI (E21-T03, slice 1).

    python RadioSurvivor/tests/coreai/test_core_npc_provider.py

CA_NPCProvider (shared/CoreAI/CA_NPCProvider.lua) is loaded with the core mod alone on package.path (no RadioSurvivor
nor Living Knox file):
- one provider at a time: registration, reload of the same provider, refusal of a second one, logged under
  [CA_NPCProvider];
- the default provider is empty (no NPC, no body, not available) and the speech bubble falls back to the vanilla
  addLineChatElement with the chat id CA_Speech;
- the optional operations of the shared notebook (isBody, speech, relationOffer, relationApply, relationPanel,
  debugPair, contacts, name) have neutral defaults, and delegate to the provider that defines them with their arguments.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
CORE_SHARED = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua' / 'shared'

PRELUDE = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, ' ') end
UIFont = { Medium = 'Medium' }
"""


class Base(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('package.path = ...; package.cpath = ""', CORE_SHARED.as_posix() + '/?.lua')
        self.lua.execute(PRELUDE)
        self.P = self.lua.eval('require("CoreAI/CA_NPCProvider")')

    def logs(self):
        return list(self.lua.eval('LOGS').values())

    def register(self, code):
        return self.lua.execute('return require("CoreAI/CA_NPCProvider").register(' + code + ')')


class RegistrationTests(Base):
    def test_one_provider_at_a_time_logged_under_its_prefix(self):
        self.assertTrue(self.register('{name = "fake"}'))
        self.assertTrue(self.register('{name = "fake"}'))
        self.assertFalse(self.register('{name = "other"}'))
        self.assertFalse(self.register('"junk"'))
        self.assertEqual(self.logs(), [
            '[CA_NPCProvider] provider fake registered',
            '[CA_NPCProvider] provider fake registered again (reload)',
            '[CA_NPCProvider] refused provider other: provider fake is already active',
            '[CA_NPCProvider] refused provider junk: not a table'])
        self.assertEqual(self.P.active().name, 'fake')
        self.assertEqual(self.P.name(), 'fake')

    def test_default_provider_is_empty(self):
        self.assertEqual(self.P.active().name, 'none')
        self.assertEqual(self.P.name(), 'none')
        self.assertFalse(self.P.available())
        self.assertEqual(len(list(self.P.objects().keys())), 0)
        self.assertIsNone(self.P.id(self.lua.eval('{}')))
        self.assertIsNone(self.P.npc(1))


class BubbleTests(Base):
    def test_vanilla_bubble_uses_the_core_chat_id(self):
        self.lua.execute(r"""
            BODY = { isDead = function() return false end,
                addLineChatElement = function(self, ...) LINE = { ... } end }
            require('CoreAI/CA_NPCProvider').bubble(BODY, 'hello', 12)
        """)
        line = list(self.lua.eval('LINE').values())
        self.assertEqual(line[0], 'hello')
        self.assertEqual(line[5], 12)
        self.assertEqual(line[6], 'CA_Speech')


OPTIONAL = r"""
CALLS = {}
local function record(name, ...) CALLS[#CALLS + 1] = name .. ':' .. table.concat({ ... }, ',') end
require('CoreAI/CA_NPCProvider').register({
    name = 'fake',
    available = function() return AVAILABLE end,
    isBody = function(object, md) record('isBody', object.tag, md.tag) return true end,
    speech = function() record('speech') return SPEECH end,
    relationOffer = function(npc, c) record('relationOffer', npc, c) return { level = 'wary' }, 'b1' end,
    relationApply = function(npc, c, b, dir, fact) record('relationApply', npc, c, b, dir, fact) return { applied = true } end,
    relationPanel = function(npc, c, team) record('relationPanel', npc, c, team.id) return { facts = {} } end,
    debugPair = function(npc, c) record('debugPair', npc, c) return { gap = 3 } end,
    contacts = function(c) record('contacts', c) return CONTACTS end,
})
"""


class OptionalOperationsTests(Base):
    def test_neutral_defaults_without_a_provider(self):
        P = self.P
        body, md = self.lua.eval('{}'), self.lua.eval('{}')
        self.assertIs(P.isBody(body, md), False)
        self.assertIsNone(P.speech())
        self.assertEqual(P.relationOffer('n1', 'c1'), None)
        self.assertEqual(P.relationApply('n1', 'c1', 'b1', 1, 'helped'), (None, 'unsupported'))
        self.assertIsNone(P.relationPanel('n1', 'c1', self.lua.eval('{id = "t"}')))
        self.assertIsNone(P.debugPair('n1', 'c1'))
        self.assertEqual(len(list(P.contacts('c1').keys())), 0)

    def test_operations_delegate_to_the_provider(self):
        self.lua.execute(OPTIONAL)
        self.lua.execute('AVAILABLE = true; SPEECH = { turns = function() end }; CONTACTS = { "n1", "n2" }')
        P = self.P
        self.assertIs(P.isBody(self.lua.eval('{tag = "o"}'), self.lua.eval('{tag = "m"}')), True)
        self.assertTrue(self.lua.eval('function(s) return rawequal(s, SPEECH) end')(P.speech()))
        relation, binding = P.relationOffer('n1', 'c1')
        self.assertEqual((relation.level, binding), ('wary', 'b1'))
        self.assertTrue(P.relationApply('n1', 'c1', 'b1', 1, 'helped').applied)
        self.assertEqual(len(list(P.relationPanel('n1', 'c1', self.lua.eval('{id = "t"}')).facts.keys())), 0)
        self.assertEqual(P.debugPair('n1', 'c1').gap, 3)
        self.assertEqual(list(P.contacts('c1').values()), ['n1', 'n2'])
        self.assertEqual(list(self.lua.eval('CALLS').values()), [
            'isBody:o,m', 'speech:', 'relationOffer:n1,c1', 'relationApply:n1,c1,b1,1,helped',
            'relationPanel:n1,c1,t', 'debugPair:n1,c1', 'contacts:c1'])

    def test_engine_not_ready_keeps_the_defaults_except_body_tags(self):
        self.lua.execute(OPTIONAL)
        self.lua.execute('AVAILABLE = false; SPEECH = {}; CONTACTS = { "n1" }')
        P = self.P
        # A body tag stays readable while the engine is not ready (corpses of an earlier session).
        self.assertIs(P.isBody(self.lua.eval('{tag = "o"}'), self.lua.eval('{tag = "m"}')), True)
        self.assertIsNone(P.speech())
        self.assertIsNone(P.relationOffer('n1', 'c1'))
        self.assertEqual(P.relationApply('n1', 'c1', 'b1', 1, 'helped'), (None, 'unsupported'))
        self.assertIsNone(P.relationPanel('n1', 'c1', self.lua.eval('{id = "t"}')))
        self.assertIsNone(P.debugPair('n1', 'c1'))
        self.assertEqual(len(list(P.contacts('c1').keys())), 0)

    def test_malformed_answers_are_neutral(self):
        self.lua.execute(OPTIONAL)
        self.lua.execute('AVAILABLE = true; SPEECH = "junk"; CONTACTS = 5')
        self.assertIsNone(self.P.speech())
        self.assertEqual(len(list(self.P.contacts('c1').keys())), 0)
        self.assertIs(self.P.isBody(None, None), False)


if __name__ == '__main__':
    unittest.main(verbosity=1)
