"""Tests hors jeu des besoins individuels des PNJ Living Knox (LK05-T06) : server/LivingKnox/LK_Needs.lua.

    python RadioSurvivor/tests/test_lk_needs.py

Bancs :
- logique pure (Needs.step, scheduleActivity, bumpOf, advanceMember) sur le serveur d'un banc tests/harness.py chargé
  comme test_lk_simulation.py ;
- registre et horloge du banc : pas horaires (EveryHours) contre rattrapage après un arrêt, coût borné, persistance ;
- cascade de LK_Decisions branchée sur les jauges (envies) ;
- pile complète des corps (banc MatBase de test_lk_decisions.py) : peur montée par une menace perçue, fuite d'un
  non-combattant, aucune jauge chez les clients MP. Les doublures NE PROUVENT PAS l'API réelle, seulement la logique.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_decisions as TD  # noqa: E402
from test_lk_decisions import DUMP, PureBase  # noqa: E402
from test_lk_simulation import Base  # noqa: E402

N = 'LivingKnox.Needs'
D = 'LivingKnox.Decisions'
G = 'LivingKnox.Groups'
SIM = 'LivingKnox.Simulation'

# Jauges de tous les membres vivants, triées : "grp-1/m-1=h,t,f,p@heure ...".
VITALS = r'''
function VITALS()
    local out = {}
    for _, gid in ipairs(LivingKnox.Groups.list()) do
        local g = LivingKnox.Groups.state.data.groups[gid]
        local mids = {}
        for mid in pairs(g.members) do mids[#mids + 1] = mid end
        table.sort(mids)
        for _, mid in ipairs(mids) do
            local v = g.members[mid].vitals
            if v then
                out[#out + 1] = gid .. "/" .. mid .. "=" .. v.hunger .. "," .. v.thirst .. "," .. v.fatigue .. ","
                    .. v.fear .. "@" .. v.hour
            end
        end
    end
    return table.concat(out, " ")
end
'''


# LK13-T09 : les passes horaires partent une par image (LK_Simulation.defer) ; ce banc les vide aussitôt.
FINISH_HOUR = 'if LivingKnox.Simulation and LivingKnox.Simulation.finishHour then LivingKnox.Simulation.finishHour() end'

class PureNeedsTests(PureBase):
    def setUp(self):
        super().setUp()
        self.run_lua(DUMP)

    def step(self, v, activity, fed='true', food='true', threat='false'):
        return self.run_lua(f'local v = {v} {N}.step(v, "{activity}", {fed}, {food}, {threat}) '
                            'return v.hunger, v.thirst, v.fatigue, v.fear')

    def test_step_is_reproducible_and_follows_the_activity(self):
        v = '{ hunger = 20, thirst = 20, fatigue = 50, fear = 40 }'
        self.assertEqual(self.step(v, 'idle'), self.step(v, 'idle'))
        self.assertEqual(self.step(v, 'idle'), (24, 25, 53, 28))
        self.assertEqual(self.step(v, 'sleep'), (22, 23, 38, 22))      # le sommeil fait baisser la fatigue
        self.assertEqual(self.step(v, 'patrol'), (25, 27, 56, 28))     # la ronde la fait monter
        self.assertEqual(self.step(v, 'flee'), (26, 29, 62, 36))       # la fuite davantage ; la peur retombe peu
        self.assertEqual(self.step(v, 'unknown'), self.step(v, 'idle'))   # liste fermée : inconnue = idle
        # Menace perçue pendant l'heure : la peur ne retombe pas.
        self.assertEqual(self.step(v, 'idle', threat='true')[3], 40)
        # Bornes 0..100.
        self.assertEqual(self.step('{ hunger = 99, thirst = 99, fatigue = 5, fear = 3 }', 'sleep', fed='false'),
                         (100, 100, 0, 0))

    def test_meal_and_drink_at_the_meal_point_only(self):
        hungry = '{ hunger = 75, thirst = 72, fatigue = 20, fear = 0 }'
        self.assertEqual(self.step(hungry, 'idle')[:2], (19, 17))               # mange et boit, puis l'heure passe
        self.assertEqual(self.step(hungry, 'idle', food='false')[:2], (79, 17))  # réserve vide : boit seulement
        self.assertEqual(self.step(hungry, 'idle', fed='false')[:2], (79, 77))   # loin du point de repas : rien
        # Sous le seuil de l'envie : aucun repas.
        self.assertEqual(self.step('{ hunger = 69, thirst = 69, fatigue = 20, fear = 0 }', 'idle')[:2], (73, 74))

    def test_schedule_of_a_member_out_of_sight(self):
        def act(edit='', k=10, fatigue=20):
            # Pas k : heure du jour (k + 6) % 24 ; k = 10 -> 16 h (jour), k = 20 -> 2 h (nuit).
            return self.run_lua(f'local g = {{ task = "scavenge", members = {{}} }} local m = {{ id = "m-1" }} {edit} '
                                f'return {N}.scheduleActivity(g, "m-1", m, {{ fatigue = {fatigue} }}, {k})')
        self.assertEqual(act(), ('work', True))
        self.assertEqual(act('g.task = "rest"'), ('rest', True))
        self.assertEqual(act('g.task = nil'), ('idle', True))
        self.assertEqual(act(k=20), ('sleep', True))
        self.assertEqual(act('m.duty = "sentry"', k=20), ('watch', True))
        self.assertEqual(act(fatigue=85), ('sleep', True))                    # envie de dormir, même de jour
        exp = 'g.expedition = { place = "houses", team = { "m-1" }, departed = 5, returns = 12 }'
        self.assertEqual(act(exp), ('travel', True))
        self.assertEqual(act(exp, k=12), ('travel', True))
        self.assertEqual(act(exp, k=13), ('work', True))                      # revenu

    def test_fear_bump_by_threat_kind_trait_and_role(self):
        def bump(t, nervous='false', combatant='false'):
            return self.ev(f'{N}.bumpOf({t}, {nervous}, {combatant})')
        self.assertEqual(bump('{ kind = "zombie", seen = true, d = 3 }'), 20)
        self.assertEqual(bump('{ kind = "zombie", seen = true, d = 9 }'), 10)
        self.assertEqual(bump('{ kind = "zombie", seen = false, d = 2 }'), 5)
        self.assertEqual(bump('{ kind = "player", flee = true, seen = true, d = 9 }'), 25)
        self.assertEqual(bump('{ kind = "player", flee = false, seen = false, d = 9 }'), 4)
        self.assertEqual(bump('{ kind = "zombie", seen = true, d = 3 }', nervous='true'), 30)
        self.assertEqual(bump('{ kind = "zombie", seen = true, d = 3 }', combatant='true'), 10)

    def test_same_activities_on_screen_and_out_of_sight_give_the_same_gauges(self):
        """Membre incarné observé avec les activités de l'horaire = membre hors écran : mêmes jauges sur 24 h (rattrapage maximal)."""
        code = f'''
            local function group()
                return {{ task = "rest", needs = {{ food = 50 }}, members = {{
                    ["m-1"] = {{ id = "m-1", alive = true, vitals = {{ hunger = 30, thirst = 10, fatigue = 60,
                        fear = 50, hour = 100 }} }} }} }}
            end
            local behaviour = {{ sleep = "sleep", rest = "rest", idle = "home", watch = "guard" }}
            -- Hors écran : rattrapage de 24 h en un appel.
            {N}.reset()
            local off = group()
            {N}.advanceMember(off, "grp-1", "m-1", off.members["m-1"], 124)
            -- A l'écran : chaque heure, observations de la cascade avec le comportement de l'horaire, puis un pas.
            {N}.reset()
            local on = group()
            local m = on.members["m-1"]
            for k = 101, 124 do
                local a = {N}.scheduleActivity(on, "m-1", m, m.vitals, k)
                for i = 1, 3 do {N}.observe("grp-1", "m-1", behaviour[a], true, (k - 1) * 60 + i * 10) end
                {N}.advanceMember(on, "grp-1", "m-1", m, k)
            end
            local a, b = off.members["m-1"].vitals, m.vitals
            return DUMP(a), DUMP(b)
        '''
        off, on = self.run_lua(code)
        self.assertEqual(off, on)
        self.assertIn('hour=124', off)

    def test_observed_activity_wins_over_the_schedule(self):
        code = f'''
            {N}.reset()
            local g = {{ task = "rest", needs = {{ food = 50 }}, members = {{ ["m-1"] = {{ id = "m-1", alive = true,
                vitals = {{ hunger = 10, thirst = 10, fatigue = 10, fear = 0, hour = 99 }} }} }} }}
            {N}.observe("grp-1", "m-1", "patrol", true, 99 * 60 + 5)
            {N}.observe("grp-1", "m-1", "patrol", true, 99 * 60 + 15)
            {N}.observe("grp-1", "m-1", "home", true, 99 * 60 + 25)
            {N}.observe("grp-1", "m-1", "dance", true, 99 * 60 + 35)   -- comportement inconnu : ignoré
            {N}.advanceMember(g, "grp-1", "m-1", g.members["m-1"], 100)
            return g.members["m-1"].vitals.fatigue
        '''
        self.assertEqual(self.run_lua(code), 16)   # ronde (+6) et non repos (-4) de la tâche du groupe


class EnvyTests(PureBase):
    """Envies transmises à la cascade de LK_Decisions (seuils NEED_HIGH)."""

    def decide(self, over=''):
        return self.run_lua(f'local o = {D}.decide(CTX({{ {over} }})) return o.rule, o.b, o.why')

    def test_high_fatigue_means_sleep_hunger_and_thirst_mean_home(self):
        self.assertEqual(self.decide('needs = { fatigue = 85 }')[:2], ('fatigue', 'sleep'))
        self.assertEqual(self.decide('needs = { hunger = 75 }')[:2], ('hunger', 'home'))
        self.assertEqual(self.decide('needs = { thirst = 75 }')[:2], ('thirst', 'home'))
        self.assertEqual(self.decide('needs = { fatigue = 85 }, atHome = false')[:2], ('fatigue', 'home'))

    def test_high_fear_makes_a_non_combatant_flee(self):
        zombie9 = '{ kind = "zombie", key = "z9", label = "9", x = 109, y = 100, z = 0, d = 9, seen = true, flee = true }'
        # Menace à 9 cases : regard sans peur, fuite quand la peur est haute (FLEE_DIST_AFRAID).
        self.assertEqual(self.decide(f'threat = {zombie9}')[:2], ('threat', 'watch'))
        # LK06-T07 : la peur haute est une constante mauvaise pour tout rôle : fuite hors du foyer, abri au foyer.
        rule, b, why = self.decide(f'threat = {zombie9}, needs = {{ fear = 80 }}, atHome = false')
        self.assertEqual((rule, b), ('threat', 'flee'))
        self.assertIn('afraid, fear 80 >= 70', why)
        rule, b, why = self.decide(f'threat = {zombie9}, needs = {{ fear = 80 }}')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('fear 80 >= 70, hiding at home', why)
        fighter = 'role = "fighter", allowed = { fight = true, guard = true }, combatant = true'
        self.assertEqual(self.decide(f'threat = {zombie9}, needs = {{ fear = 80 }}, atHome = false, {fighter}')[:2],
                         ('threat', 'flee'))
        # Aucune menace perçue, source récente de la peur à 5 cases à l'est : fuite vers l'ouest.
        out = self.run_lua(f'local o = {D}.decide(CTX({{ needs = {{ fear = 80 }}, fearFrom = {{ x = 105, y = 100, '
                           'z = 0 } })) return o.rule, o.b, o.away')
        self.assertEqual(out, ('fear', 'flee', 180))
        # Source trop lointaine, inconnue, ou combattant : à l'abri au foyer.
        self.assertEqual(self.decide('needs = { fear = 80 }, fearFrom = { x = 140, y = 100, z = 0 }')[:2],
                         ('fear', 'rest'))
        self.assertEqual(self.decide('needs = { fear = 80 }')[:2], ('fear', 'rest'))
        self.assertEqual(self.decide(f'needs = {{ fear = 80 }}, fearFrom = {{ x = 105, y = 100, z = 0 }}, '
                                     f'{fighter}')[:2], ('fear', 'flee'))   # LK06-T07 : tout rôle

    def test_decisions_read_the_registry_gauges(self):
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        gid = self.run_lua('local G = LivingKnox.Groups local g = assert(G.create({ type = "settlers", name = "Mill", '
                           'day = 1 })) assert(G.addMember(g.id, { role = "worker", day = 1 })) return g.id')
        self.assertEqual(self.run_lua(f'return DUMP({D}.needsOf("{gid}", "m-1"))'),
                         '{fatigue=20,fear=0,hunger=20,thirst=20}')   # valeurs de départ
        self.run_lua(f'{G}.state.data.groups["{gid}"].members["m-1"].vitals = '
                     '{ hunger = 10, thirst = 15, fatigue = 90, fear = 5, hour = 3 }')
        self.assertEqual(self.run_lua(f'return DUMP({D}.needsOf("{gid}", "m-1"))'),
                         '{fatigue=90,fear=5,hunger=10,thirst=15}')
        self.assertIsNone(self.ev(f'{N}.get("{gid}", "m-9")'))


class RegistryNeedsTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua(VITALS)

    def make(self, root=None):
        h = super().make(root)
        h.load('server', VITALS)
        return h

    def test_hourly_steps_equal_one_catch_up_after_a_stop(self):
        self.setup_world()
        start = self.run_lua(f'local d = {G}.copy({G}.state.data) return d')
        self.assertIsNotNone(start)
        self.every_hour(30)
        stepwise = self.ev('VITALS()')
        self.assertIn('grp-1/m-1=', stepwise)
        self.assertNotIn('@' + str(self.hour() - 1) + ' ', stepwise + ' ')
        first = self.h
        other = self.make()
        try:
            self.h = other
            self.setup_world()
            self.h.advance(30 * 60)                     # aucun EveryHours : 30 h manquées
            self.restart()
            self.h.fire(self.srv, 'OnInitGlobalModData', False)
            self.h.fire(self.srv, 'OnServerStarted')    # rattrapage au démarrage, même calcul
            self.assertEqual(self.ev('VITALS()'), stepwise)
        finally:
            self.h = first
            other.close()
        self.assertEqual(self.h.errors(self.srv), [])

    def test_gauges_are_saved_with_the_member_and_reset_when_malformed(self):
        self.setup_world()
        self.every_hour(5)
        before = self.ev('VITALS()')
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.ev('VITALS()'), before)              # relu tel quel, schéma 1 inchangé
        self.assertEqual(self.ev(f'{G}.state.data.schema'), 1)
        self.run_lua(f'{G}.state.data.groups["grp-1"].members["m-1"].vitals = {{ hunger = "x" }}')
        self.assertIsNone(self.ev(f'{G}.validGroup({G}.state.data.groups["grp-1"], "grp-1", {G}.state.data.nextId) '
                                  '== false or nil'))             # LK_Groups ne l'écarte pas : LK_Needs le répare
        self.every_hour(1)
        self.assertTrue(any('malformed gauges, reset' in line for line in self.lk()))
        self.assertIn(f'grp-1/m-1=20,20,20,0@{self.hour()}', self.ev('VITALS()'))

    def test_catch_up_is_bounded_per_member(self):
        self.setup_world()
        self.every_hour(1)
        self.run_lua('LivingKnox.Config.SIMULATION.MAX_CATCHUP_HOURS = 0')   # simulation figée : pas des besoins seul
        self.h.advance(100 * 60)
        self.run_lua(f'for k in pairs({N}.stats) do {N}.stats[k] = 0 end')
        self.h.fire(self.srv, 'EveryHours')
        self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite
        members = 10
        self.assertEqual(self.ev(f'{N}.stats.steps'), members * self.ev(f'{N}.CFG.CATCHUP_HOURS'))
        self.assertEqual(self.ev(f'{N}.stats.skipped'), members * (100 - 24))
        self.assertTrue(any('needs: 100 hour(s) missed, 24 applied' in line for line in self.lk()))
        self.assertTrue(all(f'@{self.hour()}' in part for part in self.ev('VITALS()').split(' ')))
        # Heure suivante : un pas par membre, rien de plus.
        self.run_lua('LivingKnox.Config.SIMULATION.MAX_CATCHUP_HOURS = 72')
        self.run_lua(f'for k in pairs({N}.stats) do {N}.stats[k] = 0 end')
        self.every_hour(1)
        self.assertEqual(self.ev(f'{N}.stats.steps'), members)

    def test_a_day_out_of_sight_follows_sleep_and_meals(self):
        self.setup_world()
        self.run_lua('LivingKnox.Config.SIMULATION.EXPEDITIONS.DEPART_CHANCE = 0')
        self.every_hour(72)
        for part in self.ev('VITALS()').split(' '):
            h, t, f, p = (int(x) for x in part.split('=')[1].split('@')[0].split(','))
            self.assertLess(t, 80, part)     # boit au foyer à l'envie
            self.assertLess(f, 90, part)     # dort la nuit ou à l'envie
            self.assertEqual(p, 0, part)     # aucune menace hors écran


class ClientAndStackTests(TD.MultiplayerDecisionTests):
    """Pile complète MP : aucune jauge chez les clients ; menace perçue -> peur -> fuite d'un non-combattant."""

    def test_clients_never_hold_gauges(self):
        gid = self.mk()
        self.all_members(gid, 4)
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Needs'))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Groups'))
        self.assertIsNotNone(self.ev(f'{N}.get("{gid}", "m-2")'))

    def test_perceived_threat_raises_fear_once_per_hour_and_makes_a_worker_flee(self):
        gid = self.mk()
        self.all_members(gid, 4)
        wx, wy = self.body_xy(gid, 'm-2')
        fear0 = self.ev(f'{N}.get("{gid}", "m-2").fear')
        # Zombie vu à 9 cases : au-delà de FLEE_DIST, regard et peur +10 une seule fois dans l'heure.
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "m-2"), {int(wx) + 9}, {int(wy)}, 9, 903)')
        self.all_members(gid, 4)
        self.all_members(gid, 4)
        self.assertEqual(self.ev(f'{N}.get("{gid}", "m-2").fear'), fear0 + 10)
        self.assertEqual(self.state(gid, 'm-2')[:2], ('threat', 'watch'))
        # Peur haute (registre vivant) : le même zombie à 9 cases met l'ouvrier à l'abri au foyer (LK06-T07 :
        # constante mauvaise ; hors du foyer il fuirait, banc pur).
        self.run_lua(f'{G}.state.data.groups["{gid}"].members["m-2"].vitals.fear = 75')
        self.all_members(gid, 4)
        rule, b, why = self.state(gid, 'm-2')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('fear 75 >= 70, hiding at home', why)
        self.assertEqual(self.run_lua(f'return DIRECTIVE("{gid}", "m-2").op'), 'face')
        # Le combattant voit le même zombie, peur moitié moindre, et ne fuit pas.
        fx, fy = self.body_xy(gid, 'm-1')
        f1 = self.ev(f'{N}.get("{gid}", "m-1").fear')
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "m-1"), {int(fx) + 9}, {int(fy)}, 9, 904)')
        self.all_members(gid, 4)
        self.assertEqual(self.ev(f'{N}.get("{gid}", "m-1").fear'), f1 + 5)
        self.assertEqual(self.state(gid, 'm-1')[:2], ('threat', 'watch'))
        # Activité observée gardée pour le pas horaire (mémoire du serveur seulement).
        self.assertEqual(self.ev(f'{N}.state.samples["{gid}/m-2"].n.watch') >= 1, True)
        self.assertEqual(self.h.errors('server'), [])


# Tests hérités de MultiplayerDecisionTests (déjà lancés par test_lk_decisions.py) : retirés de cette classe.
for _name in dir(TD.MultiplayerDecisionTests):
    if _name.startswith('test_') and _name not in ClientAndStackTests.__dict__:
        setattr(ClientAndStackTests, _name, None)


if __name__ == '__main__':
    unittest.main()
