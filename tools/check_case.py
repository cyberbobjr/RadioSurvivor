"""Case check of every path of the RadioSurvivor mods for a Linux (case-sensitive) dedicated server (LK13-T05).

    python RadioSurvivor/tools/check_case.py                       # published mod, then the development mod
    python RadioSurvivor/tools/check_case.py --vanilla D:/.../ProjectZomboid/media
    python RadioSurvivor/tools/check_case.py --mod PATH [--dep PATH ...]   # any mod folder (tests)

Static check only: Windows hides every case error, a Linux server does not. Each mod folder (the one holding
mod.info or common/ and the version folders) is checked with its dependencies (the development mod requires the
published one, both require batman_BeltRadio and batman_SignalSmoke from the sibling repositories Workshop/BeltRadio
and Workshop/SignalSmoke) against the vanilla
media folder, exact case everywhere:

  layout       mod.info, common/ and media/ spelled exactly (ChooseGameInfo resolves "common" and new File(dir,
               "media"): a "Media" folder is ignored on Linux, base file-path-case.md);
  vanilla-dir  a mod folder whose path matches a vanilla folder ignoring case must match it exactly (media/lua/
               shared/Translate/EN, media/AnimSets, media/textures...);
  anim-state   media/AnimSets/<group>/<state> and media/actiongroups/<group>/<state> exist in vanilla with exactly
               this case (a state folder of another case replaces the whole vanilla state, zombies-as-npc-bodies.md);
  collision    two files of the mod (common + version folders + dependencies) whose paths differ only by case;
  vanilla-file a mod file at the path of a vanilla file, ignoring case (replacement of the vanilla file, or two files
               on Linux); translation files are merged by Translator, not replaced: only their case is checked;
  require      require "X/Y" of a Lua file resolves to a Lua file of the mod, of a dependency or of vanilla
               (media/lua/<client|shared|server>/X/Y.lua) with the same case;
  media-ref    "media/..." string literals of the Lua files (comments ignored) and of media/scripts: file (or folder for
               a literal followed by ..) present in the mod, a dependency or vanilla with the same case; script fields
               Icon / mesh / texture: reported only when a file matches ignoring case (vanilla ones live in .pack);
  mod-info     poster= and icon= files next to mod.info, same case;
  translation  media/lua/shared/Translate/<LANG>/<File>.json: LANG a vanilla language folder, File a type read by
               Translator (Translator.BY_NAME or Mod, Java 42.21.0: new File(".../Translate/%s/%s.json"));
  sandbox      sandbox-options.txt: Sandbox_<translation> and Sandbox_<page> keys present in EN/Sandbox.json, no key
               of another case in any language; SandboxVars.A.B and "A.B" option names of the Lua files spelled as
               the options (Lua tables and getOptionByName are case-sensitive).

Output: one "OK" line per mod or the list of errors (rule, path, problem, expected). Exit code 0 when no error, 1
otherwise, 2 when a folder is missing. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN_MOD = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor'
DEV_MOD = ROOT / 'dev' / 'batman_RadioSurvivorTests'
# Required mod (require=batman_BeltRadio), from the sibling repository: dependency of both checked mods.
BELT_MOD = ROOT.parent / 'BeltRadio' / 'Contents' / 'mods' / 'batman_BeltRadio'
# Required mod (require=batman_SignalSmoke, 2026-10-15), from the sibling repository: dependency of both checked mods.
SIGNAL_MOD = ROOT.parent / 'SignalSmoke' / 'Contents' / 'mods' / 'batman_SignalSmoke'
sys.path.append(str(Path(__file__).resolve().parent))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)
DEFAULT_VANILLA = pz_paths.media_dir()

LUA_SIDES = ('client', 'shared', 'server')
ANIM_ROOTS = ('AnimSets', 'actiongroups')
TRANSLATE = 'lua/shared/Translate'
# zombie/core/Translator.java (42.21.0) BY_NAME, plus "Mod" (readModTranslation).
TRANSLATION_TYPES = (
    'Tooltip', 'IG_UI', 'Recipes', 'RecipeGroups', 'Farming', 'ContextMenu', 'SurvivalGuide', 'UI', 'Items',
    'ItemName', 'Moodles', 'Sandbox', 'Challenge', 'Stash', 'Moveables', 'MakeUp', 'GameSound', 'DynamicRadio',
    'EvolvedRecipeName', 'Recorded_Media', 'SurvivorNames', 'Attributes', 'Fluids', 'Print_Media', 'Print_Text',
    'Entity', 'RadioData', 'BodyParts', 'MapLabel', 'Credits', 'Mod')
VERSION_DIR = re.compile(r'^\d+(\.\d+)*$')
# Files of the vanilla media folder a mod may knowingly replace (relative to media, exact case). None today.
ALLOWED_REPLACEMENTS: frozenset[str] = frozenset()


class Problem:
    def __init__(self, rule: str, path: str, message: str, expected: str = ''):
        self.rule, self.path, self.message, self.expected = rule, path, message, expected

    def __str__(self) -> str:
        text = f'ERROR [{self.rule}] {self.path}: {self.message}'
        return text + (f' (expected: {self.expected})' if self.expected else '')


class Tree:
    """Files and folders of a media root, relative paths with '/' (exact case), with a lower-case index."""

    def __init__(self):
        self.files: dict[str, str] = {}   # exact relative path -> label of the source (for messages)
        self.dirs: set[str] = set()
        self.lower_files: dict[str, set[str]] = {}
        self.lower_dirs: dict[str, set[str]] = {}

    def add_file(self, rel: str, label: str) -> None:
        self.files.setdefault(rel, label)
        self.lower_files.setdefault(rel.lower(), set()).add(rel)

    def add_dir(self, rel: str) -> None:
        self.dirs.add(rel)
        self.lower_dirs.setdefault(rel.lower(), set()).add(rel)

    def add_media(self, media: Path, label: str) -> None:
        for dirpath, dirnames, filenames in os.walk(media):
            base = Path(dirpath).relative_to(media).as_posix()
            base = '' if base == '.' else base + '/'
            for d in dirnames:
                self.add_dir(base + d)
            for f in filenames:
                self.add_file(base + f, label)

    def find_file(self, rel: str) -> tuple[bool, list[str]]:
        """(exact match, spellings matching ignoring case)."""
        return rel in self.files, sorted(self.lower_files.get(rel.lower(), ()))

    def find_dir(self, rel: str) -> tuple[bool, list[str]]:
        rel = rel.rstrip('/')
        return rel in self.dirs, sorted(self.lower_dirs.get(rel.lower(), ()))


class Mod:
    def __init__(self, path: Path):
        self.path = path
        self.name = path.name
        self.variants: list[Path] = []   # common first, then the version folders (load order)
        common = path / 'common'
        if common.is_dir():
            self.variants.append(common)
        self.variants += sorted((p for p in path.iterdir() if p.is_dir() and VERSION_DIR.match(p.name)),
                                key=lambda p: [int(x) for x in p.name.split('.')])
        self.media = Tree()
        for variant in self.variants:
            media = variant / 'media'
            if media.is_dir():
                self.media.add_media(media, f'{self.name}/{variant.name}')

    def media_dirs(self) -> list[tuple[Path, Path]]:
        return [(v, v / 'media') for v in self.variants if (v / 'media').is_dir()]

    def rel(self, p: Path) -> str:
        return p.relative_to(self.path.parent).as_posix()


def load_vanilla(vanilla: Path) -> Tree:
    tree = Tree()
    tree.add_media(vanilla, 'vanilla')
    return tree


# ------------------------------------------------------------------ Lua lexer (comments and string literals)

def lua_strings(text: str) -> tuple[str, list[tuple[str, int, int]]]:
    """Code with comments blanked, and the string literals (value, start, end) of the code."""
    out = list(text)
    strings = []
    i, n = 0, len(text)
    long_open = re.compile(r'\[(=*)\[')

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != '\n':
                out[k] = ' '

    while i < n:
        c = text[i]
        if text.startswith('--', i):
            m = long_open.match(text, i + 2)
            if m:
                close = ']' + m.group(1) + ']'
                end = text.find(close, m.end())
                end = n if end < 0 else end + len(close)
            else:
                end = text.find('\n', i)
                end = n if end < 0 else end
            blank(i, end)
            i = end
        elif c in '"\'':
            j, buf = i + 1, []
            while j < n and text[j] != c and text[j] != '\n':
                if text[j] == '\\' and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            strings.append((''.join(buf), i, j + 1))
            i = j + 1
        elif c == '[' and long_open.match(text, i):
            m = long_open.match(text, i)
            close = ']' + m.group(1) + ']'
            end = text.find(close, m.end())
            end = n if end < 0 else end
            strings.append((text[m.end():end], i, end + len(close)))
            i = end + len(close)
        else:
            i += 1
    return ''.join(out), strings


def strip_script_comments(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


# ------------------------------------------------------------------ rules

def expect(spellings: list[str], prefix: str = '') -> str:
    return ' or '.join(prefix + s for s in spellings)


def check_layout(mod: Mod) -> list[Problem]:
    problems = []
    for child in sorted(mod.path.iterdir()):
        low = child.name.lower()
        if child.is_file() and low == 'mod.info' and child.name != 'mod.info':
            problems.append(Problem('layout', mod.rel(child), 'mod.info spelled with another case', 'mod.info'))
        if child.is_dir() and low == 'common' and child.name != 'common':
            problems.append(Problem('layout', mod.rel(child), 'common folder spelled with another case', 'common'))
    for variant in [mod.path] + mod.variants:
        for child in sorted(variant.iterdir()):
            if child.is_dir() and child.name.lower() == 'media' and child.name != 'media':
                problems.append(Problem('layout', mod.rel(child), 'media folder ignored on Linux', 'media'))
            if variant is not mod.path and child.is_file() and child.name.lower() == 'mod.info' \
                    and child.name != 'mod.info':
                problems.append(Problem('layout', mod.rel(child), 'mod.info spelled with another case', 'mod.info'))
    return problems


def check_vanilla_dirs(mod: Mod, vanilla: Tree) -> list[Problem]:
    problems = []
    for rel in sorted(mod.media.dirs):
        exact, spellings = vanilla.find_dir(rel)
        if not exact and spellings:
            problems.append(Problem('vanilla-dir', f'{mod.name}: media/{rel}', 'vanilla folder spelled with another '
                                    'case', expect(spellings, 'media/')))
    for rel in sorted(mod.media.dirs):
        parts = rel.split('/')
        if len(parts) != 3 or parts[0].lower() not in {r.lower() for r in ANIM_ROOTS}:
            continue
        exact, spellings = vanilla.find_dir(rel)
        if not exact:
            problems.append(Problem('anim-state', f'{mod.name}: media/{rel}',
                                    'state folder absent from vanilla with this exact case',
                                    expect(spellings, 'media/') if spellings else 'an existing vanilla state folder'))
    return problems


def is_translation(rel: str) -> bool:
    return rel.lower().startswith(TRANSLATE.lower() + '/')


def check_collisions(mod: Mod, deps: list[Mod], vanilla: Tree) -> list[Problem]:
    problems = []
    for low, spellings in sorted(mod.media.lower_files.items()):
        if len(spellings) > 1:
            problems.append(Problem('collision', f'{mod.name}: media/{sorted(spellings)[0]}',
                                    'files differing only by case: ' + ', '.join(sorted(spellings)),
                                    'a single spelling'))
        rel = sorted(spellings)[0]
        for dep in deps:
            other = sorted(dep.media.lower_files.get(low, ()))
            # sandbox-options.txt is read from each mod's own folder (CustomSandboxOptions.java:33-47, 42.21.0): not a
            # replacement between mods.
            if other and not is_translation(rel) and rel != 'sandbox-options.txt':
                problems.append(Problem('collision', f'{mod.name}: media/{rel}',
                                        f'same path as a file of {dep.name} ignoring case (' + ', '.join(other) + ')',
                                        'a path of its own'))
        exact, vspell = vanilla.find_file(rel)
        if not vspell:
            continue
        if is_translation(rel):
            if not exact:
                problems.append(Problem('vanilla-file', f'{mod.name}: media/{rel}', 'translation file of another case '
                                        'than the vanilla one', expect(vspell, 'media/')))
        elif rel in ALLOWED_REPLACEMENTS:
            continue
        elif exact:
            problems.append(Problem('vanilla-file', f'{mod.name}: media/{rel}', 'replaces the vanilla file of the same '
                                    'path', 'another file name (or ALLOWED_REPLACEMENTS if intended)'))
        else:
            problems.append(Problem('vanilla-file', f'{mod.name}: media/{rel}', 'path of a vanilla file with another '
                                    'case (replacement on Windows, second file on Linux)', expect(vspell, 'media/')))
    return problems


def lua_files(mod: Mod) -> list[tuple[Path, str]]:
    out = []
    for _, media in mod.media_dirs():
        for path in sorted(media.rglob('*')):
            if path.is_file() and path.suffix.lower() == '.lua':
                out.append((path, path.relative_to(media).as_posix()))
    return out


def resolve(rel: str, trees: list[Tree]) -> tuple[bool, list[str]]:
    spellings: set[str] = set()
    for tree in trees:
        exact, found = tree.find_file(rel)
        if exact:
            return True, []
        spellings.update(found)
    return False, sorted(spellings)


def resolve_dir(rel: str, trees: list[Tree]) -> tuple[bool, list[str]]:
    spellings: set[str] = set()
    for tree in trees:
        exact, found = tree.find_dir(rel)
        if exact:
            return True, []
        spellings.update(found)
    return False, sorted(spellings)


def line_of(text: str, index: int) -> int:
    return text.count('\n', 0, index) + 1


def check_lua(mod: Mod, deps: list[Mod], vanilla: Tree) -> list[Problem]:
    problems = []
    trees = [mod.media] + [d.media for d in deps] + [vanilla]
    for path, rel in lua_files(mod):
        text = path.read_text(encoding='utf-8', errors='replace')
        code, strings = lua_strings(text)
        where = f'{mod.name}: media/{rel}'
        for value, start, end in strings:
            line = line_of(text, start)
            before = code[:start].rstrip().rstrip('(').rstrip()
            if re.search(r'(^|[^\w.:])require$', before):
                target = value if value.endswith('.lua') else value + '.lua'
                candidates = [f'lua/{side}/{target}' for side in LUA_SIDES]
                found, spellings = False, set()
                for cand in candidates:
                    exact, spell = resolve(cand, trees)
                    if exact:
                        found = True
                        break
                    spellings.update(spell)
                if not found:
                    expected = ', '.join(f'require "{s.split("/", 2)[2][:-4]}" ({s})' for s in sorted(spellings))
                    problems.append(Problem('require', f'{where}:{line}', f'require "{value}" '
                                            + ('spelled with another case' if spellings else 'not found'),
                                            expected or 'an existing Lua file'))
                continue
            if value.lower().startswith('media/'):
                after = code[end:].lstrip()
                target = value[len('media/'):]
                if after.startswith('..') or target.endswith('/'):
                    folder = target.rsplit('/', 1)[0] if '/' in target else ''
                    if not folder:
                        continue
                    exact, spellings = resolve_dir(folder, trees)
                    if not exact:
                        problems.append(Problem('media-ref', f'{where}:{line}', f'folder "media/{folder}/" '
                                                + ('spelled with another case' if spellings else 'not found'),
                                                expect(spellings, 'media/')))
                else:
                    exact, spellings = resolve(target, trees)
                    if not exact:
                        problems.append(Problem('media-ref', f'{where}:{line}', f'"{value}" '
                                                + ('spelled with another case' if spellings else 'not found'),
                                                expect(spellings, 'media/')))
    return problems


SCRIPT_FIELDS = {
    'icon': lambda v: [f'textures/Item_{v}.png', f'textures/{v}.png'],
    'mesh': lambda v: [f'models_X/{v}{ext}' for ext in ('.fbx', '.FBX', '.x', '.X', '.glb')],
    'texture': lambda v: [f'textures/{v}.png'],
}


def check_scripts(mod: Mod, deps: list[Mod], vanilla: Tree) -> list[Problem]:
    problems = []
    trees = [mod.media] + [d.media for d in deps] + [vanilla]
    for _, media in mod.media_dirs():
        scripts = media / 'scripts'
        if not scripts.is_dir():
            continue
        for path in sorted(scripts.rglob('*.txt')):
            text = strip_script_comments(path.read_text(encoding='utf-8', errors='replace'))
            where = f'{mod.name}: media/{path.relative_to(media).as_posix()}'
            for m in re.finditer(r'media/[^\s,;"\'{}]+', text):
                target = m.group(0)[len('media/'):]
                exact, spellings = resolve(target, trees)
                if not exact:
                    problems.append(Problem('media-ref', f'{where}:{line_of(text, m.start())}', f'"{m.group(0)}" '
                                            + ('spelled with another case' if spellings else 'not found'),
                                            expect(spellings, 'media/')))
            for m in re.finditer(r'\b(\w+)\s*=\s*([^,\n{}=]+?)\s*,', text):
                field, value = m.group(1).lower(), m.group(2).strip()
                if field not in SCRIPT_FIELDS or value.lower().startswith('media/') or not value:
                    continue
                value = value.replace('\\', '/')
                cands = SCRIPT_FIELDS[field](value)
                if any(resolve(c, trees)[0] for c in cands):
                    continue
                spellings = sorted({s for c in cands for s in resolve(c, trees)[1]})
                if spellings:
                    problems.append(Problem('media-ref', f'{where}:{line_of(text, m.start(2))}',
                                            f'{m.group(1)} = {value}: file spelled with another case',
                                            expect(spellings, 'media/')))
    return problems


def read_mod_info(path: Path) -> dict[str, list[str]]:
    data: dict[str, list[str]] = {}
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            data.setdefault(key.strip().lower(), []).append(value.strip())
    return data


def check_mod_info(mod: Mod) -> list[Problem]:
    problems = []
    for folder in [mod.path] + mod.variants:
        info = folder / 'mod.info'
        if not info.is_file():
            continue
        data = read_mod_info(info)
        for key in ('poster', 'icon'):
            for value in data.get(key, []):
                if not value:
                    continue
                target = folder / value.replace('\\', '/')
                names = {p.name for p in target.parent.iterdir()} if target.parent.is_dir() else set()
                if target.name in names:
                    continue
                other = sorted(n for n in names if n.lower() == target.name.lower())
                problems.append(Problem('mod-info', f'{mod.rel(info)}', f'{key}={value} '
                                        + ('spelled with another case' if other else 'not found'),
                                        ', '.join(other)))
    return problems


def vanilla_languages(vanilla: Tree) -> list[str]:
    prefix = TRANSLATE + '/'
    return sorted(d[len(prefix):] for d in vanilla.dirs if d.startswith(prefix) and '/' not in d[len(prefix):])


def check_translations(mod: Mod, vanilla: Tree) -> list[Problem]:
    problems = []
    languages = vanilla_languages(vanilla)
    lower_lang = {lang.lower(): lang for lang in languages}
    lower_types = {t.lower(): t for t in TRANSLATION_TYPES}
    for rel in sorted(mod.media.files):
        if not is_translation(rel) or not rel.startswith(TRANSLATE + '/'):
            continue
        parts = rel[len(TRANSLATE) + 1:].split('/')
        where = f'{mod.name}: media/{rel}'
        if len(parts) != 2:
            problems.append(Problem('translation', where, 'not in a language folder (Translate/<LANG>/<File>.json)'))
            continue
        lang, name = parts
        if languages and lang not in languages:
            problems.append(Problem('translation', where, f'language folder "{lang}" unknown to the game',
                                    lower_lang.get(lang.lower(), 'a vanilla language folder (EN, FR...)')))
        stem, dot, ext = name.rpartition('.')
        if not dot or ext != 'json':
            problems.append(Problem('translation', where, 'translation file not read (.json only, lower case)',
                                    (stem or name) + '.json'))
            continue
        if stem not in TRANSLATION_TYPES:
            problems.append(Problem('translation', where, f'file "{name}" not read by Translator',
                                    lower_types[stem.lower()] + '.json' if stem.lower() in lower_types
                                    else 'one of ' + ', '.join(TRANSLATION_TYPES)))
    return problems


def parse_sandbox(text: str) -> list[dict]:
    text = strip_script_comments(text)
    options = []
    for m in re.finditer(r'option\s+([\w.]+)\s*\{(.*?)\}', text, flags=re.S):
        fields = dict((k.lower(), v.strip()) for k, v in re.findall(r'(\w+)\s*=\s*([^,\n]*)\s*,?', m.group(2)))
        options.append({'name': m.group(1), 'fields': fields, 'line': line_of(text, m.start())})
    return options


def translation_maps(mod: Mod, kind: str) -> dict[str, tuple[str, dict]]:
    """Language -> (relative path, keys) of the <kind>.json files of the mod."""
    out = {}
    for _, media in mod.media_dirs():
        base = media / Path(TRANSLATE)
        if not base.is_dir():
            continue
        for lang_dir in sorted(p for p in base.iterdir() if p.is_dir()):
            path = lang_dir / f'{kind}.json'
            if path.is_file():
                try:
                    data = json.loads(path.read_text(encoding='utf-8-sig'))
                except ValueError:
                    data = {}
                rel = path.relative_to(media).as_posix()
                merged = out.get(lang_dir.name, (rel, {}))[1]
                merged.update(data if isinstance(data, dict) else {})
                out[lang_dir.name] = (rel, merged)
    return out


def check_sandbox(mod: Mod, deps: list[Mod]) -> list[Problem]:
    problems = []
    options: list[dict] = []
    owner: dict[str, str] = {}
    for m in [mod] + deps:
        for variant, media in m.media_dirs():
            path = media / 'sandbox-options.txt'
            if path.is_file():
                for option in parse_sandbox(path.read_text(encoding='utf-8', errors='replace')):
                    option['where'] = f'{m.name}: {m.rel(path)}:{option["line"]}'
                    option['mod'] = m
                    options.append(option)
                    owner[option['name']] = m.name
    if not options:
        return problems
    own = [o for o in options if o['mod'] is mod]
    maps = translation_maps(mod, 'Sandbox')
    for option in own:
        short = option['name'].split('.')[-1]
        keys = ['Sandbox_' + option['fields'].get('translation', short)]
        if option['fields'].get('page'):
            keys.append('Sandbox_' + option['fields']['page'])
        for key in keys:
            en = maps.get('EN')
            if en is not None and key not in en[1]:
                other = sorted(k for k in en[1] if k.lower() == key.lower())
                problems.append(Problem('sandbox', option['where'], f'key {key} '
                                        + ('spelled with another case in ' if other else 'absent from ')
                                        + f'media/{en[0]}', ', '.join(other) or key))
            for lang, (rel, data) in sorted(maps.items()):
                if lang == 'EN' or key in data:
                    continue
                other = sorted(k for k in data if k.lower() == key.lower())
                if other:
                    problems.append(Problem('sandbox', f'{mod.name}: media/{rel}', f'key {other[0]} of another case',
                                            key))
    names = {o['name'] for o in options}
    lower_names = {n.lower(): n for n in names}
    namespaces = {n.split('.')[0] for n in names if '.' in n}
    lower_ns = {n.lower(): n for n in namespaces}
    for path, rel in lua_files(mod):
        text = path.read_text(encoding='utf-8', errors='replace')
        code, strings = lua_strings(text)
        where = f'{mod.name}: media/{rel}'
        for m in re.finditer(r'SandboxVars\.(\w+)(?:\.(\w+))?', code):
            ns, short = m.group(1), m.group(2)
            if ns.lower() not in lower_ns:
                continue
            if ns != lower_ns[ns.lower()]:
                problems.append(Problem('sandbox', f'{where}:{line_of(text, m.start())}',
                                        f'SandboxVars.{ns}: namespace of another case', 'SandboxVars.'
                                        + lower_ns[ns.lower()]))
            elif short:
                full = f'{ns}.{short}'
                if full not in names and full.lower() in lower_names:
                    problems.append(Problem('sandbox', f'{where}:{line_of(text, m.start())}',
                                            f'SandboxVars.{full}: option of another case',
                                            'SandboxVars.' + lower_names[full.lower()]))
        for value, start, _ in strings:
            low = value.lower()
            if low in lower_names and value not in names:
                problems.append(Problem('sandbox', f'{where}:{line_of(text, start)}', f'option "{value}" of another '
                                        'case', lower_names[low]))
            elif low.endswith('.') and low[:-1] in lower_ns and value[:-1] not in namespaces:
                problems.append(Problem('sandbox', f'{where}:{line_of(text, start)}', f'option prefix "{value}" of '
                                        'another case', lower_ns[low[:-1]] + '.'))
    return problems


def check_mod(mod_path: Path, dep_paths: list[Path], vanilla: Tree) -> list[Problem]:
    mod = Mod(mod_path)
    deps = [Mod(p) for p in dep_paths]
    problems = []
    problems += check_layout(mod)
    problems += check_vanilla_dirs(mod, vanilla)
    problems += check_collisions(mod, deps, vanilla)
    problems += check_lua(mod, deps, vanilla)
    problems += check_scripts(mod, deps, vanilla)
    problems += check_mod_info(mod)
    problems += check_translations(mod, vanilla)
    problems += check_sandbox(mod, deps)
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Case check of the RadioSurvivor mods (Linux servers).')
    parser.add_argument('--vanilla', type=Path, default=DEFAULT_VANILLA, help='vanilla media folder')
    parser.add_argument('--mod', type=Path, action='append', help='mod folder to check (repeatable; default: the '
                        'published mod, then the development mod)')
    parser.add_argument('--dep', type=Path, action='append', default=[], help='dependency of every --mod')
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    if not args.vanilla.is_dir():
        print(f'vanilla media folder not found: {args.vanilla} (use --vanilla)')
        return 2
    targets = [(p, args.dep) for p in args.mod] if args.mod else [(MAIN_MOD, [BELT_MOD, SIGNAL_MOD]),
                                                                  (DEV_MOD, [MAIN_MOD, BELT_MOD, SIGNAL_MOD])]
    for path, deps in targets:
        for p in [path] + deps:
            if not p.is_dir():
                print(f'mod folder not found: {p}')
                return 2
    vanilla = load_vanilla(args.vanilla)
    total = 0
    for path, deps in targets:
        problems = check_mod(path, deps, vanilla)
        total += len(problems)
        if problems:
            print(f'{path.name}: {len(problems)} error(s)')
            for problem in problems:
                print('  ' + str(problem))
        else:
            print(f'{path.name}: OK (case of every path checked against {args.vanilla})')
    print('RESULT: ' + ('FAIL' if total else 'PASS'))
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
