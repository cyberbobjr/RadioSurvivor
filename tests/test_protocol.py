"""Tests hors jeu : vrai Lua du mod (lupa, Lua 5.1, API du jeu simulée) + vrai pont en mode --offline.

    python tests/test_protocol.py

Scénarios : solo (client et serveur dans la même machine Lua) ; le serveur trie (E05-T08 : aucune fréquence de voix chez
les clients, fréquence sans voix sans réponse ni demande au pont, anti-spam) ; multijoueur (un serveur et deux
clients dans des machines Lua séparées, commandes relayées comme par le réseau) ; pont absent ; deux voix
(Walt et une voix propre au banc : routage par fréquence, historiques séparés, radio haut de gamme, heures
d'écoute, budget, fiche jamais envoyée aux clients) ; pont seul (prompt depuis la fiche, Walt inchangé, secret
retenu, compatibilité sans fiche) ; appels spontanés (E05-T05 : texte écrit par le pont, pont absent ou
antérieur qui ignore la demande : texte fixe de la fiche) ; radios du monde (E06-T03 : passagère qui émet par
l'autoradio, joueur loin d'une radio posée refusé par le serveur) ; fréquence tirée (E05-T07 : la vraie fiche de Walt tire sa fréquence, le pont
répond par l'identifiant de voix, un redémarrage garde la fréquence). Les autres scénarios donnent à Walt sa
fréquence d'exemple fixe 145.0 (WALT_FIXED).
Ne vérifie pas l'API Java réelle : le test en jeu reste nécessaire.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import unittest

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import beltradio_lib  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "Contents/mods/batman_RadioSurvivor/42.21"
LUA = MOD / "media/lua"
BRIDGE = ROOT / "bridge/radio_bridge.py"
# Fiche livrée de Walt, sa plage de tirage remplacée par la fréquence d'exemple 145.0 (E05-T07) : ces scénarios
# raisonnent sur une fréquence connue ; le tirage est couvert par scenario_drawn_frequency et
# tests/test_personas_server.py.
WALT_FIXED = re.sub(r"(?m)^frequency_range=.*$", "frequencies=145.0",
                    (MOD / "personas/walt.txt").read_text(encoding="utf-8"))

STUBS = r"""
local mode = ...
isClient = function() return mode == "client" end
isServer = function() return mode == "server" end
getText = function(k, a) return k .. (a and ("|" .. tostring(a)) or "") end
getTextOrNull = function(k) return k end
local rand = 0
ZombRand = function(a, b) rand = rand + 1 if b then return a + rand end return 1 end
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    e.Remove = function(f) for i, g in ipairs(e.list) do if g == f then table.remove(e.list, i) break end end end
    rawset(t, k, e) return e end })
function fire(name, ...) for _, f in ipairs(Events[name].list) do f(...) end end
getSandboxOptions = function() return nil end
SandboxVars = { RadioSurvivor = { Enabled = true, PlayerCooldown = 10, MaxPerHour = 60,
    SpontaneousCalls = true } }
-- Liste Java (ArrayList<String>) rendue par listFilesIn*Directory.
function JLIST(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
HOUR = 21
GT_MODDATA = {}
getGameTime = function() return {
    getYear = function() return 1993 end, getMonth = function() return 6 end, getDay = function() return 11 end,
    getHour = function() return HOUR end, getMinutes = function() return 5 end,
    getWorldAgeHours = function() return WORLD_AGE_HOURS or 0 end,
    getModData = function() return GT_MODDATA end } end
getWorld = function() return { getWorld = function() return "TestWorld" end,
    getGameMode = function() return "Multiplayer" end } end

-- Diffusions dans l'ordre : lignes (BROADCASTS) et fréquence de la chaîne (AIRED_ON).
BROADCASTS, AIRED_ON = {}, {}
RadioLine = { new = function(t) return t end }
RadioBroadCast = { new = function(id) local b = { id = id, lines = {} }
    b.AddRadioLine = function(self, l) table.insert(self.lines, l) end return b end }
local Channel = {}
Channel.__index = Channel
function Channel:setAiringBroadcast(bc)
    self.airing = bc table.insert(BROADCASTS, bc.lines) table.insert(AIRED_ON, self.freq) end
function Channel:getAiringBroadcast() return self.airing end
function Channel:getGUID() return self.uuid end
function Channel:GetFrequency() return self.freq end
function Channel:GetName() return self.name end
MANAGER = { channels = {} }
function finishAiring() for _, ch in pairs(MANAGER.channels) do ch.airing = nil end end
function MANAGER:AddChannel(ch) self.channels[ch.uuid] = ch end
function MANAGER:getRadioChannel(uuid) return self.channels[uuid] end
function MANAGER:getChannelsList()
    local list = {}
    for _, ch in pairs(self.channels) do list[#list + 1] = ch end
    return JLIST(list)
end
function MANAGER:RemoveChannel(freq)
    for uuid, ch in pairs(self.channels) do if ch.freq == freq then self.channels[uuid] = nil end end
end
DynamicRadioChannel = { new = function(name, freq, cat, uuid)
    return setmetatable({ uuid = uuid, freq = freq, name = name }, Channel) end }
ChannelCategory = { Amateur = "Amateur" }
REMOVED_NAMES = {}
getZomboidRadio = function() return {
    getScriptManager = function() if mode == "client" then return nil end return MANAGER end,
    removeChannelName = function(self, f) table.insert(REMOVED_NAMES, f) end } end

PLAYERS = {}
function makePlayer(username)
    -- Bornes de réglage et haut de gamme : données du script de l'objet (Item.java), connues du serveur.
    local device = { on = true, twoWay = true, channel = 145000, muted = false, minCh = 200, maxCh = 1000000,
        highTier = false }
    function device:getIsTwoWay() return self.twoWay end
    function device:getMinChannelRange() return self.minCh end
    function device:getMaxChannelRange() return self.maxCh end
    function device:getIsHighTier() return self.highTier end
    function device:getIsTurnedOn() return self.on end
    function device:getChannel() return self.channel end
    function device:getMicIsMuted() return self.muted end
    -- Lu par BatmanRadioSupport.canTransmitWith (Belt Walkie-Talkie) : talkie portatif, sans pile simulée.
    function device:getIsPortable() return true end
    function device:getIsTelevision() return false end
    function device:isNoTransmit() return false end
    function device:getIsBatteryPowered() return false end
    -- Inventaire principal (ItemContainer) : la radio y reste en main comme à la ceinture (container = INVENTORY) ;
    -- dans un sac, container vaut un autre conteneur. getItemWithID ne cherche que dans l'inventaire principal.
    local inventory = {}
    local radio = { isRadio = true, device = device, container = inventory }
    function radio:getDeviceData() return self.device end
    function radio:getDisplayName() return "Walkie-talkie" end
    function radio:getID() return 4242 end
    function radio:getContainer() return self.container end
    function inventory:getItemWithID(id)
        if radio.container == inventory and radio:getID() == id then return radio end
        return nil
    end
    local p = { username = username, radio = radio, inHand = true, said = {}, halos = {}, inventory = inventory }
    -- Stats (E05-T15, zombie/characters/Stats.java:80-93) : valeurs bornées 0..100, set/add/remove rendent vrai si la
    -- valeur a changé ; ennui et tristesse à 0 par défaut (CharacterStat.java:15, 34).
    p.stats = makeStats()
    function p:getStats() return self.stats end
    -- Radio équipée (main ou dos) : getEquipedRadio ; hors de la main (inHand = false), elle n'est plus équipée.
    function p:getEquipedRadio() if self.inHand then return self.radio end return nil end
    function p:getInventory() return self.inventory end
    function p:getPrimaryHandItem() if self.inHand then return self.radio end return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getClothingItem_Back() return nil end
    -- Objet accroché (ceinture) : attached = la radio (IsoGameCharacter.isAttachedItem).
    function p:isAttachedItem(item) return self.attached ~= nil and self.attached == item end
    function p:Say(t) table.insert(self.said, t) end
    function p:getPlayerNum() return 0 end
    function p:getHoursSurvived() return 80 end
    function p:getUsername() return self.username end
    function p:getDescriptor() return { getForename = function() return username end,
        getSurname = function() return "Doe" end } end
    PLAYERS[username] = p
    return p
end
CharacterStat = { BOREDOM = "Boredom", UNHAPPINESS = "Unhappiness" }
function makeStats()
    local s = { values = {} }
    function s:get(stat) return self.values[stat] or 0 end
    function s:set(stat, v)
        local old = self:get(stat)
        v = math.max(0, math.min(100, v))
        self.values[stat] = v
        return v ~= old
    end
    function s:add(stat, n) return self:set(stat, self:get(stat) + n) end
    function s:remove(stat, n) return self:add(stat, -n) end
    return s
end
-- syncPlayerStats (LuaManager.java:9339) : serveur MP seulement ; appels relevés { joueur, masque }.
SYNCED = {}
syncPlayerStats = function(p, mask) SYNCED[#SYNCED + 1] = { player = p, mask = mask } end
getOnlinePlayers = function()
    local list = {}
    for _, p in pairs(PLAYERS) do list[#list + 1] = p end
    return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
end
instanceof = function(o, c) return type(o) == "table" and o.isRadio == true and (c == "Radio" or c == "InventoryItem") end
HaloTextHelper = { addBadText = function(p, t) table.insert(p.halos, t) end,
    -- E05-T15 : halo à flèche des émissions (ISRadioInteractions.addHalo) : « texte:up » ou « texte:down ».
    addTextWithArrow = function(p, t, _sep, up) table.insert(p.halos, t .. (up and ":up" or ":down")) end,
    getGoodColor = function() return "good" end }
ISInventoryPaneContextMenu = { addToolTip = function() return {} end }
SAID_CHAT = {}
processSayMessage = function(t) table.insert(SAID_CHAT, t) end
ISTextBox = { new = function(self, x, y, w, h, text, def, target, onclick, pn, p1, p2)
    TEXTBOX = { onclick = onclick, target = target, p1 = p1, p2 = p2,
        initialise = function() end, addToUIManager = function() end }
    return TEXTBOX end }

-- Ouvre le menu de la radio du joueur, choisit l'option et valide la boîte de saisie.
function talk(player, text)
    local opts = {}
    local ctx = { addOption = function(self, label, a, f, b)
        local o = { label = label, a = a, f = f, b = b } table.insert(opts, o) return o end }
    fire("OnFillInventoryObjectContextMenu", 0, ctx, { player.radio })
    if #opts ~= 1 then return "pas d'option" end
    -- Option grisée : motif de l'infobulle gardé dans TALK_TOOLTIP.
    if opts[1].notAvailable then TALK_TOOLTIP = opts[1].toolTip and opts[1].toolTip.description return "grisee" end
    opts[1].f(opts[1].a, opts[1].b)
    local button = { internal = "OK", parent = { entry = { getText = function() return text end } } }
    TEXTBOX.onclick(TEXTBOX.target, button, TEXTBOX.p1, TEXTBOX.p2)
    return "ok"
end
"""


class Game:
    """Une machine Lua : solo, serveur ou client."""

    def __init__(self, mode: str, exchange: Path, clock, drawn: bool = False):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.rt.execute(STUBS, mode)
        g.getTimestampMs = clock
        # Zomboid/Lua/batman_RadioSurvivor/<x> -> exchange/<x> (fichiers d'échange et dossier des fiches).
        lua_path = lambda name: exchange / Path(name).relative_to("batman_RadioSurvivor")
        g.getFileWriter = lambda name, create, append: file_writer(lua_path(name), name, append)
        g.getFileReader = lambda name, create: Reader(lua_path(name))
        g.listFilesInZomboidLuaDirectory = lambda d: g.JLIST(self.rt.table_from(
            sorted(f.name for f in lua_path(d).glob("*") if f.is_file()) if lua_path(d).is_dir() else []))
        # Fiches livrées : Walt seul (ces scénarios raisonnent sur ses fréquences ; les six voix livrées sont
        # couvertes par tests/test_personas_server.py, DeliveredVoicesServerTests).
        g.listFilesInModDirectory = lambda mod, d: g.JLIST(self.rt.table_from(
            sorted(f.name for f in (MOD / d).glob("*") if f.is_file()
                   and (Path(d).name != "personas" or f.name == "walt.txt"))))
        # drawn : vraie fiche de Walt (plage de tirage) ; sinon sa fréquence d'exemple fixe (WALT_FIXED).
        g.getModFileReader = lambda mod, name, create: (
            TextReader(WALT_FIXED) if name == "personas/walt.txt" and not drawn else Reader(MOD / name))
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server', 'client'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        # Mod requis Belt Walkie-Talkie : vraie partie partagée (BatmanRadioSupport.canTransmitWith), chargée en solo,
        # sur un client et sur un serveur. Absente : SKIP (unittest.SkipTest, rapporté par main()).
        if beltradio_lib.missing():
            raise unittest.SkipTest(beltradio_lib.missing())
        self.rt.execute(f'package.path = [[{beltradio_lib.lua_path(("shared",))};]] .. package.path')
        self.rt.execute(beltradio_lib.SUPPORT_REQUIRE)
        # Mod requis Signal Smoke : doublure de son module public (tests/signalsmoke_double.py).
        self.rt.execute(SIGNAL_SMOKE)
        self.g = g

    def load(self, *files: str) -> None:
        for rel in files:
            self.rt.execute((LUA / rel).read_text(encoding="utf-8"))

    def table(self, value):
        """Copie (récursive) d'une table d'une autre machine Lua, comme le réseau."""
        if value is None:
            return None
        return self.rt.table_from({k: (self.table(v) if lupa.lua_type(v) == "table" else v)
                                   for k, v in value.items()})


# Extensions admises par getFileWriter (zombie/Lua/LuaManager.java:1045, 5535-5540 ; casse comprise).
WRITER_EXTENSIONS = ("ini", "cfg", "txt", "log", "json")


def file_writer(path: Path, name: str, append: bool):
    """getFileWriter du jeu : nil pour un chemin en `..` ou une extension non admise ; fichier créé et, sans ajout,
    tronqué dès l'ouverture (FileOutputStream) ; texte écrit tel quel en UTF-8, sans conversion des fins de ligne."""
    if ".." in name or Path(name).suffix[1:] not in WRITER_EXTENSIONS:
        return None
    return Writer(path, append)


class Writer:
    def __init__(self, path: Path, append: bool = False):
        self.path, self.parts = path, []
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not append or not path.exists():
            path.write_bytes(b"")

    def write(self, s):
        self.parts.append(s)

    def close(self):
        with self.path.open("a", encoding="utf-8", newline="") as f:
            f.write("".join(self.parts))


def Reader(path: Path):
    if not path.exists():
        return None

    class _R:
        lines = path.read_text(encoding="utf-8").splitlines()

        def readLine(self):
            return self.lines.pop(0) if self.lines else None

        def close(self):
            pass

    return _R()


def TextReader(text: str):
    class _R:
        lines = text.splitlines()

        def readLine(self):
            return self.lines.pop(0) if self.lines else None

        def close(self):
            pass

    return _R()


class Clock:
    def __init__(self):
        self.offset = 0.0

    def __call__(self):
        return time.time() * 1000 + self.offset


def start_bridge(exchange: Path, intent: str = "") -> subprocess.Popen:
    """Offline bridge on an exchange folder. intent "accept": explicit bench flag (RS_OFFLINE_INTENT, E17-T10), the
    offline reply stands for a model that accepts the open offer; never derived from the player's words."""
    env = dict(os.environ, RS_OFFLINE_INTENT=intent)
    return subprocess.Popen([sys.executable, str(BRIDGE), "--offline", "--exchange", str(exchange), "--poll", "0.05"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", env=env)


def pump(until, ticks, timeout=15.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for tick in ticks:
            tick()
        if until():
            return True
        time.sleep(0.05)
    return False


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)]


def scenario_solo(tmp: Path) -> None:
    exchange = tmp / "solo"
    exchange.mkdir()
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        game = Game("solo", exchange, clock)
        game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
                  "client/RadioSurvivor_Client.lua")
        g = game.g
        g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
        player = g.makePlayer("Kate")
        g.getPlayer = lambda: player
        g.getSpecificPlayer = lambda n: player
        g.fire("OnLoadRadioScripts", g.MANAGER, True)
        assert lua_list(g.REMOVED_NAMES) == [145000], "nom de chaîne non retiré"

        assert g.talk(player, "Ici Kate, à Riverside.") == "ok"
        assert lua_list(player.said) == ["Ici Kate, à Riverside."], lua_list(player.said)
        assert g.talk(player, "encore") == "grisee", "deuxième message accepté pendant l'attente"
        tick = lambda: g.fire("OnTick")
        assert pump(lambda: len(g.BROADCASTS) == 1, [tick]), "aucune diffusion"
        lines = lua_list(g.BROADCASTS[1])
        assert lines[0] == "<bzzt>" and "Ici Kate, à Riverside." in " ".join(lines), lines
        assert len(player.halos) == 0, lua_list(player.halos)
        g.finishAiring()
        # Écart du client aligné sur le délai du serveur (PlayerCooldown 10 s + marge 1 s, essai solo du 2026-10-09) :
        # option grisée avec le motif « Vous parlez sans arrêt » à 6 s (l'ancien écart de 5 s laissait partir la
        # phrase, refusée en rouge Cooldown par le serveur), jamais de refus rouge ; après 11 s la phrase part et le
        # serveur l'accepte.
        assert g.talk(player, "Trop vite") == "grisee"
        clock.offset += 6000
        assert g.talk(player, "Tu es là ?") == "grisee"
        assert len(player.halos) == 0, lua_list(player.halos)
        assert len(player.said) == 1
        pump(lambda: False, [tick], timeout=0.5)
        req = (exchange / "requests.txt").read_text(encoding="utf-8")
        assert "req=" not in req and req.rstrip().endswith("end"), req
        clock.offset += 5100
        assert g.talk(player, "Tu es là ?") == "ok"
        assert len(player.halos) == 0, lua_list(player.halos)
        assert lua_list(player.said)[-1] == "Tu es là ?", lua_list(player.said)
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_multiplayer(tmp: Path) -> None:
    exchange = tmp / "mp"
    exchange.mkdir()
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        server = Game("server", exchange, clock)
        server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
        sg = server.g
        clients = {}
        broadcasts = []

        def to_client(*args):
            if len(args) == 3:  # sendServerCommand(module, command, args) : tous les clients
                broadcasts.append(args[1])
                targets = list(clients.values())
            else:
                targets = [clients[args[0].username]]
                args = args[1:]
            for c in targets:
                c.g.fire("OnServerCommand", args[0], args[1], c.table(args[2]))

        sg.sendServerCommand = to_client
        sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
        # Aucune annonce aux clients, ni au chargement (réseau pas démarré : NPE en jeu), ni ensuite (E05-T08).
        assert broadcasts == [], broadcasts
        for name in ("alice", "bob"):
            c = Game("client", exchange, clock)
            # Le dossier server/ est aussi lu par un client : sa garde doit l'arrêter.
            c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
                   "client/RadioSurvivor_Client.lua")
            player = c.g.makePlayer(name)
            c.g.getPlayer = lambda p=player: p
            c.g.getSpecificPlayer = lambda n, p=player: p
            sg.makePlayer(name)
            clients[name] = c
            assert len(c.g.Events.OnClientCommand.list) == 0, "le fichier serveur s'exécute sur le client"

        def to_server(c, name):
            return lambda p, m, cmd, a: sg.fire("OnClientCommand", m, cmd, sg.PLAYERS[name], server.table(a))

        for name, c in clients.items():
            c.g.sendClientCommand = to_server(c, name)
            # Le client ne reçoit ni ne garde aucune liste de fréquences (E05-T08).
            assert c.g.require("RadioSurvivor/RadioSurvivor_Const").talkFrequencies is None

        alice, bob = clients["alice"].g.PLAYERS["alice"], clients["bob"].g.PLAYERS["bob"]
        assert clients["alice"].g.talk(alice, "Alice ici, tu me reçois ?") == "ok"
        assert clients["bob"].g.talk(bob, "Bob à l'appareil, je suis à Muldraugh.") == "ok"
        # Phrase prononcée par le chat (« dire »), pas par Say, et seulement après acceptation.
        assert lua_list(clients["alice"].g.SAID_CHAT) == ["Alice ici, tu me reçois ?"]
        assert lua_list(clients["bob"].g.SAID_CHAT) == ["Bob à l'appareil, je suis à Muldraugh."]
        assert len(alice.said) == 0

        tick = lambda: sg.fire("OnTick")
        assert pump(lambda: len(sg.BROADCASTS) == 1, [tick]), "aucune diffusion"
        # Les deux réponses arrivent presque ensemble : la seconde attend la fin de la première.
        pump(lambda: False, [tick], timeout=1.0)
        assert len(sg.BROADCASTS) == 1, "une réponse a coupé l'autre"
        sg.finishAiring()
        assert pump(lambda: len(sg.BROADCASTS) == 2, [tick]), "seconde réponse jamais diffusée"
        aired = " ".join(" ".join(lua_list(b)) for b in lua_list(sg.BROADCASTS))
        assert "Alice ici" in aired and "Muldraugh" in aired, aired

        # Radio rangée dans un sac côté serveur : refus, message affiché chez le bon client seulement.
        sg.finishAiring()
        clock.offset += 11000  # après le délai entre deux messages
        assert broadcasts == [], broadcasts
        sg.PLAYERS["bob"].inHand = False
        sg.PLAYERS["bob"].radio.container = {}
        assert clients["bob"].g.talk(bob, "Toujours là ?") == "ok"
        assert lua_list(bob.halos) == ["IGUI_RadioSurvivor_Reject_NoRadio"], lua_list(bob.halos)
        assert len(alice.halos) == 0
        # Talkie à la ceinture côté serveur (inventaire principal, accroché, ni en main ni sur le dos) : refusé par le
        # serveur aussi (décision 4 de Belt Walkie-Talkie, BatmanRadioSupport.canTransmitWith), même si le client le
        # croit en main.
        sg.PLAYERS["bob"].radio.container = sg.PLAYERS["bob"].inventory
        sg.PLAYERS["bob"].attached = sg.PLAYERS["bob"].radio
        clients["bob"].g.require("RadioSurvivor/RS_RadioTalk").resetForTests()
        assert clients["bob"].g.talk(bob, "Bob, talkie à la ceinture.") == "ok"
        assert lua_list(bob.halos) == ["IGUI_RadioSurvivor_Reject_NoRadio"] * 2, lua_list(bob.halos)
        assert "Bob, talkie à la ceinture." not in (exchange / "requests.txt").read_text(encoding="utf-8")
        # Repris en main : accepté (itemId).
        sg.PLAYERS["bob"].attached = None
        sg.PLAYERS["bob"].inHand = True
        clients["bob"].g.require("RadioSurvivor/RS_RadioTalk").resetForTests()
        assert clients["bob"].g.talk(bob, "Bob, talkie en main.") == "ok"
        assert len(bob.halos) == 2, lua_list(bob.halos)
        assert "Bob, talkie en main." in (exchange / "requests.txt").read_text(encoding="utf-8")

        history = list(exchange.glob("history_*.json"))
        assert len(history) == 1, history
        text = history[0].read_text(encoding="utf-8")
        assert '"alice": 1' in text and '"bob": 2' in text, text
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_drawn_frequency(tmp: Path) -> None:
    """E05-T07 : vraie fiche de Walt (frequency_range=130.0-149.8). Monde neuf : fréquence tirée dans la plage,
    mémorisée dans le fichier de la partie ; le pont répond par l'identifiant de voix (voice=walt), sans connaître
    la fréquence ; redémarrage du même monde : même fréquence, aucun nouveau tirage."""
    exchange = tmp / "drawn"
    exchange.mkdir()
    bridge = start_bridge(exchange)
    try:
        def start(new_game: bool):
            game = Game("solo", exchange, Clock(), drawn=True)
            game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
                      "client/RadioSurvivor_Client.lua")
            g = game.g
            g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
            player = g.makePlayer("Kate")
            g.getPlayer = lambda: player
            g.getSpecificPlayer = lambda n: player
            g.fire("OnLoadRadioScripts", g.MANAGER, new_game)
            return g, player

        g, player = start(True)
        khz = int(lua_list(g.require("RadioSurvivor/RS_Personas").served("walt"))[0])
        assert 130000 <= khz <= 149800 and khz % 200 == 0, khz
        assert lua_list(g.REMOVED_NAMES) == [khz]
        memory = list(exchange.glob("frequencies-*.txt"))
        assert len(memory) == 1, memory
        assert memory[0].read_text(encoding="utf-8") == f"RSFREQ1\nwalt 130000-149800 {khz}\n", memory[0].read_text()
        player.radio.device.channel = khz
        assert g.talk(player, "Walt ?") == "ok"
        request = (exchange / "requests.txt").read_text(encoding="utf-8")
        assert "voice=walt" in request and str(khz) not in request, request
        tick = lambda: g.fire("OnTick")
        assert pump(lambda: len(g.BROADCASTS) == 1, [tick]), "aucune diffusion"
        assert lua_list(g.AIRED_ON) == [khz], lua_list(g.AIRED_ON)

        g2, _ = start(False)
        assert int(lua_list(g2.require("RadioSurvivor/RS_Personas").served("walt"))[0]) == khz
        assert not any(" drew " in line for line in lua_list(g2.LOGS)), lua_list(g2.LOGS)
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_no_bridge(tmp: Path) -> None:
    exchange = tmp / "nobridge"
    exchange.mkdir()
    clock = Clock()
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    assert g.talk(player, "Allô ?") == "ok"
    clock.offset += 91000
    g.fire("OnTick")
    assert lua_list(g.BROADCASTS[1]) == ["<fzzt>", "<szzt>"], lua_list(g.BROADCASTS[1])
    assert lua_list(player.halos) == ["IGUI_RadioSurvivor_Reject_NoAnswer"], lua_list(player.halos)
    assert any("no answer from the bridge" in line for line in lua_list(g.LOGS))
    # Pont absent : aucune action jugée ni exécutée (E07-T01).
    assert not any(" action " in line for line in lua_list(g.LOGS)), lua_list(g.LOGS)


def scenario_bridge_alive_radio(tmp: Path) -> None:
    """E17-T16 : pont vivant (battement bridge-alive.txt tenu à jour) : la radio de Walt l'attend
    Const.BRIDGE_TIMEOUT_MS (borne du pont MAX_AGE_S + LLM_BUDGET_S + marge) ; une réponse écrite 130 s après l'envoi
    est diffusée, sans refus NoAnswer avant ; pont vivant mais muet : refus après le long délai seulement ; client plus
    patient que le serveur. Sans battement : scenario_no_bridge (91 s)."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    exchange = tmp / "alive"
    exchange.mkdir()
    clock = Clock()
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "server/RadioSurvivor/RS_BridgeAlive.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    assert const.BRIDGE_TIMEOUT_MS >= (rb.MAX_AGE_S + rb.LLM_BUDGET_S) * 1000 + 5000, const.BRIDGE_TIMEOUT_MS
    assert const.CLIENT_TIMEOUT_MS > const.BRIDGE_TIMEOUT_MS, const.CLIENT_TIMEOUT_MS
    assert const.NO_BRIDGE_TIMEOUT_MS == 90000

    def run(ms: int) -> None:
        """Real time moves by ms, the bridge beating every 5 s (OnTickEvenPaused then OnTick, as in the game)."""
        for _ in range(ms // 5000):
            clock.offset += 5000
            rb.write_alive(exchange / rb.ALIVE_FILE, clock())
            g.fire("OnTickEvenPaused")
            g.fire("OnTick")

    rb.write_alive(exchange / rb.ALIVE_FILE, clock())
    g.fire("OnTickEvenPaused")
    assert const.TIMEOUT_MS == const.BRIDGE_TIMEOUT_MS, const.TIMEOUT_MS
    assert g.talk(player, "Allô ?") == "ok"
    rid = rb.read_requests(exchange / "requests.txt")[1][0]["id"]
    run(130000)
    assert len(g.BROADCASTS) == 0, lua_list(g.BROADCASTS[1])
    assert len(player.halos) == 0, lua_list(player.halos)
    (exchange / "responses.txt").write_text(f"resp={rid}\nline=Walt, I read you.\nend\n", encoding="utf-8")
    run(5000)
    assert lua_list(g.BROADCASTS[1]) == ["<bzzt>", "Walt, I read you."], lua_list(g.BROADCASTS[1])
    assert len(player.halos) == 0, lua_list(player.halos)
    (exchange / "responses.txt").write_text("end\n", encoding="utf-8")
    g.finishAiring()
    # Alive but silent: refused after the long delay only.
    clock.offset += 11000
    assert g.talk(player, "Toujours là ?") == "ok"
    run(145000)
    assert len(g.BROADCASTS) == 1 and len(player.halos) == 0, (len(g.BROADCASTS), lua_list(player.halos))
    run(10000)
    assert lua_list(player.halos) == ["IGUI_RadioSurvivor_Reject_NoAnswer"], lua_list(player.halos)
    # Bridge stopped (heartbeat removed): back to the short delay at the next read.
    rb.remove_alive(exchange / rb.ALIVE_FILE)
    clock.offset += 11000
    g.fire("OnTickEvenPaused")
    assert const.TIMEOUT_MS == const.NO_BRIDGE_TIMEOUT_MS, const.TIMEOUT_MS
    # Heartbeat left by a killed bridge: stale after ALIVE_STALE_MS, short delay again.
    rb.write_alive(exchange / rb.ALIVE_FILE, clock())
    clock.offset += 5000
    g.fire("OnTickEvenPaused")
    assert const.TIMEOUT_MS == const.BRIDGE_TIMEOUT_MS, const.TIMEOUT_MS
    clock.offset += const.ALIVE_STALE_MS + 1000
    g.fire("OnTickEvenPaused")
    assert const.TIMEOUT_MS == const.NO_BRIDGE_TIMEOUT_MS, const.TIMEOUT_MS
    # The real bridge (offline, own process) writes its heartbeat on the exchange folder at start.
    live = tmp / "alive-real"
    live.mkdir()
    bridge = start_bridge(live)
    try:
        assert pump(lambda: (live / rb.ALIVE_FILE).exists(), [], timeout=15), "no heartbeat from the bridge"
        stamp = int((live / rb.ALIVE_FILE).read_text(encoding="utf-8").strip().split("=", 1)[1])
        assert abs(stamp - time.time() * 1000) < 15000, stamp
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


# Seconde voix, propre au banc (aucune voix livrée en plus de Walt : E05-T04 reste à décider). Poste haut de gamme
# exigé, écoute de 20:00 à 23:00 (fin exclue), budget de 2 demandes par heure réelle, un secret.
BENCH_SECRET = "He left his sister Ada at the West Point pharmacy."
BENCH_SHEET = f"""format=1
id=bench
name=Bench Tester
frequencies=150.0
radio=high_tier
listen=20:00-23:00
knows=The Muldraugh bridge fell on the second night.
ignores=What happened in Ohio.
secret={BENCH_SECRET}
budget=2
[prompt]
You are Bench Tester, a voice of the offline test bench.
"""


def write_bench(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "bench.txt").write_text(BENCH_SHEET, encoding="utf-8")


def history_files(exchange: Path) -> dict[str, dict]:
    """Nom de fichier -> contenu des historiques radio du pont."""
    return {p.name: json.loads(p.read_text(encoding="utf-8")) for p in sorted(exchange.glob("history_*.json"))}


def scenario_two_voices(tmp: Path) -> None:
    """Serveur MP et deux clients : Walt (145.0) et la voix du banc (150.0) répondent chacun sur sa fréquence, en
    parallèle, sans mélanger leurs historiques ; poste ordinaire refusé par la voix high_tier ; heures d'écoute ;
    budget de la voix ; aucune donnée de la fiche (secret compris) chez les clients."""
    exchange = tmp / "voices"
    exchange.mkdir()
    write_bench(exchange)
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        server = Game("server", exchange, clock)
        server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
        sg = server.g
        clients, to_clients = {}, []

        def to_client(*args):
            if len(args) == 3:
                targets = list(clients.values())
            else:
                targets = [clients[args[0].username]]
                args = args[1:]
            to_clients.append(repr(dict(server.table(args[2]).items())) if args[2] is not None else "")
            for c in targets:
                c.g.fire("OnServerCommand", args[0], args[1], c.table(args[2]))

        sg.sendServerCommand = to_client
        sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
        for name, khz in (("alice", 145000), ("bob", 150000)):
            c = Game("client", exchange, clock)
            c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
            player = c.g.makePlayer(name)
            player.radio.device.channel = khz
            c.g.getPlayer = lambda p=player: p
            c.g.getSpecificPlayer = lambda n, p=player: p
            sg.makePlayer(name).radio.device.channel = khz
            c.g.sendClientCommand = (lambda n: lambda p, m, cmd, a: sg.fire(
                "OnClientCommand", m, cmd, sg.PLAYERS[n], server.table(a)))(name)
            clients[name] = c
        alice, bob = clients["alice"].g.PLAYERS["alice"], clients["bob"].g.PLAYERS["bob"]
        tick = lambda: sg.fire("OnTick")

        def requests() -> str:
            path = exchange / "requests.txt"
            return path.read_text(encoding="utf-8") if path.exists() else ""

        def next_turn():
            sg.finishAiring()
            clock.offset += 11000  # délai entre deux messages d'un joueur

        # Poste ordinaire sur la fréquence d'une voix high_tier : la phrase part, personne ne répond, rien au pont.
        assert clients["bob"].g.talk(bob, "Allo, poste ordinaire ?") == "ok"
        assert lua_list(clients["bob"].g.SAID_CHAT) == ["Allo, poste ordinaire ?"]
        assert "req=" not in requests() and len(bob.halos) == 0, (requests(), lua_list(bob.halos))
        assert pump(lambda: False, [tick], timeout=0.5) is False and len(sg.BROADCASTS) == 0
        # Écart du client (délai du serveur + marge, 11 s) levé pour le banc : le pont ignore une demande datée de
        # plus de 10 s dans le futur (horloge avancée). Cadence couverte par scenario_solo et test_radio_module.
        clock.offset += 6000
        clients["bob"].g.require("RadioSurvivor/RS_RadioTalk").resetForTests()

        # Poste haut de gamme : les deux voix répondent en même temps, chacune sur sa fréquence.
        sg.PLAYERS["bob"].radio.device.highTier = True
        assert clients["alice"].g.talk(alice, "Alice pour Walt.") == "ok"
        assert clients["bob"].g.talk(bob, "Bob pour le banc.") == "ok"
        text = requests()
        assert "voice=walt" in text and "voice=bench" in text, text
        assert pump(lambda: len(sg.BROADCASTS) == 2, [tick]), "les deux voix n'ont pas répondu ensemble"
        aired = {int(sg.AIRED_ON[i]): " ".join(lua_list(sg.BROADCASTS[i])) for i in (1, 2)}
        assert "Walt, hors ligne" in aired[145000] and "Alice pour Walt" in aired[145000], aired
        assert "Bench, hors ligne" in aired[150000] and "Bob pour le banc" in aired[150000], aired

        # Historiques séparés : celui de Walt garde son nom d'avant E05-T03 ; chaque voix numérote ses appelants.
        files = history_files(exchange)
        walt_file = [n for n in files if n.count("_") == 1]
        bench_file = [n for n in files if n.endswith("_bench.json")]
        assert len(files) == 2 and len(walt_file) == 1 and len(bench_file) == 1, list(files)
        walt_log, bench_log = files[walt_file[0]], files[bench_file[0]]
        assert walt_log["callers"] == {"alice": 1} and bench_log["callers"] == {"bob": 1}, (walt_log, bench_log)
        assert "Alice" in json.dumps(walt_log) and "Bob" not in json.dumps(walt_log), walt_log
        assert "Bob" in json.dumps(bench_log) and "Alice" not in json.dumps(bench_log), bench_log

        # Budget de la voix (2 par heure réelle) : la deuxième passe, la troisième n'obtient que le silence (un refus
        # « Busy » trahirait une voix, E05-T08) ; Walt n'est pas touché.
        next_turn()
        assert clients["bob"].g.talk(bob, "Deuxième appel.") == "ok"
        assert pump(lambda: len(sg.BROADCASTS) == 3, [tick]), "deuxième appel sans réponse"
        next_turn()
        assert clients["bob"].g.talk(bob, "Troisième appel.") == "ok"
        assert len(bob.halos) == 0 and "Troisième" not in requests(), (lua_list(bob.halos), requests())
        assert lua_list(clients["bob"].g.SAID_CHAT)[-1] == "Troisième appel."
        assert clients["alice"].g.talk(alice, "Walt, toujours là ?") == "ok"
        assert pump(lambda: len(sg.BROADCASTS) == 4, [tick]), "Walt bloqué par le budget d'une autre voix"
        # Une heure réelle plus tard, le budget est rendu ; hors des heures d'écoute (23:00, fin exclue) : silence.
        next_turn()
        clock.offset += 3600000
        sg.HOUR = 23
        assert clients["bob"].g.talk(bob, "Trop tard ?") == "ok"
        assert "Trop tard" not in requests() and len(bob.halos) == 0, requests()
        sg.HOUR = 22
        next_turn()
        assert clients["bob"].g.talk(bob, "Encore à l'écoute ?") == "ok"
        assert pump(lambda: len(sg.BROADCASTS) == 5, [tick]), "voix muette pendant ses heures d'écoute"
        assert int(sg.AIRED_ON[5]) == 150000

        # Fréquence hors de portée de la radio (bornes du script) : silence, même si le client l'envoie.
        next_turn()
        sg.PLAYERS["bob"].radio.device.maxCh = 148000
        assert clients["bob"].g.talk(bob, "Hors bande") == "ok"
        assert len(bob.halos) == 0 and "Hors bande" not in requests(), (lua_list(bob.halos), requests())

        # Rien de la fiche ne part chez les clients ni sur la radio : ni secret, ni connaissances, ni prompt.
        heard = " ".join(" ".join(lua_list(b)) for b in lua_list(sg.BROADCASTS)) + " ".join(to_clients)
        for private in (BENCH_SECRET, "Muldraugh bridge", "Ohio", "offline test bench"):
            assert private not in heard, private
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_server_sorts(tmp: Path) -> None:
    """E05-T08 : le serveur trie. Serveur MP et deux clients, Walt à fréquence tirée (vraie fiche) et la voix du banc
    (150.0). Aucun message serveur -> client ne porte une fréquence de voix ; une phrase sur la fréquence de Walt
    obtient sa réponse ; sur une fréquence sans voix, la phrase part et rien d'autre (ni message, ni demande au pont,
    ni diffusion) ; l'ancienne demande de liste reste sans réponse ; un client modifié qui inonde le serveur est
    limité, sans rien coûter au pont."""
    exchange = tmp / "sorts"
    exchange.mkdir()
    write_bench(exchange)
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        server = Game("server", exchange, clock, drawn=True)
        server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
        sg = server.g
        clients, to_clients = {}, []

        def to_client(*args):
            if len(args) == 3:  # sendServerCommand(module, command, args) : tous les clients
                targets = list(clients.values())
                to_clients.append(("*", args[1]))
            else:
                targets = [clients[args[0].username]]
                args = args[1:]
            payload = server.table(args[2])
            to_clients.append((args[1], repr(dict(payload.items())) if payload is not None else ""))
            for c in targets:
                c.g.fire("OnServerCommand", args[0], args[1], c.table(args[2]))

        sg.sendServerCommand = to_client
        sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
        walt = int(lua_list(sg.require("RadioSurvivor/RS_Personas").served("walt"))[0])
        assert 130000 <= walt <= 149800, walt
        free = 160000  # aucune voix
        for name, khz in (("alice", walt), ("bob", free)):
            c = Game("client", exchange, clock)
            c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
                   "client/RadioSurvivor_Client.lua")
            player = c.g.makePlayer(name)
            player.radio.device.channel = khz
            c.g.getPlayer = lambda p=player: p
            c.g.getSpecificPlayer = lambda n, p=player: p
            sg.makePlayer(name).radio.device.channel = khz
            c.g.sendClientCommand = (lambda n: lambda p, m, cmd, a: sg.fire(
                "OnClientCommand", m, cmd, sg.PLAYERS[n], server.table(a)))(name)
            clients[name] = c
            c.g.fire("OnGameStart")
        alice, bob = clients["alice"].g.PLAYERS["alice"], clients["bob"].g.PLAYERS["bob"]
        tick = lambda: sg.fire("OnTick")

        def requests() -> str:
            path = exchange / "requests.txt"
            return path.read_text(encoding="utf-8") if path.exists() else ""

        # Fréquence sans voix : la phrase est prononcée (chat « dire »), puis plus rien.
        assert clients["bob"].g.talk(bob, "Quelqu'un sur 160 ?") == "ok"
        assert lua_list(clients["bob"].g.SAID_CHAT) == ["Quelqu'un sur 160 ?"]
        assert len(bob.halos) == 0 and "req=" not in requests(), (lua_list(bob.halos), requests())
        # Le client n'attend plus rien : après son écart (délai du serveur + marge, le même avec ou sans voix sur
        # la fréquence : rien n'en est révélé), il peut reparler. Écart levé pour le banc (le pont ignore une demande
        # datée de plus de 10 s dans le futur) ; cadence couverte par scenario_solo et test_radio_module.
        clock.offset += 6000
        clients["bob"].g.require("RadioSurvivor/RS_RadioTalk").resetForTests()
        assert clients["bob"].g.talk(bob, "Toujours personne ?") == "ok" and len(bob.halos) == 0

        # Fréquence tirée de Walt (connue du joueur par une note, E05-T09) : réponse sur cette fréquence.
        assert clients["alice"].g.talk(alice, "Walt, tu me reçois ?") == "ok"
        assert "voice=walt" in requests() and "Toujours personne" not in requests(), requests()
        assert pump(lambda: len(sg.BROADCASTS) == 1, [tick]), "Walt n'a pas répondu"
        assert lua_list(sg.AIRED_ON) == [walt], lua_list(sg.AIRED_ON)
        assert "Walt, hors ligne" in " ".join(lua_list(sg.BROADCASTS[1]))

        # Client antérieur qui demande la liste : aucune réponse.
        before = len(to_clients)
        sg.fire("OnClientCommand", "RadioSurvivor", "frequencies", sg.PLAYERS["bob"], None)
        assert len(to_clients) == before, to_clients[before:]

        # Client modifié qui inonde le serveur (sans l'écart du client) : limite par joueur, rien au pont.
        clock.offset += 61000
        answers = []
        for i in range(20):
            sent = len(to_clients)
            sg.fire("OnClientCommand", "RadioSurvivor", "talk", sg.PLAYERS["bob"],
                    server.rt.table_from({"text": f"spam {i}", "itemId": 4242, "channel": free}))
            answers.append(tuple(cmd for cmd, _ in to_clients[sent:]))
        limit = int(sg.require("RadioSurvivor/RadioSurvivor_Const").SPAM_MAX)
        assert answers[:limit] == [("accepted", "done")] * limit, answers
        assert answers[limit:] == [("rejected",)] * (20 - limit), answers
        assert "spam" not in requests(), requests()
        assert "IGUI_RadioSurvivor_Reject_Spam" in lua_list(bob.halos), lua_list(bob.halos)
        assert len(alice.halos) == 0  # les autres joueurs ne sont pas touchés

        # Aucune fréquence de voix chez les clients : ni dans les commandes reçues, ni dans leurs journaux.
        voices = [walt, 150000]
        secrets = [str(k) for k in voices] + [f"{k / 1000:.1f}" for k in voices]
        heard = " ".join(repr(m) for m in to_clients)
        for c in clients.values():
            heard += " ".join(lua_list(c.g.LOGS))
        for secret in secrets:
            assert secret not in heard, (secret, heard)
        assert not any(m[0] == "*" for m in to_clients), to_clients
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def call_game(exchange: Path, clock) -> Game:
    """Partie solo dont Walt (145.0) gagne chaque tirage d'appel spontané."""
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
    game.rt.execute('local n = 0; ZombRand = function(a, b) n = n + 1 if b then return a + n end return 0 end')
    game.g.fire("OnLoadRadioScripts", game.g.MANAGER, True)
    return game


def scenario_spontaneous_calls(tmp: Path) -> None:
    """E05-T05 : appel spontané de Walt. Pont actuel : texte écrit par le pont (hors ligne), gardé dans l'historique de
    la voix sans numéroter d'appelant. Pont absent : texte fixe après CALL_TIMEOUT_MS. Pont antérieur (kind
    radio_call inconnu) : demande ignorée sans erreur, une phrase de joueur reste servie, texte fixe à l'antenne."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb

    # Pont actuel (processus réel, --offline).
    exchange = tmp / "calls"
    exchange.mkdir()
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        game = call_game(exchange, clock)
        g = game.g
        g.fire("EveryHours")
        text = (exchange / "requests.txt").read_text(encoding="utf-8")
        assert "kind=radio_call\nvoice=walt\ndate=1993-07-12 21:05\nlanguage=EN\n" in text, text
        assert pump(lambda: len(g.BROADCASTS) == 1, [lambda: g.fire("OnTick")]), "no call aired"
        aired = lua_list(g.BROADCASTS[1])
        assert aired == ["<fzzt>", "Walt, appel général hors ligne. À vous.", "<szzt>"], aired
        history = history_files(exchange)
        assert list(history) == ["history_" + rb.hashlib.sha1(b"Multiplayer_TestWorld").hexdigest()[:16] + ".json"]
        log = next(iter(history.values()))
        assert log["callers"] == {} and log["messages"][0]["content"] == rb.CALL_MARK, log
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)

    # Prompt de l'appel : fiche sans ses secrets, langue de l'autorité, appel court sans fait inventé ni fréquence.
    write_bench(tmp / "calls-prompt")
    voices = rb.Voices(tmp / "calls-prompt" / "personas")
    seen = []
    saved_llm = rb.call_llm
    rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or "Anyone there? " + BENCH_SECRET
    try:
        lines = rb.spontaneous_call({}, rb.Conversations(tmp / "calls-prompt"), "s",
                                    {"id": "x", "kind": "radio_call", "voice": "bench", "date": "1993-07-12 21:00",
                                     "language": "FR"}, voices)
    finally:
        rb.call_llm = saved_llm
    system = seen[0][0]["content"]
    assert system.startswith("You are Bench Tester") and "Muldraugh bridge" in system, system
    assert BENCH_SECRET not in system and "Speak French" in system and "Never mention a frequency" in system, system
    assert seen[0][-1] == {"role": "user", "content": rb.CALL_MARK}, seen[0][-1]
    assert lines == [], lines  # secret cité mot pour mot : retenu, texte fixe côté serveur
    assert not list((tmp / "calls-prompt").glob("history_*.json"))

    # Pont absent : texte fixe de la fiche, composé par l'autorité, après le délai du pont.
    exchange = tmp / "calls-nobridge"
    exchange.mkdir()
    clock = Clock()
    game = call_game(exchange, clock)
    g = game.g
    g.fire("EveryHours")
    g.fire("OnTick")
    assert len(g.BROADCASTS) == 0
    clock.offset += 31000
    g.fire("OnTick")
    assert lua_list(g.BROADCASTS[1]) == ["<fzzt>", "IGUI_RadioSurvivor_Call|145.0", "<szzt>"], lua_list(g.BROADCASTS[1])

    # Pont antérieur à E05-T05 : sans la branche radio_call, la demande suit l'ancien chemin des kinds RSV2,
    # refusée par npc.unpack_request (kind inconnu) puis ignorée ; aucune réponse, aucune erreur.
    exchange = tmp / "calls-oldbridge"
    exchange.mkdir()
    write_bench(exchange)
    clock = Clock()
    game = call_game(exchange, clock)
    g = game.g
    g.fire("EveryHours")
    session, requests = rb.read_requests(exchange / "requests.txt")
    assert [r.get("kind") for r in requests] == ["radio_call"], requests
    old = rb.Bridge({"OFFLINE": "1", "OPENAI_MODEL": "offline"}, exchange)
    saved = rb.CALL_KIND
    rb.CALL_KIND = "kind-unknown-to-an-older-bridge"
    try:
        old._sync(session, requests)
        old.pool.shutdown(wait=True)
        assert old.answers == {} and old.started == set(), (old.answers, old.started)
    finally:
        rb.CALL_KIND = saved
    clock.offset += 31000
    g.fire("OnTick")
    assert lua_list(g.BROADCASTS[1]) == ["<fzzt>", "IGUI_RadioSurvivor_Call|145.0", "<szzt>"], lua_list(g.BROADCASTS[1])
    # Même pont actuel : un échec du LLM sur un appel rend une réponse vide (texte fixe côté serveur), pas des parasites.
    bridge = rb.Bridge({"OFFLINE": "1", "OPENAI_MODEL": "offline"}, exchange)
    bad = {"id": "1-2-call", "kind": "radio_call", "voice": "nobody", "sent": str(int(clock()))}
    bridge.current = {bad["id"]: bridge._token("s", bad)}
    bridge._handle("s", bad)
    assert bridge.answers == {"1-2-call": []}, bridge.answers
    bridge.pool.shutdown(wait=True)
    assert (exchange / "responses.txt").read_text(encoding="utf-8") == "resp=1-2-call\nend\n"


def scenario_bridge_voices(tmp: Path) -> None:
    """Pont seul : prompt construit depuis la fiche, Walt inchangé, secret retenu, voix sans fiche refusée."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    import persona_store
    offline = {"OFFLINE": "1"}
    req = {"caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5", "radio": "Walkie",
           "text": "Allo ?"}
    # Walt seul : son prompt est exactement le texte libre de sa fiche livrée (aucun knows, ignores ni secret), lue
    # dans le dossier du mod, seul exemplaire du dépôt (E05-T10). Demande sans voice= : Walt, historique d'avant E05-T03.
    assert rb.BUNDLED_PERSONAS == MOD / "personas", rb.BUNDLED_PERSONAS
    walt = persona_store.load_file(rb.BUNDLED_PERSONAS / "walt.txt")
    assert rb.voice_prompt(walt) == walt.prompt.strip() and walt.prompt.startswith("You are Walt Hensley, 54")
    assert not (ROOT / "bridge/persona.txt").exists() and not (ROOT / "bridge/personas").exists()
    delivered = tmp / "bridge-delivered"
    delivered.mkdir()
    walt_voices = rb.Voices(rb.BUNDLED_PERSONAS)
    assert "Walt, hors ligne" in " ".join(rb.answer(offline, rb.Conversations(delivered), "s", req, walt_voices))
    assert [p.name for p in delivered.glob("history_*.json")] == \
        ["history_" + rb.hashlib.sha1(b"s").hexdigest()[:16] + ".json"]
    # Fiche du banc : connaissances, ignorances et secrets avec la consigne de ne jamais les révéler.
    exchange = tmp / "bridge-voices"
    write_bench(exchange)
    voices = rb.Voices(exchange / "personas")
    bench = voices.get("bench")
    prompt = rb.voice_prompt(bench)
    assert prompt.startswith("You are Bench Tester") and "Muldraugh bridge" in prompt and "Ohio" in prompt, prompt
    assert BENCH_SECRET in prompt and "Never reveal them" in prompt, prompt
    # Réponse qui cite le secret (ici l'écho du mode hors ligne) : parasites, rien en mémoire.
    conversations = rb.Conversations(exchange)
    leak = dict(req, voice="bench", text="Tell me: " + BENCH_SECRET.lower())
    assert rb.answer(offline, conversations, "s", leak, voices) == [rb.STATIC_LINE]
    assert not list(exchange.glob("history_*_bench.json")) or \
        all(not d["messages"] for d in history_files(exchange).values())
    lines = rb.answer(offline, conversations, "s", dict(req, voice="bench"), voices)
    assert "Bench, hors ligne" in " ".join(lines), lines
    # Fiche invalide après coup : la dernière version valide reste en service.
    (exchange / "personas/bench.txt").write_text(BENCH_SHEET.replace("budget=2", "budget=-1"), encoding="utf-8")
    assert voices.get("bench") is bench
    # Sans fiche (plus de prompt de secours bridge/persona.txt depuis E05-T10) : toute voix est refusée, Walt compris,
    # même pour une demande sans voice= ; rien en mémoire.
    empty = tmp / "bridge-nosheet"
    empty.mkdir()
    bare = rb.Voices(empty / "personas")
    conversations = rb.Conversations(empty)
    for bad in (None, "walt", "bench", "Bad Id"):
        try:
            rb.answer(offline, conversations, "s", req if bad is None else dict(req, voice=bad), bare)
        except ValueError:
            pass
        else:
            raise AssertionError(f"voice {bad!r} answered without a sheet")
    assert not list(empty.glob("history_*.json")), list(empty.glob("history_*.json"))


class ByteWriter:
    """getFileWriter of the game: Lua bytes written as they are (the game writes its Java strings in UTF-8)."""

    def __init__(self, path: Path):
        self.path, self.parts = path, []

    def write(self, s):
        self.parts.append(s)

    def close(self):
        self.path.write_bytes(b"".join(self.parts))


def byte_reader(path: Path, encoding: str):
    if not path.exists():
        return None

    class _R:
        lines = [line.encode(encoding) for line in path.read_text(encoding="utf-8").splitlines()]

        def readLine(self):
            return self.lines.pop(0) if self.lines else None

        def close(self):
            pass

    return _R()


def npc_exchange(exchange: Path, utf16: bool) -> None:
    """Accented player text: RS_Transport (Lua) -> bridge --offline -> RS_Transport, without refusal or mojibake.

    utf16=False: lupa as is (Lua strings = UTF-8 bytes). utf16=True: RS_Codec forced into its Kahlua branch, where a
    Lua string holds one character per UTF-16 unit; under lupa only U+0000-U+00FF exist, so the game text is given
    in Latin-1 (one byte per character) and must come back in Latin-1. Units above U+00FF: tests/test_kahlua.py.
    """
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange.mkdir()
    game_encoding = "latin-1" if utf16 else "utf-8"
    rt = lupa.LuaRuntime(encoding=None, unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute(b"isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: ByteWriter(exchange / Path(name.decode()).name)
    g.getFileReader = lambda name, create: byte_reader(exchange / Path(name.decode()).name, game_encoding)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path".encode())
    codec = rt.eval(b'require("RadioSurvivor/RS_Codec")')
    codec[b"_utf16"] = True if utf16 else None
    try:
        transport = rt.eval(b'require("RadioSurvivor/RS_Transport")')
        text = "Ça va ? Où êtes-vous, près de l'église ? Réponse « vite »." if utf16 else \
            "L’abri coûte 5 €, œuvre d’été \U0001F4FB, ça va ?"
        req = {"version": 2, "kind": "npc_talk", "id": "run-a-npc-a-1", "world": "world-a", "run": "run-a",
               "npc": "npc-a", "character": "character-a", "order": 1, "revision": 1,
               "sent": int(time.time() * 1000), "channel": "say", "language": "FR", "text": text,
               "personality": {"style": "Prudent"}, "context": {"name": "Hélène"},
               "offers": {"first_aid_v1": {"quantity": 6, "durationMs": 7200000, "rewardCount": 20}}}

        def lua(value):
            if isinstance(value, dict):
                return rt.table_from({lua(k): lua(v) for k, v in value.items()})
            return value.encode(game_encoding) if isinstance(value, str) else value

        transport.npc = rt.table_from([lua(req)])
        transport.session = b"Multiplayer_test"
        assert transport.write()
        # Lua -> Python: the bridge's strict UTF-8 decoder reads the exact text.
        sent = (exchange / "requests.txt").read_text(encoding="utf-8")
        payload = next(line[8:] for line in sent.splitlines() if line.startswith("payload="))
        record = {"id": req["id"], "kind": "npc_talk", "payload": payload}
        assert protocol.unpack_request(record) == req, protocol.unpack_request(record)
        bridge = start_bridge(exchange)
        try:
            responses = exchange / "responses.txt"
            assert pump(lambda: responses.exists() and f"resp={req['id']}" in responses.read_text(encoding="utf-8"),
                        []), "aucune réponse du pont (demande refusée ?)"
        finally:
            bridge.terminate()
            bridge.communicate(timeout=10)
        # Python -> Lua: the reply is read back as game text.
        answers = transport.readNpc()
        assert answers is not None, "réponses illisibles"
        reply = answers[req["id"].encode()]
        assert reply is not None and reply[b"error"] is None, "réponse refusée"
        expected = protocol.offline(req)["text"]
        assert any(ord(c) > 127 for c in expected), expected
        assert reply[b"text"] == expected.encode(game_encoding), (reply[b"text"], expected)
    finally:
        codec[b"_utf16"] = None


def scenario_accented_npc_exchange(tmp: Path) -> None:
    npc_exchange(tmp / "accents-lupa", utf16=False)
    npc_exchange(tmp / "accents-utf16", utf16=True)


def scenario_npc_observations(tmp: Path) -> None:
    """E08-T02, champ observations= d'une demande PNJ : écrit par le vrai RS_Transport (RSV2), relu à l'identique par
    npc_protocol.unpack_request, demande admise par le pont --offline (réponse) ; un champ hors contrat fait ignorer la
    demande (aucune réponse) ; prompt : section de souvenirs non vérifiés, absente sans observation. Le modèle côté
    serveur (bornes, chaîne, boucles, purge, persistance) : tests/test_observations.py."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "npc-observations"
    exchange.mkdir()
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute("isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: file_writer(exchange / Path(name).name, name, append)
    g.getFileReader = lambda name, create: Reader(exchange / Path(name).name)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path")
    transport = rt.eval('require("RadioSurvivor/RS_Transport")')
    observations = [
        {"fact": "assault_seen", "subject": "character-a", "day": 3, "place": "près de l'église", "source": "heard",
         "hops": 2, "who": "Alice Doe", "teller": "Paul"},
        {"fact": "helicopter", "subject": "sky", "day": 4, "place": "area-39-38", "source": "seen", "hops": 0},
    ]

    def request(n: int, field) -> dict:
        req = {"version": 2, "kind": "npc_talk", "id": f"run-o-npc-o-{n}", "world": "world-o", "run": "run-o",
               "npc": f"npc-o{n}", "character": "character-a", "order": 1, "revision": 1,
               "sent": int(time.time() * 1000), "channel": "say", "language": "EN", "text": "Any news?",
               "personality": {"style": "Prudent"}, "context": {"name": "Paul"}, "offers": {}}
        if field is not None:
            req["observations"] = field
        return req

    def lua(value):
        if isinstance(value, list):
            value = dict(enumerate(value, 1))
        if isinstance(value, dict):
            return rt.table_from({k: lua(v) for k, v in value.items()})
        return value

    good, bad = request(1, observations), request(2, [dict(observations[1], place="10234,9876")])
    transport.npc = rt.table_from([lua(good), lua(bad)])
    transport.session = "Multiplayer_test"
    assert transport.write()
    sent = (exchange / "requests.txt").read_text(encoding="utf-8")
    payloads = [line[8:] for line in sent.splitlines() if line.startswith("payload=")]
    unpacked = protocol.unpack_request({"id": good["id"], "kind": "npc_talk", "payload": payloads[0]})
    assert unpacked == good, unpacked
    try:
        protocol.unpack_request({"id": bad["id"], "kind": "npc_talk", "payload": payloads[1]})
        raise AssertionError("exact coordinates admitted")
    except ValueError:
        pass
    system = protocol.prompt(unpacked, [])[0]["content"]
    assert "Your own observations (unverified memories" in system and "never proof" in system, system
    assert "- day 3, près de l'église: an assault; subject character-a (Alice Doe); told by Paul, retold 2 times." \
        in system, system
    bare = dict(unpacked)
    del bare["observations"]
    assert "Your own observations" not in protocol.prompt(bare, [])[0]["content"]
    bridge = start_bridge(exchange)
    try:
        responses = exchange / "responses.txt"
        assert pump(lambda: responses.exists() and f"resp={good['id']}" in responses.read_text(encoding="utf-8"),
                    []), "aucune réponse du pont (demande avec observations refusée ?)"
        time.sleep(0.3)
        assert f"resp={bad['id']}" not in responses.read_text(encoding="utf-8"), "out-of-contract field answered"
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_relation_change(tmp: Path) -> None:
    """E09-T04, intention change_relation : champ context.relation écrit par le vrai RS_Transport (RSV2) et relu par
    npc_protocol.unpack_request ; prompt (niveau personnel en libellé, faits citables par identifiant court, règle « une
    phrase seule ne prouve rien », section absente sans relation) ; bounded_reply : fait offert dans le sens de sa nature
    seulement, offre vide, champs dir/fact refusés sans l'intention ; model_reply : un changement hors contrat garde la
    parole sans effet ; pont --offline avec le drapeau du banc relation : réponse avec dir et fact (jamais tirée des mots
    du joueur). Le côté serveur (vérification du fait, révision, borne) : tests/test_relations.py."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "relation-change"
    exchange.mkdir()
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute("isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: file_writer(exchange / Path(name).name, name, append)
    g.getFileReader = lambda name, create: Reader(exchange / Path(name).name)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path")
    transport = rt.eval('require("RadioSurvivor/RS_Transport")')
    relation = {"level": "favorable", "trend": "up", "group": "cautious",
                "facts": [{"id": "f1", "fact": "gift", "nature": "good", "source": "group", "day": 3},
                          {"id": "f2", "fact": "assault_seen", "nature": "bad", "source": "seen", "day": 4}]}

    def request(n: int, rel) -> dict:
        req = {"version": 2, "kind": "npc_talk", "id": f"run-r-npc-r-{n}", "world": "world-r", "run": "run-r",
               "npc": f"npc-r{n}", "character": "character-a", "order": 1, "revision": 1,
               "sent": int(time.time() * 1000), "channel": "say", "language": "EN", "text": "Remember me?",
               "personality": {"style": "Direct"}, "context": {"name": "Paul"}, "offers": {}}
        if rel is not None:
            req["context"]["relation"] = rel
        return req

    def lua(value):
        if isinstance(value, list):
            value = dict(enumerate(value, 1))
        if isinstance(value, dict):
            return rt.table_from({k: lua(v) for k, v in value.items()})
        return value

    good = request(1, relation)
    transport.npc = rt.table_from([lua(good)])
    transport.session = "Multiplayer_test"
    assert transport.write()
    sent = (exchange / "requests.txt").read_text(encoding="utf-8")
    payload = [line[8:] for line in sent.splitlines() if line.startswith("payload=")][0]
    unpacked = protocol.unpack_request({"id": good["id"], "kind": "npc_talk", "payload": payload})
    assert protocol.relation_facts(unpacked) == {"f1": "up", "f2": "down"}, unpacked["context"]
    system = protocol.prompt(unpacked, [])[0]["content"]
    assert "Your personal relation with this character: favorable (trend up; your group's attitude toward them: " \
           "cautious)" in system, system
    assert "never because of words alone" in system and "fact = its exact id (f1, f2)" in system, system
    assert "plus dir and fact for intent change_relation only" in system
    # Relation without citable fact: level only, never the intent; no relation: section absent (prompt unchanged).
    bare = request(2, {"level": "wary", "trend": "stable", "group": "wary", "facts": {}})
    text = protocol.prompt(bare, [])[0]["content"]
    assert "Your personal relation with this character: wary" in text and "never use intent change_relation" in text
    assert "Your personal relation" not in protocol.prompt(request(3, None), [])[0]["content"]
    assert protocol.relation_facts(bare) == {} and protocol.relation_facts(request(3, None)) == {}
    # bounded_reply: a fact offered, in the direction of its nature, offer empty.
    ok = protocol.bounded_reply(unpacked, {"text": "Thanks again.", "intent": "change_relation", "dir": "up",
                                           "fact": "f1"})
    assert (ok["intent"], ok["dir"], ok["fact"], ok["offer"]) == ("change_relation", "up", "f1", ""), ok
    for wrong, why in (({"dir": "down", "fact": "f1"}, "inadmissible relation change"),
                       ({"dir": "up", "fact": "f2"}, "inadmissible relation change"),
                       ({"dir": "up", "fact": "f9"}, "inadmissible relation change"),
                       ({"dir": "up"}, "inadmissible relation change"),
                       ({"dir": "up", "fact": "f1", "offer": "first_aid_v1"}, "inadmissible offer")):
        try:
            protocol.bounded_reply(unpacked, dict({"text": "Hm.", "intent": "change_relation"}, **wrong))
            raise AssertionError(f"admitted: {wrong}")
        except ValueError as err:
            assert str(err) == why, (wrong, err)
    for req, fields, why in ((bare, {"intent": "change_relation", "dir": "up", "fact": "f1"}, "no relation fact to cite"),
                             (unpacked, {"intent": "none", "dir": "up", "fact": "f1"}, "relation fields without intent")):
        try:
            protocol.bounded_reply(req, dict({"text": "Hm."}, **fields))
            raise AssertionError(f"admitted: {fields}")
        except ValueError as err:
            assert str(err) == why, (fields, err)
    # Empty dir/fact beside another intent are dropped (models fill every key).
    plain = protocol.bounded_reply(unpacked, {"text": "Hi.", "intent": "none", "dir": "", "fact": None})
    assert "dir" not in plain and "fact" not in plain, plain
    # model_reply: a change outside the contract keeps the speech only, without effect.
    reply, reason = protocol.model_reply(unpacked, '{"text": "You lied.", "intent": "change_relation", "dir": "down", '
                                                   '"fact": "f1"}')
    assert (reply["intent"], reason, "dir" in reply) == ("none", "inadmissible relation change", False), (reply, reason)
    reply, reason = protocol.model_reply(unpacked, 'Sure. {"text": "I saw you.", "intent": "change_relation", '
                                                   '"dir": "down", "fact": "f2"}')
    assert (reply["intent"], reply["dir"], reply["fact"], reason) == ("change_relation", "down", "f2", ""), reply
    # Offline bench flag: last fact offered in its direction, or the one named; never read from the text.
    assert protocol.offline(unpacked, "relation")["fact"] == "f2"
    assert (protocol.offline(unpacked, "relation:up")["dir"], protocol.offline(unpacked, "relation:f1")["fact"]) == \
        ("up", "f1")
    assert protocol.offline(bare, "relation")["intent"] == "none"
    assert protocol.offline(unpacked, "")["intent"] == "none"
    bridge = start_bridge(exchange, "relation:up")
    try:
        responses = exchange / "responses.txt"
        assert pump(lambda: responses.exists() and f"resp={good['id']}" in responses.read_text(encoding="utf-8"),
                    []), "aucune réponse du pont à une demande avec relation"
        lines = responses.read_text(encoding="utf-8").splitlines()
        answer = protocol.decode(bytes.fromhex(lines[lines.index(f"resp={good['id']}") + 1][8:]))
        assert (answer["intent"], answer["dir"], answer["fact"]) == ("change_relation", "up", "f1"), answer
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


def scenario_scout_offer(tmp: Path) -> None:
    """E11-T03, offre et contexte du gabarit `scout` : écrits par le vrai RS_Transport (RSV2, indices en liste Lua),
    relus à l'identique par npc_protocol.unpack_request ; le pont --offline propose `scout_v1` seul avec un texte de
    reconnaissance, et la même demande avec M01 garde le choix déterministe de `first_aid_v1` ; le prompt porte les
    indices sans aucune coordonnée. Le modèle côté serveur (lieu, sondage, compte rendu) : tests/test_carnet.py."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "scout-offer"
    exchange.mkdir()
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute("isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: file_writer(exchange / Path(name).name, name, append)
    g.getFileReader = lambda name, create: Reader(exchange / Path(name).name)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path")
    transport = rt.eval('require("RadioSurvivor/RS_Transport")')
    clues = {1: "The place is a single-storey house.", 2: "There is a gas station a short walk to the north."}
    scout = {"kind": "scout", "place": "house", "clues": clues, "report": "in_person", "durationMs": 7200000,
             "rewardType": "Base.Bullets9mm", "rewardCount": 20}
    req = {"version": 2, "kind": "npc_talk", "id": "run-s-npc-s-1", "world": "world-s", "run": "run-s",
           "npc": "npc-s", "character": "character-a", "order": 1, "revision": 1,
           "sent": int(time.time() * 1000), "channel": "say", "language": "EN", "text": "Need anything?",
           "personality": {"style": "Prudent"},
           "context": {"name": "Paul", "mission": {"state": "active", "kind": "scout", "place": "house",
                                                   "clues": clues, "zoneReached": False, "report": "in_person",
                                                   "remainingMs": 7200000, "rewardType": "Base.Bullets9mm",
                                                   "rewardCount": 20}},
           "offers": {"scout_v1": scout}}

    def lua(value):
        if isinstance(value, dict):
            return rt.table_from({k: lua(v) for k, v in value.items()})
        return value

    transport.npc = rt.table_from([lua(req)])
    transport.session = "Multiplayer_test"
    assert transport.write()
    sent = (exchange / "requests.txt").read_text(encoding="utf-8")
    payload = next(line[8:] for line in sent.splitlines() if line.startswith("payload="))
    unpacked = protocol.unpack_request({"id": req["id"], "kind": "npc_talk", "payload": payload})
    assert unpacked == req, unpacked
    reply = protocol.offline(unpacked)
    assert (reply["intent"], reply["offer"]) == ("offer", "scout_v1"), reply
    assert "come back and tell me in person" in reply["text"] and "120 minutes" in reply["text"], reply["text"]
    fr = protocol.offline(dict(unpacked, language="FR", text="Besoin de quelque chose ?"))  # E17-T07: sentence language
    assert "revenez me le raconter en personne" in fr["text"], fr["text"]
    both = dict(unpacked, offers={"first_aid_v1": {"quantity": 6, "durationMs": 7200000, "rewardCount": 20},
                                  "scout_v1": scout})
    assert protocol.offline(both)["offer"] == "first_aid_v1", "deterministic M01 choice changed"
    system = protocol.prompt(unpacked, [])[0]["content"]
    assert "a gas station a short walk to the north" in system and '"zoneReached": false' in system, system
    context = system.split("Authoritative context: ", 1)[1]
    assert not re.search(r"\d{3}", context.replace("7200000", "")), "a coordinate reached the prompt"


def scenario_supply_offer(tmp: Path) -> None:
    """E17-T03, offre M01 tirée d'un besoin réel d'un groupe Living Knox (kind = supply, points de valeur) et contexte
    public du groupe : écrits par le vrai RS_Transport (RSV2), relus à l'identique par npc_protocol.unpack_request ;
    le pont --offline annonce le besoin, le nombre de points, le délai et le lot (ou son absence) en anglais et en
    français ; le prompt porte le résumé public sans foyer. Parcours complet avec le vrai moteur : tests/test_carnet.py
    (LivingKnoxCarnetTests)."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "supply-offer"
    exchange.mkdir()
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute("isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: file_writer(exchange / Path(name).name, name, append)
    g.getFileReader = lambda name, create: Reader(exchange / Path(name).name)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path")
    transport = rt.eval('require("RadioSurvivor/RS_Transport")')
    supply = {"kind": "supply", "unit": "value", "need": "food", "level": 20, "quantity": 60, "durationMs": 7200000,
              "accepted": {"Base.TinnedBeans": True, "Base.Rice": True},
              "values": {"Base.TinnedBeans": 2, "Base.Rice": 2}, "rewardType": "Base.Antibiotics", "rewardCount": 2,
              "noRefund": True, "supplier": "grp-1", "supply": "grp-1-food-1"}
    group = {"member": True, "group": "Ada Holt", "type": "settlers", "summary": "They met at the mill.",
             "leaderName": "Ada Holt", "isLeader": True, "role": "worker", "morale": 60, "alive": 3,
             "needs": {"food": 20, "medical": 80, "ammo": 50}, "attitude": {"level": "cautious", "trend": "stable"}}
    req = {"version": 2, "kind": "npc_talk", "id": "run-l-npc-l-1", "world": "world-l", "run": "run-l",
           "npc": "npc-l", "character": "character-a", "order": 1, "revision": 1,
           "sent": int(time.time() * 1000), "channel": "say", "language": "EN", "text": "Need anything?",
           "personality": {"style": "Prudent"}, "context": {"name": "Ada Holt", "group": group},
           "offers": {"first_aid_v1": supply}}

    def lua(value):
        if isinstance(value, dict):
            return rt.table_from({k: lua(v) for k, v in value.items()})
        return value

    transport.npc = rt.table_from([lua(req)])
    transport.session = "Multiplayer_test"
    assert transport.write()
    sent = (exchange / "requests.txt").read_text(encoding="utf-8")
    payload = next(line[8:] for line in sent.splitlines() if line.startswith("payload="))
    unpacked = protocol.unpack_request({"id": req["id"], "kind": "npc_talk", "payload": payload})
    assert unpacked == req, unpacked
    reply = protocol.offline(unpacked)
    assert (reply["intent"], reply["offer"]) == ("offer", "first_aid_v1"), reply
    assert "short of food" in reply["text"] and "60 points" in reply["text"] and "120 minutes" in reply["text"], \
        reply["text"]
    assert "2 item(s) in return" in reply["text"], reply["text"]
    fr = protocol.offline(dict(unpacked, language="FR", text="Besoin de quelque chose ?"))  # E17-T07: sentence language
    assert "manque de nourriture" in fr["text"] and "60 points" in fr["text"], fr["text"]
    none = dict(unpacked, offers={"first_aid_v1": dict(supply, rewardType="", rewardCount=0)})
    assert "the group will remember" in protocol.offline(none)["text"]
    system = protocol.prompt(unpacked, [])[0]["content"]
    assert "They met at the mill." in system and '"need": "food"' in system, system
    assert "10637" not in system and "home" not in system


# E06-T03 : même monde dans chaque machine Lua (serveur et clients) : une radio HAM posée en 102, 200, 0 et un
# véhicule 17 avec une autoradio émettrice (pièce "Radio"). Les positions et places des joueurs sont posées par machine.
WORLD = r"""
local radioInstanceof = instanceof
instanceof = function(o, c)
    if type(o) == "table" and o.class ~= nil then return o.class == c end
    return radioInstanceof(o, c)
end
local function newData(khz)
    local d = { khz = khz }
    function d:getIsTwoWay() return true end
    function d:getIsTurnedOn() return true end
    function d:getMicIsMuted() return false end
    function d:getChannel() return self.khz end
    function d:getMinChannelRange() return 200 end
    function d:getMaxChannelRange() return 1000000 end
    function d:getIsHighTier() return false end
    function d:getMicRange() return 5 end
    function d:getDeviceName() return "Ham Radio" end
    return d
end
local SQ = { getX = function() return 102 end, getY = function() return 200 end, getZ = function() return 0 end }
HAM = { class = "IsoWaveSignal", data = newData(145000) }
function HAM:getDeviceData() return self.data end
function HAM:getSquare() return SQ end
function HAM:getObjectIndex() return 0 end
SQ.getObjects = function() return { size = function() return 1 end, get = function() return HAM end } end
getCell = function() return { getGridSquare = function(_, x, y, z)
    if x == 102 and y == 200 and z == 0 then return SQ end return nil end } end
CAR = { seats = {} }
function CAR:getId() return 17 end
function CAR:getSeat(chr) return self.seats[chr] or -1 end
CAR_RADIO = { class = "VehiclePart", data = newData(145000) }
function CAR_RADIO:getDeviceData() return self.data end
function CAR_RADIO:getVehicle() return CAR end
function CAR_RADIO:getId() return "Radio" end
function CAR:getPartById(name) if name == "Radio" then return CAR_RADIO end return nil end
function locate(p, x, y, z, seat)
    p.x, p.y, p.z = x, y, z
    p.getX = function(self) return self.x end
    p.getY = function(self) return self.y end
    p.getZ = function(self) return self.z end
    p.getVehicle = function(self) if CAR.seats[self] then return CAR end return nil end
    CAR.seats[p] = seat
end
"""


def scenario_world_radios_mp(tmp: Path) -> None:
    """E06-T03 en multijoueur simulé : Alice, passagère du véhicule 17, émet par l'autoradio ; Bob, que son client
    croit près de la radio posée mais que le serveur voit loin, est refusé (TooFar) sans rien prononcer."""
    exchange = tmp / "world"
    exchange.mkdir()
    bridge = start_bridge(exchange)
    try:
        clock = Clock()
        server = Game("server", exchange, clock)
        server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
        sg = server.g
        clients = {}

        def to_client(*args):
            target = clients[args[0].username]
            target.g.fire("OnServerCommand", args[1], args[2], target.table(args[3]))

        sg.sendServerCommand = to_client
        sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
        server.rt.execute(WORLD)
        for name in ("alice", "bob"):
            c = Game("client", exchange, clock)
            c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
            c.rt.execute(WORLD)
            player = c.g.makePlayer(name)
            c.g.getPlayer = lambda p=player: p
            sg.makePlayer(name)
            c.g.sendClientCommand = (lambda n: lambda p, m, cmd, a: sg.fire(
                "OnClientCommand", m, cmd, sg.PLAYERS[n], server.table(a)))(name)
            clients[name] = c
        # Alice : passagère (place 1) chez elle et sur le serveur. Bob : à 2 cases de la HAM chez lui, à 20 sur le
        # serveur (client modifié ou position périmée).
        clients["alice"].g.locate(clients["alice"].g.PLAYERS["alice"], 300.5, 300.5, 0, 1)
        sg.locate(sg.PLAYERS["alice"], 300.5, 300.5, 0, 1)
        clients["bob"].g.locate(clients["bob"].g.PLAYERS["bob"], 100.5, 200.5, 0, None)
        sg.locate(sg.PLAYERS["bob"], 122.5, 200.5, 0, None)
        # Talkies rangés côté serveur : seule la radio désignée peut servir.
        sg.PLAYERS["alice"].inHand = False
        sg.PLAYERS["bob"].inHand = False

        alice_talk = clients["alice"].g.require("RadioSurvivor/RS_RadioTalk")
        alice = clients["alice"].g.PLAYERS["alice"]
        assert alice_talk.send(alice, clients["alice"].g.CAR_RADIO, "Passagère ici, on roule vers Rosewood.")
        assert lua_list(clients["alice"].g.SAID_CHAT) == ["Passagère ici, on roule vers Rosewood."]
        tick = lambda: sg.fire("OnTick")
        assert pump(lambda: len(sg.BROADCASTS) == 1, [tick]), "aucune réponse à la passagère"
        assert lua_list(sg.AIRED_ON) == [145000], lua_list(sg.AIRED_ON)

        bob_talk = clients["bob"].g.require("RadioSurvivor/RS_RadioTalk")
        bob = clients["bob"].g.PLAYERS["bob"]
        assert bob_talk.send(bob, clients["bob"].g.HAM, "Bob, tu me reçois ?")
        assert lua_list(bob.halos) == ["IGUI_RadioSurvivor_Reject_TooFar"], lua_list(bob.halos)
        assert len(clients["bob"].g.SAID_CHAT) == 0
        assert len(alice.halos) == 0
        # Bob réellement loin chez lui aussi : refus local, rien n'est envoyé.
        clients["bob"].g.locate(bob, 122.5, 200.5, 0, None)
        bob_talk.resetForTests()
        ok, problem = bob_talk.send(bob, clients["bob"].g.HAM, "Et maintenant ?")
        assert not ok and problem == "IGUI_RadioSurvivor_Reject_TooFar", problem
    finally:
        bridge.terminate()
        bridge.communicate(timeout=10)


# Voix du banc à actions (E07-T01) : lieu fixe, quatre actions en plus de say, un budget d'un signal par jour de jeu.
ACT_SECRET = "The cache key is under the third pew."
ACT_SHEET = f"""format=1
id=act
name=Act Tester
frequencies=152.0
location=fixed
coords=100,200,0
actions=say,signal,mark_map,reveal_area,remember
budget.signal=1
secret={ACT_SECRET}
[prompt]
You are Act Tester, a voice of the offline test bench that can act.
"""


def write_act(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "act.txt").write_text(ACT_SHEET, encoding="utf-8")


def scenario_structured_bridge(tmp: Path) -> None:
    """E07-T01, pont seul : bounded_actions (forme des actions), mode structuré d'une fiche à actions (prompt, JSON
    valide en payload RSV2, JSON invalide = say seul, fuite d'un secret dans un paramètre), mode texte inchangé pour
    une fiche say seul et hors ligne. Depuis E07-T07, seule remember (dotée d'un exécuteur) de la fiche act est
    proposée et gardée : les contrôles de forme passent par elle ; signal, mark_map et reveal_area sont retirées."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    import npc_protocol as protocol
    exchange = tmp / "structured-bridge"
    write_act(exchange)
    write_bench(exchange)
    voices = rb.Voices(exchange / "personas")
    act = voices.get("act")
    assert rb.structured(act) and not rb.structured(voices.get("bench"))

    # Forme des actions : seuls les éléments valides passent, au plus 3.
    raw = [
        {"type": "remember", "fact": "Caller 2 is Bob", "minutes": 20, "loud": True},  # forme seule : le serveur juge
        {"type": "fly"},                                   # hors catalogue
        {"type": "place_cache", "table": "a"},             # catalogue, hors fiche
        {"type": "say", "text": "x"},                      # jamais say
        "remember",                                        # pas une table
        {"type": "signal", "color": "green"},              # fiche, sans exécuteur côté serveur (E07-T07)
        {"type": "mark_map", "place": "church"},           # idem
        {"type": "remember", "fact": {"r": 1}},            # paramètre non scalaire
        {"type": "remember", "fact": "x" * 65},            # chaîne trop longue
        {"type": "remember", "fact": float("nan")},        # nombre non fini
        {"type": "remember", "Bad-Key": 1},                # nom de paramètre
        {"type": "remember", "fact": "<b>church</b>"},     # balises retirées par safe_text
        {"type": "remember", "fact": "Caller 1 is Kate"},
        {"type": "remember", "fact": "riverside"},         # quatrième valide : au-delà de 3
    ]
    kept = rb.bounded_actions(act, raw)
    assert kept == [{"type": "remember", "fact": "Caller 2 is Bob", "minutes": 20, "loud": True},
                    {"type": "remember", "fact": "b church /b"},
                    {"type": "remember", "fact": "Caller 1 is Kate"}], kept
    assert rb.bounded_actions(act, {"type": "remember"}) == [] and rb.bounded_actions(act, None) == []

    req = {"id": "1-2", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "Can you signal?", "voice": "act"}
    seen = []

    def fake(reply):
        return lambda config, messages, speaker="Walt", **_: seen.append(messages) or reply

    saved = rb.call_llm
    try:
        # JSON valide avec une action : payload radio_reply, say en lignes radio, seul le texte en mémoire.
        conversations = rb.Conversations(exchange)
        rb.call_llm = fake('```json\n{"say": "Green smoke in twenty. Over.", '
                           '"actions": [{"type": "remember", "fact": "Kate wants smoke"}, {"type": "signal", '
                           '"color": "green"}, {"type": "fly"}]}\n```')
        result = rb.answer({}, conversations, "s", req, voices)
        assert result == {"version": 2, "kind": "radio_reply", "id": "1-2", "say": ["Green smoke in twenty. Over."],
                          "actions": [{"type": "remember", "fact": "Kate wants smoke"}]}, result
        system = seen[-1][0]["content"]
        assert "Reply format" in system and "Allowed action types: remember." in system and '"fact"' in system
        assert all(name not in system for name in ("place_cache", "mark_map", "reveal_area", '"signal"',
                                                   "persona_state")), system
        assert "100,200" not in system and "coords" not in system, system
        # Le secret n'apparaît que dans la section des secrets (prompt de la voix), jamais dans la consigne de format.
        assert ACT_SECRET not in system[system.index("Reply format"):], system
        stored = history_files(exchange)["history_" + rb.hashlib.sha1(b"s").hexdigest()[:16] + "_act.json"]
        assert stored["messages"][-1] == {"role": "assistant", "content": "Green smoke in twenty. Over."}, stored
        # Sortie : resp= puis payload= (RSV2 hexadécimal), relu à l'identique.
        rb.write_responses(exchange / "responses.txt", {"1-2": result, "3-4": ["Hello."]})
        text = (exchange / "responses.txt").read_text(encoding="utf-8").splitlines()
        assert text[0] == "resp=1-2" and text[1].startswith("payload=") and text[2:] == ["resp=3-4", "line=Hello.",
                                                                                          "end"], text
        assert protocol.decode(bytes.fromhex(text[1][8:])) == {
            "version": 2, "kind": "radio_reply", "id": "1-2", "say": {1: "Green smoke in twenty. Over."},
            "actions": {1: {"type": "remember", "fact": "Kate wants smoke"}}}

        # Toutes les actions invalides (ou sans exécuteur) : sortie line= comme avant E07.
        rb.call_llm = fake('{"say": "No.", "actions": [{"type": "fly"}, {"type": "signal", "color": "red"}]}')
        assert rb.answer({}, conversations, "s", req, voices) == ["No."]
        # JSON invalide : le texte brut est say seul, sans action.
        rb.call_llm = fake('Sure thing {"say": broken')
        assert rb.answer({}, conversations, "s", req, voices) == ['Sure thing {"say": broken']
        # Secret cité dans un paramètre : parasites, rien en mémoire, aucune action.
        before = len(history_files(exchange)["history_" + rb.hashlib.sha1(b"s").hexdigest()[:16] + "_act.json"]
                     ["messages"])
        rb.call_llm = fake(json.dumps({"say": "Look there.", "actions": [
            {"type": "remember", "fact": ACT_SECRET.upper()}]}))
        assert rb.answer({}, conversations, "s", req, voices) == [rb.STATIC_LINE]
        rb.call_llm = fake(json.dumps({"say": "Sure. " + ACT_SECRET, "actions": []}))
        assert rb.answer({}, conversations, "s", req, voices) == [rb.STATIC_LINE]
        after = history_files(exchange)["history_" + rb.hashlib.sha1(b"s").hexdigest()[:16] + "_act.json"]
        assert len(after["messages"]) == before, after

        # Fiche say seul (bench) : prompt et sortie d'avant E07, même si le modèle renvoie du JSON.
        rb.call_llm = fake('{"say": "Hi.", "actions": [{"type": "signal"}]}')
        bench_req = dict(req, voice="bench")
        assert rb.answer({}, conversations, "s", bench_req, voices) == ['{"say": "Hi.", "actions": [{"type": "signal"}]}']
        assert "Reply format" not in seen[-1][0]["content"]
    finally:
        rb.call_llm = saved
    # Hors ligne : jamais d'action, même pour une fiche à actions.
    lines = rb.answer({"OFFLINE": "1"}, rb.Conversations(exchange), "offline", req, voices)
    assert isinstance(lines, list) and "Act, hors ligne" in " ".join(lines), lines


ACT_EXECUTORS = r"""
local Actions = require "RadioSurvivor/RS_Actions"
EXECUTED = {}
-- signal : budget de la fiche (1 par jour), délai d'une minute, 50 cases au plus du lieu de la voix.
Actions.register("signal", { cooldownMs = 60000, maxDistance = 50,
    validate = function(p) return type(p.color) == "string" end,
    execute = function(p, ctx) EXECUTED[#EXECUTED + 1] = "signal:" .. p.color .. ":" .. ctx.caller .. ":" .. ctx.voice
        return true end })
-- mark_map : sans budget, délai de 5 minutes.
Actions.register("mark_map", { cooldownMs = 300000,
    execute = function(p) EXECUTED[#EXECUTED + 1] = "mark_map:" .. tostring(p.place) return true end })
-- reveal_area : 10 cases au plus (l'appelant est à 30).
Actions.register("reveal_area", { maxDistance = 10,
    execute = function() EXECUTED[#EXECUTED + 1] = "reveal_area" return true end })
-- say n'est jamais un exécuteur ; une action hors catalogue non plus.
REG_SAY = Actions.register("say", { execute = function() return true end })
REG_FLY = Actions.register("fly", { execute = function() return true end })
-- remember a son exécuteur depuis E07-T03 (RS_Memory, chargé par le serveur) : retiré ici pour garder le cas
-- not_available d'E07-T01 ; scenario_memory_server le couvre.
Actions.unregister("remember")
"""


def scenario_structured_server(tmp: Path) -> None:
    """E07-T01, serveur (solo, lupa) : réponse payload= radio_reply diffusée comme line= puis actions jugées (hors
    catalogue, hors fiche, sans exécuteur, paramètres, distance, trop d'actions, exécution) ; budget du jour épuisé
    et délai ; ancienne réponse line= sans action ; réponse PNJ du même fichier ignorée par le lecteur radio et
    lecteur PNJ intact ; compteurs dans l'état privé RS_State quand il est chargé."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "structured-server"
    exchange.mkdir()
    write_act(exchange)
    clock = Clock()
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    player.radio.device.channel = 152000
    player.getX = lambda self: 130.5
    player.getY = lambda self: 200.5
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    game.rt.execute(ACT_EXECUTORS)
    assert g.REG_SAY is False and g.REG_FLY is False
    tick = lambda: g.fire("OnTick")
    talk_module = g.require("RadioSurvivor/RS_RadioTalk")

    def turn(text: str) -> str:
        g.finishAiring()
        clock.offset += 11000
        talk_module.resetForTests()
        assert g.talk(player, text) == "ok"
        request = (exchange / "requests.txt").read_text(encoding="utf-8")
        ids = [line[4:] for line in request.splitlines() if line.startswith("req=")]
        assert len(ids) == 1 and "voice=act" in request, request
        return ids[0]

    def respond(body: list[str]) -> None:
        (exchange / "responses.txt").write_text("\n".join(body + ["end"]) + "\n", encoding="utf-8")

    def payload(value) -> str:
        return "payload=" + protocol.encode(value).hex()

    def action_logs() -> list[str]:
        return [line for line in lua_list(g.LOGS) if line.startswith("[RadioSurvivor] action ")]

    # Réponse structurée : say filtré comme line= (balises, MAX_LINES), puis une décision par action proposée ; au
    # plus 3 actions jugées, le surplus refusé too_many.
    req_id = turn("Act, can you signal?")
    actions = [{"type": "fly"}, {"type": "place_cache"}, {"type": "remember", "fact": "x"},
               {"type": "signal", "color": 3}, {"type": "reveal_area"}, {"type": "signal", "color": "green"}]
    npc_reply = {"version": 2, "kind": "npc_reply", "id": "npc-1", "world": "w", "run": "r", "npc": "n", "order": 1,
                 "revision": 1, "text": "Hi", "intent": "none", "offer": ""}
    respond([f"resp={req_id}", payload({"version": 2, "kind": "radio_reply", "id": req_id,
                                        "say": ["Green <b>smoke</b> soon.", "Over."], "actions": actions}),
             "resp=npc-1", payload(npc_reply)])
    # Lecteur PNJ du même fichier : sa réponse est intacte (la réponse radio y est une entrée de plus, ignorée).
    npc_answers = g.require("RadioSurvivor/RS_Transport").readNpc()
    assert npc_answers["npc-1"]["kind"] == "npc_reply" and npc_answers["npc-1"]["text"] == "Hi"
    assert pump(lambda: len(g.BROADCASTS) == 1, [tick]), "structured reply not aired"
    assert lua_list(g.BROADCASTS[1]) == ["<bzzt>", "Green bsmoke/b soon.", "Over."], lua_list(g.BROADCASTS[1])
    assert lua_list(g.AIRED_ON) == [152000]
    assert action_logs() == [
        "[RadioSurvivor] action fly voice=act caller=solo refused reason=unknown_action",
        "[RadioSurvivor] action place_cache voice=act caller=solo refused reason=not_allowed",
        "[RadioSurvivor] action remember voice=act caller=solo refused reason=not_available",
        "[RadioSurvivor] action signal voice=act caller=solo refused reason=too_many",
        "[RadioSurvivor] action reveal_area voice=act caller=solo refused reason=too_many",
        "[RadioSurvivor] action signal voice=act caller=solo refused reason=too_many",
    ], action_logs()
    assert len(g.EXECUTED) == 0

    # Exécution, distance (reveal_area à 30 cases pour 10 permises), puis budget et délai à la réponse suivante.
    req_id = turn("Signal please.")
    respond([f"resp={req_id}", payload({"version": 2, "kind": "radio_reply", "id": req_id, "say": ["Going."],
             "actions": [{"type": "signal", "color": "green"}, {"type": "reveal_area"},
                         {"type": "mark_map", "place": "church"}]})])
    assert pump(lambda: len(g.BROADCASTS) == 2, [tick])
    assert lua_list(g.EXECUTED) == ["signal:green:solo:act", "mark_map:church"], lua_list(g.EXECUTED)
    assert action_logs()[6:] == [
        "[RadioSurvivor] action signal voice=act caller=solo accepted reason=ok",
        "[RadioSurvivor] action reveal_area voice=act caller=solo refused reason=too_far",
        "[RadioSurvivor] action mark_map voice=act caller=solo accepted reason=ok",
    ], action_logs()
    req_id = turn("Again?")
    clock.offset += 60000  # délai de signal écoulé : seul le budget du jour le refuse
    respond([f"resp={req_id}", payload({"version": 2, "kind": "radio_reply", "id": req_id, "say": ["No."],
             "actions": [{"type": "signal", "color": 3}, {"type": "signal", "color": "red"},
                         {"type": "mark_map", "place": "school"}]})])
    assert pump(lambda: len(g.BROADCASTS) == 3, [tick])
    assert action_logs()[9:] == [
        "[RadioSurvivor] action signal voice=act caller=solo refused reason=bad_params",
        "[RadioSurvivor] action signal voice=act caller=solo refused reason=budget",
        "[RadioSurvivor] action mark_map voice=act caller=solo refused reason=cooldown",
    ], action_logs()
    assert len(g.EXECUTED) == 2

    # Ancienne réponse line= : diffusée sans aucune décision d'action.
    req_id = turn("Plain line?")
    respond([f"resp={req_id}", "line=Plain answer."])
    assert pump(lambda: len(g.BROADCASTS) == 4, [tick])
    assert lua_list(g.BROADCASTS[4]) == ["<bzzt>", "Plain answer."] and len(action_logs()) == 12

    # Jour de jeu suivant : budget remis à zéro ; délai de mark_map écoulé ; compteurs dans RS_State une fois chargé.
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    sheet = g.require("RadioSurvivor/RS_Personas").get("act")
    state = g.require("RadioSurvivor/RS_State")
    state.data = game.rt.table_from({"schema": 2, "world": "w"})
    decide = lambda acts, day: actions_mod.decide(sheet, "solo", game.rt.table_from(
        [game.rt.table_from(a) for a in acts]), clock(), game.rt.table_from({"player": player, "day": day}))
    clock.offset += 300000
    decisions = decide([{"type": "signal", "color": "blue"}, {"type": "mark_map", "place": "mall"}], "1993-07-13")
    assert [(d.type, d.accepted, d.reason) for d in lua_list(decisions)] == [
        ("signal", True, "ok"), ("mark_map", True, "ok")], [(d.type, d.reason) for d in lua_list(decisions)]
    assert lua_list(decisions)[0].params.color == "blue"
    counter = state.data.actionCounters["act"]["signal"]
    assert counter.day == "1993-07-13" and counter.used == 1 and state.dirty is True
    # Voix disparue (fiche retirée) : rien n'est exécuté.
    gone = actions_mod.decide(None, "solo", game.rt.table_from([game.rt.table_from({"type": "signal", "color": "x"})]),
                              clock(), None)
    assert lua_list(gone)[0].reason == "not_allowed" and len(g.EXECUTED) == 4
    check_action_log(game, exchange, sheet, player, clock)


def check_action_log(game: "Game", exchange: Path, sheet, player, clock) -> None:
    """E07-T02 : journal admin actions-<partie>.log (une ligne par décision, tous les champs, paramètres triés et
    encodés, aucun texte de fiche ni de say) ; rotation au seuil de lignes puis de caractères, .1 conservé puis
    écrasé ; compteur initialisé par relecture du fichier existant. Doublure getFileWriter fidèle au jeu."""
    g = game.g
    TAB, NL = "\t", "\n"
    # Doublure : extension non admise (casse comprise) ou chemin relatif -> nil, comme LuaManager.getFileWriter.
    for bad in ("batman_RadioSurvivor/x.lua", "batman_RadioSurvivor/x.LOG", "batman_RadioSurvivor/../x.log"):
        assert g.getFileWriter(bad, True, False) is None, bad
    log_mod = g.require("RadioSurvivor/RS_ActionLog")
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    base = log_mod.base()
    import binascii
    assert base == "batman_RadioSurvivor/actions-" + binascii.hexlify(b"Multiplayer/TestWorld").decode(), base
    current = exchange / (Path(base).name + ".log")
    rotated = exchange / (Path(base).name + ".1.log")
    read = lambda f: f.read_text(encoding="utf-8").split(NL)[:-1]
    lines = read(current)
    assert lines[0] == log_mod.HEADER and lines[0].startswith("# RadioSurvivor action log v1"), lines[0]
    rows = [line.split(TAB) for line in lines[1:]]
    assert all(len(r) == 8 for r in rows), rows
    # 12 décisions des réponses radio (dont 3 too_many), 2 du jour suivant, 1 de la voix disparue.
    assert [(r[4], r[6], r[7]) for r in rows] == [
        ("fly", "refused", "unknown_action"), ("place_cache", "refused", "not_allowed"),
        ("remember", "refused", "not_available"), ("signal", "refused", "too_many"),
        ("reveal_area", "refused", "too_many"), ("signal", "refused", "too_many"),
        ("signal", "accepted", "ok"), ("reveal_area", "refused", "too_far"), ("mark_map", "accepted", "ok"),
        ("signal", "refused", "bad_params"), ("signal", "refused", "budget"), ("mark_map", "refused", "cooldown"),
        ("signal", "accepted", "ok"), ("mark_map", "accepted", "ok"), ("signal", "refused", "not_allowed"),
    ], [(r[4], r[7]) for r in rows]
    assert [r[2] for r in rows] == ["act"] * 14 + ["-"] and {r[3] for r in rows} == {"solo"}
    assert [r[5] for r in rows[:7]] == ["-", "-", "fact=x", "color=3", "-", "color=green", "color=green"], rows
    assert rows[8][5] == "place=church" and rows[13][5] == "place=mall"
    for r in rows:
        assert re.fullmatch(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC", r[0]), r[0]
        assert re.fullmatch(r"1993-07-12 \d\d:05", r[1]), r[1]
    text = current.read_text(encoding="utf-8")
    for leak in (ACT_SECRET, "third pew", "Green", "smoke", "Over.", "Going.", "Act Tester", "You are"):
        assert leak not in text, leak

    def decide(acts):
        return actions_mod.decide(sheet, "solo", game.rt.table_from([game.rt.table_from(a) for a in acts]), clock(),
                                  game.rt.table_from({"player": player, "day": "1993-07-13"}))

    # Paramètres triés par clé, séparateurs et contrôles encodés en %XX (une seule ligne) ; paramètres rejetés.
    decide([{"type": "signal", "zeta": "a\tb\nc\rd", "alpha": "x;y=z%", "color": "ok"},
            {"type": "signal", "color": "x" * 65}])
    rows = [line.split(TAB) for line in read(current)[1:]]
    assert len(rows) == 17 and all(len(r) == 8 for r in rows)
    assert rows[15][5] == "alpha=x%3By%3Dz%25;color=ok;zeta=a%09b%0Ac%0Dd", rows[15][5]
    assert rows[15][6:] == ["refused", "budget"] and rows[16][5:] == ["<invalid>", "refused", "bad_params"]
    first = read(current)

    # Rotation au seuil de lignes : le contenu courant passe en .1, le courant repart (en-tête + nouvelle ligne).
    const.ACTION_LOG_MAX_LINES = 5
    decide([{"type": "fly", "n": 1}])
    assert read(rotated) == first, read(rotated)
    assert read(current)[0] == log_mod.HEADER and len(read(current)) == 2 and read(current)[1].split(TAB)[5] == "n=1"
    for n in (2, 3, 4):
        decide([{"type": "fly", "n": n}])
    assert len(read(current)) == 5 and read(rotated) == first
    second = read(current)
    decide([{"type": "fly", "n": 5}])  # 6 lignes > 5 : nouvelle rotation, l'ancien .1 écrasé
    assert read(rotated) == second and read(current)[1].split(TAB)[5] == "n=5"
    # Compteur perdu (redémarrage du serveur) : relu une fois depuis le fichier, la rotation reste au bon seuil.
    log_mod.resetForTests()
    for n in (6, 7, 8):
        decide([{"type": "fly", "n": n}])
    assert len(read(current)) == 5 and read(rotated) == second
    decide([{"type": "fly", "n": 9}])
    assert len(read(current)) == 2 and [line.split(TAB)[5] for line in read(rotated)[1:]] == ["n=5", "n=6", "n=7",
                                                                                                  "n=8"]
    # Seuil de caractères : le fichier courant ne le dépasse jamais.
    const.ACTION_LOG_MAX_LINES = 2000
    const.ACTION_LOG_MAX_CHARS = 400
    for n in range(10, 30):
        decide([{"type": "fly", "n": n}])
        size = len(current.read_text(encoding="utf-8"))
        assert size <= 400, size
    assert len(read(rotated)) >= 3 and read(rotated)[0] == log_mod.HEADER


MEM_SECRET = "The mast key hides in the blue mailbox."
MEM_SHEETS = {
    # mem : remember sans plafond ; mem2 : budget.remember=2 par jour de jeu.
    "mem": f"""format=1
id=mem
name=Memo Tester
frequencies=153.0
actions=say,remember
secret={MEM_SECRET}
[prompt]
You are Memo Tester, a voice of the offline test bench that remembers.
""",
    "mem2": """format=1
id=mem2
name=Second Memo
frequencies=154.0
actions=say,remember
budget.remember=2
[prompt]
You are Second Memo, another voice of the offline test bench.
""",
}


def write_mem(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in MEM_SHEETS.items():
        (folder / f"{name}.txt").write_text(text, encoding="utf-8")


def scenario_memory_bridge(tmp: Path) -> None:
    """E07-T03, pont seul : champ memory= lu par parse_requests ; souvenirs injectés dans le prompt système (section
    non vérifiée), chaque fait passé par safe_text, fait citant un secret retiré ; champ absent, vide, illisible, trop
    long ou qui n'est pas une liste = prompt identique à celui d'avant E07-T03 ; injection aussi en mode texte."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    import npc_protocol as protocol
    exchange = tmp / "memory-bridge"
    write_mem(exchange)
    write_bench(exchange)
    voices = rb.Voices(exchange / "personas")
    mem = voices.get("mem")
    hexed = lambda value: protocol.encode(value).hex()

    # Transport : le champ memory= d'une demande radio est lu comme les autres champs.
    field = hexed(["Name is Kate", "Lives near the <b>school</b>", MEM_SECRET.lower(), "x" * 300, 7])
    text = "\n".join(["protocol=2", "session=s", "generation=1", "req=1-1", "sent=1", "caller=solo", "voice=mem",
                      "text=Hi", f"memory={field}", "commit=1", "end"])
    session, requests = rb.parse_requests(text)
    assert requests[0]["memory"] == field
    # Faits : safe_text (balises retirées), secret de la fiche retiré, trop long et non texte retirés.
    assert rb.memory_facts(requests[0], mem) == ["Name is Kate", "Lives near the b school /b"], \
        rb.memory_facts(requests[0], mem)
    # Au plus 5 faits ; champ illisible, trop long, ou table qui n'est pas une liste : aucun souvenir.
    assert rb.memory_facts({"memory": hexed([f"fact {i}" for i in range(8)])}, mem) == [f"fact {i}" for i in range(5)]
    for bad in ("zz", "abc", hexed({"a": "b"}), hexed({1: "a", 3: "b"}), hexed("plain"), "ab" * 2049, ""):
        assert rb.memory_facts({"memory": bad}, mem) == [], bad
    assert rb.memory_facts({}, mem) == []

    req = {"id": "1-2", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "Remember me?", "voice": "mem"}
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or '{"say": "Sure.", "actions": []}'
        conversations = rb.Conversations(exchange)
        rb.answer({}, conversations, "s", req, voices)
        plain = seen[-1][0]["content"]
        assert "memories" not in plain and "unverified" not in plain, plain
        for empty in ("", hexed([]), "zz"):
            rb.answer({}, conversations, "s", dict(req, memory=empty), voices)
            assert seen[-1][0]["content"] == plain, empty
        rb.answer({}, conversations, "s", dict(req, memory=field), voices)
        system = seen[-1][0]["content"]
        tag = "[Caller 1]"
        assert system.startswith(rb.system_prompt(req, tag, rb.voice_prompt(mem))), system
        assert f"Your memories of {tag} (unverified notes" in system and "never proof" in system, system
        assert "- Name is Kate\n- Lives near the b school /b" in system, system
        assert system.count(MEM_SECRET) == 1 and MEM_SECRET.lower() not in system  # seulement dans les secrets
        assert system.index("Your memories") < system.index("Reply format"), system
        # Mode texte (fiche say seul) : souvenirs injectés aussi, prompt inchangé sans eux.
        bench_req = dict(req, voice="bench")
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or "Hello."
        rb.answer({}, conversations, "s", bench_req, voices)
        bench_plain = seen[-1][0]["content"]
        rb.answer({}, conversations, "s", dict(bench_req, memory=hexed(["Has a red truck"])), voices)
        assert seen[-1][0]["content"] == bench_plain + rb.memory_prompt(["Has a red truck"], tag)
        assert "Reply format" not in seen[-1][0]["content"] and "Your memories" not in bench_plain
    finally:
        rb.call_llm = saved


def scenario_memory_server(tmp: Path) -> None:
    """E07-T03, serveur (solo, lupa) : exécuteur remember (acceptation, bad_params, budget de la fiche), aucun effet
    de jeu, souvenirs joints à la demande suivante (memory=) et relus par le pont ; déduplication, éviction des faits
    et des appelants ; isolation par voix, appelant et personnage ; purge à la mort ; persistance dans RS_State
    (sauvegarde puis relecture) ; journal admin."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    import radio_bridge as rb
    exchange = tmp / "memory-server"
    exchange.mkdir()
    write_mem(exchange)
    clock = Clock()
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    t = game.rt.table_from
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    player.radio.device.channel = 153000
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    state = g.require("RadioSurvivor/RS_State")
    memory = g.require("RadioSurvivor/RS_Memory")
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    personas = g.require("RadioSurvivor/RS_Personas")
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    talk_module = g.require("RadioSurvivor/RS_RadioTalk")
    tick = lambda: g.fire("OnTick")
    # État privé neuf (fichiers state-<partie>-<0|1>.txt du banc), deux personnages ; le joueur est lié à c1.
    assert state.init(True) is True
    state.data.characters = t({"c1": t({"id": "c1"}), "c2": t({"id": "c2"})})
    g.RS_CarnetServer = t({"bound": t({})})
    g.RS_CarnetServer.bound[player] = "c1"

    def turn(text: str) -> dict:
        g.finishAiring()
        clock.offset += 11000
        talk_module.resetForTests()
        assert g.talk(player, text) == "ok"
        parsed = rb.parse_requests((exchange / "requests.txt").read_text(encoding="utf-8"))
        assert parsed and len(parsed[1]) == 1, parsed
        return parsed[1][0]

    def respond(req_id: str, acts: list) -> None:
        body = {"version": 2, "kind": "radio_reply", "id": req_id, "say": ["Noted."], "actions": acts}
        (exchange / "responses.txt").write_text(f"resp={req_id}\npayload={protocol.encode(body).hex()}\nend\n",
                                                encoding="utf-8")

    def action_logs() -> list[str]:
        return [line for line in lua_list(g.LOGS) if line.startswith("[RadioSurvivor] action ")]

    def facts(voice, caller="solo", cid="c1") -> list[str]:
        return lua_list(memory.facts(voice, caller, cid))

    # Premier appel : aucun souvenir, pas de champ memory=.
    req = turn("Hello Memo.")
    assert req["voice"] == "mem" and "memory" not in req, req
    respond(req["id"], [{"type": "remember", "fact": "  Name is <b>Kate</b>\tfrom   Riverside "},
                        {"type": "remember", "fact": "x", "where": "here"},
                        {"type": "remember", "fact": " <> "}])
    state.dirty = False
    assert pump(lambda: len(g.BROADCASTS) == 1, [tick])
    assert action_logs() == [
        "[RadioSurvivor] action remember voice=mem caller=solo accepted reason=ok",
        "[RadioSurvivor] action remember voice=mem caller=solo refused reason=bad_params",
        "[RadioSurvivor] action remember voice=mem caller=solo refused reason=bad_params",
    ], action_logs()
    assert facts("mem") == ["Name is b Kate /b from Riverside"] and state.dirty is True
    # Aucun effet de jeu : une seule diffusion (la réponse), le joueur n'a dit que sa phrase.
    assert len(g.BROADCASTS) == 1 and lua_list(player.said) == ["Hello Memo."], lua_list(player.said)

    # Appel suivant du même appelant à la même voix : souvenirs joints (RSV2 hexadécimal), relus par le pont.
    req = turn("Do you remember me?")
    assert protocol.decode(bytes.fromhex(req["memory"])) == {1: "Name is b Kate /b from Riverside"}, req
    sheet = rb.Voices(exchange / "personas").get("mem")
    assert rb.memory_facts(req, sheet) == ["Name is b Kate /b from Riverside"]
    respond(req["id"], [])
    assert pump(lambda: len(g.BROADCASTS) == 2, [tick])

    def decide(voice, acts, caller="solo", cid="c1", day="1993-07-12"):
        decisions = actions_mod.decide(personas.get(voice), caller, t([t(a) for a in acts]), clock(),
                                       t({"player": player, "cid": cid, "day": day}))
        return [(d.type, d.reason) for d in lua_list(decisions)]

    # Déduplication (casse, espaces) : rafraîchi, pas dupliqué ; puis au plus 5 faits, le plus ancien évincé.
    assert decide("mem", [{"type": "remember", "fact": "Has a dog"},
                          {"type": "remember", "fact": "NAME is b kate /b   FROM riverside"}]) == [
        ("remember", "ok"), ("remember", "ok")]
    assert facts("mem") == ["Has a dog", "NAME is b kate /b FROM riverside"], facts("mem")
    for n in range(1, 5):
        decide("mem", [{"type": "remember", "fact": f"Fact {n}"}])
    assert facts("mem") == ["NAME is b kate /b FROM riverside", "Fact 1", "Fact 2", "Fact 3", "Fact 4"], facts("mem")
    assert decide("mem", [{"type": "remember", "fact": "y" * 65}]) == [("remember", "bad_params")]
    # Fait de 64 caractères au plus après nettoyage (balises retirées puis espaces réduits).
    long_fact = "<" * 10 + "z" * 54
    assert decide("mem", [{"type": "remember", "fact": long_fact}]) == [("remember", "ok")]
    assert facts("mem")[-1] == "z" * 54 and len(facts("mem")) == 5

    # Budget de la fiche (mem2 : 2 par jour de jeu), remis à zéro le jour suivant ; délai nul entre deux appelants.
    assert decide("mem2", [{"type": "remember", "fact": "A"}, {"type": "remember", "fact": "B"},
                           {"type": "remember", "fact": "C"}]) == [("remember", "ok"), ("remember", "ok"),
                                                                    ("remember", "budget")]
    assert decide("mem2", [{"type": "remember", "fact": "D"}], caller="bob", cid=None, day="1993-07-13") == [
        ("remember", "ok")]

    # Isolation : autre voix, autre appelant, autre personnage.
    assert facts("mem2") == ["A", "B"] and facts("mem2", "bob", None) == ["D"]
    assert facts("mem", "bob", None) == [] and facts("mem", "solo", "c2") == [] and facts("mem", "solo", None) == []
    assert memory.field("mem", "solo", "c2") is None and memory.field("mem2", "bob", "c1") is None
    g.RS_CarnetServer.bound[player] = "c2"  # nouveau personnage en solo : même clé d'appelant, aucun souvenir
    req = turn("New face here.")
    assert "memory" not in req, req
    respond(req["id"], [{"type": "remember", "fact": "Second life"}])
    assert pump(lambda: len(g.BROADCASTS) == 3, [tick])
    assert facts("mem", "solo", "c2") == ["Second life"] and len(facts("mem")) == 5

    # Appelants par voix : le moins récemment servi évincé (borne abaissée pour le banc).
    const.MEMORY_MAX_CALLERS = 3
    decide("mem2", [{"type": "remember", "fact": "E"}], caller="carl", cid=None, day="1993-07-14")
    decide("mem2", [{"type": "remember", "fact": "F"}], caller="solo", cid="c1", day="1993-07-14")  # rafraîchi
    decide("mem2", [{"type": "remember", "fact": "G"}], caller="dana", cid=None, day="1993-07-15")
    assert facts("mem2", "bob", None) == [] and facts("mem2", "carl", None) == ["E"]
    assert facts("mem2") == ["A", "B", "F"] and facts("mem2", "dana", None) == ["G"]
    const.MEMORY_MAX_CALLERS = 50

    # Persistance : sauvegarde de RS_State puis relecture (redémarrage du serveur).
    assert state.save() is True and state.dirty is False
    before = memory.field("mem", "solo", "c1")
    state.data = None
    assert state.init(False) is True
    assert memory.field("mem", "solo", "c1") == before and facts("mem", "solo", "c2") == ["Second life"]

    # Mort : personnage retiré (jamais relu), puis souvenirs purgés de toutes les voix.
    state.data.characters["c1"].retired = True
    assert facts("mem") == [] and memory.field("mem", "solo", "c1") is None
    state.dirty = False
    memory.forgetCharacter("c1")
    assert state.dirty is True
    state.data.characters["c1"].retired = False
    assert facts("mem") == [] and facts("mem2") == [] and facts("mem", "solo", "c2") == ["Second life"]

    # Journal admin : une ligne par décision, le fait nettoyé seulement par le serveur, encodé comme tout paramètre.
    log_mod = g.require("RadioSurvivor/RS_ActionLog")
    rows = [line.split("\t") for line in
            (exchange / (Path(log_mod.base()).name + ".log")).read_text(encoding="utf-8").split("\n")[1:-1]]
    assert [(r[2], r[4], r[6], r[7]) for r in rows[:3]] == [
        ("mem", "remember", "accepted", "ok"), ("mem", "remember", "refused", "bad_params"),
        ("mem", "remember", "refused", "bad_params")], rows[:3]
    assert rows[0][5] == "fact=  Name is <b>Kate</b>%09from   Riverside ", rows[0][5]
    assert rows[1][5] == "fact=x;where=here" and any(r[3] == "bob" and r[5] == "fact=D" for r in rows)
    assert MEM_SECRET not in "\n".join("\t".join(r) for r in rows)


PS_SECRET = "The generator hides behind the old chapel."
PS_SHEETS = {
    # ps : persona_state sans plafond ; ps2 : budget.persona_state=2 par jour de jeu.
    "ps": f"""format=1
id=ps
name=State Tester
frequencies=157.0
actions=say,persona_state
secret={PS_SECRET}
[prompt]
You are State Tester, a voice of the offline test bench whose mood changes.
""",
    "ps2": """format=1
id=ps2
name=Second State
frequencies=158.0
actions=say,persona_state
budget.persona_state=2
[prompt]
You are Second State, another voice of the offline test bench.
""",
}


def write_ps(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in PS_SHEETS.items():
        (folder / f"{name}.txt").write_text(text, encoding="utf-8")


def scenario_persona_bridge(tmp: Path) -> None:
    """E07-T06, pont seul : champ persona= lu par parse_requests ; état injecté dans le prompt système (section « Your
    current state »), lieu passé par safe_text et retiré s'il cite un secret ; champ absent, vide, illisible, trop
    long, clé inconnue ou niveau invalide = prompt identique à celui d'avant E07-T06 ; injection aussi en mode texte."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    import npc_protocol as protocol
    exchange = tmp / "persona-bridge"
    write_ps(exchange)
    write_bench(exchange)
    voices = rb.Voices(exchange / "personas")
    ps = voices.get("ps")
    hexed = lambda value: protocol.encode(value).hex()

    field = hexed({"morale": 3, "supplies": 7, "place": "an old <b>barn</b>"})
    text = "\n".join(["protocol=2", "session=s", "generation=1", "req=1-1", "sent=1", "caller=solo", "voice=ps",
                      "text=Hi", f"persona={field}", "commit=1", "end"])
    session, requests = rb.parse_requests(text)
    assert requests[0]["persona"] == field
    assert rb.persona_state(requests[0], ps) == {"morale": 3, "supplies": 7, "place": "an old b barn /b"}, \
        rb.persona_state(requests[0], ps)
    # Lieu absent, vide ou citant un secret : retiré, le reste gardé.
    assert rb.persona_state({"persona": hexed({"morale": 0, "supplies": 10})}, ps) == {"morale": 0, "supplies": 10}
    for place in ("", "  ", PS_SECRET.upper(), 7, "x" * 200):
        assert rb.persona_state({"persona": hexed({"morale": 5, "supplies": 5, "place": place})}, ps) == {
            "morale": 5, "supplies": 5}, place
    # Champ illisible, trop long, pas une table, clé inconnue, niveau absent, hors bornes ou non entier : ignoré.
    for bad in ("zz", "abc", hexed("plain"), hexed([1, 2]), hexed({"morale": 5, "supplies": 5, "mood": "ok"}),
                hexed({"morale": 5}), hexed({"morale": 11, "supplies": 5}), hexed({"morale": -1, "supplies": 5}),
                hexed({"morale": 4.5, "supplies": 5}), hexed({"morale": True, "supplies": 5}),
                hexed({"morale": "5", "supplies": 5}), "ab" * 513, ""):
        assert rb.persona_state({"persona": bad}, ps) is None, bad
    assert rb.persona_state({}, ps) is None
    assert rb.persona_prompt(None) == "" and rb.persona_prompt({}) == ""

    req = {"id": "1-2", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "How are you?", "voice": "ps"}
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or '{"say": "Fine.", "actions": []}'
        conversations = rb.Conversations(exchange)
        rb.answer({}, conversations, "s", req, voices)
        plain = seen[-1][0]["content"]
        assert "current state" not in plain and "Morale" not in plain, plain
        for empty in ("", "zz", hexed({"morale": 12, "supplies": 1})):
            rb.answer({}, conversations, "s", dict(req, persona=empty), voices)
            assert seen[-1][0]["content"] == plain, empty
        rb.answer({}, conversations, "s", dict(req, persona=field), voices)
        system = seen[-1][0]["content"]
        tag = "[Caller 1]"
        assert system.startswith(rb.system_prompt(req, tag, rb.voice_prompt(ps))), system
        assert ("\nYour current state (stay consistent with it; change it only for a reason in the story):\n"
                "- Morale: 3/10.\n- Supplies (food, water, ammunition): 7/10.\n"
                "- Where you say you are: an old b barn /b.") in system, system
        assert system.index("Your current state") < system.index("Reply format"), system
        # Secret dans le lieu : jamais dans le prompt hors de la section des secrets.
        rb.answer({}, conversations, "s", dict(req, persona=hexed({"morale": 2, "supplies": 2,
                                                                     "place": PS_SECRET.lower()})), voices)
        system = seen[-1][0]["content"]
        assert "Morale: 2/10" in system and "Where you say" not in system and PS_SECRET.lower() not in system
        # Avec des souvenirs : souvenirs, puis état, puis consigne de format.
        rb.answer({}, conversations, "s", dict(req, persona=field, memory=hexed(["Has a dog"])), voices)
        system = seen[-1][0]["content"]
        assert system.index("Your memories") < system.index("Your current state") < system.index("Reply format")
        # Mode texte (fiche say seul) : état injecté aussi, prompt inchangé sans lui.
        bench_req = dict(req, voice="bench")
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or "Hello."
        rb.answer({}, conversations, "s", bench_req, voices)
        bench_plain = seen[-1][0]["content"]
        rb.answer({}, conversations, "s", dict(bench_req, persona=hexed({"morale": 9, "supplies": 1})), voices)
        assert seen[-1][0]["content"] == bench_plain + rb.persona_prompt({"morale": 9, "supplies": 1})
        assert "Reply format" not in seen[-1][0]["content"] and "current state" not in bench_plain
    finally:
        rb.call_llm = saved


def scenario_persona_server(tmp: Path) -> None:
    """E07-T06, serveur (solo, lupa) : exécuteur persona_state (acceptation, pas maximal ramené, bornes 0..10 et 40
    caractères, bad_params sans champ, champ inconnu ou non entier, budget de la fiche), aucun effet de jeu, état
    joint aux demandes suivantes (persona=) seulement après un premier changement, relu par le pont ; isolation par
    voix ; persistance dans RS_State (sauvegarde puis relecture) ; fiche inchangée sur disque ; journal admin."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    import radio_bridge as rb
    exchange = tmp / "persona-server"
    exchange.mkdir()
    write_ps(exchange)
    sheet_files = [exchange / "personas" / f"{name}.txt" for name in PS_SHEETS]
    sheets_before = [p.read_bytes() for p in sheet_files]
    clock = Clock()
    game = Game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    t = game.rt.table_from
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    player.radio.device.channel = 157000
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    state = g.require("RadioSurvivor/RS_State")
    pstate = g.require("RadioSurvivor/RS_PersonaState")
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    personas = g.require("RadioSurvivor/RS_Personas")
    talk_module = g.require("RadioSurvivor/RS_RadioTalk")
    tick = lambda: g.fire("OnTick")
    assert state.init(True) is True
    state.data.characters = t({"c1": t({"id": "c1"})})
    g.RS_CarnetServer = t({"bound": t({})})
    g.RS_CarnetServer.bound[player] = "c1"

    def turn(text: str) -> dict:
        g.finishAiring()
        clock.offset += 11000
        talk_module.resetForTests()
        assert g.talk(player, text) == "ok"
        parsed = rb.parse_requests((exchange / "requests.txt").read_text(encoding="utf-8"))
        assert parsed and len(parsed[1]) == 1, parsed
        return parsed[1][0]

    def respond(req_id: str, acts: list) -> None:
        body = {"version": 2, "kind": "radio_reply", "id": req_id, "say": ["Noted."], "actions": acts}
        (exchange / "responses.txt").write_text(f"resp={req_id}\npayload={protocol.encode(body).hex()}\nend\n",
                                                encoding="utf-8")

    def action_logs() -> list[str]:
        return [line for line in lua_list(g.LOGS) if line.startswith("[RadioSurvivor] action ")]

    def current(voice):
        s = pstate.get(voice)
        return None if s is None else (s.morale, s.supplies, s.place)

    # Premier appel : état jamais changé, pas de champ persona=.
    req = turn("Hello State.")
    assert req["voice"] == "ps" and "persona" not in req, req
    assert current("ps") is None and pstate.field("ps") is None
    respond(req["id"], [{"type": "persona_state", "morale": 9, "place": "  the <b>old</b>\tbarn  "},
                        {"type": "persona_state"},
                        {"type": "persona_state", "morale": 4, "mood": "grim"}])
    state.dirty = False
    assert pump(lambda: len(g.BROADCASTS) == 1, [tick])
    assert action_logs() == [
        "[RadioSurvivor] action persona_state voice=ps caller=solo accepted reason=ok",
        "[RadioSurvivor] action persona_state voice=ps caller=solo refused reason=bad_params",
        "[RadioSurvivor] action persona_state voice=ps caller=solo refused reason=bad_params",
    ], action_logs()
    # Pas maximal : 9 demandé depuis 5 → 7 ; supplies inchangé (défaut 5) ; lieu nettoyé.
    assert current("ps") == (7, 5, "the b old /b barn") and state.dirty is True, current("ps")
    # Aucun effet de jeu : une seule diffusion, le joueur n'a dit que sa phrase.
    assert len(g.BROADCASTS) == 1 and lua_list(player.said) == ["Hello State."], lua_list(player.said)

    # Appel suivant : état joint (RSV2 hexadécimal), relu par le pont.
    req = turn("How are you now?")
    assert protocol.decode(bytes.fromhex(req["persona"])) == {"morale": 7, "supplies": 5,
                                                              "place": "the b old /b barn"}, req
    sheet = rb.Voices(exchange / "personas").get("ps")
    assert rb.persona_state(req, sheet) == {"morale": 7, "supplies": 5, "place": "the b old /b barn"}
    respond(req["id"], [])
    assert pump(lambda: len(g.BROADCASTS) == 2, [tick])

    def decide(voice, acts, caller="solo", day="1993-07-12"):
        decisions = actions_mod.decide(personas.get(voice), caller, t([t(a) for a in acts]), clock(),
                                       t({"player": player, "cid": "c1", "day": day}))
        return [(d.type, d.reason) for d in lua_list(decisions)]

    # Pas ramené vers le bas, bornes 0..10 (hors bornes ramené aussi), valeur dans le pas acceptée telle quelle.
    assert decide("ps", [{"type": "persona_state", "morale": -50, "supplies": 6}]) == [("persona_state", "ok")]
    assert current("ps")[:2] == (5, 6), current("ps")
    decide("ps", [{"type": "persona_state", "morale": 0}, {"type": "persona_state", "morale": 0},
                  {"type": "persona_state", "morale": -3}])
    assert current("ps")[0] == 0, current("ps")
    for _ in range(6):
        decide("ps", [{"type": "persona_state", "supplies": 100}])
    assert current("ps")[1] == 10, current("ps")
    assert decide("ps", [{"type": "persona_state", "supplies": 9}]) == [("persona_state", "ok")]
    assert current("ps")[1] == 9
    # Non entier, non nombre, lieu vide ou non texte : bad_params, état inchangé.
    before = current("ps")
    assert decide("ps", [{"type": "persona_state", "morale": 1.5}, {"type": "persona_state", "supplies": "3"},
                         {"type": "persona_state", "supplies": True}]) == [("persona_state", "bad_params")] * 3
    assert decide("ps", [{"type": "persona_state", "place": " <> "}, {"type": "persona_state", "place": 3},
                         {"type": "persona_state", "morale": 3, "place": ""}]) == [("persona_state", "bad_params")] * 3
    assert current("ps") == before, current("ps")
    # Lieu : 40 caractères au plus après nettoyage ; plus de 64 caractères bruts refusés par RS_Actions.
    assert decide("ps", [{"type": "persona_state", "place": "w" * 50}]) == [("persona_state", "ok")]
    assert current("ps")[2] == "w" * 40
    assert decide("ps", [{"type": "persona_state", "place": "w" * 65}]) == [("persona_state", "bad_params")]

    # Budget de la fiche (ps2 : 2 par jour de jeu), remis à zéro le jour suivant.
    assert decide("ps2", [{"type": "persona_state", "morale": 6}, {"type": "persona_state", "morale": 7},
                          {"type": "persona_state", "morale": 8}]) == [
        ("persona_state", "ok"), ("persona_state", "ok"), ("persona_state", "budget")]
    assert decide("ps2", [{"type": "persona_state", "supplies": 1}], day="1993-07-13") == [("persona_state", "ok")]
    # Isolation : chaque voix ne change que son propre état, quel que soit l'appelant.
    assert current("ps2") == (7, 3, ""), current("ps2")
    assert current("ps")[2] == "w" * 40 and current("ps")[:2] == before[:2]
    assert decide("ps2", [{"type": "persona_state", "place": "the mill"}], caller="bob", day="1993-07-13") == [
        ("persona_state", "ok")]
    assert current("ps2") == (7, 3, "the mill") and current("ps")[2] == "w" * 40
    assert protocol.decode(bytes.fromhex(pstate.field("ps2"))) == {"morale": 7, "supplies": 3, "place": "the mill"}

    # Persistance : sauvegarde de RS_State puis relecture (redémarrage du serveur).
    assert state.save() is True and state.dirty is False
    fields = (pstate.field("ps"), pstate.field("ps2"))
    state.data = None
    assert state.init(False) is True
    assert (pstate.field("ps"), pstate.field("ps2")) == fields and current("ps2") == (7, 3, "the mill")
    # Fiches jamais réécrites : seulement l'état privé.
    assert [p.read_bytes() for p in sheet_files] == sheets_before

    # Journal admin : une ligne par décision, paramètres tels que proposés.
    log_mod = g.require("RadioSurvivor/RS_ActionLog")
    rows = [line.split("\t") for line in
            (exchange / (Path(log_mod.base()).name + ".log")).read_text(encoding="utf-8").split("\n")[1:-1]]
    assert [(r[2], r[4], r[6], r[7]) for r in rows[:3]] == [
        ("ps", "persona_state", "accepted", "ok"), ("ps", "persona_state", "refused", "bad_params"),
        ("ps", "persona_state", "refused", "bad_params")], rows[:3]
    assert rows[0][5].startswith("morale=9;place=  the <b>old</b>%09barn"), rows[0][5]
    assert any(r[2] == "ps2" and r[3] == "bob" and r[5] == "place=the mill" for r in rows)
    assert PS_SECRET not in "\n".join("\t".join(r) for r in rows)


TWIN_SECRET = "The spare battery is in the blue cooler."
TWIN_SHEET = """format=1
id=twin
name=Twin Tester
frequencies=159.0
actions={actions}
secret={secret}
[prompt]
You are Twin Tester, a voice of the offline test bench.
"""


def scenario_action_descriptions(tmp: Path) -> None:
    """E07-T07, pont + serveur (lupa) : le prompt décrit les paramètres des seules actions dotées d'un exécuteur
    (remember : fact ; persona_state : morale, supplies, place), avec un exemple JSON ; une fiche qui n'autorise que
    des actions sans exécuteur reste en mode texte, prompt identique à la même fiche say seul ; la table du pont
    (EXECUTABLE_ACTIONS) et les exécuteurs enregistrés par le serveur (Actions.register) ont les mêmes noms, et les
    bornes citées sont celles de RadioSurvivor_Const."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    req = {"id": "7-7", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "How are you holding up?", "voice": "twin"}
    variants = {"say": "say", "mapper": "say,mark_map", "nothing": "say,signal,reveal_area,place_scene",
                "full": "say,signal,remember,persona_state"}
    systems: dict[str, str] = {}
    outputs: dict[str, object] = {}
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or (
            '{"say": "Fine.", "actions": [{"type": "persona_state", "morale": 4}]}')
        for name, actions in variants.items():
            exchange = tmp / f"descriptions-{name}"
            folder = exchange / "personas"
            folder.mkdir(parents=True)
            (folder / "twin.txt").write_text(TWIN_SHEET.format(actions=actions, secret=TWIN_SECRET), encoding="utf-8")
            voices = rb.Voices(folder)
            assert rb.structured(voices.get("twin")) == (name == "full"), name
            outputs[name] = rb.answer({}, rb.Conversations(exchange), "s", req, voices)
            systems[name] = seen[-1][0]["content"]
    finally:
        rb.call_llm = saved
    # Sans action dotée d'un exécuteur : mode texte, prompt et sortie identiques à la fiche say seul.
    assert "Reply format" not in systems["say"]
    assert systems["mapper"] == systems["say"] and systems["nothing"] == systems["say"]
    assert isinstance(outputs["say"], list) and outputs["say"] == outputs["mapper"] == outputs["nothing"], outputs
    # Fiche say,signal,remember,persona_state : les deux actions décrites, signal jamais proposée.
    full = systems["full"]
    assert outputs["full"]["actions"] == [{"type": "persona_state", "morale": 4}], outputs["full"]
    assert "Allowed action types: remember, persona_state." in full and '"signal"' not in full, full
    for word in ('"fact"', '"morale"', '"supplies"', '"place"', '{"type": "remember", "fact": ',
                 '{"type": "persona_state", "morale": '):
        assert word in full, (word, full)
    assert TWIN_SECRET not in full[full.index("Reply format"):] and "159" not in full, full

    # Côté serveur : exécuteurs réellement enregistrés et constantes citées.
    exchange = tmp / "descriptions-server"
    exchange.mkdir()
    game = Game("solo", exchange, Clock())
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    registered = game.rt.eval("""function(register)
        local i = 1
        while true do
            local name, value = debug.getupvalue(register, i)
            if name == nil then return nil end
            if name == "executors" then
                local out = {}
                for k in pairs(value) do out[#out + 1] = k end
                table.sort(out)
                return table.concat(out, ",")
            end
            i = i + 1
        end
    end""")(g.require("RadioSurvivor/RS_Actions").register)
    assert registered is not None, "RS_Actions.register has no 'executors' upvalue"
    names = set(registered.split(","))
    assert sorted(names) == sorted(rb.EXECUTABLE_ACTIONS), (registered, sorted(rb.EXECUTABLE_ACTIONS))
    # E11-T06: closed list of the cache tables, same order as the server (RS_Config.Caches.order).
    order = g.require("RadioSurvivor/RS_Config").Caches.order
    assert tuple(order[i] for i in range(1, len(order) + 1)) == rb.CACHE_TABLES, rb.CACHE_TABLES
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    assert (rb.MEMORY_FACT_CHARS, rb.PERSONA_LEVEL_MAX, rb.PERSONA_LEVEL_STEP, rb.PERSONA_PLACE_CHARS) == (
        const.MEMORY_FACT_CHARS, const.PERSONA_LEVEL_MAX, const.PERSONA_LEVEL_STEP, const.PERSONA_PLACE_CHARS)
    for bound in (f"at most {const.MEMORY_FACT_CHARS} characters", f"from 0 to {const.PERSONA_LEVEL_MAX}",
                  f"at most {const.PERSONA_LEVEL_STEP} per call", f"at most {const.PERSONA_PLACE_CHARS} characters"):
        assert bound in full, (bound, full)


# --- E07-T04 : action mark_map --------------------------------------------------------------------------------------

# Doublures fidèles au Java 42.21 des symboles de la carte du monde (zombie/worldMap/symbols/*.java,
# zombie/worldMap/UIWorldMap*.java, zombie/inventory/types/MapItem.java) : MapItem.getSingleton() unique jusqu'à
# MapItem.Reset (retour au menu : resetMapItem) ; UIWorldMap.new(table) ; getAPIv3():setMapItem(item) puis
# getSymbolsAPIv2() (créée une fois par interface, un écouteur permanent de plus sur les symboles de l'objet,
# WorldMapSymbolsV2.java:54-59 ; sans setMapItem : NullPointerException) ; addTexture / addTranslatedText /
# addUntranslatedText (couleur blanche, ancre 0,0, échelle 0,666 ; position en flottant 32 bits) ; getSymbolCount et
# getSymbolByIndex(i) de 0 à n-1 (hors bornes : IndexOutOfBoundsException) ; getSymbolID seulement sur une icône,
# getTranslatedText / getUntranslatedText seulement sur un texte, masqués en « ? » (espaces gardés) pour un illettré
# (WorldMapTextSymbol.java:66-89) ; setAnchor borné à 0..1 (WorldMapSymbols.java:63-64) ; icône inconnue des
# définitions : texture d'erreur (WorldMapSymbols.java:81-91).
MAP_DOUBLES = r"""
MAP_DEFS = { Target = true, Star = true, X = true, House = true }
ILLITERATE = false
UI_CREATED = 0
local function newItem() return { symbols = {}, listeners = 0 } end
MAP_ITEM = newItem()
function resetMapItem() MAP_ITEM = newItem() end
MapItem = { getSingleton = function() return MAP_ITEM end }
local function mask(text) return (string.gsub(text, "[^ ]", "?")) end
local Base = {}
function Base:getWorldX() return self.x end
function Base:getWorldY() return self.y end
function Base:isTexture() return false end
function Base:isText() return false end
function Base:setRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function Base:setAnchor(x, y) self.anchorX = math.max(0, math.min(1, x)) self.anchorY = math.max(0, math.min(1, y)) end
function Base:setScale(s) self.scale = s end
function Base:getScale() return self.scale end
local Texture = setmetatable({}, { __index = Base })
Texture.__index = Texture
function Texture:isTexture() return true end
function Texture:getSymbolID() return self.id end
local Text = setmetatable({}, { __index = Base })
Text.__index = Text
function Text:isText() return true end
function Text:getLayerID() return self.layer end
function Text:getTranslatedText() if ILLITERATE then return mask(self.text) end return self.text end
function Text:getUntranslatedText()
    if self.translated then return nil end
    if ILLITERATE then return mask(self.text) end
    return self.text
end
local function add(item, symbol)
    symbol.x, symbol.y = F32(symbol.x), F32(symbol.y)
    symbol.r, symbol.g, symbol.b, symbol.a, symbol.anchorX, symbol.anchorY, symbol.scale = 1, 1, 1, 1, 0, 0, 0.666
    table.insert(item.symbols, symbol)
    return symbol
end
local function newSymbolsAPI(item)
    if item == nil then error("java.lang.NullPointerException: uiSymbols") end
    item.listeners = item.listeners + 1
    local api = {}
    function api:addTexture(id, x, y)
        return add(item, setmetatable({ id = id, x = x, y = y, errorTexture = not MAP_DEFS[id] }, Texture))
    end
    function api:addTranslatedText(text, layer, x, y)
        return add(item, setmetatable({ text = text, layer = layer, translated = true, x = x, y = y }, Text))
    end
    function api:addUntranslatedText(text, layer, x, y)
        return add(item, setmetatable({ text = text, layer = layer, translated = false, x = x, y = y }, Text))
    end
    function api:getSymbolCount() return #item.symbols end
    function api:getSymbolByIndex(i)
        local s = item.symbols[i + 1]
        if s == nil then error("java.lang.IndexOutOfBoundsException: " .. tostring(i)) end
        return s
    end
    function api:getDefaultTextLayerID() return "text-note" end
    return api
end
UIWorldMap = { new = function(tbl)
    UI_CREATED = UI_CREATED + 1
    local state = {}
    local v3 = {}
    function v3:setMapItem(item) state.item = item end
    function v3:getSymbolsAPIv2()
        if state.api == nil then state.api = newSymbolsAPI(state.item) end
        return state.api
    end
    return { getAPIv3 = function() return v3 end }
end }
GOOD_HALOS = {}
HaloTextHelper.addGoodText = function(p, t) table.insert(GOOD_HALOS, t) end
"""


def f32(value: float) -> float:
    return struct.unpack("f", struct.pack("f", value))[0]


def map_game(mode: str, exchange: Path, clock) -> Game:
    game = Game(mode, exchange, clock)
    game.g.F32 = f32
    game.rt.execute(MAP_DOUBLES)
    return game


def map_symbols(g) -> list[tuple]:
    """Symboles de la carte : (genre, icône ou texte, x, y, ancre y, couleur r)."""
    out = []
    for s in lua_list(g.MAP_ITEM.symbols):
        kind = "texture" if s.id is not None else "text"
        out.append((kind, s.id if kind == "texture" else s.text, s.x, s.y, s.anchorY, round(s.r, 2)))
    return out


MAP_SHEETS = {
    # mapper : deux lieux, budget.mark_map=2 ; mapper2 : un lieu sans plafond ; noplace : mark_map sans lieu.
    "mapper": """format=1
id=mapper
name=Map Tester
frequencies=161.0
actions=say,mark_map,remember
budget.mark_map=2
place=mill 10600,9300,0 Old mill
place=pharmacy 11920,6905,-1 West Point <b>pharmacy</b>
[prompt]
You are Map Tester, a voice of the offline test bench who knows places.
""",
    "mapper2": """format=1
id=mapper2
name=Second Mapper
frequencies=162.0
actions=say,mark_map
place=farm 8000,8000,0 Farm
[prompt]
You are Second Mapper, another voice of the offline test bench.
""",
    "noplace": """format=1
id=noplace
name=No Place
frequencies=163.0
actions=say,remember
place=mill 10600,9300,0 Old mill
[prompt]
You are No Place, a voice that does not mark maps.
""",
}


def write_map(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in MAP_SHEETS.items():
        (folder / f"{name}.txt").write_text(text, encoding="utf-8")


def scenario_map_bridge(tmp: Path) -> None:
    """E07-T04, pont seul : le prompt d'une fiche à lieux propose mark_map avec les identifiants et libellés des
    lieux, jamais leurs coordonnées, et un exemple au premier identifiant ; bounded_actions garde un identifiant de la
    fiche et retire un identifiant inconnu, un paramètre en trop ou absent ; une fiche mark_map sans lieu reste en mode
    texte."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    exchange = tmp / "map-bridge"
    write_map(exchange)
    voices = rb.Voices(exchange / "personas")
    mapper = voices.get("mapper")
    assert [(p.id, p.x, p.y, p.z, p.label) for p in mapper.places] == [
        ("mill", 10600, 9300, 0, "Old mill"), ("pharmacy", 11920, 6905, -1, "West Point <b>pharmacy</b>")]
    assert rb.offered_actions(mapper) == ["mark_map", "remember"]
    req = {"id": "4-4", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "Where can I find medicine?", "voice": "mapper"}
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or (
            '{"say": "Try the pharmacy.", "actions": [{"type": "mark_map", "place": "pharmacy"}, '
            '{"type": "mark_map", "place": "bunker"}, {"type": "mark_map", "place": "mill", "x": 1}]}')
        out = rb.answer({}, rb.Conversations(exchange), "s", req, voices)
    finally:
        rb.call_llm = saved
    system = seen[-1][0]["content"]
    assert "Allowed action types: mark_map, remember." in system, system
    assert "Places you know (id: label):\n  - mill: Old mill\n  - pharmacy: West Point <b>pharmacy</b>" in system, system
    assert '{"type": "mark_map", "place": "mill"}' in system, system
    for secret in ("10600", "9300", "11920", "6905"):
        assert secret not in system, (secret, system)
    # Identifiant de la fiche gardé ; inconnu ou paramètre en trop retirés.
    assert out["actions"] == [{"type": "mark_map", "place": "pharmacy"}], out
    assert rb.bounded_actions(mapper, [{"type": "mark_map"}, {"type": "mark_map", "place": 3},
                                       {"type": "mark_map", "place": "MILL"},
                                       {"type": "mark_map", "place": "mill"}]) == [
        {"type": "mark_map", "place": "mill"}]
    # Lieux d'une autre voix : jamais admis.
    assert rb.bounded_actions(voices.get("mapper2"), [{"type": "mark_map", "place": "mill"}]) == []
    # noplace : mark_map non autorisée (lieux sans action) ; une fiche mark_map sans lieu reste en mode texte.
    assert rb.offered_actions(voices.get("noplace")) == ["remember"]
    assert "mark_map" not in rb.actions_prompt(voices.get("noplace"))
    folder = tmp / "map-bridge-empty" / "personas"
    folder.mkdir(parents=True)
    (folder / "empty.txt").write_text(MAP_SHEETS["mapper2"].replace("id=mapper2", "id=empty")
                                      .replace("place=farm 8000,8000,0 Farm\n", ""), encoding="utf-8")
    empty = rb.Voices(folder).get("empty")
    assert empty is not None and empty.places == [] and not rb.structured(empty)


def scenario_map_client(tmp: Path) -> None:
    """E07-T04, client seul (RS_MapActions, doublures du Java) : la commande map_mark pose une icône et le libellé au
    centre de la case, une seule API de symboles par partie, sans texte flottant (E07-T08 : l'appelant est averti par
    une ligne « mark » de son historique radio, tests/test_radio_history.py MapMarkTests) ; pas de doublon (même pour un illettré, texte repéré par
    sa position) ; un symbole effacé par le joueur est reposé ; les autres symboles du joueur ne bloquent rien ;
    arguments invalides ou carte absente : rien, une ligne console."""
    exchange = tmp / "map-client"
    exchange.mkdir()
    game = map_game("client", exchange, Clock())
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
    g = game.g
    player = g.makePlayer("kate")
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    t = game.rt.table_from
    command = lambda args: g.fire("OnServerCommand", "RadioSurvivor", "map_mark", t(args))
    mill = {"x": 10600, "y": 9300, "z": 0, "label": "Old <b>mill</b>"}
    # Un symbole du joueur ailleurs, et une icône Target de lui au même point (avant tout repère : sans effet sur le
    # texte, mais l'icône compte comme présente).
    api = g.UIWorldMap.new(t({})).getAPIv3()
    api.setMapItem(api, g.MapItem.getSingleton())
    own = api.getSymbolsAPIv2(api)
    own.addTexture(own, "House", 10000.5, 9000.5)
    assert g.UI_CREATED == 1 and g.MAP_ITEM.listeners == 1

    command(mill)
    assert map_symbols(g) == [
        ("texture", "House", 10000.5, 9000.5, 0, 1.0),
        ("texture", "Target", 10600.5, 9300.5, 1.0, 0.7),
        ("text", "Old  b mill /b", 10600.5, 9300.5, 0.0, 0.7)], map_symbols(g)
    icon, text = lua_list(g.MAP_ITEM.symbols)[1:]
    assert (icon.anchorX, icon.scale, icon.errorTexture, text.translated, text.layer) == (
        0.5, 0.666, False, True, "text-note"), (icon.anchorX, icon.scale, icon.errorTexture)
    assert lua_list(g.GOOD_HALOS) == [] and lua_list(player.halos) == []
    assert g.UI_CREATED == 2 and g.MAP_ITEM.listeners == 2  # une API de plus, une seule pour le mod
    # Même lieu : aucun doublon ; illettré : le texte masqué ne trompe pas la recherche.
    command(mill)
    g.ILLITERATE = True
    assert text.getUntranslatedText(text) is None and text.getTranslatedText(text) == "???  ? ???? ??"
    command(dict(mill, label="Other label"))
    assert len(map_symbols(g)) == 3
    assert g.UI_CREATED == 2 and g.MAP_ITEM.listeners == 2
    g.ILLITERATE = False
    # Le joueur efface le libellé : seul le libellé est reposé ; libellé vide : icône seule.
    g.table.remove(g.MAP_ITEM.symbols, 3)
    command(mill)
    assert map_symbols(g)[1:] == [("texture", "Target", 10600.5, 9300.5, 1.0, 0.7),
                                  ("text", "Old  b mill /b", 10600.5, 9300.5, 0.0, 0.7)], map_symbols(g)
    command({"x": 8000, "y": 8000.9, "z": 0, "label": " \t "})
    assert map_symbols(g)[-1] == ("texture", "Target", 8000.5, 8000.5, 1.0, 0.7), map_symbols(g)
    assert lua_list(g.GOOD_HALOS) == [] and lua_list(player.halos) == []
    # Arguments invalides : rien, une ligne console.
    before = len(map_symbols(g))
    for bad in ({"y": 1, "label": "x"}, {"x": "a", "y": 1}, {"x": -5, "y": 3}):
        command(bad)
    assert len(map_symbols(g)) == before
    logs = [line for line in lua_list(g.LOGS) if "map mark" in line]
    assert logs == ["[RadioSurvivor] map mark not added: bad_args"] * 3, logs
    # Nouvelle partie (MapItem.Reset) : nouvelle API sur les symboles de la nouvelle partie.
    g.resetMapItem()
    command(mill)
    assert len(map_symbols(g)) == 2 and g.MAP_ITEM.listeners == 1 and g.UI_CREATED == 3
    # Carte absente (MapItem.getSingleton rend nil sans script Base.Map) : rien.
    g.MapItem.getSingleton = lambda: None
    command(mill)
    assert lua_list(g.LOGS)[-1] == "[RadioSurvivor] map mark not added: no_map"
    # Les autres commandes du serveur passent toujours par RS_RadioTalk.
    g.fire("OnServerCommand", "RadioSurvivor", "rejected", t({"reason": "Cooldown"}))
    assert lua_list(player.halos) == ["IGUI_RadioSurvivor_Reject_Cooldown"]


def scenario_map_server(tmp: Path) -> None:
    """E07-T04, serveur en solo (lupa) : mark_map acceptée pour un lieu de la fiche, le repère arrive sur la carte du
    joueur (appel direct en solo), aussi par une vraie réponse du pont ; refus bad_params (lieu inconnu, d'une autre
    voix, paramètre en trop ou absent), not_allowed (fiche sans mark_map), cooldown (30 s par voix), budget du jour,
    no_player (aucun usage compté) ; journal admin ; aucune coordonnée dans requests.txt."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    exchange = tmp / "map-server"
    exchange.mkdir()
    write_map(exchange)
    clock = Clock()
    game = map_game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    t = game.rt.table_from
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    player.radio.device.channel = 161000
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    personas = g.require("RadioSurvivor/RS_Personas")
    talk_module = g.require("RadioSurvivor/RS_RadioTalk")
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    assert const.MAP_MARK_COOLDOWN_MS == 30000

    def decide(voice, acts, day="1993-07-12", who=player):
        decisions = actions_mod.decide(personas.get(voice), "solo", t([t(a) for a in acts]), clock(),
                                       t({"player": who, "day": day}))
        return [(d.type, d.reason) for d in lua_list(decisions)]

    def marks():
        return [(s[1], s[2], s[3]) for s in map_symbols(g)]

    # Vraie réponse du pont : diffusion puis repère.
    talk_module.resetForTests()
    assert g.talk(player, "Where is the mill?") == "ok"
    requests = (exchange / "requests.txt").read_text(encoding="utf-8")
    req_id = re.search(r"(?m)^req=(.+)$", requests).group(1)
    assert "voice=mapper" in requests and "10600" not in requests and "9300" not in requests, requests
    body = {"version": 2, "kind": "radio_reply", "id": req_id, "say": ["North of the river."],
            "actions": [{"type": "mark_map", "place": "mill"}]}
    (exchange / "responses.txt").write_text(f"resp={req_id}\npayload={protocol.encode(body).hex()}\nend\n",
                                            encoding="utf-8")
    assert pump(lambda: len(g.BROADCASTS) == 1, [lambda: g.fire("OnTick")])
    assert marks() == [("Target", 10600.5, 9300.5), ("Old mill", 10600.5, 9300.5)], marks()
    logs = [line for line in lua_list(g.LOGS) if line.startswith("[RadioSurvivor] action ")]
    assert logs == ["[RadioSurvivor] action mark_map voice=mapper caller=solo accepted reason=ok"], logs

    # Refus de forme : lieu inconnu, lieu d'une autre voix, paramètre en trop, absent ou non texte.
    assert decide("mapper", [{"type": "mark_map", "place": "bunker"}, {"type": "mark_map", "place": "farm"},
                             {"type": "mark_map", "place": "mill", "label": "x"}]) == [("mark_map", "bad_params")] * 3
    assert decide("mapper", [{"type": "mark_map"}, {"type": "mark_map", "place": 7},
                             {"type": "mark_map", "place": "MILL"}]) == [("mark_map", "bad_params")] * 3
    # Fiche qui ne l'autorise pas (lieux sans mark_map).
    assert decide("noplace", [{"type": "mark_map", "place": "mill"}]) == [("mark_map", "not_allowed")]
    # Délai par voix (30 s réelles), puis budget du jour (2 : le premier repère compte), jour suivant.
    assert decide("mapper", [{"type": "mark_map", "place": "pharmacy"}]) == [("mark_map", "cooldown")]
    clock.offset += 31000
    # Appelant déconnecté : refusé, aucun usage compté.
    assert decide("mapper", [{"type": "mark_map", "place": "pharmacy"}], who=None) == [("mark_map", "no_player")]
    assert decide("mapper", [{"type": "mark_map", "place": "pharmacy"}]) == [("mark_map", "ok")]
    assert marks()[2:] == [("Target", 11920.5, 6905.5), ("West Point  b pharmacy /b", 11920.5, 6905.5)], marks()
    clock.offset += 31000
    assert decide("mapper", [{"type": "mark_map", "place": "mill"}]) == [("mark_map", "budget")]
    assert decide("mapper", [{"type": "mark_map", "place": "mill"}], day="1993-07-13") == [("mark_map", "ok")]
    # Même lieu marqué deux fois : aucun doublon sur la carte ; une autre voix a son propre délai.
    assert len(marks()) == 4
    assert decide("mapper2", [{"type": "mark_map", "place": "farm"}]) == [("mark_map", "ok")]
    assert marks()[-1] == ("Farm", 8000.5, 8000.5), marks()
    # Journal admin : une ligne par décision.
    log_mod = g.require("RadioSurvivor/RS_ActionLog")
    rows = [line.split("\t") for line in
            (exchange / (Path(log_mod.base()).name + ".log")).read_text(encoding="utf-8").split("\n")[1:-1]]
    assert [(r[2], r[4], r[5], r[7]) for r in rows[:2]] == [("mapper", "mark_map", "place=mill", "ok"),
                                                           ("mapper", "mark_map", "place=bunker", "bad_params")], rows
    assert [r[7] for r in rows].count("no_player") == 1 and [r[7] for r in rows].count("cooldown") == 1


def scenario_map_mp(tmp: Path) -> None:
    """E07-T04, multijoueur (serveur et deux clients, lupa) : mark_map envoie map_mark { x, y, z, label } au seul
    appelant (sendServerCommand à 4 arguments), jamais de diffusion à tous ; seul son client a le repère."""
    exchange = tmp / "map-mp"
    exchange.mkdir()
    write_map(exchange)
    clock = Clock()
    server = Game("server", exchange, clock)
    server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
    sg = server.g
    clients, sent = {}, []

    def to_client(*args):
        sent.append(args)
        if len(args) == 3:
            return
        c = clients[args[0].username]
        c.g.fire("OnServerCommand", args[1], args[2], c.table(args[3]))

    sg.sendServerCommand = to_client
    sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
    for name in ("alice", "bob"):
        c = map_game("client", exchange, clock)
        c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
        player = c.g.makePlayer(name)
        c.g.getPlayer = lambda p=player: p
        sg.makePlayer(name)
        clients[name] = c
    actions_mod = sg.require("RadioSurvivor/RS_Actions")
    personas = sg.require("RadioSurvivor/RS_Personas")
    decisions = actions_mod.decide(personas.get("mapper"), "alice",
                                   server.rt.table_from([server.rt.table_from({"type": "mark_map", "place": "mill"})]),
                                   clock(), server.rt.table_from({"player": sg.PLAYERS["alice"], "day": "1993-07-12"}))
    assert [(d.type, d.reason) for d in lua_list(decisions)] == [("mark_map", "ok")]
    assert len(sent) == 1 and len(sent[0]) == 4 and sent[0][0].username == "alice", sent
    assert (sent[0][1], sent[0][2]) == ("RadioSurvivor", "map_mark")
    args = dict(sent[0][3].items())
    assert args == {"x": 10600, "y": 9300, "z": 0, "label": "Old mill"}, args
    assert [s[1] for s in map_symbols(clients["alice"].g)] == ["Target", "Old mill"]
    assert map_symbols(clients["bob"].g) == []


# --- E07-T05 : action reveal_area -----------------------------------------------------------------------------------

# Doublures fidèles au Java 42.21 de la carte « connue » (zombie/worldMap/WorldMapVisited.java,
# WorldMapVisitedServer.java, bytecode de coordToUnit lu par javap) : un bit « connu » par bloc de 32 x 32 cases,
# index relatif à la métagrille (cellules de 256 cases, MAP_GRID) ; setKnownInSquares(minX, minY, maxX, maxY) ramène
# chaque coordonnée dans la carte (normalizeX/Y : 0..largeur*256-1), ne fait rien si xMin == xMax ou yMin == yMax,
# puis marque les blocs de coordToUnit(min, false) à coordToUnit(max, true) inclus ; coordToUnit : c / 32, moins 1 si
# isMax et que cet INDEX DE BLOC est multiple de 32 (défaut vanilla : un bord exclu aligné révèle un bloc de plus, et le
# bloc d'index multiple de 32 ne peut pas être le dernier). isKnown(x, y) = hasFlags(x-1, y-1, x+1, y+1, any), où le
# bord haut est corrigé par % 32 sur la coordonnée. WorldMapVisitedServer : un tableau par nom de compte de la
# connexion du joueur, rien envoyé (setKnownInSquares, WorldMapVisitedServer.java:69-75). getWorld():getMetaGrid() :
# bornes en cellules (IsoMetaGrid.getMinX..getMaxY, inclus).
REVEAL_DOUBLES = r"""
MAP_GRID = { minX = 0, minY = 0, maxX = 69, maxY = 54 }
local function size() return (MAP_GRID.maxX - MAP_GRID.minX + 1) * 256, (MAP_GRID.maxY - MAP_GRID.minY + 1) * 256 end
local function clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
local function normX(x) local w = size() return clamp(x - MAP_GRID.minX * 256, 0, w - 1) end
local function normY(y) local _, h = size() return clamp(y - MAP_GRID.minY * 256, 0, h - 1) end
local function unit(c, isMax)
    c = math.floor(c / 32)
    if isMax and c % 32 == 0 then c = c - 1 end
    return c
end
function VISIT_SET(known, x1, y1, x2, y2)
    x1, y1, x2, y2 = normX(x1), normY(y1), normX(x2), normY(y2)
    if x1 == x2 or y1 == y2 then return false end
    for uy = unit(y1, false), unit(y2, true) do
        for ux = unit(x1, false), unit(x2, true) do known[ux .. "," .. uy] = true end
    end
    return true
end
local function newVisited()
    local v = { known = {}, calls = {} }
    function v:setKnownInSquares(x1, y1, x2, y2)
        table.insert(self.calls, { x1, y1, x2, y2 })
        VISIT_SET(self.known, x1, y1, x2, y2)
    end
    function v:isKnown(x, y)
        local x1, y1, x2, y2 = normX(x - 1), normY(y - 1), normX(x + 1), normY(y + 1)
        if x1 == x2 or y1 == y2 then return false end
        local ux2, uy2 = math.floor(x2 / 32), math.floor(y2 / 32)
        if x2 % 32 == 0 then ux2 = ux2 - 1 end
        if y2 % 32 == 0 then uy2 = uy2 - 1 end
        for uy = math.floor(y1 / 32), uy2 do
            for ux = math.floor(x1 / 32), ux2 do if self.known[ux .. "," .. uy] then return true end end
        end
        return false
    end
    return v
end
VISITED = newVisited()
WorldMapVisited = { getInstance = function() return VISITED end }
SERVER_VISITED = { known = {}, calls = {} }
function SERVER_VISITED:setKnownInSquares(player, x1, y1, x2, y2)
    local user = player and player:getUsername()
    if user == nil then return end
    table.insert(self.calls, { user, x1, y1, x2, y2 })
    self.known[user] = self.known[user] or {}
    VISIT_SET(self.known[user], x1, y1, x2, y2)
end
WorldMapVisitedServer = { getInstance = function() return SERVER_VISITED end }
local GRID = {}
function GRID:getMinX() return MAP_GRID.minX end
function GRID:getMinY() return MAP_GRID.minY end
function GRID:getMaxX() return MAP_GRID.maxX end
function GRID:getMaxY() return MAP_GRID.maxY end
local baseWorld = getWorld
getWorld = function()
    local w = baseWorld()
    w.getMetaGrid = function() return GRID end
    return w
end
CLIENT_COMMANDS = {}
"""


def reveal_game(mode: str, exchange: Path, clock) -> Game:
    game = map_game(mode, exchange, clock)
    game.rt.execute(REVEAL_DOUBLES)
    return game


def known_blocks(known) -> set[tuple[int, int]]:
    """Blocs « connus » (index de bloc de 32 cases, relatifs à la métagrille) d'une table de doublure."""
    return {tuple(int(v) for v in key.split(",")) for key in known.keys()}


def blocks_of(x1: int, y1: int, x2: int, y2: int) -> set[tuple[int, int]]:
    """Blocs entiers d'un rectangle de cases [x1, x2[ x [y1, y2[ (bords multiples de 32, métagrille en 0,0)."""
    return {(bx, by) for bx in range(x1 // 32, x2 // 32) for by in range(y1 // 32, y2 // 32)}


REVEAL_SHEETS = {
    # revealer : deux lieux (dont un hors de la carte du banc), budget.reveal_area=2 ; both : mark_map et
    # reveal_area ; mapless : reveal_area sans lieu ; marker : mark_map sans reveal_area.
    "revealer": """format=1
id=revealer
name=Reveal Tester
frequencies=171.0
actions=say,reveal_area
budget.reveal_area=2
place=mill 10600,9300,0 Old mill
place=far 30000,30000,0 Beyond the map
[prompt]
You are Reveal Tester, a voice of the offline test bench who knows neighbourhoods.
""",
    "both": """format=1
id=both
name=Both Tester
frequencies=172.0
actions=say,mark_map,reveal_area,remember
place=mill 10600,9300,0 Old mill
place=farm 8000,8000,0 Farm
[prompt]
You are Both Tester, a voice of the offline test bench.
""",
    "mapless": """format=1
id=mapless
name=Mapless Tester
frequencies=173.0
actions=say,reveal_area
[prompt]
You are Mapless Tester, a voice without places.
""",
    "marker": """format=1
id=marker
name=Marker Tester
frequencies=174.0
actions=say,mark_map
place=mill 10600,9300,0 Old mill
[prompt]
You are Marker Tester, a voice that only marks.
""",
}


def write_reveal(exchange: Path) -> None:
    folder = exchange / "personas"
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in REVEAL_SHEETS.items():
        (folder / f"{name}.txt").write_text(text, encoding="utf-8")


def scenario_reveal_bridge(tmp: Path) -> None:
    """E07-T05, pont seul : reveal_area proposée seulement à une fiche qui a des lieux, avec les identifiants et
    libellés (une seule liste si mark_map l'est aussi), un exemple au premier identifiant et aucune coordonnée ;
    bounded_actions garde un lieu de la fiche, retire un identifiant inconnu, un paramètre en trop ou absent ; une fiche
    reveal_area sans lieu reste en mode texte."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    exchange = tmp / "reveal-bridge"
    write_reveal(exchange)
    voices = rb.Voices(exchange / "personas")
    revealer, both = voices.get("revealer"), voices.get("both")
    assert rb.offered_actions(revealer) == ["reveal_area"]
    assert rb.offered_actions(both) == ["mark_map", "reveal_area", "remember"]
    assert rb.offered_actions(voices.get("mapless")) == [] and not rb.structured(voices.get("mapless"))
    req = {"id": "5-5", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "What is around the mill?", "voice": "both"}
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or (
            '{"say": "Houses, mostly.", "actions": [{"type": "reveal_area", "place": "mill"}, '
            '{"type": "reveal_area", "place": "bunker"}, {"type": "reveal_area", "place": "farm", "size": 999}]}')
        out = rb.answer({}, rb.Conversations(exchange), "s", req, voices)
    finally:
        rb.call_llm = saved
    system = seen[-1][0]["content"]
    assert "Allowed action types: mark_map, reveal_area, remember." in system, system
    assert system.count("Places you know (id: label):") == 1, system
    assert "Places you know (id: label):\n  - mill: Old mill\n  - farm: Farm" in system, system
    assert '{"type": "reveal_area", "place": "mill"}' in system and "- reveal_area: fill in the caller" in system
    for secret in ("10600", "9300", "8000"):
        assert secret not in system, (secret, system)
    assert out["actions"] == [{"type": "reveal_area", "place": "mill"}], out
    assert rb.bounded_actions(revealer, [{"type": "reveal_area"}, {"type": "reveal_area", "place": 3},
                                         {"type": "reveal_area", "place": "Mill"},
                                         {"type": "reveal_area", "place": "far"}]) == [
        {"type": "reveal_area", "place": "far"}]
    # Lieu d'une autre voix ; fiche qui n'autorise pas reveal_area.
    assert rb.bounded_actions(revealer, [{"type": "reveal_area", "place": "farm"}]) == []
    assert rb.bounded_actions(voices.get("marker"), [{"type": "reveal_area", "place": "mill"}]) == []


def scenario_reveal_rect(tmp: Path) -> None:
    """E07-T05, serveur (lupa) : MapMarks.revealRect rend, pour tout lieu, un rectangle aux bords multiples de 32,
    d'au plus 5 blocs (160 cases) de côté, centré sur le bloc du lieu (exactement 160 loin des bords), contenant le lieu,
    rogné aux bornes de la carte (métagrille) ; rien pour un lieu hors de la carte."""
    import random
    exchange = tmp / "reveal-rect"
    exchange.mkdir()
    game = reveal_game("solo", exchange, Clock())
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
    g = game.g
    marks = g.require("RadioSurvivor/RS_MapMarks")
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    assert (const.MAP_REVEAL_MAX_SIDE, const.MAP_REVEAL_BLOCK, marks.revealBlocks()) == (160, 32, 5)
    bounds = marks.mapBounds()
    width, height = 70 * 256, 55 * 256
    assert dict(bounds.items()) == {"x1": 0, "y1": 0, "x2": width, "y2": height}, dict(bounds.items())
    rng = random.Random(7)
    points = [(0, 0), (5, 5), (31, 31), (32, 32), (63, 64), (width - 1, height - 1), (width - 40, 100),
              (100, height - 1), (10600, 9300), (10599.5, 9300.9), (width // 2, height // 2)]
    points += [(rng.randrange(width), rng.randrange(height)) for _ in range(300)]
    for x, y in points:
        r = marks.revealRect(x, y, bounds)
        assert r is not None, (x, y)
        x1, y1, x2, y2 = r.x1, r.y1, r.x2, r.y2
        for edge in (x1, y1, x2, y2):
            assert edge == int(edge) and int(edge) % 32 == 0, ((x, y), (x1, y1, x2, y2))
        assert 0 < x2 - x1 <= 160 and 0 < y2 - y1 <= 160, ((x, y), (x1, y1, x2, y2))
        assert 0 <= x1 and x2 <= width and 0 <= y1 and y2 <= height, ((x, y), (x1, y1, x2, y2))
        assert x1 <= x < x2 and y1 <= y < y2, ((x, y), (x1, y1, x2, y2))
        bx, by = int(x) // 32, int(y) // 32
        if 2 <= bx <= width // 32 - 3:
            assert (x1, x2) == ((bx - 2) * 32, (bx + 3) * 32), ((x, y), (x1, x2))
        if 2 <= by <= height // 32 - 3:
            assert (y1, y2) == ((by - 2) * 32, (by + 3) * 32), ((x, y), (y1, y2))
    corner = marks.revealRect(5, 5, bounds)
    assert (corner.x1, corner.y1, corner.x2, corner.y2) == (0, 0, 96, 96)
    edge = marks.revealRect(width - 1, height - 1, bounds)
    assert (edge.x1, edge.y1, edge.x2, edge.y2) == (width - 96, height - 96, width, height)
    # Hors de la carte : rien ; sans bornes : rogné aux coordonnées positives seulement.
    for x, y in ((30000, 30000), (-500, 100), (100, height + 200)):
        assert marks.revealRect(x, y, bounds) is None, (x, y)
    free = marks.revealRect(30000, 31, None)
    assert (free.x1, free.y1, free.x2, free.y2) == (29920, 0, 30080, 96)
    assert marks.revealRect("a", 3, bounds) is None


def scenario_reveal_client(tmp: Path) -> None:
    """E07-T05, client seul (RS_MapActions, doublure fidèle de WorldMapVisited) : map_reveal rend connus exactement les
    blocs du rectangle, rien autour ; bord haut passé inclus (x2 - 1) : jamais le bloc de plus qu'un bord exclu aligné
    révélerait ; un dernier bloc d'index multiple de 32 n'est pas révélé (défaut vanilla, surface plus petite, jamais
    plus grande) ; rectangle non aligné, vide, négatif ou plus grand que le plafond : rien, une ligne console ;
    WorldMapVisited absent : rien ; aucune commande vanilla « map » envoyée au serveur."""
    exchange = tmp / "reveal-client"
    exchange.mkdir()
    game = reveal_game("client", exchange, Clock())
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
    g = game.g
    player = g.makePlayer("kate")
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    sent = []
    g.sendClientCommand = lambda *args: sent.append(args)
    t = game.rt.table_from
    command = lambda args: g.fire("OnServerCommand", "RadioSurvivor", "map_reveal", t(args))
    visited = g.VISITED
    assert not visited.isKnown(visited, 10600, 9300)
    command({"x1": 10560, "y1": 9248, "x2": 10720, "y2": 9408})
    assert known_blocks(visited.known) == blocks_of(10560, 9248, 10720, 9408), sorted(known_blocks(visited.known))
    assert [tuple(c.values()) for c in lua_list(visited.calls)] == [(10560, 9248, 10719, 9407)]
    assert visited.isKnown(visited, 10600, 9300) and visited.isKnown(visited, 10719, 9407)
    # Hors zone (isKnown regarde aussi la case voisine : un bloc plus loin) : inconnu.
    for x, y in ((10520, 9300), (10760, 9300), (10600, 9210), (10600, 9440)):
        assert not visited.isKnown(visited, x, y), (x, y)
    # La même zone une seconde fois : idempotent.
    command({"x1": 10560, "y1": 9248, "x2": 10720, "y2": 9408})
    assert len(known_blocks(visited.known)) == 25
    # Bord exclu aligné passé tel quel : un bloc de plus de chaque côté (preuve du choix x2 - 1).
    trial = game.rt.table_from({})
    g.VISIT_SET(trial, 0, 0, 160, 160)
    assert len(known_blocks(trial)) == 36
    trial = game.rt.table_from({})
    g.VISIT_SET(trial, 0, 0, 159, 159)
    assert known_blocks(trial) == blocks_of(0, 0, 160, 160)
    # Dernier bloc d'index multiple de 32 (352) : non révélé, jamais le bloc d'après.
    before = known_blocks(visited.known)
    command({"x1": 348 * 32, "y1": 100 * 32, "x2": 353 * 32, "y2": 105 * 32})
    added = known_blocks(visited.known) - before
    assert added == blocks_of(348 * 32, 100 * 32, 352 * 32, 105 * 32), sorted(added)
    # Arguments refusés : rien de révélé, une ligne console chacun.
    before = known_blocks(visited.known)
    calls = len(lua_list(visited.calls))
    for bad in ({"x1": 10561, "y1": 9248, "x2": 10721, "y2": 9408}, {"x1": 0, "y1": 0, "x2": 192, "y2": 96},
                {"x1": 64, "y1": 64, "x2": 64, "y2": 96}, {"x1": -32, "y1": 0, "x2": 64, "y2": 64},
                {"x1": 64, "y1": 96, "x2": 32, "y2": 160}, {"y1": 0, "x2": 64, "y2": 64},
                {"x1": "a", "y1": 0, "x2": 64, "y2": 64}, {"x1": 0.5, "y1": 0, "x2": 64, "y2": 64}):
        command(bad)
    assert known_blocks(visited.known) == before and len(lua_list(visited.calls)) == calls
    logs = [line for line in lua_list(g.LOGS) if "map area" in line]
    assert logs == ["[RadioSurvivor] map area not revealed: bad_args"] * 8, logs
    g.WorldMapVisited = None
    command({"x1": 0, "y1": 0, "x2": 64, "y2": 64})
    assert lua_list(g.LOGS)[-1] == "[RadioSurvivor] map area not revealed: no_map"
    assert [a for a in sent if len(a) > 1 and a[1] == "map"] == [], sent
    # Les repères mark_map passent toujours.
    g.fire("OnServerCommand", "RadioSurvivor", "map_mark", t({"x": 10600, "y": 9300, "z": 0, "label": "Old mill"}))
    assert [s[1] for s in map_symbols(g)] == ["Target", "Old mill"]


def scenario_reveal_server(tmp: Path) -> None:
    """E07-T05, serveur en solo (lupa) : reveal_area acceptée pour un lieu de la fiche, la zone est connue sur la
    carte du joueur (appel direct en solo, rien dans WorldMapVisitedServer) ; refus bad_params (lieu inconnu, d'une
    autre voix, paramètre en trop ou absent), not_allowed, cooldown (60 s par voix), budget du jour, no_player et
    off_map (aucun usage compté) ; journal admin ; aucune coordonnée dans requests.txt."""
    exchange = tmp / "reveal-server"
    exchange.mkdir()
    write_reveal(exchange)
    clock = Clock()
    game = reveal_game("solo", exchange, clock)
    game.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua",
              "client/RadioSurvivor_Client.lua")
    g = game.g
    t = game.rt.table_from
    g.sendClientCommand = lambda p, m, c, a: g.fire("OnClientCommand", m, c, p, a)
    player = g.makePlayer("Kate")
    player.radio.device.channel = 171000
    g.getPlayer = lambda: player
    g.getSpecificPlayer = lambda n: player
    g.fire("OnLoadRadioScripts", g.MANAGER, True)
    actions_mod = g.require("RadioSurvivor/RS_Actions")
    personas = g.require("RadioSurvivor/RS_Personas")
    const = g.require("RadioSurvivor/RadioSurvivor_Const")
    talk_module = g.require("RadioSurvivor/RS_RadioTalk")
    assert const.MAP_REVEAL_COOLDOWN_MS == 60000

    def decide(voice, acts, day="1993-07-12", who=player):
        decisions = actions_mod.decide(personas.get(voice), "solo", t([t(a) for a in acts]), clock(),
                                       t({"player": who, "day": day}))
        return [(d.type, d.reason) for d in lua_list(decisions)]

    mill = blocks_of(10528, 9216, 10688, 9376)
    # Demande au pont : identifiants seulement.
    talk_module.resetForTests()
    assert g.talk(player, "What is around the mill?") == "ok"
    requests = (exchange / "requests.txt").read_text(encoding="utf-8")
    assert "voice=revealer" in requests and "10600" not in requests and "30000" not in requests, requests

    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "ok")]
    assert known_blocks(g.VISITED.known) == mill, sorted(known_blocks(g.VISITED.known))
    assert lua_list(g.SERVER_VISITED.calls) == []
    logs = [line for line in lua_list(g.LOGS) if line.startswith("[RadioSurvivor] action ")]
    assert logs[-1] == "[RadioSurvivor] action reveal_area voice=revealer caller=solo accepted reason=ok", logs
    # Refus de forme, d'autorisation.
    assert decide("revealer", [{"type": "reveal_area", "place": "bunker"}, {"type": "reveal_area", "place": "farm"},
                               {"type": "reveal_area", "place": "mill", "size": 3}]) == [("reveal_area", "bad_params")] * 3
    assert decide("revealer", [{"type": "reveal_area"}, {"type": "reveal_area", "place": 7}]) == [
        ("reveal_area", "bad_params")] * 2
    assert decide("marker", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "not_allowed")]
    # Délai par voix (60 s réelles) ; appelant déconnecté et lieu hors de la carte : aucun usage compté.
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "cooldown")]
    clock.offset += 31000
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "cooldown")]
    clock.offset += 31000
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}], who=None) == [("reveal_area", "no_player")]
    assert decide("revealer", [{"type": "reveal_area", "place": "far"}]) == [("reveal_area", "off_map")]
    assert known_blocks(g.VISITED.known) == mill
    # Budget du jour (2 : la première révélation compte), puis jour suivant.
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "ok")]
    clock.offset += 61000
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}]) == [("reveal_area", "budget")]
    assert decide("revealer", [{"type": "reveal_area", "place": "mill"}], day="1993-07-13") == [("reveal_area", "ok")]
    # Délais séparés : mark_map de la même voix n'est pas retenue par celui de reveal_area.
    assert decide("both", [{"type": "reveal_area", "place": "farm"}, {"type": "mark_map", "place": "farm"}]) == [
        ("reveal_area", "ok"), ("mark_map", "ok")]
    assert known_blocks(g.VISITED.known) == mill | blocks_of(7936, 7936, 8096, 8096)
    assert [s[1] for s in map_symbols(g)] == ["Target", "Farm"]
    # Journal admin : une ligne par décision, le lieu par son identifiant seulement.
    log_mod = g.require("RadioSurvivor/RS_ActionLog")
    text = (exchange / (Path(log_mod.base()).name + ".log")).read_text(encoding="utf-8")
    rows = [line.split("\t") for line in text.split("\n")[1:-1]]
    assert [(r[2], r[4], r[5], r[7]) for r in rows[:2]] == [("revealer", "reveal_area", "place=mill", "ok"),
                                                           ("revealer", "reveal_area", "place=bunker", "bad_params")]
    assert [r[7] for r in rows].count("off_map") == 1 and [r[7] for r in rows].count("no_player") == 1
    assert "10528" not in text and "9216" not in text


def scenario_reveal_mp(tmp: Path) -> None:
    """E07-T05, multijoueur (serveur et deux clients, lupa) : reveal_area envoie map_reveal { x1, y1, x2, y2 } au seul
    appelant (sendServerCommand à 4 arguments) et inscrit la zone dans la seule carte de son compte tenue par le serveur
    (WorldMapVisitedServer, bord haut inclus) ; l'autre joueur n'a rien, ni chez lui ni sur le serveur."""
    exchange = tmp / "reveal-mp"
    exchange.mkdir()
    write_reveal(exchange)
    clock = Clock()
    server = reveal_game("server", exchange, clock)
    server.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "server/RadioSurvivor_Server.lua")
    sg = server.g
    clients, sent = {}, []

    def to_client(*args):
        sent.append(args)
        if len(args) == 3:
            return
        c = clients[args[0].username]
        c.g.fire("OnServerCommand", args[1], args[2], c.table(args[3]))

    sg.sendServerCommand = to_client
    sg.fire("OnLoadRadioScripts", sg.MANAGER, True)
    for name in ("alice", "bob"):
        c = reveal_game("client", exchange, clock)
        c.load("shared/RadioSurvivor/RadioSurvivor_Const.lua", "client/RadioSurvivor_Client.lua")
        player = c.g.makePlayer(name)
        c.g.getPlayer = lambda p=player: p
        sg.makePlayer(name)
        clients[name] = c
    actions_mod = sg.require("RadioSurvivor/RS_Actions")
    personas = sg.require("RadioSurvivor/RS_Personas")
    decisions = actions_mod.decide(personas.get("revealer"), "alice",
                                   server.rt.table_from([server.rt.table_from({"type": "reveal_area", "place": "mill"})]),
                                   clock(), server.rt.table_from({"player": sg.PLAYERS["alice"], "day": "1993-07-12"}))
    assert [(d.type, d.reason) for d in lua_list(decisions)] == [("reveal_area", "ok")]
    assert len(sent) == 1 and len(sent[0]) == 4 and sent[0][0].username == "alice", sent
    assert (sent[0][1], sent[0][2]) == ("RadioSurvivor", "map_reveal")
    assert dict(sent[0][3].items()) == {"x1": 10528, "y1": 9216, "x2": 10688, "y2": 9376}, dict(sent[0][3].items())
    mill = blocks_of(10528, 9216, 10688, 9376)
    assert [tuple(c.values()) for c in lua_list(sg.SERVER_VISITED.calls)] == [("alice", 10528, 9216, 10687, 9375)]
    assert known_blocks(sg.SERVER_VISITED.known["alice"]) == mill and sg.SERVER_VISITED.known["bob"] is None
    assert known_blocks(clients["alice"].g.VISITED.known) == mill
    assert known_blocks(clients["bob"].g.VISITED.known) == set()


# --- E11-T08 : mission donnée par une voix ------------------------------------------------------------------------

MISSION_SHEET = """format=1
id=giver
name=Job Giver
frequencies=164.0
actions=say,start_mission
place=depot 10600,9300,0 Fuel depot
secret=The radio mast hides the cache.
[prompt]
You are Job Giver, a voice of the offline test bench who hands out scouting jobs.
"""


def scenario_voice_mission_bridge(tmp: Path) -> None:
    """E11-T08, pont + écriture Lua : start_mission proposée avec sa description et son exemple (gabarit en liste
    fermée, lieu choisi par le serveur) ; bounded_actions retire un gabarit inconnu, un paramètre en trop ou absent ;
    le champ mission= écrit par le vrai RS_Transport (contexte de RS_MissionVoice) est relu par parse_requests et
    mission_context ; le prompt porte le type de lieu, les indices, « pas encore » ou « compte rendu accepté » et la
    récompense, jamais de chiffre ni de coordonnée ; un indice chiffré, une récompense hors fiche, un champ illisible
    sont écartés ; sans mission= le prompt est celui d'avant E11-T08."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    exchange = tmp / "voice-mission"
    folder = exchange / "personas"
    folder.mkdir(parents=True)
    (folder / "giver.txt").write_text(MISSION_SHEET, encoding="utf-8")
    voices = rb.Voices(folder)
    giver = voices.get("giver")
    # E11-T13 : report_mission (compte rendu à la radio) est permise avec start_mission sans être listée par la fiche.
    assert rb.offered_actions(giver) == ["start_mission", "report_mission"] and rb.structured(giver)
    assert rb.sheet_actions(giver) == ["say", "start_mission", "report_mission"]
    system = rb.actions_prompt(giver)
    assert "Allowed action types: start_mission, report_mission." in system, system
    assert '{"type": "start_mission", "template": "scout"}' in system and '{"type": "report_mission"}' in system
    assert "The server chooses the place and objective" in system and "10600" not in system, system
    assert rb.bounded_actions(giver, [{"type": "start_mission"}, {"type": "start_mission", "template": "deliver"},
                                      {"type": "start_mission", "template": "scout", "place": "depot"},
                                      {"type": "start_mission", "template": "scout"}]) == [
        {"type": "start_mission", "template": "scout"}]
    assert rb.bounded_actions(giver, [{"type": "report_mission", "mission": "x"}, {"type": "report_mission"}]) == [
        {"type": "report_mission"}]
    (folder / "talker.txt").write_text(MISSION_SHEET.replace("id=giver", "id=talker").replace("164.0", "165.0")
                                       .replace("actions=say,start_mission", "actions=say,remember"), encoding="utf-8")
    talker = rb.Voices(folder).get("talker")
    assert "report_mission" not in rb.offered_actions(talker)
    assert rb.bounded_actions(talker, [{"type": "report_mission"}]) == []

    # Champ mission= écrit par le vrai RS_Transport à partir d'un contexte de RS_MissionVoice.
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute("isClient = function() return false end")
    g.getFileWriter = lambda name, create, append: file_writer(exchange / Path(name).name, name, append)
    paths = ";".join((LUA / side).as_posix() + "/?.lua" for side in ("shared", "server"))
    rt.execute(f"package.path = [[{paths};]] .. package.path")
    codec = rt.eval('require("RadioSurvivor/RS_Codec")')
    transport = rt.eval('require("RadioSurvivor/RS_Transport")')
    context = rt.eval("""{ state = "active", remainingMs = 5400000, kind = "scout", place = "house",
        clues = { "The place is a large single-storey house.", "There is a gas station a short walk to the north." },
        zoneReached = false, report = "radio", turn = "not_yet" }""")
    field = codec.hexBytes(codec.encodeBytes(context))
    req = rt.eval("{}")
    for key, value in {"id": "8-8", "sentAt": 1, "caller": "kate", "voice": "giver", "name": "Kate",
                       "text": "I went there.", "mission": field}.items():
        req[key] = value
    transport.radio = rt.table_from([req])
    assert transport.write()
    parsed = rb.parse_requests((exchange / "requests.txt").read_text(encoding="utf-8"))
    sent = parsed[1][0]
    assert sent["mission"] == field, sent
    mission = rb.mission_context(sent, giver)
    assert mission == {"kind": "scout", "state": "active", "turn": "not_yet", "place": "house", "minutes": 90, "reached": False,
                       "clues": ["The place is a large single-storey house.",
                                 "There is a gas station a short walk to the north."], "reward": None,
                       "to_report": False}, mission
    prompt = rb.mission_prompt(mission, "[Caller 1]")
    assert "has NOT been there yet" in prompt and "kind: house" in prompt and "about 90 minutes" in prompt, prompt
    assert "never add report_mission" in prompt, prompt
    # Mission ouverte : la voix redit les indices si on le lui demande (E11-T09).
    assert "tell them the clues again" in prompt, prompt
    # E11-T10 : zone approximative entourée sur la carte de l'appelant tant que la mission n'est pas réussie.
    assert "is circled on [Caller 1]'s map" in prompt, prompt
    # Consigne juste après la création (E11-T09, tour « briefing ») : indices + ordre de les dire, sans « pas encore ».
    briefing = rb.mission_context({**sent, "mission": codec.hexBytes(codec.encodeBytes(rt.eval("""{ state = "active",
        remainingMs = 7200000, kind = "scout", place = "house", clues = { "The place is a large single-storey house." },
        zoneReached = false, report = "radio", turn = "briefing" }""")))}, giver)
    assert briefing and briefing["turn"] == "briefing", briefing
    told = rb.mission_prompt(briefing, "[Caller 1]")
    assert "Tell them NOW where to go" in told and "every clue above" in told, told
    assert "- What you know of the place: The place is a large single-storey house." in told, told
    assert "has NOT been there yet" not in told and "tell them the clues again" not in told, told
    # E11-T13 : objectif rempli (tour « report_due ») : la voix reconnaît le compte rendu et ajoute report_mission ;
    # le lieu que donnera la réussite est dit d'avance.
    due = rb.mission_context({**sent, "mission": codec.hexBytes(codec.encodeBytes(rt.eval("""{ state = "active",
        remainingMs = 600000, kind = "scout", place = "house", clues = { "The place is a large single-storey house." },
        zoneReached = true, toReport = true, report = "radio", turn = "report_due", reward = "Fuel depot" }""")))},
        giver)
    assert due and (due["turn"], due["to_report"], due["reward"]) == ("report_due", True, "Fuel depot"), due
    told = rb.mission_prompt(due, "[Caller 1]")
    assert "you only wait for their report" in told and '{"type": "report_mission"}' in told, told
    assert "Fuel depot" in told and "has NOT been there yet" not in told, told
    assert not re.search(r"\d", told.replace("[Caller 1]", "").replace("about 10 minutes", "")), told

    # Réponse complète : section mission dans le prompt système, avant la consigne de format ; sans mission= le prompt
    # est identique à celui d'avant E11-T08.
    seen = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **_: seen.append(messages) or '{"say": "Not yet.", "actions": []}'
        (exchange / "with").mkdir()
        base = {k: v for k, v in sent.items() if k != "mission"}
        rb.answer({}, rb.Conversations(exchange), "s", base, voices)
        rb.answer({}, rb.Conversations(exchange / "with"), "s", sent, voices)
    finally:
        rb.call_llm = saved
    without, with_mission = seen[0][0]["content"], seen[1][0]["content"]
    assert "The job you gave" not in without, without
    assert with_mission.index("The job you gave") < with_mission.index("Reply format"), with_mission
    assert with_mission.replace(prompt, "") == without, "the mission section changed something else"

    import npc_protocol as protocol

    def encoded(value) -> str:
        return protocol.encode(value).hex()

    success = {"state": "success", "remainingMs": 0, "kind": "scout", "place": "house", "zoneReached": True,
               "report": "radio", "turn": "success", "reward": "Fuel depot",
               "clues": {1: "The place is 4 floors high at 10600, 9300.", 2: "The radio mast hides the cache.",
                         3: "There is a church nearby."}}
    mission = rb.mission_context({"id": "9", "mission": encoded(success)}, giver)
    assert mission["clues"] == ["There is a church nearby."] and mission["reward"] == "Fuel depot", mission
    prompt = rb.mission_prompt(mission, "[Caller 1]")
    assert "the job is done" in prompt and "Fuel depot" in prompt and "Time left" not in prompt, prompt
    assert "circled on" not in prompt, prompt   # E11-T10 : plus de zone après la réussite
    assert not re.search(r"\d", prompt.replace("[Caller 1]", "")), prompt
    # Récompense absente de la fiche, gabarit ou tour inconnus, chiffre dans le lieu, champ illisible : écartés.
    assert rb.mission_context({"mission": encoded(dict(success, reward="Secret bunker"))}, giver)["reward"] is None
    for bad in (dict(success, kind="invented"), dict(success, turn="done"), dict(success, state="failed"),
                dict(success, place="house 12")):
        assert rb.mission_context({"mission": encoded(bad)}, giver) is None, bad
    assert rb.mission_context({"mission": "zz"}, giver) is None
    assert rb.mission_context({"mission": "ab" * 5000}, giver) is None
    assert rb.mission_prompt(None, "[Caller 1]") == ""


def scenario_report_done_bridge(tmp: Path) -> None:
    """E11-T13, pont du carnet : l'intention report_done (compte rendu d'une mission dont le serveur a vu l'objectif
    rempli) n'est admise qu'avec context.reportable (npc_talk seulement), offre vide ; hors contrat, la parole est
    gardée sans effet ; une offre qui nomme la mission est lue comme le compte rendu ; le prompt porte la règle
    (objectif rempli : report_done si la phrase en rend compte ; objectif non rempli : jamais) ; hors ligne, seulement
    avec le drapeau de banc ; l'accusé de réception n'applique que la mission nommée par la demande."""
    import os
    sys.path.insert(0, str(ROOT / "bridge"))
    import npc_protocol as protocol
    import radio_bridge as rb
    base = {"kind": "npc_talk", "id": "r-1-npc-1", "world": "w", "run": "r", "npc": "npc-1", "order": 1,
            "revision": 1, "language": "FR", "character": "c-1", "personality": {}, "offers": {}, "text": "Fini.",
            "context": {"stage": "acquainted", "mission": {"state": "active", "kind": "clear", "toReport": False}}}
    assert protocol.reportable(base) == ""
    try:
        protocol.bounded_reply(base, {"text": "Bien.", "intent": "report_done"})
        raise AssertionError("report_done without a reportable mission")
    except ValueError as err:
        assert str(err) == "no mission to report", err
    reply, why = protocol.model_reply(base, '{"text": "Bien.", "intent": "report_done"}')
    assert (reply["intent"], reply["text"], why) == ("none", "Bien.", "no mission to report"), (reply, why)
    system = protocol.prompt(base, [])[0]["content"]
    assert "is not done yet, whatever this character says" in system and "Return intent report_done" not in system
    ready = dict(base, context={"stage": "acquainted", "reportable": {"mission": "npc-1-clear1", "revision": 4},
                                "mission": {"state": "active", "kind": "clear", "toReport": True}})
    assert protocol.reportable(ready) == "npc-1-clear1"
    assert protocol.reportable(dict(ready, kind="npc_enrich")) == ""
    assert protocol.bounded_reply(ready, {"text": "Merci.", "intent": "report_done"})["intent"] == "report_done"
    try:
        protocol.bounded_reply(ready, {"text": "Merci.", "intent": "report_done", "offer": "npc-1-clear1"})
        raise AssertionError("report_done with an offer")
    except ValueError as err:
        assert str(err) == "inadmissible offer", err
    reply, why = protocol.model_reply(ready, '{"text": "Merci.", "intent": "report_done", "offer": "npc-1-clear1"}')
    assert (reply["intent"], reply["offer"], why) == ("report_done", "", ""), (reply, why)
    system = protocol.prompt(ready, [])[0]["content"]
    assert "Report of your mission" in system and "Return intent report_done, offer empty" in system, system
    assert "is not done yet" not in system
    assert protocol.report_prompt(dict(base, context={})) == ""
    # Hors ligne : seulement avec le drapeau de banc, jamais d'après la phrase.
    assert protocol.offline(ready, "")["intent"] == "none"
    assert protocol.offline(ready, "report_done")["intent"] == "report_done"
    assert protocol.offline(base, "report_done")["intent"] == "none"
    # Accusé de réception : seule la mission nommée par la demande peut être appliquée.
    (tmp / "report-done").mkdir(parents=True, exist_ok=True)
    conv = rb.NpcConversations(tmp / "report-done")
    req = dict(ready, version=2, channel="say", sent=1)
    saved = os.environ.get("RS_OFFLINE_INTENT")
    os.environ["RS_OFFLINE_INTENT"] = "report_done"
    try:
        assert conv.propose({"OFFLINE": "1"}, req)["intent"] == "report_done"
    finally:
        if saved is None:
            del os.environ["RS_OFFLINE_INTENT"]
        else:
            os.environ["RS_OFFLINE_INTENT"] = saved
    ack = {"request": req["id"], "world": "w", "run": "r", "npc": "npc-1", "order": 1, "revision": 1,
           "status": "accepted"}
    assert not conv.acknowledge(dict(ack, applied={"report": "npc-1-clear9"}))
    assert not conv.acknowledge(dict(ack, applied={"accept": "npc-1-clear1"}))
    assert conv.acknowledge(dict(ack, applied={"report": "npc-1-clear1"}))


def scenario_structured_robust(tmp: Path) -> None:
    """E07-T09, pont seul : objet JSON retrouvé entouré de texte, dans un bloc ```json, avec guillemets typographiques
    ou virgule finale, parmi plusieurs objets ; texte autour pris pour say si l'objet n'en a pas ; texte seul = say sans
    action ; consigne de format rappelée à la fin du message de l'appelant (jamais en mémoire) après un long historique
    en texte ; mode JSON de l'API demandé en mode structuré seulement, repli sans s'il est refusé (HTTP 400) et plus
    redemandé ensuite ; réponse illisible écrite en DEBUG, tronquée, jamais si elle cite un secret ; mode texte
    inchangé."""
    import contextlib
    import io
    import urllib.error
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    reply_obj = '{"say": "Look north.", "actions": [{"type": "mark_map", "place": "mill"}]}'
    actions = [{"type": "mark_map", "place": "mill"}]
    cases = [
        (reply_obj, ("Look north.", actions)),
        ("Sure, Walt here: " + reply_obj + " Over and out.", ("Look north.", actions)),
        ("Here you go:\n```json\n" + reply_obj + "\n```\nStay safe.", ("Look north.", actions)),
        ("```\n" + reply_obj + "\n```", ("Look north.", actions)),
        ('{“say”: “Look north.”, “actions”: [{“type”: “mark_map”, '
         '“place”: “mill”}]}', ("Look north.", actions)),
        ('{"say": "Look north.", "actions": [{"type": "mark_map", "place": "mill",},],}', ("Look north.", actions)),
        ('Note {"mood": 3} then {"say": "Look north.", "actions": [{"type": "mark_map", "place": "mill"}]}',
         ("Look north.", actions)),
        ("I will mark it for you. " + '{"actions": [{"type": "mark_map", "place": "mill"}]}',
         ("I will mark it for you.", actions)),
        ('{"say": "Line one\nline two", "actions": null}', ("Line one\nline two", [])),
        # Guillemets typographiques dans un JSON valide : gardés tels quels (aucune réparation).
        ('{"say": "He said “no”.", "actions": []}', ("He said “no”.", [])),
    ]
    for text, expected in cases:
        assert rb.parse_structured(text) == expected, (text, rb.parse_structured(text))
    for text in ("Just plain words, over.", 'Sure thing {"say": broken', 'Values {"mood": 3} only.'):
        assert rb.parse_structured(text) == (text, None), text

    # Journal DEBUG d'une réponse illisible : tronquée ; rien si elle cite un secret de la fiche.
    saved_debug = rb.DEBUG
    rb.DEBUG = True
    try:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rb.parse_structured("word " * 200)
            rb.parse_structured("The code is " + ACT_SECRET + ", over.", [ACT_SECRET])
        logged = out.getvalue()
        assert "structured reply unreadable (ValueError: no object)" in logged, logged
        assert "unreadable structured reply (1000 characters): 'word word" in logged and "'..." in logged, logged
        assert len(max(logged.splitlines(), key=len)) < rb.RAW_LOG_CHARS + 120, logged
        assert ACT_SECRET not in logged and "not shown: it quotes a secret" in logged, logged
    finally:
        rb.DEBUG = saved_debug

    # Bout en bout après un long historique en texte : actions gardées, rappel en fin de message, mode JSON demandé.
    exchange = tmp / "structured-robust"
    write_map(exchange)
    write_bench(exchange)
    voices = rb.Voices(exchange / "personas")
    conversations = rb.Conversations(exchange)
    for i in range(17):
        conversations.append("s", f"[Caller 1] Question {i}?", f"Plain answer {i}. Over.", "mapper")
    assert len(conversations.history("s", "mapper")) == 34
    req = {"id": "9-9", "caller": "kate", "name": "Kate", "date": "1993-07-12 21:40", "days": "3.5",
           "radio": "Walkie", "text": "Show me the mill on my map?", "voice": "mapper"}
    calls = []
    saved = rb.call_llm
    try:
        rb.call_llm = lambda config, messages, speaker="Walt", **kw: calls.append((messages, kw)) or (
            "Sure, here it is.\n```json\n" + reply_obj + "\n```")
        result = rb.answer({}, conversations, "s", req, voices)
        assert result == {"version": 2, "kind": "radio_reply", "id": "9-9", "say": ["Look north."],
                          "actions": actions}, result
        messages, kw = calls[-1]
        assert kw == {"json_mode": True}, kw
        assert len(messages) == 36 and messages[-1]["role"] == "user", messages
        last = messages[-1]["content"]
        assert last == "[Caller 1] Show me the mill on my map?" + rb.format_reminder(voices.get("mapper")), last
        assert last.endswith('Allowed action types: mark_map, remember. "actions" may be an empty list.)'), last
        assert "JSON" in last and "10600" not in last and "Old mill" not in last, last
        stored = conversations.history("s", "mapper")
        assert stored[-2] == {"role": "user", "content": "[Caller 1] Show me the mill on my map?"}, stored[-2]
        assert stored[-1] == {"role": "assistant", "content": "Look north."}, stored[-1]
        # Mode texte (fiche say seul) : message, appel et sortie d'avant E07-T09.
        rb.call_llm = lambda config, messages, speaker="Walt", **kw: calls.append((messages, kw)) or (
            'Hello there ```json {"say": "x"}```')
        bench = rb.answer({}, conversations, "s", dict(req, voice="bench"), voices)
        assert bench == rb.radio_lines('Hello there ```json {"say": "x"}```') == ['Hello there json {"say": "x"}'], bench
        messages, kw = calls[-1]
        assert kw == {} and messages[-1]["content"] == "[Caller 1] Show me the mill on my map?", (kw, messages[-1])
        assert "Reply format" not in messages[0]["content"]
    finally:
        rb.call_llm = saved

    # call_llm et response_format : réponses HTTP simulées, aucune requête réseau.
    sent = []

    class Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    def fake_urlopen(script):
        def urlopen(request, timeout=60):
            body = json.loads(request.data.decode("utf-8"))
            sent.append(body)
            step = script.pop(0)
            if isinstance(step, int):
                raise urllib.error.HTTPError(request.full_url, step, "error", {},
                                             io.BytesIO(b'{"error": "response_format is not supported"}'))
            return Resp(json.dumps({"choices": [{"message": {"content": step}, "finish_reason": "stop"}]})
                        .encode("utf-8"))
        return urlopen

    config = {"OPENAI_KEY": "k-test", "OPENAI_BASE_URL": "http://llm.invalid/v1", "OPENAI_MODEL": "m1"}
    msgs = [{"role": "system", "content": "Reply in JSON."}, {"role": "user", "content": "Hi"}]
    saved_urlopen = rb.urllib.request.urlopen
    saved_refused = set(rb._json_mode_refused)
    rb._json_mode_refused.clear()
    try:
        # Accepté : un seul appel, avec response_format.
        rb.urllib.request.urlopen = fake_urlopen([reply_obj])
        assert rb.call_llm(config, msgs, "Map", json_mode=True) == reply_obj
        assert sent[-1]["response_format"] == {"type": "json_object"} and sent[-1]["temperature"] == 0.8, sent[-1]
        # Mode texte : jamais de response_format.
        rb.urllib.request.urlopen = fake_urlopen(["Hello."])
        assert rb.call_llm(config, msgs, "Map") == "Hello." and "response_format" not in sent[-1], sent[-1]
        # Refusé (400) : nouvel essai sans, mêmes autres paramètres ; le fournisseur n'est plus sollicité ensuite.
        sent.clear()
        rb.urllib.request.urlopen = fake_urlopen([400, reply_obj])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            assert rb.call_llm(config, msgs, "Map", json_mode=True) == reply_obj
        assert "response_format" in sent[0] and "response_format" not in sent[1], sent
        assert sent[1]["temperature"] == 0.8 and "refused the JSON response mode" in out.getvalue(), out.getvalue()
        assert "k-test" not in out.getvalue()
        sent.clear()
        rb.urllib.request.urlopen = fake_urlopen([reply_obj])
        assert rb.call_llm(config, msgs, "Map", json_mode=True) == reply_obj
        assert len(sent) == 1 and "response_format" not in sent[0], sent
        # Autre modèle : toujours demandé ; trois paliers (JSON, complet, minimal).
        other = dict(config, OPENAI_MODEL="m2")
        sent.clear()
        rb.urllib.request.urlopen = fake_urlopen([400, 400, reply_obj])
        with contextlib.redirect_stdout(io.StringIO()):
            assert rb.call_llm(other, msgs, "Map", json_mode=True) == reply_obj
        assert ["response_format" in b for b in sent] == [True, False, False] and "temperature" not in sent[2], sent
        # Erreur serveur (500) : échec, rien de mémorisé.
        third = dict(config, OPENAI_MODEL="m3")
        rb.urllib.request.urlopen = fake_urlopen([500])
        try:
            rb.call_llm(third, msgs, "Map", json_mode=True)
            raise AssertionError("HTTP 500 must fail")
        except RuntimeError:
            pass
        assert ("http://llm.invalid/v1", "m3") not in rb._json_mode_refused
    finally:
        rb.urllib.request.urlopen = saved_urlopen
        rb._json_mode_refused.clear()
        rb._json_mode_refused.update(saved_refused)


def scenario_npc_reply_cleaning(tmp: Path) -> None:
    """E17-T07 : réponse d'un PNJ refusée en silence. (1) Pont : sortie LLM désordonnée (didascalies *...* et [...],
    sauts de ligne, balises, bloc ```json, texte autour, offer null, champ en trop, texte seul, trop long) -> réplique
    d'une ligne que le jeu accepte, sans effet quand l'intention ou l'offre sort du contrat ; langue de la réponse =
    langue de la phrase du joueur, jugée par le modèle (E17-T10 : consigne du prompt, langue du jeu en indice ; hors
    ligne : langue du jeu). (2) Solo simulé (vrai Lua serveur + client, vrai pont en processus, call_llm remplacé) :
    « comment ça va » avec le jeu en anglais -> consigne de langue au modèle, réponse française du modèle simulé, bulle nettoyée ;
    puis un refus (erreur du pont) journalisé une fois avec sa raison. Doublures Lua : ne prouve ni l'API Java ni le
    LLM réel."""
    sys.path.insert(0, str(ROOT / "bridge"))
    sys.path.insert(0, str(ROOT / "tests"))
    import contextlib
    import io
    import npc_protocol as protocol
    import radio_bridge as rb
    bad = re.compile(r"[\x00-\x1f\x7f<>\[\]*]")   # RS_Carnet_Server reply(): '[%c<>%[%]*]'
    req = {"version": 2, "kind": "npc_talk", "id": "run-a-npc-a-1", "world": "world-a", "run": "run-a",
           "npc": "npc-a", "character": "character-a", "order": 1, "revision": 1, "sent": int(time.time() * 1000),
           "channel": "say", "language": "EN", "text": "comment ça va", "personality": {}, "context": {},
           "offers": {"first_aid_v1": {"quantity": 6, "durationMs": 7200000, "rewardCount": 20}}}
    cases = {
        '{"text": "*hausse les épaules* Ça va.", "intent": "none", "offer": ""}': ("Ça va.", ""),
        '{"text": "Ça va.\\nEt vous ?", "intent": "none", "offer": ""}': ("Ça va. Et vous ?", ""),
        '{"text": "[soupir] Ça va [bien], <b>merci</b>.", "intent": "none", "offer": ""}': ("Ça va, merci.", ""),
        '{"text": "*soupire*", "intent": "none", "offer": ""}': ("soupire", ""),
        '```json\n{"text": "Ça va.", "intent": "none", "offer": ""}\n```': ("Ça va.", ""),
        'Voici : {"text": "Ça va.", "intent": "none", "offer": null}': ("Ça va.", ""),
        '{"text": "Ça va."}': ("Ça va.", ""),
        'Ça va, merci.': ("Ça va, merci.", ""),
        '{"text": "Ça va.", "intent": "none", "offer": "", "emotion": "calm"}': ("Ça va.", ""),   # E07-T09: key dropped
        '{"text": "Ça va.", "intent": "offer", "offer": "invented"}': ("Ça va.", "inadmissible offer"),
        '{"text": "Ça va.", "intent": "give_reward", "offer": ""}': ("Ça va.", "intent"),
    }
    for raw, (text, downgrade) in cases.items():
        reply, reason = protocol.model_reply(req, raw)
        assert (reply["text"], reason, reply["intent"], reply["offer"]) == (text, downgrade, "none", ""), (raw, reply)
    offer, reason = protocol.model_reply(req, '{"text": "Il me faut des bandages.", "intent": "offer", '
                                              '"offer": "first_aid_v1"}')
    assert (offer["intent"], offer["offer"], reason) == ("offer", "first_aid_v1", ""), offer
    long = protocol.model_reply(req, json.dumps({"text": "Ça va bien. " * 200, "intent": "none"}))[0]["text"]
    assert len(long.encode("utf-8")) <= protocol.MAX_REPLY_BYTES and long.endswith("bien."), long[-20:]
    words = protocol.model_reply(req, json.dumps({"text": "très " * 400, "intent": "none"}))[0]["text"]
    assert len(words.encode("utf-8")) <= protocol.MAX_REPLY_BYTES and words.endswith("très..."), words[-20:]
    for raw in ('{"text": "", "intent": "none"}', '{"text": "*  *"}', "```json\n```"):
        try:
            protocol.model_reply(req, raw)
            raise AssertionError(f"empty speech admitted: {raw!r}")
        except ValueError:
            pass
    for raw in cases:
        assert not bad.search(protocol.model_reply(req, raw)[0]["text"]), raw
    # Langue (E17-T10) : le modèle reconnaît celle de la phrase du joueur ; la langue du jeu n'est qu'un indice.
    # Le prompt ne dépend pas du texte du joueur ; le mode hors ligne répond dans la langue du jeu.
    system = protocol.prompt(req, [])[0]["content"]
    assert "Answer in the language the character uses in their latest sentence" in system
    assert "answer in English (the language of their game)" in system
    assert "answer in French (the language of their game)" in protocol.prompt(dict(req, language="FR"), [])[0]["content"]
    assert "no stage directions" in system
    assert protocol.offline(dict(req, offers={}))["text"].startswith("I'm listening")
    assert protocol.offline(dict(req, offers={}, language="FR"))["text"].startswith("Je vous écoute")
    enrich = dict(req, kind="npc_enrich", character="system", text="Describe your background.", language="FR",
                  offers={})
    assert "Write in French" in protocol.prompt(enrich, [])[0]["content"]

    # (2) Solo simulé : vrai Lua, vrai pont en processus, LLM remplacé.
    from test_carnet import solo_game
    path = tmp / "npc-reply-cleaning"
    clock = Clock()
    game, _player, zombie = solo_game(path, clock)
    game.rt.execute("Translator = {getLanguage = function() return {name = function() return 'EN' end} end}")
    logs = []
    game.g.print = lambda *args: logs.append(" ".join(str(a) for a in args))
    client, server = game.g.RS_CarnetClient, game.g.RS_CarnetServer
    client.selectNearest()
    sent = []

    def fake_llm(config, messages, speaker="Walt", json_mode=False):
        last = messages[-1]["content"]
        if last.endswith("Describe your background."):   # background enrichment queued by the game ticks
            return '{"text": "Un survivant de Knox.", "intent": "none", "offer": ""}'
        sent.append((messages, json_mode))
        if last.endswith("comment ça va"):
            return ('```json\n{"text": "*hausse les épaules*\\nÇa va [bien], merci. Et toi ?", "intent": "none", '
                    '"offer": null}\n```')
        if last.endswith("et demain ?"):   # E17-T15: provider overloaded, as on 2026-10-15
            raise rb.ProviderError("http_503", 'HTTP 503 : {"error": {"message": "Service is too busy."}}')
        raise RuntimeError("provider down")

    worker = rb.Bridge({"OPENAI_MODEL": "fake"}, path)
    saved = rb.call_llm
    rb.call_llm = fake_llm
    try:
        def turn(text):
            client.talk(text, True)
            reqs = [r for r in server.pending.values() if r.kind == "npc_talk"]
            assert len(reqs) == 1, reqs
            rid = reqs[0].id
            with contextlib.redirect_stdout(io.StringIO()):
                assert pump(lambda: rid in worker.answers,
                            [lambda: worker._sync(*rb.read_requests(path / "requests.txt")),
                             lambda: game.g.fire("OnTickEvenPaused")], timeout=5), (rid, logs)
            return reqs[0]

        first = turn("comment ça va")
        assert first.language == "EN", first.language
        messages, json_mode = sent[0]
        assert json_mode and "latest sentence, whatever that language is" in messages[0]["content"], messages[0]["content"][-400:]
        assert pump(lambda: len(zombie.bubbles) > 0, [lambda: game.g.fire("OnTickEvenPaused")], timeout=5), logs
        assert zombie.bubbles[1] == "Ça va, merci. Et toi ?", zombie.bubbles[1]
        assert not [line for line in logs if "refused" in line], logs
        # Refus restant : erreur du pont -> NoAnswer, une ligne de journal avec la raison.
        server.lastTalk[client.character] = None
        second = turn("et ta famille ?")
        assert pump(lambda: len(server.pending) == 0, [lambda: game.g.fire("OnTickEvenPaused")], timeout=5)
        refused = [line for line in logs if "npc_talk" in line and "refused" in line]
        assert refused == [f"[RS_Carnet] npc_talk {second.id} refused: bridge error invalid_or_unavailable"], refused
        # E17-T15: provider error named from the bridge to the server log and RS_CarnetServer.refusals, at once (no
        # wait of REQUEST_TIMEOUT_MS: the game clock is never advanced, the turn takes a few real seconds).
        server.lastTalk[client.character] = None
        started = time.time()
        third = turn("et demain ?")
        assert pump(lambda: len(server.pending) == 0, [lambda: game.g.fire("OnTickEvenPaused")], timeout=5)
        assert time.time() - started < 10 and clock.offset == 0
        refused = [line for line in logs if third.id in line and "refused" in line]
        assert refused == [f"[RS_Carnet] npc_talk {third.id} refused: bridge error http_503"], refused
        last = lua_list(server.refusals)[-1]
        assert (last.id, last.kind, last.reason) == (third.id, "npc_talk", "bridge error http_503"), dict(last)
        assert len(server.refusals) == 2 and server.MAX_REFUSALS == 16, len(server.refusals)
    finally:
        rb.call_llm = saved
        worker.pool.shutdown(wait=True)


def scenario_provider_errors(tmp: Path) -> None:
    """E17-T15: (1) call_llm names the provider failure (ProviderError.code): HTTP 503, socket timeout, refused
    connection, unreadable answer, never retried; (2) one budget LLM_BUDGET_S for all the attempts, keep-alive bytes
    included (a body that never ends is cut at the budget); (3) a request that waited more than MAX_AGE_S in the queue
    of the workers is answered `expired` without calling the model; (4) the server waits longer than the bridge can
    take (MAX_AGE_S + LLM_BUDGET_S < RS_Config.REQUEST_TIMEOUT_MS)."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import contextlib
    import io
    import urllib.error
    import radio_bridge as rb

    class Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    class Dribble:   # provider that only sends keep-alive bytes
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read1(self, n):
            time.sleep(0.05)
            return b"\n"

    config = {"OPENAI_KEY": "k-test", "OPENAI_BASE_URL": "http://llm.invalid/v1", "OPENAI_MODEL": "m-errors"}
    msgs = [{"role": "user", "content": "Hi"}]
    calls = []

    def scripted(step):
        def urlopen(request, timeout=60):
            calls.append(timeout)
            if step == 503:
                raise urllib.error.HTTPError(request.full_url, 503, "busy", {},
                                             io.BytesIO(b'{"error": {"message": "Service is too busy."}}'))
            if step == "timeout":
                raise TimeoutError("The read operation timed out")
            if step == "refused":
                raise urllib.error.URLError(ConnectionRefusedError(10061, "refused"))
            if step == "garbage":
                return Resp(b"<html>gateway</html>")
            if step == "nochoices":
                return Resp(b'{"error": "overloaded"}')
            if step == "dribble":
                return Dribble()
            raise AssertionError(step)
        return urlopen

    saved = (rb.urllib.request.urlopen, rb.TOKEN_USAGE, rb.LLM_BUDGET_S)
    rb.TOKEN_USAGE = None
    try:
        for step, code in ((503, "http_503"), ("timeout", "timeout"), ("refused", "unreachable"),
                           ("garbage", "bad_response"), ("nochoices", "bad_response")):
            rb.urllib.request.urlopen = scripted(step)
            calls.clear()
            try:
                rb.call_llm(config, msgs)
            except rb.ProviderError as err:
                assert err.code == code, (step, err.code, str(err))
                assert rb.error_code(err) == code and isinstance(err, RuntimeError)
            else:
                raise AssertionError(f"no error for {step}")
            assert len(calls) == 1, (step, calls)   # a provider failure is not retried
            assert 0 < calls[0] <= rb.LLM_BUDGET_S, calls
        assert rb.error_code(ValueError("x")) == "invalid_or_unavailable"
        # Keep-alive bytes do not extend the attempt: cut at the budget, code timeout.
        rb.LLM_BUDGET_S = 0.3
        rb.urllib.request.urlopen = scripted("dribble")
        started = time.monotonic()
        try:
            rb.call_llm(config, msgs)
            raise AssertionError("endless body accepted")
        except rb.ProviderError as err:
            assert err.code == "timeout", err.code
        assert time.monotonic() - started < 2, time.monotonic() - started
    finally:
        rb.urllib.request.urlopen, rb.TOKEN_USAGE, rb.LLM_BUDGET_S = saved

    # (3) A request taken by a worker after MAX_AGE_S is answered `expired`, the model never called.
    path = tmp / "provider-errors"
    path.mkdir(parents=True, exist_ok=True)
    worker = rb.Bridge({"OPENAI_MODEL": "fake"}, path)
    asked = []
    saved_llm = rb.call_llm
    rb.call_llm = lambda *a, **k: asked.append(a) or "{}"
    try:
        req = {"id": "1-old", "world": "w", "run": "r", "npc": "n1", "order": 1, "revision": 1, "version": 2,
               "kind": "npc_talk", "sent": str(int(time.time() * 1000 - (rb.MAX_AGE_S + 5) * 1000))}
        worker.current["1-old"] = worker._token("s", req)
        with contextlib.redirect_stdout(io.StringIO()) as out:
            worker._handle("s", req)
        assert asked == [], asked
        assert worker.answers["1-old"]["error"] == "expired", worker.answers["1-old"]
        assert "LLM error (1-old, expired)" in out.getvalue(), out.getvalue()
    finally:
        rb.call_llm = saved_llm
        worker.pool.shutdown(wait=True)

    # (4) Every answer of the bridge (start <= MAX_AGE_S, call <= LLM_BUDGET_S) is written before the server gives up.
    config_lua = ROOT / "Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/RadioSurvivor/RS_Config.lua"
    timeout_ms = int(re.search(r"REQUEST_TIMEOUT_MS = (\d+)", config_lua.read_text(encoding="utf-8")).group(1))
    assert (rb.MAX_AGE_S + rb.LLM_BUDGET_S) * 1000 + 5000 <= timeout_ms, (rb.MAX_AGE_S, rb.LLM_BUDGET_S, timeout_ms)


def scenario_debug_journal(tmp: Path) -> None:
    """E05-T13 : journal complet du pont en mode --debug. (1) call_llm en processus (urlopen remplacé) : messages
    complets (rôle et contenu), réponse brute de l'API et corps d'une erreur HTTP écrits ; ni la clé ni l'en-tête
    Authorization ; sans DEBUG, aucune de ces lignes. (2) Vrai pont --offline --debug en processus séparé : demande
    radio et demande PNJ lues (payload RSV2 décodé), réponses écrites (texte du PNJ), acquittement lu ; le même pont
    sans --debug n'écrit rien de cela."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import contextlib
    import io
    import os
    import urllib.error
    import npc_protocol as protocol
    import radio_bridge as rb

    class Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    secret = "sk-SECRET-e05t13"
    config = {"OPENAI_KEY": secret, "OPENAI_BASE_URL": "http://llm.invalid/v1", "OPENAI_MODEL": "m-debug"}
    msgs = [{"role": "system", "content": "SYSTEM PROMPT complet, ligne 1\nligne 2"},
            {"role": "user", "content": "[Caller 1] Allô Walt ?"}]
    raw = json.dumps({"id": "cmpl-1", "choices": [{"message": {"content": "Ici Walt. À vous."},
                                                   "finish_reason": "stop"}], "usage": {"total_tokens": 9}},
                     ensure_ascii=False)
    script = []

    def urlopen(request, timeout=60):
        assert request.get_header("Authorization") == "Bearer " + secret
        step = script.pop(0)
        if isinstance(step, int):
            raise urllib.error.HTTPError(request.full_url, step, "error", {}, io.BytesIO(b'{"error": "BODY-503"}'))
        return Resp(step.encode("utf-8"))

    saved = (rb.urllib.request.urlopen, rb.DEBUG, rb.TOKEN_USAGE)
    rb.urllib.request.urlopen, rb.TOKEN_USAGE = urlopen, None
    try:
        outputs = {}
        for flag in (True, False):
            rb.DEBUG = flag
            script[:] = [raw, 503]
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                assert rb.call_llm(config, msgs) == "Ici Walt. À vous."
                try:
                    rb.call_llm(config, msgs)
                    raise AssertionError("HTTP 503 must fail")
                except RuntimeError:
                    pass
            outputs[flag] = out.getvalue()
        full = outputs[True]
        assert "LLM messages (2, model m-debug)" in full, full
        assert '"content": "SYSTEM PROMPT complet, ligne 1\\nligne 2"' in full, full
        assert '"role": "user"' in full and "[Caller 1] Allô Walt ?" in full, full
        assert "LLM attempt 1 raw response:\n" + raw in full, full
        assert '{"error": "BODY-503"}' in full, full
        assert secret not in full and "Authorization" not in full and "Bearer" not in full, full
        assert outputs[False] == "", outputs[False]
    finally:
        rb.urllib.request.urlopen, rb.DEBUG, rb.TOKEN_USAGE = saved

    # (2) Vrai pont hors ligne, avec et sans --debug.
    def run_bridge(exchange: Path, debug_flag: bool) -> str:
        exchange.mkdir()
        (exchange / "personas").mkdir()
        (exchange / "personas/walt.txt").write_bytes((rb.BUNDLED_PERSONAS / "walt.txt").read_bytes())
        now = int(time.time() * 1000)
        req = {"version": 2, "kind": "npc_talk", "id": "run-d-npc-d-1", "world": "world-d", "run": "run-d",
               "npc": "npc-d", "character": "character-d", "order": 1, "revision": 1, "sent": now,
               "channel": "say", "language": "FR", "text": "Bonjour, ça va ?", "personality": {}, "context": {},
               "offers": {}}
        radio = ["req=walt-d1", f"sent={now}", "caller=alice", "name=Alice", "date=1993-07-09", "days=1",
                 "radio=Radio", "text=Allo Walt DEBUG"]
        body = ["protocol=2", "session=Multiplayer_debug", "generation=1", *radio,
                f"req={req['id']}", "kind=npc_talk", "payload=" + protocol.encode(req).hex(), "commit=1", "end"]
        (exchange / "requests.txt").write_text("\n".join(body) + "\n", encoding="utf-8")
        args = [sys.executable, str(BRIDGE), "--offline", "--exchange", str(exchange), "--poll", "0.05"]
        # Output to a file, not a pipe: a full debug journal would fill the pipe buffer and block the bridge.
        log_path = exchange.parent / (exchange.name + ".log")
        log_file = log_path.open("w", encoding="utf-8")
        process = subprocess.Popen(args + (["--debug"] if debug_flag else []), stdout=log_file,
                                   stderr=subprocess.STDOUT, env=dict(os.environ, PYTHONIOENCODING="utf-8"))
        try:
            responses = exchange / "responses.txt"
            assert pump(lambda: responses.exists() and "resp=walt-d1" in responses.read_text(encoding="utf-8")
                        and f"resp={req['id']}" in responses.read_text(encoding="utf-8"), []), "no responses"
            ack = {k: req[k] for k in ("version", "world", "run", "npc", "order", "revision", "sent")}
            ack.update(id=req["id"] + "-ack", kind="ack", request=req["id"], status="accepted", applied={})
            (exchange / "requests.txt").write_text("\n".join(
                ["protocol=2", "session=Multiplayer_debug", "generation=2", f"req={ack['id']}", "kind=ack",
                 "payload=" + protocol.encode(ack).hex(), "commit=2", "end"]) + "\n", encoding="utf-8")
            assert pump(lambda: f"resp={ack['id']}" in responses.read_text(encoding="utf-8"), []), "no ack_reply"
        finally:
            process.terminate()
            process.wait(timeout=10)
            log_file.close()
        return log_path.read_text(encoding="utf-8")

    full = run_bridge(tmp / "debug-on", True)
    assert "Requests read from requests.txt (session Multiplayer_debug)" in full, full
    assert '"text": "Allo Walt DEBUG"' in full, full                          # radio request, raw fields
    assert '"payload (decoded)"' in full and '"text": "Bonjour, ça va ?"' in full, full   # NPC request decoded
    assert "LLM messages (offline, not sent)" in full, full
    assert "Responses written to responses.txt" in full and '"kind": "npc_reply"' in full, full
    assert '"kind": "ack"' in full and '"kind": "ack_reply"' in full, full
    quiet = run_bridge(tmp / "debug-off", False)
    for marker in ("[DEBUG]", "Requests read", "LLM messages", "Responses written", "payload (decoded)"):
        assert marker not in quiet, (marker, quiet)


def scenario_unreadable_requests_wait(tmp: Path) -> None:
    """Pont : un requests.txt qui reste illisible (partiel, trop gros) est relu au tour suivant après la pause
    habituelle, jamais en boucle à vide (défaut relevé le 2026-10-12 : continue sans sleep)."""
    sys.path.insert(0, str(ROOT / "bridge"))
    import radio_bridge as rb
    exchange = tmp / "unreadable-requests"
    exchange.mkdir()
    (exchange / "requests.txt").write_text("RSV2 partial", encoding="utf-8")
    calls = {"read": 0, "sleep": 0}

    class Stop(Exception):
        pass

    def fake_read(path):
        calls["read"] += 1
        if calls["read"] > 10:   # sans pause, la boucle relirait sans fin : échec plutôt que blocage
            raise AssertionError("busy loop: %d reads, %d sleeps" % (calls["read"], calls["sleep"]))
        (exchange / "requests.txt").write_text("RSV2 partial " + str(calls["read"]), encoding="utf-8")
        return None

    def fake_sleep(seconds):
        calls["sleep"] += 1
        if calls["sleep"] >= 3:
            raise Stop()

    saved = (rb.read_requests, rb.time.sleep)
    rb.read_requests, rb.time.sleep = fake_read, fake_sleep
    bridge = rb.Bridge({"OFFLINE": "1", "OPENAI_MODEL": "offline"}, exchange)
    try:
        try:
            bridge.run(0.3)
        except Stop:
            pass
    finally:
        rb.read_requests, rb.time.sleep = saved
    assert calls["read"] <= calls["sleep"] + 1, calls


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="radiosurvivor-"))
    failures = 0
    skipped = []
    try:
        for scenario in (scenario_solo, scenario_multiplayer, scenario_drawn_frequency, scenario_no_bridge,
                         scenario_bridge_alive_radio,
                         scenario_two_voices, scenario_server_sorts, scenario_spontaneous_calls,
                         scenario_bridge_voices, scenario_accented_npc_exchange, scenario_npc_observations,
                         scenario_relation_change,
                         scenario_scout_offer, scenario_supply_offer,
                         scenario_world_radios_mp,
                         scenario_structured_bridge, scenario_structured_server,
                         scenario_memory_bridge, scenario_memory_server,
                         scenario_persona_bridge, scenario_persona_server, scenario_action_descriptions,
                         scenario_map_bridge, scenario_map_client, scenario_map_server, scenario_map_mp,
                         scenario_reveal_bridge, scenario_reveal_rect, scenario_reveal_client, scenario_reveal_server,
                         scenario_reveal_mp, scenario_voice_mission_bridge, scenario_report_done_bridge,
                         scenario_structured_robust, scenario_npc_reply_cleaning, scenario_provider_errors,
                         scenario_debug_journal,
                         scenario_unreadable_requests_wait):
            try:
                scenario(tmp)
                print(f"OK    {scenario.__name__}")
            except unittest.SkipTest as skip:
                skipped.append(str(skip))
                print(f"SKIP  {scenario.__name__} : {skip}")
            except Exception as err:  # noqa: BLE001
                failures += 1
                print(f"ÉCHEC {scenario.__name__} : {err!r}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if skipped:  # dernière ligne : résumé repris par run_all.py
        print(f"SKIP  {len(skipped)} scenario(s): {skipped[0]}")
    return 1 if failures else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
