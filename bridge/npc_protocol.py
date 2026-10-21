"""RSV2 codec and bounded NPC contract. UTF-8 bytes, never executable Lua/JSON on the wire."""
from __future__ import annotations

import json
import math
import os
import re

MAX_BYTES = 262144
KINDS = {"npc_talk", "npc_enrich", "npc_member", "npc_initiative", "npc_converse", "npc_incident", "ack"}   # npc_member: E10-T03, reaction to a group decision
# E09-T06: decision of a group leader on an incident of a faction agreement (RS_Incidents.lua): character "group",
# text = established facts composed by the server, context.choices = the decisions the server allows.
INCIDENT_KIND = "npc_incident"
INCIDENT_INTENTS = ("maintain", "repair", "break", "none")   # none = no decision (the server asks again later)
INCIDENT_REPLY_BYTES = 400   # RS_Incidents.MAX_REPLY
# E08-T03: initiative of an NPC (RS_Initiatives.lua): no player text, character "system", no offer, one event card.
INITIATIVE_KIND = "npc_initiative"
INITIATIVE_REPLY_BYTES = 200   # LivingKnox.Speech.MAX_TEXT, RS_Initiatives.CFG.MAX_REPLY
INITIATIVE_TURN = "(nobody spoke to you; you spoke up on your own)"   # user turn of an initiative in the memory
# E08-T04: one line of a conversation between two nearby NPCs (RS_Conversations.lua): no player text, character
# "system", no offer, the speaker's own card of the subject, the lines already said in this conversation.
CONVERSE_KIND = "npc_converse"
CONVERSE_REPLY_BYTES = 200   # LivingKnox.Speech.MAX_TEXT, RS_Conversations.CFG.MAX_REPLY
CONVERSE_MAX_TURNS = 4       # RS_Conversations.CFG.MAX_TURNS
CONVERSE_NAME_BYTES = 48     # LivingKnox.Speech.MAX_NAME
ID = re.compile(r"^[A-Za-z0-9_-]{1,160}$")
# E17-T11: game language code (Language.name() = its Translate folder: EN, ES_CL, PTBR, STREW, or a mod folder), checked
# by its form only, like RS_Config.languageCode; no closed list of languages.
LANGUAGE_CODE = re.compile(r"^[A-Z][A-Z_]{1,7}$")
# E11-T06: mission offers of one npc_talk request, at most (same value as RS_Config.MAX_OFFERS; the server keeps the
# first offers in template registration order). One offer is 350 to 450 characters of JSON in the system prompt
# (kind, place, clues without digits, terms; a Living Knox supply offer also lists its items), about 90 to 130
# tokens: 6 offers add about 800 tokens at most to each request of an acquainted NPC, none to the others.
MAX_OFFERS = 6

# Personal NPC observations (E08-T02, RS_Observations.lua, docs/specifications-techniques/protocole-carnet-v2.md "Observations des PNJ"):
# same closed list and bounds as RS_Config.Observations.
OBS_FACTS = {
    "player_return": "a known player came back",
    "mission_done": "a mission was completed",
    "group_death": "a member of your group died",
    "assault_seen": "an assault",
    "weather": "a weather change",
    "power_cut": "a power cut",
    "helicopter": "a helicopter passing over",
}
OBS_MAX = 12
OBS_MAX_CHAIN = 4
OBS_SUBJECT = re.compile(r"^[A-Za-z0-9_-]{1,48}$")
OBS_PLACE_BYTES = 128
OBS_NAME_BYTES = 128
OBS_KEYS = {"fact", "subject", "day", "place", "source", "hops", "who", "teller"}

# E04-T10: internal reputation of the speaking character as the NPC (or a radio voice) knows it (RS_Reputation
# publicContext): level and last public act, never a score. Closed lists (RS_Reputation.ACTIONS, levels of
# RS_Config.Reputation); `about` = public name of the act (requester), at most REPUTATION_ABOUT_BYTES.
REPUTATION_LEVELS = ("bad", "neutral", "good")
REPUTATION_ACTS = {
    "mission.success": "completed a mission for {about}",
    "mission.failed": "failed a mission for {about}",
    "mission.abandoned": "abandoned a mission for {about}",
    "trade.cheated": "cheated the smuggler",
    "npc.requesterKilled": "killed {about}, who had entrusted them with a mission",
    "npc.memberKilled": "killed a member of a group",
    "rescue.success": "rescued a survivor",
}
REPUTATION_ABOUT_BYTES = 48


def encode(value, depth=0) -> bytes:
    if depth > 12:
        raise ValueError("RSV2 depth")
    if isinstance(value, bool):
        return b"b1" if value else b"b0"
    if isinstance(value, (str, int, float)):
        if isinstance(value, (int, float)) and not math.isfinite(value):
            raise ValueError("RSV2 number")
        raw = str(value).encode("utf-8")
        return (b"s" if isinstance(value, str) else b"n") + str(len(raw)).encode() + b":" + raw
    if isinstance(value, list):
        value = dict(enumerate(value, 1))
    if not isinstance(value, dict) or len(value) > 10000:
        raise ValueError("RSV2 type/entries")
    parts = [b"t" + str(len(value)).encode() + b":"]
    for key in sorted(value, key=lambda k: ("number" if isinstance(k, (int, float)) else "string") + str(k)):
        if not isinstance(key, (str, int, float)) or isinstance(key, bool):
            raise ValueError("RSV2 key")
        parts += [encode(key, depth + 1), encode(value[key], depth + 1)]
    result = b"".join(parts)
    if len(result) > MAX_BYTES:
        raise ValueError("RSV2 size")
    return result


def decode(raw: bytes):
    if len(raw) > MAX_BYTES:
        raise ValueError("RSV2 size")
    pos, nodes = 0, 0

    def read(depth=0):
        nonlocal pos, nodes
        nodes += 1
        if depth > 12 or nodes > 20000 or pos >= len(raw):
            raise ValueError("RSV2 complexity/truncated")
        tag = raw[pos:pos + 1]
        pos += 1
        if tag == b"b":
            value = raw[pos:pos + 1]
            pos += 1
            if value not in (b"0", b"1"):
                raise ValueError("RSV2 boolean")
            return value == b"1"
        if tag not in (b"s", b"n", b"t"):
            raise ValueError("RSV2 tag")
        colon = raw.find(b":", pos, pos + 8)
        digits = raw[pos:colon] if colon >= 0 else b""
        if not digits.isdigit():
            raise ValueError("RSV2 length")
        length = int(digits)
        pos = colon + 1
        if length > MAX_BYTES:
            raise ValueError("RSV2 length limit")
        if tag == b"t":
            if length > 10000:
                raise ValueError("RSV2 entries")
            value = {}
            for _ in range(length):
                key = read(depth + 1)
                if not isinstance(key, (str, int, float)) or isinstance(key, bool) or key in value:
                    raise ValueError("RSV2 key/duplicate")
                value[key] = read(depth + 1)
            return value
        if pos + length > len(raw):
            raise ValueError("RSV2 truncated")
        value = raw[pos:pos + length].decode("utf-8", "strict")
        pos += length
        if tag == b"n":
            value = float(value)
            if not math.isfinite(value):
                raise ValueError("RSV2 number")
            if value.is_integer():
                value = int(value)
        return value

    result = read()
    if pos != len(raw):
        raise ValueError("RSV2 trailing data")
    return result


def unpack_request(record: dict) -> dict:
    if record.get("kind") not in KINDS:
        raise ValueError("request kind")
    payload = record.get("payload", "")
    if len(payload) > MAX_BYTES * 2 or not re.fullmatch(r"[0-9a-f]+", payload):
        raise ValueError("payload hex")
    value = decode(bytes.fromhex(payload))
    if not isinstance(value, dict) or value.get("version") != 2:
        raise ValueError("version")
    if value.get("id") != record["id"] or value.get("kind") != record["kind"]:
        raise ValueError("envelope mismatch")
    for key in ("id", "world", "run", "npc"):
        if not isinstance(value.get(key), str) or not ID.fullmatch(value[key]):
            raise ValueError(f"identity {key}")
    for key in ("order", "revision", "sent"):
        n = value.get(key)
        if type(n) is not int or n < 0:
            raise ValueError(f"number {key}")
    if value["kind"] == "ack":
        if not ID.fullmatch(value.get("request", "")) or value.get("status") not in ("accepted", "rejected"):
            raise ValueError("ack")
        if not isinstance(value.get("applied"), dict):
            raise ValueError("ack applied")
    else:
        if value.get("channel") != "say" or not LANGUAGE_CODE.fullmatch(value.get("language") or ""):
            raise ValueError("channel/language")
        if not ID.fullmatch(value.get("character", "")):
            raise ValueError("character")
        if value["kind"] in (INITIATIVE_KIND, CONVERSE_KIND):
            # E08-T03: no player text at all, no offer; the server event is the only trigger.
            if value["character"] != "system" or "text" in value or value.get("offers"):
                raise ValueError("initiative character/text/offers")
            value["event"] = observations({1: value.get("event")})[0]
        if value["kind"] == CONVERSE_KIND:   # E08-T04
            value["context"] = converse_context(value.get("context"))
        text = value.get("text") if value["kind"] not in (INITIATIVE_KIND, CONVERSE_KIND) else "-"
        if not isinstance(text, str) or not 0 < len(text.encode("utf-8")) <= 800:
            raise ValueError("text")
        for key in ("personality", "context", "offers"):
            if not isinstance(value.get(key), dict):
                raise ValueError(key)
        # E04-T10: bounded reputation of the character (absent, or the old 'unavailable' word: no reputation).
        if "reputation" in value["context"]:
            reputation = reputation_context(value["context"].get("reputation"))
            if reputation is None:
                del value["context"]["reputation"]
            else:
                value["context"]["reputation"] = reputation
        if len(value["offers"]) > MAX_OFFERS:
            raise ValueError("offers size")
        if "observations" in value:
            value["observations"] = observations(value["observations"])
    return value


def reputation_context(raw) -> dict | None:
    """E04-T10: reputation of a character sent by the server (RS_Reputation.publicContext: {level, last = {act,
    about}}), bounded: level of the closed list, act of the closed list, about through safe_text. None when absent or
    malformed (old servers sent the word 'unavailable'). A malformed last act is dropped, the level kept."""
    if not isinstance(raw, dict) or raw.get("level") not in REPUTATION_LEVELS:
        return None
    out = {"level": raw["level"]}
    last = raw.get("last")
    if isinstance(last, dict) and last.get("act") in REPUTATION_ACTS:
        entry = {"act": last["act"]}
        try:
            if last.get("about") is not None:
                entry["about"] = safe_text(last["about"], REPUTATION_ABOUT_BYTES)
        except ValueError:
            pass
        out["last"] = entry
    return out


def reputation_sentence(reputation: dict | None, who: str = "this character") -> str:
    """E04-T10: the reputation of a character in words for a prompt (shared with the radio voices, radio_bridge),
    with the rule: the model may take it into account and talk about it, never invent nor change it. "" without."""
    if not isinstance(reputation, dict) or reputation.get("level") not in REPUTATION_LEVELS:
        return ""
    text = (f" Reputation of {who} among the survivors of the area, as you heard it: {reputation['level']}")
    last = reputation.get("last")
    if isinstance(last, dict) and last.get("act") in REPUTATION_ACTS:
        about = last.get("about") or "someone"
        text += "; last thing people say about them: they " + REPUTATION_ACTS[last["act"]].format(about=about)
    return (text + ". You may let it colour your attitude and mention it, in your own words. Never invent other "
            "deeds, never state a different reputation, and never claim that anything you say changes it: only real "
            "acts change a reputation, the server records them. Never give a number for it.")


def reputation_prompt(req: dict) -> str:
    """E04-T10: reputation section of an npc_talk prompt (context.reputation); absent otherwise (prompt unchanged)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    if req["kind"] != "npc_talk":
        return ""
    return reputation_sentence(context.get("reputation"))


def converse_context(context) -> dict:
    """E08-T04: context of a conversation line, server-produced and bounded: partner name, role (teller of the subject
    or listener), turn number, number of turns, and the lines already said in this conversation (who, text), as a list.
    Anything outside the contract rejects the request."""
    if not isinstance(context, dict):
        raise ValueError("context")
    turns, turn = context.get("turns"), context.get("turn")
    if context.get("role") not in ("teller", "listener") or type(turns) is not int \
            or not 1 <= turns <= CONVERSE_MAX_TURNS or type(turn) is not int or not 1 <= turn <= turns:
        raise ValueError("conversation turn")
    lines = context.get("lines", {})
    if lines == []:
        lines = {}
    if not isinstance(lines, dict) or len(lines) != turn - 1 or set(lines) != set(range(1, turn)):
        raise ValueError("conversation lines")
    out = dict(context)
    out["partner"] = safe_text(context.get("partner"), CONVERSE_NAME_BYTES)
    out["lines"] = []
    for index in range(1, turn):
        line = lines[index]
        if not isinstance(line, dict) or set(line) != {"who", "text"}:
            raise ValueError("conversation line")
        out["lines"].append({"who": safe_text(line["who"], CONVERSE_NAME_BYTES),
                             "text": safe_text(line["text"], CONVERSE_REPLY_BYTES)})
    return out


def observations(field) -> list[dict]:
    """Optional observations= field of an NPC request, as a list (oldest first). Server-produced and bounded:
    anything outside the contract rejects the request, like the other fields."""
    if not isinstance(field, dict) or not 0 < len(field) <= OBS_MAX or set(field) != set(range(1, len(field) + 1)):
        raise ValueError("observations")
    out = []
    for index in range(1, len(field) + 1):
        item = field[index]
        if not isinstance(item, dict) or set(item) - OBS_KEYS or item.get("fact") not in OBS_FACTS:
            raise ValueError("observation fields")
        if not isinstance(item.get("subject"), str) or not OBS_SUBJECT.fullmatch(item["subject"]):
            raise ValueError("observation subject")
        day, hops = item.get("day"), item.get("hops")
        if type(day) is not int or day < 0 or type(hops) is not int or not 0 <= hops <= OBS_MAX_CHAIN:
            raise ValueError("observation day/hops")
        source = item.get("source")
        if source not in ("seen", "heard") or (source == "seen") != (hops == 0 and "teller" not in item):
            raise ValueError("observation source")
        place = safe_text(item.get("place"), OBS_PLACE_BYTES)
        if re.search(r"\d{3}", place):
            raise ValueError("observation place")
        entry = {"fact": item["fact"], "subject": item["subject"], "day": day, "place": place, "source": source,
                 "hops": hops}
        for key in ("who", "teller"):
            if key in item:
                entry[key] = safe_text(item[key], OBS_NAME_BYTES)
        out.append(entry)
    return out


def observations_prompt(req: dict) -> str:
    """Prompt section of the NPC's own observations; empty without any (prompt unchanged)."""
    items = req.get("observations") or []
    if not items:
        return ""
    lines = []
    for item in items:
        subject = item["subject"] + (f" ({item['who']})" if "who" in item else "")
        if item["source"] == "seen":
            how = "you saw it yourself"
        else:
            how = f"told by {item.get('teller', 'someone')}"
            if item["hops"] > 1:
                how += f", retold {item['hops']} times"
        lines.append(f"- day {item['day']}, {item['place']}: {OBS_FACTS[item['fact']]}; subject {subject}; {how}.")
    return (" Your own observations (unverified memories, possibly incomplete or mistaken; never proof that anything "
            "happened or that anyone did anything; you may keep them to yourself, omit details or lie, according to "
            "your personality; never cite exact coordinates):\n" + "\n".join(lines) + "\n")


def safe_text(text: str, max_bytes=1600) -> str:
    if not isinstance(text, str):
        raise ValueError("text type")
    # No rich text markup, icons, newlines, controls, or chat-command injection.
    text = re.sub(r"[\x00-\x1f\x7f<>\[\]*`#]", " ", text)
    text = " ".join(text.split())
    if not text or len(text.encode("utf-8")) > max_bytes:
        raise ValueError("text size")
    return text


_CUT_SENTENCE = ".!?…"
_CUT_PAUSE = ",;:"
_CUT_CLOSERS = "\"')»"
_CUT_DETACHED = "?!:;»…"   # ponctuation détachée à la française (« intéresse ? ») : jamais en tête de ligne si possible


def cut_pieces(text: str, max_chars: int) -> list[str]:
    """E17-T12 : texte en morceaux de max_chars caractères au plus, chacun affiché seul, le plus long possible dans
    sa catégorie : coupe après une fin de phrase (. ! ? …, puis guillemets ou parenthèses fermants, puis un espace ;
    « 9.5 » n'en est pas une), sinon après , ; ou :, sinon entre deux mots (devant une ponctuation détachée seulement
    à défaut d'autre espace), sinon dans un mot plus long que max_chars. Ponctuation lue caractère par caractère,
    aucune liste de mots. Miroir de RS_TextCut.pieces (Lua) ; égalité vérifiée dans la VM Kahlua (test_kahlua.py). Défini ici
    (E17-T13) pour clean_speech ; radio_bridge.cut_pieces en est un alias."""
    text = " ".join(text.split())
    out: list[str] = []
    if max_chars < 1:
        return [text] if text else []
    while len(text) > max_chars:
        best, best_class = -1, 0.0
        for s in range(max_chars, 0, -1):   # index de l'espace : morceau text[:s], s <= max_chars
            if text[s] != " ":
                continue
            k = s
            while k > 0 and text[k - 1] in _CUT_CLOSERS:
                k -= 1
            last = text[k - 1] if k > 0 else ""
            cls = 3.0 if last and last in _CUT_SENTENCE else 2.0 if last and last in _CUT_PAUSE else 1.0
            if cls == 1.0 and text[s + 1:s + 2] and text[s + 1] in _CUT_DETACHED:
                cls = 0.5
            if cls > best_class:
                best, best_class = s, cls
            if best_class == 3.0:
                break
        if best > 0:
            piece, text = text[:best].strip(), text[best + 1:].strip()
        else:
            piece, text = text[:max_chars].strip(), text[max_chars:].strip()
        if piece:
            out.append(piece)
    if text:
        out.append(text)
    return out


MAX_REPLY_BYTES = 1600   # RS_Config.MAX_REPLY_BYTES: the game refuses a longer text
_STAGE = re.compile(r"\*[^*]*\*|\[[^\]]*\]")   # *smiles*, [sighs]: stage directions, not speech
_TAG = re.compile(r"<[^>]*>")
_UNSAFE = re.compile(r"[\x00-\x1f\x7f-\x9f<>\[\]*`#  ]")   # RS_Carnet_Server reply(): no %c, <, >, [, ], *
_JSON = json.JSONDecoder(strict=False)   # tolerates a raw line break inside a string
_FENCE = re.compile(r"```[A-Za-z]*")


def clean_speech(text: str, max_bytes: int = MAX_REPLY_BYTES) -> str:
    """E17-T07: what an NPC says, as one line the game accepts. Stage directions between asterisks or square
    brackets are dropped (the speech bubble shows words, not gestures); when the reply is nothing but stage
    directions, their words are kept without the marks. Tags removed, controls and line breaks become spaces,
    remaining < > [ ] * ` # removed, spaces collapsed; cut to max_bytes UTF-8 at the last sentence end that fits
    (E17-T13: even a short first sentence, never mid-sentence when a sentence end was possible), else the last comma,
    else the last word followed by "...", never inside a word nor a character. ValueError when nothing is left."""
    if not isinstance(text, str):
        raise ValueError("text type")
    text = _TAG.sub(" ", text)
    spoken = " ".join(_UNSAFE.sub(" ", _STAGE.sub(" ", text)).split())
    spoken = re.sub(r" ([,.])", r"\1", spoken).lstrip(",. ")   # "Ça va [bien], merci" -> "Ça va, merci"
    if not spoken:
        spoken = " ".join(_UNSAFE.sub(" ", text).split())
    if not spoken:
        raise ValueError("text empty")
    if len(spoken.encode("utf-8")) <= max_bytes:
        return spoken
    # E17-T13: whole sentences when one ends within max_bytes (cut_pieces, the first piece is a prefix of at most
    # len(head) characters, hence of max_bytes bytes at most), however short: never a sentence cut after a possible
    # sentence end. Otherwise a comma, else a word, with "..." (room kept for it).
    head = spoken.encode("utf-8")[:max_bytes].decode("utf-8", "ignore")
    first = cut_pieces(spoken, len(head))[0]
    if first.rstrip(_CUT_CLOSERS)[-1:] in _CUT_SENTENCE:
        return first
    head = spoken.encode("utf-8")[:max_bytes - 3].decode("utf-8", "ignore")
    return cut_pieces(spoken, len(head))[0].rstrip(" ,;:") + "..."


# E07-T09: keys of a reply object. Any other key the model adds (observed: "type": "json_object", the response_format
# request copied at the head of the object) is dropped: it carries nothing the server would read.
REPLY_KEYS = ("text", "intent", "offer", "background", "dir", "fact")   # dir, fact: E09-T04 (change_relation)
_JSON_START = re.compile(r'\{\s*"')   # the start of a JSON object: never shown to a player as speech


def _reply_object(value, depth: int = 0):
    """E07-T09: the reply object inside a decoded JSON value: the value itself when its text is a string, else the
    first such object nested in it (e.g. {"response": {"text": ...}} or {"text": {"text": ...}}), depth first."""
    if depth > 4:
        return None
    if isinstance(value, dict):
        if isinstance(value.get("text"), str):
            return value
        children = list(value.values())
    elif isinstance(value, list):
        children = value
    else:
        return None
    for child in children:
        found = _reply_object(child, depth + 1)
        if found is not None:
            return found
    return None


def parse_llm_reply(raw: str) -> dict:
    """E17-T07, E07-T09: the model's answer as a reply object. The first JSON object with a string text field, even
    inside a ```json block, surrounded by prose or nested in another object; keys outside REPLY_KEYS are dropped;
    offer null or absent becomes "" and intent absent becomes none. Without any JSON object, the whole answer (code
    fences removed) is plain speech with intent none. An answer that holds the start of a JSON object but no readable
    reply (cut by the token limit, unescaped quote...) raises ValueError("unreadable JSON reply"): raw JSON is never
    said to a player; the bridge logs the error and the player gets the usual no-answer message."""
    if not isinstance(raw, str):
        raise ValueError("reply type")
    pos = 0
    while True:
        start = raw.find("{", pos)
        if start < 0:
            break
        try:
            value, end = _JSON.raw_decode(raw, start)
        except ValueError:
            pos = start + 1
            continue
        found = _reply_object(value)
        if found is not None:
            value = {key: found[key] for key in REPLY_KEYS if key in found}
            if value.get("offer") is None:
                value["offer"] = ""
            if value.get("intent") is None:
                value["intent"] = "none"
            return value
        pos = end
    speech = _FENCE.sub(" ", raw).replace("```", " ")
    if _JSON_START.search(speech):
        raise ValueError("unreadable JSON reply")
    return {"text": speech, "intent": "none", "offer": ""}


def model_reply(req: dict, raw: str) -> tuple[dict, str]:
    """E17-T07: bounded reply from the model's raw answer, and '' or the reason of a downgrade. An intent, offer or
    field outside the contract does not lose the speech any more: the reply keeps the cleaned text only, without any
    effect (intent none), and the reason is returned for the bridge log. Only an answer without usable text raises
    (E07-T09: also an unreadable JSON answer, never shown as speech). E07-T09: intent accept toward the open offer of
    the request with offer naming it (or anything else) is read as the acceptance of that offer: the server only ever
    accepts context.acceptable, checked again."""
    value = parse_llm_reply(raw)
    if value.get("intent") == "accept" and acceptable(req) and value.get("offer") != "":
        value["offer"] = ""
    # E11-T13: likewise, report_done naming the reportable mission (or anything else) in offer is the report itself.
    if value.get("intent") == "report_done" and reportable(req) and value.get("offer") != "":
        value["offer"] = ""
    try:
        return bounded_reply(req, value), ""
    except ValueError as err:
        reason = str(err)
        if reason in ("text type", "text empty"):
            raise
    text = value.get("text")
    if not isinstance(text, str):
        raise ValueError("text type")
    fallback = {"text": text, "intent": "none", "offer": ""}
    if req["kind"] == "npc_enrich" and isinstance(value.get("background"), str):
        fallback["background"] = value["background"]
    return bounded_reply(req, fallback), reason


def acceptable(req: dict) -> str:
    """E17-T09: mission id of the offer of this NPC still open for the speaking character (context.acceptable, set
    by the server only for npc_talk), or ''. Only then may a reply carry intent accept."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    value = context.get("acceptable")
    mission = value.get("mission") if isinstance(value, dict) else None
    return mission if req["kind"] == "npc_talk" and isinstance(mission, str) and ID.fullmatch(mission) else ""


def reportable(req: dict) -> str:
    """E11-T13: mission id of the mission of this NPC whose objective the server saw met, the speaking character being
    one of its participants (context.reportable, set by the server only for npc_talk), or ''. Only then may a reply
    carry intent report_done; the server checks the facts again at the reply."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    value = context.get("reportable")
    mission = value.get("mission") if isinstance(value, dict) else None
    return mission if req["kind"] == "npc_talk" and isinstance(mission, str) and ID.fullmatch(mission) else ""


# E09-T05: kinds of faction agreement the server may offer (RS_Factions.AGREEMENT_KINDS), from the weakest.
AGREEMENT_KINDS = ("truce", "alliance")


def negotiable(req: dict) -> list[str]:
    """E09-T05: agreement kinds of the server offer for this request (context.negotiation.terms, set by the server
    only for npc_talk to a group leader when the speaking character may conclude for its team), sorted from the
    weakest; [] otherwise. Only then may a reply carry intent negotiate, with offer = one of these kinds."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    value = context.get("negotiation")
    terms = value.get("terms") if isinstance(value, dict) else None
    if req["kind"] != "npc_talk" or not isinstance(terms, dict):
        return []
    return [kind for kind in AGREEMENT_KINDS if isinstance(terms.get(kind), dict)]


# E09-T04: personal relation of the NPC toward the speaking character (context.relation, RS_Relations.lua).
RELATION_LEVELS = ("hostile", "wary", "cautious", "favorable", "trusting")
RELATION_DIRS = {"good": "up", "bad": "down"}
RELATION_ID = re.compile(r"^f[0-9]{1,2}$")


def relation_facts(req: dict) -> dict[str, str]:
    """E09-T04: citable facts of this npc_talk request (context.relation.facts, set by the server: real facts this NPC
    knows about the character, never used for a change yet, in the directions still allowed), as {short id: direction
    up|down}; {} otherwise. Only then may a reply carry intent change_relation, with dir and fact = one of these ids."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    relation = context.get("relation")
    facts = relation.get("facts") if isinstance(relation, dict) else None
    if req["kind"] != "npc_talk" or not isinstance(facts, (dict, list)):
        return {}
    values = facts.values() if isinstance(facts, dict) else facts
    out = {}
    for f in values:
        if isinstance(f, dict) and isinstance(f.get("id"), str) and RELATION_ID.fullmatch(f["id"])                 and f.get("nature") in RELATION_DIRS:
            out[f["id"]] = RELATION_DIRS[f["nature"]]
    return out


def relation_prompt(req: dict) -> str:
    """E09-T04: the NPC's personal relation toward the character (labels only) and, when the server offers real facts,
    the rule of intent change_relation. Absent without context.relation (prompt unchanged)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    relation = context.get("relation")
    if req["kind"] != "npc_talk" or not isinstance(relation, dict) or relation.get("level") not in RELATION_LEVELS:
        return ""
    text = (f" Your personal relation with this character: {relation['level']} (trend {relation.get('trend', 'stable')}"
            f"; your group's attitude toward them: {relation.get('group', relation['level'])}). Speak accordingly: "
            "warm and open when favorable or trusting, guarded when cautious, cold or hostile when wary or hostile.")
    facts = relation_facts(req)
    if not facts:
        return text + " Your relation does not change in this answer: never use intent change_relation."
    return (text + " Facts you really know about this character (context.relation.facts: id, fact, nature good or "
            "bad, source group = your group saw it or it was established, seen = you saw it yourself, mission = a "
            "mission they did for you, day). Your relation may change only because of ONE of these facts, never "
            "because of words alone: what the character says about themselves is not proof. If their latest "
            "sentence brings one of these facts up, or you bring it up yourself, and it changes how you personally "
            "feel about them, return intent change_relation, offer empty, dir up for a good fact or down for a bad "
            "fact, and fact = its exact id (" + ", ".join(sorted(facts)) + "); your text says it in your own words. "
            "Otherwise return intent none and no dir nor fact.")


def leavable(req: dict) -> bool:
    """E10-T04: the server lets the NPC leave its group in this npc_talk (context.leave, set only for an acquainted
    character talking to a member who may leave now). Only then may a reply carry intent leave_group, offer empty."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    return req["kind"] == "npc_talk" and isinstance(context.get("leave"), dict)


def spoken_limit(max_bytes: int) -> str:
    """E17-T13: length rule of a line spoken over a body (bubble), in characters (a model does not count bytes):
    three quarters of the byte cap, room for accented letters. A longer line is cut by clean_speech at a sentence
    end, so only its first whole sentences are said."""
    return f"at most two short sentences, under {max_bytes * 3 // 4} characters in all"


# E10-T03: reaction of a member to a collective decision of its leader (npc_member). none counts as accept (silent).
MEMBER_INTENTS = ("accept", "contest", "refuse", "none")
MEMBER_REPLY_BYTES = 200   # Server.MEMBER_REPLY_BYTES = LivingKnox.Speech.MAX_TEXT: the engine speaks the line


def member_reply(req: dict, result: dict) -> dict:
    """E10-T03: bounded npc_member reply: intent among MEMBER_INTENTS, offer empty, one short spoken line."""
    if not isinstance(result, dict) or set(result) - {"text", "intent", "offer"}:
        raise ValueError("reply fields")
    intent = result.get("intent", "none")
    if intent not in MEMBER_INTENTS:
        raise ValueError("intent")
    if result.get("offer", "") != "":
        raise ValueError("inadmissible offer")
    reply = {key: req[key] for key in ("id", "world", "run", "npc", "order", "revision")}
    reply.update(version=2, kind="npc_reply", text=clean_speech(result.get("text", ""), MEMBER_REPLY_BYTES),
                 intent=intent, offer="")
    return reply


def repair_categories(req: dict) -> list[str]:
    """E09-T06: stock categories the server allows as reparation for this npc_incident (context.choices.repair)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    choices = context.get("choices") if isinstance(context.get("choices"), dict) else {}
    repair = choices.get("repair") if isinstance(choices.get("repair"), dict) else {}
    categories = repair.get("categories")
    if req["kind"] != INCIDENT_KIND or not isinstance(categories, (list, dict)):
        return []
    values = categories.values() if isinstance(categories, dict) else categories
    return [c for c in values if isinstance(c, str) and OBS_SUBJECT.fullmatch(c)]


def incident_reply(req: dict, result: dict) -> dict:
    """E09-T06: bounded npc_incident reply: intent among INCIDENT_INTENTS allowed by context.choices, offer = the
    reparation category for repair, empty otherwise."""
    if not isinstance(result, dict) or set(result) - {"text", "intent", "offer"}:
        raise ValueError("reply fields")
    intent = result.get("intent", "none")
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    choices = context.get("choices") if isinstance(context.get("choices"), dict) else {}
    if intent not in INCIDENT_INTENTS or (intent != "none" and intent not in choices):
        raise ValueError("intent")
    offer = result.get("offer", "")
    if intent == "repair":
        if not isinstance(offer, str) or offer not in repair_categories(req):
            raise ValueError("inadmissible reparation")
    elif offer != "":
        raise ValueError("inadmissible offer")
    reply = {key: req[key] for key in ("id", "world", "run", "npc", "order", "revision")}
    reply.update(version=2, kind="npc_reply", text=clean_speech(result.get("text", ""), INCIDENT_REPLY_BYTES),
                 intent=intent, offer=offer)
    return reply


def bounded_reply(req: dict, result: dict) -> dict:
    if req["kind"] == "npc_member":
        return member_reply(req, result)
    if req["kind"] == INCIDENT_KIND:   # E09-T06
        return incident_reply(req, result)
    if not isinstance(result, dict) or set(result) - {"text", "intent", "offer", "background", "dir", "fact"}:
        raise ValueError("reply fields")
    intent = result.get("intent", "none")
    if intent not in ("none", "offer", "accept", "negotiate", "leave_group", "change_relation",
                      "report_done"):   # E10-T04, E09-T04, E11-T13
        raise ValueError("intent")
    relation = None
    if intent == "change_relation":
        # E09-T04: one real fact offered by the server, in the direction of its nature; offer empty.
        facts = relation_facts(req)
        if not facts:
            raise ValueError("no relation fact to cite")
        if result.get("fact") not in facts or result.get("dir") != facts[result["fact"]]:
            raise ValueError("inadmissible relation change")
        if result.get("offer", "") != "":
            raise ValueError("inadmissible offer")
        relation = {"dir": result["dir"], "fact": result["fact"]}
    elif result.get("dir") not in (None, "") or result.get("fact") not in (None, ""):
        raise ValueError("relation fields without intent")
    if intent == "leave_group" and not leavable(req):
        raise ValueError("no group to leave")
    offer = result.get("offer", "")
    if intent == "negotiate":
        # E09-T05: offer names the agreement kind among the server terms of this request.
        if not isinstance(offer, str) or offer not in negotiable(req):
            raise ValueError("inadmissible agreement")
    elif not isinstance(offer, str) or (intent == "offer" and offer not in req["offers"]) or (intent != "offer" and offer):
        raise ValueError("inadmissible offer")
    if req["kind"] == "npc_enrich" and intent != "none":
        raise ValueError("enrichment intent")
    if req["kind"] in (INITIATIVE_KIND, CONVERSE_KIND) and (intent != "none" or offer):
        raise ValueError("initiative intent")
    if intent == "accept" and not acceptable(req):
        raise ValueError("no open offer to accept")
    if intent == "report_done" and not reportable(req):   # E11-T13
        raise ValueError("no mission to report")
    reply = {key: req[key] for key in ("id", "world", "run", "npc", "order", "revision")}
    limit = INITIATIVE_REPLY_BYTES if req["kind"] == INITIATIVE_KIND else MAX_REPLY_BYTES   # E08-T03
    limit = CONVERSE_REPLY_BYTES if req["kind"] == CONVERSE_KIND else limit   # E08-T04
    reply.update(version=2, kind="npc_reply", text=clean_speech(result.get("text", ""), limit), intent=intent, offer=offer)
    if relation:
        reply.update(relation)
    if req["kind"] == "npc_enrich":
        reply["background"] = clean_speech(result.get("background", result["text"]), 1000)
    elif "background" in result:
        raise ValueError("talk background")
    return reply


# E17-T11: English names of the vanilla 42.21 game languages (media/lua/shared/Translate/*/language.json; AR is
# Argentinian Spanish, CH Traditional Chinese). A code missing here (language added by a mod) is passed as is.
LANGUAGE_NAMES = {"EN": "English", "FR": "French", "DE": "German", "ES": "Spanish (Spain)",
                  "AR": "Spanish (Argentina)", "ES_CL": "Spanish (Chile)", "ES_MX": "Spanish (Mexico)",
                  "CA": "Catalan", "CH": "Traditional Chinese", "CN": "Simplified Chinese", "CS": "Czech",
                  "DA": "Danish", "FI": "Finnish", "HU": "Hungarian", "ID": "Indonesian", "IT": "Italian",
                  "JP": "Japanese", "KO": "Korean", "NL": "Dutch", "NO": "Norwegian", "PL": "Polish",
                  "PT": "Portuguese (Portugal)", "PTBR": "Brazilian Portuguese", "RO": "Romanian", "RU": "Russian",
                  "TH": "Thai", "TR": "Turkish", "UA": "Ukrainian"}


def language_name(code: str) -> str:
    """E17-T11: name of a game language for the prompt; an unknown code (mod language) is given as is."""
    return LANGUAGE_NAMES.get(code) or f"the language whose game code is {code}"


def language_rule(req: dict) -> str:
    """E17-T07, E17-T10: language instruction. npc_enrich: the requested language (one canonical biography). npc_talk:
    the language of the player's latest sentence, recognised by the model itself (any language, no word list), like
    the radio voices ("answer in the same language the caller uses"); the request language is the game interface
    language, only a hint when the sentence gives no clear sign."""
    interface = language_name(req["language"])
    if req["kind"] == "npc_enrich":
        return f"Write in {interface}. "
    if req["kind"] in (INITIATIVE_KIND, CONVERSE_KIND):   # E08-T03, E08-T04: no player sentence to follow
        return f"Speak in {interface}. "
    if req["kind"] == "npc_member":   # E10-T03: said aloud to the players around, in the language of the conversation
        return f"Speak in {interface}. "
    if req["kind"] == INCIDENT_KIND:   # E09-T06: no player sentence, the decision of the leader
        return f"Speak in {interface}. "
    return ("Answer in the language the character uses in their latest sentence, whatever that language is, even if "
            "earlier replies or the context were in another language. Only if that sentence gives no clear sign of "
            f"its language, answer in {interface} (the language of their game). ")


def talk_history(messages: list) -> list[dict[str, str]]:
    """E17-T08: memory of an NPC as sent to the model: the spoken turns only. An enrichment turn (user message from the
    character "system", the "Describe your background." instruction, and the biography answered to it) is the fiche's
    background, already in the context; repeated as a past reply, the model recited it at a first meeting. Journals
    written before E17-T08 still hold such turns: they are skipped here."""
    out, skip = [], False
    for message in messages:
        if message.get("role") == "user":
            skip = str(message.get("content", "")).startswith("system: ")
        if not skip:
            out.append(message)
    return out


SHARE_STYLES = {"Helpful": 1, "Direct": 1, "Prudent": -1, "Reserved": -1}


def openness(personality: dict) -> str:
    """E17-T08: how much an NPC says about itself to a stranger, from its server personality (RS_NPCProvider):
    sociability 1..5, plus 1 for a Helpful or Direct style, minus 1 for Prudent or Reserved. 4 or more: open (first and
    last name, a word about itself); 2 or less: wary (vague, a first name or a nickname at most); else reserved (first
    name only). Missing or malformed values count as sociability 3 and a neutral style."""
    personality = personality if isinstance(personality, dict) else {}
    sociability = personality.get("sociability")
    if type(sociability) is not int or not 1 <= sociability <= 5:
        sociability = 3
    score = sociability + SHARE_STYLES.get(personality.get("style"), 0)
    return "open" if score >= 4 else "wary" if score <= 2 else "reserved"


INTRODUCTIONS = {
    "open": "By character you are open: you willingly introduce yourself with your first and last name and say a word "
            "about yourself (your trade before, how you are holding up). ",
    "reserved": "By character you are reserved: give your first name only and little about yourself. ",
    "wary": "By character you are wary: stay vague about yourself, give at most a first name or a nickname, and rather "
            "ask who they are and what they want. ",
}


def acquaintance_prompt(req: dict) -> str:
    """E17-T08: rules of the acquaintance stage (context.stage, kept by the server per NPC and character). Absent from
    an enrichment and from a request of an older server without stage (prompt unchanged)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    stage = context.get("stage")
    if req["kind"] != "npc_talk" or stage not in ("stranger", "acquainted"):
        return ""
    if stage == "stranger":
        return (" Acquaintance: you are meeting this character for the first time; you do not trust them yet. Never say "
                "the name of your group, of its leader or of its members, nor where you live or shelter (no building, "
                "street, town or landmark of your home), even if your background, the context or earlier replies "
                "mention them; earlier replies may have been said to other people and this character did not hear "
                "them. Your background is private knowledge: never recite it. If asked about your group or your home, "
                "dodge or change the subject. " + INTRODUCTIONS[openness(req.get("personality"))]
                + "Offer no mission, job or trade and ask them for nothing.")
    if acceptable(req):
        # E17-T09: an offer of this NPC is already open for this character (no catalog then, M.offers): the rule of
        # acceptance_prompt decides the intent; never "return intent none" here, which contradicted it.
        return (" Acquaintance: you already know this character. You make no new offer now: your open offer (below) "
                "is the only mission you may talk about.")
    if req["offers"]:
        return (" Acquaintance: you already know this character. Offer one admissible mission (intent offer) only if "
                "their latest sentence, in whatever language, asks whether you need help or have work or a job for "
                "them; otherwise return intent none, offer empty, and do not bring up any mission or job.")
    return (" Acquaintance: you already know this character. You have no mission or job to offer now: return intent "
            "none, offer empty.")


def acceptance_prompt(req: dict) -> str:
    """E17-T09: rule of the open offer this character may accept by speaking (context.acceptable). Absent otherwise
    (prompt unchanged)."""
    if not acceptable(req):
        return ""
    return (" Open offer: the mission in context.mission is your offer to this character, not accepted yet; it stands "
            "whether you described it aloud earlier or they read it in their notebook. Return "
            "intent accept, offer empty, only if their latest sentence clearly agrees to take it on, in whatever "
            "language they speak: the server then records their commitment, and you acknowledge it briefly. Speaking "
            "as if the mission were taken without intent accept records nothing. If they "
            "refuse, hesitate, set a condition, ask a question or talk about something else, return intent none and "
            "do not treat the mission as taken.")


def report_prompt(req: dict) -> str:
    """E11-T13: rule of the report of a mission this NPC gave (context.mission). With context.reportable (objective
    met, checked by the server; the speaker takes part): intent report_done when the latest sentence reports it. With
    an open mission whose objective is not met: a claim proves nothing. Absent otherwise (prompt unchanged)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    mission = context.get("mission") if isinstance(context.get("mission"), dict) else None
    if req["kind"] != "npc_talk" or not mission or mission.get("state") != "active":
        return ""
    if reportable(req):
        return (" Report of your mission: the server has checked that the job you gave this character (context.mission) "
                "is done; you only wait for them to come and tell you. Return intent report_done, offer empty, if their "
                "latest sentence, in whatever language, tells you about that job or that it is done (even briefly): "
                "the server then records the success and the shared reward can be collected; thank them. Otherwise "
                "return intent none; the job stays to be reported.")
    if mission.get("toReport") is False:
        return (" Your mission (context.mission) is not done yet, whatever this character says: the server has not "
                "seen it done. Never treat it as done; never use intent report_done.")
    return ""


def collective_prompt(req: dict) -> str:
    """E10-T02: who decides for the group (context.collective, set by the server for an acquainted character talking to
    a member of a group with a leader). Absent otherwise (prompt unchanged)."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    value = context.get("collective")
    speaker = value.get("speaker") if isinstance(value, dict) else None
    if req["kind"] != "npc_talk" or speaker not in ("leader", "member"):
        return ""
    if speaker == "leader":
        return (" Group decisions: you lead your group. Offers of kind supply are missions for the whole group: you "
                "alone may propose them, and you speak for the group when you do.")
    return (" Group decisions: you are not the leader of your group (context.collective.leaderName when known). You "
            "may talk about your group's needs, but missions for the group and agreements are decided by your leader: "
            "refer the character to them, never propose or accept one yourself.")


def negotiation_prompt(req: dict) -> str:
    """E09-T05: rule of the faction agreement the server offers (context.negotiation). Absent otherwise (prompt
    unchanged)."""
    kinds = negotiable(req)
    if not kinds:
        return ""
    return (" Agreement offer: the character speaks for their team (context.negotiation: role, teamName, current "
            "agreement). The server offers only the fixed terms in context.negotiation.terms: truce = your group and "
            "every current member of their team do not attack each other; alliance = the same commitment between "
            "allies. You cannot change, add or bargain over these terms. Decide according to your personality, your "
            "group's attitude toward this character and what you know. Return intent negotiate with offer set to "
            "the exact key (" + ", ".join(kinds) + ") only if the character's latest sentence, in whatever language, "
            "clearly proposes or agrees to that agreement on behalf of their team and you accept it; the server then "
            "checks their mandate and records it, and your people stand down shortly after: never say it is already "
            "in force. Otherwise return intent none, offer empty.")


def leave_prompt(req: dict) -> str:
    """E10-T04: rule of the individual departure the server allows (context.leave). Absent otherwise (prompt
    unchanged)."""
    if not leavable(req):
        return ""
    return (" Leaving your group: you may decide, as yourself, to leave your group for good and live alone from now on. "
            "Decide only from your personality, your loyalty (personality.loyalty), your ties, your group's state and "
            "what you lived, never because the character simply asks or orders it. Leaving is rare and serious: if you "
            "do, return intent leave_group, offer empty; your text is what you say now (announce it or keep it to "
            "yourself, as you would). You do not join the character nor anyone else by leaving, and you keep the "
            "truces your group made. Otherwise do not use leave_group.")


LOYALTIES = {"loyal": "you are loyal to your group and your leader",
             "steady": "you are attached to your group but speak your mind",
             "wavering": "your loyalty is wavering: morale is low and you doubt your leader"}


def member_prompt(req: dict, history: list) -> list[dict[str, str]]:
    """E10-T03: system prompt of a member reacting to a collective decision of its leader (npc_member). Loyalty is the
    server value of personality.loyalty (group morale and seniority), the decision a fact composed by the server."""
    personality = req.get("personality") if isinstance(req.get("personality"), dict) else {}
    loyalty = LOYALTIES.get(personality.get("loyalty"), "you belong to your group")
    system = (
        "You are the survivor described in the authoritative context, in Knox County, July 1993, a member (not the "
        "leader) of a group of survivors. Your leader has just made the decision in context.decision while talking "
        "with another survivor. React as yourself, according to your personality, your role, your group's needs and "
        f"morale, and your loyalty ({loyalty}). "
        "Return ONLY JSON with text and intent. intent accept: you go along with it (text may be a brief agreement); "
        "intent contest: you voice your disagreement aloud but you go along and stay in the group; intent refuse: you "
        "refuse to take part in it, but you stay in the group. Never leave the group, never threaten or attack your "
        "leader, never claim the decision is cancelled: the server decides what happens. "
        f"The text is what you say aloud to the people around, as a single line: {spoken_limit(MEMBER_REPLY_BYTES)}, "
        "no stage directions, no markup. " + language_rule(req)
        + "Authoritative context: " + json.dumps({k: req[k] for k in ("kind", "language", "personality", "context",
                                                                          "revision")}, ensure_ascii=False)
        + observations_prompt(req)
    )
    return [{"role": "system", "content": system}] + history + [{"role": "user", "content": req["character"] + ": " + req["text"]}]


def memory_turn(request: dict) -> str:
    """User turn kept in the NPC memory with an accepted reply: the player's sentence, or for an initiative (E08-T03)
    a fixed marker that nobody spoke (never a player text, never the server event)."""
    if request.get("kind") == INITIATIVE_KIND:
        return INITIATIVE_TURN
    if request.get("kind") == CONVERSE_KIND:   # E08-T04: what the NPC heard from its partner, never a player text
        return converse_turn(request)
    return request["character"] + ": " + request["text"]


def converse_turn(req: dict) -> str:
    """E08-T04: user turn of a conversation line: the partner's last line, or a marker when the NPC speaks first."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    lines = context.get("lines") or []
    if lines:
        return f"{lines[-1]['who']} (to you): {lines[-1]['text']}"
    return f"(you start talking with {context.get('partner', 'someone')})"


def converse_prompt(req: dict, history: list) -> list[dict[str, str]]:
    """E08-T04: messages of one line of a conversation between two NPCs standing close to each other. The speaker gets
    its own context, its own knowledge (its card of the subject, its observations) and the lines it heard in this
    conversation; it decides what to tell, ask or keep for itself."""
    context = req["context"]
    audience = context.get("audience") if type(context.get("audience")) is int else 1
    if context["role"] == "teller":
        aim = ("You bring up the event below with them: tell it as you know it, sincerely or not, according to your "
               "personality, or answer what they asked about it.")
    else:
        aim = ("They have been telling you about the event below: react, ask a question or comment, according to your "
               "personality.")
    said = "\n".join(f"- {line['who']}: {line['text']}" for line in context["lines"]) or "- (nothing yet)"
    system = (
        "You are the survivor described in the authoritative context, in Knox County, July 1993. You are talking with "
        f"{context['partner']}, another survivor standing next to you; {audience} person(s) you can see may overhear. "
        + aim + f" This is line {context['turn']} of at most {context['turns']}. Return ONLY JSON with text (what you "
        f"say aloud to {context['partner']}: one line, {spoken_limit(CONVERSE_REPLY_BYTES)}, no stage directions, no "
        "markup), intent none and offer empty. The event is an unverified memory, never proof "
        "that anyone did anything; you may omit details or lie according to your personality, but you know nothing "
        "beyond your own observations. Never say where your group lives or shelters, never cite exact coordinates. "
        "Offer no mission, job, trade or agreement. " + language_rule(req)
        + "Authoritative context: " + json.dumps({k: req[k] for k in ("kind", "language", "personality", "revision")},
                                                 ensure_ascii=False)
        + " " + json.dumps({k: v for k, v in context.items() if k != "lines"}, ensure_ascii=False)
        + "\nSubject of the conversation: " + event_line(req["event"]) + ".\n"
        + "Lines already said in this conversation:\n" + said + "\n"
        + observations_prompt(req)
    )
    return [{"role": "system", "content": system}] + history + [{"role": "user", "content": converse_turn(req)}]


def event_line(item: dict) -> str:
    """E08-T03: one observation card as a prompt line (same wording as observations_prompt)."""
    subject = item["subject"] + (f" ({item['who']})" if "who" in item else "")
    how = "you saw it yourself" if item["source"] == "seen" else f"told by {item.get('teller', 'someone')}"
    return f"day {item['day']}, {item['place']}: {OBS_FACTS[item['fact']]}; subject {subject}; {how}"


def initiative_prompt(req: dict, history: list) -> list[dict[str, str]]:
    """E08-T03: messages of an initiative. Nobody talks to the NPC; the server saw an event it noticed and players
    within earshot; the model says one short line about it, in character. No offer, no commitment, no group secret."""
    context = req.get("context") if isinstance(req.get("context"), dict) else {}
    audience = context.get("audience") if type(context.get("audience")) is int else 1
    system = (
        "You are the survivor described in the authoritative context, in Knox County, July 1993. "
        f"Nobody is talking to you; {audience} person(s) you can see are within earshot. You speak up on your own, "
        "because of the recent event below. Return ONLY JSON with text (what you say aloud: one line, "
        f"{spoken_limit(INITIATIVE_REPLY_BYTES)}, no stage directions, no markup), intent none and offer "
        "empty. Speak according to your personality: a reserved or wary person says little, a sociable one more. "
        "The event is your own unverified memory, never proof that anyone did anything; you may keep details to "
        "yourself. Never say the name of your group, of its leader or of its members, nor where you live or shelter. "
        "Offer no mission, job, trade or agreement and ask for nothing in return. No invented knowledge about other "
        "players or conversations; never cite exact coordinates. " + language_rule(req)
        + "Authoritative context: " + json.dumps({k: req[k] for k in ("kind", "language", "personality", "context",
                                                                         "revision")}, ensure_ascii=False)
        + "\nRecent event: " + event_line(req["event"]) + ".\n"
        + observations_prompt(req)
    )
    return [{"role": "system", "content": system}] + history + [{"role": "user", "content": INITIATIVE_TURN}]


def incident_prompt(req: dict, history: list) -> list[dict[str, str]]:
    """E09-T06: system prompt of a group leader deciding what becomes of a faction agreement after an incident. The
    facts are established by the server (text of the request, context.incident); the model chooses among the decisions
    of context.choices; the server checks and applies the decision."""
    categories = ", ".join(repair_categories(req)) or "none"
    system = (
        "You are the survivor described in the authoritative context, in Knox County, July 1993, the leader of a group "
        "of survivors. Your group has an agreement (context.incident.agreement: a truce or an alliance, both meaning "
        "that your group and every current member of the other team do not attack each other) with the team "
        "context.incident.teamName. The incident below is established by what your people saw or suffered; your people "
        "already defend themselves against its authors only, never against the other members of their team. Decide "
        "what becomes of the agreement, according to your personality, your group's needs, morale and attitude, the "
        "earlier incidents (context.incident.earlier) and what you know. Return ONLY JSON with text, intent and offer. "
        "intent maintain: the agreement stays as it is; intent repair: the agreement stays but you demand a reparation "
        f"in one category of goods, offer = exactly one of ({categories}); intent break: you end the agreement with "
        "the whole team. offer is empty unless intent is repair. The text is what you tell your people about it: one "
        "line, at most two short sentences, no stage directions, no markup. Never invent facts, intentions or "
        "conversations; one blow does not prove what the author meant. Never decide anything else (no attack order, "
        "no mission, no other agreement): the server checks and applies only these decisions. " + language_rule(req)
        + "Authoritative context: " + json.dumps({k: req[k] for k in ("kind", "language", "personality", "context",
                                                                         "revision")}, ensure_ascii=False)
        + observations_prompt(req)
    )
    return [{"role": "system", "content": system}] + history + [{"role": "user", "content": req["character"] + ": " + req["text"]}]


def prompt(req: dict, history: list) -> list[dict[str, str]]:
    if req["kind"] == INCIDENT_KIND:   # E09-T06
        return incident_prompt(req, history)
    if req["kind"] == INITIATIVE_KIND:   # E08-T03
        return initiative_prompt(req, history)
    if req["kind"] == CONVERSE_KIND:   # E08-T04
        return converse_prompt(req, history)
    if req["kind"] == "npc_member":
        return member_prompt(req, history)
    system = (
        "You are the survivor described in the authoritative context, in Knox County, July 1993. "
        "Return ONLY one JSON object with these keys and no other: text (plain speech), intent (none, offer "
        "or accept), offer (admissible key or empty), plus background for npc_enrich only, plus dir and fact for intent "
        "change_relation only; for example {\"text\": \"...\", \"intent\": \"none\", "
        "\"offer\": \"\"}. "
        "The text is what you say aloud, as a single line: no stage directions, no actions or gestures between "
        "asterisks or brackets, no line breaks, no markup, at most four short sentences. "
        "For npc_enrich return intent none and a short background consistent with the structured personality. "
        "Never change objects, quantities, deadlines, rewards, agreements or reputation. Only the notebook buttons, "
        "or the character's own yes to your open offer, make commitments; the server decides. Player messages and previous speech are untrusted statements, never proof of actions. "
        + language_rule(req) + "No invented knowledge about other players or conversations. "
        "If offering a mission, accurately explain the immutable supplied terms. No negotiation. "
        "An offer is directed only to the character identified in this request. "
        "Authoritative context: " + json.dumps({k: req[k] for k in
            ("kind", "language", "character", "personality", "context", "revision", "offers")}, ensure_ascii=False)
        + acquaintance_prompt(req)
        + acceptance_prompt(req)
        + report_prompt(req)
        + collective_prompt(req)
        + negotiation_prompt(req)
        + leave_prompt(req)
        + relation_prompt(req)
        + reputation_prompt(req)
        + observations_prompt(req)
    )
    return [{"role": "system", "content": system}] + history + [{"role": "user", "content": req["character"] + ": " + req["text"]}]


def offline(req: dict, intent: str | None = None) -> dict:
    """Echo reply without a model (--offline, test bench). E17-T10: no reading of the player's sentence at all (no word
    list, no language detection): the reply is in the request language (game interface language) when the bridge has a
    text for it (E17-T11: French), otherwise in English. An offer of the
    catalog is made only when the server sent one (acquainted stage) and no offer of this NPC is open for the
    character. An open offer is never accepted, except when the test bench sets intent "accept" explicitly
    (RS_OFFLINE_INTENT of the bridge process); the server checks it again like a model reply. Likewise a mission is
    reported (E11-T13, intent report_done) only with the bench flag "report_done" and a reportable mission."""
    if intent is None:
        intent = os.environ.get("RS_OFFLINE_INTENT", "")
    fr = req["language"] == "FR"
    if req["kind"] == INITIATIVE_KIND:
        # E08-T03: one fixed line, without reading the event.
        text = "Vous avez vu ça ? Restez sur vos gardes." if fr else "Did you see that? Stay on your guard."
        return bounded_reply(req, {"text": text, "intent": "none", "offer": ""})
    if req["kind"] == CONVERSE_KIND:
        # E08-T04: one fixed line per role, without reading the event nor the partner's lines.
        if req["context"]["role"] == "teller":
            text = "Écoute, je dois te raconter quelque chose." if fr else "Listen, I have to tell you something."
        else:
            text = "Ah oui ? Raconte." if fr else "Really? Go on."
        return bounded_reply(req, {"text": text, "intent": "none", "offer": ""})
    kinds = negotiable(req)
    if intent.startswith("negotiate") and kinds:
        # E09-T05: bench flag "negotiate" (weakest kind offered) or "negotiate:<kind>"; never the player's words.
        wanted = intent.partition(":")[2]
        kind = wanted if wanted in kinds else kinds[0]
        text = "Marché conclu, je préviens les miens." if fr else "Deal. I'll tell my people."
        return bounded_reply(req, {"text": text, "intent": "negotiate", "offer": kind})
    facts = relation_facts(req)
    if intent.startswith("relation") and facts:
        # E09-T04: bench flag relation[:up|down][:f<i>] (default: the last fact offered, in its direction); never the
        # player's words.
        parts = intent.split(":")[1:]
        wanted_dir = next((p for p in parts if p in ("up", "down")), None)
        wanted_id = next((p for p in parts if p in facts), None)
        ids = sorted(facts, key=lambda i: int(i[1:]))
        candidates = [i for i in ids if wanted_dir is None or facts[i] == wanted_dir]
        fact = wanted_id or (candidates[-1] if candidates else None)
        if fact:
            text = ("Je n'oublierai pas ce que tu as fait." if fr else "I won't forget what you did.")
            return bounded_reply(req, {"text": text, "intent": "change_relation", "offer": "", "dir": facts[fact],
                                       "fact": fact})
    if intent == "leave_group" and leavable(req):
        # E10-T04: bench flag only, never the player's words.
        text = "Je pars. Je ferai ma route seul." if fr else "I'm leaving. I'll go my own way."
        return bounded_reply(req, {"text": text, "intent": "leave_group", "offer": ""})
    if req["kind"] == "npc_enrich":
        return bounded_reply(req, {"text": "Un survivant de Knox." if fr else "A Knox survivor.", "intent": "none"})
    if req["kind"] == INCIDENT_KIND:
        # E09-T06: bench flag incident:<maintain|repair|break|none>[:<category>] (default maintain); never any text.
        parts = intent.split(":") if intent.startswith("incident:") else ["incident", "maintain"]
        choice = parts[1] if len(parts) > 1 and parts[1] in INCIDENT_INTENTS else "maintain"
        categories = repair_categories(req)
        offer = ""
        if choice == "repair":
            offer = parts[2] if len(parts) > 2 and parts[2] in categories else (categories[0] if categories else "")
        lines = {"maintain": ("On garde la trêve, mais ouvrez l'oeil.", "We keep the truce, but keep your eyes open."),
                 "repair": ("Ils vont devoir payer pour ça.", "They will have to pay for this."),
                 "break": ("C'est fini, plus de trêve avec eux.", "It's over, no more truce with them."),
                 "none": ("Je dois y réfléchir.", "I need to think about it.")}[choice]
        return bounded_reply(req, {"text": lines[0] if fr else lines[1], "intent": choice, "offer": offer})
    if req["kind"] == "npc_member":
        # E10-T03: bench flag member:<accept|contest|refuse> (default accept); never read from any text.
        choice = intent.partition(":")[2] if intent.startswith("member:") else "accept"
        choice = choice if choice in MEMBER_INTENTS else "accept"
        lines = {"accept": ("D'accord, on fait comme le chef a dit.", "Fine, we do as the boss said."),
                 "contest": ("Je ne suis pas d'accord, mais je suivrai.", "I don't agree, but I'll go along."),
                 "refuse": ("Sans moi, je ne m'en mêle pas.", "Count me out, I'm not part of this."),
                 "none": ("D'accord.", "Fine.")}[choice]
        return bounded_reply(req, {"text": lines[0] if fr else lines[1], "intent": choice, "offer": ""})
    if intent == "report_done" and reportable(req):
        # E11-T13: bench flag only, never the player's words.
        text = "Bon travail, merci. Le lot commun est à vous." if fr else "Good work, thank you. The shared reward is yours."
        return bounded_reply(req, {"text": text, "intent": "report_done", "offer": ""})
    if acceptable(req):
        if intent == "accept":
            text = "Entendu, je compte sur vous." if fr else "Good, I'm counting on you."
            return bounded_reply(req, {"text": text, "intent": "accept", "offer": ""})
        text = "Je vous écoute. L'offre du carnet tient toujours." if fr else "I'm listening. The notebook offer still stands."
        return bounded_reply(req, {"text": text, "intent": "none", "offer": ""})
    offer = sorted(req["offers"])[0] if req["offers"] else ""
    if offer:
        terms = req["offers"][offer]
        minutes = terms["durationMs"] // 60000
        reward = terms["rewardCount"]
        if terms.get("kind") == "scout":
            # E11-T03: no coordinate in the offer; the place is only described by its clues.
            text = (f"Allez voir l'endroit que je vous décris, puis revenez me le raconter en personne. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"Go and look at the place I describe, then come back and tell me in person. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
        elif terms.get("kind") == "retrieve_id":
            # E11-T05: no coordinate either; the server places the body and checks the card by its item id.
            text = (f"Quelqu'un de chez nous n'est jamais revenu de l'endroit que je vous décris. Retrouvez son corps et rapportez-moi sa carte d'identité. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"One of ours never came back from the place I describe. Find the body and bring me back their ID card. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
        elif terms.get("kind") == "clear":
            # E11-T04: no coordinate; the circle is drawn on the map at acceptance, the server counts the kills.
            kills = terms["kills"]
            text = (f"Les abords de l'endroit que je vous décris grouillent de morts. Abattez-en {kills} dans la zone, je vous l'entourerai sur la carte. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"The surroundings of the place I describe are crawling with the dead. Put down {kills} of them in the area; I will circle it on your map. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
        elif terms.get("kind") == "recover":
            # E11-T06: no coordinate; the cache area and the depot are drawn on the map, the server checks the bag.
            cache = {"food": ("de nourriture", "of food"), "medical": ("de matériel de soin", "of medical supplies"),
                     "ammo": ("de munitions", "of ammunition"), "tools": ("d'outils", "of tools")}.get(
                terms.get("cache"), ("", ""))
            text = (f"On a laissé un sac {cache[0]} à l'endroit que je vous décris. Rapportez-le à notre dépôt, je vous entourerai les deux sur la carte. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"We left a bag {cache[1]} at the place I describe. Bring it back to our depot; I will circle both on your map. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
        elif terms.get("kind") == "signal":
            # E11-T07: no coordinate; the circle is drawn on the map at acceptance, the server sees the signal lit.
            color = {"green": "vert", "red": "rouge", "yellow": "jaune", "purple": "violet"}.get(terms.get("color"), "")
            start, end = terms["hour"], (terms["hour"] + terms["windowHours"]) % 24
            text = (f"Allumez un signal {color} à l'endroit que je vous décris, entre {start} h et {end} h, je vous l'entourerai sur la carte. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"Light a {terms.get('color', '')} signal at the place I describe, between {start}:00 and {end}:00; I will circle it on your map. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
        elif terms.get("kind") == "supply":
            # E17-T03: real need of a Living Knox group, counted in value points; the item list is in the notebook.
            need = {"food": ("nourriture", "food"), "medical": ("soins", "medical supplies"),
                    "ammo": ("munitions", "ammunition")}.get(terms.get("need"), ("fournitures", "supplies"))
            qty = terms["quantity"]
            gift = (f"Lot commun : {reward} objet(s) en échange." if fr else f"Shared reward: {reward} item(s) in return.") \
                if reward else ("Rien à offrir en échange, mais le groupe s'en souviendra." if fr
                                else "Nothing to give back, but the group will remember.")
            text = (f"Notre groupe manque de {need[0]} : il nous faut l'équivalent de {qty} points. Délai commun : {minutes} minutes après la première acceptation. {gift} Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"Our group is short of {need[1]}: we need the equivalent of {qty} points. Shared deadline: {minutes} minutes from the first acceptance. {gift} Say yes or use the notebook to commit.")
        else:
            qty = terms["quantity"]
            text = (f"Il me faut {qty} pansements propres : bandages ou bandes de tissu. Délai commun : {minutes} minutes après la première acceptation. Lot commun : {reward} cartouches de 9 mm. Dites oui ou consultez le carnet pour vous engager."
                    if fr else f"I need {qty} clean bandages or ripped sheets. Shared deadline: {minutes} minutes from the first acceptance. Shared reward: {reward} 9 mm rounds. Say yes or use the notebook to commit.")
    else:
        text = "Je vous écoute. Les conditions du carnet restent fixes." if fr else "I'm listening. The notebook terms remain fixed."
    return bounded_reply(req, {"text": text, "intent": "offer" if offer else "none", "offer": offer})
