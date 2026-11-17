"""Recipe help of a voice on the radio (E27-T03, ADR recettes-radio D01, D03, D06, D10).

A voice with a [help] section (persona_store.Help: jobs, from, delay) knows the recipes of its jobs. Its first LLM
call may return, next to "say" and "actions", the field FIELD: 1 to MAX_KEYWORDS short ENGLISH keywords naming what
the caller wants to make, translated by the model from any language (no word list of any language here). The bridge
then searches the index (recipe_search) and makes a second call with `facts_message` appended: the reply of that
second call is what the voice says.

Reputation gate (D03, D06): the caller's level comes from the server (field reputation=, level bad / neutral / good,
radio_bridge.reputation_field); `from` = all helps everyone, neutral helps neutral and good, good helps good only.
No level sent (no living character in the notebook) is below every level but all. Below: the prompt asks the voice
to refuse in character and FIELD is never offered nor read. The server stays the authority: this module only words
prompts and reads the level the server sent. Standard library only.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from persona_store import Help
from recipe_search import pieces

FIELD = 'recipe_search'
MAX_KEYWORDS = 4
KEYWORD_CHARS = 40
LEVEL_RANK = {'bad': 0, 'neutral': 1, 'good': 2}
FROM_RANK = {'all': -1, 'neutral': 1, 'good': 2}   # lowest level rank that is helped; all: even without a level
_KEYWORD_SYNTAX = re.compile(r"[^A-Za-z0-9 \-]")


def helps(help_: Help, level: str | None) -> bool:
    """True when the voice helps a caller of this reputation level (None: no level sent)."""
    return LEVEL_RANK.get(level, -1) >= FROM_RANK[help_.from_]


@dataclass(frozen=True)
class RecipeTurn:
    """Recipe help of one turn of a voice: its [help] and whether this caller is helped."""
    help: Help
    allowed: bool

    def prompt(self) -> str:
        """Section of the first call's system prompt (structured mode)."""
        trades = ', '.join(self.help.jobs)
        if not self.allowed:
            return ("\n\nRecipes: you know how things are made in your trade (" + trades + "), but you share that only "
                    "with people you trust more than this caller. If they ask how to make, craft, cook or build "
                    "something, refuse in character, in your own words, and give no hint at all: no ingredients, no "
                    "tools, no containers, no method, no step, not even general ones or common sense ones. Say only "
                    "that you will not help them with that.")
        return ("\n\nRecipes: you know how things are made in your trade (" + trades + "). If the caller asks how to "
                f'make, craft, cook or build something, add to your JSON object the field "{FIELD}": a list of 1 to '
                f"{MAX_KEYWORDS} short ENGLISH keywords naming only the thing they want to make, never its "
                "ingredients or tools, translated into English whatever language they speak (for example "
                '["sheet rope"], not ["ripped sheets"]; or ["soup"]); "say" can then be a few '
                "words while you look it up: your notes will come to you and you will answer. Never give a recipe "
                f'from memory. Without such a question, leave "{FIELD}" out.')

    def reminder(self) -> str:
        """Addition to the format reminder at the end of the caller's message (first call)."""
        if not self.allowed:
            return ''
        return f' Add "{FIELD}": ["english keywords"] only if they ask how to make something.'


def recipe_turn(help_: Help | None, level: str | None, has_index: bool) -> RecipeTurn | None:
    """Recipe help of this turn; None when the voice has no [help] or the bridge has no recipe index (prompt
    unchanged)."""
    if help_ is None or not has_index:
        return None
    return RecipeTurn(help_, helps(help_, level))


def keywords(raw) -> list[str]:
    """Keywords of the model's FIELD, bounded: a text or a list of texts, each reduced to ASCII letters, digits,
    spaces and hyphens (syntax only: they are quoted in a prompt), at most KEYWORD_CHARS characters, empty ones
    dropped, at most MAX_KEYWORDS."""
    values = [raw] if isinstance(raw, str) else raw if isinstance(raw, list) else []
    out: list[str] = []
    for value in values:
        if not isinstance(value, str):
            continue
        text = ' '.join(_KEYWORD_SYNTAX.sub(' ', value).split())[:KEYWORD_CHARS].strip()
        if text:
            out.append(text)
        if len(out) >= MAX_KEYWORDS:
            break
    return out


def _amount(value) -> str:
    return f"{value:g}"


def readable_type(full_type: str) -> str:
    """'Base.CookingMag2' -> 'Cooking Mag 2' (an item type without a name in the index)."""
    return ' '.join(pieces(full_type.rsplit('.', 1)[-1]))


def _choices(line: dict) -> str:
    names = [c['name'] for c in line.get('items', [])] or [c['name'] for c in line.get('fluids', [])]
    return ' or '.join(names)


def _line(line: dict) -> str:
    if 'fluids' in line:
        return f"{_amount(line['amount'])} l {_choices(line)}"
    return f"{_amount(line['count'])} x {_choices(line)}"


def describe(recipe: dict) -> str:
    """One recipe as facts in words: result, ingredients (alternatives, counts, fluids in litres), tools, skill
    levels, and what teaches it when it must be learned."""
    parts = [f"{recipe['name']}: makes " + (', '.join(_line(o) for o in recipe['outputs']) or 'nothing listed') + '.']
    used = [_line(i) for i in recipe['inputs'] if not i.get('tool')]
    tools = [_choices(i) for i in recipe['inputs'] if i.get('tool')]
    if used:
        parts.append('Needs: ' + '; '.join(used) + '.')
    if tools:
        parts.append('Tools (kept): ' + '; '.join(tools) + '.')
    if recipe['skills']:
        parts.append('Skills: ' + ', '.join(f"{s.get('perk')} level {s.get('level')}" for s in recipe['skills']) + '.')
    if recipe['learn']:
        teachers = ', '.join(readable_type(t) for t in recipe['learned_from'])
        parts.append('Must be learned first' + (f', from: {teachers}' if teachers else '') + '.')
    return ' '.join(parts)


PLAIN = " Plain spoken text, no JSON."
NOTHING_RULE = ("Tell them so now, in character and in the language the caller used; never invent a recipe, an "
                "ingredient or a step.")
ANSWER_RULE = ("Answer the caller now, in character and in the language the caller used, as a radio conversation, "
               "not a list: what it makes, what it takes, the tools and the skill, for the recipe that fits the "
               "question best. Use only these notes: never invent a recipe, an ingredient, a quantity or a step that "
               "is not in them.")


def notes(found: list[dict], searched: list[str], help_: Help) -> str:
    """The recipes found as facts (or that nothing was found), with the keywords searched, then the rule of the
    answer (ANSWER_RULE, or NOTHING_RULE when nothing was found). Shared by the answer of the same turn (E27-T03) and
    the answer to a call back (E27-T04, recipe_delay.ready_prompt)."""
    trades = ', '.join(help_.jobs)
    head = f"Keywords searched: {', '.join(searched)}\n"
    if not found:
        return ("Your recipe notes (" + trades + "): you looked through what you know and found nothing that "
                "makes what the caller asked for.\n" + head + NOTHING_RULE)
    listed = ''.join(f"{n}. {describe(recipe)}\n" for n, recipe in enumerate(found, 1))
    return ("Your recipe notes (" + trades + "), facts of the game for the question you just heard:\n" + head
            + listed + ANSWER_RULE)


def facts_message(found: list[dict], searched: list[str], help_: Help) -> str:
    """System message of the second call: the recipes found as facts, or that nothing was found, and how to answer."""
    return notes(found, searched, help_) + PLAIN
