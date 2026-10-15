"""Tests hors jeu de la parole de proximité des PNJ Living Knox (LK11-T04) : LK_Speech.lua (autorité),
LK_SpeechView.lua (clients), catalogue Data/Speech.lua et traductions IGUI_LK_Speech_* (EN, FR).

    python RadioSurvivor/tests/test_lk_speech.py

Banc tests/harness.py (serveur dédié + clients, ou solo) et doublures de test_lk_bodies.py, test_lk_guard.py,
test_lk_anim.py et test_lk_directives.py, complétées ici. Les doublures reproduisent le Java 42.21.0 relevé ; elles NE
PROUVENT PAS l'API réelle, seulement la logique :
- bulle dessinée par la vue (LK11-T09) : événement OnPreUIDraw, isoToScreenX/Y(joueur, x, y, z) (LuaManager.java:
  3355-3370, IsoUtils.java:76-79, 104-108, tileScale 2, caméra et zoom du test), getTextManager():getFontHeight et
  DrawStringCentre(UIFont, x, y, texte, r, g, b, a) (TextManager.java:80) : la doublure note chaque dessin (DRAWS) ;
  SHOWN note les bulles posées (View.show enveloppée) ;
- getBuilding / getRoom d'une case (nil dehors), isAsleep d'un joueur ;
- getTextOrNull(clé, args...) : table de traduction PROPRE à chaque machine (langue du client), %1..%4 remplacés,
  nil pour une clé inconnue (Translator.getTextOrNull) ;
- canal « dire » : message:getChat():getType():getValue() == 2, createMessage / setAuthor / setLocal /
  setOverHeadSpeech / setShouldAttractZombies / setShowInChat / showMessage (ChatBase, ChatMessage exposés,
  LuaManager.java:2623-2624) : ligne notée, aucun envoi.
Banc d'acceptation : serveur + deux clients proches (A, B) + un client éloigné (C, dans le rayon du relais des
consignes mais trop loin pour lire) ; livraison répétée ignorée.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list, LUA, DEV_LUA, DOUBLES, SHARED  # noqa: E402
from test_lk_guard import GUARD, GUARD_DOUBLES  # noqa: E402
from test_lk_anim import ANIM, ANIM_DOUBLES  # noqa: E402
from test_lk_directives import DirectiveBase  # noqa: E402

SPEECH = 'server/LivingKnox/LK_Speech.lua'
VIEW = 'client/LivingKnox/LK_SpeechView.lua'
DATA = 'shared/LivingKnox/Data/Speech.lua'
SUITE = 'shared/RST/suites/RST_LKSpeech.lua'
MOD_FILES = [LUA / SPEECH, LUA / VIEW, LUA / DATA]
DEV_FILES = [DEV_LUA / SUITE]
TRANSLATE = LUA / 'shared' / 'Translate'
PREFIX = 'IGUI_LK_Speech_'


def translations(lang):
    return json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))


SPEECH_DOUBLES = r'''
local H = HARNESS
local C = H.classes
UIFont = UIFont or { Dialogue = 'Dialogue', Medium = 'Medium' }
RANDS = 0
ZombRand = function(n) H.num(n, 'ZombRand'); RANDS = RANDS + 1; return (RANDS * 7) % n end
-- Traductions de CETTE machine (langue du client) : TRANSLATIONS posée par le test.
TRANSLATIONS = TRANSLATIONS or {}
getTextOrNull = function(key, a, b, c, d)
    local t = TRANSLATIONS[key]
    if t == nil then return nil end
    local args = { a, b, c, d }
    for i = 1, 4 do
        if args[i] ~= nil then t = string.gsub(t, '%%' .. i, tostring(args[i])) end
    end
    return t
end
function C.IsoGridSquare:getBuilding() return self.building end
function C.IsoGridSquare:getRoom() return self.room end
function C.IsoPlayer:isAsleep() return self.asleep == true end
-- Dessin des bulles (LK11-T09). isoToScreenX/Y(joueur, x, y, z) (LuaManager.java:3355-3370) : (IsoUtils.XToScreen /
-- YToScreen - décalage de la caméra) / zoom, tileScale 2 (IsoUtils.java:76-79, 104-108) : x = (x - y) * 64,
-- y = (x + y) * 32 - z * 192 ; caméra et zoom posés par le test (CAM). Joueur : index entier.
CAM = { x = 0, y = 0, zoom = 1 }
isoToScreenX = function(p, x, y, z)
    H.num(p, 'isoToScreenX'); H.num(x, 'isoToScreenX'); H.num(y, 'isoToScreenX'); H.num(z, 'isoToScreenX')
    return ((x - y) * 64 - CAM.x) / CAM.zoom
end
isoToScreenY = function(p, x, y, z)
    H.num(p, 'isoToScreenY'); H.num(x, 'isoToScreenY'); H.num(y, 'isoToScreenY'); H.num(z, 'isoToScreenY')
    return ((x + y) * 32 - z * 192 - CAM.y) / CAM.zoom
end
-- TextManager (exposé, LuaManager.java:2380) : getFontHeight(UIFont), DrawStringCentre(UIFont, x, y, texte, r, g, b,
-- a) (TextManager.java:80 ; sans police, la surcharge à 7 arguments attend un nombre en premier : refusée ici).
DRAWS = {}
local FONTS = { Dialogue = true, Medium = true, Small = true }
local TM = {}
function TM:getFontHeight(font)
    if not FONTS[font] then error('No implementation found for getFontHeight', 2) end
    return 22
end
function TM:DrawStringCentre(font, x, y, str, r, g, b, a)
    if not FONTS[font] or type(str) ~= 'string' then error('No implementation found for DrawStringCentre', 2) end
    H.num(x, 'DrawStringCentre'); H.num(y, 'DrawStringCentre'); H.num(r, 'DrawStringCentre')
    H.num(g, 'DrawStringCentre'); H.num(b, 'DrawStringCentre'); H.num(a, 'DrawStringCentre')
    DRAWS[#DRAWS + 1] = { font = font, x = x, y = y, text = str, r = r, g = g, b = b, a = a }
end
getTextManager = function() return TM end
-- Bulles posées par la vue (View.show), dans l'ordre : TRACK() enveloppe View.show une fois chargée.
SHOWN = {}
function TRACK()
    local V = LivingKnox.SpeechView
    if V == nil or V.tracked then return end
    local show = V.show
    V.show = function(z, text, c, npc)
        local ok = show(z, text, c, npc)
        if ok then
            local col = type(c) == 'table' and c or V.COLOR
            SHOWN[#SHOWN + 1] = { z = z, text = text, r = col[1], g = col[2], b = col[3], npc = npc }
        end
        return ok
    end
    V.tracked = true
end
function LINES(zb)
    local n = 0
    for _, s in ipairs(SHOWN) do if zb ~= nil and s.z == zb then n = n + 1 end end
    return n
end
function LINE(zb, i)
    local n = 0
    for _, s in ipairs(SHOWN) do
        if s.z == zb then
            n = n + 1
            if n == (i or 1) then return s end
        end
    end
    return nil
end
-- Canal « dire » (ChatBase) et message affiché localement.
CHAT_LINES = {}
local Msg = {}
Msg.__index = Msg
function Msg:setAuthor(a) self.author = a end
function Msg:setLocal(v) self.isLocal = v end
function Msg:setOverHeadSpeech(v) self.overHead = v end
function Msg:setShouldAttractZombies(v) self.attract = v end
function Msg:setShowInChat(v) self.show = v end
function Msg:getChat() return self.chat end
-- ChatType: Java enum NOT exposed to Lua (J/Lua/LuaManager.java exposes no ChatType): any method raises, tostring
-- is its name (E17-T14: "attempted index: getValue of non-table: say" in game).
function CHAT_TYPE(name)
    return setmetatable({}, {__tostring = function() return name end,
        __index = function(_, k) error("attempted index: " .. tostring(k) .. " of non-table: " .. name, 2) end})
end
CHAT_NAMES = { [2] = 'say', [5] = 'safehouse', [0] = 'general', [7] = 'admin' }
SAY_CHAT = { kind = 2 }
function SAY_CHAT:createMessage(text) return setmetatable({ text = text, chat = SAY_CHAT }, Msg) end
function SAY_CHAT:getType() return CHAT_TYPE(CHAT_NAMES[SAY_CHAT.kind]) end
function SAY_CHAT:showMessage(m)
    CHAT_LINES[#CHAT_LINES + 1] = { text = m.text, author = m.author, isLocal = m.isLocal, overHead = m.overHead,
        attract = m.attract, show = m.show }
end
function SAY_MESSAGE(kind)
    local chat = setmetatable({}, { __index = SAY_CHAT })
    chat.getType = function() return CHAT_TYPE(CHAT_NAMES[kind]) end
    return setmetatable({ text = 'hi', chat = (kind == 2) and SAY_CHAT or chat }, Msg)
end
'''


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


class SpeechBase(DirectiveBase):
    clients = ('A', 'B', 'C')
    lang = {'A': 'EN', 'B': 'FR', 'C': 'EN', 'solo': 'EN'}

    def make(self, root=None):
        h = super().make(root)
        if self.mode == 'mp':
            # Client C : même pile Living Knox que A et B (corps, garde, gestes), sans exécutant.
            h.load('C', DOUBLES)
            for path in SHARED:
                h.load('C', path)
            h.load('C', 'client/LivingKnox/LK_Client.lua')
            for path in ('server/LivingKnox/LK_Store.lua', 'server/LivingKnox/LK_Bodies.lua',
                         'server/LivingKnox/LK_Server.lua'):
                h.load('C', path)
            h.load('C', GUARD_DOUBLES)
            h.load('C', GUARD)
            h.load('C', ANIM_DOUBLES)
            h.load('C', ANIM)
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B', 'C']
        for m in names:
            mach = h.machine(m)
            mach.g.TRANSLATIONS = mach.to_lua(translations(self.lang.get(m, 'EN')))
            h.load(m, SPEECH_DOUBLES)
            h.load(m, DATA)
            if m != 'server':
                h.load(m, VIEW)
                h.load(m, 'TRACK()')
            h.load(m, SPEECH)   # toute machine charge media/lua/server : un client MP s'y arrête
        if self.mode == 'mp':
            h.move_player('C', 125, 102, 0)   # 23 cases : dans le rayon du relais (100), trop loin pour lire
        return h

    def s(self, code, m=None):
        return self.ev('LivingKnox.Speech.' + code, m)

    def v(self, code, m):
        return self.h.eval(m, 'LivingKnox.SpeechView.' + code)

    def ready(self, owner='A', machines=('A', 'B', 'C')):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        for c in self.h.clients:                     # copie pas encore reconnue (paquet reçu, drapeau absent)
            if c not in machines:
                self.h.machine(c).H.spawnZombie(zid, srv.x, srv.y, srv.z, owner)
        self.h.set_owner(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def speech_msgs(self):
        return [m for m in self.h.pending() if m['module'] == 'LivingKnox' and m['command'] == 'speech']

    def shown(self, m):
        return self.v('stats.shown', m)

    def lines(self, m, zid):
        return self.h.eval(m, f'LINES(HARNESS.zombies[{zid}])')

    def line(self, m, zid, i=1):
        return self.h.eval(m, f'LINE(HARNESS.zombies[{zid}], {i})')


class AcceptanceTests(SpeechBase):
    """Texte vu une seule fois par chaque joueur à portée ; rien pour le joueur éloigné ; livraison répétée ignorée."""

    def test_each_near_player_sees_the_bark_once_far_player_nothing(self):
        zid = self.ready('A')
        out = self.ev('(function() local o, why = LivingKnox.Speech.bark("lk-1", "greet", '
                      '{ player = HARNESS.players.A }) return o or why end)()')
        self.assertNotIsInstance(out, str, out)
        self.assertEqual(lua_list(out.names), ['A', 'B'])
        msgs = self.speech_msgs()
        self.assertEqual(sorted(m['to'] for m in msgs), ['A', 'B'])   # C (23 cases) : aucun message
        key = msgs[0]['args']['u']['k']
        self.assertTrue(key.startswith(PREFIX + 'greet_'), key)
        self.assertEqual({m['args']['u']['id'] for m in msgs}, {out.id})
        self.assertNotIn('t', msgs[0]['args']['u'])                    # le serveur n'envoie que la clé
        self.h.pump()
        for m in msgs:                                                 # livraison répétée : ignorée
            self.h._deliver(m)
        self.h.tick(10)
        self.h.pump()
        en, fr = translations('EN')[key], translations('FR')[key]
        for c, text in (('A', en), ('B', fr)):                         # chaque client dans SA langue
            self.assertEqual(self.shown(c), 1)
            self.assertEqual(self.v('stats.duplicate', c), 1)
            self.assertEqual(self.lines(c, zid), 1)
            line = self.line(c, zid)
            self.assertEqual(line.text, text)
            self.assertEqual(line.npc, 'lk-1')
        self.assertEqual(self.shown('C'), 0)
        self.assertEqual(self.v('stats.received', 'C'), 0)
        self.assertEqual(self.lines('C', zid), 0)
        self.assertEqual(self.lines('server', zid), 0)                 # rien sur le serveur
        self.assertIsNone(self.h.eval('server', 'LivingKnox.SpeechView'))  # vue absente du serveur dédié
        for c in ('A', 'B'):                                           # bulle dessinée chez chaque auditeur
            self.h.fire(c, 'OnPreUIDraw')
            self.assertEqual(self.v('stats.drawn', c), 1)
        self.h.fire('C', 'OnPreUIDraw')
        self.assertEqual(self.v('stats.drawn', 'C'), 0)
        self.assertNotEqual(en, fr)
        self.assertEqual(self.h.errors('server'), [])

    def test_far_player_walks_in_and_hears_the_next_line_only(self):
        zid = self.ready('A')
        self.ev('LivingKnox.Speech.say("lk-1", "First line.")')
        self.h.pump()
        self.h.move_player('C', 110, 102, 0)                           # 8 cases
        self.ev('LivingKnox.Speech.say("lk-1", "Second line.")')
        self.h.pump()
        self.assertEqual(self.lines('C', zid), 1)
        self.assertEqual(self.line('C', zid).text, 'Second line.')
        self.assertEqual(self.lines('A', zid), 2)

    def test_nobody_hears_nothing_sent_and_no_cooldown_used(self):
        self.ready('A')
        for c, x in (('A', 160), ('B', 170), ('C', 180)):
            self.h.move_player(c, x, 102, 0)
        r = self.ev('select(2, LivingKnox.Speech.bark("lk-1", "greet"))')
        self.assertEqual(r, 'nobody hears')
        self.assertEqual(self.speech_msgs(), [])
        self.assertIsNone(self.ev('LivingKnox.Speech.last["lk-1"]'))
        self.assertEqual(self.s('stats.silent'), 1)
        self.h.move_player('A', 104, 102, 0)
        self.assertIsNotNone(self.ev('LivingKnox.Speech.bark("lk-1", "greet")'))

    def test_client_loads_no_server_part(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Speech'))
        self.assertIsNotNone(self.h.eval('A', 'LivingKnox.SpeechView'))


class DisplayTests(SpeechBase):
    def test_written_text_goes_to_bubble_and_say_chat_with_server_name(self):
        zid = self.ready('A')
        self.h.fire('A', 'OnAddMessage', self.h.eval('A', 'SAY_MESSAGE(2)'), 0)    # canal « dire » découvert
        self.h.fire('B', 'OnAddMessage', self.h.eval('B', 'SAY_MESSAGE(5)'), 0)    # autre canal : ignoré
        out = self.ev('LivingKnox.Speech.say("lk-1", "  Stay close to the fire.  ", '
                      '{ name = "Walt Becker", id = "req-7" })')
        self.assertEqual(out.id, 'req-7')
        self.h.pump()
        chat = self.h.eval('A', 'CHAT_LINES[1]')
        self.assertEqual((chat.text, chat.author, chat.isLocal, chat.overHead, chat.attract, chat.show),
                         ('Stay close to the fire.', 'Walt Becker', True, False, False, True))
        self.assertIsNone(self.h.eval('B', 'CHAT_LINES[1]'))           # canal inconnu : bulle seule
        for c in ('A', 'B'):
            self.assertEqual(self.line(c, zid).text, 'Stay close to the fire.')
        self.assertEqual(self.h.eval('A', '#CHAT_LINES'), 1)

    def test_bark_is_bubble_only_and_colored_by_attitude(self):
        zid = self.ready('A')
        self.h.fire('A', 'OnAddMessage', self.h.eval('A', 'SAY_MESSAGE(2)'), 0)
        self.ev('LivingKnox.Speech.bark("lk-1", "warn", { band = "hostile", name = "X" })')
        self.h.pump()
        self.assertEqual(self.h.eval('A', '#CHAT_LINES'), 0)
        line = self.line('A', zid)
        self.assertEqual((line.r, line.g, line.b), (1.0, 0.7, 0.65))

    def test_body_loaded_later_then_lost_after_the_wait(self):
        zid = self.ready('A', machines=('A', 'C'))
        self.h.move_player('C', 104, 104, 0)
        self.ev('LivingKnox.Speech.say("lk-1", "Over here.")')
        self.h.pump()
        self.assertEqual(self.shown('B'), 0)                            # pas encore de copie chez B
        self.assertEqual(self.h.eval('B', '#LivingKnox.SpeechView.waiting'), 1)
        self.h.load('B', f'HARNESS.zombies[{zid}].reanimated = true')   # drapeau du joueur réanimé reçu
        self.slow()
        self.h.pump()
        self.h.tick(self.v('RETRY_EVERY', 'B'))
        self.assertEqual(self.shown('B'), 1)
        self.assertEqual(self.lines('B', zid), 1)
        self.ev('LivingKnox.Speech.say("lk-1", "Gone soon.")')
        self.h.load('B', 'LivingKnox.Anim.knownBodies = function() return {} end')
        self.h.load('B', f'HARNESS.zombies[{zid}].reanimated = false')
        self.h.pump()
        self.h.advance_ms(self.v('WAIT_MS', 'B') + 100)
        self.h.tick(self.v('RETRY_EVERY', 'B'))
        self.assertEqual(self.v('stats.lost', 'B'), 1)
        self.assertEqual(self.h.eval('B', '#LivingKnox.SpeechView.waiting'), 0)

    def test_key_with_params_and_unknown_key(self):
        zid = self.ready('A')
        for m in ('A', 'B'):
            self.h.load(m, 'TRANSLATIONS.IGUI_LK_Test = "Hello %1, %2 left."')
        out = self.ev('LivingKnox.Speech.say("lk-1", { key = "IGUI_LK_Test", params = { "Kate", 3 } })')
        self.assertIsNotNone(out)
        self.h.pump()
        self.assertEqual(self.line('A', zid).text, 'Hello Kate, 3 left.')
        self.ev('LivingKnox.Speech.say("lk-1", { key = "IGUI_LK_Missing" })')
        self.h.pump()
        self.assertEqual(self.lines('A', zid), 1)
        self.assertEqual(self.v('stats.missing', 'A'), 1)
        self.assertTrue(any('no text for key IGUI_LK_Missing' in line for line in self.h.logs('A')))

    def test_bad_input_refused(self):
        self.ready('A')
        cases = {'""': 'bad text', '"a\\nb"': 'bad text', '("x"):rep(201)': 'bad text', '{ key = "Nope" }': 'bad key',
                 '{ key = "IGUI_X", params = { 1, 2, 3, 4, 5 } }': 'bad params', '12': 'bad key'}
        for what, why in cases.items():
            self.assertEqual(self.ev(f'select(2, LivingKnox.Speech.say("lk-1", {what}))'), why, what)
        self.assertEqual(self.ev('select(2, LivingKnox.Speech.say("lk-1", "ok", { id = "bad id!" }))'), 'bad id')
        self.assertEqual(self.ev('select(2, LivingKnox.Speech.say("lk-9", "ok"))'), 'npc not embodied (unknown)')
        self.assertEqual(self.ev('select(2, LivingKnox.Speech.bark("lk-1", "dance"))'), 'unknown situation dance')
        self.assertEqual(self.speech_msgs(), [])


class BarkTests(SpeechBase):
    def test_gap_per_npc_and_same_situation_per_player(self):
        self.ready('A')
        a = 'HARNESS.players.A'
        self.assertIsNotNone(self.ev(f'LivingKnox.Speech.bark("lk-1", "greet", {{ player = {a} }})'))
        self.assertEqual(self.ev(f'select(2, LivingKnox.Speech.bark("lk-1", "rest", {{ player = {a} }}))'), 'cooldown')
        self.h.advance_ms(self.s('GAP_MS'))
        self.assertEqual(self.ev(f'select(2, LivingKnox.Speech.bark("lk-1", "greet", {{ player = {a} }}))'),
                         'said recently')
        self.assertIsNotNone(self.ev('LivingKnox.Speech.bark("lk-1", "greet", { player = HARNESS.players.B })'))
        self.h.advance_ms(self.s('SAME_MS'))
        self.assertIsNotNone(self.ev(f'LivingKnox.Speech.bark("lk-1", "greet", {{ player = {a} }})'))

    def test_last_line_of_the_npc_is_avoided(self):
        self.ready('A')
        seen = []
        for _ in range(6):
            out = self.ev('LivingKnox.Speech.bark("lk-1", "rest")')
            seen.append(out.line)
            self.run_lua('LivingKnox.Speech.recent = {}')
            self.h.advance_ms(self.s('GAP_MS'))
        for prev, cur in zip(seen, seen[1:]):
            self.assertNotEqual(prev, cur, seen)


class CatalogueTests(SpeechBase):
    mode = 'solo'

    def pick(self, situation, ctx, r, avoid='nil'):
        line = self.ev(f'LivingKnox.Speech.pick("{situation}", {ctx}, function(n) return {r} end, {avoid})')
        return line.id if line is not None else None

    def test_data_valid_and_translated_in_both_languages(self):
        self.assertEqual(lua_list(self.s('checkData()')), [])
        ids = set(lua_list(self.ev('(function() local o = {} for i, l in ipairs(LivingKnox.SpeechData.lines) do '
                                   'o[i] = l.id end return o end)()')))
        self.assertGreaterEqual(len(ids), 40)
        for lang in ('EN', 'FR'):
            keys = {k[len(PREFIX):] for k in translations(lang) if k.startswith(PREFIX)}
            self.assertEqual(keys, ids, lang)
            for k in ids:
                text = translations(lang)[PREFIX + k]
                self.assertTrue(text.strip() and len(text.encode('utf-8')) <= 200, (lang, k))
                self.assertTrue(text[0].isupper() and text[-1] in '.!?', (lang, k, text))
                self.assertTrue(all(ord(ch) <= 255 for ch in text), (lang, k, text))   # police de bulle : Latin-1
        en, fr = translations('EN'), translations('FR')
        self.assertTrue(all(en[PREFIX + k] != fr[PREFIX + k] for k in ids))

    def test_selection_by_band_type_and_role(self):
        # Toutes les répliques admises sont tirées ; aucune hors contexte.
        def admitted(situation, ctx):
            total = self.ev(f'(function() local t = 0 for _, c in ipairs(LivingKnox.Speech.candidates("{situation}", '
                            f'{ctx})) do t = t + c.w end return t end)()')
            return {self.pick(situation, ctx, r) for r in range(1, int(total) + 1)}
        self.assertEqual(admitted('greet', '{ band = "friendly" }'), {'greet_1', 'greet_2'})
        self.assertEqual(admitted('greet', '{ band = "friendly", type = "settlers" }'),
                         {'greet_1', 'greet_2', 'greet_3'})
        self.assertEqual(admitted('greet', '{ band = "hostile", type = "raiders" }'), {'greet_7', 'greet_8', 'greet_9'})
        self.assertEqual(admitted('warn', '{ band = "neutral", role = "leader" }'), {'warn_2', 'warn_3'})
        self.assertEqual(admitted('alert', '{ band = "hostile" }'), {'alert_1', 'alert_2'})
        self.assertEqual(admitted('hurt', '{ band = "neutral", role = "medic" }'),
                         {'hurt_1', 'hurt_2', 'hurt_3', 'hurt_4'})
        # Poids : rôle 1 + 3 = 4 contre 1 par réplique générique (warn_2 : 1, warn_3 : 4).
        self.assertEqual([self.pick('warn', '{ band = "neutral", role = "leader" }', r) for r in range(1, 6)],
                         ['warn_2', 'warn_3', 'warn_3', 'warn_3', 'warn_3'])
        self.assertEqual(self.pick('warn', '{ band = "neutral", role = "leader" }', 1, '"warn_2"'), 'warn_3')
        # Chaque situation, chaque attitude : au moins une réplique, quel que soit le type.
        for situation in lua_list(self.ev('LivingKnox.SpeechData.SITUATIONS')):
            for band in ('friendly', 'neutral', 'hostile'):
                for t in ('settlers', 'raiders', 'neutrals', 'unknown'):
                    self.assertIsNotNone(self.pick(situation, f'{{ band = "{band}", type = "{t}" }}', 1))

    def test_context_from_group_role_and_attitude(self):
        self.run_lua('''
            LivingKnox.Groups.ensure = function() return true end
            LivingKnox.Groups.state = { data = { groups = { ["grp-1"] = { type = "raiders", leader = "m-1",
                members = { ["m-1"] = { role = "fighter" }, ["m-2"] = { role = "medic" } } } } } }
            LivingKnox.Groups.findNpc = function(id)
                if id == "lk-1" then return "grp-1", "m-1" elseif id == "lk-2" then return "grp-1", "m-2" end
            end
            LivingKnox.Hostility.keyOf = function(p) if p == HARNESS.players.A then return "character-1" end end
            LivingKnox.Hostility.get = function(gid, key) return { level = "trusting", trend = "up" } end
            LivingKnox.Hostility.startFor = function(t) if t == "raiders" then return -50 end return 0 end
        ''')
        ctx = self.s('context("lk-1")')
        self.assertEqual((ctx.type, ctx.role, ctx.band), ('raiders', 'leader', 'hostile'))   # départ des pillards
        ctx = self.s('context("lk-2", HARNESS.players.A)')
        self.assertEqual((ctx.role, ctx.band), ('medic', 'friendly'))                        # attitude du joueur
        ctx = self.s('context("lk-3")')
        self.assertEqual((ctx.type, ctx.band), (None, 'neutral'))                            # sans groupe
        self.assertEqual([self.s(f'bandOf("{lv}")') for lv in ('trusting', 'favorable', 'cautious', 'wary',
                                                                 'hostile', 'other')],
                         ['friendly', 'friendly', 'neutral', 'hostile', 'hostile', 'neutral'])


class HearingTests(SpeechBase):
    mode = 'solo'

    def hears(self, src, dst, range_=25):
        return self.ev(f'LivingKnox.Speech.hears({src}, {dst}, {range_})')

    def test_rule_of_the_vanilla_bubble(self):
        self.run_lua('''
            local Sq = HARNESS.classes.IsoGridSquare
            function OBJ(x, y, z, b, r, extra)
                local sq = setmetatable({ x = math.floor(x), y = math.floor(y), z = z, building = b, room = r }, Sq)
                local o = { x = x, y = y, z = z, sq = sq }
                function o:getSquare() return self.sq end
                function o:getX() return self.x end
                function o:getY() return self.y end
                function o:getZ() return self.z end
                function o:isDead() return extra == "dead" end
                function o:isAsleep() return extra == "asleep" end
                return o
            end
            HOUSE, OTHER, KITCHEN, HALL = {}, {}, {}, {}
        ''')
        self.assertTrue(self.hears('OBJ(0,0,0)', 'OBJ(14,0,0)'))            # dehors : lecture sous 0,6 x 25 = 15
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(15.5,0,0)'))         # entre 15 et 25 : brouillé
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(30,0,0)'))
        self.assertTrue(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(45,0,0,HOUSE,KITCHEN)'))   # même pièce : 50
        self.assertFalse(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(51,0,0,HOUSE,KITCHEN)'))
        self.assertTrue(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(29,0,0,HOUSE,HALL)'))      # même étage : 50 x 0,6
        self.assertFalse(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(31,0,0,HOUSE,HALL)'))
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(2,0,0,HOUSE,HALL)'))                   # dehors / dedans
        self.assertFalse(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(2,0,0,OTHER,HALL)'))
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(2,0,1)'))                              # étage d'écart
        self.assertTrue(self.hears('OBJ(0,0,0,HOUSE,KITCHEN)', 'OBJ(2,0,1,HOUSE,KITCHEN)'))   # même pièce forcée
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(1,0,0,nil,nil,"dead")'))
        self.assertFalse(self.hears('OBJ(0,0,0)', 'OBJ(1,0,0,nil,nil,"asleep")'))


class SoloTests(SpeechBase):
    mode = 'solo'

    def test_solo_direct_call_shows_once_without_network(self):
        self.init()
        npc_id, body = self.spawn(102, 102)
        self.assertEqual(npc_id, 'lk-1')
        out = self.ev('LivingKnox.Speech.bark("lk-1", "smalltalk", { player = getPlayer() })')
        self.assertEqual(lua_list(out.names), ['A#0'])
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.v('stats.shown', 'solo'), 1)
        text = translations('EN')[PREFIX + out.line]
        self.assertEqual(self.v('bubbles[1].text', 'solo'), text)
        self.assertIs(self.ev('LivingKnox.SpeechView.bubbles[1].z == LivingKnox.Bodies.find("lk-1")'), True)
        self.assertEqual(self.v('last.text', 'solo'), text)
        self.assertIs(self.v(f'receive({{ id = "{out.id}", npc = "lk-1", t = "again" }})', 'solo'), False)
        self.assertEqual(self.v('stats.shown', 'solo'), 1)
        self.h.move_player('A', 160, 102, 0)
        self.assertEqual(self.ev('select(2, LivingKnox.Speech.say("lk-1", "Anyone?"))'), 'nobody hears')

    def test_dev_suite_is_listed(self):
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.speech", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.speech')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])   # E01-T19: also run by the MP server
        self.assertIsNone(listed.error)


class DrawTests(SpeechBase):
    """Bulle dessinée par la vue (LK11-T09) : OnPreUIDraw, au-dessus de la tête, pour chaque joueur local."""
    mode = 'solo'

    def setUp(self):
        super().setUp()
        self.init()
        self.spawn(102, 102)

    def draw(self):
        self.h.load('solo', 'DRAWS = {}')
        self.h.fire('solo', 'OnPreUIDraw')
        n = self.h.eval('solo', '#DRAWS')
        return [self.h.eval('solo', f'DRAWS[{i}]') for i in range(1, n + 1)]

    def head(self):
        x, y, z = (self.ev(f'LivingKnox.Bodies.find("lk-1"):get{c}()') for c in 'XYZ')
        return (x - y) * 64, (x + y) * 32 - (z + 2 / 3) * 192

    def test_line_drawn_above_the_head_with_a_shadow_each_frame(self):
        self.assertEqual(self.draw(), [])                                # rien à dessiner
        self.assertIsNotNone(self.ev('LivingKnox.Speech.say("lk-1", "Stay where you are.")'))
        for frame in (1, 2):
            draws = self.draw()
            self.assertEqual(len(draws), 3)                              # ombre (2) puis texte
            hx, hy = self.head()
            text = draws[2]
            self.assertEqual((text.font, text.text, text.a), ('Dialogue', 'Stay where you are.', 1))
            self.assertEqual((text.r, text.g, text.b), (0.95, 0.92, 0.8))  # attitude neutre
            self.assertAlmostEqual(text.x, hx)
            self.assertAlmostEqual(text.y, hy - 23)                      # bas de la ligne au point des noms vanilla
            self.assertEqual([(d.r, d.g, d.b) for d in draws[:2]], [(0, 0, 0), (0, 0, 0)])
            self.assertEqual(self.v('stats.drawn', 'solo'), frame)
        last = self.v('lastDraw', 'solo')
        self.assertEqual((last.npc, last.player), ('lk-1', 0))

    def test_camera_moves_the_bubble_and_zoom_keeps_it_over_the_head(self):
        self.ev('LivingKnox.Speech.say("lk-1", "Hey.")')
        self.h.load('solo', 'CAM = { x = 6000, y = 6500, zoom = 2 }')
        hx, hy = self.head()
        text = self.draw()[2]
        self.assertAlmostEqual(text.x, (hx - 6000) / 2)
        self.assertAlmostEqual(text.y, (hy - 6500) / 2 - 23)

    def test_long_text_wrapped_bottom_line_nearest_the_head(self):
        words = ' '.join(['word%02d' % i for i in range(24)])           # 167 caractères, 8 mots (55) par ligne
        self.ev(f'LivingKnox.Speech.say("lk-1", "{words}")')
        texts = [d for d in self.draw() if d.r != 0 or d.g != 0]
        self.assertEqual(len(texts), 3)
        self.assertEqual(' '.join(d.text for d in reversed(texts)), words)   # dessinées de bas en haut
        self.assertTrue(all(len(d.text) <= 60 for d in texts))
        self.assertEqual([round(texts[0].y - d.y) for d in texts], [0, 23, 46])

    def test_bubble_fades_then_expires_in_real_time(self):
        self.ev('LivingKnox.Speech.say("lk-1", "Ten chars.")')
        ms = self.v('bubbles[1].ms', 'solo')
        self.assertEqual(ms, 5000 + 60 * 10)
        self.h.advance_ms(ms - ms // 8)                                  # dernier huitième : alpha 0,5
        self.assertAlmostEqual(self.draw()[2].a, 0.5, places=2)
        self.h.advance_ms(ms // 8)
        self.assertEqual(self.draw(), [])
        self.assertEqual(self.h.eval('solo', '#LivingKnox.SpeechView.bubbles'), 0)
        long_text = 'x' * 200
        self.assertEqual(self.v(f'show(LivingKnox.Bodies.find("lk-1"), "{long_text}")', 'solo'), True)
        self.assertEqual(self.v('bubbles[1].ms', 'solo'), self.v('MAX_SHOW_MS', 'solo'))

    def test_next_line_replaces_the_bubble_and_dead_or_removed_body_drops_it(self):
        self.ev('LivingKnox.Speech.say("lk-1", "First.")')
        self.h.advance_ms(6000)                                          # délai de la réplique suivante
        self.ev('LivingKnox.Speech.say("lk-1", "Second.")')
        self.assertEqual([d.text for d in self.draw()], ['Second.'] * 3)
        self.run_lua('LivingKnox.Bodies.find("lk-1").square = nil')     # retiré du monde (removeFromSquare)
        self.assertEqual(self.draw(), [])
        self.assertEqual(self.h.eval('solo', '#LivingKnox.SpeechView.bubbles'), 0)

    def test_draw_error_clears_bubbles_and_warns_once(self):
        self.ev('LivingKnox.Speech.say("lk-1", "Boom.")')
        self.h.load('solo', 'getTextManager = function() return {} end')
        for _ in range(3):
            self.h.fire('solo', 'OnPreUIDraw')
            self.ev('LivingKnox.SpeechView.show(LivingKnox.Bodies.find("lk-1"), "Again.")')
        self.assertEqual(sum('draw failed' in line for line in self.h.logs('solo')), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_notebook_answer_uses_the_same_bubble(self):
        self.h.load('solo', 'shared/RadioSurvivor/RS_NPCProvider.lua')
        self.h.load('solo', 'shared/RadioSurvivor/RS_LivingKnox.lua')
        self.run_lua('RS_LivingKnox.bubble(LivingKnox.Bodies.find("lk-1"), "From the notebook.", 25)')
        line = self.h.eval('solo', 'SHOWN[#SHOWN]')
        self.assertEqual((line.text, line.npc), ('From the notebook.', 'lk-1'))
        self.assertEqual((line.r, line.g, line.b), (0.95, 0.9, 0.7))
        self.assertEqual(self.draw()[2].text, 'From the notebook.')


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
            for msg in re.findall(r'(?:warn|debug|info|error)\(\s*"([^"]*)"', code):
                self.assertTrue(all(ord(ch) < 128 for ch in msg), msg)
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')


if __name__ == '__main__':
    unittest.main()
