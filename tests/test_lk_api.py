"""Tests hors jeu de l'API publique en lecture de Living Knox (LK12-T01) : LK_API.lua (autorité).

    python RadioSurvivor/tests/test_lk_api.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Groupes construits par LivingKnox.Groups, PNJ par
LivingKnox.Identity sur le registre de LK_Store, corps liés par LivingKnox.Bodies.bound (zombies du banc). Les
doublures (getWorld, fichiers, zombies, joueurs) NE PROUVENT PAS l'API réelle, seulement la logique du mod.
Contrôles de confidentialité : aucun secret d'histoire, aucune coordonnée exacte de foyer, aucun journal, aucune
valeur autre que chaîne, nombre, booléen ou table, aucune table partagée avec les registres.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402

API_FILE = LUA / 'server' / 'LivingKnox' / 'LK_API.lua'
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/LK_Appearance.lua', 'shared/LivingKnox/LK_Identity.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = ('server/LivingKnox/LK_Server.lua', 'server/LivingKnox/LK_Stories.lua', 'server/LivingKnox/LK_API.lua')

WORLD = r'''
getWorld = function()
    return { getWorld = function() return 'rstest_api' end, getGameMode = function() return 'Multiplayer' end }
end
'''

# Outils Lua du banc : sérialisation déterministe, contrôle des valeurs, tables partagées avec les registres.
TOOLS = r'''
function DUMP(v)
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. '=' .. DUMP(v[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
end
-- Première valeur interdite (fonction, objet du moteur, table à métatable), ou nil.
function BAD_VALUE(v, path)
    path = path or '$'
    local t = type(v)
    if t == 'string' or t == 'number' or t == 'boolean' then return nil end
    if t ~= 'table' then return path .. ' is a ' .. t end
    if getmetatable(v) ~= nil then return path .. ' has a metatable' end
    for k, x in pairs(v) do
        if type(k) ~= 'string' and type(k) ~= 'number' then return path .. ' has a ' .. type(k) .. ' key' end
        local bad = BAD_VALUE(x, path .. '.' .. tostring(k))
        if bad then return bad end
    end
    return nil
end
local function collect(v, set)
    if type(v) ~= 'table' or set[v] then return end
    set[v] = true
    for _, x in pairs(v) do collect(x, set) end
end
-- Vrai si le résultat partage une table avec le registre des groupes ou celui des PNJ.
function SHARES(v)
    local set = {}
    collect(LivingKnox.Groups.state.data, set)
    collect(LivingKnox.Store.state.data, set)
    local found = false
    local function walk(x)
        if type(x) ~= 'table' or found then return end
        if set[x] then found = true return end
        for _, y in pairs(x) do walk(y) end
    end
    walk(v)
    return found
end
'''

# Deux groupes, un foyer exact (10637, 9412, 0) et une histoire composée dont les secrets sont gardés à part.
POPULATE = r'''
local G, S = LivingKnox.Groups, LivingKnox.Stories
STORY = assert(S.compose('settlers', 77, { secrets = 3 }))
local a = assert(G.create({ type = 'settlers', name = 'Mill Folk', story = STORY.summary.en,
    home = { x = 10637, y = 9412, z = 1 }, day = 2 })).id
local b = assert(G.create({ type = 'raiders', name = 'Crows', day = 3 })).id
local m1 = G.addMember(a, { role = 'worker', npc = 'lk-1', day = 2 })
local m2 = G.addMember(a, { role = 'fighter', npc = 'lk-2', day = 2 })
local m3 = G.addMember(a, { role = 'medic', day = 2 })
assert(G.setLeader(a, m1, 2))
assert(G.markDead(a, m3, 4))
assert(G.setNeed(a, 'food', 20)); assert(G.setNeed(a, 'medical', 35)); assert(G.setNeed(a, 'ammo', 60))
assert(G.setMorale(a, 71))
-- Journal privé, contenant un secret : ne doit jamais sortir.
assert(G.addLog(a, 'note', STORY.secrets[1].en, 4))
G.update(function(data) data.groups[a].task = 'scavenge' return true end)
G.addMember(b, { role = 'scout', npc = 'lk-5' })
return a, b
'''

# PNJ (registre des corps) autour du joueur A placé en (100, 100, 0).
NPCS = r'''
local I, r = LivingKnox.Identity, LivingKnox.Store.data()
local function npc(state, last)
    local n = assert(I.create(r, { female = false }, 1, 1, 0))
    if state == 'embodied' then I.markEmbodied(n, 1) elseif state == 'dead' then I.markDead(n) end
    n.last = last
    return n
end
npc('embodied', { x = 110, y = 100, z = 1 })   -- lk-1 : groupe a, worker, 10 cases, un étage au-dessus
npc('embodied', { x = 900, y = 900, z = 0 })   -- lk-2 : corps lié en (103, 104) : position vivante
npc('virtual', { x = 101, y = 100, z = 0 })    -- lk-3 : virtuel, exclu
npc('dead', { x = 102, y = 100, z = 0 })       -- lk-4 : mort, exclu
npc('embodied', { x = 145, y = 100, z = 0 })   -- lk-5 : groupe b, 45 cases
npc('embodied', { x = 200, y = 100, z = 0 })   -- lk-6 : 100 cases, au-delà du plafond
npc('embodied', nil)                           -- lk-7 : incarné sans position connue, exclu
LivingKnox.Bodies.bound['lk-2'] = HARNESS.zombies[1001]
'''


class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, WORLD)
            for path in SHARED + SERVER:
                self.h.load(m, path)
        self.h.load(self.srv, TOOLS)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.a, self.b = self.run_lua(POPULATE)
        self.h.spawn_zombie(1001, 103, 104, 0)
        self.h.move_player('A', 100, 100, 0)
        self.run_lua(NPCS)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval(self.srv, code)

    def run_lua(self, code):
        return self.h.load(self.srv, code)

    def secrets(self):
        out = []
        for i in range(1, 4):
            for lang in ('en', 'fr'):
                out.append(self.ev(f'STORY.secrets[{i}].{lang}'))
        return out

    def assert_clean(self, expr):
        """Résultat sans valeur interdite, sans table partagée, sans secret ni coordonnée exacte du foyer."""
        self.assertIsNone(self.ev(f'BAD_VALUE({expr})'), expr)
        self.assertFalse(self.ev(f'SHARES({expr})'), expr)
        dump = self.ev(f'DUMP({expr})')
        for s in self.secrets():
            self.assertNotIn(s, dump, expr)
        self.assertNotIn('10637', dump)
        self.assertNotIn('9412', dump)
        for key in ('home=', 'log=', 'story=', 'nextMember=', 'wound=', 'secrets='):
            self.assertNotIn(key, dump, expr)
        return dump


class VersionTests(Base):
    def test_control_is_not_vacuous(self):
        """Le registre brut contient bien un secret (journal) et le foyer exact : assert_clean le refuserait."""
        raw = self.ev(f'DUMP(LivingKnox.Groups.state.data.groups["{self.a}"])')
        self.assertIn(self.ev('STORY.secrets[1].en'), raw)
        self.assertIn('10637', raw)
        self.assertTrue(all(len(s) > 10 for s in self.secrets()))
        self.assertIsNotNone(self.ev('BAD_VALUE({ HARNESS.zombies[1001] })'))
        self.assertTrue(self.ev(f'SHARES({{ LivingKnox.Groups.state.data.groups["{self.a}"].needs }})'))
        with self.assertRaises(AssertionError):
            self.assert_clean(f'LivingKnox.Groups.get("{self.a}")')

    def test_version(self):
        self.assertEqual(self.ev('LivingKnox.API.VERSION'), 1)
        self.assertEqual(self.ev('LivingKnox.API.version()'), 1)
        self.assertTrue(self.ev('LivingKnox.API.isReady()'))


class GroupTests(Base):
    def test_list_groups_fields(self):
        groups = self.ev('LivingKnox.API.listGroups()')
        self.assertEqual([g.id for g in groups.values()], [self.a, self.b])
        g = groups[1]
        self.assertEqual((g.type, g.typeNameKey, g.name, g.founded), ('settlers', self.ev(
            'LivingKnox.GroupTypes.get("settlers").nameKey'), 'Mill Folk', 2))
        self.assertEqual((g.alive, g.total, g.morale, g.task), (2, 3, 71, 'scavenge'))
        self.assertEqual((g.needs.food, g.needs.medical, g.needs.ammo), (20, 35, 60))
        self.assertEqual((g.leader.id, g.leader.npc, g.leader.name), ('m-1', 'lk-1', None))
        self.assertEqual((g.area.x, g.area.y, g.area.size), (10650, 9450, 100))
        self.assertIsNone(g.area.z)
        self.assertEqual(g.summary, self.ev('STORY.summary.en'))
        self.assertIsNone(g.attitude)  # sans joueur fourni : nil (attitude par joueur, LK11-T03)
        self.assertIsNone(g.members)   # listGroups : pas de membres
        crows = groups[2]
        self.assertIsNone(crows.area)
        self.assertIsNone(crows.leader)
        self.assertIsNone(crows.task)
        self.assert_clean('LivingKnox.API.listGroups()')

    def test_get_group_members(self):
        g = self.ev(f'LivingKnox.API.getGroup("{self.a}")')
        members = [(m.id, m.role, m.alive, m.npc) for m in g.members.values()]
        self.assertEqual(members, [('m-1', 'worker', True, 'lk-1'), ('m-2', 'fighter', True, 'lk-2'),
                                   ('m-3', 'medic', False, None)])
        self.assertEqual(g.name, 'Mill Folk')
        self.assert_clean(f'LivingKnox.API.getGroup("{self.a}")')
        res = self.run_lua('return LivingKnox.API.getGroup("grp-99")')
        self.assertEqual(list(res) if isinstance(res, tuple) else res, [None, 'unknown group grp-99'])
        res = self.run_lua('return LivingKnox.API.getGroup(12)')
        self.assertEqual(res[0], None)

    def test_results_are_fresh_copies(self):
        self.run_lua(f'''
            local g = LivingKnox.API.getGroup("{self.a}")
            g.name = "changed"; g.needs.food = 99; g.members[1].role = "leader"; g.area.x = 0
            local l = LivingKnox.API.listGroups(); l[1].morale = 0; l[1].leader.id = "m-9"
            local n = LivingKnox.API.npcsNear(100, 100, 0); n[1].group = "grp-77"
            assert(LivingKnox.API.getGroup("{self.a}") ~= LivingKnox.API.getGroup("{self.a}"))
        ''')
        g = self.ev(f'LivingKnox.Groups.get("{self.a}")')
        self.assertEqual((g.name, g.needs.food, g.members['m-1'].role, g.morale, g.leader, g.home.x),
                         ('Mill Folk', 20, 'worker', 71, 'm-1', 10637))
        self.assertEqual(self.ev(f'LivingKnox.API.getGroup("{self.a}").name'), 'Mill Folk')
        self.assertEqual(self.ev('LivingKnox.API.npcsNear(100, 100, 0)[1].group'), self.a)

    def test_area_grid(self):
        self.assertEqual(self.ev('DUMP(LivingKnox.API.area(0, 99))'), '{size=100,x=50,y=50}')
        self.assertEqual(self.ev('DUMP(LivingKnox.API.area(100, 199.9))'), '{size=100,x=150,y=150}')
        self.assertIsNone(self.ev('LivingKnox.API.area("1", 2)'))

    def test_not_ready(self):
        self.run_lua('LivingKnox.Groups.state.blocked = true')
        self.assertFalse(self.ev('LivingKnox.API.isReady()'))
        self.assertEqual(self.ev('#LivingKnox.API.listGroups()'), 0)
        res = self.run_lua(f'return LivingKnox.API.getGroup("{self.a}")')
        self.assertEqual(list(res), [None, 'group registry not ready'])
        # Les PNJ à portée restent lisibles, sans groupe.
        near = self.ev('LivingKnox.API.npcsNear(100, 100, 0)')
        self.assertEqual([(p.id, p.group) for p in near.values()], [('lk-2', None), ('lk-1', None)])


class PublicGroupTests(Base):
    def test_public_group_of_a_view(self):
        dump = self.assert_clean(f'LivingKnox.API.publicGroup(LivingKnox.API.getGroup("{self.a}"))')
        self.assertEqual(dump, self.ev(f'DUMP(LivingKnox.API.getGroup("{self.a}"))'))

    def test_public_group_of_a_raw_registry_group(self):
        expr = f'LivingKnox.API.publicGroup(LivingKnox.Groups.state.data.groups["{self.a}"])'
        self.assert_clean(expr)
        self.assertEqual(self.ev(f'DUMP({expr})'), self.ev(f'DUMP(LivingKnox.API.getGroup("{self.a}"))'))
        # Le groupe brut n'est pas modifié.
        self.assertEqual(self.ev(f'LivingKnox.Groups.state.data.groups["{self.a}"].home.x'), 10637)

    def test_public_group_drops_unknown_and_non_plain_fields(self):
        self.run_lua(f'''
            local v = LivingKnox.API.getGroup("{self.a}")
            v.area = {{ x = 10637, y = 9412, size = 1 }}
            v.secret = "hidden"; v.home = nil; v.name = function() end; v.leader.obj = HARNESS.zombies[1001]
            v.members[1].wound = 40; v.members[1].npc = HARNESS.zombies[1001]; v.needs.water = 3
            PUB = LivingKnox.API.publicGroup(v)
        ''')
        dump = self.assert_clean('PUB')
        self.assertEqual(self.ev('DUMP(PUB.area)'), '{size=100,x=10650,y=9450}')
        for key in ('secret=', 'water=', 'obj='):
            self.assertNotIn(key, dump)
        self.assertIsNone(self.ev('PUB.name'))
        self.assertIsNone(self.ev('PUB.members[1].npc'))
        self.assertIsNone(self.ev('LivingKnox.API.publicGroup("x")'))


class NearTests(Base):
    def test_near_player(self):
        near = self.ev('LivingKnox.API.npcsNear(HARNESS.players.A)')
        rows = [(p.id, p.group, p.member, p.role, p.distance, p.floor, p.inWorld) for p in near.values()]
        self.assertEqual(rows, [('lk-2', self.a, 'm-2', 'fighter', 5, 0, True),
                                ('lk-1', self.a, 'm-1', 'worker', 10, 1, False)])
        self.assert_clean('LivingKnox.API.npcsNear(HARNESS.players.A)')

    def test_near_coordinates_radius_and_cap(self):
        ids = lambda expr: [p.id for p in self.ev(expr).values()]  # noqa: E731
        self.assertEqual(ids('LivingKnox.API.npcsNear(100, 100, 0, 50)'), ['lk-2', 'lk-1', 'lk-5'])
        self.assertEqual(ids('LivingKnox.API.npcsNear(100, 100, 0, 10000)'), ['lk-2', 'lk-1', 'lk-5'])  # plafond 50
        self.assertEqual(ids('LivingKnox.API.npcsNear(100, 100, 0, 5)'), ['lk-2'])
        self.assertEqual(ids('LivingKnox.API.npcsNear(HARNESS.players.A, 0)'), [])
        self.assertEqual(self.ev('LivingKnox.API.npcsNear(100, 100, 0, 50)[3].group'), self.b)
        self.assertEqual(self.ev('LivingKnox.API.NEAR_MAX'), 50)

    def test_body_out_of_world_uses_last_position(self):
        self.h.kill_zombie(1001)
        near = self.ev('LivingKnox.API.npcsNear(100, 100, 0, 50)')
        self.assertEqual([p.id for p in near.values()], ['lk-1', 'lk-5'])  # lk-2 : dernière vue en (900, 900)

    def test_bad_arguments(self):
        for call in ('npcsNear()', 'npcsNear("x")', 'npcsNear(1, 2)', 'npcsNear(1, 2, 0, -1)',
                     'npcsNear(1, 2, 0, "9")', 'npcsNear({})'):
            res = self.run_lua(f'return LivingKnox.API.{call}')
            self.assertIsNone(res[0], call)
            self.assertIn(res[1], ('bad position', 'bad radius'), call)

    def test_npc_registry_not_ready(self):
        self.run_lua('LivingKnox.Store.state.blocked = true')
        res = self.run_lua('return LivingKnox.API.npcsNear(100, 100, 0)')
        self.assertEqual(list(res), [None, 'npc registry not ready'])


class AttitudeTests(Base):
    """LK11-T03 : attitude d'un groupe envers UN joueur, dans une projection demandée pour ce joueur."""
    P1, P2 = 'character-1-1-111111', 'character-1-2-222222'

    def setUp(self):
        super().setUp()
        self.run_lua(f'''
            local H = LivingKnox.Hostility
            assert(H.record("{self.a}", "{self.P1}", "shot", {{ witnessed = true }}))
            assert(H.record("{self.a}", "{self.P1}", "kill", {{ attributable = true }}))
            assert(H.record("{self.a}", "{self.P2}", "heal", {{ witnessed = true }}))
        ''')

    def test_attitude_function(self):
        self.assertEqual(self.ev(f'DUMP(LivingKnox.API.attitude("{self.a}", "{self.P1}"))'),
                         '{level=wary,trend=down}')  # 50 - 25 - 60 = -35
        self.assertEqual(self.ev(f'DUMP(LivingKnox.API.attitude("{self.a}", "{self.P2}"))'),
                         '{level=trusting,trend=up}')
        # Groupe sans fait envers ce joueur : niveau de départ du type.
        self.assertEqual(self.ev(f'DUMP(LivingKnox.API.attitude("{self.b}", "{self.P1}"))'),
                         '{level=hostile,trend=stable}')
        self.assertEqual(list(self.run_lua(f'return LivingKnox.API.attitude("{self.a}", "bad key!")')),
                         [None, 'bad player key'])
        self.assertEqual(list(self.run_lua(f'return LivingKnox.API.attitude("grp-99", "{self.P1}")')),
                         [None, 'unknown group grp-99'])
        self.assert_clean(f'LivingKnox.API.attitude("{self.a}", "{self.P1}")')

    def test_views_for_a_player(self):
        g1 = self.ev(f'LivingKnox.API.getGroup("{self.a}", "{self.P1}")')
        g2 = self.ev(f'LivingKnox.API.listGroups("{self.P2}")')[1]
        self.assertEqual((g1.attitude.level, g1.attitude.trend), ('wary', 'down'))
        self.assertEqual((g2.attitude.level, g2.attitude.trend), ('trusting', 'up'))
        self.assertIsNone(self.ev(f'LivingKnox.API.getGroup("{self.a}").attitude'))
        self.assertIsNone(self.ev(f'LivingKnox.API.listGroups()[1].attitude'))
        dump = self.assert_clean(f'LivingKnox.API.getGroup("{self.a}", "{self.P1}")')
        self.assertIn('attitude={level=wary,trend=down}', dump)
        for key in ('value=', 'start=', 'murder=', 'facts=', self.P1):
            self.assertNotIn(key, dump)

    def test_public_projection_keeps_only_level_and_trend(self):
        dump = self.assert_clean(
            f'LivingKnox.API.publicGroup(LivingKnox.API.getGroup("{self.a}", "{self.P2}"))')
        self.assertIn('attitude={level=trusting,trend=up}', dump)
        self.run_lua(f'''
            local v = LivingKnox.API.getGroup("{self.a}", "{self.P1}")
            v.attitude.value = -70; v.attitude.facts = {{ "kill" }}
            PUB1 = LivingKnox.API.publicGroup(v)
            v.attitude = {{ level = "furious", trend = "down" }}
            PUB2 = LivingKnox.API.publicGroup(v)
        ''')
        self.assertEqual(self.ev('DUMP(PUB1.attitude)'), '{level=wary,trend=down}')
        self.assertIsNone(self.ev('PUB2.attitude'))


class SupplyTests(Base):
    """LK12-T03 : offres de ressources dérivées des réserves réelles, livraison idempotente par clé de reçu.

    Groupe a : food 20 (sous NEED_LOW : 60 V), medical 35 (sous NEED_OK : 40 V), ammo 60 (non manquante : source de la
    récompense, une boîte de chevrotine). Groupe b : réserves à 50, aucun besoin.
    """
    FOOD, MED = 'grp-1-food-1', 'grp-1-medical-2'
    P1 = 'character-1-1-111111'

    def setUp(self):
        super().setUp()
        self.offers = self.ev(f'LivingKnox.API.missionOffers("{self.a}")')

    def deliver(self, offer, items, key, player=None):
        lua_items = '{' + ', '.join(f'["{t}"] = {n}' for t, n in items.items()) + '}'
        p = f', "{player}"' if player else ''
        res = self.run_lua(f'R = {{ LivingKnox.API.deliver("{self.a}", "{offer}", {lua_items}, "{key}"{p}) }}'
                           f' return R[1], R[2]')
        return res if isinstance(res, tuple) else (res, None)

    def need(self, key):
        return self.ev(f'LivingKnox.Groups.state.data.groups["{self.a}"].needs.{key}')

    def supply_logs(self):
        log = self.ev(f'LivingKnox.Groups.state.data.groups["{self.a}"].log')
        return [e.text for e in log.values() if e.kind == 'supply']

    def advance_hours(self, hours):
        self.h.age_minutes += hours * 60
        self.h._push_clock()

    def test_offers_from_real_needs(self):
        rows = [(o.id, o.group, o.need, o.level, o.value, o.delivered, o.remaining, o.points, o.hours)
                for o in self.offers.values()]
        self.assertEqual(rows, [(self.FOOD, self.a, 'food', 20, 60, 0, 60, 15, 48),
                                (self.MED, self.a, 'medical', 35, 40, 0, 40, 10, 48)])
        food = self.offers[1]
        items = {it.type: (it.value, it.count) for it in food['items'].values()}
        self.assertEqual(len(items), 14)
        self.assertEqual(items['Base.TinnedBeans'], (2, 30))
        self.assertTrue(all(t.startswith('Base.') for t in items))
        med = {it.type: (it.value, it.count) for it in self.offers[2]['items'].values()}
        self.assertEqual(med['Base.Antibiotics'], (8, 5))
        self.assertNotIn('Base.AntibioticsBox', med)
        self.assertEqual(self.ev('DUMP(LivingKnox.API.missionOffers("grp-1")[1].reward)'),
                         '{attitudeFact=delivery,item={count=1,type=Base.ShotgunShellsBox}}')
        self.assert_clean(f'LivingKnox.API.missionOffers("{self.a}")')
        # Identifiants stables : un second appel ne rouvre rien et n'écrit pas le registre.
        seq = self.ev('LivingKnox.Groups.state.seq')
        self.assertEqual([o.id for o in self.ev(f'LivingKnox.API.missionOffers("{self.a}")').values()],
                         [self.FOOD, self.MED])
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq)
        # Toutes les valeurs V du barème sont dans les objets acceptés de leur réserve.
        self.assertEqual(self.ev('DUMP(LivingKnox.API.REWARD_ITEMS)'),
                         '{ammo=Base.ShotgunShellsBox,food=Base.TinnedBeans,medical=Base.Antibiotics}')

    def test_no_offer_without_need_or_living_member(self):
        self.assertEqual(self.ev(f'#LivingKnox.API.missionOffers("{self.b}")'), 0)
        self.run_lua(f'for _, k in ipairs({{"food", "medical", "ammo"}}) do '
                     f'assert(LivingKnox.Groups.setNeed("{self.b}", k, 39)) end')
        offers = self.ev(f'LivingKnox.API.missionOffers("{self.b}")')
        self.assertEqual([o.id for o in offers.values()], ['grp-2-food-1', 'grp-2-medical-2', 'grp-2-ammo-3'])
        self.assertIsNone(offers[1].reward.item)  # aucune réserve non manquante : réputation seule
        self.assertEqual(offers[1].value, 40)
        self.run_lua(f'assert(LivingKnox.Groups.markDead("{self.b}", "m-1"))')
        self.assertEqual(self.ev(f'#LivingKnox.API.missionOffers("{self.b}")'), 0)
        res = self.run_lua('return LivingKnox.API.missionOffers("grp-99")')
        self.assertEqual(list(res), [None, 'unknown group grp-99'])

    def test_hostile_player_gets_no_offer(self):
        self.run_lua(f'''
            local H = LivingKnox.Hostility
            assert(H.record("{self.a}", "{self.P1}", "kill", {{ witnessed = true }}))
            assert(H.record("{self.a}", "{self.P1}", "kill", {{ witnessed = true }}))
        ''')
        self.assertEqual(self.ev(f'LivingKnox.API.attitude("{self.a}", "{self.P1}").level'), 'hostile')
        self.assertEqual(self.ev(f'#LivingKnox.API.missionOffers("{self.a}", "{self.P1}")'), 0)
        self.assertEqual(self.ev(f'#LivingKnox.API.missionOffers("{self.a}", "character-2-1-1")'), 2)
        self.assertEqual(list(self.run_lua(f'return LivingKnox.API.missionOffers("{self.a}", "bad key!")')),
                         [None, 'bad player key'])
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 2}, 'k1', self.P1), (None, 'group is hostile'))
        self.assertEqual(self.need('food'), 20)

    def test_delivery_raises_reserve_once(self):
        res, err = self.deliver(self.FOOD, {'Base.TinnedBeans': 6, 'Base.Rice': 4}, 'm1-d1')
        self.assertIsNone(err)
        self.assertEqual((res.applied, res.duplicate, res.offer, res.need, res.value, res.points, res.level,
                          res.completed, res.reward), (True, False, self.FOOD, 'food', 20, 5, 25, False, None))
        self.assert_clean('R[1]')
        self.assertEqual(self.need('food'), 25)
        # Rejeu (même clé, même contenu) puis double appel (même clé, autre contenu) : aucun effet.
        for items in ({'Base.TinnedBeans': 6, 'Base.Rice': 4}, {'Base.TinnedBeans': 20}):
            res, err = self.deliver(self.FOOD, items, 'm1-d1')
            self.assertEqual((res.applied, res.duplicate, res.value, res.points, res.level), (False, True, 20, 5, 25))
        self.assertEqual(self.need('food'), 25)
        self.assertEqual(self.supply_logs(), ['food +5 (grp-1-food-1, 20 V)'])
        self.assertEqual(self.ev(f'LivingKnox.API.missionOffers("{self.a}")[1].remaining'), 40)
        # Même clé pour une autre offre : refus, sans effet.
        self.assertEqual(self.deliver(self.MED, {'Base.Bandage': 1}, 'm1-d1'), (None, 'receipt key already used'))
        self.assertEqual(self.need('medical'), 35)
        # Le reçu survit à une relecture du registre (redémarrage).
        self.run_lua('LivingKnox.Groups.state.data = nil; assert(LivingKnox.Groups.ensure())')
        res, _ = self.deliver(self.FOOD, {'Base.TinnedBeans': 6, 'Base.Rice': 4}, 'm1-d1')
        self.assertTrue(res.duplicate)
        self.assertEqual(self.need('food'), 25)

    def test_completion_reward_and_new_offer(self):
        self.deliver(self.FOOD, {'Base.TinnedBeans': 10}, 'd1')
        res, err = self.deliver(self.FOOD, {'Base.CannedChili': 20}, 'd2')
        self.assertIsNone(err)
        self.assertEqual((res.value, res.points, res.level, res.completed), (40, 10, 35, True))
        self.assertEqual(self.ev('DUMP(R[1].reward)'), '{attitudeFact=delivery,item={count=1,type=Base.ShotgunShellsBox}}')
        self.assertEqual(self.need('ammo'), 57)  # boîte de 12 V cédée : 3 points
        self.assertEqual(self.supply_logs()[-1],
                         'food +10 (grp-1-food-1, 40 V), gives 1 Base.ShotgunShellsBox, done')
        # Offre remplie : fermée ; la réserve reste sous NEED_OK, une nouvelle offre s'ouvre sous un autre identifiant.
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 1}, 'd3'), (None, 'offer closed'))
        ids = [o.id for o in self.ev(f'LivingKnox.API.missionOffers("{self.a}")').values()]
        self.assertEqual(ids, ['grp-1-food-3', self.MED])  # ordre de API.NEEDS
        # Rejeu de la livraison qui a complété l'offre : même résultat, aucune seconde récompense.
        res, _ = self.deliver(self.FOOD, {'Base.CannedChili': 20}, 'd2')
        self.assertEqual((res.duplicate, res.completed, res.reward.item.count), (True, True, 1))
        self.assertEqual((self.need('food'), self.need('ammo')), (35, 57))

    def test_cumulative_rounding_and_last_item_overshoot(self):
        points = [self.deliver(self.MED, {'Base.Bandage': 1}, f'b{i}')[0].points for i in range(3)]
        self.assertEqual(points, [0, 1, 0])  # 3 V au total : round(3 / 4) = 1 point, sans perte ni double compte
        self.deliver(self.MED, {'Base.Antibiotics': 4}, 'a1')  # 35 V
        # Reste 5 V : 2 désinfectants (6 V) passent (seul le dernier dépasse), 3 seraient de trop.
        self.assertEqual(self.deliver(self.MED, {'Base.Disinfectant': 3}, 'x1'), (None, 'too many items'))
        res, _ = self.deliver(self.MED, {'Base.Disinfectant': 2}, 'x2')
        self.assertEqual((res.value, res.completed, self.need('medical')), (5, True, 45))  # 35 + 40 / 4

    def test_reserve_bounds_and_withdrawn_reward(self):
        self.run_lua(f'assert(LivingKnox.Groups.setNeed("{self.a}", "food", 99))')  # après l'ouverture de l'offre
        self.run_lua(f'assert(LivingKnox.Groups.setNeed("{self.a}", "ammo", 41))')
        res, _ = self.deliver(self.FOOD, {'Base.TinnedBeans': 30}, 'big')
        self.assertEqual((res.points, res.level, res.completed), (1, 100, True))
        self.assertIsNone(self.ev('R[1].reward.item'))  # la cession ferait passer ammo sous NEED_OK : retirée
        self.assertEqual(self.ev('R[1].reward.attitudeFact'), 'delivery')
        self.assertEqual(self.need('ammo'), 41)
        self.assertIn('reward withdrawn', self.supply_logs()[-1])

    def test_expired_offer(self):
        self.advance_hours(48)
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 2}, 'late'), (None, 'offer expired'))
        self.assertEqual(self.need('food'), 20)
        ids = [o.id for o in self.ev(f'LivingKnox.API.missionOffers("{self.a}")').values()]
        self.assertEqual(ids, ['grp-1-food-3', 'grp-1-medical-4'])
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 2}, 'late'), (None, 'offer closed'))

    def test_bad_deliveries_change_nothing(self):
        bad = [
            ({'Base.Bandage': 1}, 'item not accepted: Base.Bandage'),
            ({'TinnedBeans': 1}, 'item not accepted: TinnedBeans'),
            ({'Base.AntibioticsBox': 1}, 'item not accepted: Base.AntibioticsBox'),
            ({'Base.TinnedBeans': 0}, 'bad count for Base.TinnedBeans'),
            ({'Base.TinnedBeans': 1.5}, 'bad count for Base.TinnedBeans'),
            ({'Base.TinnedBeans': '"2"'}, 'bad count for Base.TinnedBeans'),
            ({'Base.TinnedBeans': 61}, 'bad count for Base.TinnedBeans'),
            ({}, 'nothing delivered'),
            ({'Base.TinnedBeans': 31}, 'too many items'),
        ]
        for items, why in bad:
            self.assertEqual(self.deliver(self.FOOD, items, 'k'), (None, why), items)
        for offer, why in (('grp-2-food-1', 'unknown offer grp-2-food-1'), ('grp-1-water-1', 'unknown offer grp-1-water-1'),
                           ('grp-1-food-9', 'offer closed'), ('x', 'unknown offer x')):
            self.assertEqual(self.deliver(offer, {'Base.TinnedBeans': 1}, 'k'), (None, why))
        for key in ('', 'bad key', 'x' * 65):
            self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 1}, key), (None, 'bad receipt key'))
        res = self.run_lua(f'return LivingKnox.API.deliver("{self.a}", "{self.FOOD}", "beans", "k")')
        self.assertEqual(list(res), [None, 'bad delivery'])
        self.assertEqual(self.need('food'), 20)
        self.assertEqual(self.supply_logs(), [])
        # La clé 'k' n'a été consommée par aucun refus : elle sert encore.
        res, _ = self.deliver(self.FOOD, {'Base.TinnedBeans': 30}, 'k')
        self.assertTrue(res.applied)

    def test_not_ready_and_malformed_state(self):
        self.run_lua('LivingKnox.Groups.state.blocked = true')
        self.assertEqual(list(self.run_lua(f'return LivingKnox.API.missionOffers("{self.a}")')),
                         [None, 'group registry not ready'])
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 1}, 'k'), (None, 'group registry not ready'))
        self.run_lua('LivingKnox.Groups.state.blocked = false')
        # État des offres corrompu : remis à neuf (numérotation conservée), l'ancienne offre est fermée.
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{self.a}"].supply.offers.food.value = "x"')
        self.assertEqual(self.deliver(self.FOOD, {'Base.TinnedBeans': 1}, 'k'), (None, 'offer closed'))
        ids = [o.id for o in self.ev(f'LivingKnox.API.missionOffers("{self.a}")').values()]
        self.assertEqual(ids, ['grp-1-food-3', 'grp-1-medical-4'])


class ClientTests(Base):
    def test_no_api_on_mp_clients(self):
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.API'))


class SoloTests(Base):
    mode = 'solo'

    def test_solo(self):
        self.assertEqual(self.ev('LivingKnox.API.version()'), 1)
        self.assertEqual(self.ev('#LivingKnox.API.listGroups()'), 2)
        near = self.ev('LivingKnox.API.npcsNear(HARNESS.players.A)')
        self.assertEqual([p.id for p in near.values()], ['lk-2', 'lk-1'])


class SourceTests(unittest.TestCase):
    def test_source_writes_only_through_groups_update_and_is_kahlua_safe(self):
        # Depuis LK12-T03, les seules écritures passent par LivingKnox.Groups.update (aucun save ni fichier ici).
        src = API_FILE.read_text(encoding='utf-8')
        code = '\n'.join(re.sub(r'--.*$', '', line) for line in src.splitlines())
        self.assertTrue(code.isascii())
        self.assertTrue(src.splitlines()[next(i for i, l in enumerate(src.splitlines()) if 'isClient' in l)]
                        .startswith('if isClient() then return end'))
        for word in (r'\bnext\s*\(', r'\bgoto\b', r'coroutine', r'ModData', r'sendServerCommand', r'getFileWriter',
                     r'\bsave\s*\(', r'\bcommit\b', r'getGridSquare', r'getZombieList', r'[&|~]\s*\d', r'<<|>>'):
            self.assertIsNone(re.search(word, code), word)


# LK12-T02 : enregistreur d'événements publics, écrit comme un mod tiers (aucune dépendance : il déclare les noms).
RECORDER = r'''
EV = {}
for _, name in ipairs({ "OnLivingKnoxGroupCreated", "OnLivingKnoxMemberDied", "OnLivingKnoxGroupGone",
        "OnLivingKnoxNeedCritical", "OnLivingKnoxEncounter", "OnLivingKnoxMemberLeft" }) do
    LuaEventManager.AddEvent(name)
    Events[name].Add(function(e) EV[#EV + 1] = { name = name, e = e } end)
end
function EVS(name)
    local out = {}
    for _, r in ipairs(EV) do if r.name == name then out[#out + 1] = r.e end end
    return out
end
'''


class EventTests(Base):
    """Événements publics (LK12-T02) : une fois par fait, après la transaction, charge utile publique."""

    def setUp(self):
        super().setUp()
        self.run_lua(RECORDER)

    def names(self):
        return [r.name for r in self.ev('EV').values()]

    def flush(self):
        # Seul le pas qui vide la file : h.tick() lancerait aussi les OnTick des autres modules (hors de ce banc).
        self.h.fire(self.srv, 'OnTickEvenPaused', 0.0)

    def test_names_declared_on_authority_only(self):
        self.assertEqual(self.ev('DUMP(LivingKnox.API.EVENTS)'),
                         '{encounter=OnLivingKnoxEncounter,groupCreated=OnLivingKnoxGroupCreated,'
                         'groupGone=OnLivingKnoxGroupGone,memberDied=OnLivingKnoxMemberDied,'
                         'memberLeft=OnLivingKnoxMemberLeft,needCritical=OnLivingKnoxNeedCritical}')
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'Events.OnLivingKnoxMemberDied'))
        # Redéclaration (AddEvent idempotent) : l'abonné déjà inscrit reste en place.
        self.run_lua('LuaEventManager.AddEvent("OnLivingKnoxGroupCreated")')
        self.flush()
        self.assertEqual(self.names().count('OnLivingKnoxGroupCreated'), 2)

    def test_created_and_offscreen_death_after_transaction_once(self):
        self.assertEqual(self.names(), [])  # rien avant le pas suivant
        self.flush()
        self.assertEqual(self.names(), ['OnLivingKnoxGroupCreated', 'OnLivingKnoxGroupCreated',
                                        'OnLivingKnoxMemberDied'])
        a = self.ev('EVS("OnLivingKnoxGroupCreated")[1]')
        self.assertEqual((a.group, a.type, a.name, a.day, a.alive, a.area.x, a.area.y),
                         (self.a, 'settlers', 'Mill Folk', 2, 2, 10650, 9450))  # état relu au pas : m-3 mort
        b = self.ev('EVS("OnLivingKnoxGroupCreated")[2]')
        self.assertEqual((b.group, b.alive, b.area), (self.b, 1, None))
        d = self.ev('EVS("OnLivingKnoxMemberDied")[1]')
        self.assertEqual((d.group, d.member, d.npc, d.role, d.offscreen, d.byPlayer, d.cause, d.groupAlive, d.day),
                         (self.a, 'm-3', None, 'medic', True, False, None, 2, 4))
        self.assert_clean('EV')
        self.flush()
        self.assertEqual(len(self.names()), 3)  # aucun second déclenchement

    def test_in_world_death_once_without_private_fields(self):
        self.flush()
        self.run_lua(f'''
            local G = LivingKnox.Groups
            G.update(function(d) G.applyDeath(d.groups["{self.a}"], "m-2", 5, true) return true end)
            LivingKnox.publish("memberDied", {{ group = "{self.a}", member = "m-2", npc = "lk-2", day = 5,
                offscreen = false, body = HARNESS.zombies[1001], cause = "firearm", killer = "bob" }})
            LivingKnox.publish("npcDied", {{ npc = "lk-2", generation = 1, cause = "firearm", killer = "bob",
                weapon = "Base.Pistol", group = "{self.a}", member = "m-2", x = 10637, y = 9412, z = 0,
                body = HARNESS.zombies[1001] }})
            -- Double publication (markDead appelé en plus) : même fait, aucun second événement.
            LivingKnox.publish("memberDied", {{ group = "{self.a}", member = "m-2", npc = "lk-2", day = 5,
                offscreen = true }})
        ''')
        self.flush()
        died = self.ev('EVS("OnLivingKnoxMemberDied")')
        self.assertEqual(len(died), 2)  # m-3 (setUp) puis m-2
        d = died[2]
        self.assertEqual((d.member, d.npc, d.role, d.offscreen, d.cause, d.byPlayer, d.groupAlive, d.area.x),
                         ('m-2', 'lk-2', 'fighter', False, 'firearm', True, 1, 10650))
        dump = self.assert_clean('EV')
        for private in ('bob', 'Base.Pistol', 'body=', 'killer=', 'weapon=', 'witnesses='):
            self.assertNotIn(private, dump)
        # Un PNJ hors groupe n'est pas un membre : aucun événement.
        self.run_lua('LivingKnox.publish("npcDied", { npc = "lk-6", cause = "zombie", x = 1, y = 1, z = 0 })')
        self.flush()
        self.assertEqual(len(self.ev('EVS("OnLivingKnoxMemberDied")')), 2)

    def test_group_gone_by_death_departure_and_removal(self):
        self.flush()
        self.run_lua(f'''
            local G = LivingKnox.Groups
            assert(G.removeMember("{self.b}", "m-1", nil, "leave_group"))
            assert(G.markDead("{self.a}", "m-1")); assert(G.markDead("{self.a}", "m-2"))
        ''')
        self.flush()
        left = self.ev('EVS("OnLivingKnoxMemberLeft")')
        self.assertEqual([(e.group, e.member, e.npc, e.role, e.reason, e.groupAlive) for e in left.values()],
                         [(self.b, 'm-1', 'lk-5', 'scout', 'leave_group', 0)])
        gone = self.ev('EVS("OnLivingKnoxGroupGone")')
        # Ordre des faits : départ de b, puis morts de a (une seule disparition par groupe).
        self.assertEqual([(e.group, e.reason, e.total) for e in gone.values()],
                         [(self.b, 'left', 0), (self.a, 'dead', 3)])
        self.assertEqual(self.ev('#EVS("OnLivingKnoxMemberDied")'), 3)  # m-3 (setUp), m-1, m-2
        # Retrait d'un groupe déjà sans vivant : déjà annoncé, rien de plus ; retrait d'un groupe vivant : « removed ».
        self.run_lua(f'''
            local G = LivingKnox.Groups
            assert(G.remove("{self.a}"))
            local c = assert(G.create({{ type = 'neutrals', name = 'Drifters' }})).id
            assert(G.addMember(c, {{ role = 'worker' }}))
            assert(G.remove(c))
        ''')
        self.flush()
        gone = self.ev('EVS("OnLivingKnoxGroupGone")')
        self.assertEqual([(e.group, e.reason) for e in gone.values()][2:], [('grp-3', 'removed')])
        self.assertEqual(self.names().count('OnLivingKnoxGroupCreated'), 2)  # grp-3 retiré avant le pas : rien
        self.assert_clean('EV')

    def test_departure_reason_optional_and_dead_member_removal_ignored(self):
        self.flush()
        self.run_lua(f'''
            local G = LivingKnox.Groups
            G.update(function(d) G.applyLeave(d.groups["{self.a}"], "m-2", 6) return true end)
            assert(G.removeMember("{self.a}", "m-3"))   -- membre déjà mort : pas un départ
        ''')
        self.flush()
        left = self.ev('EVS("OnLivingKnoxMemberLeft")')
        self.assertEqual([(e.member, e.reason, e.groupAlive, e.day) for e in left.values()], [('m-2', None, 1, 6)])
        self.assertEqual(self.ev('#EVS("OnLivingKnoxGroupGone")'), 0)

    def test_need_critical_once_with_hysteresis(self):
        def set_need(key, v, gid=None):
            self.run_lua(f'assert(LivingKnox.Groups.setNeed("{gid or self.a}", "{key}", {v}))')

        def crit():
            return [(e.group, e.need, e.level, e.threshold) for e in self.ev('EVS("OnLivingKnoxNeedCritical")').values()]

        self.h.advance(10)  # premier sondage : relevé sans événement (food = 20 déjà critique)
        self.assertEqual(crit(), [])
        set_need('medical', 24)
        self.h.advance(10)
        self.assertEqual(crit(), [(self.a, 'medical', 24, 25)])
        for v in (30, 24, 39):  # sous NEED_OK : toujours critique, rien de plus
            set_need('medical', v)
            self.h.advance(10)
        self.assertEqual(len(crit()), 1)
        set_need('medical', 40)
        self.h.advance(10)
        set_need('medical', 10)
        self.h.advance(10)
        self.assertEqual(crit()[1:], [(self.a, 'medical', 10, 25)])
        # Groupe apparu après le premier sondage : jugé normalement ; groupe sans vivant : jamais.
        self.run_lua('''
            local G = LivingKnox.Groups
            local c = assert(G.create({ type = 'neutrals', name = 'Drifters', needs = { food = 5, medical = 50,
                ammo = 50 } })).id
            assert(G.addMember(c, { role = 'worker' }))
            local d = assert(G.create({ type = 'neutrals', name = 'Ghosts', needs = { food = 5, medical = 50,
                ammo = 50 } })).id
        ''')
        self.h.advance(10)
        self.assertEqual(crit()[2:], [('grp-3', 'food', 5, 25)])
        self.assert_clean('EV')

    def test_encounter_once_per_encounter(self):
        self.flush()
        for n in (1, 1, 2):
            self.run_lua(f'LivingKnox.publish("encounterStarted", {{ group = "{self.a}", npc = "lk-2", '
                         f'player = "A", level = "wary", n = {n} }})')
        self.run_lua('LivingKnox.publish("encounterStarted", { group = "grp-99", npc = "lk-2", player = "A", n = 3 })')
        self.flush()
        enc = self.ev('EVS("OnLivingKnoxEncounter")')
        self.assertEqual([(e.group, e.npc, e.player, e.level) for e in enc.values()],
                         [(self.a, 'lk-2', 'A', 'wary'), (self.a, 'lk-2', 'A', 'wary')])
        self.assert_clean('EV')

    def test_blocked_registry_drops_facts(self):
        self.run_lua('LivingKnox.Groups.state.blocked = true')
        self.flush()
        self.run_lua('LivingKnox.Groups.state.blocked = false')
        self.flush()
        self.assertEqual(self.names(), [])
        self.assertTrue(any('fact(s) dropped' in line for line in self.h.logs(self.srv)))

    def test_engine_publish_points_in_source(self):
        server = LUA / 'server' / 'LivingKnox'
        enc = (server / 'LK_Encounters.lua').read_text(encoding='utf-8')
        self.assertRegex(enc, r'if ev == "start" then\s+LivingKnox\.publish\("encounterStarted"')
        grp = (server / 'LK_Groups.lua').read_text(encoding='utf-8')
        for fact in ('groupCreated', 'memberLeft', 'groupRemoved', 'memberDied'):
            self.assertIn(f'LivingKnox.publish("{fact}"', grp)


class ThirdPartyEventTests(unittest.TestCase):
    """Un mod tiers s'abonne sans dépendance dure, chargé avant ou sans Living Knox."""

    def test_subscriber_loaded_before_or_without_living_knox(self):
        for with_lk in (True, False):
            with Harness(mode='mp') as h:
                h.load('server', WORLD)
                h.load('server', RECORDER)  # avant le moteur : déclare les noms lui-même
                if with_lk:
                    for path in SHARED + SERVER:
                        h.load('server', path)
                    h.fire('server', 'OnInitGlobalModData', False)
                    h.load('server', 'assert(LivingKnox.Groups.create({ type = "settlers", name = "Late" }))')
                h.fire('server', 'OnTickEvenPaused', 0.0)
                names = [r.name for r in h.eval('server', 'EV').values()]
                self.assertEqual(names, ['OnLivingKnoxGroupCreated'] if with_lk else [])
                self.assertEqual(h.errors('server'), [])


# LK10-T03 : groupe à graine d'histoire (résumés anglais et français composés, secrets privés), deux membres.
SEEDED = r'''
local G, S = LivingKnox.Groups, LivingKnox.Stories
SEEDED_STORY = assert(S.compose('settlers', 1234))
local c = assert(G.create({ type = 'settlers', name = 'Seeded', story = SEEDED_STORY.summary.en, storySeed = 1234,
    day = 2 })).id
G.addMember(c, { role = 'worker', npc = 'lk-8', day = 2 })
G.addMember(c, { role = 'medic', day = 2 })
return c
'''


class StoryEnrichTests(Base):
    """LK10-T03 : point d'enrichissement des histoires (texte d'un autre mod, borné, versionné, repli sur le gabarit)."""

    def setUp(self):
        super().setUp()
        self.c = self.run_lua(SEEDED)

    def call(self, code):
        res = self.run_lua('return ' + code)
        return res if isinstance(res, tuple) else (res, None)

    def story(self, lang='en', member=None):
        m = f', "{member}"' if member else ''
        res, why = self.call(f'LivingKnox.API.story("{self.c}", "{lang}"{m})')
        self.assertIsNotNone(res, why)
        return res

    def enrich(self, lang, text, opts=''):
        return self.call(f'LivingKnox.API.enrichStory("{self.c}", "{lang}", {text}{", " + opts if opts else ""})')

    def raw(self):
        return self.ev(f'DUMP(LivingKnox.Groups.state.data.groups["{self.c}"].enrich)')

    def test_template_without_any_text(self):
        for lang in ('en', 'fr', 'FR', 'de'):
            s = self.story(lang)
            want = 'fr' if lang.lower() == 'fr' else 'en'
            self.assertEqual(s.lang, want)
            self.assertEqual(s.text, self.ev(f'SEEDED_STORY.summary.{want}'))
            self.assertEqual((s.source, s.mode, s.template), ('template', None, s.text))
            self.assertTrue(s.version.startswith('t1-1234-'))
        # Groupe sans graine : le résumé du registre (anglais) dans les deux langues.
        self.assertEqual(self.ev(f'LivingKnox.API.story("{self.a}", "fr").text'), self.ev('STORY.summary.en'))
        self.assertEqual(self.ev(f'LivingKnox.API.story("{self.a}").version'), self.ev(
            f'LivingKnox.API.story("{self.a}", "fr").version'))
        self.assertEqual(self.raw(), 'nil')

    def test_replace_append_language_and_member_chain(self):
        tpl_en, tpl_fr = self.ev('SEEDED_STORY.summary.en'), self.ev('SEEDED_STORY.summary.fr')
        res, why = self.enrich('en', '"  The mill folk swear the river spoke to them.  "')
        self.assertIsNone(why)
        self.assertEqual((res.group, res.member, res.lang, res.mode, res.cleared), (self.c, None, 'en', 'replace',
                                                                                    False))
        self.assertEqual(self.story('en').text, 'The mill folk swear the river spoke to them.')  # blancs retirés
        self.assertEqual(self.story('en').source, 'group')
        self.assertEqual(self.story('fr').text, tpl_fr)                                         # autre langue
        res, _ = self.enrich('fr', '"Ils gardent la roue du moulin."', '{ mode = "append" }')
        self.assertEqual(self.story('fr').text, tpl_fr + '\nIls gardent la roue du moulin.')
        self.assertEqual((self.story('fr').mode, self.story('fr').template), ('append', tpl_fr))
        # Membre : sans texte propre, celui du groupe ; « append » complète celui du groupe.
        self.assertEqual(self.story('en', 'm-2').source, 'group')
        self.enrich('en', '"She kept the ledger."', '{ member = "m-2", mode = "append" }')
        s = self.story('en', 'm-2')
        self.assertEqual((s.text, s.source, s.member), ('The mill folk swear the river spoke to them.\nShe kept the '
                                                         'ledger.', 'member', 'm-2'))
        self.assertEqual(self.story('en', 'm-1').source, 'group')
        # Retrait : texte nil, retour au gabarit.
        res, _ = self.enrich('en', 'nil')
        self.assertTrue(res.cleared)
        self.assertEqual((self.story('en').text, self.story('en').source), (tpl_en, 'template'))
        self.assertEqual(self.story('en', 'm-2').text, tpl_en + '\nShe kept the ledger.')

    def test_bounds_and_refusals_change_nothing(self):
        self.run_lua('LivingKnox.Groups.flush()')   # LK13-T06 : écritures différées comptées après Groups.flush
        seq = self.ev('LivingKnox.Groups.state.seq')
        cases = [
            (('en', 'string.rep("a", 601)'), 'text too long'),
            (('en', 'string.rep("line\\n", 8) .. "ninth"'), 'too many lines'),
            (('en', '"tab\\there"'), 'bad character in text'),
            (('en', '"bell\\7"'), 'bad character in text'),
            (('en', '"<RGB:1,0,0>red"'), 'bad character in text'),
            (('en', '"  \\n  "'), 'empty text'),
            (('en', '42'), 'bad text'),
            (('de', '"Hallo"'), 'bad language'),
            (('en', '"x"', '{ mode = "prepend" }'), 'bad mode'),
            (('en', '"x"', '{ member = "m-9" }'), 'unknown member m-9'),
            (('en', '"x"', '{ member = "group" }'), 'unknown member group'),
            (('en', '"x"', '{ version = "t1-0-0" }'), 'stale version'),
            (('en', '"x"', '"replace"'), 'bad options'),
        ]
        for args, why in cases:
            self.assertEqual(self.enrich(*args), (None, why), args)
        self.assertEqual(self.call('LivingKnox.API.enrichStory("grp-99", "en", "x")'), (None, 'unknown group grp-99'))
        self.assertEqual(self.call(f'LivingKnox.API.story("{self.c}", "en", "m-9")'), (None, 'unknown member m-9'))
        self.assertEqual((self.ev('LivingKnox.Groups.state.seq'), self.raw()), (seq, 'nil'))
        # Bornes atteintes : acceptées (600 caractères, 8 lignes).
        self.assertFalse(self.ev('LivingKnox.Groups.isDirty()'))
        self.assertIsNone(self.enrich('en', 'string.rep("a", 600)')[1])
        self.run_lua('LivingKnox.Groups.flush()')
        self.assertIsNone(self.enrich('fr', 'string.rep("ligne\\n", 7) .. "fin"')[1])
        self.run_lua('LivingKnox.Groups.flush()')
        self.assertEqual(self.ev('LivingKnox.Groups.state.seq'), seq + 2)
        self.run_lua('LivingKnox.Groups.state.blocked = true')
        self.assertEqual(self.enrich('en', '"x"'), (None, 'group registry not ready'))
        self.assertEqual(self.call(f'LivingKnox.API.story("{self.c}")'), (None, 'group registry not ready'))

    def test_stale_template_falls_back_and_is_purged(self):
        version = self.story('en').version
        self.assertIsNone(self.enrich('en', '"Old tale."', f'{{ version = "{version}" }}')[1])
        self.assertIsNone(self.enrich('en', '"Ledger."', '{ member = "m-2" }')[1])
        self.assertEqual(self.story('en').text, 'Old tale.')
        # Gabarit changé (autre graine) : texte périmé, lecture du nouveau gabarit, refus de l'ancienne version.
        self.run_lua(f'LivingKnox.Groups.update(function(d) d.groups["{self.c}"].storySeed = 99 return true end)')
        s = self.story('en')
        self.assertEqual((s.source, s.text), ('template', self.ev('LivingKnox.Stories.compose("settlers", 99)'
                                                                   '.summary.en')))
        self.assertNotEqual(s.version, version)
        self.assertEqual(self.story('en', 'm-2').source, 'template')
        self.assertEqual(self.enrich('fr', '"Nouveau."', f'{{ version = "{version}" }}'), (None, 'stale version'))
        # Écriture suivante : les entrées périmées sont retirées.
        self.assertIsNone(self.enrich('fr', '"Nouveau."', f'{{ version = "{s.version}" }}')[1])
        self.assertNotIn('Old tale', self.raw())
        self.assertNotIn('Ledger', self.raw())
        self.assertIn('Nouveau', self.raw())
        # Membre retiré : son texte n'est plus lu, puis retiré.
        self.assertIsNone(self.enrich('fr', '"Soigne."', '{ member = "m-2" }')[1])
        self.run_lua(f'assert(LivingKnox.Groups.removeMember("{self.c}", "m-2"))')
        self.assertIsNone(self.enrich('fr', '"Encore."')[1])
        self.assertNotIn('Soigne', self.raw())

    def test_secrets_untouched_and_never_returned(self):
        secrets = [self.ev(f'SEEDED_STORY.secrets[{i}].{lang}') for i in (1, 2) for lang in ('en', 'fr')]
        self.enrich('en', '"A plain public tale."')
        self.enrich('en', '"Her part."', '{ member = "m-1" }')
        for lang in ('en', 'fr'):
            for member in (None, 'm-1'):
                m = f', "m-1"' if member else ''
                expr = f'LivingKnox.API.story("{self.c}", "{lang}"{m})'
                dump = self.assert_clean(expr)
                for s in secrets:
                    self.assertNotIn(s, dump)
        # Histoire recomposée : secrets identiques, aucun texte fourni dedans.
        again = self.ev('DUMP(LivingKnox.Stories.compose("settlers", 1234).secrets)')
        self.assertEqual(again, self.ev('DUMP(SEEDED_STORY.secrets)'))
        self.assertNotIn('public tale', again)
        # Registre : le texte fourni n'est rangé que sous enrich ; ni secret ni champ secrets.
        raw = self.raw()
        self.assertNotIn('secrets=', raw)
        for s in secrets:
            self.assertNotIn(s, raw)
        # Le résumé du registre et la vue publique du groupe sont inchangés (sens de summary gardé en version 1).
        self.assertEqual(self.ev(f'LivingKnox.API.getGroup("{self.c}").summary'), self.ev('SEEDED_STORY.summary.en'))
        self.assertNotIn('public tale', self.ev(f'DUMP(LivingKnox.API.publicGroup(LivingKnox.Groups.state.data'
                                                f'.groups["{self.c}"]))'))

    def test_persisted_and_malformed_entry_ignored(self):
        self.enrich('en', '"Kept across restarts."')
        self.enrich('fr', '"Partie du membre."', '{ member = "m-1", mode = "append" }')
        self.run_lua('local st = LivingKnox.Groups.state st.data = nil st.seq = 0 assert(LivingKnox.Groups.ensure())')
        self.assertEqual(self.story('en').text, 'Kept across restarts.')
        self.assertEqual(self.story('fr', 'm-1').source, 'member')
        # Entrée corrompue (édition manuelle) : ignorée, gabarit rendu, sans erreur.
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{self.c}"].enrich["group:en"].text = 5')
        self.assertEqual(self.story('en').source, 'template')
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{self.c}"].enrich["group:en"] = "junk"')
        self.assertEqual(self.story('en').source, 'template')
        self.assertEqual(self.h.errors(self.srv), [])

    def test_without_radiosurvivor_no_call_no_error(self):
        # Le banc ne charge aucun fichier de RadioSurvivor : le moteur seul lit le gabarit et n'écrit rien.
        self.assertIsNone(self.ev('RS_LivingKnox'))
        self.assertIsNone(self.ev('RS_NPCProvider'))
        self.h.advance(24 * 60)
        for _ in range(3):
            self.h.fire(self.srv, 'OnTickEvenPaused', 0.0)  # h.tick lancerait les OnTick d'autres modules
        for gid in (self.a, self.b, self.c):
            self.assertEqual(self.ev(f'DUMP(LivingKnox.Groups.state.data.groups["{gid}"].enrich)'), 'nil')
            self.assertEqual(self.ev(f'LivingKnox.API.story("{gid}").source'), 'template')
        self.assertEqual(self.h.errors(self.srv), [])
        src = API_FILE.read_text(encoding='utf-8')
        code = '\n'.join(re.sub(r'--.*$', '', line) for line in src.splitlines())
        for word in ('RadioSurvivor', r'\bRS_', 'Provider'):
            self.assertIsNone(re.search(word, code), word)


if __name__ == '__main__':
    unittest.main()
