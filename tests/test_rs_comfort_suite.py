"""Banc hors jeu de la suite en jeu rs.comfort (E05-T15, RS_ComfortSuite.lua) et de ses étapes client
(RST_PeerChecksComfort.lua).

    python RadioSurvivor/tests/test_rs_comfort_suite.py

Serveur dédié et deux clients du banc (tests/harness.py : machines lupa séparées, réseau en file), puis un solo. Réels :
moteur RST (RST.lua, RST_Steps.lua), la suite et ses étapes, RS_Comfort.lua et RadioSurvivor_Const.lua sur l'autorité,
RS_RadioTalk.lua sur les clients (halo de la commande comfort, branché comme RadioSurvivor_Client.lua). Doublures : file
de diffusion et rappel de réconfort de RadioSurvivor_Server (queueAir, airNext, comfortOnAir, liés par GroupRadio.bind),
voix et chaîne (RS_Personas), personnage du carnet (RS_RadioLog.characterOf), jauges (Stats, CharacterStat), paquet
SyncPlayerStats (livré par la file du banc, appliqué à la copie du joueur sur le client), HaloTextHelper.
La suite passe sur les doublures et échoue sur chaque défaut injecté (DEFECTS) : jauges jamais synchronisées vers le
client, halo absent, réconfort aussi accordé au second joueur (autorité), baisse et halo chez le second client seul ;
son message nomme l'étape en échec (campagne MP du 2026-11-14) : ligne jamais diffusée (chaîne occupée par telle
diffusion, chaîne disparue), diffusée sans réconfort (plafond horaire, personnage changé, autre table RS_Comfort).
Ne prouve ni l'API Java (SyncPlayerStats réel, HaloTextHelper remplaçable depuis Lua) ni le vrai serveur radio
(tests/test_comfort.py) : la campagne MP réelle reste nécessaire.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import harness as harness_module  # noqa: E402
from harness import ROOT, Harness  # noqa: E402

DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
REQUESTER, OTHER = 'A', 'B'
TEST_NAME = 'an answer on the air eases the requester only: gauges and halo on his client (E05-T15)'
# SyncPlayerStatsPacket.java:19 : reliability 2 (fiable, non ordonné), aucun flux ordonné.
harness_module.PACKET_CHANNELS.setdefault('SyncPlayerStats', None)

# Toutes les machines : jauges (Stats.java:76-93, CharacterStat.java:15/34 : bornes 0-100), monde de test, options.
COMMON = r'''
local H = HARNESS
local C = H.classes
local Stat = H.class('CharacterStat')
CharacterStat = { BOREDOM = setmetatable({ nameDouble = "Boredom" }, Stat),
    UNHAPPINESS = setmetatable({ nameDouble = "Unhappiness" }, Stat) }
local Stats = H.class('Stats')
function Stats:get(stat) return self.valuesDouble[stat.nameDouble] or 0 end
function Stats:set(stat, v)
    local old = self:get(stat)
    v = math.max(0, math.min(100, v))
    self.valuesDouble[stat.nameDouble] = v
    return v ~= old
end
function Stats:add(stat, n) return self:set(stat, self:get(stat) + n) end
function Stats:remove(stat, n) return self:add(stat, -n) end
function C.IsoPlayer:getStats()
    if self.statsDouble == nil then self.statsDouble = setmetatable({ valuesDouble = {} }, Stats) end
    return self.statsDouble
end
-- SyncPlayerStatsPacket.java:28-34 : 1 << rang dans CharacterStat.ORDERED_STATS (BOREDOM 1, UNHAPPINESS 20).
SyncPlayerStatsPacket = { getBitMaskForStat = function(stat)
    if stat == CharacterStat.BOREDOM then return 2 end
    if stat == CharacterStat.UNHAPPINESS then return 1048576 end
    return 0
end }
local World = H.class('IsoWorld')
function World:getWorld() return "rstest_bench" end
local world = setmetatable({}, World)
getWorld = function() return world end
SandboxVars = { RadioSurvivor = { Enabled = true } }
getText = function(key) return "txt:" .. key end
'''

# Autorité : file de diffusion et rappel de réconfort de RadioSurvivor_Server (lignes 60-68, 106-137, 216-221),
# réduits à ce que lit la suite ; syncPlayerStats : paquet à la copie du joueur sur les clients.
SERVER = r'''
local H = HARNESS
local C = H.classes
local Comfort = require "RadioSurvivor/RS_Comfort"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
SYNC_OFF = false
AIRED = {}
local BITS = { { bit = 2, field = "boredom", stat = CharacterStat.BOREDOM },
    { bit = 1048576, field = "sadness", stat = CharacterStat.UNHAPPINESS } }
syncPlayerStats = function(player, mask)
    if SYNC_OFF or not isServer() then return end
    local args = { user = player:getUsername(), mask = mask }
    for _, b in ipairs(BITS) do args[b.field] = player:getStats():get(b.stat) end
    H.sendToRelative(player:getX(), player:getY(), "SyncPlayerStats", args)
end

-- RadioChannel.getAiringBroadcast (RadioChannel.java:81) : diffusion en cours ou nil ; RadioBroadCast.getID.
local Broadcast = H.class('RadioBroadCast')
function Broadcast:getID() return self.idDouble end
local Channel = H.class('RadioChannel')
function Channel:getAiringBroadcast()
    if self.airingDouble == nil then return nil end
    return setmetatable({ idDouble = self.airingDouble }, Broadcast)
end
CHANNEL = setmetatable({}, Channel)
package.loaded["RadioSurvivor/RS_Personas"] = {
    ids = function() return { "walt" } end,
    served = function(id) if id == "walt" then return { 145000 } end return {} end,
    channel = function(khz) if khz == 145000 then return CHANNEL end return nil end,
}
-- Defaut "other_character" : nouveau personnage du carnet entre la demande et la diffusion.
local function characterOf(player) return "cid-" .. player:getUsername() .. (CHARACTER_CHANGED and "-new" or "") end
package.loaded["RadioSurvivor/RS_RadioLog"] = { characterOf = characterOf }

local function findPlayer(key)
    if not isServer() then return getPlayer() end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername() == key then return p end
    end
    return nil
end
local queue = {}
local state = {}
state.air = function(khz, lines, cid, onAir)
    if DEFECT == "other_character" then CHARACTER_CHANGED = true end
    queue[#queue + 1] = { khz = khz, lines = lines, cid = cid, onAir = onAir }
end
-- Defaut "other_module" : le serveur reconforte par une autre table RS_Comfort que celle que lit la suite.
local OtherComfort = nil
if DEFECT == "other_module" then
    package.loaded["RadioSurvivor/RS_Comfort"] = nil
    OtherComfort = require "RadioSurvivor/RS_Comfort"
    package.loaded["RadioSurvivor/RS_Comfort"] = Comfort
end
state.comfort = function(caller, cid)
    return function()
        local player = findPlayer(caller)
        if DEFECT == "stale_client" then SYNC_OFF = true end
        if DEFECT == "capped" and cid then Comfort.counts["c:" .. cid] = { hour = 2, given = 99 } end
        if player then (OtherComfort or Comfort).answered(player, cid, characterOf(player)) end
        local other = H.players["B"]
        if DEFECT == "everyone" and other ~= nil and isServer() then Comfort.answered(other, nil, nil) end
        if DEFECT == "wrong_client" and other ~= nil and isServer() then
            local s = other:getStats()
            H.sendToRelative(0, 0, "SyncPlayerStats", { user = "B", mask = 2 + 1048576,
                boredom = s:get(CharacterStat.BOREDOM) - 3, sadness = s:get(CharacterStat.UNHAPPINESS) - 1 })
            Const.toClient(other, Const.CMD.COMFORT, { boredom = 3, sadness = 1 })
        end
    end
end
package.loaded["RadioSurvivor/RS_GroupRadio"] = { state = state }
-- airNext : une ligne en attente part quand la chaine est libre, puis son rappel onAir.
Events.OnTick.Add(function()
    if #queue == 0 or CHANNEL.airingDouble ~= nil then return end
    local item = table.remove(queue, 1)
    AIRED[#AIRED + 1] = item.lines[1]
    if item.onAir then item.onAir() end
end)
'''

# Clients : copie des jauges mise à jour par SyncPlayerStats (SyncPlayerStatsPacket.parse), HaloTextHelper, vrai
# RS_RadioTalk branché comme RadioSurvivor_Client.lua:62-69 (sauf défaut no_halo).
CLIENT = r'''
local H = HARNESS
H.onPacket("SyncPlayerStats", function(a)
    local p = H.players[a.user]
    if p == nil then return end
    if math.floor(a.mask / 2) % 2 == 1 then p:getStats():set(CharacterStat.BOREDOM, a.boredom) end
    if math.floor(a.mask / 1048576) % 2 == 1 then p:getStats():set(CharacterStat.UNHAPPINESS, a.sadness) end
end)
HALOS = {}
GOOD = { r = 0, g = 255, b = 0 }
HaloTextHelper = {
    addTextWithArrow = function(player, text, separator, up, color)
        HALOS[#HALOS + 1] = text .. (up and ":up" or ":down")
    end,
    getGoodColor = function() return GOOD end,
}
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Talk = require "RadioSurvivor/RS_RadioTalk"
if DEFECT ~= "no_halo" then
    Const.clientHandler = Talk.handle
    Events.OnServerCommand.Add(function(module, command, args)
        if module == Const.MODULE then Talk.handle(command, args or {}) end
    end)
end
'''

RST_FILES = 'require "RST/RST"; require "RST/RST_Steps"; require "RST/suites/RS_ComfortSuite"'
START = ('REPORT = nil; assert(RST.start({ suite = "rs.comfort", tags = { "server", "world" } }, { ctx = { side = '
         '"server", player = HARNESS.players.A }, onDone = function(r) REPORT = r end }))')
GAUGES = {REQUESTER: (12, 7), OTHER: (30, 20)}
CAP_HOUR = 2  # heure de jeu du banc (H.clock.ageHours)


class ComfortSuiteBench(unittest.TestCase):
    def build(self, mode='mp', defect=''):
        h = Harness(mode=mode, lua_roots=[DEV_LUA])
        self.addCleanup(h.close)
        self.h = h
        names = ['solo'] if mode == 'solo' else ['server', REQUESTER, OTHER]
        for m in names:
            h.load(m, f'DEFECT = "{defect}"')
            h.load(m, COMMON)
            for user, (boredom, sadness) in GAUGES.items():
                if mode == 'solo' and user != REQUESTER:
                    continue
                h.load(m, f'local s = HARNESS.players.{user}:getStats(); s:set(CharacterStat.BOREDOM, {boredom}); '
                          f's:set(CharacterStat.UNHAPPINESS, {sadness})')
        h.load('server', SERVER)
        for m in (['solo'] if mode == 'solo' else [REQUESTER, OTHER]):
            h.load(m, CLIENT)
        for m in names:
            h.load(m, RST_FILES)
        # Cap of the requester already used up this hour (cleared by the suite, restored after), another entry kept.
        h.load('server', f'local C = require "RadioSurvivor/RS_Comfort"; '
                         f'C.counts["c:cid-A"] = {{ hour = {CAP_HOUR}, given = 5 }}; '
                         f'C.counts["c:cid-Z"] = {{ hour = {CAP_HOUR}, given = 2 }}')
        return h

    def run_suite(self, frames=3000):
        h = self.h
        h.load('server', START)
        for _ in range(frames):
            h.tick()
            h.pump()
            h.advance_ms(84)   # 100 ms par image de jeu (tick_ms 16 + 84)
            if not h.eval('server', 'RST.running()'):
                break
        for _ in range(5):     # packets of the cleanup delivered
            h.tick()
            h.pump()
        report = h.eval('server', 'REPORT')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: r for r in report.results.values()}
        self.assertIn(TEST_NAME, results)
        r = results[TEST_NAME]
        notes = list(r.notes.values()) if r.notes else []
        return r.status, r.message or '', notes

    def gauges(self, machine, user):
        s = self.h.eval(machine, f'HARNESS.players.{user}:getStats()')
        return (self.h.eval(machine, f'HARNESS.players.{user}:getStats():get(CharacterStat.BOREDOM)'),
                self.h.eval(machine, f'HARNESS.players.{user}:getStats():get(CharacterStat.UNHAPPINESS)')) if s else None

    def halos(self, machine):
        return list(self.h.eval(machine, 'HALOS').values())

    def assert_restored(self, machines):
        for m in machines:
            users = [REQUESTER] if m == 'solo' else [REQUESTER, OTHER]
            for user in users:
                self.assertEqual(self.gauges(m, user), GAUGES[user], f'gauges of {user} on {m} not restored')
        server = 'solo' if 'solo' in machines else 'server'
        counts = self.h.eval(server, 'require("RadioSurvivor/RS_Comfort").counts')
        self.assertEqual({k: (v.hour, v.given) for k, v in counts.items()},
                         {'c:cid-A': (CAP_HOUR, 5), 'c:cid-Z': (CAP_HOUR, 2)})
        self.assertEqual(self.h.eval(server, 'require("RadioSurvivor/RS_Comfort").stats.applied'), 0)

    # ------------------------------------------------------------------------------------------------ tests

    def test_mp_requester_eased_and_halo_second_client_untouched(self):
        h = self.build()
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertEqual(h.eval('server', '#AIRED'), 1)
        self.assertTrue(h.eval('server', 'AIRED[1]').startswith('RST comfort '))
        self.assertEqual(self.halos(REQUESTER), ['txt:IGUI_HaloNote_Boredom:down', 'txt:IGUI_HaloNote_Unhappiness:down'])
        self.assertEqual(self.halos(OTHER), [])
        self.assertTrue(any('client A: rs.comfort.read: boredom -3.00, unhappiness -1.00' in n for n in notes), notes)
        self.assertTrue(any('client B: rs.comfort.read: boredom -0.00' in n for n in notes), notes)
        self.assert_restored(['server', REQUESTER, OTHER])

    def test_mp_busy_channel_waits_for_its_turn(self):
        h = self.build()
        h.load('server', 'CHANNEL.airingDouble = "walt reply"')
        h.at_tick(40, lambda: h.load('server', 'CHANNEL.airingDouble = nil'))
        status, message, _ = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))

    def test_mp_sandbox_amounts_are_read(self):
        h = self.build()
        for m in ('server', REQUESTER, OTHER):
            h.load(m, 'SandboxVars.RadioSurvivor.ComfortBoredom = 7; SandboxVars.RadioSurvivor.ComfortSadness = 0')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertEqual(self.halos(REQUESTER), ['txt:IGUI_HaloNote_Boredom:down'])
        self.assertTrue(any('boredom -7.00, unhappiness -0.00' in n for n in notes), notes)

    def test_comfort_turned_off_is_a_skip(self):
        h = self.build()
        h.load('server', 'SandboxVars.RadioSurvivor.ComfortPerHour = 0')
        status, message, _ = self.run_suite()
        self.assertEqual(status, 'SKIP')
        self.assertIn('turned off', message)

    def test_solo_same_code_without_second_client(self):
        self.build(mode='solo')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertEqual(self.halos('solo'), ['txt:IGUI_HaloNote_Boredom:down', 'txt:IGUI_HaloNote_Unhappiness:down'])
        self.assertTrue(any('no other client online' in n for n in notes), notes)
        self.assert_restored(['solo'])

    # ------------------------------------------------------------------------------------------------ defects

    DEFECTS = {
        'stale_client': 'boredom drop read by the requester client',
        'no_halo': 'Boredom halo (arrow down) on the requester',
        'everyone': 'boredom of B on the authority',
        'wrong_client': 'boredom drop read by the other client B',
        # Failure message names the step that failed (MP campaign of 2026-11-14: one opaque "never went on the air").
        'capped': 'the answer aired on 145.0 MHz without its comfort: hourly cap of RS_Comfort refused the comfort',
        'other_character': 'without its comfort: notebook character changed: cid-A at the request, cid-A-new on the air',
        'other_module': 'without its comfort: gauges eased on the authority but RS_Comfort.stats.applied unchanged',
    }

    def test_mp_line_never_aired_names_the_busy_channel(self):
        h = self.build()
        h.load('server', 'CHANNEL.airingDouble = "RSV-7"')
        status, message, _ = self.run_suite()
        self.assertEqual(status, 'FAIL', message)
        self.assertIn('the answer never went on the air: voice channel of 145.0 MHz still busy with broadcast RSV-7',
                      message)
        self.assertEqual(h.eval('server', '#AIRED'), 0)

    def test_mp_line_dropped_names_the_gone_channel(self):
        h = self.build()
        h.load('server', 'CHANNEL.airingDouble = "RSV-7"')
        h.at_tick(40, lambda: h.load('server', 'package.loaded["RadioSurvivor/RS_Personas"].channel = '
                                               'function() return nil end'))
        status, message, _ = self.run_suite()
        self.assertEqual(status, 'FAIL', message)
        self.assertIn('the answer never went on the air: voice channel of 145.0 MHz gone', message)

    def test_each_defect_fails_the_suite(self):
        for defect, expected in self.DEFECTS.items():
            with self.subTest(defect=defect):
                self.build(defect=defect)
                status, message, _ = self.run_suite()
                self.assertEqual(status, 'FAIL', message)
                self.assertIn(expected, message)


if __name__ == '__main__':
    unittest.main(verbosity=2)
