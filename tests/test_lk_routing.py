"""Tests hors jeu des modèles d'itinéraire de LK_Obstacles (LK16-T11, constat D-OBS-01) : registre
LivingKnox.Obstacles.Routing (un fichier par modèle) et gel des sorties du routage.

    python RadioSurvivor/tests/test_lk_routing.py

Gel (FROZEN) : empreintes sha256 relevées sur le code d'avant le registre des modèles. Pour chaque carte du banc
(portes ouvertes, fermées, verrouillées, blindées, barricadées, du foyer du PNJ ou d'un autre groupe ; fenêtres
ouvertes, fermées, verrouillées, barricadées, inamovibles, cadres, construites, au-dessus d'un comptoir ou d'une
chute ; clôtures basses et portails ; arbres et buissons), et pour chacun des sept modèles : coût et franchissement de
chaque bord porteur d'un élément (deux sens, avec et sans bâtiments de sortie), itinéraires (cases, franchissements,
cases développées, raison) entre plusieurs paires de cases, lignes dégagées, puis points de passage et relevé de
planDoorRoute. Banc : tests/test_lk_obstacles.py (doublures des portes, fenêtres, clôtures, murs).
"""
from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_obstacles import HOUSE, ObstacleBase  # noqa: E402

MODELS = ('zombie', 'zombie-door', 'npc', 'detour', 'exit', 'exit-loose', 'trapped')

# Empreintes par carte, relevées avant le registre des modèles (LK16-T11).
FROZEN = {
    'closed': 'b13b9e5f2c09b254d1b036e9e61701f9ed99e2bb64425787a856b1992265c92f',
    'open': 'b13b9e5f2c09b254d1b036e9e61701f9ed99e2bb64425787a856b1992265c92f',
    'locked-member': 'c63b18378eae28688efedbbe121dc58b35050df4fa3d7340b39296a724db0b89',
    'locked-stranger': '792376d56793abc79b8b7edd49457f2784f4f51a04487000552eff8ffcdedcac',
    'armoured-foreign': '59f1962e5d10d0e022df5c9982cd9ef717a67244a3db1e2b99811c34458103de',
    'foreign-open-window': 'a4ac8348283bf0d5d66e77e14c3df2e8a6af6df1c0ff2aa7bd873dcbca4ea023',
    'barricaded': '337478773aed05383bcc7f850ebbca30714fc2106b157e62277102c305ad799e',
    'frames': '44ac0207395e66ac825ff8920a36531d1eddd9398a606b74aee701e9f103ba85',
    'detour-rule': '5b391a1f6c43229cd8de177fae3e90f5c946e49b1fc4a4695d1413b8a229b03b',
}

PROBE = r'''
local O = LivingKnox.Obstacles
local function fmt(v)
    if type(v) == "number" then return string.format("%.4f", v) end
    return tostring(v)
end
local function routing()
    local R = O.Routing
    if R ~= nil and R.edgeCost ~= nil then return R.edgeCost, R.edgeElement end
    local ec, el
    for i = 1, 60 do
        local name, v = debug.getupvalue(O.findRoute, i)
        if name == nil then break end
        if name == "edgeCost" then ec = v elseif name == "edgeElement" then el = v end
    end
    return ec, el
end
-- Sorties du routage sur la boîte (x1, y1)-(x2, y2) au niveau 0 : bords, itinéraires (pairs : { sx, sy, tx, ty }),
-- lignes dégagées (lines : { ax, ay, bx, by }), plans (plans : { sx, sy, tx, ty }). keys : bâtiments de sortie.
function ROUTE_PROBE(models, x1, y1, x2, y2, pairs, lines, plans, keys)
    local EC, EL = routing()
    local cell, out = getCell(), {}
    for x = x1, x2 do
        for y = y1, y2 do
            for _, k in ipairs({ "W", "N" }) do
                local sqA = k == "W" and cell:getGridSquare(x - 1, y, 0) or cell:getGridSquare(x, y - 1, 0)
                local sqB = cell:getGridSquare(x, y, 0)
                if sqA ~= nil and sqB ~= nil then
                    local el = EL(sqA, sqB)
                    if el.kind ~= "plain" and el.kind ~= "wall" then
                        for _, m in ipairs(models) do
                            for _, from in ipairs({ sqA, sqB }) do
                                for _, ek in ipairs({ false, true }) do
                                    local c, what = EC(el, m, "lk-1", sqA, sqB, ek and keys or nil, from)
                                    out[#out + 1] = "E " .. x .. "," .. y .. k .. " " .. el.kind .. " " .. m .. " "
                                        .. (from == sqA and "a" or "b") .. tostring(ek) .. " " .. fmt(c) .. " "
                                        .. tostring(what)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, p in ipairs(pairs) do
        for _, m in ipairs(models) do
            local shared = { exitKeys = keys }
            local r, n, why = O.findRoute("lk-1", p[1] + 0.5, p[2] + 0.5, p[3], p[4], 0, m, shared)
            local s = {}
            for _, q in ipairs(r or {}) do s[#s + 1] = q.x .. "," .. q.y .. "," .. tostring(q.cross) end
            out[#out + 1] = "R " .. table.concat(p, ",") .. " " .. m .. " " .. tostring(n) .. " " .. tostring(why)
                .. " " .. tostring(shared.sawRefused) .. " " .. table.concat(s, ";")
        end
    end
    for _, l in ipairs(lines) do
        for _, m in ipairs({ "npc", "trapped" }) do
            out[#out + 1] = "L " .. table.concat(l, ",") .. " " .. m .. " "
                .. tostring(O.lineClear("lk-1", l[1], l[2], l[3], l[4], 0, nil, m ~= "npc" and m or nil))
        end
    end
    for _, p in ipairs(plans) do
        local w, info = O.planDoorRoute("lk-1", p[1] + 0.5, p[2] + 0.5, p[3], p[4], 0)
        local s = {}
        for _, q in ipairs(w) do s[#s + 1] = q.x .. "," .. q.y .. (q.t and "t" or "") end
        local ref = {}
        for _, r in ipairs(info.refused or {}) do ref[#ref + 1] = r.key .. ":" .. tostring(r.why) end
        local loose = {}
        for _, r in ipairs(info.loose or {}) do loose[#loose + 1] = r.key .. ":" .. tostring(r.why) end
        local edges = {}
        for _, e in ipairs(info.doorEdges or {}) do edges[#edges + 1] = e.key end
        for _, e in ipairs(info.climbEdges or {}) do edges[#edges + 1] = "c" .. e.key end
        out[#out + 1] = "P " .. table.concat(p, ",") .. " " .. table.concat(s, ";") .. " | " .. tostring(info.reason)
            .. " | " .. table.concat({ fmt(info.nodes), fmt(info.climbs), fmt(info.npcClimbs), fmt(info.doors),
                fmt(info.steps), fmt(info.extra), fmt(info.blind), tostring(info.unsafe), tostring(info.lastResort),
                tostring(info.exitUsed), tostring(info.noExitDoor), tostring(info.exit), fmt(info.exitClimbs) }, " ")
            .. " | " .. table.concat(ref, ";") .. " | " .. table.concat(loose, ";") .. " | " .. table.concat(edges, ";")
    end
    return table.concat(out, "\n")
end
'''

BOX = (98, 94, 116, 114)
PAIRS = [(109, 102, 100, 102), (100, 102, 110, 103), (108, 96, 108, 101), (104, 113, 108, 106),
         (109, 103, 104, 112), (110, 97, 110, 101), (102, 107, 109, 101)]
LINES = [(100.5, 102.5, 109.5, 102.5), (104.5, 102.5, 107.5, 102.5), (108.5, 106.5, 108.5, 111.5),
         (103.5, 104.5, 107.5, 104.5)]
PLANS = PAIRS


class RoutingFreezeBase(ObstacleBase):
    """Maison HOUSE (B1, x 106..111, y 100..104) fermée de murs : porte (106, 102) W, fenêtre (106, 104) W, fenêtre
    (108, 100) N au-dessus d'un comptoir (case 108,100), fenêtre (110, 100) N au-dessus d'une chute (case 110,99) ;
    clôture basse le long de y = 108 (bord N, x 100..115) percée d'un portail (108, 108) N ; arbre (103, 104), buisson
    (104, 106)."""
    mode = 'solo'

    def house(self, door=None, window=None, north='window', gate=None, members=None):
        b = HOUSE
        keys = [f"{b['x1']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{b['x2']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{x},{b['y1']},0,N" for x in range(b['x1'], b['x2'])]
        keys += [f"{x},{b['y2']},0,N" for x in range(b['x1'], b['x2'])]
        skip = {'106,102,0,W', '106,104,0,W', '108,100,0,N', '110,100,0,N'}
        self.run_lua('; '.join(f'WALLS["{k}"] = true' for k in keys if k not in skip))
        self.building(b)
        self.door(**(door or {}))
        self.window(y=104, **(window or {}))
        self.window(cls=north, x=108, y=100, kind='N')
        self.window(x=110, y=100, kind='N', open=True)
        self.run_lua('local s = getCell():getGridSquare(108, 100, 0) s.blocked = true s.solidTrans = true')
        self.run_lua('getCell():getGridSquare(110, 99, 0).noFloor = true')
        self.run_lua('; '.join(f'FENCES["{x},108,0,N"] = true' for x in range(100, 116) if x != 108))
        self.door(x=108, y=108, kind='N', hoppable=True, **(gate or {}))
        self.run_lua('local s = getCell():getGridSquare(103, 104, 0) s.tree = true s.blocked = true')
        self.run_lua('getCell():getGridSquare(104, 106, 0).bush = true')
        self.init()
        if members is not None:
            self.group(member=members, home=(108, 102, 0), name='Home')
        self.spawn(x=109, y=102)

    def probe(self):
        self.h.load('solo', PROBE)
        models = '{ ' + ', '.join(f'"{m}"' for m in MODELS) + ' }'
        lua_pairs = '{ ' + ', '.join('{ %d, %d, %d, %d }' % p for p in PAIRS) + ' }'
        lua_lines = '{ ' + ', '.join('{ %s, %s, %s, %s }' % p for p in LINES) + ' }'
        lua_plans = '{ ' + ', '.join('{ %d, %d, %d, %d }' % p for p in PLANS) + ' }'
        return self.run_lua(f'return ROUTE_PROBE({models}, {BOX[0]}, {BOX[1]}, {BOX[2]}, {BOX[3]}, {lua_pairs}, '
                            f'{lua_lines}, {lua_plans}, {{ B1 = true }})')


# Cartes du gel : nom -> (arguments de house, réglages Lua avant le relevé).
MAPS = {
    'closed': ({}, ''),
    'open': ({'door': {'open': True}, 'window': {'open': True}}, ''),
    'locked-member': ({'door': {'locked': True}, 'window': {'locked': True}, 'members': True}, ''),
    'locked-stranger': ({'door': {'locked': True}, 'window': {'locked': True}}, ''),
    'armoured-foreign': ({'door': {'locked': True, 'props': '{ forceLocked = true }'},
                          'window': {'barricaded': True}, 'members': False}, ''),
    'foreign-open-window': ({'door': {'locked': True, 'props': '{ forceLocked = true }'},
                             'window': {'open': True}, 'members': False}, ''),
    'barricaded': ({'door': {'barricaded': True}, 'window': {'permaLocked': True}, 'gate': {'locked': True}}, ''),
    'frames': ({'door': {'open': True, 'barricaded': True}, 'window': {'cls': 'frame'}, 'north': 'built',
                'gate': {'open': True}}, ''),
    'detour-rule': ({'door': {'locked': True}, 'window': {'open': True}}, 'LivingKnox.Obstacles.DOORS_FIRST = false'),
}


class RoutingFreezeTests(RoutingFreezeBase):
    def test_routing_outputs_are_frozen(self):
        got = {}
        for name, (args, setup) in MAPS.items():
            self.tearDown()
            self.setUp()
            self.house(**args)
            if setup:
                self.run_lua(setup)
            out = self.probe()
            self.assertEqual(self.h.errors('solo'), [], name)
            self.assertGreater(out.count('\nE '), 100, name)
            got[name] = hashlib.sha256(out.encode('utf-8')).hexdigest()
        if not FROZEN:
            print('FROZEN = ' + repr(got))
        self.assertEqual(got, FROZEN)


class RouteModelRegistryTests(RoutingFreezeBase):
    """Modèles d'itinéraire inscrits (LivingKnox.Obstacles.Routing.registerModel), un fichier par modèle."""

    def route(self, model, a=(109, 103), b=(103, 104)):
        return self.run_lua(
            'local r, n, why = LivingKnox.Obstacles.findRoute("lk-1", %d + 0.5, %d + 0.5, %d, %d, 0, "%s") '
            'if r == nil then return "", why end local s = {} '
            'for _, p in ipairs(r) do s[#s + 1] = p.x .. "," .. p.y .. "," .. tostring(p.cross) end '
            'return table.concat(s, " "), why' % (a[0], a[1], b[0], b[1], model))

    def test_the_seven_models_are_registered(self):
        self.house()
        names = self.run_lua('local s = {} for _, m in ipairs(LivingKnox.Obstacles.Routing.list()) do '
                             's[#s + 1] = m.name end table.sort(s) return table.concat(s, " ")')
        self.assertEqual(names.split(), sorted(MODELS))

    def test_model_registered_by_the_bench_alone_is_used_by_the_search(self):
        # Modèle factice : fenêtres sans surcoût, portes et clôtures infranchissables. Porte ouverte (106, 102) W et
        # fenêtre ouverte (106, 104) W : le modèle "npc" passe par la porte, le modèle factice par la fenêtre.
        self.house(door={'open': True}, window={'open': True})
        self.assertIn('105,102,door', self.route('npc')[0])
        self.run_lua('LivingKnox.Obstacles.Routing.registerModel("bench-glass", { edgeCost = function(r) '
                     'if r.kind == "window" then return 0, "climb" end return nil end })')
        path, _ = self.route('bench-glass')
        self.assertIn('105,104,climb', path)
        self.assertNotIn('door', path)
        # Borne de recherche propre au modèle (maxNodes).
        self.run_lua('LivingKnox.Obstacles.Routing.registerModel("bench-short", { edgeCost = function() return 0 end, '
                     'maxNodes = function() return 3 end })')
        self.assertEqual(self.route('bench-short'), ('', 'more than 3 squares'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_unknown_model_and_bad_spec(self):
        self.house()
        self.assertEqual(self.route('nobody')[1], 'unknown route model nobody')
        err = self.run_lua('local ok, e = pcall(LivingKnox.Obstacles.Routing.registerModel, "bad", {}) '
                           'return tostring(ok) .. " " .. tostring(e)')
        self.assertIn('LivingKnox.Obstacles.Routing.registerModel: ', err)
        self.assertTrue(err.startswith('false'), err)


if __name__ == '__main__':
    unittest.main()
