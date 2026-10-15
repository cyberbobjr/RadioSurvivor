"""Last pages of a dead notebook character (E15-T03): request kind last_pages of the bridge.

The server (RS_LastPages.lua) sends, at the death of a notebook character, one request kind=last_pages whose payload
(hexadecimal RSV2, like the NPC kinds) holds the frozen life log (RS_LifeLog, E15-T01) reduced to facts: character
name, language, hours survived, zombies killed, profession (display name), towns crossed, last radio phrases, closed
missions with their result, missions still open at the death, rescues, totals. Never a coordinate, a frequency or an
account name. The bridge asks the model for the character's journal, written in the first person from these facts
only, and answers with a payload {kind = last_pages_reply, id, text} (or {kind = last_pages_reply, id, error}). The
server bounds and cleans the text again, lays it out in pages and writes the read-only document; without an answer
before its delay (no bridge, error, expired request) it writes its own fallback journal from the same facts.

Rules (decisions of E15): the model may invent neither a death nor an accomplished mission; a mission still open at
the death is never presented as done; no keyword list reads any text (the model writes, the server checks the form).
"""
from __future__ import annotations

import re

import npc_protocol as npc

KIND = "last_pages"
REPLY_KIND = "last_pages_reply"
MAX_TEXT_BYTES = 2400          # RS_LastPages.MAX_TEXT (characters): the server cuts again
MAX_NAME_BYTES = 160
MAX_LABEL_BYTES = 320          # labels of the life log: 80 characters, up to 4 UTF-8 bytes each
MAX_PHRASE_BYTES = 800         # RS_RadioLog.MAX_TEXT = 200 characters
MAX_ITEMS = 16                 # every list of the life log is bounded under this (RS_LifeLog.MAX_*)
TOTAL_KEYS = ("success", "failed", "cancelled", "saved", "missed")


def _list(value, key: str) -> list:
    """RSV2 list (table 1..n decoded as a dict with integer keys), bounded."""
    if value is None:
        return []
    if not isinstance(value, dict) or len(value) > MAX_ITEMS or sorted(value) != list(range(1, len(value) + 1)):
        raise ValueError(f"facts {key}")
    return [value[i] for i in range(1, len(value) + 1)]


def _label(value, key: str, limit: int = MAX_LABEL_BYTES, empty: bool = True) -> str:
    if value is None and empty:
        return ""
    if not isinstance(value, str) or len(value.encode("utf-8")) > limit:
        raise ValueError(f"facts {key}")
    text = " ".join(re.sub(r"[\x00-\x1f\x7f<>\[\]*`#]", " ", value).split())
    if not text and not empty:
        raise ValueError(f"facts {key}")
    return text


def _count(value, key: str) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0 or value > 10 ** 9:
        raise ValueError(f"facts {key}")
    return value


def unpack(record: dict) -> dict:
    """Request of the exchange file (req, kind, payload) -> checked request; ValueError when malformed."""
    if record.get("kind") != KIND:
        raise ValueError("request kind")
    payload = record.get("payload", "")
    if len(payload) > npc.MAX_BYTES * 2 or not re.fullmatch(r"[0-9a-f]+", payload):
        raise ValueError("payload hex")
    value = npc.decode(bytes.fromhex(payload))
    if not isinstance(value, dict) or value.get("id") != record.get("id") or value.get("kind") != KIND:
        raise ValueError("envelope mismatch")
    if not npc.ID.fullmatch(value["id"]):
        raise ValueError("identity id")
    sent = value.get("sent")
    if type(sent) is not int or sent < 0:
        raise ValueError("number sent")
    if not npc.LANGUAGE_CODE.fullmatch(value.get("language") or ""):
        raise ValueError("language")
    facts = value.get("facts")
    if not isinstance(facts, dict):
        raise ValueError("facts")
    totals = facts.get("totals") or {}
    if not isinstance(totals, dict):
        raise ValueError("facts totals")
    clean = {
        "name": _label(value.get("name"), "name", MAX_NAME_BYTES, empty=False),
        "hours": _count(facts.get("hours", 0), "hours"),
        "kills": _count(facts.get("kills", 0), "kills"),
        "profession": _label(facts.get("profession"), "profession"),
        "death": _label(facts.get("death"), "death"),
        "towns": [_label(t, "towns", empty=False) for t in _list(facts.get("towns"), "towns")],
        "phrases": [_label(p, "phrases", MAX_PHRASE_BYTES, empty=False) for p in _list(facts.get("phrases"), "phrases")],
        "missions": [], "open": [], "rescues": [],
        "totals": {k: _count(totals.get(k, 0), "totals") for k in TOTAL_KEYS},
    }
    for key in ("missions", "open"):
        for m in _list(facts.get(key), key):
            if not isinstance(m, dict):
                raise ValueError(f"facts {key}")
            clean[key].append({"template": _label(m.get("template"), key), "result": _label(m.get("result"), key),
                               "requester": _label(m.get("requester"), key), "place": _label(m.get("place"), key)})
    for r in _list(facts.get("rescues"), "rescues"):
        if not isinstance(r, dict) or r.get("outcome") not in ("saved", "missed"):
            raise ValueError("facts rescues")
        clean["rescues"].append({"outcome": r["outcome"], "label": _label(r.get("label"), "rescues")})
    return {"id": value["id"], "kind": KIND, "sent": sent, "language": value["language"], "facts": clean}


# Mission results of the engine (RS_Missions states) as plain words for the prompt; an unknown state is "ended".
RESULTS = {"success": "completed", "failed": "failed", "expired": "failed (out of time)"}


def _mission(m: dict, open_: bool) -> str:
    what = m["template"] or "job"
    who = f" for {m['requester']}" if m["requester"] else ""
    where = f" (a {m['place']})" if m["place"] else ""
    if open_:
        return f"- {what}{who}{where}: NOT finished, still open when you died"
    result = RESULTS.get(m["result"]) or ("cancelled" if m["result"].startswith("cancel") else "ended without success")
    return f"- {what}{who}{where}: {result}"


def facts_text(req: dict) -> str:
    """The facts as a short list for the prompt, nothing else."""
    f = req["facts"]
    days, hours = divmod(int(f["hours"]), 24)
    lines = [f"- Your name: {f['name']}.",
             f"- Time survived since the outbreak: {days} days and {hours} hours.",
             f"- Zombies you killed: {int(f['kills'])}."]
    if f["profession"]:
        lines.append(f"- Your occupation before: {f['profession']}.")
    if f["towns"]:
        lines.append("- Towns you went through, in order: " + ", ".join(f["towns"]) + ".")
    else:
        lines.append("- Towns you went through: none recorded.")
    if f["missions"]:
        lines.append("- Jobs you took on for other survivors (most recent last):")
        lines += [_mission(m, False) for m in f["missions"]]
    t = f["totals"]
    lines.append(f"- Totals of jobs: {int(t['success'])} completed, {int(t['failed'])} failed, "
                 f"{int(t['cancelled'])} cancelled.")
    if f["open"]:
        lines.append("- Jobs still open at your death (never completed):")
        lines += [_mission(m, True) for m in f["open"]]
    if f["rescues"] or t["saved"] or t["missed"]:
        lines.append(f"- People you saved: {int(t['saved'])}; people you could not save: {int(t['missed'])}.")
        lines += [f"- {'saved' if r['outcome'] == 'saved' else 'could not save'}: {r['label'] or 'someone'}"
                  for r in f["rescues"]]
    if f["phrases"]:
        lines.append("- Your last words on the radio, oldest first (quote them only as they are):")
        lines += [f'  "{p}"' for p in f["phrases"]]
    return "\n".join(lines)


def prompt(req: dict) -> list[dict[str, str]]:
    system = (
        "You write the last pages of the private journal of a survivor of the zombie outbreak in Knox County, "
        "Kentucky, July 1993. The survivor has just died; these pages are found on their body.\n"
        f"Write in {npc.language_name(req['language'])}, in the first person, as the survivor writing by hand in "
        "their notebook during their last days: plain prose, past or present tense, a few short paragraphs separated "
        "by a blank line, at most 250 words in total. No title, no date heading, no markup, no lists.\n"
        "Use ONLY the facts below. Never invent another event, place, person, number or date. Never describe how "
        "you died: you do not know it yet while you write. A job is completed only if the facts say so; a job "
        "still open was never finished. Never mention coordinates, radio frequencies or game terms.\n"
        "Facts:\n" + facts_text(req)
    )
    return [{"role": "system", "content": system},
            {"role": "user", "content": "Write the last pages of the journal now."}]


def clean_text(text: str) -> str:
    """Model text as paragraphs the server accepts: controls, markup and code fences removed, spaces collapsed,
    paragraphs kept (one blank line), cut to MAX_TEXT_BYTES at the last sentence end, else the last word.
    ValueError when nothing is left."""
    if not isinstance(text, str):
        raise ValueError("text type")
    text = re.sub(r"```[A-Za-z]*", " ", text).replace("\r", "")
    paragraphs = []
    for para in re.split(r"\n\s*\n", text):
        para = " ".join(re.sub(r"[\x00-\x1f\x7f-\x9f<>\[\]*`#]", " ", para).split())
        if para:
            paragraphs.append(para)
    out = "\n\n".join(paragraphs)
    if not out:
        raise ValueError("text empty")
    if len(out.encode("utf-8")) <= MAX_TEXT_BYTES:
        return out
    head = out.encode("utf-8")[:MAX_TEXT_BYTES - 3].decode("utf-8", "ignore")   # room for "..."
    cut = max(head.rfind(mark) for mark in (". ", "! ", "? ", ".\n", "!\n", "?\n"))
    if cut > len(head) // 3:
        return head[:cut + 1].rstrip()
    word = head.rfind(" ")
    return (head[:word] if word > 0 else head).rstrip(" ,;:\n") + "..."


def reply(req: dict, text: str) -> dict:
    return {"kind": REPLY_KIND, "id": req["id"], "text": clean_text(text)}


def failure(req: dict, reason: str) -> dict:
    """Answer without text: the server writes its fallback journal at once."""
    return {"kind": REPLY_KIND, "id": req["id"], "error": reason}


def offline(req: dict) -> dict:
    """Bench reply without a model (--offline): the facts restated plainly, in English, nothing added."""
    f = req["facts"]
    text = (f"Offline last pages of {f['name']}. {int(f['hours'])} hours survived, {int(f['kills'])} zombies killed."
            + (" Towns: " + ", ".join(f["towns"]) + "." if f["towns"] else ""))
    return reply(req, text)


def write(config: dict, req: dict, call_llm) -> dict:
    """Reply of a last_pages request; call_llm(config, messages, speaker) is the bridge's model call."""
    if config.get("OFFLINE"):
        return offline(req)
    raw = call_llm(config, prompt(req), req["facts"]["name"].split()[0])
    return reply(req, raw)
