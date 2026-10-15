"""Tests hors jeu des consignes de déplacement Living Knox (LK02-T07) : LK_Directives.lua (autorité),
LK_Executor.lua (machine qui simule le corps), LK_Presentation.lua (autres clients).

    python RadioSurvivor/tests/test_lk_directives.py

Banc tests/harness.py (serveur et deux clients, ou solo) et doublures de test_lk_bodies.py, test_lk_guard.py et
test_lk_anim.py, complétées ici. Les doublures reproduisent le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API
réelle, seulement la logique :
- pathToLocation(int, int, int) (IsoGameCharacter.java:5962-5966 -> pathToAux 5927-5958) : client et solo, ligne
  dégagée -> bPathfind faux et setMoving(true), sinon bPathfind vrai et setMoving(false) ; serveur : jamais bPathfind
  (CanUsePathfindState faux), setMoving(ligne dégagée) seulement ; setVariable d'un zombie sans effet sur le serveur ;
- marche (STEP, appelée par le banc sur la copie qui simule) : état pathfind (bPathfind vrai) -> avance ; walktoward
  (bMoving sans bPathfind) -> avance, sauf corps useless renvoyé au repos (WalkTowardState.java:56) ; arrivée ou échec
  -> bPathfind et bMoving effacés (PathFindState.java:51-71) ; la position est recopiée sur les autres machines comme
  le ferait le paquet zombie ;
- setDirectionAngle / getDirectionAngle en degrés (IsoGameCharacter.java:2626-2635) ;
- propriétaire : isRemoteZombie / getOwner / getOwnerPlayer du banc (NetworkZombieComponent.java:23,
  NetworkZombieManager.java:137-181).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list, LUA, DEV_LUA  # noqa: E402
from test_lk_anim import AnimBase  # noqa: E402

DIRECTIVES = 'server/LivingKnox/LK_Directives.lua'
EXECUTOR = 'client/LivingKnox/LK_Executor.lua'
PRESENTATION = 'client/LivingKnox/LK_Presentation.lua'
MOD_FILES = [LUA / DIRECTIVES, LUA / EXECUTOR, LUA / PRESENTATION]
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKExecutor.lua',
             DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKFarm.lua',
             DEV_LUA / 'client' / 'RST' / 'RST_LKBodiesClient.lua',
             DEV_LUA / 'server' / 'RST' / 'RST_LKBodiesServer.lua']

DIR_DOUBLES = r'''
local H = HARNESS
local Z = H.classes.IsoZombie
LINE_CLEAR, PATH_FAILS, PATHS = true, false, {}
local function bool(v, what)
    if type(v) ~= 'boolean' then error('No implementation found for ' .. what .. ' with argument ' .. tostring(v), 3) end
    return v
end
local function setPf(zb, v)
    local vars = rawget(zb, 'animVars')
    if not vars then vars = {}; zb.animVars = vars end
    vars.bpathfind = v
end
function Z:pathToLocation(x, y, z)
    H.num(x, 'pathToLocation'); H.num(y, 'pathToLocation'); H.num(z, 'pathToLocation')
    self.goal = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
    PATHS[#PATHS + 1] = string.format('%s:%d,%d@%.2f,%.2f', H.name, self.goal.x, self.goal.y, self.x, self.y)
    if isServer() then
        self.moving = LINE_CLEAR
    elseif LINE_CLEAR then
        setPf(self, false); self.moving = true
    else
        setPf(self, true); self.moving = false
    end
end
function Z:setMoving(b) self.moving = bool(b, 'setMoving') end
function Z:setDirectionAngle(a) H.num(a, 'setDirectionAngle'); self.angle = a end
function Z:getDirectionAngle() return self.angle or 0 end
function Z:getCurrentStateName() return 'idle' end
-- Un pas de marche de la copie simulée sur cette machine. Rend l'état.
function STEP(zid, speed)
    local zb = H.zombies[zid]
    if zb == nil or zb.goal == nil then return 'none' end
    local pf = zb:getVariableBoolean('bPathfind')
    if pf and PATH_FAILS then
        setPf(zb, false); zb.moving = false
        return 'failed'
    end
    if not pf and zb.moving and zb.useless then
        zb.moving = false
        return 'blocked'
    end
    if not pf and not zb.moving then return 'idle' end
    local tx, ty = zb.goal.x + 0.5, zb.goal.y + 0.5
    local dx, dy = tx - zb.x, ty - zb.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= speed then
        H.place(zb, tx, ty, zb.z)
        setPf(zb, false); zb.moving = false
        return 'reached'
    end
    H.place(zb, zb.x + dx / d * speed, zb.y + dy / d * speed, zb.z)
    return 'walking'
end
'''

TARGET = (111, 102, 0)


class DirectiveBase(AnimBase):
    def make(self, root=None):
        h = super().make(root)
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in names:
            h.load(m, DIR_DOUBLES)
            h.load(m, DIRECTIVES)
            if m != 'server':
                h.load(m, EXECUTOR)
                h.load(m, PRESENTATION)
        if self.mode == 'mp':
            h.move_player('B', 96, 108, 0)   # dans le rayon d'envoi du PNJ (102, 102), hors de sa case libre
        return h

    def d(self, code, m=None):
        return self.ev('LivingKnox.Directives.' + code, m)

    def entry(self, field, npc='lk-1'):
        return self.ev(f'LivingKnox.Directives.entries["{npc}"].{field}')

    def sim(self, zid):
        return 'solo' if self.mode == 'solo' else self.h.owners.get(zid, 'server')

    def walk(self, zid, ticks, speed=0.05, until=None):
        """ticks images : tick, pas de marche sur la copie qui simule, position recopiée, réseau livré. Rend la liste
        des distances au centre de la case visée."""
        dists = []
        for _ in range(ticks):
            self.h.tick(1)
            m = self.sim(zid)
            self.h.eval(m, f'STEP({zid}, {speed})')
            zb = self.h.zombie(m, zid)
            if self.mode == 'mp':
                self.h.move_zombie(zid, zb.x, zb.y)
                self.h.pump()
            dists.append(((zb.x - TARGET[0] - 0.5) ** 2 + (zb.y - TARGET[1] - 0.5) ** 2) ** 0.5)
            if until and until():
                break
        return dists

    def paths(self, m):
        return lua_list(self.h.eval(m, 'PATHS'))

    def done(self):
        return lambda: self.ev('LivingKnox.Directives.entries["lk-1"] ~= nil and '
                               'LivingKnox.Directives.entries["lk-1"].done') is True

    def exec_pass(self):
        self.h.tick(self.ev('LivingKnox.Executor.EXEC_EVERY', 'A' if self.mode == 'mp' else 'solo'))

    def handover(self):
        """Images au plus entre un changement de propriétaire et la reprise : passage du serveur (bail), livraison,
        passage de l'exécutant (LK03-T01)."""
        return self.ev('LivingKnox.Directives.SLOW_EVERY') + self.ev('LivingKnox.Executor.EXEC_EVERY', 'A') + 1


class MultiplayerDirectiveTests(DirectiveBase):
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

    def msgs(self, command):
        return [m for m in self.h.pending() if m['module'] == 'LivingKnox' and m['command'] == command]

    def move(self, gesture='walk'):
        return self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]}, "{gesture}")')

    def test_versioned_directive_executed_by_the_owner_only_until_arrival(self):
        zid = self.ready('A')
        self.assertEqual(self.move(), 1)
        states = self.msgs('dirState')
        self.assertEqual(sorted(m['to'] for m in states), ['A', 'B'])
        sent = dict(states[0]['args']['d']['lk-1'])
        self.assertIsInstance(sent.pop('r'), (int, float))
        # Bail 1 donné au propriétaire A (exécutant désigné o).
        self.assertEqual(sent, {'v': 1, 'l': 1, 'o': 'A', 'op': 'move', 'x': 111, 'y': 102, 'z': 0, 'g': 'walk',
                                'done': False, 's': 'issued'})
        sent_r = {m['to']: m['args']['d']['lk-1']['r'] for m in states}
        self.h.pump()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Executor.remote.r["lk-1"]'), sent_r[c])
        self.relay_tick()                                # geste : relais à l'image suivante du serveur (LK03-T05)
        self.h.pump()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")'), 'walk')
        dists = self.walk(zid, 400, until=self.done())
        self.assertIs(self.entry('done'), True)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        # Seul A a cherché un chemin, depuis la position de départ, en mode pathfind (useless gardé, aucun trajet).
        self.assertEqual(self.paths('A'), ['A:111,102@102.50,102.50'])
        self.assertEqual(self.paths('B'), [])
        self.assertEqual(self.paths('server'), [])
        self.assertIs(self.h.zombie('A', zid).useless, True)
        self.assertIs(self.ev('LivingKnox.ZombieGuard.isTravelling("lk-1")'), False)
        self.assertLessEqual(dists[-1], self.d('ARRIVE'))
        self.assertTrue(all(b <= a + 1e-9 for a, b in zip(dists, dists[1:])))
        # Geste : walk en route, idle à l'arrivée, chez les deux clients.
        self.h.pump()
        self.relayed()
        self.slow()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        # Rapports acceptés, poses relayées à B (orientation appliquée à l'arrêt, position jamais touchée).
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertGreaterEqual(self.d('stats.accepted'), 3)  # moving au départ, au moins un en route, arrived
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").s'), 'arrived')
        self.h.eval('A', f'HARNESS.zombies[{zid}]:setDirectionAngle(37)')  # orientation finale du propriétaire
        self.run_lua('LivingKnox.Directives.face("lk-1", "S")')
        self.h.pump()
        self.walk(zid, 30)
        self.assertEqual(self.entry('s'), 'faced')
        self.assertEqual(self.h.zombie('A', zid).angle, 90)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").s'), 'faced')
        self.assertEqual(self.h.zombie('B', zid).angle, 90)   # copie distante : pose appliquée une fois
        self.assertEqual(self.h.eval('A', 'LivingKnox.Presentation.stats.applied'), 0)  # copie simulée : jamais
        lines = [line for line in self.lk() if 'move #1 arrived' in line]
        self.assertEqual(len(lines), 1, self.lk())

    def test_reports_from_a_non_owner_or_implausible_are_refused(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 40)
        accepted = self.d('stats.accepted')
        x, y = self.h.zombie('server', zid).x, self.h.zombie('server', zid).y

        def report(sender, **kw):
            args = {'id': 'lk-1', 'v': 1, 'l': self.entry('l'), 's': 'moving', 'x': x, 'y': y, 'z': 0, 'a': 0,
                    'n': 1000, 't': 0}
            args.update(kw)
            self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', sender),
                        args)

        report('B', s='arrived', x=111.5, y=102.5)                   # B ne simule pas le corps
        report('A', x=x + 30, n=1001)                                 # loin de la copie du serveur
        report('A', s='arrived', n=1002)                              # arrivée annoncée loin de la case visée
        report('A', s='stopped', n=1003)                              # état sans rapport avec la consigne
        report('A', v=0, n=1004)                                      # consigne périmée : ignorée sans erreur
        stale = self.d('stats.stale')
        report('A', v=0, s='stopped', n=1005)                         # stop remplacé livré après le move : course
        self.assertEqual(self.d('stats.stale'), stale + 1)
        self.assertEqual(sum('state stopped for move' in line for line in self.lk()), 1, self.lk())  # n=1003 seul
        report('A', n=1)                                              # plus ancien que le dernier rapport de A
        self.assertEqual(self.d('stats.rejected'), 4)
        self.assertEqual(self.d('stats.accepted'), accepted)
        self.assertIs(self.entry('done'), False)
        warns = [line for line in self.lk() if 'refused' in line]
        self.assertTrue(any('from B refused: not the owner (owner A)' in w for w in warns), warns)
        self.assertTrue(any('far from the body' in w for w in warns), warns)
        self.assertTrue(any('not at the target' in w for w in warns), warns)
        # Distance parcourue bornée : saut de 30 cases entre deux rapports rapprochés, copie du serveur suivie.
        self.h.move_zombie(zid, x + 0, y + 0)
        report('A', n=2000)
        self.h.move_zombie(zid, x + 30 if x + 30 < 140 else x - 30, y)
        self.h.advance_ms(100)
        report('A', x=self.h.zombie('server', zid).x, n=2001)
        self.assertTrue(any('too fast' in w for w in self.lk() if 'refused' in w), self.lk())
        # Une ligne WARN par (expéditeur, raison) et par minute.
        report('B', s='arrived', x=111.5, y=102.5, n=3000)
        self.assertEqual(len([w for w in self.lk() if 'from B refused: not the owner' in w]), 1)

    def test_owner_transfer_midway_resumes_from_the_current_position(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        before = self.walk(zid, 90)
        mid = (self.h.zombie('server', zid).x, self.h.zombie('server', zid).y)
        self.assertTrue(102.5 + 2 < mid[0] < 111, mid)
        self.h.set_owner(zid, 'B')
        a_paths = len(self.paths('A'))
        after = self.walk(zid, self.handover())
        # B reprend dans la passe suivante, depuis la position actuelle, vers la même case ; A cesse.
        self.assertEqual(self.paths('B'), [f'B:111,102@{mid[0]:.2f},{mid[1]:.2f}'])
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.runs["lk-1"]'))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.released'), 1)
        rest = self.walk(zid, 400, until=self.done())
        self.assertEqual(len(self.paths('A')), a_paths)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        dists = before + after + rest
        self.assertTrue(all(b <= a + 1e-9 for a, b in zip(dists, dists[1:])), 'distance to the target increased')
        self.assertTrue(any('move #1 now executed by B (was A)' in line for line in self.lk()), self.lk())
        # Rapport tardif de l'ancien propriétaire : refusé.
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'A'),
                    {'id': 'lk-1', 'v': 2, 's': 'moving', 'x': 111.5, 'y': 102.5, 'z': 0, 'n': 99999})
        self.assertGreaterEqual(self.d('stats.rejected') + self.d('stats.stale'), 1)

    def test_unordered_delivery_keeps_the_newest_directive_and_pose(self):
        zid = self.ready('A')
        self.move()
        self.d('stop("lk-1")')
        self.assertEqual(len(self.msgs('dirState')), 4)  # deux tables, deux clients
        self.h.pump(order='lifo')                        # la plus récente arrive d'abord
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Executor.remote.d["lk-1"].op'), 'stop')
            self.assertEqual(self.h.eval(c, 'LivingKnox.Executor.remote.d["lk-1"].v'), 2)
        self.walk(zid, 12)
        self.assertEqual(self.entry('s'), 'stopped')
        self.assertEqual(self.paths('A'), [])            # le "move" périmé n'a jamais été exécuté
        # Poses : une plus ancienne, livrée après une plus récente, est ignorée.
        pr = self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").pr')
        r = self.h.eval('B', 'LivingKnox.Presentation.revs["lk-1"]')
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'animState',
                    {'d': {'lk-1': {'r': r + 100, 'g': 'walk', 'p': {'pr': pr - 1, 'v': 1, 's': 'moving', 'a': 0,
                                                                    'x': 0, 'y': 0, 'z': 0, 't': 0, 'ts': 0}}}})
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").pr'), pr)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.stats.older'), 1)
        # Table de consignes plus ancienne : ignorée.
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'dirState', {'rev': 0})
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.remote.d["lk-1"].op'), 'stop')

    def test_client_arriving_late_receives_directives_and_poses(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 80)
        self.h.load('B', 'LivingKnox.Executor.remote = { rev = -1, d = {} }\nLivingKnox.Presentation.poses = {}\n'
                         'LivingKnox.Presentation.revs = {}\nLivingKnox.Anim.remote = { r = {}, g = {} }\n'
                         'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                         'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual([m['from'] for m in self.h.pending() if m['command'] == 'guardHello'], ['B'])
        self.h.pump(limit=1)
        answers = [(m['to'], m['command']) for m in self.h.pending()]
        self.assertIn(('B', 'dirState'), answers)
        self.relay_tick()                                # gestes et poses : relais, image suivante (LK03-T05)
        answers = [(m['to'], m['command']) for m in self.h.pending()]
        self.assertIn(('B', 'animState'), answers)
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"].v'), 1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").s'), 'moving')
        self.assertEqual(self.paths('B'), [])            # B ne simule pas : il n'exécute rien

    def test_relay_delay_measured_with_the_synced_server_clock(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 70)
        self.assertGreaterEqual(self.h.eval('B', 'LivingKnox.Presentation.stats.samples'), 1)
        self.assertGreaterEqual(self.h.eval('B', 'LivingKnox.Presentation.stats.maxDelay'), 0)
        self.h.set_clock_synced('B', False)              # avant synchronisation : échantillon ignoré
        samples = self.h.eval('B', 'LivingKnox.Presentation.stats.samples')
        self.walk(zid, 70)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Presentation.stats.samples'), samples)

    # ---------------------------------------------------------------- corps sans propriétaire (LK03-T04)

    def assert_at_rest(self, zid, start):
        srv = self.h.zombie('server', zid)
        self.assertEqual((srv.x, srv.y), start)                      # jamais déplacé, aucun téléport
        self.assertIs(srv.moving, False)
        self.assertIs(srv.useless, True)                             # trajet fermé : useless rendu par la garde
        self.assertIs(self.ev('LivingKnox.ZombieGuard.isTravelling("lk-1")'), False)
        self.h.pump()
        self.slow()
        for c in ('A', 'B'):                                         # geste neutre chez les clients qui le voient
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")'), 'idle')

    def test_server_owned_body_suspends_its_move_at_rest_until_a_client_owns_it(self):
        zid = self.ready('server')
        self.assertEqual(self.move('run'), 1)
        self.h.pump()
        self.slow()
        srv = self.h.zombie('server', zid)
        start = (srv.x, srv.y)
        self.assertIsNotNone(self.entry('suspended'))
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.entry('o'), 'server')
        self.walk(zid, 400)                                          # 6,4 s : rien n'est exécuté
        self.assert_at_rest(zid, start)
        self.assertEqual(self.paths('server') + self.paths('A') + self.paths('B'), [])
        self.assertEqual(self.d('stats.suspended'), 1)
        # Suspendue plus longtemps que le délai maximal d'un trajet : ni close, ni perdue.
        self.h.advance_ms(self.d('TRIP_TIMEOUT_MS') + 1000)
        self.slow()
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.entry('v'), 1)
        # Un client prend la main : même consigne, geste rétabli, chemin depuis la position actuelle, une arrivée.
        self.h.set_owner(zid, 'A')
        self.h.tick(1)
        self.h.pump()
        self.assertIsNone(self.entry('suspended'))
        self.assertEqual(self.entry('o'), 'A')
        self.relayed()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")'), 'run')
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(self.entry('v'), 1)
        self.assertEqual(self.paths('A'), ['A:111,102@%.2f,%.2f' % start])
        self.assertEqual(self.d('stats.unsuspended'), 1)
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertTrue(any('move #1 resumed by A after' in line for line in self.lk()), self.lk())
        self.assertEqual(len([line for line in self.lk() if 'move #1 arrived' in line]), 1)

    def test_owner_lost_mid_walk_suspends_then_the_next_owner_resumes_from_where_it_stopped(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 60)
        srv = self.h.zombie('server', zid)
        self.assertGreater(srv.x, 103)                                # en route
        self.h.set_owner(zid, 'server')                               # plus aucun client proche du corps
        self.h.tick(1)
        self.h.pump()
        self.assertIsNotNone(self.entry('suspended'))
        start = (srv.x, srv.y)
        self.walk(zid, 300)
        self.assert_at_rest(zid, start)
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.paths('A'), ['A:111,102@102.50,102.50'])  # l'ancien ne relance rien
        self.h.set_owner(zid, 'B')
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual(self.paths('B'), ['B:111,102@%.2f,%.2f' % start])
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertEqual(len([line for line in self.lk() if 'move #1 arrived' in line]), 1)

    def test_server_owned_body_stop_and_face_wait_for_a_client(self):
        zid = self.ready('server')
        srv = self.h.zombie('server', zid)
        angle = srv.angle
        self.d('face("lk-1", "N")')
        self.h.pump()
        self.slow()
        self.assertEqual(self.entry('s'), 'issued')                   # suspendue, pas appliquée par le serveur
        self.assertIsNotNone(self.entry('suspended'))
        self.assertEqual(srv.angle, angle)
        self.h.set_owner(zid, 'A')
        self.walk(zid, 30)
        self.assertEqual(self.entry('s'), 'faced')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(self.h.zombie('A', zid).angle, 270)
        self.h.set_owner(zid, 'server')
        self.d('stop("lk-1")')
        self.slow()
        self.assertEqual(self.entry('s'), 'issued')
        self.h.set_owner(zid, 'B')
        self.walk(zid, 30)
        self.assertEqual(self.entry('s'), 'stopped')
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual(self.paths('A') + self.paths('B') + self.paths('server'), [])

    def test_path_failure_retries_then_fails(self):
        zid = self.ready('A')
        self.h.load('A', 'PATH_FAILS = true')
        self.move()
        self.h.pump()
        self.walk(zid, 200, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        # LK04-T05 : essais épuisés -> point de déblocage (1 chemin), puis chemin relancé vers l'étape (1), puis échec.
        self.assertEqual(len(self.paths('A')), 1 + self.ev('LivingKnox.Executor.MAX_RETRIES', 'A') + 2)
        self.assertEqual(self.entry('why'), 'stuck')
        self.h.pump()
        self.relayed()
        self.slow()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.assertTrue(any('move #1 failed' in line and 'no path' in line for line in self.lk()), self.lk())

    def test_forgotten_npc_drops_its_directive_and_execution(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 20)
        self.run_lua('LivingKnox.Bodies.despawn("lk-1", true)')
        self.slow()
        self.h.pump()
        self.assertIsNone(self.ev('LivingKnox.Directives.entries["lk-1"]'))
        self.exec_pass()
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.remote.d["lk-1"]'))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.runs["lk-1"]'))

    def test_validation_and_client_refusal(self):
        self.ready('A')
        self.assertIsNone(self.ev('(LivingKnox.Directives.moveTo("lk-9", 105, 102, 0))'))
        why = self.ev('select(2, LivingKnox.Directives.moveTo("lk-1", 190, 102, 0))')
        self.assertIn('squares away (max 60)', why)
        why = self.ev('select(2, LivingKnox.Directives.moveTo("lk-1", 105, 102, 0, "aim"))')
        self.assertIn('walk, run or crouch', why)
        self.run_lua('getCell():getGridSquare(105, 102, 0).blocked = true')
        why = self.ev('select(2, LivingKnox.Directives.moveTo("lk-1", 105, 102, 0))')
        self.assertIn('not walkable', why)
        why = self.ev('select(2, LivingKnox.Directives.face("lk-1", "up"))')
        self.assertIn('direction must be', why)
        self.assertEqual(self.d('angleOf("nw")'), 225)
        self.assertEqual(self.d('angleOf(-90)'), 270)
        why = self.h.eval('A', 'select(2, LivingKnox.Directives.moveTo("lk-1", 105, 102, 0))')
        self.assertIn('not the authority', why)
        self.assertEqual(self.h.pending(), [])


    # ---------------------------------------------------------------- envoi aux proches, bail, réémission (LK03-T01)

    def reset_client(self, c):
        """Client c qui se reconnecte : état Lua neuf (consignes, exécutions, liste des corps), puis guardHello."""
        self.h.load(c, 'LivingKnox.Executor.remote = { rev = -1, d = {}, r = {} }\nLivingKnox.Executor.runs = {}\n'
                       'LivingKnox.Executor.history = {}\nLivingKnox.Executor.copies = {}\n'
                       'LivingKnox.Executor.asked = {}\nLivingKnox.Executor.state.n = 0\n'
                       'LivingKnox.Executor.hands = {}\nLivingKnox.Executor.handR = {}\n'
                       'LivingKnox.Executor.claimed = {}\nLivingKnox.Executor.waitLocal = {}\n'
                       'LivingKnox.Presentation.poses = {}\n'
                       'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                       'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertIn(('guardHello', c), [(m['command'], m['from']) for m in self.h.pending()])

    def arrivals(self):
        return [line for line in self.lk() if 'move #1 arrived' in line]

    def test_only_nearby_clients_receive_and_a_player_arriving_gets_it(self):
        zid = self.ready('A')
        self.h.move_player('B', 0, 0, 0)               # B à 102 cases : hors du rayon (100)
        self.move()
        self.assertEqual([m['to'] for m in self.msgs('dirState')], ['A'])
        self.h.pump()
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"]'))
        self.walk(zid, 5)
        # B entre dans le rayon : la consigne lui est envoyée au passage suivant du serveur, sans renvoi à A.
        self.h.move_player('B', 96, 108, 0)
        self.slow()
        self.assertEqual([m['to'] for m in self.msgs('dirState')], ['B'])
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"].v'), 1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"].o'), 'A')
        self.walk(zid, 30)
        self.assertEqual(self.paths('B'), [])          # B n'est ni propriétaire ni exécutant désigné
        # B ressort du rayon : il oublie la consigne ({ gone }).
        self.h.move_player('B', 0, 0, 0)
        self.slow()
        gone = self.msgs('dirState')
        self.assertEqual([m['to'] for m in gone], ['B'])
        self.assertIs(gone[0]['args']['d']['lk-1']['gone'], True)
        self.h.pump()
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"]'))
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(len(self.arrivals()), 1)
        self.assertGreaterEqual(self.d('stats.reemitted'), 1)

    def test_duplicate_and_out_of_order_deliveries_never_execute_twice(self):
        zid = self.ready('A')
        self.move()
        first = [m for m in self.msgs('dirState') if m['to'] == 'A']
        self.h.pump()
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        reports = self.h.eval('A', 'LivingKnox.Executor.stats.reports')
        # Doublon de la première consigne, livré après la fin : ignoré (r déjà vu), rien n'est rejoué.
        for m in first:
            self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'dirState', m['args'])
        self.exec_pass()
        self.assertGreaterEqual(self.h.eval('A', 'LivingKnox.Executor.stats.older'), 1)
        # Envoi plus récent (r) d'une consigne plus ancienne (v), puis de la même consigne rouverte au même bail :
        # jamais commencés (périmée ; déjà menée ici jusqu'au bout).
        lease = self.entry('l')
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'dirState',
                    {'rev': 900, 'd': {'lk-1': {'r': 900, 'v': 0, 'l': lease, 'o': 'A', 'op': 'move', 'x': 105,
                                                 'y': 102, 'z': 0, 'g': 'walk', 'done': False, 's': 'issued'}}})
        self.exec_pass()
        self.assertGreaterEqual(self.h.eval('A', 'LivingKnox.Executor.stats.stale'), 1)
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'dirState',
                    {'rev': 901, 'd': {'lk-1': {'r': 901, 'v': 1, 'l': lease, 'o': 'A', 'op': 'move', 'x': 111,
                                                 'y': 102, 'z': 0, 'g': 'walk', 'done': False, 's': 'moving'}}})
        self.exec_pass()
        self.assertEqual(len(self.paths('A')), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.reports'), reports)
        self.assertEqual(len(self.arrivals()), 1)

    def test_new_owner_waits_for_its_lease_and_takes_over_a_step_directive_once(self):
        zid = self.ready('A')
        self.plants([(106, 102)])
        self.move()
        self.h.pump()
        for _ in range(900):
            self.track(zid, 1)
            if self.entry('k') == 2:
                break
        self.walk(zid, 3)
        a_paths = len(self.paths('A'))
        self.h.set_owner(zid, 'B')
        # B simule le corps mais n'est pas encore l'exécutant désigné : il attend le bail du serveur.
        self.h.eval('B', 'LivingKnox.Executor.pass()')
        self.assertEqual(self.paths('B'), [])
        self.assertGreaterEqual(self.h.eval('B', 'LivingKnox.Executor.stats.waiting'), 1)
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        self.assertEqual(self.entry('o'), 'B')
        self.assertEqual(self.entry('l'), 2)
        self.assertTrue(any('move #1 leased to B (was A, lease 2)' in line for line in self.lk()), self.lk())
        self.assertEqual(sorted(m['to'] for m in self.msgs('dirState')), ['A', 'B'])
        self.walk(zid, self.handover())
        self.assertEqual([p.split('@')[0] for p in self.paths('B')], ['B:109,99'])   # étape publiée, pas le point 1
        self.track(zid, 900)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual(len(self.paths('A')), a_paths)                               # A n'a plus rien lancé
        self.assertEqual(len(self.arrivals()), 1)
        self.assertEqual(self.d('stats.rejected'), 0)
        # Rapport tardif de l'ancien bail (A, en marche) : ignoré sans avertissement.
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'A'),
                    {'id': 'lk-1', 'v': 1, 'l': 1, 's': 'moving', 'x': 111.5, 'y': 102.5, 'z': 0, 'n': 99999})
        self.assertEqual([line for line in self.lk() if 'refused' in line], [])

    def test_final_report_of_the_previous_lease_closes_the_directive_once(self):
        zid = self.ready('A')
        self.d('face("lk-1", "S")')
        self.h.pump()
        self.h.eval('A', 'LivingKnox.Executor.pass()')                 # A se tourne et rapporte (message en vol)
        # (demandes d'entretien dirAsk / dirClaim d'une copie vue pour la première fois : hors sujet ici)
        self.assertEqual([m['command'] for m in self.h.pending() if m['command'] not in ('dirAsk', 'dirClaim')],
                         ['dirReport'])
        self.h.set_owner(zid, 'B')
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')     # bail donné à B avant le rapport de A
        self.assertEqual(self.entry('o'), 'B')
        self.h.pump()                                                   # rapport de A, puis consignes
        self.assertEqual(self.entry('s'), 'faced')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(self.d('stats.graced'), 1)
        self.assertTrue(any('face #1 final report faced from A (previous lease 1) accepted after the transfer to B'
                            in line for line in self.lk()), self.lk())
        self.exec_pass()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.stats.started'), 0)   # rien à reprendre
        self.assertEqual(self.d('stats.rejected'), 0)
        # Hors délai de grâce, un rapport final de l'ancien bail n'est plus accepté.
        self.d('face("lk-1", "N")')
        self.h.pump()
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        lease = self.entry('l')
        self.h.set_owner(zid, 'A')
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        self.h.advance_ms(self.d('LEASE_GRACE_MS') + 1)
        srv = self.h.zombie('server', zid)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'B'),
                    {'id': 'lk-1', 'v': 2, 'l': lease, 's': 'faced', 'x': srv.x, 'y': srv.y, 'z': 0, 'n': 7})
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.d('stats.graced'), 1)

    def test_reconnection_of_the_executor_neither_loses_nor_repeats_the_directive(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 60)
        # A se déconnecte : le moteur donne aussitôt le corps à B (clearTargetAuth), bail à B, B reprend.
        self.h.set_owner(zid, 'B')
        self.walk(zid, self.handover())
        self.assertEqual(self.entry('o'), 'B')
        self.assertEqual(len(self.paths('B')), 1)
        self.walk(zid, 20)
        # A revient (état Lua neuf) : consigne reçue, exécutant désigné B, A n'exécute rien.
        self.reset_client('A')
        self.h.pump()
        self.slow()
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.remote.d["lk-1"].o'), 'B')
        a_paths = len(self.paths('A'))
        # Le corps repasse à A (nouveau bail) : A reprend depuis la position actuelle, ses rapports repartent de 1.
        self.h.set_owner(zid, 'A')
        here = self.h.zombie('server', zid).x
        self.walk(zid, self.handover())
        resumed = self.paths('A')[a_paths:]
        self.assertEqual(len(resumed), 1, resumed)       # une seule reprise, vers la même case, sans retour
        self.assertTrue(resumed[0].startswith('A:111,102@'), resumed)
        self.assertGreaterEqual(float(resumed[0].split('@')[1].split(',')[0]), here)
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(len(self.arrivals()), 1)
        self.assertEqual(self.d('stats.rejected'), 0)

    def test_quick_reconnection_keeps_the_owner_with_a_new_lease(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 60)
        lease = self.entry('l')
        self.walk(zid, 60)                         # rapports de A : numéros au-delà de ceux d'une session neuve
        # A se reconnecte en restant propriétaire (le serveur n'a pas vu de changement) : nouveau bail pour A.
        self.reset_client('A')
        self.h.pump()
        self.assertEqual(self.entry('o'), 'A')
        self.assertGreater(self.entry('l'), lease)
        self.assertTrue(any('leased to A after A joined' in line for line in self.lk()), self.lk())
        here = self.h.zombie('A', zid).x
        self.slow()
        self.walk(zid, 400, until=self.done())
        paths = self.paths('A')
        self.assertEqual(len(paths), 2, paths)           # départ, puis reprise sous le nouveau bail
        self.assertGreaterEqual(float(paths[1].split('@')[1].split(',')[0]), here)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(len(self.arrivals()), 1)
        self.assertEqual(self.d('stats.rejected'), 0)

    def test_body_reappearance_resends_the_directive(self):
        zid = self.ready('A')
        self.move()
        self.h.pump()
        self.walk(zid, 20)
        # Serveur : corps rechargé (nouvel onlineId) -> réémission à tous les destinataires.
        self.h.load('server', f'HARNESS.zombies[{zid}].onlineID = 4242')
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        self.assertEqual(sorted(m['to'] for m in self.msgs('dirState')), ['A', 'B'])
        self.h.load('server', f'HARNESS.zombies[{zid}].onlineID = {zid}')
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        self.h.pump()
        # Client A : copie recréée (nouvel objet) -> demande dirAsk, réponse à A seul, reprise de la même consigne.
        srv = self.h.zombie('server', zid)
        self.h.advance_ms(self.ev('LivingKnox.Executor.ASK_MS', 'A'))   # première demande (copie vue) déjà ancienne
        asked = self.d('stats.asked')
        self.h.load('A', f'HARNESS.removeZombie({zid})\nNET_CREATE({zid}, {srv.x}, {srv.y}, {srv.z}, "A", 0, true)')
        asks = []
        for _ in range(120):
            self.h.tick(1)
            asks += [m for m in self.h.pending() if m['command'] == 'dirAsk']
            if asks:
                break
        self.assertEqual(len(asks), 1, self.h.pending())
        self.assertEqual(asks[0]['from'], 'A')
        self.assertEqual(list(asks[0]['args']['ids'].values()) if isinstance(asks[0]['args']['ids'], dict)
                         else asks[0]['args']['ids'], ['lk-1'])
        self.h.pump(limit=len(self.h.pending()))
        replies = [m for m in self.msgs('dirState')]
        self.assertEqual([m['to'] for m in replies], ['A'])
        self.assertEqual(replies[0]['args']['d']['lk-1']['v'], 1)
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(len(self.arrivals()), 1)
        self.assertGreaterEqual(self.h.eval('A', 'LivingKnox.Executor.stats.resumed'), 1)
        self.assertEqual(self.d('stats.asked'), asked + 1)

    # ---------------------------------------------------------------- plantes et feux de camp (LK04-T06)

    def hazard_pass(self):
        """Ticks d'un passage plantes et feux de camp de LK_Bodies (HAZARD_EVERY tranches de SCAN_EVERY images)."""
        self.h.tick(self.ev('LivingKnox.Bodies.SCAN_EVERY * LivingKnox.Bodies.HAZARD_EVERY'))

    def near(self, x, y, r=1):
        return self.ev(f'(LivingKnox.Bodies.hazardNear({x}, {y}, 0, {r}))')

    def test_target_on_a_plant_is_shifted_and_refused_inside_a_field(self):
        self.ready('A')
        self.run_lua('getCell():getGridSquare(111, 102, 0).plant = { state = "seeded" }')
        self.assertEqual(self.move(), 1)
        x, y = self.entry('x'), self.entry('y')
        self.assertEqual(max(abs(x - 111), abs(y - 102)), 3, (x, y))   # la plus proche à 2 cases de marge
        self.assertIsNone(self.near(x, y, 2))
        self.assertTrue(any('move target 111,102,0 shifted to' in line and 'farming plant at 111,102' in line
                            for line in self.lk()), self.lk())
        # Champ : une plante toutes les 2 cases, chaque case est voisine d'une plante -> refus.
        self.run_lua('for x = 103, 119, 2 do for y = 94, 110, 2 do '
                     'getCell():getGridSquare(x, y, 0).plant = true end end')
        why = self.ev('select(2, LivingKnox.Directives.moveTo("lk-1", 111, 102, 0))')
        self.assertIn('next to a farming plant', why)
        self.assertIn('no safe square within 3', why)
        self.assertEqual(self.entry('v'), 1)                           # aucune consigne émise

    # ---------------------------------------------------------------- points de passage (LK05-T12)

    def plants(self, squares):
        for x, y in squares:
            self.run_lua(f'getCell():getGridSquare({x}, {y}, 0).plant = {{ state = "seeded" }}')

    def steps(self, npc='lk-1'):
        w = self.ev(f'LivingKnox.Directives.entries["{npc}"].w')
        return [(p.x, p.y) for p in lua_list(w)] if w is not None else None

    def track(self, zid, ticks, speed=0.05):
        """Comme walk, en relevant la case du corps sur la machine qui simule à chaque image."""
        squares = []
        for _ in range(ticks):
            self.h.tick(1)
            m = self.sim(zid)
            self.h.eval(m, f'STEP({zid}, {speed})')
            zb = self.h.zombie(m, zid)
            if self.mode == 'mp':
                self.h.move_zombie(zid, zb.x, zb.y)
                self.h.pump()
            squares.append((int(zb.x // 1), int(zb.y // 1)))
            if self.done()():
                break
        return squares

    def assert_segments_clear(self, start, steps, target=TARGET):
        """Chaque segment (départ, points, destination) hors de la zone dangereuse (marge 1)."""
        pts = [start] + [(x + 0.5, y + 0.5) for x, y in steps] + [(target[0] + 0.5, target[1] + 0.5)]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = self.ev(f'(LivingKnox.Directives.hazardsOnLine({ax}, {ay}, {bx}, {by}, 0, 1))')
            self.assertEqual(n, 0, f'segment {ax},{ay} -> {bx},{by} crosses the hazard zone')

    def assert_never_in_zone(self, squares, plants):
        for sx, sy in squares:
            for px, py in plants:
                self.assertGreater(max(abs(sx - px), abs(sy - py)), 1, f'body on {sx},{sy} next to the plant {px},{py}')

    def test_straight_line_across_a_plant_is_split_into_steps_around_it(self):
        zid = self.ready('A')
        self.plants([(106, 102)])
        self.assertEqual(self.move(), 1)
        self.assertEqual((self.entry('x'), self.entry('y')), (111, 102))  # case visée sans danger : gardée
        steps = self.steps()
        self.assertEqual(steps, [(103, 99), (109, 99)])                   # coins de la boîte à 3 cases de la plante
        self.assertEqual(self.entry('k'), 1)
        self.assertLessEqual(len(steps) + 1, self.d('MAX_STEPS'))
        self.assert_segments_clear((102.5, 102.5), steps)
        self.assertEqual([line for line in self.lk() if 'straight line' in line], [])
        self.assertTrue(any('move #1 split into 3 steps around farming plants or campfires: 103,99 109,99 then '
                            '111,102' in line for line in self.lk()), self.lk())
        # Calcul déterministe : même trajet pour la même situation.
        again = lua_list(self.d('planDetour(102.5, 102.5, 111, 102, 0)'))
        self.assertEqual([(p.x, p.y) for p in again], steps)
        # Table envoyée aux clients : points de passage et étape.
        state = self.msgs('dirState')[0]['args']['d']['lk-1']
        self.assertEqual(state['k'], 1)
        self.assertEqual([(p['x'], p['y']) for p in state['w'].values()] if isinstance(state['w'], dict)
                         else [(p['x'], p['y']) for p in state['w']], steps)
        self.h.pump()
        squares = self.track(zid, 900)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(self.entry('k'), 3)
        self.assert_never_in_zone(squares, [(106, 102)])
        self.assertEqual([p.split('@')[0] for p in self.paths('A')], ['A:103,99', 'A:109,99', 'A:111,102'])
        self.assertEqual(self.paths('B'), [])
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertEqual(self.d('stats.stepIgnored'), 0)
        lines = self.lk()
        self.assertTrue(any('move #1 step 1/3 reached (by A), next 109,99' in line for line in lines), lines)
        self.assertTrue(any('move #1 step 2/3 reached (by A), next 111,102' in line for line in lines), lines)
        self.assertTrue(any('step 1/3 reached here' in line for line in self.lk('A')), self.lk('A'))
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"].k'), 3)

    def test_row_of_plants_between_the_body_and_the_target_is_bypassed(self):
        zid = self.ready('A')
        row = [(106, y) for y in range(100, 105)]   # potager : 5 plants alignés en travers du trajet
        self.plants(row)
        self.move()
        steps = self.steps()
        self.assertIsNotNone(steps)
        self.assertLessEqual(len(steps) + 1, self.d('MAX_STEPS'))
        for sx, sy in steps:
            self.assertGreaterEqual(min(max(abs(sx - px), abs(sy - py)) for px, py in row), 3, (sx, sy))
        self.assert_segments_clear((102.5, 102.5), steps)
        self.h.pump()
        squares = self.track(zid, 1200)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assert_never_in_zone(squares, row)

    def test_no_simple_detour_keeps_the_direct_trip_with_a_warning(self):
        self.ready('A')
        # Boîte des dangers trop large (colonne de 41 plants) : destination directe, avertissement.
        self.plants([(106, y) for y in range(82, 123)])
        self.assertEqual(self.move(), 1)
        self.assertIsNone(self.steps())
        warns = [line for line in self.lk() if 'straight line crosses' in line]
        self.assertEqual(len(warns), 1, self.lk())
        self.assertIn('crosses 1 farming plant or campfire square(s) (first 106,102 farming plant) and hazard area '
                      'wider than 24 squares', warns[0])
        self.assertNotIn('w', self.msgs('dirState')[-1]['args']['d']['lk-1'])

    def test_detour_refused_when_corners_are_blocked_or_too_long(self):
        self.ready('A')
        self.plants([(106, 102)])
        # Coins (et leurs voisines) impraticables : aucun contournement simple.
        self.run_lua('for x = 100, 113 do for _, y in ipairs({ 97, 98, 99, 100, 104, 105, 106, 107 }) do '
                     'getCell():getGridSquare(x, y, 0).blocked = true end end')
        self.assertIsNone(self.ev('(LivingKnox.Directives.planDetour(102.5, 102.5, 111, 102, 0))'))
        why = self.ev('select(2, LivingKnox.Directives.planDetour(102.5, 102.5, 111, 102, 0))')
        self.assertIn('no clear detour around the hazards in 106,102-106,102', why)
        self.assertEqual(self.move(), 1)
        self.assertIsNone(self.steps())
        self.assertTrue(any('straight line crosses 1 farming plant' in line and 'no clear detour' in line
                            for line in self.lk()), self.lk())
        # Détour borné : au-delà de MAX_DETOUR cases de plus que la ligne droite, pas de point de passage.
        self.run_lua('for x = 100, 113 do for _, y in ipairs({ 97, 98, 99, 100, 104, 105, 106, 107 }) do '
                     'getCell():getGridSquare(x, y, 0).blocked = false end end')
        self.assertEqual(len(lua_list(self.d('planDetour(102.5, 102.5, 111, 102, 0)'))), 2)
        self.run_lua('LivingKnox.Directives.MAX_DETOUR = 1')
        self.assertIsNone(self.ev('(LivingKnox.Directives.planDetour(102.5, 102.5, 111, 102, 0))'))
        # Ligne hors zone : aucun point ; corps parti de la zone : seul le danger lui-même compte au premier segment.
        self.run_lua('LivingKnox.Directives.MAX_DETOUR = 30')
        self.assertEqual(lua_list(self.d('planDetour(102.5, 102.5, 102, 110, 0)')), [])
        self.assertEqual(lua_list(self.d('planDetour(105.5, 103.5, 105, 108, 0)')), [])

    def test_owner_change_at_a_waypoint_resumes_at_the_published_step(self):
        zid = self.ready('A')
        self.plants([(106, 102)])
        self.move()
        self.h.pump()
        for _ in range(900):
            self.track(zid, 1)
            if self.entry('k') == 2:
                break
        self.assertEqual(self.entry('k'), 2)
        self.walk(zid, 3)
        self.h.set_owner(zid, 'B')
        self.walk(zid, self.handover())
        self.assertEqual([p.split('@')[0] for p in self.paths('B')], ['B:109,99'])   # pas de retour au point 1
        self.track(zid, 900)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual(self.entry('k'), 3)

    def test_step_reports_are_checked_one_step_at_a_time(self):
        zid = self.ready('A')
        self.plants([(106, 102)])
        self.move()
        self.h.pump()
        self.walk(zid, 12)
        srv = self.h.zombie('server', zid)
        for n, k in ((5000, 3), (5001, 2)):   # saut de deux étapes ; étape suivante loin du point 1
            self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'A'),
                        {'id': 'lk-1', 'v': 1, 'l': self.entry('l'), 's': 'moving', 'x': srv.x, 'y': srv.y,
                         'z': 0, 'a': 0, 'n': n, 't': 0, 'k': k})
        self.assertEqual(self.entry('k'), 1)
        self.assertEqual(self.d('stats.stepIgnored'), 2)
        self.assertEqual(self.d('stats.rejected'), 0)

    def test_suspended_move_with_steps_resumes_at_the_published_step(self):
        zid = self.ready('A')
        self.plants([(106, 102)])
        self.move()
        self.h.pump()
        squares = []
        for _ in range(900):                                          # A atteint le premier point de passage
            squares += self.track(zid, 1)
            if self.entry('k') == 2:
                break
        self.assertEqual(self.entry('k'), 2)
        self.h.set_owner(zid, 'server')
        self.h.tick(1)
        self.h.pump()
        self.assertIsNotNone(self.entry('suspended'))
        squares += self.track(zid, 200)
        self.assertEqual(self.entry('k'), 2)                          # étape publiée inchangée pendant la suspension
        self.h.set_owner(zid, 'B')
        squares += self.track(zid, 900)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual([p.split('@')[0] for p in self.paths('B')], ['B:109,99', 'B:111,102'])
        self.assertEqual(self.paths('server'), [])
        self.assert_never_in_zone(squares, [(106, 102)])

    def test_body_at_rest_next_to_a_plant_walks_away_once(self):
        zid = self.ready('A')
        # Consigne en cours : jamais interrompue par la règle d'arrêt.
        self.move()
        self.h.pump()
        self.walk(zid, 20)
        srv = self.h.zombie('server', zid)
        self.run_lua(f'getCell():getGridSquare({int(srv.x) + 1}, {int(srv.y)}, 0).plant = true')
        self.hazard_pass()
        self.assertEqual(self.entry('v'), 1)
        self.assertEqual(self.entry('x'), 111)
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        # A l'arrêt à côté d'une plante (case voisine, serveur seul à la voir) : consigne courte vers une case sûre.
        self.run_lua(f'getCell():getGridSquare({int(srv.x) + 1}, {int(srv.y)}, 0).plant = {{ state = "seeded" }}')
        plant = (int(srv.x) + 1, int(srv.y))
        self.hazard_pass()
        self.assertEqual(self.entry('v'), 2)
        self.assertEqual(self.entry('op'), 'move')
        self.assertEqual(self.entry('g'), 'walk')
        tx, ty = self.entry('x'), self.entry('y')
        self.assertGreaterEqual(max(abs(tx - plant[0]), abs(ty - plant[1])), 3, (tx, ty, plant))
        self.assertLessEqual(max(abs(tx - int(srv.x)), abs(ty - int(srv.y))), 4)
        self.h.pump()
        for _ in range(3):
            self.walk(zid, 200, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        self.assertIsNone(self.near(int(srv.x), int(srv.y)))           # hors de la zone, à la tolérance d'arrivée
        for _ in range(4):
            self.hazard_pass()
        self.assertEqual(self.entry('v'), 2)                           # aucun nouveau déplacement
        moved = [line for line in self.lk() if 'moved away to' in line]
        self.assertEqual(len(moved), 1, self.lk())
        self.assertIn(f'next to a farming plant at {plant[0]},{plant[1]},0', moved[0])
        self.assertEqual(self.d('stats.rejected'), 0)

    def test_campfire_seen_by_the_authority_only(self):
        zid = self.ready('A')
        srv = self.h.zombie('server', zid)
        x, y = int(srv.x), int(srv.y) + 1
        for m in ('server', 'A'):
            self.h.load(m, f'getCell():getGridSquare({x}, {y}, 0).campfire = {{ isLit = false }}')
        # Client MP : getCampfire nil, hasLitCampfire faux (systèmes du serveur seulement) ; serveur : vu, éteint ou non.
        self.assertIsNone(self.h.eval('A', f'LivingKnox.Bodies.hazardOn(getCell():getGridSquare({x}, {y}, 0))'))
        self.assertIs(self.h.eval('A', f'getCell():getGridSquare({x}, {y}, 0):hasLitCampfire()'), False)
        self.assertEqual(self.ev(f'LivingKnox.Bodies.hazardOn(getCell():getGridSquare({x}, {y}, 0))'), 'campfire')
        self.hazard_pass()
        self.assertEqual(self.entry('op'), 'move')
        self.assertTrue(any('next to a campfire' in line and 'moved away to' in line for line in self.lk()),
                        self.lk())


class SoloDirectiveTests(DirectiveBase):
    mode = 'solo'

    def test_solo_move_stop_face_without_network(self):
        self.init()
        npc_id, body = self.spawn()
        zid = body.onlineID
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'A')
        self.assertEqual(self.paths('solo'), ['solo:111,102@102.50,102.50'])
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.assertIs(body.useless, True)
        self.assertEqual(self.h.pending(), [])
        self.assertGreaterEqual(self.d('stats.accepted'), 3)
        self.assertEqual(self.d('stats.relayed'), 0)
        # Stop pendant un trajet, puis orientation.
        self.d('moveTo("lk-1", 102, 102, 0, "crouch")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'crouch')
        self.walk(zid, 30)
        self.d('stop("lk-1")')
        self.walk(zid, 15)
        self.assertEqual(self.entry('s'), 'stopped')
        x = body.x
        self.walk(zid, 60)
        self.assertEqual(body.x, x)
        self.d('face("lk-1", "W")')
        self.walk(zid, 15)
        self.assertEqual(self.entry('s'), 'faced')
        self.assertEqual(body.angle, 180)
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_body_reappearance_resumes_and_stale_directive_ignored(self):
        self.init()
        npc_id, body = self.spawn()
        zid = body.onlineID
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.walk(zid, 40)
        # Corps sorti puis revenu (déchargement, retour) : exécution lâchée, puis reprise de la même consigne.
        self.run_lua('SAVED = LivingKnox.Bodies.bound["lk-1"]; LivingKnox.Bodies.bound["lk-1"] = nil; '
                     'LivingKnox.Executor.pass()')
        self.assertIsNone(self.ev('LivingKnox.Executor.runs["lk-1"]'))
        here = body.x
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = SAVED')
        self.walk(zid, 400, until=self.done())
        paths = self.paths('solo')
        self.assertEqual(len(paths), 2, paths)           # départ, puis reprise depuis la position atteinte
        self.assertGreaterEqual(float(paths[1].split('@')[1].split(',')[0]), here)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(len([line for line in self.lk() if 'move #1 arrived' in line]), 1)
        self.assertGreaterEqual(self.ev('LivingKnox.Executor.stats.resumed'), 1)
        # Consigne périmée : jamais commencée après une plus récente, ni rejouée une fois menée à son terme.
        self.d('stop("lk-1")')
        self.walk(zid, 15)
        self.assertEqual(self.entry('s'), 'stopped')
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Executor.mayStart("lk-1", { v = 1, l = 1 }) }')),
                         [False, 'stale'])
        lease = self.entry('l')
        self.assertEqual(lua_list(self.ev(f'{{ LivingKnox.Executor.mayStart("lk-1", {{ v = 2, l = {lease} }}) }}')),
                         [False, 'already executed here'])
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_trip_around_a_plant_by_waypoints_without_network(self):
        self.init()
        npc_id, body = self.spawn()
        zid = body.onlineID
        self.run_lua('getCell():getGridSquare(106, 102, 0).plant = { state = "seeded" }')
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        squares = []
        for _ in range(900):
            self.h.tick(1)
            self.h.eval('solo', f'STEP({zid}, 0.05)')
            squares.append((int(body.x // 1), int(body.y // 1)))
            if self.done()():
                break
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('k'), 3)
        self.assertEqual([p.split('@')[0] for p in self.paths('solo')], ['solo:103,99', 'solo:109,99', 'solo:111,102'])
        self.assertTrue(all(max(abs(x - 106), abs(y - 102)) > 1 for x, y in squares), squares)
        steps = [line for line in self.lk() if 'step' in line and 'reached' in line]
        self.assertEqual(len([s for s in steps if 'INFO' in s]), 2, steps)   # une ligne par étape (autorité)
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_body_at_rest_on_a_lit_campfire_walks_away(self):
        self.init()
        npc_id, body = self.spawn()
        zid = body.onlineID
        x, y = int(body.x), int(body.y)
        self.run_lua(f'getCell():getGridSquare({x}, {y}, 0).campfire = {{ isLit = true }}')
        self.assertEqual(self.ev(f'(LivingKnox.Bodies.hazardNear({x}, {y}, 0, 1))'), 'campfire')
        self.h.tick(self.ev('LivingKnox.Bodies.SCAN_EVERY * LivingKnox.Bodies.HAZARD_EVERY'))
        self.assertEqual(self.entry('op'), 'move')
        self.walk(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertGreaterEqual(max(abs(int(body.x) - x), abs(int(body.y) - y)), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKExecutor.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.executor", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.executor')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)


    def test_farm_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKFarm.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.farm", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.farm')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)

    # LK05-T13 : emplacement de la rangée de potager cherché par la suite lk.farm avant de planter.
    def garden_site(self, x, y):
        self.h.load('solo', 'shared/RST/suites/RST_LKFarm.lua')
        self.run_lua(f'SITE, WHY = RST.LKFarm.gardenSite({x}, {y}, 0)')
        return self.ev('SITE'), self.ev('WHY')

    def site_detour(self, body, site):
        """Plante la rangée du site, rend les étapes de Directives.planDetour (liste de (x, y)) ou la raison."""
        for q in self.h.eval('solo', 'SITE.row').values():
            self.run_lua(f'getCell():getGridSquare({q.x}, {q.y}, 0).plant = {{ state = "seeded" }}')
        self.run_lua(f'STEPS, NODETOUR = LivingKnox.Directives.planDetour({body.x}, {body.y}, {site.tx}, {site.ty}, 0)')
        steps = self.ev('STEPS')
        if steps is None:
            return self.ev('NODETOUR')
        return [(s.x, s.y) for s in steps.values()]

    def test_farm_garden_site_east_on_open_ground(self):
        self.init()
        _, body = self.spawn()
        bx, by = int(body.x), int(body.y)
        site, why = self.garden_site(bx, by)
        self.assertIsNotNone(site, why)
        self.assertEqual((site.dir, site.rowAt, site.tx, site.ty), ('E', 5, bx + 10, by))
        self.assertEqual([(q.x, q.y) for q in site.row.values()], [(bx + 5, by + d) for d in range(-2, 3)])
        corners = list(site.corners.values())
        steps = self.site_detour(body, site)
        self.assertIsInstance(steps, list, steps)
        self.assertEqual(len(steps), 2, steps)
        self.assertTrue(all(f'{x},{y}' in corners for x, y in steps), (steps, corners))
        self.assertEqual(self.h.errors('solo'), [])

    def test_farm_garden_site_east_blocked_takes_west(self):
        self.init()
        _, body = self.spawn()
        bx, by = int(body.x), int(body.y)
        for d in (5, 4, 6):   # une case de chaque rangée possible à l'est : mur ou meuble
            self.run_lua(f'getCell():getGridSquare({bx + d}, {by + 1}, 0).blocked = true')
        site, why = self.garden_site(bx, by)
        self.assertIsNotNone(site, why)
        self.assertEqual((site.dir, site.rowAt, site.tx, site.ty), ('W', 5, bx - 10, by))
        steps = self.site_detour(body, site)
        self.assertIsInstance(steps, list, steps)
        self.assertEqual(len(steps), 2, steps)
        self.assertEqual(self.h.errors('solo'), [])

    def test_farm_garden_site_unloaded_east_takes_north(self):
        self.init()
        _, body = self.spawn()
        bx, by = int(body.x), int(body.y)
        self.run_lua(f'UNLOADED[#UNLOADED + 1] = {{ {bx + 8}, {bx + 40}, {by - 40}, {by + 40} }}; '
                     f'getCell():getGridSquare({bx - 5}, {by}, 0).blocked = true')
        site, why = self.garden_site(bx, by)
        self.assertIsNotNone(site, why)
        self.assertEqual((site.dir, site.tx, site.ty), ('N', bx, by - 10))
        self.assertEqual(self.h.errors('solo'), [])

    def test_farm_garden_site_none_near_a_plant(self):
        self.init()
        _, body = self.spawn()
        bx, by = int(body.x), int(body.y)
        self.run_lua(f'getCell():getGridSquare({bx}, {by + 1}, 0).plant = {{ state = "seeded" }}')
        site, why = self.garden_site(bx, by)
        self.assertIsNone(site)
        self.assertIn('S at 6: farming plant or campfire at', why)
        self.assertEqual(self.h.errors('solo'), [])

    def test_farm_suite_skips_without_a_garden_site(self):
        code = (DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKFarm.lua').read_text(encoding='utf-8')
        body = code[code.index('trip across a garden row: waypoints'):]
        self.assertLess(body.index('gardenSite(bx, by, bz)'), body.index('plantOn('))
        self.assertLess(body.index('t2:skip("no clear site for a garden row'), body.index('plantOn('))
        self.assertIn('[LKF] garden row placed at ', body)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')

    def test_presentation_never_moves_a_copy(self):
        code = (LUA / PRESENTATION).read_text(encoding='utf-8')
        code = re.sub(r'--[^\n]*', '', code)
        for call in ('pathToLocation', 'setX', 'setY', 'teleportTo', 'setMoving', 'setVariable'):
            self.assertNotIn(call, code)


if __name__ == '__main__':
    unittest.main()
