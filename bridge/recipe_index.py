"""Recipe index written by the game for the bridge (E27-T01, ADR recettes-radio D08, D11).

At every start of the authority, the game writes `<exchange>/recipes.json` with every craft recipe it really loaded
(server/RadioSurvivor/RS_RecipeIndex.lua; format in docs/specifications-techniques/index-recettes.md):

    {"format": 1, "written": <ms>, "recipes": [{"id", "name", "category", "job", "inputs", "outputs", "skills",
     "learn", "learned_from", "mod"}, ...]}

An input line is {"items": [{"item", "name"}, ...], "count", "tool"} (any one of the items) or {"fluids": [{"fluid",
"name"}, ...], "amount" (litres), "tool": false}; an output line is the same without "tool".

`RecipeIndex(exchange)` reads it at construction (bridge start) and again, on access, whenever the file's modification
time or size changed (`recipes()`, `for_jobs()`). A missing file is an empty index (one log line); a malformed file
(partial write, wrong format) is logged and the previous index is kept, read again at the next change. The bridge never
writes this file and does not know which mod writes it. Standard library only.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Callable, Iterable

FILE_NAME = 'recipes.json'
FORMAT = 1
RECIPE_KEYS = {'id': str, 'name': str, 'category': str, 'job': str, 'inputs': list, 'outputs': list,
               'skills': list, 'learn': bool, 'learned_from': list, 'mod': str}
_NEVER_READ = object()   # stamp before the first read: an absent file is reported once


class RecipeIndexError(ValueError):
    """The recipe file exists but is not a valid index."""


def parse(text: str) -> list[dict]:
    """Recipes of an index text; RecipeIndexError naming the first problem."""
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as err:
        raise RecipeIndexError(f"not JSON ({err.msg} at line {err.lineno})") from None
    if not isinstance(doc, dict) or doc.get('format') != FORMAT:
        raise RecipeIndexError(f"format is not {FORMAT}")
    recipes = doc.get('recipes')
    if not isinstance(recipes, list):
        raise RecipeIndexError("'recipes' is not a list")
    for pos, recipe in enumerate(recipes):
        if not isinstance(recipe, dict):
            raise RecipeIndexError(f"recipe {pos} is not an object")
        for key, kind in RECIPE_KEYS.items():
            if not isinstance(recipe.get(key), kind):
                raise RecipeIndexError(f"recipe {pos} ({recipe.get('id', '?')}): '{key}' missing or not {kind.__name__}")
        for side, tool in (('input', True), ('output', False)):
            for line_pos, line in enumerate(recipe[side + 's']):
                problem = _line_problem(line, tool)
                if problem:
                    raise RecipeIndexError(f"recipe {pos} ({recipe['id']}): {side} {line_pos} {problem}")
    return recipes


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _choices_problem(choices, key: str) -> str | None:
    if not isinstance(choices, list) or not choices:
        return f"'{key}s' missing or empty"
    for choice in choices:
        if not (isinstance(choice, dict) and isinstance(choice.get(key), str) and isinstance(choice.get('name'), str)):
            return f"'{key}s' entry without '{key}' and 'name' texts"
    return None


def _line_problem(line, with_tool: bool) -> str | None:
    """Why an input (with_tool) or output line is malformed, None when it is valid."""
    if not isinstance(line, dict):
        return "is not an object"
    if 'items' in line:
        problem = _choices_problem(line['items'], 'item')
        if not problem and not _is_number(line.get('count')):
            problem = "'count' missing or not a number"
    elif 'fluids' in line:
        problem = _choices_problem(line['fluids'], 'fluid')
        if not problem and not _is_number(line.get('amount')):
            problem = "'amount' missing or not a number"
    else:
        return "has neither 'items' nor 'fluids'"
    if not problem and with_tool and not isinstance(line.get('tool'), bool):
        problem = "'tool' missing or not a boolean"
    return problem


class RecipeIndex:
    """Recipes of `<exchange>/recipes.json`, reread when the game rewrites the file."""

    def __init__(self, exchange: Path, log: Callable[[str], None] = print):
        self.path = Path(exchange) / FILE_NAME
        self._log = log
        self._stamp: tuple[int, int] | None | object = _NEVER_READ
        self._recipes: list[dict] = []
        self.refresh()

    def _current_stamp(self) -> tuple[int, int] | None:
        try:
            stat = self.path.stat()
        except FileNotFoundError:
            return None
        return stat.st_mtime_ns, stat.st_size

    def refresh(self) -> bool:
        """Reads the file again if it changed since the last read; True when the index was replaced."""
        stamp = self._current_stamp()
        if stamp == self._stamp:
            return False
        self._stamp = stamp
        if stamp is None:
            self._recipes = []
            self._log(f"Recipe index: {self.path} absent, no recipe known until the game writes it")
            return True
        try:
            recipes = parse(self.path.read_text(encoding='utf-8'))
        except (OSError, UnicodeDecodeError, RecipeIndexError) as err:
            self._log(f"Recipe index: {self.path} unreadable ({err}); keeping {len(self._recipes)} recipes")
            return False
        self._recipes = recipes
        self._log(f"Recipe index: {len(recipes)} recipes read from {self.path}")
        return True

    def recipes(self) -> list[dict]:
        """Every recipe of the index (refreshed first)."""
        self.refresh()
        return list(self._recipes)

    def for_jobs(self, jobs: Iterable[str]) -> list[dict]:
        """Recipes whose job is one of these job ids (refreshed first), in file order."""
        wanted = set(jobs)
        return [recipe for recipe in self.recipes() if recipe['job'] in wanted]
