"""Tests hors jeu des routines des PNJ Living Knox (LK05-T03) : server/LivingKnox/LK_Routines.lua, branché dans
LK_Decisions.lua (cascade), LK_Directives.lua (vigilance vg portée par la consigne) et LK_Senses.lua (lecture de vg
chez un client MP).

    python RadioSurvivor/tests/test_lk_routines.py

Bancs :
- logique pure (heures, quarts, affectation des postes, des rondes et des couchages, contrôle du relevé sauvegardé) ;
- relevé d'un foyer dans un monde doublé (banc MatBase de test_lk_materialize.py) : bâtiment = rectangle BUILDINGS,
  portes et fenêtres = bords EDGES (getDoorTo, getWindowTo : IsoGridSquare.java:3107-3112, 3131-3172), couchages =
  objets dont les propriétés du sprite portent IsoFlagType.bed (IsoObject.getProperties, IsoObject.java:3136-3141 ;
  PropertyContainer.has(IsoFlagType) et get(String), PropertyContainer.java:84, 162 ; BedType lu comme
  ISWorldObjectContextMenuLogic.java:2847-2850) ;
- pile complète (corps, consignes LK03, exécutant, relais) avec le groupe de test « deciders » de test_lk_decisions.py :
  solo (marche simulée par STEP) et serveur dédié + deux clients (observateurs).
Les doublures NE PROUVENT PAS l'API réelle, seulement la logique : relevé déterministe, relèves aux heures prévues,
guet au poste, ronde, sommeil au couchage, menace qui interrompt, vigilance identique chez deux observateurs.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import CTX, DECIDERS, DUMP, PureBase  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
from test_lk_senses import SENSES_DOUBLES  # noqa: E402

SENSES = 'shared/LivingKnox/LK_Senses.lua'
R = 'LivingKnox.Routines'
D = 'LivingKnox.Decisions'

# Relevé publié pour les tests purs : 3 postes, ronde de 4 cases, 2 couchages, foyer 110,110,0.
POSTS = r'''
POSTS = { v = 1, hx = 110, hy = 110, hz = 0, day = 1,
    posts = { { x = 110, y = 115, z = 0, a = 90, k = "door" }, { x = 112, y = 105, z = 0, a = 270, k = "window" },
              { x = 105, y = 110, z = 0, a = 180, k = "window" } },
    round = { { x = 103, y = 103, z = 0 }, { x = 117, y = 103, z = 0 }, { x = 117, y = 117, z = 0 },
              { x = 103, y = 117, z = 0 } },
    beds = { { x = 107, y = 106, z = 0, bx = 107, by = 107, a = 90, q = 4 },
             { x = 113, y = 107, z = 0, bx = 113, by = 108, a = 90, q = 3 } } }
function COPY(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = COPY(x) end
    return out
end
-- Groupe minimal (registre) : membres m-1..m-n vivants, postes donnés (sentry, rest...).
function GROUP(duties)
    local g = { members = {} }
    for i, d in ipairs(duties) do g.members["m-" .. i] = { alive = true, duty = d } end
    return g
end
-- Heure d'âge du monde dont l'heure du jour est hod (premier jour : âge 0 = 7 h).
function AGE(hod, day) return (hod + 17) % 24 + 24 * (day or 0) end
'''

# Monde doublé du relevé : portes, fenêtres et couchages ; zone non chargée à partir de UNLOADED_X.
WORLD = r'''
local H = HARNESS
local C = H.classes
IsoFlagType = IsoFlagType or {}
IsoFlagType.bed = IsoFlagType.bed or "bed"   -- IsoFlagType.java:64
EDGES, EDGES_ON, UNLOADED_X = {}, true, nil
local Door = H.class('IsoDoor', C.IsoObject)
local Win = H.class('IsoWindow', C.IsoObject)
-- Porte ordinaire fermée (IsoDoor.java : IsOpen, isHoppable, isTallHoppable ; LK13-T11 : lue par
-- Executor.behindClosedDoor quand la cible d'un déplacement est juste derrière elle).
function Door:IsOpen() return false end
function Door:isHoppable() return false end
function Door:isTallHoppable() return false end
local function key(a, b) return a.x .. "," .. a.y .. "|" .. b.x .. "," .. b.y end
local function edge(a, b, kind)
    if not EDGES_ON or b == nil or EDGES[key(a, b)] ~= kind then return nil end
    return setmetatable({}, kind == "door" and Door or Win)
end
function C.IsoGridSquare:getDoorTo(nb) return edge(self, nb, "door") end
function C.IsoGridSquare:getWindowTo(nb) return edge(self, nb, "window") end
function ADD_EDGE(x, y, x2, y2, kind)
    EDGES[x .. "," .. y .. "|" .. x2 .. "," .. y2] = kind
    EDGES[x2 .. "," .. y2 .. "|" .. x .. "," .. y] = kind
end
local Props = H.class('PropertyContainer')
function Props:has(flag) return flag == IsoFlagType.bed and self.bed == true end
function Props:get(name) return rawget(self, name) end
local Bed = H.class('IsoBedDouble', C.IsoObject)
function Bed:getSprite() return self.props ~= nil and {} or nil end
function Bed:getProperties() return self.props end
function ADD_BED(x, y, bedType)
    local o = setmetatable({ props = setmetatable({ bed = true, BedType = bedType }, Props) }, Bed)
    H.addObject(x, y, 0, o)
    H.square(x, y, 0).blocked = true
    return o
end
local Cell = getmetatable(getCell())
local get = Cell.getGridSquare
function Cell:getGridSquare(x, y, z)
    if UNLOADED_X ~= nil and x >= UNLOADED_X then return nil end
    return get(self, x, y, z)
end
-- Foyer de test : bâtiment 105..115 (id 7), porte au sud, deux fenêtres, deux lits (dont un double), un fauteuil-lit.
function HOUSE()
    BUILDINGS = { { 105, 105, 115, 115, 7 } }
    ADD_EDGE(110, 115, 110, 116, "door")
    ADD_EDGE(112, 105, 112, 104, "window")
    ADD_EDGE(105, 110, 104, 110, "window")
    ADD_BED(107, 107, "goodBed")
    ADD_BED(107, 108, "goodBed")
    ADD_BED(113, 108, nil)
end
-- Un pas de marche de chaque corps qui simule ici.
function STEP_ALL(speed)
    for zid in pairs(H.zombies) do STEP(zid, speed) end
end
'''


class PureRoutineTests(PureBase):
    def setUp(self):
        super().setUp()
        self.run_lua(POSTS)

    def test_periods_watches_and_sentry_kind_by_hour_of_day(self):
        # Nuit (22 h-6 h) : guet ; aube (6 h-8 h) : ronde ; jour : ronde la première heure du quart, guet ensuite.
        want = {23: 'guard', 1: 'guard', 3: 'guard', 5: 'guard', 6: 'patrol', 7: 'patrol', 8: 'guard',
                10: 'patrol', 11: 'guard', 13: 'guard', 14: 'patrol', 15: 'guard', 18: 'patrol', 19: 'guard',
                21: 'guard'}
        for hod, kind in want.items():
            self.assertEqual(self.ev(f'{R}.sentryKind(AGE({hod}, 2), POSTS)'), kind, hod)
            self.assertEqual(self.ev(f'{R}.sentryKind(AGE({hod}, 2), nil)'), 'guard', hod)   # sans relevé
        noround = self.run_lua(f'local p = COPY(POSTS) p.round = {{}} return {R}.sentryKind(AGE(6, 2), p)')
        self.assertEqual(noround, 'guard')
        self.assertEqual(self.ev(f'{R}.period(AGE(23))'), 'night')
        self.assertEqual(self.ev(f'{R}.period(AGE(6))'), 'dawn')
        self.assertEqual(self.ev(f'{R}.period(AGE(12))'), 'day')
        # Quarts de 4 h : le numéro change à 22 h, 2 h, 6 h, 10 h, 14 h, 18 h, et seulement là.
        changes = []
        for age in range(24, 72):
            if self.ev(f'{D}.watchOf({age})') != self.ev(f'{D}.watchOf({age - 1})'):
                changes.append((age + 7) % 24)
        self.assertEqual(sorted(set(changes)), [2, 6, 10, 14, 18, 22])
        self.assertEqual(len(changes), 12)

    def test_watch_rotation_gives_every_able_member_a_turn(self):
        # Trois membres aptes au guet, objectif « settle » (un guetteur) : chacun a son quart sur une journée (I3.1),
        # le même guetteur tout le quart, même résultat d'une fois sur l'autre.
        code = r'''
            local members = {}
            for i = 1, 3 do
                members[i] = { mid = "m-" .. i, number = i, allowed = { guard = true }, wound = 0 }
            end
            local out = {}
            for age = 24, 47 do
                local duties = LivingKnox.Decisions.assignDuties(members, "settle", LivingKnox.Decisions.isNight(age),
                    LivingKnox.Decisions.rotation(5, age))
                for mid, d in pairs(duties) do
                    if d == "sentry" then out[#out + 1] = mid end
                end
            end
            return table.concat(out, ",")
        '''
        first = self.run_lua(code).split(',')
        self.assertEqual(first, self.run_lua(code).split(','))
        self.assertEqual(len(first), 24)
        self.assertEqual(set(first), {'m-1', 'm-2', 'm-3'})
        for age in range(24, 48):
            if self.ev(f'{D}.watchOf({age})') == self.ev(f'{D}.watchOf({age - 1})') and age > 24:
                self.assertEqual(first[age - 24], first[age - 25], age)

    def test_posts_rounds_and_beds_are_shared_out_deterministically(self):
        g = 'local g = GROUP({ "sentry", "rest", "sentry", "keeper" }) '
        # Postes : rang du guetteur + numéro de quart ; deux guetteurs jamais au même poste.
        for age in (40, 44, 48):
            a = self.run_lua(g + f'local p = {R}.postFor(POSTS, g, "m-1", {age}) return p.x, p.y, p.a, p.k')
            b = self.run_lua(g + f'local p = {R}.postFor(POSTS, g, "m-3", {age}) return p.x, p.y, p.a, p.k')
            self.assertNotEqual(a[:2], b[:2], age)
        seen = {self.run_lua(g + f'local p = {R}.postFor(POSTS, g, "m-1", {age}) return p.x .. "," .. p.y')
                for age in (40, 44, 48)}
        self.assertEqual(len(seen), 3)                                   # les postes tournent à chaque quart
        # Ronde : deux guetteurs répartis sur la boucle.
        self.assertEqual(self.run_lua(g + f'return {R}.roundStart(POSTS, g, "m-1"), {R}.roundStart(POSTS, g, "m-3")'),
                         (1, 3))
        # Couchages : rang parmi les présents hors guetteurs ; guetteur fatigué : lits restants ; au-delà : rien.
        self.assertEqual(self.run_lua(g + f'local b = {R}.bedFor(POSTS, g, "m-2") return b.bx, b.by'), (107, 107))
        self.assertEqual(self.run_lua(g + f'local b = {R}.bedFor(POSTS, g, "m-4") return b.bx, b.by'), (113, 108))
        self.assertIsNone(self.run_lua(g + f'return {R}.bedFor(POSTS, g, "m-1")'))
        self.assertEqual(self.run_lua('local g = GROUP({ "sentry", "rest" }) '
                                      f'local b = {R}.bedFor(POSTS, g, "m-1") return b.bx'), 113)
        # Membre en expédition ou mort : absent du rang.
        self.assertEqual(self.run_lua(g + 'g.members["m-2"].alive = false '
                                      f'local b = {R}.bedFor(POSTS, g, "m-4") return b.bx'), 107)
        self.assertEqual(self.run_lua(g + 'g.expedition = { team = { "m-2" } } '
                                      f'local b = {R}.bedFor(POSTS, g, "m-4") return b.bx'), 107)
        # Plans : poste, ronde, couchage ; replis sans relevé (regard, assis sur place).
        self.assertEqual(self.run_lua(g + f'local p = {R}.plan("guard", POSTS, g, "m-1", 40, 0) return p.kind, p.a'),
                         ('post', self.run_lua(g + f'return {R}.postFor(POSTS, g, "m-1", 40).a')))
        self.assertEqual(self.run_lua(g + f'local p = {R}.plan("patrol", POSTS, g, "m-1", 40, 0) '
                                      'return p.kind, #p.points, p.start'), ('round', 4, 1))
        self.assertEqual(self.run_lua(g + f'local p = {R}.plan("sleep", POSTS, g, "m-2", 40) '
                                      'return p.kind, p.x, p.y, p.a, p.sit'), ('bed', 107, 106, 90, True))
        self.assertEqual(self.run_lua(g + f'local p = {R}.plan("guard", nil, g, "m-1", 40, 135) return p.kind, p.a'),
                         ('face', 135))
        self.assertEqual(self.run_lua(g + f'return {R}.plan("patrol", {{ round = {{}} }}, g, "m-1", 40, 45).kind'),
                         'face')
        self.assertEqual(self.run_lua(g + f'return {R}.plan("sleep", nil, g, "m-1", 40).kind'), 'sit')
        self.assertIsNone(self.run_lua(g + f'return {R}.plan("home", POSTS, g, "m-1", 40)'))

    def test_saved_survey_is_checked_in_its_form(self):
        home = '{ x = 110, y = 110, z = 0 }'
        self.assertEqual(self.run_lua(f'return {R}.validPosts(POSTS, {home})'), True)
        cases = {
            'p.v = 2': 'unknown format',
            'p.hx = 111': 'home moved',
            'p.camp = 1': 'bad camp flag',
            'p.posts[1].k = "hatch"': 'bad posts',
            'p.posts[2].a = 360': 'bad posts',
            'p.posts[5] = p.posts[1]': 'bad posts',
            'p.posts = "x"': 'bad posts',
            'p.round[2].x = 1.5': 'bad round',
            'p.beds[1].q = 9': 'bad beds',
            'p.beds[1].z = 40': 'bad beds',
        }
        for edit, why in cases.items():
            got = self.run_lua(f'local p = COPY(POSTS) {edit} return {R}.validPosts(p, {home})')
            self.assertEqual(got, (False, why), edit)
        self.assertEqual(self.run_lua(f'return {R}.validPosts(nil, {home})'), (False, 'unknown format'))

    def test_cascade_turns_sentry_into_post_or_round_and_threat_wins(self):
        sentry = ('duty = "sentry", role = "fighter", allowed = { guard = true, fight = true }, combatant = true')
        self.assertEqual(self.decide(sentry)[:2], ('duty', 'guard'))
        self.assertEqual(self.decide(sentry + ', sentryKind = "patrol"')[:2], ('duty', 'patrol'))
        self.assertEqual(self.decide(sentry + ', sentryKind = "patrol", atHome = false')[:2], ('duty', 'home'))
        self.assertEqual(self.decide(sentry + ', sentryKind = "patrol", threat = ZOMBIE(8)')[:2], ('threat', 'watch'))
        self.assertEqual(self.decide('duty = "rest", night = true')[:2], ('duty', 'sleep'))
        self.assertEqual(self.decide('duty = "rest", night = true, threat = ZOMBIE(3)')[:2], ('threat', 'watch'))   # LK06-T07 : membre valide, il tient
        # Guet et ronde : même poste (clé) -> passer de l'un à l'autre interrompt l'état (nouvelle décision).
        st = self.run_lua(f'local a = {D}.decide(CTX({{ {sentry} }})) '
                          f'local b = {D}.decide(CTX({{ {sentry}, sentryKind = "patrol" }})) '
                          f'return {D}.replaces(a, b, a.start)')
        self.assertEqual(st, (True, 'interrupted'))


class SurveyTests(MatBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', WORLD)
        h.load('solo', POSTS)
        h.load('solo', DUMP)
        return h

    def survey(self, x=110, y=110):
        return self.run_lua(f'local p, why = {R}.survey({{ x = {x}, y = {y}, z = 0 }}) '
                            'if p == nil then return nil, why end return DUMP(p)')

    def test_doors_first_then_windows_beds_once_and_a_round_outside(self):
        self.run_lua('HOUSE()')
        p = self.run_lua(f'local p = assert({R}.survey({{ x = 110, y = 110, z = 0 }})) return p')
        posts = lua_list(self.ev(f'(function() local p = {R}.survey({{ x = 110, y = 110, z = 0 }}) local out = {{}} '
                                 'for _, e in ipairs(p.posts) do out[#out + 1] = e.k .. ":" .. e.x .. "," .. e.y .. "@" '
                                 '.. e.a end return out end)()'))
        self.assertEqual(posts, ['door:110,115@90', 'window:112,105@270', 'window:105,110@180'])
        beds = lua_list(self.ev(f'(function() local p = {R}.survey({{ x = 110, y = 110, z = 0 }}) local out = {{}} '
                                'for _, e in ipairs(p.beds) do out[#out + 1] = e.x .. "," .. e.y .. ">" .. e.bx .. "," '
                                '.. e.by .. "@" .. e.a .. "q" .. e.q end return out end)()'))
        # Lit double (107,107)-(107,108) compté une fois, meilleur d'abord ; place au nord, regard vers le lit (sud).
        self.assertEqual(beds, ['107,106>107,107@90q4', '113,107>113,108@90q3'])
        rnd = lua_list(self.ev(f'(function() local p = {R}.survey({{ x = 110, y = 110, z = 0 }}) local out = {{}} '
                               'for _, e in ipairs(p.round) do out[#out + 1] = e.x .. "," .. e.y end return out end)()'))
        self.assertEqual(rnd, ['103,103', '110,103', '117,103', '117,110', '117,117', '110,117', '103,117', '103,110'])
        self.assertIsNotNone(p)
        # Même monde, même relevé ; contrôle de forme accepté.
        self.assertEqual(self.survey(), self.survey())
        self.assertIs(self.run_lua(f'return {R}.validPosts({R}.survey({{ x = 110, y = 110, z = 0 }}), '
                                   '{ x = 110, y = 110, z = 0 })'), True)

    def test_round_avoids_blocked_squares_and_stays_on_the_leash(self):
        self.run_lua('HOUSE() HARNESS.square(103, 103, 0).blocked = true')
        rnd = lua_list(self.ev(f'(function() local p = {R}.survey({{ x = 110, y = 110, z = 0 }}) local out = {{}} '
                               'for _, e in ipairs(p.round) do out[#out + 1] = e.x .. "," .. e.y end return out end)()'))
        self.assertEqual(rnd[0], '102,102')                             # marge suivante (3 cases)
        for xy in rnd:
            x, y = map(int, xy.split(','))
            self.assertLessEqual(max(abs(x - 110), abs(y - 110)), self.ev(f'{D}.CFG.HOME_RADIUS'))

    def test_camp_and_unloaded_home(self):
        self.run_lua('HOUSE()')
        camp = self.run_lua(f'local p = {R}.survey({{ x = 140, y = 140, z = 0 }}) '
                            'return p.camp, #p.posts, #p.round, #p.beds')
        self.assertEqual(camp, (True, 0, 0, 0))
        self.run_lua('UNLOADED_X = 118')
        self.assertEqual(self.survey(), (None, 'home area not loaded'))


class RoutineStack(MatBase):
    """Pile complète avec le groupe « deciders » (combattant m-1, ouvrier m-2, combattant m-3) dans la maison HOUSE."""

    CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false'), ('fighter', 'gunner', 'true')]

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, WORLD)
            h.load(m, SENSES_DOUBLES)
            h.load(m, SENSES)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, DECIDERS)
        h.load(srv, DUMP)
        h.load(srv, 'HOUSE()')
        return h

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        if self.mode == 'mp':
            self.h.move_player('B', 101, 112)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() {R}.reset() for k in pairs({D}.stats) do {D}.stats[k] = 0 end '
                     f'for k in pairs({R}.stats) do {R}.stats[k] = 0 end')
        return gid

    def npc_of(self, gid, mid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").members["{mid}"].npc')

    def dpass(self, n=1, walk=0.0):
        """n secondes : un passage des décisions, une passe de l'exécutant ; marche de speed cases par seconde."""
        every = self.ev('LivingKnox.Executor.EXEC_EVERY', 'A' if self.mode == 'mp' else None)
        for _ in range(n):
            if walk and self.mode == 'solo':
                for _ in range(4):
                    self.run_lua(f'STEP_ALL({walk / 4})')
            self.h.advance_ms(1000)
            self.h.tick(every)
            if self.mode == 'mp':
                self.h.pump()

    def jump_to(self, hod):
        """Avance l'horloge jusqu'à la prochaine heure du jour hod (minute 0)."""
        age = self.h.age_minutes
        now_hod = ((age // 60) + 7) % 24
        hours = (hod - now_hod) % 24 or 24
        minutes = hours * 60 - age % 60
        import datetime as _dt
        self.h.date += _dt.timedelta(minutes=minutes)
        self.h.age_minutes += minutes
        self.h._push_clock()

    def sentries(self, gid):
        out = self.run_lua(f'local out = {{}} local g = LivingKnox.Groups.get("{gid}") '
                           'for mid, m in pairs(g.members) do if m.duty == "sentry" then out[#out + 1] = mid end end '
                           'table.sort(out) return out')
        return lua_list(out)

    def entry(self, gid, mid):
        return self.run_lua(f'local e = LivingKnox.Directives.get(MEMBER_NPC("{gid}", "{mid}")) '
                            'if e == nil then return nil end return e.op, e.x, e.y, e.a, e.done, e.s, e.vg')

    def b(self, gid, mid):
        return self.run_lua(f'local s = {D}.get(MEMBER_NPC("{gid}", "{mid}")) return s and s.b or nil')


class SoloRoutineTests(RoutineStack):
    mode = 'solo'

    def test_survey_saved_once_with_the_group(self):
        gid = self.mk()
        self.dpass(3)
        posts = self.run_lua(f'local p = LivingKnox.Groups.get("{gid}").posts '
                             'return p.v, #p.posts, #p.round, #p.beds, p.hx, p.hy')
        self.assertEqual(posts, (1, 3, 8, 2, 110, 110))
        self.assertEqual(self.ev(f'{R}.stats.surveys'), 1)
        self.assertEqual(len(self.lines('home 110,110,0 surveyed: 3 post(s) (1 door, 2 window)')), 1)
        # Relu du registre (nouvelle mémoire) : gardé, pas de nouveau relevé ; foyer déplacé : relevé refait.
        self.run_lua(f'{R}.reset()')
        self.dpass(3)
        self.assertEqual(self.ev(f'{R}.stats.surveys'), 1)
        self.update(gid, 'g.posts.v = 99')
        self.run_lua(f'{R}.reset()')
        self.dpass(3)
        self.assertEqual(self.ev(f'{R}.stats.surveys'), 2)
        self.assertEqual(len(self.lines('home survey redone (unknown format)')), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_sentry_walks_to_its_post_and_faces_out(self):
        gid = self.mk()
        self.jump_to(11)                                       # jour, deuxième heure du quart : guet au poste
        self.dpass(2)
        sentry = self.sentries(gid)
        self.assertEqual(len(sentry), 1)
        s = sentry[0]
        self.assertEqual(self.b(gid, s), 'guard')
        post = self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") '
                            f'local p = {R}.postFor(g.posts, g, "{s}", {D}.currentHour()) return p.x, p.y, p.a')
        op, x, y = self.entry(gid, s)[:3]
        self.assertEqual((op, x, y), ('move', post[0], post[1]))
        for _ in range(40):
            self.dpass(1, walk=1.0)
            e = self.entry(gid, s)
            if e[0] == 'face' and e[4]:
                break
        e = self.entry(gid, s)
        self.assertEqual((e[0], e[3], e[4]), ('face', post[2], True))
        bx, by = self.body_xy(gid, s)
        self.assertLessEqual(((bx - post[0] - 0.5) ** 2 + (by - post[1] - 0.5) ** 2) ** 0.5, 1.0)
        self.assertEqual(e[6], 'guard')                                          # vigilance portée par la consigne
        self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf(MEMBER_NPC("{gid}", "{s}"))'), 'guard')
        self.assertEqual(self.h.errors('solo'), [])

    def test_night_sleepers_go_to_their_beds_and_sit_a_threat_wakes_them(self):
        gid = self.mk()
        for m in ('m-1', 'm-2', 'm-3'):                                          # tous dehors, dans la cour
            self.run_lua(f'HARNESS.place(MAT_BODY("{gid}", "{m}"), 117.5, 1{int(m[2:]) + 11}.5, 0)')
        self.jump_to(23)
        self.dpass(2)
        sleepers = [m for m in ('m-1', 'm-2', 'm-3') if self.b(gid, m) == 'sleep']
        self.assertEqual(len(sleepers), 2)                                       # un guetteur, deux dormeurs
        for _ in range(60):
            self.dpass(1, walk=1.0)
            if all(self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{m}"))') == 'sit' for m in sleepers):
                break
        at_bed = 0
        for m in sleepers:
            npc = self.npc_of(gid, m)
            self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit', m)
            self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf("{npc}")'), 'sleep', m)
            bed = self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") local b = {R}.bedFor(g.posts, g, "{m}") '
                               'if b == nil then return nil end return b.x, b.y, b.a')
            if bed is not None:
                at_bed += 1
                bx, by = self.body_xy(gid, m)
                self.assertLessEqual(((bx - bed[0] - 0.5) ** 2 + (by - bed[1] - 0.5) ** 2) ** 0.5, 1.0, m)
                self.assertEqual(self.entry(gid, m)[3], bed[2], m)                # tourné vers le lit
            else:                                                                # sans couchage : dedans
                bx, by = self.body_xy(gid, m)
                self.assertTrue(105 <= bx < 116 and 105 <= by < 116, (m, bx, by))
        self.assertGreaterEqual(at_bed, 1)
        # Menace vue par l'ouvrier endormi : il se lève et fuit ; le combattant endormi se lève et regarde.
        for m in sleepers:
            x, y = self.body_xy(gid, m)
            self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "{m}"), {int(x) + 3}, {int(y)}, 3, 950)')
        self.dpass(2)
        for m in sleepers:
            npc = self.npc_of(gid, m)
            self.assertIn(self.b(gid, m), ('flee', 'watch'), m)
            self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")') == 'sit', False, m)
            self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf("{npc}")'), 'guard', m)
            self.assertIsNone(self.ev(f'{R}.get("{npc}")'), m)
        # Menace partie : retour au couchage (même plan, nouvelle consigne).
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)                                                       # LK05-T08 : alerte retombée d'abord
        self.dpass(2)
        for m in sleepers:
            self.assertEqual(self.b(gid, m), 'sleep', m)
        self.assertEqual(self.h.errors('solo'), [])

    def test_sleepers_without_a_bed_go_inside_and_sit(self):
        gid = self.mk()
        self.dpass(2)                                                            # relevé fait
        self.update(gid, 'g.posts.beds = {}')
        for m in ('m-1', 'm-2', 'm-3'):                                          # tous dehors, dans la cour
            self.run_lua(f'HARNESS.place(MAT_BODY("{gid}", "{m}"), 117.5, 1{int(m[2:]) + 11}.5, 0)')
        self.jump_to(23)
        self.dpass(2)
        sleepers = [m for m in ('m-1', 'm-2', 'm-3') if self.b(gid, m) == 'sleep']
        self.assertEqual(len(sleepers), 2)
        for _ in range(60):
            self.dpass(1, walk=1.0)
            if all(self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{m}"))') == 'sit' for m in sleepers):
                break
        for m in sleepers:
            self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{m}"))'), 'sit', m)
            bx, by = self.body_xy(gid, m)
            self.assertTrue(105 <= bx < 116 and 105 <= by < 116, (m, bx, by))
            self.assertEqual(self.entry(gid, m)[0], 'stop', m)
        self.assertEqual(self.h.errors('solo'), [])

    def test_dawn_round_visits_the_loop_in_order(self):
        gid = self.mk()
        self.jump_to(6)
        self.dpass(2)
        s = self.sentries(gid)[0]
        self.assertEqual(self.b(gid, s), 'patrol')
        npc = self.npc_of(gid, s)
        seq = []
        for _ in range(240):
            self.dpass(1, walk=1.5)
            k = self.ev(f'(function() local m = {R}.get("{npc}") return m and m.k end)()')
            if k is not None and (not seq or seq[-1] != k):
                seq.append(k)
            if len(seq) >= 10:
                break
        self.assertGreaterEqual(len(seq), 9, seq)
        for a, b in zip(seq, seq[1:]):
            self.assertEqual(b, a % 8 + 1, seq)                                  # points dans l'ordre de la boucle
        self.assertGreaterEqual(self.ev(f'{R}.stats.laps'), 1)
        self.assertEqual(self.ev(f'{R}.stats.gaveUp'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_relief_follows_the_watch_hours(self):
        # Une journée heure par heure : le guetteur et le poste de garde ne changent qu'aux relèves (22 h, 2 h, 6 h,
        # 10 h, 14 h, 18 h) ; ces relèves vont au journal du moteur, pas au journal du groupe.
        gid = self.mk()
        self.dpass(2)
        log_before = len(lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log)'
                                               ' do if e.kind == "objective" then out[#out + 1] = e.text end end '
                                               'return out')))
        prev, changes = None, []
        for _ in range(24):
            self.jump_to((((self.h.age_minutes // 60) + 7) % 24 + 1) % 24)
            self.dpass(1)
            hod = ((self.h.age_minutes // 60) + 7) % 24
            cur = tuple(self.sentries(gid))
            if prev is not None and cur != prev:
                changes.append(hod)
            prev = cur
        self.assertTrue(set(changes) <= {2, 6, 10, 14, 18, 22}, changes)
        self.assertGreaterEqual(len(changes), 3, changes)
        log_after = len(lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log)'
                                              ' do if e.kind == "objective" then out[#out + 1] = e.text end end '
                                              'return out')))
        self.assertGreaterEqual(self.ev(f'{D}.stats.watchChanges'), 3)
        self.assertLessEqual(log_after - log_before, 2)                          # nuit / jour au plus
        self.assertEqual(self.h.errors('solo'), [])


SUITE = 'shared/RST/suites/RST_LKRoutines.lua'
SUITE_FILE = Path(__file__).resolve().parents[1] / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

# Heure du jour réglable (GameTime.setTimeOfDay, GameTime.java:770) : l'âge du monde suit (nuits x 24 + heure - 7, ou
# + 17 avant 7 h ; base api-42-21.md), modélisé par un décalage ajouté à l'horloge du banc.
TIME_OF_DAY = r'''
local GT = getmetatable(getGameTime())
TOD_OFFSET = 0
local age = GT.getWorldAgeHours
function GT:getWorldAgeHours() return age(self) + TOD_OFFSET end
function GT:getTimeOfDay() return (self:getWorldAgeHours() + 7) % 24 end
function GT:setTimeOfDay(h)
    HARNESS.num(h, 'setTimeOfDay')
    TOD_OFFSET = TOD_OFFSET - (self:getTimeOfDay() + 17) % 24 + (h + 17) % 24
end
'''


class SuiteTests(RoutineStack):
    mode = 'solo'

    def test_suite_lk_routines_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.move_player('A', 110, 110)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.routines", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.routines')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.routines", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(6000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')   # relevés
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKR' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKR] measure survey: 3 post(s), round of 8, 2 bed(s)', '[LKR] measure night post',
                     '[LKR] measure sleep', '[LKR] measure threat', '[LKR] measure dawn round'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)                # groupe de test retiré
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        import re
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


class MultiplayerRoutineTests(RoutineStack):
    """Serveur dédié + deux clients proches : aucune routine chez un client, même consigne, même geste et même
    vigilance chez les deux observateurs."""

    def observed(self, gid):
        """Pour chaque membre : (consigne, geste, vigilance) vue par A et par B, après livraison."""
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        for c in ('A', 'B'):
            rows = []
            for m in ('m-1', 'm-2', 'm-3'):
                npc = self.npc_of(gid, m)
                rows.append(self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                           'local d = e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. "@" '
                                           '.. tostring(e.a) .. ":" .. tostring(e.v)) or "none" '
                                           f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") .. "|" '
                                           f'.. LivingKnox.Senses.vigilanceOf("{npc}") end)()'))
            out[c] = rows
        return out

    def test_two_observers_see_the_same_routine_and_vigilance(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Routines'))             # autorité seulement
        self.jump_to(11)
        self.dpass(3)
        day = self.observed(gid)
        self.assertEqual(day['A'], day['B'])
        s = self.sentries(gid)[0]
        i = int(s[2:]) - 1
        self.assertTrue(day['A'][i].startswith('move:'), day['A'][i])            # en route vers le poste
        self.assertTrue(day['A'][i].endswith('|guard'), day['A'][i])
        # Nuit : vigilance « sleep » des dormeurs chez les deux clients, portée par la consigne (vg).
        self.jump_to(23)
        self.dpass(3)
        night = self.observed(gid)
        self.assertEqual(night['A'], night['B'])
        sleepers = [m for m in ('m-1', 'm-2', 'm-3') if self.b(gid, m) == 'sleep']
        self.assertEqual(len(sleepers), 2)
        for m in sleepers:
            row = night['A'][int(m[2:]) - 1]
            self.assertTrue(row.endswith('|sleep'), row)
            npc = self.npc_of(gid, m)
            self.assertEqual(self.ev(f'LivingKnox.Directives.entries["{npc}"].vg'), 'sleep')
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])

    def run_scenario(self):
        gid = self.mk()
        out = []
        for hod in (11, 23, 6):
            self.jump_to(hod)
            self.dpass(3)
            out.append(self.observed(gid)['A'])
        out.append(self.run_lua(f'return DUMP(LivingKnox.Groups.get("{gid}").posts)'))
        return out

    def test_same_world_twice_gives_the_same_routine(self):
        first = self.run_scenario()
        self.h.close()
        self.h = self.make()
        self.init()
        self.away()
        second = self.run_scenario()
        self.assertEqual(first, second)


if __name__ == '__main__':
    unittest.main(verbosity=1)
