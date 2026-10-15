"""Tests hors jeu de la défense coordonnée du foyer des PNJ Living Knox (LK05-T09) : server/LivingKnox/LK_Defense.lua
(autorité), branchée dans LK_Decisions.lua (comportement « defend », règle threat après la retraite) et menée avec
LK_Combat.lua (engagement), LK_Zombies.lua (zombies vanilla), LK_Alert.lua (déclenchement) et LK_Routines.lua
(postes relevés au foyer).

    python RadioSurvivor/tests/test_lk_defense.py

Bancs :
- logique pure (rapport de forces et hystérésis, classement des postes face à la menace, affectations déterministes
  et stables, place de « defend » dans la cascade) sur le serveur d'un banc tests/harness.py ;
- pile complète (corps, consignes LK03, exécutant, relais, routines, alerte, combat, zombies) avec le groupe de test
  « deciders » (combattant m-1, ouvrier m-2, combattant m-3) dans la maison HOUSE de test_lk_routines.py (bâtiment
  105..115, porte au sud en 110,115, fenêtres au nord en 112,105 et à l'ouest en 105,110) : solo et serveur dédié +
  deux clients ;
- suite en jeu lk.defense jouée sur les doublures.
Les zombies vanilla de la horde sont vus par chaque membre incarné tant qu'ils existent (le banc ne simule pas la
vue réelle, prouvée par test_lk_senses.py). Les doublures NE PROUVENT PAS l'API réelle, seulement la logique : postes
tenus selon les rôles, aucune sortie inutile, repli quand la menace est trop forte, renforts, fin et marque d'après
l'attaque, même déroulé pour deux observateurs, aucune décision côté client.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_alert import AlertStack  # noqa: E402
from test_lk_combat import COMBAT, COMBAT_CLIENT, COMBAT_DOUBLES, RANGED_DOUBLES  # noqa: E402
from test_lk_zombies import HEALTH, HEALTH_CLIENT, ZOMBIE_DOUBLES, ZOMBIES, ZOMBIES_CLIENT  # noqa: E402

DEFENSE = 'server/LivingKnox/LK_Defense.lua'
SUITE = 'shared/RST/suites/RST_LKDefense.lua'
SUITE_FILE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKDefense.lua'
Df = 'LivingKnox.Defense'
D = 'LivingKnox.Decisions'
C = 'LivingKnox.Combat'

# Relevé publié pour les tests purs (même forme que LK_Routines.survey) : porte au sud, fenêtres au nord et à l'ouest.
PURE = r'''
POSTS = { v = 1, hx = 110, hy = 110, hz = 0,
    posts = { { x = 110, y = 115, z = 0, a = 90, k = "door" }, { x = 112, y = 105, z = 0, a = 270, k = "window" },
              { x = 105, y = 110, z = 0, a = 180, k = "window" } }, round = {}, beds = {} }
SHELTERS = { { x = 108, y = 107, z = 0 }, { x = 109, y = 107, z = 0 }, { x = 110, y = 108, z = 0 } }
HOME = { x = 110, y = 110, z = 0 }
function MEMBERS(spec)
    local out = {}
    for i, s in ipairs(spec) do
        out[i] = { mid = "m-" .. i, number = i, combatant = s ~= "w", valid = s == "f" }
    end
    return out
end
function ASSIGN(phase, spec, tx, ty, prev, blocked)
    local a = LivingKnox.Defense.assign({ phase = phase, posts = POSTS, shelters = SHELTERS, home = HOME, tx = tx,
        ty = ty, members = MEMBERS(spec), prev = prev, blocked = blocked })
    local out = {}
    for i = 1, #spec do
        local e = a["m-" .. i]
        out[i] = e and (e.key .. "@" .. tostring(e.a)) or "none"
    end
    return table.concat(out, ";")
end
'''

# Horde : zombies vanilla vus par chaque membre incarné (autorité) ; LK_Senses.perceived complété.
HORDE = r'''
HORDE_IDS = {}
local base = LivingKnox.Senses.perceived
LivingKnox.Senses.perceived = function(id)
    local per = base(id)
    local body = LivingKnox.Groups.findNpc(id) ~= nil and LivingKnox.Bodies.find(id) or nil
    if body == nil then return per end
    local out = { ms = 0, age = 0, stale = false, nz = 0, seen = 0, heard = 0, p = {}, z = {}, n = {} }
    for _, e in ipairs(per and per.p or {}) do out.p[#out.p + 1] = e end
    for _, e in ipairs(per and per.z or {}) do out.z[#out.z + 1] = e end
    local ids = {}
    for zid in pairs(HORDE_IDS) do ids[#ids + 1] = zid end
    table.sort(ids)
    for _, zid in ipairs(ids) do
        local zb = HARNESS.zombies[zid]
        if zb ~= nil and not zb:isDead() then
            local dx, dy = zb:getX() - body:getX(), zb:getY() - body:getY()
            out.z[#out.z + 1] = { o = zid, x = math.floor(zb:getX()), y = math.floor(zb:getY()), z = 0, a = 1, s = true,
                h = false, d = math.sqrt(dx * dx + dy * dy) }
        end
    end
    return out
end
-- Options sandbox du banc (LK06-T14) : OPT("ZombieEngageFighter", 2), repli sur la doublure précédente.
LK_OPTS = {}
local prevOptions = getSandboxOptions
getSandboxOptions = function()
    local prev = prevOptions ~= nil and prevOptions() or nil
    return { getOptionByName = function(_, name)
        local v = LK_OPTS[name]
        if v ~= nil then return { getValue = function() return v end } end
        if prev ~= nil then return prev:getOptionByName(name) end
        return nil
    end }
end
function OPT(name, v) LK_OPTS["LivingKnox." .. name] = v end
CARE = {}
LivingKnox.Care = { afterAttack = function(gid, mark) CARE[#CARE + 1] = { gid = gid, id = mark.id, n = #mark.wounded,
    wounded = table.concat(mark.wounded, " ") } end }
-- Cibles des consignes de déplacement : relevées pour vérifier qu'aucune ne sort du bâtiment (sortie inutile).
MOVES = {}
local moveTo = LivingKnox.Directives.moveTo
LivingKnox.Directives.moveTo = function(id, x, y, z, g)
    local v, why = moveTo(id, x, y, z, g)
    if v ~= nil then MOVES[#MOVES + 1] = { id = id, x = x, y = y, g = g } end
    return v, why
end
-- Corps des défenseurs hors du bâtiment (105..115) pendant la défense, relevés à chaque passage (SAMPLE).
OUTSIDE = 0
function SAMPLE(ids)
    for id in pairs(ids) do
        local z = LivingKnox.Bodies.find(id)
        local st = LivingKnox.Decisions.get(id)
        if z ~= nil and st ~= nil and st.b == "defend" and LivingKnox.Defense.state.npcs[id] ~= nil
            and (z:getX() < 105 or z:getX() >= 116 or z:getY() < 105 or z:getY() >= 116) then
            local w = LivingKnox.Defense.state.npcs[id]
            if w.reached then OUTSIDE = OUTSIDE + 1 end
        end
    end
end
'''


class PureDefenseBase(PureBase):
    def setUp(self):
        super().setUp()
        for path in ('server/LivingKnox/LK_Alert.lua', DEFENSE):
            self.h.load(self.srv, path)
        self.run_lua(PURE)


class AssessTests(PureDefenseBase):
    def test_withdraw_when_outnumbered_with_hysteresis(self):
        A = f'(function(...) return ({Df}.assess(...)) end)'
        self.assertEqual(self.ev(f'{A}(3, 2, nil)'), 'hold')
        self.assertEqual(self.ev(f'{A}(6, 2, nil)'), 'hold')            # 6 <= 3 x 2
        self.assertEqual(self.ev(f'{A}(7, 2, nil)'), 'withdraw')        # 7 > 3 x 2
        self.assertEqual(self.ev(f'{A}(1, 0, nil)'), 'withdraw')        # aucun combattant valide
        # Repli : retour aux postes seulement quand la menace <= 2 x combattants (pas de va-et-vient).
        self.assertEqual(self.ev(f'{A}(6, 2, "withdraw")'), 'withdraw')
        self.assertEqual(self.ev(f'{A}(5, 2, "withdraw")'), 'withdraw')
        self.assertEqual(self.ev(f'{A}(4, 2, "withdraw")'), 'hold')
        self.assertEqual(self.ev(f'{A}(6, 2, "hold")'), 'hold')
        why = self.run_lua(f'local p, w = {Df}.assess(7, 2, nil) return w')
        self.assertEqual(why, 'threat 7 > 3 x 2 able fighter(s)')

    def test_posts_facing_the_threat_come_first(self):
        def ranked(tx, ty, blocked='nil'):
            return lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs({Df}.rankPosts(POSTS.posts, {tx}, {ty}, '
                                         f'{blocked})) do out[#out + 1] = e.p.k .. e.p.x .. "," .. e.p.y .. '
                                         '(e.facing and "+" or "-") end return out'))
        self.assertEqual(ranked(110, 121), ['door110,115+', 'window105,110-', 'window112,105-'])   # au sud
        self.assertEqual(ranked(98, 110), ['window105,110+', 'door110,115-', 'window112,105-'])    # à l'ouest
        self.assertEqual(ranked(112, 98), ['window112,105+', 'window105,110-', 'door110,115-'])    # au nord
        self.assertEqual(ranked(110, 121, '{ ["post 110,115,0"] = true }'), ['window105,110-', 'window112,105-'])
        self.assertEqual(ranked('nil', 'nil'), ['door110,115+', 'window112,105+', 'window105,110+'])   # relevé

    def test_assignments_are_deterministic_unique_and_stable(self):
        # Combattants valides aux postes face à la menace (sud) ; ouvrier à l'abri le plus éloigné ; blessé à l'abri.
        out = self.ev('ASSIGN("hold", { "f", "w", "f" }, 110, 121)').split(';')
        self.assertEqual(out[0], 'post 110,115,0@90')                   # porte, regard vers la horde
        self.assertTrue(out[2].startswith('post 105,110,0@'), out)     # fenêtre ouest, ne donne pas sur la horde :
        self.assertTrue(out[2].endswith('@180'), out)                  # regard vers l'extérieur du poste
        self.assertEqual(out[1], 'shelter 108,107,0@' + out[1].split('@')[1])
        self.assertEqual(self.ev('ASSIGN("hold", { "f", "w", "f" }, 110, 121)'),
                         self.ev('ASSIGN("hold", { "f", "w", "f" }, 110, 121)'))
        # Blessé (combattant non valide) : abri, comme les non-combattants (au plus loin de la menace).
        out = self.ev('ASSIGN("hold", { "f", "w", "x" }, 110, 121)').split(';')
        self.assertTrue(out[2].startswith('shelter 109,107,0'), out)
        # Repli : tout le monde à l'abri, un abri chacun ; combattants côté menace, non-combattants au plus loin.
        out = self.ev('ASSIGN("withdraw", { "f", "w", "f" }, 110, 121)').split(';')
        self.assertEqual([o.split('@')[0] for o in out], ['shelter 110,108,0', 'shelter 108,107,0',
                                                          'shelter 109,107,0'])
        # Plus de membres que d'abris : repli sur la case du foyer.
        out = self.ev('ASSIGN("withdraw", { "w", "w", "w", "w" }, 110, 121)').split(';')
        self.assertEqual(out[3].split('@')[0], 'shelter 110,110,0')
        # Poste gardé : m-3 tenait la porte, la menace bouge un peu, il la garde (pas d'échange).
        out = self.ev('ASSIGN("hold", { "f", "w", "f" }, 109, 121, { ["m-3"] = "post 110,115,0" })').split(';')
        self.assertEqual(out[2].split('@')[0], 'post 110,115,0')
        self.assertEqual(out[0].split('@')[0], 'post 105,110,0')
        # Poste bloqué (trajet manqué) : écarté.
        out = self.ev('ASSIGN("hold", { "f" }, 110, 121, nil, { ["post 110,115,0"] = true })').split(';')
        self.assertEqual(out[0].split('@')[0], 'post 105,110,0')

    def test_defend_comes_after_surrender_and_retreat_before_fight(self):
        dv = 'defense = { id = "def-1", role = "post", key = "def:post 110,115,0", why = "home defense def-1 hold" }'
        fighter = 'role = "fighter", allowed = { fight = true, defend = true, guard = true }, combatant = true'
        rule, b, why = self.decide(f'{dv}, {fighter}, target = {{ kind = "zombie", u = "z:5", d = 4 }}')
        self.assertEqual((rule, b, why), ('threat', 'defend', 'home defense def-1 hold'))
        self.assertEqual(self.ev(f'{D}.decide(CTX({{ {dv} }})).key'), 'def:post 110,115,0')
        # Combattant à bout de nerfs : retraite avant la défense.
        self.assertEqual(self.decide(f'{dv}, {fighter}, needs = {{ fear = 95 }}, hit = {{ u = "A", minute = 600 }}')[1],
                         'retreat')
        # Sans défense : le combat libre de LK06-T04 reste.
        self.assertEqual(self.decide(f'{fighter}, target = {{ kind = "zombie", u = "z:5", d = 4 }}')[1], 'fight')
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.defend.vigil'), 'guard')
        self.assertIs(self.ev('LivingKnox.Needs == nil or LivingKnox.Needs.BEHAVIOUR_ACTIVITY.defend ~= nil'), True)


class DefenseStack(AlertStack):
    """Pile complète : groupe « deciders » dans la maison HOUSE, alerte, combat, zombies, santé, défense."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            for f in (COMBAT_DOUBLES, RANGED_DOUBLES, ZOMBIE_DOUBLES, HEALTH, COMBAT, ZOMBIES, DEFENSE):
                h.load(m, f)
            if m != 'server':
                for f in (COMBAT_CLIENT, HEALTH_CLIENT, ZOMBIES_CLIENT):
                    h.load(m, f)
        h.load('solo' if self.mode == 'solo' else 'server', HORDE)
        return h

    def dpass(self, n=1, walk=0.0):
        """Passages de RoutineStack, puis relevé des défenseurs sortis du bâtiment (SAMPLE)."""
        for _ in range(n):
            super().dpass(1, walk)
            self.run_lua('local ids = {} for _, g in ipairs(LivingKnox.Groups.list()) do '
                         'for _, m in pairs(LivingKnox.Groups.get(g.id or g).members) do '
                         'if m.npc then ids[m.npc] = true end end end SAMPLE(ids)')

    def horde(self, spots, first=7001):
        """Zombies vanilla aux cases spots, sur toutes les machines (serveur propriétaire en MP), vus par le groupe."""
        ids = []
        for i, (x, y) in enumerate(spots):
            zid = first + i
            self.h.spawn_zombie(zid, x + 0.5, y + 0.5, 0, owner='server' if self.mode == 'mp' else 'solo')
            for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
                self.h.eval(m, f'VANILLA({zid}, 2.0) ~= nil')
            self.run_lua(f'HORDE_IDS[{zid}] = true')
            ids.append(zid)
        return ids

    def kill(self, zid):
        self.run_lua(f'HORDE_IDS[{zid}] = nil')
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            self.h.eval(m, f'(function() HARNESS.removeZombie({zid}) return true end)()')

    def plan(self, gid):
        return self.run_lua(f'local p = {Df}.get("{gid}") if p == nil then return nil end '
                            'local out = {} for mid, a in pairs(p.assign) do out[#out + 1] = mid .. "=" .. a.key end '
                            'table.sort(out) return p.phase, table.concat(out, ";"), p.zombies, p.threat')

    def place_of(self, gid, mid):
        return self.ev(f'{Df}.get("{gid}").assign["{mid}"].key')

    def npcs(self, gid):
        return {m: self.npc_of(gid, m) for m in ('m-1', 'm-2', 'm-3')}

    def ids_set(self, gid):
        return '{ ' + ', '.join(f'["{n}"] = true' for n in self.npcs(gid).values()) + ' }'

    def settle(self, gid, n=40):
        """Marche (solo) jusqu'à ce que chacun soit à sa place de défense."""
        for _ in range(n):
            self.dpass(1, walk=1.0)
            if self.at_places(gid):
                return True
        return False

    def at_places(self, gid):
        return self.run_lua(f'local p = {Df}.get("{gid}") if p == nil then return false end '
                            'for mid, a in pairs(p.assign) do local z = LivingKnox.Bodies.find(MEMBER_NPC("' + gid +
                            '", mid)) local dx, dy = z:getX() - (a.x + 0.5), z:getY() - (a.y + 0.5) '
                            'if math.sqrt(dx * dx + dy * dy) > 1.0 then return false end end return true')

    def gesture(self, gid, mid, m=None):
        return self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{mid}"))', m)

    def hurt(self, gid, mid, ratio):
        """Santé de référence (LK_Health) du membre à ratio x sa santé de naissance, blessure du registre alignée."""
        self.update(gid, f'g.members["{mid}"].wound = {int(round((1 - ratio) * 100))}')
        self.run_lua(f'local n = LivingKnox.Store.data().npcs[MEMBER_NPC("{gid}", "{mid}")] '
                     f'if n.hpMax ~= nil then n.hp = n.hpMax * {ratio} end')

    def opt(self, name, value):
        """Option sandbox LivingKnox.<name> sur l'autorité (doublure OPT de HORDE)."""
        self.run_lua(f'OPT("{name}", {value})')

    def hold_posts_only(self):
        """Portée d'engagement réduite à 2 cases : tenue des postes de LK05-T09 seule (sorties de LK06-T14 : SallyTests)."""
        for role in ('Deputy', 'Fighter', 'Scout', 'Medic', 'Worker', 'Breaker'):
            self.opt('ZombieEngage' + role, 2)

    def engaged(self, gid, mid):
        return self.ev(f'(function() local o = {C}.get(MEMBER_NPC("{gid}", "{mid}")) return o and o.u or nil end)()')


class SoloDefenseTests(DefenseStack):
    mode = 'solo'

    def test_small_horde_posts_manned_fight_at_the_door_no_sortie_then_over(self):
        gid = self.mk()
        self.hold_posts_only()   # LK06-T14 : horde hors de la zone de 2 cases ; la sortie est prouvée par SallyTests
        self.jump_to(11)
        self.dpass(3)
        self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))                     # aucune menace : aucune défense
        z = self.horde([(110, 121), (111, 122), (109, 122)])                 # au sud, devant la porte
        self.dpass(3)
        phase, places, zombies, threat = self.plan(gid)
        self.assertEqual((phase, zombies, threat), ('hold', 3, 3))
        # LK06-T07 : l'ouvrier valide se bat aussi : un poste chacun (avant : ouvrier à l'abri).
        self.assertEqual(places, 'm-1=post 110,115,0;m-2=post 105,110,0;m-3=post 112,105,0')
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertEqual(self.b(gid, m), 'defend', m)
        self.assertTrue(any('home defense def-1 (hold, leader m-1): 3 zombie(s), 0 hostile(s), 3 able fighter(s)' in
                            line for line in self.lk()), self.lk()[-20:])
        log = lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                                    'if e.kind == "defense" then out[#out + 1] = e.text end end return out'))
        self.assertEqual(len(log), 1)
        self.assertTrue(self.settle(gid))
        # A leur place : regard vers la horde (porte), vers l'extérieur (fenêtre ouest, poste nord), tous en garde.
        self.dpass(2)
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertEqual(self.gesture(gid, m), 'guard', m)
        self.assertEqual(self.ev(f'LivingKnox.Directives.get(MEMBER_NPC("{gid}", "m-1")).a'), 90)
        self.assertEqual(self.ev(f'LivingKnox.Directives.get(MEMBER_NPC("{gid}", "m-2")).a'), 180)
        self.assertEqual(self.ev(f'LivingKnox.Directives.get(MEMBER_NPC("{gid}", "m-3")).a'), 270)
        npc2 = self.npc_of(gid, 'm-2')
        self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf("{npc2}")'), 'guard')
        # Horde à 6 cases de la porte, hors de la zone (2 cases), mains nues (fusil sans cartouche) : personne ne sort.
        self.dpass(5)
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertIsNone(self.engaged(gid, m), m)
        self.assertEqual(self.ev('OUTSIDE'), 0)
        # Un zombie arrive à la porte (110,116) : le défenseur de la porte le frappe depuis son poste.
        self.h.move_zombie(z[0], 110.5, 116.5)
        self.dpass(2)
        self.assertEqual(self.engaged(gid, 'm-1'), f'z:{z[0]}')
        self.assertIsNone(self.engaged(gid, 'm-3'))
        self.assertIn('home defense def-1', self.ev(f'{C}.get(MEMBER_NPC("{gid}", "m-1")) ~= nil and "home defense def-1"'))
        # Le zombie recule à 4 cases, hors de la zone : plus de mêlée, retour au poste ; aucune sortie.
        self.h.move_zombie(z[0], 110.5, 119.5)
        self.dpass(2)
        self.assertIsNone(self.engaged(gid, 'm-1'))
        self.assertTrue(self.settle(gid))
        self.assertEqual(self.ev('OUTSIDE'), 0)
        # Horde partie : la défense prend fin après END_MINUTES, marque d'après l'attaque, appel des soins.
        self.hurt(gid, 'm-2', 0.6)
        for zid in z:
            self.kill(zid)
        self.dpass(2)
        self.assertIsNotNone(self.ev(f'{Df}.get("{gid}")'))                  # pas encore : END_MINUTES
        self.h.advance(3)
        self.dpass(3)
        self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))
        self.assertEqual(self.ev(f'{Df}.after("{gid}").id'), 'def-1')
        self.assertEqual(self.ev(f'{Df}.after("{gid}").wounded[1]'), 'm-2')
        self.assertEqual((self.ev('#CARE'), self.ev('CARE[1].id'), self.ev('CARE[1].wounded')), (1, 'def-1', 'm-2'))
        self.assertTrue(any('home defense def-1 over after' in line and 'wounded: m-2' in line for line in self.lk()))
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertNotEqual(self.b(gid, m), 'defend', m)
        self.assertEqual(self.ev(f'{Df}.stats.started'), 1)
        self.assertEqual(self.ev(f'{Df}.stats.ended'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_too_strong_horde_everyone_inside_then_back_to_the_posts(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        # LK06-T07 : les trois membres se battent d'abord (7 <= 3 x 3), puis l'ouvrier prend peur (7 zombies proches :
        # peur 70, constantes mauvaises) : 7 > 3 x 2 membres valides, repli.
        z = self.horde([(108 + i, 121 + (i % 2)) for i in range(7)])
        self.dpass(3)
        phase, places, zombies, threat = self.plan(gid)
        self.assertEqual((phase, zombies), ('withdraw', 7))
        self.assertTrue(any('def-1 (hold, leader m-1): 7 zombie(s), 0 hostile(s), 3 able fighter(s)' in line
                            for line in self.lk()), self.lk()[-10:])
        self.assertEqual(self.ev(f'{D}.needsOf("{gid}", "m-2").fear'), 70)
        for part in places.split(';'):
            self.assertIn('=shelter ', part)
        keys = [p.split('=')[1] for p in places.split(';')]
        self.assertEqual(len(set(keys)), 3)                                   # un abri chacun
        self.assertTrue(any('leader m-1 orders everyone inside' in line for line in self.lk()) or
                        any('home defense def-1 (withdraw' in line for line in self.lk()), self.lk()[-10:])
        self.assertTrue(self.settle(gid))
        for m in ('m-1', 'm-3'):
            self.assertIsNone(self.engaged(gid, m), m)
        self.assertEqual(self.ev('OUTSIDE'), 0)
        # Quatre zombies tombent : 3 <= 2 x 2, retour aux postes.
        for zid in z[:4]:
            self.kill(zid)
        self.dpass(3)
        phase, places, _, _ = self.plan(gid)
        self.assertEqual(phase, 'hold')
        self.assertIn('m-1=post ', places)
        self.assertTrue(any('back to the posts' in line for line in self.lk()))
        # Combattant blessé (santé 40 % < 50 %) : plus valide, il passe à l'abri ; 3 > 3 x 1 n'est pas vrai : tenue.
        self.hurt(gid, 'm-3', 0.4)
        self.dpass(2)
        phase, places, _, _ = self.plan(gid)
        self.assertEqual(phase, 'hold')
        self.assertIn('m-3=shelter ', places)
        self.assertEqual(self.h.errors('solo'), [])

    def test_member_outside_comes_back_running_as_a_reinforcement(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        self.run_lua(f'HARNESS.place(LivingKnox.Bodies.find(MEMBER_NPC("{gid}", "m-3")), 125.5, 110.5, 0)')
        self.horde([(110, 121), (111, 122)])
        self.dpass(3)
        self.assertEqual(self.b(gid, 'm-3'), 'defend')
        key = self.place_of(gid, 'm-3')
        self.assertTrue(key.startswith('post '), key)
        op, gait, x = self.run_lua(f'local e = LivingKnox.Directives.get(MEMBER_NPC("{gid}", "m-3")) '
                                   'return e.op, e.g, e.x')
        self.assertEqual((op, gait), ('move', 'run'))
        self.assertLessEqual(x, 115)                                          # vers l'intérieur
        self.assertTrue(self.settle(gid, 60))
        # Membre trop loin (40 cases) : hors de la défense.
        self.run_lua(f'HARNESS.place(LivingKnox.Bodies.find(MEMBER_NPC("{gid}", "m-3")), 150.5, 110.5, 0)')
        self.run_lua(f'{Df}.state.groups["{gid}"].at = nil')
        self.dpass(2)
        self.assertIsNone(self.ev(f'{Df}.get("{gid}").assign["m-3"]'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_unreachable_place_is_blocked_and_another_one_given(self):
        gid = self.mk()
        self.hold_posts_only()
        self.jump_to(11)
        self.dpass(2)
        self.assertIsNotNone(self.ev('LivingKnox.Routines.state.valid["' + gid + '"]'))   # postes relevés
        # La case du poste de la porte devient injoignable (meuble posé) : trajets refusés.
        self.run_lua('HARNESS.square(110, 115, 0).blocked = true')
        self.horde([(110, 121), (111, 122)])
        self.dpass(1)
        first = 'post 110,115,0'
        for _ in range(8):
            self.dpass(1, walk=1.0)
            if self.place_of(gid, 'm-1') != first:
                break
        self.assertNotEqual(self.place_of(gid, 'm-1'), first)
        self.assertGreaterEqual(self.ev(f'{Df}.stats.blocked'), 1)
        self.assertTrue(any('cannot reach its defense place' in line for line in self.lk()))
        self.assertEqual(self.h.errors('solo'), [])


class CampDefenseTests(DefenseStack):
    """LK05-T18 (décision de l'utilisateur du 2026-10-14) : un groupe en campement (foyer hors de tout bâtiment) se
    bat sur place : défense ouverte, combattants aux postes en couronne autour du camp, sortie dans la portée de leur
    rôle puis retour aux places, membres aux constantes mauvaises au centre, repli au centre, défense close. Camp de
    test en 130,130 (aucune pièce du banc), membres m-1 combattant, m-2 ouvrier, m-3 combattant."""
    mode = 'solo'
    HOME = (130, 130)

    def mk_camp(self, hurt=None):
        x, y = self.HOME
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Camp", day = 1, '
                f'home = {{ x = {x}, y = {y}, z = 0 }} }})) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 120, 120)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset()')
        if hurt:
            self.hurt(gid, hurt, 0.4)
        self.jump_to(11)
        self.dpass(2)
        self.assertIs(self.ev(f'LivingKnox.Routines.ensurePosts("{gid}", LivingKnox.Groups.get("{gid}")).camp'), True)
        return gid

    def places(self, gid):
        out = {}
        for part in self.plan(gid)[1].split(';'):
            mid, key = part.split('=')
            role, xyz = key.split(' ')
            x, y, _ = (int(v) for v in xyz.split(','))
            out[mid] = (role, x, y)
        return out

    def ring(self, x, y):
        return max(abs(x - self.HOME[0]), abs(y - self.HOME[1]))

    def test_camp_posts_ring_and_center(self):
        x, y = self.HOME
        posts = lua_list(self.run_lua(f'local out = {{}} for _, p in ipairs({Df}.campPosts({{ x = {x}, y = {y}, z = 0 }})'
                                      '.posts) do out[#out + 1] = p.x .. "," .. p.y .. "@" .. p.a .. p.k end return out'))
        self.assertEqual(posts, ['130,127@270camp', '133,130@0camp', '130,133@90camp', '127,130@180camp',
                                 '133,127@315camp', '133,133@45camp', '127,133@135camp', '127,127@225camp'])
        # Point de la couronne injoignable (tente, meuble) : voisine praticable, toujours en couronne.
        self.run_lua('HARNESS.square(130, 133, 0).blocked = true')
        posts = lua_list(self.run_lua(f'local out = {{}} for _, p in ipairs({Df}.campPosts({{ x = {x}, y = {y}, z = 0 }})'
                                      '.posts) do out[#out + 1] = p.x .. "," .. p.y end return out'))
        self.assertEqual(posts[2], '130,132')
        # Abris : centre du camp (une case autour du foyer), hors postes, au plus loin de la menace d'abord.
        shelters = lua_list(self.run_lua(f'local out = {{}} for _, s in ipairs({Df}.campShelters({{ x = {x}, y = {y}, '
                                         f'z = 0 }}, nil, 130, 140)) do out[#out + 1] = s.x .. "," .. s.y end return out'))
        self.assertEqual(len(shelters), 8)                                    # MAX_SHELTERS
        self.assertEqual(shelters[:3], ['129,129', '130,129', '131,129'])
        self.assertTrue(all(self.ring(*(int(v) for v in s.split(','))) <= 1 for s in shelters), shelters)

    def test_camp_attacked_by_three_zombies_fights_on_the_spot_then_defense_over(self):
        gid = self.mk_camp()
        self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))                      # aucune menace : aucune défense
        z = self.horde([(130, 138), (131, 139), (129, 139)])                  # au sud, à 8-9 cases du foyer
        self.dpass(3)
        phase, _, zombies, threat = self.plan(gid)
        self.assertEqual((phase, zombies, threat), ('hold', 3, 3))
        self.assertIs(self.ev(f'{Df}.get("{gid}").camp'), True)
        self.assertTrue(any('home defense def-1 (hold, leader m-1): 3 zombie(s), 0 hostile(s), 3 able fighter(s)' in
                            line and ', camp' in line for line in self.lk()), self.lk()[-20:])
        places = self.places(gid)
        # Tout le monde se bat (LK06-T07) : un poste chacun, en couronne, le poste sud (face à la horde) d'abord.
        self.assertEqual({p[0] for p in places.values()}, {'post'})
        self.assertEqual(len({(p[1], p[2]) for p in places.values()}), 3)
        self.assertEqual(places['m-1'][1:], (130, 133))
        for mid, p in places.items():
            self.assertEqual(self.ring(p[1], p[2]), 3, (mid, p))
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertEqual(self.b(gid, m), 'defend', m)
        self.assertEqual(self.ev(f'{Df}.stats.offenses'), 0)                  # pas de fenêtre au camp
        # Sortie dans la portée du rôle (10 cases autour du poste) : un défenseur va au-devant de la horde.
        engaged = set()
        for _ in range(15):
            self.dpass(1, walk=1.0)
            for m in ('m-1', 'm-2', 'm-3'):
                if self.engaged(gid, m) is not None:
                    engaged.add(m)
            if engaged:
                break
        self.assertIn('m-1', engaged)
        npc = self.npc_of(gid, 'm-1')
        r, lx, ly = self.run_lua(f'local o = {C}.orders["{npc}"] return o.leash.r, o.leash.x, o.leash.y')
        self.assertEqual((r, lx, ly), (10, 130, 133))                          # laisse = portée autour du poste
        # Horde tuée : plus de cible, retour aux places (gestes de garde), défense close après END_MINUTES.
        for zid in z:
            self.kill(zid)
        self.dpass(2)
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertIsNone(self.engaged(gid, m), m)
        self.assertTrue(self.settle(gid, 60))
        self.dpass(2)
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertEqual(self.gesture(gid, m), 'guard', m)
        self.assertEqual(self.leash_loops(), [])
        self.h.advance(3)
        self.dpass(3)
        self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))
        self.assertEqual(self.ev(f'{Df}.after("{gid}").id'), 'def-1')
        self.assertEqual(self.ev('CARE[1].id'), 'def-1')
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertNotEqual(self.b(gid, m), 'defend', m)
        self.assertEqual(self.h.errors('solo'), [])

    def leash_loops(self):
        return [line for line in self.lk() if 'target out of the defense leash' in line]

    def test_wounded_member_at_the_center_and_overwhelmed_camp_gathers_at_the_center(self):
        gid = self.mk_camp(hurt='m-2')                                        # santé 40 % : constantes mauvaises
        self.horde([(130, 138), (131, 139), (129, 139)])
        self.dpass(3)
        places = self.places(gid)
        self.assertEqual(self.plan(gid)[0], 'hold')                           # 3 <= 3 x 2 combattants valides
        self.assertEqual(places['m-2'][0], 'shelter')
        self.assertLessEqual(self.ring(places['m-2'][1], places['m-2'][2]), 1)    # au centre du camp
        self.assertEqual(places['m-1'][0], 'post')
        self.assertEqual(places['m-3'][0], 'post')
        for _ in range(6):
            self.dpass(1, walk=1.0)
            self.assertIsNone(self.engaged(gid, 'm-2'))                       # le blessé ne sort jamais
        # Sept zombies de plus : 10 > 3 x 2, repli au centre (aucun bâtiment où entrer), personne ne sort.
        self.horde([(124 + i, 140) for i in range(7)], first=7101)
        self.dpass(3)
        self.assertEqual(self.plan(gid)[0], 'withdraw')
        places = self.places(gid)
        self.assertEqual({p[0] for p in places.values()}, {'shelter'})
        self.assertEqual(len({(p[1], p[2]) for p in places.values()}), 3)    # un abri chacun
        for mid, p in places.items():
            self.assertLessEqual(self.ring(p[1], p[2]), 1, (mid, p))
        for _ in range(6):
            self.dpass(1, walk=1.0)
            for m in ('m-1', 'm-2', 'm-3'):
                self.assertIsNone(self.engaged(gid, m), m)
        self.assertTrue(self.settle(gid, 60))
        self.assertEqual(self.h.errors('solo'), [])

    def test_camp_switch_off_keeps_the_old_behaviour(self):
        self.run_lua(f'{Df}.CFG.CAMP = false')
        try:
            gid = self.mk_camp()
            self.horde([(133, 131)])
            self.dpass(3)
            self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))
            self.assertNotEqual(self.b(gid, 'm-1'), 'defend')
        finally:
            self.run_lua(f'{Df}.CFG.CAMP = true')
        self.assertEqual(self.h.errors('solo'), [])


class SallyTests(DefenseStack):
    """LK06-T14 (décision de l'utilisateur du 2026-10-13) : en défense « hold », un membre valide va au-devant d'un
    zombie à la portée d'engagement de son rôle (ZombieEngage<Rôle>, 10 par défaut) autour de sa place, puis revient ;
    jamais en repli ni pour un membre inapte ; une cible hors de la laisse n'est jamais choisie (plus de relance en
    boucle « target out of the defense leash »). Doublures : ligne de vue et de coup Clear (LOS_RESULT)."""
    mode = 'solo'

    def start(self, spots, radius=20):
        gid = self.mk()
        self.opt('DefenseRadius', radius)   # zombie à 8 ou 12 cases du poste : 13 à 17 du foyer, recensé
        self.jump_to(11)
        self.dpass(2)
        return gid, self.horde(spots)

    def order(self, gid, mid):
        return self.run_lua(f'local o = {C}.orders[MEMBER_NPC("{gid}", "{mid}")] if o == nil then return nil end '
                            'return o.u, o.leash and o.leash.r, o.leash and o.leash.x, o.leash and o.leash.y')

    def leash_loops(self):
        return [line for line in self.lk() if 'target out of the defense leash' in line]

    def test_zombie_8_squares_from_the_post_is_engaged_then_back_to_the_post(self):
        gid, z = self.start([(110, 123)])               # 8 cases au sud du poste de la porte (110,115)
        engaged = None
        for _ in range(12):
            self.dpass(1, walk=1.0)
            engaged = self.engaged(gid, 'm-1')
            if engaged is not None:
                break
        self.assertEqual(self.plan(gid)[0], 'hold')
        self.assertEqual(self.place_of(gid, 'm-1'), 'post 110,115,0')
        self.assertEqual(engaged, f'z:{z[0]}')                         # ancien code : jamais (MELEE_ENGAGE 2)
        self.assertEqual(list(self.order(gid, 'm-1')), [f'z:{z[0]}', 10, 110, 115])   # laisse = portée du rôle
        # Hors de la zone des autres postes (fenêtres ouest et nord : 13 et 18 cases) : aucune autre sortie.
        self.assertIsNone(self.engaged(gid, 'm-2'))
        self.assertIsNone(self.engaged(gid, 'm-3'))
        # Il va au-devant du zombie : consigne de course vers sa case, hors du bâtiment.
        npc = self.npc_of(gid, 'm-1')
        self.assertTrue(self.run_lua(f'for _, mv in ipairs(MOVES) do if mv.id == "{npc}" and mv.y >= 120 then '
                                     'return true end end return false'))
        for _ in range(6):
            self.dpass(1, walk=1.0)
        self.assertEqual(self.engaged(gid, 'm-1'), f'z:{z[0]}')        # ordre gardé, sans relance
        self.assertEqual(self.leash_loops(), [])
        self.assertEqual(len([line for line in self.lk() if f'against zombie z:{z[0]}' in line
                              and 'melee #' in line and 'with' in line]), 1)
        # Zombie tué : retour au poste.
        self.kill(z[0])
        self.dpass(2)
        self.assertIsNone(self.engaged(gid, 'm-1'))
        self.assertTrue(self.settle(gid, 60))
        self.assertEqual(self.h.errors('solo'), [])

    def test_zombie_12_squares_from_every_post_is_not_engaged(self):
        gid, z = self.start([(110, 124)])               # 9 cases de la porte : défense et sortie
        for _ in range(12):
            self.dpass(1, walk=1.0)
            if self.engaged(gid, 'm-1') is not None:
                break
        self.assertEqual(self.engaged(gid, 'm-1'), f'z:{z[0]}')
        # Il recule à 12 cases de la porte (17 et 22 des fenêtres) : ordre clos une fois, jamais relancé.
        self.h.move_zombie(z[0], 110.5, 127.5)
        for _ in range(10):
            self.dpass(1, walk=1.0)
        for m in ('m-1', 'm-2', 'm-3'):
            self.assertIsNone(self.engaged(gid, m), m)
        self.assertEqual(self.plan(gid)[0], 'hold')
        starts = [line for line in self.lk() if 'melee #' in line and ' with ' in line]
        self.assertEqual(len(starts), 1, starts)
        self.assertLessEqual(len(self.leash_loops()), 1, self.leash_loops())
        self.assertTrue(self.settle(gid, 60))                          # retour au poste
        self.assertEqual(self.h.errors('solo'), [])

    def test_engage_range_read_from_the_role_of_the_member(self):
        # Ouvrier (worker) à 3 cases, combattants à 10 : m-2 (fenêtre ouest 105,110) ne sort pas vers un zombie à 8
        # cases de sa place ; le combattant de la porte (110,115), à 5 cases, si.
        self.opt('ZombieEngageWorker', 3)
        gid, z = self.start([(105, 118)])
        self.assertEqual(self.ev(f'{Df}.engageRange(MEMBER_NPC("{gid}", "m-2"))'), 3)
        self.assertEqual(self.ev(f'{Df}.engageRange(MEMBER_NPC("{gid}", "m-1"))'), 10)
        for _ in range(10):
            self.dpass(1, walk=1.0)
            self.assertIsNone(self.engaged(gid, 'm-2'))
        self.assertEqual(self.engaged(gid, 'm-1'), f'z:{z[0]}')
        self.assertEqual(self.h.errors('solo'), [])

    def test_wounded_member_and_withdraw_never_go_out(self):
        gid = self.mk()
        self.opt('DefenseRadius', 20)
        self.hurt(gid, 'm-1', 0.4)                       # constantes mauvaises : abri, jamais de sortie
        self.jump_to(11)
        self.dpass(2)
        z = self.horde([(110, 121)])
        for _ in range(8):
            self.dpass(1, walk=1.0)
            self.assertIsNone(self.engaged(gid, 'm-1'))
        self.assertTrue(self.place_of(gid, 'm-1').startswith('shelter '), self.place_of(gid, 'm-1'))
        self.assertIn(f'z:{z[0]}', (self.engaged(gid, 'm-2'), self.engaged(gid, 'm-3')))   # porte tenue : sortie
        # Repli (7 zombies de plus) : personne ne sort.
        self.horde([(104 + i, 122) for i in range(7)], first=7101)
        for _ in range(6):
            self.dpass(1, walk=1.0)
        self.assertEqual(self.plan(gid)[0], 'withdraw')
        for _ in range(4):
            self.dpass(1, walk=1.0)
            for m in ('m-1', 'm-2', 'm-3'):
                self.assertIsNone(self.engaged(gid, m), m)
        self.assertEqual(self.h.errors('solo'), [])

    def test_target_out_of_the_leash_is_never_chosen(self):
        # Ancien défaut : zombie à MELEE_ENGAGE (2) cases du corps mais hors de la laisse de sa place (1 case) et hors
        # de portée de l'arme : choisi, puis l'ordre abandonné aussitôt (« target out of the defense leash »), en
        # boucle à chaque passage. Repli (sans sortie) : laisse COMBAT_LEASH = 1.
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        npc = self.npc_of(gid, 'm-1')
        reach = self.ev(f'{C}.weaponOf("{npc}").reach')
        self.assertLess(reach, 1.85)
        bx, by = self.run_lua(f'local b = LivingKnox.Bodies.find("{npc}") return b:getX(), b:getY()')
        z = self.horde([(int(bx) - 4, int(by) - 4)])
        self.h.move_zombie(z[0], bx - 1.85, by)
        call = (f'(function() local b = LivingKnox.Bodies.find("{npc}") '
                'local a = { role = "shelter", x = math.floor(b:getX()) + 2, y = math.floor(b:getY()), z = 0, '
                'fighter = true } '
                f'local zb = HARNESS.zombies[{z[0]}] '
                'local census = { list = { { zombie = zb, key = LivingKnox.Zombies.keyOf(zb) } } } '
                f'local t = {Df}.targetFor("{npc}", b, {{}}, a, census, "withdraw") '
                'return t and t.u or "none" end)()')
        self.assertEqual(self.ev(call), 'none')
        self.h.move_zombie(z[0], bx - 1.0, by)           # à portée de l'arme : frappé sur place
        self.assertEqual(self.ev(call), f'z:{z[0]}')
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerDefenseTests(DefenseStack):
    """Serveur dédié + deux clients proches : défense décidée par le serveur seul, mêmes consignes, mêmes gestes et
    même vigilance chez A et B ; même déroulé pour le même monde."""

    def observed(self, gid):
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
                                           '.. tostring(e.a) .. ":" .. tostring(e.g)) or "none" '
                                           f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") .. "|" '
                                           f'.. LivingKnox.Senses.vigilanceOf("{npc}") end)()'))
            out[c] = rows
        return out

    def scenario(self):
        gid = self.mk()
        self.hold_posts_only()
        self.jump_to(11)
        self.dpass(2)
        self.horde([(110, 121), (111, 122), (109, 122)])
        self.dpass(3)
        first = self.observed(gid)
        self.h.move_zombie(7001, 110.5, 116.5)
        self.dpass(2)
        second = self.observed(gid)
        return gid, first, second

    def test_two_observers_see_the_same_defense(self):
        gid, first, second = self.scenario()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Defense'))            # autorité seulement
        self.assertEqual(first['A'], first['B'])
        self.assertEqual(second['A'], second['B'])
        self.assertTrue(first['A'][0].startswith('move:110,115@'), first['A'][0])   # en route vers la porte
        self.assertTrue(first['A'][0].endswith(':run|idle|guard') or '|guard' in first['A'][0], first['A'][0])
        for row in first['A']:
            self.assertTrue(row.endswith('|guard'), row)                       # vigilance de garde partout
        self.assertEqual(self.plan(gid)[0], 'hold')
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])

    def test_same_world_twice_gives_the_same_defense(self):
        def run():
            gid, first, second = self.scenario()
            return first['A'], second['A'], self.plan(gid), [line for line in self.lk() if 'home defense' in line]
        a = run()
        self.h.close()
        self.h = self.make()
        self.init()
        self.away()
        b = run()
        self.assertEqual(a, b)


class SuiteTests(DefenseStack):
    mode = 'solo'

    def start_suite(self, x, y, test):
        """Suite lk.defense sur les doublures, joueur en (x, y), seulement le test dont le nom contient test."""
        from test_lk_alert import VANILLA_ZOMBIES
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', VANILLA_ZOMBIES)
        self.h.move_player('A', x, y)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.defense", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.defense')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.defense", tags = "world", '
                                          f'test = "{test}" }}, {{ ctx = {{ player = getPlayer() }} }}))'), True)

    def run_suite(self, door=None):
        """Passages jusqu'à la fin de la suite ; door : un zombie de la horde posé là après « at places »."""
        moved = False
        for i in range(20000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 20 == 19:
                self.h.advance(1)
            if door and not moved and self.ev('LivingKnox.Defense.stats.started') == 1 and i % 50 == 0:
                if any('at places:' in line for line in self.h.logs('solo')):
                    self.run_lua('local ids = {} for zid in pairs(VANILLA) do if HARNESS.zombies[zid] then '
                                 'ids[#ids + 1] = zid end end table.sort(ids) '
                                 f'HARNESS.place(HARNESS.zombies[ids[1]], {door[0]}, {door[1]}, 0)')
                    moved = True
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        return report, results, moved

    def test_suite_lk_defense_camp_passes_on_the_doubles(self):
        # LK05-T18 : joueur sur un terrain dégagé (130,130, hors de la maison du banc) : camp, couronne de postes.
        self.start_suite(130, 130, 'camp attacked')
        report, results, _ = self.run_suite()
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKD' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKD] measure camp: 8 post(s) in a ring of 3 squares', '[LKD] measure defense started',
                     ', camp', '[LKD] measure at places', '[LKD] measure fight', '[LKD] measure defense over'):
            self.assertTrue(any(text in line for line in logs), text)
        fight = next(line for line in logs if '[LKD] measure fight' in line)
        self.assertIn('sorties 0, stuck 0', fight)
        # Campagne solo du 2026-10-15 : au camp (aucun mur), le blessé se défend au contact (point 4 de LK_Defense,
        # « sans sortie ») ; la suite compte à part les combats au-delà du contact, qui doivent rester à 0.
        wounded = next(line for line in logs if '[LKD] measure wounded member m-4: place' in line)
        self.assertIn('fights beyond contact 0, at contact ', wounded)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_lk_defense_passes_on_the_doubles(self):
        self.start_suite(110, 110, 'near the home')
        report, results, moved = self.run_suite(door=(110.5, 116.5))
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKD' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKD] measure defense started', '[LKD] measure at places', '[LKD] measure fight',
                     '[LKD] measure defense over'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertTrue(moved)
        self.assertTrue(any('melee #' in line and 'home defense def-1' in line for line in logs))   # à la porte
        fight = next(line for line in logs if '[LKD] measure fight' in line)
        self.assertIn('sorties 0, stuck 0', fight)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        for path in (SUITE_FILE, LUA / DEFENSE):
            raw = path.read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'\bbit32\b', r'[~&|]\s*\d',
                            r'<<|>>'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))
        self.assertTrue(all(b < 128 for b in SUITE_FILE.read_bytes()), 'non ASCII byte in the suite')


if __name__ == '__main__':
    unittest.main(verbosity=1)
