"""Generates the zombie AnimSet nodes of Living Knox npc bodies (LK02-T05, LK04-T11) from tools/anim_table.json.

    python RadioSurvivor/tools/gen_animsets.py            # writes or updates the generated XML files
    python RadioSurvivor/tools/gen_animsets.py --check    # exit 1 when a committed file is missing, stale or edited
    python RadioSurvivor/tools/gen_animsets.py --vanilla D:/.../ProjectZomboid/media   # vanilla media folder

Output: Contents/mods/batman_RadioSurvivor/common/media/AnimSets/zombie/<state>/lkactor_*.xml. The generator owns every
lkactor_*.xml file of that tree: a file absent from the table is removed (write) or reported (check).

Rules (Java 42.21.0, see docs/conception/corps-et-animations.md, section Animations):
- complete files, no x_extends (a relative x_extends is lost on a Linux dedicated server, base file-path-case.md);
- lower-case file names; state folders spelled exactly as the vanilla folders (AnimSets/zombie/<state>, case-sensitive
  on Linux: ZomboidFileSystem.walkGameAndModFilesInternal uses new File(root, relPath));
- file names never equal to a vanilla node of the same state (same relative path = replacement, AnimState.Parse);
- every node requires the actor variable (BOOL true): a zombie without it never passes the node (AnimCondition.check:
  a missing BOOL variable passes only "false"); no OR condition (it would bypass that rule);
- m_ConditionPriority above every vanilla non-ragdoll node of the state (AnimNode.compareSelectionConditions);
- events (LK04-T11): SetVariable and PlaySound only (OnFloor refused: it puts a zombie on the floor and damages a
  fence, ClimbThroughWindowState.animEvent, ClimbOverFenceState.OnAnimEvent_OnFloor). In a state of the "progress"
  table (climbwindow, climbfence) every node is a one-shot clip that carries the SetVariable moving the Java state on:
  "<Started> BOOL false" sets <Started>=true, "<Started> BOOL true" sets <Finished>=true (the zombie actiongroup
  leaves the state only on <Finished>; a node without it keeps the body in the climb).
With the vanilla folder available, --check and write also verify the clips (media/anims_X/Bob/<clip>.x and the vanilla
player node named as proof), the state folders and the absence of collision. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLE = ROOT / 'tools' / 'anim_table.json'
MOD = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor'
OUT = MOD / 'common' / 'media' / 'AnimSets' / 'zombie'
sys.path.append(str(Path(__file__).resolve().parent))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)
DEFAULT_VANILLA = pz_paths.media_dir()
PREFIX = 'lkactor_'
CONDITION_TYPES = {'STRING', 'STRNEQ', 'BOOL', 'EQU', 'NEQ', 'LESS', 'GTR', 'ABSLESS', 'ABSGTR'}  # OR refused
EVENT_NAMES = {'SetVariable', 'PlaySound'}  # OnFloor, SetState, CheckAttack... refused
EVENT_TIMES = {'Start', 'End'}              # or a fraction of the clip (m_TimePc)


class TableError(ValueError):
    pass


def load_table(path: Path = TABLE) -> dict:
    table = json.loads(path.read_text(encoding='utf-8'))
    validate(table)
    return table


def validate(table: dict) -> None:
    actor, gesture = table['actorVariable'], table['gestureVariable']
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', actor) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', gesture):
        raise TableError('variable names must be identifiers')
    phase = table.get('phaseVariable')  # LK04-T13: two-clip gestures, reset by LK_Anim at every gesture change
    if phase is not None and (not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', phase)
                              or phase.lower() in (actor.lower(), gesture.lower())):
        raise TableError('phaseVariable must be an identifier distinct from the actor and gesture variables')
    if not isinstance(table['conditionPriority'], int) or table['conditionPriority'] <= 0:
        raise TableError('conditionPriority must be a positive integer')
    gestures, states = set(table['gestures']), set(table['states'])
    seen_files, seen_names = set(), set()
    for node in table['nodes']:
        where = node.get('file', '?')
        if not re.fullmatch(PREFIX + r'[a-z0-9_]+\.xml', node['file']):
            raise TableError(f'{where}: file name must be lower case, start with {PREFIX} and end with .xml')
        if not re.fullmatch(r'Bob_[A-Za-z0-9_]+', node['clip']):
            raise TableError(f'{where}: clip must be a Bob_ clip')
        if not node['states'] or not set(node['states']) <= states:
            raise TableError(f'{where}: unknown state in {node["states"]}')
        for state in node['states']:
            for key, seen in (((state, node['file'].lower()), seen_files), ((state, node['name'].lower()), seen_names)):
                if key in seen:
                    raise TableError(f'{where}: duplicate {key} in state {state}')
                seen.add(key)
        extra = node.get('stateConditions', {})
        if not set(extra) <= set(node['states']):
            raise TableError(f'{where}: stateConditions for a state the node is not in')
        for cond in list(node['conditions']) + [c for cs in extra.values() for c in cs]:
            name, ctype, value = cond
            if ctype not in CONDITION_TYPES:
                raise TableError(f'{where}: condition type {ctype} refused')
            if name.lower() == actor.lower():
                raise TableError(f'{where}: the actor condition is added by the generator')
            if name.lower() == gesture.lower() and (ctype != 'STRING' or value not in gestures):
                raise TableError(f'{where}: gesture condition must be STRING with a known gesture ({value})')
        for key in ('speedScale', 'blendTime'):
            float(node[key])
        validate_events(table, node)


def validate_events(table: dict, node: dict) -> None:
    where = node['file']
    sets = set()
    for event in node.get('events', []):
        name, time, value = event
        if name not in EVENT_NAMES:
            raise TableError(f'{where}: event {name} refused (allowed: {sorted(EVENT_NAMES)})')
        if time not in EVENT_TIMES:
            pc = float(time)
            if not 0.0 <= pc <= 1.0:
                raise TableError(f'{where}: event time {time} out of 0..1')
        if not value or not re.fullmatch(r'[A-Za-z0-9_=.]+', value):
            raise TableError(f'{where}: event value {value!r} refused')
        if name == 'SetVariable':
            if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*=[A-Za-z0-9_.]+', value):
                raise TableError(f'{where}: SetVariable value must be name=value ({value})')
            sets.add(value.lower())
    for state in node['states']:
        progress = table.get('progress', {}).get(state)
        if progress is None:
            continue
        started, finished = progress
        if node['looped']:
            raise TableError(f'{where}: a {state} node must not loop (its End event moves the state on)')
        conds = {(c[0].lower(), c[1], c[2]) for c in conditions(table, node, state)}
        if (started.lower(), 'BOOL', 'false') in conds:
            needed = f'{started}=true'
        elif (started.lower(), 'BOOL', 'true') in conds:
            needed = f'{finished}=true'
        else:
            raise TableError(f'{where}: a {state} node needs a {started} BOOL condition')
        if needed.lower() not in sets:
            raise TableError(f'{where}: missing SetVariable {needed} (the body would stay in {state})')


def conditions(table: dict, node: dict, state: str) -> list[tuple[str, str, str]]:
    """Every condition of the node in this state, the actor condition first."""
    out = [(table['actorVariable'], 'BOOL', 'true')]
    out += [tuple(c) for c in node['conditions']]
    out += [tuple(c) for c in node.get('stateConditions', {}).get(state, [])]
    return out


def render(table: dict, node: dict, state: str) -> str:
    """Complete node file, vanilla layout (tabs, utf-8 declaration, no comment, no x_extends)."""
    lines = ['<?xml version="1.0" encoding="utf-8"?>', '<animNode>',
             f'\t<m_Name>{node["name"]}</m_Name>',
             f'\t<m_AnimName>{node["clip"]}</m_AnimName>',
             f'\t<m_ConditionPriority>{table["conditionPriority"]}</m_ConditionPriority>',
             f'\t<m_Looped>{"true" if node["looped"] else "false"}</m_Looped>',
             f'\t<m_BlendTime>{node["blendTime"]}</m_BlendTime>',
             f'\t<m_SpeedScale>{node["speedScale"]}</m_SpeedScale>']
    for name, ctype, value in conditions(table, node, state):
        lines += ['\t<m_Conditions>', f'\t\t<m_Name>{name}</m_Name>', f'\t\t<m_Type>{ctype}</m_Type>',
                  f'\t\t<m_Value>{value}</m_Value>', '\t</m_Conditions>']
    for name, time, value in node.get('events', []):
        when = f'\t\t<m_Time>{time}</m_Time>' if time in EVENT_TIMES else f'\t\t<m_TimePc>{time}</m_TimePc>'
        lines += ['\t<m_Events>', f'\t\t<m_EventName>{name}</m_EventName>', when,
                  f'\t\t<m_ParameterValue>{value}</m_ParameterValue>', '\t</m_Events>']
    lines.append('</animNode>')
    return '\n'.join(lines) + '\n'


def expected_files(table: dict, out: Path = OUT) -> dict[Path, str]:
    files = {}
    for node in table['nodes']:
        for state in node['states']:
            files[out / state / node['file']] = render(table, node, state)
    return files


def existing_files(out: Path = OUT) -> list[Path]:
    if not out.is_dir():
        return []
    return sorted(p for p in out.glob('*/*') if p.is_file() and p.name.lower().startswith(PREFIX))


def read_normalized(path: Path) -> str:
    return path.read_bytes().decode('utf-8').replace('\r\n', '\n')


# ------------------------------------------------------------------ vanilla checks

def vanilla_priority(path: Path, state_dir: Path) -> tuple[int, bool]:
    """(m_ConditionPriority, ragdoll) of a vanilla node, following its x_extends chain in the same folder."""
    priority, ragdoll, seen = None, False, set()
    while path is not None and path.is_file() and path not in seen:
        seen.add(path)
        root = ET.fromstring(path.read_text(encoding='utf-8', errors='replace').lstrip('\ufeff'))
        if priority is None and root.find('m_ConditionPriority') is not None:
            priority = int(root.find('m_ConditionPriority').text.strip())
        if root.find('m_isRagdoll') is not None and root.find('m_isRagdoll').text.strip() == 'true':
            ragdoll = True
        parent = root.get('x_extends')
        path = (state_dir / parent) if parent else None
    return (priority or 0), ragdoll


def check_vanilla(table: dict, vanilla: Path) -> list[str]:
    problems = []
    zombie = vanilla / 'AnimSets' / 'zombie'
    actual_states = {p.name for p in zombie.iterdir() if p.is_dir()} if zombie.is_dir() else set()
    for state in table['states']:
        if state not in actual_states:
            problems.append(f'vanilla state folder AnimSets/zombie/{state} missing (exact case)')
            continue
        vanilla_nodes = {p.name.lower(): p for p in (zombie / state).glob('*.xml')}
        for node in table['nodes']:
            if state in node['states'] and node['file'].lower() in vanilla_nodes:
                problems.append(f'{state}/{node["file"]} collides with a vanilla node (it would replace it)')
        # Ragdoll nodes (vehicle collision, priority 10) stay above ours on purpose: a physical reaction wins.
        priorities = [vanilla_priority(p, zombie / state) for p in vanilla_nodes.values()]
        highest = max((pr for pr, ragdoll in priorities if not ragdoll), default=0)
        if highest >= table['conditionPriority']:
            problems.append(f'{state}: a vanilla node has m_ConditionPriority {highest} >= ours')
        progress = table.get('progress', {}).get(state)
        if progress is not None:  # the vanilla zombie nodes of the state move it on with the same variables
            texts = ' '.join(p.read_text(encoding='utf-8', errors='replace') for p in vanilla_nodes.values())
            for var in progress:
                if f'<m_ParameterValue>{var}=true</m_ParameterValue>' not in texts:
                    problems.append(f'{state}: no vanilla node sets {var}=true')
    for node in table['nodes']:
        clip_file = vanilla / 'anims_X' / 'Bob' / (node['clip'] + '.x')
        if not clip_file.is_file():
            problems.append(f'{node["file"]}: clip file anims_X/Bob/{node["clip"]}.x missing')
        proof = vanilla / node['proof']
        if not proof.is_file():
            problems.append(f'{node["file"]}: proof {node["proof"]} missing')
        elif f'<m_AnimName>{node["clip"]}</m_AnimName>' not in proof.read_text(encoding='utf-8', errors='replace'):
            problems.append(f'{node["file"]}: {node["proof"]} does not play {node["clip"]}')
    return problems


# ------------------------------------------------------------------ main

def compare(table: dict, out: Path = OUT) -> list[str]:
    """Differences between the table and the files on disk (empty list = up to date)."""
    problems = []
    expected = expected_files(table, out)
    for path, text in expected.items():
        if not path.is_file():
            problems.append(f'missing {path.relative_to(out).as_posix()}')
        elif read_normalized(path) != text:
            problems.append(f'stale or edited {path.relative_to(out).as_posix()}')
    for path in existing_files(out):
        if path not in expected:
            problems.append(f'not in the table {path.relative_to(out).as_posix()}')
    return problems


def write(table: dict, out: Path = OUT) -> tuple[int, int]:
    """Writes the changed files and removes the stale ones; returns (written, removed)."""
    expected = expected_files(table, out)
    written = removed = 0
    for path, text in expected.items():
        if path.is_file() and read_normalized(path) == text:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode('utf-8'))
        written += 1
    for path in existing_files(out):
        if path not in expected:
            path.unlink()
            removed += 1
    return written, removed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Living Knox zombie AnimSet nodes generator.')
    parser.add_argument('--check', action='store_true', help='verify only; exit 1 when a file is not up to date')
    parser.add_argument('--vanilla', type=Path, default=DEFAULT_VANILLA, help='vanilla media folder')
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    try:
        table = load_table()
    except (TableError, KeyError, ValueError) as exc:
        print(f'FAIL table: {exc}')
        return 1
    problems = []
    if args.vanilla.is_dir():
        problems += check_vanilla(table, args.vanilla)
        vanilla_note = f'vanilla checked ({args.vanilla})'
    else:
        vanilla_note = f'vanilla folder not found, clips not checked ({args.vanilla})'
    count = len(expected_files(table))
    if args.check:
        problems += compare(table)
        for p in problems:
            print('FAIL ' + p)
        print(f'{"FAIL" if problems else "OK"}: {count} node file(s), {vanilla_note}')
        return 1 if problems else 0
    if problems:
        for p in problems:
            print('FAIL ' + p)
        print('nothing written')
        return 1
    written, removed = write(table)
    print(f'OK: {count} node file(s), {written} written, {removed} removed, {vanilla_note}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
