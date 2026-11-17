"""Shared bench machine (E26, moved from tests/radiosurvivor/test_protocol.py): one Lua machine (solo, server or client) with the
real Lua of the mods on package.path (Game.WITH_RS / Game.WITH_LK choose the mods), file doubles of the game
(getFileWriter, getFileReader), bench clock, offline bridge and helpers. Used by the tests of every folder.

Simulation, NOT validation: the doubles do not prove the Java API."""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path
import unittest
import lupa.lua51 as lupa
from harness import lua_src, core_notebook_files, rs_notebook_files  # noqa: E402  (E18-T07, E20-T01, E21-T03)
import beltradio_lib  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "Contents/mods/batman_RadioSurvivor/42.21"
LUA = MOD / "media/lua"
CORE_LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'  # mod commun (E18)
LK_LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'  # moteur des PNJ (E18-T07)
BRIDGE = ROOT / "bridge/radio_bridge.py"
# Fiche livrée de Walt, sa radio remplacée par la fréquence d'exemple fixe 145.0 (E24-T01) : ces scénarios raisonnent
# sur une fréquence connue ; le tirage est couvert par scenario_drawn_frequency et tests/radiosurvivor/test_personas_server.py.
WALT_FIXED = re.sub(r"(?m)^radio=.*$", "frequency=145.0",
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
    -- E11-T20: without WORLD_AGE_HOURS, the world age follows the play clock of the bench Clock (PLAY_MS: real ms
    -- minus the simulated downtime and pauses) over a day of MINUTES_PER_DAY real minutes. The default day of 1000
    -- real days keeps the world age near 0 (the other game-hour rules see no time pass) while CA_GameClock still
    -- counts one play ms per bench ms.
    getWorldAgeHours = function()
        if WORLD_AGE_HOURS then return WORLD_AGE_HOURS end
        return PLAY_MS and PLAY_MS() * 24 / ((MINUTES_PER_DAY or 1440000) * 60000) or 0
    end,
    getMinutesPerDay = function() return MINUTES_PER_DAY or 1440000 end,
    getModData = function() return GT_MODDATA end } end
getWorld = function() return { getWorld = function() return "TestWorld" end,
    getGameMode = function() return setmetatable({}, {__tostring = function() return "Multiplayer" end}) end } end

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
    WITH_LK = True   # E18-T09 : False = RadioSurvivor seul (Living Knox absent du chemin des modules)
    WITH_RS = True   # E21-T05 : False = mod commun et Living Knox seuls (RadioSurvivor absent du chemin des modules)

    def __init__(self, mode: str, exchange: Path, clock, drawn: bool = False):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.rt.execute(STUBS, mode)
        g.getTimestampMs = clock
        if hasattr(clock, 'play_ms'):
            g.PLAY_MS = clock.play_ms
        # Zomboid/Lua/batman_RadioSurvivor/<x> -> exchange/<x> (dossier des fiches) ; fichiers d'échange du commun -> exchange/<x> ;
        # Zomboid/Lua/batman_CoreAI/<x> -> exchange/_core/<x> (registres du mod commun, E18-T03) ;
        # Zomboid/Lua/batman_LivingKnox/<x> -> exchange/_livingknox/<x>.
        def lua_path(name):
            rel = Path(name)
            if rel.parts and rel.parts[0] == "batman_CoreAI":
                if rel.name in ("requests.txt", "responses.txt", "bridge-alive.txt"):   # E18-T12
                    return exchange / rel.name
                return exchange / "_core" / rel.relative_to("batman_CoreAI")
            if rel.parts and rel.parts[0] == "batman_LivingKnox":   # registres de Living Knox (E18-T10)
                return exchange / "_livingknox" / rel.relative_to("batman_LivingKnox")
            if rel.parts and rel.parts[0] == "batman_CoreAITests":   # fichiers du moteur RST (E21-T07)
                return exchange / "_coretests" / rel.relative_to("batman_CoreAITests")
            return exchange / rel.relative_to("batman_RadioSurvivor")
        g.getFileWriter = lambda name, create, append: file_writer(lua_path(name), name, append)
        g.getFileReader = lambda name, create: Reader(lua_path(name))
        g.listFilesInZomboidLuaDirectory = lambda d: g.JLIST(self.rt.table_from(
            sorted(f.name for f in lua_path(d).glob("*") if f.is_file()) if lua_path(d).is_dir() else []))
        # Fiches livrées : Walt seul (ces scénarios raisonnent sur ses fréquences ; les six voix livrées sont
        # couvertes par tests/radiosurvivor/test_personas_server.py, DeliveredVoicesServerTests).
        g.listFilesInModDirectory = lambda mod, d: g.JLIST(self.rt.table_from(
            sorted(f.name for f in (MOD / d).glob("*") if f.is_file()
                   and (Path(d).name != "personas" or f.name == "walt.txt"))))
        # drawn : vraie fiche de Walt (plage de tirage) ; sinon sa fréquence d'exemple fixe (WALT_FIXED).
        g.getModFileReader = lambda mod, name, create: (
            TextReader(WALT_FIXED) if name == "personas/walt.txt" and not drawn else Reader(MOD / name))
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server', 'client')) if self.WITH_RS else ''
        paths = (CORE_LUA / 'shared').as_posix() + '/?.lua;' + (CORE_LUA / 'server').as_posix() + '/?.lua;' + (CORE_LUA / 'client').as_posix() + '/?.lua;' + ((LK_LUA / 'shared').as_posix() + '/?.lua;' + (LK_LUA / 'server').as_posix() + '/?.lua;' + (LK_LUA / 'client').as_posix() + '/?.lua;' if self.WITH_LK else '') + paths  # mod commun (E18)
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        # Mod requis Belt Walkie-Talkie : vraie partie partagée (BatmanRadioSupport.canTransmitWith), chargée en solo,
        # sur un client et sur un serveur. Absente : SKIP (unittest.SkipTest, rapporté par main()).
        if beltradio_lib.missing():
            raise unittest.SkipTest(beltradio_lib.missing())
        self.rt.execute(f'package.path = [[{beltradio_lib.lua_path(("shared",))};]] .. package.path')
        self.rt.execute(beltradio_lib.SUPPORT_REQUIRE)
        # Mod requis Signal Smoke : doublure de son module public (tests/commun/signalsmoke_double.py).
        self.rt.execute(SIGNAL_SMOKE)
        self.g = g

    def load(self, *files: str) -> None:
        for rel in files:
            self.rt.execute(lua_src(rel).read_text(encoding="utf-8"))

    def load_notebook(self) -> None:
        """Fichiers client du carnet comme le jeu les charge (E21-T03) : carnet du mod commun (transport, cadre, un
        fichier par onglet commun, vues de gabarit), page de Living Knox actif (E18-T26 : panneau de relation, textes
        de ses actes), puis la part de RadioSurvivor (onglet Radio, actes, vues des missions des voix)."""
        self.load(*core_notebook_files())
        if self.WITH_LK:
            self.rt.execute('require "LivingKnox/LK_NotebookPages"')
        if self.WITH_RS:
            self.load(*rs_notebook_files())

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
    # LuaManager.getFileReader (LuaManager.java:4915-4925) logs an IOException and returns null: a file being written
    # by the bridge (Windows sharing violation) reads as absent, never as an error.
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None

    class _R:
        lines = text.splitlines()

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
    """Real clock of the bench (getTimestampMs). play_ms (E11-T20): game time in real ms at normal speed, which stops
    while the server is down or the world is paused (stop)."""

    def __init__(self):
        self.offset = 0.0
        self.down = 0.0
        self.start = time.time() * 1000

    def __call__(self):
        return time.time() * 1000 + self.offset

    def play_ms(self):
        return self() - self.start - self.down

    def stop(self, ms):
        """ms of real time without game time: server stopped, or world paused (PauseEmpty, solo pause)."""
        self.offset += ms
        self.down += ms


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
