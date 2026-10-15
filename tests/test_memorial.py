"""Mémorial du bulletin du soir (E14-T03) : RS_Facts.lua dans le vrai serveur du carnet (lupa, mêmes doublures que
tests/test_bulletin.py).

    python tests/test_memorial.py

Couvre : chaque mort du jour lue une fois, à la fin du bulletin, par le serveur (ligne d'ouverture traduite puis
noms), jamais par le pont (seul le nombre des morts lui est donné, sans nom) ; avec le pont, après son texte ; en
secours, avant la ligne de clôture ; mort répétée (même personnage) lue une fois ; 32 morts : toutes lues, lignes
bornées ; mort consignée pendant l'écriture du pont gardée pour le mémorial suivant ; aucun mémorial sans mort ;
traduction absente : les noms seuls. Ne prouve ni l'API Java réelle ni la réception radio : suite en jeu rs.bulletin.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import test_bulletin as tb
from test_carnet import convert
from test_protocol import lua_list

en = tb.en
MEMORIAL = en('IGUI_RS_Bulletin_Memorial')

# Helpers of the bulletin bench without its tests.
Base = type('Base', (unittest.TestCase,),
            {k: v for k, v in tb.BulletinTests.__dict__.items() if not k.startswith('test_')})


class MemorialTests(Base):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-memorial-')
        self.path = Path(self.tmp.name)

    def death(self, name, key):
        return self.facts.record('death', self.rt.table_from({'name': name}), key)

    def names_aired(self, lines):
        """Names read after the memorial line, each line ending with a period."""
        start = lines.index(MEMORIAL) + 1
        names = []
        for line in lines[start:]:
            if line in ('<szzt>', en('IGUI_RS_Bulletin_Close')):
                break
            self.assertTrue(line.endswith('.'), line)
            names += line[:-1].split(', ')
        return names

    def test_each_death_once_at_the_end_of_the_bridge_bulletin(self):
        self.world()
        self.die('alice')
        self.die('alice')                              # same death raised twice: one fact
        self.die('bob', 10, 10)
        self.hour(13)                                  # day 3, 20:00
        req = self.requests()[0]
        facts = list(tb.npc.decode(bytes.fromhex(req['facts'])).values())
        self.assertEqual(facts, [self.facts.deathsText(2)])
        self.assertTrue(facts[0].startswith('2 survivors died'), facts[0])
        self.assertNotIn('alice', req['facts'] + ''.join(facts))
        self.answer(req['id'], 'Good evening, Knox County.', 'Two of us did not make it today. Over.')
        self.tick()
        aired = self.aired()[0]
        self.assertEqual(aired, ['<fzzt>', 'Good evening, Knox County.', 'Two of us did not make it today. Over.',
                                 MEMORIAL, 'alice Doe, bob Doe.', '<szzt>'])
        self.assertEqual(self.names_aired(aired), ['alice Doe', 'bob Doe'])
        self.assertEqual(self.kinds(), [])
        self.assertTrue(self.logs('2 name(s) in the memorial'))

    def test_fallback_memorial_before_the_closing_line(self):
        self.world()
        self.die('alice')
        self.hour(13)
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        # Only deaths: no "nothing confirmed", the memorial, then the closing line.
        self.assertEqual(self.aired()[0], ['<fzzt>', en('IGUI_RS_Bulletin_Open'), MEMORIAL, 'alice Doe.',
                                           en('IGUI_RS_Bulletin_Close'), '<szzt>'])

    def test_many_deaths_all_read_once_on_bounded_lines(self):
        self.world()
        names = ['Survivor %s Longname-%s' % (chr(65 + i % 26), chr(97 + i // 26)) for i in range(40)]
        for i, name in enumerate(names):
            self.death(name, 'd%d' % i)
        self.hour(13)
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        aired = self.aired()[0]
        cap = int(self.facts.CAPS.death)
        read = self.names_aired(aired)
        self.assertEqual(read, names[:cap], 'each death of the day read once, in order')
        self.assertEqual(len(set(read)), cap)
        for line in aired:
            self.assertLessEqual(len(line), 140, line)
        self.assertGreater(len(aired), 6, 'names not split over several lines')

    def test_death_while_the_bridge_writes_waits_for_the_next_memorial(self):
        self.world()
        self.die('alice')
        self.hour(13)
        req = self.requests()[0]
        self.die('bob', 10, 10)                         # after the reading of the log
        self.answer(req['id'], 'Good evening. Over.')
        self.tick()
        self.assertEqual(self.names_aired(self.aired()[0]), ['alice Doe'])
        self.assertEqual(self.kinds(), ['death'])
        self.g.finishAiring()
        self.hour(24)                                   # next evening
        self.sim.clock.offset += int(self.facts.BULLETIN_TIMEOUT_MS) + 1
        self.tick()
        self.assertEqual(self.names_aired(self.aired()[1]), ['bob Doe'])

    def test_pure_lines(self):
        self.world()
        F = self.facts
        book = F.newBook()
        self.assertEqual(lua_list(F.memorialLines(F.read(book, 0))), [])
        F.add(book, 'death', self.rt.table_from({'name': 'Ann Lee'}), 3, 20, 'a')
        F.add(book, 'weather', self.rt.table_from({'weather': 'storm'}), 3, 20)
        F.add(book, 'death', self.rt.table_from({'name': 'Bo Kim'}), 3, 21, 'b')
        facts = F.read(book, 0)
        self.assertEqual(lua_list(F.memorialLines(facts)), [MEMORIAL, 'Ann Lee, Bo Kim.'])
        others, deaths = F.split(facts)
        self.assertEqual([convert(f)['kind'] for f in lua_list(others)], ['weather'])
        self.assertEqual(len(lua_list(deaths)), 2)
        self.assertIsNone(F.deathsText(0))
        self.assertEqual(F.deathsText(1)[:13], 'One survivor ')
        # Without the translation of the opening line: the names alone.
        self.rt.execute("local base = getTextOrNull; getTextOrNull = function(k) "
                        "if k == 'IGUI_RS_Bulletin_Memorial' then return nil end return base(k) end")
        self.assertEqual(lua_list(F.memorialLines(facts)), ['Ann Lee, Bo Kim.'])

    def test_rs_facts_suite_under_lupa(self):
        """Suite rs.facts (dev/.../RST/suites/RS_Facts.lua, memorial test included) run by the real RST engine."""
        sim = tb.Simulation(self.path / 'rst', world='rstest_memorial')
        self.boot(sim)
        sim.server.g.WORLD_HOURS = 50
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        tests_lua = tb.ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua/shared'
        self.rt.execute(f'package.path = [[{tests_lua.as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('local base = getWorld; getWorld = function() return base() end')
        self.rt.execute((tests_lua / 'RST/suites/RS_Facts.lua').read_text(encoding='utf-8'))
        RST = self.g.RST
        self.assertTrue(RST.start('rs.facts', self.rt.table_from({'attach': False})))
        for _ in range(100):
            if not RST.running():
                break
            RST.step()
            self.sim.clock.offset += 1000
            self.g.fire('OnTick')
        self.assertFalse(RST.running())
        summary = RST.summaryLine(RST.last())
        self.assertRegex(summary, r'(\d+) test\(s\): \1 pass, 0 fail, 0 error, 0 skip')
        self.assertIn('7 test(s)', summary)


if __name__ == '__main__':
    unittest.main(verbosity=2)
