"""Campagne découpée en N tranches lancées en parallèle (autoclient.py --shard K/N), rapports fusionnés.

    python RadioSurvivor/tools/autoclient/campaign_parallel.py --shards 3 -- --mp --clients 2 --server-campaign mp \\
        --bridge on --llm fake --timeout 5400 --wait-idle 3600
    python RadioSurvivor/tools/autoclient/campaign_parallel.py --shards 2 -- --campaign solo-rs --timeout 1800

Tout ce qui suit « -- » est passé tel quel à autoclient.py, plus --shard K/N, --out <dossier>/shard<K> et
--max-parallel (au moins N). Chaque tranche prend un emplacement de lancement (sémaphore de autoclient.py), ses
propres caches, ports de serveur et dossier de résultats ; les tranches démarrent à --stagger secondes d'écart (pic de
chargement). Une campagne à phases (--phases, mp-persist) ne se découpe pas : refusée par autoclient.py.
Fusion : dossier tools/autoclient/runs/<date>-parallel-<N>/ avec shard<K>/ (résultats de la tranche), shard<K>.log
(sortie de autoclient.py) et summary.txt : totaux (somme des premières lignes RST-RESULT de chaque client qui rend un
résultat), lignes FAIL/ERROR des rapports RST, code de chaque tranche, chemins. Code de sortie : le pire des tranches.

Copie figée (--commit REF) : git worktree détaché de REF dans %TEMP%\rs-worktree-<hash> (jamais dans le dépôt ; -2,
-3... si le dossier existe), autoclient.py et mods de CETTE copie, résultats dans tools/autoclient/runs/ du dépôt
principal, puis « git worktree remove --force » de ce worktree seulement (jamais stash, checkout ni reset du dépôt
principal) : le travail en cours d'autres agents ne change pas les mods en jeu pendant la campagne.
    python RadioSurvivor/tools/autoclient/campaign_parallel.py --commit de2981e --shards 3 -- --mp --clients 2 \
        --server-campaign mp --bridge on --llm fake --timeout 5400 --wait-idle 3600
    python RadioSurvivor/tools/autoclient/campaign_parallel.py --commit HEAD -- --mp --clients 2 \
        --phases reconnect2,reconnect,restart --server-campaign mp-persist --timeout 3600 --wait-idle 3600
Sans --shards (avec --commit seulement) : un seul lancement de autoclient.py, tel quel (campagne à phases mp-persist
comprise), dossier <parent>/run. Variables passées à autoclient.py : RS_WORKSHOP_DIR (dossier Workshop réel : mods
frères BeltRadio, CharacterReputation, SignalSmoke), RS_AUTOCLIENT_RUNS (runs/ du dépôt principal : durées des
rapports pour --shard). Le pont de la copie n'a pas de fichier de configuration (ignoré par Git) : --llm fake, ou
OPENAI_* dans l'environnement pour un vrai modèle (avertissement sinon).
"""
from __future__ import annotations

import argparse
import os
import re
import tempfile
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUTOCLIENT = HERE / 'autoclient.py'
RUNS = HERE / 'runs'
REPO = HERE.parents[1]            # RadioSurvivor (git repository)
WORKSHOP = REPO.parent            # real Workshop folder: sister mods of the campaigns
WORKTREE_PREFIX = 'rs-worktree-'
COUNTERS = ('total', 'pass', 'fail', 'error', 'skip')


def log(message: str) -> None:
    print(time.strftime('%H:%M:%S') + ' ' + message, flush=True)


def shard_command(python: str, passthrough: list[str], k: int, n: int, out: Path, max_parallel: int,
                  autoclient: Path = AUTOCLIENT) -> list[str]:
    for bad in ('--shard', '--out', '--phases'):
        if any(a == bad or a.startswith(bad + '=') for a in passthrough):
            raise ValueError(f'{bad} is set by campaign_parallel.py (or not splittable): remove it')
    if not any(a.split('=', 1)[0] in ('--campaign', '--server-campaign') for a in passthrough):
        raise ValueError('a campaign to split is needed (--campaign or --server-campaign)')
    rest = list(passthrough)
    if not any(a == '--max-parallel' or a.startswith('--max-parallel=') for a in rest):
        rest += ['--max-parallel', str(max_parallel)]
    return [python, '-u', str(autoclient)] + rest + ['--shard', f'{k}/{n}', '--out', str(out)]


def single_command(python: str, passthrough: list[str], out: Path, autoclient: Path) -> list[str]:
    """One autoclient.py launch from the frozen copy, passthrough as given (phases allowed), results in out."""
    for bad in ('--shard', '--out'):
        if any(a == bad or a.startswith(bad + '=') for a in passthrough):
            raise ValueError(f'{bad} is set by campaign_parallel.py: remove it')
    return [python, '-u', str(autoclient)] + list(passthrough) + ['--out', str(out)]


# ---------------------------------------------------------------- frozen copy (--commit)

def git(*args: str, repo: Path = REPO) -> subprocess.CompletedProcess:
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True, encoding='utf-8',
                          errors='replace')


def resolve_commit(ref: str, repo: Path = REPO) -> str:
    """Full hash of ref; ValueError when it names no commit."""
    if not ref or ref.startswith('-'):
        raise ValueError(f'bad --commit {ref!r}')
    r = git('rev-parse', '--verify', '--quiet', ref + '^{commit}', repo=repo)
    if r.returncode != 0 or not r.stdout.strip():
        raise ValueError(f'--commit {ref!r}: no such commit in {repo}')
    return r.stdout.strip()


def worktree_dir(sha: str, base: Path | None = None) -> Path:
    """%TEMP%\\rs-worktree-<12 first characters of the hash>, -2, -3... when taken (another launch on the same commit)."""
    base = Path(tempfile.gettempdir()) if base is None else base
    first = base / f'{WORKTREE_PREFIX}{sha[:12]}'
    path, n = first, 2
    while path.exists():
        path, n = base / f'{first.name}-{n}', n + 1
    return path


def add_worktree(sha: str, path: Path, repo: Path = REPO) -> None:
    """Detached worktree of sha at path (outside the repository); RuntimeError with git's message otherwise."""
    if path.resolve().is_relative_to(repo.resolve()):
        raise RuntimeError(f'worktree {path} inside the repository: refused')
    r = git('worktree', 'add', '--detach', str(path), sha, repo=repo)
    if r.returncode != 0:
        raise RuntimeError('git worktree add failed: ' + (r.stderr or r.stdout).strip())


def remove_worktree(path: Path, repo: Path = REPO) -> str:
    """git worktree remove --force of THIS worktree only (never prune, stash, checkout nor reset)."""
    if not path.name.startswith(WORKTREE_PREFIX):
        return f'not removed: {path} is not a worktree of this tool'
    r = git('worktree', 'remove', '--force', str(path), repo=repo)
    if r.returncode != 0:
        return f'WARNING: git worktree remove {path} failed: ' + (r.stderr or r.stdout).strip()
    return f'worktree {path} removed'


def copy_supported(autoclient: Path) -> bool:
    """True when the autoclient.py of the copy reads RS_WORKSHOP_DIR (commits before this option resolve the sister
    mods next to the copy, in %TEMP%: refused)."""
    try:
        return 'RS_WORKSHOP_DIR' in autoclient.read_text(encoding='utf-8')
    except OSError:
        return False


def copy_env(workshop: Path = WORKSHOP, runs: Path = RUNS) -> dict[str, str]:
    """Variables of autoclient.py launched from a frozen copy: real Workshop folder, runs/ of the main repository."""
    return dict(os.environ, RS_WORKSHOP_DIR=str(workshop), RS_AUTOCLIENT_RUNS=str(runs))


def real_model_warning(passthrough: list[str]) -> str | None:
    """Warning when the frozen copy may start the bridge with a real model and no OPENAI_KEY in the environment."""
    def value(name):
        for i, a in enumerate(passthrough):
            if a == name and i + 1 < len(passthrough):
                return passthrough[i + 1]
            if a.startswith(name + '='):
                return a.split('=', 1)[1]
        return None
    if value('--llm') == 'fake' or value('--bridge') in ('off', 'offline') or os.environ.get('OPENAI_KEY'):
        return None
    return ('if the bridge starts: the bridge of the frozen copy has no configuration file (git-ignored), a real '
            'model needs OPENAI_* in '
            'the environment; use --llm fake otherwise')


def parse_result_line(line: str) -> dict[str, int] | None:
    if not line.startswith('RST-RESULT '):
        return None
    values = dict(re.findall(r'(\w+)=(\d+)', line))
    return {k: int(values.get(k, 0)) for k in COUNTERS}


def result_files(shard_dir: Path) -> list[Path]:
    """autoclient-result.txt of the shard: solo (in the folder) or one per MP client (client<N>/)."""
    files = [shard_dir / 'autoclient-result.txt'] + sorted(shard_dir.glob('client*/autoclient-result.txt'))
    return [f for f in files if f.exists()]


def report_failures(shard_dir: Path) -> list[str]:
    """FAIL / ERROR lines of the RST reports of the shard (server and clients), with the report name."""
    out = []
    for path in sorted(shard_dir.rglob('*.txt')):
        try:
            text = path.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        if not text.startswith('RST report'):
            continue
        for line in text.splitlines():
            if re.match(r'^(FAIL|ERROR)\s', line):
                out.append(f'{path.relative_to(shard_dir.parent)}: {line.strip()}')
    return out


def merge(parent: Path, codes: dict[int, int], names: dict[int, str] | None = None,
          title: str | None = None) -> tuple[str, dict[str, int]]:
    """Summary of the shards (folders <parent>/shard<K>, or names[K]) and their totals."""
    totals = {k: 0 for k in COUNTERS}
    lines = [title or f'Parallel campaign, {len(codes)} shard(s), {parent}', '']
    failures = []
    for k in sorted(codes):
        name = (names or {}).get(k, f'shard{k}')
        shard_dir = parent / name
        firsts = []
        for f in result_files(shard_dir):
            text = f.read_text(encoding='utf-8', errors='replace').splitlines()
            counts = parse_result_line(text[0]) if text else None
            if counts:
                for key in COUNTERS:
                    totals[key] += counts[key]
                firsts.append(f'{f.relative_to(parent)}: {text[0]}')
        shown = f'shard {k}' if name == f'shard{k}' else name
        lines.append(f'{shown}: exit code {codes[k]}, log {parent / f"{name}.log"}')
        lines += ['    ' + x for x in firsts] or ['    no result file']
        failures += report_failures(shard_dir)
    lines += ['', 'TOTAL ' + ' '.join(f'{k}={totals[k]}' for k in COUNTERS), '']
    lines += [f'FAIL/ERROR lines ({len(failures)}):'] + ['  ' + f for f in failures]
    return '\n'.join(lines) + '\n', totals


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    passthrough = []
    if '--' in argv:
        i = argv.index('--')
        argv, passthrough = argv[:i], argv[i + 1:]
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument('--shards', type=int, help='number of shards launched in parallel (1..6); without it, --commit '
                                              'runs autoclient.py once (phases allowed)')
    p.add_argument('--stagger', type=int, default=20, help='seconds between two launches (default 20)')
    p.add_argument('--out', type=Path, help='parent folder (default tools/autoclient/runs/<date>-parallel-<N>)')
    p.add_argument('--commit', help='launch from a detached git worktree of this commit (%%TEMP%%\\rs-worktree-<hash>), '
                                    'removed at the end; results in runs/ of the main repository')
    p.add_argument('--dry-run', action='store_true', help='print the commands, launch nothing (no worktree created)')
    args = p.parse_args(argv)
    if args.shards is None and not args.commit:
        log('ERROR: --shards is needed (or --commit for a single launch)')
        return 2
    if args.shards is not None and not 1 <= args.shards <= 6:
        log('ERROR: --shards 1..6')
        return 2
    sha = None
    if args.commit:
        try:
            sha = resolve_commit(args.commit)
        except ValueError as e:
            log(f'ERROR: {e}')
            return 2
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    label = f'parallel-{args.shards}' if args.shards else 'run'
    parent = args.out or RUNS / (f'{stamp}-{label}' + (f'-{sha[:12]}' if sha else ''))
    wt = worktree_dir(sha) if sha else None
    autoclient = wt / 'tools' / 'autoclient' / 'autoclient.py' if wt else AUTOCLIENT
    names = {k: f'shard{k}' for k in range(1, (args.shards or 1) + 1)} if args.shards else {1: 'run'}
    try:
        if args.shards:
            cmds = {k: shard_command(sys.executable, passthrough, k, args.shards, parent / names[k], args.shards,
                                     autoclient) for k in names}
        else:
            cmds = {1: single_command(sys.executable, passthrough, parent / names[1], autoclient)}
    except ValueError as e:
        log(f'ERROR: {e}')
        return 2
    env = copy_env() if wt else None
    if wt:
        warning = real_model_warning(passthrough)
        if warning:
            log('WARNING: ' + warning)
    if args.dry_run:
        if wt:
            log(f'dry run, worktree: git -C {REPO} worktree add --detach {wt} {sha}')
            log(f'dry run, environment: RS_WORKSHOP_DIR={WORKSHOP} RS_AUTOCLIENT_RUNS={RUNS}')
        for k, cmd in cmds.items():
            log(f'dry run, {names[k]}: ' + subprocess.list2cmdline(cmd))
        return 0
    if wt:
        try:
            add_worktree(sha, wt)
        except RuntimeError as e:
            log(f'ERROR: {e}')
            return 2
        log(f'worktree {wt} at {sha[:12]} ({args.commit})')
        if not copy_supported(autoclient):
            log(f'ERROR: the autoclient.py of {args.commit} predates --commit (no RS_WORKSHOP_DIR: the sister mods '
                'would be searched in the temporary folder); use a later commit')
            log(remove_worktree(wt))
            return 2
    codes = {}
    try:
        parent.mkdir(parents=True, exist_ok=True)
        if sha:
            (parent / 'commit.txt').write_text(f'{sha}\n{args.commit}\n', encoding='utf-8')
        procs = {}
        for k, cmd in cmds.items():
            if procs:
                time.sleep(args.stagger)
            with open(parent / f'{names[k]}.log', 'wb') as out:
                procs[k] = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                            env=env)
            log(f'{names[k]} started (pid {procs[k].pid})')
        for k, proc in procs.items():
            codes[k] = proc.wait()
            log(f'{names[k]} ended, code {codes[k]}')
    finally:
        if wt:
            log(remove_worktree(wt))
    title = (f'Parallel campaign, {len(codes)} shard(s), {parent}' if args.shards else f'Single run, {parent}') \
        + (f' (commit {sha})' if sha else '')
    text, totals = merge(parent, codes, names, title)
    (parent / 'summary.txt').write_text(text, encoding='utf-8')
    print(text, end='')
    code = max(codes.values()) if codes else 2
    log(f'summary {parent / "summary.txt"}; RS_PARALLEL_EXIT={code}')
    return code


if __name__ == '__main__':
    sys.exit(main())
