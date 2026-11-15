"""Out-of-sight rule and game-hour delay of the radio voices (E20-T05, ADR D06), on the mimetic bench.

    python RadioSurvivor/tests/test_out_of_sight.py

RS_OutOfSight decides when nobody can see a point: for every connected player (server copies; solo: the local
player), Chebyshev distance > 100 tiles (UdpConnection.isRelevantTo, java 42.22 UdpConnection.java:216-232, range
GameServer.java:2638-2639: at most (20 / 2 + 2) * 8 = 96 tiles, levels ignored), or the square not loaded on the
authority. The delay counts game hours (CA_GameClock: world age), never real time: a paused game stops it, a faster
game speeds it up. A player back in view resets it; the start of the wait is saved in the record, so a restart keeps it.
"""
import unittest

from harness import Harness

SIGHT = "require('RadioSurvivor/RS_OutOfSight')"


class OutOfSightTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp')
        self.h.load('server', f"Sight = {SIGHT}; W = Sight.engine(); REC = {{}}; P = {{x = 1000, y = 1000, z = 0}}")
        self.h.move_player('A', 1000, 1000, 0)
        self.h.move_player('B', 1000, 1000, 0)

    def tearDown(self):
        self.h.close()

    def lua(self, code):
        return self.h.load('server', code)

    def seen(self, x, y, z=0):
        return self.h.eval('server', f"W.inView({{x = {x}, y = {y}, z = {z}}})")

    def away(self, *names):
        for n in names or ('A', 'B'):
            self.h.move_player(n, 2000, 2000, 0)

    def watch(self, hours=6):
        return self.h.eval('server', f"(W.watch(REC, P, {hours}))")

    def test_view_is_a_square_of_one_hundred_tiles_levels_ignored(self):
        self.assertTrue(self.seen(1100, 1000))
        self.assertTrue(self.seen(1100, 900))
        self.assertTrue(self.seen(1000, 1000, 7))
        self.assertFalse(self.seen(1101, 1000))
        self.assertFalse(self.seen(1050, 899))

    def test_any_connected_player_is_a_witness(self):
        self.away('A')
        self.assertTrue(self.seen(1000, 1000))
        self.away('B')
        self.assertFalse(self.seen(1000, 1000))

    def test_dead_player_is_no_witness(self):
        self.away('A')
        self.h.kill_player('B', events=())
        self.assertFalse(self.seen(1000, 1000))

    def test_unloaded_square_is_out_of_view(self):
        self.lua("local cell = getCell(); local real = cell.getGridSquare\n"
                 "cell.getGridSquare = function(self, x, y, z) if x == 1000 then return nil end "
                 "return real(self, x, y, z) end")
        self.assertFalse(self.seen(1000, 1000))

    def test_solo_counts_the_local_player(self):
        solo = Harness(mode='solo')
        try:
            solo.move_player('A', 10, 10, 0)
            solo.load('solo', f"W = {SIGHT}.engine()")
            self.assertTrue(solo.eval('solo', "W.inView({x = 60, y = 60, z = 0})"))
            solo.move_player('A', 500, 10, 0)
            self.assertFalse(solo.eval('solo', "W.inView({x = 60, y = 60, z = 0})"))
        finally:
            solo.close()

    def test_delay_counts_game_hours_not_real_time(self):
        self.away()
        self.assertFalse(self.watch())
        self.h.advance_ms(24 * 3600 * 1000)      # paused game: real time passes, the world age does not
        self.assertFalse(self.watch())
        self.h.advance(359)
        self.assertFalse(self.watch())
        self.h.advance(1)
        self.assertTrue(self.watch())

    def test_faster_game_speed_shortens_the_real_wait(self):
        self.away()
        self.watch()
        # Speed x3: 6 game hours in a third of their real duration at x1 (90 min per day: 3.75 real min per hour).
        self.h.advance_ms(int(6 * 3.75 * 60000 / 3))
        self.h.advance(360)
        self.assertTrue(self.watch())

    def test_back_in_view_resets_the_delay(self):
        self.away()
        self.watch()
        self.h.advance(300)
        self.h.move_player('B', 1050, 1050, 0)
        self.assertFalse(self.watch())
        self.away()
        self.assertFalse(self.watch())         # poll at the departure: the wait starts again
        self.h.advance(300)
        self.assertFalse(self.watch(), 'the wait restarted when the player came back')
        self.h.advance(60)
        self.assertTrue(self.watch())

    def test_restart_keeps_the_wait_saved_in_the_record(self):
        self.away()
        self.watch()
        self.h.advance(200)
        self.lua(f"W = {SIGHT}.engine()")      # new process: only the saved record remains
        self.assertFalse(self.watch())
        self.h.advance(160)
        self.assertTrue(self.watch())

    def test_world_age_going_back_restarts_the_wait(self):
        self.away()
        self.watch()
        self.h.set_time_of_day(8)              # admin moves the clock back (age goes back)
        self.assertFalse(self.watch())         # the wait starts again from the new age
        self.h.advance(300)
        self.assertFalse(self.watch())
        self.h.advance(60)
        self.assertTrue(self.watch())

    def test_ports_are_injected(self):
        self.lua("HOURS = 10; SPOTS = {{x = 5, y = 5}}\n"
                 "V = Sight.new({positions = function() return SPOTS end, "
                 "loaded = function() return true end, hours = function() return HOURS end})\n"
                 "R = {}")
        self.assertTrue(self.h.eval('server', "V.inView({x = 100, y = 100, z = 0})"))
        self.assertFalse(self.h.eval('server', "(V.watch(R, {x = 100, y = 100, z = 0}, 2))"))
        self.lua("SPOTS = {}; HOURS = 11")
        self.assertFalse(self.h.eval('server', "(V.watch(R, {x = 100, y = 100, z = 0}, 2))"))
        self.lua("HOURS = 13")
        self.assertTrue(self.h.eval('server', "(V.watch(R, {x = 100, y = 100, z = 0}, 2))"))


if __name__ == '__main__':
    unittest.main()
