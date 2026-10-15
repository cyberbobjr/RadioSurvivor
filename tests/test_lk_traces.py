"""Tests hors jeu des traces lisibles des groupes Living Knox (LK10-T04) : server/LivingKnox/LK_Traces.lua (carnet du
foyer d'un groupe disparu, notes sur le chef mort) et la suite en jeu lk.traces (dev/.../RST_LKTraces.lua).

    python RadioSurvivor/tests/test_lk_traces.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec le vrai registre des groupes, le vrai journal de
récit, les vraies histoires et l'aménagement des foyers (doublures de tests/test_lk_homes.py), complétés des doublures
ci-dessous, relevées dans le Java et le Lua vanilla 42.21.0, qui NE PROUVENT PAS l'API réelle :
- Literature (J/inventory/types/Literature.java:446-482) : addPage(index, texte) (coupé à 16 384), seePage,
  isEmptyPages (vrai si toutes les pages sont vides), setLockedBy / getLockedBy ; scripts Base.Notebook et
  Base.SheetPaper2 (literature.txt : CanBeWrite) ;
- ItemContainer : AddItem, DoRemoveItem, getItems ; ItemContainer.new() ; sendAddItemToContainer et
  sendRemoveItemFromContainer comptés (serveur seulement) ; IsoGridSquare.AddWorldInventoryItem (objet du monde
  transmis), getWorldObjects, transmitRemoveItemFromSquare ;
- traductions : getTextOrNull / getText lus dans les fichiers EN ou FR du mod, %N remplacés ; sur un serveur MP elles
  sont absentes jusqu'à Translator.loadFiles() (base api-42-21.md) ; Translator.getLanguage():name().
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_homes import DOUBLES, HOUSE, SHARED, DEV_LUA  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
TRANSLATE = LUA / 'shared' / 'Translate'
MODULE = 'server/LivingKnox/LK_Traces.lua'
SUITE = 'shared/RST/suites/RST_LKTraces.lua'
SUITE_FILE = DEV_LUA / SUITE
SERVER = ('server/LivingKnox/LK_Server.lua', 'server/LivingKnox/LK_Journal.lua', 'server/LivingKnox/LK_Stories.lua',
          'server/LivingKnox/LK_Homes.lua', MODULE)
T, G = 'LivingKnox.Traces', 'LivingKnox.Groups'


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def lua_str(s: str) -> str:
    """Littéral Lua ASCII : caractères non ASCII en échappements décimaux de leurs octets UTF-8."""
    return '"' + ''.join(c if (32 <= ord(c) < 127 and c not in '"\\') else ''.join('\\%d' % b for b in c.encode('utf-8'))
                         for c in s) + '"'


def text_table(lang: str) -> str:
    table = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
    rows = ',\n'.join(f'[{lua_str(k)}] = {lua_str(v)}' for k, v in table.items() if k.startswith('IGUI_LK_'))
    return '{\n' + rows + '\n}'


ITEM_DOUBLES = r'''
local H = HARNESS
local C = H.classes
COUNT.sent, COUNT.unsent, COUNT.reload = 0, 0, 0

-- Objets d'inventaire : documents Literature (Literature.java:446-482).
local Item = C.InventoryItem
function Item:hasModData() return rawget(self, 'md') ~= nil end
function Item:getFullType() return self.type end
function Item:getWorldItem() return rawget(self, 'world') end
local Lit = H.class('Literature', Item)
function Lit:addPage(i, text)
    if type(i) ~= 'number' or type(text) ~= 'string' then error('No implementation found for addPage', 2) end
    if #text > 16384 then text = string.sub(text, 1, 16384) end
    self.pages[i] = text
end
function Lit:seePage(i) return self.pages[i] end
function Lit:isEmptyPages()
    for _, p in pairs(self.pages) do if p ~= '' then return false end end
    return true
end
function Lit:setLockedBy(n) self.lockedBy = n end
function Lit:getLockedBy() return self.lockedBy end
function Lit:pageCount() local n = 0 for _ in pairs(self.pages) do n = n + 1 end return n end
local WRITABLE = { ['Base.Notebook'] = true, ['Base.SheetPaper2'] = true }
instanceItem = function(t)
    if WRITABLE[t] then return setmetatable({ type = t, pages = {} }, Lit) end
    return nil
end

-- Conteneurs (ItemContainer) : les conteneurs des objets posés deviennent des conteneurs à objets.
local Cont = H.class('ItemContainer')
function Cont:getItems() return self.items end
function Cont:getType() return self.type end
function Cont:AddItem(it) self.items:add(it) it.container = self return it end
function Cont:DoRemoveItem(it) H.listRemove(self.items, it) it.container = nil end
ItemContainer = { new = function() return setmetatable({ type = 'none', items = H.list() }, Cont) end }
function C.IsoObject:getContainer()
    local c = rawget(self, 'container')
    if c == nil then return nil end
    if getmetatable(c) ~= Cont then
        setmetatable(c, Cont)
        c.items = c.items or H.list()
    end
    return c
end
function CONTAINER(x, y, kind)
    local o = setmetatable({ container = { type = kind or 'counter' } }, C.IsoObject)
    H.addObject(x, y, 0, o)
    return o:getContainer()
end
sendAddItemToContainer = function(c, it)
    if not isServer() then error('sendAddItemToContainer called off the server', 2) end
    COUNT.sent = COUNT.sent + 1
end
sendRemoveItemFromContainer = function(c, it)
    if not isServer() then error('sendRemoveItemFromContainer called off the server', 2) end
    COUNT.unsent = COUNT.unsent + 1
end

-- Sol : objets du monde (IsoGridSquare.java:5159-5178, transmis par défaut).
local WorldItem = H.class('IsoWorldInventoryObject', C.IsoObject)
function WorldItem:getItem() return self.item end
local Sq = C.IsoGridSquare
function Sq:AddWorldInventoryItem(it, x, y, h)
    local w = setmetatable({ item = it, square = self }, WorldItem)
    it.world = w
    local list = rawget(self, 'worldObjects') or H.list()
    self.worldObjects = list
    list:add(w)
    if isServer() then COUNT.transmit = COUNT.transmit + 1 end
    return it
end
local rawRemove = Sq.transmitRemoveItemFromSquare
function Sq:transmitRemoveItemFromSquare(o)
    if getmetatable(o) == WorldItem then
        H.listRemove(self.worldObjects, o)
        return 0
    end
    return rawRemove(self, o)
end

-- Documents du groupe partout sur la carte du banc (conteneurs des objets, sol, inventaires donnés).
function DOCS(gid)
    local out = {}
    for y = 60, 260 do
        for x = 60, 260 do
            local sq = getCell():getGridSquare(x, y, 0)
            if sq then
                for _, o in ipairs(sq.objects.items) do
                    local c = rawget(o, 'container')
                    if c and c.items then
                        for _, it in ipairs(c.items.items) do
                            if it:hasModData() and it:getModData().LKTrace == gid then out[#out + 1] = it end
                        end
                    end
                end
                local w = rawget(sq, 'worldObjects')
                if w then
                    for _, wo in ipairs(w.items) do
                        local it = wo.item
                        if it and it:hasModData() and it:getModData().LKTrace == gid then out[#out + 1] = it end
                    end
                end
            end
        end
    end
    return out
end
'''


def text_doubles(lang: str, loaded: bool) -> str:
    """getTextOrNull / getText (clés du mod) et Translator ; loaded = faux : clés du mod absentes jusqu'à loadFiles."""
    return (f'local TABLE = {text_table(lang)}\nLANG = {lua_str(lang)}\n' + r'''
local KEYS = ''' + ('TABLE' if loaded else '{}') + r'''
local function fmt(text, ...)
    local args = { ... }
    return (string.gsub(text, '%%(%d)', function(d) return tostring(args[tonumber(d)] or '') end))
end
getTextOrNull = function(key, ...) local t = KEYS[key] if t == nil then return nil end return fmt(t, ...) end
getText = function(key, ...) local t = KEYS[key] if t == nil then return key end return fmt(t, ...) end
Translator = {
    getLanguage = function() return { name = function() return LANG end } end,
    loadFiles = function() COUNT.reload = COUNT.reload + 1 KEYS = TABLE end,
}
''')


class Base(unittest.TestCase):
    mode = 'solo'
    lang = 'EN'
    loaded = True

    def setUp(self):
        self.h = Harness(mode=self.mode, lua_roots=[DEV_LUA])
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, DOUBLES)
            self.h.load(m, ITEM_DOUBLES)
            self.h.load(m, text_doubles(self.lang, self.loaded or m != self.srv))
            for path in SHARED:
                self.h.load(m, path)
            for path in SERVER:
                self.h.load(m, path)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.run_lua(HOUSE)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval(self.srv, code)

    def run_lua(self, code):
        return self.h.load(self.srv, code)

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]

    def group(self, home=(103, 104, 0), members=3, name='Mill Folk', seed=4242, furnish=True):
        roles = ['worker', 'fighter', 'medic', 'scout']
        code = (f'local G = {G} local g = assert(G.create({{ type = "settlers", name = "{name}", day = 1, '
                f'storySeed = {seed}, home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }})) local first ')
        for i in range(members):
            code += f'local m{i} = assert(G.addMember(g.id, {{ role = "{roles[i]}", day = 1 }})) first = first or m{i} '
        code += 'assert(G.setLeader(g.id, first, 1)) '
        if furnish:
            code += 'assert(type(LivingKnox.Homes.check(g.id, { force = true })) == "table") '
        else:
            code += 'LivingKnox.Homes.skip(g.id) '
        return self.run_lua(code + 'return g.id, first')

    def gone(self, gid, cause='wiped'):
        self.run_lua(f'''
            local G = {G}
            for mid, m in pairs(G.get("{gid}").members) do
                if m.alive then assert(G.markDead("{gid}", mid, 2)) end
            end
            assert(G.update(function(d) G.applyGone(d.groups["{gid}"], "{cause}", 2, 30, 30) return true, true end))
        ''')

    def docs(self, gid):
        return lua_list(self.ev(f'DOCS("{gid}")'))

    def pages(self, doc):
        return [doc.pages[i] for i in sorted(doc.pages.keys())]

    def check(self, gid):
        return self.ev(f'({T}.checkHome("{gid}", {{ force = true }}))')

    def restart(self):
        self.run_lua(f'{T}.reset() LivingKnox.Homes.reset() {G}.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)


class LayoutTests(Base):
    def test_wrap_respects_the_width_and_paragraphs(self):
        lines = lua_list(self.ev(f'{T}.wrap("one two three four five six seven\\n\\nlast", 10)'))
        self.assertEqual(lines, ['one two', 'three four', 'five six', 'seven', '', 'last'])
        self.assertTrue(all(len(x) <= 10 for x in lines))

    def test_layout_keeps_entries_whole_and_drops_the_oldest(self):
        entries = ', '.join(f'"entry {i:02d} ' + 'word ' * 12 + '"' for i in range(1, 41))
        pages, omitted = self.run_lua(f'local p, o = {T}.layout({{ "Title" }}, {{ {entries} }}, 3) return p, o')
        pages = lua_list(pages)
        self.assertEqual(len(pages), 3)
        self.assertGreater(omitted, 0)
        for p in pages:
            self.assertLessEqual(len(p.split('\n')), 15)
            self.assertLessEqual(len(p), 1200)
            self.assertTrue(all(len(x) <= 40 for x in p.split('\n')))
        text = '\n'.join(pages)
        self.assertIn('entry 40', text)          # la plus récente gardée
        self.assertNotIn('entry 01', text)       # les plus anciennes omises
        # Aucune entrée coupée entre deux pages.
        for p in pages[1:]:
            self.assertTrue(p.startswith('entry '), p[:20])


class HomeTests(Base):
    def test_living_group_gets_nothing(self):
        gid, _ = self.group()
        self.assertIsNone(self.check(gid))
        self.h.advance(3)
        self.assertEqual(self.docs(gid), [])

    def test_notebook_left_once_in_the_furnished_crate(self):
        gid, _ = self.group()
        self.gone(gid)
        self.h.advance_ms(20000)
        self.assertEqual(self.ev(f'{T}.scan("minute")'), 1)
        mark = self.ev(f'{G}.get("{gid}").traces.home')
        self.assertEqual((mark.state, mark.where, mark.hx, mark.hy, mark.hz), ('done', 'container', 103, 104, 0))
        docs = self.docs(gid)
        self.assertEqual(len(docs), 1)
        doc = docs[0]
        self.assertEqual(doc.type, 'Base.Notebook')
        self.assertEqual(doc.lockedBy, 'Living Knox')
        self.assertFalse(doc.isEmptyPages(doc))
        self.assertEqual(doc.md.LKTraceKind, 'home')
        # Rangé dans la caisse de l'aménagement (ModData LKHome du groupe).
        self.assertEqual(doc.container.type, 'crate')
        text = '\n'.join(self.pages(doc))
        self.assertTrue(text.startswith('Journal: Mill Folk'), text[:60])
        story = self.ev(f'LivingKnox.Stories.compose("settlers", 4242)')
        self.assertIn(story.summary.en.split(' ')[0], text)
        for line in ('No one is left: the group is gone.', 'Death of a member (worker).',
                     'The group has a new leader (worker).'):
            self.assertIn(line, text.replace('\n', ' '))
        self.assertRegex(text, r'Day 2, \d\d:00 - ')
        # Nouveaux passages, chargements et minutes : rien de plus.
        for _ in range(3):
            self.h.advance_ms(20000)
            self.ev(f'{T}.scan("chunk")')
            self.h.advance(2)
        self.assertEqual(len(self.docs(gid)), 1)
        self.assertEqual(self.check(gid), 'done')

    def test_no_secret_and_no_coordinates_in_the_notebook(self):
        gid, _ = self.group()
        self.gone(gid)
        self.check(gid)
        text = '\n'.join(self.pages(self.docs(gid)[0]))
        story = self.ev('LivingKnox.Stories.compose("settlers", 4242)')
        for s in lua_list(story.secrets):
            self.assertNotIn(s.en, text)
        self.assertNotIn('103', text)
        self.assertNotIn('grp-', text)
        self.assertNotIn('m-1', text)

    def test_restart_and_lost_mark_never_leave_a_second_notebook(self):
        gid, _ = self.group()
        self.gone(gid)
        self.check(gid)
        self.restart()
        self.assertEqual(self.check(gid), 'done')
        self.run_lua(f'assert({G}.update(function(d) d.groups["{gid}"].traces = nil return true, true end))')
        self.run_lua(f'{T}.reset()')
        restored = self.check(gid)
        self.assertEqual((restored.state, restored.where), ('done', 'found'))
        self.assertEqual(len(self.docs(gid)), 1)
        self.assertTrue(any('already has its journal but no mark' in line for line in self.lk()))

    def test_interrupted_deposit_is_never_redone(self):
        gid, _ = self.group()
        self.gone(gid)
        self.run_lua(f'assert({G}.update(function(d) d.groups["{gid}"].traces = {{ v = 1, home = {{ hx = 103, '
                     f'hy = 104, hz = 0, day = 2, state = "placing" }} }} return true, true end))')
        self.assertEqual(self.check(gid), 'done')
        self.assertEqual(self.docs(gid), [])
        self.assertTrue(any('was interrupted' in line for line in self.lk()))

    def test_malformed_mark_is_reset(self):
        gid, _ = self.group()
        self.gone(gid)
        self.run_lua(f'assert({G}.update(function(d) d.groups["{gid}"].traces = {{ v = 9 }} return true, true end))')
        self.assertEqual(self.check(gid).where, 'container')
        self.assertTrue(self.ev(f'{T}.valid({G}.get("{gid}").traces)'))

    def test_nearest_container_then_floor(self):
        gid, _ = self.group(furnish=False)
        far = self.run_lua('return CONTAINER(108, 106, "fridge")')
        near = self.run_lua('return CONTAINER(104, 105, "counter")')
        self.run_lua('CONTAINER(120, 104, "outside")')   # hors du bâtiment : jamais choisi
        self.gone(gid)
        self.assertEqual(self.check(gid).where, 'container')
        doc = self.docs(gid)[0]
        self.assertEqual(doc.container.type, 'counter')
        self.assertEqual(len(lua_list(far['items']['items'])), 0)
        self.assertEqual(len(lua_list(near['items']['items'])), 1)
        # Camp sans conteneur : au sol sur la case du foyer.
        gid2, _ = self.group(home=(150, 150, 0), furnish=False, name='Camp')
        self.gone(gid2, 'dispersed')
        self.assertEqual(self.check(gid2).where, 'floor')
        doc2 = self.docs(gid2)[0]
        self.assertEqual((doc2.world.square.x, doc2.world.square.y), (150, 150))
        self.assertIn('The last survivors scattered.', '\n'.join(self.pages(doc2)).replace('\n', ' '))

    def test_home_not_loaded_waits(self):
        gid, _ = self.group(home=(150, 150, 0), furnish=False)
        self.gone(gid)
        self.run_lua('UNLOADED_X = 155')
        self.assertIsNone(self.check(gid))
        self.assertIsNone(self.ev(f'{G}.get("{gid}").traces'))
        self.run_lua('UNLOADED_X = nil')
        self.assertEqual(self.check(gid).where, 'floor')

    def test_clear_removes_the_documents_and_the_mark(self):
        gid, _ = self.group()
        self.gone(gid)
        self.check(gid)
        self.assertEqual(self.ev(f'{T}.clear("{gid}")'), 1)
        self.assertEqual(self.docs(gid), [])
        self.assertIsNone(self.ev(f'{G}.get("{gid}").traces'))


class ChiefTests(Base):
    def body(self, name='b1'):
        """Corps de chef simulé (ModData et inventaire), gardé dans BODIES[name] côté Lua."""
        return self.run_lua(f'BODIES = BODIES or {{}} local inv = ItemContainer.new() local b = {{ md = {{}} }} '
                            f'function b:getModData() return self.md end function b:getInventory() return inv end '
                            f'BODIES["{name}"] = b return b, inv')

    def died(self, gid, mid, name='b1', offscreen=False):
        self.run_lua(f'LivingKnox.publish("memberDied", {{ group = "{gid}", member = "{mid}", day = 2, '
                     f'offscreen = {str(offscreen).lower()}, body = BODIES["{name}"] }})')

    def notes(self, inv):
        return [it for it in lua_list(inv['items']['items']) if it.md and it.md.LKTrace]

    def test_leader_body_gets_one_note(self):
        gid, leader = self.group()
        body, inv = self.body()
        self.died(gid, leader)
        notes = self.notes(inv)
        self.assertEqual(len(notes), 1)
        note = notes[0]
        self.assertEqual((note.type, note.lockedBy, note.md.LKTraceKind), ('Base.SheetPaper2', 'Living Knox', 'chief'))
        pages = self.pages(note)
        self.assertEqual(len(pages), 1)
        self.assertTrue(pages[0].startswith('Notes: Mill Folk'), pages[0][:40])
        story = self.ev('LivingKnox.Stories.compose("settlers", 4242)')
        self.assertIn(story.motivation.en.split(' ')[0], pages[0])
        self.assertLessEqual(len(pages[0].split('\n')), 15)
        self.assertEqual(body.md.LKTraceChief, True)
        self.assertEqual(lua_list(self.ev(f'{G}.get("{gid}").traces.chiefs')), [leader])
        # Même corps, nouveau corps après un redémarrage : jamais une seconde note.
        self.died(gid, leader)
        self.restart()
        _, inv2 = self.body('b2')
        self.died(gid, leader, 'b2')
        self.assertEqual(len(self.notes(inv)), 1)
        self.assertEqual(self.notes(inv2), [])

    def test_other_members_and_offscreen_deaths_get_nothing(self):
        gid, leader = self.group()
        members = [k for k in self.ev(f'{G}.get("{gid}").members').keys() if k != leader]
        _, inv = self.body()
        self.died(gid, members[0])
        self.died(gid, leader, offscreen=True)
        self.assertEqual(self.notes(inv), [])

    def test_real_death_order_puts_the_note_in_the_body_before_the_registry_death(self):
        """LK_Bodies publie memberDied (corps présent) avant Materialize.onBodyDied (mort au registre) : le chef est
        encore chef quand la note est composée (ordre vérifié dans le source)."""
        src = (LUA / 'server/LivingKnox/LK_Bodies.lua').read_text(encoding='utf-8')
        start = src.index('function Bodies.onZombieDead')
        body = src[start:]
        self.assertLess(body.index('LivingKnox.publish("memberDied"'), body.index('M.onBodyDied'))
        self.assertIn('body = z', body[body.index('LivingKnox.publish("memberDied"'):][:200])


class FrenchTests(Base):
    lang = 'FR'

    def test_documents_follow_the_authority_language(self):
        gid, leader = self.group()
        _, inv = ChiefTests.body(self)
        ChiefTests.died(self, gid, leader)
        self.gone(gid)
        self.check(gid)
        text = '\n'.join(self.pages(self.docs(gid)[0]))
        self.assertTrue(text.startswith('Carnet : Mill Folk'), text[:40])
        story = self.ev('LivingKnox.Stories.compose("settlers", 4242)')
        self.assertIn(story.summary.fr.split(' ')[0], text)
        self.assertIn('Plus personne', text)
        self.assertRegex(text, r'Jour 2, \d\d h - ')
        note = [it for it in lua_list(inv['items']['items'])][0]
        self.assertTrue(note.pages[1].startswith('Notes : Mill Folk'))


class MultiplayerTests(Base):
    mode = 'mp'
    loaded = False

    def test_server_reloads_translations_once_and_sends_the_notebook(self):
        gid, _ = self.group()
        self.gone(gid)
        self.assertEqual(self.check(gid).where, 'container')
        self.assertEqual(self.ev('COUNT.reload'), 1)
        self.assertEqual(self.ev('COUNT.sent'), 1)
        self.assertTrue(self.ev(f'DOCS("{gid}")[1].pages[1]').startswith('Journal: Mill Folk'))
        gid2, _ = self.group(home=(150, 150, 0), furnish=False, name='Camp')
        self.gone(gid2)
        self.check(gid2)
        self.assertEqual(self.ev('COUNT.reload'), 1)
        self.ev(f'{T}.clear("{gid}")')
        self.assertEqual(self.ev('COUNT.unsent'), 1)
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, T))

    def test_no_translations_at_all_writes_nothing(self):
        self.run_lua('Translator.loadFiles = function() COUNT.reload = COUNT.reload + 1 end')
        gid, _ = self.group()
        self.gone(gid)
        self.assertIsNone(self.check(gid))
        self.assertIsNone(self.ev(f'{G}.get("{gid}").traces'))
        self.assertEqual(self.docs(gid), [])
        self.assertTrue(any('no translation' in line for line in self.lk()))


class SuiteTests(Base):
    """La suite en jeu lk.traces passe dans le banc (joueur debout dans la maison de test)."""

    def run_suite(self):
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, SUITE)
        self.run_lua('local p = setmetatable({ x = 103, y = 104, z = 0 }, HARNESS.classes.IsoPlayer) '
                     'p.square = getCell():getGridSquare(103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.traces", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        self.run_lua('CONTAINER(104, 105, "counter")')
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 2)
        self.assertEqual(len(list(self.ev(f'{G}.list()').values())), 0)
        self.assertEqual(self.docs('grp-1'), [])

    def test_suite_detects_a_duplicate(self):
        # Garde retirée : la marque perdue fait déposer un second carnet, la suite doit échouer.
        self.run_lua(f'{T}.findDocuments = function() return {{}} end')
        _, results = self.run_suite()
        self.assertEqual(results['home notebook left once when the group is gone'][0], 'FAIL')


class SourceTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_mod_source_is_kahlua_safe(self):
        raw = (LUA / MODULE).read_bytes()
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
        self.assertTrue(all(ord(ch) < 128 for ch in code))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'[^=~<>]=[^=]*\s(&|\||<<|>>)\s'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_translations_exist_in_english_and_french(self):
        keys = set(re.findall(r'"(IGUI_LK_Traces_\w+)"', (LUA / MODULE).read_text(encoding='utf-8')))
        keys |= {'IGUI_LK_Traces_' + k for k in re.findall(r'Traces\.KEY \.\. "(\w+)"',
                                                             (LUA / MODULE).read_text(encoding='utf-8'))}
        self.assertGreaterEqual(len(keys), 5)
        for lang in ('EN', 'FR'):
            table = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for k in keys:
                self.assertIn(k, table, (lang, k))

    def test_document_items_are_writable_vanilla_items(self):
        scripts = pz_paths.media_dir() / 'scripts/generated/items/literature.txt'
        if not scripts.exists():
            self.skipTest('vanilla scripts not installed')
        text = scripts.read_text(encoding='utf-8', errors='replace')
        for name, pages in (('Notebook', 10), ('SheetPaper2', 1)):
            m = re.search(r'(?ms)^\s*item ' + name + r'\s*\{(.*?)\}', text)
            self.assertIsNotNone(m, name)
            self.assertRegex(m.group(1), r'CanBeWrite\s*=\s*true')
            self.assertRegex(m.group(1), r'PageToWrite\s*=\s*%d\b' % pages)


if __name__ == '__main__':
    unittest.main()
