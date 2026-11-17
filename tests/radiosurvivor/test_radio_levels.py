"""Niveaux de radio des voix (E24-T01) : zones de tirage tirées de la table des postes, radio nécessaire d'une fréquence.

    python RadioSurvivor/tests/radiosurvivor/test_radio_levels.py

Le vrai RS_RadioLevels.lua du mod dans lupa : zones (fréquences que le poste le plus faible du niveau capte et que le
niveau précédent ne capte pas), niveau déduit d'une fréquence fixe, table conforme aux scripts d'objets du jeu
installé (MinChannel / MaxChannel de media/scripts/generated/items/radio.txt, ignoré sans le jeu), mêmes identifiants
que le lecteur du pont (persona_store.RADIOS).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua'
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tools'))
import persona_store as store  # noqa: E402
import game_items  # noqa: E402

RADIO_SCRIPT = Path('media/scripts/generated/items/radio.txt')
ITEM_RE = re.compile(r'^\s*item\s+(\w+)', re.M)


def load_levels():
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;]] .. package.path')
    return rt, rt.eval('require("RadioSurvivor/RS_RadioLevels")')


def items(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def zones(levels, ident: str) -> list[tuple[int, int]]:
    return [(int(z.low), int(z.high)) for z in items(levels.zones(ident))]


def game_channels(game: Path) -> dict[str, tuple[int, int]] | None:
    """Item type -> (MinChannel, MaxChannel) of the radio script of the installed game, or None without the game."""
    path = game / RADIO_SCRIPT
    if not path.is_file():
        return None
    text = path.read_text(encoding='utf-8', errors='replace')
    out = {}
    starts = list(ITEM_RE.finditer(text))
    for index, match in enumerate(starts):
        body = text[match.end():starts[index + 1].start() if index + 1 < len(starts) else len(text)]
        low = re.search(r'MinChannel\s*=\s*(\d+)', body)
        high = re.search(r'MaxChannel\s*=\s*(\d+)', body)
        if low and high:
            out[match.group(1)] = (int(low.group(1)), int(high.group(1)))
    return out


class RadioLevelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rt, cls.L = load_levels()
        cls.ids = [str(v) for v in items(cls.L.ids())]

    def test_five_levels_weakest_first(self):
        self.assertEqual(self.ids, ['any_talkie', 'good_talkie', 'pro_talkie', 'tactical', 'military'])

    def test_each_range_holds_the_weaker_one(self):
        for weaker, stronger in zip(self.ids, self.ids[1:]):
            a, b = self.L.get(weaker), self.L.get(stronger)
            self.assertLess(b.minKhz, a.minKhz, stronger)
            self.assertGreater(b.maxKhz, a.maxKhz, stronger)

    def test_zones_from_the_device_table(self):
        self.assertEqual(zones(self.L, 'any_talkie'), [(75000, 150000)])
        self.assertEqual(zones(self.L, 'good_talkie'), [(50000, 74800), (150200, 200000)])
        self.assertEqual(zones(self.L, 'pro_talkie'), [(25000, 49800), (200200, 300000)])
        self.assertEqual(zones(self.L, 'tactical'), [(10000, 24800), (300200, 500000)])
        self.assertEqual(zones(self.L, 'military'), [(200, 9800), (500200, 1000000)])
        self.assertIsNone(self.L.zones('high_tier'))

    def test_zone_heard_by_its_level_never_by_a_weaker_one(self):
        step = int(self.L.STEP_KHZ)
        for rank, ident in enumerate(self.ids):
            for low, high in zones(self.L, ident):
                for khz in range(low, high + 1, step):
                    self.assertEqual(self.L.levelOf(khz), ident, khz)
                    for weaker in self.ids[:rank]:
                        self.assertFalse(self.L.inZone(weaker, khz), (ident, weaker, khz))

    def test_zones_cover_every_tunable_frequency_once(self):
        step = int(self.L.STEP_KHZ)
        for khz in range(int(self.L.minKhz()), int(self.L.maxKhz()) + 1, step):
            owners = [ident for ident in self.ids if self.L.inZone(ident, khz)]
            self.assertEqual(len(owners), 1, khz)

    def test_needed_radio_of_a_fixed_frequency(self):
        cases = {145000: 'any_talkie', 75000: 'any_talkie', 150000: 'any_talkie', 150200: 'good_talkie',
                 74800: 'good_talkie', 49800: 'pro_talkie', 300000: 'pro_talkie', 300200: 'tactical',
                 10000: 'tactical', 9800: 'military', 200: 'military', 1000000: 'military'}
        for khz, ident in cases.items():
            self.assertEqual(self.L.levelOf(khz), ident, khz)
        self.assertIsNone(self.L.levelOf(0))
        self.assertIsNone(self.L.levelOf(1000200))

    def test_bounds_and_grid(self):
        self.assertEqual((int(self.L.minKhz()), int(self.L.maxKhz())), (200, 1000000))
        self.assertTrue(self.L.onGrid(145000))
        self.assertFalse(self.L.onGrid(145100))

    def test_bridge_reader_knows_the_same_levels(self):
        self.assertEqual(list(store.RADIOS), self.ids)

    def test_table_matches_the_game_scripts(self):
        channels = game_channels(game_items.DEFAULT_GAME)
        if channels is None:
            self.skipTest(f'no {RADIO_SCRIPT.as_posix()} under {game_items.DEFAULT_GAME}')
        for ident in self.ids:
            level = self.L.get(ident)
            for device in items(level.devices):
                with self.subTest(level=ident, device=device):
                    self.assertEqual(channels.get(str(device)), (int(level.minKhz), int(level.maxKhz)))
        # Every two-way device of the game belongs to a level (radios FM and TV only listen).
        listed = {str(d) for ident in self.ids for d in items(self.L.get(ident).devices)}
        two_way = {name for name in channels if 'WalkieTalkie' in name or 'HamRadio' in name or name == 'ManPackRadio'}
        self.assertEqual(two_way, listed)


if __name__ == '__main__':
    unittest.main()
