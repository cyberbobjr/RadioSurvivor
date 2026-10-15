"""Tests hors jeu de LK06-T08 (zombies attirés par les PNJ : bruit, vue à travers une fenêtre ou une porte, coups à
l'ouverture) : server/LivingKnox/LK_Zombies.lua (attrait, pas, contact) et server/LivingKnox/LK_Combat.lua (ligne de
coup, attente derrière une vitre, tir qui casse la vitre).

    python RadioSurvivor/tests/test_lk_window_lure.py

Pile de test_lk_zombies.py (solo), complétée des doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et NE
PROUVENT PAS l'API réelle :
- une maison (rectangle HOUSE, pièce ROOM ; IsoGridSquare.getRoom nil dehors) dont le bord est fait de murs, sauf une
  fenêtre (IsoWindow : IsOpen, isDestroyed, isBarricaded, smashWindow ; rideau, planches) et une porte (ouverte,
  vitrée ou pleine) ; getWindowTo / isWindowBlockedTo du bord commun (IsoGridSquare.java:971-977, IsoWindow.isBlocked
  :1120-1122) ;
- LosUtil.lineClear calculé sur ce plan : mur, rideau fermé, barricade de 3 planches ou plus, porte pleine fermée =
  Blocked ; vitre (même fermée) = ClearThroughWindow ; porte vitrée fermée = ClearThroughClosedDoor ; porte ouverte =
  ClearThroughOpenDoor (IsoGridSquare.testVisionAdjacent :6423-6539, IsoWindow.TestVision :381-401,
  IsoDoor.TestVision :914-940, IsoBarricade.TestVision :326-347, IsoCurtain.TestVision :219-239) ; LOS_FORCE impose un
  résultat ;
- getWorldSoundManager():getHearingMultiplier(zombie) (WorldSoundManager.java:407-422 ; HEARING imposé) ;
- zombie vanilla qui suit un bruit (modèle d'IsoZombie.RespondToSound, getSoundAttract, collideWith et ThumpState,
  IsoZombie.java:1303-1420, 1040-1093, WorldSoundManager.java:254-277, ThumpState.java:121-199) : bruit d'une source
  zombie ignoré, attrait = volume x (1 - distance² / (rayon x ouïe)² x atténuation des pièces), marche vers le bruit
  le plus attirant (sans décalage aléatoire), coups sur la fenêtre ou la porte fermée qui barre le passage (vitre
  cassée après GLASS_HITS coups), passage par une ouverture libre, arrêt devant un mur (le chemin vanilla le
  contournerait).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import DEV_LUA, LUA, lua_list  # noqa: E402
from test_lk_combat import PISTOL, RangedBase  # noqa: E402
from test_lk_zombies import ZombieBase  # noqa: E402

Z = 'LivingKnox.Zombies'
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKWindowLure.lua'
MOD_FILES = [LUA / 'server/LivingKnox/LK_Zombies.lua', LUA / 'server/LivingKnox/LK_Combat.lua']

WINDOW_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
HOUSE = { x0 = 96, y0 = 96, x1 = 103, y1 = 108 }
ROOM = { name = 'livingroom' }
local function inHouse(x, y) return x >= HOUSE.x0 and x <= HOUSE.x1 and y >= HOUSE.y0 and y <= HOUSE.y1 end
function Sq:getRoom() if inHouse(self.x, self.y) then return ROOM end return nil end

local Win = H.class('IsoWindow', C.IsoObject)
function Win:IsOpen() return self.open == true end
function Win:isDestroyed() return self.destroyed == true end
function Win:isBarricaded() return (self.planks or 0) > 0 end
function Win:smashWindow(...)
    if select('#', ...) ~= 0 then error('No implementation found for smashWindow', 2) end
    if self.destroyed then return end
    self.destroyed = true
    SMASHED = SMASHED + 1
end
local Door = H.class('IsoDoor', C.IsoObject)
SMASHED = 0
EDGES = {}
local function key(ax, ay, bx, by)
    if ax > bx or (ax == bx and ay > by) then ax, ay, bx, by = bx, by, ax, ay end
    return ax .. ',' .. ay .. '|' .. bx .. ',' .. by
end
-- Fenêtre ou porte sur le bord commun de (ax, ay) et (bx, by), voisines orthogonales.
function WINDOW(ax, ay, bx, by, fields)
    local w = setmetatable(fields or {}, Win)
    w.square = H.square(ax, ay, 0)
    w.x, w.y, w.z = ax, ay, 0
    w.hits = 0
    EDGES[key(ax, ay, bx, by)] = { kind = 'window', o = w }
    return w
end
function DOOR(ax, ay, bx, by, fields)
    local d = setmetatable(fields or {}, Door)
    d.square = H.square(ax, ay, 0)
    d.hits = 0
    EDGES[key(ax, ay, bx, by)] = { kind = 'door', o = d }
    return d
end
local function edge(a, b) return EDGES[key(a.x, a.y, b.x, b.y)] end
function Sq:getWindowTo(other)
    local e = edge(self, other)
    return e ~= nil and e.kind == 'window' and e.o or nil
end
local function winBlocks(w) return (not w.destroyed and not w.open) or (w.planks or 0) > 0 end
function Sq:isWindowBlockedTo(other)
    local e = edge(self, other)
    return e ~= nil and e.kind == 'window' and winBlocks(e.o)
end

-- Vue au travers du bord de deux cases voisines orthogonales : nil (rien), ou le résultat nommé.
local function crossVision(ax, ay, bx, by)
    if inHouse(ax, ay) == inHouse(bx, by) then return nil end
    local e = EDGES[key(ax, ay, bx, by)]
    if e == nil then return 'Blocked' end
    local o = e.o
    if e.kind == 'window' then
        if o.curtain == 'closed' or (o.planks or 0) >= 3 then return 'Blocked' end
        return 'ClearThroughWindow'
    end
    if o.open then return 'ClearThroughOpenDoor' end
    if o.glazed then return 'ClearThroughClosedDoor' end
    return 'Blocked'
end
LOS_FORCE = nil
LOS_CALLS = 0
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, ignoreDoors)
    for _, v in ipairs({ x0, y0, z0, x1, y1, z1 }) do
        H.num(v, 'LosUtil.lineClear')
        if v ~= math.floor(v) then error('LosUtil.lineClear: int expected, got ' .. v, 2) end
    end
    if type(ignoreDoors) ~= 'boolean' then error('No implementation found for LosUtil.lineClear', 2) end
    LOS_CALLS = LOS_CALLS + 1
    local res = LOS_FORCE
    if res == nil then
        res = 'Clear'
        local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        local px, py = x0, y0
        for i = 1, n do
            local x = math.floor(x0 + (x1 - x0) * i / n + 0.5)
            local y = math.floor(y0 + (y1 - y0) * i / n + 0.5)
            for _, s in ipairs({ { px, py, x, py }, { x, py, x, y } }) do
                if s[1] ~= s[3] or s[2] ~= s[4] then
                    local r = crossVision(s[1], s[2], s[3], s[4])
                    if r == 'Blocked' then res = 'Blocked' break end
                    if r ~= nil and res == 'Clear' then res = r end
                end
            end
            if res == 'Blocked' then break end
            px, py = x, y
        end
    end
    return setmetatable({}, { __tostring = function() return res end })
end }

HEARING = 1
local WSM = {}
WSM.__index = WSM
function WSM:getHearingMultiplier(z)
    if getmetatable(z) ~= C.IsoZombie then error('No implementation found for getHearingMultiplier', 2) end
    return HEARING
end
getWorldSoundManager = function() return setmetatable({}, WSM) end

-- Bruits du monde vivants (16 mises à jour), relevés depuis addSound.
WSOUNDS = {}
local prevAdd = addSound
addSound = function(src, x, y, z, r, v)
    prevAdd(src, x, y, z, r, v)
    WSOUNDS[#WSOUNDS + 1] = { src = src, x = x, y = y, z = z, r = r, v = v, life = 16,
        zombie = src ~= nil and getmetatable(src) == C.IsoZombie }
end

-- Zombie vanilla qui suit un bruit (voir l'en-tête). MODEL_ON = false : immobiles.
MODEL_ON = true
GLASS_HITS = 4
THUMP_TICKS = 30
SPEED = 0.03
THUMPS, STOPPED, GOALS = {}, {}, {}
local function pen(sa, sb)
    local ra, rb = sa:getRoom(), sb:getRoom()
    if ra == rb then return 1 end
    if ra == nil or rb == nil then return 1.68 end
    return 1.2
end
local function attract(zb, s)
    if s.zombie or s.r <= 0 then return 0 end
    local dx, dy = zb.x - s.x, zb.y - s.y
    local rr = s.r * HEARING
    local delta = (dx * dx + dy * dy) / (rr * rr) * pen(H.square(s.x, s.y, 0), zb.square)
    if delta >= 1 then return 0 end
    return s.v * (1 - delta)
end
-- Passage par le bord (ax, ay) -> (bx, by) : "go", "thump" (objet frappé) ou "wall".
local function cross(zb, ax, ay, bx, by)
    if inHouse(ax, ay) == inHouse(bx, by) then return 'go' end
    local e = EDGES[key(ax, ay, bx, by)]
    if e == nil then return 'wall' end
    local o = e.o
    if e.kind == 'window' then
        if not winBlocks(o) then return 'go' end
    elseif o.open then
        return 'go'
    end
    return 'thump', o, e.kind
end
local function step(zb)
    local best, goal = 0, nil
    for _, s in ipairs(WSOUNDS) do
        local a = attract(zb, s)
        if a > best then best, goal = a, s end
    end
    if goal ~= nil then
        zb.goal = { x = goal.x + 0.5, y = goal.y + 0.5 }
        GOALS[zb.onlineID] = zb.goal
    end
    if zb.goal == nil or zb.stopped then return end
    local dx, dy = zb.goal.x - zb.x, zb.goal.y - zb.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.3 then zb.goal = nil return end
    local nx, ny = zb.x + dx / d * math.min(SPEED, d), zb.y + dy / d * math.min(SPEED, d)
    local ax, ay, bx, by = math.floor(zb.x), math.floor(zb.y), math.floor(nx), math.floor(ny)
    for _, s in ipairs({ { ax, ay, bx, ay }, { bx, ay, bx, by } }) do
        if s[1] ~= s[3] or s[2] ~= s[4] then
            local what, o, kind = cross(zb, s[1], s[2], s[3], s[4])
            if what == 'wall' then
                zb.stopped = true
                STOPPED[zb.onlineID] = true
                return
            end
            if what == 'thump' then
                zb.thumpTicks = (zb.thumpTicks or 0) + 1
                if zb.thumpTicks % THUMP_TICKS == 1 then
                    local k = kind .. ':' .. zb.onlineID
                    THUMPS[k] = (THUMPS[k] or 0) + 1
                    o.hits = o.hits + 1
                    if kind == 'window' and (o.planks or 0) == 0 and o.hits >= GLASS_HITS then o:smashWindow() end
                end
                return
            end
        end
    end
    H.place(zb, nx, ny, zb.z)
end
Events.OnTick.Add(function()
    local keep = {}
    for _, s in ipairs(WSOUNDS) do
        s.life = s.life - 1
        if s.life > 0 then keep[#keep + 1] = s end
    end
    if not MODEL_ON then WSOUNDS = keep return end
    for _, zb in ipairs(H.zombieList.items) do
        if LivingKnox.Zombies.isVanilla(zb) then step(zb) end
    end
    WSOUNDS = keep
end)
function THUMPS_OF(kind, zid) return THUMPS[kind .. ':' .. zid] or 0 end
'''


class WindowBase(ZombieBase, RangedBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', WINDOW_DOUBLES)
        return h

    def place_npc(self, x, y):
        self.npc_zid = self.npc()
        self.h.move_zombie(self.npc_zid, x, y)
        return self.npc_zid

    def zombie_at(self, zid, x, y):
        self.h.spawn_zombie(zid, x, y, 0)
        self.h.eval('solo', f'VANILLA({zid}, 2) ~= nil')
        return zid

    def seconds(self, s, until=None):
        for _ in range(int(s * 1000 / self.h.tick_ms)):
            self.h.tick(1)
            if until is not None and until():
                return True
        return False

    def noises(self):
        return lua_list(self.ev('NOISES'))

    def zxy(self, zid):
        zb = self.h.zombie('solo', zid)
        return zb.x, zb.y


class WindowLureTests(WindowBase):
    def window(self, **fields):
        """Fenêtre du mur est de la maison, entre (103, 102) dedans et (104, 102) dehors."""
        lua = ', '.join(f'{k} = {self.lua_value(v)}' for k, v in fields.items())
        self.run_lua(f'W = WINDOW(103, 102, 104, 102, {{ {lua} }})')

    @staticmethod
    def lua_value(v):
        if isinstance(v, bool):
            return 'true' if v else 'false'
        if isinstance(v, str):
            return f'"{v}"'
        return str(v)

    def test_zombie_outside_comes_to_a_bare_window_and_thumps_it(self):
        self.window()
        self.place_npc(102.5, 102.5)
        zid = self.zombie_at(9001, 110.5, 102.5)
        self.run_lua('NOISES = {}')
        self.assertTrue(self.seconds(0.6, until=lambda: len(self.noises()) > 0))
        n = self.noises()[0]
        # Bruit d'attrait à la case du PNJ, source nil (une source zombie est ignorée par le moteur) ; rayon pour CE
        # zombie : 8,5 cases (de la case 102,102), dehors contre dedans x 1,68 -> ceil(8,5 x 1,296 x 1,25) + 1 = 15.
        self.assertEqual((n.x, n.y, n.r, n.v), (102, 102, 15, 20))
        self.assertIs(self.ev('NOISES[1].src == nil'), True)
        self.assertEqual(self.ev(f'{Z}.lureRadius(HARNESS.zombies[{zid}], LivingKnox.Bodies.find("lk-1"))'), 15)
        # Le zombie va vers le bruit, arrive à la fenêtre et la frappe ; il ne passe pas tant que la vitre tient.
        self.assertTrue(self.seconds(15, until=lambda: self.ev(f'THUMPS_OF("window", {zid})') >= 1))
        x, y = self.zxy(zid)
        self.assertGreaterEqual(x, 104)
        self.assertLess(x, 105)
        self.assertEqual(int(y), 102)
        self.assertEqual(self.zstat('attacks'), 0)
        # Vitre cassée par les coups : le zombie entre et vient au contact du PNJ.
        self.assertTrue(self.seconds(20, until=lambda: self.zstat('attacks') >= 1))
        self.assertEqual(self.ev('SMASHED'), 1)
        self.assertLess(self.zxy(zid)[0], 104)

    def test_closed_curtain_or_barricade_hides_the_npc(self):
        for fields in ({'curtain': 'closed'}, {'planks': 3}):
            with self.subTest(fields=fields):
                self.tearDown()
                self.setUp()
                self.window(**fields)
                self.place_npc(102.5, 102.5)
                zid = self.zombie_at(9002, 110.5, 102.5)
                self.run_lua('NOISES = {}')
                self.seconds(8)
                self.assertEqual(self.noises(), [])
                self.assertEqual(self.zstat('lures'), 0)
                self.assertEqual(self.zxy(zid), (110.5, 102.5))
                self.assertEqual(self.ev(f'THUMPS_OF("window", {zid})'), 0)
                self.assertIsNone(self.ev(f'{Z}.targetFor("lk-1")'))

    def test_two_planks_still_let_the_zombie_see_like_vanilla(self):
        # IsoBarricade.TestVision : moins de 3 planches et pas de tôle = aucun effet sur la vue (vanilla).
        self.window(planks=2)
        self.place_npc(102.5, 102.5)
        zid = self.zombie_at(9003, 110.5, 102.5)
        self.assertTrue(self.seconds(15, until=lambda: self.ev(f'THUMPS_OF("window", {zid})') >= 1))
        self.assertEqual(self.ev('SMASHED'), 0)            # planches : la vitre n'est pas atteinte (modèle)

    def test_glazed_door_seen_and_thumped_solid_door_hides(self):
        self.run_lua('D = DOOR(103, 104, 104, 104, { glazed = true })')
        self.place_npc(102.5, 104.5)
        zid = self.zombie_at(9004, 109.5, 104.5)
        self.assertTrue(self.seconds(15, until=lambda: self.ev(f'THUMPS_OF("door", {zid})') >= 1))
        self.assertGreaterEqual(self.zstat('lures'), 1)
        self.assertEqual(self.ev(f'{Z}.targetFor("lk-1").u'), f'z:{zid}')   # cible acquise à travers la vitre
        # Porte pleine fermée : rien.
        self.run_lua('D.glazed = false')
        self.h.move_zombie(zid, 109.5, 104.5)
        lures = self.zstat('lures')
        self.run_lua(f'HARNESS.zombies[{zid}].goal = nil')
        self.seconds(6)
        self.assertEqual(self.zstat('lures'), lures)
        self.assertIsNone(self.ev(f'{Z}.targetFor("lk-1")'))
        # Porte ouverte : vue.
        self.run_lua('D.open = true')
        self.seconds(4)
        self.assertGreater(self.zstat('lures'), lures)

    def test_a_noise_from_a_zombie_source_is_ignored_by_the_engine(self):
        # Cause du constat en jeu : l'ancien bruit d'attrait avait pour source le corps du PNJ (un zombie).
        self.run_lua('LOS_FORCE = "Blocked"')
        self.place_npc(90.5, 90.5)
        zid = self.zombie_at(9005, 96.5, 90.5)
        self.run_lua('addSound(LivingKnox.Bodies.find("lk-1"), 90, 90, 0, 20, 20)')
        self.seconds(1)
        self.assertIsNone(self.ev(f'GOALS[{zid}]'))
        self.run_lua('addSound(nil, 90, 90, 0, 20, 20)')
        self.seconds(0.2)
        self.assertEqual((self.ev(f'GOALS[{zid}].x'), self.ev(f'GOALS[{zid}].y')), (90.5, 90.5))

    def test_npc_footsteps_bring_a_nearby_zombie(self):
        self.run_lua('LOS_FORCE = "Blocked"')                 # aucun attrait par la vue : les pas seuls
        self.place_npc(86.5, 90.5)
        zid = self.zombie_at(9006, 92.5, 90.5)
        self.run_lua('NOISES = {}')
        self.seconds(2.5)                                     # immobile : aucun pas
        self.assertEqual(self.noises(), [])
        self.ev('LivingKnox.Anim.setGesture("lk-1", "walk") == nil')
        x = 86.5
        for _ in range(3):                                    # marche : un bruit par seconde au plus
            x += 0.5
            self.h.move_zombie(self.npc_zid, x, 90.5)
            self.seconds(1.0)
        rs = [(n.r, n.v) for n in self.noises()]
        self.assertGreaterEqual(len(rs), 2)
        self.assertLessEqual(len(rs), 3)
        self.assertEqual(set(rs), {(7, 7)})                   # ceil(0,5 x 1,4 x 10) dehors
        self.assertIs(self.ev('NOISES[1].src == nil'), True)
        self.assertGreaterEqual(self.zstat('steps'), 2)
        self.assertTrue(self.seconds(6, until=lambda: abs(self.zxy(zid)[0] - x) < 1.5))
        # Course dehors : 11 ; marche dans une pièce : moitié (3).
        self.run_lua('NOISES = {}')
        self.ev('LivingKnox.Anim.setGesture("lk-1", "run") == nil')
        self.h.move_zombie(self.npc_zid, x + 1, 90.5)
        self.seconds(1.1)
        self.assertEqual([(n.r) for n in self.noises()], [11])
        self.run_lua('NOISES = {}')
        self.ev('LivingKnox.Anim.setGesture("lk-1", "walk") == nil')
        self.h.move_zombie(self.npc_zid, 100.5, 100.5)
        self.seconds(1.1)
        self.assertEqual([(n.r) for n in self.noises()], [3])
        # Geste de repos : aucun pas même si le corps a bougé.
        self.run_lua('NOISES = {}')
        self.ev('LivingKnox.Anim.setGesture("lk-1", "idle") == nil')
        self.h.move_zombie(self.npc_zid, 101.5, 100.5)
        self.seconds(1.1)
        self.assertEqual(self.noises(), [])


class WindowCombatTests(WindowBase):
    def setUp(self):
        super().setUp()
        self.run_lua('MODEL_ON = false W = WINDOW(103, 102, 104, 102, {})')

    def test_melee_npc_waits_behind_the_glass_then_strikes_when_it_breaks(self):
        self.place_npc(103.5, 102.5)
        zid = self.zombie_at(9101, 104.4, 102.5)              # dehors, collé à la vitre (0,9 case)
        self.run_lua(f'HARNESS.zombies[{zid}].health = 100')   # survit aux coups le temps de l'essai
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'hold')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'guard')
        self.seconds(4)
        self.assertEqual(self.c('stats.applied'), 0)
        self.assertEqual(self.zstat('attacks'), 0)            # aucun coup de zombie à travers la vitre
        self.assertEqual(self.zstat('contacts'), 0)
        ok, res = self.ev('LivingKnox.Combat.lineOfStrike(LivingKnox.Bodies.find("lk-1"), '
                          f'HARNESS.zombies[{zid}])')
        self.assertEqual((ok, res), (False, 'ClosedWindow'))
        # Rapport forgé pendant l'attente : refusé.
        c = self.c('orders["lk-1"].c')
        self.assertFalse(self.ev(f'(LivingKnox.Combat.onHit(getPlayer(), {{ id = "lk-1", c = {c}, n = 0, '
                                 f'u = "z:{zid}", x = 0, y = 0, z = 0 }}))'))
        self.assertEqual(self.why('not striking'), 1)
        # Vitre cassée : frappe des deux côtés.
        self.run_lua('W:smashWindow()')
        self.seconds(0.5)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'strike')
        self.assertTrue(self.seconds(10, until=lambda: self.c('stats.applied') >= 1
                                     and self.zstat('attacks') >= 1))

    def test_open_window_allows_melee_and_glazed_door_does_not(self):
        self.run_lua('W.open = true')
        self.place_npc(103.5, 102.5)
        zid = self.zombie_at(9102, 104.4, 102.5)
        self.assertIs(self.ev(f'(LivingKnox.Combat.lineOfStrike(LivingKnox.Bodies.find("lk-1"), '
                              f'HARNESS.zombies[{zid}]))'), True)
        self.run_lua('W.open = false W.planks = 1')
        self.assertIs(self.ev(f'(LivingKnox.Combat.lineOfStrike(LivingKnox.Bodies.find("lk-1"), '
                              f'HARNESS.zombies[{zid}]))'), False)   # barricadée : jamais (isWindowBlockedTo)
        self.run_lua('D = DOOR(103, 104, 104, 104, { glazed = true })')
        self.h.move_zombie(zid, 104.4, 104.5)
        self.h.move_zombie(self.npc_zid, 103.5, 104.5)
        ok, res = self.ev(f'LivingKnox.Combat.lineOfStrike(LivingKnox.Bodies.find("lk-1"), HARNESS.zombies[{zid}])')
        self.assertEqual((ok, res), (False, 'ClearThroughClosedDoor'))
        self.assertIs(self.ev(f'LivingKnox.Combat.behindGlass(LivingKnox.Bodies.find("lk-1"), '
                              f'HARNESS.zombies[{zid}])'), True)

    def test_ranged_npc_shoots_through_the_glass_and_breaks_it(self):
        self.place_npc(102.5, 102.5)
        zid = self.zombie_at(9103, 108.5, 102.5)
        self.armed(PISTOL, mags=1)
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        self.assertTrue(self.seconds(9, until=lambda: self.c('stats.shots') >= 2))
        self.assertEqual(self.ev('SMASHED'), 1)               # une seule fois : la vitre reste cassée
        self.assertEqual(self.c('stats.windowsSmashed'), 1)
        self.assertEqual(self.why('no line of fire'), 0)
        self.assertTrue(any('shot through a closed window at 103,102,0: glass broken' in line for line in self.lk()))


class SuiteTests(WindowBase):
    def test_suite_lk_windowlure_passes_on_the_doubles(self):
        self.init()
        self.run_lua('W = WINDOW(103, 102, 104, 102, {}) '
                     'local Sq = HARNESS.classes.IsoGridSquare '
                     'function Sq:getSpecialObjects() '
                     '  if self.x == 103 and self.y == 102 then return HARNESS.list({ W }) end '
                     '  return HARNESS.list({}) end '
                     'function Sq:isFree() return true end '
                     'local Win = HARNESS.classes.IsoWindow '
                     'function Win:getOppositeSquare() return HARNESS.square(104, 102, 0) end '
                     'function Win:getNorth() return false end '
                     'local n = 9200 '
                     'addZombiesInOutfit = function(x, y, z) n = n + 1 '
                     '  local zb = HARNESS.spawnZombie(n, x + 0.5, y + 0.5, z, "server") zb.health = 2 '
                     '  return HARNESS.list({ zb }) end '
                     'local Zc = HARNESS.classes.IsoZombie '
                     'if Zc.removeFromSquare == nil then function Zc:removeFromSquare() end end '
                     'function Zc:getActionStateName() return (self.thumpTicks or 0) > 0 and "thump" or "idle" end')
        self.h.move_player('A', 100.5, 102.5)
        self.h.load('solo', 'shared/RST/suites/RST_LKWindowLure.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.windowlure", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.windowlure')
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.windowlure", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(12000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertTrue(report.ok, (results, self.h.logs('solo')[-40:]))
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKW] measure')]
        self.assertTrue(any('thumps' in line for line in measures), measures)


class SourceTests(unittest.TestCase):
    def test_sources_are_kahlua_compatible(self):
        for path in MOD_FILES + [SUITE]:
            text = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
            for bad in ('goto ', 'coroutine.', ' next(', 'string.format("%q'):
                self.assertNotIn(bad, code, f'{path.name}: {bad}')
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non-ASCII outside comments')

    def test_every_npc_noise_has_no_zombie_source(self):
        # Un bruit dont la source est un zombie (corps de PNJ) n'attire aucun zombie (WorldSoundManager.java:259-261).
        for rel in ('server/LivingKnox/LK_Zombies.lua', 'server/LivingKnox/LK_Combat.lua',
                    'server/LivingKnox/LK_Alert.lua'):
            text = (LUA / rel).read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
            for line in code.splitlines():
                if 'addSound(' in line and 'addSound(nil' not in line:
                    self.fail(f'{rel}: {line.strip()}')


if __name__ == '__main__':
    unittest.main()
