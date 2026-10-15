"""Tests hors jeu des expéditions physiques des PNJ Living Knox et de leur retour (LK05-T05) :
server/LivingKnox/LK_Expeditions.lua, branché dans LK_Decisions.lua (règle duty -> « expedition », faim et soif au
retour), LK_Materialize.lua (corps retiré -> Expeditions.onReleased), LK_Simulation.lua (retour abstrait ->
Expeditions.resolveAbstract) et LK_Needs.lua (activité « travel »), et la suite en jeu lk.expedition
(dev/.../RST_LKExpedition.lua) : liste et forme.

    python RadioSurvivor/tests/test_lk_expeditions.py

Bancs :
- logique pure (classement des bâtiments selon les manques et la distance, foyers et bâtiments récents écartés ;
  cascade ; retour abstrait reproductible sans perte de membre) ;
- pile complète (groupe « deciders » de test_lk_routines.py dans la maison HOUSE, vrais LK_Homes et LK_Stock, caisse
  PANTRY de test_lk_meals.py, bâtiment visé n° 9 à 20 cases avec un comptoir garni) : solo (marche simulée) et
  serveur dédié + deux clients.
Doublures ajoutées, relevées dans le Java 42.21.0 : IsoMetaGrid.getCellData, IsoMetaCell.getBuildingsIntersecting
(J/iso/IsoMetaCell.java), BuildingDef getX/getY/getX2/getY2 (fin exclue), getRooms, getIDString, RoomDef getName,
getZ, getX/getY/getX2/getY2 (fin exclue, J/iso/RoomDef.java:210-252), ArrayList.new.
Elles NE PROUVENT PAS l'API réelle : seulement la logique (objet retiré une seule fois du conteneur visé, rangé au
foyer et dans la référence sans perte ni vol, rien de créé à l'écran, bascule hors écran sans perte de membre, mêmes
consignes chez deux clients). Le rendu, les chemins réels et l'envoi se vérifient en jeu (suite lk.expedition).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_meals import MEAL_DOUBLES, PANTRY  # noqa: E402
from test_lk_routines import RoutineStack  # noqa: E402

EX = 'LivingKnox.Expeditions'
D = 'LivingKnox.Decisions'
ST = 'LivingKnox.Stock'
ROOT = Path(__file__).resolve().parents[1]
MODULE = 'server/LivingKnox/LK_Expeditions.lua'
MODULE_FILE = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / MODULE
SUITE = 'shared/RST/suites/RST_LKExpedition.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

# Métagrille doublée : bâtiments META (bornes incluses, comme BUILDINGS) ; bâtiment visé n° 9 (cuisine) à 20 cases du
# foyer 110,110 avec un comptoir 134,107 garni ; instanceItem compté (aucun objet créé à l'écran).
EXP_DOUBLES = r'''
local H = HARNESS
if ArrayList == nil then ArrayList = {} end
if ArrayList.new == nil then ArrayList.new = function() return H.list() end end
local RoomDef = H.class('RoomDef')
function RoomDef:getName() return self.name end
function RoomDef:getZ() return self.z end
function RoomDef:getX() return self.x1 end
function RoomDef:getY() return self.y1 end
function RoomDef:getX2() return self.x2 + 1 end   -- fin exclue (RoomDef.CalculateBounds)
function RoomDef:getY2() return self.y2 + 1 end
local Rect = H.class('RoomRect')                     -- RoomDef.RoomRect (J/iso/RoomDef.java:482-496), fin exclue
function Rect:getX() return self.x end
function Rect:getY() return self.y end
function Rect:getX2() return self.x + self.w end
function Rect:getY2() return self.y + self.h end
function RoomDef:getRects()
    return H.list({ setmetatable({ x = self.x1, y = self.y1, w = self.x2 - self.x1 + 1, h = self.y2 - self.y1 + 1 },
        Rect) })
end
local MetaDef = H.class('BuildingDef')
function MetaDef:getIDString() return tostring(self.id) end
function MetaDef:getX() return self.x1 end
function MetaDef:getY() return self.y1 end
function MetaDef:getX2() return self.x2 + 1 end
function MetaDef:getY2() return self.y2 + 1 end
function MetaDef:getRooms() return self.roomList end
META = {}
function META_ADD(id, x1, y1, x2, y2, rooms)
    local list = H.list()
    for _, r in ipairs(rooms) do
        list:add(setmetatable({ name = r[1], x1 = r[2], y1 = r[3], x2 = r[4], y2 = r[5], z = r[6] or 0 }, RoomDef))
    end
    META[#META + 1] = setmetatable({ id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2, roomList = list }, MetaDef)
end
local Cell = H.class('IsoMetaCell')
function Cell:getBuildingsIntersecting(x, y, w, h, out)
    for _, b in ipairs(META) do
        if b.x1 < x + w and b.x2 >= x and b.y1 < y + h and b.y2 >= y then out:add(b) end
    end
end
local GRID = setmetatable({}, H.class('IsoMetaGrid'))
function GRID:getCellData(cx, cy) return setmetatable({}, Cell) end
local prevWorld = getWorld
getWorld = function()
    local w = prevWorld and prevWorld() or {}
    w.getMetaGrid = function() return GRID end
    return w
end
BUILDINGS[#BUILDINGS + 1] = { 130, 104, 137, 111, 9 }
META_ADD(7, 105, 105, 115, 115, { { "kitchen", 105, 105, 115, 115 } })
META_ADD(9, 130, 104, 137, 111, { { "livingroom", 130, 104, 132, 111 }, { "kitchen", 133, 104, 137, 111 } })
local Item = HARNESS.classes.InventoryItem
function Item:getFullType() return self.t end
TARGET_FOOD = { MEAL_ITEM('Base.TinnedBeans'), MEAL_ITEM('Base.CannedCorn'), MEAL_ITEM('Base.TinnedSoup') }
TARGET_WATER = { MEAL_ITEM('Base.WaterBottle'), MEAL_ITEM('Base.WaterBottle') }
TARGET_TOOL = MEAL_ITEM('Base.Hammer', { cat = 'ToolWeapon' })
COUNTER = MEAL_BOX(134, 107, 'counter', { TARGET_TOOL, TARGET_FOOD[1], TARGET_WATER[1], TARGET_FOOD[2],
    TARGET_FOOD[3], TARGET_WATER[2] })
INSTANCED = 0
local mk = instanceItem
local CATS = { ['Base.Bandage'] = 'FirstAid', ['Base.Pills'] = 'FirstAid', ['Base.Bullets9mmBox'] = 'Ammo',
    ['Base.ShotgunShellsBox'] = 'Ammo', ['Base.NailsBox'] = 'Material', ['Base.DuctTape'] = 'Material' }
instanceItem = function(t)
    INSTANCED = INSTANCED + 1
    if t == 'Base.WaterBottle' then
        local it = MEAL_ITEM(t)
        local fc = it.fc
        function fc.Empty(f) f.fluid, f.amount = nil, 0 end
        function fc.addFluid(f, fl, a) f.fluid, f.amount = fl, a end
        function fc.getCapacity() return 1 end
        return it
    end
    if CATS[t] ~= nil then return MEAL_ITEM(t, { cat = CATS[t] }) end
    if t == 'Base.TinnedBeans' or t == 'Base.CannedCorn' or t == 'Base.TinnedSoup' then return MEAL_ITEM(t) end
    return mk(t)
end
ADDED = {}
sendAddItemToContainer = function(c, it)
    if isServer() then ADDED[#ADDED + 1] = c.type .. ':' .. tostring(it.id) end
end
'''

# Membres : chef combattant, ouvrier, deux éclaireurs (poste forager quand l'objectif est « supply »).
CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false'), ('scout', 'runner', 'true'),
        ('scout', 'runner', 'false')]


class PureExpeditionTests(PureBase):
    def setUp(self):
        super().setUp()
        for path in ('server/LivingKnox/LK_Homes.lua', 'server/LivingKnox/LK_Stock.lua',
                     'server/LivingKnox/LK_Routines.lua', MODULE):
            self.h.load(self.srv, path)

    def test_rank_follows_the_wants_then_the_distance(self):
        code = (f'''local list = {{
            {{ id = "1", x1 = 120, y1 = 100, x2 = 125, y2 = 105, rooms = {{ {{ name = "bathroom", z = 0, x1 = 120,
                y1 = 100, x2 = 125, y2 = 105 }} }} }},
            {{ id = "2", x1 = 140, y1 = 100, x2 = 146, y2 = 106, rooms = {{ {{ name = "kitchen", z = 0, x1 = 140,
                y1 = 100, x2 = 146, y2 = 106 }} }} }},
            {{ id = "3", x1 = 104, y1 = 104, x2 = 116, y2 = 116, rooms = {{ {{ name = "kitchen", z = 0, x1 = 104,
                y1 = 104, x2 = 116, y2 = 116 }} }} }},
            {{ id = "4", x1 = 200, y1 = 100, x2 = 206, y2 = 106, rooms = {{ {{ name = "kitchen", z = 0, x1 = 200,
                y1 = 100, x2 = 206, y2 = 106 }} }} }},
            {{ id = "5", x1 = 118, y1 = 90, x2 = 122, y2 = 94, rooms = {{ {{ name = "kitchen", z = 1, x1 = 118,
                y1 = 90, x2 = 122, y2 = 94 }} }} }},
        }}
        local want = {{ {{ c = "food", m = 4 }}, {{ c = "medical", m = 1 }} }}
        local out = {{}}
        for _, c in ipairs({EX}.rank(list, {{ x = 110, y = 110, z = 0 }}, want, {{}}, {{ {{ x = 110, y = 110 }} }})) do
            out[#out + 1] = c.id .. ":" .. c.d .. ":" .. c.score .. ":" .. c.room.name
        end
        local med = {{}}
        for _, c in ipairs({EX}.rank(list, {{ x = 110, y = 110, z = 0 }}, {{ want[2], want[1] }}, {{ ["2"] = true }})) do
            med[#med + 1] = c.id
        end
        return table.concat(out, " "), table.concat(med, " ")''')
        ranked, medical = self.run_lua(code)
        # Cuisine (nourriture, 1er manque) à 30 cases : 20 - 15 ; salle de bain (soins, 2e) à 10 cases : 10 - 5 ;
        # à note égale, la plus proche. Foyer (3, contient le foyer) écarté ; 4 trop loin (90 cases) ; 5 sans pièce au
        # niveau du foyer.
        self.assertEqual(ranked, '1:10:5:bathroom 2:30:5:kitchen')
        self.assertEqual(medical, '1')                                    # récent (2) écarté, 3 hors foyer : 0 case
        self.assertEqual(self.ev(f'{EX}.roomScore("kitchen", {{ {{ c = "water", m = 1 }}, {{ c = "food", m = 1 }} }})'),
                         30)
        self.assertEqual(self.ev(f'{EX}.roomScore("garage", {{ {{ c = "food", m = 1 }} }})'), 0)

    def test_cascade_sends_the_team_on_its_trip(self):
        trip = 'trip = { n = 3, phase = "out" }, duty = "forager", objective = "supply"'
        self.assertEqual(self.decide(trip)[:2], ('duty', 'expedition'))
        self.assertEqual(self.decide('trip = { n = 3, phase = "back" }, duty = "keeper", atHome = false')[:2],
                         ('duty', 'expedition'))                          # poste changé : l'expédition continue
        self.assertEqual(self.decide(trip + ', meals = true, needs = { hunger = 90, thirst = 90, fatigue = 95 }')[:2],
                         ('duty', 'expedition'))                          # faim, soif et fatigue au retour
        self.assertEqual(self.decide(trip + ', needs = { fear = 90 }')[0], 'fear')
        self.assertEqual(self.decide(trip + ', threat = ZOMBIE(3)')[:2], ('threat', 'watch'))   # LK06-T07 : membre valide, il tient
        self.assertEqual(self.decide(trip + ', health = 0.3')[0], 'wound')
        self.assertEqual(self.decide('duty = "forager", objective = "supply"')[:2], ('duty', 'home'))
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.expedition.vigil'), 'guard')
        self.assertEqual(self.ev('LivingKnox.Needs and LivingKnox.Needs.BEHAVIOUR_ACTIVITY.expedition or "travel"'),
                         'travel')

    def test_abstract_return_never_loses_a_member_and_is_reproducible(self):
        code = f'''local function run(seed, find)
            {EX}.CFG.ABSTRACT_FIND = find
            local g = {{ members = {{ ["m-3"] = {{ alive = true, wound = 10 }}, ["m-4"] = {{ alive = true }},
                ["m-5"] = {{ alive = false }} }}, log = {{}},
                expedition = {{ place = "trip", team = {{ "m-3", "m-4", "m-5" }}, departed = 10, returns = 12, trip = 2 }},
                trips = {{ v = 1, n = 2, seen = {{}}, cur = {{ n = 2, phase = "away", from = "search",
                    team = {{ "m-3", "m-4", "m-5" }}, want = {{ {{ c = "water", m = 3 }}, {{ c = "food", m = 1 }} }},
                    target = {{ x = 1, y = 2, z = 0, b = "9" }}, start = 0, due = 9, cap = 3,
                    carry = {{ {{ t = "Base.Pills", c = "medical", i = 7 }} }}, searched = {{}} }} }} }}
            local r = {EX}.resolveAbstract(g, "grp-1", 12, {D}.stream("abstract", seed, 5), 1)
            local parts = {{}}
            for _, e in ipairs(g.trips.cur.carry) do parts[#parts + 1] = e.t .. (e.a and "*" or "") end
            return {{ r.back, r.found, g.trips.cur.phase, tostring(g.expedition == nil), table.concat(parts, " "),
                tostring(g.members["m-3"].alive) .. tostring(g.members["m-4"].alive) .. g.members["m-3"].wound,
                g.log[#g.log].kind }}
        end
        local a = run(4, 0.5)
        local b = run(4, 0.5)
        local full = run(4, 1)
        {EX}.CFG.ABSTRACT_FIND = 0.5
        return table.concat(a, "|") == table.concat(b, "|"), full[1], full[2], full[3], full[4] == "true", full[5],
            full[6], full[7], a[2] <= 2'''
        same, back, found, phase, cleared, carry, alive, kind, bounded = self.run_lua(code)
        self.assertTrue(same)                                             # même flux : même butin
        self.assertEqual((back, found, phase, cleared), (2, 2, 'deliver', True))   # charge 3 : 1 porté + 2
        self.assertEqual(carry, 'Base.Pills Base.WaterBottle* Base.WaterBottle*')
        self.assertEqual(alive, 'truetrue10')                             # ni mort ni blessure
        self.assertEqual(kind, 'trip')
        self.assertTrue(bounded)

    def test_module_source_is_kahlua_safe(self):
        raw = MODULE_FILE.read_bytes().decode('utf-8')
        code = re.sub(r'--[^\n]*', '', raw)
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character outside comments')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'[^.]\.\.\.[^.]', r'<<|>>'):
            self.assertIsNone(re.search(pattern, code), pattern)


class ExpeditionStack(RoutineStack):
    """Pile complète + LK_Homes, LK_Stock, LK_Expeditions, caisse PANTRY au foyer et bâtiment visé n° 9."""

    CREW = CREW

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            for path in ('server/LivingKnox/LK_Homes.lua', 'server/LivingKnox/LK_Stock.lua', MODULE):
                h.load(m, path)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, MEAL_DOUBLES)
        h.load(srv, PANTRY)
        h.load(srv, EXP_DOUBLES)
        return h

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) assert(LivingKnox.Homes.skip(g.id)) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        if self.mode == 'mp':
            self.h.move_player('B', 101, 112)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() LivingKnox.Routines.reset() {EX}.reset() INSTANCED = 0')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual(r.action, 'filled')
        self.jump_to(9)
        return gid

    def trip(self, gid):
        return self.ev(f'{EX}.get("{gid}")')

    def phase(self, gid):
        t = self.trip(gid)
        return t.phase if t is not None else None

    def run_until(self, cond, seconds=200, walk=1.0):
        for _ in range(seconds):
            self.dpass(1, walk=walk)
            self.h.advance(1)
            if cond():
                return True
        return False

    def ids(self, expr):
        return sorted(lua_list(self.ev(expr)))

    def journal(self, gid, kind):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == kind]


class SoloExpeditionTests(ExpeditionStack):
    mode = 'solo'

    def test_foragers_leave_for_the_kitchen_that_matches_the_wants(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        t = self.trip(gid)
        self.assertEqual(lua_list(t.team), ['m-3', 'm-4'])               # éclaireurs, ni le chef ni l'ouvrier
        self.assertEqual((t.target.b, t.target.room, t.target.x, t.target.y), ('9', 'kitchen', 135, 107))
        wants = [(w.c, w.m) for w in lua_list(t.want)]
        self.assertEqual([c for c, _ in wants], ['ammo', 'materials', 'water', 'medical', 'food'])
        self.assertEqual(t.cap, 8)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").objective'), 'supply')
        self.dpass(1)
        self.assertEqual(self.b(gid, 'm-3'), 'expedition')
        self.assertEqual(self.b(gid, 'm-1'), 'guard')
        exp = self.journal(gid, 'expedition')
        self.assertEqual(len(exp), 1)
        self.assertTrue(exp[0].startswith('trip 1 to kitchen 135,107 (20 squares): m-3 m-4 for ammo 2'), exp)
        self.assertEqual(self.run_lua(f'return {EX}.tryDepart("{gid}", {D}.currentMinute())'),
                         (None, 'expedition under way'))                  # une à la fois
        self.assertEqual(self.h.errors('solo'), [])

    def test_need_blocker_keeps_home_a_member_the_trip_does_not_help(self):
        # LK05-T15 (décision du 2026-10-12) : besoin élevé = écarté, sauf faim si la nourriture est cherchée et soif si
        # l'eau l'est ; fatigue et peur écartent toujours.
        food = '{ { c = "food", m = 2 } }'
        ammo = '{ { c = "ammo", m = 2 } }'
        water = '{ { c = "water", m = 1 } }'
        self.assertIsNone(self.ev(f'{EX}.needBlocker({{ hunger = 95 }}, {food})'))
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ hunger = 95 }}, {ammo})'), 'hunger 95')
        self.assertIsNone(self.ev(f'{EX}.needBlocker({{ thirst = 80 }}, {water})'))
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ thirst = 80 }}, {food})'), 'thirst 80')
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ fatigue = 85 }}, {food})'), 'fatigue 85')
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ fear = 70 }}, {food})'), 'fear 70')
        self.assertIsNone(self.ev(f'{EX}.needBlocker({{ hunger = 69, fatigue = 79 }}, {ammo})'))

    def test_tired_forager_stays_home_hungry_one_leaves_for_food(self):
        gid = self.mk()
        # m-3 épuisé : écarté ; m-4 affamé : part, car la nourriture fait partie des manques.
        self.run_lua(f'''local orig = {D}.needsOf
            {D}.needsOf = function(g, mid)
                local n = orig(g, mid)
                if mid == "m-3" then n.fatigue = 95 end
                if mid == "m-4" then n.hunger = 95 end
                return n
            end''')
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        self.assertEqual(lua_list(self.trip(gid).team), ['m-4'])

    def test_trip_takes_real_items_once_brings_them_home_and_keeps_the_stock_honest(self):
        gid = self.mk()
        counter = self.ids('BOX_IDS(COUNTER)')
        pantry = self.ids('BOX_IDS(PANTRY)')
        wanted = self.ids('(function() local o = {} for _, it in ipairs(TARGET_FOOD) do o[#o + 1] = it.id end '
                          'for _, it in ipairs(TARGET_WATER) do o[#o + 1] = it.id end return o end)()')
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'search', seconds=80), self.phase(gid))
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'back', seconds=60), self.phase(gid))
        self.assertEqual(self.ids('BOX_IDS(COUNTER)'), [self.ev('TARGET_TOOL.id')])   # outil laissé
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 5)                 # cinq objets retirés une fois
        t = self.trip(gid)
        self.assertEqual(sorted(e.i for e in lua_list(t.carry)), wanted)
        self.assertEqual(lua_list(t.searched), ['134,107,0,counter,1'])
        self.assertEqual(self.ev(f'{EX}.carriedCount("{gid}", 1)'), 5)
        self.assertTrue(self.run_until(lambda: self.trip(gid) is None, seconds=80), self.phase(gid))
        # Rangés au foyer : même objets (identifiants), référence à jour, rien de créé, ni perte ni vol.
        self.assertEqual(self.ids('BOX_IDS(PANTRY)'), sorted(pantry + wanted))
        ref = self.ids(f'REF_IDS("{gid}")')
        for i in wanted:
            self.assertIn(i, ref)
        self.assertEqual(self.ev('INSTANCED'), 0)
        self.assertEqual(len(counter) + len(pantry), len(self.ids('BOX_IDS(COUNTER)')) + len(self.ids('BOX_IDS(PANTRY)')))
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        back = self.journal(gid, 'return')
        self.assertEqual(back, ['trip 1 back from kitchen 135,107: 2 back, food +3 water +2'])
        s = self.ev(f'LivingKnox.Groups.get("{gid}").trips')
        self.assertEqual((s.n, lua_list(s.seen)), (1, ['9']))
        # Délai de repos : pas de nouveau départ tout de suite ; le bâtiment fouillé est écarté.
        self.assertTrue(self.ev(f'{EX}.departBlocker(LivingKnox.Groups.get("{gid}"), {D}.currentMinute())')
                        .startswith('rested less than'))
        self.dpass(2)
        for m in ('m-3', 'm-4'):
            self.assertNotEqual(self.b(gid, m), 'expedition')
        self.assertEqual(self.h.errors('solo'), [])

    def test_threat_on_the_way_interrupts_then_the_trip_resumes(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        for _ in range(4):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        npc = self.npc_of(gid, 'm-3')
        x, y = self.body_xy(gid, 'm-3')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 961)')
        self.dpass(2)
        self.assertIn(self.b(gid, 'm-3'), ('flee', 'watch'))
        self.assertEqual(self.phase(gid), 'out')
        self.run_lua('PERCEPTION = {}')
        self.assertTrue(self.run_until(lambda: self.b(gid, 'm-3') == 'expedition', seconds=20))
        self.assertTrue(self.run_until(lambda: self.trip(gid) is None, seconds=240), self.phase(gid))
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 5)
        self.assertEqual(self.h.errors('solo'), [])

    def test_bodies_released_far_from_players_go_offscreen_without_losing_anyone(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        self.run_lua('LivingKnox.Simulation.onEveryHours()')              # heure simulée de départ
        self.h.move_player('A', 400, 400)
        for m in ('m-3', 'm-4'):
            npc = self.npc_of(gid, m)
            self.assertTrue(self.run_lua(f'return LivingKnox.Bodies.release("{npc}", "test")'))
        t = self.trip(gid)
        self.assertEqual((t.phase, t['from'], lua_list(t.team)), ('away', 'out', ['m-3', 'm-4']))
        e = self.ev(f'LivingKnox.Groups.get("{gid}").expedition')
        self.assertEqual((e.place, e.trip, lua_list(e.team), e.returns - e.departed), ('trip', 1, ['m-3', 'm-4'], 3))
        self.assertEqual(self.journal(gid, 'trip'), ['trip 1 offscreen (out): m-3 m-4, back in 3 h'])
        # Joueur revenu au foyer : les absents ne sont pas matérialisés.
        self.h.move_player('A', 100, 100)
        self.passes(4)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2'])
        self.h.advance(4 * 60)
        self.run_lua('LivingKnox.Simulation.onEveryHours()')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        for _ in range(3):
            self.h.advance(1)
        self.assertIsNone(self.trip(gid))
        g = self.ev(f'LivingKnox.Groups.get("{gid}")')
        self.assertTrue(all(m.alive for m in g.members.values()))           # aucune perte
        back = self.journal(gid, 'return')
        self.assertEqual(len(back), 1)
        found = self.ev('INSTANCED')
        self.assertTrue(back[0].startswith('trip 1 back from kitchen 135,107: 2 back'), back)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)                 # rien pris au comptoir hors écran
        self.assertEqual(len(self.ids('BOX_IDS(PANTRY)')), 9 + found)      # butin abstrait rangé au foyer
        self.assertEqual(len(self.ids(f'REF_IDS("{gid}")')), 8 + found)   # 8 objets classés avant
        # Matérialisation reprise : les membres revenus reçoivent un corps près du foyer.
        for _ in range(8):
            self.passes(1)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3', 'm-4'])
        self.assertEqual(self.h.errors('solo'), [])

    def test_a_never_opened_container_gets_its_vanilla_loot_first(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        self.run_lua(r'''
            FILLS = 0
            local c = COUNTER.container
            c.explored = false
            function c.isExplored(self) return self.explored end
            function c.setExplored(self, v) self.explored = v end
            ItemPickerJava = { fillContainer = function(ct, player)
                assert(player == nil)
                FILLS = FILLS + 1
                LOOT = MEAL_ITEM('Base.Bandage', { cat = 'FirstAid' })
                ct:AddItem(LOOT)
            end }''')
        took = self.run_lua(f'local t = {EX}.get("{gid}") local f = {EX}.siteContainers("{gid}", t)[1] '
                            f'return {EX}.searchContainer("{gid}", t.n, f, "lk-x", "m-3"), f.key')
        self.assertEqual(took, (6, '134,107,0,counter,1'))                 # 3 vivres, 2 eaux, le pansement tiré
        self.assertEqual(self.ev('FILLS'), 1)
        self.assertTrue(self.ev('COUNTER.container.explored'))
        self.assertIn(self.ev('LOOT.id'), [e.i for e in lua_list(self.trip(gid).carry)])
        self.assertEqual(self.ids('BOX_IDS(COUNTER)'), [self.ev('TARGET_TOOL.id')])
        self.assertEqual(self.h.errors('solo'), [])

    def test_one_member_released_while_the_other_is_seen_only_leaves_the_team(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        npc = self.npc_of(gid, 'm-4')
        self.assertTrue(self.run_lua(f'return LivingKnox.Bodies.release("{npc}", "test")'))
        t = self.trip(gid)
        self.assertEqual((t.phase, lua_list(t.team)), ('out', ['m-3']))
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerExpeditionTests(ExpeditionStack):
    """Serveur dédié + deux clients : départ et retour décidés par le serveur, mêmes consignes chez A et B, objets
    retirés et rangés par le serveur (envoyés une fois), aucune expédition chez un client."""

    mode = 'mp'

    def view(self, gid, mid):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        npc = self.npc_of(gid, mid)
        for c in ('A', 'B'):
            out[c] = self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                    'return e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. "@" '
                                    '.. tostring(e.a) .. ":" .. tostring(e.v)) or "none" end)()')
        return out

    def settle(self, gid, mids):
        """Banc MP : corps tenus par le serveur ; arrivée posée à la case visée, regard rapporté fini."""
        for mid in mids:
            self.run_lua(f'local npc = MEMBER_NPC("{gid}", "{mid}") local e = LivingKnox.Directives.entries[npc] '
                         'if e and not e.done then if e.op == "move" then '
                         f'HARNESS.place(MAT_BODY("{gid}", "{mid}"), e.x + 0.5, e.y + 0.5, e.z) end '
                         'if e.op == "face" then e.done, e.s = true, "faced" LivingKnox.Directives.sync(npc, true) '
                         'end end')

    def test_both_clients_see_the_same_departure_and_return(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Expeditions'))
        seen = []
        for _ in range(240):
            self.settle(gid, ('m-3', 'm-4'))
            self.dpass(1)
            self.h.advance(1)
            for mid in ('m-3', 'm-4'):
                v = self.view(gid, mid)
                self.assertEqual(v['A'], v['B'])
                seen.append((mid, self.phase(gid), v['A']))
            if self.journal(gid, 'return'):
                break
        self.assertEqual(self.journal(gid, 'return'), ['trip 1 back from kitchen 135,107: 2 back, food +3 water +2'])
        outs = [s for s in seen if s[1] == 'out' and s[2].startswith('move:')]
        self.assertTrue(outs, seen[:6])
        self.assertTrue(any(s[2].startswith('move:13') for s in outs), outs[:4])   # vers le bâtiment visé
        self.assertTrue(any(s[1] == 'back' and s[2].startswith('move:1') for s in seen), seen[-6:])
        food = sorted([self.ev(f'TARGET_FOOD[{i}].id') for i in (1, 2, 3)] + [self.ev(f'TARGET_WATER[{i}].id')
                                                                            for i in (1, 2)])
        sent = sorted(int(s.split(':')[1]) for s in lua_list(self.ev('MEAL_SENT')))
        self.assertEqual(sent, food)                                        # une suppression envoyée par objet
        added = sorted(int(s.split(':')[1]) for s in lua_list(self.ev('ADDED')))
        self.assertEqual(added, food)                                       # un ajout envoyé par objet
        self.assertEqual(self.ev('INSTANCED'), 0)
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteRunTests(ExpeditionStack):
    mode = 'solo'

    def test_suite_lk_expedition_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.expedition", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.expedition')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.expedition", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(12000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 10 == 9:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKX' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKX] measure departure: trip 1 to building 9 ', '[LKX] measure reached: ',
                     '[LKX] measure searched: 5 item(s) carried', '[LKX] measure home: 5 of 5 carried item(s)'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 5)
        self.assertEqual(self.h.errors('solo'), [])


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.expedition"', code)
        self.assertIn('"world"', code)


if __name__ == '__main__':
    unittest.main(verbosity=1)
