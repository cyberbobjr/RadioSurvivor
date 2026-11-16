"""Password of the voice workshop in network mode (E22-T15, ADR atelier-voix D11).

The workshop listens on the loopback without a password; on any other address (--atelier-host 0.0.0.0) every client
logs in with ATELIER_PASSWORD of bridge/.env (10 characters at least). This module holds the rules, free of HTTP:

- check_password_setting: the setting refused when absent or too short (the workshop then does not start);
- same_password: constant-time comparison (hmac.compare_digest);
- Sessions: random tokens (secrets.token_urlsafe(32)) valid 7 days, in memory only (bridge restart = log in again);
- LoginLimiter: per client address, 5 failures lock 60 s, each further failure doubles the lock up to 15 min, a
  success resets; at most GLOBAL_FAILURES failures per minute over every address, then every login refused 60 s;
- Authenticator: the three together, writing each login, failure, lock and logout in the journal (English, with the
  client address, never the password).

The clock is injected (tests). Standard library only.
"""
from __future__ import annotations

import hmac
import math
import secrets
import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass
from typing import Callable

SETTING = 'ATELIER_PASSWORD'
MIN_PASSWORD_LENGTH = 10
SESSION_SECONDS = 7 * 24 * 3600
MAX_SESSIONS = 1000
FAILURES_BEFORE_LOCK = 5
FIRST_LOCK_SECONDS = 60
MAX_LOCK_SECONDS = 15 * 60
GLOBAL_FAILURES = 30
GLOBAL_WINDOW_SECONDS = 60
GLOBAL_LOCK_SECONDS = 60
MAX_TRACKED_ADDRESSES = 4096

LOGGED_IN, BAD_PASSWORD, LOCKED = 'logged_in', 'bad_password', 'locked'

Clock = Callable[[], float]


class PasswordRefused(ValueError):
    """The password setting cannot protect the workshop: English message for the console, never the value."""


def check_password_setting(password: str | None) -> str:
    if not password:
        raise PasswordRefused(f"{SETTING} is missing from bridge/.env: the workshop needs a password to listen on the "
                              "network")
    if len(password) < MIN_PASSWORD_LENGTH:
        raise PasswordRefused(f"{SETTING} of bridge/.env is too short: {MIN_PASSWORD_LENGTH} characters at least")
    return password


def same_password(expected: str, given: str | None) -> bool:
    if not isinstance(given, str):
        return False
    return hmac.compare_digest(expected.encode('utf-8'), given.encode('utf-8'))


def _seconds(value: float) -> int:
    return max(0, math.ceil(value - 1e-9))


class Sessions:
    """Logged-in browsers: token -> end of validity. The oldest one goes when `capacity` is reached."""

    def __init__(self, clock: Clock = time.time, capacity: int = MAX_SESSIONS, lifetime: float = SESSION_SECONDS):
        self._clock, self._capacity, self._lifetime = clock, max(1, capacity), lifetime
        self._ends: OrderedDict[str, float] = OrderedDict()
        self._lock = threading.Lock()

    def create(self) -> str:
        token = secrets.token_urlsafe(32)
        with self._lock:
            now = self._clock()
            for old in [t for t, end in self._ends.items() if end <= now]:
                del self._ends[old]
            while len(self._ends) >= self._capacity:
                self._ends.popitem(last=False)
            self._ends[token] = now + self._lifetime
        return token

    def valid(self, token: str | None) -> bool:
        if not token:
            return False
        with self._lock:
            end = self._ends.get(token)
            if end is None:
                return False
            if end <= self._clock():
                del self._ends[token]
                return False
            return True

    def drop(self, token: str | None) -> bool:
        with self._lock:
            return self._ends.pop(token, None) is not None if token else False


@dataclass
class _Address:
    failures: int = 0
    locked_until: float = 0.0


class LoginLimiter:
    """Failed logins per client address and over every address (see the module docstring)."""

    def __init__(self, clock: Clock = time.time, capacity: int = MAX_TRACKED_ADDRESSES,
                 global_failures: int = GLOBAL_FAILURES):
        self._clock, self._capacity, self._global_failures = clock, max(1, capacity), global_failures
        self._addresses: OrderedDict[str, _Address] = OrderedDict()
        self._recent: deque[float] = deque()
        self._global_until = 0.0
        self._lock = threading.Lock()

    def retry_after(self, ip: str) -> int:
        """Seconds before `ip` may try again (0: now)."""
        with self._lock:
            now = self._clock()
            entry = self._addresses.get(ip)
            own = entry.locked_until if entry is not None else 0.0
            return _seconds(max(own, self._global_until) - now)

    def globally_locked(self) -> bool:
        with self._lock:
            return self._global_until > self._clock()

    def failure(self, ip: str) -> int:
        """Counts a failure of `ip`; the lock it starts in seconds (0: none)."""
        with self._lock:
            now = self._clock()
            self._count_global(now)
            entry = self._addresses.pop(ip, None) or _Address()
            self._make_room(now)
            self._addresses[ip] = entry
            entry.failures += 1
            if entry.failures < FAILURES_BEFORE_LOCK:
                return 0
            lock = min(MAX_LOCK_SECONDS, FIRST_LOCK_SECONDS * 2 ** (entry.failures - FAILURES_BEFORE_LOCK))
            entry.locked_until = now + lock
            return lock

    def success(self, ip: str) -> None:
        with self._lock:
            self._addresses.pop(ip, None)

    def tracked(self) -> int:
        with self._lock:
            return len(self._addresses)

    def _count_global(self, now: float) -> None:
        self._recent.append(now)
        while self._recent and self._recent[0] <= now - GLOBAL_WINDOW_SECONDS:
            self._recent.popleft()
        if len(self._recent) >= self._global_failures:
            self._global_until = now + GLOBAL_LOCK_SECONDS
            self._recent.clear()

    def _make_room(self, now: float) -> None:
        """Bounded table: the oldest addresses that are not locked go first, then the oldest ones."""
        if len(self._addresses) < self._capacity:
            return
        for ip in [ip for ip, e in self._addresses.items() if e.locked_until <= now]:
            del self._addresses[ip]
            if len(self._addresses) < self._capacity:
                return
        while len(self._addresses) >= self._capacity:
            self._addresses.popitem(last=False)


@dataclass(frozen=True)
class LoginResult:
    outcome: str                 # LOGGED_IN, BAD_PASSWORD or LOCKED
    token: str | None = None     # LOGGED_IN only
    retry_after: int = 0         # LOCKED: seconds before the next try


class Authenticator:
    """Logins, sessions and logouts of the workshop, each one written in the journal (`log`)."""

    def __init__(self, password: str, log: Callable[[str], None], clock: Clock = time.time,
                 sessions: Sessions | None = None, limiter: LoginLimiter | None = None):
        self._password = check_password_setting(password)
        self._log = log
        self._sessions = sessions or Sessions(clock)
        self._limiter = limiter or LoginLimiter(clock)

    def login(self, ip: str, password: str | None) -> LoginResult:
        wait = self._limiter.retry_after(ip)
        if wait:
            return LoginResult(LOCKED, retry_after=wait)
        if same_password(self._password, password):
            self._limiter.success(ip)
            self._log(f"Voice workshop: login from {ip}")
            return LoginResult(LOGGED_IN, token=self._sessions.create())
        was_global = self._limiter.globally_locked()
        lock = self._limiter.failure(ip)
        self._log(f"Voice workshop: failed login from {ip}")
        if lock:
            self._log(f"Voice workshop: logins from {ip} locked for {lock} s after repeated failures")
        if not was_global and self._limiter.globally_locked():
            self._log(f"Voice workshop: too many failed logins in a minute (last from {ip}): every login refused for "
                      f"{GLOBAL_LOCK_SECONDS} s")
        return LoginResult(BAD_PASSWORD)

    def valid(self, token: str | None) -> bool:
        return self._sessions.valid(token)

    def logout(self, ip: str, token: str | None) -> None:
        self._sessions.drop(token)
        self._log(f"Voice workshop: logout from {ip}")
