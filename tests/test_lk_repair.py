"""Tests hors jeu de l'entretien et de la réparation des défenses du foyer après une attaque (LK14-T06) :
server/LivingKnox/LK_Fortify.lua (relevé des barricades et ouvrages abîmés, chantiers « repair » du plan, ordre après
une attaque marquée par LivingKnox.Defense.after, Fortify.repair, besoin de matériaux Fortify.needOf et journal du
groupe), et la suite en jeu lk.repair (dev/.../RST_LKRepair.lua).

    python RadioSurvivor/tests/test_lk_repair.py

Banc : piles de test_lk_barricade.py (maison HOUSE 105..115, foyer 110,110, fenêtres nord 112,105 et ouest 105,110,
entrée sud 110,116, caisse : marteau, 8 planches, une boîte de clous) et de test_lk_walls.py (entrée seule, pourtour
de murs). LK_Defense n'est pas chargé : la marque d'après l'attaque est posée par une doublure de
LivingKnox.Defense.after (même forme que LK_Defense : { id, minute, minutes, wounded, why }).
Doublures ajoutées, relevées dans le Java et le Lua vanilla 42.21.0 :
- IsoBarricade.getThumpCondition (état de la planche extérieure, J/iso/objects/IsoBarricade.java:536-549 ; planches de
  la doublure = état sur 10, comme Base.Plank ConditionMax 10), removePlank(nil) (planche extérieure retirée et rendue
  avec son état ; dernière planche : barricade retirée de sa case, transmitRemoveItemFromSquare sur un serveur,
  :110-136) ;
- InventoryItem.getCondition / getConditionMax ; ItemTag.SAW (tag base:saw de Base.Saw) ;
- IsoThumpable.setHealth sur un objet posé : sync() envoyé par le serveur seul (IsoThumpable.java:288-297) ;
- sendAddItemToContainer compté sur le serveur.
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (repérage, ordre, matériaux retirés une seule fois,
planche abîmée rendue, santé remise, besoin noté une fois par attaque, transmissions faites par le serveur seul).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_barricade import BarricadeStack, F, ST  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_walls import WallStack  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITE = 'shared/RST/suites/RST_LKRepair.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

REPAIR_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Bar = IsoBarricade
-- Barricade : lien vers son ouverture (pour l'effacer quand sa dernière planche part).
local add = Bar.AddBarricadeToObject
function Bar.AddBarricadeToObject(o, addOpposite)
    local b = add(o, addOpposite)
    if b ~= nil then b.owner, b.field = o, addOpposite and 'opp' or 'own' end
    return b
end
function Bar:removePlank(chr)
    if chr ~= nil then error('unexpected character', 2) end
    local n = #self.planks
    if n == 0 then return nil end
    local cond = self.planks[n]
    table.remove(self.planks, n)
    local it = BAR_ITEM('Base.Plank', math.max(cond, 1))
    if #self.planks == 0 then
        local sq = self:getSquare()
        if sq ~= nil then H.listRemove(sq.objects, self) end
        if self.owner ~= nil then self.owner[self.field] = nil end
        if isServer() then BAR_SENT[#BAR_SENT + 1] = 'remove ' .. self.key end
    end
    return it
end
-- Barricade complète posée pour l'essai : n planches d'état 10, la dernière (extérieure) d'état outer.
function FULL(o, opposite, n, outer)
    local b = Bar.AddBarricadeToObject(o, opposite)
    for i = 1, n do b.planks[i] = (i == n) and outer or 10 end
    return b
end
local Item = C.InventoryItem
function Item:getCondition() return self.cond or 10 end
function Item:getConditionMax() return 10 end
ItemTag.SAW = ItemTag.SAW or { name = 'base:saw' }
function SAW_ITEM()
    local it = BAR_ITEM('Base.Saw')
    it.tags = { ['base:saw'] = true }
    return it
end
ADDED_SENT = 0
sendAddItemToContainer = function(c, it)
    if c == nil or it == nil then error('No implementation found for sendAddItemToContainer', 2) end
    if isServer() then ADDED_SENT = ADDED_SENT + 1 end
end
-- Marque d'après l'attaque (forme de LK_Defense.after).
function MARK(gid, id)
    local D = LivingKnox.Defense or {}
    LivingKnox.Defense = D
    D.state = D.state or {}
    D.state.after = D.state.after or {}
    if D.after == nil then D.after = function(g) return D.state.after[g] end end
    D.state.after[gid] = { id = id, minute = LivingKnox.Decisions.currentMinute(), minutes = 3, wounded = {},
        why = 'test' }
end
-- Entrées « shortage » du journal du groupe.
function SHORTAGES(gid)
    local out = {}
    for _, e in ipairs(LivingKnox.Groups.get(gid).log) do
        if e.kind == 'shortage' then out[#out + 1] = e.text end
    end
    return out
end
-- Planches de la caisse : états.
function PLANK_CONDS()
    local out = {}
    for _, it in ipairs(PANTRY.container.items.items) do
        if it.t == 'Base.Plank' then out[#out + 1] = it.cond or 10 end
    end
    table.sort(out)
    return out
end
'''

# Ouvrages posés : setHealth d'un objet posé synchronisé par le serveur (IsoThumpable.java:288-297).
WALL_REPAIR_DOUBLES = r'''
local T = HARNESS.classes.IsoThumpable
WALL.syncs = 0
function T:setHealth(h)
    if h == self.health then return end
    self.health = h
    if self.placed and isServer() then
        WALL.syncs = WALL.syncs + 1
        WALL_SENT[#WALL_SENT + 1] = 'sync ' .. tostring(self.name) .. ' ' .. h
    end
end
'''


class RepairStack(BarricadeStack):
    """Pile des barricades + doublures de réparation ; fenêtre nord barricadée (4 planches, extérieure abîmée)."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo' if self.mode == 'solo' else 'server', REPAIR_DOUBLES)
        return h

    def mk(self, builder=True, outer=3, planks_w=0):
        gid = super().mk(builder)
        self.run_lua(f'FULL(WIN_N, true, 4, {outer})')
        if planks_w:
            self.run_lua(f'FULL(WIN_W, true, {planks_w}, 10)')
        self.run_lua('BAR.made, BAR_SENT = 0, {}')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        return gid

    def plan(self, gid):
        return self.ev(f'{F}.plan("{gid}", {{ force = true }})')

    def ids(self, gid):
        return [s.id for s in self.plan(gid).sites.values() if not s.done and s.kind != 'wall']   # sans le pourtour

    def site(self, gid, sid):
        return f'(function() for _, s in ipairs({F}.plan("{gid}").sites) do if s.id == "{sid}" then return s end end end)()'

    def outer_cond(self):
        return self.run_lua('local b = WIN_N.opp return b and b.planks[#b.planks] or nil, b and #b.planks or 0')

    def drop_planks(self, gid):
        self.run_lua('local out = {} for _, it in ipairs(PANTRY.container.items.items) do '
                     'if it.t == "Base.Plank" then out[#out + 1] = it end end '
                     'for _, it in ipairs(out) do HARNESS.listRemove(PANTRY.container.items, it) end')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')


class PlanRepairTests(RepairStack):
    mode = 'solo'

    def test_damaged_outer_plank_is_a_repair_site_last_without_attack(self):
        gid = self.mk()
        plan = self.plan(gid)
        self.assertFalse(plan.urgent)
        self.assertEqual(plan.repairs, 1)
        self.assertEqual(self.ids(gid), ['barricade:105,110,0W', 'repair:112,105,0N'])
        rep = self.ev(self.site(gid, 'repair:112,105,0N'))
        self.assertEqual((rep.target, rep.tier, rep.steps, rep.opening), ('barricade', 'ground', 1, 'window'))
        self.assertAlmostEqual(rep.cond, 0.3)
        self.assertEqual((rep.inside.x, rep.inside.y, rep.outside.x, rep.outside.y), (112, 105, 112, 104))
        self.assertEqual([(m.types[1], m.n) for m in rep.materials.values()], [('Base.Plank', 1), ('Base.Nails', 1)])
        # Niveau : la réparation compte dans le rez-de-chaussée (une étape non faite de plus).
        self.run_lua('WIN_N.opp.planks[4] = 8')
        self.assertLess(plan.level, self.plan(gid).level)
        self.assertEqual(self.h.errors('solo'), [])

    def test_after_an_attack_repairs_then_started_barricades_come_first(self):
        gid = self.mk(planks_w=1)
        self.assertEqual(self.ids(gid), ['barricade:105,110,0W', 'repair:112,105,0N'])
        self.run_lua(f'MARK("{gid}", "def-1")')
        plan = self.plan(gid)
        self.assertTrue(plan.urgent)
        self.assertEqual(self.ids(gid), ['repair:112,105,0N', 'barricade:105,110,0W'])
        # La marque compte REPAIR_URGENT_MINUTES : au-delà, retour à l'ordre ordinaire (plan relevé sans forcer).
        self.h.advance(self.ev(f'{F}.CFG.REPAIR_URGENT_MINUTES') + 5)
        self.assertFalse(self.ev(f'{F}.plan("{gid}").urgent'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_sound_or_incomplete_barricades_are_not_repaired(self):
        gid = self.mk(outer=8)                                                 # 80 % : au-dessus du seuil
        self.assertEqual(self.plan(gid).repairs, 0)
        self.run_lua('WIN_N.opp.planks = { 10, 2 }')                             # incomplète : planches d'abord
        plan = self.plan(gid)
        self.assertEqual(plan.repairs, 0)
        self.assertIn('barricade:112,105,0N', self.ids(gid))
        self.assertEqual(self.h.errors('solo'), [])


class SoloRepairTests(RepairStack):
    mode = 'solo'

    def test_builder_repairs_first_after_an_attack_with_the_exact_stock(self):
        gid = self.mk()
        self.run_lua(f'MARK("{gid}", "def-1")')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('repairs') >= 1), (self.stat('planks'), self.lk()[-10:]))
        self.assertEqual(self.stat('planks'), 0)                                # rien cloué ailleurs avant
        self.assertEqual(self.outer_cond(), (10, 4))                           # planche saine à l'extérieur
        # Stock : une planche saine et un clou retirés, la planche abîmée (état 3) rendue à la caisse.
        self.assertEqual(lua_list(self.ev('PLANK_CONDS()')), [3, 5] + [10] * 6)
        self.assertEqual((self.count('Base.Nails'), self.count('Base.NailsBox')), (99, 0))
        self.assertTrue(self.ev('PANTRY.container:containsID(HAMMER_IT.id)'))
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        self.assertEqual((self.ev('BAR.sent'), self.ev('BAR.changes')), (0, 0))   # solo : aucune transmission
        self.assertEqual(self.plan(gid).repairs, 0)
        self.assertIsNone(self.ev(f'{F}.needOf("{gid}")'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_avoided_site_is_left_until_the_avoidance_ends(self):
        # Campagne MP du 2026-10-15 : déplacement "stuck" puis case évitée 60 s : le chantier n'est plus repris en
        # rafale ("cannot reach") pendant l'évitement ; le constructeur répare une fois l'évitement fini.
        gid = self.mk()
        self.run_lua(f'MARK("{gid}", "def-1")')
        npc = self.ev(f'LivingKnox.Groups.get("{gid}").members["m-2"].npc')
        self.run_lua(f'LivingKnox.Movement.stuckAt["{npc}"] = {{ {{ x = 112, y = 105, z = 0, ms = getTimestampMs() }} }}')
        self.jump_to(11)
        self.work(lambda: False, seconds=20)
        self.assertEqual((self.stat('started'), self.stat('skipped'), self.stat('repairs')), (0, 0, 0), self.lk()[-10:])
        self.run_lua(f'LivingKnox.Movement.stuckAt["{npc}"] = nil')
        self.assertTrue(self.work(lambda: self.stat('repairs') >= 1), self.lk()[-10:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_repair_rechecks_before_taking(self):
        gid = self.mk()
        rep = self.site(gid, 'repair:112,105,0N')
        self.run_lua(f'REP = {rep}')
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, HAMMER_IT)')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual(self.run_lua(f'return {F}.repair(REP, "{gid}", "m-2")'), (None, 'no hammer'))
        self.run_lua('PANTRY.container:AddItem(HAMMER_IT)')
        self.run_lua('WIN_N.opp.planks[4] = 9')                                  # réparée entre-temps
        self.assertEqual(self.run_lua(f'return {F}.repair(REP, "{gid}", "m-2")'), (None, 'already repaired'))
        self.run_lua('WIN_N.opp.metal = true')
        self.assertEqual(self.run_lua(f'return {F}.repair(REP, "{gid}", "m-2")'), (None, 'metal barricade'))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.NailsBox'), self.stat('repairs')), (8, 1, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_last_plank_replaced_recreates_the_barricade(self):
        gid = self.mk()
        self.run_lua('WIN_W.opp = nil FULL(WIN_W, true, 1, 2)')
        site = ('{ id = "repair:105,110,0W", kind = "repair", target = "barricade", x = 105, y = 110, z = 0, '
                'north = false, opening = "window", steps = 1 }')
        text, n = self.run_lua(f'return {F}.repair({site}, "{gid}", "m-2")')
        self.assertEqual(n, 1, text)
        self.assertEqual(self.run_lua('return #WIN_W.opp.planks, WIN_W.opp.planks[1]'), (1, 10))
        self.assertEqual(self.h.errors('solo'), [])

    def test_missing_planks_raise_a_material_need_once_per_attack(self):
        gid = self.mk()
        self.drop_planks(gid)
        self.assertFalse(self.ev(f'{F}.hasWork("{gid}")'))
        need = self.ev(f'{F}.needOf("{gid}")')
        self.assertEqual((need.materials['Base.Plank'], need.sites, len(lua_list(need.tools))), (1, 1, 0))
        self.assertEqual(need.text, '1 Base.Plank')
        self.assertEqual(lua_list(self.ev(f'SHORTAGES("{gid}")')), ['materials to repair 1 defence(s): 1 Base.Plank'])
        for _ in range(3):
            self.ev(f'{F}.hasWork("{gid}")')
        self.assertEqual(len(lua_list(self.ev(f'SHORTAGES("{gid}")'))), 1)    # pas de doublon
        self.run_lua(f'MARK("{gid}", "def-7")')
        self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        self.ev(f'{F}.hasWork("{gid}")')
        logs = lua_list(self.ev(f'SHORTAGES("{gid}")'))
        self.assertEqual(logs[-1], 'materials to repair 1 defence(s): 1 Base.Plank (after def-7)')
        self.assertEqual(len(logs), 2)
        # Planches revenues : la réparation redevient faisable, le besoin s'efface.
        self.run_lua('for i = 1, 2 do PANTRY.container:AddItem(BAR_ITEM("Base.Plank", 10)) end')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertTrue(self.ev(f'{F}.hasWork("{gid}")'))
        self.assertIsNone(self.ev(f'{F}.needOf("{gid}")'))
        self.assertEqual(self.h.errors('solo'), [])


class WallRepairStack(WallStack):
    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, REPAIR_DOUBLES)
        h.load(srv, WALL_REPAIR_DOUBLES)
        return h

    def damaged_wall(self, gid, health=200):
        self.run_lua(f'W0 = {F}.placeStructure(HARNESS.square(103, 103, 0), true, INFOS.walls_exterior_wooden_01_45, '
                     f'"walls_exterior_wooden_01_45", nil) W0.health = {health}')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')

    def rep(self, gid):
        return self.site(gid, 'repair:103,103,0N')


class SoloWallRepairTests(WallRepairStack):
    mode = 'solo'

    def test_wall_repaired_with_vanilla_parts_for_its_damage(self):
        gid = self.mk(shop={'Base.Plank': 2, 'Base.Nails': 4})
        self.run_lua('SAW_IT = SAW_ITEM() PANTRY.container:AddItem(SAW_IT)')
        self.damaged_wall(gid)
        rep = self.ev(self.rep(gid))
        # Dégâts 1 - 200/490 = 0,59 : planches floor(max(2 x 0,59, 1)) = 1 ; clous floor(4 x 0,59) = 2.
        self.assertEqual((rep.target, rep.tier), ('wall', 'outer'))
        self.assertEqual([(m.types[1], m.n) for m in rep.materials.values()], [('Base.Plank', 1)])
        self.assertEqual([(m.types[1], m.n) for m in rep.options.values()], [('Base.Nails', 2), ('Base.Screws', 2)])
        self.assertEqual(lua_list(rep.tools), ['HAMMER', 'SAW'])
        text, n = self.run_lua(f'return {F}.repair({self.rep(gid)}, "{gid}", "m-2")')
        self.assertEqual(n, 1, text)
        self.assertEqual(self.edge(103, 103, True)[1:3], (490, 490))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (1, 2))
        self.assertTrue(self.ev('PANTRY.container:containsID(SAW_IT.id) and PANTRY.container:containsID(HAMMER_IT.id)'))
        self.assertEqual(self.ev('WALL.syncs'), 0)                               # solo : rien envoyé
        self.assertEqual(self.ev(f'{F}.plan("{gid}", {{ force = true }}).repairs'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_saw_means_a_tool_need_and_nothing_taken(self):
        gid = self.mk(shop={'Base.Plank': 2, 'Base.Nails': 4})
        self.damaged_wall(gid)
        self.assertEqual(self.run_lua(f'return {F}.repair({self.rep(gid)}, "{gid}", "m-2")'), (None, 'no saw'))
        self.ev(f'{F}.hasWork("{gid}")')
        need = self.ev(f'{F}.needOf("{gid}")')
        self.assertEqual((lua_list(need.tools), need.text), (['SAW'], 'no material; tools: SAW'))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (2, 4))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerRepairTests(RepairStack):
    """Serveur dédié + deux clients : réparation faite et transmise par le serveur seul."""

    mode = 'mp'

    def test_server_replaces_the_plank_and_sends_one_state_change(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Fortify'))
        text, n = self.run_lua(f'return {F}.repair({self.site(gid, "repair:112,105,0N")}, "{gid}", "m-2")')
        self.assertEqual(n, 1, text)
        self.assertEqual(lua_list(self.ev('BAR_SENT')), ['state window 112,105N:opp 4'])
        self.assertEqual(self.ev('ADDED_SENT'), 1)                              # planche abîmée rendue
        self.assertEqual(self.ev('BAR.addedSent'), 100)                         # boîte ouverte pour le clou
        self.assertEqual(self.outer_cond(), (10, 4))
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class MultiplayerWallRepairTests(WallRepairStack):
    mode = 'mp'

    def test_server_restores_the_wall_health_with_one_sync(self):
        gid = self.mk(shop={'Base.Plank': 2, 'Base.Nails': 4})
        self.run_lua('PANTRY.container:AddItem(SAW_ITEM())')
        self.damaged_wall(gid, health=300)
        self.run_lua('WALL_SENT = {}')
        text, n = self.run_lua(f'return {F}.repair({self.rep(gid)}, "{gid}", "m-2")')
        self.assertEqual(n, 1, text)
        self.assertEqual(lua_list(self.ev('WALL_SENT')), ['sync WoodenWallLvl1 490'])
        self.assertEqual(self.h.errors('server'), [])


class SuiteListTests(RepairStack):
    mode = 'solo'

    def test_suite_is_listed_with_its_tags(self):
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.repair", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.repair'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.repair", { tags = { "world", "server" }', code)
        self.assertIn('Homes.skip(', code)


if __name__ == '__main__':
    unittest.main(verbosity=1)
