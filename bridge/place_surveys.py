"""Places recorded in game for the voice workshop (E22-T08, ADR atelier-voix D08).

A right click in the game, "Voice workshop: record this place" (solo or admin), makes the authority append a line to
`<Zomboid>/Lua/batman_RadioSurvivor/workshop-places.txt` (server/RadioSurvivor/RS_PlaceSurvey.lua, last 200 records
kept). Format (docs/specifications-techniques/persona-format.md, "Relevé de lieux en jeu"): lines starting with `#` are
comments; every other line is one record, fields separated by a tab, each `key=value`:

    time=<real UTC>  game=<game date>  by=<character>  at=<x>,<y>,<z>
    [room=<room name>]  [building=<x1>,<y1>,<x2>,<y2>]  [containers=<type>:<sprite>;...]

`SurveyFile.records()` reads the file each time (missing file: no record; rewritten file: read anew; unreadable or
malformed lines skipped) and returns the records newest first. Read only: the workshop never writes this file.
Standard library only.
"""
from __future__ import annotations

from pathlib import Path

FILE_NAME = 'workshop-places.txt'
MAX_RECORDS = 200            # as RS_PlaceSurvey.MAX_RECORDS: the game keeps no more
MAX_BYTES = 512 * 1024       # a bigger file is read from its end only
FIELD_CHARS = 1024          # a value longer than any the game writes is cut


def _ints(text: str, count: int) -> list[int] | None:
    parts = text.split(',')
    if len(parts) != count:
        return None
    try:
        return [int(part.strip()) for part in parts]
    except ValueError:
        return None


def parse_line(line: str) -> dict | None:
    """Record of one line of the survey file, None for a comment, a blank or a malformed line (no valid `at=`)."""
    line = line.rstrip('\r\n')
    if not line.strip() or line.startswith('#'):
        return None
    fields: dict[str, str] = {}
    for part in line.split('\t'):
        key, sep, value = part.partition('=')
        if sep:
            fields[key.strip()] = value.strip()[:FIELD_CHARS]
    at = _ints(fields.get('at', ''), 3)
    if at is None:
        return None
    record = {'at': {'x': at[0], 'y': at[1], 'z': at[2]}, 'time': fields.get('time', ''),
              'game': fields.get('game', ''), 'by': fields.get('by', ''), 'room': fields.get('room') or None,
              'building': None, 'containers': []}
    bounds = _ints(fields.get('building', ''), 4)
    if bounds is not None:
        record['building'] = dict(zip(('x1', 'y1', 'x2', 'y2'), bounds))
    for item in filter(None, fields.get('containers', '').split(';')):
        kind, _, sprite = item.partition(':')
        record['containers'].append({'type': kind.strip(), 'sprite': sprite.strip()})
    return record


class SurveyFile:
    """Adapter of the survey file the game writes."""

    def __init__(self, path: Path):
        self.path = Path(path)

    @property
    def found(self) -> bool:
        return self.path.is_file()

    def _text(self) -> str:
        try:
            with self.path.open('rb') as handle:
                handle.seek(0, 2)
                size = handle.tell()
                handle.seek(max(0, size - MAX_BYTES))
                data = handle.read(MAX_BYTES)
        except OSError:
            return ''
        if size > MAX_BYTES:
            data = data[data.find(b'\n') + 1:]       # the first line read may be cut
        return data.decode('utf-8', errors='replace')

    def records(self) -> list[dict]:
        """Records, newest first (the game appends at the end), at most MAX_RECORDS."""
        records = [record for record in map(parse_line, self._text().splitlines()) if record is not None]
        return list(reversed(records[-MAX_RECORDS:]))
