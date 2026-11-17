"""Search of the recipe index by English keywords (E27-T03, ADR recettes-radio D01).

The voice's model translates the caller's question, whatever its language, into a few English keywords; this module
finds the recipes of the index (recipe_index.RecipeIndex, already filtered by the voice's jobs) that answer them. No
word list of any language: only the words of the recipe itself are compared.

Words of a recipe, each with a weight (the best weight counts when a word appears in several places):
    OUTPUT_WEIGHT  output item types (module stripped, CamelCase split), output item and fluid names and fluid types
    ID_WEIGHT      the recipe id, split on CamelCase and underscores
    NAME_WEIGHT    the recipe name (English, or the server language: the id and the item types stay English)
Each keyword is a phrase: it counts for a recipe only when ALL its words are words of that recipe ("ripped sheets" does
not match a sheet rope), and then adds the best weight of each of its words. A recipe scores the sum over its fully
matched phrases; comparison is case-insensitive and tolerates a simple English plural (keywords are English by
contract). Best score first, ties by id; at most MAX_RESULTS recipes, none with a zero score. Pure functions, standard
library only.
"""
from __future__ import annotations

import re
from typing import Iterable

MAX_RESULTS = 5
OUTPUT_WEIGHT = 3
ID_WEIGHT = 2
NAME_WEIGHT = 1

_ALNUM = re.compile(r'[^\W_]+')                                    # runs of letters and digits, any script
_CAMEL = re.compile(r'[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+')


def pieces(text: str) -> list[str]:
    """Words of an identifier or a name, case kept: split on anything not a letter or a digit, then an ASCII run on
    CamelCase and digits ('MakeTVStand' -> Make, TV, Stand; 'CookingMag2' -> Cooking, Mag, 2)."""
    out: list[str] = []
    for run in _ALNUM.findall(text or ''):
        out.extend(_CAMEL.findall(run) if run.isascii() else [run])
    return out


def singular(word: str) -> str:
    """Simple English singular of a lower-case word (batteries -> battery, boxes -> box, ropes -> rope)."""
    if len(word) > 4 and word.endswith('ies'):
        return word[:-3] + 'y'
    if len(word) > 4 and word.endswith(('ches', 'shes', 'sses', 'xes', 'zes')):
        return word[:-2]
    if len(word) > 3 and word.endswith('s') and not word.endswith('ss'):
        return word[:-1]
    return word


def words(text: str) -> list[str]:
    """Lower-case singular words of an identifier, a name or a keyword."""
    return [singular(piece.lower()) for piece in pieces(text)]


def item_words(full_type: str) -> list[str]:
    """Words of an item type, module stripped ('Base.SheetRope' -> sheet, rope)."""
    return words(full_type.rsplit('.', 1)[-1])


def recipe_words(recipe: dict) -> dict[str, int]:
    """Word -> best weight of that word in the recipe."""
    weights: dict[str, int] = {}

    def add(found: Iterable[str], weight: int) -> None:
        for word in found:
            weights[word] = max(weight, weights.get(word, 0))

    add(words(recipe['name']), NAME_WEIGHT)
    add(words(recipe['id']), ID_WEIGHT)
    for line in recipe['outputs']:
        for choice in line.get('items', []):
            add(item_words(choice['item']), OUTPUT_WEIGHT)
            add(words(choice['name']), OUTPUT_WEIGHT)
        for choice in line.get('fluids', []):
            add(words(choice['fluid']), OUTPUT_WEIGHT)
            add(words(choice['name']), OUTPUT_WEIGHT)
    return weights


def score(recipe: dict, phrases: list[list[str]]) -> int:
    """Sum, over the phrases whose words ALL appear in the recipe, of the best weight of each of their words."""
    weights = recipe_words(recipe)
    return sum(sum(weights[word] for word in phrase) for phrase in phrases
               if all(word in weights for word in phrase))


def search(recipes: Iterable[dict], keywords: Iterable[str], limit: int = MAX_RESULTS) -> list[dict]:
    """Best recipes for these English keywords, best first, ties by id; [] when nothing matches."""
    phrases = [list(dict.fromkeys(found)) for found in (words(keyword) for keyword in keywords) if found]
    if not phrases:
        return []
    scored = [(score(recipe, phrases), recipe) for recipe in recipes]
    ranked = sorted(((s, r) for s, r in scored if s > 0), key=lambda pair: (-pair[0], pair[1]['id']))
    return [recipe for _, recipe in ranked[:limit]]
