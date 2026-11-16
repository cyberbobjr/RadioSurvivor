"""Generates the catalogue of the voice workshop (E22-T01, ADR atelier D03) from the mod's own Lua declarations.

    python RadioSurvivor/tools/gen_atelier_catalog.py [--game <folder of Project Zomboid>]   # writes catalog.json

The workshop (bridge/atelier) offers lists instead of free text from this file: mission types a voice may give and
their parameters, parameter kinds, reward kinds, shared categories, the grammar of a sheet (header and section keys,
required keys, closed lists of values) and the shipped voices (frequencies taken). Nothing is restated here: the real
Lua of the mod is loaded in lupa with the loader of the benches (tests/test_personas.LuaPersona: RS_Persona with
RS_Personas.rules, reward kinds and trade arrival modes registered) and every entry is read from a registry or a
declaration table:
- missionTypes: CA_Missions.voiceNames / voiceTemplate (declarations voiceName, voiceText, params), after every
  CoreAI/CA_Mission*.lua is required (the game loads every server file); setups: declarations of the template for
  which a voice set-up is registered (RS_MissionVoice.registerDeclaredSetup, see SETUP_CALL);
- paramKinds: RS_PersonaParams.kinds(); rewardKinds and skills: RS_Rewards.KINDS and SKILLS (rules);
- categories: personas/_categories.txt read by RS_Persona.parseCatalogue (rules.categories);
- header and sections: RS_Persona.grammar(rules) (trade arrival modes: RS_TradeArrivals.NAMES);
- voices: every shipped sheet (RS_Personas.isSheetName) read by RS_Persona.readFile with the server rules;
- items: every item type of the installed game then of the mod's own scripts, {'Module.Type': {en, fr, kg, cat}}, read
  by tools/game_items.py (name of ItemName.json, weight with the rule of RS_ItemWeights.lua, DisplayCategory) for the
  item search and the item browser of the page; itemCategories: {category: {en, fr}} named as the game's inventory
  names them (IGUI_ItemCat_<category> of IG_UI.json);
- lootLists: names of the game's loot lists for the frequency note ({loot: [...], glovebox: [...]}, tools/game_loot.py).
items, itemCategories and lootLists are read in the game folder --game (default game_items.DEFAULT_GAME, only read); when it holds no
item script, those of the current catalog.json are kept and a warning is printed: the catalogue regenerates without
the game.
Output: sorted keys, UTF-8, LF, trailing newline (diffs cleanly). tests/test_atelier_catalog.py fails when it is stale.
Python 3 standard library + lupa (dev only).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from test_personas import CORE_LUA, LUA, MOD, LuaPersona, lua_items  # noqa: E402  (loader of the lupa benches)
import game_items  # noqa: E402  (tools/, next to this file)
import game_loot  # noqa: E402

OUTPUT = ROOT / 'bridge' / 'atelier' / 'catalog.json'
PERSONAS = MOD / 'personas'
# Every mission file of the common mod: the templates register themselves in CA_Missions when required.
TEMPLATE_GLOB = 'server/CoreAI/CA_Mission*.lua'
# Voice set-ups by declaration: RS_MissionVoice keeps them private (V.registerDeclaredSetup(field, setup), one file per
# set-up under server/RadioSurvivor); their registration calls are read from the sources, the first comment line of
# the registering file describing the set-up.
SETUP_SOURCES = LUA / 'server'
MOD_MEDIA = sorted((ROOT / 'Contents' / 'mods').glob('*/*/media'), key=lambda p: p.as_posix().lower())
SETUP_CALL = re.compile(r"""\bregisterDeclaredSetup\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]""")


def load_mod() -> LuaPersona:
    """Lua state of the benches with every mission template of the common mod registered."""
    lua = LuaPersona(PERSONAS)
    for path in sorted(CORE_LUA.glob(TEMPLATE_GLOB), key=lambda p: p.name.lower()):
        lua.rt.eval(f'require("CoreAI/{path.stem}")')
    return lua


def require(lua: LuaPersona, module: str):
    return lua.rt.eval(f'require("{module}")')


def names(table) -> list[str]:
    """Sorted keys of a Lua table used as a set or a map."""
    return sorted(str(k) for k in table.keys()) if table is not None else []


def strings(table) -> list[str]:
    return [str(v) for v in lua_items(table)]


def string_map(table) -> dict[str, str]:
    return {str(k): str(v) for k, v in table.items()} if table is not None else {}


def choices(table) -> dict[str, list[str]]:
    return {str(k): strings(v) for k, v in table.items()} if table is not None else {}


def declared_setups() -> dict[str, dict[str, str]]:
    """Declaration field -> {description, file} of every voice set-up registered by declaration."""
    out = {}
    for path in sorted(SETUP_SOURCES.rglob('*.lua'), key=lambda p: p.as_posix().lower()):
        text = path.read_text(encoding='utf-8')
        for field in SETUP_CALL.findall(text):
            first = text.splitlines()[0].removeprefix('--').strip()
            out[field] = {'description': first.split(' (')[0].rstrip('.'),
                          'file': path.relative_to(ROOT).as_posix()}
    return out


def mission_types(lua: LuaPersona, setups: dict) -> dict:
    missions = require(lua, 'CoreAI/CA_Missions')
    out = {}
    for voice_name in strings(missions.voiceNames()):
        template_name, template = missions.voiceTemplate(voice_name)
        out[voice_name] = {
            'template': str(template_name),
            'voiceText': str(template.voiceText or ''),
            'params': string_map(template.params),
            'setups': [field for field in sorted(setups) if template[field] is not None],
        }
    return out


def reward_kinds(rules) -> dict:
    return {name: {'param': (str(rules.rewards[name].param) if rules.rewards[name].param is not None else None)}
            for name in names(rules.rewards)}


def categories(rules) -> dict:
    return {cid: {'items': [{'type': str(i.type), 'min': int(i.min), 'max': int(i.max)}
                            for i in lua_items(rules.categories[cid]['items'])]}
            for cid in names(rules.categories)}


def grammar(lua: LuaPersona) -> dict:
    g = require(lua, 'RadioSurvivor/RS_Persona').grammar(lua.rules)
    head = g.head
    return {
        'header': {'keys': strings(head['keys']), 'required': strings(head.required),
                   'budgetPrefix': str(head.budgetPrefix),
                   'choices': choices(head.choices)},
        'sections': {name: {'rank': int(s.rank), 'hasId': bool(s.hasId), 'keys': strings(s['keys']),
                            'required': strings(s.required), 'repeatable': strings(s.repeatable),
                            'choices': choices(s.choices)}
                     for name, s in ((str(k), v) for k, v in g.sections.items())},
        'sheet': {'format': str(g.format), 'separator': str(g.separator), 'maxPlaces': int(g.maxPlaces)},
    }


def voices(lua: LuaPersona) -> dict:
    personas = require(lua, 'RadioSurvivor/RS_Personas')
    out = {}
    for path in sorted(PERSONAS.iterdir(), key=lambda p: p.name):
        if not personas.isSheetName(path.name):
            continue
        sheet = lua.read(path.name)
        if isinstance(sheet, tuple):  # nil, reason: a shipped sheet the game refuses
            raise SystemExit(f'{path.relative_to(ROOT).as_posix()} refused by RS_Persona: {sheet[1]}')
        trade = sheet.trade
        out[str(sheet.id)] = {
            'name': str(sheet.name),
            'frequenciesKhz': [int(v) for v in lua_items(sheet.frequencies)],
            'frequencyRangesKhz': [[int(r.low), int(r.high)] for r in lua_items(sheet.frequency_ranges)],
            'arrival': str(trade.arrival) if trade is not None else None,
        }
    return out


# Readers of the installed game (folder given by --game): each takes its media folder and returns parts of the
# catalogue {name: value}; GAME_PARTS names all of them.
GAME_READERS = (
    lambda media: game_items.read_catalog([media, *MOD_MEDIA]),        # items, itemCategories
    lambda media: {'lootLists': game_loot.read_loot_lists(media)},
)
GAME_PARTS = ('itemCategories', 'items', 'lootLists')


def previous(path: Path = OUTPUT) -> dict:
    """Parts read in the game (GAME_PARTS) of the current catalogue file."""
    data = json.loads(path.read_text(encoding='utf-8')) if path.is_file() else {}
    return {name: data.get(name, {}) for name in GAME_PARTS}


def read_game(media: Path) -> dict:
    parts: dict = {}
    for read in GAME_READERS:
        parts.update(read(media))
    return {name: parts.get(name, {}) for name in GAME_PARTS}


def game_parts(game: Path = game_items.DEFAULT_GAME) -> dict:
    """GAME_PARTS read in the game installed in `game`; those of the current catalogue when the game is absent."""
    media = game_items.game_media(game)
    if media is None:
        print(f'warning: no item script under {game}: item and loot lists of the current catalogue kept',
              file=sys.stderr)
        return previous()
    return read_game(media)


def build(lua: LuaPersona, from_game: dict | None = None) -> dict:
    """Catalogue of the workshop read from the Lua state `lua` (load_mod) and the parts read in the game
    (game_parts() by default)."""
    rules = lua.rules
    setups = declared_setups()
    catalog = {
        'missionTypes': mission_types(lua, setups),
        'setups': setups,
        'paramKinds': strings(require(lua, 'RadioSurvivor/RS_PersonaParams').kinds()),
        'rewardKinds': reward_kinds(rules),
        'skills': strings(rules.skills),
        'categories': categories(rules),
        'voices': voices(lua),
    }
    catalog.update(game_parts() if from_game is None else from_game)
    catalog.update(grammar(lua))
    return catalog


def render(catalog: dict) -> str:
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Writes bridge/atelier/catalog.json from the mod and the game.')
    parser.add_argument('--game', type=Path, default=game_items.DEFAULT_GAME,
                        help='folder of Project Zomboid, only read (default: %(default)s)')
    args = parser.parse_args(argv)
    text = render(build(load_mod(), game_parts(args.game)))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    old = OUTPUT.read_bytes() if OUTPUT.is_file() else None
    new = text.encode('utf-8')
    if old == new:
        print(f'{OUTPUT.relative_to(ROOT).as_posix()} up to date')
    else:
        OUTPUT.write_bytes(new)
        print(f'{OUTPUT.relative_to(ROOT).as_posix()} written')
    print(f'{len(new)} bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
