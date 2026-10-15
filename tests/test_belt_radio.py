"""Talkie à la ceinture avec le mod requis Belt Walkie-Talkie (batman_BeltRadio), hors jeu, sous lupa.

    python RadioSurvivor/tests/test_belt_radio.py

Vraie bibliothèque chargée depuis le dépôt voisin Workshop/BeltRadio (tests/beltradio_lib.py ; SKIP si absente),
vrai adaptateur RS_BeltRadio.lua (inscription « RadioSurvivor »), vrais RS_RadioTalk et RadioSurvivor_Const, doublures
minimales de l'API Java (Radio, DeviceData, chaînes, diffusion, addSound du bruit de réception). AddDeviceText reproduit ses deux surcharges : à
8 arguments (joueur en premier, WaveSignalDevice.java:41-62) la bulle n'est dessinée que si player:isEquipped(radio),
le reste va au chat radio (absent en solo) ; à 7 arguments (texte en premier, Radio.java:77-89) SayRadio dessine la
bulle. Toutes deux déclenchent OnDeviceText. DISPLAYED = bulles à l'écran (avec leur couleur dans COLORS).
- RegistrationTests : fournisseur inscrit (chaînes des voix seulement, code de voix reconnu).
- ReceptionTests (solo) : talkie à la ceinture reçoit et affiche les voix (couleur de la ligne), une seule fois ;
  radio rangée (inventaire principal) et sac sourds (décision 3) ; radio en main laissée au vanilla ; la ligne reçue
  alimente l'historique du carnet (RS_RadioTalk.onDeviceText -> commande heard).
- MpBubbleTests (client MP) : bulle d'une radio non tenue, couleur des voix reconnue au code Const.LINE_CODE, retenue
  pour les lignes suivantes brouillées (codes vidés), blanc pour une autre chaîne.
- TransmitTests : émission refusée à la ceinture et rangée, acceptée en main ou sur le dos (client : Talk.problem ;
  prédicat partagé Const.isCarriedRadio aussi côté serveur).
- ServerTests : serveur MP (RadioSurvivor_Server.lua) : phrase d'un talkie à la ceinture refusée (NoRadio), en main
  acceptée ; lignes des voix diffusées avec le code Const.LINE_CODE et Const.LINE_COLOR.
Simulation, PAS validation en jeu : protocole dans docs/tests-en-jeu.md.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import beltradio_lib  # noqa: E402
import test_personas_server as tps  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
LINE_COLOR = (1.0, 0.82, 0.55)

STUBS = r'''
next = nil
SIDE = "solo"
isClient = function() return SIDE == "client" end
isServer = function() return SIDE == "server" end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
getText = function(k) return k end
SandboxVars = { RadioSurvivor = { Enabled = true } }
getSandboxOptions = function() return nil end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    e.Remove = function(f) for i, g in ipairs(e.list) do if g == f then table.remove(e.list, i) break end end end
    rawset(t, k, e) return e end })
function fire(name, ...) for _, f in ipairs(Events[name].list) do f(...) end end
instanceof = function(o, c)
    if type(o) ~= 'table' then return false end
    if c == 'InventoryItem' then return o.class == 'Radio' end
    return o.class == c
end
package.preload['ISUI/ISRadioAndTvMenu'] = function() ISRadioAndTvMenu = { openRadioPanel = function() end } return true end
package.preload['RadioCom/ISRadioWindow'] = function()
    ISRadioWindow = { update = function() end }
    ISCollapsableWindow = { update = function() end }
    return true
end
getActivatedMods = function() return nil end
getClimateManager = function() return { getWeatherInterference = function() return 0 end } end
getGameTime = function() return { getMinutesStamp = function() return 1 end, getMultiplier = function() return 1 end } end
-- BeltRadio 1.2.0 plays the belt audio on a world emitter (BatmanRadio_BeltAudio): sounds are not checked here.
EMITTER = setmetatable({}, { __index = function(_, k)
    if k == "isPlaying" then return function() return false end end
    return function() return 0 end end })
getWorld = function() return {
    getFreeEmitter = function() return EMITTER end,
    takeOwnershipOfEmitter = function() end,
    returnOwnershipOfEmitter = function() end } end
function jlist(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end,
    getItemByIndex = function(_, i) return t[i + 1] end } end

-- Radio d'inventaire : DeviceData lu par le récepteur (receives) et le prédicat d'émission (canTransmitWith).
-- DISPLAYED : bulles dessinées à l'écran, COLORS : leur couleur ; CHAT : chat radio (ISChat n'existe qu'en MP).
DISPLAYED, COLORS, CHAT, REPORTS = {}, {}, {}, {}
UIFont = { Medium = 'Medium' }
function newRadio(id, khz)
    -- headphones : DeviceData.headphoneType, -1 sans écouteurs (DeviceData.java:87, getHeadphoneType:380).
    local d = { on = true, khz = khz, twoWay = true, muted = false, headphones = -1 }
    function d:getIsPortable() return true end
    function d:getIsTurnedOn() return self.on end
    function d:getIsTelevision() return false end
    function d:getChannel() return self.khz end
    function d:getDeviceVolume() return 0.5 end
    function d:getDeviceVolumeRange() return 12 end
    function d:isEmergencyBroadcast() return false end
    function d:getHeadphoneType() return self.headphones end
    -- Radio d'inventaire, porteur hors pièce : 5 + (int)(baseVolumeRange 15 × volume 0.5) (DeviceData.java:869-876).
    function d:getDeviceSoundVolumeRange() return 12 end
    function d:isPlayingMedia() return false end
    function d:isNoTransmit() return false end
    function d:getIsBatteryPowered() return false end
    function d:getIsTwoWay() return self.twoWay end
    function d:getMicIsMuted() return self.muted end
    function d:getMicRange() return 5 end
    local r = { class = 'Radio', id = id, data = d }
    function r:getDeviceData() return self.data end
    function r:getID() return self.id end
    function r:getContainer() return self.container end
    function r:AddDeviceText(first, ...)
        local text, guid, codes, cr, cg, cb
        if type(first) == 'table' then
            -- AddDeviceText(player, text, r, g, b, guid, codes, distance) : WaveSignalDevice.java:41-62.
            local player, t, r1, g1, b1, gd, cd = first, ...
            text, guid, codes, cr, cg, cb = t, gd, cd, r1, g1, b1
            if player:isEquipped(self) then
                DISPLAYED[#DISPLAYED + 1] = self.id .. ':' .. text
                COLORS[#COLORS + 1] = { cr, cg, cb }
            end
        else
            -- AddDeviceText(text, r, g, b, guid, codes, distance) : Radio.java:77-89 (SayRadio, bulle « radio »).
            local r1, g1, b1, gd, cd = ...
            text, guid, codes, cr, cg, cb = first, gd, cd, r1, g1, b1
            DISPLAYED[#DISPLAYED + 1] = self.id .. ':' .. text
            COLORS[#COLORS + 1] = { cr, cg, cb }
        end
        CHAT[#CHAT + 1] = self.id .. ':' .. text
        if codes ~= nil then fire('OnDeviceText', guid, codes, -1, -1, -1, text, self) end
    end
    return r
end

INV, BAG = { items = {} }, { items = {} }
function INV:getItems() return jlist(self.items) end
ATTACHED, HAND, BACK = {}, nil, nil
PLAYER = {}
function PLAYER:getInventory() return INV end
function PLAYER:getAttachedItems() return jlist(ATTACHED) end
function PLAYER:isAttachedItem(item) for _, a in ipairs(ATTACHED) do if a == item then return true end end return false end
function PLAYER:getPrimaryHandItem() return HAND end
function PLAYER:getSecondaryHandItem() return nil end
function PLAYER:getClothingItem_Back() return BACK end
function PLAYER:getEquipedRadio() return HAND or BACK end
function PLAYER:isEquipped(item) return item == HAND or item == BACK end
-- Bulle ajoutée directement (IsoGameCharacter.addLineChatElement, 12 arguments).
function PLAYER:addLineChatElement(text, cr, cg, cb, font, range, tag, ...)
    DISPLAYED[#DISPLAYED + 1] = 'P:' .. text .. ':' .. tag
    COLORS[#COLORS + 1] = { cr, cg, cb }
end
function PLAYER:isDead() return false end
function PLAYER:getPlayerNum() return 0 end
function PLAYER:getX() return 10 end
function PLAYER:getY() return 10 end
function PLAYER:getZ() return 0 end
getPlayer = function() return PLAYER end
getSpecificPlayer = function() return PLAYER end
getNumActivePlayers = function() return 1 end
sendClientCommand = function(p, module, command, args)
    if command == 'heard' then REPORTS[#REPORTS + 1] = args.khz .. ':' .. args.text end
end
HaloTextHelper = { addBadText = function() end }
-- Bruit pour les zombies (BatmanRadio_BeltNoise) : global addSound(IsoObject, int x, int y, int z, int radius,
-- int volume) (LuaManager.java:9239-9242). SOUNDS : bruits émis.
SOUNDS = {}
addSound = function(source, x, y, z, radius, volume)
    SOUNDS[#SOUNDS + 1] = { source = source, x = x, y = y, z = z, radius = radius, volume = volume }
end

-- Radio dans l'inventaire principal (rangée), accrochée (aussi dans l'inventaire principal), en main, sur le dos ou
-- dans un sac.
function place(radio, where)
    INV.items, ATTACHED, HAND, BACK, BAG.items = {}, {}, nil, nil, {}
    if where == 'bag' then radio.container = BAG; BAG.items[1] = radio; return end
    radio.container = INV
    INV.items[1] = radio
    if where == 'belt' then ATTACHED[1] = radio elseif where == 'hand' then HAND = radio
    elseif where == 'back' then BACK = radio end
end

-- Chaînes : une voix du mod (GUID préfixé) et une station vanilla.
CHANNELS = {}
function newChannel(guid, khz)
    local c = { guid = guid, khz = khz, last = '' }
    function c:getGUID() return self.guid end
    function c:GetFrequency() return self.khz end
    function c:getAiringBroadcast() return self.bc end
    function c:getLastAiredLine() return self.last end
    function c:IsTv() return false end
    CHANNELS[#CHANNELS + 1] = c
    return c
end
-- RadioLine : texte, couleur et codes (effets) ; les voix portent Const.LINE_COLOR et Const.LINE_CODE (serveur).
function newLine(text, r, g, b, codes)
    local l = { text = text, r = r or 1, g = g or 1, b = b or 1, codes = codes or '' }
    function l:getText() return self.text end
    function l:getEffectsString() return self.codes end
    function l:getR() return self.r end
    function l:getG() return self.g end
    function l:getB() return self.b end
    return l
end
-- Diffusion de lignes, puis avance d'une ligne à la fois (RadioChannel.update : lastAiredLine, compteur).
function air(channel, texts, voice)
    local lines = {}
    for i, t in ipairs(texts) do
        if voice then
            local c = Const.LINE_COLOR
            lines[i] = newLine(t, c.r, c.g, c.b, Const.LINE_CODE)
        else
            lines[i] = newLine(t)
        end
    end
    local bc = { lines = lines, count = 0 }
    function bc:getLines() return jlist(self.lines) end
    function bc:getCurrentLineNumber() return self.count end
    channel.bc = bc
end
function step(channel)
    local bc = channel.bc
    bc.count = bc.count + 1
    channel.last = bc.lines[bc.count]:getText()
end
MANAGER = { getChannelsList = function() return jlist(CHANNELS) end }
getZomboidRadio = function() return { getScriptManager = function() if SIDE == "client" then return nil end
        return MANAGER end,
    getDisableBroadcasting = function() return false end, PlayerListensChannel = function() end } end
RadioLine = { new = function(text, r, g, b, codes) return newLine(text, r, g, b, codes) end }
'''


class Bench(unittest.TestCase):
    def setUp(self):
        if beltradio_lib.missing():
            self.skipTest(beltradio_lib.missing())
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'client'))
        self.rt.execute(f'package.path = [[{paths};{beltradio_lib.lua_path()};]] .. package.path')
        self.rt.execute(STUBS)
        self.rt.execute("Const = require('RadioSurvivor/RadioSurvivor_Const'); "
                        f"Core = {beltradio_lib.CORE_REQUIRE}; Belt = require('RadioSurvivor/RS_BeltRadio'); "
                        "Talk = require('RadioSurvivor/RS_RadioTalk'); Events.OnDeviceText.Add(Talk.onDeviceText); "
                        "fire('OnGameStart'); "
                        "WALT = newChannel('batman_RadioSurvivor-voice-walt-140800', 140800); "
                        "STATION = newChannel('vanilla-station', 98000)")
        self.g = self.rt.globals()

    def lua(self, code):
        return self.rt.execute(code)

    def displayed(self):
        return list(self.g.DISPLAYED.values())

    def colors(self):
        return [tuple(round(x, 2) for x in c.values()) for c in self.g.COLORS.values()]


class RegistrationTests(Bench):
    def test_provider_registered_with_voice_channels_and_code(self):
        self.assertTrue(self.lua('return Core.providers.RadioSurvivor ~= nil'))
        self.assertEqual(self.lua('return Core.providers.RadioSurvivor.channels()[1]:getGUID()'),
                         'batman_RadioSurvivor-voice-walt-140800')
        self.assertEqual(self.lua('return #Core.providers.RadioSurvivor.channels()'), 1)  # station vanilla exclue
        self.assertEqual(self.lua('return Const.LINE_CODE'), 'RSVO')
        self.assertEqual(len(self.g.Const.LINE_CODE), 4)  # ignoré par ISRadioInteractions (jetons > 4 caractères)
        self.assertTrue(self.lua('return Belt.recognize("RSVO") == Const.LINE_COLOR'))
        self.assertTrue(self.lua('return Belt.recognize("ABC=1,RSVO") == Const.LINE_COLOR'))
        for codes in ('""', '"MDTX"', '"RSVOX"', 'nil'):
            self.assertIsNone(self.lua(f'return Belt.recognize({codes})'), codes)
        # Rechargement Lua : remplacé par son identifiant, jamais en double.
        self.lua('Belt.register(); n = 0; for _ in pairs(Core.providers) do n = n + 1 end')
        self.assertEqual(self.g.n, 1)

    def test_client_mp_declares_no_channel_and_no_frequency(self):
        # E05-T08 : aucun client ne connaît les fréquences des voix (gestionnaire de chaînes nil sur un client MP).
        self.lua('SIDE = "client"')
        self.assertEqual(self.lua('return #Belt.channels()'), 0)
        self.assertIsNone(self.lua('return Core.providers.RadioSurvivor.frequencies'))


class ReceptionTests(Bench):
    def run_call(self, where, channel='WALT', khz=140800, texts=('<bzzt>', 'Walt here.', 'Over.'), voice=True):
        self.lua(f"DISPLAYED, COLORS, REPORTS = {{}}, {{}}, {{}}; R = newRadio(7, {khz}); place(R, '{where}'); "
                 f"air({channel}, {{ {', '.join(repr(t) for t in texts)} }}, {str(voice).lower()})")
        self.g.fire('OnTick')  # broadcast seen before its first line
        for _ in texts:
            self.lua(f'step({channel}); CLOCK = CLOCK + 5000')
            self.g.fire('OnTick')
        return self.displayed(), list(self.g.REPORTS.values())

    def test_belt_radio_hears_a_voice_once_in_its_color_and_feeds_the_history(self):
        displayed, reports = self.run_call('belt')
        self.assertEqual(displayed, ['7:<bzzt>', '7:Walt here.', '7:Over.'])
        self.assertEqual(self.colors(), [LINE_COLOR] * 3)
        self.assertEqual(reports, ['140800:Walt here.', '140800:Over.'])

    def test_stowed_radio_and_bag_hear_nothing(self):
        # Décision 3 : radio rangée (inventaire principal, ni en main, ni sur le dos, ni accrochée) sourde en solo.
        self.assertEqual(self.run_call('pocket'), ([], []))
        self.assertEqual(self.run_call('bag'), ([], []))

    def test_radio_in_hand_left_to_vanilla_and_wrong_frequency_hear_nothing(self):
        self.assertEqual(self.run_call('hand'), ([], []))
        self.assertEqual(self.run_call('belt', khz=140600), ([], []))
        self.lua("DISPLAYED = {}; R = newRadio(8, 140800); R.data.on = false; place(R, 'belt'); "
                 "air(WALT, { 'Silent.' }, true); fire('OnTick'); step(WALT); fire('OnTick')")
        self.assertEqual(self.displayed(), [])

    def test_equipped_radio_on_the_frequency_wins_over_a_belt_radio(self):
        self.lua("DISPLAYED = {}; BELT = newRadio(9, 140800); HANDR = newRadio(10, 140800); "
                 "INV.items = { BELT, HANDR }; BELT.container, HANDR.container = INV, INV; "
                 "ATTACHED = { BELT }; HAND = HANDR; air(WALT, { 'Hello.' }, true); fire('OnTick'); "
                 "step(WALT); fire('OnTick')")
        self.assertEqual(self.displayed(), [])

    def test_belt_radio_also_hears_other_stations(self):
        # Récepteur commun : toutes les chaînes du registre, dans la couleur de leur ligne.
        displayed, _ = self.run_call('belt', channel='STATION', khz=98000, texts=('Weather report.',), voice=False)
        self.assertEqual(displayed, ['7:Weather report.'])
        self.assertEqual(self.colors(), [(1, 1, 1)])

    def test_mp_client_left_to_vanilla(self):
        self.lua('SIDE = "client"')
        self.assertEqual(self.run_call('pocket'), ([], []))
        self.assertEqual(self.run_call('belt'), ([], []))


class MpBubbleTests(Bench):
    """Client MP : le vanilla (surcharge à 8 arguments) n'affiche qu'au chat radio pour une radio non tenue."""

    def setUp(self):
        super().setUp()
        self.lua('SIDE = "client"; DISPLAYED, COLORS, CHAT, REPORTS = {}, {}, {}, {}')

    def vanilla_line(self, radios, text='Walt here.', codes='RSVO'):
        # ZomboidRadio.DistributeToPlayerOnClient : chaque radio de l'inventaire principal sur la fréquence, surcharge
        # à 8 arguments, codes de la ligne transmis par WaveSignalPacket ('' : ligne sans code ou brouillée).
        for radio in radios:
            self.lua(f"{radio}:AddDeviceText(PLAYER, {text!r}, 1, 0.82, 0.55, nil, {codes!r}, -1)")
        return self.displayed()

    def test_belt_radio_gets_one_bubble_in_the_voice_color(self):
        self.lua("R = newRadio(7, 140800); place(R, 'belt')")
        self.assertEqual(self.vanilla_line(['R']), ['P:Walt here.:radio'])
        self.assertEqual(self.colors(), [LINE_COLOR])
        self.assertEqual(list(self.g.CHAT.values()), ['7:Walt here.'])
        # Ligne suivante brouillée par l'orage (codes vidés) : fréquence retenue, même couleur.
        self.lua('CLOCK = CLOCK + 5000')
        self.vanilla_line(['R'], 'W#lt h##e.', '')
        self.assertEqual(self.colors(), [LINE_COLOR, LINE_COLOR])

    def test_other_station_bubbled_in_white(self):
        self.lua("S = newRadio(9, 98000); place(S, 'belt')")
        self.assertEqual(self.vanilla_line(['S'], 'Weather report.', ''), ['P:Weather report.:radio'])
        self.assertEqual(self.colors(), [(1, 1, 1)])

    def test_two_unheld_radios_one_bubble_hand_radio_left_to_vanilla(self):
        self.lua("A = newRadio(7, 140800); B = newRadio(8, 140800); place(A, 'belt'); "
                 "B.container = INV; INV.items[2] = B")
        self.assertEqual(self.vanilla_line(['A', 'B']), ['P:Walt here.:radio'])
        self.lua("DISPLAYED = {}; R = newRadio(10, 140800); place(R, 'hand')")
        self.assertEqual(self.vanilla_line(['R']), ['10:Walt here.'])  # bulle vanilla, rien d'ajouté

    def test_solo_never_adds_a_bubble_from_the_event(self):
        self.lua("SIDE = 'solo'; R = newRadio(7, 140800); place(R, 'belt')")
        self.assertEqual(self.vanilla_line(['R']), [])


class TransmitTests(Bench):
    """Décision 4 : émission jamais depuis la ceinture ni rangée ; en main ou sur le dos."""

    def problem(self, where):
        self.lua(f"Talk.resetForTests(); R = newRadio(7, 140800); place(R, '{where}')")
        return self.lua('return Talk.problem(PLAYER, R)')

    def test_client_refuses_belt_and_stowed_accepts_hand_and_back(self):
        self.assertEqual(self.problem('belt'), 'IGUI_RadioSurvivor_NotEquipped')
        self.assertEqual(self.problem('pocket'), 'IGUI_RadioSurvivor_NotEquipped')
        self.assertEqual(self.problem('bag'), 'IGUI_RadioSurvivor_NotEquipped')
        self.assertIsNone(self.problem('hand'))
        self.assertIsNone(self.problem('back'))
        self.lua("place(R, 'belt')")
        self.assertEqual(self.lua('return Const.transmitRefusal(PLAYER, R)'), 'belt')

    def test_shared_predicate_on_a_server_ignores_unknown_states(self):
        # Serveur : allumage et micro inconnus d'une radio non tenue ; la place seule décide.
        self.lua("SIDE = 'server'; R = newRadio(7, 140800); R.data.on = false; R.data.muted = true")
        for where, expected in (('belt', False), ('pocket', False), ('bag', False), ('hand', True), ('back', True)):
            self.lua(f"place(R, '{where}')")
            self.assertEqual(self.lua('return Const.isCarriedRadio(PLAYER, R)'), expected, where)

    def test_library_missing_refuses(self):
        self.lua("BatmanRadioSupport = nil; R = newRadio(7, 140800); place(R, 'hand')")
        self.assertEqual(self.lua('return Const.transmitRefusal(PLAYER, R)'), 'noLibrary')
        self.assertFalse(self.lua('return Const.isCarriedRadio(PLAYER, R)'))


class ServerTests(tps.ServerHarness):
    """Serveur MP réel (RadioSurvivor_Server.lua) avec la partie partagée de Belt Walkie-Talkie."""

    call = tps.ServerTests.call

    def test_belt_radio_phrase_refused_hand_radio_accepted(self):
        self.rt.execute('BELT_INV = { getItemWithID = function(_, id) if id == 7 then return RADIO end end }; '
                        'RADIO.getContainer = function() return BELT_INV end; '
                        'PLAYER.getPrimaryHandItem = function() return nil end; '
                        'PLAYER.getInventory = function() return BELT_INV end; '
                        'PLAYER.isAttachedItem = function(_, item) return item == RADIO end')
        self.assertEqual(tps.lua_list(self.g.say(145000)), ['rejected:NoRadio'])
        self.rt.execute('PLAYER.isAttachedItem = function() return false end')  # rangé : refusé aussi
        self.assertEqual(tps.lua_list(self.g.say(145000)), ['rejected:NoRadio'])
        self.rt.execute('PLAYER.getPrimaryHandItem = function() return RADIO end')
        self.assertEqual(tps.lua_list(self.g.say(145000)), ['accepted'])

    def test_voice_lines_carry_the_voice_code_and_color(self):
        self.rt.execute('RadioLine = { new = function(text, r, g, b, codes) '
                        'LINES[#LINES + 1] = { text = text, r = r, g = g, b = b, codes = codes } return text end }; '
                        'LINES = {}')
        _, aired = self.call()
        self.assertEqual(len(aired), 1)
        lines = [dict(line.items()) for line in self.g.LINES.values()]
        self.assertEqual([line['text'] for line in lines], aired[0])
        for line in lines:
            self.assertEqual(line['codes'], 'RSVO')
            self.assertEqual((round(line['r'], 2), round(line['g'], 2), round(line['b'], 2)), LINE_COLOR)


if __name__ == '__main__':
    unittest.main(verbosity=1)
