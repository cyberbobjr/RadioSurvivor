"""E22-T02: voice workshop server of the bridge (bridge/atelier_server.py, ADR atelier-voix D01, D02, D06).

    python RadioSurvivor/tests/test_atelier_server.py

A real server on 127.0.0.1 (free port) over a temporary working folder and a temporary delivered folder: list, read,
write, duplicate, delete (created voice) and its refusal (delivered voice), remove, restore, export, import and its
conflict, refused ids (traversal, "_" catalogues, uppercase), static files and their traversal, foreign origins,
busy port; E22-T15: network mode (login, session cookie, lock, logout, origin) and its refused start. Every write
stays in the working folder; the delivered folder is never touched. No network beyond the
loopback, no browser.
"""
from __future__ import annotations

import http.client
import json
import socket
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import atelier_auth  # noqa: E402
import atelier_server as atelier  # noqa: E402
import radio_bridge as rb  # noqa: E402

WALT = "# delivered\nformat=1\nid=walt\nname=Walt Hensley\nfrequencies=145.0\n\n[prompt]\nYou are Walt.\n"
CODY = "format=1\nid=cody\nname=Cody\nfrequencies=146.0\n[prompt]\nYou are Cody.\n"


def snapshot(folder: Path) -> dict[str, bytes]:
    return {p.name: p.read_bytes() for p in sorted(folder.rglob("*")) if p.is_file()}


class AtelierServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.working = base / "Lua" / "batman_RadioSurvivor" / "personas"
        self.shipped = base / "mod" / "42.21" / "personas"
        self.static = base / "atelier"
        self.outside = base / "Lua" / "batman_RadioSurvivor"
        self.shipped.mkdir(parents=True)
        self.static.mkdir()
        (self.shipped / "walt.txt").write_text(WALT, encoding="utf-8", newline="")
        (self.shipped / "cody.txt").write_text(CODY, encoding="utf-8", newline="")
        (self.shipped / "_categories.txt").write_text("[category food]\n", encoding="utf-8")
        (self.shipped.parent / "mod.info").write_text("name=x\nmodversion=0.3.0\n", encoding="utf-8")
        (self.static / "index.html").write_text("<!doctype html><title>Atelier</title>", encoding="utf-8")
        (base / "secret.txt").write_text("secret", encoding="utf-8")
        self.working.mkdir(parents=True)
        (self.working / "walt.txt").write_text(WALT, encoding="utf-8", newline="")
        (self.working / "_categories.txt").write_text("not a voice", encoding="utf-8")
        self.shipped_before = snapshot(self.shipped)
        self.logs: list[str] = []
        store = atelier.VoiceStore(self.working, self.shipped)
        self.server = atelier.bind(store, 0, self.static, atelier.mod_version(self.shipped), self.logs.append)
        self.thread = atelier.start(self.server)
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.assertEqual(snapshot(self.shipped), self.shipped_before, "the delivered folder must never change")
        self.assertEqual(sorted(p.name for p in self.outside.iterdir()), ["personas"], "write outside the folder")
        self.tmp.cleanup()

    def request(self, method: str, path: str, body=None, headers: dict | None = None):
        conn = http.client.HTTPConnection(atelier.HOST, self.port, timeout=10)
        data = body
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            data = body.encode("utf-8")
        conn.request(method, path, body=data, headers=headers or {})
        resp = conn.getresponse()
        raw = resp.read()
        conn.close()
        payload = json.loads(raw) if resp.getheader("Content-Type", "").startswith("application/json") else raw
        return resp.status, payload, resp

    def voices(self) -> dict[str, dict]:
        status, payload, _ = self.request("GET", "/api/voices")
        self.assertEqual(status, 200)
        return {v["id"]: v for v in payload["voices"]}

    def assert_refused(self, status, payload, expected_status, code):
        self.assertEqual(status, expected_status, payload)
        self.assertEqual(payload["ok"], False)
        self.assertEqual(payload["code"], code)
        self.assertTrue(payload["message"])

    # --- status and list -------------------------------------------------------------------------------------------
    def test_status_names_the_folders_and_version(self):
        status, payload, _ = self.request("GET", "/api/status")
        self.assertEqual(status, 200)
        self.assertEqual(Path(payload["working"]), self.working.resolve())
        self.assertEqual(Path(payload["shipped"]), self.shipped.resolve())
        self.assertEqual(payload["version"], "0.3.0")

    def test_list_states_of_each_voice(self):
        (self.working / "walt.txt").write_text(WALT.replace("You are Walt.", "Changed."), encoding="utf-8")
        (self.working / "mine.txt").write_text("format=1\nid=mine\nname=My Voice\n", encoding="utf-8")
        voices = self.voices()
        self.assertEqual(sorted(voices), ["cody", "mine", "walt"])    # no "_" catalogue
        self.assertEqual(voices["walt"], {"id": "walt", "file": "walt.txt", "name": "Walt Hensley", "delivered": True,
                                          "custom": False, "present": True, "removed": False, "modified": True,
                                          "outdated": False})
        self.assertEqual(voices["cody"]["present"], False)            # comes back at the next world load
        self.assertEqual(voices["cody"]["name"], "Cody")
        self.assertEqual(voices["mine"]["custom"], True)
        self.assertEqual(voices["mine"]["delivered"], False)

    def test_copy_written_by_the_game_is_outdated_not_modified(self):
        """User report 2026-11-15: after a mod update, sheets the game wrote itself showed as "modified". A copy whose
        fingerprint is the one the game remembered (personas-fingerprints.txt) is outdated: the game replaces it."""
        old = WALT.replace("You are Walt.", "Older delivered text.")
        (self.working / "walt.txt").write_text(old, encoding="utf-8")
        (self.working.parent / "personas-fingerprints.txt").write_text(
            "RSFP1\nwalt.txt " + atelier.fingerprint(old) + "\n", encoding="utf-8")
        walt = self.voices()["walt"]
        self.assertEqual((walt["modified"], walt["outdated"]), (False, True))
        (self.working / "walt.txt").write_text(old + "# Edited by the admin.\n", encoding="utf-8")
        walt = self.voices()["walt"]
        self.assertEqual((walt["modified"], walt["outdated"]), (True, False))
        (self.working.parent / "personas-fingerprints.txt").unlink()   # written by the game, never by the workshop

    def test_empty_sheet_of_no_delivered_voice_is_not_listed(self):
        (self.working / "rstest_probe.txt").write_text("", encoding="utf-8")
        self.assertNotIn("rstest_probe", self.voices())

    def test_fingerprint_matches_the_game(self):
        # Value written by the game for a shipped sheet (RS_Personas.fingerprint, Adler-32 of lines joined by LF).
        self.assertEqual(atelier.fingerprint("a\r\nb\n"), atelier.fingerprint("a\nb"))

    def test_line_endings_alone_do_not_make_a_delivered_voice_modified(self):
        (self.working / "walt.txt").write_bytes(WALT.replace("\n", "\r\n").encode("utf-8"))
        self.assertFalse(self.voices()["walt"]["modified"])

    # --- read, write -----------------------------------------------------------------------------------------------
    def test_read_working_then_delivered(self):
        status, body, _ = self.request("GET", "/api/voices/walt")
        self.assertEqual((status, body.decode("utf-8")), (200, WALT))
        status, body, _ = self.request("GET", "/api/voices/cody")       # absent from the working folder
        self.assertEqual((status, body.decode("utf-8")), (200, CODY))
        self.assert_refused(*self.request("GET", "/api/voices/nobody")[:2], 404, "voice_not_found")

    def test_write_creates_then_saves_with_lf(self):
        status, payload, _ = self.request("PUT", "/api/voices/rosa", "format=1\r\nid=rosa\r\nname=Rosé\r\n")
        self.assertEqual((status, payload["code"]), (201, "voice_created"))
        self.assertEqual((self.working / "rosa.txt").read_bytes(), "format=1\nid=rosa\nname=Rosé\n".encode("utf-8"))
        status, payload, _ = self.request("PUT", "/api/voices/rosa", "format=1\nid=rosa\nname=Rosa\n")
        self.assertEqual((status, payload["code"]), (200, "voice_saved"))
        self.assertEqual(self.voices()["rosa"]["name"], "Rosa")

    def test_write_creates_the_missing_working_folder(self):
        for p in self.working.iterdir():
            p.unlink()
        self.working.rmdir()
        status, _, _ = self.request("PUT", "/api/voices/rosa", "id=rosa\n")
        self.assertEqual(status, 201)
        self.assertTrue((self.working / "rosa.txt").is_file())

    def test_write_refuses_mismatched_id_bad_utf8_and_oversize(self):
        self.assert_refused(*self.request("PUT", "/api/voices/rosa", "format=1\nid=walt\n")[:2], 400, "id_mismatch")
        self.assert_refused(*self.request("PUT", "/api/voices/rosa", b"id=rosa\n\xff\xfe")[:2], 400, "bad_encoding")
        big = "id=rosa\n" + "x" * atelier.MAX_SHEET_BYTES
        self.assert_refused(*self.request("PUT", "/api/voices/rosa", big)[:2], 413, "too_large")
        self.assertFalse((self.working / "rosa.txt").exists())

    def test_id_inside_a_section_is_not_the_head(self):
        status, _, _ = self.request("PUT", "/api/voices/rosa", "format=1\nid=rosa\n[mission x]\nid=other\n")
        self.assertEqual(status, 201)

    # --- ids and traversal -----------------------------------------------------------------------------------------
    def test_bad_ids_are_refused_everywhere(self):
        for raw in ("_categories", "Walt", "..", "%2e%2e", "..%5csecret", "a.b", "a%20b", "x" * 33, "9lives",
                    "..%2f..%2fsecret"):
            for method, suffix in (("GET", ""), ("PUT", ""), ("DELETE", ""), ("POST", "/remove"),
                                   ("POST", "/restore"), ("GET", "/export")):
                status, payload, _ = self.request(method, f"/api/voices/{raw}{suffix}", "id=x\n")
                self.assertIn(status, (400, 404), (method, raw, suffix))
                self.assertEqual(payload["ok"], False)
        status, payload, _ = self.request("POST", "/api/voices/walt/duplicate", {"newId": "../secret"})
        self.assert_refused(status, payload, 400, "bad_id")
        self.assertTrue((self.working / "_categories.txt").read_text(encoding="utf-8") == "not a voice")

    def test_static_files_and_traversal(self):
        status, body, resp = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"Atelier", body)
        self.assertTrue(resp.getheader("Content-Type").startswith("text/html"))
        for path in ("/../secret.txt", "/%2e%2e/secret.txt", "/..%2fsecret.txt", "/..%5csecret.txt",
                     "/%2e%2e%2f%2e%2e%2fsecret.txt"):
            status, payload, _ = self.request("GET", path)
            self.assertIn(status, (403, 404), path)
            self.assertNotEqual(payload, b"secret", path)
        self.assert_refused(*self.request("GET", "/missing.js")[:2], 404, "not_found")
        self.assert_refused(*self.request("POST", "/index.html", "x")[:2], 405, "method_not_allowed")

    def test_foreign_origin_and_host_are_refused(self):
        status, payload, _ = self.request("PUT", "/api/voices/rosa", "id=rosa\n", {"Origin": "http://evil.example"})
        self.assert_refused(status, payload, 403, "forbidden_origin")
        status, payload, _ = self.request("GET", "/api/voices", headers={"Host": "evil.example:80"})
        self.assert_refused(status, payload, 403, "forbidden_origin")
        status, _, _ = self.request("GET", "/api/voices", headers={"Origin": f"http://127.0.0.1:{self.port}"})
        self.assertEqual(status, 200)
        self.assertFalse((self.working / "rosa.txt").exists())

    # --- duplicate, delete, remove, restore ------------------------------------------------------------------------
    def test_duplicate_renames_the_id_line_and_refuses_existing(self):
        status, payload, _ = self.request("POST", "/api/voices/cody/duplicate", {"newId": "cody2"})
        self.assertEqual((status, payload["code"], payload["id"]), (201, "voice_created", "cody2"))
        self.assertEqual((self.working / "cody2.txt").read_text(encoding="utf-8"), CODY.replace("id=cody", "id=cody2"))
        self.assertTrue(self.voices()["cody2"]["custom"])
        for taken in ("walt", "cody", "cody2"):                     # working or delivered: both taken
            status, payload, _ = self.request("POST", "/api/voices/walt/duplicate", {"newId": taken})
            self.assert_refused(status, payload, 409, "voice_exists")
        self.assert_refused(*self.request("POST", "/api/voices/walt/duplicate", {})[:2], 400, "bad_id")
        self.assert_refused(*self.request("POST", "/api/voices/walt/duplicate", "[1]")[:2], 400, "bad_request")

    def test_delete_custom_but_not_delivered(self):
        (self.working / "mine.txt").write_text("id=mine\n", encoding="utf-8")
        status, payload, _ = self.request("DELETE", "/api/voices/mine")
        self.assertEqual((status, payload["code"]), (200, "voice_deleted"))
        self.assertFalse((self.working / "mine.txt").exists())
        self.assert_refused(*self.request("DELETE", "/api/voices/mine")[:2], 404, "voice_not_found")
        status, payload, _ = self.request("DELETE", "/api/voices/walt")
        self.assert_refused(status, payload, 409, "delivered_voice")
        self.assertIn("remove", payload["message"])
        self.assertIn("restore", payload["message"])
        self.assertTrue((self.working / "walt.txt").exists())

    def test_remove_empties_a_delivered_voice_and_restore_copies_the_mod_version(self):
        """User request 2026-11-16: "recopier du mod" puts the mod's version back at once (the bridge reads it on the
        next request, the game within 30 s), for a removed, modified or outdated copy."""
        status, payload, _ = self.request("POST", "/api/voices/walt/remove")
        self.assertEqual((status, payload["code"]), (200, "voice_removed"))
        self.assertEqual((self.working / "walt.txt").read_bytes(), b"")
        walt = self.voices()["walt"]
        self.assertEqual((walt["removed"], walt["name"]), (True, "Walt Hensley"))
        status, payload, _ = self.request("POST", "/api/voices/walt/restore")
        self.assertEqual((status, payload["code"]), (200, "voice_restored"))
        self.assertEqual((self.working / "walt.txt").read_bytes(), (self.shipped / "walt.txt").read_bytes())
        walt = self.voices()["walt"]
        self.assertEqual((walt["removed"], walt["modified"], walt["outdated"]), (False, False, False))
        self.assertEqual(self.request("POST", "/api/voices/walt/restore")[0], 200)   # already the mod's: same result

    def test_remove_and_restore_refuse_a_custom_voice(self):
        (self.working / "mine.txt").write_text("id=mine\n", encoding="utf-8")
        for action in ("remove", "restore"):
            self.assert_refused(*self.request("POST", f"/api/voices/mine/{action}")[:2], 409, "not_delivered")
        self.assertEqual((self.working / "mine.txt").read_text(encoding="utf-8"), "id=mine\n")

    # --- export, import --------------------------------------------------------------------------------------------
    def test_export_gives_the_sheet_as_attachment(self):
        status, body, resp = self.request("GET", "/api/voices/walt/export")
        self.assertEqual((status, body.decode("utf-8")), (200, WALT))
        self.assertEqual(resp.getheader("Content-Disposition"), 'attachment; filename="walt.txt"')
        self.assert_refused(*self.request("GET", "/api/voices/nobody/export")[:2], 404, "voice_not_found")

    def test_import_new_conflict_and_new_id(self):
        sheet = "format=1\nid=rosa\nname=Rosa\n"
        status, payload, _ = self.request("POST", "/api/import", {"filename": "whatever.txt", "text": sheet})
        self.assertEqual((status, payload["code"], payload["id"]), (201, "voice_imported", "rosa"))
        status, payload, _ = self.request("POST", "/api/import", {"filename": "rosa.txt", "text": sheet})
        self.assert_refused(status, payload, 409, "voice_exists")
        status, payload, _ = self.request("POST", "/api/import", {"filename": "walt.txt", "text": WALT})
        self.assert_refused(status, payload, 409, "voice_exists")
        status, payload, _ = self.request("POST", "/api/import", {"filename": "rosa.txt", "text": sheet,
                                                                  "newId": "rosa_b"})
        self.assertEqual((status, payload["id"]), (201, "rosa_b"))
        self.assertIn("id=rosa_b\n", (self.working / "rosa_b.txt").read_text(encoding="utf-8"))
        status, payload, _ = self.request("POST", "/api/import", {"filename": "noid.txt", "text": "name=X\n"})
        self.assertEqual((status, payload["id"]), (201, "noid"))
        status, payload, _ = self.request("POST", "/api/import", {"filename": "../evil.txt", "text": "name=X\n"})
        self.assertEqual(status, 201)                                # only the stem counts: inside the folder
        self.assertTrue((self.working / "evil.txt").is_file())
        status, payload, _ = self.request("POST", "/api/import", {"filename": "_x.txt", "text": "name=X\n"})
        self.assert_refused(status, payload, 400, "bad_id")
        status, payload, _ = self.request("POST", "/api/import", {"filename": "a.txt"})
        self.assert_refused(status, payload, 400, "bad_request")

    def test_unknown_route(self):
        self.assert_refused(*self.request("POST", "/api/voices/walt/explode")[:2], 404, "not_found")

    def test_local_mode_has_no_login(self):
        """E22-T15: on the loopback the workshop asks no password; the login routes do not exist."""
        self.assert_refused(*self.request("POST", "/api/login", {"password": "x"})[:2], 404, "not_found")
        self.assertIs(self.request("GET", "/api/status")[1]["login"], False)


class NetworkModeTests(unittest.TestCase):
    """E22-T15 (ADR atelier-voix D11): the network gate, served on the loopback here (no firewall prompt in tests): a
    client of the loopback logs in like any other one."""
    PASSWORD = "tablet password 42"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.working = base / "personas"
        self.shipped = base / "shipped"
        self.static = base / "atelier"
        for folder in (self.working, self.shipped, self.static / "i18n"):
            folder.mkdir(parents=True)
        (self.shipped / "walt.txt").write_text(WALT, encoding="utf-8", newline="")
        (self.static / "index.html").write_text("<!doctype html><title>Atelier</title>", encoding="utf-8")
        (self.static / "login.html").write_text("<!doctype html><title>Login</title>", encoding="utf-8")
        (self.static / "i18n" / "en.json").write_text("{}", encoding="utf-8")
        (self.static / "app.js").write_text("// app", encoding="utf-8")
        self.logs: list[str] = []
        gate = atelier.NetworkGate(atelier_auth.Authenticator(self.PASSWORD, self.logs.append))
        self.server = atelier.bind(atelier.VoiceStore(self.working, self.shipped), 0, self.static, None,
                                   self.logs.append, gate=gate)
        self.thread = atelier.start(self.server)
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        joined = "\n".join(self.logs)
        self.assertNotIn(self.PASSWORD, joined)
        self.assertNotIn("wrong guess", joined)
        self.tmp.cleanup()

    request = AtelierServerTests.request
    assert_refused = AtelierServerTests.assert_refused

    def login(self, password=PASSWORD, headers=None):
        return self.request("POST", "/api/login", {"password": password}, headers)

    def cookie(self) -> dict:
        status, payload, resp = self.login()
        self.assertEqual(status, 200, payload)
        return {"Cookie": resp.getheader("Set-Cookie").split(";", 1)[0]}

    def test_everything_but_the_login_page_needs_a_session(self):
        self.assert_refused(*self.request("GET", "/api/voices")[:2], 401, "login_required")
        self.assert_refused(*self.request("PUT", "/api/voices/rosa", "id=rosa\n")[:2], 401, "login_required")
        for path in ("/", "/index.html", "/app.js", "/vendor/../index.html"):
            status, _, resp = self.request("GET", path)
            self.assertEqual(status, 303, path)
            self.assertEqual(resp.getheader("Location"), "/login.html", path)
        for path in ("/login.html", "/i18n/en.json"):
            self.assertEqual(self.request("GET", path)[0], 200, path)
        self.assertFalse((self.working / "rosa.txt").exists())

    def test_login_sets_a_strict_session_cookie(self):
        status, payload, resp = self.login()
        self.assertEqual(status, 200, payload)
        self.assertEqual(payload["code"], "logged_in")
        cookie = resp.getheader("Set-Cookie")
        name_value, *attributes = [part.strip() for part in cookie.split(";")]
        self.assertTrue(name_value.startswith(atelier.SESSION_COOKIE + "="))
        self.assertGreaterEqual(len(name_value.split("=", 1)[1]), 40)
        self.assertEqual(set(attributes), {"HttpOnly", "SameSite=Strict", "Path=/", "Max-Age=604800"})
        headers = {"Cookie": name_value}
        self.assertEqual(self.request("GET", "/api/voices", headers=headers)[0], 200)
        self.assertEqual(self.request("GET", "/", headers=headers)[0], 200)
        self.assertIs(self.request("GET", "/api/status", headers=headers)[1]["login"], True)
        self.assertIn("Voice workshop: login from 127.0.0.1", self.logs)

    def test_wrong_password_then_locked(self):
        for _ in range(5):
            self.assert_refused(*self.login("wrong guess")[:2], 401, "bad_password")
        status, payload, resp = self.login()
        self.assert_refused(status, payload, 429, "login_locked")
        self.assertEqual(payload["retryAfter"], 60)
        self.assertEqual(resp.getheader("Retry-After"), "60")
        self.assertEqual(sum(line == "Voice workshop: failed login from 127.0.0.1" for line in self.logs), 5)
        self.assertTrue(any("locked for 60 s" in line for line in self.logs))

    def test_forged_cookie_is_refused(self):
        self.assert_refused(*self.request("GET", "/api/voices", headers={
            "Cookie": atelier.SESSION_COOKIE + "=forged"})[:2], 401, "login_required")

    def test_logout_ends_the_session(self):
        headers = self.cookie()
        status, payload, resp = self.request("POST", "/api/logout", {}, headers)
        self.assertEqual(status, 200, payload)
        self.assertIn("Max-Age=0", resp.getheader("Set-Cookie"))
        self.assert_refused(*self.request("GET", "/api/voices", headers=headers)[:2], 401, "login_required")
        self.assertIn("Voice workshop: logout from 127.0.0.1", self.logs)

    def test_any_host_but_only_its_own_origin(self):
        headers = {**self.cookie(), "Host": f"192.168.1.20:{self.port}"}
        status, payload, _ = self.request("PUT", "/api/voices/rosa", "id=rosa\n",
                                          {**headers, "Origin": "http://evil.example"})
        self.assert_refused(status, payload, 403, "forbidden_origin")
        self.assertFalse((self.working / "rosa.txt").exists())
        self.assert_refused(*self.login(headers={"Origin": "http://evil.example"})[:2], 403, "forbidden_origin")
        status, payload, _ = self.request("PUT", "/api/voices/rosa", "id=rosa\n",
                                          {**headers, "Origin": f"http://192.168.1.20:{self.port}"})
        self.assertEqual(status, 201, payload)
        self.assertEqual(self.request("GET", "/api/voices", headers=headers)[0], 200)


class BindTests(unittest.TestCase):
    def test_busy_port_moves_to_the_next_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = atelier.VoiceStore(Path(tmp) / "w", Path(tmp) / "s")
            first = atelier.bind(store, 0, log=lambda m: None)
            try:
                second = atelier.bind(store, first.server_address[1], log=lambda m: None)
                try:
                    self.assertEqual(second.server_address[0], "127.0.0.1")
                    self.assertGreater(second.server_address[1], first.server_address[1])
                finally:
                    second.server_close()
            finally:
                first.server_close()

    def test_launch_opens_the_browser_on_the_loopback(self):
        opened = []
        with tempfile.TemporaryDirectory() as tmp:
            sock = socket.socket()
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
            sock.close()
            server, thread = atelier.launch(Path(tmp) / "w", Path(tmp) / "s", port, lambda m: None, opened.append)
            server.shutdown()
            server.server_close()
            thread.join(5)
        self.assertEqual(len(opened), 1)
        self.assertTrue(opened[0].startswith("http://127.0.0.1:"))

    def test_network_mode_refuses_to_start_without_a_good_password(self):
        """E22-T15: any address but the loopback needs ATELIER_PASSWORD (10 characters at least); nothing is bound."""
        with tempfile.TemporaryDirectory() as tmp:
            for password in (None, "", "too-short"):
                opened = []
                with self.assertRaises(atelier.StartRefused) as caught:
                    atelier.launch(Path(tmp) / "w", Path(tmp) / "s", 0, lambda m: None, opened.append,
                                   host="0.0.0.0", password=password)
                self.assertIn("ATELIER_PASSWORD", str(caught.exception))
                self.assertEqual(opened, [])

    def test_gate_follows_the_host(self):
        for host in ("127.0.0.1", "localhost", "::1", "127.0.0.2"):
            self.assertIsInstance(atelier.gate_for(host, None, print), atelier.LocalGate, host)
        for host in ("0.0.0.0", "192.168.1.20", "::", "mypc.lan"):
            self.assertIsInstance(atelier.gate_for(host, "long enough password", print), atelier.NetworkGate, host)


class BridgeWiringTests(unittest.TestCase):
    def test_bridge_folders_feed_the_workshop(self):
        """The workshop writes where the game reads (personas_folder of the default exchange), not in the mod."""
        folder = rb.personas_folder(rb.DEFAULT_EXCHANGE)
        self.assertEqual(folder.parts[-2:], ("batman_RadioSurvivor", "personas"))
        self.assertTrue((rb.BUNDLED_PERSONAS / "walt.txt").is_file())
        self.assertIn("modversion", (rb.BUNDLED_PERSONAS.parent / "mod.info").read_text(encoding="utf-8"))
        self.assertIsNotNone(atelier.mod_version(rb.BUNDLED_PERSONAS))


if __name__ == "__main__":
    unittest.main()
