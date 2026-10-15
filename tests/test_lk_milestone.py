"""Tests hors jeu de la suite de jalon Living Knox lk.milestone1 (LK02-T08) et de la sonde de mesure RST_LKProbe.lua.

    python RadioSurvivor/tests/test_lk_milestone.py

Banc tests/harness.py en solo et doublures de test_lk_bodies.py, test_lk_guard.py, test_lk_anim.py,
test_lk_directives.py, test_lk_equipment.py et test_lk_appearance.py, complétées ici. Les doublures NE PROUVENT PAS
l'API réelle, seulement l'enchaînement de la suite et la logique de la sonde :
- joueur : setX / setY / setZ (case mise à jour), setLastX/Y/Z, ensureNotInVehicle (TeleportPacket.processClient,
  repris par RST_Fixtures.lua) ; getBodyDamage():getOverallBodyHealth() ;
- corps : relevé (isOnFloor faux) GET_UP_MS après sa première image ; marche : STEP (test_lk_directives.py) appelé à
  chaque image sur chaque zombie qui a un but ;
- sortie de zone : quand le joueur est à plus de 250 cases, UNLOAD de la zone de départ (joueur réanimé mis de côté,
  test_lk_bodies.py), RELOAD à son retour ;
- sonde : les abonnés OnTick du moteur sont relus dans LivingKnox.handlers ; getTimestampMs ne change qu'entre deux
  images dans le banc, le coût mesuré y vaut donc 0 ms.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_bodies import lua_list, DEV_LUA  # noqa: E402
from test_lk_directives import DirectiveBase  # noqa: E402
from test_lk_equipment import EQUIP_DOUBLES, EQUIPMENT, FISHING  # noqa: E402
from test_lk_appearance import EXTRA as APPEARANCE_EXTRA  # noqa: E402

SUITE = 'shared/RST/suites/RST_LKMilestone.lua'
PROBE = 'shared/RST/RST_LKProbe.lua'
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKMilestone.lua',
             DEV_LUA / 'shared' / 'RST' / 'RST_LKProbe.lua',
             DEV_LUA / 'shared' / 'RST' / 'RST_LKHelpers.lua']

MILESTONE_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local P = C.IsoPlayer
function P:ensureNotInVehicle() end
for _, f in ipairs({ 'X', 'Y', 'Z' }) do
    local key = string.lower(f)
    P['set' .. f] = function(self, v)
        H.num(v, 'set' .. f)
        self[key] = v
        H.place(self, self.x, self.y, self.z)
        return v
    end
    P['setLast' .. f] = function(self, v) H.num(v, 'setLast' .. f) return v end
end
local BD = H.class('BodyDamage')
function BD:getOverallBodyHealth() return self.owner.health or 100 end
function P:getBodyDamage() return setmetatable({ owner = self }, BD) end
GET_UP_MS = 2000
function GET_UP()
    local now = getTimestampMs()
    for _, zb in ipairs(H.zombieList.items) do
        if zb.onFloor then
            zb.seenMs = zb.seenMs or now
            if now - zb.seenMs >= GET_UP_MS then zb.onFloor = false end
        end
    end
end
function STEP_ALL(speed)
    local ids = {}
    for _, zb in ipairs(H.zombieList.items) do if zb.goal then ids[#ids + 1] = zb.onlineID end end
    for _, id in ipairs(ids) do STEP(id, speed) end
end
function OTICK_KEYS()
    local out = {}
    for slot, fn in pairs(LivingKnox.handlers) do
        if string.sub(slot, 1, 7) == 'OnTick/' then out[#out + 1] = slot end
    end
    table.sort(out)
    return out
end
'''

FAR_X = 250


class MilestoneBase(DirectiveBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.tick_ms = 50
        h.load('solo', EQUIP_DOUBLES)
        h.load('solo', EQUIPMENT)
        h.load('solo', FISHING)
        h.load('solo', APPEARANCE_EXTRA)
        h.load('solo', MILESTONE_DOUBLES)
        return h

    def run_suite(self, flt='{ suite = "lk.milestone1", tags = "world" }', max_ticks=20000, speed=0.08):
        self.assertIs(self.h.load('solo', f'return (RST.start({flt}, {{ ctx = {{ player = getPlayer() }} }}))'),
                      True)
        away = False
        player = self.h.player('solo', 'A')
        for _ in range(max_ticks):
            self.h.tick()
            self.h.load('solo', f'GET_UP(); STEP_ALL({speed})')
            if not away and player.x > FAR_X:
                self.h.load('solo', f'UNLOAD(0, {FAR_X}, 0, {FAR_X})')
                away = True
            elif away and player.x < FAR_X:
                self.h.load('solo', 'RELOAD()')
                away = False
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        return report, results

    def measures(self):
        return [line[len('[LKM] measure '):] for line in self.h.logs('solo') if line.startswith('[LKM] measure ')]


class SuiteTests(MilestoneBase):
    def test_suite_listed_with_world_and_server_tags(self):
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.milestone1", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.milestone1')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 3)
        self.assertIsNone(listed.error)

    def test_whole_suite_passes_on_the_doubles_and_leaves_nothing(self):
        self.init(new_world=True)
        self.h.load('solo', SUITE)
        before = lua_list(self.h.eval('solo', 'OTICK_KEYS()'))
        originals = {k: self.h.eval('solo', f'LivingKnox.handlers["{k}"]') for k in before}
        scan = self.h.eval('solo', 'LivingKnox.Bodies.scan')
        report, results = self.run_suite()
        self.assertEqual(len(results), 3, results)
        self.assertTrue(report.ok, results)
        lines = self.measures()
        steps = {line.split(' ', 1)[0] for line in lines}
        for step in ('spawn', 'stand', 'appearance', 'weapon', 'guard', 'walk', 'stop', 'face', 'run', 'speed',
                     'gesture', 'roundtrip', 'cost', 'net', 'two', 'cleanup'):
            self.assertIn(step, steps, lines)
        joined = '\n'.join(lines)
        self.assertIn('appearance lk-1 skin=', joined)
        self.assertIn('holes=0 blood=0 dirt=0 patches=0 bodyBlood=0 wounds=0 attached=0', joined)
        self.assertIn('weapon Base.Shotgun aim: hand=Base.Shotgun second=Base.Shotgun slot= Weapon=firearm', joined)
        self.assertIn('guard contact 30 s:', joined)
        self.assertIn('target 0, attack/lunge 0, eat 0', joined)
        self.assertRegex(joined, r'walk walk to \d+,\d+ \(9 squares\): arrived in \d+ ms')
        self.assertRegex(joined, r'run run to \d+,\d+ \(-9 squares\): arrived')
        self.assertIn('face S: angle 90 degrees (expected 90)', joined)
        self.assertIn('roundtrip square unloaded', joined)
        self.assertIn('same object true, tag lk-1#1 (registry generation 1)', joined)
        self.assertIn('gesture strike: actor=true gesture=strike action=idle state=idle nodes=LKActorStrike2H', joined)
        self.assertIn('two lk-2 aim: actor=true gesture=aim', joined)
        self.assertIn('cleanup 3 npc(s) created by the run (lk-1,lk-2,lk-3): nothing left, tagged bodies in the cell 0',
                      joined)
        # Vitesse mesurée sur les doublures : 0,08 case par image de 50 ms = 1,6 case/s.
        speed = re.search(r'speed walk ([\d.]+) squares/s, run ([\d.]+)', joined)
        self.assertIsNotNone(speed, lines)
        self.assertAlmostEqual(float(speed.group(1)), 1.6, delta=0.05)
        # Sonde : phases du test 1, coût lu, tranches de balayage, rien envoyé en solo.
        cost = [line for line in lines if line.startswith('cost 1 npc')]
        for phase in ('spawn', 'weapon', 'guard', 'walk', 'run', 'gestures', 'roundtrip'):
            self.assertTrue(any(f'phase {phase}:' in line for line in cost), cost)
        self.assertTrue(any(line.startswith('cost 1 npc cost on solo: 0 ms/tick over ') for line in cost), cost)
        self.assertTrue(any(re.search(r'scan: \d+ slices, [\d.]+ zombies examined per slice', line) for line in cost))
        self.assertTrue(any('net on solo: sent 0 msg, 0 B; received 0 msg, 0 B' in line for line in cost), cost)
        self.assertTrue(any(line.startswith('net 1 npc per npc on solo: sent 0 msg/s') for line in lines), lines)
        self.assertTrue(any(line.startswith('cost 0 npc') for line in lines), lines)
        # Rapport RST : les mesures sont aussi des notes du rapport.
        text = self.h.eval('solo', 'table.concat(RST.formatReport(RST.last()), "\\n")')
        self.assertIn('       note: spawn lk-1 created in ', text)
        self.assertIn('       note: cleanup 3 npc(s)', text)
        # Tout est retiré et restauré : PNJ, zombies, abonnés, sonde, balayage.
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 0)
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 0)
        self.assertIsNone(self.ev('RST.LKProbe.active'))
        self.assertEqual(lua_list(self.h.eval('solo', 'OTICK_KEYS()')), before)
        for k, fn in originals.items():
            self.h.server.g.SAME_A, self.h.server.g.SAME_B = fn, self.h.eval('solo', f'LivingKnox.handlers["{k}"]')
            self.assertIs(self.h.eval('solo', 'rawequal(SAME_A, SAME_B)'), True, k)
        self.h.server.g.SAME_A = scan
        self.assertIs(self.h.eval('solo', 'rawequal(SAME_A, LivingKnox.Bodies.scan)'), True)
        self.assertEqual(self.h.eval('solo', 'getPlayer():getX()'), 100)
        self.assertEqual(self.h.errors('solo'), [])

    def test_cleanup_test_alone_fails_without_the_earlier_tests(self):
        self.init(new_world=True)
        self.h.load('solo', SUITE)
        self.h.load('solo', 'RST.LKMilestone.ids = {}')
        report, results = self.run_suite('{ suite = "lk.milestone1", tags = "world", test = "^cleanup" }')
        self.assertEqual([r[1] for r in results], ['FAIL'])
        self.assertIn('no npc recorded by the previous tests', results[0][2])

    def test_failure_in_the_chain_still_cleans_up(self):
        self.init(new_world=True)
        self.h.load('solo', SUITE)
        # Arme refusée : le test 1 échoue à l'étape weapon, le nettoyage passe quand même.
        self.h.load('solo', 'RST.LKMilestone.WEAPON = { item = "Base.Nope", slot = "Rifle On Back", '
                            'weapon = "firearm", aimNode = "LKActorAimRifle" }')
        report, results = self.run_suite('{ suite = "lk.milestone1", tags = "world", test = "^one" }')
        self.assertEqual(results[0][1], 'FAIL', results)
        self.assertIn('setWeapon Base.Nope', results[0][2])
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 0)
        self.assertIsNone(self.ev('RST.LKProbe.active'))
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 0)


class ExecutorSuiteTests(MilestoneBase):
    """Suite en jeu lk.executor sur les doublures (solo) : test LK03-T01 de réapparition et de consigne périmée."""

    def test_reappearance_and_stale_test_passes_on_the_doubles(self):
        self.init(new_world=True)
        self.h.load('solo', 'shared/RST/suites/RST_LKExecutor.lua')
        report, results = self.run_suite('{ suite = "lk.executor", tags = "world", test = "reappearance" }')
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, results)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKX] measure ')]
        self.assertTrue(any('reappearance: arrived, directive #1, resumed 1 time(s)' in line for line in lines), lines)
        self.assertTrue(any('stale: older directive stale, finished directive already executed here' in line
                            for line in lines), lines)
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 0)


class ProbeTests(MilestoneBase):
    def counter(self, m='solo'):
        """Abonné OnTick du moteur qui compte ses appels (inscrit par LivingKnox.subscribe)."""
        self.h.load(m, 'PCALLS = 0\nLivingKnox.subscribe("OnTick", "Test.count", function() PCALLS = PCALLS + 1 end)')

    def test_installed_at_the_next_tick_without_double_or_missed_calls(self):
        self.counter()
        self.h.load('solo', PROBE)
        self.h.tick(3)
        self.assertEqual(self.h.eval('solo', 'PCALLS'), 3)
        # Démarrée depuis OnTick (comme RST en solo), après l'abonné : un appel par image, jamais deux.
        self.h.load('solo', 'Events.OnTick.Add(function() if START_NOW then START_NOW = false; '
                            'PROBE = RST.LKProbe.start() end end)\nSTART_NOW = true')
        self.h.tick(1)
        self.assertEqual(self.h.eval('solo', 'PCALLS'), 4)
        self.assertIs(self.h.eval('solo', 'PROBE.installed'), False)
        self.h.tick(5)
        self.assertEqual(self.h.eval('solo', 'PCALLS'), 9)
        self.assertIs(self.h.eval('solo', 'PROBE.installed'), True)
        self.assertIs(self.h.eval('solo', 'RST.LKProbe.split(PROBE, "first")'), True)
        self.h.tick(2)
        summary = self.h.eval('solo', 'RST.LKProbe.stop(PROBE)')
        self.assertEqual(summary.ticks, 7)
        handler = [h for h in lua_list(summary.handlers) if h.key == 'Test.count'][0]
        self.assertEqual(handler.calls, 7)
        self.h.tick(2)
        self.assertEqual(self.h.eval('solo', 'PCALLS'), 13)
        self.assertEqual([p.label for p in lua_list(summary.phases)], ['first', 'rest'])
        lines = lua_list(self.h.eval('solo', 'RST.LKProbe.lines(PROBE.summary)'))
        self.assertTrue(lines[0].startswith('cost on solo: 0 ms/tick over 7 ticks'), lines)
        self.assertIn('Test.count 0 ms/call x7 (max 0)', lines[0])
        self.assertTrue(any(line.startswith('phase first: ') for line in lines), lines)

    def test_measured_time_and_reload_during_the_probe(self):
        self.h.load('solo', PROBE)
        # Abonné qui fait avancer l'horloge simulée de 3 ms par appel.
        self.h.load('solo', 'LivingKnox.subscribe("OnTick", "Test.slow", function() '
                            'HARNESS.clock.realMs = HARNESS.clock.realMs + 3 end)')
        self.h.load('solo', 'PROBE = RST.LKProbe.start()')
        self.h.tick(5)
        # Rechargement du module pendant la sonde : le nouvel abonné remplace l'enveloppe.
        self.h.load('solo', 'NEWFN = function() end\nLivingKnox.subscribe("OnTick", "Test.slow", NEWFN)')
        summary = self.h.eval('solo', 'RST.LKProbe.stop(PROBE)')
        slow = [h for h in lua_list(summary.handlers) if h.key == 'Test.slow'][0]
        self.assertEqual((slow.calls, slow.ms, slow.max), (5, 15, 3))
        self.assertEqual(summary.maxTickMs, 3)
        self.assertEqual(summary.busyTicks, 5)
        self.assertEqual(lua_list(summary.reloaded), ['OnTick/Test.slow'])
        self.assertIs(self.h.eval('solo', 'rawequal(LivingKnox.handlers["OnTick/Test.slow"], NEWFN)'), True)
        self.assertIsNone(self.h.eval('solo', 'RST.LKProbe.active'))
        self.h.load('solo', 'RST.LKProbe.start()')  # nouvelle sonde possible
        self.assertIsNotNone(self.h.eval('solo', 'RST.LKProbe.active'))

    def test_stop_before_installation_and_console(self):
        self.h.load('solo', PROBE)
        self.assertIs(self.h.eval('solo', 'LKM.start()'), True)
        self.h.tick(2)
        self.assertIs(self.h.eval('solo', 'LKM.stop()'), True)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKM]')]
        self.assertEqual(lines[0], '[LKM] probe started on solo (measures from the next tick on)')
        self.assertTrue(lines[1].startswith('[LKM] measure observer cost on solo: 0 ms/tick over 2 ticks'), lines)
        self.assertTrue(lines[-1].startswith('[LKM] measure observer pose relay delay: last '), lines)
        self.h.load('solo', 'PROBE = RST.LKProbe.start()')
        self.assertIsNone(self.h.eval('solo', '(RST.LKProbe.start())'))
        summary = self.h.eval('solo', 'RST.LKProbe.stop(PROBE)')
        self.assertEqual(summary.ticks, 0)
        self.h.tick(2)  # l'installateur retiré ne pose plus rien
        self.assertIsNone(self.h.eval('solo', 'RST.LKProbe.active'))
        self.assertIs(self.h.eval('solo', 'PROBE.installed'), False)


class ServerProbeTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp', debug=True, lua_roots=[DEV_LUA])
        for m in ('server', 'A', 'B'):
            self.h.load(m, 'shared/LivingKnox/LK_Core.lua')
            self.h.load(m, PROBE)

    def tearDown(self):
        self.h.close()

    def test_server_counts_engine_messages_and_restores_the_global(self):
        h = self.h
        h.load('server', 'ORIGINAL = sendServerCommand\nPROBE = RST.LKProbe.start()')
        h.tick(1)
        h.load('server', 'sendServerCommand("LivingKnox", "animState", { rev = 1, g = { ["lk-1"] = "aim" } })\n'
                         'sendServerCommand(HARNESS.players.A, "LivingKnox", "dirState", { rev = 2 })\n'
                         'sendServerCommand("RST", "other", { x = 1 })')
        self.assertEqual(len(h.pending()), 5)  # appels transmis tels quels (diffusions : A et B)
        h.load('A', 'sendClientCommand(getPlayer(), "LivingKnox", "dirReport", { id = "lk-1", n = 1 })')
        h.pump()
        summary = h.eval('server', 'RST.LKProbe.stop(PROBE)')
        out, inc = summary.net.out, summary.net.inc
        # Taille : clés et chaînes (longueur), nombres 8, tables 2.
        self.assertEqual(out.byCmd.animState.bytes, 2 + 3 + 8 + 1 + 2 + 4 + 3)
        self.assertEqual(out.byCmd.dirState.bytes, 2 + 3 + 8)
        self.assertEqual((out.count, inc.count), (2, 1))
        self.assertEqual(inc.byCmd.dirReport.bytes, 2 + 2 + 4 + 1 + 8)
        self.assertIs(h.eval('server', 'rawequal(ORIGINAL, sendServerCommand)'), True)
        lines = lua_list(h.eval('server', 'RST.LKProbe.lines(PROBE.summary)'))
        self.assertIn('net on server: sent 2 msg, 36 B (animState 1/23B, dirState 1/13B); received 1 msg, 17 B '
                      '(dirReport 1/17B)', lines)

    def test_client_counts_what_it_sends_and_receives(self):
        h = self.h
        h.load('A', 'ORIGINAL = sendClientCommand\nPROBE = RST.LKProbe.start()')
        h.tick(1)
        h.load('A', 'sendClientCommand(getPlayer(), "LivingKnox", "guardHello", { v = 1 })')
        h.load('server', 'sendServerCommand("LivingKnox", "poseState", { p = {} })')
        h.pump()
        summary = h.eval('A', 'RST.LKProbe.stop(PROBE)')
        self.assertEqual((summary.net.out.count, summary.net.inc.count), (1, 1))
        self.assertIs(h.eval('A', 'rawequal(ORIGINAL, sendClientCommand)'), True)
        self.assertEqual(h.errors('A'), [])


class ReportNoteTests(unittest.TestCase):
    def test_notes_are_kept_under_the_test_line(self):
        with Harness(mode='solo', lua_roots=[DEV_LUA]) as h:
            h.load('solo', 'require "RST/RST"\n'
                           'RST.suite("x.notes", function(s) s.test("a", function(t) t:note("m 1") t:ok(true) '
                           't:note("m 2") end) s.test("b", function(t) t:ok(true) end) end)')
            report = h.eval('solo', 'RST.runSync("x.notes")')
            self.assertTrue(report.ok)
            lines = lua_list(h.eval('solo', 'RST.formatReport(RST.runSync("x.notes"))'))
            self.assertTrue(lines[0].startswith('PASS   x.notes :: a ('), lines)
            self.assertEqual(lines[1:3], ['       note: m 1', '       note: m 2'])
            self.assertTrue(lines[3].startswith('PASS   x.notes :: b ('), lines)
            self.assertIsNone(lua_list(report.results)[1].notes)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_ascii_sources(self):
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')

    def test_probe_never_changes_the_published_mod(self):
        mod = Path(__file__).resolve().parents[1] / 'Contents'
        for path in mod.rglob('*.lua'):
            self.assertNotIn('LKProbe', path.read_text(encoding='utf-8'), path)


if __name__ == '__main__':
    unittest.main()
