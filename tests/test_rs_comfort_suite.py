"""Banc hors jeu de la suite en jeu rs.comfort (E05-T15, RS_ComfortSuite.lua) et de ses étapes client
(RST_PeerChecksComfort.lua).

    python RadioSurvivor/tests/test_rs_comfort_suite.py

Serveur dédié et deux clients du banc (tests/harness.py : machines lupa séparées, réseau en file), puis un solo. Réels :
moteur RST (RST.lua, RST_Steps.lua), la suite et ses étapes, RS_Comfort.lua et RadioSurvivor_Const.lua sur l'autorité,
RS_RadioTalk.lua sur les clients (halo de la commande comfort, branché comme RadioSurvivor_Client.lua). Doublures : file
de diffusion et rappel de réconfort de RadioSurvivor_Server (queueAir, airNext, comfortOnAir, liés par GroupRadio.bind),
voix et chaîne (RS_Personas), personnage du carnet (RS_RadioLog.characterOf), jauges (Stats, CharacterStat), paquet
SyncPlayerStats (livré par la file du banc, appliqué à la copie du joueur sur le client), HaloTextHelper.
Mode dieu sur l'autorité (setGodMod forcé, remise à zéro des stats à chaque mise à jour comme BodyDamage.Update) : la
suite le lève pour le test et le rend (2e passage MP du 2026-11-14).
La suite passe sur les doublures et échoue sur chaque défaut injecté (DEFECTS) : jauges jamais synchronisées vers le
client, halo absent, réconfort aussi accordé au second joueur (autorité), baisse et halo chez le second client seul ;
isolation du second joueur jugée sur le réconfort (compteur, plafond, halo, montants), pas sur ses jauges absolues ;
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

from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
DEV_LUA = tests_lua()
REQUESTER, OTHER = 'A', 'B'
TEST_NAME = 'an answer on the air eases the requester only: gauges and halo on his client (E05-T15)'
# SyncPlayerStatsPacket.java:19 : reliability 2 (fiable, non ordonné), aucun flux ordonné.
harness_module.PACKET_CHANNELS.setdefault('SyncPlayerStats', None)
# PlayerStatsPacket.java:20 : reliability 3, ordering 12 (fiable ordonné), serveur -> client toutes les 1000 ms.
harness_module.PACKET_CHANNELS.setdefault('PlayerStats', 12)

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
-- God mode (CheatType.GOD_MODE). setGodMod(b) honours the role (ToggleGodModHimself: the bench players have none,
-- IsoGameCharacter.java:11237-11245); setGodMod(b, true) forces it like the server command godmodeplayer
-- (GodModePlayerCommand.java:41, IsoGameCharacter.java:11226-11234). On the authority, BodyDamage.Update of a god-mode
-- player calls RestoreToFullHealth -> Stats.resetStats every update (BodyDamage.java:1820-1823, 1564-1570).
function C.IsoPlayer:isGodMod() return self.godDouble == true end
function C.IsoPlayer:setGodMod(b, forced)
    if self:isDead() then return end
    if forced or self.godRightDouble then self.godDouble = b == true else self.godDouble = false end
end
-- ExtraInfoPacket.processServer (ExtraInfoPacket.java:238-245) : the client's own god mode flag, sent by
-- sendPlayerExtraInfo, applied with setGodMod(b) when its role has ToggleGodModHimself (godRightDouble).
-- GOD_BACK = { user, afterMs } : that client re-sends its god mode afterMs after the line aired.
local godBackAt = nil
Events.OnTick.Add(function()
    if GOD_BACK and AIRED_AT and godBackAt == nil then godBackAt = AIRED_AT + GOD_BACK.afterMs end
    if godBackAt and getTimestampMs() >= godBackAt then
        local p = H.players[GOD_BACK.user]
        p.godRightDouble = true
        p:setGodMod(true)
        GOD_BACK, godBackAt = nil, nil
    end
    for _, p in pairs(H.players) do
        if p:isGodMod() and not p:isDead() then
            p:getStats():set(CharacterStat.BOREDOM, 0)
            p:getStats():set(CharacterStat.UNHAPPINESS, 0)
        end
    end
end)
-- NetworkPlayerManager.update (NetworkPlayerManager.java:14, 25-35) : every 1000 ms the dedicated server sends each
-- client the full stats of its player (NetworkPlayerAI.syncStats -> PlayerStatsPacket, Stats.save / Stats.load).
local nextStatsAt = 0
Events.OnTick.Add(function()
    if SYNC_OFF or not isServer() or getTimestampMs() < nextStatsAt then return end   -- stale_client: no packet at all
    nextStatsAt = getTimestampMs() + 1000
    for user, p in pairs(H.players) do
        local s = p:getStats()
        H.sendToRelative(p:getX(), p:getY(), "PlayerStats", { user = user,
            boredom = s:get(CharacterStat.BOREDOM), sadness = s:get(CharacterStat.UNHAPPINESS) })
    end
end)
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
    -- Defaut "god_mode" : god mode given back to the requester on the authority before the line airs.
    if DEFECT == "god_mode" then H.players["A"]:setGodMod(true, true) end
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
        -- Defaut "other_eased" : gauges of B lowered on the authority by the comfort amounts, outside RS_Comfort.
        if DEFECT == "other_eased" and other ~= nil and isServer() then
            other:getStats():remove(CharacterStat.BOREDOM, 3)
            other:getStats():remove(CharacterStat.UNHAPPINESS, 1)
        end
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
    AIRED_AT = getTimestampMs()
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
-- PlayerStatsPacket.parse (PlayerStatsPacket.java:47-55) : every stat of the client copy replaced.
H.onPacket("PlayerStats", function(a)
    local p = H.players[a.user]
    if p == nil then return end
    p:getStats():set(CharacterStat.BOREDOM, a.boredom)
    p:getStats():set(CharacterStat.UNHAPPINESS, a.sadness)
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

    def test_mp_god_mode_on_the_authority_lifted_for_the_test_and_restored(self):
        # MP campaign of 2026-11-14 (2nd run): both accounts in god mode on the server (autoclient godmodeplayer); the
        # authority reset their gauges every update, so the comfort found nothing to ease.
        h = self.build()
        for user in (REQUESTER, OTHER):
            h.load('server', f'HARNESS.players.{user}:setGodMod(true, true)')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertEqual(self.halos(REQUESTER), ['txt:IGUI_HaloNote_Boredom:down', 'txt:IGUI_HaloNote_Unhappiness:down'])
        self.assertEqual(self.halos(OTHER), [])
        self.assertTrue(any('client A: rs.comfort.read: boredom -3.00, unhappiness -1.00' in n for n in notes), notes)
        for user in (REQUESTER, OTHER):
            self.assertTrue(h.eval('server', f'HARNESS.players.{user}:isGodMod()'), f'god mode of {user} not restored')

    def test_mp_second_client_god_mode_back_does_not_fail_isolation(self):
        # Full MP campaign of 2026-11-14 13:24: rs_mp2 read its gauges at 0 three seconds after the air ("boredom drop
        # read by the other client rs_mp2: expected 0 +/- 0.5, got 49.999"). Here its client re-sends god mode
        # (ExtraInfo) after the air: the authority resets its stats, the next PlayerStats packet brings 0 to client B.
        # Isolation is about the comfort (counter, cap, halo, comfort amounts), not the absolute gauges of B.
        h = self.build()
        h.load('server', f'GOD_BACK = {{ user = "{OTHER}", afterMs = 500 }}')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertEqual(self.halos(OTHER), [])
        self.assertTrue(h.eval('server', f'HARNESS.players.{OTHER}:isGodMod()'))
        self.assertTrue(any('gauges of B moved by the game' in n for n in notes), notes)

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
        'everyone': 'comforts applied for one answer (RS_Comfort.stats.applied): expected 1, got 2',
        'other_eased': 'gauges of B on the authority lowered by the comfort amounts (boredom -3.00, unhappiness -1.00)',
        'wrong_client': 'halos shown on the other client B: expected 0, got 2',
        # Failure message names the step that failed (MP campaign of 2026-11-14: one opaque "never went on the air").
        'capped': 'the answer aired on 145.0 MHz without its comfort: hourly cap of RS_Comfort refused the comfort',
        'other_character': 'without its comfort: notebook character changed: cid-A at the request, cid-A-new on the air',
        'other_module': 'without its comfort: gauges eased on the authority but RS_Comfort.stats.applied unchanged',
        'god_mode': 'without its comfort: god mode on the authority resets the stats every tick (BodyDamage.RestoreToFullHealth)',
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
