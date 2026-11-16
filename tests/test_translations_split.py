"""Translations and sandbox options of the three mods of the article (E18-T13).

    python RadioSurvivor/tests/test_translations_split.py

Each mod ships its own keys and its own options page: the core mod batman_CoreAI (IGUI_CA_: missions journal
and mission titles; no sandbox option, none of the existing options is about the missions or the bridge), Living Knox
(IGUI_LK_, Sandbox_LivingKnox_, page LivingKnox) and RadioSurvivor (the rest, page RadioSurvivor). Checks:

- union of the keys of the three mods = keys before the split (fixture tests/fixtures/e18-t13/keys-before.json, written
  from commit 4ab5c75, the last one with a single mod) + keys of the journal (E18-T06) and of the notebook frame of the
  core mod (E18-T24, journal window removed), mission titles and common tab labels renamed, keys added since (ADDED);
- no key shipped by two mods, prefixes of each mod kept apart, every shipped language has the same keys;
- every literal key used by the Lua of a mod is shipped by that mod, by a mod it requires or by the game;
- every sandbox option kept with the same name (settings of an existing game read again), on its mod's page, with its
  label in that mod;
- mission titles saved by an older game (IGUI_RS_<name>) shown with the new key (CA_MissionConfig.titleKey).
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
    'core': 'batman_CoreAI',
    'lk': 'batman_LivingKnox',
    'rs': 'batman_RadioSurvivor',
}
DEPS = {'core': (), 'lk': ('core',), 'rs': ('core',)}
FIXTURE = ROOT / 'tests' / 'fixtures' / 'e18-t13' / 'keys-before.json'

# Mission titles moved from RadioSurvivor to the core mod (old key -> new key).
RENAMED = {f'IGUI_RS_{n}': f'IGUI_CA_Mission_{n}' for n in (
    'FirstAid', 'Scout', 'Supply', 'Supply_food', 'Supply_medical', 'Supply_ammo',
    'Retrieve', 'Clear', 'Recover', 'Signal')}
# E18-T24: labels of the common tabs of the notebook, now in the core mod.
RENAMED.update({f'IGUI_RS_{n}': f'IGUI_CA_{n}' for n in ('Contacts', 'Missions', 'Reputation', 'Empty_Reputation')})
# E18-T24: frame of the notebook in the core mod; the journal window and its button are gone.
NOTEBOOK = {'IGUI_CA_Notebook', 'IGUI_CA_NotebookHint', 'IGUI_CA_Empty_Contacts'}
REMOVED = {'IGUI_CA_Journal', 'IGUI_CA_JournalButton', 'IGUI_CA_JournalHint'}
# E18-T25: the reputation page is drawn by the core mod; the act of a killed group member is Living Knox's text.
RENAMED.update({f'IGUI_RS_{n}': f'IGUI_CA_{n}' for n in (
    'GlobalReputation', 'ReputationUnavailable', 'RepLevelLine', 'RepTrendLine', 'RepLevel_bad', 'RepLevel_neutral',
    'RepLevel_good', 'RepTrend_up', 'RepTrend_down', 'RepTrend_stable', 'RepChanged', 'RepNoActs', 'RepLastActs',
    'RepAct', 'RepCapped', 'RepReason_good', 'RepReason_bad', 'RelWhen_today', 'RelWhen_yesterday', 'RelWhen_week',
    'RelWhen_earlier', 'RepReason_MissionSuccess', 'RepReason_MissionFailed', 'RepReason_MissionAbandoned')})
RENAMED['IGUI_RS_RepReason_MemberKilled'] = 'IGUI_LK_RepReason_MemberKilled'
REMOVED.add('IGUI_CA_Empty_Reputation')  # E18-T25: the core page shows the reputation (or that it is unavailable)
# E18-T26: the relation panel of an NPC is drawn by Living Knox; the core Contacts page has its own words.
RENAMED.update({k: 'IGUI_LK_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if k.startswith('IGUI_RS_Rel') and not k.startswith('IGUI_RS_RelWhen_')})
NOTEBOOK |= {'IGUI_CA_Group', 'IGUI_CA_KnownConversations', 'IGUI_CA_Contact', 'IGUI_CA_Dead'}
# E18-T20: the Team tab is Living Knox's; the errors of the mandates come from the core mod (CA_Teams).
RENAMED.update({k: 'IGUI_LK_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if any(k.startswith('IGUI_RS_' + p) for p in ('Team', 'Role_', 'Mandate', 'Empty_Team'))})
RENAMED.update({f'IGUI_RS_Error_{n}': f'IGUI_CA_Error_{n}' for n in ('MandateOwner', 'MandateMember', 'MandateFull')})
# E21-T03: generic lines of the mission views (CA_View_*) and labels of the map zones (CA_MapZones) in the core mod.
VIEW_WORDS = ('AcceptedItems', 'OneUnit', 'Progress', 'SupplyProgress', 'SupplyValues', 'ScoutMapZone', 'ScoutNotReached',
              'ScoutReached', 'ScoutReport', 'RetrieveFound', 'RetrieveMapZone', 'RetrieveNotFound', 'RetrievePerson',
              'RetrieveReport', 'SignalColor', 'SignalHour', 'SignalLit', 'SignalMapZone', 'SignalNotLit', 'SignalReport',
              'SignalRule', 'ClearBy', 'ClearMapZone', 'ClearProgress', 'ClearReport', 'ClearRule', 'RecoverCache',
              'RecoverDepotZone', 'RecoverFound', 'RecoverMapZone', 'RecoverNotFound', 'RecoverReport')
RENAMED.update({k: 'IGUI_CA_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if k[len('IGUI_RS_'):] in VIEW_WORDS
                or any(k.startswith('IGUI_RS_' + p) for p in ('Cache_', 'SignalColor_', 'MapZone'))})
NOTEBOOK |= {'IGUI_CA_Error_State'}
# E21-T04: notices of the agreements and incidents are Living Knox's (LK_AgreementNotices), same texts.
RENAMED.update({k: 'IGUI_LK_' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if any(k.startswith('IGUI_RS_' + p) for p in ('Agreement', 'Incident', 'RepairCategory_'))})
JOURNAL = {
    'IGUI_CA_Journal', 'IGUI_CA_JournalButton', 'IGUI_CA_JournalEmpty', 'IGUI_CA_JournalHint', 'IGUI_CA_Mission',
    'IGUI_CA_Participants', 'IGUI_CA_ReportHint', 'IGUI_CA_Requester', 'IGUI_CA_Reward', 'IGUI_CA_TimeLeft',
    'IGUI_CA_State_abandoned', 'IGUI_CA_State_active', 'IGUI_CA_State_cancelled_closed',
    'IGUI_CA_State_cancelled_dead', 'IGUI_CA_State_expired', 'IGUI_CA_State_failed', 'IGUI_CA_State_offer',
    'IGUI_CA_State_success', 'IGUI_CA_State_toReport'}
PREFIX_OF = {
    'core': ('IGUI_CA_', 'UI_optionscreen_binding_CoreAI'),
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
TALK = {'IGUI_LK_Talk_' + k for k in ('Menu', 'Prompt')}   # E21-T05: refusals and offers read by the notebook

# E18-T27: the option of the NPC initiatives belongs to Living Knox (its labels too).
OPTIONS_RENAMED = {'RadioSurvivor.InitiativeFrequency': 'LivingKnox.InitiativeFrequency'}
SANDBOX_RENAMED = ({k: 'Sandbox_LivingKnox_' + k[len('Sandbox_RadioSurvivor_'):]
                for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN'].get('Sandbox', [])
                if k.startswith('Sandbox_RadioSurvivor_InitiativeFrequency')})

# E18-T29: hand-over and claim from the journal of the core mod.
JOURNAL_GESTURES = {'IGUI_CA_' + k for k in ('Deliver', 'Claim', 'Delivery', 'DeliverSend', 'DeliverEmpty',
                                             'State_toClaim', 'ClaimHint', 'DeliverHint', 'Delivered',
                                             'RewardLot')} | {
    'IGUI_CA_Error_' + k for k in ('Range', 'Items', 'Storage', 'Recovery', 'Capacity', 'TooMany', 'SupplyClosed',
                                   'SupplyRefused', 'WrongCard')}

# E20-T05: the drop points of a voice mission listed by the notebook (RadioSurvivor); E20-T06: card left at a drop.
ADDED = {'IGUI_RS_DeadDropPoints', 'IGUI_RS_RetrieveDropCard',
         # E20-T09: template barricade (title, notebook view, map label).
         'IGUI_CA_Mission_Barricade', 'IGUI_CA_MapZoneBarricade', 'IGUI_CA_MapZoneBarricadeAnon',
         'IGUI_CA_BarricadePlace', 'IGUI_CA_BarricadeMapZone', 'IGUI_CA_BarricadeProgress', 'IGUI_CA_BarricadeRule',
         'IGUI_CA_BarricadeReport',
         # E20-T12: template relay (title, notebook view, map label).
         'IGUI_CA_Mission_Relay', 'IGUI_CA_MapZoneRelay', 'IGUI_CA_MapZoneRelayAnon', 'IGUI_CA_RelayPlace',
         'IGUI_CA_RelayMapZone', 'IGUI_CA_RelayLevel', 'IGUI_CA_RelayOn', 'IGUI_CA_RelayOff', 'IGUI_CA_RelayRule',
         'IGUI_CA_RelayReport'}
# E20-T13: template route (title, notebook view, map label).
ADDED |= {'IGUI_CA_Mission_Route', 'IGUI_CA_MapZoneRoute', 'IGUI_CA_MapZoneRouteAnon', 'IGUI_CA_RouteProgress',
          'IGUI_CA_RouteNext', 'IGUI_CA_RouteAllCrossed', 'IGUI_CA_RouteMapZone', 'IGUI_CA_RouteRule',
          'IGUI_CA_RouteReport'}
# E20-T14: template watch (title, notebook view, map label).
ADDED |= {'IGUI_CA_Mission_Watch', 'IGUI_CA_MapZoneWatch', 'IGUI_CA_MapZoneWatchAnon', 'IGUI_CA_WatchPlace',
          'IGUI_CA_WatchMapZone', 'IGUI_CA_WatchProgress', 'IGUI_CA_WatchDone', 'IGUI_CA_WatchRule',
          'IGUI_CA_WatchReport'}
# E20-T15: template item (title, notebook view, map label).
ADDED |= {'IGUI_CA_Mission_Item', 'IGUI_CA_MapZoneItem', 'IGUI_CA_MapZoneItemAnon', 'IGUI_CA_ItemWhat',
          'IGUI_CA_ItemPlace', 'IGUI_CA_ItemMapZone', 'IGUI_CA_ItemFound', 'IGUI_CA_ItemNotFound', 'IGUI_CA_ItemDropIt',
          'IGUI_CA_ItemOnlyThis', 'IGUI_CA_ItemReport'}


# E20-T11: radio lines of the arrival modes road and cache (RS_TradeRun.textFor), notes of the town traders.
ADDED |= {'IGUI_RS_TradeRun_' + k for k in (
    'Pier_road', 'Cancel_late_road', 'Done_road', 'Cancel_nodrop_road', 'Cancel_checkpoint', 'Cancel_air_patrol',
    'Cancel_washout', 'Pier_cache', 'Cancel_late_cache', 'Done_cache', 'Cheated_cache', 'Cancel_nodrop_cache',
    'Cancel_sweep', 'Cancel_overflight')}
# E22-T08: "Voice workshop: record this place" (RS_PlaceSurveyMenu) and its halo texts.
ADDED |= {'IGUI_RS_Survey_Menu', 'IGUI_RS_Survey_Done', 'IGUI_RS_Survey_Refused'}
# E23-T02: mission lost with a dead participant (state cancelled_lost, notices of the next character); E23-T03: delay
# stopped while the voice cannot hear the report.
ADDED |= {'IGUI_CA_LostMission', 'IGUI_CA_LostMissionTeam', 'IGUI_CA_State_cancelled_lost',
          'IGUI_CA_MissionState_cancelled_lost', 'IGUI_CA_StateShort_cancelled_lost', 'IGUI_CA_MissionPaused',
          'IGUI_RS_VoiceSilentWaiting'}
TOWN_NOTES = ('Wanda', 'Lamar', 'Delphine', 'Hollis', 'Loretta', 'Virgil', 'Boone', 'Odessa', 'Ezra', 'Maxine')
# E22-T07: generic handwritten note of the voices whose note text is written in their sheet (title and name only).
ADDED_FILES = {
    'Print_Media': {f'Print_Media_RadioSurvivor_Note{n}_{p}' for n in TOWN_NOTES for p in ('title', 'info')}
    | {'Print_Media_RadioSurvivor_NoteVoice_title'},
    'Print_Text': {f'Print_Text_RadioSurvivor_Note{n}_info' for n in TOWN_NOTES},
    'ItemName': {'RadioSurvivor.NoteTrade', 'RadioSurvivor.NoteVoice'},
}

# E21-T03: pages of the notebook moved to the core mod (CA_NotebookContacts, CA_NotebookMissions, CA_NotebookReputation,
# CA_NotebookClient): their words moved with them (same text); RadioSurvivor keeps what its Radio tab still uses.
NOTEBOOK_WORDS = (
    'Abandon', 'Accept', 'ClaimedBy', 'ClearTarget', 'ClueDistance_blocks', 'ClueDistance_short', 'ClueFloors_five',
    'ClueFloors_four', 'ClueFloors_single', 'ClueFloors_tall', 'ClueFloors_three', 'ClueFloors_two',
    'ClueSize_large', 'ClueSize_medium', 'ClueSize_small', 'ClueSize_very_large', 'Clue_Basement', 'Clue_BuiltUp',
    'Clue_FewHouses', 'Clue_Isolated', 'Clue_Kind', 'Clue_Landmark', 'Clue_LandmarkNext', 'Clue_NoLandmark',
    'Clue_TownCountry', 'Clue_TownFar', 'Clue_TownIn', 'Clue_TownOutskirts', 'ConfirmAbandon', 'ConfirmAccept',
    'ConfirmDelivery', 'ConfirmSupply', 'Contact', 'Dead', 'Deliver', 'Empty_Missions', 'Error_Bridge',
    'Error_Busy', 'Error_Capacity', 'Error_Chat', 'Error_Cooldown', 'Error_Identity', 'Error_Items',
    'Error_NoAnswer', 'Error_Recovery', 'Error_Session', 'Error_State', 'Error_Storage', 'Error_SupplyClosed',
    'Error_SupplyRefused', 'Error_Text', 'Error_TooMany', 'Error_WrongCard', 'Group', 'Invite', 'JoinRequester',
    'KnownConversations', 'Landmark_bakery', 'Landmark_bar', 'Landmark_barn', 'Landmark_bookstore',
    'Landmark_church', 'Landmark_clinic', 'Landmark_clothing', 'Landmark_daycare', 'Landmark_firestation',
    'Landmark_gas', 'Landmark_grocery', 'Landmark_gunstore', 'Landmark_gym', 'Landmark_hardware',
    'Landmark_hospital', 'Landmark_library', 'Landmark_liquor', 'Landmark_mechanic', 'Landmark_motel',
    'Landmark_pharmacy', 'Landmark_police', 'Landmark_post', 'Landmark_restaurant', 'Landmark_school',
    'Landmark_theatre', 'Landmark_warehouse', 'NewOffer', 'NoNPCProvider', 'NoRefund', 'Participants',
    'Place_apartments', 'Place_church', 'Place_clinic', 'Place_farmhouse', 'Place_firestation', 'Place_hospital',
    'Place_house', 'Place_house_garage', 'Place_motel', 'Place_police', 'Place_school', 'RepAdminButton',
    'RepAdminDenied', 'RepAdminLine', 'RepAdminTitle', 'RepWarn', 'ReportButton', 'ReportInPerson', 'Requester',
    'ReviewDelivery', 'RewardGoodwill', 'RewardInformation', 'SaveNote', 'ScoutClues', 'ScoutPlace',
    'StateShort_cancelled_closed', 'StateShort_cancelled_dead', 'StateShort_expired', 'StateShort_failed',
    'StateShort_offer', 'StateShort_toReport', 'Style_Direct', 'Style_Helpful', 'Style_Prudent', 'Style_Reserved',
    'Talk', 'TalkDead', 'TalkOutOfRange', 'TalkPlaceholder', 'TalkSelectFirst', 'TalkSend', 'TalkWaiting', 'Target',
    'Time', 'Traits', 'UseChat'
)
RENAMED.update({f'IGUI_RS_{n}': f'IGUI_CA_{n}' for n in NOTEBOOK_WORDS})
RENAMED.update({k: 'IGUI_CA_Mission' + k[len('IGUI_RS_'):] for k in json.loads(FIXTURE.read_text(encoding='utf-8'))['keys']['EN']
                ['IG_UI'] if k.startswith('IGUI_RS_State_')})
RENAMED.update({'IGUI_RS_' + old: 'IGUI_CA_' + new for old, new in (
    ('Claim', 'ClaimShared'), ('Reward', 'RewardShared'), ('Delivery', 'DeliveryPieces'),
    ('Empty_Contacts', 'NoContactsSelect'), ('Error_Range', 'Error_NpcRange'))})
UI_RENAMED = {'UI_optionscreen_binding_RadioSurvivorSelect': 'UI_optionscreen_binding_CoreAISelect'}
# Words the core pages share with RadioSurvivor's Radio tab (kept there too): a copy in the core mod.
ADDED |= {
    'IGUI_CA_Dir_east', 'IGUI_CA_Dir_north', 'IGUI_CA_Dir_north_east', 'IGUI_CA_Dir_north_west',
    'IGUI_CA_Dir_south', 'IGUI_CA_Dir_south_east', 'IGUI_CA_Dir_south_west', 'IGUI_CA_Dir_west', 'IGUI_CA_None',
    'IGUI_CA_Say'
}
# E23-T06..T08: trade by lists of items (agreed deal in the notebook, nothing left, trader never left alone).
ADDED |= {'IGUI_RS_Radio_trade', 'IGUI_RS_TradeDeal', 'IGUI_RS_RepReason_TradeNoDrop', 'IGUI_RS_Event_trade_nodrop',
          'IGUI_RS_TradeRun_Cancel_watched'}
# E24-T01: frequency debug panel, radio needed by level and fixed or drawn frequency instead of bands.
ADDED |= {'IGUI_RS_FreqDebug_Col_draw', 'IGUI_RS_FreqDebug_Drawn'} | {
    f'IGUI_RS_FreqDebug_Radio_{level}' for level in ('any_talkie', 'good_talkie', 'pro_talkie', 'tactical', 'military')}
REMOVED |= {'IGUI_RS_FreqDebug_Col_ranges', 'IGUI_RS_FreqDebug_Radio_any', 'IGUI_RS_FreqDebug_Radio_high_tier'}


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
                    expected = ((expected - set(RENAMED)) | set(RENAMED.values()) | JOURNAL | NOTEBOOK | TALK | JOURNAL_GESTURES | ADDED) - REMOVED
                elif name == 'UI':   # E21-T03: key binding of the notebook selection, now the core mod's
                    expected = {UI_RENAMED.get(k, k) for k in expected}
                elif name in ADDED_FILES:
                    expected = expected | ADDED_FILES[name]
                elif name == 'Sandbox':
                    moved = {k for k in expected if k in SANDBOX_RENAMED}
                    expected = (expected - moved) | {SANDBOX_RENAMED[k] for k in moved}
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
        before = [OPTIONS_RENAMED.get(name, name) for name in self.before['options']]
        self.assertEqual(sorted(names), sorted(before), 'sandbox option names kept')

    def test_mission_titles_in_the_core_mod(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        path = media('core') / 'lua' / 'shared' / 'CoreAI' / 'CA_MissionConfig.lua'
        mc = lua.execute(path.read_text(encoding='utf-8'))
        titles = {t.titleKey for t in mc.Missions.values()}
        # Renamed titles of an older game, or titles of templates added since (ADDED).
        self.assertTrue(titles <= set(RENAMED.values()) | ADDED, sorted(titles))


if __name__ == '__main__':
    unittest.main(verbosity=2)
