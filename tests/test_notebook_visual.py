"""Protocole visuel du carnet (E03-T02) : suite en jeu `rs.notebook.visual` exécutée hors du jeu.

    python tests/test_notebook_visual.py

Banc lupa (Lua 5.1, `next` retiré comme dans Kahlua) : vrai client du carnet (`RS_Client.lua`, `RS_Notebook.lua`) sur le
serveur simulé de `tests/test_carnet.py`, doublures ISUI de `NOTEBOOK_UI` complétées (fenêtre repliable avec ses boutons
de titre, dialogue vanilla dimensionné par son texte et gardé à l'écran, texte riche avec couleurs par ligne, défilement
borné), largeurs de texte RÉELLES lues dans les polices du jeu (`media/fonts/EN/1x/zomboid{Small,Medium,Large}.fnt` :
`xadvance`, crénage et dernière lettre comptée par sa largeur comme `AngelCodeFont.getWidth`), tables EN et FR réelles
du mod. Le vrai moteur RST (`RST.lua`) joue les trois tests de la suite avec une horloge simulée et une image ISUI par
pas (mise à jour Java, prerender, enfants, render).
Ne prouve ni l'API Java du jeu, ni le rendu, ni le changement réel de résolution : la suite en jeu et les captures
restent nécessaires. SKIP si les polices du jeu sont absentes.
"""
from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

from test_carnet import Simulation, NOTEBOOK_UI, ROOT

FONTS = pz_paths.media_dir() / 'fonts/EN/1x'
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_NotebookVisual.lua'
MOD = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21'
TABLES = {lang: MOD / 'media' / 'lua' / 'shared' / 'Translate' / lang / 'IG_UI.json' for lang in ('EN', 'FR')}


class Font:
    """Police BMFont texte : largeur comme AngelCodeFont.getWidth (42.21), hauteur de ligne."""

    def __init__(self, path: Path):
        self.chars, self.kerning, self.line_height = {}, {}, 0
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            fields = dict(re.findall(r'(\w+)=(-?\d+)', line))
            if line.startswith('common '):
                self.line_height = int(fields['lineHeight'])
            elif line.startswith('char '):
                self.chars[int(fields['id'])] = (int(fields['xadvance']), int(fields['width']))
            elif line.startswith('kerning '):
                self.kerning[(int(fields['first']), int(fields['second']))] = int(fields['amount'])

    def width(self, text: str) -> int:
        widest = width = 0
        last = None
        units = text.encode('utf-16-le')
        ids = [int.from_bytes(units[i:i + 2], 'little') for i in range(0, len(units), 2)]
        for i, cid in enumerate(ids):
            if cid == 10:
                width = 0
                continue
            if cid not in self.chars:
                continue
            if last is not None:
                width += self.kerning.get((last, cid), 0)
            last = cid
            advance, glyph = self.chars[cid]
            width += advance if i < len(ids) - 1 else glyph
            widest = max(widest, width)
        return widest


EXTRA_UI = r'''
-- Real font metrics (Python), fonts of size 1x.
TM = {}
-- Bytes passed as numbers: a string cut inside a UTF-8 sequence (lupa strings are bytes) stays measurable.
function TM:MeasureStringX(font, text) return PY_WIDTH(font or 'Small', string.byte(tostring(text or ''), 1, -1)) end
function TM:MeasureStringY(font) return PY_HEIGHT(font or 'Small') end
function TM:getFontHeight(font) return PY_HEIGHT(font or 'Small') end
function TM:getFontFromEnum(font) local h = PY_HEIGHT(font or 'Small'); return {getLineHeight = function() return h end} end
getTextManager = function() return TM end

-- Display: borderless windowed takes the monitor size (Core.setDisplayModeInternal, 42.21).
MONITOR = {w = 2560, h = 1440}
SCREEN = {w = 2560, h = 1440, full = false, borderless = true}
SCREEN_MODES = {'1024 x 768', '1280 x 720', '1600 x 900', '1920 x 1080', '2560 x 1440'}
DISPLAY_CALLS, SHOTS, MOUSE = {}, {}, {x = 300, y = 200}
CORE = {}
function CORE:getScreenWidth() return SCREEN.w end
function CORE:getScreenHeight() return SCREEN.h end
function CORE:isFullScreen() return SCREEN.full end
function CORE:getOptionBorderlessWindow() return SCREEN.borderless end
function CORE:setOptionBorderlessWindow(b) SCREEN.borderless = b end
function CORE:setResolutionAndFullScreen(w, h, full)
    DISPLAY_CALLS[#DISPLAY_CALLS + 1] = w .. 'x' .. h .. (full and ' full' or '') .. (SCREEN.borderless and ' borderless' or '')
    if not full and SCREEN.borderless then w, h = MONITOR.w, MONITOR.h end
    SCREEN.w, SCREEN.h, SCREEN.full = w, h, full
end
function CORE:getScreenModes() local t = {} for i, m in ipairs(SCREEN_MODES) do t[i] = m end return t end
function CORE:getOptionFontSizeReal() return 2 end
function CORE:getKey(name) if name == 'RadioSurvivorSelect' then return 34 end return 0 end
function CORE:addKeyBinding() end
function CORE:isKey() return false end
getCore = function() return CORE end
takeScreenshot = function(name)
    if string.find(name, '..', 1, true) then error('IllegalArgumentException: ' .. name) end
    SHOTS[#SHOTS + 1] = name
end

local Element = getmetatable(ISButton)
function Element:removeFromUIManager()
    for i, e in ipairs(UI_ROOTS) do if rawequal(e, self) then table.remove(UI_ROOTS, i); break end end
end
function Element:setMaxDrawHeight(h) self.maxDrawHeight = h end
function Element:clearMaxDrawHeight() self.maxDrawHeight = nil end
function Element:getAbsoluteX() local x, e = 0, self; while e do x = x + (e.x or 0); e = e.parent end; return x end
function Element:getAbsoluteY() local y, e = 0, self; while e do y = y + (e.y or 0); e = e.parent end; return y end
function Element:shrinkWrap() end
-- ISUIElement:getX/getY/getWidth/getHeight read the Java object (moved by the anchors, ISUIElement.lua:259-387).
function Element:getX() local j = self.javaObject; if j and j.x then return j.x end; return self.x end
function Element:getY() local j = self.javaObject; if j and j.y then return j.y end; return self.y end
function Element:getWidth() local j = self.javaObject; if j and j.width then return j.width end; return self.width end
function Element:getHeight() local j = self.javaObject; if j and j.height then return j.height end; return self.height end
-- ISUIElement:setYScroll (ISUIElement.lua:1685-1700): bounded by the content, Java and Lua fields.
function Element:setYScroll(y)
    local j = self.javaObject
    if not j then return end
    local sh = j.scrollHeight or 0
    if -y > sh - self.height then y = -(sh - self.height) end
    if -y < 0 then y = 0 end
    j.yScroll, self.yScroll = y, y
end
function Element:setScrollHeight(h) if self.javaObject then self.javaObject.scrollHeight = h; self:setYScroll(self:getYScroll()) end end

-- ISCollapsableWindow:createChildren (ISCollapsableWindow.lua:26-93): resize widgets, close, info, pin, collapse.
function ISCollapsableWindow:createChildren()
    local th = self:titleBarHeight()
    local bh, rh = th - 2, self:resizeWidgetHeight()
    local function child(name, x, y, w, h, visible)
        local e = ISButton:new(x, y, w, h, '', self, nil)
        e:initialise(); self:addChild(e); e:setVisible(visible); self[name] = e
    end
    child('resizeWidget', self.width - rh, self.height - rh, rh, rh, self.resizable ~= false)
    child('resizeWidget2', 0, self.height - rh, self.width - rh, rh, self.resizable ~= false)
    self.resizeWidget.anchorLeft, self.resizeWidget.anchorRight = false, true
    self.resizeWidget.anchorTop, self.resizeWidget.anchorBottom = false, true
    self.resizeWidget2.anchorRight, self.resizeWidget2.anchorTop, self.resizeWidget2.anchorBottom = true, false, true
    child('closeButton', 1, 1, bh, bh, true)
    child('infoButton', 1 + bh + 3, 1, bh, bh, false)
    child('pinButton', self.width - 1 - bh, 1, bh, bh, false)
    child('collapseButton', self.width - 1 - bh, 1, bh, bh, true)
    self.pinButton.anchorLeft, self.pinButton.anchorRight = false, true
    self.collapseButton.anchorLeft, self.collapseButton.anchorRight = false, true
    for _, e in ipairs({self.resizeWidget, self.resizeWidget2, self.pinButton, self.collapseButton}) do
        local j = e.javaObject
        j.anchorLeft, j.anchorRight, j.anchorTop, j.anchorBottom = e.anchorLeft, e.anchorRight, e.anchorTop, e.anchorBottom
    end
end
function ISCollapsableWindow:setResizable(v)
    self.resizable = v
    if self.resizeWidget then self.resizeWidget:setVisible(v); self.resizeWidget2:setVisible(v) end
end
-- The field pin = true of ISCollapsableWindow:new hides the method on an instance (ISCollapsableWindow.lua:381):
-- the vanilla pin button calls the class function.
function ISCollapsableWindow:collapse() self.pin = false; self.collapseButton:setVisible(false); self.pinButton:setVisible(true) end
ISCollapsableWindow.pin = function(self) self.pin = true; self.collapseButton:setVisible(true); self.pinButton:setVisible(false) end
local collapsableNew = ISCollapsableWindow.new
function ISCollapsableWindow.new(class, x, y, w, h)
    local o = collapsableNew(class, x, y, w, h); o.pin, o.isCollapsed, o.resizable = true, false, true; return o
end
function ISCollapsableWindow:resizeWidgetHeight() return math.floor((TM:getFontHeight(UIFont.Small) + 6) / 2) + 2 end

-- ISModalDialog (ISModalDialog.lua:166-215): sized to its widest line, centred on the mouse, kept on screen
-- (ISUIElement:setX/setY of a top-level element), Yes / No buttons of 100 px at the bottom.
function ISModalDialog:new(x, y, w, h, text, yesno, target, onclick)
    text = string.gsub(text, '\\n', '\n')
    local tw, lines = 0, 0
    for line in string.gmatch(text .. '\n', '([^\n]*)\n') do
        tw = math.max(tw, getTextManager():MeasureStringX(UIFont.Small, line)); lines = lines + 1
    end
    w = math.max(w, tw + 10, 232)
    h = math.max(h, 20 + lines * getTextManager():getFontHeight(UIFont.Small) + 20 + 25 + 10)
    local o = getmetatable(ISButton).new(self, x, y, w, h)
    o.text, o.yesno, o.target, o.onclick = text, yesno, target, onclick
    o.x = math.max(0, math.min(MOUSE.x - w / 2, SCREEN.w - w))
    o.y = math.max(0, math.min(MOUSE.y - h / 2, SCREEN.h - h))
    return o
end
function ISModalDialog:initialise()
    self.children = {}
    local bh = getTextManager():getFontHeight(UIFont.Small) + 6
    self.yes = ISButton:new((self.width - 10) / 2 - 100, self.height - 10 - bh - 1, 100, bh, 'Yes', self, nil)
    self.no = ISButton:new((self.width + 10) / 2, self.height - 10 - bh - 1, 100, bh, 'No', self, nil)
    self.yes.internal, self.no.internal = 'YES', 'NO'
    self.yes:initialise(); self:addChild(self.yes); self.no:initialise(); self:addChild(self.no)
end

-- ISRichTextPanel:paginate: words wrapped at width - margins in the default font, <LINE>, colour of a line (rgb).
function ISRichTextPanel:paginate()
    self.textDirty, self.lines, self.lineX, self.rgb, self.fonts = false, {}, {}, {}, {}
    local maxW = self.width - self.marginRight - self.marginLeft
    local font = self.defaultFont or UIFont.Small
    local current, n, color = nil, 0, nil
    local function flush()
        if current and current ~= '' then
            n = n + 1; self.lines[n], self.lineX[n] = current, 0
            if color then self.rgb[n] = color; color = nil end
        end
        current = nil
    end
    for token in string.gmatch(tostring(self.text or ''), '%S+') do
        if token == '<LINE>' then flush()
        elseif string.sub(token, 1, 5) == '<RGB:' then
            local r, g, b = string.match(token, '<RGB:([%d.]+),([%d.]+),([%d.]+)>')
            color = {r = tonumber(r), g = tonumber(g), b = tonumber(b)}
        elseif not (string.sub(token, 1, 1) == '<' and string.sub(token, -1) == '>') then
            local chunk = (current and current ~= '') and (current .. ' ' .. token) or token
            if current and current ~= '' and getTextManager():MeasureStringX(font, chunk) > maxW then flush(); current = token
            else current = chunk end
        end
    end
    flush()
    local h = self.marginTop + n * getTextManager():getFontHeight(font) + self.marginBottom
    if self.autosetheight then self:setHeight(h) end
    self:setScrollHeight(h)
end

-- Real translations of the mod (table EN_TEXTS), raw key otherwise (Translator.getText).
local function format(text, ...)
    local args = {...}
    return (string.gsub(text, '%%(%d)', function(i) local v = args[tonumber(i)]; return v == nil and ('%' .. i) or tostring(v) end))
end
getTextOrNull = function(key, ...) local t = EN_TEXTS[key]; if t == nil then return nil end; return format(t, ...) end
getText = function(key, ...) return format(EN_TEXTS[key] or key, ...) end

-- Inventory of the player with display names; item scripts.
NAMES = {['Base.Bandage'] = 'Bandage', ['Base.FirstAidKit'] = 'First Aid Kit', ['Base.Bullets9mm'] = '9mm Rounds',
    ['Base.TinnedBeans'] = 'Beans', ['Base.WaterBottle'] = 'Water Bottle'}
getScriptManager = function() return {FindItem = function(_, t)
    if NAMES[t] then return {getDisplayName = function() return NAMES[t] end} end
end} end
function namedItem(kind)
    local it = item(kind)
    it.getDisplayName = function(self) return self.name or NAMES[kind] or kind end
    -- InventoryItem.setName: getDisplayName then answers the new name.
    it.setName = function(self, name) self.name = name end
    return it
end
instanceItem = namedItem
-- One frame of the UI manager: update then render of every root (UIManager.update / render).
function UI_FRAME()
    DRAWS = {}
    for _, e in ipairs(UI_ROOTS) do
        if e.javaObject and e.javaObject.visible then
            if e.update then e:update() end
            FRAME(e)
        end
    end
end
'''

RUN_ASYNC = '''
return function(test)
    local filter = {suite = "rs.notebook.visual"}
    if test then filter.test = test end
    return RST.start(filter, {attach = false, budgetMs = 100000})
end
'''


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


@unittest.skipUnless((FONTS / 'zomboidSmall.fnt').is_file(), 'polices du jeu absentes (media/fonts/EN/1x)')
class NotebookVisualTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-notebook-visual-')
        self.sim = Simulation(Path(self.tmp.name) / 'w')
        c = self.c = self.sim.add_client('alice')
        self.sim.select('alice')
        fonts = {name: Font(FONTS / f'zomboid{name}.fnt') for name in ('Small', 'Medium', 'Large')}
        c.g.PY_WIDTH = lambda font, *octets: fonts[str(font)].width(bytes(octets).decode('utf-8', errors='replace'))
        c.g.PY_HEIGHT = lambda font: fonts[str(font)].line_height
        tables = {lang: path.read_text(encoding='utf-8').splitlines() for lang, path in TABLES.items()}
        c.rt.execute(NOTEBOOK_UI)
        import json
        c.g.EN_TEXTS = c.rt.table_from(json.loads(TABLES['EN'].read_text(encoding='utf-8')))
        c.rt.execute(EXTRA_UI)

        def reader(mod, path, create):
            m = re.match(r'media/lua/shared/Translate/(\w+)/IG_UI\.json$', str(path))
            if str(mod) != 'batman_RadioSurvivor' or not m or m.group(1) not in tables:
                return None
            lines = list(tables[m.group(1)])
            return c.rt.eval('function(lines) local i = 0; return {readLine = function() i = i + 1; return lines[i] end,'
                             ' close = function() end} end')(c.rt.table_from(lines))
        c.g.getModFileReader = reader
        inv = c.g.getSpecificPlayer(0).getInventory(c.g.getSpecificPlayer(0))
        for kind in ('Base.Bandage', 'Base.FirstAidKit', 'Base.Bandage'):
            inv.AddItem(inv, c.g.namedItem(kind))
        c.load('client/RS_Carnet_Client.lua')
        c.rt.execute('SIDEBAR = getmetatable(ISButton).new(ISEquippedItem, 0, 100, 48, 300); SIDEBAR.playerNum = 0; '
                     'ISEquippedItem.initialise(SIDEBAR); ISEquippedItem.instance = SIDEBAR')
        shared = (TESTS_LUA / 'shared').as_posix()
        c.rt.execute(f'package.path = [[{shared}/?.lua;]] .. package.path')
        c.rt.execute('require "RST/RST"')
        # getTimestampMs is a Python callable here (type userdata, not function): RST would fall back to os.time.
        c.rt.execute('RST.clock = function() return getTimestampMs() end')
        c.rt.execute(SUITE.read_text(encoding='utf-8'))
        self.g = c.g

    def tearDown(self):
        self.tmp.cleanup()

    # -------------------------------------------------------------------------------------------------- helpers
    def run_async(self, test=None, ticks=3000):
        started = self.c.rt.execute(RUN_ASYNC)(test)
        self.assertTrue(started, 'RST.start refused')
        for _ in range(ticks):
            self.sim.clock.offset += 100
            self.g.UI_FRAME()
            if not self.g.RST.step():
                break
        else:
            self.fail('run not finished')
        return self.results(self.g.RST.last())

    def run_sync(self, test):
        report = self.c.rt.eval('function(t) return RST.runSync({suite = "rs.notebook.visual", test = t}) end')(test)
        return self.results(report)

    def results(self, report):
        # Strings passed as hexadecimal bytes: a note may hold a text cut inside a UTF-8 sequence under lupa.
        rows = self.c.rt.eval('''function(report)
            local function hex(s)
                if s == nil then return "" end
                return (string.gsub(tostring(s), ".", function(c) return string.format("%02x", string.byte(c)) end))
            end
            local out = {}
            for _, r in ipairs(report.results) do
                local notes = {}
                for i, n in ipairs(r.notes or {}) do notes[i] = hex(n) end
                out[#out + 1] = {test = hex(r.test), status = r.status, message = hex(r.message), notes = notes}
            end
            return out
        end''')(report)

        def text(h):
            return bytes.fromhex(h).decode('utf-8', errors='replace')
        out = {}
        for r in rows.values():
            out[text(r.test)] = (r.status, text(r.message), [text(n) for n in r.notes.values()])
        return out

    def only(self, results):
        self.assertEqual(len(results), 1, results)
        return next(iter(results.values()))

    # ---------------------------------------------------------------------------------------------------- tests
    def test_translation_tables_fit_with_the_real_fonts(self):
        status, message, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'PASS', '\n'.join([str(message)] + notes))
        measured = [n for n in notes if 'notebook strings measured' in n]
        self.assertEqual(len(measured), 4, notes)  # EN / FR, current / larger font
        for line in measured:
            self.assertRegex(line, r' \d{3} keys, \d{3} notebook strings measured, 0 problem')

    def test_views_at_two_resolutions_restore_the_display(self):
        self.c.rt.execute('ORIG_RECEIVE = RS_CarnetClient.receive')
        status, message, notes = self.only(self.run_async('views'))
        self.assertEqual(status, 'PASS', '\n'.join([str(message)] + notes))
        shots = lua_list(self.g.SHOTS)
        views = ['radio', 'contacts', 'missions', 'offer', 'reputation', 'team', 'delivery', 'confirm', 'quote',
                 'contacts_min', 'contacts_large']
        expected = [f'rs_notebook_{v}_{w}x{h}_fs2.png' for w, h in ((1280, 720), (1920, 1080)) for v in views]
        self.assertEqual(shots, expected)
        # Windowed (borderless off: otherwise the monitor size), then the mode of origin restored.
        self.assertEqual(lua_list(self.g.DISPLAY_CALLS), ['1280x720', '1920x1080', '2560x1440 borderless'])
        screen = self.g.SCREEN
        self.assertEqual((screen.w, screen.h, screen.full, screen.borderless), (2560, 1440, False, True))
        # Test windows and dialogs removed, snapshot and hooks restored.
        self.assertEqual(len(lua_list(self.g.UI_ROOTS)), 0)
        client = self.g.RS_CarnetClient
        self.assertIsNone(client.window)
        self.assertFalse(any(r.id.startswith('rsv_') for r in client.snapshot.contacts.values()))
        self.assertTrue(self.c.rt.eval('RS_CarnetClient.receive == ORIG_RECEIVE'), 'receive hook not restored')

    def test_scroll_refresh_collapse_close_sidebar_and_shortcut(self):
        status, message, notes = self.only(self.run_async('scroll'))
        self.assertEqual(status, 'PASS', '\n'.join([str(message)] + notes))
        self.assertIn('rs_notebook_scrolled_2560x1440_fs2.png', lua_list(self.g.SHOTS))
        self.assertTrue(any(n.startswith('refresh: selection rsv_c11 row 11') for n in notes), notes)
        self.assertTrue(any(n.startswith('shortcut key 34') for n in notes), notes)

    def test_detects_a_button_outside_the_window(self):
        self.c.rt.execute('''
            local layout = RS_UI_Notebook.layout
            RS_UI_Notebook.layout = function(self) layout(self); if self.saveNote then self.saveNote:setX(self.width) end end
        ''')
        status, message, notes = self.only(self.run_async('views'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any('saveNote' in n and 'outside the window' in n for n in notes), notes)
        screen = self.g.SCREEN
        self.assertEqual((screen.w, screen.h, screen.borderless), (2560, 1440, True), 'display not restored on failure')

    def test_detects_a_text_wider_than_its_button(self):
        self.c.rt.execute('''
            local layout = RS_UI_Notebook.layout
            RS_UI_Notebook.layout = function(self) layout(self); if self.talk then self.talk:setWidth(20) end end
        ''')
        status, _, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any('text wider than its button' in n for n in notes), notes)

    def test_detects_a_long_label_in_a_table(self):
        self.c.rt.execute('''
            local read = RST.NotebookVisual.readTable
            RST.NotebookVisual.readTable = function(lang)
                local T, n = read(lang)
                if lang == "FR" then T["IGUI_RS_Deliver"] = string.rep("Livrer ", 30) end
                return T, n
            end
        ''')
        status, _, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any(n.startswith('FR current font string: IGUI_RS_Deliver') for n in notes), notes)
        self.assertFalse(any(n.startswith('EN ') for n in notes if 'problem(s)' not in n), notes)

    def test_detects_controls_pushed_out_by_a_larger_font_at_the_former_minimum(self):
        # Minimum size before E03-T02 (660 x 480 whatever the font): the Contacts buttons leave the window.
        self.c.rt.execute('''
            local new = RS_UI_Notebook.new
            RS_UI_Notebook.new = function(self)
                local o = new(self); o.minimumWidth, o.minimumHeight = 660, 480; return o
            end
        ''')
        status, _, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any(n.startswith('EN larger font contacts: ') and 'outside the window 660x480' in n
                            for n in notes), notes)
        self.assertFalse(any(n.startswith('EN current font contacts: ') for n in notes), notes)

    def test_detects_a_one_line_confirmation_wider_than_1280_with_a_larger_font(self):
        # Confirmation before E03-T02: one line, never cut by the vanilla dialog.
        self.c.rt.execute('''
            local read = RST.NotebookVisual.readTable
            RST.NotebookVisual.readTable = function(lang)
                local T, n = read(lang)
                T["IGUI_RS_ConfirmSupply"] = string.gsub(T["IGUI_RS_ConfirmSupply"], "\\n", " ")
                return T, n
            end
        ''')
        status, _, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any(n.startswith('FR larger font string: IGUI_RS_ConfirmSupply dialog line') for n in notes), notes)
        self.assertFalse(any(n.startswith('EN current font string') or n.startswith('FR current font string')
                             for n in notes), notes)

    def delivery_rows(self):
        """Rows of a delivery window over a notebook at the current screen, as drawn (texts, list width)."""
        return self.c.rt.eval('''function()
            local Notebook = require "RadioSurvivor/RS_Notebook"
            local mission = RST.NotebookVisual.fixture(RS_CarnetClient, getSpecificPlayer(0)).missions[1]
            local dw = Notebook.newDelivery(mission)
            dw:instantiate()
            local out = {}
            dw.items.drawText = function(_, s, x) out[#out + 1] = {s = s, x = x} end
            for _, item in ipairs(dw.items.items) do dw.items:doDrawItem(0, item, false) end
            dw.items.drawText = nil
            return out, dw.items.width
        end''')()

    def test_long_item_name_cut_in_its_delivery_row(self):
        long_name = self.g.RST.NotebookVisual.LONG_ITEM
        inv = self.g.getSpecificPlayer(0).getInventory(self.g.getSpecificPlayer(0))
        it = self.g.instanceItem('Base.Bandage')
        it.setName(it, long_name)
        inv.AddItem(inv, it)
        rows, list_w = self.delivery_rows()
        texts = [r.s for r in rows.values()]
        cut = [s for s in texts if s.startswith('[ ] Sterilized Bandage')]
        self.assertEqual(len(cut), 1, texts)
        self.assertTrue(cut[0].endswith('...') and long_name not in cut[0], cut[0])
        font = Font(FONTS / 'zomboidSmall.fnt')
        for r in rows.values():
            self.assertLessEqual(r.x + font.width(r.s), list_w - 13, r.s)
        self.assertIn('[ ] Bandage', texts)  # short names unchanged

    def test_views_add_and_remove_the_long_item(self):
        inv = self.g.getSpecificPlayer(0).getInventory(self.g.getSpecificPlayer(0))
        before = len(lua_list(inv['items']))
        status, message, notes = self.only(self.run_async('views'))
        self.assertEqual(status, 'PASS', '\n'.join([str(message)] + notes))
        self.assertEqual(len(lua_list(inv['items'])), before, 'long named test item left in the inventory')

    def test_delivery_window_over_the_notebook_and_on_screen(self):
        self.c.rt.execute('RS_UI_Notebook.toggle()')
        geo = self.c.rt.eval('''function()
            local Notebook, w = require "RadioSurvivor/RS_Notebook", RS_CarnetClient.window
            local mission = RST.NotebookVisual.fixture(RS_CarnetClient, getSpecificPlayer(0)).missions[1]
            local out = {}
            for i, pos in ipairs({{nil, nil}, {-500, -400}, {SCREEN.w - 50, SCREEN.h - 30}}) do
                if pos[1] then w:setX(pos[1]); w:setY(pos[2]) end
                local dw = w:openDelivery(mission)
                out[i] = {dw.x, dw.y, dw.width, dw.height, w.x, w.y, w.width, w.height}
                dw:setVisible(false); dw:removeFromUIManager()
            end
            return out
        end''')()
        sw, sh = self.g.SCREEN.w, self.g.SCREEN.h
        for i, g in enumerate(geo.values()):
            x, y, w, h, nx, ny, nw, nh = (g[k] for k in range(1, 9))
            self.assertTrue(0 <= x and x + w <= sw and 0 <= y and y + h <= sh, (i, x, y, w, h))
            if i == 0:  # notebook centred: delivery window centred on it, away from the sidebar (x 0..48)
                self.assertAlmostEqual(x + w / 2, nx + nw / 2, delta=1)
                self.assertAlmostEqual(y + h / 2, ny + nh / 2, delta=1)
                self.assertGreater(x, 48)

    def test_detects_a_delivery_window_in_the_top_left_corner(self):
        # Placement before E03-T07: Delivery:new(0, 0, ...), under the sidebar.
        self.c.rt.execute('''
            local new = RS_UI_Notebook.newDelivery
            RS_UI_Notebook.newDelivery = function(mission)
                local dw = new(mission); dw:setX(0); dw:setY(0); return dw
            end
        ''')
        status, _, notes = self.only(self.run_async('views'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any('not over the notebook' in n or 'on the sidebar' in n for n in notes), notes)
        self.assertTrue(any('on the sidebar' in n for n in notes), notes)

    def test_detects_an_item_name_not_cut(self):
        # Rows before E03-T07: the name drawn whole.
        self.c.rt.execute('''
            local new = RS_UI_Notebook.newDelivery
            RS_UI_Notebook.newDelivery = function(...)
                local dw = new(...)
                local create = dw.createChildren
                dw.createChildren = function(self)
                    create(self)
                    self.items.doDrawItem = function(list, y, item)
                        list:drawText((list.parent.chosen[item.item.id] and '[x] ' or '[ ] ') .. item.text, 8, y + 4)
                        return y + list.itemheight
                    end
                end
                return dw
            end
        ''')
        status, _, notes = self.only(self.run_sync('translation tables'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any('item row wider than the list' in n and 'Sterilized Bandage' in n for n in notes), notes)

    def test_detects_a_detail_that_jumps_on_refresh(self):
        self.c.rt.execute('''
            local refresh = RS_UI_Notebook.refresh
            RS_UI_Notebook.refresh = function(self) refresh(self); self.detail:setYScroll(0) end
        ''')
        status, _, notes = self.only(self.run_async('scroll'))
        self.assertEqual(status, 'FAIL')
        self.assertTrue(any('refresh moved page' in n for n in notes), notes)

    def test_skipped_on_a_server(self):
        self.c.rt.execute('isServer = function() return true end')
        status, message, _ = self.only(self.run_sync('translation tables'))
        self.assertEqual((status, message), ('SKIP', 'client UI (not on a server)'))


class SourceTests(unittest.TestCase):
    def test_kahlua_constraints(self):
        code = re.sub(r'--\[\[.*?\]\]', '', SUITE.read_text(encoding='utf-8'), flags=re.S)
        code = re.sub(r'--[^\n]*', '', code)
        self.assertTrue(code.isascii())
        self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code))
        self.assertIsNone(re.search(r'\bgoto\b|debug\.traceback|%q|coroutine\.', code))
        self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', code.replace('~=', '')))

    def test_suite_in_the_solo_rs_campaign(self):
        campaign = (TESTS_LUA / 'client' / 'RST' / 'RST_Campaign.lua').read_text(encoding='utf-8')
        block = campaign.split('RST.CAMPAIGNS["solo-rs"]', 1)[1].split('}', 1)[0]
        self.assertIn('"rs.notebook.visual"', block)


if __name__ == '__main__':
    unittest.main(verbosity=1)
