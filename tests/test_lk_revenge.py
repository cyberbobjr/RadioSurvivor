"""Tests hors jeu de la vengeance différée d'un groupe Living Knox (LK11-T05) : section « vengeance » de
server/LivingKnox/LK_Relations.lua, branchée dans LK_Simulation.lua (heure hors écran, retour de l'équipe),
LK_Decisions.lua (comportement « revenge ») et LK_Hostility.lua (raison de cible « revenge »), et la suite en jeu
lk.revenge (dev/.../RST_LKRevenge.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_revenge.py

Bancs tests/harness.py :
- hors écran (serveur dédié + deux clients, registres réels des groupes et des attitudes, simulation réelle) :
  serment selon le type et l'attitude, délai, équipe tirée de l'effectif réel, trajet, traque, retour, abandon après
  MAX_FAILS traques manquées, rancune éteinte, cible morte, persistance, reproductibilité ;
- à l'écran (pile des corps de test_lk_materialize.py, cadre de décision, type de test « avengers ») : corps de
  l'équipe créés seulement à SPAWN_MIN cases au moins de tout joueur, jamais au foyer, comportement « revenge » et
  marche vers la zone, attente si seules des cases proches des joueurs sont chargées.
Les doublures NE PROUVENT PAS l'API réelle (SafeHouse, addZombiesInOutfit, chemins) : seulement la logique. Le rendu,
la marche réelle et l'engagement se vérifient en jeu (suite lk.revenge, protocole de docs/conception/vengeance.md).
"""
from __future__ import annotations

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

R = 'LivingKnox.Relations'
SIM = 'LivingKnox.Simulation'
D = 'LivingKnox.Decisions'
RELATIONS = 'server/LivingKnox/LK_Relations.lua'
ROOT = Path(__file__).resolve().parents[1]
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared' / 'RST' / 'suites' \
    / 'RST_LKRevenge.lua'
KEY_A, KEY_B = 'c-alpha', 'c-bravo'
CANON = ('require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes('
         'LivingKnox.Groups.state.data))')

# Type de test : combattants (fight, defend) et ouvriers ; hostilité 60 -> départ prudent (-12), meurtre -> hostile.
AVENGERS = r'''
if not LivingKnox.GroupTypes.isKnown("avengers") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "avengers", nameKey = "IGUI_LK_GroupType_raiders", size = { min = 1, max = 12 },
        hostility = 60, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard", "defend", "fight" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } } },
        profiles = {
            { id = "gunner", role = "fighter", weight = 1, weapons = { "Base.Shotgun" }, looks = { "manFairBeard" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
'''

# Identité du carnet (RS_Carnet_Server.bound) et faits publiés relevés.
CARNET = r'''
RS_CarnetServer = RS_CarnetServer or { bound = {} }
function BIND(name, key) RS_CarnetServer.bound[HARNESS.players[name]] = key end
REV_FACTS = {}
for _, n in ipairs({ "revengeSworn", "revengeStarted", "revengeEnded" }) do
    LivingKnox.listen(n, "test", function(info) REV_FACTS[#REV_FACTS + 1] = { name = n, info = info } end)
end
SafeHouse = { hasSafehouse = function(u) return SAFEHOUSES and SAFEHOUSES[u] or nil end }
local SH = {}
SH.__index = SH
function SH:getX() return self.x end
function SH:getY() return self.y end
function SH:getW() return self.w end
function SH:getH() return self.h end
function SAFEHOUSE(u, x, y, w, h)
    SAFEHOUSES = SAFEHOUSES or {}
    SAFEHOUSES[u] = setmetatable({ x = x, y = y, w = w, h = h }, SH)
end
function REV_LOG(gid)
    local out = {}
    for _, e in ipairs(LivingKnox.Groups.get(gid).log) do
        if e.kind == "revenge" then out[#out + 1] = e.text end
    end
    return out
end
'''

# Équipage : m-1 chef combattant, m-2 et m-3 combattants, m-4 ouvrier, m-5 combattant.
CREW = ['fighter', 'fighter', 'fighter', 'worker', 'fighter']


class OffscreenBase(SimBase):
    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        h.load(self.srv, AVENGERS)
        for m in (('solo',) if self.mode == 'solo' else ('server', 'A', 'B')):
            h.load(m, RELATIONS)
        h.load(self.srv, CARNET)
        return h

    def setUp(self):
        super().setUp()
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.run_lua(f'{R}.REVENGE.SPEED = 300')
        self.run_lua('BIND("A", "c-alpha")')
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        self.h0 = self.ev(f'{SIM}.currentHour()')

    def mk(self, gtype='avengers', crew=CREW, home=(1000, 1000, 0), name='Crows'):
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "{gtype}", name = "{name}", day = 1, '
                f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }})) ')
        for role in crew:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", day = 1 }})) '
        return self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')

    def kill(self, gid, mid='m-4', key=KEY_A, x=1000, y=1600, u='A'):
        self.run_lua(f'LivingKnox.Groups.markDead("{gid}", "{mid}")')
        return self.run_lua(f'return {R}.memberKilled("{gid}", "{mid}", "{key}", '
                            f'{{ u = "{u}", x = {x}, y = {y}, z = 0 }})')

    def rev(self, gid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").revenge')

    def step_to(self, hour):
        return self.ev(f'{SIM}.step({hour})')

    def log(self, gid):
        return list(self.ev(f'REV_LOG("{gid}")').values())

    def facts(self):
        return [(f.name, f.info.player) for f in self.ev('REV_FACTS').values()]

    def level(self, gid, key=KEY_A):
        return self.ev(f'LivingKnox.Hostility.get("{gid}", "{key}").level')


class OathTests(OffscreenBase):
    def test_oath_depends_on_type_and_attitude(self):
        # Pillards : hostiles dès le départ, le meurtre les fait jurer.
        raiders = self.mk('raiders', ['deputy', 'fighter', 'breaker', 'worker'], name='Crows')
        out = self.kill(raiders)
        self.assertEqual((out.sworn, out.reason, out.level), (True, 'sworn', 'hostile'))
        r = self.rev(raiders)
        self.assertEqual((r.key, r.u, r.victim, r.phase, r.fails, r.n), (KEY_A, 'A', 'm-4', 'sworn', 0, 0))
        self.assertEqual(r.due - r.sworn, 72)
        self.assertEqual((r.zone.x, r.zone.y, r.zone.src), (1000, 1600, 'kill'))
        self.assertEqual(self.log(raiders), ['m-4 killed by c-alpha: revenge sworn, leaving in 72 h'])
        self.assertEqual(self.facts(), [('revengeSworn', KEY_A)])
        # Colons : un premier meurtre les laisse prudents (50 - 60 = -10) : pas de serment ; le second les fait jurer.
        settlers = self.mk('settlers', ['deputy', 'fighter', 'fighter', 'worker', 'worker'], name='Mill')
        out = self.kill(settlers)
        self.assertEqual((out.sworn, out.reason, out.level), (False, 'attitude cautious', 'cautious'))
        self.assertIsNone(self.rev(settlers))
        out = self.kill(settlers, mid='m-5')
        self.assertEqual((out.sworn, out.level), (True, 'hostile'))
        # Neutres : hostiles après un seul meurtre (6 - 60).
        neutrals = self.mk('neutrals', ['deputy', 'fighter', 'fighter', 'worker'], name='Ford')
        self.assertTrue(self.kill(neutrals).sworn)

    def test_one_revenge_per_group_and_enough_fighters(self):
        gid = self.mk()
        self.assertTrue(self.kill(gid).sworn)
        self.run_lua('BIND("B", "c-bravo")')
        again = self.kill(gid, mid='m-5', key=KEY_B, u='B')
        self.assertEqual((again.sworn, again.reason), (False, 'busy'))
        same = self.kill(gid, mid='m-3')
        self.assertEqual((same.sworn, same.reason), (False, 'already sworn'))
        self.assertEqual(self.rev(gid).key, KEY_A)
        # Un seul combattant hors chef : trop faible pour jurer.
        weak = self.mk(crew=['fighter', 'fighter', 'worker', 'worker'], name='Weak')
        self.run_lua(f'LivingKnox.Groups.markDead("{weak}", "m-2")')
        out = self.kill(weak, mid='m-3')
        self.assertEqual((out.sworn, out.reason), (False, 'too weak'))
        # Désactivée : rien.
        self.run_lua(f'{R}.REVENGE.ENABLED = false')
        off = self.mk(name='Off')
        self.assertEqual(self.kill(off).reason, 'disabled')
        # Toujours un fait d'attitude « kill » attribuable (déclin plafonné après un meurtre).
        self.assertIs(self.ev(f'LivingKnox.Hostility.debugPair("{off}", "{KEY_A}").murder'), True)

    def test_npc_died_fact_needs_a_player_identified_by_the_server(self):
        gid = self.mk()
        # Tueur sans personnage du carnet : ni fait ni serment.
        self.run_lua(f'{R}.onNpcDied({{ group = "{gid}", member = "m-4", npc = "lk-9", killer = "B", '
                     'x = 1000, y = 1600, z = 0 })')
        self.assertIsNone(self.rev(gid))
        self.assertIsNone(self.ev(f'LivingKnox.Hostility.debugPair("{gid}", "{KEY_B}")'))
        # Mort sans tueur (feu, zombie) : rien.
        self.run_lua(f'{R}.onNpcDied({{ group = "{gid}", member = "m-4", npc = "lk-9", x = 1, y = 1, z = 0 }})')
        self.assertIsNone(self.rev(gid))
        # Fait publié par LK_Bodies (npcDied) : joueur identifié par son compte, puis sa clé du carnet.
        self.run_lua(f'LivingKnox.publish("npcDied", {{ group = "{gid}", member = "m-4", npc = "lk-9", '
                     'killer = "A", x = 1000, y = 1600, z = 0 })')
        self.assertEqual(self.rev(gid).key, KEY_A)
        # E09-T06: RS_Factions also listens to npcDied (incidents of a truce): one listener of Relations.
        self.assertEqual(self.ev('(function() local n = 0 for _, e in ipairs(LivingKnox.listeners.npcDied) do '
                                 'if e.key == "Relations.revenge" then n = n + 1 end end return n end)()'), 1)

    def test_revenge_target_is_attacked_by_the_existing_target_choice(self):
        gid = self.mk()
        self.run_lua('BIND("B", "c-bravo")')
        cands = (f'{{ {{ u = "A", key = "{KEY_A}", d = 9 }}, {{ u = "B", key = "{KEY_B}", d = 3 }} }}')
        res = self.ev(f'LivingKnox.Hostility.chooseTarget("{gid}", "lk-1", {cands})')
        self.assertIsNone(res.target)                                        # prudents : ni attaque ni sommation
        self.kill(gid)
        # Le lendemain (provocation passée) : la vengeance seule désigne A.
        res = self.ev(f'LivingKnox.Hostility.chooseTarget("{gid}", "lk-1", {cands}, LivingKnox.Groups.today() + 5)')
        self.assertEqual((res.target.u, res.target.action, res.target.reason), ('A', 'attack', 'revenge'))
        self.assertEqual(len(list(res.list.values())), 1)
        self.assertEqual(self.run_lua('return LivingKnox.Hostility.targetRule({ level = "trusting", revenge = true })'),
                         ('attack', 'revenge'))
        self.assertEqual(self.run_lua('return LivingKnox.Hostility.targetRule({ covered = true, revenge = true })'),
                         (None, 'covered'))


class DelayOptionTests(OffscreenBase):
    """LK11-T10 : délai du serment au départ = option sandbox LivingKnox.RevengeDelayHours (entier 12..336, défaut 72),
    lue au serment. Doublure de getSandboxOptions():getOptionByName(nom) fidèle à SandboxOptions.java : nil pour une
    option inconnue, sinon un objet dont getValue() rend un nombre (option integer) et dont setValue(n) hors
    min..max est ignoré (IntegerConfigOption). JAVA_OPTIONS écrit directement : valeurs invalides pour la robustesse."""

    OPTION = r'''
    JAVA_OPTIONS = JAVA_OPTIONS or {}
    local BOUNDS = { ["LivingKnox.RevengeDelayHours"] = { 12, 336 } }
    getSandboxOptions = function()
        return { getOptionByName = function(_, name)
            if JAVA_OPTIONS[name] == nil then return nil end
            return { getValue = function() return JAVA_OPTIONS[name] end,
                     setValue = function(_, n)
                         local b = BOUNDS[name]
                         if b == nil or (n >= b[1] and n <= b[2]) then JAVA_OPTIONS[name] = n end
                     end }
        end }
    end
    '''

    def set_option(self, value):
        self.run_lua(f'JAVA_OPTIONS["LivingKnox.RevengeDelayHours"] = {value}')

    def setUp(self):
        super().setUp()
        self.run_lua(self.OPTION)

    def test_option_sets_the_departure_after_the_oath(self):
        self.set_option(24)
        gid = self.mk()
        self.assertTrue(self.kill(gid).sworn)
        r = self.rev(gid)
        self.assertEqual(r.due - r.sworn, 24)
        self.assertEqual(self.log(gid), ['m-4 killed by c-alpha: revenge sworn, leaving in 24 h'])
        self.step_to(r.due - 1)
        self.assertEqual(self.rev(gid).phase, 'sworn')
        self.step_to(r.due)
        self.assertEqual((self.rev(gid).phase, self.rev(gid).dep), ('out', r.due))

    def test_absent_or_out_of_bounds_option_gives_72_hours(self):
        names = iter(['G1', 'G2', 'G3', 'G4', 'G5', 'G6'])
        gid = self.mk(name=next(names))                       # option unknown to Java, no SandboxVars
        self.assertTrue(self.kill(gid).sworn)
        self.assertEqual(self.rev(gid).due - self.rev(gid).sworn, 72)
        for bad in ('11', '337', '24.5', '-1', '"x"'):
            with self.subTest(value=bad):
                self.set_option(bad)
                gid = self.mk(name=next(names))
                self.assertTrue(self.kill(gid).sworn)
                self.assertEqual(self.rev(gid).due - self.rev(gid).sworn, 72)
        self.assertEqual(self.ev(f'{R}.revengeDelayHours()'), 72)
        self.set_option(12)
        self.assertEqual(self.ev(f'{R}.revengeDelayHours()'), 12)
        self.set_option(336)
        self.assertEqual(self.ev(f'{R}.revengeDelayHours()'), 336)

    def test_sandbox_vars_fallback(self):
        self.run_lua('SandboxVars = SandboxVars or {} SandboxVars.LivingKnox = SandboxVars.LivingKnox or {} '
                     'SandboxVars.LivingKnox.RevengeDelayHours = 48')
        try:
            self.assertEqual(self.ev(f'{R}.revengeDelayHours()'), 48)
            self.set_option(30)                                # registered (Java) option first
            self.assertEqual(self.ev(f'{R}.revengeDelayHours()'), 30)
        finally:
            self.run_lua('SandboxVars.LivingKnox.RevengeDelayHours = nil')

    def test_sworn_revenge_keeps_its_departure_when_the_option_changes(self):
        self.set_option(24)
        first = self.mk(name='Crows')
        self.assertTrue(self.kill(first).sworn)
        due = self.rev(first).due
        self.set_option(200)
        self.step_to(self.h0 + 1)
        self.assertEqual(self.rev(first).due, due)
        self.step_to(due)
        self.assertEqual(self.rev(first).phase, 'out')
        second = self.mk(name='Ford')                          # the next oath reads the new value
        self.assertTrue(self.kill(second, mid='m-5').sworn)
        self.assertEqual(self.rev(second).due - self.rev(second).sworn, 200)

    def test_forced_delay_wins_over_the_option(self):
        self.set_option(24)
        self.run_lua(f'{R}.REVENGE.DELAY_HOURS = 0')
        try:
            gid = self.mk()
            self.assertTrue(self.kill(gid).sworn)
            self.assertEqual(self.rev(gid).due, self.rev(gid).sworn)
        finally:
            self.run_lua(f'{R}.REVENGE.DELAY_HOURS = nil')


class OffscreenTests(OffscreenBase):
    def sworn(self, **kw):
        gid = self.mk()
        self.assertTrue(self.kill(gid, **kw).sworn)
        return gid

    def test_delay_then_a_real_team_leaves_home(self):
        gid = self.sworn()
        due = self.rev(gid).due
        self.step_to(due - 1)
        self.assertEqual(self.rev(gid).phase, 'sworn')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        self.step_to(due)
        r = self.rev(gid)
        # Combattants vivants hors chef, au foyer, par numéro ; TEAM_MAX = 3, un vivant au moins reste.
        self.assertEqual(lua_list(r.team), ['m-2', 'm-3', 'm-5'])
        self.assertEqual((r.phase, r.n, r.dep, r.travel, r.arrive - r.dep), ('out', 1, due, 2, 2))
        e = self.ev(f'LivingKnox.Groups.get("{gid}").expedition')
        self.assertEqual((e.place, e.departed, e.returns), ('revenge', due, r.leave + 2))
        self.assertEqual(lua_list(e.team), ['m-2', 'm-3', 'm-5'])
        # Absents du foyer : ni matérialisés au foyer, ni dans la simulation horaire.
        g = f'LivingKnox.Groups.get("{gid}")'
        self.assertEqual(lua_list(self.ev(f'LivingKnox.Materialize.presentMembers({g})')), ['m-1'])
        self.assertEqual(lua_list(self.ev(f'{SIM}.homeMembers({g}, {{ "m-1", "m-2", "m-3", "m-5" }})')), ['m-1'])
        self.assertEqual(self.log(gid)[-1], 'attempt 1 on c-alpha: m-2 m-3 m-5 left for 1000,1600 (kill), 2 h away')
        self.assertEqual(self.facts()[-1], ('revengeStarted', KEY_A))
        # Aucun membre créé de rien : l'effectif du groupe est inchangé.
        self.assertEqual(self.ev(f'LivingKnox.Groups.livingCount({g})'), 4)
        self.assertEqual(self.ev(f'{g}.nextMember'), 6)

    def test_team_waits_while_too_small_or_busy(self):
        gid = self.sworn()
        due = self.rev(gid).due
        self.step_to(due - 1)
        self.run_lua(f'local d = LivingKnox.Groups.state.data.groups["{gid}"] '
                     'd.members["m-2"].wound = 50 d.members["m-3"].wound = 50')
        self.step_to(due + 3)
        self.assertEqual(self.rev(gid).phase, 'sworn')                       # un seul valide : attente
        self.run_lua(f'local d = LivingKnox.Groups.state.data.groups["{gid}"] '
                     'd.members["m-2"].wound = nil d.members["m-3"].wound = nil '
                     'd.expedition = { place = "houses", team = { "m-2" }, departed = 0, returns = 100000 }')
        self.step_to(due + 4)
        self.assertEqual(self.rev(gid).phase, 'sworn')                       # expédition en cours : attente
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].expedition = nil')
        self.step_to(due + 5)
        self.assertEqual(self.rev(gid).phase, 'out')

    def test_three_failed_hunts_then_abandon(self):
        gid = self.sworn()
        h = self.rev(gid).due
        seen = []
        for _ in range(200):
            h += 1
            self.step_to(h)
            r = self.rev(gid)
            if r is None:
                break
            seen.append((r.phase, r.fails))
        self.assertIsNone(self.rev(gid))
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        self.assertIn(('hunt', 0), seen)
        self.assertIn(('back', 1), seen)
        self.assertIn(('sworn', 2), seen)
        # Équipe de chaque départ : combattants vivants hors chef de l'effectif réel (une blessure tirée par la
        # simulation peut en retenir un au foyer).
        pattern = [r'attempt 1 on c-alpha: (m-[235] ?)+ left for 1000,1600 \(kill\), 2 h away',
                   r'attempt 1 on c-alpha failed \(1/3\): heading home', r'attempt 1 on c-alpha: [1-3] back home',
                   r'attempt 2 on c-alpha: (m-[235] ?)+ left for 1000,1600 \(kill\), 2 h away',
                   r'attempt 2 on c-alpha failed \(2/3\): heading home', r'attempt 2 on c-alpha: [1-3] back home',
                   r'attempt 3 on c-alpha: (m-[235] ?)+ left for 1000,1600 \(kill\), 2 h away',
                   r'attempt 3 on c-alpha failed \(3/3\): heading home', r'attempt 3 on c-alpha: [1-3] back home',
                   r'revenge on c-alpha ended: given_up \(3 attempt\(s\), 3 failed\)']
        got = self.log(gid)[-10:]
        self.assertEqual(len(got), 10)
        for line, pat in zip(got, pattern):
            self.assertRegex(line, '^' + pat + '$')
        ended = [f for f in self.ev('REV_FACTS').values() if f.name == 'revengeEnded']
        self.assertEqual([(f.info.ending, f.info.fails) for f in ended], [('given_up', 3)])
        # Tous revenus, vivants, présents au foyer ; la cible n'est plus attaquée pour la vengeance.
        g = f'LivingKnox.Groups.get("{gid}")'
        self.assertEqual(lua_list(self.ev(f'LivingKnox.Materialize.presentMembers({g})')),
                         ['m-1', 'm-2', 'm-3', 'm-5'])
        self.assertIs(self.ev(f'LivingKnox.Hostility.isRevengeTarget("{gid}", "{KEY_A}")'), False)

    def test_grudge_fades_with_the_attitude(self):
        # Neutres : -54 après le meurtre, déclin de 2 par jour vers -15 : méfiants (-44) après 5 jours.
        gid = self.mk('neutrals', ['deputy', 'fighter', 'fighter', 'fighter', 'worker'], name='Ford')
        self.assertTrue(self.kill(gid, mid='m-5').sworn)
        self.run_lua(f'{R}.REVENGE.DELAY_HOURS = 200')
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].revenge.due = '
                     f'LivingKnox.Groups.state.data.groups["{gid}"].revenge.sworn + 200')
        day = self.ev('LivingKnox.Groups.today()')
        self.ev(f'LivingKnox.Hostility.decay({day + 4})')
        self.step_to(self.h0 + 1)
        self.assertEqual(self.rev(gid).phase, 'sworn')
        self.ev(f'LivingKnox.Hostility.decay({day + 5})')
        self.assertEqual(self.level(gid), 'wary')
        self.step_to(self.h0 + 2)
        self.assertIsNone(self.rev(gid))
        self.assertEqual(self.log(gid)[-1], 'revenge on c-alpha ended: faded (0 attempt(s), 0 failed)')

    def test_grudge_fading_during_the_trip_turns_the_team_back(self):
        gid = self.sworn()
        due = self.rev(gid).due
        self.step_to(due)
        self.assertEqual(self.rev(gid).phase, 'out')
        # Une mission réussie et un don ramènent l'attitude au-dessus d'hostile : la rancune s'éteint.
        for fact in ('mission_success', 'mission_success', 'gift'):
            self.ev(f'LivingKnox.Hostility.record("{gid}", "{KEY_A}", "{fact}", {{ attributable = true }})')
        self.assertEqual(self.level(gid), 'wary')
        self.step_to(due + 1)
        r = self.rev(gid)
        self.assertEqual((r.phase, r.ending, r.fails), ('back', 'faded', 0))
        self.step_to(due + 3)
        self.assertIsNone(self.rev(gid))
        self.assertEqual(self.log(gid)[-1], 'revenge on c-alpha ended: faded (1 attempt(s), 0 failed)')

    def test_target_death_ends_the_revenge(self):
        gid = self.sworn()
        due = self.rev(gid).due
        self.step_to(due + 2)
        self.assertEqual(self.rev(gid).phase, 'hunt')
        self.h.kill_player('A')
        r = self.rev(gid)
        self.assertEqual((r.phase, r.ending), ('back', 'target_dead'))
        self.step_to(due + 6)
        self.assertIsNone(self.rev(gid))
        self.assertEqual(self.log(gid)[-1], 'revenge on c-alpha ended: target_dead (1 attempt(s), 0 failed)')
        # Pendant le délai : fin immédiate.
        other = self.mk(name='Other')
        self.run_lua('BIND("B", "c-bravo")')
        self.assertTrue(self.kill(other, key=KEY_B, u='B').sworn)
        self.h.kill_player('B')
        self.assertIsNone(self.rev(other))

    def test_team_wiped_out_counts_as_a_failure(self):
        gid = self.sworn()
        due = self.rev(gid).due
        self.step_to(due + 2)
        for mid in ('m-2', 'm-3', 'm-5'):
            self.run_lua(f'LivingKnox.Groups.markDead("{gid}", "{mid}")')
        self.step_to(due + 3)
        r = self.rev(gid)
        self.assertEqual((r.phase, r.fails), ('sworn', 1))
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").expedition'))
        self.assertEqual(self.log(gid)[-1], 'attempt 1 on c-alpha: no one came back (1/3)')
        # Plus personne pour partir : attente (la rancune ou un nouveau membre décidera).
        self.step_to(due + 40)
        self.assertEqual(self.rev(gid).phase, 'sworn')

    def test_last_known_zone_is_the_safehouse_of_the_killer(self):
        gid = self.sworn()
        self.run_lua('SAFEHOUSE("A", 1300, 1000, 10, 6)')
        self.step_to(self.rev(gid).due)
        r = self.rev(gid)
        self.assertEqual((r.zone.x, r.zone.y, r.zone.z, r.zone.src, r.travel), (1305, 1003, 0, 'safehouse', 2))

    def test_saved_and_reread_and_checked_in_its_form(self):
        gid = self.sworn()
        self.step_to(self.rev(gid).due)
        self.h.load(self.srv, 'LivingKnox.Groups.flush()')  # arrêt propre : écriture différée faite (LK13-T06)
        root, age = self.h.root, self.h.age_minutes
        self.h._tmp = None
        self.h.close()
        self.h = self.make(root=root)
        self.h.age_minutes = age
        self.h._push_clock()
        self.addCleanup(shutil.rmtree, root, True)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        r = self.rev(gid)
        self.assertEqual((r.phase, r.key, lua_list(r.team)), ('out', KEY_A, ['m-2', 'm-3', 'm-5']))
        # Forme contrôlée : malformée -> oubliée avec un avertissement, le groupe garde le reste.
        bad = self.run_lua(f'local r = LivingKnox.Groups.state.data.groups["{gid}"].revenge '
                           'local a = { {R}.validRevenge(r) } r.phase = "dance" '.replace('{R}', R) +
                           f'local b = {{ {R}.validRevenge(r) }} return a[1], b[1], b[2]')
        self.assertEqual(bad, (True, False, 'bad phase'))
        self.ev(f'{R}.offscreenHour(LivingKnox.Groups.state.data.groups["{gid}"], "{gid}", 0)')
        self.assertIsNone(self.ev(f'LivingKnox.Groups.state.data.groups["{gid}"].revenge'))
        self.assertTrue(any('record dropped: bad phase' in line for line in self.lk()))
        for case in ('r.key = "a b"', 'r.zone = nil', 'r.team = {}', 'r.leave = r.arrive - 1', 'r.ending = "x"',
                     'r.fails = -1'):
            with self.subTest(case=case):
                out = self.run_lua('local r = { v = 1, key = "k", victim = "m-1", sworn = 1, phase = "hunt", n = 1, '
                                   'fails = 0, zone = { x = 1, y = 1, z = 0, src = "kill" }, team = { "m-2" }, '
                                   f'dep = 1, arrive = 2, leave = 3, travel = 1 }} {case} return {R}.validRevenge(r)')
                self.assertFalse(out[0] if isinstance(out, tuple) else out)

    def test_same_hours_one_by_one_or_caught_up_give_the_same_registry(self):
        def run(one_by_one):
            h = self.make()
            try:
                h.fire(self.srv, 'OnInitGlobalModData', True)
                h.load(self.srv, 'BIND("A", "c-alpha")')
                h.eval(self.srv, f'{SIM}.step()')
                h0 = h.eval(self.srv, f'{SIM}.currentHour()')
                code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "avengers", name = "Crows", '
                        'day = 1, home = { x = 1000, y = 1000, z = 0 } })) ')
                for role in CREW:
                    code += f'assert(G.addMember(g.id, {{ role = "{role}", day = 1 }})) '
                gid = h.load(self.srv, code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
                h.load(self.srv, f'LivingKnox.Groups.markDead("{gid}", "m-4") '
                                 f'{R}.memberKilled("{gid}", "m-4", "c-alpha", {{ u = "A", x = 1000, y = 1600, '
                                 f'z = 0, hour = {h0} }})')
                if one_by_one:
                    for k in range(1, 73):
                        h.eval(self.srv, f'{SIM}.step({h0 + k})')
                    for k in range(73, 121):
                        h.eval(self.srv, f'{SIM}.step({h0 + k})')
                else:
                    h.eval(self.srv, f'{SIM}.step({h0 + 72})')
                    h.eval(self.srv, f'{SIM}.step({h0 + 120})')
                return h.eval(self.srv, CANON)
            finally:
                h.close()
        a, b = run(True), run(False)
        self.assertEqual(a, b)
        self.assertIn('72657665', a)   # « reve(nge) » encodé : le champ est bien là


class HuntBase(MatBase):
    """Pile des corps (serveur dédié + deux clients) avec le cadre de décision ; foyer 110,110 loin des joueurs."""
    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, DECIDERS)
        h.load(srv, DUMP)
        h.load(srv, AVENGERS)
        h.load(srv, 'shared/LivingKnox/Data/LK_Type_raiders.lua')
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, RELATIONS)
        h.load(srv, CARNET)
        return h

    def setUp(self):
        super().setUp()
        self.run_lua(f'{D}.state.lastPass = 1e18')   # aucune décision avant le test
        self.run_lua(f'{R}.REVENGE.SPEED = 100000 {R}.REVENGE.DELAY_HOURS = 0')
        self.run_lua('BIND("A", "c-alpha")')
        self.players = ['A'] if self.mode == 'solo' else ['A', 'B']
        self.h.move_player('A', 400, 400)
        if self.mode != 'solo':
            self.h.move_player('B', 410, 395)
        self.gid = self.mk_group(crew=[('fighter', 'gunner', 'false'), ('fighter', 'gunner', 'false'),
                                       ('fighter', 'gunner', 'nil'), ('worker', 'cook', 'nil'),
                                       ('worker', 'cook', 'nil')], name='Crows')
        self.run_lua(f'LivingKnox.Groups.update(function(d) d.groups["{self.gid}"].type = "avengers" '
                     'return true, true end)')
        self.ev(f'{SIM}.step()')
        self.h0 = self.ev(f'{SIM}.currentHour()')
        self.run_lua(f'LivingKnox.Groups.markDead("{self.gid}", "m-4")')
        out = self.run_lua(f'return {R}.memberKilled("{self.gid}", "m-4", "c-alpha", '
                           '{ u = "A", x = 400, y = 400, z = 0 })')
        self.assertTrue(out.sworn)
        self.ev(f'{SIM}.step({self.h0 + 1})')          # départ (délai nul), trajet d'une heure
        self.ev(f'{SIM}.step({self.h0 + 2})')          # arrivée : traque
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{self.gid}").revenge.phase'), 'hunt')
        self.team = lua_list(self.ev(f'LivingKnox.Groups.get("{self.gid}").revenge.team'))

    def hunt_passes(self, n=3):
        return sum(self.ev(f'{R}.huntPass()') for _ in range(n))

    def player_gap(self, x, y):
        return min(max(abs(x - self.ev(f'HARNESS.players.{p}:getX()')), abs(y - self.ev(f'HARNESS.players.{p}:getY()')))
                   for p in self.players)


class HuntTests(HuntBase):
    def test_team_bodies_appear_away_from_every_player(self):
        self.assertEqual(self.team, ['m-2', 'm-3'])       # combattants hors chef ; m-5 ouvrier, m-4 mort
        self.assertEqual(self.hunt_passes(), 2)
        self.assertEqual(self.bodies(self.gid), ['m-2', 'm-3'])
        for mid in self.team:
            x, y = self.body_xy(self.gid, mid)
            with self.subTest(mid=mid):
                self.assertGreaterEqual(self.player_gap(x, y), self.ev(f'{R}.REVENGE.SPAWN_MIN'))
                self.assertLessEqual(max(abs(x - 400), abs(y - 400)), 76)   # près de la zone, côté foyer
                self.assertLess(x + y, 800)
        # Jamais au foyer : chef et ouvrier restent sans corps (aucun joueur près du foyer).
        self.assertIsNone(self.member(self.gid, 'm-1', 'npc'))
        self.assertEqual(self.ev(f'{R}.revengeStats.spawned'), 2)
        self.assertEqual(self.hunt_passes(), 0)          # pas de doublon
        self.assertEqual(self.h.errors('server'), [])

    def test_no_body_when_only_squares_near_the_players_are_loaded(self):
        # Tout est déchargé sauf un carré de 35 cases autour du joueur A : aucune case assez loin -> attente.
        self.run_lua('UNLOADED = { { -10000, 364, -10000, 10000 }, { 436, 10000, -10000, 10000 }, '
                     '{ -10000, 10000, -10000, 364 }, { -10000, 10000, 436, 10000 } }')
        self.assertEqual(self.hunt_passes(), 0)
        self.assertEqual(self.bodies(self.gid), [])
        self.assertGreater(self.ev(f'{R}.revengeStats.spawnWaits'), 0)
        self.assertEqual(len([line for line in self.lk() if 'no loaded free square' in line]), 1)
        self.run_lua('UNLOADED = {}')
        self.assertEqual(self.hunt_passes(), 2)

    def test_no_body_while_no_player_is_near_the_zone(self):
        for p in self.players:
            self.h.move_player(p, 700, 700)
        self.assertEqual(self.hunt_passes(), 0)

    def test_members_hunt_toward_the_zone_through_the_decision_frame(self):
        self.hunt_passes()
        self.run_lua(f'{D}.state.lastPass = nil {D}.reset()')
        for _ in range(4):
            self.h.advance_ms(1000)
            self.h.tick(len(self.team))   # LK13-T11 : membres d'un passage évalués un par image
        for mid in self.team:
            with self.subTest(mid=mid):
                st = self.run_lua(f'local s = {D}.get(MEMBER_NPC("{self.gid}", "{mid}")) return s.rule, s.b, s.why')
                self.assertEqual(st[:2], ('duty', 'revenge'))
                self.assertEqual(st[2], 'revenge 1 hunt')
                d = self.ev(f'DIRECTIVE("{self.gid}", "{mid}")')
                self.assertEqual(d.op, 'move')
                x, y = self.body_xy(self.gid, mid)
                self.assertLessEqual(max(abs(d.x - x), abs(d.y - y)), self.ev(f'{R}.REVENGE.STEP') + 2)
                # Plus près de la ronde autour de la zone (400,400 ± 8) que le corps.
                self.assertLess(max(abs(d.x - 400), abs(d.y - 400)), max(abs(x - 400), abs(y - 400)))
        # Clients : aucune décision, aucun module d'autorité.
        if self.mode != 'solo':
            for c in ('A', 'B'):
                self.assertIsNone(self.h.eval(c, R))

    def test_released_team_stays_away_from_home(self):
        self.hunt_passes()
        for p in self.players:
            self.h.move_player(p, 100, 100)                # près du foyer, loin de la traque
        self.wait(70)
        self.assertEqual(self.bodies(self.gid), ['m-1', 'm-5'])     # présents au foyer seulement
        for mid in self.team:
            self.assertEqual(self.npc(self.gid, mid, 'state'), 'virtual')


class SoloHuntTests(HuntTests):
    mode = 'solo'


SUITE = 'oath, team from the roster, spawn away from the players, abandon'


class SuiteTests(HuntBase):
    """La suite en jeu lk.revenge passe dans le banc (joueur cible A loin de tout foyer)."""

    def setUp(self):
        MatBase.setUp(self)
        self.players = ['A', 'B']
        self.h.move_player('A', 400, 400)
        self.h.move_player('B', 405, 402)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKRevenge.lua')

    def run_suite(self, prep=''):
        self.run_lua(DelayOptionTests.OPTION)
        self.run_lua('if JAVA_OPTIONS["LivingKnox.RevengeDelayHours"] == nil then '
                     'JAVA_OPTIONS["LivingKnox.RevengeDelayHours"] = 72 end')
        if prep:
            self.run_lua(prep)
        self.run_lua('PLAYER = HARNESS.players.A')
        self.assertTrue(self.ev('RST.start({ suite = "lk.revenge", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
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
        self.assertEqual(self.ev('JAVA_OPTIONS["LivingKnox.RevengeDelayHours"]'), 72)   # option restored
        self.assertIsNone(self.ev(f'{R}.REVENGE.DELAY_HOURS'))   # forcing removed: back to the option (LK11-T10)
        self.assertEqual(self.ev('ALL_TAGGED()'), 0)

    def test_suite_detects_a_constant_delay_and_a_missing_option(self):
        name = 'the oath delay comes from the RevengeDelayHours option'
        _, results = self.run_suite(f'{R}.revengeDelayHours = function() return 72 end')
        self.assertEqual(results[name][0], 'FAIL')

    def test_suite_fails_without_the_option(self):
        name = 'the oath delay comes from the RevengeDelayHours option'
        _, results = self.run_suite('getSandboxOptions = function() return { getOptionByName = function() '
                                    'return nil end } end')
        self.assertEqual(results[name][0], 'FAIL')
        self.assertIn('option LivingKnox.RevengeDelayHours not registered', results[name][1])

    def test_suite_detects_a_body_spawned_next_to_the_player(self):
        _, results = self.run_suite(f'{R}.spawnSquare = function(zone, home, players, used) '
                                    'return getCell():getGridSquare(402, 400, 0) end')
        self.assertEqual(results[SUITE][0], 'FAIL')


class SourceTests(unittest.TestCase):
    def test_translations_and_ascii_code(self):
        import json
        for lang in ('EN', 'FR'):
            data = json.loads((LUA / 'shared' / 'Translate' / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            data['IGUI_LK_Revenge_Sworn'].encode('latin-1')
        src = (LUA / RELATIONS).read_text(encoding='utf-8')
        for n, line in enumerate(src.splitlines(), 1):
            with self.subTest(line=n):
                self.assertTrue(line.split('--', 1)[0].isascii(), line)
        self.assertIsNone(re.search(r'\bgoto\b|\bnext\(|\bcoroutine\.', src))
        self.assertTrue(SUITE_FILE.exists())

    def test_delay_option_and_translations(self):
        # LK11-T10 : entier 12..336, défaut 72, page LivingKnox ; = Config.DEFAULTS / Config.INT_BOUNDS.
        import json
        opts = (LUA.parent / 'sandbox-options.txt').read_text(encoding='utf-8')
        self.assertRegex(opts, r'option LivingKnox\.RevengeDelayHours\n\{\n\ttype = integer,\n\tmin = 12,\n'
                               r'\tmax = 336,\n\tdefault = 72,\n\tpage = LivingKnox,\n'
                               r'\ttranslation = LivingKnox_RevengeDelayHours,\n\}')
        config = (LUA / 'shared' / 'LivingKnox' / 'LK_Config.lua').read_text(encoding='utf-8')
        self.assertIn('RevengeDelayHours = 72,', config)
        self.assertIn('RevengeDelayHours = { 12, 336 },', config)
        for lang in ('EN', 'FR'):
            sb = json.loads((LUA / 'shared' / 'Translate' / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            for k in ('RevengeDelayHours', 'RevengeDelayHours_tooltip'):
                with self.subTest(lang=lang, key=k):
                    self.assertTrue(sb['Sandbox_LivingKnox_' + k].strip())
                    sb['Sandbox_LivingKnox_' + k].encode('latin-1')


if __name__ == '__main__':
    unittest.main()
