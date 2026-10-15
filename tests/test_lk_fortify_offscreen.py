"""Tests hors jeu du rattrapage hors écran de la fortification (LK14-T05) : server/LivingKnox/LK_Fortify.lua
(Fortify.snapshot, offscreenHour, offscreenLevel, offscreenFeasible, applyPending, scan), accroche dans
LK_Simulation.lua (Simulation.advance, après chaque heure de chaque groupe), matériaux pris par LK_Stock.lua
(Stock.offscreenCount, Stock.offscreenTake : journal d'écarts du stock, LK09-T06), et la suite en jeu
lk.fortify_offscreen (dev/.../RST_LKFortifyOffscreen.lua). LK13-T07 : forme compacte du relevé au registre et
migration de l'ancienne forme (CompactFormTests).

    python RadioSurvivor/tests/test_lk_fortify_offscreen.py

Banc : pile de test_lk_barricade.py et test_lk_walls.py (groupe « deciders » dans la maison HOUSE 105..115, foyer
110,110, deux fenêtres, porte d'entrée sud, caisse de la cuisine avec un marteau, 8 planches et une boîte de clous ;
ouvrier m-2 au poste « builder »). Hors écran : toute la carte hors de la zone chargée (UNLOADED_X = 100) et corps
retirés (Simulation.isEmbodied rend faux, comme après LK_Materialize) ; arrivée d'un joueur : UNLOADED_X = nil puis
examen Fortify.scan (EveryOneMinute).
Doublures ajoutées : ModData des objets d'inventaire (InventoryItem.getModData / hasModData, J/inventory/
InventoryItem.java) ; refus d'une écriture du registre (arrêt brutal entre la pose et l'écriture).
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (matériaux pris une seule fois dans la
référence, état posé = état simulé, aucun double après une application interrompue, transmissions faites par le
serveur seul).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_barricade import FORTIFY, F, ST, BarricadeStack  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_walls import WALL_DOUBLES  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITE = 'shared/RST/suites/RST_LKFortifyOffscreen.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE
SIM = 'server/LivingKnox/LK_Simulation.lua'

OFF_DOUBLES = r'''
local Item = HARNESS.classes.InventoryItem
function Item:getModData() local md = rawget(self, 'md') if not md then md = {} self.md = md end return md end
function Item:hasModData() return rawget(self, 'md') ~= nil end
-- Heure simulée hors écran sur le registre vivant (comme le pas de la simulation).
function OFF_FORT(gid, hour)
    local out
    assert(LivingKnox.Groups.update(function(d)
        out = LivingKnox.Fortify.offscreenHour(d.groups[gid], gid, hour)
        return true, true
    end))
    return out
end
-- Vue de travail du relevé (LK13-T07 : le registre garde la forme compacte, Fortify.fortView la relit).
function FORT(gid) local g = LivingKnox.Groups.get(gid) return LivingKnox.Fortify.fortView(g.fort, g.home) end
function STOCK_PENDING(gid) return LivingKnox.Stock.pendingCount(LivingKnox.Groups.get(gid).stock) end
-- Marques d'application restantes (fenêtres et leurs barricades, objets de la caisse, ouvrages).
function MARKS()
    local n = 0
    for _, o in ipairs({ WIN_N, WIN_W, WIN_N.own, WIN_N.opp, WIN_W.own, WIN_W.opp }) do
        if o ~= nil and o:hasModData() and o:getModData().LKFortOp ~= nil then n = n + 1 end
    end
    for _, it in ipairs(PANTRY.container.items.items) do
        if it:hasModData() and it:getModData().LKFortOp ~= nil then n = n + 1 end
    end
    for x = 100, 120 do
        for y = 100, 120 do
            local sq = HARNESS.square(x, y, 0)
            for _, o in ipairs(sq.objects.items) do
                if o.name ~= nil and o:hasModData() and o:getModData().LKFortOp ~= nil then n = n + 1 end
            end
        end
    end
    return n
end
-- Arrêt brutal : l'écriture du registre qui ôte les écarts de pose est perdue (registre revenu à son état d'avant).
local function deep(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end
FAIL_FORT_WRITE = false
local G = LivingKnox.Groups
local update = G.update
G.update = function(fn)
    return update(function(data)
        local before = {}
        for gid, g in pairs(data.groups) do
            if type(g.fort) == 'table' then before[gid] = deep(g.fort) end
        end
        local changed, result = fn(data)
        if FAIL_FORT_WRITE and changed then
            for gid, f in pairs(before) do
                local g = data.groups[gid]
                local now = g and LivingKnox.Fortify.fortView(g.fort, g.home)
                local was = g and LivingKnox.Fortify.fortView(f, g.home)
                if now ~= nil and was ~= nil and #now.pend.ops < #was.pend.ops then
                    data.groups[gid].fort = f
                    FAIL_FORT_WRITE = false
                    return false, false
                end
            end
        end
        return changed, result
    end)
end
'''

DAY_HOUR = 28     # heure simulée dont l'heure du jour de début vaut 10 ((28 + 6) % 24)
NIGHT_HOUR = 17   # heure du jour de début 23


class OffscreenStack(BarricadeStack):
    """Pile des barricades + doublures des murs ; relevé hors écran pris foyer chargé, puis foyer hors zone."""

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, WALL_DOUBLES)
        h.load(srv, OFF_DOUBLES)
        return h

    def prepare(self, extra=None):
        """Groupe, ouvrier m-2 au poste builder, relevé pris foyer chargé, puis foyer hors zone et corps retirés."""
        gid = self.mk()
        for t, n in (extra or {}).items():
            self.run_lua(f'SHOP("{t}", {n})')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].members["m-2"].duty = "builder" '
                     'return true, true end))')
        self.assertIsNotNone(self.ev(f'{F}.feasible("{gid}")'))
        fort = self.ev(f'FORT("{gid}")')
        self.assertIsNotNone(fort)
        self.run_lua('UNLOADED_X = 100 LivingKnox.Simulation.isEmbodied = function() return false end')
        return gid

    def off(self, gid, hour=DAY_HOUR):
        return self.ev(f'OFF_FORT("{gid}", {hour})')

    def arrive(self):
        self.run_lua('UNLOADED_X = nil')
        return self.ev(f'{F}.scan("minute")')

    def level_from_world(self, gid):
        return self.ev(f'{F}.plan("{gid}", {{ force = true }}).level')


class PureOffscreenTests(OffscreenStack):
    mode = 'solo'

    def test_snapshot_keeps_the_plan_sites_tools_and_levels(self):
        gid = self.prepare()
        fort = self.ev(f'FORT("{gid}")')
        sites = list(fort.sites.values())
        self.assertEqual([s.id for s in sites[:2]], ['barricade:112,105,0N', 'barricade:105,110,0W'])
        self.assertEqual((sites[0].k, sites[0].t, sites[0].s, sites[0].h, sites[0].o), ('barricade', 'ground', 4, 0,
                                                                                         True))
        self.assertEqual(sites[2].id, 'wall:103,103,0N')
        self.assertTrue(fort.tools.HAMMER)
        self.assertEqual((fort.tiers.ground.h, fort.tiers.ground.s), (0, 8))
        self.assertEqual(len(lua_list(fort.pend.ops)), 0)
        # Foyer hors zone : niveau et chantiers faisables tirés du relevé.
        plan = self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        self.assertTrue(plan.stale)
        self.assertEqual(self.ev(f'{F}.levelOf("{gid}")'), self.ev(f'{F}.offscreenLevel("{gid}")'))
        feas = lua_list(self.ev(f'{F}.feasible("{gid}")'))
        self.assertEqual([s.id for s in feas], ['barricade:112,105,0N', 'barricade:105,110,0W'])
        self.assertTrue(all(s.offscreen for s in feas))
        self.assertTrue(self.ev(f'{F}.hasWork("{gid}")'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_work_at_night_without_builder_or_with_bodies(self):
        gid = self.prepare()
        self.assertIsNone(self.off(gid, NIGHT_HOUR))
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].members["m-2"].duty = "keeper" '
                     'return true, true end))')
        self.assertIsNone(self.off(gid))
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].members["m-2"].duty = "builder" '
                     'return true, true end))')
        self.run_lua('LivingKnox.Simulation.isEmbodied = function() return true end')   # vrais ouvriers au travail
        self.assertIsNone(self.off(gid))
        self.assertEqual(len(lua_list(self.ev(f'FORT("{gid}").pend.ops'))), 0)
        self.assertEqual(self.ev(f'STOCK_PENDING("{gid}")'), 0)
        self.assertEqual(self.h.errors('solo'), [])


class SoloOffscreenTests(OffscreenStack):
    mode = 'solo'

    def test_offscreen_barricades_are_placed_on_arrival_as_simulated(self):
        gid = self.prepare()
        r = self.off(gid)
        self.assertEqual((r.builders, r.steps, r.sites), (1, 8, 2))
        # Référence du stock : 8 planches prises (écarts « take »), 8 clous de la boîte notés ; rien dans le monde.
        self.assertEqual(self.ev(f'STOCK_PENDING("{gid}")'), 8)
        self.assertEqual(self.ev(f'{F}.available("{gid}")["Base.Plank"]'), None)
        fort = self.ev(f'FORT("{gid}")')
        ops = lua_list(fort.pend.ops)
        self.assertEqual([(o.id, o.a, o.b) for o in ops], [('barricade:112,105,0N', 0, 4),
                                                           ('barricade:105,110,0W', 0, 4)])
        boxes = lua_list(fort.boxes)
        self.assertEqual([(b.i, b.u) for b in boxes], [(self.ev('BOX.id'), 8)])
        self.assertEqual((fort.tiers.ground.h, fort.tiers.ground.s), (8, 8))
        level = self.ev(f'{F}.levelOf("{gid}")')
        self.assertFalse(self.ev(f'{F}.hasWork("{gid}")'))                  # plus de planches pour un mur
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 0), (0, 0)))
        self.assertEqual(self.off(gid).steps, 0)                             # plus rien de faisable
        # Zone non chargée : rien n'est posé.
        self.assertEqual(self.ev(f'{F}.scan("minute")'), 0)
        self.assertEqual(self.planks('WIN_N'), (0, 0))
        # Arrivée : barricades posées dehors (côté du plan), 4 planches ; boîte ouverte, 92 clous ; stock appliqué.
        self.assertEqual(self.arrive(), 1)
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual(self.planks('ENTRY'), (0, 0))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 92, 0))
        self.assertTrue(self.ev('PANTRY.container:containsID(HAMMER_IT.id)'))
        self.assertEqual(self.ev(f'STOCK_PENDING("{gid}")'), 0)
        self.assertEqual(self.ev('MARKS()'), 0)
        fort = self.ev(f'FORT("{gid}")')
        self.assertEqual((len(lua_list(fort.pend.ops)), len(lua_list(fort.boxes))), (0, 0))
        # État posé = état simulé : plan relu dans le monde, même niveau ; stock relu sans perte ni vol.
        self.assertEqual(self.level_from_world(gid), level)
        plan = self.ev(f'{F}.plan("{gid}")')
        self.assertTrue(all(s.done for s in plan.sites.values() if s.tier == 'ground'))
        c = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((c.missing, c.lost, len(lua_list(c.thefts))), (0, 0, 0))
        self.assertEqual(self.ev(f'{F}.available("{gid}")["Base.Nails"]'), 92)
        self.assertEqual((self.ev('BAR.made'), self.ev('BAR.construction')), (2, 2))
        # Aucun double : examens suivants sans effet.
        for _ in range(3):
            self.assertEqual(self.ev(f'{F}.scan("minute")'), 0)
        self.assertEqual((self.planks('WIN_N'), self.count('Base.Nails')), ((0, 4), 92))
        self.assertTrue(any(f'fortify: group {gid} offscreen work placed: 2 change(s) placed (8 step(s))' in ln
                            for ln in self.lk()), self.lk()[-10:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_walls_and_time_budget(self):
        gid = self.prepare(extra={'Base.Plank': 4})
        self.run_lua(f'{F}.CFG.OFF_WORK_MINUTES = 5')                         # 2 étapes et demie par heure
        steps = [self.off(gid, DAY_HOUR + i).steps for i in range(5)]
        self.assertEqual(steps, [2, 3, 2, 3, 0])                              # reste de minutes gardé d'une heure à l'autre
        self.run_lua(f'{F}.CFG.OFF_WORK_MINUTES = 30')
        fort = self.ev(f'FORT("{gid}")')
        ids = [o.id for o in lua_list(fort.pend.ops)]
        self.assertEqual(ids, ['barricade:112,105,0N', 'barricade:112,105,0N', 'barricade:105,110,0W',
                               'barricade:105,110,0W', 'barricade:105,110,0W', 'wall:103,103,0N'])
        wall = lua_list(fort.pend.ops)[-1]
        self.assertEqual((wall.a, wall.b), (0, 2))                            # cadre puis mur la même heure
        self.assertEqual(lua_list(fort.boxes)[0].u, 14)                       # 8 + 2 + 4 clous
        self.assertEqual(self.arrive(), 1)
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        name, health = self.run_lua('local o = EDGE(103, 103, true) return o and o.name, o and o.health')
        self.assertEqual((name, health), ('WoodenWallLvl1', 490))
        self.assertEqual(self.run_lua('local n = 0 for _, o in ipairs(HARNESS.square(103, 103, 0).objects.items) do '
                                      'if o.name == "WoodenWallFrame" then n = n + 1 end end return n'), 0)
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (0, 86))
        self.assertEqual(self.ev('MARKS()'), 0)
        plan = self.ev(f'{F}.plan("{gid}")')
        wall_site = next(s for s in plan.sites.values() if s.id == 'wall:103,103,0N')
        self.assertTrue(wall_site.done)
        self.assertEqual(self.h.errors('solo'), [])

    def test_interrupted_application_is_resumed_without_double(self):
        gid = self.prepare()
        self.off(gid)
        self.run_lua('FAIL_FORT_WRITE = true UNLOADED_X = nil')
        self.ev(f'{F}.applyPending("{gid}")')
        # Pose faite, écriture perdue : marques gardées, écarts toujours en attente.
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual(self.count('Base.Nails'), 92)
        self.assertGreater(self.ev('MARKS()'), 0)
        self.assertEqual(len(lua_list(self.ev(f'FORT("{gid}").pend.ops'))), 2)
        self.run_lua(f'{F}.reset()')                                          # mémoire perdue aussi
        r = self.ev(f'{F}.applyPending("{gid}")')
        self.assertEqual((r.placed, r.adopted, r.steps), (0, 2, 0))
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 92, 0))
        self.assertEqual(self.ev('MARKS()'), 0)
        self.assertEqual(len(lua_list(self.ev(f'FORT("{gid}").pend.ops'))), 0)
        c = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((c.missing, c.lost), (0, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_world_already_at_the_target_is_not_placed_again(self):
        gid = self.prepare()
        self.off(gid)
        self.run_lua('UNLOADED_X = nil')
        # Fenêtre nord déjà garnie de 4 planches de ce côté (état réel en avance) : rien n'y est reposé.
        self.run_lua('WIN_N.opp = HARNESS.addObject(112, 104, 0, setmetatable({ planks = { 10, 10, 10, 10 }, '
                     'key = "n" }, IsoBarricade))')
        r = self.ev(f'{F}.applyPending("{gid}")')
        self.assertEqual((r.placed, r.already, r.steps), (1, 1, 4))
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual(self.h.errors('solo'), [])

    def test_simulation_step_runs_the_offscreen_hour(self):
        gid = self.prepare()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.simHour = {DAY_HOUR - 1} return true, true end))')
        self.assertEqual(self.run_lua(f'return LivingKnox.Simulation.step({DAY_HOUR})'), 1)
        self.assertEqual(self.ev(f'{F}.stats.offSteps'), 8)
        self.assertEqual(len(lua_list(self.ev(f'FORT("{gid}").pend.ops'))), 2)
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerOffscreenTests(OffscreenStack):
    """Serveur dédié + deux clients : travail hors écran posé et transmis par le serveur seul, une fois."""

    mode = 'mp'

    def test_server_places_and_sends_each_barricade_once(self):
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Fortify'))
        gid = self.prepare()
        self.off(gid)
        self.assertEqual(self.arrive(), 1)
        self.assertEqual(lua_list(self.ev('BAR_SENT')), ['new window 112,105N:opp 4', 'new window 105,110W:opp 4'])
        self.assertEqual(self.ev('BAR.addedSent'), 92)                         # clous de la boîte, une fois
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (0, 92))
        self.assertEqual(self.ev(f'{F}.scan("minute")'), 0)
        self.assertEqual(len(lua_list(self.ev('BAR_SENT'))), 2)
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class CompactFormTests(OffscreenStack):
    """LK13-T07 : relevé gardé au registre en forme compacte ; ancienne forme 1 relue et convertie sans perte de
    chantier en attente ni double pose."""

    mode = 'solo'

    def raw(self, gid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").fort')

    def size(self, gid):
        return self.run_lua('local C = require "RadioSurvivor/RS_Codec" '
                            f'return #C.encodeBytes(LivingKnox.Groups.get("{gid}").fort)')

    def to_old(self, gid):
        """Relevé remis dans l'ancienne forme 1 (tables, identifiants, clé en texte complet du plan quand la mémoire le
        connaît), comme avant LK13-T07."""
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) local g = d.groups["{gid}"] '
                     'local v = LivingKnox.Fortify.fortView(g.fort, g.home) v.v = 1 '
                     f'local m = LivingKnox.Fortify.state.keys and LivingKnox.Fortify.state.keys["{gid}"] '
                     'v.key = m and m.text or "old plan key text" g.fort = v return true, true end))')

    def test_registry_keeps_the_compact_form(self):
        gid = self.prepare()
        raw = self.raw(gid)
        self.assertEqual(raw.v, 2)
        sites = raw.sites.split(';')
        self.assertEqual(sites[0], 'bg2,-5,0N140')                 # barricade:112,105,0N, foyer 110,110, 0/4 planches
        self.assertEqual(len(sites), len(lua_list(self.ev(f'FORT("{gid}").sites'))))
        self.assertEqual((raw.tools, raw.ops, raw.boxes, raw.pn), ('HAMMER', '', '', 0))
        self.assertTrue(raw.tiers.startswith('0/8,'))
        self.assertLess(len(raw.key), 40)                            # empreinte du plan, pas son texte
        compact = self.size(gid)
        self.to_old(gid)
        old = self.size(gid)
        self.assertLessEqual(compact * 2, old, (compact, old))       # registre au moins divisé par deux
        # Même plan relevé de nouveau : relevé non réécrit (même empreinte) ; ancienne forme réécrite une fois.
        self.run_lua(f'{F}.migrate()')
        n = self.ev(f'{F}.stats.snapshots')
        self.run_lua(f'UNLOADED_X = nil {F}.invalidate("{gid}") {F}.feasible("{gid}")')
        self.assertEqual(self.ev(f'{F}.stats.snapshots'), n)
        self.assertEqual(self.raw(gid).v, 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_digest_and_round_trip(self):
        d = [self.ev(f'{F}.digest("{t}")') for t in ('', 'a', 'b', 'ab', 'ba')]
        self.assertEqual(len(set(d)), 5)
        self.assertEqual(self.ev(f'{F}.digest("ab")'), d[3])
        gid = self.prepare()
        self.off(gid)
        same = self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") '
                            'local p = LivingKnox.Fortify.packFort(LivingKnox.Fortify.fortView(g.fort, g.home)) '
                            'for k, v in pairs(g.fort) do if p[k] ~= v then return k end end '
                            'for k, v in pairs(p) do if g.fort[k] ~= v then return k end end return true')
        self.assertIs(same, True)
        # Chaîne mal formée : relevé invalide (remplacé au prochain relevé, comme avant).
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].fort.sites = "bg2,-5" '
                     'return true, true end))')
        self.assertIsNone(self.ev(f'FORT("{gid}")'))
        self.assertFalse(self.ev(f'{F}.hasPending("{gid}")'))

    def test_old_form_with_pending_work_is_migrated_and_placed_once(self):
        gid = self.prepare()
        self.off(gid)
        before = [(o.u, o.id, o.a, o.b) for o in lua_list(self.ev(f'FORT("{gid}").pend.ops'))]
        self.to_old(gid)
        self.assertEqual(self.raw(gid).v, 1)
        self.run_lua(f'{F}.reset()')
        self.assertEqual(self.ev(f'{F}.scan("minute")'), 0)          # zone non chargée : conversion seule
        raw = self.raw(gid)
        self.assertEqual(raw.v, 2)
        self.assertEqual(raw.boxes, f'{self.ev("BOX.id")}:8')
        self.assertEqual([(o.u, o.id, o.a, o.b) for o in lua_list(self.ev(f'FORT("{gid}").pend.ops'))], before)
        self.assertTrue(any('1 offscreen survey(s) rewritten in the compact form' in ln for ln in self.lk()))
        self.assertEqual(self.arrive(), 1)
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 92, 0))
        self.assertEqual(self.ev('MARKS()'), 0)
        for _ in range(3):
            self.assertEqual(self.ev(f'{F}.scan("minute")'), 0)
        self.assertEqual((self.planks('WIN_N'), self.count('Base.Nails')), ((0, 4), 92))
        self.assertEqual(self.raw(gid).ops, '')
        self.assertEqual(self.h.errors('solo'), [])

    def test_old_form_after_an_interrupted_application_is_adopted(self):
        gid = self.prepare()
        self.off(gid)
        self.run_lua('FAIL_FORT_WRITE = true UNLOADED_X = nil')
        self.ev(f'{F}.applyPending("{gid}")')                          # pose faite, écriture perdue, marques gardées
        self.assertGreater(self.ev('MARKS()'), 0)
        self.to_old(gid)                                               # registre d'avant LK13-T07
        self.run_lua(f'{F}.reset()')
        self.assertEqual(self.ev(f'{F}.migrate()'), 1)
        r = self.ev(f'{F}.applyPending("{gid}")')
        self.assertEqual((r.placed, r.adopted, r.steps), (0, 2, 0))
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 92, 0))
        self.assertEqual(self.ev('MARKS()'), 0)
        self.assertEqual((self.raw(gid).ops, self.raw(gid).boxes), ('', ''))
        self.assertEqual(self.h.errors('solo'), [])

    def test_offscreen_hour_on_the_old_form_writes_the_compact_form(self):
        gid = self.prepare()
        self.to_old(gid)
        r = self.off(gid)
        self.assertEqual((r.builders, r.steps, r.sites), (1, 8, 2))
        raw = self.raw(gid)
        self.assertEqual(raw.v, 2)
        self.assertEqual(len(raw.ops.split(';')), 2)
        self.assertEqual(self.arrive(), 1)
        self.assertEqual((self.planks('WIN_N'), self.planks('WIN_W')), ((0, 4), (0, 4)))
        self.assertEqual(self.h.errors('solo'), [])


class SuiteListTests(OffscreenStack):
    mode = 'solo'

    def test_suite_is_listed_with_its_tags(self):
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.fortify_offscreen", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.fortify_offscreen'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)

    def test_suite_passes_on_the_doubles_and_cleans_up(self):
        self.run_lua('require "RST/RST"')
        # Doublures de la suite : objets créés comme ceux de la caisse ; retrait de la planche extérieure
        # (IsoBarricade.removePlank, J/iso/objects/IsoBarricade.java:110-136 : la dernière efface la barricade).
        self.run_lua('instanceItem = function(t) return BAR_ITEM(t) end '
                     'function IsoBarricade:removePlank(chr) table.remove(self.planks) '
                     'if #self.planks == 0 then for _, o in ipairs({ WIN_N, WIN_W }) do '
                     'if o.own == self then o.own = nil end if o.opp == self then o.opp = nil end end end end')
        self.h.load('solo', SUITE)
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 110, 110, 0) PLAYER = p')
        before = len(list(self.ev('LivingKnox.Groups.list()').values()))
        self.assertTrue(self.ev('RST.start({ suite = "lk.fortify_offscreen", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {}, self.lk()[-15:])
        self.assertEqual(report.total, 1)
        self.assertEqual(len(list(self.ev('LivingKnox.Groups.list()').values())), before)
        self.assertEqual(self.planks('WIN_N'), (0, 0))                          # planches de l'essai retirées
        self.assertEqual((self.count('Base.Plank'), self.count('Base.NailsBox'), self.count('Base.Hammer')), (8, 1, 1))
        self.assertEqual(self.h.errors('solo'), [])


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.fortify_offscreen", { tags = { "world", "server" }', code)
        self.assertIn('Homes.skip(', code)

    def test_module_sources_are_kahlua_safe(self):
        for rel in (FORTIFY, SIM, 'server/LivingKnox/LK_Stock.lua'):
            path = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / rel
            raw = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in raw.splitlines())
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII character in the code of {rel}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code), (rel, pattern))


if __name__ == '__main__':
    unittest.main(verbosity=1)
