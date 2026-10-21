"""Radio voice sheets (E05-T01, ranges E05-T07): read and strictly validate one `.txt` sheet per voice.

    python bridge/persona_store.py FILE.txt [...]     validate sheets, one line per file, exit code 1 on error

Format: docs/specifications-techniques/persona-format.md. The server reads the same files with
Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Persona.lua: same rules, same messages
("line N: reason"), checked by tests/test_personas.py. Lines are split like Java's BufferedReader.readLine (the game's
getFileReader): "\\r\\n", "\\r" or "\\n". Invalid UTF-8 is decoded as U+FFFD, as Java's InputStreamReader does, then
refused. Standard library only.
"""
from __future__ import annotations

import io
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

FORMAT = '1'
SEPARATOR = '[prompt]'
BOM = '\ufeff'
REPLACEMENT = '\ufffd'
# Actions of the closed catalogue (note de travail, section 02). Only `say` is executed before E07.
ACTIONS = ('say', 'mark_map', 'reveal_area', 'signal', 'place_cache', 'place_scene', 'start_mission',
           'persona_state', 'remember', 'propose_trade', 'report_mission', 'share_frequency')
RADIOS = ('any', 'high_tier')
LOCATIONS = ('none', 'fixed', 'rescue')
CACHE_TABLES = ('medical', 'ammo', 'tools', 'food', 'radio')
MISSION_TEMPLATES = ('scout', 'deliver', 'retrieve', 'clear', 'signal')
REWARDS = ('cache', 'frequency', 'stashmap', 'lesson')
TEACHES = ('Doctor', 'Aiming', 'Reloading', 'Woodwork', 'Mechanics', 'Electricity', 'MetalWelding',
           'Cooking', 'Farming', 'Fishing', 'Trapping', 'PlantScavenging')
STATES = ('active', 'silent', 'gone', 'dead')
REPEATABLE = ('knows', 'ignores', 'secret', 'place')
KEYS = ('format', 'id', 'name', 'language', 'frequencies', 'frequency_range', 'radio', 'listen', 'location',
        'coords', 'knows', 'ignores', 'secret', 'place', 'actions', 'budget', 'call_one_in', 'call_text', 'state',
        'cache_table', 'shares', 'teaches', 'missions', 'rewards')
REQUIRED = ('format', 'id', 'name')   # then frequencies or frequency_range (one of them, not both: E05-T07)
MIN_KHZ, MAX_KHZ, STEP_KHZ = 1000, 999800, 200
MAX_COUNT = 999999
MAX_CALL_ONE_IN = 1000
# Known places of the voice (E07-T04, action mark_map): at most MAX_PLACES lines, label of at most
# MAX_PLACE_LABEL_BYTES bytes in UTF-8 (the Lua reader counts the same bytes from the UTF-16 units of Kahlua).
MAX_PLACES = 12
MAX_PLACE_LABEL_BYTES = 48

ID_RE = re.compile(r'[a-z][a-z0-9_]{0,31}')
LANGUAGE_RE = re.compile(r'[a-z][a-z]')
FREQUENCY_RE = re.compile(r'([0-9]{1,3})\.([0-9])')
RANGE_RE = re.compile(r'([0-9][0-9]):([0-9][0-9])-([0-9][0-9]):([0-9][0-9])')
COORDS_RE = re.compile(r'([0-9]{1,6}),([0-9]{1,6}),(-?[0-9]{1,2})')
COUNT_RE = re.compile(r'[0-9]{1,6}')
TEXT_KEY_RE = re.compile(r'[A-Za-z0-9_]+')
KEY_RE = re.compile(r'[a-z_]+(\.[a-z_]+)?')
PLACE_RE = re.compile(r'([^ \t]+)[ \t]+([^ \t]+)[ \t]+(.+)')
PLACE_ID_RE = re.compile(r'[a-z0-9_]{1,32}')


class PersonaError(ValueError):
    """Refused sheet: `line` is 1-based, `reason` is the same English text as the Lua reader."""

    def __init__(self, line: int, reason: str):
        super().__init__(f'line {line}: {reason}')
        self.line, self.reason = line, reason


@dataclass
class Place:
    """Known place of a voice (place= line, E07-T04): id offered to the LLM with its label, coordinates kept by
    the server and sent only to the caller of an accepted mark_map."""
    id: str
    x: int
    y: int
    z: int
    label: str


@dataclass
class Persona:
    format: str
    id: str
    name: str
    frequencies: list[int]                     # kHz, in file order; [] when the sheet gives ranges to draw from
    prompt: str
    frequency_ranges: list[tuple[int, int]] = field(default_factory=list)   # (low, high) kHz, frequency_range
    language: str = 'en'
    radio: str = 'any'
    listen: list[tuple[int, int]] = field(default_factory=list)   # (from, to) minutes of the game day; [] = always
    location: str = 'none'
    coords: tuple[int, int, int] | None = None
    knows: list[str] = field(default_factory=list)
    ignores: list[str] = field(default_factory=list)
    secrets: list[str] = field(default_factory=list)
    places: list[Place] = field(default_factory=list)       # place=, in file order (E07-T04)
    actions: list[str] = field(default_factory=lambda: ['say'])
    budget: int = 0                            # requests per real hour for this voice, 0 = global cap only
    budgets: dict[str, int] = field(default_factory=dict)          # action -> uses per game day, 0 = no cap
    call_one_in: int = 0                       # spontaneous call: one chance in N per game hour, 0 = never
    call_text: str = ''                        # translation key of the fixed call, %1 = frequency label
    cache_table: str = ''
    shares: list[str] = field(default_factory=list)
    teaches: str = ''
    missions: list[str] = field(default_factory=lambda: ['scout'])
    rewards: list[str] = field(default_factory=list)
    state: str = 'active'


def split_lines(text: str) -> list[str]:
    """Lines as BufferedReader.readLine returns them (no trailing empty line after a final line break)."""
    lines = re.split(r'\r\n|\r|\n', text)
    if lines and lines[-1] == '':
        lines.pop()
    return lines


def trim(value: str) -> str:
    return value.strip(' \t')


def _count(value: str, key: str, line: int, maximum: int = MAX_COUNT) -> int:
    if not COUNT_RE.fullmatch(value) or int(value) > maximum:
        raise PersonaError(line, f"bad {key} '{value}' (whole number from 0 to {maximum})")
    return int(value)


def _list(value: str) -> list[str]:
    return [trim(part) for part in value.split(',')]


def _frequency(part: str, line: int) -> int:
    match = FREQUENCY_RE.fullmatch(part)
    if not match:
        raise PersonaError(line, f"bad frequency '{part}' (MHz with one decimal, e.g. 145.0)")
    khz = int(match.group(1)) * 1000 + int(match.group(2)) * 100
    if khz < MIN_KHZ or khz > MAX_KHZ:
        raise PersonaError(line, f'frequency {part} out of range (1.0 to 999.8 MHz)')
    if khz % STEP_KHZ != 0:
        raise PersonaError(line, f'frequency {part} is not on the 0.2 MHz step of the radios')
    return khz


def _frequencies(value: str, line: int) -> list[int]:
    result = []
    for part in _list(value):
        khz = _frequency(part, line)
        if khz in result:
            raise PersonaError(line, f'duplicate frequency {part}')
        result.append(khz)
    return result


def _frequency_ranges(value: str, line: int) -> list[tuple[int, int]]:
    """Ranges to draw from (E05-T07): "low-high" in MHz, low < high, no overlap inside the sheet."""
    result: list[tuple[int, int]] = []
    for part in _list(value):
        bad_range = f"bad frequency range '{part}' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)"
        halves = part.split('-')
        if len(halves) != 2:
            raise PersonaError(line, bad_range)
        low, high = _frequency(trim(halves[0]), line), _frequency(trim(halves[1]), line)
        if low >= high:
            raise PersonaError(line, bad_range)
        for other_low, other_high in result:
            if low <= other_high and high >= other_low:
                raise PersonaError(line, f"frequency range '{part}' overlaps another range of the sheet")
        result.append((low, high))
    return result


def _listen(value: str, line: int) -> list[tuple[int, int]]:
    if value == 'always':
        return []
    result = []
    for part in _list(value):
        match = RANGE_RE.fullmatch(part)
        hours = [int(g) for g in match.groups()] if match else []
        if not match or hours[0] > 23 or hours[2] > 23 or hours[1] > 59 or hours[3] > 59:
            raise PersonaError(line, f"bad listening hours '{part}' (always, or HH:MM-HH:MM ranges separated by "
                                     'commas)')
        start, stop = hours[0] * 60 + hours[1], hours[2] * 60 + hours[3]
        if start == stop:
            raise PersonaError(line, f"empty listening range '{part}'")
        result.append((start, stop))
    return result


def _coords(value: str, line: int) -> tuple[int, int, int]:
    match = COORDS_RE.fullmatch(value)
    if not match or not -32 <= int(match.group(3)) <= 31:
        raise PersonaError(line, f"bad coords '{value}' (x,y,z whole numbers, z from -32 to 31)")
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def _place(value: str, line: int, places: list[Place], place_lines: dict[str, int]) -> Place:
    """One place= line (E07-T04): "<id> <x>,<y>,<z> <label>"."""
    match = PLACE_RE.fullmatch(value)
    if not match:
        raise PersonaError(line, f"bad place '{value}' (id x,y,z label, e.g. mill 10600,9300,0 Old mill)")
    ident, coords, label = match.group(1), match.group(2), match.group(3)
    if not PLACE_ID_RE.fullmatch(ident):
        raise PersonaError(line, f"bad place id '{ident}' (a to z, 0 to 9 and _, 32 characters at most)")
    numbers = COORDS_RE.fullmatch(coords)
    if not numbers or not -32 <= int(numbers.group(3)) <= 31:
        raise PersonaError(line, f"bad place coords '{coords}' (x,y,z whole numbers, z from -32 to 31)")
    if len(label.encode('utf-8')) > MAX_PLACE_LABEL_BYTES:
        raise PersonaError(line, f"place label of '{ident}' too long ({MAX_PLACE_LABEL_BYTES} bytes of UTF-8 at "
                                 'most)')
    if ident in place_lines:
        raise PersonaError(line, f"duplicate place '{ident}' (first set on line {place_lines[ident]})")
    if len(places) >= MAX_PLACES:
        raise PersonaError(line, f'too many places ({MAX_PLACES} at most)')
    place_lines[ident] = line
    return Place(ident, int(numbers.group(1)), int(numbers.group(2)), int(numbers.group(3)), label)


def _actions(value: str, line: int) -> list[str]:
    result = []
    for part in _list(value):
        if part not in ACTIONS:
            raise PersonaError(line, f"unknown action '{part}'")
        if part in result:
            raise PersonaError(line, f"duplicate action '{part}'")
        result.append(part)
    return result


def _closed_list(value: str, key: str, allowed: tuple[str, ...] | None, line: int) -> list[str]:
    result = []
    for part in _list(value):
        if (allowed is not None and part not in allowed) or (allowed is None and not ID_RE.fullmatch(part)):
            raise PersonaError(line, f"bad {key} entry '{part}'")
        if part in result:
            raise PersonaError(line, f"duplicate {key} entry '{part}'")
        result.append(part)
    return result


def _choice(value: str, key: str, allowed: tuple[str, ...], line: int) -> str:
    if value not in allowed:
        raise PersonaError(line, f"bad {key} '{value}' (expected {', '.join(allowed)})")
    return value


def parse_lines(lines: list[str], expected_id: str | None = None) -> Persona:
    """Validate a sheet given as lines; raise PersonaError on the first error. expected_id = file name stem."""
    # One typed variable per key (None = line absent); `seen` gives the line of each non-repeatable key.
    fmt: str | None = None
    ident: str | None = None
    name: str | None = None
    language: str | None = None
    frequencies: list[int] | None = None
    ranges: list[tuple[int, int]] | None = None
    radio: str | None = None
    listen: list[tuple[int, int]] | None = None
    location: str | None = None
    coords: tuple[int, int, int] | None = None
    actions: list[str] | None = None
    reward_fields: dict = {}
    budget: int | None = None
    call_one_in: int | None = None
    call_text: str | None = None
    state: str | None = None
    repeated: dict[str, list[str]] = {key: [] for key in REPEATABLE if key != 'place'}
    places: list[Place] = []
    place_lines: dict[str, int] = {}
    budgets: dict[str, int] = {}
    seen: dict[str, int] = {}
    budget_lines: list[tuple[str, int]] = []
    separator = 0
    for number, raw in enumerate(lines, 1):
        if number == 1 and raw.startswith(BOM):
            raise PersonaError(1, 'file starts with a byte order mark (save it as UTF-8 without BOM)')
        if REPLACEMENT in raw:
            raise PersonaError(number, 'invalid UTF-8 (save the file as UTF-8)')
        if separator:
            continue
        text = trim(raw)
        if text == SEPARATOR:
            separator = number
            continue
        if text == '' or text.startswith('#'):
            continue
        if '=' not in text:
            raise PersonaError(number, f"expected key=value or {SEPARATOR}")
        key, value = text.split('=', 1)
        key, value = trim(key), trim(value)
        if not KEY_RE.fullmatch(key):
            raise PersonaError(number, f"bad key '{key}'")
        action = None
        if key.startswith('budget.'):
            action = key[len('budget.'):]
            if action not in ACTIONS:
                raise PersonaError(number, f"unknown action '{action}' in key '{key}'")
        elif key not in KEYS:
            raise PersonaError(number, f"unknown key '{key}'")
        if key not in REPEATABLE:
            if key in seen:
                raise PersonaError(number, f"duplicate key '{key}' (first set on line {seen[key]})")
            seen[key] = number
        if value == '':
            raise PersonaError(number, f"empty value for key '{key}'")
        if action is not None:
            budgets[action] = _count(value, key, number)
            budget_lines.append((action, number))
        elif key == 'format':
            if value != FORMAT:
                raise PersonaError(number, f"unsupported format '{value}' (expected {FORMAT})")
            fmt = value
        elif key == 'id':
            if not ID_RE.fullmatch(value):
                raise PersonaError(number, f"bad id '{value}' (a to z, 0 to 9 and _, starting with a letter, "
                                           '32 characters at most)')
            ident = value
        elif key == 'language':
            if not LANGUAGE_RE.fullmatch(value):
                raise PersonaError(number, f"bad language '{value}' (two lowercase letters, e.g. en)")
            language = value
        elif key == 'frequencies':
            frequencies = _frequencies(value, number)
        elif key == 'frequency_range':
            ranges = _frequency_ranges(value, number)
        elif key == 'radio':
            radio = _choice(value, key, RADIOS, number)
        elif key == 'listen':
            listen = _listen(value, number)
        elif key == 'location':
            location = _choice(value, key, LOCATIONS, number)
        elif key == 'coords':
            coords = _coords(value, number)
        elif key in ('cache_table', 'teaches'):
            reward_fields[key] = _choice(value, key, CACHE_TABLES if key == 'cache_table' else TEACHES, number)
        elif key in ('shares', 'missions', 'rewards'):
            allowed_entries = {'shares': None, 'missions': MISSION_TEMPLATES, 'rewards': REWARDS}
            reward_fields[key] = _closed_list(value, key, allowed_entries[key], number)
        elif key == 'actions':
            actions = _actions(value, number)
        elif key == 'budget':
            budget = _count(value, key, number)
        elif key == 'call_one_in':
            call_one_in = _count(value, key, number, MAX_CALL_ONE_IN)
        elif key == 'call_text':
            if not TEXT_KEY_RE.fullmatch(value):
                raise PersonaError(number, f"bad call_text '{value}' (translation key: A to Z, a to z, 0 to 9 "
                                           'and _)')
            call_text = value
        elif key == 'state':
            state = _choice(value, key, STATES, number)
        elif key == 'place':
            places.append(_place(value, number, places, place_lines))
        elif key in REPEATABLE:
            repeated[key].append(value)
        else:
            name = value

    end = max(len(lines), 1)
    if not separator:
        raise PersonaError(end, f'missing {SEPARATOR} line before the prompt text')
    body = lines[separator:]
    while body and trim(body[0]) == '':
        body.pop(0)
    while body and trim(body[-1]) == '':
        body.pop()
    if not body:
        raise PersonaError(separator, f'empty prompt text after {SEPARATOR}')
    # REQUIRED, in this order (same first missing key as the Lua reader).
    if fmt is None:
        raise PersonaError(separator, "missing key 'format'")
    if ident is None:
        raise PersonaError(separator, "missing key 'id'")
    if name is None:
        raise PersonaError(separator, "missing key 'name'")
    if frequencies is None and ranges is None:
        raise PersonaError(separator, "missing key 'frequencies' or 'frequency_range'")
    if frequencies is not None and ranges is not None:
        raise PersonaError(max(seen['frequencies'], seen['frequency_range']),
                           'frequencies and frequency_range cannot be used together (fixed frequencies or ranges to '
                           'draw from)')
    if expected_id is not None and ident != expected_id:
        raise PersonaError(seen['id'], f"id '{ident}' does not match the file name '{expected_id}.txt'")
    location = location or 'none'
    if location == 'fixed' and coords is None:
        raise PersonaError(seen['location'], 'location fixed needs a coords line')
    if location != 'fixed' and coords is not None:
        raise PersonaError(seen['coords'], 'coords is only allowed with location=fixed')
    if call_one_in and call_text is None:
        raise PersonaError(seen['call_one_in'], 'call_one_in needs a call_text line')
    actions = actions or ['say']
    for action, number in budget_lines:
        if action not in actions:
            raise PersonaError(number, f"budget.{action} set but action '{action}' is not in actions")

    return Persona(
        format=fmt, id=ident, name=name, frequencies=frequencies or [], frequency_ranges=ranges or [],
        prompt='\n'.join(body), language=language or 'en', radio=radio or 'any', listen=listen or [],
        location=location, coords=coords, knows=repeated['knows'], ignores=repeated['ignores'],
        secrets=repeated['secret'], places=places, actions=actions, budget=budget or 0, budgets=budgets,
        call_one_in=call_one_in or 0, call_text=call_text or '', state=state or 'active', **reward_fields)


def parse_bytes(raw: bytes, expected_id: str | None = None) -> Persona:
    """Decode as the game does (UTF-8, invalid bytes -> U+FFFD, BOM kept), then validate."""
    return parse_lines(split_lines(raw.decode('utf-8', errors='replace')), expected_id)


def load_file(path: Path | str) -> Persona:
    """Read and validate one sheet; its `id` must equal the file name without `.txt`."""
    path = Path(path)
    return parse_bytes(path.read_bytes(), path.stem if path.suffix == '.txt' else None)


def main(argv: list[str]) -> int:
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if not argv:
        print((__doc__ or '').strip().splitlines()[2].strip())
        return 2
    failed = 0
    for name in argv:
        try:
            persona = load_file(name)
        except (OSError, PersonaError) as exc:
            failed += 1
            print(f'{name}: {exc}')
        else:
            mhz = ', '.join([f'{khz / 1000:.1f}' for khz in persona.frequencies]
                            + [f'{low / 1000:.1f}-{high / 1000:.1f}' for low, high in persona.frequency_ranges])
            print(f'{name}: OK ({persona.id}, {mhz} MHz, {persona.state})')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
