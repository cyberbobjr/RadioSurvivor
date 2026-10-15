"""Tests hors jeu de la pose des barricades par les PNJ Living Knox (LK14-T03) : server/LivingKnox/LK_Fortify.lua
(Fortify.run, nailPlank, openingOf, release), branché dans LK_Routines.lua (comportement « chore » d'un membre de poste
« builder »), matériaux pris par LK_Stock.lua (findItem, takeItem, check), et la suite en jeu lk.barricade
(dev/.../RST_LKBarricade.lua).

    python RadioSurvivor/tests/test_lk_barricade.py

Banc : pile complète des repas (groupe « deciders » de test_lk_routines.py dans la maison HOUSE 105..115, vrais
LK_Homes et LK_Stock, foyer marqué aménagé sans pose par LivingKnox.Homes.skip), ouvrier m-2 mis au poste « builder »
par une enveloppe de Decisions.assignDuties ; solo (marche simulée) et serveur dédié + deux clients.
Doublures ajoutées, relevées dans le Java et le Lua vanilla 42.21.0 :
- BuildingDef getX/getY (début), getX2/getY2 (fin exclusive), getMaxLevel (J/iso/BuildingDef.java:82-100) ;
- ouvertures posées sur la case dont elles sont le bord nord ou ouest : IsoWindow, IsoDoor (getNorth, IsOpen,
  isBarricadeAllowed, getBarricadeOnSameSquare / OnOppositeSquare, getOppositeSquare : BarricadeAble) ;
- IsoBarricade.AddBarricadeToObject(obj, addOpposite) (barricade existante rendue, sinon créée sur la case de l'objet
  ou la case opposée : IsoBarricade.java:739-764), addPlank(chr, plank) (4 au plus, état de la planche, :90-108),
  getNumPlanks, isMetal, isMetalBar ; transmitCompleteItemToClients et sendObjectChange(IsoObjectChange.STATE) comptés
  sur le serveur seulement (IsoObject.java:4265-4272, 4314-4322) ; buildUtil.setHaveConstruction ;
- objets : getFullType, hasTag(ItemTag.HAMMER) ; ItemContainer.AddItems(type, n) (ItemContainer.java:372-380) et
  sendAddItemsToContainer (LuaManager.java:9713, serveur seulement).
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (une planche et un clou retirés par planche
posée, référence du stock à jour sans perte ni vol, boîte de clous ouverte une fois, entrée jamais barricadée, rien
fait si le travail est interrompu, transmissions faites par le serveur seul, mêmes gestes chez deux clients).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_meals import MealStack  # noqa: E402

F = 'LivingKnox.Fortify'
R = 'LivingKnox.Routines'
ST = 'LivingKnox.Stock'
ROOT = Path(__file__).resolve().parents[1]
FORTIFY = 'server/LivingKnox/LK_Fortify.lua'
SUITE = 'shared/RST/suites/RST_LKBarricade.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

BARRICADE_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
if rawget(Sq, 'isWaterSquare') == nil then function Sq:isWaterSquare() return self.water == true end end
-- Rectangle du bâtiment (BUILDINGS de test_lk_materialize.py : x1, y1, x2, y2 inclus, id).
local Def = C.BuildingDef
local function rect(id)
    for _, b in ipairs(BUILDINGS) do if tostring(b[5]) == tostring(id) then return b end end
    error('unknown building ' .. tostring(id), 3)
end
function Def:getX() return rect(self.id)[1] end
function Def:getY() return rect(self.id)[2] end
function Def:getX2() return rect(self.id)[3] + 1 end
function Def:getY2() return rect(self.id)[4] + 1 end
function Def:getMaxLevel() return 0 end
-- Barricades.
IsoObjectChange = IsoObjectChange or { STATE = 'STATE' }
BAR = { made = 0, sent = 0, changes = 0, construction = 0 }
BAR_SENT = {}
local Bar = C.IsoBarricade or H.class('IsoBarricade', C.IsoObject)
IsoBarricade = Bar
function Bar:getSprite() return nil end
function Bar:getNumPlanks() return #self.planks end
function Bar:isMetal() return self.metal == true end
function Bar:isMetalBar() return false end
function Bar:getThumpCondition()   -- LK14-T06 : planche extérieure (état / 10, IsoBarricade.java:536-549)
    local n = #self.planks
    if n == 0 then return 0 end
    return math.min(self.planks[n] / 10, 1)
end
function Bar:addPlank(chr, plank)
    if chr ~= nil then error('unexpected character', 2) end
    if self.metal or #self.planks >= 4 then return end
    self.planks[#self.planks + 1] = plank ~= nil and (plank.cond or 10) or 10
end
function Bar:transmitCompleteItemToClients()
    if isServer() then
        BAR.sent = BAR.sent + 1
        BAR_SENT[#BAR_SENT + 1] = 'new ' .. self.key .. ' ' .. #self.planks
    end
end
function Bar:sendObjectChange(change)
    if change ~= IsoObjectChange.STATE then error('No implementation found for sendObjectChange', 2) end
    if isServer() then
        BAR.changes = BAR.changes + 1
        BAR_SENT[#BAR_SENT + 1] = 'state ' .. self.key .. ' ' .. #self.planks
    end
end
function Bar.AddBarricadeToObject(o, addOpposite)
    if type(addOpposite) ~= 'boolean' then error('No implementation found for AddBarricadeToObject', 2) end
    local field = addOpposite and 'opp' or 'own'
    if o[field] ~= nil then return o[field] end
    local sq = addOpposite and o:getOppositeSquare() or o:getSquare()
    if sq == nil then return nil end
    local b = setmetatable({ planks = {}, key = o.key .. (addOpposite and ':opp' or ':own') }, Bar)
    H.addObject(sq.x, sq.y, sq.z, b)
    o[field] = b
    BAR.made = BAR.made + 1
    return b
end
buildUtil = { setHaveConstruction = function(sq, b)
    if sq == nil or b ~= true then error('bad setHaveConstruction', 2) end
    BAR.construction = BAR.construction + 1
end }
-- Ouvertures : fenêtres et portes posées sur la case dont elles sont le bord nord (north) ou ouest.
local function edgeClass(name)
    local cls = C[name] or H.class(name, C.IsoObject)
    function cls:getSprite() return nil end
    function cls:getNorth() return self.north == true end
    function cls:isBarricadeAllowed() return self.allowed ~= false end
    function cls:getBarricadeOnSameSquare() return self.own end
    function cls:getBarricadeOnOppositeSquare() return self.opp end
    function cls:getOppositeSquare()
        if self.north then return H.square(self.x, self.y - 1, self.z) end
        return H.square(self.x - 1, self.y, self.z)
    end
    function cls:IsOpen() return self.open == true end
    return cls
end
local OPEN_CLS = { window = edgeClass('IsoWindow'), door = edgeClass('IsoDoor') }
function OPENING(kind, x, y, north, fields)
    local o = setmetatable(fields or {}, OPEN_CLS[kind])
    o.north, o.key = north, kind .. ' ' .. x .. ',' .. y .. (north and 'N' or 'W')
    H.addObject(x, y, 0, o)
    return o
end
-- Objets de chantier : planches, clous, boîte de clous, marteau.
local Item = C.InventoryItem
if rawget(Item, 'getFullType') == nil then function Item:getFullType() return self.t end end
ItemTag = ItemTag or {}
ItemTag.HAMMER = ItemTag.HAMMER or { name = 'base:hammer' }
function Item:hasTag(tag)
    if type(tag) ~= 'table' or tag.name == nil then error('No implementation found for hasTag', 2) end
    return self.tags ~= nil and self.tags[tag.name] == true
end
local CAT = { ['Base.Plank'] = 'MaterialWeapon', ['Base.Nails'] = 'Material', ['Base.NailsBox'] = 'Material',
    ['Base.Hammer'] = 'ToolWeapon' }
function BAR_ITEM(t, cond)
    MEAL_NEXT = MEAL_NEXT + 3
    local it = setmetatable({ id = MEAL_NEXT, t = t, cat = CAT[t] or 'Material', cond = cond }, Item)
    if t == 'Base.Hammer' then it.tags = { ['base:hammer'] = true } end
    return it
end
local Ctr = C.ItemContainer
function Ctr:AddItems(t, n)
    if type(t) ~= 'string' or type(n) ~= 'number' then error('No implementation found for AddItems', 2) end
    local list = H.list()
    for _ = 1, n do
        local it = BAR_ITEM(t)
        self.items:add(it)
        list:add(it)
    end
    return list
end
BAR.addedSent = 0
sendAddItemsToContainer = function(c, list)
    if getmetatable(c) ~= Ctr or type(list) ~= 'table' then error('No implementation found for sendAddItemsToContainer', 2) end
    if isServer() then BAR.addedSent = BAR.addedSent + list:size() end
end
-- Nombre d'objets d'un type dans la caisse.
function COUNT(box, t)
    local n = 0
    for _, it in ipairs(box.container.items.items) do if it.t == t then n = n + 1 end end
    return n
end
-- Ouvrier : le membre mid est mis au poste "builder" le jour (enveloppe de l'attribution des postes).
BUILDERS = {}
local D = LivingKnox.Decisions
local assign = D.assignDuties
D.assignDuties = function(members, objective, night, rotation)
    local out = assign(members, objective, night, rotation)
    for mid in pairs(BUILDERS) do
        if out[mid] ~= nil and not night then out[mid] = 'builder' end
    end
    return out
end
'''

# Maison HOUSE (105..115, foyer 110,110) : fenêtre nord (112,105) portée par la case intérieure, fenêtre ouest
# (105,110) portée par la case intérieure, porte sud (110,116) portée par la case extérieure = entrée du foyer.
# Caisse de la cuisine (112,112) : 8 planches (état 10 et 5), une boîte de clous, un marteau.
WORKSHOP = r'''
WIN_N = OPENING('window', 112, 105, true)
WIN_W = OPENING('window', 105, 110, false)
ENTRY = OPENING('door', 110, 116, true)
HAMMER_IT = BAR_ITEM('Base.Hammer')
PANTRY.container:AddItem(HAMMER_IT)
for i = 1, 8 do PANTRY.container:AddItem(BAR_ITEM('Base.Plank', i == 1 and 5 or 10)) end
BOX = BAR_ITEM('Base.NailsBox')
PANTRY.container:AddItem(BOX)
'''


class BarricadeStack(MealStack):
    """Pile des repas + LK_Fortify et ses doublures ; caisse garnie de planches, d'une boîte de clous et d'un marteau."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            h.load(m, FORTIFY)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, BARRICADE_DOUBLES)
        h.load(srv, WORKSHOP)
        return h

    def mk(self, builder=True):
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end')
        gid = super().mk()
        self.run_lua(f'{F}.reset() for k in pairs({F}.stats) do {F}.stats[k] = 0 end')
        if builder:
            self.run_lua('BUILDERS["m-2"] = true')
        return gid

    def stat(self, name):
        return self.ev(f'{F}.stats.{name}')

    def planks(self, var):
        return self.run_lua(f'local o = {var} local a = o.own and #o.own.planks or 0 local b = o.opp and #o.opp.planks '
                            'or 0 return a, b')

    def count(self, t):
        return self.ev(f'COUNT(PANTRY, "{t}")')

    def holder(self, phase=None):
        cond = f' and m.phase == "{phase}"' if phase else ''
        return self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "fortify"{cond} then return id end '
                            'end return nil')

    def work(self, cond, seconds=200):
        return self.run_until(cond, seconds=seconds, walk=1.0)


class PureBarricadeTests(BarricadeStack):
    mode = 'solo'

    def test_gesture_is_an_existing_generated_node_reset_by_leave(self):
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        g = self.ev(f'{F}.CFG.GESTURE')
        self.assertIn(g, table['gestures'])
        self.assertTrue(any(['LKGesture', 'STRING', g] in n['conditions'] for n in table['nodes']), g)
        self.assertTrue(self.ev(f'{R}.GESTURES["{g}"]'))                     # remis debout par Routines.leave

    def test_plan_sees_the_two_windows_and_keeps_the_entry_free(self):
        gid = self.mk()
        plan = self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        ids = [s.id for s in plan.sites.values() if s.tier == 'ground']
        self.assertEqual(ids, ['barricade:112,105,0N', 'barricade:105,110,0W'])
        self.assertEqual((plan.entry.x, plan.entry.y, plan.entry.north), (110, 116, True))
        self.assertEqual(self.h.errors('solo'), [])


class SoloBarricadeTests(BarricadeStack):
    mode = 'solo'

    def test_builder_barricades_both_windows_with_the_exact_stock(self):
        gid = self.mk()
        avail0 = self.ev(f'{F}.available("{gid}")')
        self.assertEqual((avail0['Base.Plank'], avail0['Base.Nails']), (8, 100))
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('finished') >= 2), (self.stat('planks'), self.lk()[-10:]))
        # Barricades posées dehors (côté prévu par le plan), 4 planches chacune ; la planche abîmée (état 5) gardée.
        self.assertEqual(self.planks('WIN_N'), (0, 4))                          # objet sur la case intérieure
        self.assertEqual(self.planks('WIN_W'), (0, 4))
        conds = sorted(self.run_lua('local out = {} for _, o in ipairs({ WIN_N.opp, WIN_W.opp }) do '
                                    'for _, c in ipairs(o.planks) do out[#out + 1] = c end end return out').values())
        self.assertEqual(conds, [5] + [10] * 7)
        self.assertEqual(self.planks('ENTRY'), (0, 0))                          # entrée praticable
        # Stock : 8 planches et 8 clous retirés, boîte ouverte une fois (100 clous), marteau gardé.
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 92, 0))
        self.assertTrue(self.ev('PANTRY.container:containsID(HAMMER_IT.id)'))
        self.assertEqual((self.stat('planks'), self.stat('boxes'), self.stat('started')), (8, 1, 2))
        avail = self.ev(f'{F}.available("{gid}")')
        self.assertEqual((avail['Base.Plank'] if 'Base.Plank' in avail.keys() else 0, avail['Base.Nails']), (0, 92))
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        # Solo : aucune transmission ; drapeau de construction posé par planche.
        self.assertEqual((self.ev('BAR.sent'), self.ev('BAR.changes'), self.ev('BAR.made')), (0, 0, 2))
        self.assertEqual(self.ev('BAR.construction'), 8)
        # Niveau du foyer : les deux ouvertures du rez-de-chaussée sont faites.
        plan = self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        self.assertTrue(all(s.done for s in plan.sites.values() if s.tier == 'ground'))
        # Plus rien de faisable : plus aucune planche posée.
        for _ in range(30):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        self.assertEqual(self.stat('planks'), 8)
        self.assertEqual(self.h.errors('solo'), [])

    def test_material_counts_limit_the_work(self):
        gid = self.mk()
        # 5 planches : la première fenêtre seulement (le second chantier en demande 4).
        self.run_lua('local n = 0 for _, it in ipairs(PANTRY.container.items.items) do '
                     'if it.t == "Base.Plank" and n < 3 then n = n + 1 TAKE_OUT = TAKE_OUT or {} '
                     'TAKE_OUT[#TAKE_OUT + 1] = it end end for _, it in ipairs(TAKE_OUT) do '
                     'HARNESS.listRemove(PANTRY.container.items, it) end')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('finished') >= 1))
        for _ in range(40):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        self.assertEqual(self.stat('planks'), 4)
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 0)))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (1, 96))
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_hammer_means_no_site_and_nothing_taken(self):
        gid = self.mk()
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, HAMMER_IT)')
        self.jump_to(11)
        for _ in range(40):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        self.assertEqual((self.stat('started'), self.stat('planks')), (0, 0))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.NailsBox')), (8, 1))
        self.assertFalse(self.ev(f'{F}.hasWork("{gid}")'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_not_a_builder_means_no_barricade(self):
        self.mk(builder=False)
        self.jump_to(11)
        for _ in range(30):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        self.assertEqual(self.stat('started'), 0)
        self.assertEqual(self.count('Base.Plank'), 8)
        self.assertEqual(self.h.errors('solo'), [])

    def test_work_interrupted_before_the_plank_takes_nothing(self):
        gid = self.mk()
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.holder('work') is not None))
        npc = self.holder('work')
        self.run_lua(f'{R}.leave("{npc}")')                                     # menace, autre consigne...
        self.assertEqual((self.stat('planks'), self.count('Base.Plank'), self.count('Base.NailsBox')), (0, 8, 1))
        self.assertEqual(self.run_lua(f'local n = 0 for _ in pairs({F}.state.claims) do n = n + 1 end return n'), 0)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("%s")' % npc), 'idle')
        self.assertEqual(self.h.errors('solo'), [])

    def test_nail_plank_rechecks_the_world_before_taking(self):
        gid = self.mk()
        site = (f'{{ id = "barricade:110,116,0N", x = 110, y = 116, z = 0, north = true, opening = "door", '
                f'steps = 4, opp = false }}')
        self.assertEqual(self.run_lua(f'return {F}.nailPlank({site}, "{gid}", "m-2")'), (None, 'home entry'))
        back = self.run_lua('BACK = OPENING("door", 115, 108, false, { open = true }) return true')
        self.assertTrue(back)
        door = ('{ id = "barricade:115,108,0W", x = 115, y = 108, z = 0, north = false, opening = "door", '
                'steps = 4, opp = true }')
        self.assertEqual(self.run_lua(f'return {F}.nailPlank({door}, "{gid}", "m-2")'), (None, 'door open'))
        self.run_lua('BACK.opp = setmetatable({ planks = {}, metal = true, key = "m" }, IsoBarricade) BACK.open = false')
        self.assertEqual(self.run_lua(f'return {F}.nailPlank({door}, "{gid}", "m-2")'), (None, 'metal barricade'))
        gone = ('{ id = "barricade:108,105,0N", x = 108, y = 105, z = 0, north = true, opening = "window", '
                'steps = 4, opp = true }')
        self.assertEqual(self.run_lua(f'return {F}.nailPlank({gone}, "{gid}", "m-2")'), (None, 'opening gone'))
        # Rien de pris par ces refus.
        self.assertEqual((self.count('Base.Plank'), self.count('Base.NailsBox'), self.stat('planks')), (8, 1, 0))
        # Barricade déjà commencée d'un côté : complétée de ce côté, même si le plan visait l'autre.
        self.run_lua('WIN_W.own = HARNESS.addObject(105, 110, 0, setmetatable({ planks = { 10 }, key = "w" }, IsoBarricade))')
        win = ('{ id = "barricade:105,110,0W", x = 105, y = 110, z = 0, north = false, opening = "window", '
               'steps = 4, opp = true }')
        text, n = self.run_lua(f'return {F}.nailPlank({win}, "{gid}", "m-2")')
        self.assertEqual(n, 2, text)
        self.assertEqual(self.planks('WIN_W'), (2, 0))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (7, 99, 0))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerBarricadeTests(BarricadeStack):
    """Serveur dédié + deux clients : planches posées et transmises par le serveur seul ; mêmes gestes chez A et B."""

    mode = 'mp'

    def view(self, npc):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        for c in ('A', 'B'):
            out[c] = self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                    'local d = e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. "@" '
                                    '.. tostring(e.a) .. ":" .. tostring(e.v)) or "none" '
                                    f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") end)()')
        return out

    def test_server_nails_and_sends_each_plank_once(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Fortify'))
        self.jump_to(11)
        seen, npc = [], None
        for _ in range(200):
            # Banc MP : corps tenus par le serveur (aucun exécutant) ; arrivée posée à la place, regard rapporté fini.
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "fortify" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if npc is None:
                npc = self.holder()
            if npc is not None:
                v = self.view(npc)
                self.assertEqual(v['A'], v['B'])
                seen.append(v['A'])
            if self.stat('finished') >= 2:
                break
        self.assertEqual(self.stat('planks'), 8, seen[-5:])
        # Une barricade neuve envoyée complète (1 planche), puis 3 changements d'état, pour chaque fenêtre.
        sent = lua_list(self.ev('BAR_SENT'))
        self.assertEqual(sent, ['new window 112,105N:opp 1', 'state window 112,105N:opp 2',
                                'state window 112,105N:opp 3', 'state window 112,105N:opp 4',
                                'new window 105,110W:opp 1', 'state window 105,110W:opp 2',
                                'state window 105,110W:opp 3', 'state window 105,110W:opp 4'])
        self.assertEqual(self.ev('BAR.addedSent'), 100)                         # clous de la boîte, une fois
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (0, 92))
        self.assertTrue(any(s.endswith('|' + self.ev(f'{F}.CFG.GESTURE')) for s in seen), seen[-5:])
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteListTests(BarricadeStack):
    mode = 'solo'

    def test_suite_is_listed_with_its_tags(self):
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.barricade", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.barricade'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.barricade", { tags = { "world", "server" }', code)
        self.assertIn('Homes.skip(', code)

    def test_module_source_is_kahlua_safe(self):
        path = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / FORTIFY
        raw = path.read_text(encoding='utf-8')
        code = '\n'.join(line.split('--', 1)[0] for line in raw.splitlines())
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character in the code')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main(verbosity=1)
