"""Fiche d'un PNJ par clic droit, besoins et santé modifiables (LK13-T13) : opérations npc / npcSet de LK_Admin.lua
(autorité) et fenêtre client LK_NpcSheet.lua.

    python RadioSurvivor/tests/test_lk_npcsheet.py

Banc tests/harness.py, pile complète des corps (MatBase de test_lk_materialize.py, type « deciders » de
test_lk_decisions.py : groupes, matérialisation, consignes, rapports, santé, besoins, cascade) :
- MP (serveur dédié + clients A admin et B sans la capacité) : refus sans donnée ni écriture pour B, fiche complète
  pour A par le réseau, bornes, note au journal du groupe, faim réglée lue au passage de décision suivant, relecture
  toutes les 2 s fiche ouverte et aucun message fiche fermée ;
- solo : refus sans le mode debug (sans donnée ni écriture), appel direct avec le mode debug, option du clic droit
  présente seulement avec le droit, corps cliqué reconnu.
- LK13-T15 : sections étiquetées et champs préremplis ; actions npcRole / npcName / npcGoto refusées à un client sans
  la capacité, rôle borné aux rôles du type, nom borné (client et autorité), téléportation (/teleportto en MP, déplacement
  par l'autorité en solo, dernière position connue, refus sans position), nom repris par le fournisseur du carnet.
Doublures de droits : celles de test_lk_admin.py (checkPermissions et getRole():hasCapability lisent ADMINS). Elles
ne prouvent pas l'API réelle (suite en jeu lk.npcsheet).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA  # noqa: E402
from test_lk_admin import CLIENT_TEXT, PERMISSIONS, role_for  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import DECIDERS, DUMP  # noqa: E402
from test_lk_health import HEALTH, HEALTH_DOUBLES  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402

ADMIN_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Admin.lua'
SHEET_FILE = LUA / 'client' / 'LivingKnox' / 'LK_NpcSheet.lua'
TRANSLATE = LUA / 'shared' / 'Translate'
SUITE = 'shared/RST/suites/RST_LKNpcSheet.lua'
SUITE_FILE = Path(__file__).resolve().parents[1] / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE
A = 'LivingKnox.Admin'
S = 'LivingKnox.NpcSheet'
D = 'LivingKnox.Decisions'

# Menu contextuel minimal (ISContextMenu:addOption) et objets cliqués (IsoObject:getSquare).
MENU = r'''
function MENU()
    local m = { options = {} }
    function m:addOption(name, target, fn, a, b) self.options[#self.options + 1] = { name = name, target = target,
        fn = fn, a = a, b = b } return self.options[#self.options] end
    return m
end
function CLICKED(x, y, z)
    local sq = getCell():getGridSquare(x, y, z or 0)
    return { { getSquare = function() return sq end } }
end
'''


class SheetBase(MatBase):
    CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false')]

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            h.load(m, DECIDERS)
            h.load(m, HEALTH_DOUBLES)
            h.load(m, HEALTH)
            h.load(m, PERMISSIONS)
            # Mode debug réglable par le test (le banc le fixe à sa création).
            h.load(m, 'DBG = true isDebugEnabled = function() return DBG == true end')
            h.load(m, 'server/LivingKnox/LK_Admin.lua')
        h.load(self.srv, DUMP)
        h.load(self.srv, 'ADMINS.A = true local l = getOnlinePlayers() '
                         'for i = 0, l:size() - 1 do GIVE_ROLE(l:get(i)) end')
        for c in (['solo'] if self.mode == 'solo' else ['A', 'B']):
            h.load(c, CLIENT_TEXT)
            h.load(c, MENU)
            h.load(c, 'client/LivingKnox/LK_AdminView.lua')
            h.load(c, 'client/LivingKnox/LK_NpcSheet.lua')
        if self.mode == 'mp':
            h.load('A', role_for(True))
            h.load('B', role_for(False))
        return h

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')   # aucune décision pendant la matérialisation
        self.h.move_player('A', 100, 100)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() {D}.state.lastPass = nil')
        return gid

    def npc_of(self, gid, mid):
        return self.member(gid, mid, 'npc')

    def dpass(self, n=1):
        # LK13-T11 : les membres d'un passage sont évalués un par image (MEMBERS_PER_FRAME) : quatre images.
        for _ in range(n):
            self.h.advance_ms(1000)
            self.h.tick(4)

    def seq(self):
        self.run_lua('LivingKnox.Groups.flush()')
        return self.ev('LivingKnox.Groups.state.seq')

    def admin_log(self, gid):
        g = self.ev(f'LivingKnox.Groups.get("{gid}")')
        return [g.log[i].text for i in range(1, len(g.log) + 1) if g.log[i].kind == 'admin']

    def vitals(self, gid, mid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").members["{mid}"].vitals')


class MPTests(SheetBase):
    def test_non_admin_client_gets_refusals_without_data_and_nothing_is_written(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.assertFalse(self.h.eval('B', f'{S}.canUse()'))
        seq = self.seq()
        hp = self.npc(gid, 'm-2', 'hp')
        self.h.load('B', 'GOT = {} local base = LivingKnox.NpcSheet.onServerCommand '
                         'LivingKnox.NpcSheet.onServerCommand = function(m, c, a) '
                         'if c == "adminReply" then GOT[#GOT + 1] = a end return base(m, c, a) end')
        self.h.load('B', f'{S}.state.npc = "{npc}" {S}.send("npc", {{ npc = "{npc}" }}) '
                         f'{S}.set("hunger", 99) {S}.set("health", 5)')
        self.h.pump()
        self.h.pump()
        got = lua_list(self.h.eval('B', 'GOT'))
        self.assertEqual(len(got), 3)
        for a in got:
            self.assertEqual(sorted(a.keys()), ['err', 'n', 'ok', 'op'])
            self.assertEqual(a.err, 'denied')
        self.assertEqual(self.h.eval('B', f'{S}.state.status'), 'IGUI_LK_Sheet_Denied')
        self.assertIsNone(self.h.eval('B', f'{S}.state.data'))
        self.assertEqual(self.seq(), seq)
        self.assertIsNone(self.vitals(gid, 'm-2'))
        self.assertEqual(self.npc(gid, 'm-2', 'hp'), hp)
        self.assertEqual(self.admin_log(gid), [])
        self.assertTrue(any('admin: request npcSet refused for B' in line for line in self.h.logs('server')))
        # Le client MP ne décide jamais : la garde de LK_Admin s'arrête avant les données.
        self.assertIsNone(self.h.eval('A', f'{A}.npcView'))

    def test_admin_reads_the_whole_sheet_through_the_network(self):
        gid = self.mk()
        self.dpass(2)
        npc = self.npc_of(gid, 'm-2')
        self.assertTrue(self.h.eval('A', f'{S}.canUse()'))
        self.h.load('A', f'{S}.state.npc = "{npc}" {S}.refresh()')
        self.h.pump()
        self.h.pump()
        d = self.h.eval('A', f'{S}.state.data')
        self.assertIsNotNone(d)
        self.assertEqual((d.id, d.gid, d.mid, d.group, d.type, d.role, d.profile),
                         (npc, gid, 'm-2', 'Mill', 'deciders', 'worker', 'cook'))
        self.assertIs(d.leader, False)
        self.assertEqual(d.leaderId, 'm-1')
        self.assertIs(d.embodied, True)
        self.assertEqual(d.state, 'embodied')
        self.assertEqual((d.home.x, d.home.y, d.home.z), (110, 110, 0))
        x, y = self.body_xy(gid, 'm-2')
        self.assertAlmostEqual(d.pos.x, x, delta=0.06)
        self.assertAlmostEqual(d.pos.y, y, delta=0.06)
        self.assertEqual((d.needs.hunger, d.needs.thirst, d.needs.fatigue, d.needs.fear), (20, 20, 20, 0))
        self.assertEqual(d.envy.hunger, 70)
        self.assertEqual(d.health.pct, 100)
        self.assertEqual(d.health.bleedPct, 0)
        self.assertIsNotNone(d.decision)
        self.assertIsInstance(d.decision.b, str)
        self.assertIsInstance(d.decision.rule, str)
        self.assertEqual(d.weapon.t, 'Base.KitchenKnife')
        self.assertEqual(d.wound, 0)
        # LK13-T15 : sections étiquetées, nombres arrondis, santé en %, rôles du type, champs préremplis.
        secs = lua_list(self.h.eval('A', f'{S}.sections({S}.state.data)'))
        self.assertEqual([s.title for s in secs], [f'IGUI_LK_Sheet_Sec_{k}' for k in (
            'Identity', 'Needs', 'Health', 'Behaviour', 'Perception', 'Equipment')])
        rows = {r[1]: r[2] for s in secs for r in lua_list(s.rows)}
        self.assertEqual(rows['IGUI_LK_Sheet_L_Health'], '100 %')
        self.assertEqual(rows['IGUI_LK_Sheet_Field_hunger'], 'IGUI_LK_Sheet_NeedCell|20|70')
        self.assertEqual(rows['IGUI_LK_Sheet_L_Weapon'], 'Base.KitchenKnife')
        self.assertEqual(rows['IGUI_LK_Sheet_L_Role'], 'worker / cook')
        self.assertEqual(lua_list(d.roles), ['fighter', 'scout', 'medic', 'worker'])
        for field, value in (('hunger', '20'), ('fear', '0'), ('health', '100'), ('bleed', '0'), ('wound', '0')):
            self.assertEqual(self.h.eval('A', f'{S}.fieldValue({S}.state.data, "{field}")'), value, field)
        self.assertEqual(self.h.errors('server'), [])
        self.assertEqual(self.h.errors('A'), [])

    def test_bounded_settings_logged_in_the_group_journal_and_read_by_the_next_decision(self):
        gid = self.mk()
        self.dpass(2)
        npc = self.npc_of(gid, 'm-2')
        self.assertNotEqual(self.ev(f'{D}.get("{npc}").rule'), 'hunger')
        self.h.load('A', f'{S}.state.npc = "{npc}" {S}.set("hunger", 150)')
        self.h.pump()
        self.h.pump()
        self.assertEqual(self.h.eval('A', f'{S}.state.data.needs.hunger'), 100)       # borné
        self.assertEqual(self.h.eval('A', f'{S}.state.status'), 'IGUI_LK_Sheet_SetDone|IGUI_LK_Sheet_Field_hunger|20|100')
        self.assertEqual(self.vitals(gid, 'm-2').hunger, 100)
        self.assertEqual(self.admin_log(gid), [f'hunger m-2 ({npc}) 20 -> 100 set by admin A'])
        self.dpass(1)                                                                 # passage de décision suivant
        self.assertEqual((self.ev(f'{D}.get("{npc}").rule'), self.ev(f'{D}.get("{npc}").why')), ('hunger', 'hunger 100'))
        # Autres bornes : peur négative, santé, saignement, blessure, champ inconnu, valeur non numérique.
        cases = [('fear', -20, 0), ('health', 0, 1), ('health', 250, 100), ('health', 42.25, 42.3), ('bleed', 500, 60),
                 ('bleed', 12.5, 12.5), ('wound', 400, 99), ('wound', 0, 0)]
        for field, value, expected in cases:
            with self.subTest(field=field, value=value):
                r = self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "npcSet", n = 1, npc = "{npc}", '
                            f'field = "{field}", value = {value} }})')
                self.assertTrue(r.ok, r.err)
                self.assertEqual(r.value, expected)
        self.assertAlmostEqual(self.npc(gid, 'm-2', 'hp') / self.npc(gid, 'm-2', 'hpMax'), 0.423, places=3)
        self.assertAlmostEqual(self.npc(gid, 'm-2', 'bleed'), 0.125, places=6)
        self.assertIsNone(self.member(gid, 'm-2', 'wound'))
        for field, value, err in (('morale', 5, 'unknown field'), ('hunger', '"x"', 'bad value'),
                                  ('hunger', '0/0', 'bad value')):
            r = self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "npcSet", n = 1, npc = "{npc}", '
                        f'field = "{field}", value = {value} }})')
            self.assertEqual((r.ok, r.err), (False, err))
        r = self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "npc", n = 1, npc = "lk-999" }})')
        self.assertEqual(r.err, 'npc lk-999 is not in a group')
        self.assertEqual(len(self.admin_log(gid)), 1 + len(cases))
        self.assertEqual(self.h.errors('server'), [])

    def test_refresh_every_two_seconds_while_open_and_nothing_once_closed(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-1')

        def requests():
            return [m for m in self.h.pending() if m.get('command') == 'adminRequest']

        # Fiche fermée : aucune relecture.
        self.h.load('A', f'{S}.state.npc = "{npc}"')
        self.assertFalse(self.h.eval('A', f'{S}.poll(getTimestampMs())'))
        self.assertEqual(requests(), [])
        # Fiche ouverte : une requête, puis rien avant 2 s, puis une autre.
        self.h.load('A', f'{S}.state.window = {{}}')
        self.assertTrue(self.h.eval('A', f'{S}.poll(getTimestampMs())'))
        self.assertEqual(len(requests()), 1)
        self.h.pump()
        self.h.pump()
        self.assertFalse(self.h.eval('A', f'{S}.poll(getTimestampMs() + 1999)'))
        self.assertTrue(self.h.eval('A', f'{S}.poll(getTimestampMs() + 2000)'))
        self.assertEqual(len(requests()), 1)
        self.assertFalse(self.h.eval('A', f'{S}.poll(getTimestampMs() + 9000)'))     # réponse attendue
        self.h.pump()
        self.h.pump()
        # Fermée : plus rien, même longtemps après.
        self.h.load('A', f'{S}.closed({S}.state.window)')
        self.assertFalse(self.h.eval('A', f'{S}.poll(getTimestampMs() + 60000)'))
        self.assertEqual(requests(), [])
        self.assertIsNone(self.h.eval('A', f'{S}.state.npc'))
        # Une réponse de la fiche n'est pas comptée comme périmée par la fenêtre des groupes.
        self.assertEqual(self.h.eval('A', 'LivingKnox.AdminView.stats.stale'), 0)


class SoloTests(SheetBase):
    mode = 'solo'

    def test_solo_requires_the_debug_mode(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.run_lua('DBG = false')
        self.assertFalse(self.ev(f'{S}.canUse()'))
        seq = self.seq()
        self.run_lua(f'{S}.state.npc = "{npc}" {S}.refresh() {S}.set("hunger", 90)')
        self.assertEqual(self.h.pending(), [])                                         # aucune commande réseau
        self.assertEqual(self.ev(f'{S}.state.status'), 'IGUI_LK_Sheet_Denied')
        self.assertIsNone(self.ev(f'{S}.state.data'))
        self.assertEqual(self.seq(), seq)
        self.assertIsNone(self.vitals(gid, 'm-2'))
        self.assertTrue(any('refused for' in line and 'debug mode off' in line for line in self.h.logs('solo')))
        # Les autres opérations de l'outil restent ouvertes au joueur solo (décision de LK13-T01).
        self.assertTrue(self.ev(f'{A}.request(getSpecificPlayer(0), {{ op = "list", n = 1 }}).ok'))
        self.run_lua('DBG = true')
        self.assertTrue(self.ev(f'{S}.canUse()'))
        self.run_lua(f'{S}.set("thirst", 77)')
        self.assertEqual(self.ev(f'{S}.state.data.needs.thirst'), 77)
        self.assertEqual(self.vitals(gid, 'm-2').thirst, 77)

    def test_context_menu_option_only_with_the_right_on_a_clicked_body(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        x, y = self.body_xy(gid, 'm-2')
        clicked = f'CLICKED({int(x)}, {int(y)}, 0)'
        self.run_lua('DBG = false')
        self.run_lua(f'M = MENU() {S}.fill(0, M, {clicked}, false)')
        self.assertEqual(self.ev('#M.options'), 0)
        self.run_lua('DBG = true')
        self.assertEqual(self.ev(f'{S}.bodyNear(getSpecificPlayer(0), {clicked})'), npc)
        self.run_lua(f'M = MENU() {S}.fill(0, M, CLICKED(300, 300, 0), false)')
        self.assertEqual(self.ev('#M.options'), 0)                                     # aucun corps près du clic
        self.run_lua(f'M = MENU() {S}.fill(0, M, {clicked}, false)')
        self.assertEqual(self.ev('#M.options'), 1)
        self.assertEqual(self.ev('M.options[1].name'), 'IGUI_LK_Sheet_Menu')
        self.assertEqual(self.ev('M.options[1].a'), npc)


# LK13-T15 : doublures de la téléportation. Client : capacité TeleportToCoordinates (TeleportToCommand.java:24) et
# commande de chat SendCommandToServer notée ; solo : teleportTo du joueur noté (IsoGameCharacter.java:15069-15079).
TELEPORT_RIGHT = r'''
Capability.TeleportToCoordinates = 'cap:TeleportToCoordinates'
TP_RIGHT = true
local p = getSpecificPlayer(0)
local base = p.getRole
p.getRole = function(self)
    local r = base(self)
    return { hasCapability = function(_, c)
        if c == Capability.TeleportToCoordinates then return TP_RIGHT == true end
        return r:hasCapability(c)
    end }
end
SENT_CMDS = {}
SendCommandToServer = function(c) SENT_CMDS[#SENT_CMDS + 1] = c end
'''
SOLO_TELEPORT = r'''
Capability = Capability or {}
SENT_CMDS = {}
SendCommandToServer = function(c) SENT_CMDS[#SENT_CMDS + 1] = c end
TP = nil
getSpecificPlayer(0).teleportTo = function(self, x, y, z) TP = { x = x, y = y, z = z } end
'''


class ActionsMPTests(SheetBase):
    """Actions d'administration de LK13-T15 : rôle, prénom et nom, téléportation (autorité, droits, bornes)."""

    def req(self, op, **fields):
        args = ', '.join(f'{k} = {v}' for k, v in fields.items())
        return self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "{op}", n = 1, {args} }})')

    def test_each_action_is_refused_to_a_non_admin_without_data_or_write(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        seq = self.seq()
        self.h.load('B', 'GOT = {} local base = LivingKnox.NpcSheet.onServerCommand '
                         'LivingKnox.NpcSheet.onServerCommand = function(m, c, a) '
                         'if c == "adminReply" then GOT[#GOT + 1] = a end return base(m, c, a) end')
        self.h.load('B', f'{S}.state.npc = "{npc}" {S}.setRole("fighter") {S}.rename("Jane", "Doe") '
                         f'{S}.send("npcGoto", {{ npc = "{npc}" }})')
        self.h.pump()
        self.h.pump()
        got = lua_list(self.h.eval('B', 'GOT'))
        self.assertEqual(sorted(a.op for a in got), ['npcGoto', 'npcName', 'npcRole'])
        for a in got:
            self.assertEqual(sorted(a.keys()), ['err', 'n', 'ok', 'op'])
            self.assertEqual(a.err, 'denied')
        self.assertEqual(self.seq(), seq)
        self.assertEqual(self.member(gid, 'm-2', 'role'), 'worker')
        self.assertIsNone(self.member(gid, 'm-2', 'firstName'))
        self.assertEqual(self.admin_log(gid), [])
        logs = self.h.logs('server')
        for op in ('npcRole', 'npcName', 'npcGoto'):
            self.assertTrue(any(f'admin: request {op} refused for B' in line for line in logs), op)
        # Sans la capacité de téléportation, la fiche ne demande rien (message clair).
        self.h.load('B', TELEPORT_RIGHT)
        self.h.load('B', f'TP_RIGHT = false {S}.teleport("{npc}")')
        self.assertEqual(self.h.eval('B', f'{S}.state.status'), 'IGUI_LK_Sheet_GotoNoRight')
        self.assertEqual([m for m in self.h.pending() if m.get('command') == 'adminRequest'], [])

    def test_role_changed_within_the_roles_of_the_group_type(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.h.load('A', f'{S}.state.npc = "{npc}" {S}.setRole("fighter")')
        self.h.pump()
        self.h.pump()
        self.assertEqual(self.member(gid, 'm-2', 'role'), 'fighter')
        self.assertEqual(self.h.eval('A', f'{S}.state.data.role'), 'fighter')
        self.assertEqual(self.h.eval('A', f'{S}.state.status'),
                         'IGUI_LK_Sheet_SetDone|IGUI_LK_Sheet_Field_role|worker|fighter')
        self.assertEqual(self.admin_log(gid), [f'role m-2 ({npc}) worker -> fighter set by admin A'])
        self.assertTrue(any(f'admin: A set the role of {npc}' in line for line in self.h.logs('server')))
        for role, err in (('"deputy"', 'role deputy is not a role of type deciders'),
                          ('"breaker"', 'role breaker is not a role of type deciders'),
                          ('"king"', 'role king is not a role of type deciders'),
                          ('"fighter"', 'role unchanged'), ('5', 'bad role')):
            r = self.req('npcRole', npc=f'"{npc}"', role=role)
            self.assertEqual((r.ok, r.err), (False, err))
        self.assertEqual(len(self.admin_log(gid)), 1)

    def test_first_and_last_name_bounded_and_never_interpreted(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        # Contrôle côté client avant envoi : aucun message pour un nom invalide.
        self.h.load('A', f'{S}.state.npc = "{npc}" {S}.rename("J4ne", "Doe")')
        self.assertEqual(self.h.eval('A', f'{S}.state.status'), 'IGUI_LK_Sheet_BadName')
        self.assertEqual([m for m in self.h.pending() if m.get('command') == 'adminRequest'], [])
        self.h.load('A', f'{S}.rename("  Mary   Ann ", "O\'Neil-Smith")')
        self.h.pump()
        self.h.pump()
        self.assertEqual((self.member(gid, 'm-2', 'firstName'), self.member(gid, 'm-2', 'lastName')),
                         ('Mary Ann', "O'Neil-Smith"))
        d = self.h.eval('A', f'{S}.state.data')
        self.assertEqual((d.name, d.named, d.firstName, d.lastName), ("Mary Ann O'Neil-Smith", True, 'Mary Ann',
                                                                       "O'Neil-Smith"))
        self.assertEqual(len(self.admin_log(gid)), 1)
        self.assertIn("-> Mary Ann O'Neil-Smith set by admin A", self.admin_log(gid)[0])
        # Autorité : bornes revérifiées (texte vide, chiffres, balise, trop long, non texte, non ASCII).
        for first in ('""', '"   "', '"J4ne"', '"<RGB:1,0,0>Bob"', '"' + 'a' * 25 + '"', '12', '"\\195\\169lise"'):
            r = self.req('npcName', npc=f'"{npc}"', first=first, last='"Doe"')
            self.assertEqual((r.ok, r.err), (False, 'bad name'), first)
        r = self.req('npcName', npc=f'"{npc}"', first='"' + 'a' * 24 + '"', last='"Doe"')
        self.assertTrue(r.ok, r.err)
        r = self.req('npcName', npc=f'"{npc}"', first='"' + 'a' * 24 + '"', last='"Doe"')
        self.assertEqual(r.err, 'name unchanged')
        self.assertEqual(self.h.errors('server'), [])

    def test_teleport_by_teleportto_next_to_the_body_or_to_the_last_known_position(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.h.load('A', TELEPORT_RIGHT)
        self.h.load('A', f'{S}.teleport("{npc}")')
        self.h.pump()
        self.h.pump()
        sent = lua_list(self.h.eval('A', 'SENT_CMDS'))
        self.assertEqual(len(sent), 1)
        m = re.fullmatch(r'/teleportto (-?\d+),(-?\d+),(-?\d+)', sent[0])
        self.assertIsNotNone(m, sent)
        x, y = self.body_xy(gid, 'm-2')
        self.assertLessEqual(abs(int(m.group(1)) - int(x)), 1)
        self.assertLessEqual(abs(int(m.group(2)) - int(y)), 1)
        self.assertEqual(self.h.eval('A', f'{S}.state.status'), f'IGUI_LK_Sheet_GotoDone|{sent[0][12:]}')
        self.assertTrue(any(t.startswith(f'teleport of admin A to m-2 ({npc}) at ') for t in self.admin_log(gid)))
        self.assertTrue(any(f'admin: A teleported to {npc}' in line for line in self.h.logs('server')))
        # Hors écran : dernière position connue, sinon refus clair.
        self.run_lua(f'LivingKnox.Bodies.find = function() return nil end '
                     f'LivingKnox.Store.data().npcs["{npc}"].last = {{ x = 5.5, y = 6.2, z = 0 }}')
        r = self.req('npcGoto', npc=f'"{npc}"')
        self.assertTrue(r.ok, r.err)
        self.assertEqual((r.dest.x, r.dest.y, r.dest.z, r.dest.last, r.moved), (5, 6, 0, True, False))
        self.assertEqual(r.dest.src, 'last')
        # LK13-T16 : sans dernière position, le foyer du groupe (110,110,0) ; refus seulement sans foyer non plus.
        self.run_lua(f'LivingKnox.Store.data().npcs["{npc}"].last = nil')
        r = self.req('npcGoto', npc=f'"{npc}"')
        self.assertTrue(r.ok, r.err)
        self.assertEqual((r.dest.src, r.dest.last, r.dest.z), ('home', False, 0))
        self.assertLessEqual(max(abs(r.dest.x - 110), abs(r.dest.y - 110)), 1)
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].home = nil')
        r = self.req('npcGoto', npc=f'"{npc}"')
        self.assertEqual((r.ok, r.err), (False, 'no known position'))


class ActionsSoloTests(SheetBase):
    mode = 'solo'

    def test_solo_teleport_moves_the_player_on_the_authority(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.run_lua(SOLO_TELEPORT)
        self.run_lua(f'{S}.teleport("{npc}")')
        tp = self.ev('TP')
        self.assertIsNotNone(tp)
        x, y = self.body_xy(gid, 'm-2')
        self.assertLessEqual(abs(tp.x - int(x)), 1)
        self.assertLessEqual(abs(tp.y - int(y)), 1)
        self.assertEqual(lua_list(self.ev('SENT_CMDS')), [])
        self.assertTrue(self.ev(f'{S}.state.status').startswith('IGUI_LK_Sheet_GotoDone|'))
        # Sans le mode debug : refus.
        self.run_lua('DBG = false TP = nil')
        self.run_lua(f'{S}.teleport("{npc}")')
        self.assertIsNone(self.ev('TP'))
        self.assertEqual(self.ev(f'{S}.state.status'), 'IGUI_LK_Sheet_Denied')

    def test_given_name_reaches_the_notebook_provider(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.h.load('solo', 'shared/RadioSurvivor/RS_LivingKnox.lua')
        self.assertTrue(self.ev(f'{A}.hookNames()'))
        self.assertTrue(self.ev(f'{A}.hookNames()'))                      # une seule enveloppe
        drawn = self.ev(f'RS_LivingKnox.npc("{npc}").name')
        self.assertIsInstance(drawn, str)
        view = self.ev(f'{A}.npcView("{npc}").npc')
        self.assertEqual((view.name, view.named), (drawn, False))
        self.assertEqual(f'{view.firstName} {view.lastName}', drawn)
        self.run_lua(f'{S}.state.npc = "{npc}" {S}.rename("Jane", "Doe")')
        self.assertEqual(self.ev(f'RS_LivingKnox.npc("{npc}").name'), 'Jane Doe')
        self.assertEqual(self.ev(f'{A}.npcView("{npc}").npc.name'), 'Jane Doe')
        self.assertEqual(self.ev(f'{A}.activity("{gid}", 0).group.members[2].name'), 'Jane Doe')


class SuiteTests(SheetBase):
    """Suite en jeu lk.npcsheet exécutée par le vrai moteur RST sur les doublures du banc (solo, mode debug)."""
    mode = 'solo'

    def run_suite(self):
        self.h.move_player('A', 110, 110)
        self.h.load('solo', SOLO_TELEPORT)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.npcsheet", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(3000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
        report = self.h.eval('solo', 'RST.last()')
        return report, [(r.test, r.status, r.message) for r in lua_list(report.results)]

    def test_suite_lk_npcsheet_passes_on_the_doubles(self):
        report, results = self.run_suite()
        self.assertEqual(len(results), 6, results)
        # Fenêtre solo (2026-10-15) : client solo du jeu seulement (aucune fenêtre sur ce banc, SKIP ici)
        self.assertEqual([r[1] for r in results if r[0].startswith('solo window: ')], ['SKIP'])
        # E01-T16: the real "user" client needs a dedicated server and a second client (SKIP here)
        self.assertEqual([r[1] for r in results if r[0] == 'a real client with the user role is refused without data (E01-T16)'], ['SKIP'])
        self.assertTrue(report.ok, results)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)                      # groupe de test retiré
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_detects_a_missing_bound(self):
        self.run_lua('local set = LivingKnox.Admin.npcSet LivingKnox.Admin.npcSet = function(id, f, v, who) '
                     'if f == "hunger" then v = math.min(v, 120) end local r, e = set(id, f, v, who) '
                     'if r and f == "hunger" then r.value = v end return r, e end')
        report, results = self.run_suite()
        self.assertFalse(report.ok)
        failed = [r for r in results if r[1] == 'FAIL']
        self.assertEqual(len(failed), 1, results)
        self.assertIn('hunger kept within its bound', failed[0][2])

    def test_suite_detects_a_role_outside_the_type(self):
        self.run_lua('local base = LivingKnox.Admin.rolesOf LivingKnox.Admin.rolesOf = function(t) '
                     'local out = base(t) out[#out + 1] = "breaker" return out end')
        report, results = self.run_suite()
        self.assertFalse(report.ok)
        failed = [r for r in results if r[1] == 'FAIL']
        self.assertEqual(len(failed), 1, results)
        self.assertIn('role outside the roles of the type accepted', failed[0][2])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


class StaticTests(unittest.TestCase):
    def test_constants_shared_with_the_authority(self):
        admin = ADMIN_FILE.read_text(encoding='utf-8')
        sheet = SHEET_FILE.read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY', 'CAPABILITY'):
            a = re.search(rf'^Admin\.{name} = "([^"]+)"', admin, re.M).group(1)
            s = re.search(rf'^Sheet\.{name} = "([^"]+)"', sheet, re.M).group(1)
            self.assertEqual(a, s, name)
        fields_a = re.search(r'^Admin\.SHEET_FIELDS = \{([^}]*)\}', admin, re.M).group(1)
        fields_s = re.search(r'^Sheet\.FIELDS = \{([^}]*)\}', sheet, re.M).group(1)
        self.assertEqual(fields_a.strip(), fields_s.strip())
        # Constantes avant la garde du client MP ; aucune donnée après.
        self.assertLess(admin.index('Admin.SHEET_FIELDS'), admin.index('if isClient() then return Admin end'))

    def test_translations_en_fr_cover_every_sheet_key_without_a_bare_percent(self):
        import json
        sheet = SHEET_FILE.read_text(encoding='utf-8')
        used = set(k for k in re.findall(r'tr\("(\w+)"', sheet) if not k.endswith('_')) | {f'Field_{f}' for f in
                                                         re.findall(r'"(\w+)"', re.search(
                                                             r'^Sheet\.FIELDS = \{([^}]*)\}', sheet, re.M).group(1))}
        srcs = re.search(r'^Sheet\.POS_SOURCES = \{([^}]*)\}', sheet, re.M).group(1)
        used |= {f'Pos_{k}' for k in re.findall(r'(\w+) = true', srcs)}             # LK13-T16
        self.assertIn('Pos_home', used)
        for lang in ('EN', 'FR'):
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for key in used:
                self.assertIn(f'IGUI_LK_Sheet_{key}', data, lang)
            for k, v in data.items():
                if k.startswith('IGUI_LK_Sheet_'):
                    self.assertNotIn('%', re.sub(r'%\d', '', v), k)   # % seul : avertissement du Translator


if __name__ == '__main__':
    unittest.main(verbosity=1)
