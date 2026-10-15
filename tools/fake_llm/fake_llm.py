#!/usr/bin/env python3
"""Deterministic fake LLM for the RadioSurvivor test campaigns (no network model, no key, standard library only).

An HTTP server compatible with the call of the bridge (bridge/radio_bridge.py, call_llm): POST <base>/chat/completions
with {model, messages[, temperature, max_tokens, response_format]}; the answer is an OpenAI-style chat completion
(choices[0].message.content, finish_reason, usage). The Authorization header is ignored and never logged.

    python tools/fake_llm/fake_llm.py --port P [--log FILE] [--delay-ms N] [--fail timeout|http_503|garbage]
                                      [--intents negotiate,leave_group]

Prints "FAKE LLM READY port=P" (flushed) once listening on 127.0.0.1; --port 0 takes a free port, the line gives it.
Bridge side: OPENAI_BASE_URL=http://127.0.0.1:P/v1 OPENAI_MODEL=fake OPENAI_KEY=fake (environment wins over .env).

Replies are immediate (unless --delay-ms) and a pure function of the messages (no randomness): the kind of request is
recognised from the prompts the bridge builds, and each reply is valid for that kind (the bridge parses it without
fallback nor rejection):
    radio        free text of a radio voice: a few short sentences (<= 8 radio lines of 100 characters);
    radio_json   structured radio reply {"say", "actions"}: an action only when the prompt offers it AND a server
                 fact of the prompt calls for it (report_mission on a "report due" mission, propose_trade from the
                 trade book when the run is open, otherwise remember when allowed); briefing turn: the clues said;
    radio_call   spontaneous call (1-2 sentences);         bulletin   evening bulletin from the facts of the prompt;
    last_pages   journal of a dead character, from the facts of the prompt;
    npc_*        NPC JSON {"text", "intent", "offer"[, "background", "dir", "fact"]} read from the authoritative
                 context of the prompt (same admissibility helpers as the bridge, npc_protocol):
                 npc_talk     report_done when context.reportable; accept when context.acceptable and this
                              conversation already had a turn (never at the first turn the fake sees with that NPC);
                              change_relation on the last citable fact; offer = first key of the catalogue (not
                              from a member when the leader decides); negotiate / leave_group only with --intents;
                              otherwise none, and at the FIRST turn the fake sees with a stranger (stage "stranger",
                              no previous reply of that NPC in the history) a long answer of several whole sentences,
                              more than LONG_MIN characters (E17-T13, rs.npctalk: the speech bubble is cut in pieces
                              of LK_SpeechView.PIECE = 180 characters; every test of that suite meets a new NPC);
                 npc_enrich   none + background;   npc_member  accept;   npc_incident  maintain (else the first allowed);
                 npc_initiative / npc_converse  none, one short line.
The fake never reads the player's sentence to decide anything (no word list, no language detection): language comes
from the request (context language, "Speak <language>" of the prompt), English otherwise.

--fail MODE (to test the fallbacks of the bridge and of the server): timeout (connection held open, no answer),
http_503 (provider error), garbage (HTTP 200 with a body that is not JSON).
--log FILE: one JSON line per request received (time, path, kind, sizes, json mode, intent/actions, failure), never
a header nor the messages themselves.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bridge"))
import npc_protocol as npc  # noqa: E402  (pure helpers of the bridge: acceptable, reportable, relation_facts...)

READY = "FAKE LLM READY port={port}"
FAIL_MODES = ("timeout", "http_503", "garbage")
OPTIONAL_INTENTS = ("negotiate", "leave_group")
TIMEOUT_HOLD_S = 600          # --fail timeout: longer than the bridge budget (LLM_BUDGET_S = 60)

# Markers of the prompts built by the bridge (radio_bridge.py, bulletin.py, last_pages.py, npc_protocol.py).
NPC_HEAD = "You are the survivor described in the authoritative context"
AUTH = "Authoritative context: "
LAST_PAGES_HEAD = "You write the last pages of the private journal"
CALL_MARK = "[General call]"
BULLETIN_MARK = "[Evening bulletin]"
STRUCTURED = "Reply format: return ONLY one JSON object"
REPORT_DUE = "you only wait for their report"
BRIEFING = "they are waiting for the details"
TRADE_BOOK = "Your trade book (kept by the other side"


def digest(*parts: str) -> int:
    """Stable choice index from the content (never random, never Python's salted hash)."""
    return int(hashlib.sha256("\x1f".join(parts).encode("utf-8")).hexdigest()[:8], 16)


def pick(options: list[str], *parts: str) -> str:
    return options[digest(*parts) % len(options)]


def french(code_or_name: str | None) -> bool:
    return (code_or_name or "").strip().upper() in ("FR", "FRENCH")


# --- texts -----------------------------------------------------------------------------------------------------------

RADIO = {
    "en": ["I hear you, loud enough. Stay off the main roads and keep your radio dry. Call again tonight. Over.",
           "Copy that. Nothing new on my side, the dead are quiet for now. Keep your head down. Over.",
           "Good to hear a voice. Lock your doors, ration your water, and do not trust strangers. Over."],
    "fr": ["Je vous reçois. Évitez les grands axes et gardez votre radio au sec. Rappelez ce soir. Terminé.",
           "Bien reçu. Rien de neuf de mon côté, les morts sont calmes pour l'instant. Restez discret. Terminé.",
           "Ça fait du bien d'entendre une voix. Fermez vos portes, rationnez l'eau. Terminé."],
}
CALL = {"en": "This is a general call to anyone listening. Stay safe out there. Over.",
        "fr": "Appel général à quiconque écoute. Restez prudents. Terminé."}
TALK = {
    "en": ["Easy there, I am listening. Times are hard around here, so talk slowly. What do you want from me?",
           "I see you. Keep your hands where I can see them. We can talk, but I will not stay out here long.",
           "Another living face, good. The roads are bad this week. Say what you need and keep it short."],
    "fr": ["Doucement, je vous écoute. Les temps sont durs par ici, alors parlez calmement. Que voulez-vous ?",
           "Je vous vois. Gardez les mains en vue. On peut parler, mais je ne reste pas longtemps dehors.",
           "Un visage vivant, tant mieux. Les routes sont mauvaises cette semaine. Dites ce qu'il vous faut."],
}
OFFER = {"en": "I could use a hand. The terms are written in your notebook, take a look. Say yes if you are in.",
         "fr": "J'aurais besoin d'un coup de main. Les conditions sont dans votre carnet. Dites oui si ça vous va."}
ACCEPT = {"en": "Good, I am counting on you. Come back when it is done.",
          "fr": "Entendu, je compte sur vous. Revenez quand ce sera fait."}
STANDING = {"en": "I am listening. My offer in your notebook still stands.",
            "fr": "Je vous écoute. Mon offre dans votre carnet tient toujours."}
REPORT = {"en": "Good work, thank you. The shared reward is yours.",
          "fr": "Bon travail, merci. Le lot commun est à vous."}
RELATION = {"en": "I have not forgotten that. It counts for me.",
            "fr": "Je n'ai pas oublié ça. Ça compte pour moi."}
NEGOTIATE = {"en": "Deal. I will tell my people.", "fr": "Marché conclu, je préviens les miens."}
LEAVE = {"en": "I am leaving. I will go my own way.", "fr": "Je pars. Je ferai ma route seul."}
BACKGROUND = {"en": "I fixed engines before all this. Now I keep my head down and my knife sharp.",
              "fr": "Je réparais des moteurs avant tout ça. Maintenant je fais profil bas."}
# E17-T13: first answer to a stranger, longer than one bubble piece (LK_SpeechView.PIECE = 180); whole sentences, each
# well under 180 characters, so RS_TextCut cuts between sentences.
LONG_MIN = 181
LONG_TALK = {
    "en": ("Easy there, stranger, I am listening. I have been on my own for a while now, so forgive me if I do not trust "
           "you right away. The roads around here are full of the dead, and the living are not much better. I keep "
           "to the back streets and I sleep with one eye open. If you want something from me, say it plainly. "
           "Maybe we can help each other, maybe not."),
    "fr": ("Doucement, l'inconnu, je vous écoute. Je suis seul depuis un bon moment, alors pardonnez-moi si je ne vous "
           "fais pas confiance tout de suite. Les routes du coin sont pleines de morts, et les vivants ne valent "
           "guère mieux. Je passe par les petites rues et je dors d'un oeil. Si vous voulez quelque chose, dites-le "
           "franchement. On peut peut-être s'entraider, ou pas."),
}
INITIATIVE = {"en": "Did you see that? Stay on your guard.", "fr": "Vous avez vu ça ? Restez sur vos gardes."}
CONVERSE = {"teller": {"en": "Listen, I have to tell you something.", "fr": "Écoute, je dois te raconter quelque chose."},
            "listener": {"en": "Really? Go on.", "fr": "Ah oui ? Raconte."}}
MEMBER = {"en": "Fine, we do as the boss said.", "fr": "D'accord, on fait comme le chef a dit."}
INCIDENT = {"maintain": {"en": "We keep the truce, but keep your eyes open.",
                         "fr": "On garde la trêve, mais ouvrez l'oeil."},
            "repair": {"en": "They will have to pay for this.", "fr": "Ils vont devoir payer pour ça."},
            "break": {"en": "It is over, no more truce with them.", "fr": "C'est fini, plus de trêve avec eux."},
            "none": {"en": "I need to think about it.", "fr": "Je dois y réfléchir."}}


def lang(is_fr: bool) -> str:
    return "fr" if is_fr else "en"


# --- request reading -------------------------------------------------------------------------------------------------

def split_messages(messages: list) -> tuple[str, list[dict], str]:
    """System content, history (between system and the last user turn), last user content."""
    msgs = [m for m in messages if isinstance(m, dict)]
    system = str(msgs[0].get("content", "")) if msgs and msgs[0].get("role") == "system" else ""
    last = str(msgs[-1].get("content", "")) if msgs and msgs[-1].get("role") == "user" else ""
    start = 1 if system else 0
    end = len(msgs) - 1 if last else len(msgs)
    return system, msgs[start:end], last


def authoritative(system: str) -> list[dict]:
    """JSON objects that follow "Authoritative context: " in an NPC prompt (the converse prompt has two)."""
    pos = system.find(AUTH)
    if pos < 0:
        return []
    decoder, out, pos = json.JSONDecoder(), [], pos + len(AUTH)
    for _ in range(2):
        while pos < len(system) and system[pos] == " ":
            pos += 1
        if pos >= len(system) or system[pos] != "{":
            break
        try:
            value, pos = decoder.raw_decode(system, pos)
        except ValueError:
            break
        if isinstance(value, dict):
            out.append(value)
    return out


def classify(messages: list) -> str:
    system, _, last = split_messages(messages)
    if system.startswith(NPC_HEAD):
        objs = authoritative(system)
        kind = objs[0].get("kind") if objs else None
        return kind if isinstance(kind, str) and kind.startswith("npc_") else "npc_unknown"
    if system.startswith(LAST_PAGES_HEAD):
        return "last_pages"
    if last == BULLETIN_MARK:
        return "bulletin"
    if last == CALL_MARK:
        return "radio_call"
    if STRUCTURED in system:
        return "radio_json"
    return "radio"


# --- NPC replies -----------------------------------------------------------------------------------------------------

def npc_request(system: str) -> dict:
    """The request as the bridge put it in the prompt, plus the fields npc_protocol helpers read."""
    objs = authoritative(system)
    req = dict(objs[0]) if objs else {}
    if len(objs) > 1 and "context" not in req:
        req["context"] = objs[1]
    req.setdefault("context", {})
    req.setdefault("offers", {})
    return req


def npc_reply(system: str, history: list[dict], last: str, intents: set[str]) -> dict:
    req = npc_request(system)
    kind = req.get("kind", "npc_talk")
    ctx = req["context"] if isinstance(req["context"], dict) else {}
    lg = lang(french(req.get("language")))
    if kind == "npc_enrich":
        return {"text": BACKGROUND[lg], "intent": "none", "offer": "", "background": BACKGROUND[lg]}
    if kind == npc.INITIATIVE_KIND:
        return {"text": INITIATIVE[lg], "intent": "none", "offer": ""}
    if kind == npc.CONVERSE_KIND:
        role = ctx.get("role") if ctx.get("role") in CONVERSE else "listener"
        return {"text": CONVERSE[role][lg], "intent": "none", "offer": ""}
    if kind == "npc_member":
        return {"text": MEMBER[lg], "intent": "accept", "offer": ""}
    if kind == npc.INCIDENT_KIND:
        choices = ctx.get("choices") if isinstance(ctx.get("choices"), dict) else {}
        choice = next((c for c in ("maintain", "repair", "break") if c in choices), "none")
        offer = ""
        if choice == "repair":
            categories = npc.repair_categories(req)
            if categories:
                offer = categories[0]
            else:
                choice = "none"
        return {"text": INCIDENT[choice][lg], "intent": choice, "offer": offer}
    # npc_talk (and any later talk-like kind): server facts of the context only, never the player's words.
    talk = dict(req, kind="npc_talk")
    text = pick(TALK[lg], last, json.dumps(ctx, sort_keys=True, ensure_ascii=False))
    if npc.reportable(talk):
        return {"text": REPORT[lg], "intent": "report_done", "offer": ""}
    if npc.acceptable(talk):
        # Accepted only once the conversation already had a turn with this NPC (the history the bridge keeps for
        # it): the first sentence the fake hears about an open offer never takes it.
        if any(m.get("role") == "assistant" for m in history):
            return {"text": ACCEPT[lg], "intent": "accept", "offer": ""}
        return {"text": STANDING[lg], "intent": "none", "offer": ""}
    if "negotiate" in intents and npc.negotiable(talk):
        return {"text": NEGOTIATE[lg], "intent": "negotiate", "offer": npc.negotiable(talk)[0]}
    if "leave_group" in intents and npc.leavable(talk):
        return {"text": LEAVE[lg], "intent": "leave_group", "offer": ""}
    facts = npc.relation_facts(talk)
    if facts:
        fact = sorted(facts, key=lambda i: int(i[1:]))[-1]
        return {"text": RELATION[lg], "intent": "change_relation", "offer": "", "dir": facts[fact], "fact": fact}
    offers = req.get("offers") if isinstance(req.get("offers"), dict) else {}
    collective = ctx.get("collective") if isinstance(ctx.get("collective"), dict) else {}
    if offers and ctx.get("stage") != "stranger" and collective.get("speaker") != "member":
        return {"text": OFFER[lg], "intent": "offer", "offer": sorted(offers)[0]}
    if ctx.get("stage") == "stranger" and not any(m.get("role") == "assistant" for m in history):
        return {"text": LONG_TALK[lg], "intent": "none", "offer": ""}
    return {"text": text, "intent": "none", "offer": ""}


# --- radio replies ---------------------------------------------------------------------------------------------------

def speaks_french(system: str) -> bool:
    m = re.search(r"- Speak ([A-Za-z ()]+)\.", system)
    return bool(m) and french(m.group(1))


def allowed_actions(system: str) -> list[str]:
    m = re.search(r"Allowed action types: ([a-z_, ]+)\. At most", system)
    return [a.strip() for a in m.group(1).split(",") if a.strip()] if m else []


def briefing_say(system: str) -> str:
    place = re.search(r"\(kind: ([^)]+)\)", system)
    clues = re.findall(r"^- What you know of the place: (.+)$", system, re.M)
    objective = re.search(r"^- The job: (.+)$", system, re.M)
    words = ["Here is the job: " + objective.group(1) if objective else
             f"Here is the job: go and look at a {place.group(1) if place else 'building'}."]
    words += clues
    words.append("Check your map, then call me back. Over.")
    return " ".join(words)


def trade_action(system: str) -> dict | None:
    """First offer the trade book allows: one piece of the first line within the run limits, lowest margin."""
    if TRADE_BOOK not in system or "already booked by another group" in system or "This week's run is over" in system:
        return None
    if re.search(r"^- Your offer to .*\(standing\)", system, re.M):
        return None
    limits = re.search(r"you take at most ([\d.]+) points of goods in all, and the goods you bring weigh at most "
                       r"([\d.]+) kg", system)
    margin = re.search(r"- Your margin with .*?: from ([\d.]+) to ([\d.]+)", system)
    cap, kg = (float(limits.group(1)), float(limits.group(2))) if limits else (float("inf"), float("inf"))
    for name, left, weight, unit in re.findall(
            r"^  - ([A-Za-z0-9_]{1,40}): (\d+) left, value [\d.]+, ([\d.]+) kg, (\d+) points each$", system, re.M):
        if int(left) >= 1 and float(weight) <= kg and int(unit) <= cap:
            action = {"type": "propose_trade", "items": f"{name}:1"}
            if margin and 0 <= float(margin.group(1)) <= 1:
                action["margin"] = float(margin.group(1))
            return action
    return None


def radio_json(system: str, last: str) -> dict:
    allowed = allowed_actions(system)
    lg = lang(speaks_french(system))
    if BRIEFING in system:
        return {"say": briefing_say(system), "actions": []}
    if REPORT_DUE in system and "report_mission" in allowed:
        return {"say": "Report received, thank you. Well done. Over.", "actions": [{"type": "report_mission"}]}
    # Explicit machine-readable test requests, independent of the caller's language.
    # They still pass through the prompt's sheet whitelist and the real server executor.
    requested = re.search(r"\[mission:(scout|deliver|retrieve|clear|signal)\]", last)
    templates = re.search(r"Allowed mission templates: ([a-z_, ]+)\.", system)
    permitted = [v.strip() for v in templates.group(1).split(",")] if templates else ["scout"]
    if requested and "start_mission" in allowed and requested.group(1) in permitted:
        return {"say": "I may have a job for you. Over.",
                "actions": [{"type": "start_mission", "template": requested.group(1)}]}
    if "[share_frequency]" in last and "share_frequency" in allowed:
        return {"say": "I can try to introduce you to someone. Over.", "actions": [{"type": "share_frequency"}]}
    if "propose_trade" in allowed:
        action = trade_action(system)
        if action:
            return {"say": "I can bring you something on the next run. The count will be firm. Over.",
                    "actions": [action]}
    actions = [{"type": "remember", "fact": "Called me on the radio"}] if "remember" in allowed else []
    return {"say": pick(RADIO[lg], last), "actions": actions}


def bulletin_text(system: str) -> str:
    facts = re.findall(r"^  \* (.+)$", system, re.M)
    if not facts:
        return "Evening bulletin. No confirmed report reached me today. Stay safe. Over."
    return " ".join(["Evening bulletin.", *facts[:2], "That is all for tonight. Over."])


def last_pages_text(system: str) -> str:
    def fact(pattern: str, default: str) -> str:
        m = re.search(pattern, system, re.M)
        return m.group(1) if m else default
    name = fact(r"^- Your name: (.+?)\.$", "a survivor")
    days = fact(r"^- Time survived since the outbreak: (\d+) days", "a few")
    kills = fact(r"^- Zombies you killed: (\d+)\.$", "some")
    return (f"My name is {name}. I have held on for {days} days since it all started, and I put down {kills} of "
            "them.\n\nI do not know how many days are left. If someone finds this notebook, keep going.")


# --- reply -----------------------------------------------------------------------------------------------------------

def reply_for(body: dict, intents: frozenset = frozenset()) -> tuple[str, dict]:
    """(content, meta) for one chat completion body; meta goes to the log (kind, intent or actions)."""
    messages = body.get("messages") if isinstance(body.get("messages"), list) else []
    kind = classify(messages)
    system, history, last = split_messages(messages)
    meta: dict = {"kind": kind}
    if kind.startswith("npc_"):
        value = npc_reply(system, history, last, set(intents))
        meta["intent"] = value["intent"]
        return json.dumps(value, ensure_ascii=False), meta
    if kind == "radio_json":
        value = radio_json(system, last)
        meta["actions"] = [a["type"] for a in value["actions"]]
        return json.dumps(value, ensure_ascii=False), meta
    if kind == "last_pages":
        return last_pages_text(system), meta
    if kind == "bulletin":
        return bulletin_text(system), meta
    if kind == "radio_call":
        return CALL[lang(speaks_french(system))], meta
    return pick(RADIO["en"], last, system[:200]), meta


def completion(body: dict, content: str) -> dict:
    prompt_chars = sum(len(str(m.get("content", ""))) for m in body.get("messages", []) if isinstance(m, dict))
    prompt_tokens, completion_tokens = max(1, prompt_chars // 4), max(1, len(content) // 4)
    return {
        "id": "fake-" + hashlib.sha256(content.encode("utf-8")).hexdigest()[:16],
        "object": "chat.completion",
        "created": 0,
        "model": str(body.get("model") or "fake"),
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
                  "total_tokens": prompt_tokens + completion_tokens},
    }


class FakeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port: int, log: Path | None, delay_ms: int, fail: str | None, intents: frozenset):
        super().__init__(("127.0.0.1", port), Handler)
        self.log_path, self.delay_ms, self.fail, self.intents = log, delay_ms, fail, intents
        self.log_lock = threading.Lock()
        self.stopping = threading.Event()

    def record(self, entry: dict) -> None:
        if self.log_path is None:
            return
        line = json.dumps(entry, ensure_ascii=False)
        with self.log_lock:
            with self.log_path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")


class Handler(BaseHTTPRequestHandler):
    server: FakeServer
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):   # no default stderr line per request (the JSONL log is the journal)
        pass

    def _send(self, status: int, payload: bytes, ctype: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, json.dumps({"object": "list", "data": [{"id": "fake", "object": "model"}]}).encode())
        else:
            self._send(404, b'{"error": {"message": "not found"}}')

    def do_POST(self):
        started = time.monotonic()
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b""
        entry: dict = {"time": round(time.time(), 3), "path": self.path, "bytes": len(raw)}
        if not self.path.rstrip("/").endswith("/chat/completions"):
            entry["status"] = 404
            self.server.record(entry)
            self._send(404, b'{"error": {"message": "unknown endpoint"}}')
            return
        try:
            body = json.loads(raw.decode("utf-8"))
            if not isinstance(body, dict) or not isinstance(body.get("messages"), list):
                raise ValueError("messages")
        except (ValueError, UnicodeDecodeError):
            entry.update(status=400, kind="bad_request")
            self.server.record(entry)
            self._send(400, b'{"error": {"message": "invalid body"}}')
            return
        entry.update(messages=len(body["messages"]), json_mode="response_format" in body,
                     parameters=sorted(k for k in body if k != "messages"))
        content, meta = reply_for(body, self.server.intents)
        entry.update(meta)
        if self.server.delay_ms > 0:
            time.sleep(self.server.delay_ms / 1000)
        fail = self.server.fail
        if fail == "timeout":
            entry.update(status="held", fail=fail)
            self.server.record(entry)
            # Answer never sent: the bridge gives up after its own budget; the connection is dropped at shutdown.
            self.server.stopping.wait(TIMEOUT_HOLD_S)
            self.close_connection = True
            return
        if fail == "http_503":
            entry.update(status=503, fail=fail)
            self.server.record(entry)
            self._send(503, b'{"error": {"message": "fake provider overloaded", "type": "server_error"}}')
            return
        if fail == "garbage":
            entry.update(status=200, fail=fail)
            self.server.record(entry)
            self._send(200, b"<html>fake gateway page, not JSON</html>", "text/html")
            return
        payload = json.dumps(completion(body, content), ensure_ascii=False).encode("utf-8")
        entry.update(status=200, reply_chars=len(content), ms=round((time.monotonic() - started) * 1000, 1))
        self.server.record(entry)
        self._send(200, payload)


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=0, help="port on 127.0.0.1 (0: a free port, printed)")
    parser.add_argument("--log", type=Path, help="JSONL journal of the requests received")
    parser.add_argument("--delay-ms", type=int, default=0, help="delay before each answer, in milliseconds")
    parser.add_argument("--fail", choices=FAIL_MODES, help="failure mode of every answer")
    parser.add_argument("--intents", default="",
                        help="optional NPC intents allowed when the request offers them: negotiate,leave_group")
    args = parser.parse_args(argv)
    wanted = {i.strip() for i in args.intents.split(",") if i.strip()}
    unknown = wanted - set(OPTIONAL_INTENTS)
    if unknown:
        parser.error(f"unknown intents: {', '.join(sorted(unknown))}")
    args.intents = frozenset(wanted)
    if args.delay_ms < 0:
        parser.error("--delay-ms must be >= 0")
    return args


def main(argv=None) -> None:
    args = parse_args(argv)
    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
    server = FakeServer(args.port, args.log, args.delay_ms, args.fail, args.intents)
    print(READY.format(port=server.server_address[1]), flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.stopping.set()
        server.server_close()


if __name__ == "__main__":
    main()
