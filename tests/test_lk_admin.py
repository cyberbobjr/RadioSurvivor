"""Outils d'administration de Living Knox (LK13-T01) : LK_Admin.lua (autorité) et LK_AdminView.lua (fenêtre client).

    python RadioSurvivor/tests/test_lk_admin.py

Trois bancs :
- lupa direct de tests/test_lk_relief.py (carte de test, vrai registre, vraie population, vrais sites et relève) :
  contrôle d'accès (refus sans donnée, journal borné), liste, détail, foyer déplacé et contrôlé, relève forcée ;
  la suite en jeu lk.admin exécutée par le vrai moteur RST ;
- tests/harness.py en MP (serveur dédié + deux clients) : la fenêtre du client admin A et celle du client B (rôle
  sans la capacité) passent par sendClientCommand / sendServerCommand ; B ne reçoit qu'un refus sans donnée ;
- harness en solo : la fenêtre appelle LivingKnox.Admin.request directement.
Doublures : checkPermissions(joueur, capacité) et getRole():hasCapability lisent une table ADMINS (le Java vérifie le
rôle de la connexion, J/Lua/LuaManager.java:2913-2919) ; elles ne prouvent pas l'API réelle (voir la suite lk.admin).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402
from test_lk_api import POPULATE, SERVER as API_SERVER, SHARED as API_SHARED, WORLD as API_WORLD  # noqa: E402
from test_lk_population import lua_list  # noqa: E402
from test_lk_relief import ReliefBench, TESTS_LUA  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
ADMIN_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Admin.lua'
VIEW_FILE = LUA / 'client' / 'LivingKnox' / 'LK_AdminView.lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKAdmin.lua'
GROUPS = 'LivingKnox.Groups'
ADMIN = 'LivingKnox.Admin'

PERMISSIONS = r'''
Capability = { PopmanManage = 'cap:PopmanManage', AddItem = 'cap:AddItem' }
ADMINS = {}
CHECKS = {}
LOST_CONNECTION = false
checkPermissions = function(player, cap)
    CHECKS[#CHECKS + 1] = tostring(cap)
    if LOST_CONNECTION then return true end   -- LuaManager.java:2916-2919 : connexion introuvable -> vrai
    return cap == Capability.PopmanManage and ADMINS[player:getUsername()] == true
end
-- Rôle copié de la connexion (GameServer.java:2643) : même table ADMINS.
function GIVE_ROLE(p)
    p.getRole = function(self)
        return { hasCapability = function(_, c) return c == Capability.PopmanManage and ADMINS[self:getUsername()] == true end }
    end
    return p
end
'''

SENT = r'''
SENT = {}
sendServerCommand = function(player, module, command, args)
    SENT[#SENT + 1] = { player = player, module = module, command = command, args = args }
end
'''


def user(name, x=100, y=100):
    return (f'(function() local p = Player({x}, {y}) p.getZ = function() return 0 end '
            f'p.getUsername = function() return "{name}" end return GIVE_ROLE(p) end)()')


class AdminBench(ReliefBench):
    def setUp(self):
        super().setUp()
        self.rt.execute(PERMISSIONS + SENT)
        self.rt.execute('require "LivingKnox/LK_Admin"')
        self.rt.execute(f'BOSS = {user("boss")} ADMINS.boss = true PEON = {user("peon")}')

    def req(self, player, **args):
        fields = ', '.join(f'{k} = {self.lua(v)}' for k, v in args.items())
        return self.ev(f'{ADMIN}.request({player}, {{ {fields} }})')

    @staticmethod
    def lua(v):
        if isinstance(v, str):
            return f'"{v}"'
        if isinstance(v, bool):
            return 'true' if v else 'false'
        return str(v)

    def server(self):
        self.rt.execute('SIDE = "server"')

    def keys(self, t):
        return sorted(k for k in t.keys())

    def seq(self):
        self.rt.execute(f'{GROUPS}.flush()')   # LK13-T06 : écriture différée faite avant de compter
        return self.ev(f'{GROUPS}.state.seq')


class AccessTests(AdminBench):
    def test_server_refuses_every_request_of_a_non_admin_without_data(self):
        self.server()
        seq = self.seq()
        for op, extra in (('list', {}), ('group', {'gid': 'grp-1'}), ('relief', {'gid': 'grp-1'}),
                          ('home', {'gid': 'grp-1', 'x': 5000, 'y': 5000, 'z': 0})):
            with self.subTest(op=op):
                r = self.req('PEON', op=op, n=9, **extra)
                self.assertEqual(self.keys(r), ['err', 'n', 'ok', 'op'])
                self.assertEqual((r.ok, r.err, r.n, r.op), (False, 'denied', 9, op))
        self.assertEqual(self.seq(), seq)                         # rien écrit
        self.assertEqual(set(lua_list(self.g.CHECKS)), {'cap:PopmanManage'})
        self.assertEqual(self.ev(f'{ADMIN}.stats.refused'), 4)
        warns = [line for line in self.logs('WARN') if 'admin: request' in line]
        self.assertEqual(len(warns), 4)                           # une ligne par opération
        self.assertIn('admin: request list refused for peon (missing capability PopmanManage)', warns[0])

    def test_refusal_log_is_bounded_per_player_and_operation(self):
        self.server()
        for _ in range(5):
            self.req('PEON', op='list', n=1)
        warns = [line for line in self.logs('WARN') if 'admin: request' in line]
        self.assertEqual(len(warns), 1)
        self.g.CLOCK = self.g.CLOCK + 60000
        self.req('PEON', op='list', n=2)
        warns = [line for line in self.logs('WARN') if 'admin: request' in line]
        self.assertEqual(len(warns), 2)
        self.assertIn('4 more refusal(s) not logged', warns[1])
        self.assertEqual(self.ev(f'{ADMIN}.stats.refused'), 6)

    def test_admin_allowed_on_server_solo_player_allowed_nil_and_mp_client_refused(self):
        self.server()
        self.assertTrue(self.req('BOSS', op='list', n=1).ok)
        self.assertEqual(self.req('nil', op='list', n=1).err, 'denied')
        self.rt.execute('SIDE = "solo"')
        self.assertTrue(self.req('PEON', op='list', n=1).ok)    # solo : le joueur local administre sa partie
        self.rt.execute('SIDE = "client"')
        self.assertEqual(self.req('BOSS', op='list', n=1).err, 'denied')
        self.rt.execute('SIDE = "server" LOST_CONNECTION = true')  # checkPermissions vrai : le rôle tranche
        self.assertEqual(self.req('PEON', op='list', n=1).err, 'denied')
        self.assertTrue(self.req('BOSS', op='list', n=1).ok)
        self.rt.execute('PEON.getRole = function() return nil end')
        self.assertEqual(self.req('PEON', op='list', n=1).err, 'denied')
        self.rt.execute('SIDE = "server" Capability = nil')
        self.assertEqual(self.req('BOSS', op='list', n=1).err, 'denied')

    def test_unknown_or_malformed_requests(self):
        self.assertEqual(self.req('BOSS', op='wipe', n=1).err, 'unknown request')
        r = self.ev(f'{ADMIN}.request(BOSS, nil)')
        self.assertEqual((r.ok, r.err, r.n), (False, 'unknown request', 0))
        r = self.ev(f'{ADMIN}.request(BOSS, {{ op = "list", n = -3 }})')
        self.assertEqual(r.n, 0)

    def test_client_command_routing_answers_only_the_sender(self):
        self.server()
        self.ev(f'{ADMIN}.onClientCommand("LivingKnox", "adminRequest", BOSS, {{ op = "list", n = 4 }})')
        self.ev(f'{ADMIN}.onClientCommand("LivingKnox", "bodyReport", BOSS, {{ op = "list", n = 5 }})')
        self.ev(f'{ADMIN}.onClientCommand("Other", "adminRequest", BOSS, {{ op = "list", n = 6 }})')
        self.ev(f'{ADMIN}.onClientCommand("LivingKnox", "adminRequest", PEON, nil)')
        sent = lua_list(self.g.SENT)
        self.assertEqual(len(sent), 2)
        self.assertEqual((sent[0].module, sent[0].command, sent[0].args.n), ('LivingKnox', 'adminReply', 4))
        self.assertTrue(sent[0].args.ok)
        self.assertTrue(self.ev('SENT[1].player == BOSS and SENT[2].player == PEON'))
        self.assertEqual((sent[1].args.ok, sent[1].args.err), (False, 'denied'))

    def test_constants_shared_with_the_client_view(self):
        admin = ADMIN_FILE.read_text(encoding='utf-8')
        view = VIEW_FILE.read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY', 'CAPABILITY'):
            a = re.search(rf'^Admin\.{name} = "([^"]+)"', admin, re.M).group(1)
            v = re.search(rf'^View\.{name} = "([^"]+)"', view, re.M).group(1)
            self.assertEqual(a, v, name)
        # Garde serveur avant toute donnée : l'autorité seule décide, un client MP s'arrête après les constantes.
        self.assertLess(admin.index('if isClient() then return Admin end'), admin.index('require "LivingKnox/LK_Groups"'))


class ReadTests(AdminBench):
    def test_list_rows_with_exact_homes_and_state(self):
        r = self.req('BOSS', op='list', n=1)
        self.assertTrue(r.ok)
        rows = lua_list(r.groups)
        self.assertEqual([x.id for x in rows], ['grp-1', 'grp-2', 'grp-3', 'grp-4'])
        for x in rows:
            g = self.group(x.id)
            self.assertEqual((x.type, x.name, x.alive, x.total, x.morale), (g.type, g.name, len(self.living(x.id)),
                             len(self.members(g)), g.morale))
            self.assertEqual((x.home.x, x.home.y, x.home.z), (g.home.x, g.home.y, g.home.z))
            self.assertIsNone(x.gone)
            self.assertEqual(x.leader, g.leader)
        self.assertTrue(r.enabled)
        self.assertEqual(r.hour, 0)
        # Copies : modifier la réponse ne touche pas le registre.
        rows[0].home.x = -5
        self.assertNotEqual(self.group('grp-1').home.x, -5)

    def test_gone_group_shows_cause_due_and_relief(self):
        self.kill('grp-2')
        self.step(10)
        x = lua_list(self.req('BOSS', op='list', n=1).groups)[1]
        self.assertEqual(x.gone.cause, 'wiped')
        self.assertEqual(x.gone.dueIn, x.gone.due - 0)
        self.assertEqual(x.alive, 0)

    def test_detail_members_and_log(self):
        self.kill('grp-1', keep=3)
        r = self.req('BOSS', op='group', n=2, gid='grp-1')
        self.assertTrue(r.ok)
        d = r.group
        g = self.group('grp-1')
        members = lua_list(d.members)
        self.assertEqual([m.id for m in members], [m.id for m in self.members(g)])
        dead = [m for m in members if not m.alive]
        self.assertTrue(dead)
        self.assertEqual(d.story, g.story)
        log = lua_list(d.log)
        self.assertEqual([(e.kind, e.text) for e in log], self.kinds('grp-1'))
        self.assertEqual(log[-1].kind, 'died')
        self.assertIsNone(d.replaces)
        self.assertEqual(self.req('BOSS', op='group', n=3, gid='grp-77').err, 'unknown group grp-77')


class ReliefTests(AdminBench):
    def test_forced_relief_of_a_wiped_group(self):
        self.kill('grp-1')
        r = self.req('BOSS', op='relief', n=1, gid='grp-1')
        self.assertTrue(r.ok, r.err)
        self.assertEqual(r.relief, 'grp-5')
        g = self.group('grp-1')
        self.assertEqual((g.gone.cause, g.gone.relief), ('wiped', 'grp-5'))
        self.assertIn(('admin', 'relief forced by boss'), self.kinds('grp-1'))
        self.assertEqual(self.kinds('grp-1')[-1], ('relieved', 'grp-5'))
        self.assertGreaterEqual(len(self.living('grp-5')), 1)
        self.assertEqual(self.req('BOSS', op='group', n=2, gid='grp-5').group.replaces, 'grp-1')
        self.assertEqual(self.req('BOSS', op='relief', n=3, gid='grp-1').err, 'already relieved by grp-5')
        self.assertTrue(any('admin: boss forced the relief of grp-1: grp-5' in line for line in self.logs('INFO')))

    def test_forced_relief_of_an_already_gone_group_before_its_delay(self):
        self.kill('grp-2')
        self.step(0)
        due = self.group('grp-2').gone.due
        self.assertGreater(due, 0)
        r = self.req('BOSS', op='relief', n=1, gid='grp-2')
        self.assertTrue(r.ok, r.err)
        self.assertEqual(self.group('grp-2').gone.relief, r.relief)

    def test_refused_for_living_or_never_populated_groups_and_disabled_engine(self):
        n = len(self.living('grp-1'))
        self.assertEqual(self.req('BOSS', op='relief', n=1, gid='grp-1').err, f'group is not gone ({n} living)')
        self.ev(f'{GROUPS}.create({{ type = "settlers", name = "Empty" }})')
        self.assertEqual(self.req('BOSS', op='relief', n=2, gid='grp-5').err, 'group never had a member')
        self.assertEqual(self.req('BOSS', op='relief', n=3, gid='grp-99').err, 'unknown group grp-99')
        self.kill('grp-1')
        self.opt('Enabled', 'false')
        seq = self.seq()
        self.assertEqual(self.req('BOSS', op='relief', n=4, gid='grp-1').err, 'engine disabled')
        self.assertEqual(self.seq(), seq)

    def test_no_site_keeps_the_mark_and_reports_the_next_try(self):
        self.kill('grp-1')
        self.rt.execute('SAVED_GRID = GRID GRID = nil')
        r = self.req('BOSS', op='relief', n=1, gid='grp-1')
        self.assertFalse(r.ok)
        self.assertIn('no relief possible now', r.err)
        self.assertIn('next try at hour 24', r.err)
        g = self.group('grp-1')
        self.assertIsNone(g.gone.relief)
        self.assertEqual(g.gone.due, 24)
        self.rt.execute('GRID = SAVED_GRID')
        self.assertTrue(self.req('BOSS', op='relief', n=2, gid='grp-1').ok)


class HomeTests(AdminBench):
    def move(self, gid='grp-1', x=0, y=0, z=0, n=1):
        return self.req('BOSS', op='home', n=n, gid=gid, x=x, y=y, z=z)

    def free_square(self):
        """Case de la carte loin de tous les foyers et des refuges."""
        return 12000, 12000

    def test_valid_move_one_write_and_an_admin_log_entry(self):
        old = dict(self.group('grp-1').home.items())
        seq = self.seq()
        x, y = self.free_square()
        r = self.move(x=x, y=y, z=1)
        self.assertTrue(r.ok, r.err)
        self.assertEqual((r.home.x, r.home.y, r.home.z), (x, y, 1))
        self.assertEqual(dict(r.old.items()), old)
        self.assertEqual(dict(self.group('grp-1').home.items()), {'x': x, 'y': y, 'z': 1})
        self.assertEqual(self.seq(), seq + 1)
        text = f'home {old["x"]},{old["y"]},{old["z"]} -> {x},{y},1 by boss'
        self.assertEqual(self.kinds('grp-1')[-1], ('admin', text))
        self.assertTrue(any(f'admin: boss moved the home of grp-1 from {old["x"]},{old["y"]},{old["z"]} to {x},{y},1'
                            in line for line in self.logs('INFO')))

    def test_controls(self):
        x, y = self.free_square()
        other = self.group('grp-2').home
        seq = self.seq()
        cases = (
            (dict(x=1.5, y=y), 'bad square'), (dict(x=-1, y=y), 'bad square'), (dict(x=x, y=y, z=40), 'bad square'),
            (dict(x='a', y=y), 'bad square'), (dict(x=20000, y=y), 'outside the map'),
            (dict(x=3000, y=3005), 'inside a player safehouse'),
            (dict(x=other.x + 10, y=other.y + 10), 'too close to the home of grp-2'),
            (dict(gid='grp-9', x=x, y=y), 'unknown group grp-9'),
        )
        for i, (args, err) in enumerate(cases):
            with self.subTest(args=args):
                fields = dict(x=x, y=y, z=0)
                fields.update(args)
                self.assertEqual(self.move(n=i, **fields).err, err)
        old = self.group('grp-1').home
        self.assertEqual(self.move(x=old.x, y=old.y, z=old.z).err, 'home unchanged')
        self.assertEqual(self.seq(), seq)
        # Juste à HOME_GAP du foyer d'un autre groupe : accepté.
        gap = self.ev(f'{ADMIN}.CFG.HOME_GAP')
        self.assertTrue(self.move(x=other.x + gap, y=other.y, z=0).ok)

    def test_gone_group_and_missing_metagrid(self):
        self.kill('grp-3')
        self.step(5)
        x, y = self.free_square()
        self.assertEqual(self.move(gid='grp-3', x=x, y=y).err, 'group grp-3 is gone')
        self.rt.execute('GRID = nil')
        self.assertEqual(self.move(x=x, y=y).err, 'no metagrid')


class SuiteTests(AdminBench):
    """Suite en jeu lk.admin exécutée par le vrai moteur RST contre la carte de test."""

    def setUp(self):
        super().setUp()
        self.rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/shared/?.lua;]] .. package.path')
        self.rt.execute('getGameTime = function() return { getWorldAgeHours = function() return 300.25 end } end')
        self.rt.execute('if PLAYER.getZ == nil then PLAYER.getZ = function() return 0 end end')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def run_suite(self):
        self.assertTrue(self.ev('RST.start("lk.admin", { attach = false, ctx = { player = PLAYER } })'))
        for _ in range(200):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        report, results = self.run_suite()
        # E01-T16: the real "user" client needs a dedicated server and a second client (SKIP here)
        self.assertEqual(results.pop('a real client with the user role is refused without data (E01-T16)')[0], 'SKIP')
        # Fenêtre solo (2026-10-15) : client solo du jeu seulement (aucune fenêtre sur ce banc, SKIP ici)
        self.assertEqual(results.pop('solo window: debug menu button, list, detail, journal, home move, forced relief')[0], 'SKIP')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 5)
        self.assertEqual(lua_list(self.g.LivingKnox.Groups.list()), ['grp-1', 'grp-2', 'grp-3', 'grp-4'])

    def test_suite_detects_a_missing_access_check(self):
        self.rt.execute(f'{ADMIN}.isAllowed = function() return true end')
        _, results = self.run_suite()
        status, message = results['a request without an allowed player is refused without data']
        self.assertEqual(status, 'FAIL')
        self.assertIn('accepted', message)


# Harness ------------------------------------------------------------------------------------------------------------

NO_GRID = r'''
local baseWorld = getWorld
getWorld = function() local w = baseWorld() w.getMetaGrid = function() return nil end return w end
'''

CLIENT_TEXT = r'''
getText = function(key, ...)
    local parts = { key }
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    return table.concat(parts, '|')
end
getTextOrNull = function(key) return nil end
'''


def role_for(admin: bool) -> str:
    return ('local p = getSpecificPlayer(0) '
            f'p.getRole = function() return {{ hasCapability = function(_, c) return {"true" if admin else "false"} '
            'and c == Capability.PopmanManage end } end')


class HarnessBase(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, API_WORLD + NO_GRID)
            self.h.load(m, PERMISSIONS)
            for path in API_SHARED + API_SERVER:
                self.h.load(m, path)
            self.h.load(m, 'server/LivingKnox/LK_Admin.lua')
        self.h.load(self.srv, 'ADMINS.A = true local l = getOnlinePlayers() '
                              'for i = 0, l:size() - 1 do GIVE_ROLE(l:get(i)) end')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.a, self.b = self.h.load(self.srv, POPULATE)
        clients = ('solo',) if self.mode == 'solo' else ('A', 'B')
        for c in clients:
            self.h.load(c, CLIENT_TEXT)
            self.h.load(c, 'client/LivingKnox/LK_AdminView.lua')
        if self.mode == 'mp':
            self.h.load('A', role_for(True))
            self.h.load('B', role_for(False))

    def tearDown(self):
        self.h.close()


class MPTests(HarnessBase):
    def test_admin_client_gets_the_list_and_the_detail_through_the_network(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Admin.request'))       # client MP : garde avant les données
        self.assertTrue(self.h.eval('A', 'LivingKnox.AdminView.canUse()'))
        self.h.load('A', 'LivingKnox.AdminView.send("list")')
        self.assertEqual(self.h.eval('A', 'LivingKnox.AdminView.state.pending.list'), 1)
        self.h.pump()
        self.h.pump()
        rows = self.h.eval('A', 'LivingKnox.AdminView.state.groups')
        self.assertEqual([rows[i].id for i in range(1, len(rows) + 1)], [self.a, self.b])
        self.assertEqual((rows[1].home.x, rows[1].home.y, rows[1].home.z), (10637, 9412, 1))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.AdminView.state.pending.list'))
        self.h.load('A', f'LivingKnox.AdminView.select("{self.a}")')
        self.h.pump()
        self.h.pump()
        detail = self.h.eval('A', 'LivingKnox.AdminView.state.detail')
        self.assertEqual(detail.id, self.a)
        self.assertEqual(len(detail.members), 3)
        text = self.h.eval('A', 'LivingKnox.AdminView.detailText(LivingKnox.AdminView.state.detail)')
        self.assertIn('IGUI_LK_Admin_Members', text)
        self.assertIn('note', text)                                         # journal (l'admin le voit)
        self.assertEqual(self.h.errors('server'), [])

    def test_non_admin_client_gets_a_refusal_without_any_data(self):
        self.assertFalse(self.h.eval('B', 'LivingKnox.AdminView.canUse()'))
        for op, fields in (('list', ''), ('group', f'gid = "{self.a}"'), ('relief', f'gid = "{self.a}"'),
                           ('home', f'gid = "{self.a}", x = 5000, y = 5000, z = 0')):
            self.h.load('B', f'LivingKnox.AdminView.send("{op}", {{ {fields} }})')
        self.h.pump(limit=4)                                                # requêtes seulement
        replies = [m for m in self.h.pending() if m.get('command') == 'adminReply']
        self.assertEqual(len(replies), 4)
        for m in replies:
            self.assertEqual(sorted(m['args'].keys()), ['err', 'n', 'ok', 'op'])
            self.assertEqual(m['args']['err'], 'denied')
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.AdminView.state.status'), 'IGUI_LK_Admin_Denied')
        rows = self.h.eval('B', 'LivingKnox.AdminView.state.groups')
        self.assertEqual(len(rows), 0)
        self.assertTrue(any('admin: request home refused for B' in line for line in self.h.logs('server')))
        self.assertEqual(self.h.eval('server', f'LivingKnox.Groups.state.data.groups["{self.a}"].home.x'), 10637)

    def test_stale_reply_is_ignored(self):
        self.h.load('A', 'LivingKnox.AdminView.send("list") LivingKnox.AdminView.send("list")')
        self.h.pump()
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.AdminView.stats.stale'), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.AdminView.stats.received'), 1)


class SoloTests(HarnessBase):
    mode = 'solo'

    def test_solo_window_logic_calls_the_authority_directly(self):
        self.assertTrue(self.h.eval('solo', 'LivingKnox.AdminView.canUse()'))
        self.h.load('solo', 'LivingKnox.AdminView.send("list")')
        self.assertEqual(self.h.pending(), [])                               # aucune commande réseau
        rows = self.h.eval('solo', 'LivingKnox.AdminView.state.groups')
        self.assertEqual(len(rows), 2)
        self.assertIsNone(self.h.eval('solo', 'LivingKnox.AdminView.state.pending.list'))
        line = self.h.eval('solo', 'LivingKnox.AdminView.rowText(LivingKnox.AdminView.state.groups[1])')
        self.assertIn('IGUI_LK_Admin_Home|10637,9412,1', line)
        self.assertIn('IGUI_LK_Admin_Alive|2|3', line)
        self.h.load('solo', f'LivingKnox.AdminView.send("home", {{ gid = "{self.a}", x = 1, y = 1, z = 0 }})')
        self.assertEqual(self.h.eval('solo', 'LivingKnox.AdminView.state.status'),
                         'IGUI_LK_Admin_Error|no metagrid')


if __name__ == '__main__':
    unittest.main(verbosity=1)
