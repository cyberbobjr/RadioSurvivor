"""Tests hors jeu de l'action « s'écarter » et du signalement d'un blocage par un PNJ (LK18-T02, ADR
adr-ceder-le-passage.md D01, D03, D06) :
- client/LivingKnox/LK_PassageSignal.lua (exécutant : PNJ devant soi sur le trajet, signal, attente bornée), branché
  dans client/LivingKnox/LK_Executor.lua ;
- server/LivingKnox/LK_PassageAuthority.lua (autorité : contrôles, cases libres, arbitrage, ordre) ;
- server/LivingKnox/Decisions/LK_Decide_StepAside.lua (action « s'écarter » : extension du cadre de décision, fin
  de l'écart, reprise) ; shared/LivingKnox/LK_Movement.lua (échec « stuck » excusé après un passage accordé).

    python tests/test_lk_step_aside.py

Banc tests/harness.py et doublures de test_lk_movement.py (marche en ligne droite, cases bloquées). STEP_P y ajoute
le contact entre deux corps (centres à moins de BODY cases : le corps pousse sans avancer, comme deux zombies qui ne
se traversent pas). Preuve de la logique Lua, pas du chemin natif réel ni des collisions du moteur.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import lua_src  # noqa: E402
from test_lk_bodies import DEV_LUA  # noqa: E402
import test_lk_movement as TM  # noqa: E402
import test_lk_decisions as TDEC  # noqa: E402

SIGNAL = 'client/LivingKnox/LK_PassageSignal.lua'
AUTHORITY = 'server/LivingKnox/LK_PassageAuthority.lua'
STEP_ASIDE = 'server/LivingKnox/Decisions/LK_Decide_StepAside.lua'
STOP_PLACE = 'server/LivingKnox/LK_StopPlace.lua'
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKPassage.lua'
PA = 'LivingKnox.PassageAuthority'
SA = 'LivingKnox.StepAside'

# Marche avec contact entre corps : STEP_M de test_lk_movement.py, plus le contact (BODY cases entre deux centres).
BUMP_DOUBLES = r'''
local H = HARNESS
BODY = 0.9
local function setPf(zb, v)
    local vars = rawget(zb, 'animVars')
    if not vars then vars = {}; zb.animVars = vars end
    vars.bpathfind = v
end
local function bumps(zid, nx, ny)
    for id, o in pairs(H.zombies) do
        if id ~= zid and o.z == H.zombies[zid].z then
            local dx, dy = o.x - nx, o.y - ny
            if dx * dx + dy * dy < BODY * BODY then
                local cx, cy = o.x - H.zombies[zid].x, o.y - H.zombies[zid].y
                if dx * dx + dy * dy < cx * cx + cy * cy then return true end   -- s'en approcher seulement
            end
        end
    end
    return false
end
function STEP_P(zid, speed)
    local zb = H.zombies[zid]
    if zb == nil or zb.goal == nil then return 'none' end
    local pf = zb:getVariableBoolean('bPathfind')
    if not pf and not zb.moving then return 'idle' end
    local tx, ty = zb.goal.x + 0.5, zb.goal.y + 0.5
    local dx, dy = tx - zb.x, ty - zb.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= speed then
        if bumps(zid, tx, ty) then return 'pressing' end
        H.place(zb, tx, ty, zb.z)
        setPf(zb, false); zb.moving = false
        return 'reached'
    end
    local nx, ny = zb.x + dx / d * speed, zb.y + dy / d * speed
    if H.square(nx, ny, zb.z).blocked or bumps(zid, nx, ny) then return 'pressing' end
    H.place(zb, nx, ny, zb.z)
    return 'walking'
end
'''


def stack(h, machines):
    """Fichiers du passage chargés comme le jeu : media/lua/server partout (un client MP s'y arrête), client hors
    serveur dédié."""
    for m in machines:
        h.load(m, BUMP_DOUBLES)
        h.load(m, STOP_PLACE)
        h.load(m, AUTHORITY)
        h.load(m, STEP_ASIDE)
        if m != 'server':
            h.load(m, SIGNAL)


class PassageBase(TM.MovementBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        stack(h, ['solo'] if self.mode == 'solo' else ['server', 'A', 'B'])
        return h

    def second(self, x, y, owner=None):
        """Deuxième PNJ (lk-2) créé loin puis posé en (x, y) : la création refuse une case voisine d'un corps."""
        _, body = self.spawn(x=140, y=140)
        zid = body.onlineID
        self.run_lua(f'HARNESS.place(LivingKnox.Bodies.find("lk-2"), {x}, {y}, 0)')
        if self.mode == 'mp':
            self.mirror(zid, owner or 'server')
        return zid

    def walk_both(self, ids, ticks, speed=0.05, until=None):
        for _ in range(ticks):
            self.h.tick(1)
            for zid in ids:
                m = self.sim(zid)
                self.h.eval(m, f'STEP_P({zid}, {speed})')
                if self.mode == 'mp':
                    zb = self.h.zombie(m, zid)
                    self.h.move_zombie(zid, zb.x, zb.y)
            if self.mode == 'mp':
                self.h.pump()
            if until and until():
                return True
        return False

    def signal(self, **over):
        """Signal de lk-1 (consigne courante) bloqué par lk-2, remis directement à l'autorité (solo)."""
        args = {'id': '"lk-1"', 'v': 'e.v', 'l': 'e.l or 0', 'b': '"lk-2"', 'x': 'm:getX()', 'y': 'm:getY()',
                'z': 'm:getZ()', 'bx': 'b:getX()', 'by': 'b:getY()', 'bz': 'b:getZ()', 'tx': '111', 'ty': '102'}
        args.update(over)
        fields = ', '.join(f'{k} = {v}' for k, v in args.items())
        return self.run_lua('local e = LivingKnox.Directives.get("lk-1") local m = LivingKnox.Bodies.find("lk-1") '
                            'local b = LivingKnox.Bodies.find("lk-2") '
                            f'local d, why = {PA}.onSignal(getPlayer(), {{ {fields} }}) '
                            'if d == nil then return nil, why end return d.action, d.to.x, d.to.y')

    def directive(self, npc):
        return self.run_lua(f'local e = LivingKnox.Directives.get("{npc}") if e == nil then return nil end '
                            'return e.op, e.x, e.y, e.done, e.s')


class SignalDetectionTests(PassageBase):
    """Exécutant : PNJ juste devant soi, vers l'étape, au plus RANGE cases, même niveau."""

    def ahead(self, tx=111, ty=102):
        return self.run_lua('local z = LivingKnox.Bodies.find("lk-1") '
                            'local id = LivingKnox.PassageSignal.blockerAhead(z, LivingKnox.Executor.loadedBodies(), '
                            f'"lk-1", {tx}, {ty}) return id')

    def test_npc_just_ahead_on_the_way_is_found(self):
        self.solo_ready()
        self.second(103.5, 102.5)
        self.assertEqual(self.ahead(), 'lk-2')

    def test_npc_behind_far_or_on_another_level_is_ignored(self):
        self.solo_ready()
        self.second(101.5, 102.5)                                   # derrière
        self.assertIsNone(self.ahead())
        self.run_lua('HARNESS.place(LivingKnox.Bodies.find("lk-2"), 104.5, 102.5, 0)')   # 2 cases : trop loin
        self.assertIsNone(self.ahead())
        self.run_lua('HARNESS.place(LivingKnox.Bodies.find("lk-2"), 103.5, 102.5, 1)')   # autre niveau
        self.assertIsNone(self.ahead())
        self.run_lua('HARNESS.place(LivingKnox.Bodies.find("lk-2"), 103.5, 102.5, 0)')
        self.assertIsNone(self.ahead(tx=95, ty=102))                # étape dans l'autre sens


class AuthorityTests(PassageBase):
    """Autorité : voisinage (D06), case de retrait libre, arbitrage, ordre au bloqueur."""

    def setUp(self):
        super().setUp()
        self.solo_ready()
        self.second(103.5, 102.5)
        self.move()

    def test_lower_priority_blocker_is_ordered_aside_off_the_path(self):
        action, x, y = self.signal()
        self.assertEqual(action, 'stepAside')
        self.assertIn((x, y), [(103, 101), (103, 103)])
        # Marche visant la case libre juste au-delà (un corps « arrive » à ARRIVE = 1 case du centre visé).
        op, dx, dy, done, _ = self.directive('lk-2')
        self.assertEqual((op, dx, dy, done), ('move', x, y + (y - 102), False))
        self.assertEqual(self.ev(f'{PA}.stats.granted'), 1)
        self.assertIsNotNone(self.ev(f'{SA}.orders["lk-2"]'))
        self.assertTrue(any('npc lk-1: blocked by npc lk-2' in s and 'stepAside' in s for s in self.lk()), self.lk())

    def test_not_neighbours_refused(self):
        self.run_lua('HARNESS.place(LivingKnox.Bodies.find("lk-2"), 106.5, 102.5, 0)')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('not neighbours', why)
        self.assertIsNone(self.directive('lk-2'))
        self.run_lua('HARNESS.place(LivingKnox.Bodies.find("lk-2"), 103.5, 102.5, 1)')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('not neighbours', why)

    def test_no_free_square_refused(self):
        self.run_lua('for x = 99, 107 do for y = 98, 106 do '
                     'if not ((x == 102 or x == 103) and y == 102) then BLOCK(x, y) end end end')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('no free square', why)
        self.assertIsNone(self.directive('lk-2'))

    def test_square_taken_by_a_standing_character_is_not_free(self):
        self.run_lua('for x = 99, 107 do for y = 98, 106 do '
                     'if not ((x == 102 or x == 103) and y == 102) and not (x == 103 and y == 101) then '
                     'BLOCK(x, y) end end end')
        self.run_lua('local o = { x = 103.5, y = 101.5, z = 0 } HARNESS.place(o, 103.5, 101.5, 0) '
                     'setmetatable(o, HARNESS.classes.IsoZombie)')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('no free square', why)

    def high(self):
        self.run_lua(f'LivingKnox.Passage.priority("t.high", 90) {PA}.kindOf = function(id) '
                     'if id == "lk-2" then return "t.high" end return nil end')

    def test_moving_blocker_with_priority_keeps_its_way(self):
        self.high()
        v = self.d('moveTo("lk-2", 103, 106, 0, "walk")')            # en marche : la priorité départage (D02)
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('priority', why)
        self.assertEqual(self.run_lua('return LivingKnox.Directives.get("lk-2").v'), v)

    def test_stationary_blocker_yields_whatever_its_priority(self):
        # ADR, mise à jour du 2026-11-15 (soir), D07 : refus « blocker has priority (guard vs meal) » de la campagne.
        self.high()
        action, x, y = self.signal()
        self.assertEqual(action, 'stepAside')
        self.assertEqual(self.directive('lk-2')[0], 'move')
        self.assertTrue(any('granted (nil vs t.high)' in s for s in self.lk()), self.lk())

    def test_blocker_in_combat_or_in_care_keeps_its_place(self):
        self.run_lua('LivingKnox.Combat = { get = function(id) if id == "lk-2" then return {} end end }')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('in combat', why)
        self.h.advance_ms(self.ev(f'{PA}.SIGNAL_MS'))              # un signal par demandeur et par SIGNAL_MS
        self.run_lua('LivingKnox.Combat = nil LivingKnox.Care = { get = function() return nil end, '
                     'taskOf = function() return nil end, caredFor = function(id) return id == "lk-2" end }')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('cared for', why)
        self.h.advance_ms(self.ev(f'{PA}.SIGNAL_MS'))
        self.run_lua('LivingKnox.Care = { get = function() return nil end, caredFor = function() return false end, '
                     'taskOf = function(id) if id == "lk-2" then return "lk-9", {} end return nil end }')
        d, why = self.signal()
        self.assertIsNone(d)
        self.assertIn('caring', why)
        self.assertIsNone(self.directive('lk-2'))

    def test_free_square_reachable_around_a_corner_within_three_squares(self):
        # ADR D08 : refus « no free square for the blocker (chore vs guard) » de la campagne. Seule case libre :
        # 104,104, joignable par 103,103 puis 103,104 (plantes : on y passe, on ne s'y arrête pas) ; la ligne droite
        # depuis le bloqueur coupe 104,103, bloquée.
        self.run_lua('for x = 99, 107 do for y = 98, 106 do local keep = (x == 102 or x == 103) and y == 102 '
                     'keep = keep or (x == 103 and (y == 103 or y == 104)) or (x == 104 and y == 104) '
                     'if not keep then BLOCK(x, y) end end end '
                     'getCell():getGridSquare(103, 103, 0).plant = { state = "seeded" } '
                     'getCell():getGridSquare(103, 104, 0).plant = { state = "seeded" }')
        self.assertIsNone(self.run_lua('local n = 0 for _, c in ipairs(' + PA + '.freeAround(103, 102, 0)) do '
                                       'if c.x ~= 104 or c.y ~= 104 then n = n + 1 end end '
                                       'if n > 0 then return n end return nil'))
        action, x, y = self.signal()
        self.assertEqual((x, y), (104, 104))
        self.assertIn(action, ('stepAside', 'backOff'))   # derrière le bloqueur : recul

    def test_passage_squares_are_allowed_for_the_yield(self):
        # D08 : une case de passage (couloir d'une case de large, 103,103..104 entre deux colonnes bloquées) reste une
        # case de retrait.
        self.run_lua('for y = 103, 105 do BLOCK(102, y) BLOCK(104, y) end')
        cells = self.run_lua('local out = {} for _, c in ipairs(' + PA + '.freeAround(103, 102, 0)) do '
                             'out[#out + 1] = c.x .. "," .. c.y end return table.concat(out, " ")')
        self.assertIn('103,103', cells.split())

    def test_signal_of_a_closed_or_other_move_refused(self):
        d, why = self.signal(v='e.v + 1')
        self.assertIsNone(d)
        self.assertIn('no open move', why)
        d, why = self.signal(b='"lk-9"')
        self.assertIsNone(d)
        self.assertIn('blocker', why)

    def test_granted_passage_excuses_a_later_stuck_failure(self):
        self.signal()
        v, l = self.run_lua('local e = LivingKnox.Directives.get("lk-1") return e.v, e.l')
        ok = self.run_lua('local z = LivingKnox.Bodies.find("lk-1") return LivingKnox.Directives.onReport('
                          f'getPlayer(), {{ id = "lk-1", v = {v}, l = {l}, s = "failed", x = z:getX(), '
                          'y = z:getY(), z = 0, n = 1000000, why = "stuck", wd = "bench" })')
        self.assertIs(ok, True)
        self.assertEqual(self.mv('stats.excused'), 1)
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(LivingKnox.Movement.stuckAt) do n = n + 1 end '
                                      'return n'), 0)
        self.assertIs(self.run_lua('return LivingKnox.Movement.takeStuck("lk-1", ' + str(v) + ')'), False)


class SoloPassageTests(PassageBase):
    """Bout à bout en solo : lk-1 bute contre lk-2 immobile sur sa ligne, signale, lk-2 s'écarte puis revient."""

    def test_blocked_mover_signals_blocker_steps_aside_then_returns(self):
        z1 = self.solo_ready()
        z2 = self.second(104.5, 102.5)
        self.move()
        self.assertTrue(self.walk_both([z1, z2], 4000, until=self.done()), 'move never closed')
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.ev('LivingKnox.Executor.stats.passageSignals'), 1)
        self.assertEqual(self.ev(f'{PA}.stats.granted'), 1)
        self.assertEqual(self.mv('stats.stuck'), 0)
        # PNJ devant cherché dès PassageSignal.STILL_MS : aucun traitement du blocage (STUCK_MS) n'a commencé.
        self.assertIsNone(self.ev('LivingKnox.Executor.stats.stuckSeen'))
        # Le bloqueur, sans consigne avant, revient à sa case une fois le demandeur passé.
        self.walk_both([z1, z2], 1500, until=lambda: self.ev(f'{SA}.orders["lk-2"] == nil') is True)
        op, x, y, _, _ = self.directive('lk-2')
        self.assertEqual((op, x, y), ('move', 104, 102))
        self.walk_both([z1, z2], 1500, until=lambda: self.directive('lk-2')[3] is True)
        self.assertLessEqual(self.run_lua('local z = LivingKnox.Bodies.find("lk-2") '
                                          'return LivingKnox.Directives.dist(z:getX(), z:getY(), 104.5, 102.5)'),
                             self.ev('LivingKnox.Directives.ARRIVE'))
        lines = self.lk()
        self.assertTrue(any('npc lk-2: stepped aside for lk-1' in s and 'passed' in s for s in lines), lines)
        self.assertEqual(self.h.errors('solo'), [])

    def test_refused_signal_keeps_the_stuck_handling(self):
        z1 = self.solo_ready()
        z2 = self.second(104.5, 102.5)
        self.run_lua('LivingKnox.Combat = { get = function(id) if id == "lk-2" then return {} end end }')
        self.move()
        self.assertTrue(self.walk_both([z1, z2], 4000, until=self.done()), 'move never closed')
        self.assertEqual(self.ev('LivingKnox.Executor.stats.passageSignals'), 1)
        self.assertEqual(self.ev(f'{PA}.stats.granted'), 0)
        self.assertIsNone(self.directive('lk-2'))
        # Contourné par le point de déblocage, ou échec « stuck » : le traitement habituel du blocage.
        self.assertIn(self.entry('s'), ('arrived', 'failed'))


class MultiplayerPassageTests(PassageBase):
    """Serveur dédié + deux clients : A simule les deux corps ; le serveur seul arbitre et ordonne."""
    mode = 'mp'

    def test_owner_signal_reaches_the_server_which_orders_the_blocker(self):
        z1 = self.ready('A')
        z2 = self.second(104.5, 102.5, owner='A')
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.move()
        self.assertTrue(self.walk_both([z1, z2], 4000, until=self.done()), 'move never closed')
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.passageSignals'), 1)
        self.assertEqual(self.ev(f'{PA}.stats.granted'), 1)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.StepAside'))   # client : aucune décision
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.h.errors(m), [], m)

    def test_signal_from_a_client_that_does_not_own_the_mover_is_refused(self):
        z1 = self.ready('A')
        self.second(103.5, 102.5, owner='A')
        self.move()
        srv = self.h.zombie('server', z1)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'passageBlocked', self.h.player('server', 'B'),
                    {'id': 'lk-1', 'v': self.entry('v'), 'l': self.entry('l'), 'b': 'lk-2', 'x': srv.x, 'y': srv.y,
                     'z': 0, 'bx': 103.5, 'by': 102.5, 'bz': 0, 'tx': 111, 'ty': 102})
        self.assertEqual(self.ev(f'{PA}.stats.granted'), 0)
        self.assertTrue(any('not the owner of lk-1' in s for s in self.lk()), self.lk())


class StepAsideDecisionTests(TDEC.SoloDecisionTests):
    """Extension du cadre de décision (pile complète de test_lk_decisions.py) : un membre de garde s'écarte, attend,
    puis reprend son comportement. Les tests hérités sont retirés ici (ils tournent dans leur propre fichier)."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', STOP_PLACE)
        h.load('solo', AUTHORITY)
        h.load('solo', STEP_ASIDE)
        return h

    def guard_and_mover(self):
        gid = self.mk()
        self.all_members(gid, 4)
        self.assertEqual(self.state(gid, 'm-1')[:2], ('duty', 'guard'))
        guard = self.run_lua(f'return MEMBER_NPC("{gid}", "m-1")')
        mover = self.run_lua(f'return MEMBER_NPC("{gid}", "m-2")')
        # Marche ouverte du demandeur (consigne hors du cadre : gardée ; sur ce banc, aucun corps ne marche).
        self.assertIsNotNone(self.run_lua(f'local z = LivingKnox.Bodies.find("{mover}") return '
                                          f'LivingKnox.Directives.moveTo("{mover}", math.floor(z:getX()) + 6, '
                                          'math.floor(z:getY()), 0, "walk")'))
        return gid, guard, mover

    def order(self, guard, mover):
        x, y = self.run_lua(f'local z = LivingKnox.Bodies.find("{guard}") return math.floor(z:getX()), '
                            'math.floor(z:getY())')
        ok, why = self.run_lua(f'local ok, why = {SA}.order("{guard}", {{ action = "stepAside", to = {{ x = {x}, '
                               f'y = {y + 2}, z = 0 }} }}, "{mover}") return ok, tostring(why)')
        self.assertIs(ok, True, why)
        return x, y

    def test_extension_is_declared_through_the_registry(self):
        found = self.run_lua('for _, x in ipairs(LivingKnox.Decisions.extensions) do if x.id == "stepAside" then '
                             'return x.rules[1].before, x.apply ~= nil, x.leave ~= nil end end return nil')
        self.assertEqual(found, ('threat', True, True))
        self.assertIsNotNone(self.ev('LivingKnox.Decisions.BEHAVIOURS.stepAside'))

    def test_guard_steps_aside_waits_then_resumes_its_duty(self):
        gid, guard, mover = self.guard_and_mover()
        x, y = self.order(guard, mover)
        e = self.run_lua(f'local e = LivingKnox.Directives.get("{guard}") return e.op, e.x, e.y')
        self.assertEqual(e, ('move', x, y + 2))
        # Directive du cadre (jamais « externe ») : l'évaluation suivante prend le comportement « stepAside ».
        self.assertEqual(self.ev(f'LivingKnox.Decisions.state.issued["{guard}"]'),
                         self.run_lua(f'return LivingKnox.Directives.get("{guard}").v'))
        self.all_members(gid, 4)
        self.assertEqual(self.state(gid, 'm-1')[:2], ('stepAside', 'stepAside'))
        # Attente bornée : HOLD_MS passées, l'écart prend fin, le cadre rend son poste au membre.
        self.h.advance_ms(self.ev(f'{SA}.HOLD_MS') + 1)
        self.h.tick(2)
        self.assertIsNone(self.ev(f'{SA}.orders["{guard}"]'))
        self.all_members(gid, 4)
        self.assertEqual(self.state(gid, 'm-1')[:2], ('duty', 'guard'))
        self.assertTrue(any(f'npc {guard}: stepped aside for {mover}' in s and 'timeout' in s
                            for s in self.h.logs('solo')), self.h.logs('solo'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_order_ends_once_the_mover_has_passed(self):
        gid, guard, mover = self.guard_and_mover()
        x, y = self.order(guard, mover)
        self.all_members(gid, 4)
        # Le demandeur passe de l'autre côté de la case quittée (départ noté à l'ordre).
        self.run_lua(f'local o = {SA}.orders["{guard}"] o.start = {{ x = {x} - 1.5, y = {y} + 0.5 }} '
                     f'local z = LivingKnox.Bodies.find("{mover}") HARNESS.place(z, {x} + 2.5, {y} + 0.5, 0) '
                     f'LivingKnox.Directives.moveTo("{mover}", {x} + 6, {y}, 0, "walk")')
        self.h.advance_ms(self.ev(f'{SA}.CHECK_MS') + 1)
        self.h.tick(2)
        self.assertIsNone(self.ev(f'{SA}.orders["{guard}"]'))
        self.assertTrue(any(f'npc {guard}: stepped aside for {mover}' in s and 'passed' in s
                            for s in self.h.logs('solo')), self.h.logs('solo'))

    def test_member_kind_and_combat_read_from_the_decisions(self):
        gid, guard, mover = self.guard_and_mover()
        self.assertEqual(self.ev(f'{PA}.kindOf("{guard}")'), 'guard')
        self.assertIs(self.run_lua(f'return {PA}.canMove("{guard}", LivingKnox.Bodies.find("{guard}"))'), True)
        self.run_lua(f'LivingKnox.Decisions.state.members["{guard}"].b = "fight"')
        self.assertEqual(self.run_lua(f'return {PA}.canMove("{guard}", LivingKnox.Bodies.find("{guard}"))'),
                         (False, 'in combat'))


for _name in dir(TDEC.MultiplayerDecisionTests):
    if _name.startswith('test_'):
        setattr(StepAsideDecisionTests, _name, None)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_source_and_english_logs(self):
        for path in (lua_src(SIGNAL), lua_src(AUTHORITY), lua_src(STEP_ASIDE), SUITE):
            src = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in src.splitlines())
            self.assertTrue(code.isascii(), path.name)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')

    def test_no_closed_list_of_behaviours(self):
        for path in (lua_src(AUTHORITY), lua_src(STEP_ASIDE)):
            code = path.read_text(encoding='utf-8')
            self.assertIsNone(re.search(r'kind\s*==\s*"', code), path.name)

    def test_suite_lists_two_world_tests(self):
        src = SUITE.read_text(encoding='utf-8')
        self.assertIn('RST.suite("lk.passage", { tags = { "world", "server" }', src)
        self.assertEqual(len(re.findall(r'suite\.test\(', src)), 2)


class SuiteListTests(PassageBase):
    def make(self, root=None):
        h = super().make(root)
        h.load('solo', 'shared/RST/suites/RST_LKPassage.lua')
        return h

    def test_suite_is_listed(self):
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.passage", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.passage')
        self.assertIsNone(listed.error)
        self.assertEqual(listed.count, 2)


if __name__ == '__main__':
    unittest.main()
