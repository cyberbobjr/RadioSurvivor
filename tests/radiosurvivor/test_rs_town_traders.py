"""Un marchand par ville vanilla (E20-T11, ADR D08) : fiches livrées, modes d'arrivée `road` et `cache`, notes de
fréquence déclarées dans les fiches.

    python RadioSurvivor/tests/radiosurvivor/test_rs_town_traders.py

Fiches réelles lues par RS_Persona (lupa) et par bridge/persona_store.py ; doublures de test_rs_trade_traders.py
(joueurs, cellule, sacs, horloge du monde) et, pour la planque, des conteneurs d'objets aux cases (IsoGridSquare
.getObjects, IsoObject.getContainerCount / getContainerByIndex). Couvre : une fiche par ville vanilla de la 42.22 et
son mode d'arrivée, chaque objet du stock présent dans les scripts du jeu (media/scripts) et coté au barème, plages de
fréquences sans recouvrement, rendez-vous (landing=, lieux communs) aux coordonnées relevées, note de fréquence déclarée (objet, clés de
traduction EN/FR, listes de butin vanilla) et aucune voix nommée dans le code des notes, aucun marchand nommé dans le
code ; passage complet par la route (signal, sons du fourgon, sac, hors de vue + délai, échange, texte du mode) ;
causes de la route ; passage par planque (aucun signal ni son, paiement dans le conteneur du lieu, sac au sol ignoré) ;
causes partagées par les modes (RS_TradeCauses).
Ne prouve ni l'API Java réelle ni le multijoueur : suite en jeu rs.trade_road.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.append(str(Path(__file__).resolve().parents[2] / 'tools'))

import pz_paths  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_rs_trade_run import EN, LUA, CORE_LUA, MOD, ROOT, TraderProxy, lua_list, persona_store  # noqa: E402
from test_rs_trade_traders import TradersHarness  # noqa: E402

FR = json.loads((LUA / 'shared/Translate/FR/IG_UI.json').read_text(encoding='utf-8'))
PERSONAS = MOD / 'personas'
VANILLA = pz_paths.media_dir()
TRANSLATE = LUA / 'shared/Translate'
NOTES_SCRIPT = MOD / 'media/scripts/RadioSurvivor_notes.txt'

# Ville vanilla 42.22 (étiquettes text-town de media/maps/Muldraugh, KY/worldmap-annotations.lua) -> marchand, mode.
# Valley Station (étiquette sans ville dans les lotpacks 42.22) n'a pas de marchand.
TOWNS = {
    'Riverside': ('gus', 'boat'), 'West Point': ('wanda', 'boat'), 'Brandenburg': ('lamar', 'boat'),
    'Louisville': ('delphine', 'boat'), 'Muldraugh': ('hollis', 'road'), 'March Ridge': ('loretta', 'road'),
    'Irvington': ('virgil', 'road'), 'Echo Creek': ('boone', 'road'), 'Rosewood': ('odessa', 'cache'),
    'Ekron': ('ezra', 'cache'), 'Fallas Lake': ('maxine', 'cache'),
}
NEW_TRADERS = sorted(vid for vid, _ in TOWNS.values() if vid != 'gus')
# Lieux relevés sur la carte 42.22 (lotheader et tuiles cités dans chaque fiche).
LANDINGS = {
    'gus': (6041, 5217, 0), 'wanda': (11827, 6588, 0), 'lamar': (1637, 5576, 0), 'delphine': (12899, 1150, 0),
    'hollis': (10583, 9700, 0), 'loretta': (10298, 12625, 0), 'virgil': (2620, 14095, 0), 'boone': (3480, 10929, 0),
    'odessa': (8155, 11650, 0), 'ezra': (643, 9740, 0), 'maxine': (7236, 8282, 0),
}
ARRIVAL_DIR = LUA / 'server/RadioSurvivor/TradeArrivals'


def sheet_paths() -> list[Path]:
    return sorted(p for p in PERSONAS.glob('*.txt') if not p.name.startswith('_'))


def translations(lang: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in (TRANSLATE / lang).glob('*.json'):
        out.update(json.loads(path.read_text(encoding='utf-8')))
    return out


def vanilla_items() -> dict[str, float]:
    """Module.Type -> poids du script de chaque objet des scripts du jeu installé (42.22)."""
    out: dict[str, float] = {}
    for path in (VANILLA / 'scripts').rglob('*.txt'):
        module, current = None, None
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            m = re.match(r'\s*module\s+(\w+)', line)
            if m:
                module = m.group(1)
            m = re.match(r'\s*item\s+(\w+)\s*$', line)
            if m and module:
                current = f'{module}.{m.group(1)}'
                out.setdefault(current, 0.0)
            m = re.match(r'\s*Weight\s*=\s*([0-9.]+)', line)
            if m and current and out[current] == 0.0:
                out[current] = float(m.group(1))
    return out


CATALOG = ROOT / 'bridge' / 'atelier' / 'catalog.json'


def code_files() -> list[Path]:
    """Code du mod et du pont : hors fiches, traductions et bancs."""
    out = []
    for root in (ROOT / 'Contents', ROOT / 'bridge'):
        for path in root.rglob('*'):
            if not path.is_file() or path.suffix not in ('.lua', '.py', '.txt', '.info', '.json'):
                continue
            parts = set(path.parts)
            if 'personas' in parts or 'Translate' in parts or 'tests' in parts or '__pycache__' in parts:
                continue
            if path == CATALOG:  # E22-T01 : catalogue généré depuis les fiches livrées (voix listées), pas du code
                continue
            out.append(path)
    return out


class TownTradersHarness(TradersHarness):
    """Modes d'arrivée livrés inscrits ; fiches réelles des marchands lues par RS_Persona."""

    def setUp(self):
        super().setUp()
        for path in sorted(ARRIVAL_DIR.glob('*.lua')):
            self.rt.eval(f'require("RadioSurvivor/TradeArrivals/{path.stem}")')
        self.sheets = {}
        for vid in NEW_TRADERS:
            self.sheets[vid] = self.add_voice((PERSONAS / f'{vid}.txt').read_text(encoding='utf-8'), vid)
        full = lambda spec, seed, passage: self.rt.table_from({e.n: 4 for e in lua_list(spec['items'])})  # noqa: E731
        self.T.drawStock = full

    def trader(self, vid):
        return TraderProxy(self.Trade, vid)

    def roll_zero(self, salt_name):
        """Le tirage reproductible de la cause `salt_name` de RS_TradeCauses tombe sur 0 (annulation), les autres non."""
        salt = self.rt.eval('require("RadioSurvivor/RS_TradeCauses")')[salt_name]
        self.T.runRoll = lambda passage, s, n: 0 if s == salt else n - 1

    def run_rules(self, vid, hours):
        """Règles du passage (RS_TradeRun) à l'heure du monde `hours`."""
        self.g.CLOCK.hours = hours
        return self.Run.updateTrader(vid, hours)


class ShippedSheetsTests(TownTradersHarness):

    def test_every_shipped_sheet_loads_in_lua_and_python(self):
        for path in sheet_paths():
            with self.subTest(path.name):
                persona_store.load_file(path)
                if path.stem in NEW_TRADERS:
                    self.assertIsNotNone(self.sheets[path.stem].trade)

    def test_one_trader_per_vanilla_town_with_its_arrival_mode(self):
        annotations = (VANILLA / 'maps/Muldraugh, KY/worldmap-annotations.lua').read_text(encoding='utf-8')
        labels = {re.sub(r'(?<!^)(?=[A-Z])', ' ', m) for m in
                  re.findall(r'addUntranslatedText\("MapLabel_(\w+)", "text-town"', annotations)}
        self.assertEqual(labels - set(TOWNS), {'Valley Station'})
        self.assertEqual(set(TOWNS) - labels, set())
        for town, (vid, arrival) in TOWNS.items():
            sheet = self.gus if vid == 'gus' else self.sheets[vid]
            with self.subTest(town):
                self.assertEqual(sheet.trade.arrival, arrival)
                self.assertEqual(lua_list(sheet.actions), ['say', 'propose_trade', 'share_frequency'])
                self.assertEqual(sheet.state, 'active')
                self.assertGreater(len(sheet.prompt), 800)

    def test_trade_items_exist_in_the_game_scripts_and_have_a_price(self):
        items = vanilla_items()
        mod_items = {f'RadioSurvivor.{n}' for n in re.findall(
            r'(?m)^\s*item\s+(\w+)', '\n'.join(p.read_text(encoding='utf-8') for p in (MOD / 'media/scripts').glob('*.txt')))}
        tv = self.rt.eval('require("CoreAI/CA_TradeValues")')
        for vid in ['gus', *NEW_TRADERS]:
            sheet = self.gus if vid == 'gus' else self.sheets[vid]
            for e in lua_list(sheet.trade['items']):
                with self.subTest(vid=vid, item=e.t):
                    self.assertTrue(e.t in items or e.t in mod_items, f'{e.t} is not an item of the 42.22 scripts')
                    self.assertGreater(tv.sellValue(e.t), 0, f'{e.t} has no value in CA_TradeValues')
                    if e.t in items:
                        self.assertGreaterEqual(e.w + 1e-9, items[e.t], f'{e.t} lighter than its script')

    def test_landings_at_the_verified_coordinates(self):
        for vid, at in LANDINGS.items():
            sheet = self.gus if vid == 'gus' else self.sheets[vid]
            landings = lua_list(sheet.trade.landings)
            with self.subTest(vid):
                self.assertEqual(len(landings), 1)
                self.assertEqual((landings[0].x, landings[0].y, landings[0].z), at)

    def test_discovery_notes_are_declared_with_translations_and_vanilla_lists(self):
        en, fr = translations('EN'), translations('FR')
        mod_items = set(re.findall(r'(?m)^\s*item\s+(\w+)', NOTES_SCRIPT.read_text(encoding='utf-8')))
        proc = (VANILLA / 'lua/server/Items/ProceduralDistributions.lua').read_text(encoding='utf-8', errors='replace')
        veh = (VANILLA / 'lua/server/Vehicles/VehicleDistributions.lua').read_text(encoding='utf-8', errors='replace')
        keys = set()
        for vid in NEW_TRADERS:
            note = self.sheets[vid].note
            with self.subTest(vid):
                self.assertIsNotNone(note, f'{vid} has no [note] section')
                self.assertEqual(note.module, 'RadioSurvivor')
                self.assertIn(note.type, mod_items)
                self.assertNotIn(note.key, keys)
                keys.add(note.key)
                stem = f'RadioSurvivor_{note.key}'
                for tr in (en, fr):
                    self.assertIn(f'Print_Media_{stem}_title', tr)
                    self.assertEqual(tr[f'Print_Media_{stem}_info'].count('%1'), 1)
                    self.assertGreaterEqual(tr[f'Print_Text_{stem}_info'].count('%1'), 1)
                    self.assertTrue(tr[f'Print_Media_{stem}_info'].startswith('<type:parent, width:'))
                self.assertNotEqual(en[f'Print_Text_{stem}_info'], fr[f'Print_Text_{stem}_info'])
                for e in lua_list(note.loot):
                    self.assertRegex(proc, rf'(?m)^\t{e.list} = \{{', e.list)
                for e in lua_list(note.glovebox):
                    self.assertRegex(veh, rf'(?m)^VehicleDistributions\.{e.list} = \{{', e.list)
                self.assertGreater(len(lua_list(note.loot)) + len(lua_list(note.glovebox)), 0)
        self.assertIn('RadioSurvivor.NoteTrade', en)
        self.assertIn('RadioSurvivor.NoteTrade', fr)

    def test_notes_are_declared_not_coded(self):
        voices = [p.stem for p in sheet_paths()]
        for rel in ('shared/RadioSurvivor/RS_Notes.lua', 'server/RadioSurvivor/RS_NotesServer.lua',
                    'client/RadioSurvivor/RS_NotesReader.lua'):
            code = re.sub(r'--[^\n]*', '', (LUA / rel).read_text(encoding='utf-8'))
            for vid in voices:
                with self.subTest(file=rel, voice=vid):
                    self.assertNotRegex(code, rf'(?i)\b{vid}\b')

    def test_no_trader_named_in_code(self):
        files = code_files()
        self.assertGreater(len(files), 50)
        for path in files:
            text = path.read_text(encoding='utf-8', errors='replace').lower()
            for vid in NEW_TRADERS:
                with self.subTest(file=path.name, voice=vid):
                    self.assertNotIn(vid, text)


class RoadPassageTests(TownTradersHarness):
    VID = 'hollis'

    def test_full_road_passage(self):
        hollis = self.trader(self.VID)
        x, y, _ = LANDINGS[self.VID]
        self.g.CLOCK.hours = 4.0                                                    # jour 1, 11:00
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Battery:4', voice=self.VID), 'ok')
        run = hollis.lastRun()
        self.assertEqual((run.landing.x, run.landing.y), (x, y))
        self.assertEqual(run.start, 17.0)                                           # jour 2, 00:00
        mark = lua_list(self.g.MARKS)[-1]
        self.assertEqual(mark.place.label, EN['IGUI_RS_TradeRun_Pier_road'])
        # Ni lampe ni fusée : rien ; lampe tenue au bord de la route : arrivée, portière du fourgon.
        kate.x, kate.y = x, y
        self.assertIsNone(self.run_rules(self.VID, 17.2))
        kate.hands = self.t({1: self.g.lamp(True)})
        self.assertEqual(self.run_rules(self.VID, 17.3), 'arrived')
        self.assertEqual(self.sounds(), [('VehicleDoorCloseVan', x, y)])
        bag = self.g.dropBag(x, y, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.assertIsNone(self.update(self.VID, 17.4))                              # sous les yeux de kate
        kate.x = x + 150
        self.assertIsNone(self.update(self.VID, 17.5))                              # attente commencée
        self.assertIsNone(self.update(self.VID, 17.5 + self.Ex.DELAY_HOURS - 0.1))
        self.assertEqual(self.update(self.VID, 17.5 + self.Ex.DELAY_HOURS), 'done')
        self.assertEqual(self.bag_items(bag)[-4:], ['Base.Battery'] * 4)
        self.assertEqual(self.sounds()[-1], ('VehicleTrunkCloseVan', x, y))
        self.assertEqual(self.aired()[-1][1], EN['IGUI_RS_TradeRun_Done_road'])

    def test_causes_of_the_road(self):
        # E23-T08 : patrouille et hélicoptère par tirage reproductible du passage (RS_TradeCauses), orage réel.
        for cause, setup in (('checkpoint', lambda: self.roll_zero('PATROL_SALT')),
                             ('air_patrol', lambda: self.roll_zero('HELICOPTER_SALT')),
                             ('washout', lambda: setattr(self.g, 'STORM', True))):
            with self.subTest(cause):
                self.setUp()
                self.g.CLOCK.hours = 4.0
                kate = self.make('kate', 'fac-1', 50, 50)
                self.assertEqual(self.decide(kate, 'Battery:1', voice=self.VID), 'ok')
                setup()
                self.assertEqual(self.run_rules(self.VID, 16.1), cause)
                self.assertEqual(self.aired()[-1][1], EN[f'IGUI_RS_TradeRun_Cancel_{cause}'])
                self.assertNotEqual(EN[f'IGUI_RS_TradeRun_Cancel_{cause}'], FR[f'IGUI_RS_TradeRun_Cancel_{cause}'])


CONTAINERS = r"""
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
OBJECTS = {}
local worldCell = getCell
getCell = function()
    local cell = worldCell()
    return { getGridSquare = function(_, x, y, z)
        local sq = cell:getGridSquare(x, y, z)
        if sq == nil then return nil end
        local objects = {}
        for i, c in ipairs(OBJECTS[x .. "," .. y] or {}) do
            objects[i] = { getContainerCount = function() return 1 end,
                getContainerByIndex = function(_, n) if n == 0 then return c end return nil end }
        end
        sq.getObjects = function() return list(objects) end
        return sq
    end }
end
function placeContainer(x, y, items)
    local c = makeContainer(items or {})
    local key = x .. "," .. y
    OBJECTS[key] = OBJECTS[key] or {}
    table.insert(OBJECTS[key], c)
    return c
end
"""


class CachePassageTests(TownTradersHarness):
    VID = 'odessa'

    def setUp(self):
        super().setUp()
        self.rt.execute(CONTAINERS)

    def test_full_cache_passage(self):
        odessa = self.trader(self.VID)
        x, y, _ = LANDINGS[self.VID]
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Bandage:2', voice=self.VID), 'ok')
        run = odessa.lastRun()
        self.assertEqual(run.start, 30.0)                                           # jour 2, 13:00
        self.assertEqual(lua_list(self.g.MARKS)[-1].place.label, EN['IGUI_RS_TradeRun_Pier_cache'])
        dumpster = self.g.placeContainer(x - 1, y - 1, self.t([self.it('MoneyBundle') for _ in range(2)]))
        ground = self.g.dropBag(x, y, self.t([self.it('MoneyBundle') for _ in range(3)]))
        # Aucun signal : le marchand vient à l'heure, personne au lieu, aucun son.
        self.assertIsNone(self.run_rules(self.VID, 29.9))
        self.assertEqual(self.run_rules(self.VID, 30.0), 'arrived')
        self.assertEqual(self.sounds(), [])
        kate.x, kate.y = x + 200, y
        self.assertIsNone(self.update(self.VID, 30.1))
        self.assertIsNone(self.update(self.VID, 30.1 + 2 - 0.1))                   # delay_hours=2 de la fiche
        self.assertEqual(self.update(self.VID, 30.1 + 2), 'done')
        self.assertEqual([i.t for i in lua_list(dumpster.list)], ['Base.Bandage', 'Base.Bandage'])
        self.assertEqual(self.bag_items(ground), ['Base.MoneyBundle'] * 3)          # sac au sol : ignoré
        self.assertEqual(self.sounds(), [])
        self.assertEqual(self.aired()[-1][1], EN['IGUI_RS_TradeRun_Done_cache'])

    def test_empty_cache_means_no_deal(self):
        x, y, _ = LANDINGS[self.VID]
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Bandage:2', voice=self.VID), 'ok')
        self.g.placeContainer(x, y)
        self.assertEqual(self.run_rules(self.VID, 30.0), 'arrived')
        kate.x = x + 200
        self.assertIsNone(self.update(self.VID, 30.1))
        self.assertEqual(self.update(self.VID, 32.1), 'no_drop')
        self.assertEqual(self.aired()[-1][1], EN['IGUI_RS_TradeRun_Cancel_nodrop_cache'])

    def test_causes_of_the_cache(self):
        for cause, setup in (('sweep', lambda: self.roll_zero('PATROL_SALT')),
                             ('overflight', lambda: self.roll_zero('HELICOPTER_SALT'))):
            with self.subTest(cause):
                self.setUp()
                self.g.CLOCK.hours = 4.0
                kate = self.make('kate', 'fac-1', 50, 50)
                self.assertEqual(self.decide(kate, 'Bandage:1', voice=self.VID), 'ok')
                setup()
                self.assertEqual(self.run_rules(self.VID, 29.1), cause)
                self.assertEqual(self.aired()[-1][1], EN[f'IGUI_RS_TradeRun_Cancel_{cause}'])


class SharedCausesTests(unittest.TestCase):

    def test_modes_build_their_checks_from_the_shared_module(self):
        modes = sorted(ARRIVAL_DIR.glob('*.lua'))
        self.assertEqual([p.stem for p in modes],
                         ['RS_TradeArrival_Boat', 'RS_TradeArrival_Cache', 'RS_TradeArrival_Road'])
        for path in modes:
            code = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
            with self.subTest(path.name):
                self.assertIn('require "RadioSurvivor/RS_TradeCauses"', code)
                self.assertNotRegex(code, r'roll\(|stormy\(')
                self.assertTrue(code.isascii())


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
