"""Voice workshop server (E22-T02, ADR atelier-voix D01, D02, D06): a local web page to write the radio voice sheets.

    python bridge/radio_bridge.py --atelier [--atelier-port 8765] [--atelier-host 0.0.0.0]

Listens on 127.0.0.1 by default and serves the page of bridge/atelier/ (index.html, app.js, catalog.json...) and a JSON API
on the sheets of the working folder, the one the game reads again every 30 s (D02): never the folder of the mod.

    GET    /api/status                     working and delivered folders, version of the mod
    GET    /api/voices                     one entry per voice: id, file, name, delivered, modified, removed, custom,
                                           present (false: the delivered sheet comes back at the next world load)
    GET    /api/voices/<id>                text of the sheet (working file, else the delivered one)
    PUT    /api/voices/<id>                body = text of the sheet: written (UTF-8, LF), created when new
    DELETE /api/voices/<id>                voice created by the player: file deleted; delivered voice: refused
    POST   /api/voices/<id>/duplicate      {"newId": "..."}: copy under a new id
    POST   /api/voices/<id>/remove         delivered voice: emptied file (the only removal the game knows)
    POST   /api/voices/<id>/restore        delivered voice: working file deleted, recopied at the next world load
    GET    /api/voices/<id>/export         the .txt sheet as an attachment
    POST   /api/import                     {"filename", "text", "newId"?}: new voice, conflict when the id exists
    GET    /api/verdicts                   E22-T04: the game's last verdict per voice id, read in its console:
                                           {state: refused | changed | loaded | removed, line, reason, time}
    GET    /api/log?since=<seq>            E22-T10: journal entries after <seq> (bridge and game lines), last seq,
                                           whether the bridge loop runs
    GET    /api/surveys                    E22-T08: places recorded in game (place_surveys.py), newest first, and
                                           where the survey file is
    POST   /api/ai/personality             E22-T06 (D04): {voiceId, description, name, knows[], ignores[], secret[]}
                                           -> {prompt}: English personality text ([prompt] of the sheet)
    POST   /api/ai/story                   {voiceId, missionType, voiceText, context} -> {story}: one sentence
    POST   /api/ai/try                     {voiceId, sheetText, history[], text} -> {lines}: a test turn with the voice
                                           built from the unsaved text; no AI configured: 503 ai_unavailable
    POST   /api/login                      E22-T15, network mode only: {"password"} -> session cookie; 401 bad_password,
                                           429 login_locked {retryAfter}
    POST   /api/logout                     network mode only: the session ends

Access (E22-T15, ADR atelier-voix D11) is one gate chosen from the listening address: on the loopback (LocalGate) the
Host must be the loopback and the Origin, when present, our own page, as before; on any other address (NetworkGate)
every client logs in with ATELIER_PASSWORD (atelier_auth), the loopback included, and a state-changing request whose
Origin is not its own scheme://Host is refused. Without a session, /api/* answers 401 and a page redirects to the login
page; only the login page and what it loads (PUBLIC_PATHS) are served without one.

Every answer of a write or a refusal is {"ok": bool, "code": stable code for the page to translate, "message":
English text}. The format of a sheet is not checked here: the game is the only judge (D03); only the size, the
encoding and the `id=` line of the head (same id as the file) are. Ids follow persona_store.ID_RE: never a file starting
with "_" (catalogues such as _categories.txt), never a path outside the working folder. Standard library only.
"""
from __future__ import annotations

import ipaddress
import json
import os
import re
import socket
import sys
import threading
import urllib.parse
import webbrowser
import zlib
from dataclasses import dataclass, field
from http.cookies import CookieError, SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable, Protocol

import atelier_ai
import atelier_auth
import persona_store

HOST = '127.0.0.1'
DEFAULT_PORT = 8765
PORT_TRIES = 10                      # busy port: the next ones are tried
MAX_SHEET_BYTES = 256 * 1024
MAX_JSON_BYTES = 2 * MAX_SHEET_BYTES  # an import carries a whole sheet in JSON
MAX_DISCARD_BYTES = 16 * 1024 * 1024  # unread body still drained up to this size
STATIC_ROOT = Path(__file__).resolve().parent / 'atelier'
SUFFIX = '.txt'
ID_LINE_RE = re.compile(r'^[ \t]*id[ \t]*=(.*)$')
CONTENT_TYPES = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
                 '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
                 '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
                 '.txt': 'text/plain; charset=utf-8'}


class AtelierError(Exception):
    """Refused operation: HTTP status, stable code and English message for the page (extra fields and headers)."""

    def __init__(self, status: int, code: str, message: str, extra: dict | None = None,
                 headers: dict[str, str] | None = None):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message
        self.extra, self.headers = extra or {}, headers or {}


class StartRefused(Exception):
    """The workshop cannot start as asked (network mode without a good password): English message for the console."""


@dataclass
class Done:
    """Accepted operation."""
    code: str
    message: str
    status: int = 200


def normalize(text: str) -> str:
    """LF line breaks, no BOM: the text the game reads (its fingerprints ignore line endings)."""
    if text.startswith(persona_store.BOM):
        text = text[len(persona_store.BOM):]
    lines = persona_store.split_lines(text)
    return '\n'.join(lines) + '\n' if lines else ''


def head_lines(lines: list[str]) -> range:
    """Indexes of the head of a sheet: the lines before its first section."""
    for index, line in enumerate(lines):
        if persona_store.trim(line).startswith('['):
            return range(index)
    return range(len(lines))


FINGERPRINTS = 'personas-fingerprints.txt'


def fingerprint(text: str) -> str:
    """Fingerprint of a sheet as RS_Personas.fingerprint computes it: Adler-32 (decimal) of its UTF-8 bytes, lines
    (split like Java readLine: LF, CR or CRLF, no empty last line) joined by LF."""
    lines = re.split(r'\r\n|\r|\n', text)
    if lines and lines[-1] == '':
        lines.pop()
    return str(zlib.adler32('\n'.join(lines).encode('utf-8')))


def head_value(text: str, key: str) -> str | None:
    """Value of `key=` in the head, read leniently (no validation: D03)."""
    lines = persona_store.split_lines(text)
    for index in head_lines(lines):
        name, sep, value = lines[index].partition('=')
        if sep and persona_store.trim(name) == key:
            return persona_store.trim(value)
    return None


def with_id(text: str, voice_id: str) -> str:
    """Text whose `id=` line of the head names `voice_id` (copy, import under a new id); no such line: unchanged."""
    lines = persona_store.split_lines(text)
    for index in head_lines(lines):
        if ID_LINE_RE.match(lines[index]):
            lines[index] = f'id={voice_id}'
            break
    return '\n'.join(lines) + '\n' if lines else ''


def mod_version(shipped: Path) -> str | None:
    """modversion= of the mod.info next to the delivered sheets, None when unreadable."""
    try:
        text = (shipped.parent / 'mod.info').read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError):
        return None
    for line in persona_store.split_lines(text):
        name, sep, value = line.partition('=')
        if sep and name.strip() == 'modversion':
            return value.strip()
    return None


class VoiceStore:
    """Operations on the voice sheets: writes only in `working`, reads the delivered sheets of `shipped`."""

    def __init__(self, working: Path, shipped: Path):
        self.working, self.shipped = Path(working), Path(shipped)
        self._lock = threading.Lock()

    # --- paths and reads -------------------------------------------------------------------------------------------
    @staticmethod
    def check_id(voice_id: str) -> str:
        if not isinstance(voice_id, str) or not persona_store.ID_RE.fullmatch(voice_id):
            raise AtelierError(400, 'bad_id', f"invalid voice id {voice_id!r}: lowercase letters, digits and '_', "
                                              "starting with a letter, at most 32 characters")
        return voice_id

    def _file(self, folder: Path, voice_id: str) -> Path:
        self.check_id(voice_id)
        path = folder / (voice_id + SUFFIX)
        if path.resolve().parent != folder.resolve():   # defence in depth: the id rule already forbids it
            raise AtelierError(400, 'bad_id', f"voice id {voice_id!r} leaves the folder")
        return path

    def working_file(self, voice_id: str) -> Path:
        return self._file(self.working, voice_id)

    def shipped_file(self, voice_id: str) -> Path:
        return self._file(self.shipped, voice_id)

    def is_delivered(self, voice_id: str) -> bool:
        return self.shipped_file(voice_id).is_file()

    def exists(self, voice_id: str) -> bool:
        return self.working_file(voice_id).is_file() or self.is_delivered(voice_id)

    @staticmethod
    def _ids(folder: Path) -> set[str]:
        if not folder.is_dir():
            return set()
        return {p.name[:-len(SUFFIX)] for p in folder.iterdir()
                if p.is_file() and p.name.endswith(SUFFIX) and persona_store.ID_RE.fullmatch(p.name[:-len(SUFFIX)])}

    @staticmethod
    def _read(path: Path) -> str:
        return path.read_bytes().decode('utf-8', errors='replace')

    def read(self, voice_id: str) -> str:
        for path in (self.working_file(voice_id), self.shipped_file(voice_id)):
            if path.is_file():
                return self._read(path)
        raise AtelierError(404, 'voice_not_found', f"voice '{voice_id}' not found")

    def entry(self, voice_id: str) -> dict:
        work, ship = self.working_file(voice_id), self.shipped_file(voice_id)
        present, delivered = work.is_file(), ship.is_file()
        text = self._read(work) if present else ''
        shipped_text = self._read(ship) if delivered else ''
        removed = present and text == ''
        differs = delivered and present and not removed and normalize(text) != normalize(shipped_text)
        # A copy the game wrote itself (its fingerprint is the one the game remembered) is an older delivered version:
        # the game replaces it at the next world load. Only a copy changed by someone is "modified".
        outdated = differs and self._fingerprints().get(work.name) == fingerprint(text)
        return {'id': voice_id, 'file': work.name,
                'name': head_value(text if present and not removed else shipped_text, 'name') or '',
                'delivered': delivered, 'custom': not delivered, 'present': present, 'removed': removed,
                'modified': differs and not outdated, 'outdated': outdated}

    def _fingerprints(self) -> dict[str, str]:
        """Fingerprints the game remembered for the sheets it wrote (RS_Personas, personas-fingerprints.txt next to
        the working folder: header RSFP1, then `name.txt fingerprint`); empty when absent or unreadable."""
        try:
            lines = (self.working.parent / FINGERPRINTS).read_text(encoding='utf-8').splitlines()
        except (OSError, UnicodeDecodeError):
            return {}
        if not lines or lines[0].strip() != 'RSFP1':
            return {}
        return dict(line.split(' ', 1) for line in lines[1:] if line.count(' ') == 1)

    def voices(self) -> list[dict]:
        entries = [self.entry(i) for i in sorted(self._ids(self.working) | self._ids(self.shipped))]
        # An empty sheet of no delivered voice is no voice at all (left over by in-game tests): not listed.
        return [e for e in entries if not (e['custom'] and e['removed'])]

    def sheet_mtime(self, voice_id: str) -> float | None:
        """Modification time of the working sheet the game reads, None when absent (the game copies the delivered one
        again at the next world load)."""
        try:
            return self.working_file(voice_id).stat().st_mtime
        except (OSError, AtelierError):
            return None

    def sheet_text(self, voice_id: str) -> str | None:
        """Text the game reads for this voice (working file, else the delivered one it copies), None when absent."""
        try:
            return self.read(voice_id)
        except AtelierError:
            return None

    # --- writes ----------------------------------------------------------------------------------------------------
    @staticmethod
    def check_text(voice_id: str, text: str) -> str:
        if len(text.encode('utf-8')) > MAX_SHEET_BYTES:
            raise AtelierError(413, 'too_large', f"sheet larger than {MAX_SHEET_BYTES // 1024} KB")
        named = head_value(text, 'id')
        if named is not None and named != voice_id:
            raise AtelierError(400, 'id_mismatch', f"the sheet says id={named} but is saved as '{voice_id}': "
                                                   "the id line must match the voice")
        return normalize(text)

    def _write(self, voice_id: str, text: str) -> None:
        path = self.working_file(voice_id)
        self.working.mkdir(parents=True, exist_ok=True)
        temp = path.with_name(path.name + '.tmp')   # not *.txt: never read by the game
        temp.write_bytes(text.encode('utf-8'))
        os.replace(temp, path)

    def write(self, voice_id: str, text: str) -> Done:
        text = self.check_text(self.check_id(voice_id), text)
        with self._lock:
            created = not self.exists(voice_id)
            self._write(voice_id, text)
        if created:
            return Done('voice_created', f"voice '{voice_id}' created", 201)
        return Done('voice_saved', f"voice '{voice_id}' saved; the game reads it again within 30 s")

    def _create(self, voice_id: str, text: str) -> None:
        """New voice under `voice_id` (copy, import): refused when it already exists, delivered or not."""
        self.check_id(voice_id)
        if self.exists(voice_id):
            raise AtelierError(409, 'voice_exists', f"voice '{voice_id}' already exists: choose another id")
        self._write(voice_id, self.check_text(voice_id, with_id(text, voice_id)))

    def duplicate(self, voice_id: str, new_id: str) -> Done:
        text = self.read(voice_id)
        with self._lock:
            self._create(new_id, text)
        return Done('voice_created', f"voice '{voice_id}' copied as '{new_id}'", 201)

    def delete(self, voice_id: str) -> Done:
        path = self.working_file(voice_id)
        if self.is_delivered(voice_id):
            raise AtelierError(409, 'delivered_voice', f"voice '{voice_id}' is delivered with the mod and cannot be "
                                                       "deleted: use remove to silence it or restore to get the "
                                                       "delivered version back")
        with self._lock:
            if not path.is_file():
                raise AtelierError(404, 'voice_not_found', f"voice '{voice_id}' not found")
            path.unlink()
        return Done('voice_deleted', f"voice '{voice_id}' deleted")

    def _delivered_only(self, voice_id: str, verb: str) -> None:
        if not self.is_delivered(voice_id):
            raise AtelierError(409, 'not_delivered', f"voice '{voice_id}' is not delivered with the mod: cannot "
                                                     f"{verb} it, delete it instead")

    def remove(self, voice_id: str) -> Done:
        self._delivered_only(voice_id, 'remove')
        with self._lock:
            self._write(voice_id, '')
        return Done('voice_removed', f"voice '{voice_id}' removed: its sheet is now empty, the game drops it within "
                                     "30 s; restore brings it back")

    def restore(self, voice_id: str) -> Done:
        self._delivered_only(voice_id, 'restore')
        with self._lock:
            self.working_file(voice_id).unlink(missing_ok=True)
        return Done('voice_restored', f"voice '{voice_id}' restored: the delivered version comes back at the next "
                                      "world load")

    def import_voice(self, filename: str, text: str, new_id: str | None = None) -> tuple[str, Done]:
        """Sheet of another player: id = new_id, else its id= line, else the file name."""
        if not isinstance(text, str):
            raise AtelierError(400, 'bad_request', "missing text of the imported sheet")
        voice_id = new_id or head_value(text, 'id') or Path(str(filename or '')).stem
        self.check_id(voice_id)
        with self._lock:
            self._create(voice_id, text)
        return voice_id, Done('voice_imported', f"voice '{voice_id}' imported", 201)


# --- live sources (E22-T04, E22-T10) ---------------------------------------------------------------------------------
class Journal(Protocol):
    def since(self, seq: int) -> tuple[list[dict], int]: ...


class GameVerdicts(Protocol):
    path: Path
    found: bool

    def refresh(self) -> None: ...

    def verdicts(self, read_sheet: Callable[[str], str | None]) -> dict[str, dict]: ...


class PlaceSurveys(Protocol):
    path: Path
    found: bool

    def records(self) -> list[dict]: ...


@dataclass
class Live:
    """What the workshop reads live, built by the composition root (radio_bridge.main): the journal of the bridge and
    the game, the game's console (None when its folder is unknown), whether the bridge loop runs, the workshop AI
    (E22-T06; None when no LLM is configured or the bridge runs offline) and the places recorded in game (E22-T08)."""
    journal: Journal | None = None
    game: GameVerdicts | None = None
    bridge_running: Callable[[], bool] = field(default=lambda: False)
    ai: atelier_ai.WorkshopAI | None = None
    surveys: PlaceSurveys | None = None


# --- access (E22-T15, ADR atelier-voix D11) --------------------------------------------------------------------------
SESSION_COOKIE = 'atelier_session'
LOGIN_PAGE = '/login.html'
# Served without a session: the login page and what it loads (strings, styles), and the login itself.
PUBLIC_PATHS = frozenset({LOGIN_PAGE, '/login.js', '/dom.js', '/i18n.js', '/i18n/fr.json', '/i18n/en.json',
                          '/theme.css', '/vendor/pico.min.css', '/api/login'})
SAFE_METHODS = frozenset({'GET', 'HEAD'})


@dataclass(frozen=True)
class Request:
    """What a gate reads of a request: method, decoded path, Host and Origin headers, session token, port served."""
    method: str
    path: str
    host: str | None
    origin: str | None
    token: str | None
    port: int


def forbidden_origin() -> AtelierError:
    return AtelierError(403, 'forbidden_origin', "request refused: the workshop only answers its own page")


class Gate(Protocol):
    """Who may use the workshop. `login`: the page shows a logout button; `routes`: API routes the gate adds."""
    login: bool
    routes: tuple

    def admit(self, request: Request) -> None: ...


class LocalGate:
    """Loopback mode: no password; Host is the loopback (no DNS rebinding), Origin absent or our own page."""
    login = False
    routes: tuple = ()

    def admit(self, request: Request) -> None:
        allowed = {f'{HOST}:{request.port}', f'localhost:{request.port}'}
        if request.host not in allowed or (request.origin is not None
                                           and request.origin not in {f'http://{a}' for a in allowed}):
            raise forbidden_origin()


class NetworkGate:
    """Network mode: any Host, but a state-changing request comes from its own page (Origin absent or equal to
    http://<Host>) and every path but PUBLIC_PATHS needs a session of `auth`."""
    login = True

    def __init__(self, auth: atelier_auth.Authenticator):
        self.auth = auth
        self.routes = AUTH_ROUTES

    def admit(self, request: Request) -> None:
        if (request.method not in SAFE_METHODS and request.origin is not None
                and request.origin != f'http://{request.host}'):
            raise forbidden_origin()
        if request.path in PUBLIC_PATHS or self.auth.valid(request.token):
            return
        if request.path.startswith('/api/'):
            raise AtelierError(401, 'login_required', "log in first: the workshop asks for its password")
        raise AtelierError(303, 'login_required', "log in first", headers={'Location': LOGIN_PAGE})


def is_loopback(host: str) -> bool:
    if host.lower() == 'localhost':
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def gate_for(host: str, password: str | None, log: Callable[[str], None]) -> Gate:
    """LocalGate on the loopback, else NetworkGate over ATELIER_PASSWORD (StartRefused when absent or too short)."""
    if is_loopback(host):
        return LocalGate()
    try:
        return NetworkGate(atelier_auth.Authenticator(password, log))
    except atelier_auth.PasswordRefused as err:
        raise StartRefused(f"{err}; the voice workshop does not start on {host}") from None


# --- HTTP adapter ----------------------------------------------------------------------------------------------------
VOICE = r'/api/voices/([^/]+)'
ROUTES: list[tuple[str, re.Pattern, str]] = [
    ('GET', re.compile(r'/api/status'), 'status'),
    ('GET', re.compile(r'/api/voices'), 'list_voices'),
    ('GET', re.compile(VOICE + r'/export'), 'export_voice'),
    ('GET', re.compile(VOICE), 'read_voice'),
    ('PUT', re.compile(VOICE), 'write_voice'),
    ('DELETE', re.compile(VOICE), 'delete_voice'),
    ('POST', re.compile(VOICE + r'/duplicate'), 'duplicate_voice'),
    ('POST', re.compile(VOICE + r'/remove'), 'remove_voice'),
    ('POST', re.compile(VOICE + r'/restore'), 'restore_voice'),
    ('POST', re.compile(r'/api/import'), 'import_voice'),
    ('GET', re.compile(r'/api/verdicts'), 'game_verdicts'),
    ('GET', re.compile(r'/api/log'), 'journal'),
    ('GET', re.compile(r'/api/surveys'), 'place_surveys'),
    ('POST', re.compile(r'/api/ai/([a-z]+)'), 'ai_request'),
]
AUTH_ROUTES: tuple[tuple[str, re.Pattern, str], ...] = (    # E22-T15: network mode only (NetworkGate.routes)
    ('POST', re.compile(r'/api/login'), 'login'),
    ('POST', re.compile(r'/api/logout'), 'logout'),
)
# E22-T06: /api/ai/<kind> -> (method of atelier_ai.WorkshopAI, key of its answer)
AI_REQUESTS = {'personality': ('personality', 'prompt'), 'story': ('story', 'story'), 'try': ('try_voice', 'lines')}
AI_UNAVAILABLE = ("no AI is configured for the bridge: copy bridge/.env.example to bridge/.env, fill in OPENAI_KEY, "
                  "OPENAI_BASE_URL and OPENAI_MODEL, then restart the bridge without --offline")


class AtelierServer(ThreadingHTTPServer):
    daemon_threads = True
    # Windows' SO_REUSEADDR lets a second server take a busy port: off there, so a busy port moves to the next one.
    allow_reuse_address = sys.platform != 'win32'

    def __init__(self, address: tuple[str, int], store: VoiceStore, static_root: Path, version: str | None,
                 log: Callable[[str], None], live: Live | None = None, gate: Gate | None = None):
        if ':' in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, AtelierHandler)
        self.store, self.static_root, self.version, self.log = store, Path(static_root), version, log
        self.live = live or Live()
        self.gate = gate or LocalGate()
        self.routes = (*ROUTES, *self.gate.routes)

    @property
    def url(self) -> str:
        """Address for a browser of this machine: the loopback when listening on every address."""
        host = self.server_address[0]
        if host in ('0.0.0.0', '::'):
            host = HOST
        return f'http://{"[" + host + "]" if ":" in host else host}:{self.server_address[1]}/'


class AtelierHandler(BaseHTTPRequestHandler):
    server: AtelierServer
    server_version = 'RadioSurvivorAtelier'
    _unread = 0                      # bytes of the request body not read yet

    def log_message(self, fmt: str, *args) -> None:   # quiet: errors only, through the server log
        pass

    # --- plumbing --------------------------------------------------------------------------------------------------
    def _send(self, status: int, body: bytes, content_type: str, headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def _json(self, status: int, payload, headers: dict[str, str] | None = None) -> None:
        self._send(status, json.dumps(payload, ensure_ascii=False).encode('utf-8'), CONTENT_TYPES['.json'], headers)

    def _done(self, done: Done, headers: dict[str, str] | None = None, **extra) -> None:
        self._json(done.status, {'ok': True, 'code': done.code, 'message': done.message, **extra}, headers)

    def _error(self, err: AtelierError) -> None:
        self._json(err.status, {'ok': False, 'code': err.code, 'message': err.message, **err.extra}, err.headers)

    def _length(self) -> int:
        try:
            return max(0, int(self.headers.get('Content-Length') or 0))
        except ValueError:
            raise AtelierError(400, 'bad_request', "invalid Content-Length") from None

    def _body(self, limit: int) -> str:
        if self._unread > limit:
            raise AtelierError(413, 'too_large', f"request larger than {limit // 1024} KB")
        length, self._unread = self._unread, 0
        try:
            return self.rfile.read(length).decode('utf-8')
        except UnicodeDecodeError:
            raise AtelierError(400, 'bad_encoding', "the text is not valid UTF-8") from None

    def _discard(self) -> None:
        """Body left unread (refused request, route without body) read and dropped before the connection closes:
        closing on unread bytes resets it and the page loses the answer. A huge one is not read."""
        length, self._unread = self._unread, 0
        if length > MAX_DISCARD_BYTES:
            return
        while length > 0:
            chunk = self.rfile.read(min(length, 65536))
            if not chunk:
                break
            length -= len(chunk)

    def _json_body(self) -> dict:
        try:
            data = json.loads(self._body(MAX_JSON_BYTES) or '{}')
        except json.JSONDecodeError:
            raise AtelierError(400, 'bad_request', "the request body is not valid JSON") from None
        if not isinstance(data, dict):
            raise AtelierError(400, 'bad_request', "the request body must be a JSON object")
        return data

    def _token(self) -> str | None:
        """Session token of the cookie, None when absent or unreadable."""
        try:
            morsel = SimpleCookie(self.headers.get('Cookie') or '').get(SESSION_COOKIE)
        except CookieError:
            return None
        return morsel.value if morsel is not None else None

    def _request(self, path: str) -> Request:
        return Request(self.command, path, self.headers.get('Host'), self.headers.get('Origin'), self._token(),
                       self.server.server_address[1])

    def _dispatch(self) -> None:
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        self._unread = 0
        try:
            self._unread = self._length()
            self.server.gate.admit(self._request(path))     # the one access check (E22-T15)
            if not path.startswith('/api/'):
                if self.command not in ('GET', 'HEAD'):
                    raise AtelierError(405, 'method_not_allowed', f"{self.command} not allowed on {path}")
                return self.static(path)
            for method, pattern, name in self.server.routes:
                match = pattern.fullmatch(path)
                if match and method == self.command:
                    return getattr(self, name)(*match.groups())
            raise AtelierError(404, 'not_found', f"no API route {self.command} {path}")
        except AtelierError as err:
            self._error(err)
        except OSError as err:
            self.server.log(f"atelier: {self.command} {path} failed: {type(err).__name__}: {err}")
            self._error(AtelierError(500, 'io_error', f"file operation failed ({type(err).__name__})"))
        finally:
            self._discard()

    do_GET = do_HEAD = do_PUT = do_POST = do_DELETE = _dispatch

    # --- static page -----------------------------------------------------------------------------------------------
    def static(self, path: str) -> None:
        root = self.server.static_root.resolve()
        relative = path.lstrip('/') or 'index.html'
        target = (root / relative).resolve()
        if root != target and root not in target.parents:
            raise AtelierError(403, 'forbidden_path', "path outside the workshop folder")
        if target.is_dir():
            target = target / 'index.html'
        if not target.is_file():
            raise AtelierError(404, 'not_found', f"{relative} not found in the workshop folder")
        content_type = CONTENT_TYPES.get(target.suffix.lower(), 'application/octet-stream')
        self._send(200, target.read_bytes(), content_type)

    # --- API -------------------------------------------------------------------------------------------------------
    def status(self) -> None:
        store = self.server.store
        self._json(200, {'ok': True, 'working': str(store.working.resolve()), 'shipped': str(store.shipped.resolve()),
                         'workingExists': store.working.is_dir(), 'version': self.server.version,
                         'ai': self.server.live.ai is not None, 'login': self.server.gate.login})

    # --- login (E22-T15, network mode only: AUTH_ROUTES) -----------------------------------------------------------
    def login(self) -> None:
        result = self.server.gate.auth.login(self.client_address[0], self._json_body().get('password'))
        if result.outcome == atelier_auth.LOCKED:
            raise AtelierError(429, 'login_locked', f"too many failed logins: try again in {result.retry_after} s",
                               {'retryAfter': result.retry_after}, {'Retry-After': str(result.retry_after)})
        if result.outcome != atelier_auth.LOGGED_IN:
            raise AtelierError(401, 'bad_password', "wrong password")
        cookie = (f'{SESSION_COOKIE}={result.token}; HttpOnly; SameSite=Strict; Path=/; '
                  f'Max-Age={atelier_auth.SESSION_SECONDS}')
        self._done(Done('logged_in', "logged in"), {'Set-Cookie': cookie})

    def logout(self) -> None:
        self.server.gate.auth.logout(self.client_address[0], self._token())
        self._done(Done('logged_out', "logged out"),
                   {'Set-Cookie': f'{SESSION_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'})

    def list_voices(self) -> None:
        self._json(200, {'ok': True, 'voices': self.server.store.voices()})

    def read_voice(self, voice_id: str) -> None:
        self._send(200, self.server.store.read(voice_id).encode('utf-8'), CONTENT_TYPES['.txt'])

    def export_voice(self, voice_id: str) -> None:
        body = self.server.store.read(voice_id).encode('utf-8')
        self._send(200, body, CONTENT_TYPES['.txt'],
                   {'Content-Disposition': f'attachment; filename="{voice_id}{SUFFIX}"'})

    def write_voice(self, voice_id: str) -> None:
        self.server.store.check_id(voice_id)
        self._done(self.server.store.write(voice_id, self._body(MAX_SHEET_BYTES)), id=voice_id)

    def delete_voice(self, voice_id: str) -> None:
        self._done(self.server.store.delete(voice_id), id=voice_id)

    def duplicate_voice(self, voice_id: str) -> None:
        new_id = self._json_body().get('newId')
        self._done(self.server.store.duplicate(voice_id, new_id), id=new_id)

    def remove_voice(self, voice_id: str) -> None:
        self._done(self.server.store.remove(voice_id), id=voice_id)

    def restore_voice(self, voice_id: str) -> None:
        self._done(self.server.store.restore(voice_id), id=voice_id)

    def import_voice(self) -> None:
        data = self._json_body()
        voice_id, done = self.server.store.import_voice(data.get('filename'), data.get('text'), data.get('newId'))
        self._done(done, id=voice_id)

    # --- live (E22-T04, E22-T10) -----------------------------------------------------------------------------------
    def _game(self) -> dict:
        """New lines of the game's console read, and where it is."""
        game = self.server.live.game
        if game is not None:
            game.refresh()
        return {'gameLog': str(game.path) if game is not None else None,
                'gameLogFound': bool(game is not None and game.found)}

    def game_verdicts(self) -> None:
        state = self._game()
        game = self.server.live.game
        verdicts = game.verdicts(self.server.store.sheet_text, self.server.store.sheet_mtime) if game is not None else {}
        self._json(200, {'ok': True, 'verdicts': verdicts, **state})

    def journal(self) -> None:
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        try:
            since = int((query.get('since') or ['0'])[0])
        except ValueError:
            raise AtelierError(400, 'bad_request', "since must be a whole number") from None
        state = self._game()
        journal = self.server.live.journal
        entries, last = journal.since(since) if journal is not None else ([], 0)
        self._json(200, {'ok': True, 'entries': entries, 'last': last,
                         'bridge': bool(self.server.live.bridge_running()), **state})

    def place_surveys(self) -> None:
        surveys = self.server.live.surveys
        self._json(200, {'ok': True, 'records': surveys.records() if surveys is not None else [],
                         'surveysFile': str(surveys.path) if surveys is not None else None,
                         'surveysFound': bool(surveys is not None and surveys.found)})

    # --- workshop AI (E22-T06) -------------------------------------------------------------------------------------
    def ai_request(self, kind: str) -> None:
        if kind not in AI_REQUESTS:
            raise AtelierError(404, 'not_found', f"no AI request '{kind}'")
        ai = self.server.live.ai
        if ai is None:
            raise AtelierError(503, 'ai_unavailable', AI_UNAVAILABLE)
        data = self._json_body()
        method, key = AI_REQUESTS[kind]
        try:
            result = getattr(ai, method)(data)
        except atelier_ai.AiError as err:
            raise AtelierError(err.status, err.code, err.message) from None
        self._json(200, {'ok': True, 'code': 'ok', key: result})


# --- composition -----------------------------------------------------------------------------------------------------
def bind(store: VoiceStore, port: int = DEFAULT_PORT, static_root: Path = STATIC_ROOT, version: str | None = None,
         log: Callable[[str], None] = print, tries: int = PORT_TRIES, live: Live | None = None,
         host: str = HOST, gate: Gate | None = None) -> AtelierServer:
    """Server on `host`, on `port` or, when busy, one of the next `tries - 1` ports (0: any free port)."""
    last: OSError | None = None
    for candidate in ([0] if port == 0 else range(port, port + tries)):
        try:
            return AtelierServer((host, candidate), store, static_root, version, log, live, gate)
        except OSError as err:
            last = err
    raise OSError(f"no free port from {port} to {port + tries - 1}: {last}")


def start(server: AtelierServer) -> threading.Thread:
    thread = threading.Thread(target=server.serve_forever, args=(0.1,), name='atelier', daemon=True)
    thread.start()
    return thread


def lan_address() -> str | None:
    """IPv4 address of this machine on its network (the one its default route uses), None when unknown. Connecting a
    UDP socket sends nothing."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(('192.0.2.1', 9))      # TEST-NET-1: only routed, never reached
            address = probe.getsockname()[0]
    except OSError:
        return None
    return None if address.startswith(('0.', '127.')) else address


def network_line(server: AtelierServer) -> str:
    """Startup line of the network mode (ADR atelier-voix D11)."""
    host, port = server.server_address[:2]
    shown = f'[{host}]' if ':' in host else host
    line = f"Voice workshop on http://{shown}:{port}/ (password required)"
    if host in ('0.0.0.0', '::'):
        lan = lan_address()
        line += f"; from another device: http://{lan}:{port}/" if lan else "; from any address of this machine"
    return line


def launch(working: Path, shipped: Path, port: int = DEFAULT_PORT, log: Callable[[str], None] = print,
           open_browser: Callable[[str], object] = webbrowser.open, live: Live | None = None,
           host: str = HOST, password: str | None = None) -> tuple[AtelierServer, threading.Thread]:
    """Workshop of the voices of `working` (delivered ones in `shipped`), served in the background, page opened.
    Any `host` but the loopback needs `password` (ATELIER_PASSWORD): StartRefused otherwise, nothing bound."""
    gate = gate_for(host, password, log)
    server = bind(VoiceStore(working, shipped), port, version=mod_version(Path(shipped)), log=log, live=live,
                  host=host, gate=gate)
    thread = start(server)
    log(f"Voice workshop: {server.url} (voice sheets: {Path(working).resolve()})")
    if gate.login:
        log(network_line(server))
    game = server.live.game
    if game is not None:
        log(f"Voice workshop: game verdicts read in {game.path}" + ("" if game.found else " (not found yet)"))
    surveys = server.live.surveys
    if surveys is not None:
        log(f"Voice workshop: places recorded in game read in {surveys.path}"
            + ("" if surveys.found else " (none recorded yet)"))
    if not open_browser(server.url):
        log("Voice workshop: open the address above in your browser")
    return server, thread


def serve_until_interrupted(server: AtelierServer, thread: threading.Thread, log: Callable[[str], None] = print) -> None:
    try:
        while thread.is_alive():
            thread.join(0.5)
    except KeyboardInterrupt:
        log("Voice workshop stopped")
    finally:
        server.shutdown()
        server.server_close()
