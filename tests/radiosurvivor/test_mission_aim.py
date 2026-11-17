"""Objectif d'une mission de voix tiré dans une zone ou à une distance de l'appelant (E25-T02, ADR lieux communs D01,
D03, D05) : RS_MissionAim et chaque gabarit qui a un objectif, dans lupa.

    python RadioSurvivor/tests/radiosurvivor/test_mission_aim.py

Vrai RadioSurvivor_Server et vrai RS_MissionVoice (départ d'une mission de voix), vrais gabarits du mod commun, vrai
tirage CA_Sites.draw ; métagrille du banc carnet (SCOUT_GRID : maisons de trois pièces, getBuildingAt par les pièces).
Un banc par gabarit (scout, clear, retrieve, signal, barricade, relay, watch, item) : near, far, very_far et une zone
visent le bâtiment tiré à cette distance ou dans cette zone ; deux départs successifs tirent à nouveau ; genre absent,
rien à cette distance : refus no_place ; la règle de densité de clear s'applique au bâtiment tiré ; deliver ne
tire rien.
Ne prouve ni l'API Java réelle ni le réseau : protocole en jeu dans le compte rendu de E25-T02.
"""
from __future__ import annotations

import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_carnet as carnet_helpers
from test_mission_clear import CLEAR_WORLD

# Caller alice at (10, 10). scoutHouse(id, x, y, 10, 10): site point (x + 4, y + 4). voice_sim brings 5001 (too close),
# 5002 (150, 10: near) and 5003 (600, 10: very far).
NEAR, FAR, VERY_FAR, IN_ZONE = 5002, 6102, 5003, 6103
HOUSES = {FAR: (350, 10), IN_ZONE: (1500, 1500)}
ZONE = {'id': 'town', 'label': 'Old town', 'z': 0, 'area': {'x1': 1480, 'y1': 1480, 'x2': 1540, 'y2': 1540}}
CORNERS = {NEAR: (150, 10), FAR: (350, 10), VERY_FAR: (600, 10), IN_ZONE: (1500, 1500)}

# What each template keeps of its objective: building key, footprint corner or spot.
TEMPLATES = {
    'scout': {}, 'clear': {}, 'retrieve': {}, 'signal': {},
    'barricade': {}, 'relay': {}, 'watch': {}, 'item': {'params': {'item': 'Base.Locket'}},
}


def aimed_corner(m) -> tuple:
    """Footprint corner (x1, y1) of the building the mission aims at, read from what its template keeps."""
    if m.siteKey:
        return 'key', m.siteKey
    if m.template in ('barricade', 'relay'):
        return 'corner', (m.site.x1, m.site.y1)
    if m.template == 'item':
        return 'corner', (m.bounds.x1, m.bounds.y1)
    return 'spot', (m.spot.x - 4, m.spot.y - 4)


def expected(template, house) -> tuple:
    if template in ('scout', 'clear', 'retrieve', 'signal'):
        return 'key', f'b{house}'
    if template in ('barricade', 'relay', 'item'):
        return 'corner', CORNERS[house]
    return 'spot', CORNERS[house]


class AimHarness(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name, houses=HOUSES, far_only=False):
        sim = self.voice_sim(name, far_only=far_only)
        rt = sim.server.rt
        rt.execute("RandomizedWorldBase = RandomizedWorldBase or {}; local cell = getCell(); "
                   "cell.getGridSquare = function() return nil end; getCell = function() return cell end")
        rt.execute(CLEAR_WORLD)
        for house, (x, y) in houses.items():
            sim.server.g.scoutHouse(house, x, y, 10, 10)
        # The game loads every server file of the mod: the set-up of the objective registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        self.voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.store = rt.eval("require('CoreAI/CA_NotebookStore')")
        return sim

    def sheet(self, sim, template, target=None, building=None, params=None):
        """Parsed sheet double (E25-T01 shape): one [mission] section of this type aimed at target (a place id, or a
        distance name; absent: near, as RS_Persona sets it), shared places box (a dead drop) and town (a zone)."""
        rt = sim.server.rt
        kind = target if target in (None, 'near', 'far', 'very_far') else 'place'
        aim = {'kind': kind or 'near'}
        if kind == 'place':
            aim['id'] = target
        if building:
            aim['building'] = building
        zone = dict(ZONE, area=rt.table_from(ZONE['area']))
        places = {'box': rt.table_from({'id': 'box', 'x': 100, 'y': 10, 'z': 0, 'label': 'Supply depot'}),
                  'town': rt.table_from(zone)}
        section = {'id': template, 'type': template, 'target': rt.table_from(aim), 'drops': rt.table_from(['box']),
                   'params': rt.table_from(params or TEMPLATES.get(template, {}).get('params', {}))}
        return rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([rt.table_from(section)]),
                              'places': rt.table_from(places)})

    def start(self, sim, sheet, template):
        sim.clock.offset += 1800001  # past the cooldown of the previous mission of this voice
        return self.voice.start(self.store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000,
                                template)

    def started(self, sim, template, **kw):
        m = self.start(sim, self.sheet(sim, template, **kw), template)
        self.assertFalse(isinstance(m, tuple), f'{template}: {m}')
        return m

    def close(self, sim, m):
        self.assertTrue(sim.server.rt.eval("require('CoreAI/CA_Missions')").finish(sim.state(), m, 'failed'))


class EveryTemplateTests(AimHarness):

    def test_each_template_aims_at_the_building_drawn_for_each_target(self):
        cases = (('near', NEAR), ('far', FAR), ('very_far', VERY_FAR), ('town', IN_ZONE))
        for template in TEMPLATES:
            sim = self.world('aim-' + template)
            for target, house in cases:
                with self.subTest(template=template, target=target):
                    m = self.started(sim, template, target=target)
                    self.assertEqual(aimed_corner(m), expected(template, house))
                    self.close(sim, m)

    def test_a_section_without_target_is_near(self):
        sim = self.world('aim-default')
        m = self.started(sim, 'scout')
        self.assertEqual((m.siteKey, m.place, m.placeKind), (f'b{NEAR}', 'house', 'house'))

    def test_drawn_building_named_by_its_kind_and_described_by_clues(self):
        sim = self.world('aim-clues')
        m = self.started(sim, 'scout', target='far')
        self.assertEqual(m.place, 'house')
        self.assertTrue(m.clues and m.clueData, 'clues of the drawn building')
        self.assertFalse(any(ch.isdigit() for line in m.clues.values() for ch in line))

    def test_each_start_draws_again(self):
        """Two near buildings: successive starts of the same section aim at both (a fresh draw for each offer)."""
        sim = self.world('aim-again', houses={6104: (10, 160)})
        keys = set()
        for _ in range(12):
            m = self.started(sim, 'scout', target='near')
            keys.add(m.siteKey)
            self.close(sim, m)
        self.assertEqual(keys, {f'b{NEAR}', 'b6104'})

    def test_nothing_at_that_distance_or_of_that_kind_refuses_the_start(self):
        sim = self.world('aim-none', houses={}, far_only=True)
        for template in ('scout', 'barricade', 'watch'):
            with self.subTest(template=template):
                self.assertEqual(self.start(sim, self.sheet(sim, template, target='near'), template),
                                 (None, 'no_place'))
        sim = self.world('aim-kind')
        self.assertEqual(self.start(sim, self.sheet(sim, 'relay', target='far', building='church'), 'relay'),
                         (None, 'no_place'))
        self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_zone_with_a_building_kind_draws_only_that_kind(self):
        sim = self.world('aim-zone-kind')
        m = self.started(sim, 'watch', target='town', building='house')
        self.assertEqual(aimed_corner(m), expected('watch', IN_ZONE))
        self.close(sim, m)
        self.assertEqual(self.start(sim, self.sheet(sim, 'watch', target='town', building='school'), 'watch'),
                         (None, 'no_place'))

    def test_deliver_draws_nothing(self):
        sim = self.world('aim-deliver', houses={})
        m = self.started(sim, 'deliver')
        self.assertEqual(m.template, 'deliver')


class ClearDensityTests(AimHarness):
    """clear keeps its density rule on a drawn objective (declaration acceptSite handed to CA_Sites.draw: a refused
    building is skipped for the next one, tests/coreai/test_site_draw.py)."""

    def test_accept_site_is_the_density_rule_of_an_offer(self):
        sim = self.world('aim-clear-accept')
        rt = sim.server.rt
        accept = rt.eval("""function(intensity)
            RS_CLEAR.intensity = intensity
            local c = require('CoreAI/CA_MissionConfig').Missions.clear
            local site = {key = 'b1', bounds = {x1 = 150, y1 = 10, x2 = 160, y2 = 20}}
            local ok, why = require('CoreAI/CA_MissionClear').acceptSite(c, site)
            return ok, why, site.kills
        end""")
        ok, _, kills = accept(128)
        self.assertTrue(ok)
        self.assertGreater(kills, 0)
        ok, why, _ = accept(0)
        self.assertFalse(ok)
        self.assertIn('too few zombies', why)

    def test_no_building_dense_enough_refuses_clear_only(self):
        sim = self.world('aim-clear-empty')
        sim.server.g.RS_CLEAR.intensity = 0
        self.assertEqual(self.start(sim, self.sheet(sim, 'clear', target='near'), 'clear'), (None, 'no_place'))
        m = self.started(sim, 'scout', target='near')
        self.assertEqual(m.siteKey, f'b{NEAR}')


if __name__ == '__main__':
    unittest.main()
