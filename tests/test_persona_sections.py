"""Fiche à sections (E20-T03, ADR D03, D04) : ce que le serveur seul valide dans une fiche de voix.

    python RadioSurvivor/tests/test_persona_sections.py

Vrai RS_Persona avec les vraies règles du serveur (RS_Personas.rules : registre des gabarits du mod commun, natures de
récompense de RS_Rewards, catalogue livré personas/_categories.txt), dans lupa. Couvre les sections [mission],
[rewards] et [category] (le pont les passe sans les lire : chaque cas refusé ici est accepté par persona_store), un
faux type de mission inscrit par le banc avec ses propres paramètres (aucune modification du lecteur), le catalogue
livré (les tables de cache figées de CA_MissionConfig, objet par objet), les six fiches livrées (ce que propose chaque
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
    # E20-T08 : enchainement par equipe, etat de recit pose a la reussite, recit borne (texte du travail, jobs=).
    ('mission scope team', mission('type=scout\nscope=team\n'), None),
    ('bad mission scope', mission('type=scout\nscope=world\n'), (15, "bad scope 'world' (expected character, team)")),
    ('mission sets_state', mission('type=scout\nsets_state=returned\n'), None),
    ('bad sets_state', mission('type=scout\nsets_state=Back home\n'),
     (15, "bad sets_state 'Back home' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('story too long', mission('type=scout\nstory=' + 'x' * 201 + '\n'),
     (15, 'story too long (200 bytes of UTF-8 at most)')),
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

# E20-T07 : section [trade] (troc de la voix). TRADE_HEAD : lignes 1 à 9 ; trade(body) : en-tête ligne 10, première clé
# ligne 11 ; TRADE_OK : lignes 11 à 16 (E23-T06 : accept= en ligne 16).
TRADE_HEAD = HEAD + 'actions=say,propose_trade\n[place dock]\nat=1,2,0\nlabel=Old dock\nuse=landing\n'
TRADE_OK = 'landing=dock\narrival=boat\nevery_days=7\nhours=01:00-03:00\nitem=Base.Battery:1-2\naccept=Base.MoneyBundle\n'


def trade(body: str) -> str:
    return TRADE_HEAD + '[trade]\n' + body + PROMPT


CASES += [
    ('trade section', trade(TRADE_OK), None),
    ('trade with groups, delay and margin',
     trade(TRADE_OK + 'group=seeds:3-8:2\nitem=Base.CornBagSeed:seeds\nitem=Base.KaleBagSeed:seeds\n'
           'delay_hours=2.5\nmargin=0.2-0.4\n'), None),
    ('propose_trade without trade', HEAD + 'actions=say,propose_trade\n' + PROMPT,
     (5, 'action propose_trade needs a [trade] section')),
    ('trade without propose_trade', HEAD + '[place dock]\nat=1,2,0\nlabel=Old dock\nuse=landing\n[trade]\n' + TRADE_OK
     + PROMPT, (9, 'section [trade] needs the action propose_trade')),
    ('trade without landing', trade('arrival=boat\nevery_days=7\nhours=01:00-03:00\nitem=Base.Battery:1\n'),
     (10, "missing key 'landing' in [trade]")),
    ('landing to an absent place', trade(TRADE_OK.replace('landing=dock', 'landing=ghost')),
     (11, "unknown place 'ghost'")),
    ('landing to a place without use=landing',
     HEAD + 'actions=say,propose_trade\n[place mill]\nat=1,2,0\nlabel=Mill\nuse=mark\n[trade]\n'
     + TRADE_OK.replace('landing=dock', 'landing=mill') + PROMPT, (11, "place 'mill' has no use=landing")),
    ('unknown arrival', trade(TRADE_OK.replace('arrival=boat', 'arrival=zeppelin')),
     (12, "unknown arrival 'zeppelin' (expected boat, cache, road)")),
    ('bad every_days', trade(TRADE_OK.replace('every_days=7', 'every_days=0')),
     (13, "bad every_days '0' (whole number from 1 to 28)")),
    ('bad trade hours', trade(TRADE_OK.replace('hours=01:00-03:00', 'hours=1-3')),
     (14, "bad trade hours '1-3' (one HH:MM-HH:MM range of the meeting, e.g. 01:00-03:00)")),
    ('empty trade hours', trade(TRADE_OK.replace('hours=01:00-03:00', 'hours=02:00-02:00')),
     (14, "empty trade hours '02:00-02:00'")),
    ('bad trade item', trade(TRADE_OK.replace('item=Base.Battery:1-2', 'item=Battery:2')),
     (15, "bad trade item 'Battery:2' (Module.Type:quantity, e.g. Base.Battery:4-12)")),
    # E22-T12 : poids lu dans le script de l'objet ; une ligne à trois parties (ancien poids écrit) est refusée.
    ('trade item with a written weight', trade(TRADE_OK.replace('item=Base.Battery:1-2', 'item=Base.Battery:1-2:0.1')),
     (15, "bad trade item 'Base.Battery:1-2:0.1' (Module.Type:quantity, e.g. Base.Battery:4-12)")),
    ('unknown trade item type', trade(TRADE_OK.replace('item=Base.Battery:1-2', 'item=Base.FluxCapacitor:1-2')),
     (15, "unknown trade item 'Base.FluxCapacitor' (no item script of that type)")),
    ('duplicate trade item', trade(TRADE_OK + 'item=Base.Battery:1\n'), (17, "duplicate trade item 'Battery'")),
    ('unknown trade group', trade(TRADE_OK + 'item=Base.CornBagSeed:seeds\n'), (17, "unknown trade group 'seeds'")),
    ('trade group without item', trade(TRADE_OK + 'group=seeds:1-2\n'), (17, "trade group 'seeds' has no item")),
    ('bad trade margin', trade(TRADE_OK + 'margin=0.6-0.2\n'),
     (17, "bad margin '0.6-0.2' (lowest-highest from 0 to 1, e.g. 0.10-0.50)")),
    ('unknown key in trade', trade(TRADE_OK + 'colour=red\n'), (17, "unknown key 'colour' in [trade]")),
    # E23-T06 : ce que la voix accepte en paiement (objets à valeur de vente, catégories), obligatoire.
    ('trade without accept', trade(TRADE_OK.replace('accept=Base.MoneyBundle\n', '')),
     (10, "missing key 'accept' in [trade]")),
    ('trade accepts categories', trade(TRADE_OK + 'accept=cash\naccept=papers_of_the_dead\n'), None),
    ('bad trade accept', trade(TRADE_OK + 'accept=gold coins\n'),
     (17, "bad trade accept 'gold coins' (Module.Type or a category, e.g. Base.MoneyBundle or ammo)")),
    ('duplicate trade accept', trade(TRADE_OK + 'accept=Base.MoneyBundle\n'),
     (17, "duplicate trade accept 'Base.MoneyBundle'")),
    ('trade accept without value', trade(TRADE_OK + 'accept=Base.Hammer\n'),
     (17, "trade accept 'Base.Hammer' has no trade value (an item a trader cannot take)")),
    ('trade accept of an unknown category', trade(TRADE_OK + 'accept=gems\n'),
     (17, "unknown category 'gems' in trade accept")),
    ('trade accept of a category without value', trade(TRADE_OK + 'accept=tools\n'),
     (17, "category 'tools' has no item with a trade value")),
]

# E20-T11 : section [note] (note de fréquence déclarée par la fiche). En-tête ligne 13, NOTE_OK lignes 14 et 15.
NOTE_OK = 'item=RadioSurvivor.NoteWalt\nkey=NoteWalt\n'


def note(body: str) -> str:
    return BASE + '[note]\n' + body + PROMPT


CASES += [
    ('note section', note(NOTE_OK + 'loot=OfficeDesk:4\nloot=CrateFishing:1.5\nglovebox=GloveBox:1.5\ncorpse=yes\n'),
     None),
    ('note without key', note('item=RadioSurvivor.NoteWalt\n'), (13, "missing key 'key' in [note]")),
    ('note without item', note('key=NoteWalt\n'), (13, "missing key 'item' in [note]")),
    # E22-T07 : note écrite dans la fiche (text= répétable, %1 = fréquence), sans item ni key.
    ('written note', note('text=Need help? Call Mae\ntext=on %1 MHz.\nloot=OfficeDesk:2\ncorpse=yes\n'), None),
    ('written note of 8 lines of 40 bytes', note('text=%1\n' + ('text=' + 'é' * 20 + '\n') * 7), None),
    ('empty note', note('corpse=yes\n'), (13, "missing key 'text' in [note] (or item and key)")),
    ('written note without frequency', note('text=Call Mae.\n'),
     (13, 'note text needs %1 (the frequency) on one of its lines')),
    ('written note with item', note('text=Call %1\nitem=RadioSurvivor.NoteWalt\n'),
     (15, "item and key cannot be used with text in [note] (text goes on the handwritten note of the mod)")),
    ('written note with key', note('key=NoteWalt\ntext=Call %1\n'),
     (14, "item and key cannot be used with text in [note] (text goes on the handwritten note of the mod)")),
    ('note text line too long', note('text=%1 ' + 'a' * 38 + '\n'),
     (14, 'note text too long (40 bytes of UTF-8 at most)')),
    ('note text with a tag', note('text=<b>%1\n'),
     (14, "bad note text '<b>%1' (no <, > or ^; % only in %1, the frequency)")),
    ('note text with a caret', note('text=%1^next\n'),
     (14, "bad note text '%1^next' (no <, > or ^; % only in %1, the frequency)")),
    ('too many note text lines', note('text=%1\n' * 9), (22, 'too many note text lines (8 at most)')),
    ('bad note item', note(NOTE_OK.replace('RadioSurvivor.NoteWalt', 'NoteWalt')),
     (14, "bad note item 'NoteWalt' (Module.Type, e.g. RadioSurvivor.NoteWalt)")),
    ('bad note key', note(NOTE_OK.replace('key=NoteWalt', 'key=Note Walt')),
     (15, "bad note key 'Note Walt' (A to Z, a to z, 0 to 9 and _)")),
    ('bad loot', note(NOTE_OK + 'loot=OfficeDesk\n'), (16, "bad loot 'OfficeDesk' (list:weight, e.g. OfficeDesk:4)")),
    ('zero loot weight', note(NOTE_OK + 'glovebox=GloveBox:0\n'), (16, "bad glovebox weight '0' (above 0)")),
    ('duplicate loot list', note(NOTE_OK + 'loot=OfficeDesk:4\nloot=OfficeDesk:2\n'),
     (17, "duplicate loot list 'OfficeDesk'")),
    ('bad corpse', note(NOTE_OK + 'corpse=maybe\n'), (16, "bad corpse 'maybe' (yes or no)")),
    ('unknown key in note', note(NOTE_OK + 'colour=red\n'), (16, "unknown key 'colour' in [note]")),
]

# Faux type de mission du banc : chaque genre de paramètre, déclaré par le gabarit seul.
FAKE_TEMPLATE = r'''
require('CoreAI/CA_Missions').register('watchtower', {voiceName = 'watch_tower',
    voiceText = 'watch from a tower',
    params = {count = 'count', note = 'text', spot = 'place', quantity = 'range', items = 'category'}})
'''
FAKE_MISSION = mission('type=watch_tower\ncount=3\nnote=Count the crows.\nspot=church\nquantity=1-2\nitems=food\n')

# Natures de récompense du catalogue, dans l'ordre de CA_MissionConfig.Caches.order.
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

    def test_note_section_content(self):
        p, _ = self.read(note(NOTE_OK + 'loot=OfficeDesk:4\nloot=CrateFishing:1.5\nglovebox=GloveBox:2\ncorpse=yes\n'))
        n = p.note
        self.assertEqual((n.item, n.module, n.type, n.key, n.corpse),
                         ('RadioSurvivor.NoteWalt', 'RadioSurvivor', 'NoteWalt', 'NoteWalt', True))
        self.assertEqual([(e.list, e.weight) for e in lua_items(n.loot)], [('OfficeDesk', 4), ('CrateFishing', 1.5)])
        self.assertEqual([(e.list, e.weight) for e in lua_items(n.glovebox)], [('GloveBox', 2)])
        self.assertFalse(self.read(note(NOTE_OK))[0].note.corpse)

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
        self.assertEqual((meds.scope, meds.sets_state, look.scope), ('character', None, 'character'))
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
        # Contenu exact des tables figées de CA_MissionConfig.Caches.tables (caches des voix : catalogue, E20-T04).
        tables = self.lua.rt.eval('require("CoreAI/CA_MissionConfig").Caches')
        lines = store.split_lines(CATALOGUE.read_text(encoding='utf-8'))
        catalogue = self.lua.module.parseCatalogue(self.lua.rt.table_from(lines))
        self.assertFalse(isinstance(catalogue, tuple), catalogue)
        for name in lua_items(tables.order):
            with self.subTest(name):
                expected = [(row[1], row[2], row[2]) for row in lua_items(tables.tables[name])]
                self.assertEqual([(i.type, i.min, i.max) for i in lua_items(catalogue[name]['items'])], expected)
        # E23-T06 : plus les catégories de paiement des marchands (accept=), qui ne sont pas des tables de cache.
        payment = ['cash', 'jewelry', 'military_gear', 'papers_of_the_dead', 'pictures']
        self.assertEqual(sorted(catalogue.keys()), sorted(list(lua_items(tables.order)) + payment))
        self.assertEqual(sorted(self.lua.rules.categories.keys()), sorted(list(lua_items(tables.order)) + payment))

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
        self.assertEqual(rb.offered_actions(drops_only), ['remember'])   # E22-T13: every voice remembers


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
        # E20-T10 : Darlene donne la chaîne du retour à sa clinique (tests/test_darlene_chain.py), Cody les cinq types.
        expected = {
            'darlene': ('medical', 'Doctor',
                        [('scout_clinic', 'scout'), ('clear_clinic', 'clear'), ('secure_clinic', 'barricade'),
                         ('meds', 'deliver')],
                        [('clinic', ['mark', 'target']), ('drop_dumpsters', ['drop']), ('drop_bookstore', ['drop'])]),
            'cody': ('ammo', 'Aiming', [(t, t) for t in ('scout', 'deliver', 'retrieve', 'clear', 'signal')],
                     [('checkpoint', ['mark', 'target', 'drop'])]),
        }
        for vid, (table, skill, missions, places) in expected.items():
            with self.subTest(vid):
                s = self.sheets[vid]
                self.assertEqual([(m.id, m.type) for m in lua_items(s.missions)], missions)
                self.assertEqual([(r.kind, r.param, r.weight) for r in lua_items(s.rewards)],
                                 [('cache', table, 1), ('frequency', None, 1), ('stashmap', None, 1),
                                  ('lesson', skill, 1)])
                self.assertEqual([(q.id, lua_items(q.uses)) for q in lua_items(s.places)], places)

    def test_other_voices_give_no_mission(self):
        for vid in ('walt', 'gus', 'nightowl', 'whitaker'):
            with self.subTest(vid):
                s = self.sheets[vid]
                # E20-T07 : Gus n'a qu'un lieu, son ponton de rendez-vous (use=landing), et sa section [trade].
                places = [(p.id, tuple(lua_items(p.uses))) for p in lua_items(s.places)]
                self.assertEqual((lua_items(s.missions), lua_items(s.rewards), places),
                                 ([], [], [('riverside_pier', ('landing',))] if vid == 'gus' else []))
                self.assertEqual(s.trade is not None, vid == 'gus')


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
