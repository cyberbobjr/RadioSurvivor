"""Translations and sandbox options of the three mods of the article (E18-T13).

    python RadioSurvivor/tests/test_translations_split.py

Each mod ships its own keys and its own options page: the core mod batman_RadioSurvivorCore (IGUI_RC_: missions journal
and mission titles; no sandbox option, none of the existing options is about the missions or the bridge), Living Knox
(IGUI_LK_, Sandbox_LivingKnox_, page LivingKnox) and RadioSurvivor (the rest, page RadioSurvivor). Checks:

- union of the keys of the three mods = keys before the split (fixture tests/fixtures/e18-t13/keys-before.json, written
  from commit 4ab5c75, the last one with a single mod) + keys of the journal (E18-T06) and of the notebook frame of the
  core mod (E18-T24, journal window removed), mission titles and common tab labels renamed;
- no key shipped by two mods, prefixes of each mod kept apart, every shipped language has the same keys;
- every literal key used by the Lua of a mod is shipped by that mod, by a mod it requires or by the game;
- every sandbox option kept with the same name (settings of an existing game read again), on its mod's page, with its
  label in that mod;
- mission titles saved by an older game (IGUI_RS_<name>) shown with the new key (RC_MissionConfig.titleKey).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

from lupa import LuaRuntime

sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders)

ROOT = Path(__file__).resolve().parents[1]
MODS_DIR = ROOT / 'Contents' / 'mods'
MODS = {
    'core': 'batman_RadioSurvivorCore',
    'lk': 'batman_LivingKnox',
    'rs': 'batman_RadioSurvivor',
}
DEPS = {'core': (), 'lk': ('core',), 'rs': ('core',)}
FIXTURE = ROOT / 'tests' / 'fixtures' / 'e18-t13' / 'keys-before.json'

# Mission titles moved from RadioSurvivor to the core mod (old key -> new key).
RENAMED = {f'IGUI_RS_{n}': f'IGUI_RC_Mission_{n}' for n in (
    'FirstAid', 'Scout', 'Supply', 'Supply_food', 'Supply_medical', 'Supply_ammo',
    'Retrieve', 'Clear', 'Recover', 'Signal')}
# E18-T24: labels of the common tabs of the notebook, now in the core mod.
RENAMED.update({f'IGUI_RS_{n}': f'IGUI_RC_{n}' for n in ('Contacts', 'Missions', 'Reputation', 'Empty_Reputation')})
# E18-T24: frame of the notebook in the core mod; the journal window and its button are gone.
NOTEBOOK = {'IGUI_RC_Notebook', 'IGUI_RC_NotebookHint', 'IGUI_RC_Empty_Contacts'}
REMOVED = {'IGUI_RC_Journal', 'IGUI_RC_JournalButton', 'IGUI_RC_JournalHint'}
# E18-T25: the reputation page is drawn by the core mod; the act of a killed group member is Living Knox's text.
RENAMED.update({f'IGUI_RS_{n}': f'IGUI_RC_{n}' for n in (
    'GlobalReputation', 'ReputationUnavailable', 'RepLevelLine', 'RepTrendLine', 'RepLevel_bad', 'RepLevel_neutral',
    'RepLevel_good', 'RepTrend_up', 'RepTrend_down', 'RepTrend_stable', 'RepChanged', 'RepNoActs', 'RepLastActs',
    'RepAct', 'RepCapped', 'RepReason_good', 'RepReason_bad', 'RelWhen_today', 'RelWhen_yesterday', 'RelWhen_week',
    'RelWhen_earlier', 'RepReason_MissionSuccess', 'RepReason_MissionFailed', 'RepReason_MissionAbandoned')})
RENAMED['IGUI_RS_RepReason_MemberKilled'] = 'IGUI_LK_RepReason_MemberKilled'
REMOVED.add('IGUI_RC_Empty_Reputation')  # E18-T25: the core page shows the reputation (or that it is unavailable)
# E18-T26: the relation panel of an NPC is drawn by Living Knox; the core Contacts page has its own words.
RENAMED.update({k: 'IGUI_LK_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if k.startswith('IGUI_RS_Rel') and not k.startswith('IGUI_RS_RelWhen_')})
NOTEBOOK |= {'IGUI_RC_Group', 'IGUI_RC_KnownConversations', 'IGUI_RC_Contact', 'IGUI_RC_Dead'}
# E18-T20: the Team tab is Living Knox's; the errors of the mandates come from the core mod (RC_Teams).
RENAMED.update({k: 'IGUI_LK_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if any(k.startswith('IGUI_RS_' + p) for p in ('Team', 'Role_', 'Mandate', 'Empty_Team'))})
RENAMED.update({f'IGUI_RS_Error_{n}': f'IGUI_RC_Error_{n}' for n in ('MandateOwner', 'MandateMember', 'MandateFull')})
NOTEBOOK |= {'IGUI_RC_Error_State'}
JOURNAL = {
    'IGUI_RC_Journal', 'IGUI_RC_JournalButton', 'IGUI_RC_JournalEmpty', 'IGUI_RC_JournalHint', 'IGUI_RC_Mission',
    'IGUI_RC_Participants', 'IGUI_RC_ReportHint', 'IGUI_RC_Requester', 'IGUI_RC_Reward', 'IGUI_RC_TimeLeft',
    'IGUI_RC_State_abandoned', 'IGUI_RC_State_active', 'IGUI_RC_State_cancelled_closed',
    'IGUI_RC_State_cancelled_dead', 'IGUI_RC_State_expired', 'IGUI_RC_State_failed', 'IGUI_RC_State_offer',
    'IGUI_RC_State_success', 'IGUI_RC_State_toReport'}
PREFIX_OF = {
    'core': ('IGUI_RC_',),
    'lk': ('IGUI_LK_', 'Sandbox_LivingKnox'),
}
KEY_IN_LUA = re.compile(r"""["']((?:IGUI|Sandbox|ContextMenu|Tooltip|UI|Print_Media|Print_Text|Challenge)_[A-Za-z0-9_]+)["']""")


def media(mod: str) -> Path:
    return MODS_DIR / MODS[mod] / '42.21' / 'media'


def shipped(mod: str) -> dict[str, dict[str, set[str]]]:
    """{language: {file: keys}} of a mod (common and 42.21)."""
    out: dict[str, dict[str, set[str]]] = {}
    for variant in ('common', '42.21'):
        base = MODS_DIR / MODS[mod] / variant / 'media' / 'lua' / 'shared' / 'Translate'
        for path in sorted(base.glob('*/*.json')):
            data = json.loads(path.read_text(encoding='utf-8-sig'))
            out.setdefault(path.parent.name, {}).setdefault(path.stem, set()).update(data)
    return out


def flat(keys: dict[str, set[str]]) -> set[str]:
    return set().union(*keys.values()) if keys else set()


def options(mod: str) -> list[tuple[str, str, str]]:
    """(name, page, translation) of every option of a mod's sandbox-options.txt."""
    path = media(mod) / 'sandbox-options.txt'
    if not path.exists():
        return []
    text = path.read_text(encoding='utf-8')
    out = []
    for name, body in re.findall(r'^option\s+(\S+)\s*\{(.*?)\}', text, re.M | re.S):
        page = re.search(r'page\s*=\s*([A-Za-z0-9_]+)', body)
        tr = re.search(r'\btranslation\s*=\s*([A-Za-z0-9_]+)', body)
        out.append((name, page.group(1) if page else '', tr.group(1) if tr else ''))
    return out


# E18-T18: speech of Living Knox alone.
TALK = {'IGUI_LK_Talk_' + k for k in ('Menu', 'Prompt', 'Offer', 'Range', 'Text', 'Chat', 'Cooldown', 'Busy',
                                           'Bridge', 'NoAnswer')}


class TranslationSplitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = json.loads(FIXTURE.read_text(encoding='utf-8'))
        cls.keys = {mod: shipped(mod) for mod in MODS}

    def languages(self):
        return sorted(self.before['keys'])

    def test_union_is_keys_before_plus_journal(self):
        for lang in self.languages():
            for name, before in self.before['keys'][lang].items():
                expected = set(before)
                if name == 'IG_UI':
                    expected = ((expected - set(RENAMED)) | set(RENAMED.values()) | JOURNAL | NOTEBOOK | TALK) - REMOVED
                union = set()
                for mod in MODS:
                    union |= self.keys[mod].get(lang, {}).get(name, set())
                self.assertEqual(sorted(expected - union), [], f'{lang}/{name}.json: keys lost')
                self.assertEqual(sorted(union - expected), [], f'{lang}/{name}.json: unexpected keys')

    def test_no_key_in_two_mods(self):
        for lang in self.languages():
            seen: dict[str, str] = {}
            for mod in MODS:
                for key in flat(self.keys[mod].get(lang, {})):
                    self.assertNotIn(key, seen, f'{lang}: {key} shipped by {seen.get(key)} and {mod}')
                    seen[key] = mod

    def test_prefixes_kept_apart(self):
        for lang in self.languages():
            for mod in MODS:
                for key in flat(self.keys[mod].get(lang, {})):
                    owner = next((m for m, prefixes in PREFIX_OF.items() if key.startswith(prefixes)), 'rs')
                    self.assertEqual(owner, mod, f'{lang}: {key} in {mod}')

    def test_every_language_has_the_same_keys(self):
        for mod in MODS:
            langs = self.keys[mod]
            ref = langs.get('EN', {})
            for lang, files in langs.items():
                for name in set(ref) | set(files):
                    self.assertEqual(sorted(ref.get(name, set()) ^ files.get(name, set())), [],
                                     f'{MODS[mod]} {lang}/{name}.json differs from EN')
            self.assertEqual(sorted(langs), self.languages(), f'{MODS[mod]}: shipped languages')

    def test_keys_used_by_lua_are_reachable(self):
        vanilla = set()
        for path in (pz_paths.media_dir() / 'lua' / 'shared' / 'Translate' / 'EN').glob('*.json'):
            vanilla |= set(json.loads(path.read_text(encoding='utf-8-sig', errors='replace')))
        for mod in MODS:
            reachable = flat(self.keys[mod].get('EN', {})) | vanilla
            for dep in DEPS[mod]:
                reachable |= flat(self.keys[dep].get('EN', {}))
            missing = set()
            for path in sorted((media(mod) / 'lua').rglob('*.lua')):
                for key in KEY_IN_LUA.findall(path.read_text(encoding='utf-8')):
                    if not key.endswith('_') and key not in reachable:
                        missing.add(f'{path.name}: {key}')
            self.assertEqual(sorted(missing), [], f'{MODS[mod]}: keys used but not shipped by it or its requirements')

    def test_sandbox_options_kept_on_their_page(self):
        names = []
        pages = {'core': None, 'lk': 'LivingKnox', 'rs': 'RadioSurvivor'}
        for mod in MODS:
            sandbox = flat(self.keys[mod].get('EN', {}))
            for name, page, tr in options(mod):
                names.append(name)
                self.assertEqual(page, pages[mod], f'{name}: page in {MODS[mod]}')
                self.assertIn(f'Sandbox_{tr}', sandbox, f'{name}: label not in {MODS[mod]}')
        self.assertEqual(options('core'), [], 'the core mod has no sandbox option')
        self.assertEqual(sorted(names), sorted(self.before['options']), 'sandbox option names kept')

    def test_mission_titles_in_the_core_mod(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        path = media('core') / 'lua' / 'shared' / 'RadioSurvivorCore' / 'RC_MissionConfig.lua'
        mc = lua.execute(path.read_text(encoding='utf-8'))
        titles = {t.titleKey for t in mc.Missions.values()}
        self.assertTrue(titles <= set(RENAMED.values()), sorted(titles))


if __name__ == '__main__':
    unittest.main(verbosity=2)
