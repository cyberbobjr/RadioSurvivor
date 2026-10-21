"""Tests hors jeu des raids des groupes pillards Living Knox (LK11-T07) : server/LivingKnox/LK_Raids.lua, branché
dans LK_Simulation.lua (heure hors écran, retour de l'équipe), LK_Decisions.lua (comportement « revenge », raison
« raid ») et LK_Relations.lua (trajet abstrait, corps à distance des joueurs et marche de la vengeance, partagés),
options sandbox LivingKnox.RaidsEnabled / RaidDays (LK_Config.lua), et la suite en jeu lk.raid
(dev/.../RST_LKRaid.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_raids.py

Bancs tests/harness.py :
- repérage : bâtiments (BuildingDef : getIDString, getX/getY, getX2/getY2 exclusifs, getMaxLevel ; case ->
  getBuildingDef), refuges vanilla (SafeHouse.getSafeHouse(case), getX/getY/getW/getH), ouvertures barricadables
  (isBarricaded), IsoThumpable (marque LKHome d'un foyer), IsoGenerator (isActivated) ; score des signes, base près
  d'un foyer de groupe ignorée, groupe pillard le plus proche, jours différents ;
- hors écran (serveur dédié + deux clients, registres réels des groupes et des attitudes, simulation réelle) :
  éclaireurs réels, annulation par leur mort, annonce, attaque par l'effectif réel, retour, fréquence, attitude,
  désactivation, persistance, reproductibilité ;
- à l'écran (pile des corps de test_lk_materialize.py, cadre de décision) : corps des éclaireurs et des pillards
  créés seulement à SPAWN_MIN cases au moins de tout joueur, jamais au foyer, marche vers la base.
Les doublures NE PROUVENT PAS l'API réelle (SafeHouse, IsoGenerator, barricades, addZombiesInOutfit, chemins) :
seulement la logique. Le rendu, la marche réelle, le forçage et l'engagement se vérifient en jeu (suite lk.raid,
protocole de docs/annexes/conception/raids.md).
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import DECIDERS, DUMP  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
from test_lk_simulation import Base as SimBase  # noqa: E402

RA = 'LivingKnox.Raids'
R = 'LivingKnox.Relations'
SIM = 'LivingKnox.Simulation'
D = 'LivingKnox.Decisions'
RELATIONS = 'server/LivingKnox/LK_Relations.lua'
RAIDS = 'server/LivingKnox/LK_Raids.lua'
ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared' / 'RST' / 'suites' \
    / 'RST_LKRaid.lua'
KEY_A, KEY_B = 'c-alpha', 'c-bravo'
CANON = ('require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes('
         'LivingKnox.Groups.state.data))')

# Type de test : rôles "raid" (combattants, éclaireurs) et ouvriers ; hostilité 90 -> pillards hostiles (-50).
MARAUDERS = r'''
if not LivingKnox.GroupTypes.isKnown("marauders") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "marauders", nameKey = "IGUI_LK_GroupType_raiders", size = { min = 1, max = 12 },
        hostility = 90, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "raid", "guard", "defend", "fight" } },
                  scout = { weight = 1, behaviours = { "scout", "raid" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } } },
        profiles = {
            { id = "gunner", role = "fighter", weight = 1, weapons = { "Base.Shotgun" }, looks = { "manFairBeard" } },
            { id = "lookout", role = "scout", weight = 1, weapons = { "Base.HuntingKnife" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
'''

# Doublures du repérage (serveur) : bâtiments, refuges, ouvertures, constructions, générateurs ; identité du carnet ;
# faits publiés relevés.
SURVEY = r'''
local H = HARNESS
local C = H.classes
RS_CarnetServer = RS_CarnetServer or { bound = {} }
function BIND(name, key) RS_CarnetServer.bound[HARNESS.players[name]] = key end
RAID_FACTS = {}
for _, n in ipairs({ "raidScouting", "raidAnnounced", "raidLaunched", "raidEnded" }) do
    LivingKnox.listen(n, "test", function(info) RAID_FACTS[#RAID_FACTS + 1] = { name = n, info = info } end)
end
-- Bâtiments : { x1, y1, x2, y2 (inclus), id, maxLevel }.
RAID_BUILDINGS = {}
local Def = H.class('BuildingDef')
function Def:getIDString() return tostring(self.b[5]) end
function Def:getX() return self.b[1] end
function Def:getY() return self.b[2] end
function Def:getX2() return self.b[3] + 1 end
function Def:getY2() return self.b[4] + 1 end
function Def:getMaxLevel() return self.b[6] or 0 end
local Sq = C.IsoGridSquare
local previousDef = Sq.getBuildingDef
function Sq:getBuildingDef()
    for _, b in ipairs(RAID_BUILDINGS) do
        if self.x >= b[1] and self.x <= b[3] and self.y >= b[2] and self.y <= b[4] then
            return setmetatable({ b = b }, Def)
        end
    end
    if previousDef ~= nil then return previousDef(self) end
    return nil
end
-- Refuges vanilla : { x, y, w, h, owner } ; getSafeHouse(case) = refuge qui contient la case (SafeHouse.java:128-150).
SAFEHOUSES = {}
local SH = H.class('SafeHouse')
function SH:getX() return self.x end
function SH:getY() return self.y end
function SH:getW() return self.w end
function SH:getH() return self.h end
SafeHouse = {
    getSafeHouse = function(sq)
        for _, s in ipairs(SAFEHOUSES) do
            if sq:getX() >= s.x and sq:getX() < s.x + s.w and sq:getY() >= s.y and sq:getY() < s.y + s.h then return s end
        end
        return nil
    end,
    hasSafehouse = function(u)
        for _, s in ipairs(SAFEHOUSES) do if s.owner == u then return s end end
        return nil
    end,
}
function SAFEHOUSE(x, y, w, h, owner)
    SAFEHOUSES[#SAFEHOUSES + 1] = setmetatable({ x = x, y = y, w = w, h = h, owner = owner }, SH)
end
local Window = H.class('IsoWindow', C.IsoObject)
function Window:isBarricaded() return self.barricaded == true end
local Thump = H.class('IsoThumpable', C.IsoObject)
function Thump:isBarricaded() return self.barricaded == true end
local Gen = H.class('IsoGenerator', C.IsoObject)
function Gen:isActivated() return self.on == true end
function WINDOW(x, y, z, barricaded) return H.addObject(x, y, z, setmetatable({ barricaded = barricaded }, Window)) end
function THUMP(x, y, z, tag)
    local o = H.addObject(x, y, z, setmetatable({}, Thump))
    if tag then o:getModData().LKHome = tag end
    return o
end
function GENERATOR(x, y, z, on) return H.addObject(x, y, z, setmetatable({ on = on }, Gen)) end
function RAID_LOG(gid)
    local out = {}
    for _, e in ipairs(LivingKnox.Groups.get(gid).log) do
        if e.kind == "raid" then out[#out + 1] = e.text end
    end
    return out
end
-- Base de test toute faite (bâtiment 995..1005 x 1595..1605).
function BASE(id, x, y)
    x, y = x or 1000, y or 1600
    return { id = id or "b:7", x1 = x - 5, y1 = y - 5, x2 = x + 5, y2 = y + 5, x = x, y = y, z = 0, src = "building",
        top = 0 }
end
-- Base notée par le groupe gid les jours d1 et d2 (comme Raids.survey), occupant A de clé key.
function NOTE(gid, d1, d2, key, base)
    LivingKnox.Groups.update(function(d)
        local g = d.groups[gid]
        for _, day in ipairs({ d1, d2 }) do
            LivingKnox.Raids.note(g, gid, base or BASE(), { text = "generator", score = 2 }, "A", key, day)
        end
        return true, true
    end)
end
'''

# Équipage : m-1 chef combattant, m-2 éclaireur, m-3 combattant, m-4 ouvrier, m-5 combattant, m-6 combattant.
CREW = ['fighter', 'scout', 'fighter', 'worker', 'fighter', 'fighter']


class RaidBase(SimBase):
    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        h.load(self.srv, MARAUDERS)
        h.load(self.srv, 'shared/LivingKnox/Data/LK_Type_raiders.lua')
        for m in (('solo',) if self.mode == 'solo' else ('server', 'A', 'B')):
            h.load(m, RELATIONS)
            h.load(m, RAIDS)
        h.load(self.srv, SURVEY)
        h.load(self.srv, 'SandboxVars = SandboxVars or {} SandboxVars.LivingKnox = SandboxVars.LivingKnox or {} '
                         'SandboxVars.LivingKnox.RaidDays = 3')
        return h

    def setUp(self):
        super().setUp()
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'{RA}.CFG.SPEED = 300')
        self.run_lua(f'BIND("A", "{KEY_A}")')
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.h0 = self.ev(f'{SIM}.currentHour()')

    def mk(self, gtype='marauders', crew=CREW, home=(1000, 1000, 0), name='Crows'):
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "{gtype}", name = "{name}", day = 1, '
                f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }})) ')
        for role in crew:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", day = 1 }})) '
        return self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')

    def raid(self, gid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").raid')

    def step_to(self, hour):
        return self.ev(f'{SIM}.step({hour})')

    def log(self, gid):
        return list(self.ev(f'RAID_LOG("{gid}")').values())

    def facts(self):
        return [(f.name, f.info.ending) for f in self.ev('RAID_FACTS').values()]

    def next_day(self, days=1):
        self.h.age_minutes += days * 24 * 60
        self.h._push_clock()

    def survey(self):
        return self.ev(f'{RA}.survey()')


class SignTests(RaidBase):
    def house(self, x=1000, y=1600, gid=7):
        self.run_lua(f'RAID_BUILDINGS[#RAID_BUILDINGS + 1] = {{ {x - 5}, {y - 5}, {x + 5}, {y + 5}, {gid}, 1 }}')

    def test_signs_and_score(self):
        self.house()
        b = 'LivingKnox.Raids.baseOf(HARNESS.players.A)'
        self.h.move_player('A', 1000, 1600)
        base = self.ev(b)
        self.assertEqual((base.id, base.x1, base.y1, base.x2, base.y2, base.x, base.y, base.src, base.top),
                         ('b:7', 995, 1595, 1005, 1605, 1000, 1600, 'building', 1))
        self.assertEqual(self.ev(f'{RA}.signs({b}).score'), 0)                     # maison vide
        self.run_lua('WINDOW(995, 1598, 0, true)')
        self.assertEqual(self.ev(f'{RA}.signs({b}).score'), 0)                     # une barricade : pas assez
        self.run_lua('WINDOW(1006, 1600, 1, true) WINDOW(1000, 1595, 0, false)')   # bord est, étage
        s = self.ev(f'{RA}.signs({b})')
        self.assertEqual((s.barricades, s.score, s.text), (2, 1, 'barricades'))
        self.run_lua('THUMP(1001, 1601, 0) THUMP(1002, 1601, 0, "grp-9")')        # une marquée d'un foyer
        self.assertEqual(self.ev(f'{RA}.signs({b}).constructions'), 1)
        self.run_lua('THUMP(1003, 1601, 0)')
        self.run_lua('GENERATOR(1008, 1600, 0, false)')                             # éteint : rien
        self.assertEqual(self.ev(f'{RA}.signs({b}).score'), 2)
        self.run_lua('GENERATOR(1008, 1601, 0, true)')                              # allumé, dehors à 3 cases
        s = self.ev(f'{RA}.signs({b})')
        self.assertEqual((s.generator, s.constructions, s.score, s.text),
                         (1, 2, 4, 'generator barricades constructions'))
        # Refuge vanilla : seul, il suffit (3 points) ; il prime sur le bâtiment.
        self.run_lua('SAFEHOUSE(1100, 1100, 6, 4, "A")')
        self.h.move_player('A', 1102, 1101)
        base = self.ev(b)
        self.assertEqual((base.id, base.x1, base.x2, base.y2, base.src), ('sh:1100,1100', 1100, 1105, 1103,
                                                                           'safehouse'))
        self.assertEqual(self.ev(f'{RA}.signs({b}).score'), 3)
        self.h.move_player('A', 300, 300)
        self.assertIsNone(self.ev(b))                                                # dehors : pas de base

    def test_survey_notes_the_base_on_distinct_days_for_the_nearest_raider_group(self):
        self.house()
        self.run_lua('GENERATOR(1000, 1600, 0, true)')
        self.h.move_player('A', 1000, 1600)
        self.h.move_player('B', 1001, 1601)
        self.run_lua('BIND("B", "c-bravo")')
        mill = self.mk('settlers', ['deputy', 'fighter', 'worker'], home=(1000, 1400, 0), name='Mill')
        far = self.mk(home=(5000, 5000, 0), name='Far')
        crows = self.mk(home=(1000, 1000, 0))
        near = self.mk(home=(1200, 1600, 0), name='Near')
        self.assertEqual(self.survey(), 2)                                           # A repère, B occupant
        self.assertIsNone(self.raid(mill))                                           # pas pillards
        self.assertIsNone(self.raid(far))
        self.assertIsNone(self.raid(crows))                                          # plus loin que Near
        r = self.raid(near)
        self.assertEqual((r.phase, r.base.id, r.seen, r.signs), ('watch', 'b:7', 1, 'generator'))
        self.assertEqual([(o.u, o.k) for o in r.occ.values()], [('A', KEY_A), ('B', KEY_B)])
        self.assertEqual(self.log(near), ['spotted a player base at 1000,1600 (generator)'])
        self.assertEqual(self.survey(), 0)                                           # même jour : rien de neuf
        self.assertEqual(self.raid(near).seen, 1)
        self.next_day()
        self.assertEqual(self.survey(), 1)
        self.assertEqual(self.raid(near).seen, 2)

    def test_survey_ignores_weak_signs_group_homes_and_disabled_raids(self):
        self.house()
        self.h.move_player('A', 1000, 1600)
        self.h.move_player('B', 300, 300)
        gid = self.mk()
        self.run_lua('WINDOW(995, 1598, 0, true)')
        self.assertEqual(self.survey(), 0)                                           # signes trop faibles
        self.run_lua('GENERATOR(1000, 1600, 0, true)')
        self.run_lua('SandboxVars.LivingKnox.RaidsEnabled = false')
        self.assertEqual(self.survey(), 0)                                           # raids désactivés
        self.run_lua('SandboxVars.LivingKnox.RaidsEnabled = true')
        self.mk('settlers', ['deputy', 'worker'], home=(1030, 1620, 0), name='Mill')    # foyer à 30 cases
        self.assertEqual(self.survey(), 0)
        self.assertIsNone(self.raid(gid))
        self.assertEqual(len([line for line in self.lk() if 'next to a group home' in line]), 1)


class OffscreenTests(RaidBase):
    def watched(self, key=KEY_A, **kw):
        gid = self.mk(**kw)
        self.run_lua(f'NOTE("{gid}", 1, 2, "{key}")')
        return gid

    def test_scouts_leave_once_the_base_is_occupied_and_raids_are_allowed(self):
        gid = self.mk(name='Once')
        self.run_lua(f'NOTE("{gid}", 1, 1, "{KEY_A}")')
        other = self.watched(name='Other')
        self.step_to(60)
        self.assertEqual(self.raid(other).phase, 'watch')                            # monde de moins de 3 jours
        self.assertTrue(any('world too young' in line for line in self.lk()))
        self.step_to(72)
        self.assertEqual(self.raid(gid).phase, 'watch')                              # un seul jour de signes
        r = self.raid(other)
        # Éclaireurs réels : rôle scout d'abord, puis un rôle "raid" valide (une blessure tirée par la simulation
        # peut en retenir un), jamais le chef ni l'ouvrier.
        team = lua_list(r.team)
        self.assertEqual((r.phase, r.step, len(team), team[0], r.start, r.travel), ('scout', 'out', 2, 'm-2', 72, 2))
        self.assertIn(team[1], ('m-3', 'm-5', 'm-6'))
        e = self.ev(f'LivingKnox.Groups.get("{other}").expedition')
        self.assertEqual((e.place, e.departed, e.returns), ('raid', 72, r.leave + 2))
        g = f'LivingKnox.Groups.get("{other}")'
        self.assertEqual(sorted(lua_list(self.ev(f'LivingKnox.Materialize.presentMembers({g})'))),
                         sorted({'m-1', 'm-3', 'm-4', 'm-5', 'm-6'} - set(team)))
        self.assertEqual(self.log(other)[-1], f'scouts {" ".join(team)} left for the base at 1000,1600, 2 h away')
        self.assertEqual(self.facts(), [('raidScouting', None)])
        self.assertEqual(self.ev(f'{g}.nextMember'), 7)                               # aucun membre créé

    def test_killed_scouts_call_the_raid_off(self):
        gid = self.watched()
        self.step_to(72)
        self.step_to(74)
        self.assertEqual(self.raid(gid).step, 'at')
        team = lua_list(self.raid(gid).team)
        for mid in team:
            self.run_lua(f'LivingKnox.Groups.markDead("{gid}", "{mid}")')
        self.step_to(75)
        self.assertIsNone(self.raid(gid))
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        self.assertEqual(self.log(gid)[-2:], [f'scouts {" ".join(team)} did not come back: raid on 1000,1600 called off',
                                              'raid on 1000,1600 ended: cancelled'])
        self.assertEqual(self.facts()[-1], ('raidEnded', 'cancelled'))
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").raidLast'), 72)
        for hour in range(76, 76 + 72, 12):
            self.step_to(hour)
            self.assertIsNone(self.raid(gid))                                        # aucune attaque
        self.assertNotIn('raidLaunched', [f[0] for f in self.facts()])

    def test_scouts_announce_then_the_real_roster_attacks_and_goes_home(self):
        gid = self.watched()
        seen = []
        for hour in range(72, 140):
            self.step_to(hour)
            r = self.raid(gid)
            if r is None:
                break
            seen.append((r.phase, r.step))
        self.assertIsNone(self.raid(gid))
        for state in (('scout', 'out'), ('scout', 'at'), ('scout', 'back'), ('ready', None), ('raid', 'out'),
                      ('raid', 'at'), ('raid', 'back')):
            self.assertIn(state, seen)
        pattern = [r'scouts m-2 m-[356] left for the base at 1000,1600, 2 h away',
                   r'scouts saw the base at 1000,1600 \(generator\): attack in about 26 h',
                   r'scouts back home \(2\): raid on 1000,1600 at hour \d+',
                   r'raiders (m-[2356] ?)+ left for the base at 1000,1600, 2 h away',
                   r'raid on 1000,1600: [1-5] still standing, heading home',
                   r'raid on 1000,1600: [1-5] back home',
                   r'raid on 1000,1600 ended: done']
        got = self.log(gid)[-7:]
        self.assertEqual(len(got), 7)
        for line, pat in zip(got, pattern):
            self.assertRegex(line, '^' + pat + '$')
        self.assertEqual([f[0] for f in self.facts()], ['raidScouting', 'raidAnnounced', 'raidLaunched', 'raidEnded'])
        self.assertEqual(self.facts()[-1], ('raidEnded', 'done'))
        launched = [f for f in self.ev('RAID_FACTS').values() if f.name == 'raidLaunched'][0]
        team = lua_list(launched.info.team)
        # Effectif réel : rôles "raid" vivants au foyer, éclaireurs revenus compris, jamais le chef ni l'ouvrier.
        self.assertTrue(set(team) <= {'m-2', 'm-3', 'm-5', 'm-6'} and len(team) >= 2, team)
        g = f'LivingKnox.Groups.get("{gid}")'
        self.assertEqual(self.ev(f'{g}.raidLast'), 72)
        self.assertEqual(self.ev(f'{g}.nextMember'), 7)
        self.assertEqual(sorted(lua_list(self.ev(f'LivingKnox.Materialize.presentMembers({g})'))),
                         ['m-1', 'm-2', 'm-3', 'm-4', 'm-5', 'm-6'])

    def test_frequency_and_one_raid_at_a_time(self):
        a = self.watched()
        b = self.watched(name='Wolves', home=(1500, 1000, 0))
        self.step_to(72)
        self.assertEqual(self.raid(a).phase, 'scout')
        self.assertEqual(self.raid(b).phase, 'watch')                                # un raid à la fois
        self.assertTrue(any('raid of ' + a + ' under way' in line for line in self.lk()))
        for hour in range(73, 140):
            self.step_to(hour)
            if self.raid(a) is None:
                break
        end = hour
        self.assertIsNone(self.raid(a))
        self.assertEqual(self.raid(b).phase, 'watch')                                # 3 jours depuis le départ
        self.run_lua(f'NOTE("{b}", {end // 24 + 1}, {end // 24 + 2}, "{KEY_A}")')
        self.step_to(72 + 71)
        self.assertEqual(self.raid(b).phase, 'watch')
        self.step_to(72 + 72)
        self.assertEqual(self.raid(b).phase, 'scout')

    def test_no_raid_on_occupants_who_are_not_hostile(self):
        gid = self.watched()
        for fact in ('mission_success', 'mission_success', 'mission_success', 'gift', 'gift'):
            self.ev(f'LivingKnox.Hostility.record("{gid}", "{KEY_A}", "{fact}", {{ attributable = true }})')
        self.assertNotEqual(self.ev(f'LivingKnox.Hostility.get("{gid}", "{KEY_A}").level'), 'hostile')
        self.step_to(72)
        self.assertEqual(self.raid(gid).phase, 'watch')
        self.assertTrue(any('no hostile occupant' in line for line in self.lk()))
        # Pendant l'attente de l'attaque : paix faite -> fin "peace".
        other = self.watched(name='Other', key=KEY_B)
        self.step_to(73)
        self.assertEqual(self.raid(other).phase, 'scout')
        for hour in range(74, 90):
            self.step_to(hour)
            if self.raid(other).phase == 'ready':
                break
        for fact in ('mission_success', 'mission_success', 'mission_success', 'gift', 'gift'):
            self.ev(f'LivingKnox.Hostility.record("{other}", "{KEY_B}", "{fact}", {{ attributable = true }})')
        self.step_to(hour + 30)
        self.assertIsNone(self.raid(other))
        self.assertEqual(self.log(other)[-1], 'raid on 1000,1600 ended: peace')

    def test_raids_disabled_end_a_watch_and_occupant_without_identity_counts(self):
        gid = self.mk()
        self.run_lua(f'NOTE("{gid}", 1, 2, nil)')                                   # occupant sans carnet
        self.run_lua('SandboxVars.LivingKnox.RaidsEnabled = false')
        self.step_to(72)
        self.assertIsNone(self.raid(gid))
        self.assertEqual(self.log(gid)[-1], 'raid on 1000,1600 ended: disabled')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").raidLast'))       # aucun raid parti
        self.run_lua('SandboxVars.LivingKnox.RaidsEnabled = true')
        other = self.mk(name='Other')
        self.run_lua(f'NOTE("{other}", 3, 4, nil)')
        self.step_to(73)
        self.assertEqual(self.raid(other).phase, 'scout')                            # niveau de départ : hostile

    def test_saved_and_reread_and_checked_in_its_form(self):
        gid = self.watched()
        self.step_to(72)
        self.h.load(self.srv, 'LivingKnox.Groups.flush()')  # arrêt propre : écriture différée faite (LK13-T06)
        root, age = self.h.root, self.h.age_minutes
        self.h._tmp = None
        self.h.close()
        self.h = self.make(root=root)
        self.h.age_minutes = age
        self.h._push_clock()
        self.addCleanup(shutil.rmtree, root, True)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        r = self.raid(gid)
        self.assertEqual((r.phase, r.step, lua_list(r.team), r.base.id), ('scout', 'out', ['m-2', 'm-3'], 'b:7'))
        bad = self.run_lua(f'local r = LivingKnox.Groups.state.data.groups["{gid}"].raid '
                           f'local a = {{ {RA}.validRaid(r) }} r.step = "dance" '
                           f'local b = {{ {RA}.validRaid(r) }} return a[1], b[1], b[2]')
        self.assertEqual(bad, (True, False, 'bad step'))
        self.ev(f'{RA}.offscreenHour(LivingKnox.Groups.state.data, LivingKnox.Groups.state.data.groups["{gid}"], '
                f'"{gid}", 0)')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.state.data.groups["{gid}"].raid'))
        self.assertTrue(any('record dropped: bad step' in line for line in self.lk()))
        base = ('{ id = "b:1", x1 = 1, y1 = 1, x2 = 2, y2 = 2, x = 1, y = 1, z = 0, src = "building" }')
        for case in ('r.base.src = "cave"', 'r.occ = {}', 'r.occ[1].k = "a b"', 'r.team = {}', 'r.leave = r.arrive - 1',
                     'r.ending = "x"', 'r.seen = 0', 'r.phase = "ready"'):
            with self.subTest(case=case):
                out = self.run_lua(f'local r = {{ v = 1, phase = "raid", step = "at", base = {base}, signs = "x", '
                                   'seen = 2, last = 2, k = 1, occ = { { u = "A", k = "c-alpha" } }, start = 1, '
                                   'team = { "m-2" }, dep = 1, arrive = 2, leave = 3, travel = 1 } '
                                   f'{case} return {RA}.validRaid(r)')
                self.assertFalse(out[0] if isinstance(out, tuple) else out)

    def test_same_hours_one_by_one_or_caught_up_give_the_same_registry(self):
        def run(one_by_one):
            h = self.make()
            try:
                h.fire(self.srv, 'OnInitGlobalModData', True)
                h.load(self.srv, f'BIND("A", "{KEY_A}")')
                h.eval(self.srv, f'{SIM}.step()')
                code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "marauders", name = "Crows", '
                        'day = 1, home = { x = 1000, y = 1000, z = 0 } })) ')
                for role in CREW:
                    code += f'assert(G.addMember(g.id, {{ role = "{role}", day = 1 }})) '
                gid = h.load(self.srv, code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
                h.load(self.srv, f'NOTE("{gid}", 1, 2, "{KEY_A}")')
                if one_by_one:
                    for k in range(1, 121):
                        h.eval(self.srv, f'{SIM}.step({k})')
                else:
                    h.eval(self.srv, f'{SIM}.step(60)')
                    h.eval(self.srv, f'{SIM}.step(120)')
                return h.eval(self.srv, CANON)
            finally:
                h.close()
        a, b = run(True), run(False)
        self.assertEqual(a, b)
        self.assertIn('7261696' , a)   # « rai(d) » encodé : le champ est bien là


class HuntBase(MatBase):
    """Pile des corps (serveur dédié + deux clients) avec le cadre de décision ; foyer 110,110, base à 400,400."""
    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, DECIDERS)
        h.load(srv, DUMP)
        h.load(srv, MARAUDERS)
        h.load(srv, 'shared/LivingKnox/Data/LK_Type_raiders.lua')
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, RELATIONS)
            h.load(m, RAIDS)
        h.load(srv, SURVEY)
        return h

    def setUp(self):
        super().setUp()
        self.run_lua(f'{D}.state.lastPass = 1e18')   # aucune décision avant le test
        self.run_lua(f'{RA}.CFG.SPEED = 100000 {RA}.settings = function() return {{ enabled = true, days = 0 }} end')
        self.players = ['A'] if self.mode == 'solo' else ['A', 'B']
        self.h.move_player('A', 400, 400)
        if self.mode != 'solo':
            self.h.move_player('B', 410, 395)
        self.gid = self.mk_group(crew=[('fighter', 'gunner', 'false'), ('fighter', 'gunner', 'false'),
                                       ('fighter', 'gunner', 'nil'), ('worker', 'cook', 'nil'),
                                       ('fighter', 'gunner', 'nil')], name='Crows')
        self.run_lua(f'LivingKnox.Groups.update(function(d) local g = d.groups["{self.gid}"] g.type = "marauders" '
                     'g.members["m-2"].role = "scout" return true, true end)')
        self.ev(f'{SIM}.step()')
        self.h0 = self.ev(f'{SIM}.currentHour()')
        self.run_lua(f'NOTE("{self.gid}", 1, 2, "c-alpha", BASE("b:9", 400, 400))')
        self.ev(f'{SIM}.step({self.h0 + 1})')          # départ des éclaireurs (fréquence nulle), une heure de trajet
        self.ev(f'{SIM}.step({self.h0 + 2})')          # arrivée : guet
        r = self.ev(f'LivingKnox.Groups.get("{self.gid}").raid')
        self.assertEqual((r.phase, r.step), ('scout', 'at'))
        self.team = lua_list(r.team)

    def passes(self, n=3):
        return sum(self.ev(f'{RA}.pass()') for _ in range(n))

    def player_gap(self, x, y):
        return min(max(abs(x - self.ev(f'HARNESS.players.{p}:getX()')), abs(y - self.ev(f'HARNESS.players.{p}:getY()')))
                   for p in self.players)


class HuntTests(HuntBase):
    def test_scout_bodies_appear_away_from_every_player_and_watch_the_base(self):
        self.assertEqual(self.team, ['m-2', 'm-3'])       # éclaireur d'abord, puis un combattant ; jamais le chef
        self.assertEqual(self.passes(), 2)
        self.assertEqual(self.bodies(self.gid), ['m-2', 'm-3'])
        for mid in self.team:
            x, y = self.body_xy(self.gid, mid)
            with self.subTest(mid=mid):
                self.assertGreaterEqual(self.player_gap(x, y), self.ev(f'{R}.REVENGE.SPAWN_MIN'))
                self.assertLessEqual(max(abs(x - 400), abs(y - 400)), 76)   # près de la base, côté foyer
                self.assertLess(x + y, 800)
        self.assertIsNone(self.member(self.gid, 'm-1', 'npc'))           # jamais au foyer
        self.assertEqual(self.passes(), 0)                                # pas de doublon
        # Cadre de décision : comportement de traque, raison « raid », ronde des éclaireurs à WATCH_RADIUS.
        self.run_lua(f'{D}.state.lastPass = nil {D}.reset()')
        for _ in range(4):
            self.h.advance_ms(1000)
            self.h.tick(len(self.team))   # LK13-T11 : membres d'un passage évalués un par image
        for mid in self.team:
            with self.subTest(mid=mid):
                st = self.run_lua(f'local s = {D}.get(MEMBER_NPC("{self.gid}", "{mid}")) return s.rule, s.b, s.why')
                self.assertEqual(st, ('duty', 'revenge', 'raid 1 hunt'))
                d = self.ev(f'DIRECTIVE("{self.gid}", "{mid}")')
                self.assertEqual(d.op, 'move')
                x, y = self.body_xy(self.gid, mid)
                self.assertLess(max(abs(d.x - 400), abs(d.y - 400)), max(abs(x - 400), abs(y - 400)))
        self.assertEqual(self.ev(f'{RA}.memberHunt("{self.gid}", "m-2").patrol'), self.ev(f'{RA}.CFG.WATCH_RADIUS'))
        self.assertEqual(self.h.errors('server'), [])
        if self.mode != 'solo':
            for c in ('A', 'B'):
                self.assertIsNone(self.h.eval(c, RA))

    def test_no_body_when_only_squares_near_the_players_are_loaded_or_nobody_is_home(self):
        self.run_lua('UNLOADED = { { -10000, 364, -10000, 10000 }, { 436, 10000, -10000, 10000 }, '
                     '{ -10000, 10000, -10000, 364 }, { -10000, 10000, 436, 10000 } }')
        self.assertEqual(self.passes(), 0)
        self.assertGreater(self.ev(f'{RA}.stats.spawnWaits'), 0)
        self.run_lua('UNLOADED = {}')
        for p in self.players:
            self.h.move_player(p, 700, 700)
        self.assertEqual(self.passes(), 0)
        self.assertEqual(self.bodies(self.gid), [])

    def test_attack_team_bodies_far_from_the_players_then_announce_line(self):
        self.passes()
        self.run_lua(f'SAID = {{}} {R}.say = function(npc, key, player, band) '
                     'SAID[#SAID + 1] = { npc = npc, key = key, band = band } return true end')
        self.ev(f'{SIM}.step({self.h0 + 6})')          # fin du guet (4 h) : annonce, retour
        self.assertTrue(any(t.startswith('scouts saw the base at 400,400') for t in
                            lua_list(self.ev(f'RAID_LOG("{self.gid}")'))))
        self.assertEqual(self.ev(f'#{RA}.state.lines'), 1)                  # réplique d'un éclaireur incarné
        self.assertEqual(self.ev('#SAID'), 0)                               # pas dans l'écriture du registre
        self.passes(1)
        self.assertEqual(self.ev(f'#{RA}.state.lines'), 0)
        said = self.ev('SAID[1]')
        self.assertEqual((said.npc, said.key, said.band),
                         (self.member(self.gid, 'm-2', 'npc'), 'IGUI_LK_Raid_Scouted', 'hostile'))
        for p in self.players:
            self.h.move_player(p, 1000, 1000)          # loin de tout : corps rendus à la simulation
        self.wait(70)
        self.run_lua(f'{RA}.CFG.ANNOUNCE_HOURS = 0')
        for k in range(7, 12):
            self.ev(f'{SIM}.step({self.h0 + k})')
            if self.ev(f'LivingKnox.Groups.get("{self.gid}").raid.phase') == 'raid':
                break
        for p in self.players:
            self.h.move_player(p, 400, 400 if p == 'A' else 402)
        self.ev(f'{SIM}.step({self.h0 + k + 1})')
        r = self.ev(f'LivingKnox.Groups.get("{self.gid}").raid')
        self.assertEqual((r.phase, r.step), ('raid', 'at'))
        team = lua_list(r.team)
        self.assertGreaterEqual(len(team), 2)
        self.assertNotIn('m-1', team)
        self.assertEqual(self.passes(4), len(team))
        for mid in team:
            x, y = self.body_xy(self.gid, mid)
            with self.subTest(mid=mid):
                self.assertGreaterEqual(self.player_gap(x, y), self.ev(f'{R}.REVENGE.SPAWN_MIN'))
        self.assertEqual(self.ev(f'{RA}.memberHunt("{self.gid}", "{team[0]}").patrol'),
                         self.ev(f'{RA}.CFG.ATTACK_RADIUS'))


class SoloHuntTests(HuntTests):
    mode = 'solo'


SUITE_TESTS = ('scouts, announce, real team far from the players, return', 'killed scouts call the raid off')


class SuiteTests(HuntBase):
    """La suite en jeu lk.raid passe dans le banc (joueur A dehors, loin de tout foyer)."""

    def setUp(self):
        MatBase.setUp(self)
        self.players = ['A', 'B']
        self.h.move_player('A', 400, 400)
        self.h.move_player('B', 405, 402)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKRaid.lua')

    def run_suite(self, prep=''):
        if prep:
            self.run_lua(prep)
        self.run_lua('PLAYER = HARNESS.players.A')
        self.assertTrue(self.ev('RST.start({ suite = "lk.raid", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(800):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        before = set(lua_list(self.ev('LivingKnox.Groups.list()')))
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 2)
        self.assertEqual(set(lua_list(self.ev('LivingKnox.Groups.list()'))), before)
        self.assertEqual(self.ev(f'{RA}.CFG.SCOUT_HOURS'), 4)
        self.assertEqual(self.ev(f'{RA}.settings().days'), 14)
        self.assertEqual(self.ev('ALL_TAGGED()'), 0)

    def test_suite_detects_a_body_spawned_next_to_the_player(self):
        _, results = self.run_suite(f'{R}.spawnSquare = function(zone, home, players, used) '
                                    'return getCell():getGridSquare(402, 400, 0) end')
        self.assertEqual(results[SUITE_TESTS[0]][0], 'FAIL')


class SourceTests(unittest.TestCase):
    def test_options_translations_and_ascii_code(self):
        opts = (MEDIA / 'sandbox-options.txt').read_text(encoding='utf-8')
        self.assertIn('option LivingKnox.RaidsEnabled\n{\n\ttype = boolean,\n\tdefault = true,', opts)
        self.assertRegex(opts, r'option LivingKnox\.RaidDays\n\{\n\ttype = integer,\n\tmin = 3,\n\tmax = 90,\n'
                               r'\tdefault = 14,')
        for lang in ('EN', 'FR'):
            ui = json.loads((LUA / 'shared' / 'Translate' / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            ui['IGUI_LK_Raid_Scouted'].encode('latin-1')
            sb = json.loads((LUA / 'shared' / 'Translate' / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            for k in ('RaidsEnabled', 'RaidsEnabled_tooltip', 'RaidDays', 'RaidDays_tooltip'):
                sb['Sandbox_LivingKnox_' + k].encode('latin-1')
        src = (LUA / RAIDS).read_text(encoding='utf-8')
        for n, line in enumerate(src.splitlines(), 1):
            with self.subTest(line=n):
                self.assertTrue(line.split('--', 1)[0].isascii(), line)
        self.assertIsNone(re.search(r'\bgoto\b|\bnext\(|\bcoroutine\.', src))
        self.assertTrue(SUITE_FILE.exists())


if __name__ == '__main__':
    unittest.main()
