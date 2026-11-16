"""Catalogue de l'atelier des voix (E22-T01, ADR atelier D03) : bridge/atelier/catalog.json généré depuis le mod.

    python RadioSurvivor/tests/test_atelier_catalog.py

Le catalogue est reconstruit en mémoire par tools/gen_atelier_catalog.py depuis les vraies déclarations Lua du mod
chargées dans lupa (registre des gabarits de CA_Missions, genres de RS_PersonaParams, natures de RS_Rewards, modes
d'arrivée de RS_TradeArrivals, grammaire de RS_Persona, catalogue personas/_categories.txt, fiches livrées) et comparé
au fichier livré : un écart veut dire que le mod a changé sans que le catalogue soit régénéré. Un faux gabarit inscrit
par le banc apparaît au catalogue sans aucune modification du générateur (ouvert à l'extension).
Objets et listes de butin (E22-T12) : lus dans le jeu installé par tools/game_items.py (poids selon la règle de
RS_ItemWeights.lua, noms de ItemName.json, catégorie DisplayCategory nommée par IG_UI.json) et tools/game_loot.py, bancs sur un faux jeu ; sans le jeu, le générateur
garde les listes du catalogue livré : la comparaison reste complète, et porte aussi sur les objets dès que le jeu est
installé.
"""
from __future__ import annotations

import io
import json
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_atelier_catalog as gen  # noqa: E402
import game_items  # noqa: E402

FAKE_TEMPLATE = r'''
local function aimAt() return true end
require('CoreAI/CA_Missions').register('bench_fake', {idPrefix = 'benchfake', voiceName = 'bench_fake',
    voiceText = 'do a bench thing at a place', params = {spot = 'place', count = 'count'}, aimAt = aimAt})
'''


class AtelierCatalogTests(unittest.TestCase):
    def test_shipped_catalogue_is_up_to_date(self):
        # Without the game (--game folder absent) the generator keeps the item list of catalog.json: everything else is
        # still compared, and the item list too whenever the game is installed.
        expected = gen.render(gen.build(gen.load_mod()))
        actual = gen.OUTPUT.read_text(encoding='utf-8') if gen.OUTPUT.is_file() else ''
        self.assertTrue(actual == expected,
                        f'{gen.OUTPUT.relative_to(ROOT).as_posix()} is not up to date with the mod: '
                        'run python tools/gen_atelier_catalog.py')

    def test_render_is_deterministic(self):
        catalog = gen.build(gen.load_mod(), gen.previous())
        text = gen.render(catalog)
        self.assertEqual(text, gen.render(json.loads(text)))
        self.assertTrue(text.endswith('}\n'))
        self.assertNotIn('\r', text)

    def test_mission_template_added_to_the_mod_appears_without_generator_change(self):
        lua = gen.load_mod()
        lua.rt.execute(FAKE_TEMPLATE)
        types = gen.build(lua, gen.previous())['missionTypes']
        self.assertEqual(types['bench_fake'], {
            'params': {'count': 'count', 'spot': 'place'},
            'setups': ['aimAt'],
            'template': 'bench_fake',
            'voiceText': 'do a bench thing at a place',
        })
        self.assertNotIn('bench_fake', gen.build(gen.load_mod(), gen.previous())['missionTypes'])

    def test_sellable_items_are_those_the_trade_prices(self):
        """E22-T17: a trader only sells an item with a sale value (CA_TradeValues.sellValue, RS_Trade refuses the others
        with not_in_stock): the catalogue lists them, the price list and the sale-only items registered by the mods."""
        sellable = gen.build(gen.load_mod(), gen.previous())['sellable']
        items = gen.previous()['items']
        self.assertEqual(sellable, sorted(sellable))
        self.assertEqual([t for t in sellable if t not in items], [])
        self.assertIn('Base.Battery', sellable)                  # price list
        self.assertIn('RadioSurvivor.OutsideNews', sellable)     # sale only, registered by RS_Trade
        self.assertNotIn('Base.Axe', sellable)
        self.assertLess(len(sellable), len(items) // 10)

    def test_sale_value_registered_by_a_mod_makes_an_item_sellable_without_generator_change(self):
        lua = gen.load_mod()
        lua.rt.execute('require("CoreAI/CA_TradeValues").registerSellOnly("Base.Axe", { v = 3, k = "supply" })')
        self.assertIn('Base.Axe', gen.build(lua, gen.previous())['sellable'])

    def test_shipped_traders_only_stock_sellable_items(self):
        lua = gen.load_mod()
        sellable = set(gen.build(lua, gen.previous())['sellable'])
        stocked = {}
        for path in sorted(gen.PERSONAS.glob('*.txt')):
            sheet = lua.read(path.name) if not path.name.startswith('_') else None
            if sheet is None or isinstance(sheet, tuple) or sheet.trade is None:
                continue
            stocked[path.name] = [str(e.t) for e in gen.lua_items(sheet.trade['items'])]
        self.assertGreater(len(stocked), 2)
        self.assertEqual({name: [t for t in types if t not in sellable] for name, types in stocked.items()
                          if any(t not in sellable for t in types)}, {})


# Item scripts and names of a fake game: weight, fluid container created full, defaults, names and their fallbacks.
FAKE_SCRIPT = """module Base
{
    imports { Base }
    /* a comment { with braces } */
    item Jug
    {
        DisplayCategory = WaterContainer,
        Weight = 0.2,
        Tags = base:water,
        component FluidContainer
        {
            Capacity = 2.0,
            Fluids
            {
                fluid = Water:1.0,
            }
        }
    }
    item EmptyFlask
    {
        DisplayCategory = Junk,
        Weight = 0.3,
        component FluidContainer { Capacity = 1.0, }
    }
    item Pebble
    {
        DisplayName = Small Pebble,
        DisplayCategory = Junk,
    }
    item Ghost
    {
        Weight = -2,
        component FluidContainer { Capacity = 0.01, Fluids { Fluid { type = Water, } } }
    }
}
"""
FAKE_NAMES = {'EN': {'Base.Jug': 'Jug', 'Base.EmptyFlask': 'Flask', 'Base.Ghost': 'Ghost'},
              'FR': {'Base.Jug': 'Cruche'}}
MOD_SCRIPT = ('module Base { item Jug { Weight = 0.5, DisplayCategory = WaterContainer, } }\n'
              'module Mine { item Thing { Weight = 0.25, DisplayCategory = Gizmo, } }\n')
# Category names of the game's inventory (IG_UI.json IGUI_ItemCat_<category>): French falls back on English, a
# category without a name keeps its raw name.
FAKE_UI = {'EN': {'IGUI_ItemCat_WaterContainer': 'Water Container', 'IGUI_ItemCat_Junk': 'Junk', 'IGUI_Other': 'x'},
           'FR': {'IGUI_ItemCat_WaterContainer': 'Récipient'}}


def fake_media(root: Path, script: str, names: dict, ui: dict | None = None) -> Path:
    media = root / 'media'
    (media / 'scripts' / 'items').mkdir(parents=True)
    (media / 'scripts' / 'items' / 'fake.txt').write_text(script, encoding='utf-8')
    for lang, table in names.items():
        folder = media / 'lua' / 'shared' / 'Translate' / lang
        folder.mkdir(parents=True)
        (folder / 'ItemName.json').write_text(json.dumps(table), encoding='utf-8')
    for lang, table in (ui or {}).items():
        (media / 'lua' / 'shared' / 'Translate' / lang / 'IG_UI.json').write_text(json.dumps(table), encoding='utf-8')
    return media


class GameItemsTests(unittest.TestCase):
    """tools/game_items.py: the weight rule of RS_ItemWeights.lua read from item scripts, names of ItemName.json."""

    def test_weights_and_names_of_item_scripts(self):
        with tempfile.TemporaryDirectory() as tmp:
            game = fake_media(Path(tmp) / 'game', FAKE_SCRIPT, FAKE_NAMES, FAKE_UI)
            mod = fake_media(Path(tmp) / 'mod', MOD_SCRIPT, {'EN': {'Mine.Thing': 'Thing'}})
            items = game_items.read_items([game])
            later = game_items.read_catalog([game, mod])
        self.assertEqual(items, {
            'Base.Jug': {'en': 'Jug', 'fr': 'Cruche', 'kg': 2.2, 'cat': 'WaterContainer'},  # 0.2 + 2 litres created full
            'Base.EmptyFlask': {'en': 'Flask', 'fr': 'Flask', 'kg': 0.3, 'cat': 'Junk'},    # no initial fluid: empty
            'Base.Pebble': {'en': 'Small Pebble', 'fr': 'Small Pebble', 'kg': 1.0, 'cat': 'Junk'},  # DisplayName, Weight 1
            'Base.Ghost': {'en': 'Ghost', 'fr': 'Ghost', 'kg': 0.05, 'cat': ''},  # negative weight 0, capacity >= 0.05
        })
        self.assertEqual(later['items']['Base.Jug'], {'en': 'Jug', 'fr': 'Cruche', 'kg': 0.5, 'cat': 'WaterContainer'},
                         'a later folder wins')
        self.assertEqual(later['items']['Mine.Thing'], {'en': 'Thing', 'fr': 'Thing', 'kg': 0.25, 'cat': 'Gizmo'})
        self.assertEqual(later['itemCategories'], {
            'Gizmo': {'en': 'Gizmo', 'fr': 'Gizmo'},                         # no name in the game: raw category
            'Junk': {'en': 'Junk', 'fr': 'Junk'},                            # French falls back on English
            'WaterContainer': {'en': 'Water Container', 'fr': 'Récipient'},
        })

    def test_loot_lists_of_the_shipped_notes_are_offered(self):
        lists = gen.previous()['lootLists']
        self.assertGreater(len(lists['loot']), 500)
        for key in ('loot', 'glovebox'):
            used = sorted({m.group(1) for path in gen.PERSONAS.glob('*.txt')
                           for m in re.finditer(rf'^{key}=([A-Za-z0-9_]+):', path.read_text(encoding='utf-8'), re.M)})
            with self.subTest(key):
                self.assertTrue(used)
                self.assertEqual([name for name in used if name not in lists[key]], [])

    def test_catalogue_keeps_its_item_list_without_the_game(self):
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()) as err:
            kept = gen.game_parts(Path(tmp) / 'no_game')
        self.assertEqual(kept, gen.previous())
        self.assertEqual(sorted(kept), ['itemCategories', 'items', 'lootLists'])
        self.assertIn('warning', err.getvalue())

    def test_shipped_stock_items_are_in_the_item_list(self):
        listed = gen.previous()['items']
        self.assertGreater(len(listed), 1000, 'the catalogue lists the item types of the game')
        stock = sorted({m.group(1) for path in gen.PERSONAS.glob('*.txt')
                        for m in re.finditer(r'^item=([A-Za-z0-9_]+\.[A-Za-z0-9_]+):', path.read_text(encoding='utf-8'),
                                             re.M)})
        self.assertGreater(len(stock), 20)
        self.assertEqual([t for t in stock if t not in listed], [])
        # a weight read for each (a diamond, 0.001 kg in its script, rounds to 0 in the catalogue) and both names
        self.assertTrue(all(listed[t]['kg'] >= 0 and listed[t]['en'] and listed[t]['fr'] for t in stock))
        self.assertGreater(sum(listed[t]['kg'] > 0 for t in stock), len(stock) * 0.9)
        categories = gen.previous()['itemCategories']
        self.assertTrue(all(listed[t]['cat'] in categories for t in stock), 'every stock item has a named category')
        self.assertEqual(categories.get('Food', {}).get('fr'), 'Nourriture', "the game's own category names")


if __name__ == '__main__':
    unittest.main()
