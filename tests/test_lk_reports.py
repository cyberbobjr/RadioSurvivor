"""Tests hors jeu des rapports d'état Living Knox (LK03-T02) : LK_Reports.lua (autorité), envoi par LK_Executor.lua.

    python RadioSurvivor/tests/test_lk_reports.py

Banc tests/harness.py (serveur et deux clients, ou solo), doublures des consignes (test_lk_directives.py) complétées
de getHealth (IsoGameCharacter.java:2898) et isCrawling (IsoZombie.java:3998). Les doublures NE PROUVENT PAS l'API
réelle, seulement la logique : propriétaire, bail, ordre, cadence, plausibilité, santé, bornes.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA  # noqa: E402
from test_lk_directives import DirectiveBase, TARGET  # noqa: E402
from test_lk_milestone import MilestoneBase  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_equipment import EQUIP_DOUBLES, EQUIPMENT  # noqa: E402

REPORTS = 'server/LivingKnox/LK_Reports.lua'
EXECUTOR = 'client/LivingKnox/LK_Executor.lua'

REPORT_DOUBLES = r'''
local Z = HARNESS.classes.IsoZombie
function Z:getHealth() return rawget(self, 'health') or 2 end
function Z:isCrawling() return self.crawling == true end
'''


class ReportBase(DirectiveBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, REPORT_DOUBLES)
            h.load(m, REPORTS)
        return h

    def r(self, code, m=None):
        return self.ev('LivingKnox.Reports.' + code, m)

    def state(self, field):
        return self.ev(f'LivingKnox.Reports.get("lk-1") and LivingKnox.Reports.get("lk-1").{field}')

    def why(self, reason):
        return self.ev(f'LivingKnox.Reports.stats.why["{reason}"] or 0')

    def refused(self):
        return [line for line in self.lk() if 'state report on npc' in line and 'refused' in line]


class MultiplayerReportTests(ReportBase):
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

    def silence(self, *clients):
        """Coupe l'envoi automatique des rapports d'état sur ces clients (rapports forgés seuls)."""
        for c in clients:
            self.h.load(c, 'LivingKnox.Reports = nil')

    def forge(self, sender, zid, gap_ms=300, **kw):
        """Rapport d'état envoyé au serveur au nom de sender (par défaut : position de la copie du serveur, bail
        courant). Rend vrai si accepté."""
        self.h.advance_ms(gap_ms)
        srv = self.h.zombie('server', zid)
        lease = self.ev('LivingKnox.Directives.entries["lk-1"] and LivingKnox.Directives.entries["lk-1"].l or 0')
        self.n = getattr(self, 'n', 1000) + 1
        args = {'id': 'lk-1', 'l': lease, 'n': self.n, 'x': srv.x, 'y': srv.y, 'z': srv.z, 'a': 90.0,
                'act': 'idle', 'hp': 2, 'pose': 'stand', 't': 0}
        args.update(kw)
        before = self.r('stats.accepted')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'bodyReport', self.h.player('server', sender), args)
        return self.r('stats.accepted') == before + 1

    def test_owner_reports_accepted_while_walking_at_a_bounded_rate(self):
        zid = self.ready('A')
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.h.pump()
        start = self.h.real_ms
        accepted = self.r('stats.accepted')                # rapport d'avant la consigne (corps au repos)
        sent = []
        for _ in range(400):
            self.h.tick(1)
            self.h.eval('A', f'STEP({zid}, 0.05)')
            zb = self.h.zombie('A', zid)
            self.h.move_zombie(zid, zb.x, zb.y)
            sent += [m for m in self.h.pending() if m['command'] == 'bodyReport']
            self.h.pump()
            if self.done()():
                break
        self.walk(zid, 120)                                 # au repos après l'arrivée
        sent += [m for m in self.h.pending() if m['command'] == 'bodyReport']
        self.h.pump()
        seconds = (self.h.real_ms - start) / 1000
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual({m['from'] for m in sent}, {'A'})  # B ne simule pas le corps : il ne rapporte rien
        self.assertGreaterEqual(len(sent), 4)
        # Cadence : au plus un rapport par seconde, plus un par changement d'activité (moving, arrived), plus le premier.
        self.assertLessEqual(len(sent), seconds + 3, (len(sent), seconds))
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.r('stats.accepted') - accepted, len(sent))
        self.assertEqual(self.state('by'), 'A')
        self.assertEqual(self.state('act'), 'arrived')
        self.assertEqual(self.state('pose'), 'stand')
        self.assertEqual(self.state('hp'), 2)
        self.assertLessEqual(abs(self.state('x') - self.h.zombie('server', zid).x), 0.5)
        args = sent[0]['args']
        self.assertEqual(sorted(args), ['a', 'act', 'hp', 'id', 'l', 'n', 'pose', 't', 'x', 'y', 'z'])
        self.assertEqual((args['l'], args['act']), (1, 'moving'))
        self.assertEqual(self.h.errors('server'), [])

    def test_forged_and_incoherent_reports_are_refused_and_logged(self):
        zid = self.ready('A')
        self.silence('A', 'B')
        self.assertTrue(self.forge('A', zid))               # référence acceptée (PNJ sans consigne : bail 0)
        ref = (self.state('x'), self.state('ms'), self.state('n'))
        self.assertFalse(self.forge('B', zid))              # non-propriétaire
        self.assertFalse(self.forge('A', zid, l=7))         # bail jamais donné
        self.assertFalse(self.forge('A', zid, n=self.n - 5))  # numéro rejoué / plus ancien
        srv = self.h.zombie('server', zid)
        self.assertFalse(self.forge('A', zid, x=srv.x + 30))  # loin de la copie du serveur
        for bad in ({'z': 40}, {'hp': 50}, {'hp': -1}, {'act': 'dance'}, {'pose': 'fly'}, {'x': -5}, {'a': 1000}):
            self.assertFalse(self.forge('A', zid, **bad), bad)
        self.assertFalse(self.forge('A', zid, hp='full'))  # forme
        self.assertEqual((self.state('x'), self.state('ms'), self.state('n')), ref)   # état serveur inchangé
        self.assertEqual(self.why('not the owner'), 1)
        self.assertEqual(self.why('unknown lease'), 1)
        self.assertEqual(self.why('replayed or older report'), 1)
        self.assertEqual(self.why('far from the body'), 1)
        self.assertEqual(self.why('out of bounds'), 7)
        self.assertEqual(self.why('bad report'), 1)
        warns = self.refused()
        self.assertTrue(any('WARN state report on npc lk-1 from B refused: not the owner (owner A)' in w
                            for w in warns), warns)
        self.assertTrue(any('out of bounds (level 40.00)' in w for w in warns), warns)
        # Une ligne par (expéditeur, raison) et par minute.
        self.assertFalse(self.forge('B', zid))
        self.assertEqual(len([w for w in warns if 'from B refused: not the owner' in w]), 1)
        self.assertEqual(len([w for w in self.refused() if 'from B refused: not the owner' in w]), 1)

    def test_teleport_impossible_level_change_and_health_rise_refused(self):
        zid = self.ready('A')
        self.silence('A', 'B')
        self.assertTrue(self.forge('A', zid, gap_ms=0))
        x, y = self.h.zombie('server', zid).x, self.h.zombie('server', zid).y
        # Saut de 50 cases en 1 s, la copie du serveur ayant suivi : refusé, aucun téléport accepté.
        self.h.move_zombie(zid, x + 50, y)
        self.assertFalse(self.forge('A', zid, gap_ms=1000))
        self.assertEqual(self.why('too fast'), 1)
        self.assertEqual(self.state('x'), x)
        self.h.move_zombie(zid, x + 2, y)                   # 2 cases en 1,3 s : plausible
        self.assertTrue(self.forge('A', zid))
        x = x + 2
        # Changement d'étage : 3 niveaux en 1 s vers le haut, refusé ; 1 niveau en 1 s accepté.
        self.h.move_zombie(zid, x, y, 3)
        self.assertFalse(self.forge('A', zid, gap_ms=1000))
        self.assertEqual(self.why('impossible climb'), 1)
        self.h.move_zombie(zid, x, y, 1)
        self.assertTrue(self.forge('A', zid, gap_ms=1000))
        # Descente : chute de 1 niveau tout de suite acceptée ; 8 niveaux en 1 s refusés (chute du moteur ~ 2,5).
        self.h.move_zombie(zid, x, y, 0)
        self.assertTrue(self.forge('A', zid, gap_ms=100))
        self.h.move_zombie(zid, x, y, 8)
        self.assertFalse(self.forge('A', zid, gap_ms=100))   # copie du serveur à 8 : montée impossible
        # Santé : baisse acceptée, remontée sans soin refusée, remontée après un soin connu acceptée une fois.
        self.h.move_zombie(zid, x, y, 0)
        self.assertTrue(self.forge('A', zid, hp=1.5))
        self.assertFalse(self.forge('A', zid, hp=2.0))
        self.assertEqual(self.why('health rose without a known heal'), 1)
        self.assertEqual(self.state('hp'), 1.5)
        self.assertIs(self.r('noteHeal("lk-1", 0.3)'), True)
        self.assertFalse(self.forge('A', zid, hp=2.0))       # soin plus petit que la hausse
        self.assertTrue(self.forge('A', zid, hp=1.8))
        self.assertFalse(self.forge('A', zid, hp=1.9))       # crédit consommé
        self.assertEqual(self.state('hp'), 1.8)
        self.assertEqual(self.r('stats.healed'), 1)
        self.assertEqual(self.h.zombie('server', zid).x, x)  # rien n'a déplacé le corps
        self.assertTrue(any('WARN' in w and 'too fast (50.0 squares in 1000 ms)' in w for w in self.refused()),
                        self.refused())

    def test_lease_previous_lease_and_designated_executor(self):
        zid = self.ready('A')
        self.silence('A', 'B')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        self.h.pump()
        self.assertTrue(self.forge('A', zid))               # bail 1 de la consigne, exécutant A
        self.assertFalse(self.forge('A', zid, l=0))         # bail plus ancien (avant la consigne) : course, INFO
        self.assertEqual(self.why('previous lease'), 1)
        self.assertTrue(any('INFO state report on npc lk-1 from A refused: previous lease' in w
                            for w in self.refused()), self.refused())
        # B devient propriétaire : avant le passage du serveur, le bail désigne encore A.
        self.h.set_owner(zid, 'B')
        self.assertFalse(self.forge('B', zid))
        self.assertEqual(self.why('not the designated executor'), 1)
        self.assertFalse(self.forge('A', zid))              # A n'est plus le propriétaire
        self.h.eval('server', 'LivingKnox.Directives.serverPass()')
        self.assertEqual(self.entry('o'), 'B')
        self.assertFalse(self.forge('B', zid, l=1))         # bail 1 périmé
        self.assertTrue(self.forge('B', zid))               # bail 2
        self.assertEqual(self.state('by'), 'B')
        self.assertTrue(any('npc lk-1: state now reported by B (was A)' in line for line in self.lk()), self.lk())

    def test_running_owner_ahead_of_a_stale_server_copy_is_accepted(self):
        """Campagne MP 2026-10-14 : la copie du serveur ne suit la position du proprietaire qu'a chaque paquet zombie
        (toutes les 4 s) ; un corps en course etait refuse "far from the body (6.1 squares)"."""
        zid = self.ready('A')
        self.silence('A', 'B')
        srv = self.h.zombie('server', zid)
        self.assertTrue(self.forge('A', zid))
        x0 = srv.x
        for i in range(1, 9):                       # 4 s de course a 4,78 cases/s, copie du serveur immobile
            self.assertTrue(self.forge('A', zid, gap_ms=500, x=x0 + 2.39 * i), i)
        self.assertEqual(self.why('far from the body'), 0)
        self.assertFalse(self.forge('A', zid, gap_ms=500, x=x0 + 30))   # au-dela : refuse

    def test_refusals_counted_per_npc(self):
        """Campagne MP 2026-10-14 : lk.executor comptait les refus de TOUS les PNJ (rapports en vol de corps retires
        par la suite precedente) ; rejectedOf(id) ne compte que ceux d'un PNJ dont le corps est present."""
        zid = self.ready('A')
        self.silence('A', 'B')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        self.h.pump()
        self.assertTrue(self.forge('A', zid))
        self.assertFalse(self.forge('A', zid, l=0))          # previous lease : refus du PNJ suivi, course (INFO)
        self.assertEqual(self.r('rejectedOf("lk-1")'), (1, 0))   # total, suspects
        self.assertFalse(self.forge('A', zid, x=self.h.zombie('server', zid).x + 30))   # suspect (WARN)
        self.assertEqual(self.r('rejectedOf("lk-1")'), (2, 1))
        self.assertEqual(self.r('rejectedOf("lk-9")'), (0, 0))
        self.h.eval('server', 'LivingKnox.Reports.onReport(PLAYERS and PLAYERS.A or nil, { id = "lk-9", l = 0, n = 1, '
                              'x = 1, y = 1, z = 0, a = 0, hp = 1, act = "idle", pose = "stand" })')
        self.assertEqual(self.why('no body'), 1)              # compte global seulement
        self.assertEqual(self.r('rejectedOf("lk-9")'), (0, 0))
        self.assertEqual(self.r('rejectedOf("lk-1")'), (2, 1))
        self.r('forget("lk-1")', 'server')
        self.assertEqual(self.r('rejectedOf("lk-1")'), (0, 0))

    def test_closed_directive_lease_follows_the_owner(self):
        zid = self.ready('A')
        self.d('face("lk-1", "S")')
        self.h.pump()
        self.walk(zid, 30)
        self.assertIs(self.entry('done'), True)
        lease = self.entry('l')
        self.h.set_owner(zid, 'B')
        self.slow()
        self.h.pump()
        self.assertEqual(self.entry('o'), 'B')
        self.assertGreater(self.entry('l'), lease)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.remote.d["lk-1"].l'), self.entry('l'))
        self.walk(zid, 80)
        self.h.pump()
        self.assertEqual(self.state('by'), 'B')
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.h.eval('B', 'LivingKnox.Executor.stats.started'), 0)   # consigne close : rien à faire

    def test_reconnection_resets_the_report_numbers(self):
        zid = self.ready('A')
        self.silence('A', 'B')
        self.assertTrue(self.forge('A', zid, n=500))
        self.assertFalse(self.forge('A', zid, n=1))          # plus ancien
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'guardHello', self.h.player('server', 'A'), {'v': 1})
        self.h.pump()
        self.assertTrue(self.forge('A', zid, n=1))           # nouvelle session : numéros repartis de 1

    def test_rate_limit(self):
        zid = self.ready('A')
        self.silence('A', 'B')
        self.run_lua('LivingKnox.Reports.buckets = {}')
        results = [self.forge('A', zid, gap_ms=0) for _ in range(14)]
        self.assertEqual(results.count(True), self.ev('LivingKnox.Config.REPORTS.BURST'))
        self.assertGreaterEqual(self.why('too many reports'), 1)
        self.assertTrue(self.forge('A', zid, gap_ms=1000))   # seau rechargé

    def test_mp_client_stops_at_the_guard(self):
        self.ready('A')
        self.assertEqual(self.h.eval('A', 'LivingKnox.Reports.CMD_REPORT'), 'bodyReport')
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Reports.onReport'))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Reports.states'))

    def test_copy_out_of_the_client_world_sends_nothing_until_it_returns(self):
        """LK03-T07 : copie du propriétaire sortie de sa liste des zombies (corps déchargé chez lui, objet gardé en
        cache) : aucun rapport ; copie revenue : rapports repris, aucun refus."""
        zid = self.ready('A')
        idle = self.ev('LivingKnox.Config.REPORTS.IDLE_MS')
        self.h.load('A', f'GONE_COPY = HARNESS.zombies[{zid}]; HARNESS.listRemove(HARNESS.zombieList, GONE_COPY)')
        self.h.pump()
        sent = []
        for _ in range(4):
            self.h.advance_ms(idle + 100)
            self.exec_pass()
            sent += [m for m in self.h.pending() if m['command'] == 'bodyReport']
            self.h.pump()
        self.assertEqual(sent, [])
        self.assertGreaterEqual(self.h.eval('A', 'LivingKnox.Executor.stats.unloaded'), 1)
        accepted = self.r('stats.accepted')
        self.h.load('A', 'HARNESS.zombieList:add(GONE_COPY)')
        self.exec_pass()
        sent = [m for m in self.h.pending() if m['command'] == 'bodyReport']
        self.h.pump()
        self.assertEqual([m['from'] for m in sent], ['A'])
        self.assertEqual(self.r('stats.accepted'), accepted + 1)
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.h.errors('A'), [])

    def test_no_body_refusal_written_once_per_absence(self):
        """LK03-T07 : défense du serveur gardée ; refus "no body" compté à chaque fois, écrit une fois par PNJ,
        expéditeur et absence (même après la minute), de nouveau après un rapport qui retrouve le corps."""
        zid = self.ready('A')
        self.silence('A', 'B')
        self.assertTrue(self.forge('A', zid))
        self.run_lua('SAVED = LivingKnox.Bodies.bound["lk-1"]; LivingKnox.Bodies.bound["lk-1"] = nil')
        self.assertFalse(self.forge('A', zid))
        self.assertFalse(self.forge('A', zid, gap_ms=61000))
        self.assertFalse(self.forge('A', zid, gap_ms=61000))
        self.assertEqual(self.why('no body'), 3)
        lines = [w for w in self.refused() if 'refused: no body' in w]
        self.assertEqual(lines, ['[LivingKnox] INFO state report on npc lk-1 from A refused: no body (embodied)'])
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = SAVED')
        self.assertTrue(self.forge('A', zid))
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = nil')
        self.assertFalse(self.forge('A', zid))
        self.assertEqual(len([w for w in self.refused() if 'refused: no body' in w]), 2)

    def test_owner_transfer_midway_new_owner_reports_after_its_lease(self):
        zid = self.ready('A')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        self.h.pump()
        self.walk(zid, 90)
        self.assertEqual(self.state('by'), 'A')
        self.h.set_owner(zid, 'B')
        self.h.eval('B', 'LivingKnox.Executor.pass()')     # B simule, mais le bail désigne encore A : rien envoyé
        self.assertEqual([m for m in self.h.pending() if m['command'] == 'bodyReport'], [])
        self.walk(zid, 400, until=self.done())
        self.walk(zid, 80)
        self.assertEqual(self.entry('by'), 'B')
        self.assertEqual(self.state('by'), 'B')
        self.assertEqual(self.state('l'), self.entry('l'))
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())


class OwnershipHandoverTests(ReportBase):
    """LK03-T03 : transfert de propriété sans perte d'état. Serveur et deux clients, propriétaire qui alterne ; le
    banc change le propriétaire sur toutes les machines à la même image (le jeu : serveur d'abord, client par le paquet
    ZombieList) et livre les commandes à la fin de chaque image (le réseau réel ajoute son aller-retour)."""

    def make(self, root=None):
        h = super().make(root)
        for m in ('server', 'A', 'B'):
            h.load(m, EQUIP_DOUBLES)
            h.load(m, EQUIPMENT)
        return h

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

    def hp(self, m, zid):
        return self.h.eval(m, f'HARNESS.zombies[{zid}]:getHealth()')

    silence = MultiplayerReportTests.silence

    def owner_on(self, machines, zid, owner):
        for m in machines:
            self.h.load(m, f'HARNESS.zombies[{zid}].owner = "{owner}"')

    def npaths(self, m):
        return self.h.eval(m, '#PATHS')

    def forge(self, sender, zid, gap_ms=300, **kw):
        self.h.advance_ms(gap_ms)
        srv = self.h.zombie('server', zid)
        self.n = getattr(self, 'n', 1000) + 1
        args = {'id': 'lk-1', 'l': 0, 'n': self.n, 'x': srv.x, 'y': srv.y, 'z': srv.z, 'a': 90.0, 'act': 'idle',
                'hp': 2, 'pose': 'stand', 't': 0}
        args.update(kw)
        before = self.r('stats.accepted')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'bodyReport', self.h.player('server', sender), args)
        return self.r('stats.accepted') == before + 1

    def test_alternating_owners_keep_the_npc_walking_with_its_state(self):
        zid = self.ready('A')
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun") }')), [True])
        self.h.pump()
        self.h.load('B', 'LivingKnox.Equipment.remote = { rev = -1, w = {} }')   # table des armes manquée par B
        # Copie de A blessée : santé acceptée 1,4 ; la copie de B garde sa santé de création (2).
        self.h.eval('A', f'HARNESS.zombies[{zid}]:setHealth(1.4)')
        self.walk(zid, 90)
        self.assertEqual(self.state('hp'), 1.4)
        self.assertEqual(self.hp('B', zid), 2)
        self.run_lua('getCell():getGridSquare(106, 102, 0).plant = { state = "seeded" }')   # trajet à étapes
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.assertEqual(self.ev('#LivingKnox.Directives.entries["lk-1"].w'), 2)
        self.h.pump()
        tick_ms = self.h.tick_ms
        intervals = [130, 131, 133, 136, 140, 145, 151, 158, 166, 175]   # >= 2 s entre deux changements (moteur)
        # Images entre le changement sur le serveur et sa connaissance par les clients (paquet ZombieList) ;
        # pendant ce temps l'ancien propriétaire croit encore simuler le corps et sa copie continue son chemin.
        lags = [0, 3, 6, 9, 2, 5, 8, 1, 4, 7]
        owner, sim, t, i, t_next = 'A', 'A', 0, 0, intervals[0]
        transfers, delays, lagged, violations, ks = [], [], [], [], []
        pending, frozen, learn_at = None, {}, None
        stall, max_stall, last = 0, 0, None
        b_health = None
        while t < 6000 and not self.done()():
            if t == t_next:
                owner = 'B' if owner == 'A' else 'A'
                lag = lags[i % len(lags)]
                self.owner_on(['server'], zid, owner)
                learn_at = t + lag
                pending = (t, owner, self.npaths(owner), lag)
                transfers.append(t)
                i += 1
                t_next = t + intervals[i % len(intervals)]
            if learn_at is not None and t == learn_at:
                self.owner_on(['A', 'B'], zid, owner)
                self.h.owners[zid] = sim = owner
                frozen = {('B' if owner == 'A' else 'A'): None}
                learn_at = None
            self.h.tick(1)
            t += 1
            self.h.eval(sim, f'STEP({zid}, 0.01)')
            zb = self.h.zombie(sim, zid)
            self.h.move_zombie(zid, zb.x, zb.y)
            for m in self.h.pending():
                if m['command'] in ('dirReport', 'bodyReport') and m['from'] != owner and learn_at is None:
                    violations.append((t, m['from'], m['command']))
            self.h.pump()
            for c, n in list(frozen.items()):               # l'ancien propriétaire ne lance plus rien
                if n is None:
                    frozen[c] = self.npaths(c)
                elif self.npaths(c) != n:
                    violations.append((t, c, 'path'))
            if pending is not None and self.npaths(pending[1]) > pending[2]:
                delays.append(t - pending[0])
                lagged.append(t - pending[0] - pending[3])
                pending = None
                if owner == 'B' and b_health is None:
                    b_health = self.hp('B', zid)
            pos = (round(zb.x, 6), round(zb.y, 6))
            stall = stall + 1 if pos == last else 0
            max_stall = max(max_stall, stall)
            last = pos
            ks.append(self.entry('k'))
        self.walk(zid, 90)
        self.h.pump()
        # Le PNJ a poursuivi son action : une seule consigne, menée à terme une fois, étapes jamais reprises.
        self.assertGreaterEqual(len(transfers), 6, transfers)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('v'), 1)
        self.assertEqual(len([line for line in self.lk() if 'move #1 arrived' in line]), 1)
        self.assertTrue(all(b >= a for a, b in zip(ks, ks[1:])), ks)
        self.assertEqual(ks[-1], 3)
        self.assertEqual(violations, [])
        # Reprise : chaque nouveau propriétaire relance le chemin ; aucun arrêt d'une seconde.
        self.assertEqual(len(delays), len(transfers), (delays, transfers))
        self.assertLessEqual(max(lagged), 3, (delays, lagged))   # au plus 3 images après que le client le sait
        self.assertLess(max(delays) * tick_ms, 1000)
        self.assertLess(max_stall * tick_ms, 1000, max_stall)
        self.assertLessEqual(max_stall, 4, max_stall)
        resumed, resume_max = self.d('stats.resumed'), self.d('stats.resumeMax')
        self.assertGreaterEqual(resumed, len(transfers))
        self.assertLess(resume_max, 1000)
        # Santé acceptée remise : copie de B abaissée à 1,4 avant son premier rapport ; aucun rapport refusé.
        self.assertEqual(b_health, 1.4)
        self.assertEqual(self.hp('B', zid), 1.4)
        self.assertEqual(self.state('hp'), 1.4)
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertEqual(self.why('health rose without a known heal'), 0)
        self.assertEqual([line for line in self.lk() if 'refused' in line], [])
        self.assertGreaterEqual(self.h.eval('B', 'LivingKnox.Executor.stats.healthSet'), 1)
        # Arme : table reprise par B depuis la remise ; accrochée sur la copie de chaque client.
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'LivingKnox.Equipment.remote.w["lk-1"].t'), 'Base.Shotgun')
            self.assertEqual(self.h.eval(c, f'HARNESS.zombies[{zid}]:getAttachedItem("Rifle On Back"):getFullType()'),
                             'Base.Shotgun')
        self.assertEqual(self.ev('LivingKnox.Directives.hands["lk-1"]'), owner)
        sys.stderr.write(f'\n[LK03-T03] {len(transfers)} transfers, client lag 0-{max(lags)} frames: resume '
                         f'{max(delays)} frames at most after the server change ({max(delays) * tick_ms} ms, mean '
                         f'{sum(delays) * tick_ms / len(delays):.0f} ms), {max(lagged)} after the client knows; '
                         f'longest stop {max_stall * tick_ms} ms; server measure {resumed} resumptions, max '
                         f'{resume_max} ms\n')

    def test_previous_owner_reports_ignored_during_the_grace_then_refused(self):
        zid = self.ready('A')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        self.h.pump()
        self.walk(zid, 60)
        self.silence('A', 'B')
        # Le serveur seul voit B propriétaire (A n'a pas encore reçu ZombieList) ; même image : remise encore à A.
        self.h.load('server', f'HARNESS.zombies[{zid}].owner = "B"')
        srv = self.h.zombie('server', zid)
        lease = self.entry('l')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirReport', self.h.player('server', 'A'),
                    {'id': 'lk-1', 'v': 1, 'l': lease, 's': 'moving', 'x': srv.x, 'y': srv.y, 'z': 0, 'n': 5000})
        self.assertEqual(self.d('stats.previousOwner'), 1)
        self.assertFalse(self.forge('A', zid, l=lease))
        self.assertEqual(self.why('previous owner'), 1)
        self.h.tick(1)                                       # image suivante : bail et remise à B, A la rend
        self.assertEqual((self.entry('o'), self.ev('LivingKnox.Directives.hands["lk-1"]')), ('B', 'B'))
        hands = [m for m in self.h.pending() if m['command'] == 'npcHand']
        self.assertEqual(sorted(m['to'] for m in hands), ['A', 'B'])
        self.assertTrue(all(m['args']['d']['lk-1']['o'] == 'B' for m in hands))
        self.assertFalse(self.forge('A', zid, l=lease))      # rapport en vol de A : ignoré, pas refusé
        self.assertEqual(self.why('previous owner'), 2)
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.d('stats.rejected'), 0)
        self.assertEqual([line for line in self.lk() if 'WARN' in line and 'refused' in line], [])
        self.h.pump()
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.hands["lk-1"]'))
        # Délai passé : un rapport de l'ancien propriétaire redevient un refus.
        self.h.advance_ms(self.d('OWNER_GRACE_MS') + 1)
        self.assertFalse(self.forge('A', zid, l=self.entry('l')))
        self.assertEqual(self.why('not the owner'), 1)

    def test_claim_answers_only_the_owner_and_hands_back_after_reconnection(self):
        zid = self.ready('A')
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.hands["lk-1"].o'), 'A')
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Executor.hands["lk-1"]'))
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'dirClaim', self.h.player('server', 'B'),
                    {'ids': ['lk-1']})
        self.assertEqual(self.d('stats.claimIgnored'), 1)
        self.assertEqual([m for m in self.h.pending() if m['command'] == 'npcHand'], [])
        # A se reconnecte (état Lua neuf, aucune remise) : guardHello, demande, remise renvoyée ; rapports repris.
        self.h.load('A', 'LivingKnox.Executor.hands = {}\nLivingKnox.Executor.handR = {}\n'
                         'LivingKnox.Executor.claimed = {}')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'guardHello', self.h.player('server', 'A'), {'v': 1})
        self.assertIsNone(self.ev('LivingKnox.Directives.hands["lk-1"]'))
        before = self.r('stats.accepted')
        self.walk(zid, 30)
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.hands["lk-1"].o'), 'A')
        self.walk(zid, 400)
        self.assertGreater(self.r('stats.accepted'), before)
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())


class SoloReportTests(ReportBase):
    mode = 'solo'

    def test_solo_reports_by_direct_call_with_the_same_checks(self):
        self.init()
        _, body = self.spawn()
        zid = body.onlineID
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.walk(zid, 400, until=self.done())
        self.walk(zid, 80)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.h.pending(), [])
        self.assertGreaterEqual(self.r('stats.accepted'), 3)
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual(self.state('act'), 'arrived')
        # Corps au sol, puis santé qui remonte sans soin : refusée aussi en solo.
        self.run_lua(f'HARNESS.zombies[{zid}].onFloor = true; HARNESS.zombies[{zid}].health = 1.2')
        self.walk(zid, 30)
        self.assertEqual((self.state('pose'), self.state('hp')), ('floor', 1.2))
        self.run_lua(f'HARNESS.zombies[{zid}].health = 2')
        self.h.advance_ms(1000)
        self.walk(zid, 30)
        self.assertEqual(self.state('hp'), 1.2)
        self.assertGreaterEqual(self.why('health rose without a known heal'), 1)
        # Accéléré : contrôles de durée allégés (l'horloge réelle ne mesure plus le temps de jeu).
        self.run_lua(f'HARNESS.zombies[{zid}].health = 1.2; getGameSpeed = function() return 3 end')
        before = self.r('stats.fastForward')
        self.run_lua(f'HARNESS.place(HARNESS.zombies[{zid}], {body.x} + 5, {body.y}, 0)')
        self.walk(zid, 80)
        self.assertGreater(self.r('stats.fastForward'), before)
        self.assertEqual(self.why('too fast'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_body_set_aside_sends_no_report_until_its_return(self):
        """LK03-T07 (essai du 2026-10-11) : corps mis de côté au déchargement de son chunk (même objet, gardé dans
        Bodies.bound, ni mort ni retiré) : aucun rapport, aucun refus "no body" ; retour : rapports et marche repris."""
        self.init()
        _, body = self.spawn()
        zid = body.onlineID
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.walk(zid, 40)
        self.assertGreaterEqual(self.r('stats.accepted'), 1)
        self.assertIsNotNone(self.ev('LivingKnox.Executor.runs["lk-1"]'))
        idle = self.ev('LivingKnox.Config.REPORTS.IDLE_MS')
        states = self.ev('LivingKnox.Executor.stats.states')
        received = self.r('stats.received')
        self.run_lua('UNLOAD(90, 120, 90, 120)')                            # joueur toujours proche : pas de retrait
        self.assertIsNotNone(self.ev('LivingKnox.Bodies.bound["lk-1"]'))
        for _ in range(4):
            self.h.advance_ms(idle + 100)
            self.exec_pass()
        self.assertEqual(self.ev('LivingKnox.Executor.stats.states'), states)
        self.assertEqual(self.r('stats.received'), received)
        self.assertIsNone(self.ev('LivingKnox.Executor.runs["lk-1"]'))   # exécution lâchée
        self.assertEqual(self.npc_state(), 'embodied')
        self.run_lua('RELOAD()')
        zid = self.ev('LivingKnox.Bodies.bound["lk-1"]:getOnlineID()')     # nouvel onlineId au retour
        self.exec_pass()
        self.assertGreater(self.r('stats.received'), received)
        self.walk(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())
        self.assertEqual([w for w in self.refused() if 'no body' in w], [])
        self.assertEqual(self.h.errors('solo'), [])

    def npc_state(self):
        return self.ev('LivingKnox.Store.data().npcs["lk-1"].state')


class ReleaseBase(ReportBase):
    """LK03-T04 : corps loin des joueurs rendu à la simulation abstraite (LK_Bodies.releasePass). Registres des corps,
    des groupes (type settlers chargé) et des armes ; rapports d'état chargés (santé acceptée)."""

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, EQUIP_DOUBLES)
            h.load(m, EQUIPMENT)
            h.load(m, 'shared/LivingKnox/Data/LK_Type_settlers.lua')
        return h

    def release_pass(self):
        """Images d'un passage de retrait (RELEASE_EVERY tranches de SCAN_EVERY images, 0,96 s au banc)."""
        self.h.tick(self.ev('LivingKnox.Bodies.SCAN_EVERY * LivingKnox.Bodies.RELEASE_EVERY'))

    def wait(self, seconds):
        """Laisse passer environ seconds secondes réelles, un passage de retrait toutes les 5 s (sous RELEASE_GAP_MS)."""
        for _ in range(max(1, round(seconds / 5))):
            self.h.advance_ms(4040)
            self.release_pass()

    def npc_field(self, field):
        return self.ev(f'LivingKnox.Store.data().npcs["lk-1"].{field}')

    def group(self):
        """Groupe settlers dont un membre est lié au PNJ lk-1 ; rend (groupe, membre)."""
        gid, mid = self.run_lua('local G = LivingKnox.Groups '
                                'local g = assert(G.create({ type = "settlers", name = "Mill", day = 1 })) '
                                'return g.id, assert(G.addMember(g.id, { role = "worker", npc = "lk-1", day = 1 }))')
        return gid, mid

    def assert_released(self, gid, mid, hp):
        self.assertEqual(self.npc_field('state'), 'virtual')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)                     # aucun corps dans le monde
        self.assertIsNone(self.ev('LivingKnox.Bodies.bound["lk-1"]'))
        self.assertIsNone(self.ev('LivingKnox.Directives.entries["lk-1"]'))
        self.assertIsNone(self.ev('LivingKnox.Reports.get("lk-1")'))
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.assertAlmostEqual(self.npc_field('hp'), hp, places=6)
        self.assertEqual(self.npc_field('weapon'), 'Base.Shotgun')         # équipement gardé au registre
        self.assertIsNotNone(self.ev('LivingKnox.Identity.validate(LivingKnox.Store.data())'))
        # Registre des groupes : membre toujours présent, vivant, lien npc intact.
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Groups.findNpc("lk-1") }')), [gid, mid])
        self.assertIs(self.ev(f'LivingKnox.Groups.get("{gid}").members["{mid}"].alive'), True)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").members["{mid}"].npc'), 'lk-1')
        # Aucun orphelin : un balayage complet ne retire rien.
        self.run_lua('LivingKnox.Bodies.scanAll()')
        self.assertEqual([line for line in self.lk() if 'orphan' in line], [])


class MultiplayerReleaseTests(ReleaseBase):
    ready = OwnershipHandoverTests.ready

    def leave(self, x=400, y=400):
        for c in ('A', 'B'):
            self.h.move_player(c, x, y)

    def test_far_body_released_with_its_state_and_its_group_link(self):
        zid = self.ready('A')
        gid, mid = self.group()
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun") }')), [True])
        self.assertEqual(self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})'), 1)
        self.h.pump()
        self.h.load('A', f'HARNESS.zombies[{zid}].health = 1.5')           # coup encaissé chez le propriétaire
        self.walk(zid, 60)
        self.assertAlmostEqual(self.state('hp'), 1.5, places=6)
        # Les joueurs s'éloignent : le serveur simule le corps, la consigne est suspendue, le corps au repos.
        self.leave()
        self.h.set_owner(zid, 'server')
        self.h.tick(1)
        self.h.pump()
        self.assertIsNotNone(self.entry('suspended'))
        self.wait(50)
        self.assertEqual(self.npc_field('state'), 'embodied')              # délai pas encore écoulé
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        seen = self.h.zombie('server', zid).x
        self.wait(15)
        self.assert_released(gid, mid, 1.5)
        self.assertLessEqual(abs(self.npc_field('last.x') - seen), 1)    # position approximative (case)
        lines = [line for line in self.lk() if 'released to the offscreen simulation' in line]
        self.assertEqual(len(lines), 1, self.lk())
        self.assertIn('body removed', lines[0])
        self.assertIn('directive move #1 abandoned', lines[0])
        self.assertIn('weapon Base.Shotgun', lines[0])
        self.h.pump()
        for c in ('A', 'B'):                                                # plus aucune consigne chez les clients
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Executor.remote.d["lk-1"]'))
        # Le PNJ continue en abstrait : une nouvelle incarnation reprend son identité et son lien de groupe.
        self.h.move_player('A', 100, 100)
        body = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertIsNotNone(body)
        self.assertEqual(self.npc_field('generation'), 2)
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Groups.findNpc("lk-1") }')), [gid, mid])
        self.assertEqual(self.r('stats.rejected'), 0, self.refused())

    def test_body_seen_by_a_player_is_never_released_and_the_delay_restarts(self):
        zid = self.ready('server')                                          # serveur propriétaire, joueurs proches
        gid, mid = self.group()
        self.run_lua('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        self.wait(70)
        self.assertEqual(self.npc_field('state'), 'embodied')              # vu de A : jamais retiré, au repos
        self.assertIsNotNone(self.entry('suspended'))
        srv = self.h.zombie('server', zid)
        self.assertEqual((srv.x, srv.y), (102.5, 102.5))
        # Joueurs partis 40 s, puis A revient au bord du rayon (118 cases) : le délai repart de zéro.
        self.leave()
        self.wait(40)
        self.h.move_player('A', 220, 102)
        self.wait(5)
        self.leave()
        self.wait(40)
        self.assertEqual(self.npc_field('state'), 'embodied')
        self.wait(25)
        self.assert_released(gid, mid, 2)                                  # santé de la copie du serveur

    def test_client_owned_body_is_never_released(self):
        zid = self.ready('A')
        self.leave()                                                        # propriétaire désigné par le moteur
        self.wait(70)
        self.assertEqual(self.npc_field('state'), 'embodied')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        self.assertEqual(self.h.owners[zid], 'A')

    def test_pause_does_not_count_in_the_delay(self):
        self.ready('server')
        self.leave()
        self.wait(50)
        self.h.advance_ms(30000)                                            # serveur figé (pause, PauseEmpty)
        self.release_pass()
        self.wait(50)
        self.assertEqual(self.npc_field('state'), 'embodied')
        self.wait(15)
        self.assertEqual(self.npc_field('state'), 'virtual')

    def test_body_out_of_the_loaded_area_released_then_removed_as_an_orphan_on_return(self):
        zid = self.ready('A')
        gid, mid = self.group()
        self.walk(zid, 400, until=lambda: self.state('hp') is not None)  # un rapport d'état accepté
        self.run_lua('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")')
        self.h.move_player('A', 210, 102)                                   # 108 cases : encore proche
        self.h.move_player('B', 400, 400)
        self.run_lua('UNLOAD(90, 120, 90, 120)')                            # corps mis de côté sur le serveur
        self.assertIsNone(self.ev('(LivingKnox.Bodies.find("lk-1"))'))
        self.wait(70)
        self.assertEqual(self.npc_field('state'), 'embodied')              # dernière position vue proche de A
        self.h.move_player('A', 400, 400)
        self.wait(65)
        self.assertEqual(self.npc_field('state'), 'virtual')
        lines = [line for line in self.lk() if 'released to the offscreen simulation' in line]
        self.assertEqual(len(lines), 1, self.lk())
        self.assertIn('body out of the loaded area', lines[0])
        self.assertEqual(self.npc_field('hp'), 2)                           # dernier rapport accepté pour ce corps
        # Retour de la zone : le corps mis de côté revient et le balayage le retire comme orphelin.
        self.run_lua('RELOAD()')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        self.run_lua('LivingKnox.Bodies.scanAll()')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)
        self.assertTrue(any('orphan lk-1' in line and 'notEmbodied' in line for line in self.lk()), self.lk())
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Groups.findNpc("lk-1") }')), [gid, mid])
        self.assertEqual(self.npc_field('state'), 'virtual')


class SoloReleaseTests(ReleaseBase):
    mode = 'solo'

    def test_solo_body_far_from_the_player_is_released(self):
        self.init()
        npc_id, body = self.spawn()
        self.assertEqual(npc_id, 'lk-1')
        gid, mid = self.group()
        self.run_lua('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]})')
        body.health = 1.25
        self.walk(body.onlineID, 30)
        self.wait(70)
        self.assertEqual(self.npc_field('state'), 'embodied')              # joueur proche : jamais retiré
        self.h.move_player('A', 400, 400)
        self.wait(65)
        self.assert_released(gid, mid, 1.25)

    def test_solo_body_set_aside_far_from_the_player_is_released(self):
        self.init()
        self.spawn()
        gid, mid = self.group()
        self.run_lua('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")')
        self.run_lua('UNLOAD(90, 120, 90, 120)')                            # hors de la zone chargée du joueur
        self.h.move_player('A', 400, 400)
        self.wait(65)
        self.assertEqual(self.npc_field('state'), 'virtual')
        self.run_lua('RELOAD()')
        self.run_lua('LivingKnox.Bodies.scanAll()')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Groups.findNpc("lk-1") }')), [gid, mid])


class ExecutorSuiteReportTests(MilestoneBase):
    """Suite en jeu lk.executor sur les doublures (solo), rapports d'état chargés : test de la marche de 9 cases."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', REPORT_DOUBLES)
        h.load('solo', REPORTS)
        return h

    def test_move_test_counts_accepted_state_reports(self):
        self.init(new_world=True)
        self.h.load('solo', 'shared/RST/suites/RST_LKExecutor.lua')
        report, results = self.run_suite('{ suite = "lk.executor", tags = "world", test = "move 9" }')
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, results)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKX] measure state reports')]
        self.assertEqual(len(lines), 1, self.h.logs('solo'))
        self.assertRegex(lines[0], r'during the move: \d+ accepted, 0 refused, last arrived pose stand health 2 by A')


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_no_body_moved(self):
        for rel in (REPORTS, EXECUTOR):
            text = (LUA / rel).read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{rel}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{rel}: {pattern}')
        code = re.sub(r'--[^\n]*', '', (LUA / REPORTS).read_text(encoding='utf-8'))
        for call in ('pathToLocation', 'setX', 'setY', 'setZ', 'teleportTo', 'setHealth', 'setMoving'):
            self.assertNotIn(call, code)
        self.assertIn('if isClient() then return Reports end', code)


if __name__ == '__main__':
    unittest.main()
