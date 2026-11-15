"""Live journal of the voice workshop (E22-T10, ADR atelier-voix D09): the last lines of the bridge and of the game.

A bounded, thread-safe ring buffer kept in memory only (the lines can hold players' dialogues: never written to disk).
Two adapters feed it through `append`: `radio_bridge.log` (source "bridge") and `game_console.GameConsole` (source
"game", the `[RadioSurvivor] personas:` lines of console.txt). The workshop reads it with `since(seq)`.

Each entry: {seq, time (epoch seconds), level (debug, info, warning, error), source, text, voice (id or None)}.
The level and the voice come from `classify`, over rule tables owned by the adapter that knows its message formats:
a rule is anchored on a fixed message format, never a keyword looked for in free text. Standard library only.
"""
from __future__ import annotations

import re
import threading
import time
from collections import deque
from typing import Callable, Iterable, Pattern

LEVELS = ('debug', 'info', 'warning', 'error')
DEFAULT_LEVEL = 'info'
DEFAULT_CAPACITY = 2000
MAX_TEXT = 8000          # a --debug dump of the LLM messages can be long: cut, the terminal keeps the whole text


def classify(text: str, level_rules: Iterable[tuple[Pattern, str]],
             voice_rules: Iterable[Pattern]) -> tuple[str, str | None]:
    """(level, voice) of a line: first level rule whose pattern matches the start of the text, else info; first voice
    rule that matches the start of the text, its group 'voice', else None."""
    level = next((lvl for pattern, lvl in level_rules if pattern.match(text)), DEFAULT_LEVEL)
    voice = None
    for pattern in voice_rules:
        match = pattern.match(text)
        if match:
            voice = match.group('voice')
            break
    return level, voice


class LogBuffer:
    """The last `capacity` lines, numbered from 1 without gap (seq); the oldest ones are dropped first."""

    def __init__(self, capacity: int = DEFAULT_CAPACITY, clock: Callable[[], float] = time.time):
        self._entries: deque[dict] = deque(maxlen=max(1, capacity))
        self._seq = 0
        self._lock = threading.Lock()
        self._clock = clock

    @property
    def last(self) -> int:
        with self._lock:
            return self._seq

    def append(self, text: str, source: str = 'bridge', level: str = DEFAULT_LEVEL, voice: str | None = None) -> dict:
        text = str(text)
        if len(text) > MAX_TEXT:
            text = text[:MAX_TEXT] + ' [...]'
        with self._lock:
            self._seq += 1
            entry = {'seq': self._seq, 'time': round(self._clock(), 3),
                     'level': level if level in LEVELS else DEFAULT_LEVEL,
                     'source': source, 'text': text, 'voice': voice}
            self._entries.append(entry)
        return entry

    def since(self, seq: int) -> tuple[list[dict], int]:
        """Entries after `seq` and the last seq. A cursor beyond the last one (the bridge restarted, the page did not)
        gives every entry kept."""
        with self._lock:
            last = self._seq
            if not self._entries:
                return [], last
            if seq > last or seq < 0:
                seq = 0
            start = max(0, seq - self._entries[0]['seq'] + 1)
            return [dict(e) for e in list(self._entries)[start:]], last


def compile_rules(rules: Iterable[tuple[str, str]]) -> tuple[tuple[Pattern, str], ...]:
    """Level rules written as (regex, level)."""
    return tuple((re.compile(pattern), level) for pattern, level in rules)
