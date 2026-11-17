"""Recipe search with a delay (E27-T04, ADR recettes-radio D04, D07): what the voice says while it looks through its
notes, and the answer when the caller calls back.

The server is the authority on time: it keeps ONE pending search per notebook character and per voice (ids found,
keywords, game hour when it is ready) and joins it to every later request of that caller to that voice as the field
FIELD (hex RSV2 of {ids, ready, keywords}). This module only reads that field and words the prompts:
- first question of a voice whose delay is in DELAY_WORDS: the bridge searches, but the second call (callback_message)
  gives no fact: the voice says it must look through its notes and asks to be called back; the ids found go back to the
  server as "searched" of radio_reply;
- pending not ready (waiting_prompt): still looking, nothing found yet, no fact;
- pending ready (ready_prompt): the recipes are facts of the first call and are returned as delivered.
Delays are data (DELAY_WORDS, mirrored in hours by RS_RecipeSearches.DELAY_HOURS on the server); `now` is absent: the
answer comes in the same turn (E27-T03). Standard library only.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

import npc_protocol as npc
import recipe_help
from persona_store import Help

FIELD = 'recipe'
FIELD_CHARS = 4096
MAX_IDS = 8
ID_CHARS = 128
DELAY_WORDS = {'hour': 'about an hour', 'half_day': 'about half a day', 'day': 'about a day'}
_HEX = re.compile(r"(?:[0-9a-f]{2})+")
NO_HINT = "give no recipe, no ingredient, no tool, no step, not even a guess"


@dataclass(frozen=True)
class Pending:
    """Search of this caller kept by the server: recipe ids found, keywords searched, ready to be given or not."""
    ids: tuple[str, ...]
    ready: bool
    keywords: tuple[str, ...]


def delayed(help_: Help) -> bool:
    """True when the voice looks through its notes before answering (delay other than now)."""
    return help_.delay in DELAY_WORDS


def _strings(value, limit: int, chars: int) -> tuple[str, ...]:
    if value is None:
        return ()
    if not isinstance(value, dict) or set(value) != set(range(1, len(value) + 1)) or len(value) > limit:
        raise ValueError("list")
    out = []
    for index in range(1, len(value) + 1):
        item = value[index]
        if not isinstance(item, str) or not item or len(item) > chars:
            raise ValueError("list item")
        out.append(item)
    return tuple(out)


def pending_field(req: dict[str, str], log) -> Pending | None:
    """Pending search of the request (field FIELD); None when absent. Unreadable: None and one journal line."""
    raw = req.get(FIELD)
    if not raw:
        return None
    try:
        if len(raw) > FIELD_CHARS or not _HEX.fullmatch(raw):
            raise ValueError("hex")
        value = npc.decode(bytes.fromhex(raw))
        if not isinstance(value, dict) or not isinstance(value.get('ready'), bool):
            raise ValueError("fields")
        ids = _strings(value.get('ids'), MAX_IDS, ID_CHARS)
        words = recipe_help.keywords(list(_strings(value.get('keywords'), recipe_help.MAX_KEYWORDS,
                                                   recipe_help.KEYWORD_CHARS)))
    except ValueError as err:
        log(f"request {req.get('id', '?')}: recipe search state ignored ({err})")
        return None
    return Pending(ids, value['ready'], tuple(words))


def found_ids(recipes: list[dict], ids) -> list[dict]:
    """Recipes of `recipes` (the voice's jobs) with these ids, in the order of `ids`; unknown ids dropped."""
    by_id = {recipe['id']: recipe for recipe in recipes}
    return [by_id[i] for i in ids if i in by_id]


def same_search(pending: Pending, ids: list[str], searched: list[str]) -> bool:
    """A search asked again while waiting: same recipes found (or, both empty, the same keywords)."""
    if set(ids) != set(pending.ids):
        return False
    return bool(ids) or {w.lower() for w in searched} == {w.lower() for w in pending.keywords}


def callback_message(searched: list[str], help_: Help) -> str:
    """System message of the second call of a delayed search: no fact, call back later."""
    return ("Your recipe notes (" + ', '.join(help_.jobs) + ") are not at hand: you keep them elsewhere and must look "
            f"through them first (keywords searched: {', '.join(searched)}). Tell the caller now, in character and in "
            "the language the caller used, that you will look it up and that they should call you back in "
            f"{DELAY_WORDS[help_.delay]} (game time); {NO_HINT}." + recipe_help.PLAIN)


def _waiting(pending: Pending) -> str:
    return (f"you are still looking through your notes for what the caller asked you (keywords: "
            f"{', '.join(pending.keywords) or 'unknown'}) and you have not found it yet. If they ask about it, tell "
            f"them so in character and ask them to call back later; {NO_HINT}.")


def waiting_prompt(pending: Pending) -> str:
    """Section of the first call's system prompt while the search is not ready."""
    return ("\n\nRecipe search in progress: " + _waiting(pending) + ' Use "' + recipe_help.FIELD
            + '" only if they ask how to make something else.')


def waiting_message(pending: Pending) -> str:
    """System message of the second call when the caller asks the same thing again before it is ready."""
    return "Recipe search in progress: " + _waiting(pending) + recipe_help.PLAIN


def ready_prompt(found: list[dict], pending: Pending, help_: Help) -> str:
    """Section of the first call's system prompt when the caller calls back and the search is ready: the facts, to be
    said in "say"."""
    return ("\n\nRecipe search done: the caller called back for what they asked you to look up. "
            + recipe_help.notes(found, list(pending.keywords), help_)
            + ' Put that answer in "say".')
