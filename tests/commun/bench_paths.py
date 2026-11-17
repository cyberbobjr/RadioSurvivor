"""Folders of the offline tests (E26, ADR adr-coreai-separation D09).

tests/coreai, tests/radiosurvivor, tests/livingknox and tests/ensemble hold the tests of each mod; tests/commun holds
what several folders import (doubles, harness, benches, fixtures, Kahlua bench). A test starts with:

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))
    import bench_paths  # noqa: E402,F401

which puts tests/commun and tests/coreai on sys.path (every mod depends on the common mod), so the test runs as
`python tests/<folder>/test_x.py` from any working directory. A test of tests/ensemble also calls
bench_paths.use('radiosurvivor', 'livingknox'). A RadioSurvivor test never imports from tests/livingknox, nor the
reverse.
"""
from __future__ import annotations

import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parents[1]
ROOT = TESTS.parent
COMMUN = TESTS / 'commun'
FIXTURES = COMMUN / 'fixtures'
KAHLUA = COMMUN / 'kahlua'
MOD_FOLDERS = ('coreai', 'radiosurvivor', 'livingknox', 'ensemble')


def use(*folders: str) -> None:
    """Puts these folders of tests/ on sys.path (once each)."""
    for name in folders:
        path = str(TESTS / name)
        if path not in sys.path:
            sys.path.insert(1, path)


use('commun', 'coreai')
