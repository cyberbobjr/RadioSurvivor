"""Repository checks of RadioSurvivor in one command (LK01-T05).

    python RadioSurvivor/tests/run_all.py [--mod radiosurvivor|livingknox] [--keep-going] [--only NAME ...]
                                          [--luacheck-baseline N]

Steps are read from the test folders (ADR adr-coreai-separation D09, E26), never from a hand-written list: every
tests/<folder>/test_<name>.py is the step <name>, folder by folder (coreai, radiosurvivor, livingknox, ensemble), files
in name order; two files with the same name in two folders stop the script. tests/commun holds the shared doubles,
harness, benches and fixtures: no step.

--mod radiosurvivor: tests/coreai and tests/radiosurvivor (luacheck reads batman_CoreAI and batman_RadioSurvivor
only). --mod livingknox: tests/coreai and tests/livingknox (luacheck: batman_CoreAI and batman_LivingKnox). Without
--mod: the whole repository, tests/ensemble included (tests of both mods together).

Runs, in order, and stops at the first failure (unless --keep-going):
    <name>             tests/<folder>/test_<name>.py, Python / lupa tests of the folders of the scope
    case               tools/check_case.py (case of every path of both mods against the vanilla media folder, LK13-T05);
                       SKIP (not PASS) when the vanilla media folder or the required mod batman_BeltRadio
                       (sibling repository Workshop/BeltRadio) is missing
    kahlua             tests/coreai/test_kahlua.py; SKIP (not PASS) when Java, projectzomboid.jar, stdlib.lua or ECJ is missing
    luacheck-contents  luacheck on Contents; FAIL if the warning count exceeds the baseline of tests/luacheck_baseline.txt
    luacheck-dev       luacheck on dev (development mod), same rule
    plan-check         tools/plan.py check

Paths are relative to this file: the script runs from any working directory. One line per step (PASS / FAIL /
SKIP and duration), then a summary; a failed step prints its command, exit code and last output lines.
--luacheck-baseline N overrides the Contents baseline for this run only (to check that the comparison fails).
Exit code: 0 when no step failed (skipped steps allowed), 1 otherwise. Standard library only.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests'
BASELINE_FILE = TESTS / 'luacheck_baseline.txt'
LUACHECK_CONFIG = ROOT / '.luacheckrc'
TAIL_LINES = 20

LUACHECK_STEPS = {'luacheck-contents': 'Contents', 'luacheck-dev': 'dev'}
# ADR adr-coreai-separation D09 (E26): one folder of tests per mod; a scope runs the folders of its mod and of the
# common mod, the whole repository (no --mod) also runs tests/ensemble (Radio Survivor and Living Knox together).
TEST_FOLDERS = ('coreai', 'radiosurvivor', 'livingknox', 'ensemble')
SCOPE_FOLDERS = {
    'radiosurvivor': ('coreai', 'radiosurvivor'),
    'livingknox': ('coreai', 'livingknox'),
    None: TEST_FOLDERS,
}
# Folders read by luacheck per scope (under Contents/mods and dev); None = the whole folder.
MOD_FOLDERS = {
    'radiosurvivor': {'Contents': ['mods/batman_CoreAI', 'mods/batman_RadioSurvivor'],
                      'dev': ['batman_CoreAITests', 'batman_RadioSurvivorTests']},
    'livingknox': {'Contents': ['mods/batman_CoreAI', 'mods/batman_LivingKnox'],
                   'dev': ['batman_CoreAITests', 'batman_LivingKnoxTests', 'batman_LivingKnoxTestClothes']},
}


def discover(folders=TEST_FOLDERS) -> dict[str, Path]:
    """Python steps read from the folders: step name (file name without test_) -> test file, folder by folder."""
    tests: dict[str, Path] = {}
    for folder in folders:
        for path in sorted((TESTS / folder).glob('test_*.py')):
            name = path.stem[len('test_'):]
            if name in tests:
                raise SystemExit(f'duplicate step name {name}: {tests[name]} and {path}')
            tests[name] = path
    return tests


PYTHON_TESTS = discover()
STEPS = list(PYTHON_TESTS) + ['case'] + list(LUACHECK_STEPS) + ['plan-check']


class Result:
    def __init__(self, name: str, status: str, seconds: float, detail: str = '', command: list[str] | None = None,
                 code: int | None = None, output: str = ''):
        self.name, self.status, self.seconds, self.detail = name, status, seconds, detail
        self.command, self.code, self.output = command, code, output


def run(command: list[str]) -> tuple[int, str]:
    env = dict(os.environ, PYTHONIOENCODING='utf-8')
    proc = subprocess.run(command, cwd=ROOT.parent, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          encoding='utf-8', errors='replace')
    return proc.returncode, proc.stdout or ''


def kahlua_missing() -> str | None:
    """Missing prerequisite of tests/coreai/test_kahlua.py, read from the test module itself (same paths, same env vars)."""
    spec = importlib.util.spec_from_file_location('rs_test_kahlua', PYTHON_TESTS['kahlua'])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.missing_prerequisites()


def read_baselines() -> dict[str, int]:
    baselines = {}
    for line in BASELINE_FILE.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        folder, count = line.split()
        baselines[folder] = int(count)
    return baselines


def step_python(name: str) -> Result:
    started = time.monotonic()
    if name == 'kahlua':
        missing = kahlua_missing()
        if missing:
            return Result(name, 'SKIP', time.monotonic() - started, 'prerequisite missing: ' + missing)
    command = [sys.executable, str(PYTHON_TESTS[name])]
    code, output = run(command)
    seconds = time.monotonic() - started
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    summary = lines[-1] if lines else ''
    ran = [i for i, line in enumerate(lines) if re.match(r'^Ran \d+ tests? in ', line)]
    if ran:  # unittest: "Ran N tests in Xs" then "OK" / "OK (skipped=N)" / "FAILED (...)"
        summary = ' '.join(lines[ran[-1]:ran[-1] + 2])
    status = 'PASS' if code == 0 else 'FAIL'
    if status == 'PASS' and name == 'kahlua' and 'skipped=' in summary:
        status = 'SKIP'  # skipped inside the test file: never reported as a success
    # Every test skipped (prerequisite missing, e.g. the Belt Walkie-Talkie library next to this repository):
    # SKIP, never PASS. unittest: "Ran N tests" and "skipped=N"; test_protocol.py: "SKIP" lines and no "OK" line.
    ran_count = re.search(r'Ran (\d+) tests?', summary)
    skipped_count = re.search(r'skipped=(\d+)', summary)
    if status == 'PASS' and ran_count and skipped_count and ran_count.group(1) == skipped_count.group(1) != '0':
        status = 'SKIP'
    if status == 'PASS' and any(line.startswith('SKIP') for line in lines) \
            and not any(line.startswith('OK ') for line in lines):
        status = 'SKIP'
        summary = next(line for line in lines if line.startswith('SKIP'))
    return Result(name, status, seconds, summary, command, code, output)


def step_luacheck(name: str, baselines: dict[str, int], override: int | None, mod: str | None = None) -> Result:
    started = time.monotonic()
    folder = LUACHECK_STEPS[name]
    exe = shutil.which('luacheck')
    if exe is None:
        return Result(name, 'FAIL', time.monotonic() - started, 'luacheck not found on PATH')
    limit = override if (override is not None and folder == 'Contents') else baselines.get(folder)
    if limit is None:
        return Result(name, 'FAIL', time.monotonic() - started, f'no baseline for {folder} in {BASELINE_FILE.name}')
    parts = MOD_FOLDERS[mod][folder] if mod else None
    paths = [str(ROOT / folder / part) for part in parts if (ROOT / folder / part).is_dir()] if parts else [str(ROOT / folder)]
    command = [exe, *paths, '--config', str(LUACHECK_CONFIG)]
    code, output = run(command)
    seconds = time.monotonic() - started
    match = re.search(r'Total: (\d+) warnings? / (\d+) errors?', output)
    if not match:
        return Result(name, 'FAIL', seconds, 'no luacheck total in the output', command, code, output)
    warnings, errors = int(match.group(1)), int(match.group(2))
    # Keep only the warning / error lines and the total for the failure report (not the "Checking ... OK" lines).
    output = '\n'.join(line.strip() for line in output.splitlines()
                        if re.search(r': \([WE]\d+\)|^Total:', line.strip()))
    detail = f'{warnings} warning(s), {errors} error(s), baseline {limit}'
    if errors > 0 or code > 1:
        return Result(name, 'FAIL', seconds, detail + ': luacheck errors', command, code, output)
    if warnings > limit:
        return Result(name, 'FAIL', seconds, detail + ': more warnings than the baseline', command, code, output)
    if warnings < limit:
        detail += f' (below the baseline: lower it in tests/{BASELINE_FILE.name})'
    return Result(name, 'PASS', seconds, detail, command, code, output)


def step_plan() -> Result:
    started = time.monotonic()
    command = [sys.executable, str(ROOT / 'tools' / 'plan.py'), 'check']
    code, output = run(command)
    last = output.strip().splitlines()[-1] if output.strip() else ''
    return Result('plan-check', 'PASS' if code == 0 else 'FAIL', time.monotonic() - started, last, command, code,
                  output)


def step_case() -> Result:
    started = time.monotonic()
    spec = importlib.util.spec_from_file_location('rs_check_case', ROOT / 'tools' / 'check_case.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not module.DEFAULT_VANILLA.is_dir():
        return Result('case', 'SKIP', time.monotonic() - started,
                      f'prerequisite missing: vanilla media folder {module.DEFAULT_VANILLA}')
    if not module.BELT_MOD.is_dir():
        return Result('case', 'SKIP', time.monotonic() - started,
                      f'prerequisite missing: required mod batman_BeltRadio {module.BELT_MOD}')
    command = [sys.executable, str(ROOT / 'tools' / 'check_case.py')]
    code, output = run(command)
    last = output.strip().splitlines()[-1] if output.strip() else ''
    return Result('case', 'PASS' if code == 0 else 'FAIL', time.monotonic() - started, last, command, code, output)


def report_failure(result: Result) -> None:
    print(f'  step:    {result.name}')
    if result.command:
        print('  command: ' + ' '.join(result.command))
    if result.code is not None:
        print(f'  exit:    {result.code}')
    if result.detail:
        print(f'  detail:  {result.detail}')
    lines = result.output.rstrip().splitlines()
    if lines:
        print(f'  last {min(TAIL_LINES, len(lines))} output line(s):')
        for line in lines[-TAIL_LINES:]:
            print('    ' + line)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='RadioSurvivor repository checks.')
    parser.add_argument('--mod', choices=sorted(MOD_FOLDERS),
                        help='only the checks of this mod and the common mod (default: the whole repository)')
    parser.add_argument('--keep-going', action='store_true', help='run every step, then summarize')
    parser.add_argument('--only', action='append', choices=STEPS, metavar='NAME',
                        help='run only this step (repeatable): ' + ', '.join(STEPS))
    parser.add_argument('--luacheck-baseline', type=int, metavar='N',
                        help='override the Contents luacheck baseline for this run')
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    in_scope = set(discover(SCOPE_FOLDERS[args.mod]))
    selected = [s for s in STEPS if (s in in_scope or s not in PYTHON_TESTS) and (not args.only or s in args.only)]
    baselines = read_baselines()
    results: list[Result] = []
    stopped = False
    total_started = time.monotonic()
    for name in selected:
        if name in PYTHON_TESTS:
            result = step_python(name)
        elif name == 'case':
            result = step_case()
        elif name in LUACHECK_STEPS:
            result = step_luacheck(name, baselines, args.luacheck_baseline, args.mod)
        else:
            result = step_plan()
        results.append(result)
        line = f'{result.status:<4}  {result.name:<18} {result.seconds:6.1f} s'
        print(line + (f'  {result.detail}' if result.detail else ''), flush=True)
        if result.status == 'FAIL':
            report_failure(result)
            if not args.keep_going:
                stopped = True
                break

    failed = [r.name for r in results if r.status == 'FAIL']
    skipped = [r.name for r in results if r.status == 'SKIP']
    passed = [r.name for r in results if r.status == 'PASS']
    not_run = selected[len(results):]
    print(f'Summary: {len(passed)} passed, {len(failed)} failed, {len(skipped)} skipped'
          + (f', {len(not_run)} not run' if not_run else '')
          + f' ({time.monotonic() - total_started:.1f} s)')
    if failed:
        print('Failed: ' + ', '.join(failed))
    if skipped:
        print('Skipped: ' + ', '.join(skipped))
    if stopped and not_run:
        print('Not run (stopped at the first failure, use --keep-going): ' + ', '.join(not_run))
    print('RESULT: ' + ('FAIL' if failed else 'PASS'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
