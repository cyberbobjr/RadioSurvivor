"""Tests hors jeu de la matérialisation des groupes Living Knox (LK09-T03) : LK_Materialize.lua, avec LK_Bodies.lua
(création, retrait LK03-T04, mort), LK_Groups.lua et LK_Simulation.lua.

    python RadioSurvivor/tests/test_lk_materialize.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo), pile complète des corps (doublures de
test_lk_bodies.py, consignes, rapports d'état, équipement : banc ReleaseBase de test_lk_reports.py). Doublure ajoutée :
IsoGridSquare.getBuildingDef (J/iso/IsoGridSquare.java:7805-7816 : bâtiment de la PIÈCE de la case, nil hors pièce),
BuildingDef.getIDString (J/iso/BuildingDef.java:217-219) ; bâtiments = rectangles BUILDINGS. Les doublures NE PROUVENT PAS
l'API réelle, seulement la logique : état visible = état simulé (membres présents au foyer, blessures, recrues),
aucun mort réapparu, aller-retour sans doublon ni perte, bornes, hystérésis avec le retrait.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, lua_list  # noqa: E402
from test_lk_reports import ReleaseBase  # noqa: E402

MATERIALIZE = LUA / 'server' / 'LivingKnox' / 'LK_Materialize.lua'
SUITE = (Path(__file__).resolve().parents[1] / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
         / 'shared' / 'RST' / 'suites' / 'RST_LKMaterialize.lua')
HOME = (110, 110, 0)

MAT_DOUBLES = r'''
local H = HARNESS
local C = H.classes
-- Escaliers (IsoGridSquare.java:2173-2175) : square.stairs = vrai.
function C.IsoGridSquare:HasStairs() return self.stairs == true end
-- Bâtiments : { x1, y1, x2, y2, id } (bornes incluses) ; une case hors rectangle n'a pas de pièce.
BUILDINGS = {}
local Def = H.class('BuildingDef')
function Def:getIDString() return tostring(self.id) end  -- BuildingDef.java:217-219
function C.IsoGridSquare:getBuildingDef()
    for _, b in ipairs(BUILDINGS) do
        if self.x >= b[1] and self.x <= b[3] and self.y >= b[2] and self.y <= b[4] then
            return setmetatable({ id = b[5] }, Def)
        end
    end
    return nil
end
if LivingKnox.GroupTypes and not LivingKnox.GroupTypes.isKnown("testers") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "testers", nameKey = "IGUI_LK_GroupType_settlers", size = { min = 1, max = 12 },
        hostility = 10, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard" } }, worker = { weight = 1, behaviours = { "chores" } } },
        profiles = {
            { id = "gunner", role = "fighter", weight = 1, weapons = { "Base.Shotgun", "Base.Pistol" },
              looks = { "manFairBeard", "womanTanBob" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
-- Membres d'un groupe qui ont un corps dans le monde (triés).
function MAT_BODIES(gid)
    local g = LivingKnox.Groups.get(gid)
    local out = {}
    for mid, m in pairs(g.members) do
        if m.npc and (LivingKnox.Bodies.find(m.npc)) then out[#out + 1] = mid end
    end
    table.sort(out)
    return out
end
-- Corps étiquetés vivants dans le monde, tous PNJ confondus.
function ALL_TAGGED()
    local n = 0
    for _, zb in ipairs(H.zombieList.items) do
        if not zb:isDead() and zb:hasModData() and zb:getModData().lkNpcId ~= nil then n = n + 1 end
    end
    return n
end
function MAT_BODY(gid, mid)
    local m = LivingKnox.Groups.get(gid).members[mid]
    return m.npc and (LivingKnox.Bodies.find(m.npc)) or nil
end
'''

# Déplacement local du joueur (RST_Fixtures.placeLocal, TeleportPacket.processClient), comme test_lk_milestone.py.
PLAYER_MOVES = r'''
local H = HARNESS
local P = H.classes.IsoPlayer
function P:ensureNotInVehicle() end
for _, f in ipairs({ 'X', 'Y', 'Z' }) do
    local key = string.lower(f)
    P['set' .. f] = function(self, v)
        H.num(v, 'set' .. f)
        self[key] = v
        H.place(self, self.x, self.y, self.z)
        return v
    end
    P['setLast' .. f] = function(self, v) H.num(v, 'setLast' .. f) return v end
end
'''

# Membres : (rôle, profil, femme)
CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'true'), ('fighter', 'gunner', 'nil'),
        ('worker', 'cook', 'false'), ('worker', 'cook', 'nil')]


class MatBase(ReleaseBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, MAT_DOUBLES)
        return h

    def setUp(self):
        super().setUp()
        self.init()
        self.away()

    def away(self, x=400, y=400):
        for p in (['A'] if self.mode == 'solo' else ['A', 'B']):
            self.h.move_player(p, x, y)

    def passes(self, n=1):
        self.h.tick(n * self.ev('LivingKnox.Bodies.SCAN_EVERY'))

    def mk_group(self, crew=CREW, home=HOME, leader=1, name='Mill'):
        h = 'nil' if home is None else f'{{ x = {home[0]}, y = {home[1]}, z = {home[2]} }}'
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "testers", name = "{name}", '
                f'day = 1, home = {h} }})) ')
        for role, profile, female in crew:
            code += (f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, '
                     f'day = 1 }})) ')
        if leader:
            code += f'assert(G.setLeader(g.id, "m-{leader}", 1)) '
        return self.run_lua(code + 'return g.id')

    def member(self, gid, mid, field):
        return self.ev(f'LivingKnox.Groups.get("{gid}").members["{mid}"].{field}')

    def npc(self, gid, mid, field):
        return self.ev(f'LivingKnox.Store.data().npcs[LivingKnox.Groups.get("{gid}").members["{mid}"].npc].{field}')

    def bodies(self, gid):
        return lua_list(self.ev(f'MAT_BODIES("{gid}")'))

    def update(self, gid, lua_body):
        """lua_body s'exécute avec g = groupe vivant ; une sauvegarde."""
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) local g = d.groups["{gid}"] {lua_body} '
                     f'return true end))')

    def body_xy(self, gid, mid):
        return self.run_lua(f'local z = MAT_BODY("{gid}", "{mid}") return z:getX(), z:getY()')

    def lines(self, text):
        return [line for line in self.lk() if text in line]


class MultiplayerMaterializeTests(MatBase):
    def prepared(self):
        """Groupe de cinq : m-1 chef, m-3 blessé (40), m-4 mort, m-5 en expédition. Joueurs loin."""
        gid = self.mk_group()
        self.run_lua(f'assert(LivingKnox.Groups.markDead("{gid}", "m-4", 1))')
        self.update(gid, 'g.expedition = { place = "houses", team = { "m-5" }, departed = 0, returns = 100000 } '
                         'g.members["m-3"].wound = 40')
        return gid

    def test_present_members_get_bodies_from_the_simulated_state(self):
        gid = self.prepared()
        self.passes(3)
        self.assertEqual(self.bodies(gid), [])                               # personne près du foyer
        self.h.move_player('A', 100, 100)
        self.passes(1)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2'])                    # chef d'abord, PER_PASS = 2
        self.passes(1)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3'])
        self.passes(5)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3'])            # ni le mort ni l'absent
        self.assertIsNone(self.member(gid, 'm-4', 'npc'))
        self.assertIsNone(self.member(gid, 'm-5', 'npc'))
        self.assertEqual(self.ev('ALL_TAGGED()'), 3)
        # Santé : naissance (2 sur ce banc) x (100 - blessure) / 100.
        self.assertEqual(self.npc(gid, 'm-3', 'hpMax'), 2)
        self.assertAlmostEqual(self.run_lua(f'return MAT_BODY("{gid}", "m-3"):getHealth()'), 1.2, places=6)
        self.assertEqual(self.run_lua(f'return MAT_BODY("{gid}", "m-1"):getHealth()'), 2)
        # Apparence et arme du profil du type ; sexe du membre.
        p1 = self.npc(gid, 'm-1', 'profile')
        self.assertEqual((p1.look, p1.female), ('manFairBeard', False))
        self.assertIn(self.npc(gid, 'm-1', 'weapon'), ('Base.Shotgun', 'Base.Pistol'))
        p2 = self.npc(gid, 'm-2', 'profile')
        self.assertEqual((p2.female, p2.outfit), (True, 'Generic02'))
        self.assertEqual(self.npc(gid, 'm-2', 'weapon'), 'Base.KitchenKnife')
        # Places : autour du foyer, cases distinctes et non voisines.
        pts = [self.body_xy(gid, mid) for mid in ('m-1', 'm-2', 'm-3')]
        for x, y in pts:
            self.assertLessEqual(max(abs(x - 110.5), abs(y - 110.5)), 8)
        for i in range(3):
            for j in range(i + 1, 3):
                self.assertGreaterEqual(max(abs(pts[i][0] - pts[j][0]), abs(pts[i][1] - pts[j][1])), 2)
        self.assertEqual(len(self.lines('materialized as npc')), 3)
        self.assertEqual(self.h.errors('server'), [])

    def test_round_trip_keeps_identities_without_duplicates_or_losses(self):
        gid = self.prepared()
        self.h.move_player('A', 100, 100)
        self.passes(3)
        ids = {mid: self.member(gid, mid, 'npc') for mid in ('m-1', 'm-2', 'm-3')}
        next_id = self.ev('LivingKnox.Store.data().nextId')
        self.run_lua(f'MAT_BODY("{gid}", "m-1").health = 1.0')                 # coup encaissé
        for cycle in range(2):
            self.away()
            self.wait(65)
            for mid in ids:
                self.assertEqual(self.npc(gid, mid, 'state'), 'virtual', (cycle, mid))
            self.assertEqual(self.ev('ALL_TAGGED()'), 0)
            self.assertEqual(self.member(gid, 'm-1', 'wound'), 50)              # 1.0 sur 2 -> 50
            self.assertIsNone(self.member(gid, 'm-2', 'wound'))
            self.assertEqual(self.member(gid, 'm-3', 'wound'), 40)              # 1.2 sur 2 -> 40, inchangée
            self.h.move_player('A', 100, 100)
            self.passes(3)
            self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3'])
            self.assertEqual({mid: self.member(gid, mid, 'npc') for mid in ids}, ids)
            self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), next_id)  # aucun PNJ nouveau
            self.assertEqual(self.npc(gid, 'm-1', 'generation'), cycle + 2)
            self.assertEqual(self.ev('ALL_TAGGED()'), 3)
            self.assertAlmostEqual(self.run_lua(f'return MAT_BODY("{gid}", "m-1"):getHealth()'), 1.0, places=6)
            self.assertAlmostEqual(self.run_lua(f'return MAT_BODY("{gid}", "m-3"):getHealth()'), 1.2, places=6)
        self.assertEqual(len(self.lines('back to the offscreen simulation at home')), 6)
        self.run_lua('LivingKnox.Bodies.scanAll()')
        self.assertEqual([line for line in self.lk() if 'orphan' in line or 'duplicate' in line], [])
        self.assertIsNotNone(self.ev('LivingKnox.Groups.validate(LivingKnox.Groups.state.data)'))

    def test_hysteresis_between_materialization_and_release(self):
        gid = self.prepared()
        self.h.move_player('A', 210, 110)                                      # 100 cases : rien
        self.passes(4)
        self.assertEqual(self.bodies(gid), [])
        self.h.move_player('A', 190, 110)                                      # 80 cases : matérialisés
        self.passes(3)
        self.assertEqual(len(self.bodies(gid)), 3)
        self.h.move_player('A', 225, 110)                                      # entre les deux rayons
        self.wait(75)
        self.assertEqual(len(self.bodies(gid)), 3)                              # ni retrait, ni nouveau corps
        self.assertEqual(self.ev('ALL_TAGGED()'), 3)
        self.h.move_player('A', 300, 110)
        self.wait(65)
        self.assertEqual(self.bodies(gid), [])
        self.assertEqual(self.npc(gid, 'm-1', 'state'), 'virtual')
        self.assertEqual(self.ev('LivingKnox.Materialize.settings().radius'), 80)
        self.run_lua('LivingKnox.Config.MATERIALIZE.RADIUS = 500')             # plafonné : hystérésis gardée
        self.assertEqual(self.ev('LivingKnox.Materialize.settings().radius'), 111)

    def test_body_death_marks_the_member_dead_once_and_it_never_comes_back(self):
        gid = self.prepared()
        self.run_lua('PUB = {} LivingKnox.listen("memberDied", "test", function(i) PUB[#PUB + 1] = i end)')
        self.h.move_player('A', 100, 100)
        self.passes(3)
        morale = self.ev(f'LivingKnox.Groups.get("{gid}").morale')
        self.run_lua(f'local z = MAT_BODY("{gid}", "m-2") z.dead = true HARNESS.trigger("OnZombieDead", z) '
                     f'HARNESS.trigger("OnZombieDead", z)')                    # second événement (feu)
        self.assertIs(self.member(gid, 'm-2', 'alive'), False)
        self.assertEqual(self.ev('#PUB'), 1)
        self.assertIs(self.ev('PUB[1].offscreen'), False)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").morale'), morale - 10)
        died = self.run_lua(f'local n = 0 for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                            f'if e.kind == "died" and e.text == "m-2" then n = n + 1 end end return n')
        self.assertEqual(died, 1)
        # Chef tué : succession immédiate (comme hors écran), un seul fait publié.
        self.run_lua(f'local z = MAT_BODY("{gid}", "m-1") z.dead = true HARNESS.trigger("OnZombieDead", z)')
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").leader'), 'm-3')
        self.assertEqual(self.ev('#PUB'), 2)
        # Aller-retour : seuls les vivants présents reviennent.
        self.away()
        self.wait(65)
        self.h.move_player('A', 100, 100)
        self.passes(4)
        self.assertEqual(self.bodies(gid), ['m-3'])
        self.assertEqual(self.ev('ALL_TAGGED()'), 1)
        # PNJ trouvé mort alors que son membre vivait (incohérence d'une ancienne version) : marqué mort, jamais recréé.
        self.away()
        self.wait(65)
        self.run_lua(f'LivingKnox.Store.data().npcs[LivingKnox.Groups.get("{gid}").members["m-3"].npc].state = "dead"')
        self.h.move_player('A', 100, 100)
        self.passes(4)
        self.assertEqual(self.bodies(gid), [])
        self.assertIs(self.member(gid, 'm-3', 'alive'), False)
        self.assertEqual(self.ev('#PUB'), 2)                                   # aucune publication de plus
        self.assertEqual(len(self.lines('marked dead, not materialized')), 1)
        self.assertEqual(self.ev('ALL_TAGGED()'), 0)

    def test_recruits_and_returning_members_are_materialized_like_the_others(self):
        gid = self.prepared()
        self.h.move_player('A', 100, 100)
        self.passes(3)
        self.run_lua(f'assert(LivingKnox.Groups.addMember("{gid}", {{ role = "worker", profile = "cook", day = 2 }}))')
        self.update(gid, 'g.expedition = nil')                                 # retour d'expédition
        self.passes(2)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3', 'm-5', 'm-6'])
        self.assertEqual(self.ev('ALL_TAGGED()'), 5)

    def test_bounds_spread_creation_and_unknown_or_unloaded_home(self):
        self.run_lua('local c = LivingKnox.Config.MATERIALIZE c.MAX_PER_GROUP = 2 c.MAX_TOTAL = 3 c.PER_PASS = 1')
        g1 = self.mk_group(crew=CREW[:3])
        g2 = self.mk_group(crew=CREW[:3], home=(130, 90, 0), name='Farm')
        g3 = self.mk_group(crew=CREW[:2], home=None, name='Drifters')
        self.h.move_player('A', 100, 100)
        self.passes(1)
        self.assertEqual(self.ev('ALL_TAGGED()'), 1)                            # un corps par passage
        self.passes(1)
        self.assertEqual(self.ev('ALL_TAGGED()'), 2)
        self.passes(10)
        self.assertEqual(self.bodies(g1), ['m-1', 'm-2'])
        self.assertEqual(self.bodies(g2), ['m-1'])
        self.assertEqual(self.bodies(g3), [])
        self.assertEqual(self.ev('ALL_TAGGED()'), 3)
        self.assertEqual(len(self.lines('MAX_PER_GROUP reached')), 1)          # une fois par approche
        self.assertEqual(len(self.lines('MAX_TOTAL reached')), 1)
        # Foyer non chargé : attente, puis création au chargement.
        self.away()
        self.wait(65)
        self.run_lua('local c = LivingKnox.Config.MATERIALIZE c.MAX_PER_GROUP = 8 c.MAX_TOTAL = 24 c.PER_PASS = 2')
        self.run_lua('UNLOAD(100, 120, 100, 120)')
        self.h.move_player('A', 100, 60)
        self.passes(4)
        self.assertEqual(self.bodies(g1), [])
        self.assertEqual(len(self.bodies(g2)), 3)
        self.run_lua('RELOAD()')
        self.passes(3)
        self.assertEqual(self.bodies(g1), ['m-1', 'm-2', 'm-3'])

    def test_placement_inside_the_home_building_or_outside_for_a_camp(self):
        self.run_lua('BUILDINGS = { { 106, 106, 113, 113, 7 }, { 141, 136, 150, 144, 8 } }')
        self.run_lua('for x = 108, 112 do getCell():getGridSquare(x, 110, 0).stairs = true end')  # escalier
        g1 = self.mk_group()
        g2 = self.mk_group(crew=CREW[:4], home=(140, 140, 0), name='Camp')
        self.h.move_player('A', 120, 125)
        self.passes(6)
        self.assertEqual(len(self.bodies(g1)), 5)
        self.assertEqual(len(self.bodies(g2)), 4)
        for mid in ('m-1', 'm-2', 'm-3', 'm-4', 'm-5'):
            x, y = self.body_xy(g1, mid)
            self.assertTrue(106 <= x < 114 and 106 <= y < 114, (mid, x, y))
            self.assertFalse(108 <= x < 113 and 110 <= y < 111, (mid, x, y))   # jamais sur l'escalier
        for mid in ('m-1', 'm-2', 'm-3', 'm-4'):
            x, y = self.body_xy(g2, mid)
            self.assertFalse(141 <= x < 151 and 136 <= y < 145, (mid, x, y))
            self.assertLessEqual(max(abs(x - 140.5), abs(y - 140.5)), 8)
        # Bâtiment trop petit pour tous : on attend (avertissement unique), sans poser dehors.
        self.run_lua('BUILDINGS = { { 160, 160, 163, 163, 9 } }')
        g3 = self.mk_group(home=(161, 161, 0), name='Shed')
        self.passes(6)
        n = len(self.bodies(g3))
        self.assertGreaterEqual(n, 1)
        self.assertLess(n, 5)
        for mid in self.bodies(g3):
            x, y = self.body_xy(g3, mid)
            self.assertTrue(160 <= x < 164 and 160 <= y < 164, (mid, x, y))
        self.assertEqual(len([line for line in self.lines('no free square within') if g3 in line]), 1)

    def test_offscreen_simulation_leaves_embodied_members_to_their_body(self):
        gid = self.prepared()
        self.run_lua('LivingKnox.Config.MATERIALIZE.MAX_PER_GROUP = 2')
        self.update(gid, 'g.members["m-1"].wound = 60 g.members["m-3"].wound = 60 g.needs.medical = 0')
        self.h.move_player('A', 100, 100)
        self.passes(3)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2'])                    # m-3 reste hors écran
        self.run_lua('assert(LivingKnox.Groups.update(function(d) d.simHour = 100 '
                     'return LivingKnox.Simulation.advance(d, 124, {}) end))')
        self.assertEqual(self.member(gid, 'm-1', 'wound'), 60)                # corps : santé du corps
        self.assertGreater(self.member(gid, 'm-3', 'wound'), 60)              # abstrait : s'aggrave sans soins
        self.assertTrue(self.ev(f'LivingKnox.Simulation.materialized(LivingKnox.Groups.state.data.groups["{gid}"])'))
        team = lua_list(self.run_lua(
            f'local S, g = LivingKnox.Simulation, LivingKnox.Groups.state.data.groups["{gid}"] '
            'local living = {} for mid, m in pairs(g.members) do if m.alive then living[#living + 1] = mid end end '
            'return S.teamCandidates(g, living, S.expeditionSettings())'))
        self.assertNotIn('m-2', team)                                          # jamais une expédition d'un corps
        # Événements : aucun pour un groupe matérialisé, ni comme cible ; un groupe abstrait en tire.
        other = self.mk_group(crew=CREW[:3], home=(900, 900, 0), name='Far')
        got = self.run_lua(
            'local S = LivingKnox.Simulation local s = S.eventSettings() s.maxDaily = 1 s.illness.CHANCE = 1 '
            'local d = LivingKnox.Groups.state.data '
            f'local out = S.runEvents(d, {{ "{gid}", "{other}" }}, 100, 7, s, {{}}) '
            'local r = {} for _, e in ipairs(out) do r[#r + 1] = e.group end return r')
        self.assertEqual(lua_list(got), [other])

    def test_mp_clients_never_materialize(self):
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Materialize'))
        gid = self.prepared()
        self.h.move_player('A', 100, 100)
        self.passes(3)
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])
        self.assertEqual(len(self.bodies(gid)), 3)

    def test_member_body_death_publishes_npc_died_with_group_and_cause(self):
        # LK07-T04 : fait "npcDied" (point d'appel de LK12-T02) et cause ajoutée à "memberDied".
        gid = self.prepared()
        self.run_lua('PUB, NPCD = {}, {} LivingKnox.listen("memberDied", "test", function(i) PUB[#PUB + 1] = i end) '
                     'LivingKnox.listen("npcDied", "test", function(i) NPCD[#NPCD + 1] = i end)')
        self.h.move_player('A', 100, 100)
        self.passes(3)
        self.run_lua(f'local z = MAT_BODY("{gid}", "m-2") z.dead = true HARNESS.trigger("OnZombieDead", z) '
                     f'HARNESS.trigger("OnZombieDead", z)')
        self.assertEqual((self.ev('#PUB'), self.ev('#NPCD')), (1, 1))
        self.assertEqual(self.ev('PUB[1].cause'), 'unknown')
        self.assertEqual((self.ev('NPCD[1].group'), self.ev('NPCD[1].member'), self.ev('NPCD[1].cause')),
                         (gid, 'm-2', 'unknown'))
        self.assertEqual(self.ev('NPCD[1].npc'), self.ev(f'LivingKnox.Groups.get("{gid}").members["m-2"].npc'))
        self.assertIs(self.member(gid, 'm-2', 'alive'), False)


class SoloMaterializeTests(MatBase):
    mode = 'solo'

    def test_solo_approach_departure_and_return(self):
        gid = self.mk_group(crew=CREW[:3])
        self.update(gid, 'g.members["m-2"].wound = 25')
        self.h.move_player('A', 100, 100)
        self.passes(2)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3'])
        self.assertAlmostEqual(self.run_lua(f'return MAT_BODY("{gid}", "m-2"):getHealth()'), 1.5, places=6)
        self.away()
        self.wait(65)
        self.assertEqual(self.bodies(gid), [])
        self.assertEqual(self.member(gid, 'm-2', 'wound'), 25)
        self.h.move_player('A', 100, 100)
        self.passes(2)
        self.assertEqual(self.bodies(gid), ['m-1', 'm-2', 'm-3'])
        self.assertEqual(self.ev('ALL_TAGGED()'), 3)
        self.assertEqual(self.h.errors('solo'), [])


class SoloSuiteTests(MatBase):
    mode = 'solo'

    def test_suite_lk_materialize_passes_on_the_doubles(self):
        gid = self.mk_group(crew=CREW[:3])
        self.update(gid, 'g.members["m-3"].wound = 30')
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', 'shared/RST/suites/RST_LKMaterialize.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.materialize", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.materialize')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.materialize", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(4000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, results)
        self.assertTrue(any('[LKM] measure materialize: group grp-1, 3 bodies' in line
                            for line in self.h.logs('solo')), self.h.logs('solo')[-20:])


class ConversionTests(MatBase):
    mode = 'solo'

    def test_health_and_wound_round_trip(self):
        for full in (1.8, 2, 3.7, 0.5):
            for w in range(0, 100):
                back = self.ev(f'LivingKnox.Materialize.woundOf(LivingKnox.Materialize.healthOf({w}, {full}), {full})')
                self.assertEqual(back, w, (full, w))
        self.assertEqual(self.ev('LivingKnox.Materialize.woundOf(0, 2)'), 99)  # jamais mort par la conversion
        self.assertEqual(self.ev('LivingKnox.Materialize.woundOf(3, 2)'), 0)
        self.assertIsNone(self.ev('LivingKnox.Materialize.woundOf(nil, 2)'))
        self.assertAlmostEqual(self.ev('LivingKnox.Materialize.healthOf(150, 2)'), 0.02, places=6)

    def test_full_health_checked_at_reload(self):
        def check(value):
            return self.ev('(select(2, LivingKnox.Identity.validate({ schema = 2, nextId = 2, npcs = { ["lk-1"] = { '
                           'id = "lk-1", generation = 0, state = "virtual", hpMax = ' + value + ', '
                           'profile = LivingKnox.Identity.normalizeProfile({}, 1), want = { x = 1, y = 1, z = 0 } '
                           '} } })))')
        for bad in ('-1', '0', '40', '"full"'):
            self.assertEqual(check(bad), 'npc lk-1: bad full health', bad)
        for good in ('1.8', '32.767', 'nil'):
            self.assertIsNone(check(good), good)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_source_and_english_logs(self):
        text = MATERIALIZE.read_text(encoding='utf-8')
        code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
        code = re.sub(r'--[^\n]*', '', code)
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character in code')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b', r'//', r'&',
                        r'\|', r'<<', r'>>', r'~[^=]'):
            self.assertIsNone(re.search(pattern, code, flags=re.M), pattern)
        self.assertTrue(text.startswith('-- Living Knox'))
        self.assertIn('if isClient() then return end', text)
        # Aucun accès à une ModData globale (registres privés seulement).
        self.assertNotIn('ModData.', code)

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main()
