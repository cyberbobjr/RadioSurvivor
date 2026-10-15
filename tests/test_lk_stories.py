"""Tests hors jeu des histoires de groupe Living Knox (LK10-T01) : gabarits Data/Stories.lua, combineur LK_Stories.lua.

    python RadioSurvivor/tests/test_lk_stories.py            # banc
    python RadioSurvivor/tests/test_lk_stories.py --sample   # trois histoires par type, en anglais et en français

Banc tests/harness.py (lupa, Lua 5.1). Les longueurs sont comptées en octets UTF-8 : en Kahlua, une chaîne compte
en unités UTF-16 (base kahlua-lua.md), jamais plus que ses octets, donc une borne tenue ici l'est aussi en jeu.
Les règles de compatibilité sont revérifiées ici en Python à partir des données, indépendamment du combineur.
"""
from __future__ import annotations

import sys
import unittest
from itertools import combinations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402

DATA_FILE = LUA / 'shared' / 'LivingKnox' / 'Data' / 'Stories.lua'
SERVER_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Stories.lua'
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua')
STORIES = 'server/LivingKnox/LK_Stories.lua'
CATEGORIES = ('origins', 'motivations', 'tones', 'leaderPasts', 'secrets')
SEEDS = range(1, 101)
SUMMARY_MAX = 600


def py(value):
    """Table Lua -> liste (clés 1..n) ou dictionnaire, récursivement."""
    if hasattr(value, 'items') and not isinstance(value, (str, bytes, dict)):
        d = {k: py(v) for k, v in value.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d
    return value


def nbytes(text: str) -> int:
    return len(text.encode('utf-8'))


def make(mode='solo'):
    h = Harness(mode=mode)
    machines = ('solo',) if mode == 'solo' else ('server', 'A')
    for m in machines:
        for path in SHARED:
            h.load(m, path)
        h.load(m, STORIES)
    return h


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = make()
        cls.data = py(cls.h.eval('solo', 'LivingKnox.StoryData'))
        cls.types = py(cls.h.eval('solo', 'LivingKnox.Stories.groupTypes()'))  # sans registre : types livrés
        cls.by_id = {c: {f['id']: f for f in cls.data[c]} for c in CATEGORIES}

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def compose(self, group_type, seed, opts='nil'):
        seed_lua = repr(seed) if isinstance(seed, int) else '"' + seed + '"'
        out = self.h.eval('solo', f'LivingKnox.Stories.compose("{group_type}", {seed_lua}, {opts})')
        if isinstance(out, tuple):
            return py(out[0]), out[1]
        return py(out), None

    def frags(self, story):
        """Fragments des données choisis par une histoire, dans l'ordre du tirage."""
        out = [self.by_id['origins'][story['origin']['id']], self.by_id['motivations'][story['motivation']['id']],
               self.by_id['tones'][story['tone']['id']], self.by_id['leaderPasts'][story['leader']['past']['id']]]
        return out + [self.by_id['secrets'][s['id']] for s in story['secrets']]


class DataTests(Base):
    def test_check_data_is_clean_and_counts(self):
        self.assertEqual(py(self.h.eval('solo', 'LivingKnox.Stories.checkData()')), {})
        counts = {c: len(self.data[c]) for c in CATEGORIES}
        minimum = {'origins': 21, 'motivations': 15, 'tones': 6, 'leaderPasts': 10, 'secrets': 12}
        for c, n in minimum.items():
            self.assertGreaterEqual(counts[c], n, c)
        self.assertEqual(set(self.types), {'settlers', 'raiders', 'neutrals'})
        # LK10-T05 : assez d'origines par type pour que deux groupes d'une population partagent rarement la leur.
        for t in self.types:
            n = len([f for f in self.data['origins'] if not f.get('types') or t in f['types']])
            self.assertGreaterEqual(n, 12, f'origins for {t}')
        for t in self.types:  # chaque type a ses fragments propres dans chaque catégorie
            for c in CATEGORIES:
                own = [f for f in self.data[c] if f.get('types') and t in f['types']]
                self.assertTrue(own, f'{c} has no fragment of its own for {t}')

    def test_registry_types_covered(self):
        # Registre LK08-T02 chargé comme en jeu (fichiers partagés, dont les types livrés) : mêmes types couverts.
        h = Harness(mode='solo')
        try:
            for path in SHARED + ('shared/LivingKnox/LK_GroupTypes.lua',):
                h.load('solo', path)
            for path in sorted((LUA / 'shared' / 'LivingKnox' / 'Data').glob('LK_Type_*.lua')):
                h.load('solo', 'shared/LivingKnox/Data/' + path.name)
            h.load('solo', STORIES)
            ids = py(h.eval('solo', 'LivingKnox.GroupTypes.ids()'))
            self.assertEqual(py(h.eval('solo', 'LivingKnox.Stories.groupTypes()')), ids)
            self.assertTrue(set(self.types) <= set(ids), ids)
            self.assertEqual(py(h.eval('solo', 'LivingKnox.Stories.checkData()')), {})
        finally:
            h.close()

    def test_lua_sources_are_ascii(self):
        # Kahlua remplace tout octet non ASCII d'un littéral (base kahlua-lua.md) : échappements d'octets seulement.
        for path in (DATA_FILE, SERVER_FILE):
            text = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
            self.assertTrue(code.isascii(), f'non-ASCII outside comments in {path.name}')

    def test_texts_are_clean(self):
        accents = 0
        for c in CATEGORIES:
            for f in self.data[c]:
                for key in ('en', 'fr', 'frF'):
                    text = f.get(key)
                    if text is None:
                        continue
                    where = f'{c}.{f["id"]}.{key}'
                    self.assertNotIn('�', text, where)
                    self.assertEqual(text, text.strip(), where)
                    self.assertNotIn('  ', text, where)
                    if c == 'leaderPasts':  # apposition : minuscule, sans point final
                        self.assertTrue(text[0].islower() and not text.endswith('.'), where)
                    else:
                        self.assertTrue(text[0].isupper() and text.endswith('.'), where)
                    if key == 'en':
                        self.assertTrue(text.isascii(), where)
                    accents += sum(ch in 'éèêàâçôîïù' for ch in text)
                self.assertNotEqual(f['en'], f['fr'], f['id'])
                for mark in (' ;', ' :'):  # espace avant ; et : en français seulement
                    self.assertNotIn(mark, f['en'], f['id'])
        self.assertGreater(accents, 100)
        # Passés de chef : forme féminine pour chaque forme française accordée (sinon fr vaut pour les deux sexes).
        for f in self.data['leaderPasts']:
            if f['fr'].startswith('ancien ') or f['id'] in ('nurse', 'mechanic', 'trucker', 'preacher'):
                self.assertIn('frF', f, f['id'])

    def test_names_and_no_vehicle_fragments(self):
        # Relecture 2026-10-10 : noms de personnages (ASCII), aucun fragment qui suppose des véhicules au campement.
        for key, n in (('firstNamesMale', 16), ('firstNamesFemale', 16), ('surnames', 24)):
            names = self.data[key]
            self.assertGreaterEqual(len(names), n, key)
            self.assertEqual(len(names), len(set(names)), key)
            for name in names:
                self.assertTrue(name.isascii() and name.isalpha() and name[0].isupper(), name)
        for c in CATEGORIES:
            for f in self.data[c]:
                self.assertFalse({'road', 'convoy'} & set(f.get('tags', []) + f.get('excludes', [])
                                                       + f.get('requires', [])), f['id'])
                self.assertNotIn(f['id'], ('bikers', 'truck_stop'))
                for key in ('en', 'fr', 'frF'):
                    text = f.get(key, '').lower()
                    for word in ('motorcycle', 'motard', 'semi-remorque', ' rigs', 'truck stop', 'loading dock', 'quais de'):
                        self.assertNotIn(word, text, f'{f["id"]}.{key}')

    def test_worst_case_summary_fits(self):
        # Pire cas par type et par langue : plus longs fragments permis + nom de chef de NAME_MAX octets.
        name_max = self.h.eval('solo', 'LivingKnox.Stories.NAME_MAX')
        self.assertEqual(self.h.eval('solo', 'LivingKnox.Stories.SUMMARY_MAX'), SUMMARY_MAX)
        lead = {'en': nbytes('Their leader is , .'), 'fr': nbytes('Leur chef est , .')}
        for t in self.types + ['traders']:
            for lang in ('en', 'fr'):
                def longest(c):
                    sizes = [nbytes(f.get('frF', f[lang]) if lang == 'fr' else f[lang]) for f in self.data[c]
                             if not f.get('types') or t in f['types']]
                    sizes += [nbytes(f[lang]) for f in self.data[c] if not f.get('types') or t in f['types']]
                    return max(sizes)
                total = (longest('origins') + longest('motivations') + longest('tones') + longest('leaderPasts')
                         + lead[lang] + name_max + 3)
                self.assertLessEqual(total, SUMMARY_MAX, f'{t}/{lang}: {total}')


class ComposeTests(Base):
    def check_rules(self, group_type, story):
        frags = self.frags(story)
        for f in frags:
            self.assertTrue(not f.get('types') or group_type in f['types'], f'{f["id"]} not for {group_type}')
        for a, b in combinations(frags, 2):
            self.assertFalse(set(a.get('excludes', [])) & set(b.get('tags', [])), f'{a["id"]} excludes {b["id"]}')
            self.assertFalse(set(b.get('excludes', [])) & set(a.get('tags', [])), f'{b["id"]} excludes {a["id"]}')
        for i, f in enumerate(frags):
            if f.get('requires'):
                before = set().union(*(set(x.get('tags', [])) for x in frags[:i]))
                self.assertTrue(set(f['requires']) & before, f'{f["id"]} requirement not met')
        ids = [s['id'] for s in story['secrets']]
        self.assertEqual(len(ids), len(set(ids)))
        # Incohérences grossières nommées : ton pacifique ou pieux et violence, pillards pacifiques.
        tags = set().union(*(set(f.get('tags', [])) for f in frags))
        if story['tone']['id'] == 'peaceful':
            self.assertFalse(tags & {'violent', 'power'})
        if story['tone']['id'] == 'devout':
            self.assertFalse(tags & {'violent', 'plunder'})
        if story['tone']['id'] == 'wary':
            self.assertNotIn('plunder', tags)
        if story['tone']['id'] == 'desperate':
            self.assertFalse(tags & {'power', 'hoard'})
        if group_type == 'raiders':
            self.assertNotIn(story['tone']['id'], ('peaceful', 'devout', 'grieving'))
            self.assertNotIn(story['motivation']['id'], ('take_in', 'hold_ground', 'wait_army'))
        if group_type == 'settlers':
            self.assertFalse({'violent', 'plunder', 'power'} & tags)

    def test_hundred_draws_per_type(self):
        for t in self.types:
            summaries, origins, tones = set(), set(), set()
            for seed in SEEDS:
                story, err = self.compose(t, seed)
                self.assertIsNone(err, f'{t}/{seed}')
                self.assertEqual((story['type'], story['seed'], story['format']), (t, seed, 1))
                self.check_rules(t, story)
                self.assertEqual(len(story['secrets']), 2)
                for lang in ('en', 'fr'):
                    s = story['summary'][lang]
                    self.assertLessEqual(nbytes(s), SUMMARY_MAX, f'{t}/{seed}/{lang}')
                    self.assertIn(story['leader']['name'], s)
                    self.assertTrue(s.startswith(story['origin'][lang]) and s.endswith(story['tone'][lang]))
                    self.assertIn(story['leader']['past'][lang], s)
                    for sec in story['secrets']:
                        self.assertNotIn(sec[lang], s)
                past = self.by_id['leaderPasts'][story['leader']['past']['id']]
                expected = past.get('frF', past['fr']) if story['leader']['female'] else past['fr']
                self.assertEqual(story['leader']['past']['fr'], expected)
                summaries.add(story['summary']['en'])
                origins.add(story['origin']['id'])
                tones.add(story['tone']['id'])
            self.assertGreaterEqual(len(summaries), 95, t)
            self.assertEqual(origins, {f['id'] for f in self.data['origins'] if not f.get('types') or t in f['types']})
            self.assertGreaterEqual(len(tones), 4, t)

    def test_rule_check_catches_a_broken_rule(self):
        # Le contrôle Python n'est pas complaisant : sans l'exclusion du ton pacifique, il voit l'incohérence.
        h = make()
        try:
            h.load('solo', 'for _, t in ipairs(LivingKnox.StoryData.tones) do'
                           ' if t.id == "peaceful" then t.types = nil; t.excludes = nil end end')
            caught = 0
            for seed in SEEDS:
                story = py(h.eval('solo', f'LivingKnox.Stories.compose("raiders", {seed})'))
                try:
                    self.check_rules('raiders', story)
                except AssertionError:
                    caught += 1
            self.assertGreater(caught, 0)
        finally:
            h.close()

    def test_deterministic_across_runs(self):
        first = [self.compose(t, s) for t in self.types for s in (1, 7, 99, 'grp-3')]
        again = [self.compose(t, s) for t in self.types for s in (1, 7, 99, 'grp-3')]
        self.assertEqual(first, again)
        other = make()  # nouvelle VM : même résultat (aucun état caché, aucune autre source de hasard)
        try:
            self.assertEqual(py(other.eval('solo', 'LivingKnox.Stories.compose("raiders", 42)')),
                             self.compose('raiders', 42)[0])
        finally:
            other.close()
        self.assertNotEqual(self.compose('settlers', 1)[0]['summary'], self.compose('settlers', 2)[0]['summary'])
        self.assertNotEqual(self.compose('settlers', 5)[0]['summary'], self.compose('neutrals', 5)[0]['summary'])

    def test_options_and_errors(self):
        story, _ = self.compose('settlers', 3, '{ leaderName = "Ada Combs", female = true, secrets = 3 }')
        self.assertEqual((story['leader']['name'], story['leader']['female'], len(story['secrets'])),
                         ('Ada Combs', True, 3))
        self.assertIn('Their leader is Ada Combs, ', story['summary']['en'])
        self.assertIn('Leur chef est Ada Combs, ', story['summary']['fr'])
        base, _ = self.compose('settlers', 3)
        self.assertEqual(base['origin'], story['origin'])  # les options ne décalent pas le tirage
        for args, reason in [('"Settlers", 1', 'bad type'), ('"", 1', 'bad type'), ('nil, 1', 'bad type'),
                             ('"settlers", 1.5', 'bad seed'), ('"settlers", nil', 'bad seed'),
                             ('"settlers", ""', 'bad seed'), ('"settlers", 2^51', 'bad seed'),
                             ('"settlers", 1, 5', 'bad options'), ('"settlers", 1, { secrets = 4 }', 'bad secret count'),
                             ('"settlers", 1, { female = 1 }', 'bad female flag'),
                             ('"settlers", 1, { leaderName = string.rep("x", 33) }', 'bad leader name')]:
            out = self.h.eval('solo', f'LivingKnox.Stories.compose({args})')
            self.assertEqual(out, (None, reason), args)
        story, _ = self.compose('settlers', -12)
        self.assertIsNotNone(story)

    def test_type_without_own_fragments(self):
        # Type ajouté par données (LK08-T02) sans gabarit propre : seuls les fragments sans liste types.
        for seed in SEEDS:
            story, err = self.compose('traders', seed)
            self.assertIsNone(err)
            for f in self.frags(story):
                self.assertNotIn('types', f)

    def test_language_choice(self):
        story, _ = self.compose('neutrals', 8)
        self.h.load('solo', 'STORY = LivingKnox.Stories.compose("neutrals", 8)')
        self.assertEqual(self.h.eval('solo', 'LivingKnox.Stories.text(STORY, "FR")'), story['summary']['fr'])
        self.assertEqual(self.h.eval('solo', 'LivingKnox.Stories.text(STORY, "fr")'), story['summary']['fr'])
        self.assertEqual(self.h.eval('solo', 'LivingKnox.Stories.text(STORY, "EN")'), story['summary']['en'])
        self.assertEqual(self.h.eval('solo', 'LivingKnox.Stories.text(STORY, "DE")'), story['summary']['en'])
        self.assertIsNone(self.h.eval('solo', 'LivingKnox.Stories.text(nil, "FR")'))


class PrivacyTests(Base):
    def test_secrets_marked_private_and_stripped(self):
        self.assertEqual(py(self.h.eval('solo', 'LivingKnox.Stories.PRIVATE_FIELDS')), ['secrets'])
        self.h.load('solo', 'STORY = LivingKnox.Stories.compose("raiders", 17, { secrets = 3 })'
                            ' PUB = LivingKnox.Stories.publicView(STORY)')
        story, pub = py(self.h.eval('solo', 'STORY')), py(self.h.eval('solo', 'PUB'))
        self.assertTrue(all(s['private'] is True for s in story['secrets']))
        self.assertNotIn('secrets', pub)
        self.assertEqual(len(story['secrets']), 3)  # l'original garde ses secrets
        flat = repr(pub)
        for s in story['secrets']:
            self.assertNotIn(s['en'], flat)
            self.assertNotIn(s['fr'], flat)
        self.assertFalse(self.h.eval('solo', 'rawequal(PUB.leader, STORY.leader)'))  # copie profonde
        self.assertEqual({k: v for k, v in story.items() if k != 'secrets'}, pub)

    def test_client_stops_at_guard(self):
        h = make('mp')
        try:
            self.assertIsNone(h.eval('A', 'LivingKnox.Stories'))  # client MP : media/lua/server sans effet
            self.assertIsNotNone(h.eval('server', 'LivingKnox.Stories.compose("settlers", 1)'))
            h.load('A', 'shared/LivingKnox/Data/Stories.lua')  # gabarits partagés seulement, aucun tirage
            self.assertIsNotNone(h.eval('A', 'LivingKnox.StoryData'))
            self.assertFalse([e for e in h.errors('A') + h.errors('server')])
        finally:
            h.close()


def sample():
    h = make()
    try:
        types = py(h.eval('solo', 'LivingKnox.Stories.groupTypes()'))
        for t in types:
            for seed in (1, 2, 3):
                story = py(h.eval('solo', f'LivingKnox.Stories.compose("{t}", {seed})'))
                print(f'=== {t} / seed {seed} ({"F" if story["leader"]["female"] else "M"}) ===')
                for lang in ('en', 'fr'):
                    print(f'[{lang}] {story["summary"][lang]}')
                    for s in story['secrets']:
                        print(f'  (secret) {s[lang]}')
                print()
    finally:
        h.close()


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if '--sample' in sys.argv:
        sample()
    else:
        unittest.main()
