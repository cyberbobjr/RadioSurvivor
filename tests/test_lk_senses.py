"""Tests hors jeu de la perception des PNJ Living Knox (LK05-T01) : shared/LivingKnox/LK_Senses.lua (calcul chez
l'exécutant, mémoire de l'autorité), envoi par LK_Executor.lua dans le rapport d'état de LK_Reports.lua.

    python RadioSurvivor/tests/test_lk_senses.py

Banc tests/harness.py. Doublures (SENSES_DOUBLES) : LosUtil.lineClear sur des murs, portes et fenêtres déclarés par
le test (même parcours de cases que J/iso/LosUtil.java:28-152, résultat nommé comme LosUtil.TestResults), niveau de
lumière d'une case (IsoGridSquare.getLightLevel), pièce d'une case, météo (ClimateManager), posture et allure d'un
joueur (isSneaking, isRunning, isSprinting, isPlayerMoving, getTorchStrength). Les doublures NE PROUVENT PAS l'API
réelle, seulement la logique : modèle, déterminisme, budget, transport et contrôles.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_reports import ReportBase, REPORT_DOUBLES, REPORTS, EXECUTOR  # noqa: E402
from test_lk_milestone import MilestoneBase  # noqa: E402

SENSES = 'shared/LivingKnox/LK_Senses.lua'
SUITE = 'shared/RST/suites/RST_LKSenses.lua'
CORE = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua')

SENSES_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local function enum(name) return setmetatable({ name = name }, { __tostring = function(s) return s.name end }) end
local TR = { Clear = enum('Clear'), ClearThroughOpenDoor = enum('ClearThroughOpenDoor'),
    ClearThroughWindow = enum('ClearThroughWindow'), Blocked = enum('Blocked'),
    ClearThroughClosedDoor = enum('ClearThroughClosedDoor') }
-- Bords : { axis = 'x' (bord entre at - 1 et at, lignes lo..hi) ou 'y', kind = 'wall' | 'closed' | 'open' | 'glass' }.
WALLS = {}
LOS_CALLS = 0
local function crosses(w, bx, by, ax, ay)
    if w.axis == 'x' then
        return math.min(ax, bx) < w.at and math.max(ax, bx) >= w.at
            and ((ay >= w.lo and ay <= w.hi) or (by >= w.lo and by <= w.hi))
    end
    return math.min(ay, by) < w.at and math.max(ay, by) >= w.at
        and ((ax >= w.lo and ax <= w.hi) or (bx >= w.lo and bx <= w.hi))
end
local function edge(bx, by, ax, ay)
    local res = 'Clear'
    for _, w in ipairs(WALLS) do
        if crosses(w, bx, by, ax, ay) then
            if w.kind == 'wall' or w.kind == 'closed' then return 'Blocked' end
            if w.kind == 'open' then res = 'ClearThroughOpenDoor' elseif w.kind == 'glass' then res = 'ClearThroughWindow' end
        end
    end
    return res
end
-- LosUtil.lineClear(cell, x0, y0, z0, x1, y1, z1, bIgnoreDoors) : parcours de l'axe principal (LosUtil.java:44-110).
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, ignoreDoors)
    for _, v in ipairs({ x0, y0, z0, x1, y1, z1 }) do
        H.num(v, 'LosUtil.lineClear')
        if v ~= math.floor(v) then error('LosUtil.lineClear: int expected, got ' .. v, 2) end
    end
    if type(ignoreDoors) ~= 'boolean' then error('No implementation found for LosUtil.lineClear', 2) end
    LOS_CALLS = LOS_CALLS + 1
    if z0 ~= z1 then return TR.Blocked end
    local test, bx, by = 'Clear', x0, y0
    local function visit(ax, ay)
        local r = edge(bx, by, ax, ay)
        if r == 'Blocked' then return true end
        if test == 'Clear' then test = r end
        bx, by = ax, ay
        return false
    end
    local dx, dy = x1 - x0, y1 - y0
    if math.abs(dx) > math.abs(dy) then
        local s = dx < 0 and -1 or 1
        local m, t, x = dy / dx * s, 0.5 + y0, x0
        while x ~= x1 do
            x = x + s; t = t + m
            if visit(x, math.floor(t)) then return TR.Blocked end
        end
    elseif dy ~= 0 then
        local s = dy < 0 and -1 or 1
        local m, t, y = dx / dy * s, 0.5 + x0, y0
        while y ~= y1 do
            y = y + s; t = t + m
            if visit(math.floor(t), y) then return TR.Blocked end
        end
    end
    return TR[test]
end }
-- Lumière : LIGHT["x,y,z"] ou LIGHT_DEFAULT ; pièces : ROOMS["x,y,z"] = nom (nil = dehors).
LIGHT, LIGHT_DEFAULT, ROOMS = {}, 1, {}
local rooms = {}
local Sq = C.IsoGridSquare
function Sq:getLightLevel(idx)
    H.num(idx, 'getLightLevel')
    local v = LIGHT[self.x .. ',' .. self.y .. ',' .. self.z]
    if v == nil then return LIGHT_DEFAULT end
    return v
end
function Sq:getRoom()
    local name = ROOMS[self.x .. ',' .. self.y .. ',' .. self.z]
    if name == nil then return nil end
    rooms[name] = rooms[name] or { name = name }
    return rooms[name]
end
CLIMATE = { fog = 0, rain = 0, day = 1, ambient = 1 }
local CM = H.class('ClimateManager')
function CM:getFogIntensity() return CLIMATE.fog end
function CM:getRainIntensity() return CLIMATE.rain end
function CM:getDayLightStrength() return CLIMATE.day end
function CM:getAmbient() return CLIMATE.ambient end
getClimateManager = function() return setmetatable({}, CM) end
local P = C.IsoPlayer
function P:isGhostMode() return self.ghost == true end
function P:isInvisible() return self.invisible == true end
function P:getTorchStrength() return self.torch or 0 end
function P:isSneaking() return self.sneaking == true end
function P:isSprinting() return self.sprinting == true end
function P:isRunning() return self.running == true end
function P:isPlayerMoving() return self.walking == true or self.running == true or self.sprinting == true end
local Z = C.IsoZombie
if rawget(Z, 'isCrawling') == nil then function Z:isCrawling() return self.crawling == true end end
if rawget(Z, 'getDirectionAngle') == nil then function Z:getDirectionAngle() return self.angle or 0 end end
-- addSound(source, x, y, z, radius, volume) (LuaManager.java:9239) : bruit du monde, OnWorldSound (WorldSoundManager.java:480).
addSound = function(src, x, y, z, r, v) H.trigger('OnWorldSound', x, y, z, r, v, src) end
function WALL(axis, at, lo, hi, kind) WALLS[#WALLS + 1] = { axis = axis, at = at, lo = lo, hi = hi, kind = kind or 'wall' } end
-- Résumé lisible et stable (comparaison de deux bancs).
function DUMP(sen)
    if sen == nil then return 'nil' end
    local parts = { 'v' .. sen.v, 'nz' .. sen.nz }
    for _, list in ipairs({ { 'p', sen.p }, { 'z', sen.z }, { 'n', sen.n } }) do
        for _, e in ipairs(list[2]) do
            parts[#parts + 1] = string.format('%s:%s:%s,%s,%s:%s:%s:%s:%s', list[1], tostring(e.u or e.o), tostring(e.x),
                tostring(e.y), tostring(e.z), tostring(e.a), tostring(e.s), tostring(e.h), tostring(e.r))
        end
    end
    return table.concat(parts, '|')
end
'''

# PNJ simulés directement (KNOWN = { [npcId] = zombie }) : modèle et passage de perception sans le reste du moteur.
UNIT_HELPERS = r'''
KNOWN = {}
function NPC(id, zid, x, y, angle)
    local zb = HARNESS.spawnZombie(zid, x, y, 0, 'solo')
    zb.angle = angle or 0
    KNOWN[id] = zb
    return zb
end
function SCAN() return LivingKnox.Senses.scan(KNOWN, getTimestampMs()) end
function ENTRY(id, u)
    local sen = LivingKnox.Senses.summary(id)
    if sen == nil then return nil end
    for _, e in ipairs(sen.p) do if e.u == u then return e end end
    return nil
end
'''


class UnitBase(unittest.TestCase):
    def setUp(self):
        self.h = self.make()

    def tearDown(self):
        self.h.close()

    def make(self):
        h = Harness(mode='solo', clients=('A',), debug=True)
        for path in CORE:
            h.load('solo', path)
        h.load('solo', SENSES_DOUBLES)
        h.load('solo', SENSES)
        h.load('solo', UNIT_HELPERS)
        return h

    def lua(self, code):
        return self.h.load('solo', code)

    def ev(self, expr):
        return self.h.eval('solo', expr)

    def player(self, **flags):
        p = self.h.player('solo', 'A')
        for k, v in flags.items():
            setattr(p, k, v)
        return p

    def scans(self, n, ms=200):
        for _ in range(n):
            self.h.advance_ms(ms)
            self.lua('SCAN()')

    def entry(self, npc='n1', user='A'):
        return self.ev(f'ENTRY("{npc}", "{user}")')

    def until_seen(self, npc='n1', limit=60, ms=200):
        """Nombre de passages jusqu'à la cible vue, ou None."""
        for i in range(1, limit + 1):
            self.scans(1, ms)
            e = self.entry(npc)
            if e is not None and e.s:
                return i
        return None


class ModelTests(UnitBase):
    def evaluate(self, npc='{ vigil = "rest", pose = "stand" }', **o):
        fields = {'kind': '"player"', 'd': 6, 'dz': 0, 'cos': 1, 'light': 1, 'motion': '"walk"', 'room': '"same"',
                  'los': '"Clear"'}
        fields.update({k: (f'"{v}"' if isinstance(v, str) and not v.startswith('"') else
                           ('true' if v is True else 'false' if v is False else v)) for k, v in o.items()})
        table = '{ ' + ', '.join(f'{k} = {v}' for k, v in fields.items()) + ' }'
        return self.ev(f'LivingKnox.Senses.evaluate({npc}, {table})')

    def test_documented_figures(self):
        S = 'LivingKnox.Senses'
        day = self.evaluate()
        self.assertAlmostEqual(day.r, 20.0)                      # jour, debout, marche, en face, repos
        self.assertAlmostEqual(self.evaluate(motion='still').r, 14.0)
        self.assertAlmostEqual(self.evaluate(sneak=True).r, 10.0)
        self.assertAlmostEqual(self.evaluate(light=0).r, 5.0)    # nuit sans lumière
        self.assertAlmostEqual(self.evaluate(light=0, torch=True).r, 18.5)
        self.assertAlmostEqual(self.evaluate(los='ClearThroughWindow').r, 16.0)
        self.assertEqual(self.evaluate(los='Blocked').r, 0)
        self.assertEqual(self.evaluate(cos=-1).r, 0)             # dans le dos
        self.assertAlmostEqual(self.evaluate(cos=-1, d=1).r, 12.0)   # contact : champ au moins 0,6
        self.assertAlmostEqual(self.evaluate(dz=1, los='Clear').r, 10.0)
        self.assertEqual(self.evaluate(npc='{ vigil = "sleep" }').r, 0)
        self.assertAlmostEqual(self.evaluate(npc='{ vigil = "guard" }').r, 26.0)
        self.assertAlmostEqual(self.evaluate(npc='{ vigil = "rest", pose = "floor" }').r, 10.0)
        self.assertAlmostEqual(self.evaluate(fog=1).r, 13.0)
        # Ouïe : rayon du bruit propre selon l'allure, murs (autre pièce / dehors), étages x3.
        self.assertEqual(self.evaluate(motion='still').hr, 0)
        self.assertAlmostEqual(self.evaluate(motion='run', room='outside', los='Blocked').hr, 10 / 1.68)
        self.assertAlmostEqual(self.evaluate(motion='walk', sneak=True).hr, 1.5)
        self.assertAlmostEqual(self.evaluate(noise=40, motion='still', room='other').hr, 40 / 1.2)
        self.assertAlmostEqual(self.ev(f'{S}.hearDistance({{ d = 4, dz = 1 }})'), 5.0)
        self.assertTrue(self.evaluate(motion='run', room='outside', los='Blocked', d=4).heard)
        self.assertFalse(self.evaluate(motion='run', room='outside', los='Blocked', d=4).sight)

    def test_same_inputs_same_result_for_the_pure_model(self):
        code = ('local o = { kind = "player", d = 7.3, dz = 0, cos = 0.8, light = 0.4, motion = "run", room = "other", '
                'los = "ClearThroughWindow", noise = 3, x = 1, y = 2, z = 0 }; local n = { vigil = "busy" }; '
                'local tr = { a = 0.2 }; local ev = LivingKnox.Senses.evaluate(n, o); '
                'LivingKnox.Senses.step(tr, ev, o, 0.37, 1000); '
                'return string.format("%.12f|%.12f|%s|%s|%.12f", ev.r, ev.hr, tostring(tr.s), tostring(tr.h), tr.a)')
        self.assertEqual(self.lua(code), self.lua(code))

    def test_awareness_rises_in_sight_and_decays_out_of_sight(self):
        S = 'LivingKnox.Senses'
        a = self.lua(f'local tr = {{}}; local o = {{ d = 10 }}; for i = 1, 3 do {S}.step(tr, {{ sight = true, r = 20 }}, o, '
                     f'0.2, i * 200) end; return tr.a')
        self.assertAlmostEqual(a, 3 * 0.2 * (0.25 + 2.0 * 0.5))
        s, a2 = self.lua(f'local tr = {{ a = 1 }}; {S}.step(tr, nil, nil, 2, 0); return tr.s, tr.a')
        self.assertFalse(s)
        self.assertAlmostEqual(a2, 0.75)                          # pas borné à MAX_DT = 1 s


class ScanTests(UnitBase):
    def setUp(self):
        super().setUp()
        self.lua('NPC("n1", 9001, 106.5, 100.5, 180)')           # regarde vers l'ouest (x décroissants)
        self.h.move_player('A', 100.5, 100.5, 0)                  # 6 cases devant lui

    def test_player_in_the_open_seen_quickly(self):
        self.player(walking=True)
        n = self.until_seen()
        self.assertIsNotNone(n)
        self.assertLessEqual(n, 5)
        e = self.entry()
        self.assertEqual((e.x, e.y, e.z, e.s, e.a), (100, 100, 0, True, 1))
        self.assertGreater(self.ev('LOS_CALLS'), 0)

    def test_wall_or_closed_door_blocks_sight(self):
        for kind in ('wall', 'closed'):
            with self.subTest(kind=kind):
                self.lua(f'WALLS = {{}}; WALL("x", 103, 90, 110, "{kind}"); LivingKnox.Senses.npcs = {{}}')
                self.player(walking=False)
                self.assertIsNone(self.until_seen(limit=30))
                e = self.entry()
                self.assertTrue(e is None or (not e.s and e.a == 0))

    def test_open_door_and_window_do_not_block(self):
        for kind, most in (('open', 5), ('glass', 6)):
            with self.subTest(kind=kind):
                self.lua(f'WALLS = {{}}; WALL("x", 103, 90, 110, "{kind}"); LivingKnox.Senses.npcs = {{}}')
                n = self.until_seen()
                self.assertIsNotNone(n)
                self.assertLessEqual(n, most)

    def test_night_without_light_reduces_the_range(self):
        self.lua('LIGHT_DEFAULT = 0; CLIMATE.day = 0; CLIMATE.ambient = 0')
        self.player(walking=True)
        self.assertIsNone(self.until_seen(limit=30))              # portée 5 < 6 cases
        self.h.move_player('A', 103.5, 100.5, 0)                  # 3 cases
        self.assertIsNotNone(self.until_seen(limit=30))
        # Lampe allumée en main : visible à 6 cases dans le noir.
        self.lua('LivingKnox.Senses.npcs = {}')
        self.h.move_player('A', 100.5, 100.5, 0)
        self.player(torch=0.8)
        self.assertIsNotNone(self.until_seen(limit=30))
        # Lumière de la case de la cible (lampadaire) plutôt que la nuit générale.
        self.lua('LivingKnox.Senses.npcs = {}; LIGHT["100,100,0"] = 1')
        self.player(torch=0)
        self.assertIsNotNone(self.until_seen(limit=30))

    def test_noise_heard_through_a_wall(self):
        self.lua('WALL("x", 103, 90, 110, "wall"); for x = 103, 110 do for y = 95, 105 do '
                 'ROOMS[x .. "," .. y .. ",0"] = "house" end end')
        self.h.move_player('A', 102.5, 100.5, 0)                  # 4 cases, mur entre eux, lui dedans, le joueur dehors
        self.player(walking=False)
        self.scans(5)
        self.assertIsNone(self.entry())                          # immobile derrière le mur : ni vu ni entendu
        self.player(running=True)
        self.scans(2)
        e = self.entry()
        self.assertTrue(e.h)
        self.assertFalse(e.s)
        self.assertEqual((e.x, e.y), (102, 100))
        # Plus de bruit : entendu encore HEAR_MS, puis oublié.
        self.player(running=False)
        self.scans(10, ms=200)
        self.assertTrue(self.entry().h)
        self.scans(10, ms=200)
        self.assertIsNone(self.entry())
        # Bruit du monde émis par le joueur immobile (tir, cri) : entendu ; bruit sans source : liste n.
        self.lua('addSound(HARNESS.players.A, 102, 100, 0, 20, 20); addSound(nil, 98, 99, 0, 30, 30)')
        self.scans(1)
        e = self.entry()
        self.assertTrue(e.h)
        self.assertFalse(e.s)
        noises = lua_list(self.ev('(LivingKnox.Senses.summary("n1")).n'))
        self.assertEqual([(n.x, n.y, n.r) for n in noises], [(98, 99, 30), (102, 100, 20)])

    def test_wide_world_sound_bounded_in_the_summary(self):
        # Essai MP du 2026-10-14 (E01-T15) : un bruit plus large que CHECK.NOISE_MAX (hélicoptère vanilla, 500)
        # faisait refuser tout le rapport d'état ("bad report", senses noise 1). Rayon borné dans le résumé.
        self.lua('addSound(nil, 98, 99, 0, 500, 500)')
        self.scans(1)
        noises = lua_list(self.ev('(LivingKnox.Senses.summary("n1")).n'))
        self.assertEqual([(n.x, n.y, n.r) for n in noises], [(98, 99, 300)])
        self.assertIsNone(self.ev('LivingKnox.Senses.validate(LivingKnox.Senses.summary("n1"))'))

    def test_crouched_target_detected_later(self):
        self.h.move_player('A', 96.5, 100.5, 0)                  # 10 cases
        self.player(walking=True)
        standing = self.until_seen(ms=100)
        self.lua('LivingKnox.Senses.npcs = {}')
        self.player(walking=True, sneaking=True)
        crouched = self.until_seen(ms=100)
        self.assertIsNotNone(standing)
        self.assertIsNotNone(crouched)
        self.assertGreater(crouched, standing)
        # Plus loin que la portée accroupie (10 x 0,5 x ... = 10 cases) : jamais vu accroupi, vu debout.
        self.h.move_player('A', 93.5, 100.5, 0)                  # 13 cases
        self.lua('LivingKnox.Senses.npcs = {}')
        self.assertIsNone(self.until_seen(limit=40, ms=100))
        self.player(sneaking=False)
        self.assertIsNotNone(self.until_seen(limit=40, ms=100))

    def test_vigilance_from_the_activity(self):
        self.h.move_player('A', 84.5, 100.5, 0)                  # 22 cases : au-delà du repos (20), en deçà de la garde
        self.player(walking=True)
        self.assertIsNone(self.until_seen(limit=20))
        self.lua('LivingKnox.Senses.setVigilance("n1", "guard"); LivingKnox.Senses.npcs = {}')
        self.assertIsNotNone(self.until_seen(limit=40))
        self.h.move_player('A', 104.5, 100.5, 0)                 # 2 cases, mais endormi : aucune vue
        self.lua('LivingKnox.Senses.setVigilance("n1", "sleep"); LivingKnox.Senses.npcs = {}')
        self.assertIsNone(self.until_seen(limit=20))
        self.assertFalse(self.lua('return LivingKnox.Senses.setVigilance("n1", "dreaming")'))

    def test_target_behind_the_npc_not_seen_except_at_contact(self):
        self.lua('KNOWN.n1.angle = 0')                            # regarde vers l'est, le joueur est à l'ouest
        self.player(walking=True)
        self.assertIsNone(self.until_seen(limit=20))
        self.h.move_player('A', 105.5, 100.5, 0)
        self.assertIsNotNone(self.until_seen(limit=20))

    def test_ghost_or_dead_players_ignored(self):
        self.player(walking=True, ghost=True)
        self.assertIsNone(self.until_seen(limit=10))
        self.player(ghost=False, dead=True)
        self.assertIsNone(self.until_seen(limit=10))

    def test_zombies_perceived_npc_bodies_excluded_summary_bounded(self):
        self.h.move_player('A', 300, 300, 0)
        for i in range(10):
            self.h.spawn_zombie(100 + i, 104.5, 96.5 + i, 0, owner='solo')
        self.lua('NPC("n2", 9002, 105.5, 101.5, 0)')            # autre corps de PNJ, juste à côté
        self.scans(15)
        sen = self.ev('(LivingKnox.Senses.summary("n1"))')
        self.assertEqual(sen.nz, 10)
        listed = lua_list(sen.z)
        self.assertEqual(len(listed), 6)                          # BUDGET.ZOMBIES
        self.assertNotIn(9002, [e.o for e in listed])
        self.assertTrue(all(e.s for e in listed))
        self.assertEqual(lua_list(sen.p), [])


class WallCornerScanTests(UnitBase):
    """LK05-T17 : coin de mur frôlé (géométrie de l'essai en jeu, repère de SuiteWallSiteTests) : le PNJ ne voit pas
    le joueur depuis le couple de cases exact et le voit dès que le joueur fait un pas (lineClear Clear)."""

    def test_npc_sees_the_player_one_square_aside_of_a_grazed_corner(self):
        self.lua(SuiteWallSiteTests.KITCHEN)
        self.lua('NPC("n1", 9001, 98.5, 100.5, 0)')                # regarde vers l'est
        self.player(walking=False)
        self.h.move_player('A', 100.5, 101.5, 0)
        self.assertIsNone(self.until_seen(limit=30))
        self.h.move_player('A', 100.5, 100.5, 0)                  # un pas vers le nord
        self.assertIsNotNone(self.until_seen(limit=30))


class DeterminismAndCostTests(unittest.TestCase):
    SCRIPT = [
        ('lua', 'NPC("n1", 9001, 106.5, 100.5, 180); NPC("n2", 9002, 90.5, 90.5, 45); WALL("y", 95, 80, 100, "glass")'),
        ('player', (100.5, 100.5)),
        ('lua', 'HARNESS.players.A.walking = true'),
        ('scan', 4), ('player', (99.5, 99.5)), ('scan', 3),
        ('lua', 'addSound(HARNESS.players.A, 99, 99, 0, 25, 25); HARNESS.spawnZombie(300, 101.5, 95.5, 0, "solo")'),
        ('scan', 3), ('lua', 'HARNESS.players.A.sneaking = true'), ('player', (92.5, 96.5)), ('scan', 6),
    ]

    def run_script(self):
        h = Harness(mode='solo', clients=('A',), debug=False)
        try:
            for path in CORE:
                h.load('solo', path)
            h.load('solo', SENSES_DOUBLES)
            h.load('solo', SENSES)
            h.load('solo', UNIT_HELPERS)
            dumps = []
            for kind, arg in self.SCRIPT:
                if kind == 'lua':
                    h.load('solo', arg)
                elif kind == 'player':
                    h.move_player('A', arg[0], arg[1], 0)
                else:
                    for _ in range(arg):
                        h.advance_ms(170)
                        h.load('solo', 'SCAN()')
                        dumps.append(h.eval('solo', 'DUMP(LivingKnox.Senses.summary("n1")) .. " / " '
                                                    '.. DUMP(LivingKnox.Senses.summary("n2"))'))
            return dumps
        finally:
            h.close()

    def test_same_inputs_same_result(self):
        first, second = self.run_script(), self.run_script()
        self.assertEqual(first, second)
        self.assertTrue(any(':true:' in d for d in first), first)   # le scénario voit bien quelque chose

    def test_cost_bounded_per_pass(self):
        h = Harness(mode='solo', clients=('A',), debug=False)
        try:
            for path in CORE:
                h.load('solo', path)
            h.load('solo', SENSES_DOUBLES)
            h.load('solo', SENSES)
            h.load('solo', UNIT_HELPERS)
            h.load('solo', 'for i = 1, 20 do NPC(string.format("n%02d", i), 9000 + i, 100 + i, 100, 180) end; '
                           'for i = 1, 300 do HARNESS.spawnZombie(i, 95 + (i % 30), 90 + math.floor(i / 30), 0, "solo") end')
            h.move_player('A', 110, 101, 0)
            budget = h.eval('solo', 'LivingKnox.Senses.BUDGET')
            covered = set()
            for _ in range(10):
                h.advance_ms(160)
                before = h.eval('solo', 'LOS_CALLS')
                n = h.load('solo', 'return SCAN()')
                last = h.eval('solo', 'LivingKnox.Senses.stats.last')
                self.assertEqual(n, budget.NPCS)
                self.assertLessEqual(last.targets, budget.NPCS * budget.TARGETS)
                self.assertLessEqual(last.los, budget.LOS)
                self.assertLessEqual(h.eval('solo', 'LOS_CALLS') - before, budget.LOS)
                self.assertLessEqual(last.zombies, budget.ZOMBIE_SCAN)
                covered |= {k for k in lua_list(h.eval('solo', '(function() local t = {} for id in pairs('
                                                       'LivingKnox.Senses.npcs) do t[#t + 1] = id end return t end)()'))}
            st = h.eval('solo', 'LivingKnox.Senses.stats')
            self.assertEqual(st.maxNpcs, budget.NPCS)
            self.assertLessEqual(st.maxLos, budget.LOS)
            self.assertGreater(st.losSkipped, 0)                  # budget atteint : cibles reportées, pas d'appel de plus
            self.assertEqual(len(covered), 20)                     # tour à tour : tous les PNJ examinés en 5 passages
        finally:
            h.close()


# ---------------------------------------------------------------- transport par le rapport d'état et mémoire serveur

class SensesReportBase(ReportBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, SENSES_DOUBLES)
            h.load(m, SENSES)
        return h

    def s(self, code, m=None):
        return self.ev('LivingKnox.Senses.' + code, m)

    def stand(self, m, zid, angle):
        self.h.load(m, f'local zb = HARNESS.zombies[{zid}]; zb.onFloor = false; zb.angle = {angle}')


class SoloSensesReportTests(SensesReportBase):
    mode = 'solo'

    def test_npc_sees_the_player_and_the_authority_keeps_it(self):
        zid = self.npc()                                          # corps à 102,102 ; joueur A à 100,100
        self.stand('solo', zid, 225)
        self.h.player('solo', 'A').walking = True
        for _ in range(12):
            self.exec_pass()
        e = self.s('perceivedPlayer("lk-1", "A")')
        self.assertIsNotNone(e)
        self.assertTrue(e.s)
        self.assertAlmostEqual(e.d, 2.8, places=1)
        p = self.s('perceived("lk-1")')
        self.assertEqual((p.seen, p.by, p.stale), (1, 'A', False))
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        # Mur entre eux : plus vu (attention qui retombe), toujours rapporté.
        self.h.load('solo', 'WALL("x", 102, 90, 110, "wall")')
        for _ in range(40):
            self.exec_pass()
        e = self.s('perceivedPlayer("lk-1", "A")')
        self.assertTrue(e is None or not e.s)
        # PNJ oublié par les rapports : perception oubliée.
        self.r('forget("lk-1")')
        self.assertIsNone(self.s('perceived("lk-1")'))


class MultiplayerSensesReportTests(SensesReportBase):
    def ready(self, owner='A'):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def run_passes(self, n, zid):
        sent = []
        for _ in range(n):
            self.exec_pass()
            sent += [m for m in self.h.pending() if m['command'] == 'bodyReport']
            self.h.pump()
        return sent

    def test_owner_computes_server_keeps_the_last_value(self):
        zid = self.ready('A')
        self.stand('A', zid, 225)                                 # A à 100,100 devant ; B à 96,108 sur le côté
        self.h.player('A', 'A').walking = True                    # copie du joueur A sur la machine A
        sent = self.run_passes(15, zid)
        self.assertTrue(sent)
        self.assertEqual({m['from'] for m in sent}, {'A'})        # B ne simule pas le corps : il ne mesure rien
        self.assertTrue(all('sen' in m['args'] for m in sent))
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        e = self.s('perceivedPlayer("lk-1", "A")')
        self.assertTrue(e.s)
        self.assertEqual(self.s('perceived("lk-1").by'), 'A')
        self.assertIsNone(self.h.eval('B', '(LivingKnox.Senses.summary("lk-1"))'))
        self.assertEqual(self.h.errors('server'), [])

    def forge(self, zid, sen, gap_ms=600):
        self.h.advance_ms(gap_ms)
        srv = self.h.zombie('server', zid)
        self.n = getattr(self, 'n', 5000) + 1
        args = {'id': 'lk-1', 'l': 0, 'n': self.n, 'x': srv.x, 'y': srv.y, 'z': srv.z, 'a': 90.0, 'act': 'idle',
                'hp': 2, 'pose': 'stand', 't': 0, 'sen': sen}
        before = self.r('stats.accepted')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'bodyReport', self.h.player('server', 'A'), args)
        return self.r('stats.accepted') == before + 1

    def test_malformed_summary_refuses_the_report_implausible_entries_dropped(self):
        zid = self.ready('A')
        self.h.load('A', 'LivingKnox.Reports = nil')              # rapports forgés seuls
        good = {'v': 1, 'nz': 1, 'p': [{'u': 'B', 'x': 96, 'y': 108, 'z': 0, 'a': 0.5, 's': False, 'h': True}],
                'z': [{'o': 77, 'x': 104, 'y': 104, 'z': 0, 'a': 1, 's': True, 'h': False}], 'n': []}
        self.h.spawn_zombie(77, 104, 104)                         # zombie 77 connu du serveur
        self.assertTrue(self.forge(zid, good))
        p = self.s('perceived("lk-1")')
        self.assertEqual((p.nz, p.heard, p.seen), (1, 1, 1))
        # Zombie inconnu du serveur (copie fantôme d'un corps retiré, campagne MP 2026-10-14) : entrée retirée.
        ghost = dict(good, z=[{'o': 78, 'x': 104, 'y': 104, 'z': 0, 'a': 1, 's': True, 'h': False}])
        self.h.advance_ms(200)                                    # liste des zombies du serveur relue
        self.assertTrue(self.forge(zid, ghost))
        self.assertEqual(self.s('perceived("lk-1").seen'), 0)
        self.assertEqual(self.s('stats.ghosts'), 1)
        self.assertTrue(self.forge(zid, good))
        for bad, why in (({'v': 2, 'nz': 0}, 'bad report'), ({'v': 1, 'nz': -1}, 'out of bounds'),
                         ({'v': 1, 'nz': 0, 'p': [{'u': 'B', 'x': 1, 'y': 1, 'z': 0, 'a': 3, 's': True, 'h': True}]},
                          'bad report'),
                         ({'v': 1, 'nz': 0, 'z': [{'o': i, 'x': 1, 'y': 1, 'z': 0, 'a': 1, 's': True, 'h': False}
                                                  for i in range(7)]}, 'out of bounds')):
            with self.subTest(bad=bad):
                before = self.why(why)
                self.assertFalse(self.forge(zid, bad))
                self.assertEqual(self.why(why), before + 1)
                self.assertEqual(self.s('perceived("lk-1").nz'), 1)   # mémoire inchangée
        # Entrées implausibles retirées, le reste gardé : joueur inconnu, vu à 200 cases, bruit plus loin que son rayon.
        mixed = {'v': 1, 'nz': 0,
                 'p': [{'u': 'Nobody', 'x': 100, 'y': 100, 'z': 0, 'a': 1, 's': True, 'h': False},
                       {'u': 'B', 'x': 300, 'y': 102, 'z': 0, 'a': 1, 's': True, 'h': False},
                       {'u': 'A', 'x': 100, 'y': 100, 'z': 0, 'a': 1, 's': True, 'h': False}],
                 'n': [{'x': 102, 'y': 200, 'z': 0, 'r': 10}, {'x': 102, 'y': 110, 'z': 0, 'r': 10}]}
        dropped = self.s('stats.dropped')
        self.assertTrue(self.forge(zid, mixed))
        self.assertEqual(self.s('stats.dropped') - dropped, 3)
        p = self.s('perceived("lk-1")')
        self.assertEqual([e.u for e in lua_list(p.p)], ['A'])
        self.assertEqual([(n.x, n.y) for n in lua_list(p.n)], [(102, 110)])

    def test_report_advanced_when_the_npc_starts_seeing(self):
        zid = self.ready('A')
        self.stand('A', zid, 45)                                  # regarde vers le sud-est : A (100,100) dans le dos
        self.h.move_player('B', 300, 300, 0)
        self.run_passes(40, zid)                                  # au repos : un rapport toutes les IDLE_MS
        self.assertIsNone(self.s('perceivedPlayer("lk-1", "A")'))
        self.h.move_player('A', 106, 106, 0)                      # entre dans son champ, à 5,7 cases
        start = self.h.real_ms
        seen_at = None
        for _ in range(60):
            self.run_passes(1, zid)
            e = self.s('perceivedPlayer("lk-1", "A")')
            if e is not None and e.s:
                seen_at = self.h.real_ms
                break
        self.assertIsNotNone(seen_at)
        self.assertLess(seen_at - start, 3000)                    # bien avant IDLE_MS (5 s)


# ---------------------------------------------------------------- LK06-T11 : fenêtre frappée rapportée au serveur

# Fenêtre (IsoWindow) posée sur la case 105,104, bord ouest (dehors 104,104), et cible de coups d'un zombie
# (getThumpTarget : posée par ThumpState chez le propriétaire, par le paquet Thump chez les autres clients ; jamais
# sur la copie du serveur d'un zombie simulé par un client, ThumpPacket.java:54-63).
THUMP_DOUBLES = r"""
local H = HARNESS
local C = H.classes
function C.IsoZombie:getThumpTarget() return self.thump end
local Win = C.IsoWindow or H.class('IsoWindow', C.IsoObject)
function Win:getSquare() return self.square end
function Win:getNorth() return self.north == true end
TWIN = setmetatable({ square = H.square(105, 104, 0), north = false }, Win)
local getWin = C.IsoGridSquare.getWindowTo
function C.IsoGridSquare:getWindowTo(nb)
    if nb ~= nil and self.y == 104 and nb.y == 104 and self.z == 0
        and ((self.x == 104 and nb.x == 105) or (self.x == 105 and nb.x == 104)) then return TWIN end
    if getWin ~= nil then return getWin(self, nb) end
    return nil
end
"""


class ThumpReportTests(SensesReportBase):
    """LK06-T11 : le client qui simule un zombie rapporte la fenetre qu'il frappe (commande zombieThumps), qu'il simule
    ou non les corps de PNJ voisins ; le serveur la garde apres controle (zombie connu et simule par ce client, fenetre
    reelle, copie a portee)."""

    def make(self, root=None):
        h = super().make(root)
        for m in ('server', 'A', 'B'):
            h.load(m, THUMP_DOUBLES)
        return h

    def ready(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def passes(self, n, gap=250):
        sent = []
        for _ in range(n):
            self.h.advance_ms(gap)
            self.exec_pass()
            sent += [m for m in self.h.pending() if m['command'] == 'zombieThumps']
            self.h.pump()
        return sent

    def thump(self, machine, on=True):
        self.h.eval(machine, f'(function() HARNESS.zombies[88].thump = {"TWIN" if on else "nil"} return true end)()')

    def test_owner_reports_the_window_server_keeps_it_then_forgets_it(self):
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='A')                 # simule par A, colle a la vitre
        self.assertFalse(self.passes(8))                                 # aucun coup : aucun envoi
        self.assertIsNone(self.s('thumpOf(88)'))
        self.thump('A')
        self.thump('B')                                                  # copie distante de B : jamais rapportee
        sent = self.passes(8)
        self.assertTrue(sent)
        self.assertEqual({m['from'] for m in sent}, {'A'})
        w = sent[0]['args']['w'][0] if isinstance(sent[0]['args']['w'], list) else sent[0]['args']['w'][1]
        self.assertEqual((w['o'], w['x'], w['y'], w['z'], w['k']), (88, 105, 104, 0, 'W'))
        self.assertLessEqual(len(sent), 2)                               # renvoye toutes les 2 s seulement
        t = self.s('thumpOf(88)')
        self.assertEqual((t.x, t.y, t.z, t.k, t.by), (105, 104, 0, 'W', 'A'))
        self.assertIsNone(self.h.eval('server', 'HARNESS.zombies[88]:getThumpTarget()'))   # copie du serveur
        # Le zombie ne frappe plus : liste vide envoyee aussitot, fenetre oubliee par le serveur.
        self.thump('A', False)
        sent = self.passes(2)
        self.assertEqual(len(sent), 1)
        self.assertIsNone(sent[0]['args'].get('w'))
        self.assertIsNone(self.s('thumpOf(88)'))
        self.assertEqual(self.s('stats.thumpsDropped or 0'), 0)
        self.assertEqual(self.h.errors('server'), [])

    def test_owner_reports_a_fallen_zombie_the_server_copy_does_not_see(self):
        """Campagne MP du 2026-10-15 : zombie à terre après l'enjambée, copie du serveur debout (aucun coup au sol)."""
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='A')
        self.assertIs(self.s('onFloor(HARNESS.zombies[88])'), False)
        self.h.eval('A', '(function() HARNESS.zombies[88].onFloor = true return true end)()')
        self.h.eval('B', '(function() HARNESS.zombies[88].onFloor = true return true end)()')   # copie distante
        sent = self.passes(4)
        self.assertEqual({m['from'] for m in sent}, {'A'})
        f = sent[0]['args']['f']
        f = f[0] if isinstance(f, list) else f[1]
        self.assertEqual((f['o'], f['x'], f['y'], f['z']), (88, 104, 104, 0))
        self.assertIs(self.s('onFloor(HARNESS.zombies[88])'), True)        # copie du serveur pas au sol
        self.assertIs(self.h.eval('server', 'HARNESS.zombies[88]:isOnFloor()'), False)
        # Relevé : liste vidée aussitôt, plus au sol pour le serveur.
        self.h.eval('A', '(function() HARNESS.zombies[88].onFloor = false return true end)()')
        self.passes(2)
        self.assertIs(self.s('onFloor(HARNESS.zombies[88])'), False)
        # Rapport d'un client qui ne simule pas ce zombie : ignoré.
        self.h.advance_ms(500)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'zombieThumps', self.h.player('server', 'B'),
                    {'n': 50, 'f': [{'o': 88, 'x': 104, 'y': 104, 'z': 0}]})
        self.assertIs(self.s('onFloor(HARNESS.zombies[88])'), False)
        self.assertGreaterEqual(self.s('stats.floorDropped'), 1)
        self.assertEqual(self.h.errors('server'), [])

    def test_owner_of_the_zombie_without_any_npc_body_still_reports(self):
        """Campagne MP du 2026-10-15 : corps simules par A, zombie passe a B pendant qu'il frappe : B le rapporte."""
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='B')
        self.thump('A')                                                  # A : copie distante (paquet Thump relaye)
        self.thump('B')
        sent = self.passes(6)
        self.assertEqual({m['from'] for m in sent}, {'B'})
        self.assertEqual(self.s('thumpOf(88).by'), 'B')

    def test_report_for_a_zombie_simulated_by_another_client_dropped(self):
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='A')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'zombieThumps', self.h.player('server', 'B'),
                    {'n': 1, 'w': [{'o': 88, 'x': 105, 'y': 104, 'z': 0, 'k': 'W'}]})
        self.assertIsNone(self.s('thumpOf(88)'))
        self.assertEqual(self.s('stats.thumpsDropped'), 1)

    def test_window_far_from_the_server_copy_dropped(self):
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='A')
        self.thump('A')
        self.h.eval('server', '(function() HARNESS.place(HARNESS.zombies[88], 97.5, 104.5, 0) return true end)()')
        self.passes(8)
        self.assertIsNone(self.s('thumpOf(88)'))                         # 7,5 cases de la fenetre sur le serveur
        self.assertGreaterEqual(self.s('stats.thumpsDropped'), 1)

    def test_malformed_or_replayed_report_refused(self):
        self.ready()
        self.h.spawn_zombie(88, 104.5, 104.5, owner='A')
        A = self.h.player('server', 'A')
        good = [{'o': 88, 'x': 105, 'y': 104, 'z': 0, 'k': 'W'}]
        for args in ({'n': 1, 'w': [{'o': 88, 'x': 105, 'y': 104, 'z': 0, 'k': 'E'}]}, {'w': good},
                     {'n': 2, 'w': [dict(good[0], o=i) for i in range(5)]}):
            with self.subTest(args=args):
                before = self.s('stats.thumpsRefused or 0')
                self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'zombieThumps', A, args)
                self.assertEqual(self.s('stats.thumpsRefused or 0'), before + 1)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'zombieThumps', A, {'n': 5, 'w': good})
        self.assertIsNotNone(self.s('thumpOf(88)'))
        self.h.advance_ms(500)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'zombieThumps', A, {'n': 5})   # rejoue : ignore
        self.assertIsNotNone(self.s('thumpOf(88)'))


# ---------------------------------------------------------------- suite en jeu lk.senses sur les doublures

class SuiteTests(MilestoneBase):
    def make(self, root=None):
        h = super().make(root)
        h.load('solo', REPORT_DOUBLES)
        h.load('solo', REPORTS)
        h.load('solo', SENSES_DOUBLES)
        h.load('solo', SENSES)
        return h

    def test_suite_listed_with_world_and_server_tags(self):
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.senses", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.senses')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 2)

    def test_suite_passes_on_the_doubles(self):
        self.init(new_world=True)
        self.h.load('solo', 'WALL("x", 103, 90, 110, "wall")')   # mur à l'est du joueur (100,100)
        self.h.load('solo', SUITE)
        report, results = self.run_suite('{ suite = "lk.senses", tags = "world" }')
        self.assertEqual(len(results), 2, results)
        self.assertTrue(report.ok, results)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKS] measure ')]
        self.assertTrue(any('open ground: seen after' in line for line in lines), lines)
        self.assertTrue(any('behind a wall: heard after' in line for line in lines), lines)


class SuiteWallSiteTests(MilestoneBase):
    """LK05-T17 : essai en jeu du 2026-10-12, PNJ 10691,9485 et joueur 10693,9486 (cuisine ouverte sur le salon, mur
    sud de la cuisine et passage sans mur, cellule 41_37). Repère du banc : (x - 10593, y - 9385). lineClear rend
    Blocked pour ce couple de cases exactement (le pas en diagonale frôle l'angle du mur) et Clear une case à côté :
    l'ancien choix du site retenait ce coin ; un pas du joueur ou du corps suffisait pour que le PNJ « voie à travers
    le mur ». Les doublures suivent le parcours de LosUtil.java:28-152 avec un mur par bord."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', REPORT_DOUBLES)
        h.load('solo', REPORTS)
        h.load('solo', SENSES_DOUBLES)
        h.load('solo', SENSES)
        return h

    KITCHEN = ('WALL("x", 99, 90, 98, "wall"); WALL("y", 101, 90, 98, "wall"); '   # cuisine x <= 98, y <= 100
               'WALL("x", 104, 90, 110, "wall")')                                 # pièce fermée à l'est

    def los(self, x0, y0, x1, y1):
        return self.h.eval('solo', f'LivingKnox.Senses.lineOfSight({x0}, {y0}, 0, {x1}, {y1}, 0)')

    def run_with_shift(self, to, max_ticks=20000, speed=0.08):
        """Lance la suite ; dès le site du test du mur choisi, le joueur passe en `to` (x, y). Rend le rapport, les
        résultats et le site choisi (x, y)."""
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.senses", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        site = None
        for _ in range(max_ticks):
            self.h.tick()
            self.h.load('solo', f'GET_UP(); STEP_ALL({speed})')
            if site is None:
                for line in self.h.logs('solo'):
                    m = re.search(r'behind a wall: npc square (\d+),(\d+)', line)
                    if m:
                        site = (int(m.group(1)), int(m.group(2)))
                        self.h.move_player('A', to[0] + 0.5, to[1] + 0.5, 0)
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return report, [(r.test, r.status, r.message) for r in lua_list(report.results)], site

    def test_grazing_corner_blocked_for_the_exact_squares_only(self):
        self.h.load('solo', self.KITCHEN)
        self.assertEqual(self.los(98, 100, 100, 101), 'Blocked')     # couple de l'essai en jeu
        self.assertEqual(self.los(98, 100, 100, 100), 'Clear')       # joueur une case au nord
        self.assertEqual(self.los(98, 99, 100, 101), 'Clear')        # PNJ une case au nord

    def test_site_behind_a_real_wall_survives_a_one_square_shift(self):
        self.init(new_world=True)
        self.h.load('solo', self.KITCHEN)
        self.h.move_player('A', 100.5, 101.5, 0)
        self.h.load('solo', SUITE)
        report, results, site = self.run_with_shift((100, 100))
        self.assertIsNotNone(site, results)
        self.assertNotEqual(site, (98, 100))                         # coin frôlé refusé
        self.assertGreaterEqual(site[0], 104)                        # derrière le mur plein de l'est
        self.assertTrue(report.ok, results)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKS] measure behind a wall after')]
        self.assertTrue(any(', player 100,100, los Blocked' in line for line in lines), lines)

    def test_player_who_walks_round_the_wall_reported_as_moved(self):
        self.init(new_world=True)
        self.h.load('solo', 'WALL("x", 103, 90, 110, "wall")')
        self.h.load('solo', SUITE)
        report, results, site = self.run_with_shift((106, 100))      # le joueur passe derrière le mur
        self.assertIsNotNone(site, results)
        self.assertFalse(report.ok, results)
        wall = [r for r in results if r[0].startswith('behind a wall')]
        self.assertEqual(wall[0][1], 'FAIL', results)
        self.assertIn('line of sight no longer blocked at the measure', wall[0][2])
        self.assertIn('player 106,100, los Clear', wall[0][2])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        files = [LUA / SENSES, LUA / REPORTS, LUA / EXECUTOR, DEV_LUA / SUITE]
        for path in files:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b', r'ZombRand',
                            r'\bmath\.random\b', r'\bRand\.'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        self.assertTrue(all(b < 128 for b in (DEV_LUA / SUITE).read_bytes()))
        code = re.sub(r'--[^\n]*', '', (LUA / SENSES).read_text(encoding='utf-8'))
        # Aucune décision ni effet sur le monde : aucun déplacement, consigne, santé ou commande réseau.
        for call in ('pathToLocation', 'setHealth', 'moveTo', 'sendServerCommand', 'sendClientCommand', 'setTarget',
                     'ModData'):
            self.assertNotIn(call, code)


if __name__ == '__main__':
    unittest.main()
