"""Panneau de debug des PNJ (LK13-T14) : journal d'activité en mémoire server/LivingKnox/LK_Activity.lua, opération
« activity » de LK_Admin.lua (autorité) et panneau client client/LivingKnox/LK_DebugView.lua.

    python RadioSurvivor/tests/test_lk_debugview.py

Banc tests/harness.py, pile de tests/test_lk_npcsheet.py (SheetBase : groupe « deciders » matérialisé, cascade,
besoins, santé, droits simulés) :
- MP (serveur dédié + clients A admin et B sans la capacité) : refus sans donnée pour B, liste des groupes et activité
  en direct pour A par le réseau, faim réglée par npcSet visible au journal d'activité comme changement de
  comportement, envoi incrémental, journal borné à 200 lignes, aucune écriture de registre, relecture toutes les 2 s
  panneau ouvert et aucune requête panneau fermé, fiche d'un membre ouverte depuis le panneau ;
- solo : refus sans le mode debug, bouton du panneau debug vanilla (ISDebugMenu, doublure) présent seulement avec le
  droit et sans retirer les autres boutons, écouteur de l'alerte ;
- LK13-T15 : cellules des tableaux, mise en page, coupure « ... », tri stable et infobulle de LK_Table.lua, bouton de
  téléportation du panneau ;
- suite en jeu lk.debugview jouée par le vrai moteur RST sur les doublures du banc (solo).
Doublures de droits : celles de test_lk_admin.py. Elles ne prouvent pas l'API réelle (suite en jeu lk.debugview).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_npcsheet import SheetBase  # noqa: E402

ADMIN_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Admin.lua'
ACTIVITY_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Activity.lua'
VIEW_FILE = LUA / 'client' / 'LivingKnox' / 'LK_DebugView.lua'
TRANSLATE = LUA / 'shared' / 'Translate'
SUITE = 'shared/RST/suites/RST_LKDebugView.lua'
SUITE_FILE = Path(__file__).resolve().parents[1] / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE
A = 'LivingKnox.Admin'
AC = 'LivingKnox.Activity'
V = 'LivingKnox.DebugView'
S = 'LivingKnox.NpcSheet'
D = 'LivingKnox.Decisions'

# Doublure du panneau debug vanilla (M/client/DebugUIs/DebugMenu/ISDebugMenu.lua:16-66) : setupButtons ajoute ses
# boutons, les trie, puis « Fermer ».
DEBUG_MENU = r'''
ISDebugMenu = {}
function ISDebugMenu:addButtonInfo(title, fn, tab) self.buttons = self.buttons or {}
    local info = { title = title, func = fn, tab = tab } table.insert(self.buttons, info) return info end
function ISDebugMenu:setupButtons()
    self:addButtonInfo("General", function() end, "MAIN")
    self:addButtonInfo("Cheats", function() end, "MAIN")
    table.sort(self.buttons, function(a, b) return a.title < b.title end)
    self:addButtonInfo("Close", nil, "MAIN")
end
function DEBUG_MENU_TITLES()
    local m = setmetatable({ buttons = {} }, { __index = ISDebugMenu })
    m:setupButtons()
    local out = {}
    for i, b in ipairs(m.buttons) do out[i] = b.title end
    return out, m
end
'''


class ViewBase(SheetBase):
    def make(self, root=None):
        h = super().make(root)
        for c in (['solo'] if self.mode == 'solo' else ['A', 'B']):
            h.load(c, DEBUG_MENU)
            h.load(c, 'client/LivingKnox/LK_DebugView.lua')
            # Fiche LK13-T13 : sans ISCollapsableWindow sur le banc, Sheet.open n'existe pas ; doublure qui note le PNJ.
            h.load(c, f'OPENED = nil {S}.open = function(npc) OPENED = npc {S}.state.npc = npc return {{}} end')
        return h

    def open_view(self, machine, gid=None):
        """Panneau « ouvert » sans fenêtre réelle (aucune ISCollapsableWindow sur le banc)."""
        self.h.load(machine, f'{V}.state.window = {{}}')
        if gid is not None:
            self.h.load(machine, f'{V}.select("{gid}")')

    def requests(self):
        return [m for m in self.h.pending() if m.get('command') == 'adminRequest']

    def round_trip(self):
        self.h.pump()
        self.h.pump()

    def entries(self, gid, after=0):
        return lua_list(self.ev(f'{AC}.entries("{gid}", {after})'))


class MPTests(ViewBase):
    def test_non_admin_client_is_refused_without_data(self):
        gid = self.mk()
        self.assertFalse(self.h.eval('B', f'{V}.canUse()'))
        self.h.load('B', 'GOT = {} local base = LivingKnox.DebugView.onServerCommand '
                         'LivingKnox.DebugView.onServerCommand = function(m, c, a) '
                         'if c == "adminReply" then GOT[#GOT + 1] = a end return base(m, c, a) end')
        self.h.load('B', f'{V}.state.selected = "{gid}" {V}.send()')
        self.round_trip()
        got = lua_list(self.h.eval('B', 'GOT'))
        self.assertEqual(len(got), 1)
        self.assertEqual(sorted(got[0].keys()), ['err', 'n', 'ok', 'op'])
        self.assertEqual((got[0].op, got[0].err), ('activity', 'denied'))
        self.assertEqual(self.h.eval('B', f'{V}.state.status'), 'IGUI_LK_Debug_Denied')
        self.assertIsNone(self.h.eval('B', f'{V}.state.data'))
        self.assertEqual(lua_list(self.h.eval('B', f'{V}.state.groups')), [])
        self.assertTrue(any('admin: request activity refused for B' in line for line in self.h.logs('server')))
        # Réponse du panneau ni périmée pour la fenêtre des groupes ni lue par la fiche.
        self.assertEqual(self.h.eval('B', 'LivingKnox.AdminView.stats.stale'), 0)
        self.assertEqual(self.h.eval('B', f'{S}.stats.stale'), 0)
        # Le client MP ne tient aucun journal : la garde de LK_Activity s'arrête avant les données.
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Activity'))

    def test_admin_reads_groups_live_activity_and_the_hunger_change_in_the_activity_log(self):
        gid = self.mk()
        self.dpass(2)
        npc = self.npc_of(gid, 'm-2')
        seq = self.seq()
        self.assertTrue(self.h.eval('A', f'{V}.canUse()'))
        self.open_view('A', gid)
        self.assertEqual(len(self.requests()), 1)
        self.round_trip()
        groups = lua_list(self.h.eval('A', f'{V}.state.groups'))
        self.assertEqual([g.id for g in groups], [gid])
        d = self.h.eval('A', f'{V}.state.data')
        self.assertEqual((d.id, d.name, d.type), (gid, 'Mill', 'deciders'))
        members = lua_list(d.members)
        self.assertEqual([m.id for m in members], ['m-1', 'm-2'])
        m2 = members[1]
        self.assertEqual((m2.npc, m2.role, m2.alive, m2.embodied), (npc, 'worker', True, True))
        self.assertIsInstance(m2.b, str)
        self.assertIsInstance(m2.rule, str)
        self.assertEqual((m2.needs.hunger, m2.needs.thirst), (20, 20))
        self.assertEqual(m2.hp, 100)
        x, y = self.body_xy(gid, 'm-2')
        self.assertAlmostEqual(m2.pos.x, x, delta=0.06)
        self.assertAlmostEqual(m2.pos.y, y, delta=0.06)
        self.assertIs(members[0].leader, True)
        first = lua_list(self.h.eval('A', f'{V}.state.entries'))
        kinds = {e.k for e in first}
        self.assertIn('behaviour', kinds)
        self.assertIn('objective', kinds)                  # groupe noté à son arrivée
        self.assertTrue(all(isinstance(e.m, int) for e in first))
        # LK13-T15 : cellules des tableaux (membre, groupe, journal d'activité).
        cells = self.h.eval('A', f'{V}.memberCells({V}.state.data.members[2])')
        self.assertEqual(cells.npc, f'{npc} - IGUI_LK_Debug_Present')
        self.assertEqual((cells.role, cells.health), ('worker', '100 %'))
        self.assertEqual(cells.needs, '20/20/20/0')
        self.assertTrue(cells.rule.startswith(m2.rule + ': '))
        self.assertRegex(cells.pos, r'^IGUI_LK_Debug_Pos_body\|\d+,\d+,0$')
        self.assertIn('IGUI_LK_Debug_Leader', self.h.eval('A', f'{V}.memberCells({V}.state.data.members[1]).member'))
        g = self.h.eval('A', f'{V}.groupCells({V}.state.groups[1])')
        self.assertEqual((g.gid, g.gname, g.alive), (gid, 'Mill', 'IGUI_LK_Debug_AliveCell|2|2|2'))
        e = self.h.eval('A', f'{V}.entryCells({V}.state.entries[1])')
        self.assertTrue(e.when.startswith('IGUI_LK_Debug_When|'))
        self.assertIn('IGUI_LK_Debug_Header', self.h.eval('A', f'{V}.headerText({V}.state.data)'))
        # Faim mise par la fiche (npcSet) : le passage de décision suivant change le comportement, noté au journal.
        self.h.load('A', f'{S}.state.npc = "{npc}" {S}.set("hunger", 95)')
        self.round_trip()
        self.dpass(1)
        lines = [e for e in self.entries(gid) if e.k == 'behaviour' and e.npc == npc and 'rule hunger' in e.t]
        self.assertEqual(len(lines), 1, [e.t for e in self.entries(gid)])
        self.assertEqual(lines[0].mid, 'm-2')
        self.assertIn('-> ', lines[0].t)
        # Envoi incrémental : seules les lignes nouvelles repartent.
        after = self.h.eval('A', f'{V}.state.after')
        self.h.load('A', f'{V}.state.lastMs = nil {V}.poll(getTimestampMs())')
        sent = self.requests()
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0]['args']['after'], after)
        self.round_trip()
        got = lua_list(self.h.eval('A', f'{V}.state.entries'))
        self.assertEqual(len(got), len(first) + len([e for e in self.entries(gid, after)]))
        self.assertTrue(any(e.npc == npc and 'rule hunger' in e.t for e in got))
        self.assertEqual(len({e.s for e in got}), len(got))   # aucune ligne reçue deux fois
        # Le journal d'activité n'écrit pas le registre (seule l'écriture du réglage de la faim).
        self.assertEqual(self.seq(), seq + 1)
        self.assertEqual(self.h.errors('server'), [])
        self.assertEqual(self.h.errors('A'), [])

    def test_activity_log_is_bounded_to_200_lines_and_never_saved(self):
        gid = self.mk()
        seq = self.seq()
        self.run_lua(f'for i = 1, 260 do {AC}.note("{gid}", "m-1", "care", "line " .. i) end')
        kept = self.entries(gid)
        self.assertEqual(len(kept), 200)
        self.assertEqual(self.ev(f'{AC}.count("{gid}")'), 200)
        self.assertEqual(kept[-1].t, 'line 260')
        self.assertEqual(kept[0].s, kept[-1].s - 199)
        self.assertEqual([e.s for e in kept], sorted(e.s for e in kept))
        self.assertEqual(len(self.entries(gid, kept[-1].s - 5)), 5)
        self.assertEqual(self.seq(), seq)                  # aucune écriture du registre des groupes
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").activity'))
        # Sorte inconnue et groupe absent : rien.
        self.assertIsNone(self.ev(f'{AC}.note("{gid}", nil, "chat", "x")'))
        self.assertIsNone(self.ev(f'{AC}.note(nil, nil, "care", "x")'))
        # Le panneau garde aussi 200 lignes au plus.
        self.open_view('A', gid)
        self.round_trip()
        self.assertEqual(self.h.eval('A', f'#{V}.state.entries'), 200)
        self.run_lua(f'for i = 1, 30 do {AC}.note("{gid}", nil, "meal", "more " .. i) end')
        self.h.load('A', f'{V}.state.lastMs = nil {V}.poll(getTimestampMs())')
        self.round_trip()
        got = lua_list(self.h.eval('A', f'{V}.state.entries'))
        self.assertEqual(len(got), 200)
        self.assertEqual(got[-1].t, 'more 30')
        # Texte borné.
        self.run_lua(f'{AC}.note("{gid}", nil, "care", string.rep("x", 500))')
        self.assertEqual(len(self.entries(gid)[-1].t), 160)

    def test_refresh_every_two_seconds_while_open_and_nothing_once_closed(self):
        gid = self.mk()
        # Panneau fermé : aucune requête.
        self.h.load('A', f'{V}.state.selected = "{gid}"')
        self.assertFalse(self.h.eval('A', f'{V}.poll(getTimestampMs())'))
        self.assertEqual(self.requests(), [])
        # Ouvert : une requête, rien avant 2 s, rien tant que la réponse est attendue.
        self.h.load('A', f'{V}.state.window = {{}}')
        self.assertTrue(self.h.eval('A', f'{V}.poll(getTimestampMs())'))
        self.assertEqual(len(self.requests()), 1)
        self.assertFalse(self.h.eval('A', f'{V}.poll(getTimestampMs() + 9000)'))     # réponse attendue
        self.round_trip()
        self.assertFalse(self.h.eval('A', f'{V}.poll(getTimestampMs() + 1999)'))
        self.assertTrue(self.h.eval('A', f'{V}.poll(getTimestampMs() + 2000)'))
        self.assertEqual(len(self.requests()), 1)
        self.round_trip()
        # Fermé (réponse éventuelle ignorée) : plus rien, même longtemps après.
        self.h.load('A', f'{V}.closed({V}.state.window)')
        self.assertFalse(self.h.eval('A', f'{V}.poll(getTimestampMs() + 60000)'))
        self.assertEqual(self.requests(), [])
        self.assertEqual(self.h.eval('A', 'LivingKnox.AdminView.stats.stale'), 0)

    def test_member_sheet_opened_from_the_panel(self):
        gid = self.mk()
        npc = self.npc_of(gid, 'm-2')
        self.open_view('A', gid)
        self.round_trip()
        self.assertIsNone(self.h.eval('A', f'{V}.openSheet()'))         # aucun membre choisi
        self.assertIsNotNone(self.h.eval('A', f'{V}.openSheet("m-2")'))
        self.assertEqual(self.h.eval('A', 'OPENED'), npc)
        self.assertEqual(self.h.eval('A', f'{V}.state.member'), 'm-2')
        # Changer de groupe oublie le membre choisi et l'activité reçue.
        self.h.load('A', f'{V}.select("grp-999")')
        self.assertIsNone(self.h.eval('A', f'{V}.state.member'))
        self.assertEqual(self.h.eval('A', f'#{V}.state.entries'), 0)
        self.round_trip()
        self.assertEqual(self.h.eval('A', f'{V}.state.status'), 'IGUI_LK_Debug_Error|unknown group grp-999')


class TableTests(ViewBase):
    """LK13-T15 : fonctions pures du tableau (LK_Table.lua) et cellules du panneau sur des lignes construites."""
    mode = 'solo'
    T = 'LivingKnox.Table'

    def test_layout_fills_the_width_and_keeps_the_minimums(self):
        cols = lua_list(self.run_lua(f'return {self.T}.layout({{ {{ key = "a", min = 50, weight = 1 }}, '
                                     '{ key = "b", min = 100, weight = 3 }, { key = "c" } }, 600)'))
        self.assertEqual([c.x for c in cols], [0, cols[0].w, cols[0].w + cols[1].w])
        self.assertEqual(sum(c.w for c in cols), 600)
        self.assertGreaterEqual(cols[0].w, 50)
        self.assertGreater(cols[1].w, cols[0].w)
        # Trop étroit : chaque colonne garde son minimum.
        cols = lua_list(self.run_lua(f'return {self.T}.layout({{ {{ key = "a", min = 50 }}, {{ key = "b", min = 80 }} }}, 60)'))
        self.assertEqual([c.w for c in cols], [50, 80])

    def test_clip_adds_an_ellipsis_only_when_the_text_does_not_fit(self):
        m = 'function(s) return #s * 7 end'
        self.assertEqual(self.run_lua(f'return ({self.T}.clip("abcdef", 42, {m}))'), 'abcdef')
        self.assertEqual(self.run_lua(f'return ({self.T}.clip("abcdefghij", 50, {m}))'), 'abcd...')
        self.assertEqual(self.run_lua(f'return ({self.T}.clip("abcdefghij", 10, {m}))'), '')
        self.assertEqual(self.run_lua(f'return ({self.T}.clip(nil, 10, {m}))'), '')

    def test_sorted_is_stable_numbers_and_texts_then_blanks(self):
        code = (f'local rows = {{ {{ id = 1, v = "b" }}, {{ id = 2, v = 10 }}, {{ id = 3, v = "-" }}, '
                '{ id = 4, v = 2 }, { id = 5, v = "A" }, { id = 6, v = 10 } } '
                'local function ids(list) local out = {} for i, r in ipairs(list) do out[i] = r.id end return out end '
                f'local val = function(r) return r.v end '
                f'return ids({self.T}.sorted(rows, "v", false, val)), ids({self.T}.sorted(rows, "v", true, val))')
        up, down = self.run_lua(code)
        self.assertEqual(lua_list(up), [4, 2, 6, 5, 1, 3])
        self.assertEqual(lua_list(down), [2, 6, 4, 1, 5, 3])
        tip = self.run_lua(f'return {self.T}.tooltip({{ {{ key = "a", title = "A" }}, {{ key = "b", title = "B" }} }}, '
                           '{ a = "x<y", b = "" })')
        self.assertEqual(tip, 'A: x(y')

    def test_group_and_member_cells(self):
        g = self.ev(f'{V}.groupCells({{ id = "grp-3", name = "Mill", type = "deciders", leader = "m-1", '
                    'leaderName = "Jane Doe", alive = 2, total = 3, embodied = 1, objective = "supply", '
                    'alert = { kind = "zombie", level = 45 }, defense = "hold" })')
        self.assertEqual((g.leader, g.alive, g.objective), ('Jane Doe (m-1)', 'IGUI_LK_Debug_AliveCell|2|3|1', 'supply'))
        self.assertEqual(g.alert, 'IGUI_LK_Debug_AlertCell|zombie|45, IGUI_LK_Debug_DefenseCell|hold')
        self.assertEqual(self.ev(f'{V}.groupSort({{ id = "grp-12" }}, "gid")'), 12)
        dead = self.ev(f'{V}.memberCells({{ id = "m-4", npc = "lk-9", role = "scout", alive = false }})')
        self.assertEqual((dead.npc, dead.behaviour, dead.pos), ('lk-9 - IGUI_LK_Debug_Dead', '-', '-'))
        m = self.ev(f'{V}.memberCells({{ id = "m-2", name = "Bob Ray", npc = "lk-7", role = "worker", alive = true, '
                    'away = true, b = "meal", rule = "hunger", why = "hunger 95", key = "stock", hp = 42.5, wound = 3, '
                    'pos = { x = 10.6, y = 20.2, z = 0, last = true }, needs = { hunger = 95, thirst = 1, fatigue = 2, '
                    'fear = 0 } })')
        self.assertEqual((m.member, m.npc), ('m-2 Bob Ray', 'lk-7 - IGUI_LK_Debug_Away'))
        self.assertEqual((m.rule, m.target, m.health), ('hunger: hunger 95', 'stock', '42.5 % IGUI_LK_Debug_Wound|3'))
        self.assertEqual(m.pos, 'IGUI_LK_Debug_Pos_last|10,20,0')
        # LK13-T16 : source donnée par l'autorité, foyer du groupe dans la liste des groupes.
        home = self.ev(f'{V}.memberCells({{ id = "m-3", npc = "lk-8", alive = true, '
                       'pos = { x = 110, y = 111, z = 0, src = "home" } }).pos')
        self.assertEqual(home, 'IGUI_LK_Debug_Pos_home|110,111,0')
        self.assertEqual(self.ev(f'{V}.groupCells({{ id = "grp-3", home = {{ x = 110, y = 111, z = 0 }} }}).home'),
                         '110,111,0')
        self.assertEqual(self.ev(f'{V}.groupCells({{ id = "grp-3" }}).home'), '-')


class TeleportTests(ViewBase):
    def test_teleport_button_of_the_panel(self):
        from test_lk_npcsheet import TELEPORT_RIGHT
        gid = self.mk()
        self.h.load('A', TELEPORT_RIGHT)
        self.open_view('A', gid)
        self.round_trip()
        self.assertIsNone(self.h.eval('A', f'{V}.teleport()'))                    # aucun membre choisi
        self.assertIsNotNone(self.h.eval('A', f'{V}.teleport("m-2")'))
        self.round_trip()
        sent = lua_list(self.h.eval('A', 'SENT_CMDS'))
        self.assertEqual(len(sent), 1)
        self.assertTrue(sent[0].startswith('/teleportto '))
        self.assertTrue(self.h.eval('A', f'{V}.state.status').startswith('IGUI_LK_Sheet_GotoDone|'))


class PositionTests(ViewBase):
    """LK13-T16 : position et source de chaque membre vivant, téléportation hors écran et au foyer du groupe."""

    def hide(self, npc):
        """Corps de npc introuvable (hors écran) et dernière position effacée : PNJ jamais vu."""
        self.run_lua(f'local base = LivingKnox.Bodies.find LivingKnox.Bodies.find = function(id, ...) '
                     f'if id == "{npc}" then return nil end return base(id, ...) end '
                     f'LivingKnox.Store.data().npcs["{npc}"].last = nil')

    def add_unborn(self, gid):
        """Troisième membre ajouté sans passage de matérialisation : aucun PNJ, aucun corps."""
        self.run_lua(f'assert(LivingKnox.Groups.addMember("{gid}", {{ role = "worker", profile = "cook", '
                     'female = false, day = 1 }))')

    def test_every_living_member_has_a_position_and_a_source(self):
        gid = self.mk()
        npc2 = self.npc_of(gid, 'm-2')
        self.hide(npc2)
        self.add_unborn(gid)
        self.open_view('A', gid)
        self.round_trip()
        members = lua_list(self.h.eval('A', f'{V}.state.data.members'))
        self.assertEqual([m.id for m in members], ['m-1', 'm-2', 'm-3'])
        for m in members:
            self.assertIs(m.alive, True)
            self.assertIn(m.pos.src, ('body', 'last', 'home'), m.id)
            for k in ('x', 'y', 'z'):
                self.assertIsInstance(getattr(m.pos, k), (int, float), (m.id, k))
        self.assertEqual(members[0].pos.src, 'body')
        self.assertEqual((members[1].pos.src, members[1].pos.x, members[1].pos.y, members[1].pos.z),
                         ('home', 110, 110, 0))
        self.assertIsNone(members[2].npc)
        self.assertEqual((members[2].pos.src, members[2].pos.x, members[2].pos.y), ('home', 110, 110))
        self.assertEqual(self.h.eval('A', f'{V}.memberCells({V}.state.data.members[3]).pos'),
                         'IGUI_LK_Debug_Pos_home|110,110,0')
        self.assertEqual(self.h.eval('A', f'{V}.groupCells({V}.state.groups[1]).home'), '110,110,0')
        # Dernière position connue : prise avant le foyer.
        self.run_lua(f'LivingKnox.Store.data().npcs["{npc2}"].last = {{ x = 140.4, y = 150.7, z = 1 }}')
        self.h.load('A', f'{V}.state.lastMs = nil {V}.poll(getTimestampMs())')
        self.round_trip()
        p = self.h.eval('A', f'{V}.state.data.members[2].pos')
        self.assertEqual((p.src, p.x, p.y, p.z), ('last', 140.4, 150.7, 1))
        # Fiche : même position et même source.
        v = self.ev(f'{A}.npcView("{npc2}").npc.pos')
        self.assertEqual((v.src, v.x), ('last', 140.4))
        self.assertEqual(self.h.errors('server'), [])
        self.assertEqual(self.h.errors('A'), [])

    def test_teleport_to_a_never_embodied_member_leads_to_the_group_home(self):
        from test_lk_npcsheet import TELEPORT_RIGHT
        gid = self.mk()
        npc2 = self.npc_of(gid, 'm-2')
        self.hide(npc2)
        self.h.load('A', TELEPORT_RIGHT)
        self.open_view('A', gid)
        self.round_trip()
        self.assertIsNotNone(self.h.eval('A', f'{V}.teleport("m-2")'))
        self.round_trip()
        sent = lua_list(self.h.eval('A', 'SENT_CMDS'))
        self.assertEqual(len(sent), 1)
        m = re.fullmatch(r'/teleportto (-?\d+),(-?\d+),(-?\d+)', sent[0])
        self.assertIsNotNone(m, sent)
        self.assertLessEqual(max(abs(int(m.group(1)) - 110), abs(int(m.group(2)) - 110)), 1)
        self.assertEqual(int(m.group(3)), 0)
        self.assertEqual(self.h.eval('A', f'{V}.state.status'), f'IGUI_LK_Sheet_GotoHome|{sent[0][12:]}')
        self.assertTrue(any(t.startswith(f'teleport of admin A to m-2 ({npc2}) at ') and t.endswith('(group home)')
                            for t in self.admin_log(gid)))

    def test_teleport_to_the_home_of_the_chosen_group_and_refusal_without_data(self):
        from test_lk_npcsheet import TELEPORT_RIGHT
        gid = self.mk()
        self.h.load('A', TELEPORT_RIGHT)
        self.assertIsNone(self.h.eval('A', f'{V}.teleportHome()'))                # aucun groupe choisi
        self.open_view('A', gid)
        self.round_trip()
        self.assertIsNotNone(self.h.eval('A', f'{V}.teleportHome()'))
        self.round_trip()
        sent = lua_list(self.h.eval('A', 'SENT_CMDS'))
        self.assertEqual(len(sent), 1)
        m = re.fullmatch(r'/teleportto (-?\d+),(-?\d+),(-?\d+)', sent[0])
        self.assertLessEqual(max(abs(int(m.group(1)) - 110), abs(int(m.group(2)) - 110)), 1)
        self.assertEqual(self.h.eval('A', f'{V}.state.status'), f'IGUI_LK_Sheet_GotoHome|{sent[0][12:]}')
        self.assertEqual(self.admin_log(gid), [f'teleport of admin A to the group home at {sent[0][12:]}'])
        self.assertTrue(any(f'admin: A teleported to the home of {gid}' in line for line in self.h.logs('server')))
        # Client sans la capacité : refus sans donnée ni écriture.
        seq = self.seq()
        self.h.load('B', 'GOT = {} local base = LivingKnox.NpcSheet.onServerCommand '
                         'LivingKnox.NpcSheet.onServerCommand = function(m, c, a) '
                         'if c == "adminReply" then GOT[#GOT + 1] = a end return base(m, c, a) end')
        self.h.load('B', f'{S}.send("homeGoto", {{ gid = "{gid}" }})')
        self.round_trip()
        got = lua_list(self.h.eval('B', 'GOT'))
        self.assertEqual(len(got), 1)
        self.assertEqual(sorted(got[0].keys()), ['err', 'n', 'ok', 'op'])
        self.assertEqual((got[0].op, got[0].err), ('homeGoto', 'denied'))
        self.assertEqual(self.seq(), seq)
        self.assertTrue(any('admin: request homeGoto refused for B' in line for line in self.h.logs('server')))
        # Groupe inconnu, foyer inconnu.
        r = self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "homeGoto", n = 1, gid = "grp-999" }})')
        self.assertEqual((r.ok, r.err), (False, 'unknown group grp-999'))
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].home = nil')
        r = self.ev(f'{A}.request(getOnlinePlayers():get(0), {{ op = "homeGoto", n = 1, gid = "{gid}" }})')
        self.assertEqual((r.ok, r.err), (False, 'no known position'))


class PositionSoloTests(ViewBase):
    mode = 'solo'

    def test_solo_home_teleport_moves_the_player_and_needs_the_debug_mode(self):
        from test_lk_npcsheet import SOLO_TELEPORT
        gid = self.mk()
        self.run_lua(SOLO_TELEPORT)
        self.run_lua(f'{V}.state.window = {{}} {V}.select("{gid}")')
        self.run_lua(f'{V}.teleportHome()')
        tp = self.ev('TP')
        self.assertIsNotNone(tp)
        self.assertLessEqual(max(abs(tp.x - 110), abs(tp.y - 110)), 1)
        self.assertEqual(lua_list(self.ev('SENT_CMDS')), [])
        self.assertTrue(self.ev(f'{V}.state.status').startswith('IGUI_LK_Sheet_GotoHome|'))
        self.run_lua('DBG = false TP = nil')
        self.run_lua(f'{S}.teleportHome("{gid}")')
        self.assertIsNone(self.ev('TP'))
        self.assertEqual(self.ev(f'{S}.state.status'), 'IGUI_LK_Sheet_Denied')


class SoloTests(ViewBase):
    mode = 'solo'

    def test_solo_requires_the_debug_mode(self):
        gid = self.mk()
        self.run_lua('DBG = false')
        self.assertFalse(self.ev(f'{V}.canUse()'))
        self.run_lua(f'{V}.state.window = {{}} {V}.select("{gid}")')
        self.assertEqual(self.h.pending(), [])                                         # aucune commande réseau
        self.assertEqual(self.ev(f'{V}.state.status'), 'IGUI_LK_Debug_Denied')
        self.assertIsNone(self.ev(f'{V}.state.data'))
        self.assertTrue(any('refused for' in line and 'debug mode off' in line for line in self.h.logs('solo')))
        self.run_lua('DBG = true')
        self.run_lua(f'{V}.state.lastMs = nil {V}.poll(getTimestampMs())')
        self.assertEqual(self.ev(f'{V}.state.data.id'), gid)
        self.assertIsNone(self.ev(f'{V}.state.status'))

    def test_debug_menu_button_only_with_the_right_and_others_kept(self):
        self.run_lua('DBG = false')
        titles = lua_list(self.ev('(DEBUG_MENU_TITLES())'))
        self.assertEqual(titles, ['Cheats', 'General', 'Close'])
        self.run_lua('DBG = true')
        titles, menu = self.run_lua('return DEBUG_MENU_TITLES()')
        titles = lua_list(titles)
        # trié, avant « Fermer » ; LK13-T01 : bouton de la fenêtre d'administration posé par la même enveloppe
        self.assertEqual(titles, ['Cheats', 'General', 'IGUI_LK_Admin_DebugButton', 'IGUI_LK_Debug_Button', 'Close'])
        self.assertEqual(self.ev('(select(2, DEBUG_MENU_TITLES())).buttons[3].tab'), 'MAIN')
        self.assertEqual(self.ev('(select(2, DEBUG_MENU_TITLES())).buttons[4].tab'), 'MAIN')
        # Rechargement du fichier : un seul bouton (enveloppe non empilée).
        self.h.load('solo', 'client/LivingKnox/LK_DebugView.lua')
        reloaded = lua_list(self.ev('(DEBUG_MENU_TITLES())'))
        self.assertEqual(reloaded.count('IGUI_LK_Debug_Button'), 1)
        self.assertEqual(reloaded.count('IGUI_LK_Admin_DebugButton'), 1)

    def test_alert_listener_writes_the_activity_log(self):
        gid = self.mk()
        self.assertTrue(self.ev(f'{AC}.hookAlert()'))
        self.run_lua(f'local A = LivingKnox.Alert for _, l in ipairs(A.listeners) do if l.name == "Activity" then '
                     f'l.h.raised("{gid}", {{ kind = "zombie", label = "42", level = 45, x = 1, y = 2, z = 0, '
                     f'spotter = "lk-1" }}, "raised") l.h.calm("{gid}", {{ kind = "zombie", label = "42", level = 9 }}) '
                     'end end')
        alerts = [e.t for e in self.entries(gid) if e.k == 'alert']
        self.assertEqual(alerts[-2:], ['alert raised: zombie 42, level 45 at 1,2,0, seen by lk-1',
                                       'alert calm: zombie 42, level 9'])
        # Un seul écouteur malgré plusieurs inscriptions.
        self.assertTrue(self.ev(f'{AC}.hookAlert()'))
        n = self.run_lua('local n = 0 for _, l in ipairs(LivingKnox.Alert.listeners) do '
                         'if l.name == "Activity" then n = n + 1 end end return n')
        self.assertEqual(n, 1)


class SuiteTests(ViewBase):
    """Suite en jeu lk.debugview exécutée par le vrai moteur RST sur les doublures du banc (solo, mode debug)."""
    mode = 'solo'

    def run_suite(self):
        self.h.move_player('A', 110, 110)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.debugview", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(3000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
        report = self.h.eval('solo', 'RST.last()')
        return report, [(r.test, r.status, r.message) for r in lua_list(report.results)]

    def test_suite_lk_debugview_passes_on_the_doubles(self):
        report, results = self.run_suite()
        self.assertEqual(len(results), 6, results)
        # Fenêtre solo (2026-10-15) : client solo du jeu seulement (aucune fenêtre sur ce banc, SKIP ici)
        self.assertEqual([r[1] for r in results if r[0].startswith('solo window: ')], ['SKIP'])
        # E01-T16: the real "user" client needs a dedicated server and a second client (SKIP here)
        self.assertEqual([r[1] for r in results if r[0] == 'a real client with the user role is refused without data (E01-T16)'], ['SKIP'])
        self.assertTrue(report.ok, results)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)                      # groupe de test retiré
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_detects_a_missing_behaviour_line(self):
        self.run_lua('LivingKnox.Activity.behaviour = function() return nil end')
        report, results = self.run_suite()
        self.assertFalse(report.ok)
        failed = [r for r in results if r[1] == 'FAIL']
        self.assertEqual(len(failed), 1, results)
        self.assertIn('hunger change in the activity log', failed[0][2])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


class StaticTests(unittest.TestCase):
    def test_constants_shared_with_the_authority(self):
        admin = ADMIN_FILE.read_text(encoding='utf-8')
        activity = ACTIVITY_FILE.read_text(encoding='utf-8')
        view = VIEW_FILE.read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY', 'CAPABILITY'):
            a = re.search(rf'^Admin\.{name} = "([^"]+)"', admin, re.M).group(1)
            v = re.search(rf'^DebugView\.{name} = "([^"]+)"', view, re.M).group(1)
            self.assertEqual(a, v, name)
        op = re.search(r'^DebugView\.OP = "([^"]+)"', view, re.M).group(1)
        self.assertIn(f'{op} = true', re.search(r'^Admin\.OPS = \{([^}]*)\}', admin, re.M).group(1))
        self.assertIn(f'{op} = true', re.search(r'^Admin\.DEBUG_OPS = \{([^}]*)\}', admin, re.M).group(1))
        mx_a = re.search(r'^Activity\.MAX = (\d+)', activity, re.M).group(1)
        mx_v = re.search(r'^DebugView\.MAX = (\d+)', view, re.M).group(1)
        self.assertEqual((mx_a, mx_v), ('200', '200'))
        # Constantes avant la garde du client MP.
        self.assertLess(admin.index('Admin.DEBUG_OPS'), admin.index('if isClient() then return Admin end'))

    def test_sources_are_kahlua_safe(self):
        for path in (ACTIVITY_FILE, VIEW_FILE):
            raw = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw, flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))

    def test_translations_en_fr_cover_every_panel_key_without_a_bare_percent(self):
        view = VIEW_FILE.read_text(encoding='utf-8')
        used = {k for k in re.findall(r'\btr\("(\w+)"', view) if not k.endswith('_')}
        kinds = re.search(r'^Activity\.KINDS = \{([^}]*)\}', ACTIVITY_FILE.read_text(encoding='utf-8'), re.M).group(1)
        used |= {f'Kind_{k}' for k in re.findall(r'(\w+) = true', kinds)}
        cols = view[view.index('DebugView.GROUP_COLUMNS = {'):view.index('-- Cellules d\'une ligne de groupe')]
        used |= {f'Col_{k}' for k in re.findall(r'key = "(\w+)"', cols)}
        srcs = re.search(r'^DebugView\.POS_SOURCES = \{([^}]*)\}', view, re.M).group(1)
        used |= {f'Pos_{k}' for k in re.findall(r'(\w+) = true', srcs)}             # LK13-T16
        self.assertIn('Pos_home', used)
        self.assertGreaterEqual(len([k for k in used if k.startswith('Col_')]), 24)
        for lang in ('EN', 'FR'):
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for key in used:
                self.assertIn(f'IGUI_LK_Debug_{key}', data, lang)
            self.assertIn('IGUI_LK_Admin_DebugView', data, lang)
            for k, v in data.items():
                if k.startswith('IGUI_LK_Debug_'):
                    self.assertNotIn('%', re.sub(r'%\d', '', v), k)   # % seul : avertissement du Translator


if __name__ == '__main__':
    unittest.main(verbosity=1)
