"""Tests hors jeu de la règle des places d'arrêt (LK18-T03, ADR adr-ceder-le-passage.md D04) :
server/LivingKnox/LK_StopPlace.lua et ses appelants (place au foyer LK_Materialize.placeFor, place à côté d'un
objet Routines.exec.placeBeside, postes du relevé Routines.survey : test_lk_routines.py).

    python tests/test_lk_stop_place.py

Banc tests/harness.py (Living Knox seul, solo). Doublures du Java 42.22 relevé :
- porte d'un bord commun (IsoGridSquare.getDoorTo, IsoGridSquare.java:3103-3112 : IsoDoor ou IsoThumpable porte,
  vue des deux cases du bord) ; bord fermé (isBlockedTo = mur, fenêtre ou porte fermée, :936-938) ;
- case impraticable (isFree(false) faux : sq.blocked, doublure du banc) ;
- bâtiment d'une case (getBuildingDef ; rectangle BUILDINGS, comme test_lk_materialize.py).
Elles NE PROUVENT PAS l'API réelle, seulement la règle : une case de porte, un seuil (case voisine d'un bord de
porte, d'un côté ou de l'autre) et un passage d'une case de large sont décalés à la case la plus proche qui convient ;
une case ordinaire est gardée.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

S = 'LivingKnox.StopPlace'

WORLD = r'''
local H = HARNESS
local C = H.classes
EDGES = {}
BUILDINGS = {}
local Door = H.class('IsoDoor', C.IsoObject)
function Door:IsOpen() return self.open == true end
local function key(a, b) return a.x .. "," .. a.y .. "|" .. b.x .. "," .. b.y end
-- Bord commun de deux cases voisines : "door", "openDoor" ou "wall".
function ADD_EDGE(x, y, x2, y2, kind)
    EDGES[x .. "," .. y .. "|" .. x2 .. "," .. y2] = kind
    EDGES[x2 .. "," .. y2 .. "|" .. x .. "," .. y] = kind
end
local function edgeOf(a, b)
    if b == nil or a.z ~= b.z then return nil end
    return EDGES[key(a, b)]
end
function C.IsoGridSquare:getDoorTo(nb)
    local k = edgeOf(self, nb)
    if k == "door" or k == "openDoor" then return setmetatable({ open = k == "openDoor" }, Door) end
    return nil
end
function C.IsoGridSquare:isBlockedTo(nb)
    local k = edgeOf(self, nb)
    return k == "wall" or k == "door"
end
local Def = H.class('BuildingDef')
function Def:getIDString() return tostring(self.id) end
function C.IsoGridSquare:getBuildingDef()
    for _, b in ipairs(BUILDINGS) do
        if self.x >= b[1] and self.x <= b[3] and self.y >= b[2] and self.y <= b[4] then
            return setmetatable({ id = b[5] }, Def)
        end
    end
    return nil
end
-- Plantes cultivées et feux de camp (IsoGridSquare.java:9713-9765, lus par Bodies.freeSquare) : aucun sur ce banc.
function C.IsoGridSquare:hasFarmingPlant() return false end
function C.IsoGridSquare:getCampfire() return nil end
function BLOCK(x, y) H.square(x, y, 0).blocked = true end
function SQ(x, y) return getCell():getGridSquare(x, y, 0) end
function FREE(sq) return sq:isFree(false) end
function XY(sq) if sq == nil then return nil end return sq:getX(), sq:getY() end
'''


class StopPlaceBase(unittest.TestCase):
    files = ('server/LivingKnox/LK_Bodies.lua', 'server/LivingKnox/LK_StopPlace.lua')

    def setUp(self):
        self.h = Harness(with_rs=False, mode='solo')
        self.h.load('solo', WORLD)
        for path in self.files:
            self.h.load('solo', path)

    def tearDown(self):
        self.h.close()

    def run_lua(self, code):
        return self.h.load('solo', code)

    def why(self, x, y):
        return self.run_lua(f'return {S}.blocksPassage(SQ({x}, {y}))')

    def nearest(self, x, y, radius=3, accept='FREE', rank=1):
        return self.run_lua(f'return XY({S}.nearest({x}, {y}, 0, {radius}, {accept}, {rank}))')


class RuleTests(StopPlaceBase):
    def test_ordinary_square_is_kept(self):
        self.assertIsNone(self.why(50, 50))
        self.assertEqual(self.nearest(50, 50), (50, 50))

    def test_door_square_and_both_thresholds_are_refused(self):
        ADD = 'ADD_EDGE(10, 10, 10, 11, "door")'   # porte sur le bord sud de 10,10
        self.run_lua(ADD)
        self.assertIsNotNone(self.why(10, 10))
        self.assertIsNotNone(self.why(10, 11))   # seuil de l'autre côté
        self.assertIsNone(self.why(9, 10))        # à côté du bord, pas dessus
        self.assertEqual(self.nearest(10, 10), (10, 9))   # vers l'intérieur, la plus proche
        self.assertEqual(self.nearest(10, 11), (9, 11))   # à côté du bord, pas dessus

    def test_open_door_and_gate_are_refused_too(self):
        self.run_lua('ADD_EDGE(20, 20, 21, 20, "openDoor")')
        self.assertIsNotNone(self.why(20, 20))
        self.assertIsNotNone(self.why(21, 20))

    def test_one_square_wide_passage_between_walls_is_refused(self):
        # Couloir nord-sud : murs à l'ouest et à l'est de 30,30.
        self.run_lua('ADD_EDGE(30, 30, 29, 30, "wall") ADD_EDGE(30, 30, 31, 30, "wall")')
        self.assertIsNotNone(self.why(30, 30))
        x, y = self.nearest(30, 30)
        self.assertNotEqual((x, y), (30, 30))
        self.assertIsNone(self.why(x, y))

    def test_one_square_wide_passage_between_furniture_is_refused(self):
        self.run_lua('BLOCK(40, 39) BLOCK(40, 41)')   # meubles au nord et au sud de 40,40
        self.assertIsNotNone(self.why(40, 40))
        self.assertIsNone(self.why(41, 40))
        self.assertEqual(self.nearest(40, 40), (39, 40))

    def test_square_against_one_wall_is_kept(self):
        self.run_lua('ADD_EDGE(60, 60, 60, 59, "wall") ADD_EDGE(60, 60, 59, 60, "wall")')   # coin
        self.assertIsNone(self.why(60, 60))

    def test_callers_criteria_are_kept_and_rank_counts_good_places(self):
        self.run_lua('ADD_EDGE(70, 70, 70, 71, "door")')
        # Critère de l'appelant : x pair seulement ; 70,70 est un seuil, 70,69 la plus proche qui convient.
        self.run_lua('function EVEN(sq) return sq:getX() % 2 == 0 and sq:isFree(false) end')
        self.assertEqual(self.nearest(70, 70, accept='EVEN'), (70, 69))
        self.assertEqual(self.nearest(70, 70, accept='EVEN', rank=2), (70, 68))

    def test_without_any_good_place_the_callers_choice_stays(self):
        # Tout le voisinage est un couloir : repli sur la case la plus proche qui satisfait l'appelant.
        self.run_lua('function ONLY(sq) return sq:getX() == 80 and sq:getY() == 80 end '
                     'ADD_EDGE(80, 80, 79, 80, "wall") ADD_EDGE(80, 80, 81, 80, "wall")')
        self.assertEqual(self.nearest(80, 80, accept='ONLY'), (80, 80))
        self.assertIsNone(self.run_lua(f'return {S}.nearest(80, 80, 0, 2, function() return false end, 1)'))


class CallerTests(StopPlaceBase):
    files = ('server/LivingKnox/LK_Bodies.lua', 'server/LivingKnox/LK_Materialize.lua',
             'server/LivingKnox/LK_RoutineExec.lua', 'server/LivingKnox/LK_Routines.lua')

    def test_home_place_is_not_a_threshold(self):
        # Foyer : bâtiment 100..110 ; case du foyer juste derrière la porte d'entrée (bord sud de 105,110).
        self.run_lua('BUILDINGS = { { 100, 100, 110, 110, 3 } } ADD_EDGE(105, 110, 105, 111, "door")')
        got = self.run_lua('return XY(LivingKnox.Materialize.placeFor({ x = 105, y = 110, z = 0 }, "3", 4))')
        self.assertEqual(got, (105, 109))
        # Foyer sur une case ordinaire : gardé.
        self.assertEqual(self.run_lua('return XY(LivingKnox.Materialize.placeFor({ x = 103, y = 103, z = 0 }, "3", 4))'),
                         (103, 103))

    def test_place_beside_an_object_avoids_a_corridor(self):
        # Objet en 120,120 ; la voisine nord (première essayée) est un couloir entre deux meubles : place à l'est.
        self.run_lua('BLOCK(119, 119) BLOCK(121, 119)')
        p = self.run_lua('local p = LivingKnox.Routines.exec.placeBeside(getCell(), 120, 120, 0, nil, {}) '
                         'return p.x, p.y')
        self.assertNotEqual(p, (120, 119))
        self.assertIsNone(self.why(*p))

    def test_place_beside_keeps_the_only_neighbour_left(self):
        # Seule voisine praticable : un seuil. Elle reste la place (la corvée doit se faire à côté de l'objet).
        self.run_lua('BLOCK(131, 130) BLOCK(129, 130) BLOCK(130, 131) ADD_EDGE(130, 129, 130, 128, "openDoor")')
        p = self.run_lua('local p = LivingKnox.Routines.exec.placeBeside(getCell(), 130, 130, 0, nil, {}) '
                         'return p.x, p.y')
        self.assertEqual(p, (130, 129))


if __name__ == '__main__':
    unittest.main(verbosity=2)
