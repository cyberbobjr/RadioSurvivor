"""Site réel des campagnes rejoué au banc (E19-T08, ADR banc mimétique D05) : lecture de l'export produit en jeu par la
suite site.export (dev/.../RST/suites/RST_SiteExport.lua, format dans son en-tête) et chargement dans les doublures du
monde des bancs d'obstacles (tests/test_lk_obstacles.py : DOOR_DOUBLES, WINDOW_DOUBLES, LANE_DOUBLES, UNLOAD_DOUBLES).

L'export décrit un bâtiment du jeu : il reste local, jamais versionné. Recherche (find_export) :
    1. variable d'environnement RS_SITE_EXPORT ;
    2. %USERPROFILE%/Zomboid/Lua/batman_RadioSurvivor/tests/site-export.txt (suite jouée dans la partie de l'auteur) ;
    3. tests/fixtures/local/site-export.txt (copie locale, ignorée par git) ;
    4. le plus récent tools/autoclient/runs/*/site-export.txt (suite jouée par autoclient : le cache y est recopié).
available() dit si un export existe ; les bancs qui en dépendent sont sautés sinon.

    site = parse(text)                 enregistrements par sorte (registre KINDS : sorte -> champs typés)
    install(h, machines, site, radius) monde du banc : bâtiments, pièces, cases, murs, portes, fenêtres, clôtures,
                                       escaliers, conteneurs, lits ; cases hors export (et, avec radius, à plus de
                                       radius cases de tout joueur) déchargées : getGridSquare rend nil.
Les doublures propres au site (SITE_DOUBLES) : bâtiment et pièce lus par case comme le jeu (getBuildingDef par la
pièce, IsoGridSquare.java:7789-7816 ; getBuildingAt par la pièce, IsoMetaGrid.java:271-280 ; checkKeyId d'après les
deux côtés, IsoDoor.java:1885-1907), objets à conteneur et lits.
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent
ENV_VAR = 'RS_SITE_EXPORT'
FILE_NAME = 'site-export.txt'
LOCAL_FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'local' / FILE_NAME
RUNS_DIR = ROOT / 'tools' / 'autoclient' / 'runs'
GAME_TESTS_DIR = Path('Zomboid') / 'Lua' / 'batman_RadioSurvivor' / 'tests'


# ---------------------------------------------------------------- format

def _int(text: str) -> int:
    """Entier écrit par Kahlua (« 10650 », ou « 10650.0 » pour un double entier)."""
    try:
        return int(text)
    except ValueError:
        value = float(text)
        if not value.is_integer():
            raise
        return int(value)


def _word(text: str) -> str | None:
    return None if text == '-' else text


def _flags(text: str) -> frozenset[str]:
    return frozenset() if text == '-' else frozenset(text.split(','))


REST = object()   # dernier champ : reste de la ligne (version du jeu)


@dataclass(frozen=True)
class Kind:
    """Sorte d'enregistrement : nom et (champ, convertisseur) dans l'ordre de la ligne."""
    name: str
    fields: tuple[tuple[str, Callable[[str], object] | object], ...]


XYZE = (('x', _int), ('y', _int), ('z', _int), ('edge', str))
XYZ = XYZE[:3]

# Registre des sortes, dans l'ordre de chargement (bâtiments avant les cases qui les citent).
KINDS: dict[str, Kind] = {k.name: k for k in (
    Kind('H', XYZ + (('radius', _int), ('version', REST))),
    Kind('G', (('id', str), ('keyId', _int), ('x1', _int), ('y1', _int), ('x2', _int), ('y2', _int))),
    Kind('S', XYZ + (('building', _word), ('roomId', _word), ('room', _word), ('flags', _flags))),
    Kind('W', XYZE),
    Kind('D', XYZE + (('cls', str), ('keyId', _int), ('ddi', _int), ('gdi', _int), ('flags', _flags))),
    Kind('O', XYZE + (('cls', str), ('flags', _flags))),
    Kind('F', XYZE),
    Kind('C', XYZ + (('type', _word),)),
    Kind('B', XYZ + (('bedType', _word),)),
    Kind('T', XYZ),
)}


@dataclass
class Site:
    header: dict
    records: dict[str, list[dict]] = field(default_factory=dict)

    def of(self, kind: str) -> list[dict]:
        return self.records.get(kind, [])

    @property
    def origin(self) -> tuple[int, int, int]:
        return self.header['x'], self.header['y'], self.header['z']


def parse_line(line: str, number: int = 0) -> tuple[str, dict]:
    tokens = line.split()
    kind = KINDS.get(tokens[0])
    if kind is None:
        raise ValueError(f'site export line {number}: unknown record kind {tokens[0]!r}')
    values = tokens[1:]
    record = {}
    for i, (name, conv) in enumerate(kind.fields):
        if conv is REST:
            record[name] = ' '.join(values[i:])
            return kind.name, record
        if i >= len(values):
            raise ValueError(f'site export line {number}: {kind.name} record needs {len(kind.fields)} fields: {line!r}')
        try:
            record[name] = conv(values[i])
        except ValueError as exc:
            raise ValueError(f'site export line {number}: bad {name} {values[i]!r} ({exc})') from None
    if len(values) != len(kind.fields):
        raise ValueError(f'site export line {number}: {kind.name} record has {len(values)} fields, '
                         f'{len(kind.fields)} expected: {line!r}')
    return kind.name, record


def parse(text: str) -> Site:
    """Export -> Site. Lignes vides et commentaires (#) ignorés ; une seule ligne H, la première."""
    header = None
    records: dict[str, list[dict]] = {}
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        kind, record = parse_line(line, number)
        if kind == 'H':
            if header is not None:
                raise ValueError(f'site export line {number}: second header')
            header = record
            continue
        if header is None:
            raise ValueError(f'site export line {number}: record before the header')
        records.setdefault(kind, []).append(record)
    if header is None:
        raise ValueError('site export: no header line')
    return Site(header, records)


# ---------------------------------------------------------------- export file

def candidates(environ=None, home: Path | None = None, runs: Path = RUNS_DIR,
               fixture: Path = LOCAL_FIXTURE) -> list[Path]:
    """Emplacements possibles de l'export, dans l'ordre de recherche."""
    environ = os.environ if environ is None else environ
    out = []
    if environ.get(ENV_VAR):
        out.append(Path(environ[ENV_VAR]))
    if home is None:
        home = Path(environ['USERPROFILE']) if environ.get('USERPROFILE') else Path.home()
    out.append(home / GAME_TESTS_DIR / FILE_NAME)
    out.append(fixture)
    if runs.is_dir():
        out.extend(sorted(runs.glob(f'*/{FILE_NAME}'), key=lambda p: p.stat().st_mtime, reverse=True))
    return out


def find_export(**kwargs) -> Path | None:
    return next((p for p in candidates(**kwargs) if p.is_file()), None)


def available() -> bool:
    return find_export() is not None


def load_export(path: Path | None = None) -> Site:
    path = path or find_export()
    if path is None:
        raise FileNotFoundError('no site export (see tests/site_world.py)')
    return parse(path.read_text(encoding='ascii'))


# ---------------------------------------------------------------- bench world

# Après DOOR_DOUBLES, WINDOW_DOUBLES, LANE_DOUBLES et UNLOAD_DOUBLES (tests/test_lk_obstacles.py).
SITE_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
local Obj = C.IsoObject
SITE = { defs = {}, rooms = {}, buildings = {}, defAt = {}, exported = {}, radius = nil }
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local function edgeKey(r) return key(r.x, r.y, r.z) .. ',' .. r.edge end

-- Pièces et bâtiments (IsoRoom.java:58-66, 470 ; RoomDef.java:64-70, 202-212 ; IsoBuilding.java:119).
local RoomDef = H.class('RoomDef')
function RoomDef:getIDString() return self.id end
function RoomDef:getName() return self.name end
function RoomDef:getBuilding() return self.def end
local Building = H.class('IsoBuilding')
function Building:getDef() return self.def end
local Room = H.class('IsoRoom')
function Room:getName() return self.roomDef.name end
function Room:getRoomDef() return self.roomDef end
function Room:getBuilding() return self.building end

-- IsoGridSquare.java:7789-7816 : bâtiment de la case par sa pièce (dehors : nil).
function Sq:getBuildingDef()
    local r = rawget(self, 'room')
    return r ~= nil and r:getBuilding():getDef() or nil
end
-- IsoMetaGrid.java:271-280 : bâtiment par la pièce de la métagrille (case chargée ou non).
local grid = { getBuildingAt = function(_, x, y, z)
    H.num(x, 'getBuildingAt'); H.num(y, 'getBuildingAt'); H.num(z, 'getBuildingAt')
    return SITE.defAt[key(math.floor(x), math.floor(y), math.floor(z))]
end }
local baseWorld = getWorld
getWorld = function()
    local w = baseWorld and baseWorld() or {}
    w.getMetaGrid = function() return grid end
    return w
end
-- IsoDoor.java:1885-1907 : keyId propre, sinon celui du bâtiment quand un seul des deux côtés (case de la porte, case
-- opposée) est dans un bâtiment, ou forceLocked ; bâtiments lus par la pièce de chaque case.
function C.IsoDoor:checkKeyId()
    if (self.keyId or -1) ~= -1 then return self.keyId end
    local ox, oy = self.x, self.y
    if self.north then oy = oy - 1 else ox = ox - 1 end
    local sq, other = self.square, getCell():getGridSquare(ox, oy, self.z)
    if sq == nil or other == nil then return -1 end
    local a, b = sq:getBuildingDef(), other:getBuildingDef()
    if a == nil and b ~= nil then self.keyId = b:getKeyId() elseif a ~= nil and b == nil then self.keyId = a:getKeyId()
    elseif a ~= nil and self.props ~= nil and self.props.forceLocked then self.keyId = a:getKeyId() end
    if self.locked and not self.lockedByKey and (self.keyId or -1) ~= -1 then self.lockedByKey = true end
    return self.keyId or -1
end

-- Objets à sprite et conteneurs (IsoObject.java:1892, 4845-4855 ; PropertyContainer.java:162, 190).
IsoFlagType = IsoFlagType or {}
IsoFlagType.bed = IsoFlagType.bed or 'bed'
local Props = H.class('PropertyContainer')
function Props:has(flag) local v = rawget(self, flag) return v ~= nil and v ~= false end
function Props:get(name) return rawget(self, name) end
local Sprite = H.class('IsoSprite')
function Sprite:getProperties() return self.props end
function Obj:getSprite() return rawget(self, 'sprite') end
function Obj:getProperties() local s = rawget(self, 'sprite') return s ~= nil and s.props or nil end
function Obj:getContainerCount() return rawget(self, 'container') ~= nil and 1 or 0 end
function Obj:getContainerByIndex(i) if i == 0 then return rawget(self, 'container') end return nil end
C.ItemContainer.getType = function(self) return self.type end

-- Drapeaux de l'export -> champs des doublures.
local SQUARE_FIELDS = { blocked = 'blocked', solid = 'solid', solidtrans = 'solidTrans', nofloor = 'noFloor',
    tree = 'tree', bush = 'bush', water = 'water' }
local DOOR_FIELDS = { open = 'open', locked = 'locked', lockedByKey = 'lockedByKey', barricaded = 'barricaded',
    hoppable = 'hoppable', tall = 'tall', obstructed = 'obstructed', padlock = 'padlock' }
local WINDOW_FIELDS = { open = 'open', locked = 'locked', smashed = 'destroyed', barricaded = 'barricaded',
    permaLocked = 'permaLocked', invincible = 'invincible' }
local function fieldsOf(flags, map)
    local out = {}
    for name, f in pairs(map) do if flags[name] then out[f] = true end end
    return out
end
local function roomOf(r)
    if r.roomId == nil then return nil end
    local room = SITE.rooms[r.roomId]
    if room == nil then
        local def = SITE.defs[r.building]
        local b = SITE.buildings[r.building]
        if b == nil then b = setmetatable({ def = def }, Building); SITE.buildings[r.building] = b end
        room = setmetatable({ roomDef = setmetatable({ id = r.roomId, name = r.room, def = def }, RoomDef),
            building = b }, Room)
        SITE.rooms[r.roomId] = room
    end
    return room
end

-- Registre : sorte d'enregistrement -> pose dans le monde du banc.
SITE_APPLY = {
    G = function(r)
        SITE.defs[r.id] = setmetatable({ id = r.id, keyId = r.keyId, x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2 },
            C.BuildingDef)
    end,
    S = function(r)
        local sq = H.square(r.x, r.y, r.z)
        for name, f in pairs(SQUARE_FIELDS) do sq[f] = r.flags[name] == true end
        sq.outside = r.flags.outside == true
        sq.room = roomOf(r)
        local k = key(r.x, r.y, r.z)
        SITE.exported[k] = true
        SITE.defAt[k] = r.building and SITE.defs[r.building] or nil
    end,
    W = function(r) WALLS[edgeKey(r)] = true end,
    D = function(r)
        local f = fieldsOf(r.flags, DOOR_FIELDS)
        f.keyId = r.keyId
        if r.ddi ~= -1 then f.double = true end
        if r.gdi ~= -1 then f.garage = r.gdi end
        if r.flags.forceLocked then f.props = { forceLocked = true } end
        NEW_DOOR(r.x, r.y, r.z, r.edge, r.cls, f)
    end,
    O = function(r) NEW_WINDOW(r.x, r.y, r.z, r.edge, r.cls, fieldsOf(r.flags, WINDOW_FIELDS)) end,
    F = function(r) FENCES[edgeKey(r)] = true end,
    C = function(r) H.addObject(r.x, r.y, r.z).container = setmetatable({ type = r.type }, C.ItemContainer) end,
    B = function(r)
        local o = H.addObject(r.x, r.y, r.z)
        o.sprite = setmetatable({ props = setmetatable({ bed = true, BedType = r.bedType }, Props) }, Sprite)
    end,
    T = function(r)
        local k = r.x .. ',' .. r.y
        if STAIRS[k] == nil or STAIRS[k] > r.z + 1 then STAIRS[k] = r.z + 1 end
        H.square(r.x, r.y, r.z).stairs = true
    end,
}
function SITE_LOAD(kind, list)
    local f = SITE_APPLY[kind]
    if f == nil then error('site: no loader for record kind ' .. tostring(kind)) end
    for _, r in ipairs(list) do f(r) end
end

-- Zone chargée (UNLOAD_DOUBLES) : case exportée et, avec SITE.radius, à au plus radius cases (Chebyshev) d'un joueur.
function SITE.loaded(x, y, z)
    if not SITE.exported[key(x, y, z)] then return false end
    local r = SITE.radius
    if r == nil then return true end
    for _, p in pairs(H.players) do
        if math.abs(math.floor(p.x) - x) <= r and math.abs(math.floor(p.y) - y) <= r then return true end
    end
    return false
end
setmetatable(UNLOADED, { __index = function(_, k)
    local x, y, z = string.match(k, '^([^,]+),([^,]+),([^,]+)$')
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x == nil then return nil end
    return not SITE.loaded(math.floor(x), math.floor(y), math.floor(z))
end })
'''


def _lua_value(value):
    if isinstance(value, frozenset):
        return {name: True for name in value}
    return value


def install(h, machines, site: Site, radius: int | None = None) -> None:
    """Charge site dans le monde du banc de chaque machine (doublures des obstacles déjà chargées). radius : cases
    déchargées au-delà de radius cases de tout joueur (sinon : seules les cases hors export le sont)."""
    from test_lk_obstacles import UNLOAD_DOUBLES
    for m in machines:
        h.load(m, UNLOAD_DOUBLES)
        h.load(m, SITE_DOUBLES)
        machine = h.machine(m)
        for kind in KINDS:
            records = site.of(kind)
            if not records:
                continue
            machine.g.SITE_BATCH = machine.to_lua([{k: _lua_value(v) for k, v in r.items()} for r in records])
            h.load(m, f'SITE_LOAD("{kind}", SITE_BATCH); SITE_BATCH = nil')
        if radius is not None:
            h.load(m, f'SITE.radius = {int(radius)}')
