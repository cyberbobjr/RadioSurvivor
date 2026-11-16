"""E22-T04, E22-T10: the game's verdict and the live journal of the voice workshop (ADR atelier-voix D03, D09).

    python RadioSurvivor/tests/test_atelier_log.py

- bridge/log_buffer.py: bounds of the ring buffer, `since`, thread safety;
- radio_bridge.log: every line also goes to the buffer, with its level and the voice its fixed format names (never a
  voice quoted in a player's text);
- bridge/game_console.py over the fixture tests/fixtures/atelier/console.txt: persona lines read, refusal then fix,
  file rewritten at game start or cut, missing file, last line without its line break, sheet text changed;
- the routes GET /api/verdicts and GET /api/log of a real server on 127.0.0.1;
- sheet.js `locate` and verdict.js `plainReason` in node (skipped without node).
No game, no browser.
"""
from __future__ import annotations

import contextlib
import http.client
import io
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
sys.path.insert(0, str(ROOT / "tests"))
import atelier_server as atelier  # noqa: E402
import game_console  # noqa: E402
import log_buffer  # noqa: E402
import radio_bridge as rb  # noqa: E402
from test_atelier_ui import NODE, module_url, run_node  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "atelier" / "console.txt"
PREFIX = "LOG  : General      f:0> [batman_RadioSurvivor]     [RadioSurvivor] personas: "
CODY = "format=1\nid=cody\nname=Cody\nfrequency=146\n[prompt]\nYou are Cody.\n"


def persona(message: str) -> str:
    return PREFIX + message + "\n"


class LogBufferTests(unittest.TestCase):
    def test_bounded_and_numbered_without_gap(self):
        buf = log_buffer.LogBuffer(capacity=5, clock=lambda: 12.5)
        for index in range(8):
            buf.append(f"line {index}")
        entries, last = buf.since(0)
        self.assertEqual(last, 8)
        self.assertEqual([e["seq"] for e in entries], [4, 5, 6, 7, 8])
        self.assertEqual(entries[0], {"seq": 4, "time": 12.5, "level": "info", "source": "bridge",
                                      "text": "line 3", "voice": None})

    def test_since_gives_the_new_entries_only(self):
        buf = log_buffer.LogBuffer(capacity=5)
        for index in range(8):
            buf.append(f"line {index}")
        self.assertEqual([e["seq"] for e in buf.since(6)[0]], [7, 8])
        self.assertEqual(buf.since(8), ([], 8))
        self.assertEqual([e["seq"] for e in buf.since(2)[0]], [4, 5, 6, 7, 8], "dropped lines are gone")
        self.assertEqual(len(buf.since(100)[0]), 5, "a cursor of an older bridge run gives everything kept")
        self.assertEqual(log_buffer.LogBuffer().since(0), ([], 0))

    def test_unknown_level_and_long_text(self):
        buf = log_buffer.LogBuffer()
        entry = buf.append("x" * (log_buffer.MAX_TEXT + 50), level="loud")
        self.assertEqual(entry["level"], "info")
        self.assertTrue(entry["text"].endswith(" [...]"))
        self.assertEqual(len(entry["text"]), log_buffer.MAX_TEXT + len(" [...]"))

    def test_thread_safe(self):
        buf = log_buffer.LogBuffer(capacity=100)
        threads = [threading.Thread(target=lambda: [buf.append("x") for _ in range(500)]) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        entries, last = buf.since(0)
        self.assertEqual(last, 4000)
        self.assertEqual([e["seq"] for e in entries], list(range(3901, 4001)))


class BridgeLogTests(unittest.TestCase):
    def setUp(self):
        self.saved = rb.LOG_BUFFER
        rb.LOG_BUFFER = log_buffer.LogBuffer()

    def tearDown(self):
        rb.LOG_BUFFER = self.saved

    def logged(self, *messages: str) -> list[tuple[str, str | None]]:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            for message in messages:
                rb.log(message)
        self.assertEqual(len(out.getvalue().splitlines()), len(messages), "the terminal still shows every line")
        return [(e["level"], e["voice"]) for e in rb.LOG_BUFFER.since(0)[0]]

    def test_voice_named_by_the_fixed_formats(self):
        self.assertEqual(self.logged(
            "Bob -> walt : hello there",
            "reply of voice 'walt': Copy that. / Over.",
            "general call of voice cody",
            "evening bulletin of voice ezra",
            "voice 'boone': action 1 dropped, unknown type 'fly'",
            "voice sheet C:\\Zomboid\\Lua\\batman_RadioSurvivor\\personas\\delphine.txt refused, line 3: bad key 'Radio'",
            "[DEBUG] reply of voice 'walt': debug copy",
        ), [("info", "walt"), ("info", "walt"), ("info", "cody"), ("info", "ezra"),
            ("info", "boone"), ("error", "delphine"), ("debug", "walt")])

    def test_player_text_is_never_searched(self):
        self.assertEqual(self.logged(
            "Bob -> 42 : tell voice 'walt' hi -> cody : over",      # an NPC id, then words of the player
            "Bob -> walt : the reply of voice 'cody': x",
            "Exchange directory: C:\\Zomboid\\Lua\\batman_CoreAI",
            "LLM error (r12, timeout): read timed out",
            "Expired request ignored (r3, 80s)",
        ), [("info", None), ("info", "walt"), ("info", None), ("error", None), ("warning", None)])

    def test_spoken_text_of_answers(self):
        self.assertEqual(rb.spoken_text(["One.", "Two."]), "One. / Two.")
        self.assertEqual(rb.spoken_text({"say": ["Hi."], "actions": []}), "Hi.")
        self.assertEqual(rb.spoken_text([]), "")
        self.assertEqual(rb.spoken_text({"kind": "npc_reply"}), "")

    def test_game_log_next_to_the_lua_folder(self):
        self.assertEqual(rb.game_log_file(Path("C:/Users/x/Zomboid/Lua/batman_CoreAI")),
                         Path("C:/Users/x/Zomboid/console.txt"))
        self.assertEqual(rb.game_log_file(Path("/srv/cache/Lua/batman_CoreAI/sub")), Path("/srv/cache/console.txt"))
        self.assertIsNone(rb.game_log_file(Path("/tmp/exchange")))


class GameConsoleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.console = Path(self.tmp.name) / "console.txt"
        self.sheets = {"cody": CODY, "walt": "walt sheet\n"}
        self.journal = log_buffer.LogBuffer()
        self.now = [100.0]
        self.game = game_console.GameConsole(self.console, self.journal, clock=lambda: self.now[0])

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text: str, mode: str = "w") -> None:
        with self.console.open(mode, encoding="utf-8", newline="") as handle:
            handle.write(text)

    def verdicts(self) -> dict:
        self.game.refresh()
        return self.game.verdicts(self.sheets.get)

    def test_fixture_lines_journal_and_verdicts(self):
        self.write(FIXTURE.read_text(encoding="utf-8"))
        verdicts = self.verdicts()
        self.assertEqual(verdicts, {
            "cody": {"state": "refused", "line": 5, "reason": "bad frequency '146' (MHz with one decimal, e.g. 145.0)",
                     "time": 100.0},
            "walt": {"state": "refused", "line": 9, "reason": "unknown key 'colour'", "time": 100.0},
        })
        entries = self.journal.since(0)[0]
        self.assertEqual(len(entries), 7, "every persona line, no other line")
        self.assertTrue(all(e["source"] == "game" and e["text"].startswith("personas: ") for e in entries))
        self.assertEqual([(e["level"], e["voice"]) for e in entries], [
            ("info", "walt"), ("info", "walt"), ("error", "cody"), ("warning", "ezra"), ("error", None),
            ("error", "gen1"), ("error", "walt")])

    def test_refusal_older_than_the_sheet_is_not_shown(self):
        """User report 2026-11-15: a sheet restored (or rewritten) after the game's last console line keeps no stale
        refusal, even when the game is closed and the console never changes again."""
        import os
        self.write(persona("ERROR: batman_RadioSurvivor/personas/walt.txt refused, line 23: unknown key 'place'"))
        os.utime(self.console, (1000.0, 1000.0))
        self.game.refresh()
        older = {"walt": 900.0}
        self.assertEqual(self.game.verdicts(self.sheets.get, older.get)["walt"]["state"], "refused")
        newer = {"walt": 1100.0}
        self.assertEqual(self.game.verdicts(self.sheets.get, newer.get)["walt"]["state"], "changed")
        self.assertEqual(self.game.verdicts(self.sheets.get, {}.get)["walt"]["state"], "changed",
                         "working sheet deleted (restored): the game copies the delivered one again")

    def test_refused_then_fixed(self):
        self.write(persona("ERROR: batman_RadioSurvivor/personas/cody.txt refused, line 5: bad frequency '146'"))
        self.assertEqual(self.verdicts()["cody"]["state"], "refused")
        self.sheets["cody"] = CODY.replace("146", "146.0")
        self.assertEqual(self.verdicts()["cody"]["state"], "changed", "the text changed: waiting for the game")
        self.now[0] = 130.0
        self.write(persona("voice 'cody' loaded: state active, frequencies 146.0"), "a")
        self.assertEqual(self.verdicts()["cody"], {"state": "loaded", "line": None, "reason": None, "time": 130.0})

    def test_updated_and_removed_end_a_refusal(self):
        self.write(persona("ERROR: batman_RadioSurvivor/personas/cody.txt refused, line 1: x")
                   + persona("INFO: voice 'cody' updated to the delivered version (Zomboid/Lua/x/cody.txt)")
                   + persona("ERROR: batman_RadioSurvivor/personas/walt.txt refused, line 2: y")
                   + persona("voice 'walt' removed (empty file)"))
        verdicts = self.verdicts()
        self.assertEqual((verdicts["cody"]["state"], verdicts["walt"]["state"]), ("loaded", "removed"))

    def test_missing_file_then_created(self):
        self.assertEqual(self.verdicts(), {})
        self.assertFalse(self.game.found)
        self.write(persona("ERROR: batman_RadioSurvivor/personas/cody.txt refused, line 5: bad"))
        self.assertTrue(self.game.found)
        self.assertEqual(self.verdicts()["cody"]["line"], 5)

    def test_line_without_its_break_waits(self):
        line = persona("ERROR: batman_RadioSurvivor/personas/cody.txt refused, line 5: bad")
        self.write(line[:40])
        self.assertEqual(self.verdicts(), {})
        self.write(line[40:], "a")
        self.assertEqual(self.verdicts()["cody"]["reason"], "bad")
        self.assertEqual(len(self.journal.since(0)[0]), 1)

    def test_rewritten_at_game_start(self):
        self.write("LOG  : General      f:0> session one, a long first line of the console of the game\n"
                   + persona("ERROR: batman_RadioSurvivor/personas/cody.txt refused, line 5: bad") * 3)
        self.assertEqual(self.verdicts()["cody"]["state"], "refused")
        # New session, longer than the old file: the start differs, read again from the start.
        self.write("LOG  : General      f:0> session two\n" + persona("voice 'walt' loaded: state active") * 6)
        self.assertEqual(self.verdicts()["walt"]["state"], "loaded")
        self.assertEqual(self.verdicts()["cody"]["state"], "refused", "kept until the game says otherwise")
        # Cut shorter than what was read: read again from the start.
        self.write(persona("voice 'cody' loaded: state active"))
        self.assertEqual(self.verdicts()["cody"]["state"], "loaded")
        self.assertEqual(len(self.journal.since(0)[0]), 3 + 6 + 1)

    def test_persona_message_and_events(self):
        self.assertIsNone(game_console.persona_message("[RadioSurvivor] mission: x"))
        self.assertEqual(game_console.sheet_event(
            "ERROR: batman_RadioSurvivor/personas/walt.txt refused, line 7: duplicate key 'name' (first set on line 3)."),
            ("walt", "refused", 7, "duplicate key 'name' (first set on line 3)"))
        self.assertEqual(game_console.sheet_event("ERROR: batman_RadioSurvivor/personas/walt.txt refused, cannot read"),
                         ("walt", "refused", None, "cannot read"))
        self.assertIsNone(game_console.sheet_event("WARNING: voice 'walt' modified by the admin, x"))


class LiveRoutesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.working, shipped = base / "Lua" / "batman_RadioSurvivor" / "personas", base / "mod" / "personas"
        self.working.mkdir(parents=True)
        shipped.mkdir(parents=True)
        (self.working / "cody.txt").write_text(CODY, encoding="utf-8", newline="")
        self.console = base / "console.txt"
        self.console.write_text(FIXTURE.read_text(encoding="utf-8"), encoding="utf-8", newline="")
        self.journal = log_buffer.LogBuffer()
        self.running = threading.Event()
        live = atelier.Live(self.journal, game_console.GameConsole(self.console, self.journal), self.running.is_set)
        self.server = atelier.bind(atelier.VoiceStore(self.working, shipped), 0, base, None, lambda m: None, live=live)
        atelier.start(self.server)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def get(self, path: str) -> tuple[int, dict]:
        conn = http.client.HTTPConnection(atelier.HOST, self.server.server_address[1], timeout=10)
        conn.request("GET", path)
        resp = conn.getresponse()
        payload = json.loads(resp.read())
        conn.close()
        return resp.status, payload

    def test_verdicts_route(self):
        status, payload = self.get("/api/verdicts")
        self.assertEqual(status, 200)
        self.assertEqual(payload["gameLog"], str(self.console))
        self.assertTrue(payload["gameLogFound"])
        self.assertEqual(payload["verdicts"]["cody"]["state"], "refused")
        self.assertEqual(payload["verdicts"]["cody"]["line"], 5)
        conn = http.client.HTTPConnection(atelier.HOST, self.server.server_address[1], timeout=10)
        conn.request("PUT", "/api/voices/cody", body=CODY.replace("146", "146.0").encode("utf-8"))
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()
        self.assertEqual(self.get("/api/verdicts")[1]["verdicts"]["cody"]["state"], "changed")

    def test_log_route_since_and_bridge_state(self):
        self.journal.append("Bob -> cody : hello", "bridge", "info", "cody")
        status, payload = self.get("/api/log?since=0")
        self.assertEqual(status, 200)
        self.assertFalse(payload["bridge"])
        self.assertEqual(payload["last"], 8)
        self.assertEqual([e["source"] for e in payload["entries"]], ["bridge"] + ["game"] * 7)
        self.running.set()
        self.journal.append("reply of voice 'cody': Hi.", "bridge", "info", "cody")
        status, payload = self.get("/api/log?since=8")
        self.assertTrue(payload["bridge"])
        self.assertEqual([(e["seq"], e["text"]) for e in payload["entries"]], [(9, "reply of voice 'cody': Hi.")])
        self.assertEqual(self.get("/api/log?since=abc")[0], 400)

    def test_without_live_sources(self):
        server = atelier.bind(atelier.VoiceStore(self.working, self.working), 0, self.working, None, lambda m: None)
        atelier.start(server)
        try:
            conn = http.client.HTTPConnection(atelier.HOST, server.server_address[1], timeout=10)
            conn.request("GET", "/api/log")
            payload = json.loads(conn.getresponse().read())
            conn.request("GET", "/api/verdicts")
            verdicts = json.loads(conn.getresponse().read())
            conn.close()
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual((payload["entries"], payload["last"], payload["bridge"], payload["gameLog"]), ([], 0, False, None))
        self.assertEqual(verdicts["verdicts"], {})


@unittest.skipUnless(NODE, "node is not installed")
class PageModulesTests(unittest.TestCase):
    def test_locate_and_plain_reason(self):
        sheet_text = ("# comment\nformat=1\nid=x\n\nfrequency=145\n[place mill]\nat=1,2,0\n"
                      "[mission m1]\ntype=deliver\n[prompt]\nYou are X.\n")
        script = f"""
import * as sheet from '{module_url('sheet.js')}';
import {{ plainReason }} from '{module_url('verdict.js')}';
const text = {json.dumps(sheet_text)};
const t = (key, args = {{}}) => `${{key}}|${{args.name ?? ''}}`;
console.log(JSON.stringify({{
  lines: [1, 2, 4, 5, 6, 7, 9, 11, 99].map((n) => sheet.locate(text, n)),
  reasons: ["unknown key 'colour'", "bad frequency '145' (MHz with one decimal, e.g. 145.0)",
            "unknown place 'mill'", "something new"].map((r) => plainReason(t, r)),
}}));
"""
        got = run_node(script)
        head = lambda field: {"block": "head", "id": None, "field": field}  # noqa: E731
        self.assertEqual(got["lines"], [
            head(None), head("format"), head(None), head("frequency"),
            {"block": "place", "id": "mill", "field": None}, {"block": "place", "id": "mill", "field": "at"},
            {"block": "mission", "id": "m1", "field": "type"}, {"block": "prompt", "id": None, "field": None},
            {"block": "prompt", "id": None, "field": None}])
        self.assertEqual(got["reasons"], ["verdict.why.unknown_key|colour", "verdict.why.frequency|",
                                          "verdict.why.unknown_ref|mill", "verdict.why.other|"])


if __name__ == "__main__":
    unittest.main()
