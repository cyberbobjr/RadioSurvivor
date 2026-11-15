"""E22-T11: help of every setting of the voice workshop (bridge/atelier/help.js, i18n help.* keys).

    python RadioSurvivor/tests/test_atelier_help.py

Every element of the catalogue (bridge/atelier/catalog.json) has a help topic in French and in English, its key derived
from the catalogue names: a new mission type, parameter, reward kind, section key or closed choice only needs new
help keys, and this bench names the missing ones. Topics:
- help.head.<key>, help.head.<key>.<value>          head keys of a sheet and their closed choices (actions...);
- help.<section>.<key>, help.<section>.<key>.<value> keys of each section kind and their closed choices;
- help.mission_type.<type>                          each mission type; each of its parameters has
  help.mission_type.<type>.<param> or help.param.<param>, and each parameter kind help.param_kind.<kind>;
- help.reward.<kind>, help.skill.<skill>, help.shared_category.<id>;
- every literal topic the scripts pass to hint() (fields of the steps that are not catalogue names: help.ui.*).
A topic exists when its `.what` line exists; its other parts are .game, .example and .tip, all optional.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATELIER = ROOT / 'bridge' / 'atelier'
PARTS = ('what', 'game', 'example', 'tip')
HINT_LITERAL = re.compile(r"""hint\(\s*[a-zA-Z.]+\s*,\s*'(help\.[a-z0-9_.]+)'""")


def strings(lang: str) -> dict:
    return json.loads((ATELIER / 'i18n' / f'{lang}.json').read_text(encoding='utf-8'))


def catalog() -> dict:
    return json.loads((ATELIER / 'catalog.json').read_text(encoding='utf-8'))


def required_topics(data: dict) -> list[str]:
    """Help topics every catalogue element needs (the parameters of mission types are checked apart)."""
    topics = []
    header = data['header']
    for key in header['keys']:
        topics.append(f'help.head.{key}')
    for key, values in header['choices'].items():
        topics += [f'help.head.{key}.{value}' for value in values]
    for kind, section in data['sections'].items():
        topics += [f'help.{kind}.{key}' for key in section['keys']]
        for key, values in section.get('choices', {}).items():
            topics += [f'help.{kind}.{key}.{value}' for value in values]
    topics += [f'help.mission_type.{name}' for name in data['missionTypes']]
    topics += [f'help.param_kind.{kind}' for kind in data['paramKinds']]
    topics += [f'help.reward.{kind}' for kind in data['rewardKinds']]
    topics += [f'help.skill.{skill}' for skill in data['skills']]
    topics += [f'help.shared_category.{name}' for name in data['categories']]
    return topics


def script_topics() -> list[str]:
    found = set()
    for path in sorted(ATELIER.rglob('*.js')):
        found |= set(HINT_LITERAL.findall(path.read_text(encoding='utf-8')))
    return sorted(found)


class AtelierHelpTests(unittest.TestCase):
    def missing(self, topics: list[str]) -> dict[str, list[str]]:
        out = {}
        for lang in ('fr', 'en'):
            table = strings(lang)
            out[lang] = sorted(f'{topic}.what' for topic in topics if not str(table.get(f'{topic}.what', '')).strip())
        return out

    def test_every_catalogue_element_has_help_in_both_languages(self):
        topics = required_topics(catalog())
        self.assertGreater(len(topics), 100)
        self.assertEqual(self.missing(topics), {'fr': [], 'en': []})

    def test_every_mission_parameter_has_help(self):
        data = catalog()
        for lang in ('fr', 'en'):
            table = strings(lang)
            missing = [f'help.mission_type.{name}.{key}.what or help.param.{key}.what'
                       for name, mission in data['missionTypes'].items() for key in mission['params']
                       if f'help.mission_type.{name}.{key}.what' not in table and f'help.param.{key}.what' not in table]
            with self.subTest(lang):
                self.assertEqual(missing, [])

    def test_every_field_shown_by_the_steps_has_help(self):
        topics = script_topics()
        self.assertGreater(len(topics), 15, 'the steps pass their help topics to hint()')
        self.assertEqual(self.missing(topics), {'fr': [], 'en': []})

    def test_french_and_english_hold_the_same_help_keys(self):
        fr = {k for k in strings('fr') if k.startswith('help.')}
        en = {k for k in strings('en') if k.startswith('help.')}
        self.assertEqual(sorted(fr - en), [])
        self.assertEqual(sorted(en - fr), [])

    def test_help_keys_are_topic_parts(self):
        for lang in ('fr', 'en'):
            table = strings(lang)
            bad = sorted(k for k in table if k.startswith('help.') and k.rsplit('.', 1)[1] not in PARTS)
            orphans = sorted(k for k in table if k.startswith('help.') and not k.endswith('.what')
                             and f'{k.rsplit(".", 1)[0]}.what' not in table)
            with self.subTest(lang):
                self.assertEqual(bad, [], 'a help key ends with .what, .game, .example or .tip')
                self.assertEqual(orphans, [], 'a help part without the .what line of its topic')


if __name__ == '__main__':
    unittest.main()
