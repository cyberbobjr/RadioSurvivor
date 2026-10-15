"""Notes de fréquences (E05-T09) : RS_Notes.lua, RS_NotesServer.lua et RS_NotesReader.lua dans lupa, plus contrôles
statiques des scripts d'objets, des traductions et des listes de butin vanilla.

    python RadioSurvivor/tests/test_notes.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) avec les doublures de test_personas_server.py (fiches
réellement livrées, tirage d'un monde neuf) et des doublures minimales de l'objet, des distributions, de
ItemPickerJava et de ISReadABook. Couvre : fréquence écrite par l'autorité égale au tirage de la partie (cinq voix,
whitaker sans note), voix silencieuse ou disparue (note sans fréquence), OnCreate rejoué sur un client MP (aucune
fréquence, aucun fournisseur), aucune commande réseau dans les modules des notes, texte composé FR/EN (traductions
réelles, %1 remplacé comme Translator), ouverture du document (clés remises, autres documents intacts), butin selon
NoteRarity (facteurs, idempotence, mod désactivé), listes citées par des salles ou des véhicules de la 42.21.
Ne prouve pas l'API Java réelle : suite en jeu rs.notes et protocole docs/tests-en-jeu.md § 13.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

import lupa.lua51 as lupa

from test_personas_server import LUA, MOD, Harness, lua_list

ROOT = Path(__file__).resolve().parents[1]
TRANSLATE = LUA / 'shared/Translate'
SCRIPT = MOD / 'media/scripts/RadioSurvivor_notes.txt'
NOTES_LUA = [LUA / 'shared/RadioSurvivor/RS_Notes.lua', LUA / 'server/RadioSurvivor/RS_NotesServer.lua',
             LUA / 'client/RadioSurvivor/RS_NotesReader.lua']
VANILLA = pz_paths.media_dir()
VOICES = ['walt', 'darlene', 'cody', 'gus', 'nightowl']
TYPES = {'walt': 'NoteWalt', 'darlene': 'NoteDarlene', 'cody': 'NoteCody', 'gus': 'NoteGus',
         'nightowl': 'NoteNightOwl'}


def translations(lang: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in (TRANSLATE / lang).glob('*.json'):
        out.update(json.loads(path.read_text(encoding='utf-8')))
    return out


# Objet, distributions, ItemPickerJava, Events ; getText : table LANG (traductions réelles) avec %1..%9 remplacés
# comme Translator (clé inconnue rendue telle quelle).
NOTE_STUBS = r"""
function newItem(itemType)
    local item = { type = itemType, md = nil }
    function item:getType() return self.type end
    function item:getModData() if not self.md then self.md = {} end return self.md end
    function item:hasModData() return self.md ~= nil end
    return item
end
PARSED = 0
ItemPickerJava = { Parse = function() PARSED = PARSED + 1 end }
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    rawset(t, k, e) return e end })
LANG = {}
getText = function(key, ...)
    local s = LANG[key]
    if s == nil then return key end
    local args = { ... }
    return (string.gsub(s, "%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end
function resetLoot(lists, vehicles)
    ProceduralDistributions = { list = {} }
    for _, name in ipairs(lists) do ProceduralDistributions.list[name] = { rolls = 4, items = { "Base.Pencil", 2 } } end
    VehicleDistributions = {}
    for _, name in ipairs(vehicles) do VehicleDistributions[name] = { rolls = 1, items = {} } end
end
resetLoot({}, {})
package.preload["Items/ProceduralDistributions"] = function() return true end
package.preload["Vehicles/VehicleDistributions"] = function() return true end
"""


class NotesHarness(Harness):
    """Fiches réellement livrées, monde neuf (tirage), modules des notes chargés sur l'autorité (solo)."""

    bundled = None

    def setUp(self):
        super().setUp()
        self.rt.execute(NOTE_STUBS)
        self.load_world(True)
        self.Notes = self.rt.eval('require("RadioSurvivor/RS_Notes")')
        self.NS = self.rt.eval('require("RadioSurvivor/RS_NotesServer")')

    def set_lang(self, lang: str):
        table = self.rt.table_from(translations(lang))
        self.g.LANG = table

    def create(self, voice: str):
        item = self.g.newItem(TYPES[voice])
        self.g.RadioSurvivorNotes.onCreate(item)
        return item

    def entries(self) -> list:
        return [self.NS.ENTRIES[i] for i in range(1, len(self.NS.ENTRIES) + 1)]

    def reset_loot(self):
        lists = [e.list for e in self.entries() if not e.vehicle]
        vehicles = [e.list for e in self.entries() if e.vehicle]
        self.g.resetLoot(self.rt.table_from(lists), self.rt.table_from(vehicles))

    def items_of(self, entry) -> list:
        if entry.vehicle:
            return lua_list(self.g.VehicleDistributions[entry.list]['items'])
        return lua_list(self.g.ProceduralDistributions.list[entry.list]['items'])


class AuthorityTests(NotesHarness):

    def test_note_carries_the_drawn_frequency_of_its_voice(self):
        for voice in VOICES:
            with self.subTest(voice):
                served = self.served(voice)
                self.assertGreater(len(served), 0)
                md = self.create(voice).md
                self.assertEqual(md['printMedia']['id'], f'RadioSurvivor_{TYPES[voice]}')
                self.assertEqual(md['printMedia']['info'], f'Print_Media_RadioSurvivor_{TYPES[voice]}_info')
                self.assertEqual(md['printMedia']['text'], f'Print_Text_RadioSurvivor_{TYPES[voice]}_info')
                self.assertEqual(md['printMedia']['title'], f'Print_Media_RadioSurvivor_{TYPES[voice]}_title')
                self.assertEqual(md['RadioSurvivorNote']['voice'], voice)
                self.assertEqual(md['RadioSurvivorNote']['khz'], served[0])

    def test_two_worlds_two_frequencies(self):
        first = self.create('walt').md['RadioSurvivorNote']['khz']
        self.g.SEED, self.g.WORLD = 777, 'rstest_b'
        self.new_manager()
        self.load_world(True)
        second = self.create('walt').md['RadioSurvivorNote']['khz']
        self.assertEqual(second, self.served('walt')[0])
        self.assertNotEqual(first, second)

    def test_whitaker_has_no_note(self):
        self.assertIsNone(self.Notes.forVoice('whitaker'))
        self.assertEqual(sorted(e.voice for e in self.entries() if e.voice == 'whitaker'), [])
        self.assertEqual({e.voice for e in self.entries()}, set(VOICES))

    def test_silent_or_gone_voice_gives_a_note_without_frequency(self):
        for state in ('silent', 'gone'):
            with self.subTest(state):
                text = (self.dir / 'cody.txt').read_text(encoding='utf-8')
                self.write('cody.txt', re.sub(r'(?m)^state=.*$', f'state={state}', text))
                self.P.reload()
                note = self.create('cody').md['RadioSurvivorNote']
                self.assertEqual(note['voice'], 'cody')
                self.assertIsNone(note['khz'])
                self.assertEqual(self.Notes.frequencyLabel(note), '???.?')

    def test_unknown_item_type_left_alone(self):
        item = self.g.newItem('SheetPaper2')
        self.g.RadioSurvivorNotes.onCreate(item)
        self.assertIsNone(item.md)


class ClientTests(unittest.TestCase):
    """Client MP : fichiers server non chargés (isClient), OnCreate rejoué sans fournisseur ni fréquence."""

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute('SIDE = "client" isClient = function() return true end isServer = function() return false end '
                        'print = function() end')
        self.rt.execute(NOTE_STUBS)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server', 'client'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')

    def test_client_writes_no_frequency(self):
        notes = self.rt.eval('require("RadioSurvivor/RS_Notes")')
        self.rt.execute('require("RadioSurvivor/RS_NotesServer")')  # rend tout de suite sur un client
        self.assertIsNone(notes.frequencyProvider)
        self.assertEqual(len(lua_list(self.g.Events.OnInitGlobalModData.list)), 0)
        item = self.g.newItem('NoteWalt')
        self.g.RadioSurvivorNotes.onCreate(item)
        self.assertEqual(item.md['RadioSurvivorNote']['voice'], 'walt')
        self.assertIsNone(item.md['RadioSurvivorNote']['khz'])

    def test_no_network_command_in_the_note_modules(self):
        for path in NOTES_LUA:
            code = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
            with self.subTest(path.name):
                self.assertIsNone(re.search(r'send(Server|Client)Command|ModData\.(add|transmit|request)', code))


class ComposeTests(NotesHarness):

    def test_text_composed_in_english_and_french(self):
        for lang in ('EN', 'FR'):
            self.set_lang(lang)
            tr = translations(lang)
            for voice in VOICES:
                with self.subTest(lang=lang, voice=voice):
                    md = self.create(voice).md
                    label = self.Const.frequencyLabel(self.served(voice)[0])
                    info, text = self.Notes.compose(md)
                    self.assertIn(label + ' MHz', info)
                    self.assertIn(label + ' MHz', text)
                    self.assertNotIn('%1', info + text)
                    key = f'Print_Media_RadioSurvivor_{TYPES[voice]}_info'
                    self.assertEqual(info, tr[key].replace('%1', label))
        # Les deux langues diffèrent bien (pas de repli silencieux sur l'anglais).
        self.assertNotEqual(translations('EN')['Print_Text_RadioSurvivor_NoteGus_info'],
                            translations('FR')['Print_Text_RadioSurvivor_NoteGus_info'])

    def test_smudged_frequency(self):
        self.set_lang('EN')
        md = self.create('walt').md
        md['RadioSurvivorNote']['khz'] = None
        info, text = self.Notes.compose(md)
        self.assertIn('???.? MHz', info)
        self.assertIn('???.? MHz', text)

    def test_other_document_not_composed(self):
        md = self.rt.eval('{ printMedia = { id = "KnoxKnews_July1", info = "Print_Media_KnoxKnews_July1_info" } }')
        self.assertIsNone(self.Notes.compose(md))


READER_STUBS = r"""
DISPLAYED, LOADED = {}, 0
ISReadABook = {}
function ISReadABook:displayPrintMedia()
    local val = self.item:getModData().printMedia
    DISPLAYED[#DISPLAYED + 1] = { info = getText(val.info), text = getText(val.text), title = getText(val.title) }
end
function ISReadABook:startLoadingPrintMediaTextures() LOADED = LOADED + 1 return "texture" end
package.preload["TimedActions/ISReadABook"] = function() return true end
"""


class ReaderTests(NotesHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(READER_STUBS)
        paths = (LUA / 'client').as_posix() + '/?.lua'
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.rt.execute('require("RadioSurvivor/RS_NotesReader")')

    def read(self, item):
        action = self.rt.eval('function(item) return setmetatable({ item = item }, { __index = ISReadABook }) end')(item)
        self.assertIsNone(action.startLoadingPrintMediaTextures(action))
        action.displayPrintMedia(action)
        return self.g.DISPLAYED[len(self.g.DISPLAYED)]

    def test_document_opened_with_the_frequency_then_keys_restored(self):
        for lang in ('FR', 'EN'):
            self.set_lang(lang)
            item = self.create('nightowl')
            shown = self.read(item)
            label = self.Const.frequencyLabel(self.served('nightowl')[0])
            self.assertIn(label, shown['info'])
            self.assertIn(label, shown['text'])
            self.assertEqual(shown['title'], translations(lang)['Print_Media_RadioSurvivor_NoteNightOwl_title'])
            self.assertEqual(item.md['printMedia']['info'], 'Print_Media_RadioSurvivor_NoteNightOwl_info')
            self.assertEqual(item.md['printMedia']['text'], 'Print_Text_RadioSurvivor_NoteNightOwl_info')
        self.assertEqual(self.g.LOADED, 0)

    def test_other_document_untouched(self):
        item = self.g.newItem('Flier')
        item.getModData(item)['printMedia'] = self.rt.eval('{ id = "Flier1", info = "Print_Media_Flier1_info", '
                                                           'text = "Print_Text_Flier1_info", title = "t" }')
        action = self.rt.eval('function(item) return setmetatable({ item = item }, { __index = ISReadABook }) end')(item)
        self.assertEqual(action.startLoadingPrintMediaTextures(action), 'texture')
        action.displayPrintMedia(action)
        self.assertEqual(self.g.DISPLAYED[1]['info'], 'Print_Media_Flier1_info')

    def test_reload_does_not_stack_wrappers(self):
        self.rt.execute('package.loaded["RadioSurvivor/RS_NotesReader"] = nil require("RadioSurvivor/RS_NotesReader")')
        self.set_lang('EN')
        self.read(self.create('gus'))
        self.assertEqual(len(self.g.DISPLAYED), 1)


class LootTests(NotesHarness):

    def option(self, value=None, enabled=True):
        self.rt.execute(f'SandboxVars.RadioSurvivor.NoteRarity = {value if value is not None else "nil"}')
        self.g.ENABLED = enabled

    def test_rarity_factors(self):
        for value, factor in ((None, 1), (1, 0), (2, 0.4), (3, 1), (4, 2.5), (9, 1)):
            with self.subTest(value=value):
                self.option(value)
                self.reset_loot()
                parsed = self.g.PARSED
                added = self.NS.addToLoot()
                entries = self.entries()
                if factor == 0:
                    self.assertEqual(added, 0)
                    self.assertEqual(self.g.PARSED, parsed)
                else:
                    self.assertEqual(added, len(entries))
                    self.assertEqual(self.g.PARSED, parsed + 1)
                for entry in entries:
                    items = self.items_of(entry)
                    full = f'RadioSurvivor.{TYPES[entry.voice]}'
                    if factor == 0:
                        self.assertNotIn(full, items)
                    else:
                        i = items.index(full)
                        self.assertAlmostEqual(items[i + 1], entry.weight * factor)

    def test_idempotent_and_registered_on_init_global_mod_data(self):
        self.option(3)
        self.reset_loot()
        handlers = lua_list(self.g.Events.OnInitGlobalModData.list)
        self.assertEqual(len(handlers), 1)
        handlers[0]()
        self.assertEqual(self.NS.addToLoot(), 0)
        for entry in self.entries():
            self.assertEqual(self.items_of(entry).count(f'RadioSurvivor.{TYPES[entry.voice]}'), 1)

    def test_disabled_mod_adds_nothing(self):
        self.option(4, enabled=False)
        self.reset_loot()
        self.assertEqual(self.NS.addToLoot(), 0)

    def test_missing_list_logged(self):
        self.option(3)
        self.reset_loot()
        self.rt.execute('ProceduralDistributions.list.PoliceDesk = nil')
        self.assertEqual(self.NS.addToLoot(), len(self.entries()) - 1)
        self.assertEqual(len(self.logs_with('loot list PoliceDesk not found')), 1)


class StaticTests(unittest.TestCase):

    def entries(self) -> list[tuple[str, str, bool]]:
        code = (LUA / 'server/RadioSurvivor/RS_NotesServer.lua').read_text(encoding='utf-8')
        return [(m.group(1), m.group(2), bool(m.group(3))) for m in re.finditer(
            r'\{ voice = "(\w+)", list = "(\w+)", weight = [\d.]+(, vehicle = true)? \}', code)]

    def test_item_scripts(self):
        text = SCRIPT.read_text(encoding='utf-8')
        self.assertTrue(text.lstrip().startswith('module RadioSurvivor'))
        items = re.findall(r'item (\w+)\s*\{([^}]*)\}', text)
        self.assertEqual([name for name, _ in items], [TYPES[v] for v in VOICES])
        for name, body in items:
            with self.subTest(name):
                self.assertIn('OnCreate = RadioSurvivorNotes.onCreate,', body)
                self.assertIn('ItemType = base:literature,', body)
                self.assertIn('base:fastread', body)
                self.assertNotRegex(body, r'CanBeWrite|PageToWrite')

    def test_vanilla_icons_and_models(self):
        packs = sorted((VANILLA / 'texturepacks').glob('UI*.pack'))
        models = VANILLA / 'scripts/generated/models_items.txt'
        if not packs or not models.is_file():
            self.skipTest('vanilla media folder missing')
        blob = b''.join(p.read_bytes() for p in packs)
        model_text = models.read_text(encoding='utf-8', errors='replace')
        text = SCRIPT.read_text(encoding='utf-8')
        for icon in re.findall(r'Icon = (\w+),', text):
            self.assertRegex(blob, re.compile(rb'Item_' + icon.encode() + rb'(?![A-Za-z0-9_])'), icon)
        for model in set(re.findall(r'StaticModel = (\w+),', text)):
            self.assertRegex(model_text, rf'(?m)^\s*model {model}\s*$', model)

    def test_translations_complete_and_consistent(self):
        en, fr = translations('EN'), translations('FR')
        for voice in VOICES:
            t = TYPES[voice]
            keys = [f'RadioSurvivor.{t}', f'Print_Media_RadioSurvivor_{t}_title',
                    f'Print_Media_RadioSurvivor_{t}_info', f'Print_Text_RadioSurvivor_{t}_info']
            for key in keys:
                with self.subTest(key):
                    self.assertIn(key, en)
                    self.assertIn(key, fr)
                    self.assertEqual(re.findall(r'%\d', en[key]), re.findall(r'%\d', fr[key]))
                    self.assertNotRegex(en[key] + fr[key], r'%[^1]')
            for lang, tr in (('EN', en), ('FR', fr)):
                with self.subTest(lang=lang, voice=voice):
                    self.assertEqual(tr[f'Print_Media_RadioSurvivor_{t}_info'].count('%1'), 1)
                    self.assertGreaterEqual(tr[f'Print_Text_RadioSurvivor_{t}_info'].count('%1'), 1)
        for n in range(1, 5):
            self.assertIn(f'Sandbox_RadioSurvivor_NoteRarity_option{n}', en)
            self.assertIn(f'Sandbox_RadioSurvivor_NoteRarity_option{n}', fr)

    def test_layouts_parse_like_the_vanilla_reader(self):
        # PrintMedia.lua:68-84 : découpe sur <, >, puis , et : ; tout paramètre doit être clé:valeur.
        for lang in ('EN', 'FR'):
            tr = translations(lang)
            for voice in VOICES:
                info = tr[f'Print_Media_RadioSurvivor_{TYPES[voice]}_info']
                with self.subTest(lang=lang, voice=voice):
                    self.assertTrue(info.startswith('<type:parent, width:'))
                    for chunk in info.split('<')[1:]:
                        params, _, content = chunk.partition('>')
                        self.assertNotIn('>', content)
                        for param in params.split(','):
                            parts = param.split(':')
                            self.assertEqual(len(parts), 2, param)
                        self.assertNotRegex(params, r'texture:')  # rectangles seulement (rien à précharger)

    def test_no_secret_and_no_clinic_invitation(self):
        # Aucun secret des fiches, aucune invitation de Darlene à la clinique.
        bundled = MOD / 'personas'
        for lang in ('EN', 'FR'):
            tr = translations(lang)
            blob = ' '.join(v for k, v in tr.items() if 'RadioSurvivor_Note' in k).lower()
            with self.subTest(lang):
                for word in ('clinic', 'clinique', 'west point', 'insulin', 'whitaker', 'carl', 'civilians', 'civils',
                             'television', 'télévision'):
                    self.assertNotIn(word, blob)
        for voice in VOICES:
            for line in (bundled / f'{voice}.txt').read_text(encoding='utf-8').splitlines():
                if line.startswith('secret='):
                    self.assertNotIn(line[7:].lower()[:30], ' '.join(translations('EN').values()).lower())

    def test_loot_lists_cited_by_rooms_or_vehicles(self):
        dist = VANILLA / 'lua/server/Items/Distributions.lua'
        proc = VANILLA / 'lua/server/Items/ProceduralDistributions.lua'
        veh = VANILLA / 'lua/server/Vehicles/VehicleDistributions.lua'
        if not (dist.is_file() and proc.is_file() and veh.is_file()):
            self.skipTest('vanilla media folder missing')
        dist_text = re.sub(r'--[^\n]*', '', dist.read_text(encoding='utf-8', errors='replace'))
        proc_text = proc.read_text(encoding='utf-8', errors='replace')
        veh_text = veh.read_text(encoding='utf-8', errors='replace')
        entries = self.entries()
        self.assertEqual(len(entries), 20)
        for voice, name, vehicle in entries:
            with self.subTest(name):
                if vehicle:
                    self.assertIsNotNone(re.search(rf'(?m)^VehicleDistributions\.{name} = \{{', veh_text), name)
                    self.assertIsNotNone(re.search(rf'GloveBox = VehicleDistributions\.{name};', veh_text), name)
                else:
                    self.assertIsNotNone(re.search(rf'(?m)^\t{name} = \{{', proc_text), name)
                    self.assertIsNotNone(re.search(rf'name\s*=\s*"{name}"', dist_text), name)


if __name__ == '__main__':
    unittest.main(verbosity=1)
