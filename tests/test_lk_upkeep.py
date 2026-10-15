"""Tests hors jeu de l'entretien du foyer des PNJ Living Knox (LK05-T10) : server/LivingKnox/LK_Upkeep.lua (tâches
refuel, repair, clean, glass ; lumières), branché dans LK_Routines.lua (comportement « chore »), matériaux pris par
LK_Stock.lua (findItem, findFluid, drawFluid, takeItem), et la suite en jeu lk.upkeep (dev/.../RST_LKUpkeep.lua).

    python RadioSurvivor/tests/test_lk_upkeep.py

Bancs :
- logique pure (plage éclairée) ;
- pile complète (groupe « deciders » de test_lk_routines.py dans la maison HOUSE, vrais LK_Homes et LK_Stock, foyer
  marqué aménagé sans pose par LivingKnox.Homes.skip, doublures de repas de test_lk_meals.py) : solo (marche simulée)
  et serveur dédié + deux clients.
Doublures ajoutées, relevées dans le Java 42.21.0 :
- FluidContainer.getAmount, adjustAmount (fixe la quantité, bornée à 0 : base api-42-21.md), Fluid.Petrol, Bleach,
  CleaningLiquid ; InventoryItem.hasTag(ItemTag) (InventoryItem.java:2667), isBroken (:2932) ; ItemTag.CLEAN_STAINS
  (ItemTag.java:77) ; ZomboidGlobals.CleanBloodBleachAmount (M/shared/defines.lua:47) ; sendItemStats (LuaManager.java
  :3758, envoi par le serveur seulement) ;
- IsoGenerator : getFuel, getMaxFuel = 10, setFuel borné 0..10, isActivated, getCondition, setCondition borné 0..100,
  synchronisés par le Java sur un serveur (IsoGenerator.java:436-511) ;
- IsoGridSquare.haveBlood, removeBlood (taches de la case et du sol à une case autour, paquet RemoveBlood sur un
  serveur : IsoGridSquare.java:4657, 4818-4840), removeGrime, getBrokenGlass (:2657), transmitRemoveItemFromSquare
  (:5072) ; IsoRoom.getLightSwitches (IsoRoom.java:474) ; IsoLightSwitch isActivated, getCanBeModified, getUseBattery,
  canSwitchLight, setActive (toute la pièce, IsoLightSwitch.java:449-530).
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (chaque effet appliqué une fois, quantités exactes,
rien hors du foyer, rien chez un client, mêmes consignes chez deux clients). Le vrai Java se vérifie en jeu (suite
lk.upkeep, puis séance MP).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_meals import MealStack  # noqa: E402
from test_lk_routines import TIME_OF_DAY  # noqa: E402

U = 'LivingKnox.Upkeep'
R = 'LivingKnox.Routines'
ST = 'LivingKnox.Stock'
ROOT = Path(__file__).resolve().parents[1]
UPKEEP = 'server/LivingKnox/LK_Upkeep.lua'
SUITE = 'shared/RST/suites/RST_LKUpkeep.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

UPKEEP_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local FluidCls = getmetatable(Fluid.Water)
for _, n in ipairs({ 'Petrol', 'Bleach', 'CleaningLiquid' }) do Fluid[n] = setmetatable({ name = n }, FluidCls) end
local FC = C.FluidContainer
function FC:getAmount() return self.amount or 0 end
function FC:adjustAmount(a)
    H.num(a, 'adjustAmount')
    self.amount = math.max(0, a)
end
local Item = C.InventoryItem
function Item:hasTag(tag)
    if type(tag) ~= 'table' or tag.name == nil then error('No implementation found for hasTag', 2) end
    return self.tags ~= nil and self.tags[tag.name] == true
end
function Item:isBroken() return self.broken == true end
ItemTag = { CLEAN_STAINS = { name = 'CleanStains' } }
ZomboidGlobals = { CleanBloodBleachAmount = 0.24999 }
UPK = { stats = 0, fuelSyncs = 0, condSyncs = 0, blood = 0, bloodSent = 0, grime = 0, removed = 0, lightSyncs = 0,
    events = 0 }
UPK_STATS = {}
sendItemStats = function(it)
    if getmetatable(it) == nil then error('No implementation found for sendItemStats', 2) end
    if isServer() then
        UPK.stats = UPK.stats + 1
        UPK_STATS[#UPK_STATS + 1] = tostring(it.id) .. ':' .. string.format('%.3f', it.fc and it.fc.amount or -1)
    end
end
Events.OnObjectAboutToBeRemoved.Add(function() UPK.events = UPK.events + 1 end)
-- Objet d'entretien : récipient (fluid, amount) ou objet simple (cat, tags).
function UPK_ITEM(t, o)
    o = o or {}
    MEAL_NEXT = MEAL_NEXT + 3
    local it = setmetatable({ id = MEAL_NEXT, t = t, cat = o.cat or 'Household', tags = o.tags, broken = o.broken }, Item)
    if o.fluid ~= nil then it.fc = setmetatable({ fluid = Fluid[o.fluid], amount = o.amount or 1 }, FC) end
    return it
end
-- Générateur posé sur une case (case pleine).
local Gen = H.class('IsoGenerator', C.IsoObject)
function Gen:getSprite() return nil end
function Gen:getFuel() return self.fuel end
function Gen:getMaxFuel() return 10 end
function Gen:setFuel(f)
    H.num(f, 'setFuel')
    self.fuel = math.max(0, math.min(f, 10))
    if isServer() then UPK.fuelSyncs = UPK.fuelSyncs + 1 end
end
function Gen:isActivated() return self.on == true end
function Gen:getCondition() return self.cond end
function Gen:setCondition(c)
    H.num(c, 'setCondition')
    self.cond = math.max(0, math.min(math.floor(c), 100))
    if isServer() then UPK.condSyncs = UPK.condSyncs + 1 end
end
-- owner : identifiant du groupe dont le générateur porte la marque (LK05-T19, LivingKnox.Homes.markGenerator), ou nil
-- (générateur d'un joueur : aucune marque).
function UPK_GEN(x, y, fuel, cond, on, owner)
    local o = setmetatable({ fuel = fuel, cond = cond, on = on }, Gen)
    if owner ~= nil then LivingKnox.Homes.markGenerator(o, owner) end
    H.addObject(x, y, 0, o)
    H.square(x, y, 0).blocked = true
    return o
end
-- Sang, saleté et verre brisé.
local Sq = C.IsoGridSquare
function Sq:haveBlood() return self.blood == true end
function Sq:removeBlood(remote, onlyWall)
    if type(remote) ~= 'boolean' or type(onlyWall) ~= 'boolean' then error('No implementation found for removeBlood', 2) end
    for dx = -1, 1 do
        for dy = -1, 1 do H.square(self.x + dx, self.y + dy, self.z).blood = nil end
    end
    UPK.blood = UPK.blood + 1
    if isServer() then UPK.bloodSent = UPK.bloodSent + 1 end
end
function Sq:removeGrime() UPK.grime = UPK.grime + 1 end
local Glass = H.class('IsoBrokenGlass', C.IsoObject)
function Glass:getSprite() return nil end
function Sq:getBrokenGlass()
    for _, o in ipairs(self.objects.items) do
        if getmetatable(o) == Glass then return o end
    end
    return nil
end
function Sq:transmitRemoveItemFromSquare(o)
    if H.listRemove(self.objects, o) then
        UPK.removed = UPK.removed + 1
        return 0
    end
    return -1
end
function UPK_GLASS(x, y) return H.addObject(x, y, 0, setmetatable({}, Glass)) end
-- Pièces et interrupteurs : rectangles UPK_ROOMS { x1, y1, x2, y2, nom } (dans le bâtiment) ; une pièce = une table
-- stable avec sa liste d'interrupteurs.
UPK_ROOMS = {}
local Room = H.class('IsoRoom')
function Room:getLightSwitches() return self.switches end
local rooms = {}
function Sq:getRoom()
    for _, r in ipairs(UPK_ROOMS) do
        if self.z == 0 and self.x >= r[1] and self.x <= r[3] and self.y >= r[2] and self.y <= r[4] then
            rooms[r[5]] = rooms[r[5]] or setmetatable({ name = r[5], switches = H.list() }, Room)
            return rooms[r[5]]
        end
    end
    return nil
end
local LS = H.class('IsoLightSwitch', C.IsoObject)
function LS:getSprite() return nil end
function LS:isActivated() return self.on == true end
function LS:getCanBeModified() return self.mod == true end
function LS:getUseBattery() return self.battery == true end
function LS:canSwitchLight() return self.powered == true end
function LS:setActive(b)
    if type(b) ~= 'boolean' then error('No implementation found for setActive', 2) end
    if b == self.on then return self.on end
    if self:canSwitchLight() then
        for _, o in ipairs(self.room.switches.items) do o.on = b end
        if isServer() then UPK.lightSyncs = UPK.lightSyncs + 1 end
    end
    return self.on == true
end
function UPK_SWITCH(x, y, o)
    local sq = H.square(x, y, 0)
    local room = assert(sq:getRoom(), 'no room at ' .. x .. ',' .. y)
    local ls = setmetatable({ room = room, powered = o.powered, mod = o.mod, battery = o.battery, on = o.on }, LS)
    H.addObject(x, y, 0, ls)
    room.switches:add(ls)
    return ls
end
function UPK_ROOM(x, y) return H.square(x, y, 0):getRoom() end
'''

# Caisse de l'atelier (112,112 : la caisse des repas, garnie en plus) : bidon d'essence (4 l), pièce électronique,
# eau de Javel (1 l), torchon ; générateur à l'ouest de la maison, dans la zone du foyer.
SUPPLIES = r'''
CAN = UPK_ITEM('Base.PetrolCan', { fluid = 'Petrol', amount = 4, cat = 'VehicleMaintenance' })
SCRAP = UPK_ITEM('Base.ElectronicsScrap', { cat = 'Electronics' })
BLEACH = UPK_ITEM('Base.Bleach', { fluid = 'Bleach', amount = 1 })
CLOTH = UPK_ITEM('Base.DishCloth', { tags = { CleanStains = true } })
for _, it in ipairs({ CAN, SCRAP, BLEACH, CLOTH }) do PANTRY.container:AddItem(it) end
'''


class PureUpkeepTests(PureBase):
    def setUp(self):
        super().setUp()
        self.h.load('solo', 'server/LivingKnox/LK_Homes.lua')
        self.h.load('solo', 'server/LivingKnox/LK_Stock.lua')
        self.h.load('solo', UPKEEP)

    def test_lit_hours_wrap_around_midnight(self):
        lit = [h for h in range(24) if self.ev(f'{U}.dark({h})')]
        self.assertEqual(lit, [0, 1, 2, 3, 4, 5, 6, 19, 20, 21, 22, 23])
        self.assertEqual(self.ev(f'{U}.GESTURE.refuel'), 'kneel')
        for kind in lua_list(self.ev(f'{U}.JOBS')):
            self.assertTrue(self.ev(f'{R}.GESTURES[{U}.GESTURE["{kind}"]]'), kind)   # remis debout par leave


class UpkeepStack(MealStack):
    """Pile des repas + LK_Upkeep et ses doublures ; caisse garnie de matériaux d'entretien."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            h.load(m, UPKEEP)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, UPKEEP_DOUBLES)
        h.load(srv, SUPPLIES)
        return h

    def mk(self):
        gid = super().mk()
        self.run_lua(f'{U}.reset() for k in pairs({U}.stats) do {U}.stats[k] = 0 end')
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end')
        return gid

    def jobs(self, gid):
        out = self.run_lua(f'local j, why = {U}.jobs("{gid}", LivingKnox.Groups.get("{gid}")) if j == nil then '
                           'return why end local out = {} for i, e in ipairs(j) do out[i] = e.key end return out')
        return out if isinstance(out, str) else lua_list(out)

    def stat(self, name):
        return self.ev(f'{U}.stats.{name}')

    def work(self, cond, seconds=150):
        """Journée de corvées (11 h) : passe jusqu'à cond()."""
        return self.run_until(cond, seconds=seconds)


class JobSurveyTests(UpkeepStack):
    mode = 'solo'

    def test_jobs_listed_only_with_materials_and_only_in_the_home(self):
        gid = self.mk()
        self.assertEqual(self.jobs(gid), [])
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 40, false, "{gid}") UPK_GLASS(109, 113) '
                     'HARNESS.square(108, 112, 0).blood = true')
        self.assertEqual(self.jobs(gid), ['refuel 107,112,0', 'repair 107,112,0', 'clean 108,112,0',
                                          'glass 109,113,0'])
        # Sans essence, sans pièce, sans outil propre : seulement le verre.
        self.run_lua('CAN.fc.amount = 0 HARNESS.listRemove(PANTRY.container.items, SCRAP) CLOTH.broken = true')
        self.assertEqual(self.jobs(gid), ['glass 109,113,0'])
        self.run_lua('CAN.fc.amount = 4 PANTRY.container:AddItem(SCRAP) CLOTH.broken = false BLEACH.fc.amount = 0.2')
        self.assertEqual(self.jobs(gid), ['refuel 107,112,0', 'repair 107,112,0', 'glass 109,113,0'])  # Javel < dose
        # Générateur en marche ou bien tenu : pas de réparation ; plein : pas de plein.
        self.run_lua('GEN.on = true')
        self.assertEqual(self.jobs(gid)[:2], ['refuel 107,112,0', 'glass 109,113,0'])
        self.run_lua('GEN.on = false GEN.fuel = 5 GEN.cond = 60')
        self.assertEqual(self.jobs(gid), ['glass 109,113,0'])

    def test_glass_kept_when_blood_fills_the_job_list(self):
        """Campagne MP 2026-10-14 : taches de sang des combats precedents partout dans la maison, MAX_JOBS rempli de
        "clean" et verre jamais propose."""
        gid = self.mk()
        stains = ' '.join(f'HARNESS.square({x}, {y}, 0).blood = true' for x in (106, 107, 108) for y in (110, 111, 112))
        self.run_lua('UPK_GLASS(109, 113) ' + stains)
        jobs = self.jobs(gid)
        self.assertEqual(len(jobs), self.ev(f'{U}.CFG.MAX_JOBS'), jobs)
        self.assertIn('glass 109,113,0', jobs)
        self.assertEqual(jobs[-1], 'glass 109,113,0')                 # ordre de JOBS garde
        self.assertEqual(sum(j.startswith('clean ') for j in jobs), len(jobs) - 1)

    def test_nothing_outside_the_home(self):
        gid = self.mk()
        # Hors du bâtiment (sang, verre) ; générateur sur le bord de la zone ou au-delà ; autre niveau.
        self.run_lua('HARNESS.square(117, 110, 0).blood = true UPK_GLASS(117, 111) '
                     f'UPK_GEN(120, 110, 1, 30, false, "{gid}") UPK_GEN(125, 110, 1, 30, false, "{gid}") '
                     'HARNESS.square(108, 112, 1).blood = true')
        self.assertEqual(self.jobs(gid), [])
        self.assertEqual(self.jobs('no-such'), 'no home')


    def test_only_the_generators_of_the_group_are_listed(self):
        """LK05-T19 (decision du 2026-10-14) : generateur d'un joueur (aucune marque) ou d'un autre groupe dans la zone :
        jamais une tache, meme vide et use ; celui du groupe, si."""
        gid = self.mk()
        self.run_lua('PLAYER_GEN = UPK_GEN(117, 112, 0, 10, false) INSIDE_GEN = UPK_GEN(112, 108, 1, 20, false) '
                     'OTHER_GEN = UPK_GEN(113, 108, 1, 20, false, "grp-other")')
        self.assertEqual(self.jobs(gid), [])
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 40, false, "{gid}")')
        self.assertEqual(self.jobs(gid), ['refuel 107,112,0', 'repair 107,112,0'])
        # Marque lue a chaque releve : le meme generateur marque pour un autre groupe n'est plus le sien.
        self.run_lua('LivingKnox.Homes.markGenerator(GEN, "grp-other")')
        self.assertEqual(self.jobs(gid), [])
        self.assertFalse(self.ev(f'LivingKnox.Homes.groupGenerator(PLAYER_GEN, "{gid}")'))
        self.assertFalse(self.ev('LivingKnox.Homes.groupGenerator(GEN, nil)'))
        self.assertFalse(self.ev(f'LivingKnox.Homes.groupGenerator(HARNESS.square(108, 112, 0), "{gid}")'))


class SoloUpkeepTests(UpkeepStack):
    mode = 'solo'

    def test_player_generator_nearby_is_neither_refuelled_nor_repaired(self):
        """LK05-T19 : generateur du groupe rempli et repare ; generateur d'un joueur a proximite (dans la maison et dans
        le jardin), vide et use, intact ; verre ramasse comme avant (autres corvees inchangees)."""
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 40, false, "{gid}") PLAYER_GEN = UPK_GEN(117, 112, 0, 10, false) '
                     'HOUSE_GEN = UPK_GEN(112, 108, 1, 20, false) UPK_GLASS(109, 113) CAN.fc.amount = 20')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('refuels') >= 1 and self.stat('repairs') >= 1
                                  and self.stat('glass') >= 1),
                        (self.stat('refuels'), self.stat('repairs'), self.stat('glass'), self.lk()[-8:]))
        for _ in range(40):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual((self.stat('refuels'), self.stat('repairs'), self.stat('glass')), (1, 1, 1))
        self.assertAlmostEqual(self.ev('GEN.fuel'), 10.0, places=6)
        self.assertEqual(self.ev('GEN.cond'), 44)
        self.assertEqual((self.ev('PLAYER_GEN.fuel'), self.ev('PLAYER_GEN.cond')), (0, 10))
        self.assertEqual((self.ev('HOUSE_GEN.fuel'), self.ev('HOUSE_GEN.cond')), (1, 20))
        self.assertAlmostEqual(self.ev('CAN.fc.amount'), 12.0, places=6)            # 8 l pour le seul generateur du groupe
        self.assertFalse(self.ev('PANTRY.container:containsID(SCRAP.id)'))          # la seule piece : au groupe
        self.assertFalse(any('117,112' in line or '112,108' in line for line in self.lk() if 'upkeep' in line),
                         self.lk()[-10:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_generator_swapped_for_an_unmarked_one_before_the_effect_is_left_alone(self):
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 90, false, "{gid}")')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.run_lua(
            f'for _, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.phase == "work" then return true end '
            'end return false')))
        # Un joueur reprend le generateur et en pose un autre (sans marque : setInfoFromItem ne recopie pas la ModData).
        self.run_lua('HARNESS.listRemove(HARNESS.square(107, 112, 0).objects, GEN) '
                     'NEW_GEN = UPK_GEN(107, 112, 2, 90, false)')
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.stat('refuels'), 0)
        self.assertGreaterEqual(self.stat('skipped'), 1)
        self.assertAlmostEqual(self.ev('NEW_GEN.fuel'), 2.0, places=6)
        self.assertAlmostEqual(self.ev('CAN.fc.amount'), 4.0, places=6)
        self.assertEqual(self.h.errors('solo'), [])

    def test_generator_refuelled_with_the_exact_petrol_and_repaired_with_one_part(self):
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 40, false, "{gid}")')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('refuels') >= 1 and self.stat('repairs') >= 1),
                        (self.stat('refuels'), self.stat('repairs'), self.lk()[-8:]))
        self.assertAlmostEqual(self.ev('GEN.fuel'), 6.0, places=6)                # 2 + les 4 l du bidon
        self.assertAlmostEqual(self.ev('CAN.fc.amount'), 0.0, places=6)
        self.assertEqual(self.ev('GEN.cond'), 44)                                   # +4 (une pièce)
        self.assertFalse(self.ev('PANTRY.container:containsID(SCRAP.id)'))
        self.assertTrue(self.ev('PANTRY.container:containsID(CAN.id)'))             # bidon vide gardé
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual((self.ev('UPK.stats'), self.ev('UPK.fuelSyncs')), (0, 0))  # solo : rien à envoyer
        # Plus rien à faire : plein au-dessus du seuil, plus de pièce ; jamais deux fois.
        for _ in range(40):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual((self.stat('refuels'), self.stat('repairs')), (1, 1))
        self.assertAlmostEqual(self.ev('GEN.fuel'), 6.0, places=6)
        log = [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'upkeep']
        self.assertEqual(len(log), 2, log)
        self.assertEqual(sorted(t.split(' (')[0] for t in log),
                         ['generator at 107,112 refuelled 2.00 -> 6.00 l', 'generator at 107,112 repaired 40 -> 44'])
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_big_can_fills_only_the_room_left(self):
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 1.5, 90, true, "{gid}") CAN.fc.amount = 20')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('refuels') >= 1))
        self.assertAlmostEqual(self.ev('GEN.fuel'), 10.0, places=6)
        self.assertAlmostEqual(self.ev('CAN.fc.amount'), 11.5, places=6)            # 20 - 8,5 exactement
        self.assertEqual(self.stat('repairs'), 0)                                     # en marche, bien tenu
        self.assertEqual(self.h.errors('solo'), [])

    def test_blood_cleaned_with_one_dose_and_glass_removed_once(self):
        gid = self.mk()
        self.run_lua('HARNESS.square(108, 112, 0).blood = true UPK_GLASS(109, 113)')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('cleaned') >= 1 and self.stat('glass') >= 1),
                        (self.stat('cleaned'), self.stat('glass'), self.jobs(gid)))
        self.assertFalse(self.ev('HARNESS.square(108, 112, 0).blood == true'))
        self.assertIsNone(self.ev('HARNESS.square(109, 113, 0):getBrokenGlass()'))
        self.assertAlmostEqual(self.ev('BLEACH.fc.amount'), 1 - 0.24999, places=6)
        self.assertTrue(self.ev('PANTRY.container:containsID(CLOTH.id)'))           # l'outil reste
        self.assertEqual((self.ev('UPK.blood'), self.ev('UPK.grime'), self.ev('UPK.removed'), self.ev('UPK.events')),
                         (1, 1, 1, 1))
        for _ in range(30):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual((self.stat('cleaned'), self.stat('glass'), self.ev('UPK.blood')), (1, 1, 1))
        self.assertEqual(self.h.errors('solo'), [])

    def test_job_interrupted_before_the_effect_is_not_applied_then_done_once(self):
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 90, false, "{gid}")')
        self.jump_to(11)
        holder = lambda: self.run_lua(  # noqa: E731
            f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.phase == "work" then '
            'return id end end return nil')
        self.assertTrue(self.work(lambda: holder() is not None))
        npc = holder()
        x, y = self.run_lua(f'local z = LivingKnox.Bodies.find("{npc}") return z:getX(), z:getY()')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 960)')
        self.dpass(2)
        self.assertEqual(self.stat('refuels'), 0)                                     # rien versé
        self.assertAlmostEqual(self.ev('GEN.fuel'), 2.0, places=6)
        self.assertEqual(self.run_lua(f'local n = 0 for _ in pairs({U}.state.claims) do n = n + 1 end return n'), 0)
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)
        self.assertTrue(self.work(lambda: self.stat('refuels') >= 1))
        for _ in range(20):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.stat('refuels'), 1)
        self.assertAlmostEqual(self.ev('GEN.fuel'), 6.0, places=6)
        self.assertEqual(self.h.errors('solo'), [])

    def test_material_gone_before_the_effect_means_nothing_done(self):
        gid = self.mk()
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 90, false, "{gid}")')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.run_lua(
            f'for _, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.phase == "work" then return true end '
            'end return false')))
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, CAN)')               # bidon emporté entre-temps
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.stat('refuels'), 0)
        self.assertGreaterEqual(self.stat('skipped'), 1)
        self.assertAlmostEqual(self.ev('GEN.fuel'), 2.0, places=6)
        self.assertEqual(self.h.errors('solo'), [])


class LightTests(UpkeepStack):
    mode = 'solo'

    def setup_rooms(self):
        self.run_lua('UPK_ROOMS = { { 106, 106, 109, 109, "den" }, { 110, 106, 114, 114, "hall" }, '
                     '{ 106, 110, 108, 113, "closet" }, { 117, 106, 119, 109, "shed" } } '
                     'DEN = UPK_SWITCH(106, 106, { powered = true }) DEN2 = UPK_SWITCH(109, 106, { powered = true }) '
                     'HALL = UPK_SWITCH(114, 106, { powered = true }) LAMP = UPK_SWITCH(106, 111, { powered = true, '
                     'mod = true, battery = true }) SHED = UPK_SWITCH(117, 106, { powered = true })')

    def place(self, gid, mid, x, y):
        self.run_lua(f'HARNESS.place(MAT_BODY("{gid}", "{mid}"), {x}.5, {y}.5, 0)')

    def test_entering_a_powered_room_at_night_lights_it_once(self):
        gid = self.mk()
        self.setup_rooms()
        self.jump_to(20)
        for mid in ('m-1', 'm-2', 'm-3'):
            self.place(gid, mid, 112, 112)                                            # tous dans le hall
        self.assertEqual(self.ev(f'{U}.lights()'), 1)                                 # hall
        self.assertTrue(self.ev('HALL.on'))
        self.assertEqual(self.ev(f'{U}.lights()'), 0)                                 # déjà dedans : pas d'entrée
        self.run_lua('HALL.on = false')
        self.assertEqual(self.ev(f'{U}.lights()'), 0)                                 # éteinte par un joueur : gardée
        self.place(gid, 'm-2', 107, 107)
        self.assertEqual(self.ev(f'{U}.lights()'), 1)                                 # le premier allume la pièce
        self.assertTrue(self.ev('DEN.on and DEN2.on'))
        self.place(gid, 'm-2', 112, 112)
        self.assertEqual(self.ev(f'{U}.lights()'), 1)                                 # retour au hall : rallumé
        self.run_lua('DEN.on, DEN2.on = false, false DEN.powered, DEN2.powered = false, false')
        self.place(gid, 'm-2', 107, 107)
        self.assertEqual(self.ev(f'{U}.lights()'), 0)                                 # sans courant
        self.assertFalse(self.ev('DEN.on'))
        # Lampe sur pile du cagibi écartée ; hors du bâtiment du foyer (remise à 117) : jamais.
        self.place(gid, 'm-1', 107, 112)
        self.assertEqual(self.ev(f'{U}.lights()'), 0)
        self.assertFalse(self.ev('LAMP.on == true'))
        self.place(gid, 'm-3', 117, 107)
        self.assertEqual(self.ev(f'{U}.lights()'), 0)
        self.assertFalse(self.ev('SHED.on == true'))
        # Le jour : rien, mémoire effacée ; le soir suivant, la pièce où l'on se tient compte comme une entrée.
        self.place(gid, 'm-1', 112, 112)
        self.run_lua('HALL.on = false')
        self.jump_to(10)
        self.assertEqual(self.ev(f'{U}.lights()'), 0)
        self.assertFalse(self.ev('HALL.on'))
        self.jump_to(19)
        self.assertEqual(self.ev(f'{U}.lights()'), 1)
        self.assertEqual(self.ev(f'{U}.stats.lights'), 4)
        self.assertEqual(self.h.errors('solo'), [])

    def test_lights_follow_the_minute_event(self):
        gid = self.mk()
        self.setup_rooms()
        self.jump_to(21)
        self.place(gid, 'm-1', 112, 112)
        self.h.advance(1)
        self.assertTrue(self.ev('HALL.on'))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerUpkeepTests(UpkeepStack):
    """Serveur dédié + deux clients : effets appliqués par le serveur, envoyés une fois ; mêmes consignes et gestes chez
    A et B ; aucun entretien chez un client."""

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

    def test_server_refuels_once_and_both_clients_see_the_same_work(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Upkeep'))
        self.run_lua(f'GEN = UPK_GEN(107, 112, 2, 90, false, "{gid}")')
        self.jump_to(11)
        seen = []
        npc = None
        for _ in range(120):
            # Banc MP : corps tenus par le serveur (aucun exécutant) ; arrivée posée à la place, regard rapporté fini.
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if npc is None:
                npc = self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" then return id end '
                                   'end return nil')
            if npc is not None:
                v = self.view(npc)
                self.assertEqual(v['A'], v['B'])
                seen.append(v['A'])
            if self.stat('refuels') >= 1:
                break
        self.assertEqual(self.stat('refuels'), 1, seen[-5:])
        self.assertAlmostEqual(self.ev('GEN.fuel'), 6.0, places=6)
        self.assertEqual(lua_list(self.ev('UPK_STATS')), [f'{self.ev("CAN.id")}:0.000'])   # un seul envoi du bidon
        self.assertEqual(self.ev('UPK.fuelSyncs'), 1)
        self.assertTrue(any(s.endswith('|kneel') for s in seen), seen)
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])

    def test_lights_and_glass_sent_from_the_server(self):
        gid = self.mk()
        self.run_lua('UPK_ROOMS = { { 110, 106, 114, 114, "hall" } } HALL = UPK_SWITCH(114, 106, { powered = true })')
        self.jump_to(21)
        self.run_lua(f'HARNESS.place(MAT_BODY("{gid}", "m-1"), 112.5, 112.5, 0)')
        self.assertEqual(self.ev(f'{U}.lights()'), 1)
        self.assertEqual(self.ev('UPK.lightSyncs'), 1)
        self.assertEqual(self.h.errors('server'), [])


class SuiteTests(UpkeepStack):
    mode = 'solo'

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def run_suite(self, before=None):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        # Fixture de la suite : objets d'entretien, générateur posé par IsoGenerator.new, verre, tache de sang.
        self.h.load('solo', r'''
            HARNESS.listRemove(PANTRY.container.items, CAN) HARNESS.listRemove(PANTRY.container.items, SCRAP)
            HARNESS.listRemove(PANTRY.container.items, BLEACH) HARNESS.listRemove(PANTRY.container.items, CLOTH)
            for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end
            local FC = HARNESS.classes.FluidContainer
            function FC:Empty() self.fluid, self.amount = nil, 0 end
            function FC:addFluid(f, a) self.fluid, self.amount = f, a end
            local Item = HARNESS.classes.InventoryItem
            function Item:setCondition(c) self.cond = c end
            function Item:getModData() self.md = self.md or {} return self.md end
            local mk = instanceItem
            instanceItem = function(t)
                if t == 'Base.PetrolCan' or t == 'Base.Bleach' then return UPK_ITEM(t, { fluid = 'Water', amount = 0 }) end
                if t == 'Base.ElectronicsScrap' then return UPK_ITEM(t, { cat = 'Electronics' }) end
                if t == 'Base.DishCloth' then return UPK_ITEM(t, { tags = { CleanStains = true } }) end
                if t == 'Base.Generator' then return UPK_ITEM(t, { cat = 'Electronics' }) end
                return mk(t)
            end
            local Gen = HARNESS.classes.IsoGenerator
            function Gen:getObjectIndex() return self.square.objects:indexOf(self) end
            IsoGenerator = { new = function(item, cell, sq)
                local g = UPK_GEN(sq:getX(), sq:getY(), item:getModData().fuel, item.cond, false)
                return g
            end }
            local Sq = HARNESS.classes.IsoGridSquare
            function Sq:addBrokenGlass() if self:getBrokenGlass() == nil then UPK_GLASS(self.x, self.y) end
                return self:getBrokenGlass() end
            local Chunk = HARNESS.class('IsoChunk')
            function Chunk:addBloodSplat(x, y, z, kind)
                HARNESS.square(math.floor(x), math.floor(y), math.floor(z)).blood = true
            end
            function Sq:getChunk() return setmetatable({}, Chunk) end
        ''')
        if before:
            self.run_lua(before)
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.upkeep", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(9000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 10 == 9:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 2, results)
        self.assertEqual(results[0][1], 'PASS', (results, [x for x in self.h.logs('solo') if 'LKU' in x or 'ERROR' in x][-20:]))
        self.assertEqual(results[1][1], 'SKIP', results)                              # aucune pièce doublée
        return self.h.logs('solo')

    def test_suite_lk_upkeep_passes_on_the_doubles(self):
        logs = self.run_suite()
        for text in ('[LKU] measure fixture of ', '[LKU] measure done: fuel 2.00 -> 6.00, can 0.00 l, condition 50 -> 54',
                     '[LKU] measure unmarked generator: fuel 0.00 -> 0.00, condition 30 -> 30'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_clears_older_glass_before_its_fixture(self):
        # Campagne solo du 2026-10-15 : un verre plus ancien de la maison (fenêtre cassée par les combats d'une
        # suite précédente) était ramassé d'abord, « glass removals » atteint, le verre de la suite encore là.
        logs = self.run_suite('OLD_GLASS = UPK_GLASS(106, 113)')
        self.assertTrue(any('[LKU] measure 1 older broken glass removed before the fixture' in line for line in logs))
        self.assertTrue(any('[LKU] measure done: ' in line and 'glass false' in line for line in logs))
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_is_listed_with_its_tags(self):
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.upkeep", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.upkeep'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)

    def test_module_source_is_kahlua_safe(self):
        path = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / UPKEEP
        raw = path.read_text(encoding='utf-8')
        code = '\n'.join(line.split('--', 1)[0] for line in raw.splitlines())
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character in the code')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main(verbosity=1)
