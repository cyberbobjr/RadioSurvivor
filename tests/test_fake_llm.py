"""Faux modèle LLM déterministe des campagnes de test (tools/fake_llm/fake_llm.py) contre le VRAI pont.

    python RadioSurvivor/tests/test_fake_llm.py

Le faux serveur est lancé comme le ferait autoclient.py (--port 0, ligne « FAKE LLM READY port=P ») ; chaque type de
demande est construit par les vraies fonctions du pont (radio_bridge.answer, spontaneous_call, evening_bulletin,
last_pages.write, npc_protocol.prompt + call_llm + model_reply) et la réponse doit être lue sans repli ni rejet :
- radio libre (lignes radio bornées), radio structurée (report_mission sur compte rendu attendu, propose_trade
  depuis le livre, consigne de briefing sans action), appel spontané, bulletin du soir, dernières pages ;
- PNJ : étranger (none ; premier tour : réplique longue de plusieurs phrases, E17-T13), catalogue (offer), offre ouverte au premier tour (none) puis après un tour (accept),
  compte rendu (report_done), fait de relation (change_relation), négociation et départ seulement avec --intents,
  enrichissement, initiative, conversation, réaction de membre, incident ;
- déterminisme, journal JSONL (sans en-tête ni clé), modes d'échec (http_503, garbage, timeout) vus par call_llm ;
- bout en bout : radio_bridge.py --test avec OPENAI_* dans l'environnement.
Aucun appel réseau hors 127.0.0.1, aucune clé lue.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAKE = ROOT / "tools" / "fake_llm" / "fake_llm.py"
BRIDGE = ROOT / "bridge" / "radio_bridge.py"
sys.path.insert(0, str(ROOT / "bridge"))
import bulletin  # noqa: E402
import last_pages  # noqa: E402
import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402
sys.path.insert(0, str(FAKE.parent))

rb.log = lambda msg: None   # quiet bench; downgrades are checked through the return values


def start_fake(*args: str) -> tuple[subprocess.Popen, int]:
    proc = subprocess.Popen([sys.executable, "-u", str(FAKE), "--port", "0", *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    line = proc.stdout.readline().strip()
    if not line.startswith("FAKE LLM READY port="):
        proc.kill()
        raise RuntimeError(f"fake LLM did not start: {line!r} {proc.stderr.read()}")
    return proc, int(line.split("=", 1)[1])


def stop(proc: subprocess.Popen) -> None:
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
    for stream in (proc.stdout, proc.stderr):
        stream.close()


def config(port: int) -> dict:
    return {"OPENAI_BASE_URL": f"http://127.0.0.1:{port}/v1", "OPENAI_MODEL": "fake", "OPENAI_KEY": "sk-fakekey-0000000000000000"}


def hexed(value) -> str:
    return npc.encode(value).hex()


def npc_req(kind="npc_talk", context=None, offers=None, language="EN", **extra) -> dict:
    req = {"id": "rq-1", "world": "w1", "run": "r1", "npc": "lk-1", "order": 1, "revision": 1, "sent": 0,
           "version": 2, "kind": kind, "channel": "say", "language": language, "character": "c-1",
           "text": "Hello there, anything for me?", "personality": {"sociability": 3, "style": "Direct"},
           "context": context or {}, "offers": offers or {}}
    if kind in (npc.INITIATIVE_KIND, npc.CONVERSE_KIND):
        req["character"] = "system"
        req.pop("text")
        req["event"] = {"fact": "weather", "subject": "storm", "day": 3, "place": "Muldraugh", "source": "seen",
                        "hops": 0}
    req.update(extra)
    return req


SCOUT_OFFER = {"m-7": {"kind": "scout", "durationMs": 3600000, "rewardCount": 10, "clues": {1: "a blue door"}}}
TRADE_BOOK = {"passage": 2, "cap": 100, "kg": 10, "marginMin": 0.2, "marginMax": 0.5, "cordon": 1.2,
              "stock": {1: {"n": "Antibiotics", "q": 3, "v": 10, "w": 0.1, "unit": 12}}, "takes": {}, "deals": {},
              "run": {"status": "free", "from": 1, "to": 4, "days": 1, "inHours": 20}}


class FakeLLMTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="rs_fake_llm_"))
        cls.log = cls.tmp / "fake.jsonl"
        cls.proc, cls.port = start_fake("--log", str(cls.log))
        cls.cfg = config(cls.port)
        cls.saved = (rb.TOKEN_USAGE,)
        rb.TOKEN_USAGE = None
        cls.voices = rb.Voices(rb.BUNDLED_PERSONAS)
        # Test sheet: Walt with mission and memory actions (sheet copied in the temp folder, never the delivered one).
        sheets = cls.tmp / "personas"
        sheets.mkdir()
        text = (rb.BUNDLED_PERSONAS / "walt.txt").read_text(encoding="utf-8")
        text = text.replace("id=walt", "id=rstfake").replace("actions=say", "actions=say,start_mission,remember")
        (sheets / "rstfake.txt").write_text(text, encoding="utf-8")
        cls.mission_voices = rb.Voices(sheets)

    @classmethod
    def tearDownClass(cls):
        stop(cls.proc)
        rb.TOKEN_USAGE, = cls.saved
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def conversations(self) -> rb.Conversations:
        folder = Path(tempfile.mkdtemp(dir=self.tmp))
        return rb.Conversations(folder)

    def radio(self, voice="walt", voices=None, **fields):
        req = {"caller": "solo", "name": "Kate", "date": "1993-07-12 21:40", "days": "3", "radio": "Walkie-talkie",
               "text": "Anyone out there?", "voice": voice, "id": "radio-1", **fields}
        return rb.answer(self.cfg, self.conversations(), "s1", req, voices or self.voices)

    def assert_lines(self, lines, max_lines=rb.MAX_LINES):
        self.assertIsInstance(lines, list)
        self.assertTrue(lines and rb.STATIC_LINE not in lines, lines)
        self.assertLessEqual(len(lines), max_lines)
        for line in lines:
            self.assertLessEqual(len(line), rb.MAX_LINE_CHARS)

    # --- radio --------------------------------------------------------------------------------------------------

    def test_radio_free_text(self):
        self.assert_lines(self.radio())

    def test_radio_free_text_is_deterministic(self):
        self.assertEqual(self.radio(), self.radio())

    def test_radio_structured_report_due(self):
        mission = {"kind": "scout", "state": "active", "turn": "report_due", "place": "house",
                   "clues": {1: "a blue door"}, "toReport": True, "zoneReached": True, "remainingMs": 600000}
        out = self.radio("rstfake", self.mission_voices, mission=hexed(mission))
        self.assertIsInstance(out, dict)
        self.assertEqual([{"type": "report_mission"}], out["actions"])
        self.assert_lines(out["say"])

    def test_radio_structured_briefing_says_the_clues(self):
        mission = {"kind": "scout", "state": "active", "turn": "briefing", "place": "gas station",
                   "clues": {1: "a red roof", 2: "next to a water tower"}, "zoneReached": False}
        lines = self.radio("rstfake", self.mission_voices, mission=hexed(mission))
        self.assertIsInstance(lines, list)   # no action: plain lines
        said = " ".join(lines)
        self.assertIn("gas station", said)
        self.assertIn("a red roof", said)

    def test_radio_structured_plain_turn_remembers(self):
        out = self.radio("rstfake", self.mission_voices)
        self.assertEqual("remember", out["actions"][0]["type"])
        self.assertEqual(1, len(out["actions"]))

    def test_radio_trade_offer_from_the_book(self):
        out = self.radio("gus", trade=hexed(TRADE_BOOK))
        self.assertIsInstance(out, dict)
        self.assertEqual([{"type": "propose_trade", "items": "Antibiotics:1", "margin": 0.2}], out["actions"])

    def test_radio_trade_run_taken_no_offer(self):
        book = dict(TRADE_BOOK, run={"status": "taken", "from": 1, "to": 4})
        out = self.radio("gus", trade=hexed(book))
        self.assertIsInstance(out, list)

    def test_spontaneous_call(self):
        req = {"kind": rb.CALL_KIND, "voice": "walt", "date": "1993-07-12 21:00", "language": "FR", "id": "c1"}
        lines = rb.spontaneous_call(self.cfg, self.conversations(), "s1", req, self.voices)
        self.assert_lines(lines, rb.CALL_MAX_LINES)

    def test_evening_bulletin(self):
        req = {"kind": bulletin.KIND, "voice": "nightowl", "date": "1993-07-12 20:00", "language": "EN", "id": "b1",
               "facts": hexed({1: "The power went out in Muldraugh.", 2: "A helicopter flew over Riverside."})}
        lines = rb.evening_bulletin(self.cfg, self.conversations(), "s1", req, self.voices)
        self.assert_lines(lines, bulletin.MAX_LINES)
        self.assertIn("Muldraugh", " ".join(lines))

    def test_last_pages(self):
        payload = {"id": "lp-1", "kind": last_pages.KIND, "sent": 0, "language": "EN", "name": "Kate Smith",
                   "facts": {"hours": 80, "kills": 12, "profession": "Nurse", "towns": {1: "Muldraugh"}}}
        req = last_pages.unpack({"id": "lp-1", "kind": last_pages.KIND, "payload": hexed(payload)})
        out = last_pages.write(self.cfg, req, rb.call_llm)
        self.assertNotIn("error", out)
        self.assertIn("Kate Smith", out["text"])
        self.assertIn("\n\n", out["text"])

    # --- NPC ----------------------------------------------------------------------------------------------------

    def npc(self, req, history=None, cfg=None) -> dict:
        raw = rb.call_llm(cfg or self.cfg, npc.prompt(req, history or []), "NPC", json_mode=True)
        result, downgraded = npc.model_reply(req, raw)
        self.assertEqual("", downgraded, f"reply downgraded: {raw}")
        self.assertTrue(result["text"])
        return result

    def test_npc_stranger_none(self):
        r = self.npc(npc_req(context={"stage": "stranger"}))
        self.assertEqual(("none", ""), (r["intent"], r["offer"]))

    def test_npc_stranger_first_turn_long_then_short(self):
        # E17-T13 (rs.npctalk): the first answer to a stranger needs several bubble pieces of LK_SpeechView.PIECE
        # (180) characters, cut between whole sentences; same answer whatever the player said.
        import fake_llm
        for language in ("EN", "FR"):
            texts = {self.npc(npc_req(context={"stage": "stranger"}, language=language, text=said))["text"]
                     for said in ("Hi there!", "Tell me everything you saw, in detail.")}
            self.assertEqual(1, len(texts), texts)
            text = texts.pop()
            self.assertGreaterEqual(len(text.encode("utf-8")), fake_llm.LONG_MIN)
            sentences = [x for x in text.replace("!", ".").replace("?", ".").split(". ") if x]
            self.assertGreater(len(sentences), 2)
            self.assertTrue(all(len(x.encode("utf-8")) < 180 for x in sentences), sentences)
        history = [{"role": "user", "content": "c-1: Hi"}, {"role": "assistant", "content": "Hello."}]
        later = self.npc(npc_req(context={"stage": "stranger"}), history)["text"]
        self.assertLess(len(later), 180)

    def test_npc_acquainted_offer(self):
        r = self.npc(npc_req(context={"stage": "acquainted"}, offers=SCOUT_OFFER))
        self.assertEqual(("offer", "m-7"), (r["intent"], r["offer"]))

    def test_npc_member_never_offers(self):
        ctx = {"stage": "acquainted", "collective": {"speaker": "member", "leaderName": "Boss"}}
        self.assertEqual("none", self.npc(npc_req(context=ctx, offers=SCOUT_OFFER))["intent"])

    def test_npc_open_offer_first_turn_kept(self):
        ctx = {"stage": "acquainted", "acceptable": {"mission": "m-7"}, "mission": {"state": "offer"}}
        self.assertEqual("none", self.npc(npc_req(context=ctx))["intent"])

    def test_npc_open_offer_accepted_after_a_turn(self):
        ctx = {"stage": "acquainted", "acceptable": {"mission": "m-7"}, "mission": {"state": "offer"}}
        history = [{"role": "user", "content": "c-1: Need help?"}, {"role": "assistant", "content": "Say yes."}]
        self.assertEqual("accept", self.npc(npc_req(context=ctx), history)["intent"])

    def test_npc_report_done(self):
        ctx = {"stage": "acquainted", "reportable": {"mission": "m-7"}, "mission": {"state": "active",
                                                                                     "toReport": True}}
        self.assertEqual("report_done", self.npc(npc_req(context=ctx))["intent"])

    def test_npc_relation_change(self):
        ctx = {"stage": "acquainted", "relation": {"level": "cautious", "facts": {
            1: {"id": "f1", "nature": "good", "fact": "gift"}, 2: {"id": "f2", "nature": "bad", "fact": "hit"}}}}
        r = self.npc(npc_req(context=ctx))
        self.assertEqual(("change_relation", "f2", "down"), (r["intent"], r.get("fact"), r.get("dir")))

    def test_npc_negotiate_and_leave_only_with_intents(self):
        ctx = {"stage": "acquainted", "negotiation": {"terms": {"truce": {}, "alliance": {}}}, "leave": {}}
        self.assertEqual("none", self.npc(npc_req(context=ctx))["intent"])
        proc, port = start_fake("--intents", "negotiate")
        try:
            r = self.npc(npc_req(context=ctx), cfg=config(port))
            self.assertEqual(("negotiate", "truce"), (r["intent"], r["offer"]))
        finally:
            stop(proc)
        proc, port = start_fake("--intents", "leave_group")
        try:
            self.assertEqual("leave_group", self.npc(npc_req(context=ctx), cfg=config(port))["intent"])
        finally:
            stop(proc)

    def test_npc_enrich(self):
        r = self.npc(npc_req("npc_enrich", language="FR"))
        self.assertEqual("none", r["intent"])
        self.assertTrue(r["background"])

    def test_npc_initiative(self):
        r = self.npc(npc_req(npc.INITIATIVE_KIND, context={"audience": 1}))
        self.assertEqual("none", r["intent"])
        self.assertLessEqual(len(r["text"].encode("utf-8")), npc.INITIATIVE_REPLY_BYTES)

    def test_npc_converse(self):
        for role, turn in (("teller", 1), ("listener", 2)):
            ctx = {"partner": "Ann", "role": role, "turn": turn, "turns": 2,
                   "lines": [{"who": "Ann", "text": "Did you hear?"}] if turn == 2 else []}
            req = npc_req(npc.CONVERSE_KIND, context=npc.converse_context(
                dict(ctx, lines={i + 1: x for i, x in enumerate(ctx["lines"])})))
            self.assertEqual("none", self.npc(req)["intent"])

    def test_npc_member_reaction(self):
        r = self.npc(npc_req("npc_member", context={"decision": "supply run"},
                             personality={"loyalty": "steady"}))
        self.assertEqual("accept", r["intent"])

    def test_npc_incident(self):
        ctx = {"incident": {"agreement": "truce", "teamName": "T"},
               "choices": {"maintain": {}, "repair": {"categories": {1: "food"}}, "break": {}}}
        self.assertEqual("maintain", self.npc(npc_req(npc.INCIDENT_KIND, context=ctx))["intent"])

    # --- journal, failures, end to end --------------------------------------------------------------------------

    def test_log_has_kinds_and_no_key(self):
        self.radio()
        self.npc(npc_req(context={"stage": "stranger"}))
        text = self.log.read_text(encoding="utf-8")
        self.assertNotIn("sk-fakekey", text)
        self.assertNotIn("Authorization", text)
        kinds = {json.loads(line)["kind"] for line in text.splitlines() if line.strip()}
        # E07-T10: Walt has share_frequency, so his calls are structured (radio_json), no longer plain text.
        self.assertTrue({"radio_json", "npc_talk"} <= kinds, kinds)

    def test_failure_modes(self):
        saved = rb.LLM_BUDGET_S
        try:
            for mode, code in (("http_503", "http_503"), ("garbage", "bad_response"), ("timeout", "timeout")):
                proc, port = start_fake("--fail", mode)
                try:
                    rb.LLM_BUDGET_S = 2
                    with self.assertRaises(rb.ProviderError) as caught:
                        rb.call_llm(config(port), [{"role": "user", "content": "x"}])
                    self.assertEqual(code, caught.exception.code, mode)
                finally:
                    stop(proc)
        finally:
            rb.LLM_BUDGET_S = saved

    def test_bridge_console_end_to_end(self):
        env = dict(os.environ, OPENAI_BASE_URL=f"http://127.0.0.1:{self.port}/v1", OPENAI_MODEL="fake",
                   OPENAI_KEY="fake", PYTHONIOENCODING="utf-8")
        exchange = self.tmp / "exchange"
        out = subprocess.run([sys.executable, str(BRIDGE), "--test", "Allo ?", "--exchange", str(exchange),
                              "--env", str(self.tmp / "absent.env")],
                             env=env, capture_output=True, text=True, encoding="utf-8", timeout=60)
        self.assertEqual(0, out.returncode, out.stderr)
        body = [line for line in out.stdout.splitlines() if line.strip() and not line.startswith(("[", "="))]
        self.assertTrue(body, out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
