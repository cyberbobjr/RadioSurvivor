"""Tests hors jeu de la détection de blocage et du déblocage des PNJ Living Knox (LK04-T05) :
shared/LivingKnox/LK_Movement.lua, branché dans client/LivingKnox/LK_Executor.lua (exécutant), server/LivingKnox/
LK_Directives.lua (raison « stuck », case évitée) et server/LivingKnox/LK_Decisions.lua (échéance avancée).

    python RadioSurvivor/tests/test_lk_movement.py

Banc tests/harness.py (serveur et deux clients, ou solo) et doublures de test_lk_directives.py (pathToLocation, mode
pathfind, marche), complétées ici. Les doublures reproduisent le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API
réelle ni le chemin natif, seulement la logique :
- STEP_M : pas de marche en ligne droite vers le but du dernier pathToLocation (comme STEP) ; une case
  impraticable (sq.blocked, isFree(false) faux, IsoGridSquare.java:2894-2915) arrête le corps, qui reste en recherche
  (bPathfind vrai) : corps qui pousse contre un meuble ; WOBBLE[zid] : corps qui va et vient d'une case sans approcher
  (chemin qui oscille) ;
- recherche terminée sans arrivée (PATH_FAILS) : bPathfind et bMoving effacés (PathFindState.java:51-71).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list, LUA, DEV_LUA  # noqa: E402
import test_lk_directives as TD  # noqa: E402
import test_lk_decisions as TDEC  # noqa: E402

MOVEMENT = 'shared/LivingKnox/LK_Movement.lua'
MOD_FILE = LUA / MOVEMENT
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKStuck.lua'
TARGET = TD.TARGET   # (111, 102, 0) ; corps créé en 102, 102

MOVE_DOUBLES = r'''
local H = HARNESS
WOBBLE = {}
local function setPf(zb, v)
    local vars = rawget(zb, 'animVars')
    if not vars then vars = {}; zb.animVars = vars end
    vars.bpathfind = v
end
-- Un pas de la copie simulée ici. Rend l'état.
function STEP_M(zid, speed)
    local zb = H.zombies[zid]
    if zb == nil or zb.goal == nil then return 'none' end
    local pf = zb:getVariableBoolean('bPathfind')
    if pf and PATH_FAILS then
        setPf(zb, false); zb.moving = false
        return 'failed'
    end
    if not pf and not zb.moving then return 'idle' end
    if WOBBLE[zid] then
        local n = (zb.wob or 0) + 1
        zb.wob = n
        local dx = (math.floor(n / 20) % 2 == 0) and speed or -speed
        H.place(zb, zb.x + dx, zb.y, zb.z)
        return 'wobbling'
    end
    local tx, ty = zb.goal.x + 0.5, zb.goal.y + 0.5
    local dx, dy = tx - zb.x, ty - zb.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= speed then
        H.place(zb, tx, ty, zb.z)
        setPf(zb, false); zb.moving = false
        return 'reached'
    end
    local nx, ny = zb.x + dx / d * speed, zb.y + dy / d * speed
    if H.square(nx, ny, zb.z).blocked then return 'pressing' end
    H.place(zb, nx, ny, zb.z)
    return 'walking'
end
function BLOCK(x, y) H.square(x, y, 0).blocked = true end
'''


class MovementBase(TD.DirectiveBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, MOVE_DOUBLES)
        return h

    def mirror(self, zid, owner, machines=('A', 'B')):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)

    def ready(self, owner='A'):
        zid = self.npc()
        self.mirror(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def solo_ready(self):
        self.init()
        _, body = self.spawn()
        return body.onlineID

    def move(self, x=TARGET[0], y=TARGET[1]):
        v = self.d(f'moveTo("lk-1", {x}, {y}, {TARGET[2]}, "walk")')
        if self.mode == 'mp':
            self.h.pump()
        return v

    def all_machines(self, code):
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            self.h.load(m, code)

    def walk_m(self, zid, ticks, speed=0.05, until=None, step=True):
        """ticks images : tick, pas STEP_M sur la copie qui simule (si step), position recopiée, réseau livré."""
        for _ in range(ticks):
            self.h.tick(1)
            m = self.sim(zid)
            if step:
                self.h.eval(m, f'STEP_M({zid}, {speed})')
            if self.mode == 'mp':
                zb = self.h.zombie(m, zid)
                self.h.move_zombie(zid, zb.x, zb.y)
                self.h.pump()
            if until and until():
                return True
        return False

    def exe(self):
        return 'A' if self.mode == 'mp' else 'solo'

    def mv(self, code, m=None):
        return self.h.eval(m or self.exe(), 'LivingKnox.Movement.' + code)

    def now(self):
        return self.ev('getTimestampMs()')


class MultiplayerStuckTests(MovementBase):
    """Serveur dédié + deux clients ; A simule le corps et exécute."""

    def test_wobbling_body_fails_as_stuck_within_30_s_and_the_target_is_avoided(self):
        zid = self.ready('A')
        self.h.load('A', f'WOBBLE[{zid}] = true')
        t0 = self.now()
        self.move()
        self.assertTrue(self.walk_m(zid, 3000, until=self.done()), 'move never closed')
        ms = self.now() - t0
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.entry('why'), 'stuck')
        self.assertIn('no approach', self.entry('wd'))
        self.assertLess(ms, 30000)
        self.assertGreaterEqual(ms, 2 * self.mv('STUCK_MS'))          # nouvelle requête, puis point, puis échec
        self.assertEqual(self.mv('stats.repaths'), 1)
        self.assertEqual(self.mv('stats.unblocks'), 1)
        self.assertEqual(self.mv('stats.stuck'), 1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Movement.stats.stuck'), 0)   # B ne simule pas : rien
        lines = self.lk()
        self.assertTrue(any('move #1 failed after' in line and '(stuck: no approach' in line for line in lines), lines)
        self.assertTrue(any('target 111,102,0 avoided by this npc' in line for line in lines), lines)
        a_lines = [line for line in self.lk('A') if 'npc lk-1' in line]
        self.assertTrue(any('new path request' in line for line in a_lines), a_lines)
        self.assertTrue(any('unblocking through' in line for line in a_lines), a_lines)
        # Même PNJ, même case (ou voisine) : refusée pendant AVOID_MS ; autre case acceptée ; puis de nouveau permise.
        v, why = self.run_lua('return LivingKnox.Directives.moveTo("lk-1", 111, 103, 0, "walk")')
        self.assertIsNone(v)
        self.assertIn('avoided: this npc got stuck going to 111,102,0', why)
        self.assertIsNotNone(self.d('moveTo("lk-1", 104, 106, 0, "walk")'))
        self.h.advance_ms(self.ev('LivingKnox.Movement.AVOID_MS'))
        self.assertIsNotNone(self.d('moveTo("lk-1", 111, 102, 0, "walk")'))
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.h.errors(m), [], m)

    def test_before_lk04_t05_a_wobbling_body_was_never_reported(self):
        """Témoin : détection coupée (STUCK_MS immense), le va-et-vient d'une case n'arrête jamais la consigne."""
        zid = self.ready('A')
        self.h.load('A', f'WOBBLE[{zid}] = true; LivingKnox.Movement.STUCK_MS = 1e12')
        self.move()
        self.assertFalse(self.walk_m(zid, 3000, until=self.done()))
        self.assertIs(self.entry('done'), False)

    def test_body_pressing_against_furniture_takes_an_unblocking_point_and_arrives(self):
        zid = self.ready('A')
        self.all_machines('BLOCK(106, 102)')                      # meuble plein sur la ligne droite
        t0 = self.now()
        self.move()
        self.assertTrue(self.walk_m(zid, 3000, until=self.done()), 'move never closed')
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertLess(self.now() - t0, 30000)
        self.assertEqual(self.mv('stats.unblocks'), 1)
        self.assertEqual(self.mv('stats.unblockReached'), 1)
        self.assertEqual(self.mv('stats.stuck'), 0)
        # Point de déblocage : case libre en ligne dégagée, la plus proche de l'étape, ordre fixe (105,100).
        paths = lua_list(self.h.eval('A', 'PATHS'))
        self.assertTrue(any(p.startswith('A:105,100@') for p in paths), paths)
        self.assertEqual(paths[-1].split('@')[0], 'A:111,102')
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(LivingKnox.Movement.stuckAt) do n = n + 1 end '
                                      'return n'), 0)

    def test_gesture_climb_and_door_wait_pause_the_detection(self):
        zid = self.ready('A')
        self.move()
        self.walk_m(zid, 20)
        # Geste ponctuel (attendre, forcer, ouvrir une fenêtre : LK04-T04/T13) pendant 20 s, corps immobile.
        self.h.load('A', 'BASE_ACT = LivingKnox.Anim.actOf; LivingKnox.Anim.actOf = function() return "wait", 0 end')
        self.walk_m(zid, 1250, step=False)
        self.h.load('A', 'LivingKnox.Anim.actOf = BASE_ACT')
        # Escalade (climbwindow) pendant 10 s, corps immobile.
        self.h.load('A', f'HARNESS.zombies[{zid}].actionState = "climbwindow"')
        self.walk_m(zid, 625, step=False)
        self.h.load('A', f'HARNESS.zombies[{zid}].actionState = nil')
        self.assertTrue(self.walk_m(zid, 2000, until=self.done()), 'move never closed')
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.stats.stuckSeen'))
        self.assertEqual(self.mv('stats.unblocks'), 0)

    def test_detour_on_new_squares_is_progress(self):
        """Un corps qui s'éloigne de l'étape sur des cases nouvelles (détour du chemin vanilla) progresse."""
        zid = self.ready('A')
        self.move()
        self.walk_m(zid, 10)
        # Détour : le corps part vers le nord-ouest 10 s (cases nouvelles), puis reprend vers la case visée.
        self.h.load('A', f'local z = HARNESS.zombies[{zid}] DETOUR_GOAL = z.goal z.goal = {{ x = 96, y = 92, z = 0 }}')
        self.walk_m(zid, 625, speed=0.012)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.stats.stuckSeen'))
        self.h.load('A', f'HARNESS.zombies[{zid}].goal = DETOUR_GOAL')
        self.assertTrue(self.walk_m(zid, 3000, until=self.done()))
        self.assertEqual(self.entry('s'), 'arrived')

    def test_report_reason_and_detail_are_bounded(self):
        zid = self.ready('A')
        self.move()
        self.walk_m(zid, 5)
        srv = self.h.zombie('server', zid)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'A'),
                    {'id': 'lk-1', 'v': 1, 'l': self.entry('l'), 's': 'failed', 'x': srv.x, 'y': srv.y, 'z': 0,
                     'a': 0, 'n': 10 ** 6, 't': 0, 'why': 'x' * 500, 'wd': 'y' * 900})
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(len(self.entry('why')), self.ev('LivingKnox.Movement.WHY_MAX'))
        self.assertEqual(len(self.entry('wd')), self.ev('LivingKnox.Movement.DETAIL_MAX'))
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(LivingKnox.Movement.stuckAt) do n = n + 1 end '
                                      'return n'), 0)                # autre raison : rien d'évité


class SoloStuckTests(MovementBase):
    mode = 'solo'

    def test_solo_unreachable_target_fails_as_stuck_quickly(self):
        zid = self.solo_ready()
        self.h.load('solo', 'PATH_FAILS = true')
        t0 = self.now()
        self.move()
        self.assertTrue(self.walk_m(zid, 3000, until=self.done()))
        self.assertLess(self.now() - t0, 30000)
        self.assertEqual(self.entry('why'), 'stuck')
        self.assertIn('no path', self.entry('wd'))
        self.assertEqual(self.mv('stats.unblocks'), 1)
        v, why = self.run_lua('return LivingKnox.Directives.moveTo("lk-1", 111, 102, 0, "walk")')
        self.assertIsNone(v)
        self.assertIn('avoided', why)
        self.run_lua('LivingKnox.Movement.forgetStuck("lk-1")')
        self.assertIsNotNone(self.d('moveTo("lk-1", 111, 102, 0, "walk")'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_unblocking_point_needs_a_clear_line_and_avoids_plants(self):
        self.solo_ready()
        code = ('local z = LivingKnox.Bodies.find("lk-1") HARNESS.place(z, 105.9, 102.5, 0) '
                'local p, why = LivingKnox.Movement.unblockPoint(z, 111, 102) '
                'if p == nil then return nil, why end return p.x .. "," .. p.y')
        self.assertEqual(self.run_lua(code), '108,102')            # rien de bloqué : la plus proche de l'étape
        self.run_lua('BLOCK(106, 102)')
        self.assertEqual(self.run_lua(code), '105,100')            # (106,102) bloquée coupe les lignes vers l'est
        self.run_lua('getCell():getGridSquare(105, 99, 0).plant = { state = "seeded" }')
        self.assertEqual(self.run_lua(code), '105,104')            # plante à une case de (105,100)
        self.run_lua('for x = 102, 109 do for y = 98, 106 do if not (x == 105 and y == 102) then BLOCK(x, y) end '
                     'end end')
        p, why = self.run_lua(code)
        self.assertIsNone(p)
        self.assertIn('no free square in a clear line', why)

    def test_clear_line_rejects_walls_and_cut_corners(self):
        self.solo_ready()
        self.run_lua('WALL = {} function HARNESS.classes.IsoGridSquare:isBlockedTo(o) '
                     'return WALL[self.x .. "," .. self.y .. ">" .. o.x .. "," .. o.y] == true end')
        line = 'return LivingKnox.Movement.clearLine(100.5, 100.5, 103.5, 100.5, 0)'
        self.assertIs(self.run_lua(line), True)
        self.run_lua('WALL["101,100>102,100"] = true')
        self.assertIs(self.run_lua(line), False)
        diag = 'return LivingKnox.Movement.clearLine(100.5, 100.5, 101.5, 101.5, 0)'
        self.assertIs(self.run_lua(diag), True)
        self.run_lua('BLOCK(101, 100)')                             # coin : une des deux cases pleine
        self.assertIs(self.run_lua(diag), False)

    def test_progress_counts_approach_and_new_squares_only(self):
        self.solo_ready()
        self.run_lua('RUN = {} Z = { x = 100.5, y = 100.5, z = 0 } '
                     'function Z:getX() return self.x end function Z:getY() return self.y end '
                     'function Z:getZ() return self.z end LivingKnox.Movement.begin(RUN, 0)')
        p = 'return LivingKnox.Movement.progress(RUN, Z, {d}, {t})'
        self.assertIs(self.run_lua(p.format(d=10, t=0)), False)
        self.assertIs(self.run_lua(p.format(d=9.8, t=5000)), False)   # moins d'IMPROVE : pas un progrès
        self.assertIs(self.run_lua(p.format(d=9.8, t=6000)), True)
        self.assertIs(self.run_lua(p.format(d=9.4, t=6100)), False)   # approche d'IMPROVE : progrès
        self.run_lua('Z.x = 101.5')                                   # case nouvelle, plus loin : progrès
        self.assertIs(self.run_lua(p.format(d=10.5, t=12000)), False)
        self.run_lua('Z.x = 100.5')                                   # case déjà vue : rien
        self.assertIs(self.run_lua(p.format(d=10, t=18100)), True)
        self.run_lua('LivingKnox.Movement.pause(RUN, 18200)')
        self.assertIs(self.run_lua(p.format(d=10, t=24000)), False)   # pause : le temps repart
        self.assertIs(self.run_lua(p.format(d='nil', t=30300)), True)   # autre niveau : seules les cases comptent


class StuckDecisionTests(TDEC.SoloDecisionTests):
    """Cadre de décision (solo, pile complète de test_lk_decisions.py) : consigne du cadre close en échec « stuck ».
    Les tests hérités de test_lk_decisions.py sont retirés ici (ils tournent dans leur propre fichier)."""

    def test_stuck_directive_of_the_frame_is_decided_again_and_its_target_avoided(self):
        gid = self.mk()
        self.all_members(gid, 4)
        # Membre emporté loin du foyer : à l'échéance, retour au foyer en marchant (consigne du cadre).
        self.run_lua(f'local z = MAT_BODY("{gid}", "m-2") HARNESS.place(z, 90.5, 110.5, 0)')
        until = self.run_lua(f'return LivingKnox.Decisions.get(MEMBER_NPC("{gid}", "m-2")).untilMin')
        self.h.advance(until - self.ev('LivingKnox.Decisions.currentMinute()'))
        self.all_members(gid, 4)
        npc = self.run_lua(f'return MEMBER_NPC("{gid}", "m-2")')
        op, x, y, v, l = self.run_lua(f'local e = LivingKnox.Directives.get("{npc}") return e.op, e.x, e.y, e.v, e.l')
        self.assertEqual(op, 'move')
        self.assertEqual(self.ev(f'LivingKnox.Decisions.state.issued["{npc}"]'), v)
        # L'exécutant rapporte l'échec « stuck » (rapport direct en solo).
        ok = self.run_lua(f'local z = MAT_BODY("{gid}", "m-2") return LivingKnox.Directives.onReport(getPlayer(), '
                          f'{{ id = "{npc}", v = {v}, l = {l}, s = "failed", x = z:getX(), y = z:getY(), z = 0, '
                          f'n = 1000000, why = "stuck", wd = "no approach (bench)" }})')
        self.assertIs(ok, True)
        decided = self.ev('LivingKnox.Decisions.stats.decided')
        refused = self.ev('LivingKnox.Decisions.stats.refused')
        self.all_members(gid, 4)
        self.assertEqual(self.ev('LivingKnox.Movement.stats.taken'), 1)
        self.assertGreater(self.ev('LivingKnox.Decisions.stats.decided'), decided)   # décision reprise
        self.assertGreaterEqual(self.ev('LivingKnox.Movement.stats.avoided'), 1)
        self.assertGreater(self.ev('LivingKnox.Decisions.stats.refused'), refused)   # même case refusée
        e = self.run_lua(f'local e = LivingKnox.Directives.get("{npc}") return e.op, e.x, e.y, e.s')
        self.assertFalse(e[0] == 'move' and (e[1], e[2]) == (x, y) and e[3] != 'failed', e)
        self.assertTrue(any(f'npc {npc}: chore directive stuck, decision taken again' in line
                            for line in self.h.logs('solo')), self.h.logs('solo'))
        self.assertEqual(self.h.errors('solo'), [])


for _name in dir(TDEC.MultiplayerDecisionTests):
    if _name.startswith('test_'):
        setattr(StuckDecisionTests, _name, None)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_source_and_english_logs(self):
        for path in (MOD_FILE, SUITE):
            src = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in src.splitlines())
            self.assertTrue(code.isascii(), path.name)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'[^=~<>]=?>>|<<'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')

    def test_suite_lists_with_world_tags(self):
        src = SUITE.read_text(encoding='utf-8')
        self.assertIn('RST.suite("lk.stuck", { tags = { "world", "server" }', src)
        self.assertEqual(len(re.findall(r'suite\.test\(', src)), 2)


class SuiteListTests(MovementBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', 'shared/RST/suites/RST_LKStuck.lua')
        return h

    def test_suite_is_listed(self):
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.stuck", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.stuck')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertEqual(listed.count, 2)


if __name__ == '__main__':
    unittest.main()
