"""Banc hors jeu de la suite en jeu rs.missions.clock (E11-T20, RS_MissionClock.lua) : délais des missions en temps
de jeu, chrono arrêté pendant la pause et accéléré en avance rapide, en solo.

    python tests/test_rs_mission_clock_suite.py

Solo du banc (tests/harness.py, mode='solo', une image = TICK_MS ms réelles). Réels : moteur RST (RST.lua), la suite,
CA_Missions.advance et CA_GameClock (compteur de temps de jeu) du mod commun. Doublures fidèles au Java 42.22 :
- SpeedControls par les globales setGameSpeed / getGameSpeed / isGamePaused (LuaManager.java:6420-6450,
  SpeedControls.java:100-147, GameTime.java:191-200) : SetCurrentGameSpeed remet le multiplicateur de GameTime à 1,
  la vitesse 0 garde vitesse et multiplicateur d'avant la pause, la vitesse 5 les rend ; en solo getGameSpeed rend la
  vitesse courante et isGamePaused vaut vitesse == 0 ;
- GameTime.setMultiplier / getTrueMultiplier / getWorldAgeHours ; l'âge du monde avance dans GameTime.update, avant
  OnTick (IngameState.java:1573-1582), de la durée réelle de l'image fois le multiplicateur, un jour de jeu durant
  getMinutesPerDay minutes réelles à x1 (GameTime.java:474-480) ;
- image en pause (GameWindow.java:373-391) : seul OnTickEvenPaused part, ni GameTime.update ni OnTick : la boucle du
  banc met la machine en pause (h.set_paused) au début de chaque image où isGamePaused() est vrai ;
- donneur 'npc' du moteur réduit à find (comme RS_MissionHooks pour une fiche sans moteur : toujours présente).
La suite passe sur ces doublures, rend la vitesse trouvée au départ (jamais une partie en pause), retire ses abonnés,
et échoue sur chaque défaut injecté (DEFECTS) : décompte en temps réel, décompte en temps réel arrêté seulement par la
pause (vitesse ignorée), CA_Missions.advance en erreur pendant la pause (la partie reprend quand même).
Ne prouve ni l'API Java réelle (SpeedControls présent, facteur réel de l'avance rapide) ni la cadence réelle du jeu :
la campagne solo-rs en jeu reste nécessaire.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import ROOT, Harness  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402

from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
DEV_LUA = tests_lua()
TICK_MS = 100
TEST_NAME = 'countdown stopped while paused, faster at fast-forward (E11-T20)'

COMMON = r'''
local H = HARNESS
local World = H.class('IsoWorld')
function World:getWorld() return "rstest_bench" end
local world = setmetatable({}, World)
getWorld = function() return world end

FRAME_MS = %d
SPEED = { current = 1, multiplier = 1, speedBeforePause = 1, multiBeforePause = 1, age = 100 }
local GT = H.classes.GameTime
function GT:setMultiplier(m) SPEED.multiplier = m end
function GT:getTrueMultiplier() return SPEED.multiplier end
function GT:getWorldAgeHours() return SPEED.age end
-- SpeedControls.SetCurrentGameSpeed (SpeedControls.java:129-147) through LuaManager.setGameSpeed (6429-6437).
setGameSpeed = function(n)
    SPEED.multiplier = 1
    if n == 0 then SPEED.speedBeforePause, SPEED.multiBeforePause = SPEED.current, SPEED.multiplier end
    if n == 5 then
        n = SPEED.speedBeforePause
        SPEED.multiplier = SPEED.multiBeforePause
    end
    SPEED.current = n
end
getGameSpeed = function() return SPEED.current end          -- SpeedControls.java:100-105 (solo)
isGamePaused = function() return SPEED.current == 0 end      -- GameTime.java:191-200 (solo)
-- GameTime.update before OnTick of the frame (subscribed before RST attaches): frame time x multiplier.
Events.OnTick.Add(function()
    if isGamePaused() then return end
    SPEED.age = SPEED.age + FRAME_MS * SPEED.multiplier / (getGameTime():getMinutesPerDay() * 60000 / 24)
end)
-- Listener counts of the two tick events (the suite must remove what it adds).
LISTENERS = { OnTick = 0, OnTickEvenPaused = 0 }
for _, name in ipairs({ "OnTick", "OnTickEvenPaused" }) do
    local e = Events[name]
    local add, remove = e.Add, e.Remove
    e.Add = function(f) LISTENERS[name] = LISTENERS[name] + 1 return add(f) end
    e.Remove = function(f) LISTENERS[name] = LISTENERS[name] - 1 return remove(f) end
end
-- Giver 'npc' of the engine (RS_MissionHooks npcGiver: a fiche of no engine is always present).
require('CoreAI/CA_Missions').registerDonor('npc', {
    find = function(state, id) return state.npcs and state.npcs[id] or nil end })
''' % TICK_MS

DEFECTS = {
    # Countdown in real time (getTimestampMs): runs on while paused.
    'real_time': ('countdown moved while paused', r'''
require('CoreAI/CA_GameClock').meter = function()
    local last
    return function()
        local now = getTimestampMs()
        local d = last and now - last or 0
        last = now
        return d
    end
end'''),
    # Countdown in real time, stopped by the pause only: the game speed is ignored.
    'speed_ignored': ('fast: countdown = world age elapsed x msPerHour', r'''
require('CoreAI/CA_GameClock').meter = function()
    local last
    return function()
        local now = getTimestampMs()
        local d = (last and not isGamePaused()) and now - last or 0
        last = now
        return d
    end
end'''),
    # The engine raises while the game is paused: the test fails, the game still resumes.
    'advance_error': ('CA_Missions.advance raised in the driver', r'''
local M = require('CoreAI/CA_Missions')
local real = M.advance
M.advance = function(state, ms)
    if isGamePaused() then error("advance broken while paused") end
    return real(state, ms)
end'''),
}

START = ('REPORT = nil; assert(RST.start({ suite = "rs.missions.clock", tags = { "world" } }, '
         '{ onDone = function(r) REPORT = r end }))')


class MissionClockSuiteBench(unittest.TestCase):
    def build(self, defect: str = '', before: str = ''):
        h = Harness(mode='solo', lua_roots=[DEV_LUA], tick_ms=TICK_MS)
        self.addCleanup(h.close)
        self.h = h
        h.load('solo', SIGNAL_SMOKE)
        h.load('solo', COMMON)
        h.load('solo', 'require "RST/RST"; require "RST/suites/RS_MissionClock"')
        if defect:
            h.load('solo', DEFECTS[defect][1])
        if before:
            h.load('solo', before)
        return h

    def run_suite(self, frames: int = 3000):
        h = self.h
        h.load('solo', START)
        self.paused_frames = 0
        for _ in range(frames):
            paused = bool(h.eval('solo', 'isGamePaused()'))
            self.paused_frames += paused
            h.set_paused('solo', paused)
            h.tick()
            if not h.eval('solo', 'RST.running()'):
                break
        report = h.eval('solo', 'REPORT')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: r for r in report.results.values()}
        self.assertIn(TEST_NAME, results)
        r = results[TEST_NAME]
        notes = list(r.notes.values()) if r.notes else []
        return r.status, r.message or '', notes

    def speed(self):
        return self.h.eval('solo', 'SPEED.current'), self.h.eval('solo', 'SPEED.multiplier')

    def assert_left_clean(self, speed=(1, 1)):
        self.assertEqual(self.speed(), speed, 'game speed not restored')
        self.assertFalse(self.h.eval('solo', 'isGamePaused()'), 'game left paused')
        self.assertEqual(self.h.eval('solo', 'LISTENERS.OnTickEvenPaused'), 0, 'driver left subscribed')
        self.assertEqual(self.h.eval('solo', 'LISTENERS.OnTick'), 0, 'OnTick counter left subscribed')

    # ------------------------------------------------------------------------------------------------ tests

    def test_pause_stops_and_fast_forward_speeds_the_countdown(self):
        self.build()
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''), notes)
        self.assertTrue(any(n.endswith('play ms in 3000 real ms (rate 1)') for n in notes), notes)
        self.assertTrue(any(n.startswith('pause: 0 play ms counted in 2900 real ms') and
                            n.endswith('OnTick fired 0 times') for n in notes), notes)
        self.assertTrue(any('ratio to x1 20.01 (expected about 20)' in n for n in notes), notes)
        self.assertGreaterEqual(self.paused_frames, 30)
        self.assert_left_clean()

    def test_fast_forward_found_at_the_start_is_restored(self):
        self.build(before='setGameSpeed(2); getGameTime():setMultiplier(5)')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''), notes)
        self.assert_left_clean(speed=(2, 5))

    def test_mp_or_dedicated_server_is_a_skip(self):
        for side in ('isClient', 'isServer'):
            with self.subTest(side=side):
                self.build(before=f'{side} = function() return true end')
                status, message, _ = self.run_suite()
                self.assertEqual(status, 'SKIP')
                self.assertIn('solo only', message)
                self.assertEqual(self.paused_frames, 0)
                self.assert_left_clean()

    def test_each_defect_fails_and_never_leaves_the_game_paused(self):
        for defect, (expected, _) in DEFECTS.items():
            with self.subTest(defect=defect):
                self.build(defect=defect)
                status, message, _ = self.run_suite()
                self.assertEqual(status, 'FAIL', message)
                self.assertIn(expected, message)
                self.assert_left_clean()


if __name__ == '__main__':
    unittest.main(verbosity=2)
