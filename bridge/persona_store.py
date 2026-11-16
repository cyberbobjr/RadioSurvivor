"""Radio voice sheets (E05-T01, sections E20-T03, radio levels E24-T01): read and validate one `.txt` sheet per voice.

    python bridge/persona_store.py FILE.txt [...]     validate sheets, one line per file, exit code 1 on error

Format: docs/specifications-techniques/persona-format.md. The server reads the same files with
Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Persona.lua, the only full validator (ADR
D03, E20-T03). This reader takes the head, the [place] sections and the prompt with the same rules and messages
("line N: reason"), checked by tests/test_personas.py; it skips the [mission], [rewards], [category], [trade] and
[note] sections without reading them. Lines are split like Java's BufferedReader.readLine (the game's getFileReader): "\\r\\n", "\\r"
or "\\n". Invalid UTF-8 is decoded as U+FFFD, as Java's InputStreamReader does, then refused. Standard library only.
"""
from __future__ import annotations

import io
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

FORMAT = '1'
SEPARATOR = '[prompt]'
BOM = '﻿'
REPLACEMENT = '�'
# Actions of the closed catalogue a sheet may list (note de travail, section 02). Only `say` is executed before E07.
# E22-T13: `remember` is no sheet action any more: every voice has it (radio_bridge.UNIVERSAL_ACTIONS).
ACTIONS = ('say', 'mark_map', 'reveal_area', 'signal', 'place_cache', 'place_scene', 'start_mission',
           'persona_state', 'propose_trade', 'report_mission', 'share_frequency')
# Radio needed to hear the voice (E24-T01): ids of RS_RadioLevels.lua, weakest first (tests/test_radio_levels.py checks
# they are the same). The server draws a free frequency in the level's zone; the bridge only checks the name.
RADIOS = ('any_talkie', 'good_talkie', 'pro_talkie', 'tactical', 'military')
LOCATIONS = ('none', 'fixed', 'rescue')
STATES = ('active', 'silent', 'gone', 'dead')
# Uses of a place (ADR D04): mark (mark_map, reveal_area), target (mission goal), drop (dead drop), landing (trade).
USES = ('mark', 'target', 'drop', 'landing')
REQUIRED = ('format', 'id', 'name')   # then radio or frequency (exactly one of them: E24-T01)
MIN_KHZ, MAX_KHZ, STEP_KHZ = 200, 1000000, 200   # every radio of the game (RS_RadioLevels.lua, level military)
MAX_COUNT = 999999
MAX_CALL_ONE_IN = 1000
MAX_CALL_BYTES = 200   # call= written in the sheet (E22-T07), UTF-8 bytes as RS_Persona.lua
# Known places of the voice: at most MAX_PLACES [place] sections, label of at most MAX_PLACE_LABEL_BYTES bytes in
# UTF-8 (the Lua reader counts the same bytes from the UTF-16 units of Kahlua).
MAX_PLACES = 12
MAX_PLACE_LABEL_BYTES = 48

ID_RE = re.compile(r'[a-z][a-z0-9_]{0,31}')
SECTION_ID_RE = re.compile(r'[a-z0-9_]{1,32}')
HEADER_RE = re.compile(r'\[[ \t]*([^ \t\]]*)[ \t]*(.*?)[ \t]*\]')
LANGUAGE_RE = re.compile(r'[a-z][a-z]')
FREQUENCY_RE = re.compile(r'([0-9]{1,4})\.([0-9])')
RANGE_RE = re.compile(r'([0-9][0-9]):([0-9][0-9])-([0-9][0-9]):([0-9][0-9])')
COORDS_RE = re.compile(r'([0-9]{1,6}),([0-9]{1,6}),(-?[0-9]{1,2})')
COUNT_RE = re.compile(r'[0-9]{1,6}')
TEXT_KEY_RE = re.compile(r'[A-Za-z0-9_]+')
KEY_RE = re.compile(r'[a-z_]+')
DOTTED_KEY_RE = re.compile(r'[a-z_]+(\.[a-z_]+)?')


class PersonaError(ValueError):
    """Refused sheet: `line` is 1-based, `reason` is the same English text as the Lua reader."""

    def __init__(self, line: int, reason: str):
        super().__init__(f'line {line}: {reason}')
        self.line, self.reason = line, reason


@dataclass
class Place:
    """Known place of a voice ([place <id>] section): id offered to the LLM with its label when its uses allow it
    (mark: mark_map, reveal_area); coordinates kept by the server and sent only to the caller of an accepted
    action."""
    id: str
    x: int = 0
    y: int = 0
    z: int = 0
    label: str = ''
    uses: tuple[str, ...] = ()


@dataclass
class Persona:
    format: str
    id: str
    name: str
    prompt: str
    frequency: int | None = None               # kHz of frequency=; None: the server draws one for `radio`
    radio: str | None = None                   # radio= as written; None with frequency= (the server derives it)
    language: str = 'en'
    listen: list[tuple[int, int]] = field(default_factory=list)   # (from, to) minutes of the game day; [] = always
    location: str = 'none'
    coords: tuple[int, int, int] | None = None
    places: list[Place] = field(default_factory=list)       # [place] sections, in file order
    actions: list[str] = field(default_factory=lambda: ['say'])
    budget: int = 0                            # requests per real hour for this voice, 0 = global cap only
    budgets: dict[str, int] = field(default_factory=dict)          # action -> uses per game day, 0 = no cap
    call_one_in: int = 0                       # spontaneous call: one chance in N per game hour, 0 = never
    call_text: str = ''                        # translation key of the fixed call, %1 = frequency label
    call: str = ''                             # fixed call written in the sheet, %1 = frequency label (E22-T07)
    shares: list[str] = field(default_factory=list)
    state: str = 'active'
    trade_accepts: list[str] = field(default_factory=list)   # [trade] accept= values, in file order (E23-T06)

    def places_for(self, use: str) -> list[Place]:
        """Places of the sheet with this use, in file order."""
        return [p for p in self.places if use in p.uses]


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
    """Fixed frequency (frequency=, E24-T01): MHz with one decimal, inside every radio's bounds, on their step."""
    match = FREQUENCY_RE.fullmatch(part)
    if not match:
        raise PersonaError(line, f"bad frequency '{part}' (MHz with one decimal, e.g. 145.0)")
    khz = int(match.group(1)) * 1000 + int(match.group(2)) * 100
    if khz < MIN_KHZ or khz > MAX_KHZ:
        raise PersonaError(line, f'frequency {part} out of range ({MIN_KHZ / 1000:.1f} to {MAX_KHZ / 1000:.1f} MHz)')
    if khz % STEP_KHZ != 0:
        raise PersonaError(line, f'frequency {part} is not on the {STEP_KHZ / 1000:.1f} MHz step of the radios')
    return khz


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


def _parse_coords(value: str) -> tuple[int, int, int] | None:
    match = COORDS_RE.fullmatch(value)
    if not match or not -32 <= int(match.group(3)) <= 31:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def _coords(value: str, line: int) -> tuple[int, int, int]:
    coords = _parse_coords(value)
    if coords is None:
        raise PersonaError(line, f"bad coords '{value}' (x,y,z whole numbers, z from -32 to 31)")
    return coords


def _actions(value: str, line: int) -> list[str]:
    result = []
    for part in _list(value):
        if part not in ACTIONS:
            raise PersonaError(line, f"unknown action '{part}'")
        if part in result:
            raise PersonaError(line, f"duplicate action '{part}'")
        result.append(part)
    return result


def _closed_list(value: str, key: str, allowed: tuple[str, ...] | None, line: int, hint: str = '') -> list[str]:
    result = []
    for part in _list(value):
        if (allowed is not None and part not in allowed) or (allowed is None and not ID_RE.fullmatch(part)):
            raise PersonaError(line, f"bad {key} entry '{part}'{hint}")
        if part in result:
            raise PersonaError(line, f"duplicate {key} entry '{part}'")
        result.append(part)
    return result


def _choice(value: str, key: str, allowed: tuple[str, ...], line: int) -> str:
    if value not in allowed:
        raise PersonaError(line, f"bad {key} '{value}' (expected {', '.join(allowed)})")
    return value


def _format(value: str, line: int) -> str:
    if value != FORMAT:
        raise PersonaError(line, f"unsupported format '{value}' (expected {FORMAT})")
    return value


def _id(value: str, line: int) -> str:
    if not ID_RE.fullmatch(value):
        raise PersonaError(line, f"bad id '{value}' (a to z, 0 to 9 and _, starting with a letter, 32 characters "
                                 'at most)')
    return value


def _language(value: str, line: int) -> str:
    if not LANGUAGE_RE.fullmatch(value):
        raise PersonaError(line, f"bad language '{value}' (two lowercase letters, e.g. en)")
    return value


def _call_text(value: str, line: int) -> str:
    if not TEXT_KEY_RE.fullmatch(value):
        raise PersonaError(line, f"bad call_text '{value}' (translation key: A to Z, a to z, 0 to 9 and _)")
    return value


def _text(value: str, line: int) -> str:
    return value


def _call(value: str, line: int) -> str:
    """Call written in the sheet (E22-T07): bounded, no <, > or ^, % only in %1 (same rules as RS_Persona.lua)."""
    if len(value.encode('utf-8')) > MAX_CALL_BYTES:
        raise PersonaError(line, f'call too long ({MAX_CALL_BYTES} bytes of UTF-8 at most)')
    if re.search(r'[<>^]', value) or '%' in value.replace('%1', ''):
        raise PersonaError(line, f"bad call '{value}' (no <, > or ^; % only in %1, the frequency)")
    return value


# Head: one reader per key -> (field of Persona, reader(value, line)).
HEAD: dict[str, tuple[str, Callable[[str, int], object]]] = {
    'format': ('format', _format),
    'id': ('id', _id),
    'name': ('name', _text),
    'language': ('language', _language),
    'frequency': ('frequency', _frequency),
    'radio': ('radio', lambda value, line: _choice(value, 'radio', RADIOS, line)),
    'listen': ('listen', _listen),
    'location': ('location', lambda value, line: _choice(value, 'location', LOCATIONS, line)),
    'coords': ('coords', _coords),
    'shares': ('shares', lambda value, line: _closed_list(value, 'shares', None, line)),
    'actions': ('actions', _actions),
    'budget': ('budget', lambda value, line: _count(value, 'budget', line)),
    'call_one_in': ('call_one_in', lambda value, line: _count(value, 'call_one_in', line, MAX_CALL_ONE_IN)),
    'call_text': ('call_text', _call_text),
    'call': ('call', _call),
    'state': ('state', lambda value, line: _choice(value, 'state', STATES, line)),
}


@dataclass
class Section:
    """An open section: name, id ('' when the section takes none), header line, key -> line of its value."""
    name: str
    id: str
    line: int
    lines: dict[str, int] = field(default_factory=dict)
    place: Place | None = None
    accepts: list[str] = field(default_factory=list)

    @property
    def title(self) -> str:
        return f'[{self.name} {self.id}]' if self.id else f'[{self.name}]'


def _place_at(sec: Section, value: str, line: int) -> None:
    coords = _parse_coords(value)
    if coords is None:
        raise PersonaError(line, f"bad place coords '{value}' (x,y,z whole numbers, z from -32 to 31)")
    sec.place.x, sec.place.y, sec.place.z = coords


def _place_label(sec: Section, value: str, line: int) -> None:
    if len(value.encode('utf-8')) > MAX_PLACE_LABEL_BYTES:
        raise PersonaError(line, f"place label of '{sec.id}' too long ({MAX_PLACE_LABEL_BYTES} bytes of UTF-8 at "
                                 'most)')
    sec.place.label = value


def _place_use(sec: Section, value: str, line: int) -> None:
    sec.place.uses = tuple(_closed_list(value, 'use', USES, line, f" (expected {', '.join(USES)})"))


class PlaceSection:
    """[place <id>]: at=x,y,z, label=text, use=list among USES; the only section this reader reads."""
    example = 'mill'
    KEYS: dict[str, Callable[[Section, str, int], None]] = {'at': _place_at, 'label': _place_label, 'use': _place_use}

    def open(self, sec: Section, places: list[Place]) -> None:
        if len(places) >= MAX_PLACES:
            raise PersonaError(sec.line, f'too many places ({MAX_PLACES} at most)')
        sec.place = Place(sec.id)

    def line(self, sec: Section, text: str, number: int) -> None:
        key, value = _key_value(text, number, dotted=False)
        if key in sec.lines:
            raise PersonaError(number, f"duplicate key '{key}' in {sec.title} (first set on line {sec.lines[key]})")
        if value == '':
            raise PersonaError(number, f"empty value for key '{key}'")
        sec.lines[key] = number
        reader = self.KEYS.get(key)
        if reader is None:
            raise PersonaError(number, f"unknown key '{key}' in {sec.title}")
        reader(sec, value, number)

    def close(self, sec: Section, places: list[Place]) -> None:
        for key in self.KEYS:
            if key not in sec.lines:
                raise PersonaError(sec.line, f"missing key '{key}' in {sec.title}")
        places.append(sec.place)


class SkippedSection:
    """Section validated by the server only (RS_Persona, ADR D03): its lines are not read here."""

    def __init__(self, example: str | None):
        self.example = example

    def open(self, sec: Section, places: list[Place]) -> None:
        pass

    def line(self, sec: Section, text: str, number: int) -> None:
        pass

    def close(self, sec: Section, places: list[Place]) -> None:
        pass


class TradeSection(SkippedSection):
    """[trade]: validated by the server only (RS_Persona); the bridge keeps the raw values of `accept=` (E23-T06: what
    the voice accepts as payment, items or categories), for the workshop and the tools. The trade book the LLM reads
    comes with each request (trade=), resolved by the server."""

    def line(self, sec: Section, text: str, number: int) -> None:
        if '=' in text:
            key, value = text.split('=', 1)
            if trim(key) == 'accept' and trim(value):
                sec.accepts.append(trim(value))


# Sections of a sheet, in the order of the Lua reader's messages; example None = section without id.
SECTIONS: dict[str, PlaceSection | SkippedSection] = {
    'place': PlaceSection(), 'mission': SkippedSection('meds'), 'rewards': SkippedSection(None),
    'category': SkippedSection('snacks'), 'trade': TradeSection(None), 'note': SkippedSection(None),
}
SECTIONS_EXPECTED = ', '.join(SECTIONS) + ' or prompt'


def _key_value(text: str, line: int, dotted: bool) -> tuple[str, str]:
    if '=' not in text:
        raise PersonaError(line, f'expected key=value or {SEPARATOR}')
    key, value = text.split('=', 1)
    key, value = trim(key), trim(value)
    if not (DOTTED_KEY_RE if dotted else KEY_RE).fullmatch(key):
        raise PersonaError(line, f"bad key '{key}'")
    return key, value


def _open_section(name: str, ident: str, line: int, first_lines: dict[tuple[str, str], int]) -> Section:
    handler = SECTIONS.get(name)
    if handler is None:
        raise PersonaError(line, f"unknown section '{name}' (expected {SECTIONS_EXPECTED})")
    if handler.example and not ident:
        raise PersonaError(line, f'section [{name}] needs an id, e.g. [{name} {handler.example}]')
    if not handler.example and ident:
        raise PersonaError(line, f'section [{name}] takes no id')
    if ident and not SECTION_ID_RE.fullmatch(ident):
        raise PersonaError(line, f"bad {name} id '{ident}' (a to z, 0 to 9 and _, 32 characters at most)")
    if (name, ident) in first_lines:
        first = first_lines[(name, ident)]
        if not ident:
            raise PersonaError(line, f'duplicate section [{name}] (first set on line {first})')
        raise PersonaError(line, f"duplicate {name} '{ident}' (first set on line {first})")
    first_lines[(name, ident)] = line
    return Section(name, ident, line)


class _Head:
    """Values of the head lines: one field of Persona per key, `seen` gives the line of each key."""

    def __init__(self):
        self.fields: dict[str, object] = {}
        self.seen: dict[str, int] = {}
        self.budgets: dict[str, int] = {}
        self.budget_lines: list[tuple[str, int]] = []

    def line(self, text: str, number: int) -> None:
        key, value = _key_value(text, number, dotted=True)
        action = None
        if key.startswith('budget.'):
            action = key[len('budget.'):]
            if action not in ACTIONS:
                raise PersonaError(number, f"unknown action '{action}' in key '{key}'")
        elif key not in HEAD:
            raise PersonaError(number, f"unknown key '{key}'")
        if key in self.seen:
            raise PersonaError(number, f"duplicate key '{key}' (first set on line {self.seen[key]})")
        self.seen[key] = number
        if value == '':
            raise PersonaError(number, f"empty value for key '{key}'")
        if action is not None:
            self.budgets[action] = _count(value, key, number)
            self.budget_lines.append((action, number))
            return
        target, reader = HEAD[key]
        self.fields[target] = reader(value, number)


def parse_lines(lines: list[str], expected_id: str | None = None) -> Persona:
    """Validate a sheet given as lines; raise PersonaError on the first error. expected_id = file name stem."""
    head = _Head()
    places: list[Place] = []
    accepts: list[str] = []
    first_lines: dict[tuple[str, str], int] = {}
    current: Section | None = None
    separator = 0
    for number, raw in enumerate(lines, 1):
        if number == 1 and raw.startswith(BOM):
            raise PersonaError(1, 'file starts with a byte order mark (save it as UTF-8 without BOM)')
        if REPLACEMENT in raw:
            raise PersonaError(number, 'invalid UTF-8 (save the file as UTF-8)')
        if separator:
            continue
        text = trim(raw)
        if text == '' or text.startswith('#'):
            continue
        header = HEADER_RE.fullmatch(text)
        if header:
            if current is not None:
                SECTIONS[current.name].close(current, places)
                accepts += current.accepts
            current = None
            if header.group(1) == 'prompt' and not header.group(2):
                separator = number
            else:
                current = _open_section(header.group(1), header.group(2), number, first_lines)
                SECTIONS[current.name].open(current, places)
        elif current is not None:
            SECTIONS[current.name].line(current, text, number)
        else:
            head.line(text, number)

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
    fields, seen = head.fields, head.seen
    for key in REQUIRED:   # in this order (same first missing key as the Lua reader)
        if key not in fields:
            raise PersonaError(separator, f"missing key '{key}'")
    if 'radio' not in fields and 'frequency' not in fields:
        raise PersonaError(separator, "missing key 'radio' or 'frequency'")
    if 'radio' in fields and 'frequency' in fields:
        raise PersonaError(max(seen['radio'], seen['frequency']),
                           'radio and frequency cannot be used together (a radio level to draw a free frequency, or '
                           'one fixed frequency)')
    if expected_id is not None and fields['id'] != expected_id:
        raise PersonaError(seen['id'], f"id '{fields['id']}' does not match the file name '{expected_id}.txt'")
    location = fields.setdefault('location', 'none')
    if location == 'fixed' and 'coords' not in fields:
        raise PersonaError(seen['location'], 'location fixed needs a coords line')
    if location != 'fixed' and 'coords' in fields:
        raise PersonaError(seen['coords'], 'coords is only allowed with location=fixed')
    if 'call' in fields and 'call_text' in fields:
        raise PersonaError(max(seen['call'], seen['call_text']),
                           'call and call_text cannot be used together (text written in the sheet or translation key)')
    if fields.get('call_one_in') and 'call' not in fields and 'call_text' not in fields:
        raise PersonaError(seen['call_one_in'], 'call_one_in needs a call or call_text line')
    actions = fields.setdefault('actions', ['say'])
    for action, number in head.budget_lines:
        if action not in actions:
            raise PersonaError(number, f"budget.{action} set but action '{action}' is not in actions")
    return Persona(prompt='\n'.join(body), places=places, budgets=head.budgets, trade_accepts=accepts, **fields)


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
            where = f'{persona.frequency / 1000:.1f} MHz' if persona.frequency is not None else persona.radio
            print(f'{name}: OK ({persona.id}, {where}, {persona.state})')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
