"""E22-T15: password of the voice workshop in network mode (bridge/atelier_auth.py, ADR atelier-voix D11).

    python RadioSurvivor/tests/test_atelier_auth.py

Pure logic over a fake clock: password setting refused when absent or short, constant-time comparison, sessions and
their expiry, per-address lock (5 failures, 60 s, doubled up to 15 min, reset on success), global limiter, bounded
address table, journal lines (address, never the password). No socket.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import atelier_auth as auth  # noqa: E402

PASSWORD = "correct horse battery"


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class PasswordSettingTests(unittest.TestCase):
    def test_missing_or_short_password_is_refused(self):
        for value in (None, "", "qzx", "123456789"):
            with self.assertRaises(auth.PasswordRefused) as caught:
                auth.check_password_setting(value)
            self.assertIn("ATELIER_PASSWORD", str(caught.exception))
            if value:
                self.assertNotIn(value, str(caught.exception))

    def test_ten_characters_are_enough(self):
        self.assertEqual(auth.check_password_setting("0123456789"), "0123456789")

    def test_compare(self):
        self.assertTrue(auth.same_password(PASSWORD, PASSWORD))
        self.assertFalse(auth.same_password(PASSWORD, PASSWORD + "x"))
        self.assertFalse(auth.same_password(PASSWORD, ""))
        self.assertFalse(auth.same_password(PASSWORD, None))
        self.assertTrue(auth.same_password("mot de passe été", "mot de passe été"))


class SessionTests(unittest.TestCase):
    def test_session_lives_seven_days(self):
        clock = Clock()
        sessions = auth.Sessions(clock)
        token = sessions.create()
        self.assertGreaterEqual(len(token), 40)
        self.assertTrue(sessions.valid(token))
        clock.now += auth.SESSION_SECONDS - 1
        self.assertTrue(sessions.valid(token))
        clock.now += 2
        self.assertFalse(sessions.valid(token))

    def test_tokens_are_unique_and_unknown_ones_refused(self):
        sessions = auth.Sessions(Clock())
        first, second = sessions.create(), sessions.create()
        self.assertNotEqual(first, second)
        for token in (None, "", "forged", first + "x"):
            self.assertFalse(sessions.valid(token))

    def test_drop_ends_a_session(self):
        sessions = auth.Sessions(Clock())
        token = sessions.create()
        self.assertTrue(sessions.drop(token))
        self.assertFalse(sessions.valid(token))
        self.assertFalse(sessions.drop(token))

    def test_session_count_is_bounded(self):
        sessions = auth.Sessions(Clock(), capacity=3)
        tokens = [sessions.create() for _ in range(5)]
        self.assertEqual([sessions.valid(t) for t in tokens], [False, False, True, True, True])


class LimiterTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.limiter = auth.LoginLimiter(self.clock)

    def fail(self, ip: str, times: int):
        return [self.limiter.failure(ip) for _ in range(times)]

    def test_five_failures_lock_sixty_seconds(self):
        self.assertEqual(self.fail("10.0.0.2", 4), [0, 0, 0, 0])
        self.assertEqual(self.limiter.retry_after("10.0.0.2"), 0)
        self.assertEqual(self.limiter.failure("10.0.0.2"), 60)
        self.assertEqual(self.limiter.retry_after("10.0.0.2"), 60)
        self.assertEqual(self.limiter.retry_after("10.0.0.3"), 0)     # another address is free
        self.clock.now += 59.5
        self.assertEqual(self.limiter.retry_after("10.0.0.2"), 1)     # rounded up
        self.clock.now += 0.5
        self.assertEqual(self.limiter.retry_after("10.0.0.2"), 0)

    def test_each_further_failure_doubles_up_to_fifteen_minutes(self):
        self.fail("10.0.0.2", 5)
        locks = []
        for _ in range(6):
            self.clock.now += self.limiter.retry_after("10.0.0.2")
            locks.append(self.limiter.failure("10.0.0.2"))
        self.assertEqual(locks, [120, 240, 480, 900, 900, 900])

    def test_success_resets(self):
        self.fail("10.0.0.2", 5)
        self.limiter.success("10.0.0.2")
        self.assertEqual(self.limiter.retry_after("10.0.0.2"), 0)
        self.assertEqual(self.fail("10.0.0.2", 4), [0, 0, 0, 0])

    def test_global_limiter_locks_every_address(self):
        for n in range(auth.GLOBAL_FAILURES - 1):
            self.limiter.failure(f"10.1.{n // 4}.{n % 4}")              # never five from one address
        self.assertEqual(self.limiter.retry_after("10.9.9.9"), 0)
        self.assertFalse(self.limiter.globally_locked())
        self.limiter.failure("10.2.0.1")
        self.assertTrue(self.limiter.globally_locked())
        self.assertEqual(self.limiter.retry_after("10.9.9.9"), auth.GLOBAL_LOCK_SECONDS)
        self.clock.now += auth.GLOBAL_LOCK_SECONDS
        self.assertEqual(self.limiter.retry_after("10.9.9.9"), 0)

    def test_failures_older_than_the_window_do_not_count_globally(self):
        for n in range(auth.GLOBAL_FAILURES - 1):
            self.limiter.failure(f"10.1.{n // 4}.{n % 4}")
        self.clock.now += auth.GLOBAL_WINDOW_SECONDS + 1
        self.limiter.failure("10.2.0.1")
        self.assertFalse(self.limiter.globally_locked())

    def test_address_table_is_bounded_and_keeps_locked_ones(self):
        limiter = auth.LoginLimiter(self.clock, capacity=4, global_failures=10_000)
        for _ in range(5):
            limiter.failure("10.0.0.1")                                 # locked
        for n in range(10):
            limiter.failure(f"10.0.1.{n}")
        self.assertLessEqual(limiter.tracked(), 4)
        self.assertEqual(limiter.retry_after("10.0.0.1"), 60)


class AuthenticatorTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.lines: list[str] = []
        self.gate = auth.Authenticator(PASSWORD, self.lines.append, self.clock)

    def test_good_password_opens_a_session(self):
        result = self.gate.login("10.0.0.2", PASSWORD)
        self.assertEqual(result.outcome, auth.LOGGED_IN)
        self.assertTrue(self.gate.valid(result.token))
        self.assertTrue(any("10.0.0.2" in line and "login" in line for line in self.lines))

    def test_wrong_password_then_lock(self):
        for _ in range(4):
            result = self.gate.login("10.0.0.2", "wrong password")
            self.assertEqual(result.outcome, auth.BAD_PASSWORD)
            self.assertIsNone(result.token)
        result = self.gate.login("10.0.0.2", "wrong password")
        self.assertEqual(result.outcome, auth.BAD_PASSWORD)
        result = self.gate.login("10.0.0.2", PASSWORD)              # even the right one while locked
        self.assertEqual(result.outcome, auth.LOCKED)
        self.assertEqual(result.retry_after, 60)
        self.assertIsNone(result.token)
        self.clock.now += 60
        self.assertEqual(self.gate.login("10.0.0.2", PASSWORD).outcome, auth.LOGGED_IN)
        joined = "\n".join(self.lines)
        self.assertIn("locked for 60 s", joined)
        self.assertNotIn("wrong password", joined)
        self.assertNotIn(PASSWORD, joined)
        self.assertTrue(all("10.0.0.2" in line for line in self.lines))

    def test_logout_ends_the_session(self):
        token = self.gate.login("10.0.0.2", PASSWORD).token
        self.gate.logout("10.0.0.2", token)
        self.assertFalse(self.gate.valid(token))
        self.assertIn("logout", self.lines[-1])

    def test_global_lock_is_logged_once(self):
        for n in range(auth.GLOBAL_FAILURES):
            self.gate.login(f"10.1.{n // 4}.{n % 4}", "nope nope nope")
        self.assertEqual(self.gate.login("10.9.9.9", PASSWORD).outcome, auth.LOCKED)
        self.assertEqual(sum("every login refused" in line for line in self.lines), 1)


if __name__ == "__main__":
    unittest.main()
