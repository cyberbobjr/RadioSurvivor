"""Bulletin du soir (E14-T02) : RS_Facts.lua (journal des faits) + RadioSurvivor_Server.lua (chaîne du chroniqueur,
file de demandes au pont) dans le vrai serveur du carnet (lupa, Lua 5.1, `next` retiré comme dans Kahlua), et le pont
(bridge/bulletin.py, radio_bridge.evening_bulletin).

    python tests/test_bulletin.py

Couvre : heure de l'option RadioSurvivor.ChronicleHour (jour des faits de 7 h à 7 h), un bulletin par soirée, demande
kind=bulletin au pont (voix du chroniqueur, faits confirmés en phrases anglaises, aucune coordonnée), texte du pont
diffusé sur la fréquence du chroniqueur (parasites retirés, lignes bornées), bulletin de secours traduit construit à
partir des faits quand le pont se tait, purge des faits lus après la diffusion (un fait consigné entre-temps reste),
bulletin perdu par un redémarrage redemandé le même soir, chroniqueur absent ou mod désactivé : aucun bulletin ; pont :
prompt sans secret ni fait inventé, faits illisibles ou qui citent un secret retirés, réponse vide en cas d'échec, pont
réel --offline de bout en bout, pont antérieur qui ignore la demande.
Doublures du jeu de tests/test_carnet.py, tests/test_observations.py et tests/test_facts.py ; traducteur fidèle à
getText/getTextOrNull (table anglaise du mod, nil pour une clé inconnue). Ne prouve ni l'API Java réelle ni la réception
radio : suite en jeu rs.bulletin.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, convert
from test_facts import FACT_STUBS, MULDRAUGH
from test_observations import GAME_CLOCK, WORLD_STUBS
from test_protocol import MOD, ROOT, lua_list, pump, start_bridge

sys.path.insert(0, str(ROOT / 'bridge'))
import bulletin  # noqa: E402
import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402

FACTS_LUA = MOD / 'media/lua/server/RadioSurvivor/RS_Facts.lua'
TRANSLATE = MOD / 'media/lua/shared/Translate'
NIGHTOWL = (MOD / 'personas/nightowl.txt').read_text(encoding='utf-8')
# Fiche livrée du chroniqueur avec une fréquence fixe à la place de ses plages de tirage (E05-T07).
NIGHTOWL_FIXED = re.sub(r'(?m)^frequency_range=.*$', 'frequencies=112.4', NIGHTOWL)
KHZ = 112400
SECRET = "His wife's name was among the names he read on the very first night."

# Traducteur fidèle (42.21) : table anglaise du mod, nil pour une clé inconnue (getTextOrNull), %N remplacés.
TRANSLATOR = r'''
local texts = ...
getTextOrNull = function(key) return texts[key] end
getText = function(key, ...)
    local text = texts[key] or key
    local args = {...}
    for i = 1, select('#', ...) do
        text = string.gsub(text, '%%' .. i, function() return tostring(args[i]) end)
    end
    return text
end
'''


def en(key: str) -> str:
    return json.loads((TRANSLATE / 'EN/IG_UI.json').read_text(encoding='utf-8'))[key]


class BulletinTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-bulletin-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def boot(self, sim):
        """Radio server (chronicler on 112.4) and the fact log on a Simulation server."""
        g, rt = sim.server.g, sim.server.rt
        rt.execute(GAME_CLOCK)
        rt.execute(WORLD_STUBS)
        rt.execute(FACT_STUBS)
        texts = json.loads((TRANSLATE / 'EN/IG_UI.json').read_text(encoding='utf-8'))
        rt.execute(TRANSLATOR, rt.table_from(texts))
        g.SandboxVars.RadioSurvivor.SpontaneousCalls = False
        (sim.path / 'personas').mkdir(parents=True, exist_ok=True)
        (sim.path / 'personas/nightowl.txt').write_text(NIGHTOWL_FIXED, encoding='utf-8')
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        g.fire('OnLoadRadioScripts', g.MANAGER, True)
        self.facts = rt.eval("require('RadioSurvivor/RS_Facts')")

    def world(self, name='bulletin', hours=48):
        sim = Simulation(self.path / name)
        self.boot(sim)
        sim.server.g.WORLD_HOURS = hours
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        return sim

    # Aides
    def hour(self, n=1):
        for _ in range(n):
            self.g.WORLD_HOURS += 1
            self.g.fire('EveryHours')

    def tick(self):
        self.sim.clock.offset += 600   # POLL_MS
        self.g.fire('OnTick')

    def requests(self):
        path = self.sim.path / 'requests.txt'
        if not path.exists():
            return []
        parsed = rb.parse_requests(path.read_text(encoding='utf-8'))
        self.assertIsNotNone(parsed)
        return [r for r in parsed[1] if r.get('kind') == 'bulletin']

    def answer(self, req_id, *lines):
        body = [f'resp={req_id}'] + [f'line={line}' for line in lines] + ['end']
        (self.sim.path / 'responses.txt').write_text('\n'.join(body) + '\n', encoding='utf-8')

    def aired(self):
        return [lua_list(b) for b in lua_list(self.g.BROADCASTS)]

    def kinds(self):
        return [convert(f)['kind'] for f in lua_list(self.facts.list(0).facts)]

    def die(self, name, x=MULDRAUGH[0], y=MULDRAUGH[1]):
        p = self.g.PLAYERS[name]
        p.x, p.y, p.dead = x, y, True
        self.g.fire('OnCharacterDeath', p)

    def logs(self, text):
        return [line for line in lua_list(self.g.LOGS) if text in line]

    # ---------------------------------------------------------------------------------------------- server

    def test_due_hour_of_the_fact_day(self):
        self.world()
        F = self.facts
        book = F.newBook()
        due = lambda hour, at=20: F.bulletinDue(book, 3, hour, at)
        self.assertEqual([h for h in range(24) if due(h)], [0, 1, 2, 3, 4, 5, 6, 20, 21, 22, 23])
        # An hour before 7 am belongs to the evening of the previous calendar day (fact day from 7 am to 7 am).
        self.assertEqual([h for h in range(24) if due(h, 2)], [2, 3, 4, 5, 6])
        self.assertEqual([h for h in range(24) if due(h, 7)], list(range(24)))
        book.aired = 3
        self.assertFalse(due(23))
        # Option: registered first, then SandboxVars, then 20; outside 0..23 or not an integer: 20.
        self.assertEqual(F.chronicleHour(), 20)
        self.g.SandboxVars.RadioSurvivor.ChronicleHour = 2
        self.assertEqual(F.chronicleHour(), 2)
        for bad in (24, -1, 2.5, 'x'):
            self.g.SandboxVars.RadioSurvivor.ChronicleHour = bad
            self.assertEqual(F.chronicleHour(), 20, bad)
        self.rt.execute("local base = getSandboxOptions; getSandboxOptions = function() local o = base(); "
                        "o.getOptionByName = function(_, n) if n == 'RadioSurvivor.ChronicleHour' then "
                        "return {getValue = function() return 22 end} end end; return o end")
        self.assertEqual(F.chronicleHour(), 22)

    def test_fallback_bulletin_once_an_evening_without_bridge(self):
        self.world()
        self.die('alice')
        self.facts.record('weather', self.rt.table_from({'weather': 'storm'}))
        self.hour(12)                                  # day 3, 19:00
        self.assertEqual(self.requests(), [])
        self.hour()                                    # 20:00
        reqs = self.requests()
        self.assertEqual(len(reqs), 1)
        req = reqs[0]
        self.assertEqual((req['voice'], req['date'][:4], req['language']), ('nightowl', '1993', 'FR'))
        self.assertTrue(req['id'].endswith('-bulletin'), req['id'])
        facts = npc.decode(bytes.fromhex(req['facts']))
        # E14-T03: the dead are never named to the bridge (one sentence with their number; memorial at the end).
        self.assertEqual(list(facts.values()), [self.facts.deathsText(1), 'Around 07:00, A thunderstorm broke out.'])
        self.assertFalse(any('alice' in f for f in facts.values()), 'a name of the dead given to the bridge')
        self.assertNotIn('x', req)
        for value in req.values():
            if value is not req['facts'] and value is not req['id'] and value is not req['sent']:
                self.assertIsNone(re.search(r'\d{3}', value.replace('1993', '')), value)
        for text in facts.values():
            self.assertIsNone(re.search(r'\d{3}', text), text)
        # Nothing on the air while the bridge may still answer; the fallback after its delay.
        self.tick()
        self.assertEqual(self.aired(), [])
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS)
        self.tick()
        self.assertEqual(self.aired(), [['<fzzt>', en('IGUI_RS_Bulletin_Open'), en('IGUI_RS_Bulletin_Weather_storm'),
                                         en('IGUI_RS_Bulletin_Memorial'), 'alice Doe.', en('IGUI_RS_Bulletin_Close'),
                                         '<szzt>']])
        self.assertEqual(lua_list(self.g.AIRED_ON), [KHZ])
        self.assertEqual(self.kinds(), [], 'facts read by the bulletin not purged')
        self.assertEqual(self.sim.state().facts.aired, 3)
        self.assertEqual(self.requests(), [])
        # Once an evening: nothing more until the next fact day reaches its hour.
        self.die('bob', 10, 10)
        self.hour(10)                                  # day 4, 06:00
        self.g.finishAiring()
        self.assertEqual(self.requests(), [])
        self.hour(14)                                  # day 4, 20:00
        self.assertEqual(len(self.requests()), 1)
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        self.assertEqual(self.aired()[1][2:5], [en('IGUI_RS_Bulletin_Memorial'), 'bob Doe.', en('IGUI_RS_Bulletin_Close')])
        # An evening without any fact: the bulletin still airs.
        self.hour(24)
        self.g.finishAiring()
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        self.assertEqual(self.aired()[2], ['<fzzt>', en('IGUI_RS_Bulletin_Open'), en('IGUI_RS_Bulletin_None'),
                                           en('IGUI_RS_Bulletin_Close'), '<szzt>'])

    def test_bridge_text_aired_and_later_fact_kept(self):
        self.world()
        self.die('alice')
        self.hour(13)
        req = self.requests()[0]
        # A fact recorded while the bridge writes: kept for the next bulletin.
        self.facts.record('power_cut', self.rt.table_from({}))
        self.answer(req['id'], 'Good evening, Knox County.', '<fzzt>', 'We lost Alice Doe in Muldraugh today.',
                    *['Line %d.' % i for i in range(8)])
        self.tick()
        aired = self.aired()
        self.assertEqual(len(aired), 1)
        self.assertEqual(aired[0][:3], ['<fzzt>', 'Good evening, Knox County.', 'We lost Alice Doe in Muldraugh today.'])
        # Bridge lines bounded, then the memorial read by the server (E14-T03).
        self.assertEqual(len(aired[0]), int(self.facts.BULLETIN_MAX_LINES) + 4, 'bridge lines not bounded')
        self.assertEqual(aired[0][-3:], [en('IGUI_RS_Bulletin_Memorial'), 'alice Doe.', '<szzt>'])
        self.assertEqual(self.kinds(), ['power_cut'])
        self.assertEqual(self.requests(), [])
        self.assertTrue(self.logs('aired (bridge)'))

    def test_bridge_alive_answer_after_130_s_is_aired(self):
        """E17-T16: a bridge seen alive (heartbeat) may answer up to 135 s after the request: the bulletin waits
        Const.BRIDGE_TIMEOUT_MS and airs its text at 130 s; without heartbeat the short delay stays (test above)."""
        self.world()
        self.die('alice')
        self.hour(12)
        self.sim.clock.offset += 5000                  # past the last read of the heartbeat (ALIVE_READ_MS)
        rb.write_alive(self.sim.path / rb.ALIVE_FILE, self.sim.clock())
        self.hour()                                    # 20:00, bridge alive at the request
        req = self.requests()[0]
        wait = self.rt.eval("require('RadioSurvivor/RadioSurvivor_Const').BRIDGE_TIMEOUT_MS")
        self.assertGreaterEqual(wait, (rb.MAX_AGE_S + rb.LLM_BUDGET_S) * 1000 + 5000)
        self.sim.clock.offset += 130000
        self.tick()
        self.assertEqual(self.aired(), [], 'fallback aired while the bridge may still answer')
        self.answer(req['id'], 'Good evening, Knox County.')
        self.tick()
        self.assertEqual(self.aired()[0][:2], ['<fzzt>', 'Good evening, Knox County.'])
        self.assertTrue(self.logs('aired (bridge)'))

    def test_bridge_alive_but_silent_fallback_after_the_long_delay(self):
        self.world()
        self.die('alice')
        self.hour(12)
        self.sim.clock.offset += 5000                  # past the last read of the heartbeat (ALIVE_READ_MS)
        rb.write_alive(self.sim.path / rb.ALIVE_FILE, self.sim.clock())
        self.hour()
        self.sim.clock.offset += 145000
        self.tick()
        self.assertEqual(self.aired(), [])
        self.sim.clock.offset += 6000
        self.tick()
        self.assertEqual(self.aired()[0][1], en('IGUI_RS_Bulletin_Open'))

    def test_many_facts_deaths_first_and_bounded(self):
        self.world()
        for i in range(20):
            self.facts.record('passage', self.rt.table_from({'event': 'crossing'}), 'p%d' % i)
        self.die('alice')
        self.hour(13)
        facts = list(npc.decode(bytes.fromhex(self.requests()[0]['facts'])).values())
        self.assertEqual(len(facts), self.facts.BULLETIN_MAX_FACTS)
        self.assertEqual(facts[0], self.facts.deathsText(1), 'the death left out of a full bulletin')
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        aired = self.aired()[0]
        self.assertEqual(aired[2], 'The smuggler was heard from, somewhere in the county.')
        self.assertEqual(aired[-5:-2], [en('IGUI_RS_Bulletin_More').replace('%1', '11'),   # 16 passages (cap) - 5 told
                                        en('IGUI_RS_Bulletin_Memorial'), 'alice Doe.'])
        self.assertLessEqual(len(aired), int(self.facts.FALLBACK_MAX_FACTS) + 7)

    def test_restart_before_airing_asks_again_the_same_evening(self):
        sim = self.world()
        self.die('alice')
        self.hour(13)
        self.assertEqual(len(self.requests()), 1)
        self.g.fire('OnSave')
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        self.boot(restart)
        restart.server.g.WORLD_HOURS = self.g.WORLD_HOURS
        self.sim, self.g, self.rt = restart, restart.server.g, restart.server.rt
        self.assertEqual(self.kinds(), ['death'])
        self.hour()                                    # 21:00, not aired yet: asked again
        self.assertEqual(len(self.requests()), 1)
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        self.assertEqual(self.aired()[0][2:4], [en('IGUI_RS_Bulletin_Memorial'), 'alice Doe.'])
        self.assertEqual(self.sim.state().facts.aired, 3)

    def test_no_bulletin_without_chronicler_or_when_disabled(self):
        self.world()
        (self.sim.path / 'personas/nightowl.txt').write_text(NIGHTOWL_FIXED.replace('state=active', 'state=silent'),
                                                             encoding='utf-8')
        self.sim.clock.offset += 31000
        self.g.fire('OnTickEvenPaused')               # sheets read again
        self.hour(15)
        self.assertEqual(self.requests(), [])
        self.assertEqual(len(self.logs('is not on the air')), 1, 'logged once a day')
        (self.sim.path / 'personas/nightowl.txt').write_text(NIGHTOWL_FIXED, encoding='utf-8')
        self.sim.clock.offset += 31000
        self.g.fire('OnTickEvenPaused')
        self.g.SandboxVars.RadioSurvivor.Enabled = False
        self.hour()
        self.assertEqual(self.requests(), [])
        self.g.SandboxVars.RadioSurvivor.Enabled = True
        self.hour()                                    # still the same evening: the bulletin is late, not lost
        self.assertEqual(len(self.requests()), 1)

    def test_chronicler_gone_while_the_bridge_writes(self):
        self.world()
        self.die('alice')
        self.hour(13)
        (self.sim.path / 'personas/nightowl.txt').write_text(NIGHTOWL_FIXED.replace('state=active', 'state=gone'),
                                                             encoding='utf-8')
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.g.fire('OnTickEvenPaused')
        self.tick()
        self.assertEqual(self.aired(), [])
        self.assertEqual(self.kinds(), ['death'], 'facts purged without a bulletin')
        self.assertTrue(self.logs('evening bulletin dropped'))

    def test_translations_and_ascii_code(self):
        source = FACTS_LUA.read_text(encoding='utf-8')
        self.assertTrue(source.isascii())
        keys = set(re.findall(r"'(IGUI_RS_Bulletin_\w+)'", source))
        keys |= {'IGUI_RS_Bulletin_Mission_' + r for r in ('success', 'failed', 'abandoned')}
        keys |= {'IGUI_RS_Bulletin_Weather_' + w for w in ('storm', 'tropical_storm', 'blizzard')}
        keys |= {'IGUI_RS_Bulletin_Place_' + k for k in ('TownIn', 'TownOutskirts', 'TownCountry', 'TownFar')}
        keys -= {'IGUI_RS_Bulletin_Mission_', 'IGUI_RS_Bulletin_Weather_', 'IGUI_RS_Bulletin_Place_'}
        tables = {lang: json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8')) for lang in ('EN', 'FR')}
        for key in sorted(keys):
            for lang, table in tables.items():
                self.assertIn(key, table, f'{lang} {key}')
            self.assertEqual(sorted(re.findall(r'%\d', tables['EN'][key])),
                             sorted(re.findall(r'%\d', tables['FR'][key])), key)
        sandbox = {lang: json.loads((TRANSLATE / lang / 'Sandbox.json').read_text(encoding='utf-8')) for lang in ('EN', 'FR')}
        for lang, table in sandbox.items():
            self.assertIn('Sandbox_RadioSurvivor_ChronicleHour', table, lang)
            self.assertIn('Sandbox_RadioSurvivor_ChronicleHour_tooltip', table, lang)
        options = (MOD / 'media/sandbox-options.txt').read_text(encoding='utf-8')
        self.assertRegex(options, r'option RadioSurvivor\.ChronicleHour\s*\{\s*type = integer,\s*min = 0,\s*max = 23,'
                                  r'\s*default = 20,')

    def test_in_game_suite_under_lupa(self):
        """Suite rs.bulletin (dev/.../RST/suites/RS_Facts.lua) run by the real RST engine on this server, bridge silent:
        the forced bulletin is aired by the fallback after its delay."""
        sim = Simulation(self.path / 'rst', world='rstest_bulletin')
        self.boot(sim)
        sim.server.g.WORLD_HOURS = 50
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        sim.add_client('alice')
        self.die('alice')
        tests_lua = ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua/shared'
        self.rt.execute(f'package.path = [[{tests_lua.as_posix()}/?.lua;]] .. package.path')
        # RST.saveName checks type(getWorld) == "function": a Lua function, as the Java global is for Kahlua.
        self.rt.execute('local base = getWorld; getWorld = function() return base() end')
        self.rt.execute((tests_lua / 'RST/suites/RS_Facts.lua').read_text(encoding='utf-8'))
        RST = self.g.RST
        started = RST.start('rs.bulletin', self.rt.table_from({'attach': False}))
        self.assertTrue(started)
        for _ in range(400):
            if not RST.running():
                break
            RST.step()
            self.sim.clock.offset += 1000
            self.g.fire('OnTick')
        self.assertFalse(RST.running())
        summary = RST.summaryLine(RST.last())
        self.assertIn('2 test(s): 2 pass, 0 fail, 0 error, 0 skip', summary)
        self.assertEqual(self.aired()[0][2:4], [en('IGUI_RS_Bulletin_Memorial'), 'alice Doe.'])

    # ---------------------------------------------------------------------------------------------- bridge

    def bridge_req(self, facts=None, raw=None, language='FR'):
        req = {'id': '1-2-bulletin', 'kind': 'bulletin', 'voice': 'nightowl', 'date': '1993-07-14 20:00',
               'language': language}
        if facts is not None:
            req['facts'] = npc.encode({i + 1: f for i, f in enumerate(facts)}).hex()
        if raw is not None:
            req['facts'] = raw
        return req

    def voices(self):
        folder = self.path / 'exchange'
        (folder / 'personas').mkdir(parents=True, exist_ok=True)
        (folder / 'personas/nightowl.txt').write_text(NIGHTOWL_FIXED, encoding='utf-8')
        return folder, rb.Voices(folder / 'personas')

    def test_bridge_prompt_only_the_facts_and_no_secret(self):
        folder, voices = self.voices()
        seen = []
        saved = rb.call_llm
        rb.call_llm = lambda config, messages, speaker='Walt', **_: seen.append(messages) or \
            'Good evening, Knox County. We lost Alice Doe in Muldraugh. Over.'
        try:
            lines = rb.evening_bulletin({}, rb.Conversations(folder), 's',
                                        self.bridge_req(['Around 07:00, A survivor, Alice Doe, died in Muldraugh.',
                                                         SECRET]), voices)
            empty = rb.evening_bulletin({}, rb.Conversations(folder), 's2', self.bridge_req(), voices)
            garbage = rb.evening_bulletin({}, rb.Conversations(folder), 's3', self.bridge_req(raw='zz'), voices)
            rb.call_llm = lambda config, messages, speaker='Walt', **_: 'Tonight: ' + SECRET
            leaked = rb.evening_bulletin({}, rb.Conversations(folder), 's4', self.bridge_req([]), voices)
        finally:
            rb.call_llm = saved
        system = seen[0][0]['content']
        self.assertTrue(system.startswith('You are Lyle Ferrand'), system[:80])
        self.assertNotIn(SECRET, system)
        self.assertIn('Speak French', system)
        self.assertIn('* Around 07:00, A survivor, Alice Doe, died in Muldraugh.', system)
        self.assertIn('never add one', system)
        self.assertIn('Never mention a frequency', system)
        self.assertEqual(seen[0][-1], {'role': 'user', 'content': bulletin.MARK})
        self.assertEqual(lines, ['Good evening, Knox County. We lost Alice Doe in Muldraugh. Over.'])
        empty_system = seen[1][0]['content']
        self.assertIn('No confirmed report reached you today', empty_system)
        self.assertNotIn('Confirmed reports of the day', empty_system)
        self.assertIn('No confirmed report reached you today', seen[2][0]['content'], 'unreadable facts kept')
        self.assertEqual(leaked, [], 'a bulletin quoting a secret is aired')
        history = json.loads(next(folder.glob('history_*.json')).read_text(encoding='utf-8'))
        self.assertEqual(history['messages'][0]['content'], bulletin.MARK)

    def test_bridge_sync_failure_and_older_bridge(self):
        folder, _ = self.voices()
        bridge = rb.Bridge({'OFFLINE': '1', 'OPENAI_MODEL': 'offline'}, folder)
        bad = dict(self.bridge_req([]), voice='nobody', sent='0')
        bridge.current = {bad['id']: bridge._token('s', bad)}
        bridge._handle('s', bad)
        self.assertEqual(bridge.answers, {'1-2-bulletin': []})
        bridge.pool.shutdown(wait=True)
        # Older bridge: the kind is unknown, the record follows the RSV2 path and is dropped without an answer.
        old = rb.Bridge({'OFFLINE': '1', 'OPENAI_MODEL': 'offline'}, folder)
        saved = bulletin.KIND
        bulletin.KIND = 'kind-unknown-to-an-older-bridge'
        try:
            old._sync('s', [dict(self.bridge_req([]), sent=str(int(rb.time.time() * 1000)))])
            old.pool.shutdown(wait=True)
            self.assertEqual((old.answers, old.started), ({}, set()))
        finally:
            bulletin.KIND = saved

    def test_real_offline_bridge_end_to_end(self):
        self.world()
        self.die('alice')
        bridge = start_bridge(self.sim.path)
        try:
            self.hour(13)
            self.assertTrue(pump(lambda: len(self.aired()) == 1, [self.tick]), 'no bulletin aired')
        finally:
            bridge.terminate()
            bridge.communicate(timeout=10)
        aired = ' '.join(self.aired()[0])
        self.assertIn('bulletin du soir hors ligne', aired)
        self.assertNotIn('alice Doe, died', aired)
        self.assertTrue(aired.endswith(en('IGUI_RS_Bulletin_Memorial') + ' alice Doe. <szzt>'), aired)
        self.assertEqual(self.kinds(), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
