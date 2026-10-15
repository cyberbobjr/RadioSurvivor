"""Zip de test local de Radio Survivor, sans le Workshop (pour un testeur qui installe les mods à la main).

    python RadioSurvivor/tools/make_test_zip.py            # écrit RadioSurvivor/dist/RadioSurvivor-<version>-test.zip
    python RadioSurvivor/tools/make_test_zip.py --list     # affiche le contenu sans rien écrire

Contenu (fichiers suivis par Git seulement, jamais de résultat de test ni de configuration locale) :
    LISEZMOI.md                        docs/LISEZMOI-test-local.md
    mods/batman_RadioSurvivor/         Contents/mods/batman_RadioSurvivor
    mods/batman_BeltRadio/             ../BeltRadio/Contents/mods/batman_BeltRadio      (mod requis)
    mods/batman_SignalSmoke/           ../SignalSmoke/Contents/mods/batman_SignalSmoke  (mod requis)
    bridge/                            bridge/*.py et bridge/.env.example (jamais bridge/.env)
    docs/installation-pont.md, docs/bridge-setup.md
TooltipLib (requis par Belt Walkie-Talkie) est un mod tiers : il n'est pas fourni, le testeur s'y abonne sur le Workshop.
Refus (code 1) si un fichier .env, un dossier runs/ ou un mod de développement entrerait dans le zip.
Bibliothèque standard seulement.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSHOP = ROOT.parent
MOD_INFO = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'mod.info'

# (dépôt Git, sous-dossier dans ce dépôt, dossier dans le zip)
SOURCES = [
    (ROOT, 'Contents/mods/batman_RadioSurvivor', 'mods/batman_RadioSurvivor'),
    (WORKSHOP / 'BeltRadio', 'Contents/mods/batman_BeltRadio', 'mods/batman_BeltRadio'),
    (WORKSHOP / 'SignalSmoke', 'Contents/mods/batman_SignalSmoke', 'mods/batman_SignalSmoke'),
]
SINGLE = [
    ('docs/LISEZMOI-test-local.md', 'LISEZMOI.md'),
    ('docs/installation-pont.md', 'docs/installation-pont.md'),
    ('docs/bridge-setup.md', 'docs/bridge-setup.md'),
    ('bridge/.env.example', 'bridge/.env.example'),
]
FORBIDDEN = re.compile(r'(^|/)(\.env|runs|dev|tests|__pycache__)(/|$)|\.pyc$')


def tracked(repo: Path, sub: str) -> list[str]:
    out = subprocess.run(['git', '-C', str(repo), 'ls-files', '--', sub], capture_output=True, text=True, check=True)
    return [line for line in out.stdout.splitlines() if line]


def version() -> str:
    m = re.search(r'^modversion=(\S+)', MOD_INFO.read_text(encoding='utf-8'), re.M)
    return m.group(1) if m else 'dev'


def entries() -> list[tuple[Path, str]]:
    files: list[tuple[Path, str]] = []
    for repo, sub, dest in SOURCES:
        names = tracked(repo, sub)
        if not names:
            sys.exit(f'nothing tracked in {repo / sub}')
        for name in names:
            files.append((repo / name, dest + name[len(sub):]))
    for name in tracked(ROOT, 'bridge'):
        if name.endswith('.py'):
            files.append((ROOT / name, name))
    for src, dest in SINGLE:
        path = ROOT / src
        if not path.is_file():
            sys.exit(f'missing {path}')
        files.append((path, dest))
    bad = [dest for _, dest in files if FORBIDDEN.search(dest) and not dest.endswith('.env.example')]
    if bad:
        sys.exit('refused, forbidden entries: ' + ', '.join(bad))
    return files


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--list', action='store_true', help='show the content, write nothing')
    args = parser.parse_args()
    files = entries()
    top = f'RadioSurvivor-{version()}-test'
    if args.list:
        for _, dest in files:
            print(f'{top}/{dest}')
        print(f'{len(files)} file(s)')
        return
    out = ROOT / 'dist' / f'{top}.zip'
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for src, dest in files:
            z.write(src, f'{top}/{dest}')
    print(f'{out} ({len(files)} files, {out.stat().st_size // 1024} KiB)')


if __name__ == '__main__':
    main()
