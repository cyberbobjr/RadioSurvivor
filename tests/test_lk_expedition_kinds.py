"""Tests hors jeu des genres d'expédition Living Knox (LK16-T08, constats C-X01 à C-X04 de l'audit SOLID) :
server/LivingKnox/LK_Expeditions.lua (moteur) et les genres inscrits par Expeditions.registerKind (bâtiment, cueillette,
pêche : dossier server/LivingKnox/Expeditions/).

    python tests/test_lk_expedition_kinds.py

Bancs (pile de la pêche de test_lk_food.py : bâtiment visé n° 9, forêt DeepForest et lac proches, caisse garnie hors
nourriture) :
- gel : empreintes (sha256) relevées sur le code d'avant le registre des genres : décisions de départ (tryDepart) sur
  une grille d'heures (nuit, aube, jour, crépuscule), de présence de bâtiments, d'eau et de cueillette, de manques et d'équipes ;
  déroulé complet d'une expédition de chaque genre (phases, places, gestes, objets pris, dépôt, journal) ; retours
  hors écran de chaque genre (tirages) ;
- acceptation : un genre d'expédition inscrit par ce banc seul part, se déroule, revient et se résout hors écran sans
  rien toucher au moteur.
"""
from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import DUMP  # noqa: E402
from test_lk_food import FishStack  # noqa: E402

EX = 'LivingKnox.Expeditions'
D = 'LivingKnox.Decisions'
# Empreintes (sha256) relevées sur le code d'avant le registre des genres d'expédition (LK16-T08).
FROZEN_DEPARTURES = '3fb5215a5318f01be425f2acb82caa7f45c6bd16a0d8979e215991b95b3e62bd'
FROZEN_TRIPS = {'building': '8b55accbab95cba1f3f4cb08acbcf433a0200779d37ef9a07b9a56b9a65f6630',
                'forage': '8baf3050fc13ee165747b5c334b7daf3eefd72a98487401297995049244513b2',
                'fish': 'd63b946590fd14956caa6f4fda615a73d61c86bbea0c85a7bec4a9a9e1d448d0'}
FROZEN_OFFSCREEN = '02c3298f1edb2b665d535fd4a402891cc1f448486cedd46aac3e0ba610ffebe8'

# Grille des départs : heures, eau et forêt présentes ou non, manques (Stock.needs), besoins des fourrageurs.
GRID = r'''
local E = LivingKnox.Expeditions
local G = LivingKnox.Groups
local ST = LivingKnox.Stock
local DEC = LivingKnox.Decisions
local NEEDS = {
    "real",
    { { c = "food", missing = 12 }, { c = "water", missing = 3 } },
    { { c = "water", missing = 4 }, { c = "food", missing = 6 } },
    { { c = "food", missing = 1 } },
    {},
}
local TEAMS = {
    {},
    { ["m-3"] = { fatigue = 95 } },
    { ["m-3"] = { fatigue = 95 }, ["m-4"] = { fatigue = 95 } },
    { ["m-4"] = { hunger = 95 } },
    { ["m-3"] = { thirst = 90 } },
}
function KIND_GRID(gid, hod)
    local out = {}
    local zones0, needs0, needsOf0, meta0 = ZONES, ST.needs, DEC.needsOf, META
    for _, built in ipairs({ true, false }) do
    META = built and meta0 or {}
    for _, water in ipairs({ true, false }) do
        for _, forest in ipairs({ true, false }) do
            local z = {}
            for _, zn in ipairs(zones0) do
                if (zn.type ~= "Water" or water) and (zn.type ~= "DeepForest" or forest) then z[#z + 1] = zn end
            end
            ZONES = z
            FISH_WATER(100, 124, 107, 131, water)
            for ni, needs in ipairs(NEEDS) do
                if needs == "real" then ST.needs = needs0 else
                    ST.needs = function() return { needs = needs } end
                end
                for ti, over in ipairs(TEAMS) do
                    DEC.needsOf = function(g2, mid)
                        local n = {}
                        for k, v in pairs(needsOf0(g2, mid) or {}) do n[k] = v end
                        for k, v in pairs(over[mid] or {}) do n[k] = v end
                        return n
                    end
                    local refused = E.stats.refused
                    local n, why = E.tryDepart(gid, DEC.currentMinute())
                    local g = G.get(gid)
                    local last = g.log[#g.log]
                    out[#out + 1] = table.concat({ hod, tostring(built), tostring(water), tostring(forest), ni, ti,
                        tostring(n),
                        tostring(why), E.stats.refused - refused, DUMP(E.get(gid)),
                        last and (last.kind .. ":" .. last.text) or "-" }, "|")
                    G.update(function(d) d.groups[gid].trips = nil return true, true end)
                    E.reset()
                end
            end
        end
    end
    end
    ZONES, ST.needs, DEC.needsOf, META = zones0, needs0, needsOf0, meta0
    FISH_WATER(100, 124, 107, 131, true)
    return table.concat(out, "\n")
end
-- Pas d'une expédition à l'écran : phase, tirages, charge, conteneurs fouillés ; pour chaque fourrageur : place,
-- arrivée, regard, retour, conteneur en cours, case du corps, geste.
function KIND_STEP(gid)
    local t = E.get(gid)
    if t == nil then return "none" end
    local parts = { t.phase, tostring(t.k), #t.carry, #t.searched }
    for _, mid in ipairs({ "m-3", "m-4" }) do
        local npc = MEMBER_NPC(gid, mid)
        local m = npc and E.memberState(npc) or nil
        local z = npc and LivingKnox.Bodies.find(npc) or nil
        parts[#parts + 1] = mid .. ":" .. (m and DUMP({ spot = m.spot, arrived = m.arrived, faced = m.faced,
            home = m.home, job = m.job and m.job.key, stay = m.stay }) or "-") .. ":"
            .. (z and (math.floor(z:getX()) .. "," .. math.floor(z:getY())) or "-") .. ":"
            .. tostring(npc and LivingKnox.Anim.gestureOf(npc))
    end
    return table.concat(parts, "|")
end
-- Bilan d'une expédition rentrée : journal, historique, objets rangés, compteurs.
function KIND_END(gid)
    local g = G.get(gid)
    local log = {}
    for _, e in ipairs(g.log) do log[#log + 1] = e.kind .. ":" .. e.text end
    local types = {}
    for _, it in ipairs(PANTRY.container.items.items) do types[#types + 1] = it.t end
    table.sort(types)
    return table.concat({ table.concat(log, ";"), DUMP(g.trips), table.concat(types, " "), MEAL_COUNT.removed,
        tostring(MADE), tostring(INSTANCED), DUMP(E.stats), DUMP(LivingKnox.Food.stats) }, "|")
end
-- Retour hors écran (pur) d'une expédition du genre kind (nil : bâtiment), k0 tirages déjà faits, flux seed.
function KIND_OFF(kind, k0, seed)
    local room = kind == "fish" and "Water" or (kind == "forage" and "DeepForest" or "kitchen")
    local want = kind == nil and { { c = "water", m = 3 }, { c = "food", m = 2 }, { c = "medical", m = 2 } }
        or { { c = "food", m = 12 } }
    local g = { members = { ["m-3"] = { alive = true }, ["m-4"] = { alive = true }, ["m-5"] = { alive = false } },
        log = {}, expedition = { place = "trip", team = { "m-3", "m-4", "m-5" }, departed = 10, returns = 12,
        trip = 2 }, trips = { v = 1, n = 2, seen = {}, cur = { n = 2, phase = "away", from = "search",
        team = { "m-3", "m-4", "m-5" }, want = want, target = { x = 118, y = 122, z = 0, b = kind or "9",
        room = room, label = "x" }, start = 0, due = 9, cap = 8, carry = {}, searched = {}, kind = kind,
        k = kind and k0 or nil, r = kind and 8 or nil } } }
    local r = E.resolveAbstract(g, "grp-1", 12, DEC.stream("abstract", seed, 5), 1)
    return DUMP(r) .. DUMP(g.trips.cur) .. DUMP(g.log)
end
'''


def digest(text: str) -> str:
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


class KindStack(FishStack):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', DUMP)
        h.load('solo', GRID)
        return h

    def supply(self, gid):
        self.run_lua(f'LivingKnox.Groups.update(function(d) local g = d.groups["{gid}"] g.objective = "supply" '
                     'g.members["m-3"].duty, g.members["m-4"].duty = "forager", "forager" return true, true end)')

    def full_trip(self, gid, seconds=600):
        """Déroulé à l'écran jusqu'au retour : pas distincts (KIND_STEP), puis bilan (KIND_END)."""
        steps = []
        started = False
        for _ in range(seconds):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
            s = self.run_lua(f'return KIND_STEP("{gid}")')
            if s != 'none':
                started = True
            if not steps or steps[-1] != s:
                steps.append(s)
            if started and s == 'none':
                break
        self.assertTrue(started and steps[-1] == 'none', steps[-3:])
        return '\n'.join(steps) + '\n#' + self.run_lua(f'return KIND_END("{gid}")')


class FrozenKindTests(KindStack):
    """LK16-T08 : comportement figé avant le registre des genres (aucun changement de départ, de cible, d'équipe,
    d'objet rapporté ni de tirage hors écran)."""

    def test_departure_decisions_are_frozen(self):
        gid = self.mk()
        self.supply(gid)
        out = []
        for hod in (16, 18, 19, 22, 4, 5, 6, 9, 12):
            self.jump_to(hod)
            out.append(self.run_lua(f'return KIND_GRID("{gid}", {hod})'))
        text = '\n'.join(out)
        for word in ('kind=fish', 'kind=forage', 'kitchen 135,107', 'hour of day 22', 'no fishing:',
                     'no forager free to leave', 'nothing missing', 'no building near home'):
            self.assertIn(word, text)                                       # la grille couvre chaque cas
        self.assertEqual(digest(text), FROZEN_DEPARTURES)
        self.assertEqual(self.h.errors('solo'), [])

    def check_trip(self, name, prepare):
        prepare()
        gid = self.mk()
        if name == 'fish':
            self.jump_to(5)
        text = self.full_trip(gid)
        self.assertIn('back from', text)
        self.assertEqual(digest(text), FROZEN_TRIPS[name], name)
        self.assertEqual(self.h.errors('solo'), [])

    def test_building_trip_is_frozen(self):
        self.check_trip('building', lambda: self.run_lua('ZONES = {}'))

    def test_foraging_trip_is_frozen(self):
        self.check_trip('forage', lambda: None)

    def test_fishing_trip_is_frozen(self):
        self.check_trip('fish', lambda: None)

    def test_offscreen_returns_are_frozen(self):
        out = []
        for kind in ('nil', '"forage"', '"fish"'):
            for k0 in (0, 3):
                for seed in (4, 9):
                    out.append(self.run_lua(f'return KIND_OFF({kind}, {k0}, {seed})'))
        text = '\n'.join(out)
        self.assertIn('Base.WaterBottle', text)
        self.assertEqual(digest(text), FROZEN_OFFSCREEN)
        self.assertEqual(self.h.errors('solo'), [])


# Genre factice inscrit par le banc seul (LK16-T08, acceptation) : récupération de clous dans une cour, deux tirages
# fixes par sortie, objets créés au dépôt ; à toute heure, avant tout autre genre.
SALVAGE = r'''
local E = LivingKnox.Expeditions
SALVAGED = 0
E.registerKind({ id = "salvage", order = 1, gesture = "kneel", verb = "salvages",
    hours = function() return true end,
    pickTarget = function(gid, g, want)
        return { x = 118, y = 110, z = 0, b = "salvage", room = "yard", label = "salvage 118,110", d = 8, score = 0 }
    end,
    wants = function() return { { c = "materials", m = 2 } } end,
    start = function(cur, target, team) cur.k, cur.r = 0, 2 end,
    valid = E.drawnValid,
    round = E.drawnRound,
    offscreen = E.drawnOffscreen,
    conditions = function() return {} end,
    detail = function() return "" end,
    minutes = function() return 1 end,
    draw = function(gid, t, k, c) return { { t = "Base.NailsBox", c = "materials", a = true, f = true } }, "nails" end,
    make = function(itemType)
        SALVAGED = SALVAGED + 1
        return { instanceItem(itemType) }, 0
    end,
})
'''


class KindRegistryTests(KindStack):
    def test_a_kind_registered_by_one_file_leaves_runs_and_comes_back(self):
        """LK16-T08 (acceptation) : un genre inscrit par le banc seul (aucun moteur touché) est choisi au départ,
        mené sur place (geste, tirages), déposé au foyer et résolu hors écran avec ses propres tirages."""
        gid = self.mk()
        self.run_lua(SALVAGE)
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        t = self.trip(gid)
        self.assertEqual((t.kind, t.k, t.r, t.target.b), ('salvage', 0, 2, 'salvage'))
        self.assertEqual([(w.c, w.m) for w in lua_list(t.want)], [('materials', 2)])
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'back', seconds=200), self.phase(gid))
        self.assertEqual([e.t for e in lua_list(self.trip(gid).carry)], ['Base.NailsBox', 'Base.NailsBox'])
        self.assertTrue(self.run_until(lambda: self.trip(gid) is None, seconds=120), self.phase(gid))
        self.assertEqual(self.journal(gid, 'return'), ['trip 1 back from salvage 118,110: 2 back, materials +2'])
        self.assertEqual(self.ev('SALVAGED'), 2)
        off = self.run_lua('return KIND_OFF("salvage", 0, 4)')
        self.assertIn('Base.NailsBox', off)
        self.assertIn('back offscreen: 2 back, 8 item(s) found', off)       # huit tirages restants, charge 8
        self.assertEqual(self.h.errors('solo'), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
