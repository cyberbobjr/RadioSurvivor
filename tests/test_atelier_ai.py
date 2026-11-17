"""E22-T06: the bridge's LLM helps to write a voice in the workshop (ADR atelier-voix D04).

    python RadioSurvivor/tests/test_atelier_ai.py

A real workshop server on 127.0.0.1 (port 0) whose AI is built by radio_bridge.workshop_ai over the deterministic fake
LLM (tools/fake_llm, port 0): POST /api/ai/personality, /api/ai/suggest and /api/ai/try answer; without configuration
or offline the routes answer 503 ai_unavailable and no call is made; the bridge's prompt cap refuses an oversized
request before any call (prompt_too_large); /api/ai/suggest (E24-T04) fills one field of the page from the whole
unsaved sheet, in the voice's or the page's language, the frequency mark `{frequency}` turned into %1; /api/ai/try
builds the voice prompt with radio_bridge.voice_turn from the UNSAVED text of the page; the token usage journal marks
the calls source=workshop; no file of the working folder changes. No paid LLM, no .env read, no game.
"""
from __future__ import annotations

import http.client
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
sys.path.insert(0, str(ROOT / "tests"))
import atelier_ai  # noqa: E402
import atelier_server as atelier  # noqa: E402
import persona_store  # noqa: E402
import radio_bridge as rb  # noqa: E402
from test_fake_llm import start_fake, stop  # noqa: E402
import fake_llm  # noqa: E402  (tools/fake_llm, put on the path by test_fake_llm)

SAVED = "format=1\nid=zed\nname=Zed Moore\nfrequency=146.0\n[prompt]\nYou are Zed, the saved version.\n"
UNSAVED = "format=1\nid=zed\nname=Zed Moore\nfrequency=146.0\n[prompt]\nYou are Zed. UNSAVED-MARK-42.\n"


def snapshot(folder: Path) -> dict[str, tuple[bytes, int]]:
    return {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in sorted(folder.iterdir())}


class WorkshopAiRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fake_log = Path(tempfile.gettempdir()) / f"fake-atelier-ai-{id(cls)}.jsonl"
        cls.fake, cls.port = start_fake("--log", str(cls.fake_log))

    @classmethod
    def tearDownClass(cls):
        stop(cls.fake)
        cls.fake_log.unlink(missing_ok=True)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.working, shipped = base / "personas", base / "mod"
        self.working.mkdir()
        shipped.mkdir()
        (self.working / "zed.txt").write_text(SAVED, encoding="utf-8", newline="")
        self.lines: list[str] = []
        self.sent: list[list[dict]] = []
        self.saved = (rb.log, rb.call_llm, rb.TOKEN_USAGE)
        rb.log = self.lines.append
        real_call = rb.call_llm

        def spy(config, messages, speaker="Walt", json_mode=False):
            self.sent.append(messages)
            return real_call(config, messages, speaker, json_mode)
        rb.call_llm = spy
        rb.TOKEN_USAGE = rb.TokenUsageLog(base / "usage" / "token_usage.jsonl")
        self.config = {"OPENAI_BASE_URL": f"http://127.0.0.1:{self.port}/v1", "OPENAI_MODEL": "fake",
                       "OPENAI_KEY": "fake", "LLM_MAX_TOKENS": 1000, "LLM_MAX_PROMPT_CHARS": 16000}
        self.server = self.serve(rb.workshop_ai(self.config))
        self.before = snapshot(self.working)

    def serve(self, ai):
        server = atelier.bind(atelier.VoiceStore(self.working, self.working.parent / "mod"), 0,
                              self.working.parent, None, lambda m: None, live=atelier.Live(ai=ai))
        atelier.start(server)
        return server

    def tearDown(self):
        rb.log, rb.call_llm, rb.TOKEN_USAGE = self.saved
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def post(self, kind: str, body: dict, server=None) -> tuple[int, dict]:
        server = server or self.server
        conn = http.client.HTTPConnection(atelier.HOST, server.server_address[1], timeout=30)
        conn.request("POST", f"/api/ai/{kind}", body=json.dumps(body).encode("utf-8"),
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        payload = json.loads(resp.read())
        conn.close()
        return resp.status, payload

    def usage(self) -> list[dict]:
        return [json.loads(line) for line in rb.TOKEN_USAGE.path.read_text(encoding="utf-8").splitlines()]

    def test_personality(self):
        status, payload = self.post("personality", {"voiceId": "zed", "name": "Zed Moore",
                                                    "description": "Un vieux mécanicien qui répare des radios."})
        self.assertEqual((status, payload["ok"]), (200, True), payload)
        self.assertTrue(payload["prompt"].startswith("You are Zed Moore"), payload["prompt"])
        system, user = (m["content"] for m in self.sent[0])
        self.assertTrue(system.startswith("Workshop task: personality."))
        self.assertIn("Un vieux mécanicien", user)
        self.assertIn("workshop AI personality for voice 'zed'", self.lines)
        self.assertEqual(rb.bridge_line("workshop AI personality for voice 'zed'"), ("info", "zed"))
        self.assertEqual([e.get("source") for e in self.usage()], ["workshop"])
        self.assertEqual(snapshot(self.working), self.before)

    def suggest(self, field: str, **body) -> tuple[int, dict]:
        return self.post("suggest", {"field": field, "voiceId": "zed", "sheetText": UNSAVED, **body})

    def test_suggest_sends_the_whole_unsaved_sheet_details_and_current_text(self):
        status, payload = self.suggest("mission_story", pageLanguage="en", current="Bring me food.",
                                       details={"mission_type": "Deliver", "target_place": "the shed"})
        self.assertEqual((status, payload["ok"], payload["code"]), (200, True, "ok"), payload)
        self.assertEqual(payload["text"], fake_llm.WORKSHOP_SUGGEST_TEXTS["mission_story"])
        system, user = (m["content"] for m in self.sent[0])
        self.assertTrue(system.startswith("Workshop task: suggest."), system)
        self.assertIn("Knox Event", system)
        self.assertIn("first person", system)          # task lines of the mission_story entry
        self.assertIn("at most 200 characters", system)
        self.assertIn("Field to fill: mission_story", user)
        self.assertIn("UNSAVED-MARK-42", user)
        self.assertIn("- mission_type: Deliver", user)
        self.assertIn("- target_place: the shed", user)
        self.assertIn('Text in the field now: "Bring me food."', user)
        self.assertIn("workshop AI suggest mission_story for voice 'zed'", self.lines)
        self.assertEqual(self.usage()[0]["source"], "workshop")
        self.assertEqual(snapshot(self.working), self.before)

    def test_suggest_author_text_is_data(self):
        status, payload = self.suggest("description", current="{voice} {0} }{", details={"x": "{field}"})
        self.assertEqual(status, 200, payload)
        user = self.sent[0][1]["content"]
        self.assertIn('Text in the field now: "{voice} {0} }{"', user)
        self.assertIn("- x: {field}", user)
        self.assertIn("Details of what this field is for:\n- x: {field}", user)
        self.suggest("description")
        self.assertIn("Details of what this field is for:\n- (none)", self.sent[1][1]["content"])
        self.assertNotIn("Text in the field now", self.sent[1][1]["content"])

    def test_suggest_language_from_the_sheet_or_the_page(self):
        french_sheet = UNSAVED.replace("name=Zed Moore\n", "name=Zed Moore\nlanguage=fr\n")
        self.suggest("mission_story", sheetText=french_sheet, pageLanguage="en")
        self.assertIn("Write in French", self.sent[-1][0]["content"])
        self.suggest("place_label", pageLanguage="fr")
        self.assertIn("Write in English", self.sent[-1][0]["content"])
        self.suggest("description", pageLanguage="fr")
        self.assertIn("Write in French", self.sent[-1][0]["content"])
        self.assertIn("Page language of the author: French", self.sent[-1][1]["content"])
        self.suggest("paquet_name", sheetText=french_sheet)
        self.assertIn("Write in English", self.sent[-1][0]["content"])

    def test_suggest_frequency_mark(self):
        status, payload = self.suggest("call")
        self.assertEqual(status, 200, payload)
        self.assertIn("{frequency}", self.sent[0][0]["content"])
        self.assertEqual(payload["text"], fake_llm.WORKSHOP_SUGGEST_TEXTS["call"].replace("{frequency}", "%1"))
        status, payload = self.suggest("note_line")
        self.assertEqual(status, 200, payload)
        self.assertIn("%1", payload["text"])
        self.assertLessEqual(len(payload["text"].encode("utf-8")), 40)

    def test_suggest_name_without_sheet_other_fields_need_it(self):
        status, payload = self.post("suggest", {"field": "name", "details": {"voice_type": "A medic"}})
        self.assertEqual(status, 200, payload)
        self.assertEqual(payload["text"], fake_llm.WORKSHOP_SUGGEST_TEXTS["name"])
        system, user = (m["content"] for m in self.sent[0])
        self.assertIn("Write in English", system)
        self.assertIn("(no sheet yet: the voice is being created)", user)
        self.assertIn("workshop AI suggest name for voice 'new'", self.lines)
        for body in ({"field": "description"}, {"field": "call", "sheetText": "  "},
                     {"field": "nope", "sheetText": UNSAVED}, {"field": "name", "voiceId": "Bad Id"},
                     {"field": "name", "pageLanguage": "de"}, {"field": "name", "current": 3},
                     {"field": "name", "details": ["a"]}, {"field": "name", "details": {"Bad": "x"}},
                     {"field": "name", "details": {"k": 1}}, {"field": "name", "details": {"k": "x" * 601}},
                     {"field": "name", "details": {f"k{'_' * i}": "x" for i in range(17)}}):
            status, payload = self.post("suggest", body)
            self.assertEqual((status, payload["code"]), (400, "bad_request"), body)
        self.assertEqual(len(self.sent), 1)

    def scripted(self, answer: str):
        """A server whose AI answers `answer` to every request (shaping and checks of the real WorkshopAI)."""
        return self.serve(atelier_ai.WorkshopAI(lambda messages: answer, None, self.lines.append))

    def test_suggest_without_frequency_mark_fails(self):
        server = self.scripted("Tune in tonight, I will be there.")
        try:
            status, payload = self.post("suggest", {"field": "call", "sheetText": UNSAVED}, server)
            self.assertEqual((status, payload["code"]), (502, "ai_no_frequency"))
            status, payload = self.post("suggest", {"field": "mission_state", "sheetText": UNSAVED}, server)
            self.assertEqual((status, payload["text"]), (200, "Tune in tonight, I will be there."))
        finally:
            server.shutdown()
            server.server_close()

    def test_suggest_note_cut_at_40_bytes_and_cleaned(self):
        server = self.scripted('"Écoutez <{frequency}> chaque ^soir, après 100% le coucher du soleil."')
        try:
            status, payload = self.post("suggest", {"field": "note_line", "sheetText": UNSAVED}, server)
            self.assertEqual(status, 200, payload)
            self.assertEqual(payload["text"], "Écoutez %1 chaque soir, après 100 le")
            self.assertLessEqual(len(payload["text"].encode("utf-8")), 40)
            server2 = self.scripted("   \n")
            try:
                status, payload = self.post("suggest", {"field": "name"}, server2)
                self.assertEqual((status, payload["code"]), (502, "ai_failed"))
            finally:
                server2.shutdown()
                server2.server_close()
        finally:
            server.shutdown()
            server.server_close()

    def test_try_uses_the_unsaved_text_and_the_bridge_prompt(self):
        history = [{"role": "user", "content": "Hello [Caller 7]?"}, {"role": "assistant", "content": "Zed here. Over."}]
        status, payload = self.post("try", {"voiceId": "zed", "sheetText": UNSAVED, "history": history,
                                            "text": "Who are you?"})
        self.assertEqual(status, 200, payload)
        self.assertTrue(payload["lines"] and all(len(line) <= rb.MAX_LINE_CHARS for line in payload["lines"]))
        messages = self.sent[0]
        sheet = persona_store.parse_bytes(UNSAVED.encode("utf-8"), "zed")
        req = dict(rb.WORKSHOP_REQUEST, text="Who are you?", voice="zed")
        # E22-T13: every voice has remember, so the game prompt (and this one) ends with the reply format.
        jobs = rb.voice_jobs(req)
        self.assertEqual(messages[0]["content"], rb.system_prompt(req, rb.WORKSHOP_TAG, rb.voice_prompt(sheet))
                         + rb.actions_prompt(sheet, jobs))
        self.assertIn("UNSAVED-MARK-42", messages[0]["content"])
        self.assertNotIn("the saved version", messages[0]["content"])
        self.assertEqual(messages[1:], [{"role": "user", "content": "[Caller 1] Hello (Caller 7)?"},
                                        {"role": "assistant", "content": "Zed here. Over."},
                                        {"role": "user", "content": "[Caller 1] Who are you?"
                                         + rb.format_reminder(sheet, jobs)}])
        self.assertIn("workshop AI try for voice 'zed'", self.lines)
        self.assertEqual(self.usage()[0]["source"], "workshop")
        self.assertEqual(snapshot(self.working), self.before)

    def test_try_refuses_an_invalid_sheet_without_call(self):
        status, payload = self.post("try", {"voiceId": "zed", "sheetText": "format=1\nid=zed\n", "text": "Hi"})
        self.assertEqual((status, payload["code"]), (422, "sheet_refused"))
        status, payload = self.post("try", {"voiceId": "Bad Id", "sheetText": UNSAVED, "text": "Hi"})
        self.assertEqual((status, payload["code"]), (400, "bad_request"))
        self.assertEqual(self.sent, [])

    def test_oversized_request_refused_by_the_bridge_cap(self):
        calls_before = len(self.fake_log.read_text(encoding="utf-8").splitlines()) if self.fake_log.is_file() else 0
        status, payload = self.post("personality", {"voiceId": "zed", "description": "x" * 20000})
        self.assertEqual((status, payload["code"]), (413, "prompt_too_large"))
        calls_after = len(self.fake_log.read_text(encoding="utf-8").splitlines()) if self.fake_log.is_file() else 0
        self.assertEqual(calls_after, calls_before, "never sent to the provider")
        status, payload = self.post("try", {"voiceId": "zed", "text": "Hi",
                                            "sheetText": UNSAVED.replace("UNSAVED-MARK-42.", "y" * 20000)})
        self.assertEqual((status, payload["code"]), (413, "prompt_too_large"))
        self.assertEqual(snapshot(self.working), self.before)

    def test_unavailable_without_configuration_or_offline(self):
        self.assertIsNone(rb.workshop_ai(None))
        self.assertIsNone(rb.workshop_ai({"OFFLINE": "1", "OPENAI_MODEL": "offline"}))
        server = self.serve(None)
        try:
            for kind in ("personality", "suggest", "try"):
                status, payload = self.post(kind, {"voiceId": "zed", "description": "x", "text": "Hi",
                                                   "sheetText": UNSAVED, "field": "name"}, server)
                self.assertEqual((status, payload["ok"], payload["code"]), (503, False, "ai_unavailable"))
                self.assertIn(".env", payload["message"])
            conn = http.client.HTTPConnection(atelier.HOST, server.server_address[1], timeout=10)
            conn.request("GET", "/api/status")
            self.assertFalse(json.loads(conn.getresponse().read())["ai"])
            conn.close()
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(self.sent, [])
        status, payload = self.post("unknown", {})
        self.assertEqual((status, payload["code"]), (404, "not_found"))


class AnswerShapes(unittest.TestCase):
    def test_one_sentence(self):
        self.assertEqual(atelier_ai.one_sentence('"Bring me the medicine. Over."\nSecond line', 200),
                         "Bring me the medicine. Over.")
        long = "First part is short. " + "word " * 60
        self.assertEqual(atelier_ai.one_sentence(long, 200), "First part is short.")
        cut = atelier_ai.one_sentence("word " * 80, 200)
        self.assertLessEqual(len(cut), 200)
        self.assertTrue(cut.endswith("word"))

    def test_line_and_paragraph(self):
        self.assertEqual(atelier_ai.one_line('\n"The Old Mill"\nsecond', 48), "The Old Mill")
        self.assertEqual(atelier_ai.one_line("Riverside water tower by the school", 20), "Riverside water")
        self.assertEqual(atelier_ai.paragraph("A nurse.\nShe hides.\n\nShe is kind. " + "x " * 400, 40),
                         "A nurse. She hides. She is kind.")

    def test_cut_by_bytes_never_splits_a_character(self):
        self.assertEqual(atelier_ai.one_line("éééé éé", 9, "bytes"), "éééé")
        self.assertEqual(atelier_ai.one_line("ééééé", 5, "bytes"), "éé")

    def test_plain_text_drops_a_fence(self):
        self.assertEqual(atelier_ai.plain_text("```text\nYou are Zed.\n```"), "You are Zed.")

    def test_templates_are_data_with_markers(self):
        templates = atelier_ai.load_templates()
        self.assertEqual(sorted(templates), ["personality"])
        self.assertTrue(templates["personality"]["system"].startswith("Workshop task: personality."))
        self.assertIn('End each transmission with "Over."', templates["personality"]["system"])

    def test_suggest_fields_are_data(self):
        book = atelier_ai.load_suggest()
        self.assertTrue(book.common.startswith("Workshop task: suggest."))
        self.assertEqual(sorted(book.fields), sorted(["name", "description", "persona_idea", "place_label",
                                                      "mission_story", "mission_state", "call", "note_line",
                                                      "paquet_name", "category_name"]))
        for name, spec in book.fields.items():
            self.assertTrue(spec.task and spec.meaning, name)
            self.assertGreater(spec.max, 0, name)
            self.assertIn(spec.unit, ("chars", "bytes"), name)
            self.assertIn(spec.language, ("voice", "page"), name)
            self.assertIn(spec.sentences, ("one", "line", "paragraph"), name)
        self.assertEqual((book.fields["note_line"].max, book.fields["note_line"].unit), (40, "bytes"))
        self.assertTrue(book.fields["call"].frequency and book.fields["note_line"].frequency)
        self.assertFalse(book.fields["name"].sheet_required)
        self.assertTrue(all(spec.sheet_required for name, spec in book.fields.items() if name != "name"))

if __name__ == "__main__":
    unittest.main()
