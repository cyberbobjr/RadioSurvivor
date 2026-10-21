"""Module « Émettre » de la fenêtre radio (E06-T02) : RS_RadioTalk.lua et RS_RadioModule.lua dans lupa.

    python RadioSurvivor/tests/test_radio_module.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) avec des doublures minimales de l'API Java (radios,
DeviceData, instanceof) et de l'interface vanilla (ISRadioWindow, RWMPanel, ISTextEntryBox, ISButton, clavier à
l'écran). Couvre : visibilité selon l'état de la radio (émettrice, allumée, micro), radio posée et autoradio (E06-T03 :
micro à portée et même étage, joueur assis dans le véhicule, champs envoyés au serveur), envoi commun avec le menu (texte nettoyé, coupé, attente, écart de
5 s, réponses du serveur), deux dernières lignes par fréquence (bornes, doublons, portée d'écoute, ChatMessage),
module ajouté une fois à la fenêtre, visibilité relue à chaque image, focus clavier rendu (envoi, Échap, fermeture,
module masqué, clavier à l'écran), manette. Ne prouve ni l'API Java ni le rendu : suite en jeu rs.radiomodule et
protocole docs/annexes/tests/tests-en-jeu.md.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

import lupa.lua51 as lupa

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import beltradio_lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
TALK = LUA / 'client' / 'RadioSurvivor' / 'RS_RadioTalk.lua'
MODULE = LUA / 'client' / 'RadioSurvivor' / 'RS_RadioModule.lua'
MENU = LUA / 'client' / 'RadioSurvivor_Client.lua'
NOTEBOOK = LUA / 'client' / 'RadioSurvivor' / 'RS_Notebook.lua'
HISTORY = LUA / 'client' / 'RadioSurvivor' / 'RS_RadioHistory.lua'

STUBS = r"""
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
SIDE = "solo"
isServer = function() return false end
isClient = function() return SIDE == "client" end
SENT, HALOS, SAID, PROCESSED = {}, {}, {}, {}
sendClientCommand = function(player, module, command, args) SENT[#SENT + 1] = { module = module, command = command,
    args = args } end
HaloTextHelper = { addBadText = function(player, text) HALOS[#HALOS + 1] = text end }
processSayMessage = function(text) PROCESSED[#PROCESSED + 1] = text end
getText = function(key, a) if a ~= nil then return key .. "(" .. tostring(a) .. ")" end return key end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    rawset(t, k, e) return e end })

-- Classes Java : instanceof selon le champ class des doublures.
instanceof = function(o, name)
    if type(o) ~= "table" then return false end
    if name == "InventoryItem" then return o.class == "Radio" end
    return o.class == name
end

function newData(twoWay, on, muted, khz)
    local d = { twoWay = twoWay, on = on, muted = muted, khz = khz or 145000 }
    function d:getIsTwoWay() return self.twoWay end
    function d:getIsTurnedOn() return self.on end
    function d:getMicIsMuted() return self.muted end
    function d:getChannel() return self.khz end
    function d:getMicRange() return 5 end
    -- Lu par BatmanRadioSupport.canTransmitWith (Belt Walkie-Talkie) : talkie portatif, sans pile simulée.
    function d:getIsPortable() return true end
    function d:getIsTelevision() return false end
    function d:isNoTransmit() return false end
    function d:getIsBatteryPowered() return false end
    return d
end
function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    return sq
end
-- Véhicule : places occupées (personnage -> place), comme BaseVehicle.getSeat (-1 hors du véhicule).
function newVehicle(id)
    local v = { id = id, seats = {} }
    function v:getId() return self.id end
    function v:getSeat(chr) return self.seats[chr] or -1 end
    return v
end
-- Radio d'inventaire (Radio), posée (IsoWaveSignal : case 100, 200, 0, index 3) ou autoradio (VehiclePart "Radio").
function newDevice(class, data, id)
    local o = { class = class, data = data, id = id or 42, sq = newSquare(100, 200, 0), index = 3, vehicle = nil }
    function o:getDeviceData() return self.data end
    function o:getID() return self.id end
    function o:getSquare() return self.sq end
    function o:getObjectIndex() return self.index end
    function o:getVehicle() return self.vehicle end
    function o:getId() return "Radio" end
    function o:getContainer() return self.container end
    return o
end
function newPlayer(radio)
    local p = { radio = radio, x = 100.5, y = 200.5, z = 0, num = 0, said = {}, vehicle = nil }
    -- Radio équipée = en main (ou sur le dos) ; inventaire principal : la radio y est quand container = p.inv.
    p.inv = {}
    -- Objets accrochés (ceinture) : IsoGameCharacter.isAttachedItem.
    p.attached = {}
    function p:isAttachedItem(item) return self.attached[item] == true end
    function p:getEquipedRadio() return self.radio end
    function p:getPrimaryHandItem() return self.radio end
    function p:getSecondaryHandItem() return nil end
    function p:getClothingItem_Back() return nil end
    function p:getInventory() return self.inv end
    function p:getVehicle() return self.vehicle end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:getPlayerNum() return self.num end
    function p:Say(text) SAID[#SAID + 1] = text end
    return p
end
PLAYER = newPlayer(nil)
getPlayer = function() return PLAYER end

-- Interface vanilla minimale.
UIFont = { Small = "Small" }
getTextManager = function() return {
    getFontHeight = function() return 18 end,
    MeasureStringX = function(_, font, text) return 7 * string.len(text) end } end
local function derive(base, name)
    local c = {}
    setmetatable(c, { __index = base })
    c.__index = c
    c.Type = name
    c.derive = derive
    return c
end
ISUIElement = { derive = derive }
ISUIElement.__index = ISUIElement
function ISUIElement.new(class, x, y, w, h)
    local o = { x = x, y = y, width = w, height = h, children = {}, visible = true }
    setmetatable(o, class)
    return o
end
function ISUIElement:initialise() end
function ISUIElement:addChild(child)
    child.parent = self
    self.children[#self.children + 1] = child
    if child.instantiate then child:instantiate() end
    if child.createChildren then child:createChildren() end
end
function ISUIElement:setHeight(h) self.height = h end
function ISUIElement:getHeight() return self.height end
function ISUIElement:setVisible(v) self.visible = v end
function ISUIElement:isVisible() return self.visible end
function ISUIElement:update() end
function ISUIElement:render() end
function ISUIElement:prerender() end
function ISUIElement:drawText(text, x, y) DRAWN[#DRAWN + 1] = text end
DRAWN = {}
ISPanel = derive(ISUIElement, "ISPanel")
ISPanel.new = ISUIElement.new
ISPanelJoypad = derive(ISPanel, "ISPanelJoypad")
RWMPanel = derive(ISPanelJoypad, "RWMPanel")
function RWMPanel:new(x, y, w, h) return ISUIElement.new(self, x, y, w, h) end
function RWMPanel:clear() self.player, self.device, self.deviceData, self.deviceType = nil, nil, nil, nil end
function RWMPanel:readFromObject(p, d, data, kind)
    self.player, self.device, self.deviceData, self.deviceType = p, d, data, kind
    return true
end
function RWMPanel:update() end
function RWMPanel:render() end

ISTextEntryBox = derive(ISPanelJoypad, "ISTextEntryBox")
function ISTextEntryBox:new(title, x, y, w, h) local o = ISUIElement.new(self, x, y, w, h); o.title = title; return o end
function ISTextEntryBox:instantiate()
    local entry = self
    self.javaObject = { text = self.title, focused = false, editable = true, max = nil }
end
function ISTextEntryBox:setMaxTextLength(n)
    if not self.javaObject then error("attempted index: setMaxTextLength of non-table: null") end
    self.javaObject.max = n
end
function ISTextEntryBox:getText() return self.javaObject.text end
function ISTextEntryBox:setText(t) self.javaObject.text = t end
function ISTextEntryBox:focus() self.javaObject.focused = true end
function ISTextEntryBox:unfocus() self.javaObject.focused = false end
function ISTextEntryBox:isFocused() return self.javaObject.focused end
function ISTextEntryBox:setEditable(e) self.javaObject.editable = e end
function ISTextEntryBox:setPlaceholderText(t) self.placeholder = t end

ISButton = derive(ISUIElement, "ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local o = ISUIElement.new(self, x, y, w, h); o.title, o.target, o.onclick, o.enable = title, target, onclick, true
    return o
end
function ISButton:setEnable(e) self.enable = e end
function ISButton:click() return self.onclick(self.target, self) end

RWMElement = derive(ISPanelJoypad, "RWMElement")
function RWMElement:new(x, y, w, h, subpanel, title, radioParent)
    local o = ISUIElement.new(self, x, y, w, h)
    o.subpanel, o.titleText, o.radioParent = subpanel, title, radioParent
    return o
end
function RWMElement:createChildren() self:addChild(self.subpanel) end
function RWMElement:clear() if self.subpanel.clear then self.subpanel:clear() end end
function RWMElement:readFromObject(p, d, data, kind) return self.subpanel:readFromObject(p, d, data, kind) end

ISRadioWindow = derive(ISPanel, "ISRadioWindow")
PRERENDERS = 0
function ISRadioWindow:new(x, y, w, h, player)
    local o = ISUIElement.new(self, x, y, w, h)
    o.modules, o.player, o.playerNum = {}, player, player:getPlayerNum()
    return o
end
function ISRadioWindow:instantiate() self:createChildren() end
function ISRadioWindow:initialise() end
function ISRadioWindow:createChildren()
    self.vanillaChildren = true
    self:addModule(RWMPanel:new(0, 0, self.width, 0), "IGUI_RadioMicrophone", true)
end
function ISRadioWindow:addModule(panel, name, enable)
    local m = { enabled = enable, element = RWMElement:new(0, 0, self.width, 0, panel, name, self) }
    table.insert(self.modules, m)
    self:addChild(m.element)
end
function ISRadioWindow:prerender() PRERENDERS = PRERENDERS + 1 end
function ISRadioWindow:readFromObject(player, device)
    for _, m in ipairs(self.modules) do m.element:clear() end
    local kind = (instanceof(device, "Radio") and "InventoryItem") or (instanceof(device, "IsoWaveSignal") and "IsoObject")
        or (instanceof(device, "VehiclePart") and "VehiclePart")
    for _, m in ipairs(self.modules) do
        m.enabled = m.element:readFromObject(player, device, device:getDeviceData(), kind)
        m.element:setVisible(m.enabled)
    end
end
function ISRadioWindow:close() self:clear() end
function ISRadioWindow:clear()
    for _, m in ipairs(self.modules) do m.enabled = false; m.element:clear() end
end
function ISRadioWindow:focusSelf() self.focusedSelf = true end

JoypadState = { players = {} }
Joypad = { AButton = 0, BButton = 1, XButton = 2, YButton = 3 }
OSK_VISIBLE = false
OnScreenKeyboard = {
    IsVisible = function() return OSK_VISIBLE end,
    Show = function(num, entry, data) OSK_VISIBLE = true; OSK_ENTRY = entry; return { shown = true } end,
}
RS_CLIENT_STUB = { window = nil }
package.preload["RadioSurvivor/RS_Client"] = function() return RS_CLIENT_STUB end
TOGGLES = 0
package.preload["RadioSurvivor/RS_Notebook"] = function() return { toggle = function() TOGGLES = TOGGLES + 1 end } end
for _, name in ipairs({ "RadioCom/ISRadioWindow", "RadioCom/RadioWindowModules/RWMPanel", "ISUI/ISTextEntryBox",
    "ISUI/ISButton" }) do
    package.preload[name] = function() return true end
end
"""


class Bench(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent de Kahlua
        self.rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;{(LUA / "client").as_posix()}/?.lua;]]'
                        ' .. package.path')
        self.rt.execute(STUBS)
        # Mod requis Belt Walkie-Talkie : vrai prédicat d'émission (BatmanRadioSupport.canTransmitWith).
        if beltradio_lib.missing():
            self.skipTest(beltradio_lib.missing())
        self.rt.execute(f'package.path = [[{beltradio_lib.lua_path(("shared",))};]] .. package.path')
        self.rt.execute(beltradio_lib.SUPPORT_REQUIRE)
        self.rt.execute('Talk = require "RadioSurvivor/RS_RadioTalk"; Const = require "RadioSurvivor/RadioSurvivor_Const"')

    def lua(self, code):
        return self.rt.execute(code)


class TalkTests(Bench):

    def test_module_shown_only_for_two_way_on_and_mic_open(self):
        cases = [((True, True, False), True), ((False, True, False), False), ((True, False, False), False),
                 ((True, True, True), False)]
        for (two_way, on, muted), expected in cases:
            got = self.lua(f'return Talk.moduleShown(newData({str(two_way).lower()}, {str(on).lower()}, '
                           f'{str(muted).lower()}))')
            self.assertEqual(got, expected, (two_way, on, muted))
        self.assertFalse(self.lua('return Talk.moduleShown(nil)'))
        self.lua('SandboxVars = { RadioSurvivor = { Enabled = false } }')
        self.assertFalse(self.lua('return Talk.moduleShown(newData(true, true, false))'))

    def test_device_types_like_the_vanilla_window(self):
        self.assertEqual(self.lua('return Talk.deviceType(newDevice("Radio"))'), 'InventoryItem')
        self.assertEqual(self.lua('return Talk.deviceType(newDevice("IsoWaveSignal"))'), 'IsoObject')
        self.assertEqual(self.lua('return Talk.deviceType(newDevice("VehiclePart"))'), 'VehiclePart')
        self.assertIsNone(self.lua('return Talk.deviceType({})'))

    def test_unknown_device_refused_without_sending(self):
        self.lua('Talk.resetForTests()')
        self.assertFalse(self.lua('return (Talk.send(PLAYER, {}, "hello"))'))
        self.assertEqual(len(self.g.SENT), 0)
        self.assertEqual(self.g.HALOS[1], 'IGUI_RadioSurvivor_Reject_NoRadio')

    def test_world_radio_sends_its_square_and_index(self):
        """E06-T03 : radio posée à portée du micro, même étage ; case, index et fréquence envoyés, pas d'itemId."""
        self.lua('Talk.resetForTests(); D = newDevice("IsoWaveSignal", newData(true, true, false, 145200)); '
                 'PLAYER.radio = nil')
        self.assertTrue(self.lua('return Talk.send(PLAYER, D, "hello")'))
        args = self.g.SENT[1].args
        self.assertEqual((args.source, args.x, args.y, args.z, args.index, args.channel),
                         ('world', 100, 200, 0, 3, 145200))
        self.assertIsNone(args.itemId)
        self.assertIsNone(args.vehicleId)

    def test_world_radio_mic_range_and_floor(self):
        # Distance entière < 5 (ZomboidRadio.java:519) : 4 cases passent, 5 non ; autre étage refusé.
        self.lua('D = newDevice("IsoWaveSignal", newData(true, true, false)); Talk.resetForTests()')
        for (x, y, z), expected in (((104.9, 200.5, 0), None), ((105.2, 200.5, 0), 'IGUI_RadioSurvivor_Reject_TooFar'),
                                    ((103.5, 203.5, 0), None), ((104.5, 203.5, 0), 'IGUI_RadioSurvivor_Reject_TooFar'),
                                    ((100.5, 200.5, 1), 'IGUI_RadioSurvivor_Reject_TooFar'),
                                    ((100.5, 200.5, 0.6), None)):
            self.lua(f'PLAYER.x, PLAYER.y, PLAYER.z = {x}, {y}, {z}')
            self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), expected, (x, y, z))
        self.lua('PLAYER.x, PLAYER.y, PLAYER.z = 100.5, 200.5, 0; D.data.on = false')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_Off')
        self.lua('D.data.on = true; D.data.muted = true')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_MicMuted')
        self.lua('D.data.twoWay = false')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_NotTwoWay')

    def test_car_radio_driver_and_passenger_send_the_vehicle(self):
        self.lua('V = newVehicle(17); D = newDevice("VehiclePart", newData(true, true, false, 146000)); D.vehicle = V; '
                 'Talk.resetForTests()')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_Reject_NotInVehicle')
        for seat in (0, 1, 3):
            self.lua(f'SENT = {{}}; Talk.resetForTests(); PLAYER.vehicle = V; V.seats[PLAYER] = {seat}')
            self.assertTrue(self.lua('return Talk.send(PLAYER, D, "hello")'), seat)
            args = self.g.SENT[1].args
            self.assertEqual((args.source, args.vehicleId, args.part, args.channel), ('vehicle', 17, 'Radio', 146000))
            self.assertIsNone(args.itemId)
        # Dans un autre véhicule, ou compté hors des places : refusé.
        self.lua('PLAYER.vehicle = newVehicle(18)')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_Reject_NotInVehicle')
        self.lua('PLAYER.vehicle = V; V.seats[PLAYER] = nil')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, D)'), 'IGUI_RadioSurvivor_Reject_NotInVehicle')

    def test_inventory_radio_keeps_the_old_fields(self):
        # Un serveur antérieur à E06-T03 reçoit les mêmes champs qu'avant : { text, itemId, channel }, sans source.
        self.lua('R = newDevice("Radio", newData(true, true, false), 9); PLAYER.radio = R; Talk.resetForTests()')
        self.assertTrue(self.lua('return Talk.send(PLAYER, R, "hello")'))
        args = self.g.SENT[1].args
        self.assertEqual(sorted(args.keys()), ['channel', 'itemId', 'text'])

    def test_inventory_radio_checks_in_order(self):
        self.lua('R = newDevice("Radio", newData(true, true, false)); Talk.resetForTests()')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotEquipped')
        self.lua('PLAYER.radio = R')
        self.assertIsNone(self.lua('return Talk.problem(PLAYER, R)'))
        self.lua('R.data.muted = true')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_MicMuted')
        self.lua('R.data.on = false')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_Off')
        self.lua('R.data.twoWay = false')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotTwoWay')

    def test_belt_or_stowed_radio_refused_take_it_in_hand(self):
        # Décision 4 de Belt Walkie-Talkie : talkie à la ceinture ou rangé (inventaire principal, sac) refusé avec
        # « prenez le talkie en main », rien d'envoyé ; en main il émet ; une radio d'écoute seule garde son motif.
        self.lua('R = newDevice("Radio", newData(true, true, false, 140800), 11); PLAYER.radio = nil; '
                 'R.container = PLAYER.inv; PLAYER.attached[R] = true; Talk.resetForTests(); SENT = {}; HALOS = {}')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotEquipped')
        self.assertFalse(self.lua('return (Talk.send(PLAYER, R, "Walt, belt radio"))'))
        self.assertEqual(len(self.g.SENT), 0)
        self.assertEqual(self.g.HALOS[1], 'IGUI_RadioSurvivor_NotEquipped')
        self.lua('PLAYER.attached[R] = nil')  # rangé dans l'inventaire principal
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotEquipped')
        self.lua('R.container = { bag = true }')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotEquipped')
        self.lua('R.data.twoWay = false')
        self.assertEqual(self.lua('return Talk.problem(PLAYER, R)'), 'IGUI_RadioSurvivor_NotTwoWay')
        self.lua('R.data.twoWay = true; R.container = PLAYER.inv; PLAYER.radio = R')
        self.assertIsNone(self.lua('return Talk.problem(PLAYER, R)'))
        self.assertTrue(self.lua('return Talk.send(PLAYER, R, "Walt, hand radio")'))
        self.assertEqual((self.g.SENT[1].args.itemId, self.g.SENT[1].args.channel), (11, 140800))

    def test_send_waiting_cooldown_and_answers(self):
        self.lua('R = newDevice("Radio", newData(true, true, false, 145200), 7); PLAYER.radio = R; Talk.resetForTests()')
        long = 'x' * 250
        self.assertTrue(self.lua(f'return Talk.send(PLAYER, R, "  hello\\nthere {long}")'))
        sent = self.g.SENT[1]
        self.assertEqual((sent.module, sent.command), ('RadioSurvivor', 'talk'))
        self.assertEqual(len(sent.args.text), 200)
        self.assertTrue(sent.args.text.startswith('hello there x'))
        self.assertEqual((sent.args.itemId, sent.args.channel), (7, 145200))
        # Attente d'une réponse puis écart du client : motif passager.
        self.assertEqual(self.lua('return Talk.busyReason()'), 'IGUI_RadioSurvivor_Reject_Waiting')
        self.assertFalse(self.lua('return (Talk.send(PLAYER, R, "again"))'))
        self.lua('Talk.handle("accepted", { text = "hello" }); Talk.handle("done", {})')
        self.assertEqual(list(self.g.SAID.values()), ['hello'])
        self.assertEqual(self.lua('return Talk.busyReason()'), 'IGUI_RadioSurvivor_Reject_Spam')
        # Écart aligné sur le délai du serveur (PlayerCooldown 10 s + marge 1 s) : encore grisé à 10,9 s.
        self.lua('CLOCK = CLOCK + 10900')
        self.assertEqual(self.lua('return Talk.busyReason()'), 'IGUI_RadioSurvivor_Reject_Spam')
        self.lua('CLOCK = CLOCK + 100')
        self.assertIsNone(self.lua('return Talk.busyReason()'))
        self.assertFalse(self.lua('return (Talk.send(PLAYER, R, "   "))'))  # texte vide : rien, pas de motif
        self.assertEqual(len(self.g.SENT), 1)
        # Refus du serveur : attente levée, motif affiché.
        self.assertTrue(self.lua('return Talk.send(PLAYER, R, "third")'))
        self.lua('HALOS = {}; Talk.handle("rejected", { reason = "Busy" })')
        self.assertEqual(self.g.HALOS[1], 'IGUI_RadioSurvivor_Reject_Busy')
        self.assertFalse(self.lua('return Talk.isWaiting()'))
        # MP : la phrase acceptée passe par le chat « dire ».
        self.lua('SIDE = "client"; Talk.handle("accepted", { text = "mp" })')
        self.assertEqual(list(self.g.PROCESSED.values()), ['mp'])

    def test_waiting_forgotten_after_client_timeout(self):
        self.lua('R = newDevice("Radio", newData(true, true, false)); PLAYER.radio = R; Talk.resetForTests();'
                 'Talk.send(PLAYER, R, "hi"); CLOCK = CLOCK + Const.CLIENT_TIMEOUT_MS + 1')
        self.assertFalse(self.lua('return Talk.isWaiting()'))

    def test_last_lines_bounded_per_frequency_and_deduplicated(self):
        self.lua('Talk.forgetLines(); for i = 1, 5 do CLOCK = CLOCK + 3000; Talk.recordLine(145000, "line " .. i) end')
        self.assertEqual(list(self.lua('return Talk.lastLines(145000)').values()), ['line 4', 'line 5'])
        self.assertFalse(self.lua('return Talk.recordLine(145000, "line 5")'))  # même ligne par deux appareils
        self.lua('CLOCK = CLOCK + 3000')
        self.assertTrue(self.lua('return Talk.recordLine(145000, "line 5")'))  # répétée plus tard : gardée
        self.assertEqual(len(self.lua('return Talk.lastLines(99999)')), 0)
        self.lua('for f = 1, Talk.MAX_FREQUENCIES do Talk.recordLine(100000 + f, "x") end')
        self.assertEqual(len(self.lua('return Talk.lastLines(145000)')), 0)  # plus ancienne fréquence oubliée
        self.assertEqual(len(self.lua('return Talk.lastLines(100001)')), 1)

    def test_device_text_range_and_chat_message(self):
        self.lua('Talk.forgetLines(); D = newDevice("IsoWaveSignal", newData(true, true, false, 146000))')
        self.lua('Talk.onDeviceText("g", "", 103.0, 203.0, 0.0, "near", D)')
        self.lua('Talk.onDeviceText("g", "", 110.0, 200.0, 0.0, "far", D)')
        self.lua('Talk.onDeviceText("g", "", 101.0, 201.0, 1.0, "upstairs", D)')
        self.lua('H = newDevice("Radio", newData(true, true, false, 146000));'
                 'Talk.onDeviceText("g", "", -1, -1, -1, { class = "ChatMessage", getText = function() return "player" end }, H)')
        self.lua('Talk.onDeviceText("g", "", -1, -1, -1, "unknown device", {})')
        self.assertEqual(list(self.lua('return Talk.lastLines(146000)').values()), ['near', 'player'])
        self.assertEqual(len(self.g.Events.OnDeviceText.list), 0)  # inscrit par le module seulement


class ModuleTests(Bench):

    def setUp(self):
        super().setUp()
        self.lua('Module = require "RadioSurvivor/RS_RadioModule"; W = ISRadioWindow:new(0, 0, 300, 500, PLAYER); W:instantiate();'
                 'REC = W.rsTalkRecord; P = REC.element.subpanel; assert(W.modules[2] == REC)')

    def test_added_once_with_translated_title_and_vanilla_children(self):
        self.assertTrue(self.g.W.vanillaChildren)
        self.assertEqual(self.lua('return #W.modules'), 2)
        self.assertEqual(self.lua('return REC.element.titleText'), 'IGUI_RadioSurvivor_Module')
        self.lua('Module.install(); Module.addTo(W); W2 = ISRadioWindow:new(0, 0, 300, 500, PLAYER); W2:instantiate()')
        self.assertEqual(self.lua('return #W.modules'), 2)
        self.assertEqual(self.lua('return #W2.modules'), 2)
        self.assertEqual(self.lua('return P.entry.javaObject.max'), 200)
        self.assertEqual(len(self.g.Events.OnDeviceText.list), 1)
        self.assertEqual(len(self.g.Events.OnGameStart.list), 1)

    def test_presence_by_radio_type(self):
        cases = [('Radio', True, True), ('IsoWaveSignal', True, True), ('VehiclePart', True, True),
                 ('Radio', False, False), ('VehiclePart', False, False)]
        for cls, two_way, expected in cases:
            self.lua(f'D = newDevice("{cls}", newData({str(two_way).lower()}, true, false)); W:readFromObject(PLAYER, D)')
            self.assertEqual(self.lua('return REC.enabled'), expected, (cls, two_way))
            self.assertEqual(self.lua('return REC.element.visible'), expected, (cls, two_way))

    def test_visibility_follows_power_and_mic_each_frame(self):
        self.lua('D = newDevice("Radio", newData(true, false, false)); PLAYER.radio = D; W:readFromObject(PLAYER, D)')
        self.assertFalse(self.lua('return REC.enabled'))
        self.lua('D.data.on = true; W:prerender()')
        self.assertTrue(self.lua('return REC.enabled and REC.element.visible'))
        self.assertGreater(self.g.PRERENDERS, 0)  # la méthode de la fenêtre est toujours appelée
        self.lua('P.entry:focus(); D.data.muted = true; W.subFocus = REC; JoypadState.players[1] = {}; W:prerender()')
        self.assertFalse(self.lua('return REC.enabled or REC.element.visible'))
        self.assertFalse(self.lua('return P.entry:isFocused()'))
        self.assertTrue(self.g.W.focusedSelf)

    def test_enter_sends_and_releases_focus(self):
        self.lua('Talk.resetForTests(); D = newDevice("Radio", newData(true, true, false)); PLAYER.radio = D;'
                 'W:readFromObject(PLAYER, D); P:update(); P.entry:focus(); P.entry:setText("Walt, you there?");'
                 'P.entry.onCommandEntered(P.entry)')
        self.assertEqual(self.g.SENT[1].args.text, 'Walt, you there?')
        self.assertEqual(self.lua('return P.entry:getText()'), '')
        self.assertFalse(self.lua('return P.entry:isFocused()'))
        self.assertEqual(self.lua('return P.entry.placeholder'), 'IGUI_RadioSurvivor_Talk(145.0)')
        # Grisé pendant l'attente, avec le motif dessiné.
        self.lua('P:update(); DRAWN = {}; P:render()')
        self.assertFalse(self.lua('return P.entry.javaObject.editable or P.sendButton.enable'))
        self.assertIn('IGUI_RadioSurvivor_Reject_Waiting', list(self.g.DRAWN.values()))
        self.lua('Talk.handle("done", {}); CLOCK = CLOCK + 11000; P:update()')
        self.assertTrue(self.lua('return P.entry.javaObject.editable and P.sendButton.enable'))

    def test_refused_send_keeps_text_and_releases_focus(self):
        self.lua('Talk.resetForTests(); D = newDevice("IsoWaveSignal", newData(true, true, false)); D.sq.x = 120;'
                 'W:readFromObject(PLAYER, D); P.entry:focus(); P.entry:setText("hello"); P.sendButton:click()')
        self.assertEqual(len(self.g.SENT), 0)
        self.assertEqual(self.g.HALOS[1], 'IGUI_RadioSurvivor_Reject_TooFar')
        self.assertEqual(self.lua('return P.entry:getText()'), 'hello')
        self.assertFalse(self.lua('return P.entry:isFocused()'))

    def test_belt_radio_window_greyed_take_it_in_hand(self):
        # Fenêtre d'un talkie à la ceinture (« Options de l'appareil » de Belt Walkie-Talkie) : module visible, saisie
        # grisée avec « prenez le talkie en main » (décision 4) ; en main, la saisie revient.
        self.lua('Talk.resetForTests(); D = newDevice("Radio", newData(true, true, false)); D.container = PLAYER.inv;'
                 'PLAYER.radio = nil; PLAYER.attached[D] = true; W:readFromObject(PLAYER, D); P:update();'
                 'DRAWN = {}; P:render()')
        self.assertTrue(self.lua('return REC.enabled'))
        self.assertFalse(self.lua('return P.entry.javaObject.editable or P.sendButton.enable'))
        self.assertIn('IGUI_RadioSurvivor_NotEquipped', list(self.g.DRAWN.values()))
        self.lua('PLAYER.attached[D] = nil; PLAYER.radio = D; P:update()')
        self.assertTrue(self.lua('return P.entry.javaObject.editable and P.sendButton.enable'))

    def test_escape_and_window_close_release_focus(self):
        self.lua('D = newDevice("Radio", newData(true, true, false)); W:readFromObject(PLAYER, D);'
                 'P.entry:focus(); P.entry.onOtherKey(P.entry, 15)')
        self.assertTrue(self.lua('return P.entry:isFocused()'))  # Tab : rien
        self.lua('P.entry.onOtherKey(P.entry, 1)')
        self.assertFalse(self.lua('return P.entry:isFocused()'))
        self.lua('P.entry:focus(); W:close()')
        self.assertFalse(self.lua('return P.entry:isFocused()'))

    def test_last_lines_drawn_for_the_radio_frequency(self):
        self.lua('Talk.forgetLines(); D = newDevice("Radio", newData(true, true, false, 145000));'
                 'W:readFromObject(PLAYER, D); DRAWN = {}; P:render()')
        self.assertEqual(list(self.g.DRAWN.values()), ['IGUI_RadioSurvivor_NothingHeard(145.0)'])
        self.lua('Talk.recordLine(145000, "one"); CLOCK = CLOCK + 3000; Talk.recordLine(145000, "two");'
                 'Talk.recordLine(147000, "other"); DRAWN = {}; P:render()')
        self.assertEqual(list(self.g.DRAWN.values()), ['one', 'two'])
        self.lua(f'Talk.recordLine(145000, "{"w" * 200}"); DRAWN = {{}}; P:render()')
        self.assertTrue(list(self.g.DRAWN.values())[1].endswith('...'))

    def test_joypad_keyboard_send_and_notebook(self):
        self.lua('Talk.resetForTests(); D = newDevice("Radio", newData(true, true, false)); PLAYER.radio = D;'
                 'W:readFromObject(PLAYER, D); JD = { player = 0, focus = REC.element }; JoypadState.players[1] = JD;'
                 'P:onJoypadDown(Joypad.AButton)')
        self.assertTrue(self.lua('return OSK_ENTRY == P.entry and P.oskOpen and JD.focus.shown'))
        # Clavier refermé : il redonne le focus au champ ; le module le rend après le délai.
        self.lua('P.entry:focus(); OSK_VISIBLE = false; P:update()')
        self.assertTrue(self.lua('return P.entry:isFocused()'))
        self.lua('CLOCK = CLOCK + 300; P:update()')
        self.assertFalse(self.lua('return P.entry:isFocused()'))
        self.lua('P.entry:setText("over"); P:onJoypadDown(Joypad.YButton)')
        self.assertEqual(self.g.SENT[1].args.text, 'over')
        self.lua('P:onJoypadDown(Joypad.XButton)')
        self.assertEqual(self.g.TOGGLES, 1)
        self.lua('RS_CLIENT_STUB.window = { isVisible = function() return true end, bringToTop = function() BROUGHT = true end };'
                 'P.notebookButton:click()')
        self.assertEqual(self.g.TOGGLES, 1)
        self.assertTrue(self.g.BROUGHT)
        self.assertEqual(self.lua('return P:getAPrompt()'), 'IGUI_RadioSurvivor_Type')
        self.assertEqual(self.lua('return P:getYPrompt()'), 'IGUI_RadioSurvivor_Send')


class SourceTests(unittest.TestCase):

    def test_kahlua_constraints(self):
        for path in (TALK, MODULE, MENU, NOTEBOOK, HISTORY):
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|coroutine\.|debug\.traceback|%q', code), path.name)
            self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', code.replace('~=', '')), path.name)
            self.assertTrue(code.isascii(), f'{path.name}: non-ASCII outside comments')

    def test_menu_uses_the_shared_send_path(self):
        menu = re.sub(r'--[^\n]*', '', MENU.read_text(encoding='utf-8'))
        self.assertIn('Talk.send(player, radio,', menu)
        self.assertIn('Const.clientHandler = Talk.handle', menu)
        self.assertNotIn('sendClientCommand', menu)
        self.assertIn('IGUI_RadioSurvivor_Talk', menu)  # menu « Parler sur … » gardé jusqu'à validation (E06-T01)

    def test_notebook_say_line_uses_the_shared_send_path(self):
        # Say line of the notebook Radio tab (E06-T06): Talk.send and Talk.busyReason, never its own command.
        notebook = re.sub(r'--[^\n]*', '', NOTEBOOK.read_text(encoding='utf-8'))
        self.assertIn("require 'RadioSurvivor/RS_RadioTalk'", notebook)
        self.assertIn('Talk.send(player, talkDevice(player), text)', notebook)
        self.assertIn('Talk.busyReason()', notebook)
        self.assertNotIn('sendClientCommand', notebook)

    def test_notebook_keys_exist_in_en_and_fr(self):
        keys = {'IGUI_RS_' + k for k in re.findall(r"\btr\('(\w+)'\s*[,)]", NOTEBOOK.read_text(encoding='utf-8'))}
        keys |= {'IGUI_RS_' + k for k in ('Radio', 'Contacts', 'Missions', 'Reputation')}
        keys |= {'IGUI_RS_Radio_' + k for k in ('said', 'reply', 'heard')}
        keys |= set(re.findall(r"getText\('(IGUI_\w+)'\s*[,)]", NOTEBOOK.read_text(encoding='utf-8')))
        for lang in ('EN', 'FR'):
            data = json.loads((LUA / 'shared' / 'Translate' / lang / 'IG_UI.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(sorted(k for k in keys if k not in data), [], lang)
            for kind in ('said', 'reply', 'heard'):
                self.assertTrue(data['IGUI_RS_Radio_' + kind].startswith('%1 '), (lang, kind))
                self.assertIn('%2', data['IGUI_RS_Radio_' + kind], (lang, kind))

    def test_translation_keys_exist_in_en_and_fr(self):
        keys = set(re.findall(r'"(IGUI_(?:RadioSurvivor|RS)_\w+)"', MODULE.read_text(encoding='utf-8')
                              + TALK.read_text(encoding='utf-8'))) - {'IGUI_RadioSurvivor_Reject_'}
        keys |= {'IGUI_RadioSurvivor_Reject_' + r for r in ('Busy', 'Waiting', 'Spam', 'NoRadio')}
        for lang in ('EN', 'FR'):
            data = json.loads((LUA / 'shared' / 'Translate' / lang / 'IG_UI.json').read_text(encoding='utf-8-sig'))
            missing = sorted(k for k in keys if k not in data)
            self.assertEqual(missing, [], lang)
            self.assertIn('%1', data['IGUI_RadioSurvivor_NothingHeard'], lang)


if __name__ == '__main__':
    unittest.main()
