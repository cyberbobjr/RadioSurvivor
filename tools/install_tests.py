"""Copie le mod de développement batman_RadioSurvivorTests vers le dossier des mods locaux du jeu.

    python RadioSurvivor/tools/install_tests.py              # vers %USERPROFILE%\\Zomboid\\mods
    python RadioSurvivor/tools/install_tests.py --dry-run    # affiche seulement ce qui serait fait
    python RadioSurvivor/tools/install_tests.py --dest D:\\autre\\mods

Le mod n'est jamais publié. Une copie existante n'est remplacée que si elle porte le marqueur
`.rst-installed` posé par ce script ; sinon le script refuse (code 2) pour ne pas écraser un dossier
inconnu. Le dossier Workshop Steam (108600) est refusé comme destination.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD_ID = 'batman_RadioSurvivorTests'
SOURCE = ROOT / 'dev' / MOD_ID
MARKER = '.rst-installed'
IGNORE = shutil.ignore_patterns('__pycache__', '*.pyc', '*.bak', '*.tmp', 'Thumbs.db', 'desktop.ini', '.DS_Store')


def default_dest() -> Path:
    home = os.environ.get('USERPROFILE') or str(Path.home())
    return Path(home) / 'Zomboid' / 'mods'


def install(dest: Path, dry_run: bool = False, source: Path = SOURCE, out=print) -> int:
    if not (source / '42.21' / 'mod.info').is_file():
        out(f'ERREUR : source introuvable ou incomplète : {source}')
        return 1
    dest = Path(dest)
    parts = [p.lower() for p in dest.resolve().parts]
    if 'steamapps' in parts and '108600' in parts:
        out(f'ERREUR : destination refusée (Workshop Steam, lecture seule) : {dest}')
        return 2
    target = dest / MOD_ID
    if target.exists():
        if not (target / MARKER).is_file():
            out(f'ERREUR : {target} existe sans le marqueur {MARKER} : copie refusée '
                '(dossier non installé par ce script ; le déplacer ou le supprimer à la main).')
            return 2
        out(f'{"[essai] " if dry_run else ""}remplacement de {target}')
        if not dry_run:
            shutil.rmtree(target)
    else:
        out(f'{"[essai] " if dry_run else ""}création de {target}')
    if dry_run:
        for path in sorted(source.rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                out(f'[essai] copie {path.relative_to(source)}')
        return 0
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, target, ignore=IGNORE)
    (target / MARKER).write_text(f'installed by tools/install_tests.py from {source}\n'
                                 f'{datetime.now().isoformat(timespec="seconds")}\n', encoding='utf-8')
    count = sum(1 for p in target.rglob('*') if p.is_file())
    out(f'installé : {target} ({count} fichiers, marqueur compris)')
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--dest', type=Path, default=None, help='dossier des mods locaux (défaut : %%USERPROFILE%%\\Zomboid\\mods)')
    parser.add_argument('--dry-run', action='store_true', help="n'écrit rien, affiche les opérations")
    args = parser.parse_args(argv)
    return install(args.dest or default_dest(), dry_run=args.dry_run)


if __name__ == '__main__':
    sys.exit(main())
