"""Item types of the installed game for the voice workshop (E22-T12): name in English and French, weight in kg, and
the category the game shows in the inventory.

Read-only over the game folder (media/scripts and media/lua/shared/Translate), used by gen_atelier_catalog.py. The
weight follows the mod's own rule (RS_ItemWeights.lua, the source of truth in game):
- script Weight (Item.java:103 default 1.0, :2104-2107 parsed, negative read as 0; getActualWeight :557-562);
- plus the capacity of a FluidContainer component created full: a `Fluids` block holding at least one `fluid = ...`
  value or `Fluid { }` block (FluidContainerScript.java:195-240), capacity in litres at least 0.05
  (FluidContainerScript.java:72, FluidUtil.getMinContainerCapacity), one litre counted 1 kg;
- rounded to 0.01 kg (RS_ItemWeights round2).
Names: Translate/<LANG>/ItemName.json ("Module.Type": name, JSON since 42.21), else the script DisplayName, else the
type; French falls back on English as the game does.
Category: script DisplayCategory (Item.java:2977-2978, every item of the 42.22 scripts has one), named as the inventory
shows it, getText("IGUI_ItemCat_" .. category) (ISInventoryPane.lua:2552-2553) read in Translate/<LANG>/IG_UI.json, else
the raw category; French falls back on English.
Python 3 standard library only.
"""
from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_GAME = Path(r'D:\SteamLibrary\steamapps\common\ProjectZomboid')
LANGUAGES = ('en', 'fr')
DEFAULT_WEIGHT = 1.0
MIN_CAPACITY = 0.05
CATEGORY_KEY = 'IGUI_ItemCat_'
COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)


@dataclass
class Block:
    """One `type id { ... }` block of a script: its `key = value` lines in order and its child blocks."""
    type: str
    id: str = ''
    values: list[tuple[str, str]] = field(default_factory=list)
    children: list['Block'] = field(default_factory=list)

    def value(self, key: str) -> str | None:
        """Last value of `key` (case-insensitive, as the game reads it), or None."""
        found = [v for k, v in self.values if k.lower() == key.lower()]
        return found[-1] if found else None

    def child(self, type_: str, id_: str | None = None) -> 'Block | None':
        for c in self.children:
            if c.type.lower() == type_.lower() and (id_ is None or c.id.lower() == id_.lower()):
                return c
        return None


def _header(text: str) -> Block:
    words = text.split()
    return Block(type=words[0] if words else '', id=' '.join(words[1:]))


def _add_values(block: Block, text: str) -> None:
    for part in text.split(','):
        if '=' in part:
            key, _, val = part.partition('=')
            block.values.append((key.strip(), val.strip()))


def parse_script(text: str) -> list[Block]:
    """Top-level blocks of a script file (`module Base { ... }`), comments removed."""
    root = Block('root')
    stack = [root]
    buffer: list[str] = []
    for char in COMMENT.sub('', text):
        if char == '{':
            pending = ''.join(buffer)
            # Values written before the header belong to the parent; the header is the last non-empty line.
            lines = [line for line in pending.replace(',', ',\n').splitlines() if line.strip()]
            header = lines.pop() if lines else ''
            _add_values(stack[-1], '\n'.join(lines))
            block = _header(header.strip().rstrip(','))
            stack[-1].children.append(block)
            stack.append(block)
            buffer = []
        elif char == '}':
            _add_values(stack[-1], ''.join(buffer))
            buffer = []
            if len(stack) > 1:
                stack.pop()
        else:
            buffer.append(char)
    return root.children


def _number(text: str | None, default: float) -> float:
    try:
        return float(text) if text is not None else default
    except ValueError:
        return default


def _fluid_kg(item: Block) -> float:
    container = item.child('component', 'FluidContainer')
    if container is None:
        return 0.0
    fluids = container.child('Fluids')
    filled = fluids is not None and (any(k.lower() == 'fluid' for k, _ in fluids.values)
                                     or fluids.child('Fluid') is not None)
    return max(_number(container.value('Capacity'), 0.0), MIN_CAPACITY) if filled else 0.0


def round2(x: float) -> float:
    return math.floor(x * 100 + 0.5) / 100


def item_weight(item: Block) -> float:
    """Weight in kg of an item block, with the rule of RS_ItemWeights.lua."""
    return round2(max(_number(item.value('Weight'), DEFAULT_WEIGHT), 0.0) + _fluid_kg(item))


def read_scripts(scripts: Path) -> dict[str, Block]:
    """'Module.Type' -> item block of every script under `scripts` (a later file redefining a type wins)."""
    items: dict[str, Block] = {}
    for path in sorted(scripts.rglob('*.txt'), key=lambda p: p.as_posix().lower()):
        for module in parse_script(path.read_text(encoding='utf-8', errors='replace')):
            if module.type.lower() != 'module' or not module.id:
                continue
            for block in module.children:
                if block.type.lower() == 'item' and re.fullmatch(r'[A-Za-z0-9_]+', block.id):
                    items[f'{module.id}.{block.id}'] = block
    return items


def read_names(translate: Path, lang: str) -> dict[str, str]:
    path = translate / lang.upper() / 'ItemName.json'
    if not path.is_file():
        return {}
    return {str(k): str(v) for k, v in json.loads(path.read_text(encoding='utf-8-sig')).items()}


def read_category_names(translate: Path, lang: str) -> dict[str, str]:
    """Category -> its name in `lang` (IGUI_ItemCat_<Category> of IG_UI.json)."""
    path = translate / lang.upper() / 'IG_UI.json'
    if not path.is_file():
        return {}
    table = json.loads(path.read_text(encoding='utf-8-sig'))
    return {str(k)[len(CATEGORY_KEY):]: str(v) for k, v in table.items() if str(k).startswith(CATEGORY_KEY)}


def read_catalog(media_dirs: list[Path]) -> dict[str, dict]:
    """Items and their categories of the `media` folders, read in order (the game's, then the mods'): a later folder
    redefining a type or a name wins.
    - 'items': 'Module.Type' -> {'en': name, 'fr': name, 'kg': weight, 'cat': category ('' when none)};
    - 'itemCategories': category used by an item -> {'en': name, 'fr': name}."""
    blocks: dict[str, Block] = {}
    names: dict[str, dict[str, str]] = {lang: {} for lang in LANGUAGES}
    cat_names: dict[str, dict[str, str]] = {lang: {} for lang in LANGUAGES}
    for media in media_dirs:
        blocks.update(read_scripts(media / 'scripts'))
        translate = media / 'lua' / 'shared' / 'Translate'
        for lang in LANGUAGES:
            names[lang].update(read_names(translate, lang))
            cat_names[lang].update(read_category_names(translate, lang))
    items = {}
    for full_type, block in blocks.items():
        fallback = block.value('DisplayName') or full_type.split('.', 1)[1]
        en = names['en'].get(full_type) or fallback
        items[full_type] = {'en': en, 'fr': names['fr'].get(full_type) or en, 'kg': item_weight(block),
                            'cat': block.value('DisplayCategory') or ''}
    categories = {}
    for cat in sorted({item['cat'] for item in items.values() if item['cat']}):
        en = cat_names['en'].get(cat) or cat
        categories[cat] = {'en': en, 'fr': cat_names['fr'].get(cat) or en}
    return {'items': items, 'itemCategories': categories}


def read_items(media_dirs: list[Path]) -> dict[str, dict]:
    """'Module.Type' -> {'en', 'fr', 'kg', 'cat'} of every item type of the `media` folders (read_catalog)."""
    return read_catalog(media_dirs)['items']


def game_media(game: Path) -> Path | None:
    """media folder of the game installed in `game`, or None when no item script is there."""
    media = game / 'media'
    return media if (media / 'scripts').is_dir() else None
