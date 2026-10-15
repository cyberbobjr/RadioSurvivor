"""Locate the Project Zomboid installation and the Steam Workshop folder of this machine.

Order: environment variables first, then the Steam libraries declared in libraryfolders.vdf (Steam folder from the
Windows registry or the standard locations), keeping the first library that holds ProjectZomboid.

    PZ_STEAM_LIBRARY  Steam library holding the game (folder that contains steamapps/)
    PZ_DIR            game folder (RS_PZ_DIR is also accepted)
    PZ_MEDIA          vanilla media folder

Nothing found: the returned paths do not exist, so the callers skip what needs the game.
Command line: python tools/pz_paths.py [--steam-library|--game|--media|--workshop]
"""
import os
import re
import sys
from functools import lru_cache
from pathlib import Path

GAME_SUBDIR = Path('steamapps') / 'common' / 'ProjectZomboid'
WORKSHOP_SUBDIR = Path('steamapps') / 'workshop' / 'content' / '108600'
MISSING = Path('<ProjectZomboid not found: set PZ_STEAM_LIBRARY>')


def _steam_roots():
    roots = []
    if sys.platform == 'win32':
        try:
            import winreg
            for hive, key, name in ((winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam', 'SteamPath'),
                                    (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath')):
                try:
                    with winreg.OpenKey(hive, key) as k:
                        roots.append(Path(winreg.QueryValueEx(k, name)[0]))
                except OSError:
                    pass
        except ImportError:
            pass
        for env in ('ProgramFiles(x86)', 'ProgramFiles'):
            if os.environ.get(env):
                roots.append(Path(os.environ[env]) / 'Steam')
    home = Path.home()
    roots += [home / '.steam' / 'steam', home / '.local' / 'share' / 'Steam',
              home / 'Library' / 'Application Support' / 'Steam']
    return roots


def _libraries():
    libraries = []
    for root in _steam_roots():
        libraries.append(root)
        vdf = root / 'steamapps' / 'libraryfolders.vdf'
        try:
            text = vdf.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for value in re.findall(r'"path"\s+"([^"]+)"', text):
            libraries.append(Path(value.replace('\\\\', '\\')))
    return libraries


@lru_cache(maxsize=None)
def steam_library():
    """Steam library that holds ProjectZomboid (MISSING when none)."""
    if os.environ.get('PZ_STEAM_LIBRARY'):
        return Path(os.environ['PZ_STEAM_LIBRARY'])
    for library in _libraries():
        if (library / GAME_SUBDIR).is_dir():
            return library
    return MISSING


def game_dir():
    value = os.environ.get('PZ_DIR') or os.environ.get('RS_PZ_DIR')
    return Path(value) if value else steam_library() / GAME_SUBDIR


def media_dir():
    value = os.environ.get('PZ_MEDIA')
    return Path(value) if value else game_dir() / 'media'


def workshop_dir():
    """Steam Workshop content folder of Project Zomboid (subscribed mods, read only)."""
    return steam_library() / WORKSHOP_SUBDIR


if __name__ == '__main__':
    choice = sys.argv[1] if len(sys.argv) > 1 else '--game'
    print({'--steam-library': steam_library, '--game': game_dir, '--media': media_dir,
           '--workshop': workshop_dir}[choice]())
