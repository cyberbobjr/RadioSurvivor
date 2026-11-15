"""Loot list names of the installed game for the frequency note of the voice workshop ([note] loot= and glovebox=).

Read-only over the game's media/lua/server, used by gen_atelier_catalog.py. The mod looks the names up in the same
tables (RS_NotesServer.lua): loot= in ProceduralDistributions.list (Items/ProceduralDistributions.lua, one entry per
line `<tab>Name = {` at the first level of the table), glovebox= in VehicleDistributions (Vehicles/
VehicleDistributions.lua, `VehicleDistributions.<Name> = {`), of which only the glove box lists (name containing
GloveBox) are offered. Python 3 standard library only.
"""
from __future__ import annotations

import re
from pathlib import Path

PROCEDURAL = Path('lua/server/Items/ProceduralDistributions.lua')
VEHICLE = Path('lua/server/Vehicles/VehicleDistributions.lua')
PROCEDURAL_ENTRY = re.compile(r'^\t([A-Za-z0-9_]+) = \{', re.M)
VEHICLE_ENTRY = re.compile(r'^VehicleDistributions\.([A-Za-z0-9_]*GloveBox[A-Za-z0-9_]*) = \{', re.M)


def _names(path: Path, pattern: re.Pattern) -> list[str]:
    return sorted(set(pattern.findall(path.read_text(encoding='utf-8', errors='replace')))) if path.is_file() else []


def read_loot_lists(media: Path) -> dict[str, list[str]]:
    """{'loot': procedural list names, 'glovebox': glove box list names} of the game's `media` folder."""
    return {'loot': _names(media / PROCEDURAL, PROCEDURAL_ENTRY), 'glovebox': _names(media / VEHICLE, VEHICLE_ENTRY)}
