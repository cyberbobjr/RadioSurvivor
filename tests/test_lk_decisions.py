"""Tests hors jeu du cadre de décision des PNJ Living Knox (LK05-T02) : server/LivingKnox/LK_Decisions.lua.

    python RadioSurvivor/tests/test_lk_decisions.py

Deux bancs :
- logique pure (Decisions.decide, scoreObjectives, assignDuties, threatsOf, needsOf) sur le serveur d'un banc
  tests/harness.py chargé comme test_lk_simulation.py ;
- pile complète des corps (banc MatBase de test_lk_materialize.py : groupes, matérialisation, consignes LK03, rapports,
  santé) avec un type de groupe de test « deciders ». La perception est injectée (LivingKnox.Senses.perceived
  remplacée par une table du test) : sa logique est prouvée par test_lk_senses.py. Les doublures NE PROUVENT PAS l'API
  réelle, seulement la logique : décisions reproductibles, autorité seule, cascade, postes, journal, coût borné.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
from test_lk_simulation import WORLD, SHARED, SERVER  # noqa: E402

D = 'LivingKnox.Decisions'

# Sérialisation stable d'une table Lua plate ou imbriquée (clés triées).
DUMP = r'''
function DUMP(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. DUMP(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
'''

# Contexte de membre de base (pur) : non-combattant au foyer, de jour, sans menace.
CTX = r'''
function CTX(over)
    local c = { id = "lk-7", gid = "grp-1", mid = "m-2", role = "worker", allowed = { chores = true, cook = true },
        combatant = false, x = 100.5, y = 100.5, z = 0, home = { x = 100, y = 100, z = 0 }, atHome = true,
        needs = { hunger = 0, thirst = 0, fatigue = 0, fear = 0 }, health = 1, duty = "keeper",
        objective = "settle", night = false, minute = 600 }
    for k, v in pairs(over or {}) do c[k] = v end
    if c.threat == false then c.threat = nil end   -- false : effacer (un nil ne passe pas dans une table)
    if c.duty == false then c.duty = nil end
    if c.home == false then c.home = nil end   -- LK06-T05 : membre sans foyer
    return c
end
function ZOMBIE(d, seen)
    return { kind = "zombie", key = "z42", label = "42", x = 100 + d, y = 100, z = 0, d = d, seen = seen ~= false,
        flee = true }
end
'''

# Type de groupe de test : combattants (fight, defend), ouvriers, soignants, éclaireurs.
DECIDERS = r'''
if not LivingKnox.GroupTypes.isKnown("deciders") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "deciders", nameKey = "IGUI_LK_GroupType_settlers", size = { min = 1, max = 12 },
        hostility = 10, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard", "defend", "fight" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } },
                  medic = { weight = 1, behaviours = { "heal", "chores" } },
                  scout = { weight = 1, behaviours = { "scout", "forage" } } },
        profiles = {
            { id = "gunner", role = "fighter", weight = 1, weapons = { "Base.Shotgun" }, looks = { "manFairBeard" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
            { id = "doc", role = "medic", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
            { id = "runner", role = "scout", weight = 1, outfits = { "Generic02" }, weapons = { "Base.HandAxe" } },
        },
    }))
end
-- Perception injectée par le test : PERCEPTION[npcId] = résumé de LivingKnox.Senses.perceived.
PERCEPTION = {}
LivingKnox.Senses = LivingKnox.Senses or { setVigilance = function() return true end }
LivingKnox.Senses.perceived = function(id) return PERCEPTION[id] end
function SEE_ZOMBIE(id, x, y, d, o)
    PERCEPTION[id] = { ms = 0, age = 0, stale = false, nz = 1, seen = 1, heard = 0, p = {},
        z = { { o = o or 900, x = x, y = y, z = 0, a = 1, s = true, h = false, d = d } }, n = {} }
end
function MEMBER_NPC(gid, mid) return LivingKnox.Groups.get(gid).members[mid].npc end
function DIRECTIVE(gid, mid)
    local e = LivingKnox.Directives.get(MEMBER_NPC(gid, mid))
    if e == nil then return nil end
    return { op = e.op, x = e.x, y = e.y, a = e.a, g = e.g, v = e.v }
end
'''


# LK13-T09 : les passes horaires partent une par image (LK_Simulation.defer) ; ce banc les vide aussitôt.
FINISH_HOUR = 'if LivingKnox.Simulation and LivingKnox.Simulation.finishHour then LivingKnox.Simulation.finishHour() end'

class PureBase(unittest.TestCase):
    mode = 'solo'

    def setUp(self):
        self.h = Harness(mode=self.mode)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, WORLD)
            for path in SHARED:
                self.h.load(m, path)
            self.h.load(m, SERVER)
        self.h.load(self.srv, DUMP)
        self.h.load(self.srv, CTX)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval(self.srv, code)

    def run_lua(self, code):
        return self.h.load(self.srv, code)

    def decide(self, over=''):
        """(règle, comportement, raison) de Decisions.decide(CTX({ over }))."""
        return self.run_lua(f'local o = {D}.decide(CTX({{ {over} }})) return o.rule, o.b, o.why')


class CascadeTests(PureBase):
    def test_same_inputs_give_the_same_choice_reason_and_deadline(self):
        cases = ['', 'threat = ZOMBIE(3)', 'threat = ZOMBIE(9)', 'duty = "sentry", role = "fighter", '
                 'allowed = { guard = true, fight = true }, combatant = true', 'health = 0.3, atHome = false',
                 'needs = { fatigue = 95 }, night = true']
        for over in cases:
            first = self.run_lua(f'return DUMP({D}.decide(CTX({{ {over} }})))')
            self.run_lua(f'{D}.reset()')
            second = self.run_lua(f'return DUMP({D}.decide(CTX({{ {over} }})))')
            self.assertEqual(first, second, over)
        # Autre minute de jeu : même choix et même raison, échéance retirée (hasard tiré de l'identité et du temps).
        a = self.run_lua(f'local o = {D}.decide(CTX({{ duty = "rest", minute = 600 }})) return o.b, o.why, o.untilMin')
        b = self.run_lua(f'local o = {D}.decide(CTX({{ duty = "rest", minute = 601 }})) return o.b, o.why, o.untilMin')
        self.assertEqual(a[:2], b[:2])
        self.assertTrue(620 <= a[2] <= 640 and 621 <= b[2] <= 641)

    def test_fixed_priorities_threat_first_routine_last(self):
        everything = ('threat = ZOMBIE(9), needs = { fear = 90, hunger = 90, thirst = 90, fatigue = 90 }, '
                      'health = 0.2, duty = "rest"')
        self.assertEqual(self.decide(everything)[0], 'threat')
        self.assertEqual(self.decide(everything.replace('threat = ZOMBIE(9), ', ''))[0], 'fear')
        no_fear = everything.replace('threat = ZOMBIE(9), ', '').replace('fear = 90', 'fear = 0')
        self.assertEqual(self.decide(no_fear)[:2], ('wound', 'rest'))
        self.assertEqual(self.decide(no_fear.replace('health = 0.2', 'health = 0.9'))[0], 'hunger')
        thirst = no_fear.replace('health = 0.2', 'health = 0.9').replace('hunger = 90', 'hunger = 0')
        self.assertEqual(self.decide(thirst)[0], 'thirst')
        fatigue = thirst.replace('thirst = 90', 'thirst = 0')
        self.assertEqual(self.decide(fatigue)[:2], ('fatigue', 'sleep'))
        duty = fatigue.replace('fatigue = 90', 'fatigue = 0')
        self.assertEqual(self.decide(duty)[:2], ('duty', 'rest'))
        self.assertEqual(self.decide('duty = false')[:3], ('routine', 'home', 'routine'))
        # Loin du foyer : les règles du foyer y ramènent d'abord.
        self.assertEqual(self.decide('health = 0.2, atHome = false')[:2], ('wound', 'home'))

    def test_role_decides_between_flight_and_watch(self):
        # LK06-T07 : le rôle ne décide plus de la fuite ; un membre valide de tout rôle tient (regard), un membre aux
        # constantes mauvaises (santé < WOUND_RATIO, peur >= NEED_HIGH.fear) fuit, ou s'abrite au foyer.
        rule, b, why = self.decide('threat = ZOMBIE(3)')
        self.assertEqual((rule, b), ('threat', 'watch'))
        self.assertIn('too close, able member holds', why)
        rule, b, why = self.decide('threat = ZOMBIE(3), health = 0.4, atHome = false')
        self.assertEqual((rule, b), ('threat', 'flee'))
        self.assertIn('too close, health 40% < 50%', why)
        self.assertEqual(self.decide('threat = ZOMBIE(3), needs = { fear = 70 }, atHome = false')[:2],
                         ('threat', 'flee'))
        rule, b, why = self.decide('threat = ZOMBIE(3), health = 0.4')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 40% < 50%, hiding at home', why)
        fighter = 'threat = ZOMBIE(3), role = "fighter", allowed = { fight = true, guard = true }, combatant = true'
        self.assertEqual(self.decide(fighter)[:2], ('threat', 'watch'))
        self.assertEqual(self.decide(fighter + ', health = 0.4, atHome = false')[:2], ('threat', 'flee'))
        self.assertEqual(self.decide('threat = ZOMBIE(9)')[:2], ('threat', 'watch'))   # au-delà de FLEE_DIST
        # Fuite : à l'opposé de la menace (zombie à l'est -> angle 180, ouest).
        self.assertEqual(self.run_lua(f'return {D}.decide(CTX({{ threat = ZOMBIE(3), health = 0.4, atHome = false }}))'
                                      '.away'), 180)
        # Regard : vers la menace (est = 0).
        self.assertEqual(self.run_lua(f'return {D}.decide(CTX({{ threat = ZOMBIE(9) }})).angle'), 0)
        # Poste de guet : permis seulement à un rôle qui sait garder (guard, patrol, defend) ; sinon la routine.
        self.assertEqual(self.decide('duty = "sentry"')[:2], ('routine', 'home'))
        sentry = 'duty = "sentry", role = "fighter", allowed = { guard = true }, combatant = false'
        self.assertEqual(self.decide(sentry)[:2], ('duty', 'guard'))
        self.assertEqual(self.ev(f'{D}.allows(CTX({{ combatant = true }}), "flee")'), True)   # LK06-T07 : tout rôle
        self.assertEqual(self.ev(f'{D}.allows(CTX(), "guard")'), False)
        self.assertEqual(self.ev(f'{D}.allows(CTX(), "dance")'), False)   # liste fermée

    def test_deadline_or_interruption_only(self):
        self.run_lua(f'ST = {D}.decide(CTX({{ duty = "rest" }}))')
        until = self.ev('ST.untilMin')
        self.assertEqual(self.ev(f'{D}.replaces(ST, {D}.decide(CTX({{ duty = "rest", minute = 610 }})), 610)'), False)
        self.assertEqual(self.run_lua(f'return {D}.replaces(ST, {D}.decide(CTX({{ duty = "rest", minute = {until} }})),'
                                      f' {until})'), (True, 'deadline'))
        self.assertEqual(self.run_lua(f'return {D}.replaces(ST, {D}.decide(CTX({{ duty = "rest", minute = 601, '
                                      f'threat = ZOMBIE(12) }})), 601)'), (True, 'interrupted'))
        self.assertEqual(self.run_lua(f'return {D}.replaces(nil, ST, 600)'), (True, 'new'))

    def test_needs_interface_is_neutral_until_lk05_t06(self):
        self.assertEqual(self.run_lua(f'return DUMP({D}.needsOf("grp-1", "m-1"))'),
                         '{fatigue=0,fear=0,hunger=0,thirst=0}')
        self.run_lua('LivingKnox.Needs = { get = function(g, m) return { hunger = 85.4, thirst = "x", fear = 150 } end }')
        self.assertEqual(self.run_lua(f'return DUMP({D}.needsOf("grp-1", "m-1"))'),
                         '{fatigue=0,fear=100,hunger=85,thirst=0}')

    def test_threats_from_perception_and_attitude(self):
        per = ('{ stale = false, z = { { o = 5, x = 104, y = 100, z = 0, a = 1, s = false, h = true, d = 4 }, '
               '{ o = 6, x = 120, y = 100, z = 0, a = 0.4, s = false, h = false, d = 20 } }, '
               'p = { { u = "A", x = 102, y = 100, z = 0, s = true, h = false, d = 2 }, '
               '{ u = "B", x = 101, y = 100, z = 0, s = true, h = false, d = 1 }, '
               '{ u = "C", x = 103, y = 100, z = 0, s = true, h = false, d = 3 } } }')
        out = self.run_lua(f'local t = {D}.threatsOf({per}, {{ A = "hostile", B = "favorable", C = "wary" }}) '
                           'local r = {} for i, e in ipairs(t) do r[i] = e.key .. ":" .. tostring(e.flee) end '
                           'return table.concat(r, " ")')
        self.assertEqual(out, 'pA:true pC:false z5:true')   # zombie non vu ni entendu ignoré, joueur favorable aussi
        self.assertEqual(self.ev(f'#{D}.threatsOf({{ stale = true, z = {{ {{ o = 1, s = true, d = 1, x = 0, y = 0, '
                                 f'z = 0 }} }}, p = {{}} }}, {{}})'), 0)
        self.assertEqual(self.ev(f'#{D}.threatsOf(nil, {{}})'), 0)


# Expression évaluée aussi dans la VM Kahlua réelle (tests/test_kahlua.py, KR-DECIDE) : mêmes valeurs attendues.
KR_DECIDE = ('local D = LivingKnox.Decisions; local function c(t) local b = { id = "lk-7", allowed = { chores = '
             'true }, combatant = false, x = 100.5, y = 100.5, z = 0, home = { x = 100, y = 100, z = 0 }, atHome = '
             'true, needs = { hunger = 0, thirst = 0, fatigue = 0, fear = 0 }, health = 1, duty = "keeper", '
             'objective = "settle", night = false, minute = 600 } for k, v in pairs(t) do b[k] = v end return b '
             'end; local zt = { kind = "zombie", key = "z42", label = "42", x = 103, y = 98, z = 0, d = 3.2, seen '
             '= true, flee = true }; local a = D.decide(c({ threat = zt, health = 0.4, atHome = false })); '
             'local b = D.decide(c({ duty = '
             '"sentry", allowed = { guard = true }, home = { x = 95, y = 97, z = 0 } })); local e = D.decide(c({ '
             'health = 0.3, minute = 12345 })); local s = D.scoreObjectives({ gidNumber = 3, day = 4, night = '
             'false, needs = { food = 20, medical = 50, ammo = 50 }, rest = 40, worstWound = 10, threats = 1, '
             'hostility = 90, traits = { nervous = true } }); local r = D.stream("lk-7", 600, 3); return '
             '"KR-DECIDE " .. a.b .. " " .. a.away .. " " .. a.side .. " " .. a.untilMin .. " " .. b.b .. " " .. '
             'b.angle .. " " .. b.untilMin .. " " .. e.b .. " " .. e.untilMin .. " " .. s.objective .. " " .. '
             's.scores.guard .. " " .. s.scores.supply .. " " .. string.format("%.6f", r())')
KR_EXPECTED = 'KR-DECIDE flee 146 1 602 guard 31 620 rest 12379 supply 44 61 0.205245'


class KahluaParityTests(PureBase):
    def test_same_values_as_the_kahlua_run(self):
        self.assertEqual(self.run_lua(KR_DECIDE), KR_EXPECTED)


class ObjectiveTests(PureBase):
    GIN = ('{ gidNumber = 3, day = 4, night = false, needs = { food = 50, medical = 50, ammo = 50 }, rest = 50, '
           'worstWound = 0, threats = 0, hostility = 10, traits = {} }')

    def score(self, edit='', jitter=None):
        j = 'nil' if jitter is None else jitter
        return self.run_lua(f'local old = {D}.CFG.JITTER {D}.CFG.JITTER = {j} or old '
                            f'local g = {self.GIN} {edit} local r = {D}.scoreObjectives(g) {D}.CFG.JITTER = old '
                            'return r.objective, r.why, DUMP(r.scores)')

    def test_utility_picks_the_pressing_objective_with_its_reason(self):
        self.assertEqual(self.score(jitter=0)[0], 'settle')
        obj, why, _ = self.score('g.night = true', jitter=0)
        self.assertEqual((obj, why.split(' (')[0]), ('rest', 'rest 70'))
        self.assertIn('night', why)
        obj, why, _ = self.score('g.needs.food = 10', jitter=0)
        self.assertEqual(obj, 'supply')
        self.assertIn('food 10', why)
        obj, why, _ = self.score('g.threats = 3', jitter=0)
        self.assertEqual(obj, 'guard')
        self.assertIn('threats 3', why)
        obj, why, _ = self.score('g.worstWound = 60', jitter=0)
        self.assertEqual(obj, 'heal')
        self.assertEqual(self.score('g.worstWound = 60 g.needs.medical = 0', jitter=0)[0], 'supply')   # rien pour soigner
        self.assertEqual(self.score('g.fortification = 0 g.needs = { food = 90, medical = 90, ammo = 90 }',
                                    jitter=0)[0], 'fortify')

    def test_leader_personality_tips_the_balance(self):
        self.assertEqual(self.score('g.threats = 1', jitter=0)[0], 'settle')
        obj, why, _ = self.score('g.threats = 1 g.traits = { nervous = true }', jitter=0)
        self.assertEqual(obj, 'guard')
        self.assertIn('leader nervous', why)

    def test_jitter_is_bounded_and_reproducible_per_group_and_day(self):
        base = self.score(jitter=0)[2]
        a, b = self.score()[2], self.score()[2]
        self.assertEqual(a, b)
        other_day = self.score('g.day = 5')[2]
        self.assertTrue(a != base or other_day != base)
        for text in (a, other_day):
            for part in text.strip('{}').split(','):
                key, value = part.split('=')
                ref = dict(p.split('=') for p in base.strip('{}').split(','))[key]
                self.assertLessEqual(abs(int(value) - int(ref)), 3)

    def test_duties_follow_roles_wounds_and_rotate_by_day(self):
        members = ('{ { mid = "m-1", number = 1, allowed = { guard = true, fight = true }, wound = 0 }, '
                   '{ mid = "m-2", number = 2, allowed = { chores = true }, wound = 0 }, '
                   '{ mid = "m-3", number = 3, allowed = { guard = true }, wound = 70 }, '
                   '{ mid = "m-4", number = 4, allowed = { patrol = true, heal = true }, wound = 0 } }')

        def duties(obj, night='false', rot=0):
            return self.run_lua(f'return DUMP({D}.assignDuties({members}, "{obj}", {night}, {rot}))')
        self.assertEqual(duties('guard'), '{m-1=sentry,m-2=keeper,m-3=rest,m-4=sentry}')
        self.assertEqual(duties('settle'), '{m-1=sentry,m-2=keeper,m-3=rest,m-4=keeper}')
        self.assertEqual(duties('settle', rot=2), '{m-1=keeper,m-2=keeper,m-3=rest,m-4=sentry}')   # relève
        self.assertEqual(duties('rest', 'true'), '{m-1=sentry,m-2=rest,m-3=rest,m-4=rest}')
        self.assertEqual(duties('heal'), '{m-1=sentry,m-2=keeper,m-3=rest,m-4=carer}')
        self.assertEqual(duties('guard'), duties('guard'))


class RegistryFieldTests(PureBase):
    def test_objective_and_duty_are_checked_in_their_form(self):
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "settlers", name = "Mill", day = 1 })) '
                'local mid = assert(G.addMember(g.id, { role = "worker", day = 1 })) local d = G.state.data '
                'local live = d.groups[g.id] ')
        ok = self.run_lua(code + 'live.objective = "guard" live.members[mid].duty = "sentry" '
                          'return G.validGroup(live, g.id, d.nextId)')
        self.assertEqual(ok, True)
        bad = self.run_lua(code + 'live.objective = "1 guard" return G.validGroup(live, g.id, d.nextId)')
        self.assertEqual(bad, (False, 'bad objective'))
        bad = self.run_lua(code + 'live.members[mid].duty = 5 return G.validGroup(live, g.id, d.nextId)')
        self.assertEqual(bad, (False, 'member m-1: bad duty'))


class MultiplayerDecisionTests(MatBase):
    """Pile complète : serveur dédié + deux clients ; groupe « deciders » matérialisé près du joueur A."""

    CREW4 = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false'), ('medic', 'doc', 'true'),
             ('scout', 'runner', 'nil')]

    def make(self, root=None):
        h = super().make(root)
        h.load(self.srv_name(), DECIDERS)
        h.load(self.srv_name(), DUMP)
        return h

    def srv_name(self):
        return 'solo' if self.mode == 'solo' else 'server'

    def mk(self, crew=None, n=None):
        crew = crew or self.CREW4
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile, female in crew:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        code += 'assert(G.setLeader(g.id, "m-1", 1)) return g.id'
        gid = self.run_lua(code)
        self.run_lua(f'{D}.state.lastPass = 1e18')   # aucune décision pendant la matérialisation
        self.h.move_player('A', 100, 100)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(crew):
                break
        self.assertEqual(len(self.bodies(gid)), len(crew))
        self.run_lua(f'{D}.reset() for k in pairs({D}.stats) do {D}.stats[k] = 0 end')
        return gid

    def dpass(self, n=1):
        """n passages des décisions (au plus un par PASS_MS), membres évalués sur les images qui suivent."""
        # LK13-T11 : les membres d'un passage sont évalués un par image (MEMBERS_PER_FRAME) : quatre images.
        for _ in range(n):
            self.h.advance_ms(1000)
            self.h.tick(4)

    def all_members(self, gid, count):
        """Passages jusqu'à ce que chaque membre ait été évalué au moins une fois."""
        self.dpass(-(-count // 4) + 1)

    def state(self, gid, mid):
        return self.run_lua(f'local s = {D}.get(MEMBER_NPC("{gid}", "{mid}")) if s == nil then return nil end '
                            'return s.rule, s.b, s.why')

    def test_clients_never_decide_and_the_server_logs_the_objective(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Decisions'))
        self.all_members(gid, 4)
        self.assertEqual(self.ev(f'{D}.stats.decided'), 4)
        log = self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                           'if e.kind == "objective" then out[#out + 1] = e.text end end return out')
        log = lua_list(log)
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('settle '), log[0])
        self.assertIn('sentry m-1', log[0])   # seul rôle apte au guet
        self.assertEqual(self.member(gid, 'm-1', 'duty'), 'sentry')
        self.assertEqual(self.state(gid, 'm-1')[:2], ('duty', 'guard'))
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-1").op'), 'face')
        # LK05-T04 : de jour, l'ouvrier (keeper) fait une corvée ; foyer sans bâtiment ni meuble sur le banc : repos
        # assis sur place (arrêt, geste « sit »).
        self.assertEqual(self.state(gid, 'm-2')[:2], ('duty', 'chore'))
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").op'), 'stop')
        # Même heure, même état : aucune nouvelle entrée de journal ni nouvelle consigne avant l'échéance.
        issued = self.ev(f'{D}.stats.issued')
        self.h.fire('server', 'EveryHours')
        self.h.load('server', FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.dpass(4)
        self.assertEqual(self.ev(f'{D}.stats.issued'), issued)
        self.assertEqual(self.ev(f'{D}.stats.objectiveChanges'), 1)
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])

    def test_threat_beats_routine_non_combatant_flees_combatant_watches(self):
        # LK06-T07 : la fuite dépend des constantes, non du rôle : l'ouvrier m-2 est blessé (santé 40 %) et fuit ; le
        # combattant m-1, valide, tient (regard). Un ouvrier valide tient aussi (test_cascade, banc pur).
        gid = self.mk()
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].members["m-2"].wound = 60')
        self.assertEqual(self.ev(f'{D}.healthOf(LivingKnox.Groups.state.data.groups["{gid}"].members["m-2"])'), 0.4)
        self.all_members(gid, 4)
        fx, fy = self.body_xy(gid, 'm-1')
        wx, wy = self.body_xy(gid, 'm-2')
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "m-1"), {int(fx) + 3}, {int(fy)}, 3, 901)')
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "m-2"), {int(wx) + 3}, {int(wy)}, 3, 902)')
        self.all_members(gid, 4)
        rule, b, why = self.state(gid, 'm-1')
        self.assertEqual((rule, b), ('threat', 'watch'))
        self.assertIn('able member holds', why)
        d1 = self.run_lua(f'return DUMP(DIRECTIVE("{gid}", "m-1"))')
        self.assertIn('op=face', d1)
        self.assertIn('a=0', d1)                                   # regard vers l'est, la menace
        rule, b, why = self.state(gid, 'm-2')
        self.assertEqual((rule, b), ('threat', 'retreat'))         # blessé au foyer : il s'abrite (LK06-T07)
        self.assertIn('health 40% < 50%, hiding at home', why)
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").op'), 'face')
        # Hors du foyer, le même blessé fuit : s'éloigne vers l'ouest.
        self.run_lua(f'{D}.state.members[MEMBER_NPC("{gid}", "m-2")] = nil')
        self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].home = {{ x = 130, y = 130, z = 0 }}')
        self.all_members(gid, 4)
        rule, b, why = self.state(gid, 'm-2')
        self.assertEqual((rule, b), ('threat', 'flee'))
        d2 = self.run_lua(f'local e = DIRECTIVE("{gid}", "m-2") return e.op, e.g, e.x')
        self.assertEqual(d2[:2], ('move', 'run'))
        self.assertLess(d2[2], wx - 5)                             # s'éloigne vers l'ouest
        self.run_lua(f'local g = LivingKnox.Groups.state.data.groups["{gid}"] g.home = {{ x = 110, y = 110, z = 0 }} '
                     'g.members["m-2"].wound = 0 g.members["m-2"].duty = "keeper"')   # soigné : suite d'avant
        self.assertGreaterEqual(self.ev(f'{D}.knownThreats("{gid}", {D}.currentHour())'), 2)
        # Menace disparue (interruption) : poste du groupe ; le corps n'a pas bougé (serveur seul propriétaire, consigne
        # suspendue) et reste au foyer : la fuite est arrêtée.
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)                                         # LK05-T08 : l'alerte de groupe retombe d'abord
        self.all_members(gid, 4)
        self.assertEqual(self.state(gid, 'm-2')[:2], ('duty', 'chore'))   # corvée (LK05-T04)
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").op'), 'stop')
        # Corps emporté loin du foyer : état gardé jusqu'à l'échéance, puis retour au foyer en marchant.
        self.run_lua(f'local z = MAT_BODY("{gid}", "m-2") HARNESS.place(z, 90.5, 110.5, 0)')
        until = self.run_lua(f'return {D}.get(MEMBER_NPC("{gid}", "m-2")).untilMin')
        self.all_members(gid, 4)
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").op'), 'stop')
        self.h.advance(until - self.ev(f'{D}.currentMinute()'))
        self.all_members(gid, 4)
        self.assertEqual(self.run_lua(f'local e = DIRECTIVE("{gid}", "m-2") return e.op, e.g'), ('move', 'walk'))
        self.assertLessEqual(max(abs(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").x') - 110),
                                 abs(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").y') - 110)), 6)
        self.assertEqual(self.h.errors('server'), [])

    def test_cost_per_pass_is_bounded(self):
        crew = self.CREW4 + self.CREW4
        gid = self.mk(crew)
        self.dpass(1)
        self.assertEqual(self.ev(f'{D}.stats.evaluated'), 4)
        self.dpass(1)
        self.assertEqual(self.ev(f'{D}.stats.evaluated'), 8)
        # Images sans passage (moins de PASS_MS) : rien.
        self.h.tick(20)
        self.assertEqual(self.ev(f'{D}.stats.evaluated'), 8)
        # LK13-T11 : un membre évalué par image ; deux passages de quatre membres.
        self.assertEqual(self.ev(f'{D}.stats.maxPerPass'), 1)
        self.assertEqual(self.ev(f'{D}.stats.passes'), 2)
        self.assertEqual(len(self.bodies(gid)), 8)

    def test_hourly_scoring_one_group_per_frame_after_the_deferred_pass(self):
        # LK13-T11 : notation de l'heure en file (un groupe matérialisé par image, à partir de l'image qui suit la
        # passe différée) ; écriture retenue jusqu'à la fin ; finishHour fait le reste tout de suite.
        gid = self.mk()
        self.all_members(gid, 4)
        s0 = self.ev(f'{D}.stats.scored')
        self.run_lua(f'{D}.onEveryHours({D}.currentHour())')
        self.assertEqual(self.ev(f'{D}.stats.scored'), s0)             # rien dans l'image de la passe
        self.assertTrue(self.ev('LivingKnox.Groups.isHeld()'))
        self.assertTrue(self.ev(f'{D}.hourScoringPending("{gid}", {D}.currentHour())'))
        self.h.tick(1)
        self.assertEqual(self.ev(f'{D}.stats.scored'), s0 + 1)
        self.assertFalse(self.ev(f'{D}.hourScoringPending("{gid}", {D}.currentHour())'))
        self.assertFalse(self.ev('LivingKnox.Groups.isHeld()'))
        self.run_lua(f'{D}.onEveryHours({D}.currentHour())')
        self.run_lua('LivingKnox.Simulation.finishHour()')
        self.assertEqual(self.ev(f'{D}.stats.scored'), s0 + 2)
        self.assertFalse(self.ev('LivingKnox.Groups.isHeld()'))
        self.assertEqual(self.h.errors('server'), [])

    def test_hourly_objective_change_is_journaled_with_its_reason(self):
        gid = self.mk()
        self.all_members(gid, 4)
        self.update(gid, 'g.needs.food = 5')
        self.h.advance(60)
        self.h.fire('server', 'EveryHours')
        self.h.load('server', FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        log = lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                                    'if e.kind == "objective" then out[#out + 1] = e.text end end return out'))
        self.assertEqual(len(log), 2)
        self.assertTrue(log[1].startswith('supply '), log[1])
        self.assertIn('food', log[1])
        self.assertIn('forager m-4', log[1])                       # éclaireur : apte à la fouille
        self.assertEqual(self.member(gid, 'm-4', 'duty'), 'forager')
        self.assertEqual(self.ev('LivingKnox.Groups.state.blocked'), False)

    def run_scenario(self):
        gid = self.mk()
        self.all_members(gid, 4)
        x, y = self.body_xy(gid, 'm-3')
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "m-3"), {int(x) - 2}, {int(y)}, 2, 903)')
        self.all_members(gid, 4)
        self.h.advance(61)
        self.h.fire('server', 'EveryHours')
        self.h.load('server', FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.all_members(gid, 4)
        return self.run_lua('local out = {} for id, s in pairs(LivingKnox.Decisions.state.members) do '
                            'out[#out + 1] = id .. ":" .. s.rule .. ":" .. s.b .. ":" .. s.why .. ":" .. s.untilMin end '
                            f'table.sort(out) return table.concat(out, "|") .. "#" .. DUMP(LivingKnox.Groups.get("{gid}").log)')

    def test_same_world_twice_gives_the_same_decisions(self):
        first = self.run_scenario()
        self.h.close()
        self.h = self.make()
        self.init()
        self.away()
        second = self.run_scenario()
        self.assertEqual(first, second)
        self.assertIn('threat:watch:zombie 903 at 2.0 (seen), too close, able member holds', first)   # LK06-T07


class SoloDecisionTests(MultiplayerDecisionTests):
    mode = 'solo'

    def test_clients_never_decide_and_the_server_logs_the_objective(self):
        gid = self.mk()
        self.all_members(gid, 4)
        self.assertEqual(self.ev(f'{D}.stats.decided'), 4)
        self.assertEqual(self.member(gid, 'm-1', 'duty'), 'sentry')
        self.assertEqual(self.h.errors('solo'), [])

    def test_hourly_objective_change_is_journaled_with_its_reason(self):
        gid = self.mk()
        self.all_members(gid, 4)
        self.update(gid, 'g.needs.food = 5')
        self.h.advance(60)
        self.h.fire('solo', 'EveryHours')
        self.h.load('solo', FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{gid}").objective'), 'supply')

    test_threat_beats_routine_non_combatant_flees_combatant_watches = None
    test_same_world_twice_gives_the_same_decisions = None


# LK06-T05 : retraite, fuite pondérée, reddition (logique pure de la cascade).
FIGHTER = ('role = "fighter", allowed = { fight = true, guard = true, defend = true }, combatant = true, '
           'target = { u = "A", d = 4, reason = "hostile" }')
SEEN_A = 'seen = { A = { x = 104, y = 100, z = 0, d = 4 } }'


class RetreatSurrenderTests(PureBase):
    def test_retreat_thresholds_of_health_fear_and_morale(self):
        # LK06-T07 : sous WOUND_RATIO (50 %), constantes mauvaises : plus de combat, retraite (avant : combat jusqu'à 35 %).
        self.assertEqual(self.decide(f'{FIGHTER}, health = 0.5, atHome = false')[:2], ('threat', 'fight'))
        rule, b, why = self.decide(f'{FIGHTER}, health = 0.36, atHome = false')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 36% < 50%, back home', why)
        rule, b, why = self.decide(f'{FIGHTER}, health = 0.34, atHome = false')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 34% < 35%, back home', why)
        # Au foyer, un blessé s'abrite (LK06-T07 ; avant : il s'y défendait) ; sans foyer, il fuit.
        rule, b, why = self.decide(f'{FIGHTER}, health = 0.2')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 20% < 50%, hiding at home', why)
        self.assertIn('fleeing', self.decide(f'{FIGHTER}, health = 0.2, home = false')[2])
        # Peur : ne se bat plus à 70 (NEED_HIGH.fear, LK06-T07 ; avant : 85), rompt à 85, se terre au foyer.
        self.assertEqual(self.decide(f'{FIGHTER}, needs = {{ fear = 69 }}')[:2], ('threat', 'fight'))
        rule, b, why = self.decide(f'{FIGHTER}, needs = {{ fear = 84 }}')
        self.assertEqual((b, why), ('retreat', 'player A at 4.0, fear 84 >= 70, hiding at home'))
        rule, b, why = self.decide(f'{FIGHTER}, needs = {{ fear = 85 }}')
        self.assertEqual(b, 'retreat')
        self.assertIn('fear 85 >= 85, hiding at home', why)
        # Moral du groupe bas (< 30) : santé limite 50 % (= WOUND_RATIO depuis LK06-T07), peur limite 65.
        self.assertNotIn('group morale', self.decide(f'{FIGHTER}, health = 0.45, atHome = false, morale = 30')[2])
        rule, b, why = self.decide(f'{FIGHTER}, health = 0.45, atHome = false, morale = 29')
        self.assertEqual(b, 'retreat')
        self.assertIn('group morale 29', why)
        self.assertEqual(self.decide(f'{FIGHTER}, needs = {{ fear = 65 }}, morale = 29')[1], 'retreat')
        self.assertEqual(self.decide(f'{FIGHTER}, needs = {{ fear = 64 }}, morale = 29')[1], 'fight')
        # Aucun danger (ni cible, ni coup, ni menace proche) : aucune retraite, même blessé.
        self.assertEqual(self.decide('health = 0.2, atHome = false')[:2], ('wound', 'home'))
        # Non-combattant blessé loin du foyer, zombie proche : il rentre au foyer au lieu de fuir.
        self.assertEqual(self.decide('health = 0.3, atHome = false, threat = ZOMBIE(5)')[1], 'retreat')
        self.assertEqual(self.decide('health = 0.3, threat = ZOMBIE(5)')[1], 'retreat')   # LK06-T07 : abri au foyer
        self.assertEqual(self.decide('health = 0.3, threat = ZOMBIE(5), home = false')[1], 'retreat')
        # Coup reçu récent : danger, même sans menace perçue.
        self.assertEqual(self.decide('health = 0.3, atHome = false, hit = { u = "A", minute = 600 }')[1], 'retreat')

    def test_weighted_flight_follows_the_closest_threats(self):
        two = ('threat = ZOMBIE(2), threats = { ZOMBIE(2), { kind = "zombie", key = "z43", label = "43", x = 100, '
               'y = 92, z = 0, d = 8, seen = true, flee = true } }')
        unfit = 'health = 0.4, atHome = false'   # LK06-T07 : seul un membre aux constantes mauvaises fuit
        self.assertEqual(self.run_lua(f'return {D}.decide(CTX({{ {unfit}, {two} }})).away'), 166)   # 180 sans le second
        self.assertEqual(self.run_lua(f'return {D}.decide(CTX({{ {unfit}, threat = ZOMBIE(2), threats = {{ ZOMBIE(2) }} '
                                      f'}})).away'), 180)
        # Menaces symétriques : direction tirée (reproductible), jamais nil.
        sym = ('threat = ZOMBIE(2), threats = { ZOMBIE(2), { kind = "zombie", key = "z44", label = "44", x = 98, '
               'y = 100, z = 0, d = 2, seen = true, flee = true } }')
        a = self.run_lua(f'return {D}.decide(CTX({{ {unfit}, {sym} }})).away')
        self.assertEqual(a, self.run_lua(f'return {D}.decide(CTX({{ {unfit}, {sym} }})).away'))
        self.assertEqual(a % 45, 0)
        # Retraite sans foyer : même angle pondéré, regard vers la menace la plus proche.
        out = self.run_lua(f'local o = {D}.decide(CTX({{ {FIGHTER}, health = 0.2, home = false, {two} }})) '
                           'return o.b, o.away, o.angle')
        self.assertEqual(out, ('retreat', 166, 0))

    def test_surrender_of_a_non_combatant_hit_or_cornered_by_a_player(self):
        can = f'canSurrender = true, {SEEN_A}'
        self.assertEqual(self.decide(f'{can}, health = 0.7, hit = {{ u = "A", minute = 600 }}')[1], 'home')
        rule, b, why = self.decide(f'{can}, health = 0.5, hit = {{ u = "A", minute = 600 }}')
        self.assertEqual((rule, b), ('threat', 'surrender'))
        self.assertIn('hit by A at 4.0, health 50%', why)
        out = self.run_lua(f'local o = {D}.decide(CTX({{ {can}, health = 0.5, hit = {{ u = "A", minute = 600 }} }})) '
                           'return o.key, o.u, o.angle')
        self.assertEqual(out, ('pA', 'A', 0))                      # regard vers le joueur, à l'est
        # Frappé en bonne santé, même de tout près : pas de reddition.
        close = 'canSurrender = true, seen = { A = { x = 101, y = 100, z = 0, d = 1.5 } }'
        self.assertNotEqual(self.decide(f'{close}, hit = {{ u = "A", minute = 600 }}')[1], 'surrender')
        # Agresseur non perçu : lieu du coup reçu (regard vers lui).
        out = self.run_lua(f'local o = {D}.decide(CTX({{ canSurrender = true, health = 0.5, hit = {{ u = "A", '
                           'minute = 600, x = 100, y = 103 } })) return o.b, o.angle')
        self.assertEqual(out, ('surrender', 90))
        # Acculé par un joueur hostile, sans coup reçu.
        hostile = ('threat = { kind = "player", key = "pB", label = "B", x = 102, y = 100, z = 0, d = 1.8, '
                   'seen = true, flee = true }')
        self.assertIn('cornered by B', self.decide(f'canSurrender = true, {hostile}, threats = {{ {hostile[9:]} }}')[2])
        # Combattant, groupe qui tire le premier (canSurrender faux), joueur qui a rompu une reddition : jamais.
        self.assertEqual(self.decide(f'{SEEN_A}, health = 0.5, hit = {{ u = "A", minute = 600 }}')[1], 'home')
        self.assertNotEqual(self.decide(f'{can}, betrayed = {{ A = true }}, health = 0.5, '
                                        f'hit = {{ u = "A", minute = 600 }}')[1], 'surrender')
        # Reddition en cours : gardée tant que le joueur reste perçu à 15 cases, puis 2 minutes hors de vue.
        cur = 'canSurrender = true, surrendered = { u = "A", last = 600 }'
        self.assertIn('still surrendering to A at 4.0', self.decide(f'{cur}, {SEEN_A}')[2])
        self.assertEqual(self.decide(f'{cur}, minute = 602')[1], 'surrender')
        self.assertNotEqual(self.decide(f'{cur}, minute = 603')[1], 'surrender')
        far = 'seen = { A = { x = 120, y = 100, z = 0, d = 20 } }'
        self.assertNotEqual(self.decide(f'{cur}, {far}, minute = 603')[1], 'surrender')
        # Reddition avant la retraite (blessé, loin du foyer, frappé par un joueur).
        self.assertEqual(self.decide(f'{can}, health = 0.2, atHome = false, hit = {{ u = "A", minute = 600 }}')[1],
                         'surrender')

    def test_same_inputs_same_defence_decision(self):
        for over in (f'{FIGHTER}, health = 0.2, home = false, threat = ZOMBIE(3), threats = {{ ZOMBIE(3) }}',
                     f'canSurrender = true, {SEEN_A}, health = 0.5, hit = {{ u = "A", minute = 600 }}'):
            first = self.run_lua(f'return DUMP({D}.decide(CTX({{ {over} }})))')
            self.run_lua(f'{D}.reset()')
            self.assertEqual(first, self.run_lua(f'return DUMP({D}.decide(CTX({{ {over} }})))'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
