"""Fiche à sections (E20-T03, ADR D03, D04) : ce que le serveur seul valide dans une fiche de voix.

    python RadioSurvivor/tests/test_persona_sections.py

Vrai RS_Persona avec les vraies règles du serveur (RS_Personas.rules : registre des gabarits du mod commun, natures de
récompense de RS_Rewards, catalogue livré personas/_categories.txt), dans lupa. Couvre les sections [mission],
[rewards] et [category] (le pont les passe sans les lire : chaque cas refusé ici est accepté par persona_store), un
faux type de mission inscrit par le banc avec ses propres paramètres (aucune modification du lecteur), le catalogue
livré (les tables de cache figées de RC_MissionConfig, objet par objet), les six fiches livrées (ce que propose chaque
voix) et les exemples de fiche des pages 10 du wiki FR et EN, chargés tels quels.
Les cas communs aux deux lecteurs (tête, [place], en-têtes de section) sont dans tests/test_personas.py.
"""
from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

from test_personas import HEAD, MOD, PROMPT, ROOT, LuaPersona, lua_items, store

DROP = '[place church]\nat=1,2,0\nlabel=Behind the church\nuse=drop\n'          # lignes 5 à 8
TARGET = '[place clinic]\nat=3,4,0\nlabel=West Point clinic\nuse=mark,target\n'  # lignes 9 à 12
BASE = HEAD + DROP + TARGET                                                     # ligne suivante : 13
EVERY = (BASE
         + '[mission meds]\ntype=deliver\nitems=medical\nquantity=2-4\ndrops=any\nweight=3\n'
         + 'story=I need bandages before the next fever.\n'
         + '[mission look]\ntype=scout\ntarget=clinic\nafter=meds\n'
         + '[category snacks]\nitem=Base.Crisps:1-2\nitem=Base.Pop:1\n'
         + '[rewards]\npool=cache:medical:3, cache:snacks:1, frequency:1, stashmap:1, lesson:Doctor:2\n' + PROMPT)
UNKNOWN_SKILL = ("unknown skill 'Carpentry' (expected Doctor, Aiming, Reloading, Woodwork, Mechanics, Electricity, "
                 'MetalWelding, Cooking, Farming, Fishing, Trapping, PlantScavenging)')


def mission(body: str) -> str:
    """BASE, une section [mission m] de corps `body` (ligne 13 : en-tête, ligne 14 : première clé), le prompt."""
    return BASE + '[mission m]\n' + body + PROMPT


def rewards(pool: str) -> str:
    return BASE + '[rewards]\npool=' + pool + '\n' + PROMPT


# (nom, contenu, ligne et raison ; None = fiche valide). Le fichier s'appelle case.txt.
CASES: list[tuple[str, str, tuple[int, str] | None]] = [
    ('every section', EVERY, None),
    ('mission with type only', mission('type=scout\n'), None),
    ('drops listed', mission('type=deliver\ndrops=church\n'), None),
    ('unknown type', mission('type=fly\n'), (14, "unknown mission type 'fly'")),
    ('mission without type', mission('weight=2\n'), (13, "missing key 'type' in [mission m]")),
    ('mission line without equal sign', mission('type=scout\nbring bandages\n'),
     (15, 'expected key=value or [prompt]')),
    ('duplicate mission key', mission('type=scout\ntype=clear\n'),
     (15, "duplicate key 'type' in [mission m] (first set on line 14)")),
    ('drops to an absent place', mission('type=deliver\ndrops=mill\n'), (15, "unknown place 'mill'")),
    ('drops to a place without use=drop', mission('type=deliver\ndrops=church,clinic\n'),
     (15, "place 'clinic' has no use=drop")),
    ('duplicate drops entry', mission('type=deliver\ndrops=church,church\n'), (15, "duplicate drops entry 'church'")),
    ('drops any without a drop place', HEAD + TARGET + '[mission m]\ntype=deliver\ndrops=any\n'
     + PROMPT, (11, 'drops=any needs a place with use=drop')),
    ('target to an absent place', mission('type=scout\ntarget=mill\n'), (15, "unknown place 'mill'")),
    ('target to a place without use=target', mission('type=scout\ntarget=church\n'),
     (15, "place 'church' has no use=target")),
    ('unknown category of a mission', mission('type=deliver\nitems=weapons\n'), (15, "unknown category 'weapons'")),
    ('unknown parameter of the type', mission('type=scout\ncount=3\n'),
     (15, "unknown key 'count' for mission type 'scout'")),
    ('bad parameter value', mission('type=deliver\nquantity=4-2\n'),
     (15, "bad range '4-2' (whole number or range lowest first, e.g. 2-4)")),
    ('mission weight zero', mission('type=scout\nweight=0\n'), (15, "bad weight '0' (whole number from 1 to 999999)")),
    ('mission weight not a number', mission('type=scout\nweight=high\n'),
     (15, "bad weight 'high' (whole number from 1 to 999999)")),
    ('after an unknown mission', mission('type=scout\nafter=ghost\n'), (15, "unknown mission 'ghost' in after=")),
    ('after itself', mission('type=scout\nafter=m\n'), (15, "after= cycle through mission 'm'")),
    ('after cycle', BASE + '[mission a]\ntype=scout\nafter=b\n[mission b]\ntype=clear\nafter=a\n' + PROMPT,
     (15, "after= cycle through mission 'a'")),
    ('unknown reward', rewards('gold:1'), (14, "unknown reward 'gold' (expected cache, frequency, lesson, stashmap)")),
    ('reward without weight', rewards('frequency'),
     (14, "bad reward 'frequency' (kind:weight or kind:parameter:weight, e.g. cache:medical:3)")),
    ('reward weight zero', rewards('frequency:0'), (14, "bad reward weight '0' (whole number from 1 to 999999)")),
    ('reward weight not a number', rewards('stashmap:x'),
     (14, "bad reward weight 'x' (whole number from 1 to 999999)")),
    ('reward needs a parameter', rewards('cache:3'),
     (14, "reward 'cache' needs a parameter (kind:parameter:weight)")),
    ('reward takes no parameter', rewards('frequency:food:1'),
     (14, "reward 'frequency' takes no parameter (kind:weight)")),
    ('unknown category of a reward', rewards('cache:weapons:1'), (14, "unknown category 'weapons'")),
    ('unknown skill', rewards('lesson:Carpentry:1'), (14, UNKNOWN_SKILL)),
    ('duplicate reward', rewards('frequency:1, frequency:2'), (14, "duplicate reward 'frequency'")),
    ('rewards without pool', BASE + '[rewards]\n' + PROMPT, (13, "missing key 'pool' in [rewards]")),
    ('unknown key in rewards', BASE + '[rewards]\npool=frequency:1\ncolour=red\n' + PROMPT,
     (15, "unknown key 'colour' in [rewards]")),
    ('category of the catalogue redefined', BASE + '[category medical]\nitem=Base.Bandage:1\n' + PROMPT,
     (13, "category 'medical' already exists in the shared catalogue")),
    ('category without item', BASE + '[category snacks]\n' + PROMPT, (13, "missing key 'item' in [category snacks]")),
    ('bad item', BASE + '[category snacks]\nitem=Crisps:2\n' + PROMPT,
     (14, "bad item 'Crisps:2' (Module.Type:quantity, e.g. Base.Bandage:2-4)")),
    ('bad item quantity', BASE + '[category snacks]\nitem=Base.Crisps:2-1\n' + PROMPT,
     (14, "bad range '2-1' (whole number or range lowest first, e.g. 2-4)")),
    ('duplicate item', BASE + '[category snacks]\nitem=Base.Crisps:1\nitem=Base.Crisps:2\n' + PROMPT,
     (15, "duplicate item 'Base.Crisps' in [category snacks]")),
    ('unknown key in a category', BASE + '[category snacks]\nitem=Base.Crisps:1\nweight=2\n' + PROMPT,
     (15, "unknown key 'weight' in [category snacks]")),
]

# Faux type de mission du banc : chaque genre de paramètre, déclaré par le gabarit seul.
FAKE_TEMPLATE = r'''
require('RadioSurvivorCore/RC_Missions').register('watchtower', {voiceName = 'watch_tower',
    voiceText = 'watch from a tower',
    params = {count = 'count', note = 'text', spot = 'place', quantity = 'range', items = 'category'}})
'''
FAKE_MISSION = mission('type=watch_tower\ncount=3\nnote=Count the crows.\nspot=church\nquantity=1-2\nitems=food\n')

# Natures de récompense du catalogue, dans l'ordre de RC_MissionConfig.Caches.order.
CATALOGUE = MOD / 'personas/_categories.txt'
WIKI_PAGES = (ROOT / 'docs/wiki/fr/10-creer-une-voix-radio.md', ROOT / 'docs/wiki/en/10-creating-radio-voices.md')


def wiki_sheets(page: Path) -> list[str]:
    """Exemples de fiche complets d'une page du wiki : blocs de code (ini ou text) qui ont une ligne format= et une
    ligne [prompt]."""
    blocks = re.findall(r'```(?:ini|text)\n(.*?)```', page.read_text(encoding='utf-8'), flags=re.S)
    return [b for b in blocks if re.search(r'(?m)^format=', b) and re.search(r'(?m)^\[prompt\]$', b)]


class SectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        cls.lua = LuaPersona(cls.folder)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, content: str):
        path = self.folder / 'case.txt'
        path.write_bytes(content.encode('utf-8'))
        return self.lua.read('case.txt'), path

    def test_cases(self):
        self.assertEqual(len({name for name, _, _ in CASES}), len(CASES))
        for name, content, expected in CASES:
            with self.subTest(name):
                result, path = self.read(content)
                if expected is None:
                    self.assertFalse(isinstance(result, tuple), result)
                else:
                    self.assertEqual(result, (None, f'line {expected[0]}: {expected[1]}'))
                # ADR D03 : le pont ne lit ni [mission], ni [rewards], ni [category].
                self.assertEqual(store.load_file(path).id, 'case')

    def test_every_section_content(self):
        p, _ = self.read(EVERY)
        places = {q.id: lua_items(q.uses) for q in lua_items(p.places)}
        self.assertEqual(places, {'church': ['drop'], 'clinic': ['mark', 'target']})
        meds, look = lua_items(p.missions)
        self.assertEqual((meds.id, meds.type, meds.weight, meds.story, lua_items(meds.drops), meds.target),
                         ('meds', 'deliver', 3, 'I need bandages before the next fever.', ['church'], None))
        self.assertEqual((meds.params['items'], meds.params.quantity['min'], meds.params.quantity['max']),
                         ('medical', 2, 4))
        self.assertEqual((look.id, look.type, look.weight, look.after, look.target, lua_items(look.drops)),
                         ('look', 'scout', 1, 'meds', 'clinic', []))
        self.assertEqual([(r.kind, r.param, r.weight) for r in lua_items(p.rewards)],
                         [('cache', 'medical', 3), ('cache', 'snacks', 1), ('frequency', None, 1),
                          ('stashmap', None, 1), ('lesson', 'Doctor', 2)])
        snacks = p.categories['snacks']
        self.assertEqual([(i.type, i.min, i.max) for i in lua_items(snacks['items'])],
                         [('Base.Crisps', 1, 2), ('Base.Pop', 1, 1)])

    def test_a_fake_type_accepts_its_own_parameters_without_change_of_the_reader(self):
        result, _ = self.read(FAKE_MISSION)
        self.assertEqual(result, (None, "line 14: unknown mission type 'watch_tower'"))
        self.lua.rt.execute(FAKE_TEMPLATE)
        p, _ = self.read(FAKE_MISSION)
        self.assertFalse(isinstance(p, tuple), p)
        m = lua_items(p.missions)[0]
        self.assertEqual((m.type, m.params['count'], m.params.note, m.params.spot, m.params['items']),
                         ('watch_tower', 3, 'Count the crows.', 'church', 'food'))
        self.assertEqual((m.params.quantity['min'], m.params.quantity['max']), (1, 2))
        self.assertEqual(self.read(FAKE_MISSION.replace('count=3', 'count=many'))[0],
                         (None, "line 15: bad count 'many' (whole number from 0 to 999999)"))
        self.assertEqual(self.read(FAKE_MISSION.replace('count=3', 'colour=red'))[0],
                         (None, "line 15: unknown key 'colour' for mission type 'watch_tower'"))

    def test_catalogue_holds_the_fixed_cache_tables(self):
        # Contenu exact des tables figées de RC_MissionConfig.Caches.tables (E20-T04 tirera dans le catalogue).
        tables = self.lua.rt.eval('require("RadioSurvivorCore/RC_MissionConfig").Caches')
        lines = store.split_lines(CATALOGUE.read_text(encoding='utf-8'))
        catalogue = self.lua.module.parseCatalogue(self.lua.rt.table_from(lines))
        self.assertFalse(isinstance(catalogue, tuple), catalogue)
        for name in lua_items(tables.order):
            with self.subTest(name):
                expected = [(row[1], row[2], row[2]) for row in lua_items(tables.tables[name])]
                self.assertEqual([(i.type, i.min, i.max) for i in lua_items(catalogue[name]['items'])], expected)
        self.assertEqual(sorted(catalogue.keys()), sorted(lua_items(tables.order)))
        self.assertEqual(sorted(self.lua.rules.categories.keys()), sorted(lua_items(tables.order)))

    def test_catalogue_refuses_anything_but_categories(self):
        parse = self.lua.module.parseCatalogue
        table = self.lua.rt.table_from
        self.assertEqual(parse(table(['# shared', '[place mill]', 'at=1,2,0'])),
                         (None, "line 2: unknown section 'place' (expected category)"))
        self.assertEqual(parse(table(['format=1'])), (None, 'line 1: expected [category <id>]'))
        self.assertEqual(parse(table(['[category a]', 'item=Base.A:1', '[category a]', 'item=Base.B:1'])),
                         (None, "line 3: duplicate category 'a' (first set on line 1)"))


class PlaceUseTests(unittest.TestCase):
    """Chaque consommateur ne prend que les lieux de son usage : repères (mark_map, reveal_area) les lieux use=mark,
    planques (deliver, cache de récompense) les lieux use=drop."""

    SHEET = (HEAD + 'actions=say,mark_map,reveal_area\n' + DROP + TARGET
             + '[place mill]\nat=5,6,0\nlabel=Old mill\nuse=drop,mark\n' + PROMPT)

    def test_server_places_by_use(self):
        lua = LuaPersona(ROOT)
        sheet = lua.module.parseLines(lua.rt.table_from(store.split_lines(self.SHEET)), None, lua.rules)
        ids = {use: [p.id for p in lua_items(lua.module.placesFor(sheet, use))] for use in ('mark', 'drop', 'target')}
        self.assertEqual(ids, {'mark': ['clinic', 'mill'], 'drop': ['church', 'mill'], 'target': ['clinic']})
        self.assertEqual(lua.module.placeFor(sheet, 'drop').id, 'church')
        self.assertIsNone(lua.module.placeFor(sheet, 'landing'))

    def test_bridge_offers_only_mark_places(self):
        import radio_bridge as rb
        sheet = store.parse_lines(store.split_lines(self.SHEET))
        self.assertEqual([p.id for p in sheet.places_for('mark')], ['clinic', 'mill'])
        prompt = rb.actions_prompt(sheet)
        self.assertIn('clinic: West Point clinic', prompt)
        self.assertNotIn('church', prompt)
        drops_only = store.parse_lines(store.split_lines(HEAD + 'actions=say,mark_map\n' + DROP + PROMPT))
        self.assertEqual(rb.offered_actions(drops_only), [])


class DeliveredSheetsTests(unittest.TestCase):
    """Les six fiches livrées passent au format à sections sans changer ce que propose chaque voix (ADR D11)."""

    @classmethod
    def setUpClass(cls):
        cls.lua = LuaPersona(MOD / 'personas')
        cls.sheets = {p.stem: cls.lua.read(p.name) for p in sorted((MOD / 'personas').glob('*.txt'))
                      if not p.name.startswith('_')}

    def test_every_sheet_loads(self):
        for vid, sheet in self.sheets.items():
            with self.subTest(vid):
                self.assertFalse(isinstance(sheet, tuple), sheet)

    def test_mission_givers_offer_the_same_jobs_and_rewards(self):
        # Avant E20-T03 : missions=scout,deliver,retrieve,clear,signal ; rewards=cache,frequency,stashmap,lesson ;
        # cache_table et teaches propres à chaque voix ; un seul lieu (dépôt de deliver et cache de récompense).
        expected = {'darlene': ('medical', 'Doctor', 'clinic'), 'cody': ('ammo', 'Aiming', 'checkpoint')}
        for vid, (table, skill, place) in expected.items():
            with self.subTest(vid):
                s = self.sheets[vid]
                self.assertEqual([(m.id, m.type) for m in lua_items(s.missions)],
                                 [(t, t) for t in ('scout', 'deliver', 'retrieve', 'clear', 'signal')])
                self.assertEqual([(r.kind, r.param, r.weight) for r in lua_items(s.rewards)],
                                 [('cache', table, 1), ('frequency', None, 1), ('stashmap', None, 1),
                                  ('lesson', skill, 1)])
                self.assertEqual([(q.id, lua_items(q.uses)) for q in lua_items(s.places)],
                                 [(place, ['mark', 'target', 'drop'])])

    def test_other_voices_give_no_mission(self):
        for vid in ('walt', 'gus', 'nightowl', 'whitaker'):
            with self.subTest(vid):
                s = self.sheets[vid]
                self.assertEqual((lua_items(s.missions), lua_items(s.rewards), lua_items(s.places)), ([], [], []))


class WikiExamplesTests(unittest.TestCase):
    """Pages 10 du wiki FR et EN : chaque exemple de fiche complet se charge tel quel (décision « le wiki suit le
    code » du 2026-11-14)."""

    def test_wiki_examples_load(self):
        lua = LuaPersona(ROOT)
        for page in WIKI_PAGES:
            examples = wiki_sheets(page)
            self.assertTrue(examples, page.name)
            for number, text in enumerate(examples, 1):
                with self.subTest(page=page.name, example=number):
                    result = lua.module.parseLines(lua.rt.table_from(store.split_lines(text)), None, lua.rules)
                    self.assertFalse(isinstance(result, tuple), result)
                    store.parse_lines(store.split_lines(text))


if __name__ == '__main__':
    unittest.main(verbosity=1)
