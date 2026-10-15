"""Tests hors jeu du stock réel des foyers Living Knox (LK08-T06) et de sa gestion (LK08-T07 : seuils, autonomie,
rationnement au journal, besoins ordonnés lus par LK_Decisions) : server/LivingKnox/LK_Stock.lua et la suite en
jeu lk.stock (dev/.../RST_LKStock.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_stock.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec le vrai registre des groupes, le vrai
aménagement des foyers (LK_Homes, doublures de tests/test_lk_homes.py) et le vrai registre des attitudes
(LK_Hostility). Doublures ajoutées, relevées dans le Java 42.21.0 :
- conteneurs : IsoObject.getContainerCount / getContainerByIndex (J/iso/IsoObject.java:4822-4840) ; ItemContainer
  getType, getItems, isExplored / setExplored, AddItem (retire l'objet de son conteneur précédent,
  J/inventory/ItemContainer.java:444), Remove, getItemWithIDRecursiv (:2909, sacs compris) ;
- objets : InventoryItem.getID (identifiant tiré à la création, InventoryItemFactory.java:126), getFullType,
  getDisplayCategory (:2873, valeurs des scripts generated/items), getFluidContainer ; FluidContainer Empty,
  addFluid(Fluid, quantité) (surcharges Fluid / FluidType / String : une autre valeur est refusée), getCapacity,
  isEmpty, getPrimaryFluid ; bouteille d'eau créée avec un fluide tiré au hasard (PickRandomFluid) ;
- instanceItem (LuaManager.java:4669) : nil pour un type inconnu ; sendAddItemToContainer (:9700) compté sur le
  serveur seulement ;
- inventaire du joueur (IsoPlayer.getInventory) ; clé de joueur de LK_Hostility = RS_CarnetServer.bound[joueur].
Elles NE PROUVENT PAS l'API réelle, seulement la logique : suite en jeu lk.stock.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_homes import DOUBLES as HOME_DOUBLES, HOUSE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'
MODULES = ('server/LivingKnox/LK_Homes.lua', 'server/LivingKnox/LK_Stock.lua')
ST = 'LivingKnox.Stock'

STOCK_DOUBLES = r'''
local H = HARNESS
local C = H.classes
COUNT.sent = 0

-- Fluides ------------------------------------------------------------------------------------------------------------
local FluidCls = H.class('Fluid')
Fluid = {}
for _, n in ipairs({ 'Water', 'TaintedWater', 'RubbingAlcohol', 'Cola' }) do
    Fluid[n] = setmetatable({ name = n }, FluidCls)
end
local FC = H.class('FluidContainer')
function FC:Empty() self.fluid, self.amount = nil, 0 end
function FC:addFluid(f, amount)
    if getmetatable(f) ~= FluidCls then error('No implementation found for addFluid', 2) end
    H.num(amount, 'addFluid')
    if self.fluid ~= nil and self.fluid ~= f then return end   -- mélange non modélisé : refusé
    self.fluid = f
    self.amount = math.min(self.cap, (self.amount or 0) + amount)
end
function FC:getCapacity() return self.cap end
function FC:isEmpty() return self.fluid == nil or (self.amount or 0) <= 0 end
function FC:getPrimaryFluid() return self.fluid end

-- Objets d'inventaire --------------------------------------------------------------------------------------------------
ITEM_DEFS = {
    ['Base.TinnedBeans'] = { cat = 'Food' }, ['Base.CannedCorn'] = { cat = 'Food' },
    ['Base.TinnedSoup'] = { cat = 'Food' }, ['Base.CannedChili'] = { cat = 'Food' },
    ['Base.CannedPeas'] = { cat = 'Food' }, ['Base.Crackers'] = { cat = 'Food' },
    ['Base.Pop'] = { cat = 'Food', fluid = 'Cola', cap = 0.5 },
    ['Base.WaterBottle'] = { cat = 'Water', fluid = 'Cola', cap = 1.0 },   -- PickRandomFluid
    ['Base.Bandage'] = { cat = 'FirstAid' }, ['Base.Pills'] = { cat = 'FirstAid' },
    ['Base.Disinfectant'] = { cat = 'FirstAid', fluid = 'RubbingAlcohol', cap = 0.5 },
    ['Base.AlcoholWipes'] = { cat = 'FirstAid' }, ['Base.RippedSheets'] = { cat = 'Bandage' },
    ['Base.Bullets9mmBox'] = { cat = 'Ammo' }, ['Base.ShotgunShellsBox'] = { cat = 'Ammo' },
    ['Base.NailsBox'] = { cat = 'Material' }, ['Base.Rope'] = { cat = 'Material' },
    ['Base.DuctTape'] = { cat = 'Material' }, ['Base.ScrapMetal'] = { cat = 'Material' },
    ['Base.Plank'] = { cat = 'MaterialWeapon' }, ['Base.Hammer'] = { cat = 'ToolWeapon' },
    ['Base.Bag_Schoolbag'] = { cat = 'Bag', bag = true },
}
NEXT_ID = 1000000
local Item = C.InventoryItem
function Item:getID() return self.id end
function Item:getFullType() return self.type end
function Item:getDisplayCategory() return self.cat end
function Item:getFluidContainer() return rawget(self, 'fc') end
function Item:hasModData() return rawget(self, 'md') ~= nil end
instanceItem = function(t)
    local d = ITEM_DEFS[t]
    if d == nil then return nil end
    NEXT_ID = NEXT_ID + 7
    local it = setmetatable({ id = NEXT_ID, type = t, cat = d.cat }, Item)
    if d.fluid then it.fc = setmetatable({ fluid = Fluid[d.fluid], amount = d.cap, cap = d.cap }, FC) end
    if d.bag then it.inner = NEW_CONTAINER('bag') end
    return it
end

-- Conteneurs ---------------------------------------------------------------------------------------------------------
local Ctr = H.class('ItemContainer')
function NEW_CONTAINER(t, explored) return setmetatable({ type = t, items = H.list(), explored = explored ~= false }, Ctr) end
function Ctr:getType() return self.type end
function Ctr:getItems() return self.items end
function Ctr:isExplored() return self.explored == true end
function Ctr:setExplored(v) self.explored = v end
function Ctr:AddItem(it)
    if type(it) ~= 'table' then error('AddItem(String) not expected here', 2) end
    local prev = rawget(it, 'container')
    if prev then H.listRemove(prev.items, it) end
    self.items:add(it)
    it.container = self
    return it
end
function Ctr:Remove(it)
    H.listRemove(self.items, it)
    if rawget(it, 'container') == self then it.container = nil end
end
function Ctr:containsID(id)
    H.num(id, 'containsID')
    for _, it in ipairs(self.items.items) do if it.id == id then return true end end
    return false
end
function Ctr:getItemWithIDRecursiv(id)
    H.num(id, 'getItemWithIDRecursiv')
    for _, it in ipairs(self.items.items) do
        if it.id == id then return it end
        local inner = rawget(it, 'inner')
        if inner then
            local r = inner:getItemWithIDRecursiv(id)
            if r then return r end
        end
    end
    return nil
end
local function asContainer(o)
    local c = rawget(o, 'container')
    if c == nil then return nil end
    if getmetatable(c) ~= Ctr then
        setmetatable(c, Ctr)
        c.items = rawget(c, 'items') or H.list()
        c.explored = false   -- meuble posé : conteneur jamais rempli
    end
    return c
end
function C.IsoObject:getContainerCount()
    local extra = rawget(self, 'extra')
    return (asContainer(self) and 1 or 0) + (extra and #extra or 0)
end
function C.IsoObject:getContainerByIndex(i)
    H.num(i, 'getContainerByIndex')
    if i == 0 and asContainer(self) then return asContainer(self) end
    local extra = rawget(self, 'extra')
    return extra and extra[i] or nil
end
-- Meuble à conteneur(s) d'un bâtiment (sans sprite) : types et contenus.
function FURNITURE(x, y, types, contents)
    local o = setmetatable({}, C.IsoObject)
    o.container = NEW_CONTAINER(types[1])
    o.extra = {}
    for n = 2, #types do o.extra[n - 1] = NEW_CONTAINER(types[n]) end
    for _, t in ipairs(contents or {}) do o.container:AddItem(instanceItem(t)) end
    H.addObject(x, y, 0, o)
    return o
end
sendAddItemToContainer = function(c, it)
    if getmetatable(c) ~= Ctr then error('No implementation found for sendAddItemToContainer', 2) end
    if isServer() then COUNT.sent = COUNT.sent + 1 end
end
sendRemoveItemFromContainer = function() end

-- Joueurs -------------------------------------------------------------------------------------------------------------
function C.IsoPlayer:getInventory()
    local inv = rawget(self, 'inv')
    if not inv then inv = NEW_CONTAINER('none') self.inv = inv end
    return inv
end
RS_CarnetServer = { bound = {} }
function BIND(name, key) RS_CarnetServer.bound[HARNESS.players[name]] = key end

-- Aides ---------------------------------------------------------------------------------------------------------------
function OWNED(gid)
    local out = {}
    for _, t in ipairs(TAGGED(gid)) do
        if t.o.getContainerCount and t.o:getContainerCount() > 0 then out[#out + 1] = t.o:getContainerByIndex(0) end
    end
    return out
end
function STOCKED(gid)
    local n = 0
    for _, c in ipairs(OWNED(gid)) do
        for _, it in ipairs(c.items.items) do
            if it:hasModData() and it:getModData().LKStock == gid then n = n + 1 end
        end
    end
    return n
end
function FIRST_STOCKED(gid, t)
    for _, c in ipairs(OWNED(gid)) do
        for _, it in ipairs(c.items.items) do
            if it.type == t then return it, c end
        end
    end
end
function REF_IDS(gid)
    local g = LivingKnox.Groups.get(gid)
    local out = {}
    for _, e in ipairs(g.stock.items) do out[#out + 1] = e.i end
    table.sort(out)
    return out
end
function REAL_IDS(gid)
    local g = LivingKnox.Groups.get(gid)
    local style, def = LivingKnox.Homes.ready(g.home)
    local cts = assert(LivingKnox.Stock.containers(gid, g.home, style, def and def:getIDString()))
    local out = {}
    for _, e in ipairs(LivingKnox.Stock.read(cts)) do out[#out + 1] = e.i end
    table.sort(out)
    return out
end
'''

# Cuisine dans la maison de test : frigo et congélateur (un objet, deux conteneurs), placard ; poubelle dehors.
KITCHEN = r'''
FRIDGE = FURNITURE(108, 102, { 'fridge', 'freezer' }, { 'Base.TinnedBeans', 'Base.Hammer' })
FRIDGE.extra[1]:AddItem(instanceItem('Base.Pop'))
CUPBOARD = FURNITURE(109, 102, { 'counter' }, { 'Base.Bandage', 'Base.Plank' })
BIN = FURNITURE(98, 95, { 'bin' }, { 'Base.TinnedBeans' })
'''

SETTLERS_KIT = 18
RAIDERS_KIT = 15


class Base(unittest.TestCase):
    mode = 'solo'

    def setUp(self):
        self.h = Harness(mode=self.mode, lua_roots=[DEV_LUA])
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, HOME_DOUBLES)
            self.h.load(m, STOCK_DOUBLES)
            for path in SHARED:
                self.h.load(m, path)
            self.h.load(m, SERVER)
            for path in MODULES:
                self.h.load(m, path)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)

    def tearDown(self):
        self.h.close()

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]

    def group(self, gtype='settlers', home=(103, 104, 0), members=4, name='Mill'):
        roles = ['worker', 'fighter', 'medic', 'scout', 'worker', 'fighter', 'deputy', 'worker']
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "{gtype}", name = "{name}", day = 1, '
                f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }})) ')
        for i in range(members):
            code += f'assert(G.addMember(g.id, {{ role = "{roles[i]}", day = 1 }})) '
        return self.run_lua(code + 'return g.id')

    def minute(self):
        """Une minute de jeu (LK_Homes puis LK_Stock, abonnés à EveryOneMinute), après CHECK_MS."""
        self.h.advance_ms(5000)
        self.h.advance(1)
        self.run_lua(f'{ST}.finishQueue()')   # LK13-T09 : relecture étalée, un groupe par image

    def check(self, gid):
        return self.ev(f'({ST}.check("{gid}", {{ force = true }}))')

    def why(self, gid):
        return self.run_lua(f'return select(2, {ST}.check("{gid}", {{ force = true }}))')

    def totals(self, gid):
        t = self.ev(f'{ST}.totals("{gid}")')
        return dict(t.items())

    def take(self, gid, item_type, player='A', into_bag=False):
        """Le joueur prend un objet du stock (transfert : même objet, même identifiant)."""
        code = f'local it = assert(FIRST_STOCKED("{gid}", "{item_type}")) local inv = HARNESS.players["{player}"]:getInventory() '
        if into_bag:
            code += ('local bag = instanceItem("Base.Bag_Schoolbag") inv:AddItem(bag) bag.inner:AddItem(it) ')
        else:
            code += 'inv:AddItem(it) '
        return self.run_lua(code + 'return it.id')


class PureTests(Base):
    def test_categories_from_script_data(self):
        code = ('local it = instanceItem("%s") %s return %s.categoryOf(it)')
        cases = [
            ('Base.TinnedBeans', '', 'food'),
            ('Base.Pop', '', 'food'),                       # boisson : fluide qui n'est pas de l'eau
            ('Base.WaterBottle', '', None),                 # fluide tiré au hasard (ici du soda)
            ('Base.WaterBottle', 'it.fc:Empty() it.fc:addFluid(Fluid.Water, 1)', 'water'),
            ('Base.WaterBottle', 'it.fc:Empty() it.fc:addFluid(Fluid.TaintedWater, 1)', 'water'),
            ('Base.WaterBottle', 'it.fc:Empty()', None),    # vide
            ('Base.Bandage', '', 'medical'), ('Base.RippedSheets', '', 'medical'),
            ('Base.Disinfectant', '', 'medical'),
            ('Base.Bullets9mmBox', '', 'ammo'),
            ('Base.NailsBox', '', 'materials'), ('Base.Plank', '', 'materials'),
            ('Base.Hammer', '', None), ('Base.Bag_Schoolbag', '', None),
        ]
        for t, prep, want in cases:
            with self.subTest(t=t, prep=prep):
                self.assertEqual(self.run_lua(code % (t, prep, ST)), want)

    def test_every_kit_item_exists_and_has_its_category(self):
        # Doublures ITEM_DEFS relevées dans media/scripts/generated/items (DisplayCategory) : chaque objet des kits
        # est connu et classé (une bouteille remplie d'eau compte comme eau).
        out = self.run_lua(f'''
            local bad = {{}}
            for gtype, kit in pairs({ST}.KITS) do
                for _, e in ipairs(kit) do
                    local it = instanceItem(e[1])
                    if it and e.fill then it.fc:Empty() it.fc:addFluid(Fluid[e.fill], it.fc:getCapacity()) end
                    if it == nil or {ST}.categoryOf(it) == nil then bad[#bad + 1] = gtype .. ":" .. e[1] end
                end
            end
            return table.concat(bad, ",")''')
        self.assertEqual(out, '')
        sizes = self.run_lua(f'local s = {{}} for k, kit in pairs({ST}.KITS) do local n = 0 '
                             f'for _, e in ipairs(kit) do n = n + e[2] end s[k] = n end return s')
        self.assertEqual(dict(sizes.items()), {'settlers': SETTLERS_KIT, 'raiders': RAIDERS_KIT, 'neutrals': 14})

    def test_valid_reference(self):
        home = '{ x = 5, y = 6, z = 0 }'
        ok = (f'{ST}.validRef({{ v = 1, hx = 5, hy = 6, hz = 0, fill = "done", day = 1, '
              f'items = {{ {{ i = 1234567, t = "Base.Rope", c = "materials", k = "1,2,0,crate,1" }} }} }}, {home})')
        self.assertTrue(self.ev(f'({ok})'))
        for bad in ('nil', '{}',
                    '{ v = 2, hx = 5, hy = 6, hz = 0, fill = "done", items = {} }',
                    '{ v = 1, hx = 5, hy = 7, hz = 0, fill = "done", items = {} }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, fill = "maybe", items = {} }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, fill = "done" }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, fill = "done", items = { { i = 1.5, t = "Base.Rope", c = "materials", k = "a" } } }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, fill = "done", items = { { i = 1, t = "Base.Rope", c = "tools", k = "a" } } }'):
            with self.subTest(bad=bad):
                self.assertFalse(self.ev(f'({ST}.validRef({bad}, {home}))'))

    def test_diff(self):
        out = self.run_lua(f'''
            local ref = {{ {{ i = 1, k = "a" }}, {{ i = 2, k = "a" }}, {{ i = 3, k = "b" }} }}
            local real = {{ {{ i = 2, k = "b" }}, {{ i = 3, k = "b" }}, {{ i = 4, k = "a" }}, {{ i = 5, k = "a" }} }}
            local d = {ST}.diff(ref, real)
            return #d.missing, d.missing[1].i, d.added, d.moved''')
        self.assertEqual(tuple(out), (1, 1, 2, 1))


class BuildingTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)

    def filled(self, members=4):
        gid = self.group(members=members)
        self.minute()
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").furnish.state'), 'done')
        return gid

    def test_stock_filled_once_reference_equals_real_content(self):
        gid = self.filled()
        s = self.ev(f'LivingKnox.Groups.get("{gid}").stock')
        self.assertEqual((s.v, s.fill, s.hx, s.hy, s.hz), (1, 'done', 103, 104, 0))
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        # Kit + frigo (haricots ; marteau ignoré) + congélateur (soda = nourriture) + placard (bandage, planche) ;
        # poubelle hors du bâtiment ignorée.
        self.assertEqual(self.totals(gid), {'food': 6 + 2, 'water': 3, 'medical': 5 + 1, 'ammo': 1,
                                            'materials': 3 + 1})
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), list(self.ev(f'REAL_IDS("{gid}")').values()))
        # Eau : vraie eau, pleine ; objets du kit marqués ; caisse marquée explorée (pas de butin vanilla en plus).
        self.assertEqual(self.run_lua(f'local it = FIRST_STOCKED("{gid}", "Base.WaterBottle") '
                                      f'return it.fc.fluid.name, it.fc.amount'), ('Water', 1.0))
        self.assertTrue(self.ev(f'OWNED("{gid}")[1]:isExplored()'))
        self.assertTrue(any(f'stock: group {gid} home 103,104,0: 18 item(s) stored (settlers kit)' in line
                            for line in self.lk()), self.lk())
        self.assertEqual(self.ev('COUNT.sent'), 0)   # solo : rien à envoyer
        # Minutes suivantes : relectures sans rien créer, référence inchangée.
        before = list(self.ev(f'REF_IDS("{gid}")').values())
        for _ in range(3):
            self.minute()
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), before)

    def test_restart_does_not_fill_again(self):
        gid = self.filled()
        before = list(self.ev(f'REF_IDS("{gid}")').values())
        self.run_lua(f'{ST}.reset() LivingKnox.Homes.reset() LivingKnox.Groups.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.minute()
        r = self.check(gid)
        self.assertEqual((r.action, r.missing, r.added), ('checked', 0, 0))
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), before)

    def test_interrupted_filling_is_never_redone(self):
        gid = self.group()
        self.run_lua(f'LivingKnox.Homes.check("{gid}", {{ force = true }}) '
                     f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].stock = {{ v = 1, hx = 103, '
                     f'hy = 104, hz = 0, fill = "filling", day = 1, items = {{}} }} return true end))')
        r = self.check(gid)
        self.assertEqual(r.action, 'checked')
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), 0)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").stock.fill'), 'done')
        self.assertTrue(any('left half filled' in line for line in self.lk()))
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), list(self.ev(f'REAL_IDS("{gid}")').values()))

    def test_lost_reference_is_restored_without_creating(self):
        gid = self.filled()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].stock = nil return true end))')
        r = self.check(gid)
        self.assertEqual(r.action, 'restored')
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        self.assertTrue(any('reference restored, nothing created' in line for line in self.lk()))

    def test_theft_is_detected_and_reported_once(self):
        gid = self.filled()
        self.run_lua('BIND("A", "c-alpha")')
        a = self.take(gid, 'Base.Bullets9mmBox')
        b = self.take(gid, 'Base.TinnedBeans', into_bag=True)   # rangé dans un sac de l'inventaire
        r = self.check(gid)
        self.assertEqual((r.missing, r.lost), (2, 0))
        thefts = [dict(t.items()) for t in r.thefts.values()]
        self.assertEqual(thefts, [{'player': 'A', 'items': 2, 'result': 'reported'}])
        self.assertTrue(self.ev(f'LivingKnox.Hostility.isKnown("{gid}", "c-alpha")'))
        self.assertEqual(self.ev(f'LivingKnox.Hostility.state.data.groups["{gid}"]["c-alpha"].facts[1].fact'), 'theft')
        ids = list(self.ev(f'REF_IDS("{gid}")').values())
        self.assertNotIn(a, ids)
        self.assertNotIn(b, ids)
        self.assertEqual(self.totals(gid)['ammo'], 0)
        self.assertTrue(any('2 item(s) taken by A, theft reported' in line for line in self.lk()), self.lk())
        # Relecture suivante : rien de nouveau.
        r = self.check(gid)
        self.assertEqual((r.missing, len(r.thefts)), (0, 0))

    def test_second_theft_within_the_hour_is_not_counted_twice(self):
        gid = self.filled()
        self.run_lua('BIND("A", "c-alpha")')
        self.take(gid, 'Base.Rope')
        self.assertEqual(self.check(gid).thefts[1].result, 'reported')
        self.take(gid, 'Base.NailsBox')
        self.assertEqual(self.check(gid).thefts[1].result, 'cooldown')
        self.h.advance(61)
        self.take(gid, 'Base.DuctTape')
        self.assertEqual(self.check(gid).thefts[1].result, 'reported')
        self.assertEqual(self.ev(f'#LivingKnox.Hostility.state.data.groups["{gid}"]["c-alpha"].facts'), 2)

    def test_player_without_notebook_key_is_not_reported(self):
        gid = self.filled()
        self.take(gid, 'Base.Rope')
        r = self.check(gid)
        self.assertEqual(r.thefts[1].result, 'no key')
        self.assertFalse(self.ev(f'LivingKnox.Hostility.isKnown("{gid}", "c-alpha")'))
        self.assertTrue(any('not reported: no notebook character bound' in line for line in self.lk()))

    def test_item_gone_without_holder_is_a_loss(self):
        gid = self.filled()
        self.run_lua(f'local it, c = FIRST_STOCKED("{gid}", "Base.Pills") c:Remove(it)')
        r = self.check(gid)
        self.assertEqual((r.missing, r.lost, len(r.thefts)), (1, 1, 0))
        self.assertTrue(any('1 item(s) gone without a known taker' in line for line in self.lk()))

    def test_added_and_moved_items_are_accepted(self):
        gid = self.filled()
        self.run_lua(f'local it = FIRST_STOCKED("{gid}", "Base.Rope") FRIDGE.container:AddItem(it) '
                     f'CUPBOARD.container:AddItem(instanceItem("Base.ShotgunShellsBox"))')
        r = self.check(gid)
        self.assertEqual((r.missing, r.added, r.moved, len(r.thefts)), (0, 1, 1, 0))
        self.assertEqual(self.totals(gid)['ammo'], 2)
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), list(self.ev(f'REAL_IDS("{gid}")').values()))

    def test_waits_for_furnishing_and_loaded_area(self):
        gid = self.group()
        self.assertEqual(self.why(gid), 'home not furnished yet')
        self.run_lua(f'LivingKnox.Homes.check("{gid}", {{ force = true }})')
        self.run_lua('UNLOADED_X = 112')
        self.assertEqual(self.why(gid), 'home area not loaded')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").stock'))
        self.run_lua('UNLOADED_X = nil')
        self.assertEqual(self.check(gid).action, 'filled')

    def test_unloaded_square_inside_the_area_blocks_the_check(self):
        gid = self.filled()
        self.run_lua('local Cell = getmetatable(getCell()) local get = Cell.getGridSquare '
                     'function Cell:getGridSquare(x, y, z) if x == 108 and y == 102 then return nil end '
                     'return get(self, x, y, z) end')
        self.assertEqual(self.why(gid), 'home area not loaded')

    def test_skipped_home_gets_no_stock_items(self):
        gid = self.group()
        self.run_lua(f'assert(LivingKnox.Homes.skip("{gid}"))')
        r = self.check(gid)
        self.assertEqual(r.action, 'filled')
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), 0)
        self.assertEqual(self.totals(gid), {'food': 2, 'water': 0, 'medical': 1, 'ammo': 0, 'materials': 1})

    def test_home_moved_resets_the_reference(self):
        gid = self.filled()
        self.run_lua(f'assert(LivingKnox.Groups.setHome("{gid}", 180, 180, 0))')
        self.h.advance_ms(20000)   # nouvel essai de LK_Homes après RETRY_MS
        self.minute()
        s = self.ev(f'LivingKnox.Groups.get("{gid}").stock')
        self.assertEqual((s.hx, s.hy, s.fill), (180, 180, 'done'))

    def test_disabled_engine_does_nothing(self):
        gid = self.group()
        self.run_lua(f'LivingKnox.Homes.check("{gid}", {{ force = true }}) '
                     'SandboxVars = { LivingKnox = { Enabled = false } }')
        self.h.advance_ms(5000)
        self.assertEqual(self.ev(f'{ST}.scan("minute")'), 0)
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").stock'))


class CampTests(Base):
    def test_camp_stock_is_spread_over_the_tents(self):
        # Une case de chaque petite tente porte le conteneur (newtiledefinitions.tiles.txt : camping_01_0 et _3,
        # container = tent, ContainerCapacity = 30).
        self.run_lua('SPRITES.camping_01_0.props.container = "tent" SPRITES.camping_01_3.props.container = "tent"')
        gid = self.group('raiders', home=(200, 200, 0), members=5, name='Crows')
        self.minute()
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), RAIDERS_KIT)
        counts = self.run_lua(f'local out = {{}} for _, c in ipairs(OWNED("{gid}")) do out[#out + 1] = c:getItems():size() end '
                              f'return out')
        counts = [n for n in counts.values() if n > 0]
        self.assertGreater(len(counts), 1)
        self.assertLessEqual(max(counts) - min(counts), 1)
        self.assertEqual(self.totals(gid), {'food': 4, 'water': 2, 'medical': 3, 'ammo': 3, 'materials': 3})


class MultiplayerTests(Base):
    mode = 'mp'

    def test_server_sends_every_item_and_attributes_a_remote_player(self):
        self.run_lua(HOUSE)
        gid = self.group()
        self.minute()
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        self.assertEqual(self.ev('COUNT.sent'), SETTLERS_KIT)
        self.run_lua('BIND("B", "c-bravo")')
        self.take(gid, 'Base.Pills', player='B')
        r = self.check(gid)
        self.assertEqual([dict(t.items()) for t in r.thefts.values()],
                         [{'player': 'B', 'items': 1, 'result': 'reported'}])
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, ST))


def needs_list(a):
    """Liste ordonnée des besoins d'une évaluation (proxy Lua) : [(catégorie, a, visée, niveau, statut)]."""
    return [(n.c, n.have, n.want, n.level, n.status) for n in a.needs.values()]


class SupplyPureTests(Base):
    """LK08-T07 : seuils, autonomie, rationnement et besoins (logique pure)."""

    def assess(self, totals, members):
        t = ', '.join(f'{k} = {v}' for k, v in totals.items())
        return self.ev(f'{ST}.assess({{ {t} }}, {members})')

    def test_thresholds_follow_living_members(self):
        stock = {'food': 8, 'water': 3, 'medical': 6, 'ammo': 1, 'materials': 4}
        a = self.assess(stock, 4)
        self.assertEqual(dict(a.want.items()), {'food': 12, 'water': 12, 'medical': 4, 'ammo': 2, 'materials': 4})
        self.assertEqual(dict(a.levels.items()), {'food': 67, 'water': 25, 'medical': 100, 'ammo': 50,
                                                  'materials': 100})
        self.assertEqual(dict(a.days.items()), {'food': 2.0, 'water': 0.7})
        self.assertEqual(a.autonomy, 0.7)
        self.assertEqual(needs_list(a), [('water', 3, 12, 25, 'low'), ('ammo', 1, 2, 50, 'low'),
                                         ('food', 8, 12, 67, 'low')])
        a = self.assess(stock, 2)   # deux morts : visées réduites
        self.assertEqual(dict(a.want.items()), {'food': 6, 'water': 6, 'medical': 2, 'ammo': 1, 'materials': 2})
        self.assertEqual(a.autonomy, 1.5)
        self.assertEqual(needs_list(a), [('water', 3, 6, 50, 'low')])
        a = self.assess(stock, 7)   # 0,5 munition par membre : arrondi au-dessus
        self.assertEqual(a.want.ammo, 4)
        self.assertIsNone(self.assess(stock, 0))

    def test_needs_order_is_fixed_and_reproducible(self):
        stock = {'food': 1, 'water': 0, 'medical': 0, 'ammo': 1, 'materials': 2}
        first = needs_list(self.assess(stock, 4))
        # Épuisés d'abord (ordre des catégories à niveau égal), puis critiques, puis bas.
        self.assertEqual(first, [('water', 0, 12, 0, 'empty'), ('medical', 0, 4, 0, 'empty'),
                                 ('food', 1, 12, 8, 'critical'), ('ammo', 1, 2, 50, 'low'),
                                 ('materials', 2, 4, 50, 'low')])
        for _ in range(3):
            self.assertEqual(needs_list(self.assess(stock, 4)), first)
        self.assertEqual(needs_list(self.assess({'food': 99, 'water': 99, 'medical': 9, 'ammo': 9,
                                                 'materials': 9}, 4)), [])

    def test_ration_levels_and_margin(self):
        code = (f'local a = {ST}.assess({{ food = %d, water = %d, medical = 0, ammo = 0, materials = 0 }}, 4) '
                f'return {ST}.rationLevel(a, %d)')
        cases = [
            ((12, 12, 0), 0), ((8, 12, 0), 0),     # 2 jours : normal
            ((7, 12, 0), 1), ((4, 12, 0), 1),      # moins de 2 jours : réduit
            ((3, 12, 0), 2), ((3, 12, 1), 2),      # moins d'un jour : strict, aussitôt
            ((0, 12, 0), 3), ((12, 0, 1), 3),      # nourriture ou eau à zéro : épuisé
            ((5, 12, 2), 2),                       # 1,2 jour : pas encore 1,5 jour d'avance
            ((6, 12, 2), 1),                       # 1,5 jour : réduit
            ((8, 12, 1), 1), ((10, 12, 1), 0),     # retour au normal à 2,5 jours seulement
            ((1, 12, 3), 2),                       # vivres revenus : fin de l'épuisement
        ]
        for (food, water, cur), want in cases:
            with self.subTest(food=food, water=water, cur=cur):
                self.assertEqual(self.run_lua(code % (food, water, cur)), want)


class SupplyTests(Base):
    """LK08-T07 dans le foyer de test : rationnement au journal, besoins lus par le cadre de décision."""

    filled = BuildingTests.filled

    def setUp(self):
        super().setUp()
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)

    def rations(self, gid):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'ration']

    def put(self, item_type, n, water=False):
        prep = 'it.fc:Empty() it.fc:addFluid(Fluid.Water, 1) ' if water else ''
        self.run_lua(f'for _ = 1, {n} do local it = instanceItem("{item_type}") {prep}'
                     f'CUPBOARD.container:AddItem(it) end')

    def test_rationing_is_logged_when_stock_drops_and_eased_with_margin(self):
        gid = self.filled()
        start = 'ration strict (was normal): 0.7 day(s) of food and water for 4 (food 8, water 3)'
        self.assertEqual(self.rations(gid), [start])
        self.assertTrue(any(f'stock: group {gid} {start}' in line for line in self.lk()), self.lk())
        a = self.ev(f'{ST}.needs("{gid}")')
        self.assertEqual((a.ration, a.rationName, a.portion), (2, 'strict', 0.5))
        self.assertEqual(self.ev(f'{ST}.portion("{gid}")'), 0.5)
        self.assertEqual(needs_list(a), [('water', 3, 12, 25, 'low'), ('ammo', 1, 2, 50, 'low'),
                                         ('food', 8, 12, 67, 'low')])
        for _ in range(2):   # relectures sans changement : rien de plus au journal
            self.minute()
        self.assertEqual(len(self.rations(gid)), 1)
        self.put('Base.WaterBottle', 6, water=True)   # eau 9 : 2 jours, mais pas 1,5 jour d'avance sur le strict
        self.assertEqual(self.check(gid).ration, 1)
        self.put('Base.WaterBottle', 3, water=True)
        self.put('Base.TinnedBeans', 4)               # 3 jours : retour au normal
        self.assertEqual(self.check(gid).ration, 0)
        self.run_lua('BIND("A", "c-alpha")')
        self.run_lua('local inv = HARNESS.players.A:getInventory() local list = {} '
                     'for _, it in ipairs(CUPBOARD.container.items.items) do '
                     'if it.type == "Base.WaterBottle" then list[#list + 1] = it end end '
                     'for _, it in ipairs(list) do inv:AddItem(it) end')
        for _ in range(3):                            # toute l'eau emportée : épuisé
            self.take(gid, 'Base.WaterBottle')
        self.assertEqual(self.check(gid).ration, 3)
        self.assertEqual(self.rations(gid)[1:], [
            'ration reduced (was strict): 2.0 day(s) of food and water for 4 (food 8, water 9)',
            'ration normal (was reduced): 3.0 day(s) of food and water for 4 (food 12, water 12)',
            'ration out (was normal): 0.0 day(s) of food and water for 4 (food 12, water 0)'])
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").stock.ration'), 3)

    def test_member_death_lowers_the_thresholds(self):
        gid = self.filled()
        self.run_lua(f'assert(LivingKnox.Groups.markDead("{gid}", "m-1")) '
                     f'assert(LivingKnox.Groups.markDead("{gid}", "m-2"))')
        self.assertEqual(self.check(gid).ration, 1)   # 1,5 jour pour 2
        a = self.ev(f'{ST}.needs("{gid}")')
        self.assertEqual((a.members, a.want.food), (2, 6))
        self.assertEqual(needs_list(a), [('water', 3, 6, 50, 'low')])

    def test_restart_keeps_the_ration_level(self):
        gid = self.filled()
        self.run_lua(f'{ST}.reset() LivingKnox.Homes.reset() LivingKnox.Groups.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.check(gid).ration, 2)
        self.assertEqual(len(self.rations(gid)), 1)

    def test_bad_ration_value_keeps_the_reference(self):
        gid = self.filled()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].stock.ration = "x" return true end))')
        r = self.check(gid)
        self.assertEqual((r.action, r.ration), ('checked', 2))
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)

    def test_no_reference_means_no_needs(self):
        gid = self.group()
        self.assertEqual(self.run_lua(f'return select(2, {ST}.needs("{gid}"))'),
                         'no stock reference or no living member')
        self.assertEqual(self.ev(f'{ST}.portion("{gid}")'), 1)

    def test_decisions_read_the_stock_levels(self):
        gid = self.filled()
        code = (f'local g = LivingKnox.Groups.get("{gid}") local D = LivingKnox.Decisions '
                f'local gin = D.groupInput("{gid}", g, 30) local old = D.CFG.JITTER D.CFG.JITTER = 0 '
                f'local r = D.scoreObjectives(gin) D.CFG.JITTER = old '
                f'return gin.needs.food, gin.needs.water, gin.needs.medical, gin.needs.ammo, r.objective, r.why')
        food, water, medical, ammo, objective, why = self.run_lua(code)
        self.assertEqual((food, water, medical, ammo), (67, 25, 100, 50))
        self.assertEqual(objective, 'supply')
        self.assertTrue(why.startswith('supply 53 (water 25)'), why)
        # Sans référence de stock : besoins abstraits du registre, eau ignorée (comportement d'avant LK08-T07).
        self.run_lua(f'{ST}.clear("{gid}")')
        food, water, medical, ammo, objective, _ = self.run_lua(code)
        self.assertEqual((food, water, medical, ammo), (50, None, 50, 50))


class SuiteTests(Base):
    """La suite en jeu lk.stock passe dans le banc (joueur debout dans la maison de test)."""

    def run_suite(self):
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKStock.lua')
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.stock", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        self.run_lua('BIND("A", "c-alpha")')
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 1)
        self.assertEqual(len(list(self.ev('LivingKnox.Groups.list()').values())), 0)
        self.assertEqual(self.ev('HARNESS.players.A:getInventory():getItems():size()'), 0)

    def test_suite_detects_a_duplicate(self):
        # Garde retirée : la référence perdue fait recréer le kit, la suite doit échouer.
        self.run_lua('BIND("A", "c-alpha")')
        # Objets du kit sans marque LKStock : la garde « restored » ne les voit plus, le kit est recréé.
        self.run_lua('local mk = instanceItem instanceItem = function(t) local it = mk(t) '
                     'if it then local md = it:getModData() setmetatable(md, { __newindex = function() end }) end '
                     'return it end')
        _, results = self.run_suite()
        self.assertEqual(results['home stock filled once, reference equals content, theft detected'][0], 'FAIL')


# LK09-T06 -------------------------------------------------------------------------------------------------------------
# Doublures ajoutées : ItemContainer.DoRemoveItem (J/inventory/ItemContainer.java:1979, une seule surcharge) ;
# sendRemoveItemFromContainer (LuaManager.java:9734, envoi par le serveur seulement) compté.
OFFSCREEN_DOUBLES = r'''
local Ctr = getmetatable(NEW_CONTAINER('x'))
COUNT.removedItems, COUNT.removeSent = 0, 0
function Ctr:DoRemoveItem(it)
    if type(it) ~= 'table' then error('No implementation found for DoRemoveItem', 2) end
    self:Remove(it)
    COUNT.removedItems = COUNT.removedItems + 1
end
sendRemoveItemFromContainer = function(c, it)
    if getmetatable(c) ~= Ctr or type(it) ~= 'table' then error('No implementation found for sendRemoveItemFromContainer', 2) end
    if isServer() then COUNT.removeSent = COUNT.removeSent + 1 end
end
-- Écriture hors écran sur le registre vivant (comme le pas de la simulation).
function OFF_MEAL(gid, hour, day)
    local out
    assert(LivingKnox.Groups.update(function(d)
        out = LivingKnox.Stock.offscreenHour(d.groups[gid], gid, hour, day or 1)
        return true, true
    end))
    return out
end
function OFF_LOOT(gid, gains, day)
    local out
    assert(LivingKnox.Groups.update(function(d)
        out = LivingKnox.Stock.offscreenLoot(d.groups[gid], gid, gains, day or 1)
        return true, true
    end))
    return out
end
function PENDING(gid)
    return LivingKnox.Stock.pendingCount(LivingKnox.Groups.get(gid).stock)
end
-- Objets d'un type dans tous les conteneurs du foyer, et objets portant encore une marque d'application.
function COUNT_TYPE(gid, t)
    local g = LivingKnox.Groups.get(gid)
    local style, def = LivingKnox.Homes.ready(g.home)
    local cts = assert(LivingKnox.Stock.containers(gid, g.home, style, def and def:getIDString()))
    local n, marked = 0, 0
    for _, ct in ipairs(cts) do
        for _, it in ipairs(ct.container.items.items) do
            if t == nil or it.type == t then n = n + 1 end
            if it:hasModData() and it:getModData().LKStockOp ~= nil then marked = marked + 1 end
        end
    end
    return n, marked
end
'''

MEAL_HOUR = 12   # heure simulée dont l'heure du jour de début vaut OFFSCREEN.MEAL_HOUR = 18 ((12 + 6) % 24)


class OffscreenTests(Base):
    """LK09-T06 : repas et butin hors écran dans la référence, appliqués aux conteneurs à l'arrivée d'un joueur."""

    filled = BuildingTests.filled

    def setUp(self):
        super().setUp()
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua(OFFSCREEN_DOUBLES)

    def same(self, gid):
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), list(self.ev(f'REAL_IDS("{gid}")').values()))

    def restart(self):
        self.run_lua(f'{ST}.reset() LivingKnox.Homes.reset() LivingKnox.Groups.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)

    def test_offscreen_meal_changes_the_reference_then_the_containers_on_arrival(self):
        gid = self.filled()   # 4 colons, nourriture 8, eau 3, ration stricte (0,5)
        real = list(self.ev(f'REAL_IDS("{gid}")').values())
        self.run_lua('UNLOADED_X = 112')   # foyer hors de la zone chargée
        self.assertIsNone(self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR - 1})'))   # pas l'heure du repas
        meal = self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        self.assertEqual((meal.eaters, meal.portion, meal.food, meal.water, meal.wantFood, meal.wantWater),
                         (4, 0.5, 2, 2, 2, 2))
        self.assertEqual(self.totals(gid), {'food': 6, 'water': 1, 'medical': 6, 'ammo': 1, 'materials': 4})
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 4)
        self.assertEqual(self.why(gid), 'home area not loaded')   # rien n'est appliqué tant que le foyer est illisible
        self.run_lua('UNLOADED_X = nil')   # un joueur arrive
        self.assertEqual(list(self.ev(f'REAL_IDS("{gid}")').values()), real)   # conteneurs encore intacts
        r = self.check(gid)
        self.assertEqual((r.action, r.missing, r.lost, r.added), ('checked', 0, 0, 0))
        self.assertEqual((r.applied.removed, r.applied.gone, r.applied.made), (4, 0, 0))
        self.assertEqual(self.ev('COUNT.removedItems'), 4)
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.same(gid)
        self.assertEqual(self.totals(gid), {'food': 6, 'water': 1, 'medical': 6, 'ammo': 1, 'materials': 4})
        self.assertTrue(any(f'stock: group {gid} offscreen changes applied' in line for line in self.lk()), self.lk())

    def test_offscreen_loot_creates_vanilla_items_on_arrival(self):
        gid = self.filled()
        self.assertEqual(self.ev(f'OFF_LOOT("{gid}", {{ food = 26, medical = 2, ammo = 11, water = 5 }})'), 8)
        self.assertEqual(self.totals(gid), {'food': 13, 'water': 4, 'medical': 6, 'ammo': 3, 'materials': 4})
        self.assertEqual(self.ev(f'{ST}.reference("{gid}").pending'), 8)
        r = self.check(gid)
        self.assertEqual((r.missing, r.added, r.applied.made, r.applied.removed), (0, 0, 8, 0))
        self.same(gid)
        self.assertEqual(self.totals(gid), {'food': 13, 'water': 4, 'medical': 6, 'ammo': 3, 'materials': 4})
        # Objets marqués du groupe, rangés dans la caisse posée, marque d'application effacée ; eau vraiment remplie.
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT + 8)
        self.assertEqual(self.ev(f'select(2, COUNT_TYPE("{gid}"))'), 0)
        self.assertEqual(self.run_lua('local n = 0 for _, c in ipairs(OWNED("' + gid + '")) do '
                                      'for _, it in ipairs(c.items.items) do if it.type == "Base.WaterBottle" '
                                      'and it.fc.fluid == Fluid.Water and it.fc.amount == it.fc.cap then n = n + 1 end '
                                      'end end return n'), 4)
        # Plus rien en attente : relectures sans changement.
        for _ in range(2):
            self.assertEqual(self.check(gid).applied, None)
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT + 8)

    def test_meal_cancels_pending_loot_first(self):
        gid = self.filled()
        self.assertEqual(self.ev(f'OFF_LOOT("{gid}", {{ food = 10 }})'), 2)
        meal = self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        self.assertEqual((meal.food, meal.water), (2, 2))
        ops = self.ev(f'LivingKnox.Groups.get("{gid}").stock.pend.ops')
        self.assertEqual([(o.o, o.c) for o in ops.values()], [('take', 'water'), ('take', 'water')])
        r = self.check(gid)
        self.assertEqual((r.applied.removed, r.applied.made, r.missing), (2, 0, 0))
        self.same(gid)
        self.assertEqual(self.totals(gid)['food'], 8)

    def test_meal_follows_ration_members_and_expedition(self):
        gid = self.filled(members=6)   # 6 colons : 0,4 jour d'eau, ration stricte
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].expedition = '
                     f'{{ place = "houses", team = {{ "m-5", "m-6" }}, departed = 1, returns = 99 }} return true end))')
        meal = self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        self.assertEqual((meal.eaters, meal.portion, meal.food, meal.water), (4, 0.5, 2, 2))
        # Eau épuisée : le repas suivant prend ce qui reste, la ration passe à « out » (part 0 : plus aucun repas).
        meal = self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR + 24}, 2)')
        self.assertEqual((meal.water, meal.wantWater), (1, 2))
        self.assertEqual(self.ev(f'{ST}.needs("{gid}").rationName'), 'out')
        self.assertTrue(any(e.kind == 'ration' and e.text.startswith('ration out') and e.day == 2
                            for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values()))
        meal = self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR + 48}, 3)')
        self.assertEqual((meal.portion, meal.food, meal.water), (0, 0, 0))
        self.check(gid)
        self.same(gid)

    def test_interrupted_application_is_resumed_without_duplicate(self):
        gid = self.filled()
        self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')                 # 4 prises
        self.assertEqual(self.ev(f'OFF_LOOT("{gid}", {{ food = 15 }})'), 3)   # puis 3 ajouts
        before = self.ev(f'(COUNT_TYPE("{gid}"))')
        # Arrêt brutal pendant l'application : le deuxième objet créé ne peut pas être rangé.
        self.run_lua('local Ctr = getmetatable(NEW_CONTAINER("x")) local add = Ctr.AddItem local n = 0 '
                     'function Ctr:AddItem(it) n = n + 1 if n == 2 then Ctr.AddItem = add error("crash") end '
                     'return add(self, it) end')
        ok, err = self.run_lua(f'return pcall({ST}.check, "{gid}", {{ force = true }})')
        self.assertFalse(ok)
        self.assertIn('crash', err)
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 7)                 # registre non écrit
        self.assertEqual(tuple(self.ev(f'COUNT_TYPE("{gid}")')), (before - 4 + 1, 1))   # un objet créé, marqué
        self.restart()                                                    # mémoire perdue, monde et registre gardés
        r = self.check(gid)
        self.assertEqual((r.applied.removed, r.applied.gone, r.applied.adopted, r.applied.made), (0, 4, 1, 2))
        self.assertEqual((r.missing, r.lost, r.added), (0, 0, 0))
        self.assertEqual(tuple(self.ev(f'COUNT_TYPE("{gid}")')), (before - 4 + 3, 0))   # ni perte ni doublon
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.same(gid)
        # Objets marqués du groupe : kit - 2 bouteilles prises + 3 créés (les 2 vivres pris viennent du frigo et du
        # congélateur, premiers dans l'ordre des conteneurs).
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT - 2 + 3)

    def test_change_added_during_application_stays_pending(self):
        gid = self.filled()
        self.assertEqual(self.ev(f'OFF_LOOT("{gid}", {{ food = 10 }})'), 2)
        # Une heure simulée tombe pendant l'application (premier objet créé) : un nouvel ajout s'inscrit au journal.
        self.run_lua(f'local mk = instanceItem local once = true instanceItem = function(t) '
                     f'if once then once = false OFF_LOOT("{gid}", {{ ammo = 5 }}) end return mk(t) end')
        r = self.check(gid)
        self.assertEqual((r.applied.made, r.missing, r.added), (2, 0, 0))
        ops = self.ev(f'LivingKnox.Groups.get("{gid}").stock.pend.ops')
        self.assertEqual([(o.o, o.c, o.u) for o in ops.values()], [('add', 'ammo', 3)])
        self.assertEqual(self.totals(gid)['ammo'], 2)
        r = self.check(gid)
        self.assertEqual(r.applied.made, 1)
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.assertEqual(self.ev('(COUNT_TYPE("' + gid + '", "Base.Bullets9mmBox"))')
                         + self.ev('(COUNT_TYPE("' + gid + '", "Base.ShotgunShellsBox"))'), 2)
        self.same(gid)

    def test_item_already_gone_is_not_counted_twice(self):
        gid = self.filled()
        self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        # Une bouteille prise hors écran a déjà quitté le monde (mangée par un repas réel, retirée d'une autre façon).
        self.run_lua(f'local p = LivingKnox.Groups.get("{gid}").stock.pend.ops local id '
                     f'for _, o in ipairs(p) do if o.c == "water" then id = o.i end end '
                     f'for _, c in ipairs(OWNED("{gid}")) do for _, it in ipairs(c.items.items) do '
                     f'if it.id == id then c:Remove(it) end end end')
        r = self.check(gid)
        self.assertEqual((r.applied.removed, r.applied.gone, r.missing, r.lost), (3, 1, 0, 0))
        self.same(gid)

    def test_pending_list_is_bounded_and_unknown_items_dropped(self):
        gid = self.filled()   # 25 objets suivis (kit et cuisine)
        tracked = len(list(self.ev(f'REF_IDS("{gid}")').values()))
        added = self.ev(f'OFF_LOOT("{gid}", {{ food = 5000 }})')
        self.assertEqual(added, self.ev(f'{ST}.MAX_ITEMS') - tracked)
        self.assertEqual(self.ev(f'OFF_LOOT("{gid}", {{ ammo = 50 }})'), 0)
        # Type non vanilla dans le journal : abandonné à l'application, avertissement.
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) local p = d.groups["{gid}"].stock.pend '
                     f'p.ops[1].t = "Mod.Thing" return true end))')
        r = self.check(gid)
        self.assertEqual((r.applied.dropped, r.applied.made), (1, added - 1))
        self.assertTrue(any('pending Mod.Thing not created: not a vanilla item (dropped)' in line for line in self.lk()))
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.same(gid)

    def test_malformed_pending_list_keeps_the_reference(self):
        gid = self.filled()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].stock.pend = '
                     f'{{ n = 1, ops = {{ {{ u = 5, o = "add", t = "Base.Rope", c = "materials" }} }} }} return true end))')
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        r = self.check(gid)
        self.assertEqual((r.action, r.applied), ('checked', None))
        self.assertEqual(self.ev(f'STOCKED("{gid}")'), SETTLERS_KIT)
        for bad in ('{ n = -1, ops = {} }', '{ n = 2, ops = { { u = 1, o = "add", t = "Base.Rope", c = "x" } } }',
                    '{ n = 2, ops = { { u = 1, o = "take", t = "Base.Rope", c = "materials" } } }',
                    '{ n = 2, ops = { { u = 1, o = "add", t = "Base.Rope", c = "materials" }, '
                    '{ u = 1, o = "add", t = "Base.Rope", c = "materials" } } }'):
            with self.subTest(bad=bad):
                self.assertFalse(self.ev(f'{ST}.validPend({bad})'))
        self.assertTrue(self.ev(f'{ST}.validPend({{ n = 3, ops = {{ {{ u = 3, o = "take", i = 5, t = "Base.Rope", '
                                f'c = "materials", k = "1,1,0,crate,1" }} }} }})'))

    def test_meal_before_a_real_meal_lookup(self):
        # Une prise du groupe (repas réel, entretien) applique d'abord les écarts : l'objet repéré existe encore.
        gid = self.filled()
        self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        found = self.ev(f'{ST}.findMeal("{gid}", "water")')
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.assertEqual(self.totals(gid)['water'], 1)
        self.assertEqual(found.c, 'water')
        self.same(gid)

    def test_simulation_drives_the_stock_reproducibly(self):
        gid = self.filled()
        out = self.run_lua(f'''
            local C = require("RadioSurvivor/RS_Codec")
            local S = LivingKnox.Simulation
            LivingKnox.Config.SIMULATION.EXPEDITIONS.DEPART_CHANCE = 1
            local d = LivingKnox.Groups.state.data
            d.groups["{gid}"].needs.food = 10
            d.simHour = 100
            local raw = C.encodeBytes(d)
            local a, b = C.decodeBytes(raw), C.decodeBytes(raw)
            S.advance(a, 172, nil)
            for h = 101, 172 do S.advance(b, h, nil) end
            local ea, eb = C.hexBytes(C.encodeBytes(a)), C.hexBytes(C.encodeBytes(b))
            local pend = a.groups["{gid}"].stock.pend
            local takes, adds = 0, 0
            for _, o in ipairs(pend and pend.ops or {{}}) do
                if o.o == "take" then takes = takes + 1 else adds = adds + 1 end
            end
            local loot = 0
            for _, e in ipairs(a.groups["{gid}"].log) do if e.kind == "return" then loot = loot + 1 end end
            LivingKnox.Groups.state.data = a
            assert(LivingKnox.Groups.save())
            return ea == eb, takes, adds, loot''')
        same, takes, adds, returns = out
        self.assertTrue(same)            # même registre, octet pour octet, heure par heure ou en un rattrapage
        self.assertGreater(takes, 0)     # trois repas quotidiens
        self.assertGreater(returns, 0)   # au moins une expédition abstraite revenue
        self.assertGreater(adds, 0)
        r = self.check(gid)
        self.assertEqual((r.missing, r.lost, r.added), (0, 0, 0))
        self.assertEqual(self.ev(f'PENDING("{gid}")'), 0)
        self.same(gid)

    def test_suite_passes_and_cleans_up(self):
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKOffscreenStock.lua')
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.offscreen_stock", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 1)
        self.assertEqual(len(list(self.ev('LivingKnox.Groups.list()').values())), 0)


class OffscreenMultiplayerTests(Base):
    mode = 'mp'

    def test_server_sends_removed_and_created_items(self):
        self.run_lua(HOUSE)
        self.run_lua(OFFSCREEN_DOUBLES)
        gid = self.group()
        self.minute()
        sent = self.ev('COUNT.sent')
        self.ev(f'OFF_MEAL("{gid}", {MEAL_HOUR})')
        self.ev(f'OFF_LOOT("{gid}", {{ food = 10 }})')
        r = self.check(gid)
        self.assertEqual((r.applied.removed, r.applied.made), (4, 2))
        self.assertEqual((self.ev('COUNT.removeSent'), self.ev('COUNT.sent') - sent), (4, 2))
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, ST))


if __name__ == '__main__':
    unittest.main()
