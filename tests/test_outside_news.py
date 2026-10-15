"""Journal du dehors (E13-T05) : RS_OutsideNews.lua, RS_OutsideNewsServer.lua et RS_NotesReader.lua dans lupa, plus
contrôles statiques du script d'objet, des traductions, de la mise en page et du barème.

    python RadioSurvivor/tests/test_outside_news.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) avec des doublures minimales : GameTime (âge du monde,
calendrier compté depuis 0), instanceItem (qui appelle l'OnCreate du script comme Item.InstanceItem), getText sur
les traductions réelles (%1..%9 remplacés comme Translator, clé inconnue rendue telle quelle), joueur et inventaire,
ISReadABook. Couvre : édition créée par le point d'appel E13-T04 (clés et nombres seulement dans la ModData), texte
qui change d'un passage à l'autre (une jamais répétée deux fois de suite, prix qui montent), même passage = même
édition, date du jour de jeu, édition de la semaine en cours par défaut et à l'OnCreate, numéro invalide refusé,
composition FR/EN sans clé ni paramètre restant, mise en page lisible par le parseur vanilla et tenant dans la page
(métriques des polices SDF vanilla, retour à la ligne d'AtomUIText), glyphes présents, ouverture du document (titre,
mise en page et transcription composés puis clés remises, marque « lu » par édition), journal non revendable
(barème), commande de test give, client MP (fichier serveur non chargé), aucun secret ni fréquence.
Ne prouve pas l'API Java réelle : suite en jeu rs.outside_news.
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

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21'
LUA = MOD / 'media/lua'
TRANSLATE = LUA / 'shared/Translate'
SCRIPT = MOD / 'media/scripts/RadioSurvivor_outsidenews.txt'
NEWS_LUA = [LUA / 'shared/RadioSurvivor/RS_OutsideNews.lua', LUA / 'server/RadioSurvivor/RS_OutsideNewsServer.lua',
            LUA / 'client/RadioSurvivor/RS_NotesReader.lua']
VANILLA = pz_paths.media_dir()
FONTS = VANILLA / 'fonts'
K = 'Print_Text_RadioSurvivor_OutsideNews_'


def translations(lang: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in (TRANSLATE / lang).glob('*.json'):
        out.update(json.loads(path.read_text(encoding='utf-8')))
    return out


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


STUBS = r"""
LOGS, SENT = {}, {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
SIDE = SIDE or "solo"
isClient = function() return SIDE == "client" end
isServer = function() return SIDE == "server" end
CLOCK = { hours = 0, y = 1993, m = 6, d = 8 }
getGameTime = function() return {
    getWorldAgeHours = function() return CLOCK.hours end,
    getYear = function() return CLOCK.y end,
    getMonth = function() return CLOCK.m end,
    getDay = function() return CLOCK.d end } end
function newItem(itemType)
    local item = { type = itemType, md = nil }
    function item:getType() return self.type end
    function item:getFullType() return "RadioSurvivor." .. self.type end
    function item:getModData() if not self.md then self.md = {} end return self.md end
    function item:hasModData() return self.md ~= nil end
    return item
end
-- Item.InstanceItem : objet du script puis OnCreate (fonction résolue par son nom pointé).
INSTANCE_OK = true
instanceItem = function(fullType)
    if not INSTANCE_OK or fullType ~= "RadioSurvivor.OutsideNews" then return nil end
    local item = newItem("OutsideNews")
    RadioSurvivorOutsideNews.onCreate(item)
    return item
end
function newPlayer(name)
    local items = {}
    local inv = { items = items }
    function inv:AddItem(item) items[#items + 1] = item return item end
    local p = { inv = inv }
    function p:getInventory() return self.inv end
    function p:getUsername() return name end
    return p
end
PLAYER = newPlayer("solo_player")
getPlayer = function() return PLAYER end
sendAddItemToContainer = function(inv, item) SENT[#SENT + 1] = item end
LANG = {}
getText = function(key, ...)
    local s = LANG[key]
    if s == nil then return key end
    local args = { ... }
    return (string.gsub(s, "%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end
DISPLAYED, LOADED = {}, 0
ISReadABook = {}
function ISReadABook:displayPrintMedia()
    local val = self.item:getModData().printMedia
    DISPLAYED[#DISPLAYED + 1] = { info = getText(val.info), text = getText(val.text), title = getText(val.title) }
end
function ISReadABook:startLoadingPrintMediaTextures() LOADED = LOADED + 1 return "texture" end
package.preload["TimedActions/ISReadABook"] = function() return true end
"""


class NewsHarness(unittest.TestCase):

    side = 'solo'

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.g.SIDE = self.side
        self.rt.execute(STUBS)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server', 'client'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.News = self.rt.eval('require("RadioSurvivor/RS_OutsideNews")')
        self.NS = self.rt.eval('require("RadioSurvivor/RS_OutsideNewsServer")')
        self.set_lang('EN')

    def set_lang(self, lang: str):
        self.g.LANG = self.rt.table_from(translations(lang))

    def edition(self, passage):
        item = self.NS.create(passage)
        self.assertIsNotNone(item)
        return item

    def compose(self, item):
        info, text, title = self.News.compose(item.md)
        return info, text, title

    def read(self, item):
        action = self.rt.eval('function(item) return setmetatable({ item = item }, { __index = ISReadABook }) end')(item)
        self.assertIsNone(action.startLoadingPrintMediaTextures(action))
        action.displayPrintMedia(action)
        return self.g.DISPLAYED[len(self.g.DISPLAYED)]

    def logs_with(self, text: str) -> list[str]:
        return [line for line in lua_list(self.g.LOGS) if text in line]


class CreateTests(NewsHarness):

    def test_edition_of_a_passage_holds_keys_and_numbers_only(self):
        self.g.CLOCK.y, self.g.CLOCK.m, self.g.CLOCK.d = 1993, 7, 2   # 3 août 1993 (mois et jours depuis 0)
        md = self.edition(4).md
        pm = md['printMedia']
        self.assertEqual(pm['id'], 'RadioSurvivor_OutsideNews_4')
        self.assertEqual(pm['title'], pm['id'])          # marque « lu » : addReadPrintMedia(id) = isPrintMediaRead(title)
        self.assertEqual(pm['info'], 'Print_Media_RadioSurvivor_OutsideNews_info')
        self.assertEqual(pm['text'], 'Print_Text_RadioSurvivor_OutsideNews_info')
        n = md['RadioSurvivorOutsideNews']
        self.assertEqual((n['format'], n['edition'], n['y'], n['m'], n['d']), (1, 4, 1993, 8, 3))
        self.assertTrue(1 <= n['lead'] <= 10)
        briefs = lua_list(n['briefs'])
        self.assertEqual(len(briefs), 3)
        self.assertEqual(len(set(briefs)), 3)
        for k, v in n.items():
            with self.subTest(field=k):
                if k == 'briefs':
                    continue
                self.assertIsInstance(v, (int, float))

    def test_same_passage_same_content(self):
        a = self.edition(9).md['RadioSurvivorOutsideNews']
        b = self.edition(9).md['RadioSurvivorOutsideNews']
        self.assertEqual(a['lead'], b['lead'])
        self.assertEqual(lua_list(a['briefs']), lua_list(b['briefs']))
        self.assertEqual((a['gas'], a['bread']), (b['gas'], b['bread']))

    def test_consecutive_passages_never_share_the_front_page(self):
        leads = [self.rt.eval(f'(require("RadioSurvivor/RS_OutsideNews").select({n}))') for n in range(1, 61)]
        for n in range(len(leads) - 1):
            self.assertNotEqual(leads[n], leads[n + 1], n + 1)
        self.assertEqual(sorted(leads[:10]), list(range(1, 11)))   # dix éditions, dix unes différentes

    def test_prices_climb_from_one_passage_to_the_next(self):
        prev = None
        for n in range(1, 30):
            md = self.edition(n).md['RadioSurvivorOutsideNews']
            if prev is not None:
                self.assertGreater(md['gas'], prev['gas'])
                self.assertGreaterEqual(md['bread'], prev['bread'])
            prev = {'gas': md['gas'], 'bread': md['bread']}
        last = self.edition(9999).md['RadioSurvivorOutsideNews']
        self.assertEqual((last['gas'], last['bread']), (9999, 9999))

    def test_default_edition_is_the_week_of_the_world(self):
        for hours, edition in ((0, 1), (167.9, 1), (168, 2), (24 * 7 * 5 + 3, 6)):
            with self.subTest(hours=hours):
                self.g.CLOCK.hours = hours
                self.assertEqual(self.edition(None).md['RadioSurvivorOutsideNews']['edition'], edition)

    def test_on_create_gives_a_readable_edition(self):
        self.g.CLOCK.hours = 400
        item = self.g.newItem('OutsideNews')
        self.g.RadioSurvivorOutsideNews.onCreate(item)
        self.assertEqual(item.md['RadioSurvivorOutsideNews']['edition'], 3)
        other = self.g.newItem('NoteWalt')
        self.g.RadioSurvivorOutsideNews.onCreate(other)
        self.assertIsNone(other.md)

    def test_invalid_passage_refused(self):
        for bad in (0, -1, 1.5, 10000, '"3"'):
            with self.subTest(bad=bad):
                self.assertIsNone(self.rt.eval(f'require("RadioSurvivor/RS_OutsideNewsServer").create({bad})'))
        self.assertEqual(len(self.logs_with('invalid passage number')), 5)
        self.g.INSTANCE_OK = False
        self.assertIsNone(self.NS.create(2))
        self.assertEqual(len(self.logs_with('instanceItem(RadioSurvivor.OutsideNews) returned nil')), 1)

    def test_give_puts_the_edition_in_the_inventory(self):
        item = self.g.RadioSurvivorOutsideNews.give(5)
        items = lua_list(self.g.PLAYER.inv['items'])
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].md['RadioSurvivorOutsideNews']['edition'], 5)
        self.assertEqual(item.md['printMedia']['id'], 'RadioSurvivor_OutsideNews_5')
        self.assertEqual(len(lua_list(self.g.SENT)), 0)   # solo : aucun envoi
        self.assertEqual(len(self.logs_with('edition 5 given to solo_player')), 1)


class ServerGiveTests(NewsHarness):
    side = 'server'

    def test_give_on_a_server_sends_the_item(self):
        other = self.g.newPlayer('bob')
        self.g.RadioSurvivorOutsideNews.give(2, other)
        self.assertEqual(len(lua_list(other.inv['items'])), 1)
        self.assertEqual(len(lua_list(self.g.SENT)), 1)


class ComposeTests(NewsHarness):

    def test_text_changes_from_one_passage_to_the_next(self):
        for lang in ('EN', 'FR'):
            self.set_lang(lang)
            texts = [self.compose(self.edition(n)) for n in range(1, 12)]
            with self.subTest(lang=lang):
                for a, b in zip(texts, texts[1:]):
                    self.assertNotEqual(a[0], b[0])
                    self.assertNotEqual(a[1], b[1])
                    self.assertNotEqual(a[2], b[2])
                self.assertEqual(len({t[1] for t in texts}), len(texts))

    def test_composed_in_english_and_french_without_keys_nor_placeholders(self):
        self.g.CLOCK.y, self.g.CLOCK.m, self.g.CLOCK.d = 1993, 8, 14      # 15 septembre 1993
        for lang, date, title, price in (('EN', 'September 15, 1993', 'News From Outside - No. 3', '$'),
                                         ('FR', '15 septembre 1993', 'Nouvelles du dehors - n\u00b0 3', ' $')):
            self.set_lang(lang)
            item = self.edition(3)
            info, text, shown = self.compose(item)
            n = item.md['RadioSurvivorOutsideNews']
            tr = translations(lang)
            with self.subTest(lang=lang):
                self.assertEqual(shown, title)
                for part in (date, tr[f'{K}lead{n["lead"]}_head'], tr[f'{K}lead{n["lead"]}_body'], tr[f'{K}masthead']):
                    self.assertIn(part, info)
                    self.assertIn(part, text)
                for i in lua_list(n['briefs']):
                    self.assertIn(tr[f'{K}brief{i}_body'], text)
                self.assertNotRegex(info + text + shown, r'%|Print_(Text|Media)_|RadioSurvivor_OutsideNews')
                self.assertIn(price, text)
                gas = n['gas']
                cents = f'{gas // 100}' + ('.' if lang == 'EN' else ',') + f'{gas % 100:02d}'
                self.assertIn(cents, text)
        self.assertNotEqual(translations('EN')[f'{K}lead1_body'], translations('FR')[f'{K}lead1_body'])

    def test_unknown_date_and_other_documents(self):
        item = self.edition(2)
        item.md['RadioSurvivorOutsideNews']['m'] = 13
        self.assertIn('Date smudged', self.compose(item)[1])
        other = self.rt.eval('{ printMedia = { id = "RadioSurvivor_NoteWalt", info = "x" } }')
        self.assertIsNone(self.News.compose(other))
        broken = self.edition(2)
        broken.md['RadioSurvivorOutsideNews']['lead'] = 11
        self.assertIsNone(self.News.compose(broken.md))

    def test_layout_parses_like_the_vanilla_reader(self):
        # PrintMedia.lua:68-84 : découpe sur <, >, puis , et : ; tout paramètre doit être clé:valeur.
        for lang in ('EN', 'FR'):
            self.set_lang(lang)
            for n in (1, 2, 7, 120):
                info = self.compose(self.edition(n))[0]
                with self.subTest(lang=lang, edition=n):
                    self.assertTrue(info.startswith('<type:parent, width:600, height:800>'))
                    for chunk in info.split('<')[1:]:
                        params, _, content = chunk.partition('>')
                        self.assertNotIn('>', content)
                        for param in params.split(','):
                            self.assertEqual(len(param.split(':')), 2, param)
                        self.assertNotRegex(params, r'texture:')   # rectangles seulement (rien à précharger)


class ReaderTests(NewsHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute('require("RadioSurvivor/RS_NotesReader")')

    def test_document_opened_composed_then_keys_restored(self):
        for lang in ('FR', 'EN'):
            self.set_lang(lang)
            item = self.edition(6)
            shown = self.read(item)
            info, text, title = self.compose(item)
            self.assertEqual((shown['info'], shown['text'], shown['title']), (info, text, title))
            pm = item.md['printMedia']
            self.assertEqual((pm['info'], pm['text'], pm['title']),
                             ('Print_Media_RadioSurvivor_OutsideNews_info', 'Print_Text_RadioSurvivor_OutsideNews_info',
                              'RadioSurvivor_OutsideNews_6'))
        self.assertEqual(self.g.LOADED, 0)

    def test_broken_edition_falls_back_to_the_vanilla_window(self):
        item = self.edition(6)
        item.md['RadioSurvivorOutsideNews'] = None
        shown = self.read(item)
        self.assertEqual(shown['info'], translations('EN')['Print_Media_RadioSurvivor_OutsideNews_info'])

    def test_frequency_notes_still_composed(self):
        self.rt.execute('Notes = require("RadioSurvivor/RS_Notes")')
        item = self.g.newItem('NoteGus')
        self.g.RadioSurvivorNotes.onCreate(item)
        shown = self.read(item)
        self.assertIn('???.? MHz', shown['info'])
        self.assertEqual(shown['title'], translations('EN')['Print_Media_RadioSurvivor_NoteGus_title'])
        self.assertEqual(item.md['printMedia']['title'], 'Print_Media_RadioSurvivor_NoteGus_title')


class ClientTests(NewsHarness):
    side = 'client'

    def test_server_file_not_loaded_on_an_mp_client(self):
        self.assertIsNone(self.g.RadioSurvivorOutsideNews.give)
        item = self.g.newItem('OutsideNews')
        self.g.RadioSurvivorOutsideNews.onCreate(item)   # rejoué à la réception, remplacé par la ModData du serveur
        self.assertEqual(item.md['RadioSurvivorOutsideNews']['edition'], 1)

    def test_no_network_command_in_the_news_modules(self):
        for path in NEWS_LUA[:2]:
            code = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
            with self.subTest(path.name):
                self.assertIsNone(re.search(r'send(Server|Client)Command|ModData\.(add|transmit|request)', code))


class TradeTests(unittest.TestCase):

    def test_sold_by_the_smuggler_never_bought_back(self):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        tv = rt.execute((LUA / 'shared/RadioSurvivor/RS_TradeValues.lua').read_text(encoding='utf-8'))
        self.assertEqual(tv.value('RadioSurvivor.OutsideNews')[0], 0)
        self.assertFalse(tv.isBase('RadioSurvivor.OutsideNews'))
        self.assertIsNone(tv.entry('RadioSurvivor.OutsideNews'))
        self.assertEqual(tv.sellValue('RadioSurvivor.OutsideNews'), 2)
        self.assertEqual(tv.sellValue('Base.Battery'), 2)
        self.assertEqual(tv.sellValue('RadioSurvivor.NoteWalt'), 0)
        self.assertEqual(tv.SELL_ONLY['RadioSurvivor.OutsideNews'].cap, 1)
        doc = (ROOT / 'docs/passeur-table.md').read_text(encoding='utf-8')
        self.assertRegex(doc, r'\| Journal du dehors \(`RadioSurvivor\.OutsideNews`[^|]*\| [^|]+\| 2 \| 1 ')


def font_metrics(name: str) -> tuple[dict[int, int], int]:
    advance, line = {}, 0
    for row in (FONTS / f'{name}.fnt').read_text(encoding='utf-8', errors='replace').splitlines():
        if row.startswith('char '):
            f = dict(re.findall(r'(\w+)=(-?\d+)', row))
            advance[int(f['id'])] = int(f['xadvance'])
            line = max(line, int(f['height']) + int(f['yoffset']))   # AngelCodeFont.java:357
    return advance, line


def wrap_lines(text: str, advance: dict[int, int], auto_width: int | None) -> tuple[int, float]:
    """Nombre de lignes et largeur max (unités de police) d'après AtomUIText.updateInternalValues, sans crénage."""
    if auto_width is None:
        return 1, sum(advance.get(ord(c), 0) for c in text)
    lines, x, last_space, diff_x, widest = 1, 0.0, -1, 0.0, 0.0
    for i, c in enumerate(text):
        if c == ' ':
            last_space, diff_x = i, x
        if x >= auto_width and last_space != -1:
            widest = max(widest, diff_x)
            lines += 1
            last_space = -1
            x -= diff_x
        x += advance.get(ord(c), 0)
    return lines, max(widest, x)


@unittest.skipUnless(FONTS.is_dir(), 'vanilla fonts missing')
class PageFitTests(NewsHarness):
    """Chaque bloc de texte tient dans la page et ne déborde pas sur le suivant, dans les deux langues."""

    def blocks(self, n_lead: int, briefs: list[int], lang: str):
        tr = translations(lang)
        layout = self.News.LAYOUT
        date = tr[f'{K}date'].replace('%1', '28').replace('%2', max((tr[f'{K}month{m}'] for m in range(1, 13)),
                                                                     key=len)).replace('%3', '1993')
        price = tr[f'{K}price'].replace('%1', '99').replace('%2', '99')
        yield 'masthead', layout.masthead, tr[f'{K}masthead']
        yield 'subline', layout.subline, tr[f'{K}subline'].replace('%1', '9999')
        yield 'date', layout.date, date
        yield 'leadHead', layout.leadHead, tr[f'{K}lead{n_lead}_head']
        yield 'leadBody', layout.leadBody, tr[f'{K}lead{n_lead}_body']
        for i in briefs:
            yield f'briefHead{i}', layout.briefHead, tr[f'{K}brief{i}_head']
            yield f'briefBody{i}', layout.briefBody, tr[f'{K}brief{i}_body']
        yield 'prices', layout.prices, tr[f'{K}prices'].replace('%1', price).replace('%2', price)

    def test_every_template_fits(self):
        metrics = {name: font_metrics(name) for name in ('SdfOldBold', 'SdfOldRegular')}
        L = self.News.LAYOUT
        for lang in ('EN', 'FR'):
            for lead in range(1, 11):
                for name, b, text in self.blocks(lead, list(range(1, 13)), lang):
                    advance, line = metrics[b.font]
                    with self.subTest(lang=lang, block=name):
                        missing = sorted({c for c in text if ord(c) not in advance})
                        self.assertEqual(missing, [], 'glyphs missing from ' + b.font)
                        lines, width = wrap_lines(text, advance, b.autoWidth)
                        width_px = width * b.scale
                        left = b.x - width_px * (b.pivotX or 0)
                        self.assertGreaterEqual(left, 20)
                        self.assertLessEqual(left + width_px, 580)
                        bottom = b.y + lines * line * b.scale
                        limit = b.bottom
                        if name.startswith('briefHead'):
                            limit = L.briefBody.y      # le titre d'une brève tient sur une ligne
                        self.assertLessEqual(bottom, limit, f'{lines} lines')
        # La dernière brève reste au-dessus du filet des prix.
        self.assertLessEqual(L.briefBody.bottom + 2 * L.briefBody.step, 720)


class StaticTests(unittest.TestCase):

    def test_item_script(self):
        text = SCRIPT.read_text(encoding='utf-8')
        self.assertTrue(text.lstrip().startswith('module RadioSurvivor'))
        items = re.findall(r'item (\w+)\s*\{([^}]*)\}', text)
        self.assertEqual([name for name, _ in items], ['OutsideNews'])
        body = items[0][1]
        self.assertIn('OnCreate = RadioSurvivorOutsideNews.onCreate,', body)
        self.assertIn('ItemType = base:literature,', body)
        self.assertIn('DisplayCategory = Literature,', body)
        self.assertIn('base:fastread', body)
        self.assertNotRegex(body, r'CanBeWrite|PageToWrite|base:newspaper')

    def test_vanilla_icon_and_models(self):
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
        keys = ['RadioSurvivor.OutsideNews', 'Print_Media_RadioSurvivor_OutsideNews_title',
                'Print_Media_RadioSurvivor_OutsideNews_info', 'Print_Text_RadioSurvivor_OutsideNews_info']
        keys += [K + k for k in ('masthead', 'subline', 'date', 'undated', 'price', 'prices')]
        keys += [f'{K}lead{i}_{p}' for i in range(1, 11) for p in ('head', 'body')]
        keys += [f'{K}brief{i}_{p}' for i in range(1, 13) for p in ('head', 'body')]
        keys += [f'{K}month{i}' for i in range(1, 13)]
        news_keys = sorted(k for k in en if 'OutsideNews' in k)
        self.assertEqual(news_keys, sorted(keys))
        self.assertEqual(sorted(k for k in fr if 'OutsideNews' in k), sorted(keys))
        for key in keys:
            with self.subTest(key):
                self.assertEqual(sorted(re.findall(r'%\d', en[key])), sorted(re.findall(r'%\d', fr[key])))
                self.assertNotRegex(en[key] + fr[key], r'%[^1-3]|%$')
                if key.startswith(K) and key != K + 'info':
                    self.assertNotRegex(en[key] + fr[key], r'[<>^]')

    def test_no_secret_and_no_frequency(self):
        bundled = MOD / 'personas'
        blobs = {lang: ' '.join(v for k, v in translations(lang).items() if 'OutsideNews' in k).lower()
                 for lang in ('EN', 'FR')}
        for lang, blob in blobs.items():
            with self.subTest(lang):
                self.assertNotRegex(blob, r'mhz|khz|\d{2,}[.,]\d|fr[eé]quence|frequency')
                for word in ('walt', 'darlene', 'cody', 'gus', 'night owl', 'whitaker', 'lacombe', 'ponton', 'pontoon',
                             'landing', 'brandenburg', 'riverside', 'rescue', 'secours', 'helicopter', 'hélicoptère'):
                    self.assertNotRegex(blob, rf'{word}')
        everything = blobs['EN'] + ' ' + blobs['FR']
        for path in bundled.glob('*.txt'):
            for line in path.read_text(encoding='utf-8').splitlines():
                if line.startswith('secret='):
                    self.assertNotIn(line[7:].lower()[:30], everything)

    def test_lua_ascii_only_outside_comments(self):
        for path in NEWS_LUA:
            for no, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                with self.subTest(file=path.name, line=no):
                    self.assertTrue(code.isascii(), line)


if __name__ == '__main__':
    unittest.main(verbosity=1)
