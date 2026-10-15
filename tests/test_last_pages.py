"""Dernières pages d'un personnage du carnet (E15-T03) : banc hors jeu, vrai Lua du mod sous lupa (API du jeu simulée)
et vrai pont (bridge/radio_bridge.py, bridge/last_pages.py) en mode hors ligne, dans le même processus.

    python RadioSurvivor/tests/test_last_pages.py

- BridgeUnitTests : contrat de la demande last_pages côté pont (enveloppe, faits bornés, refus d'une charge mal formée),
  prompt (faits seuls, langue, mission ouverte jamais accomplie, ni coordonnée ni fréquence), texte nettoyé et borné,
  réponse hors ligne, échec.
- RoundTripTests : mort d'un personnage du carnet -> une demande kind=last_pages dans requests.txt (faits, sans
  coordonnée, sans jeton) -> vrai pont hors ligne -> responses.txt -> document dans le cadavre marqué (pages écrites,
  verrouillé, nom, jeton), relevé libéré, demande retirée, un seul document même après d'autres passages.
- FallbackTests : sans pont (délai), réponse d'erreur, demande expirée, redémarrage qui perd la demande : journal de
  secours fidèle aux faits ; mort en feu : au sol ; case non chargée : attente ; aucun relevé : aucune demande ;
  traductions absentes sur le serveur : rechargées une fois ; textes anglais par défaut sinon ; solo sans envoi réseau.
- OptionTests (E15-T04) : option sandbox RadioSurvivor.LastPages déclarée (booléen, activée par défaut, traductions EN
  et FR), option enregistrée lue avant SandboxVars ; désactivée : aucun relevé, aucun secours noté, aucune demande ni
  jeton ni document à la mort ; coupée après une mort : demande retirée du fichier du pont, relevé figé libéré, rien
  posé même texte prêt ou option rétablie ; relevés vivants effacés puis repris de zéro à la réactivation.
- LayoutTests : texte nettoyé et borné, mise en pages bornée (PAGES pages de LINES lignes).
- SuiteTests : la suite en jeu rs.lastpages passe sur ce banc.
Simulation, PAS validation en jeu.
"""
from __future__ import annotations

import json
import sys
import time
import unittest
from pathlib import Path

from harness import Harness, ROOT
from test_lifelog import SETUP, py, values

sys.path.insert(0, str(ROOT / 'bridge'))
import last_pages  # noqa: E402
import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402

TRANSLATE = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/Translate'
DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'


def lua_str(s: str) -> str:
    """Littéral Lua ASCII : caractères non ASCII en échappements décimaux de leurs octets UTF-8."""
    return '"' + ''.join(c if (32 <= ord(c) < 127 and c not in '"\\') else ''.join('\\%d' % b for b in c.encode('utf-8'))
                         for c in s) + '"'


def text_table(lang: str) -> str:
    table = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
    rows = ',\n'.join(f'[{lua_str(k)}] = {lua_str(v)}' for k, v in table.items()
                      if k.startswith('IGUI_RS_LastPages_'))
    return '{\n' + rows + '\n}'


DOUBLES = r'''
local H = HARNESS
local C = H.classes
COUNT = { sent = 0, ground = 0, reload = 0 }

-- Objets d'inventaire et documents Literature (Literature.java:280-286, 446-482).
local Item = H.class('InventoryItem')
function Item:getModData() local md = rawget(self, 'md') if not md then md = {} self.md = md end return md end
function Item:hasModData() return rawget(self, 'md') ~= nil end
function Item:getFullType() return self.type end
function Item:setName(n) self.name = n end
function Item:getName() return self.name end
function Item:setCustomName(b) self.custom = b end
function Item:getContainer() return rawget(self, 'container') end
function Item:getWorldItem() return rawget(self, 'world') end
local Lit = H.class('Literature', Item)
function Lit:addPage(i, text)
    if type(i) ~= 'number' or type(text) ~= 'string' then error('No implementation found for addPage', 2) end
    self.pages[i] = string.sub(text, 1, 16384)
end
function Lit:seePage(i) return self.pages[i] end
function Lit:getCustomPages() local n = 0 for _ in pairs(self.pages) do n = n + 1 end return H.list(self.pages) end
function Lit:setLockedBy(n) self.lockedBy = n end
function Lit:getLockedBy() return self.lockedBy end
instanceItem = function(t)
    if t == 'Base.Notebook' then return setmetatable({ type = t, pages = {} }, Lit) end
    return nil
end

-- Conteneur d'un cadavre et cadavre (IsoDeadBody.java:327-333 : conteneur du mort ; 378 : ModData recopiées).
local Cont = H.class('ItemContainer')
function Cont:getItems() return self.items end
function Cont:getParent() return self.parent end
function Cont:AddItem(it) self.items:add(it) it.container = self return it end
function Cont:Remove(it) H.listRemove(self.items, it) it.container = nil end
local Body = H.class('IsoDeadBody', C.IsoObject)
function Body:getContainer() return self.container end
function Body:setFakeDead(v) self.fakeDead = v end
function C.IsoGridSquare:getStaticMovingObjects()
    local l = rawget(self, 'statics') if not l then l = H.list() self.statics = l end return l
end
function C.IsoGridSquare:removeCorpse(b) H.listRemove(self:getStaticMovingObjects(), b) b.square = nil end
function CORPSE(p, dx)
    local sq = H.square(p.x + (dx or 0), p.y, p.z)
    local body = setmetatable({ x = sq.x, y = sq.y, z = sq.z, square = sq }, Body)
    body.container = setmetatable({ items = H.list(), parent = body }, Cont)
    if p.getModData then
        for k, v in pairs(p:getModData()) do body:getModData()[k] = v end
    end
    sq:getStaticMovingObjects():add(body)
    return body
end
sendAddItemToContainer = function(c, it)
    if not isServer() then error('sendAddItemToContainer called off the server', 2) end
    COUNT.sent = COUNT.sent + 1
end
sendRemoveItemFromContainer = function() end

-- Sol (IsoGridSquare.java:5200-5205, objet préparé transmis).
local WorldItem = H.class('IsoWorldInventoryObject', C.IsoObject)
function WorldItem:getItem() return self.item end
function C.IsoGridSquare:getWorldObjects()
    local l = rawget(self, 'worldObjects') if not l then l = H.list() self.worldObjects = l end return l
end
function C.IsoGridSquare:AddWorldInventoryItem(it, x, y, h, transmit)
    local w = setmetatable({ item = it, square = self }, WorldItem)
    it.world = w
    self:getWorldObjects():add(w)
    if transmit then COUNT.ground = COUNT.ground + 1 end
    return it
end
function C.IsoGridSquare:transmitRemoveItemFromSquare(w) H.listRemove(self:getWorldObjects(), w) w.square = nil end
RandomizedWorldBase = { createRandomDeadBody = function(sq) return CORPSE({ x = sq.x, y = sq.y, z = sq.z }) end }
IsoDirections = { S = 'S' }

-- Cases non chargées (IsoCell.getGridSquare rend nil).
UNLOADED = {}
local rawSquare = C.IsoCell.getGridSquare
function C.IsoCell:getGridSquare(x, y, z)
    if UNLOADED[math.floor(x) .. ',' .. math.floor(y)] then return nil end
    return rawSquare(self, x, y, z)
end

-- Personnage : feu (IsoGameCharacter.isOnFire) ; métier affiché (CharacterProfessionDefinition.getUIName).
function C.IsoGameCharacter:isOnFire() return self.fire == true end
PROF_UI = { doctor = 'Doctor', policeofficer = 'Police Officer' }
CharacterProfessionDefinition = { getCharacterProfessionDefinition = function(prof)
    local name = PROF_UI[prof:getName()]
    if not name then return nil end
    return { getUIName = function() return name end }
end }

-- Documents de ce jeton : cadavres et sol des cases autour de (x, y).
function FIND(token, x, y, z)
    local found = {}
    for dy = -3, 3 do
        for dx = -3, 3 do
            local sq = H.square(x + dx, y + dy, z or 0)
            for _, b in ipairs(sq:getStaticMovingObjects().items) do
                for _, it in ipairs(b.container.items.items) do
                    if it:hasModData() and it:getModData().RS_LastPagesToken == token then
                        found[#found + 1] = { where = 'corpse', item = it }
                    end
                end
            end
            for _, w in ipairs(sq:getWorldObjects().items) do
                local it = w.item
                if it:hasModData() and it:getModData().RS_LastPagesToken == token then
                    found[#found + 1] = { where = 'ground', item = it }
                end
            end
        end
    end
    return found
end
'''


def text_doubles(lang: str, loaded: bool) -> str:
    return (f'local TABLE = {text_table(lang)}\nLANG = {lua_str(lang)}\n' + r'''
KEYS = ''' + ('TABLE' if loaded else '{}') + r'''
local function fmt(text, ...)
    local args = { ... }
    return (string.gsub(text, '%%(%d)', function(d) return tostring(args[tonumber(d)] or '') end))
end
getTextOrNull = function(key, ...) local t = KEYS[key] if t == nil then return nil end return fmt(t, ...) end
getText = function(key, ...) local t = KEYS[key] if t == nil then return key end return fmt(t, ...) end
NO_RELOAD = false
Translator = {
    getLanguage = function() return { name = function() return LANG end } end,
    loadFiles = function() COUNT.reload = COUNT.reload + 1 if not NO_RELOAD then KEYS = TABLE end end,
}
''')


FACTS = r'''
local p = HARNESS.players.A
p.kills, p.hours, p.prof = 41, 100.25, 'doctor'
Log.add('char-a', 145000, 'said', 'If anyone hears this, the church is safe.')
S.data.missions['m1'] = { id = 'm1', npc = 'v', template = 'scout', state = 'success', requesterName = 'Walt',
    placeKind = 'church', participants = { ['char-a'] = true } }
S.data.missions['m2'] = { id = 'm2', npc = 'v', template = 'deliver', state = 'active', requesterName = 'Marla',
    placeKind = 'farm', participants = { ['char-a'] = true } }
'''


class Bench(unittest.TestCase):
    mode = 'mp'
    lang = 'EN'
    loaded = True

    def setUp(self):
        self.h = Harness(mode=self.mode, clients=('A', 'B'), lua_roots=[DEV_LUA])
        self.h.server.g.NEW_WORLD = True
        self.h.load('server', SETUP)
        self.h.load('server', DOUBLES)
        self.h.load('server', text_doubles(self.lang, self.loaded))
        self.h.load('server', "LastPages = require 'RadioSurvivor/RS_LastPages'; "
                              "Transport = require 'RadioSurvivor/RS_Transport'")
        self.exchange = self.h.file_root('server') / 'batman_RadioSurvivor'

    def tearDown(self):
        self.h.close()

    def lua(self, code):
        return self.h.load('server', code)

    def ev(self, expr):
        return self.h.eval('server', expr)

    def now_clock(self):
        """Horloge réelle du banc mise à l'heure : le pont refuse une demande de plus de 120 s."""
        self.h.advance_ms(int(time.time() * 1000) - self.h.real_ms)

    def die(self, user='A', x=200, y=300, fire=False, corpse=True):
        self.h.move_player(user, x, y)
        if fire:
            self.lua(f"HARNESS.players.{user}.fire = true")
        self.h.kill_player(user)
        if corpse:
            self.lua(f"BODY = CORPSE(HARNESS.players.{user})")

    def requests(self):
        path = self.exchange / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def pages_request(self):
        parsed = rb.read_requests(self.exchange / 'requests.txt')
        self.assertIsNotNone(parsed)
        session, requests = parsed
        mine = [r for r in requests if r.get('kind') == last_pages.KIND]
        return session, requests, mine

    def run_bridge(self, config=None):
        session, requests, _ = self.pages_request()
        bridge = rb.Bridge(config or {'OFFLINE': '1', 'OPENAI_MODEL': 'offline'}, self.exchange)
        bridge._sync(session, requests)
        bridge.pool.shutdown(wait=True)
        return bridge

    def after_delay(self, ms=None):
        self.h.advance_ms(ms if ms is not None else self.ev('LastPages.DELAY_MS'))
        self.lua('LastPages.poll()')

    def found(self, token, x=200, y=300):
        return [(f['where'], f['item']) for f in values(self.ev(f"FIND('{token}', {x}, {y}, 0)"))]

    def pages_text(self, item):
        return '\n'.join(item.pages[i] for i in sorted(item.pages))


class BridgeUnitTests(unittest.TestCase):
    FACTS = {'hours': 100.2, 'kills': 41, 'profession': 'Doctor', 'death': '07/12 21:05',
             'towns': {1: 'Muldraugh', 2: 'West Point'}, 'phrases': {1: 'If anyone hears this, the church is safe.'},
             'missions': {1: {'template': 'scout', 'result': 'success', 'requester': 'Walt', 'place': 'church'}},
             'open': {1: {'template': 'deliver', 'result': 'open', 'requester': 'Marla', 'place': 'farm'}},
             'rescues': {}, 'totals': {'success': 1, 'failed': 0, 'cancelled': 0, 'saved': 0, 'missed': 0}}

    def record(self, **change):
        value = {'id': '17-1-pages', 'kind': 'last_pages', 'sent': 17, 'language': 'FR', 'name': 'Kate Doe',
                 'facts': dict(self.FACTS)}
        value.update(change)
        return {'id': '17-1-pages', 'kind': 'last_pages', 'payload': npc.encode(value).hex()}

    def test_unpack_checks_the_envelope_and_bounds(self):
        req = last_pages.unpack(self.record())
        self.assertEqual(req['facts']['towns'], ['Muldraugh', 'West Point'])
        self.assertEqual(req['facts']['open'][0]['requester'], 'Marla')
        bad = [self.record(id='other'), self.record(kind='npc_talk'), self.record(language='fr'),
               self.record(sent=-1), self.record(name=''), self.record(facts='x'),
               self.record(facts=dict(self.FACTS, towns={i: 't' for i in range(1, 20)})),
               self.record(facts=dict(self.FACTS, rescues={1: {'outcome': 'won', 'label': 'x'}})),
               self.record(facts=dict(self.FACTS, kills=-3)),
               {'id': '17-1-pages', 'kind': 'last_pages', 'payload': 'zz'}]
        for record in bad:
            with self.assertRaises(ValueError, msg=record):
                last_pages.unpack(record)

    def test_prompt_uses_the_facts_only(self):
        req = last_pages.unpack(self.record())
        system = last_pages.prompt(req)[0]['content']
        self.assertIn('Write in French', system)
        self.assertIn('Use ONLY the facts below', system)
        self.assertIn('Never describe how you died', system)
        self.assertIn('4 days and 4 hours', system)
        self.assertIn('Zombies you killed: 41', system)
        self.assertIn('scout for Walt (a church): completed', system)
        self.assertIn('deliver for Marla (a farm): NOT finished', system)
        self.assertIn('"If anyone hears this, the church is safe."', system)
        self.assertNotIn('khz', system.lower())

    def test_clean_text_keeps_paragraphs_and_bounds(self):
        self.assertEqual(last_pages.clean_text('```\nDay one.  <b>x</b>\n\n\n[sigh] Day two.\r\n'),
                         'Day one. b x /b\n\nsigh Day two.')
        long = ' '.join(['word'] * 1000) + '.'
        self.assertLessEqual(len(last_pages.clean_text(long).encode()), last_pages.MAX_TEXT_BYTES)
        with self.assertRaises(ValueError):
            last_pages.clean_text(' \n <> ')

    def test_write_offline_model_and_failure(self):
        req = last_pages.unpack(self.record())
        self.assertEqual(last_pages.write({'OFFLINE': '1'}, req, None)['text'],
                         'Offline last pages of Kate Doe. 100 hours survived, 41 zombies killed. '
                         'Towns: Muldraugh, West Point.')
        seen = []
        result = last_pages.write({}, req, lambda config, messages, speaker: seen.append(speaker) or 'Day 4. Still here.')
        self.assertEqual(result, {'kind': 'last_pages_reply', 'id': '17-1-pages', 'text': 'Day 4. Still here.'})
        self.assertEqual(seen, ['Kate'])
        self.assertEqual(last_pages.failure(req, 'expired'),
                         {'kind': 'last_pages_reply', 'id': '17-1-pages', 'error': 'expired'})

    def test_bridge_failure_answers_with_an_error_payload(self):
        req = last_pages.unpack(self.record())
        req['sent'] = str(int(__import__('time').time() * 1000))   # E17-T15: an older request is answered `expired`
        with __import__('tempfile').TemporaryDirectory() as tmp:
            bridge = rb.Bridge({'OPENAI_MODEL': 'x', 'OPENAI_BASE_URL': 'http://127.0.0.1:9', 'OPENAI_KEY': 'k'},
                               Path(tmp))
            saved = rb.call_llm
            rb.call_llm = lambda *a, **k: (_ for _ in ()).throw(RuntimeError('down'))
            try:
                bridge.current = {req['id']: bridge._token('s', req)}
                bridge._handle('s', req)
            finally:
                rb.call_llm = saved
                bridge.pool.shutdown(wait=True)
            self.assertEqual(bridge.answers[req['id']]['error'], 'invalid_or_unavailable')
            self.assertEqual(bridge._group('s', req), ('last_pages', req['id']))


class RoundTripTests(Bench):
    def test_bridge_text_in_the_marked_corpse_once(self):
        self.lua("bind('A', 'char-a'); bind('B', 'char-b')")
        self.lua('LifeLog.poll()')
        self.lua(FACTS)
        self.h.move_player('A', 10754, 9926)   # Muldraugh
        self.lua('LifeLog.poll()')
        self.now_clock()
        self.die(x=200, y=300)
        token = self.ev("HARNESS.players.A:getModData().RS_LastPagesToken")
        self.assertRegex(token, r'^lp-\d+-\d+$')
        self.assertEqual(self.ev("BODY:getModData().RS_LastPagesToken"), token)
        # One request, facts only: no coordinate, frequency or token in it.
        _, _, mine = self.pages_request()
        self.assertEqual(len(mine), 1)
        req = last_pages.unpack(mine[0])
        self.assertEqual(req['facts']['name'], 'A')
        self.assertEqual(req['facts']['profession'], 'Doctor')
        self.assertEqual(req['facts']['towns'], ['Muldraugh'])
        self.assertEqual([m['result'] for m in req['facts']['open']], ['open'])
        decoded = npc.decode(bytes.fromhex(mine[0]['payload']))

        def keys(value):
            return set(value) | {k for v in value.values() if isinstance(v, dict) for k in keys(v)}                 if isinstance(value, dict) else set()
        self.assertFalse(keys(decoded) & {'x', 'y', 'z', 'khz', 'token', 'cid', 'username'}, keys(decoded))
        self.assertNotIn(token, repr(decoded))
        self.assertNotIn('145000', repr(decoded))
        # The bridge answers; before DELAY_MS nothing is placed.
        self.run_bridge()
        self.lua('LastPages.poll()')
        self.assertEqual(self.found(token), [])
        self.assertEqual(self.ev("LifeLog.get('char-a').pages.state"), 'ready')
        self.assertEqual(self.ev("LifeLog.get('char-a').pages.source"), 'bridge')
        self.assertNotIn('kind=last_pages', self.requests(), 'request kept after its answer')
        self.after_delay()
        docs = self.found(token)
        self.assertEqual([w for w, _ in docs], ['corpse'])
        item = docs[0][1]
        self.assertEqual(item.type, 'Base.Notebook')
        self.assertEqual(item.lockedBy, 'RadioSurvivor')
        self.assertEqual(item.name, 'Last pages of A')
        self.assertTrue(item.custom)
        text = self.pages_text(item)
        self.assertTrue(text.startswith('The last pages of A\n\nOffline last pages of A.'), text)
        self.assertEqual(' '.join(text.split()), 'The last pages of A Offline last pages of A. 100 hours survived, '
                                                 '41 zombies killed. Towns: Muldraugh.')
        self.assertTrue(all(len(line) <= 40 for line in text.split('\n')), text)
        self.assertEqual(self.ev('COUNT.sent'), 1)
        self.assertIsNone(self.ev("LifeLog.get('char-a')"), 'frozen log not released')
        # Later passes, a second death event: never a second document.
        self.after_delay(10000)
        self.lua("LifeLog.characterDeath(HARNESS.players.A)")
        self.after_delay(100000)
        self.assertEqual(len(self.found(token)), 1)
        self.assertEqual(self.ev('COUNT.sent'), 1)
        self.assertIsNotNone(self.ev("LifeLog.get('char-b')"))
        self.assertEqual(self.h.errors('server'), [])


class FallbackTests(Bench):
    def setUp(self):
        super().setUp()
        self.lua("bind('A', 'char-a')")
        self.lua('LifeLog.poll()')
        self.lua(FACTS)
        self.h.move_player('A', 10754, 9926)
        self.lua('LifeLog.poll()')

    def token(self):
        return self.ev("HARNESS.players.A:getModData().RS_LastPagesToken")

    def test_no_bridge_fallback_journal_faithful_to_the_facts(self):
        self.die()
        self.after_delay()
        self.assertEqual(self.found(self.token()), [], 'placed before the bridge delay')
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        docs = self.found(self.token())
        self.assertEqual([w for w, _ in docs], ['corpse'])
        text = self.pages_text(docs[0][1])
        for part in ('The last pages of A', 'I have held on for 4 days and 4 hours', 'Before all this, I was: Doctor.',
                     'I have put down 41 of the dead.', 'I went through Muldraugh.',
                     'I took on jobs for other survivors: 1 done, 0 failed, 0 dropped.',
                     'I never finished what I promised to Marla.', 'My last words on the radio:',
                     '- If anyone hears this, the church is safe.', 'these were my last pages.'):
            self.assertIn(part, ' '.join(text.split()))
        self.assertNotIn('kind=last_pages', self.requests())
        self.assertEqual(values(py(self.ev("LifeLog.frozen()"))), [])

    def test_error_or_expired_answer_gives_the_fallback_at_once(self):
        self.die()   # bench clock far in the past: the bridge expires the request
        self.run_bridge()
        self.after_delay()
        docs = self.found(self.token())
        self.assertEqual(len(docs), 1)
        self.assertIn('I have put down 41 of the dead.', self.pages_text(docs[0][1]))

    def alive(self):
        """E17-T16: heartbeat of a running bridge at the bench clock (bridge/radio_bridge.py write_alive)."""
        rb.write_alive(self.exchange / rb.ALIVE_FILE, self.h.real_ms)

    def wait_alive(self, total_ms, step_ms=5000):
        """Bench clock moved by total_ms with a fresh heartbeat every step_ms (a running bridge), polled each time."""
        for _ in range(total_ms // step_ms):
            self.alive()
            self.after_delay(step_ms)

    def test_bridge_alive_answer_after_130_s_is_used(self):
        """E17-T16: a bridge seen alive may answer up to 135 s after the request: its text at 130 s is kept."""
        self.assertGreaterEqual(self.ev("require('RadioSurvivor/RadioSurvivor_Const').BRIDGE_TIMEOUT_MS"),
                                (rb.MAX_AGE_S + rb.LLM_BUDGET_S) * 1000 + 5000)
        self.now_clock()
        self.alive()
        self.die()
        self.wait_alive(130000)
        self.assertEqual(self.found(self.token()), [], 'fallback before the bridge bound')
        self.assertEqual(self.ev("LifeLog.get('char-a').pages.state"), 'asked')
        self.run_bridge()
        self.after_delay()
        docs = self.found(self.token())
        self.assertEqual(len(docs), 1)
        self.assertIn('Offline last pages of A.', ' '.join(self.pages_text(docs[0][1]).split()))
        self.assertEqual(self.h.errors('server'), [])

    def test_bridge_alive_but_silent_fallback_after_the_long_delay(self):
        self.alive()
        self.die()
        self.wait_alive(145000)
        self.assertEqual(self.found(self.token()), [])
        self.wait_alive(10000)
        self.assertEqual(len(self.found(self.token())), 1)

    def test_stale_heartbeat_keeps_the_short_delay(self):
        """A bridge stopped without removing its file (crash): heartbeat older than ALIVE_STALE_MS = no bridge."""
        self.alive()
        self.die()
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.after_delay()
        self.assertEqual(len(self.found(self.token())), 1)

    def test_restart_losing_the_request_gives_the_fallback(self):
        self.die()
        self.lua('LastPages.resetForTests()')   # in-memory request lost, as after a restart
        self.after_delay()
        self.assertEqual(len(self.found(self.token())), 1)

    def test_on_fire_on_the_ground(self):
        self.die(fire=True)
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual([w for w, _ in self.found(self.token())], ['ground'])
        self.assertEqual(self.ev('COUNT.ground'), 1)
        self.assertEqual(self.ev('COUNT.sent'), 0)

    def test_corpse_gone_on_the_ground_and_unloaded_square_waits(self):
        self.die(corpse=False)
        self.lua("UNLOADED['200,300'] = true")
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual(self.found(self.token()), [])
        self.assertEqual(self.ev("LifeLog.get('char-a').pages.state"), 'ready')
        self.lua("UNLOADED['200,300'] = nil")
        self.after_delay(0)
        self.assertEqual([w for w, _ in self.found(self.token())], ['ground'])

    def test_no_identity_no_request(self):
        self.lua("RS_CarnetServer.bound = {}; HARNESS.players.B.kills = 1")
        self.h.kill_player('B')
        self.assertNotIn('kind=last_pages', self.requests())
        self.assertIsNone(self.ev("HARNESS.players.B:getModData().RS_LastPagesToken"))


class MissingTranslationsTests(Bench):
    loaded = False

    def test_server_reloads_the_mod_translations_once(self):
        self.lua("bind('A', 'char-a'); LifeLog.poll()")
        self.die()
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual(self.ev('COUNT.reload'), 1)
        self.assertEqual(len(self.found(self.ev("HARNESS.players.A:getModData().RS_LastPagesToken"))), 1)

    def test_english_defaults_without_any_translation(self):
        self.lua("NO_RELOAD = true; bind('A', 'char-a'); LifeLog.poll()")
        self.die()
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        docs = self.found(self.ev("HARNESS.players.A:getModData().RS_LastPagesToken"))
        self.assertIn('I have not had to kill any of them.', self.pages_text(docs[0][1]))
        self.assertEqual(self.ev('COUNT.reload'), 1)


class FrenchTests(Bench):
    lang = 'FR'

    def test_french_fallback(self):
        self.lua("bind('A', 'char-a'); LifeLog.poll(); HARNESS.players.A.kills = 2; LifeLog.poll()")
        self.die()
        _, _, mine = self.pages_request()
        self.assertEqual(last_pages.unpack(mine[0])['language'], 'FR')
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        docs = self.found(self.ev("HARNESS.players.A:getModData().RS_LastPagesToken"))
        self.assertIn('J\'ai abattu 2 de ces morts.', self.pages_text(docs[0][1]))


class SoloTests(Bench):
    mode = 'solo'

    def test_solo_corpse_without_network_send(self):
        self.lua("bind('A', 'char-s', 'solo'); LifeLog.poll()")
        self.die()
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual([w for w, _ in self.found(self.ev("HARNESS.players.A:getModData().RS_LastPagesToken"))],
                         ['corpse'])
        self.assertEqual(self.ev('COUNT.sent'), 0)


class LayoutTests(Bench):
    def test_clean_text_and_layout_bounds(self):
        self.assertEqual(self.ev(r'LastPages.cleanText("a\r\nb <i>[c]</i>\1")'), 'a\nb  i  c  /i  ')
        self.assertIsNone(self.ev('LastPages.cleanText("  <>  ")'))
        long = self.ev('LastPages.cleanText(string.rep("word ", 2000))')
        self.assertLessEqual(len(long), self.ev('LastPages.MAX_TEXT') + 3)
        pages = values(py(self.ev('LastPages.layout(string.rep("line of text\\n", 400))')))
        self.assertEqual(len(pages), self.ev('LastPages.PAGES'))
        self.assertTrue(all(len(p.split('\n')) <= self.ev('LastPages.LINES') for p in pages))
        self.assertTrue(pages[-1].endswith(' ...'))
        wrapped = values(py(self.ev('LastPages.layout(string.rep("abcdefghi ", 20))')))[0].split('\n')
        self.assertTrue(all(len(line) <= self.ev('LastPages.WIDTH') for line in wrapped))


SANDBOX = Path(__file__).resolve().parent.parent / 'Contents/mods/batman_RadioSurvivor/42.21/media/sandbox-options.txt'

# Option enregistrée (SandboxOptions.getOptionByName -> BooleanSandboxOption : getValue, getDefaultValue), lue en
# premier par RadioSurvivor_Const ; les autres options restent lues dans SandboxVars.
REGISTERED = r'''
REGISTERED_LASTPAGES = true
getSandboxOptions = function()
    return { getOptionByName = function(_, name)
        if name ~= 'RadioSurvivor.LastPages' then return nil end
        return { getValue = function() return REGISTERED_LASTPAGES end, getDefaultValue = function() return true end }
    end }
end
'''


class OptionTests(Bench):
    """E15-T04 : option sandbox RadioSurvivor.LastPages ; désactivée = aucun relevé ni document."""

    def off(self):
        self.lua('SandboxVars.RadioSurvivor.LastPages = false')

    def on(self):
        self.lua('SandboxVars.RadioSurvivor.LastPages = true')

    def token(self, user='A'):
        return self.ev(f"HARNESS.players.{user}:getModData().RS_LastPagesToken")

    def test_declared_on_by_default_with_translations(self):
        text = SANDBOX.read_text(encoding='utf-8')
        block = text[text.index('option RadioSurvivor.LastPages'):]
        block = block[:block.index('}') + 1]
        for line in ('type = boolean,', 'default = true,', 'page = RadioSurvivor,',
                     'translation = RadioSurvivor_LastPages,'):
            self.assertIn(line, block)
        for lang in ('EN', 'FR'):
            table = json.loads((TRANSLATE / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            self.assertTrue(table.get('Sandbox_RadioSurvivor_LastPages'), lang)
            self.assertTrue(table.get('Sandbox_RadioSurvivor_LastPages_tooltip'), lang)
        # Absente de SandboxVars et non enregistrée : activée.
        self.assertIs(self.ev("require('RadioSurvivor/RadioSurvivor_Const').lastPages()"), True)

    def test_registered_option_read_first(self):
        self.lua(REGISTERED)
        self.lua("SandboxVars.RadioSurvivor.LastPages = true; REGISTERED_LASTPAGES = false")
        self.assertIs(self.ev("require('RadioSurvivor/RadioSurvivor_Const').lastPages()"), False)
        self.lua("bind('A', 'char-a'); LifeLog.poll()")
        self.assertIsNone(self.ev("LifeLog.get('char-a')"))

    def test_off_no_log_no_request_no_document(self):
        self.off()
        self.lua("bind('A', 'char-a')")
        self.lua('LifeLog.poll()')
        self.lua(FACTS)
        self.h.move_player('A', 10754, 9926)
        self.lua('LifeLog.poll()')
        self.assertIsNone(self.ev("LifeLog.get('char-a')"))
        self.assertFalse(self.ev("LifeLog.rescue('char-a', 'saved', 'x')"))
        self.die()
        self.assertIsNone(self.token())
        self.assertNotIn('kind=last_pages', self.requests())
        self.assertEqual(values(py(self.ev('LifeLog.frozen()'))), [])
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual(self.ev('#BODY.container.items.items'), 0)
        self.assertEqual(self.ev('#HARNESS.square(200, 300, 0):getWorldObjects().items'), 0)
        self.assertEqual(self.ev('COUNT.sent') + self.ev('COUNT.ground'), 0)
        self.assertEqual(self.h.errors('server'), [])

    def test_turned_off_after_death_withdraws_request_and_places_nothing(self):
        self.lua("bind('A', 'char-a'); LifeLog.poll()")
        self.die()
        token = self.token()
        self.assertIsNotNone(token)
        self.assertIn('kind=last_pages', self.requests())
        self.off()
        self.lua('LastPages.poll()')
        self.assertNotIn('kind=last_pages', self.requests(), 'request kept after the option was turned off')
        self.assertIsNone(self.ev("LifeLog.get('char-a')"))
        self.on()
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual(self.found(token), [])
        self.assertEqual(self.h.errors('server'), [])

    def test_text_ready_then_off_places_nothing(self):
        self.lua("bind('A', 'char-a'); LifeLog.poll()")
        self.die()
        token = self.token()
        self.lua("UNLOADED['200,300'] = true")   # text ready, death square not loaded: not placed yet
        self.after_delay(self.ev('LastPages.TIMEOUT_MS'))
        self.assertEqual(self.ev("LifeLog.get('char-a').pages.state"), 'ready')
        self.off()
        self.lua("UNLOADED['200,300'] = nil")
        self.lua('LastPages.poll()')
        self.assertIsNone(self.ev("LifeLog.get('char-a')"))
        self.on()
        self.after_delay(0)
        self.assertEqual(self.found(token), [])
        self.assertEqual(self.ev('COUNT.sent') + self.ev('COUNT.ground'), 0)

    def test_live_logs_dropped_when_off_and_restarted_when_on(self):
        self.lua("bind('A', 'char-a'); LifeLog.poll()")
        self.lua('HARNESS.players.A.kills = 7')
        self.h.move_player('A', 10754, 9926)
        self.lua('LifeLog.poll()')
        self.assertEqual(self.ev("#LifeLog.get('char-a').towns"), 1)
        self.off()
        self.lua('LifeLog.poll()')
        self.assertIsNone(self.ev("LifeLog.get('char-a')"))
        self.assertEqual(self.ev('count(S.data.lifelogs.logs)'), 0)
        self.on()
        self.h.move_player('A', 200, 300)
        self.lua('LifeLog.poll()')
        log = self.ev("LifeLog.get('char-a')")
        self.assertIsNotNone(log)
        self.assertEqual(log.kills, 7)
        self.assertEqual(self.ev("#LifeLog.get('char-a').towns"), 0)


class SuiteTests(Bench):
    def test_suite_passes(self):
        self.lua(REGISTERED)
        self.lua("bind('A', 'char-a'); HARNESS.players.A.prof = 'doctor'")
        self.h.move_player('A', 100, 100)
        # World suites run on a save named rstest* only (RST guard); the state is already loaded.
        self.lua("getWorld = function() return { getGameMode = function() return 'Multiplayer' end, "
                 "getWorld = function() return 'rstest-bench' end } end")
        self.h.load('server', 'shared/RST/suites/RS_LastPages.lua')
        report = self.h.eval('server', 'RST.runSync({ suite = "rs.lastpages", tags = "world" }, '
                                       '{ player = HARNESS.players.A })')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual(len(results), 5, results)
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(self.ev('S.data.lifelogs and #LifeLog.frozen()'), 0)


if __name__ == '__main__':
    unittest.main()
