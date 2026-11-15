"""The game's verdict on the voice sheets (E22-T04, ADR atelier-voix D03) and its lines in the live journal (E22-T10, D09).

The game is the only judge of a sheet: RS_Personas.lua writes in the console (`<Zomboid>/console.txt` in solo, the
console file of a dedicated server) a line per sheet it reads, with the prefix `[RadioSurvivor] personas: `
(docs/specifications-techniques/persona-format.md, "Chargement par le serveur", "Erreurs"):

    ERROR: batman_RadioSurvivor/personas/<id>.txt refused, line N: <reason>[; the previous valid version stays ...]
    voice '<id>' loaded: state ..., ...          voice '<id>' updated: state ..., ...
    INFO: voice '<id>' updated to the delivered version (...)
    voice '<id>' removed (<why>)

`GameConsole.refresh()` reads the new lines of that file (missing file tolerated; a file rewritten at game start is
read again from its start), copies every persona line into the journal (source "game") and keeps the last verdict per
sheet: refused (line, reason) until a later line shows the voice loaded, updated or removed, or until the text of the
sheet changes (state "changed": the game reads it again within 30 s). Standard library only.
"""
from __future__ import annotations

import hashlib
import os
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Protocol

import log_buffer

MARK = '[RadioSurvivor] personas: '
ID = r'[a-z][a-z0-9_]{0,31}'
HEAD_BYTES = 256          # start of the file: when it changes, the game wrote a new console
TRAILER = r'(?:; the previous valid version stays in service)?\.?$'   # ".": the DebugLog copy ends lines with a dot

# Events of a sheet, extended by data: (pattern of the message, state).
EVENTS: tuple[tuple[re.Pattern, str], ...] = (
    (re.compile(rf'^ERROR: batman_RadioSurvivor/personas/(?P<voice>{ID})\.txt refused, '
                rf'(?:line (?P<line>\d+): )?(?P<reason>.*?){TRAILER}'), 'refused'),
    (re.compile(rf"^voice '(?P<voice>{ID})' (?:loaded|updated): "), 'loaded'),
    (re.compile(rf"^INFO: voice '(?P<voice>{ID})' updated to the delivered version"), 'loaded'),
    (re.compile(rf"^voice '(?P<voice>{ID})' removed \("), 'removed'),
)
LEVEL_RULES = log_buffer.compile_rules((('ERROR:', 'error'), ('WARNING:', 'warning'), ('INFO:', 'info')))
# The persona lines are the game's own fixed formats (no player text): the first voice named is the one concerned.
VOICE_RULES = (re.compile(rf'^.*?personas/(?P<voice>{ID})\.txt\b'), re.compile(rf"^.*?\bvoice '(?P<voice>{ID})'"))


class LogSink(Protocol):
    def append(self, text: str, source: str = ..., level: str = ..., voice: str | None = ...) -> dict: ...


@dataclass
class Verdict:
    state: str                 # refused, loaded, removed
    time: float
    line: int | None = None
    reason: str | None = None
    digest: str | None = None  # text of the sheet when the refusal was first shown


def persona_message(line: str) -> str | None:
    """Message after the `[RadioSurvivor] personas: ` prefix, None for any other console line."""
    at = line.find(MARK)
    return line[at + len(MARK):].rstrip('\r\n') if at >= 0 else None


def sheet_event(message: str) -> tuple[str, str, int | None, str | None] | None:
    """(voice, state, line, reason) of a persona message that tells the fate of a sheet, else None."""
    for pattern, state in EVENTS:
        match = pattern.match(message)
        if match:
            groups = match.groupdict()
            line = groups.get('line')
            return groups['voice'], state, int(line) if line else None, groups.get('reason')
    return None


def digest(text: bytes | str | None) -> str | None:
    """Fingerprint of a sheet text, line endings ignored (as the game's)."""
    if text is None:
        return None
    raw = text.encode('utf-8') if isinstance(text, str) else text
    return hashlib.sha1(raw.replace(b'\r\n', b'\n')).hexdigest()


class ConsoleTail:
    """New complete lines of a growing text file. Missing file: no line. Rewritten file (shorter than what was read,
    or a different start): read again from its start. A last line without its line break waits for it."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.offset = 0
        self.head = b''

    @property
    def found(self) -> bool:
        return self.path.is_file()

    def read(self) -> list[str]:
        try:
            with self.path.open('rb') as handle:
                size = os.fstat(handle.fileno()).st_size
                head = handle.read(min(HEAD_BYTES, size))
                common = min(len(head), len(self.head))
                if size < self.offset or head[:common] != self.head[:common]:
                    self.offset = 0          # a new console: the game started again
                self.head = head
                handle.seek(self.offset)
                data = handle.read(max(0, size - self.offset))
        except OSError:
            return []
        end = data.rfind(b'\n') + 1
        self.offset += end
        return data[:end].decode('utf-8', errors='replace').splitlines()


class GameConsole:
    """Adapter of the game's console: persona lines into the journal, last verdict per sheet."""

    def __init__(self, path: Path, sink: LogSink | None = None, clock: Callable[[], float] = time.time):
        self.tail = ConsoleTail(path)
        self.sink = sink
        self.clock = clock
        self._verdicts: dict[str, Verdict] = {}
        self._lock = threading.Lock()

    @property
    def path(self) -> Path:
        return self.tail.path

    @property
    def found(self) -> bool:
        return self.tail.found

    def _console_mtime(self) -> float | None:
        try:
            return self.tail.path.stat().st_mtime
        except OSError:
            return None

    def refresh(self) -> None:
        with self._lock:
            for line in self.tail.read():
                message = persona_message(line)
                if message is None:
                    continue
                now = self.clock()
                if self.sink is not None:
                    level, voice = log_buffer.classify(message, LEVEL_RULES, VOICE_RULES)
                    self.sink.append(f'personas: {message}', 'game', level, voice)
                event = sheet_event(message)
                if event:
                    voice, state, line_no, reason = event
                    self._verdicts[voice] = Verdict(state, now, line_no, reason)

    def verdicts(self, read_sheet: Callable[[str], bytes | str | None],
                 sheet_mtime: Callable[[str], float | None] | None = None) -> dict[str, dict]:
        """Verdict per voice id. A refusal is "changed" when the sheet text changed since the refusal was shown, or
        when the sheet file is newer than the console (written, restored or recopied after the game's last line: the
        game has not judged this version yet; an old console of a closed game keeps no stale refusal)."""
        out = {}
        console_mtime = self._console_mtime()
        with self._lock:
            for voice, verdict in self._verdicts.items():
                state = verdict.state
                if state == 'refused':
                    current = digest(read_sheet(voice))
                    if verdict.digest is None:
                        verdict.digest = current
                    elif current != verdict.digest:
                        state = 'changed'
                    if state == 'refused' and sheet_mtime is not None and console_mtime is not None:
                        mtime = sheet_mtime(voice)
                        if mtime is None or mtime > console_mtime:
                            state = 'changed'
                out[voice] = {'state': state, 'line': verdict.line, 'reason': verdict.reason,
                              'time': round(verdict.time, 3)}
        return out
