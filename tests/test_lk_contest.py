"""Tests hors jeu de la contestation et du refus d'un membre incarné (E10-T03).

    python RadioSurvivor/tests/test_lk_contest.py

Trois bancs :
- logique pure de LK_Decisions (loyalté dérivée du moral et de l'ancienneté, règles de refus d'un ordre du moteur) ;
- pile complète des corps (banc MatBase de test_lk_materialize.py, type de test « deciders » de test_lk_decisions.py) :
  guet refusé à la notation horaire (un autre membre le prend, journal « refusal », réplique de gabarit), départ en
  expédition refusé (LK_Expeditions.teamOf), place de défense refusée (Decisions.judgeDefense), aucun appel au pont ;
- carnet (Simulation de test_carnet.py, vrai moteur Living Knox, vrai pont hors ligne) : décision collective du chef
  née d'une conversation, réaction des membres incarnés par le modèle (npc_member : accept, contest, refuse), quota
  par décision, journal du groupe et réplique entendue, membre parti entre-temps refusé.
La parole de proximité (LivingKnox.Speech) est remplacée par une doublure qui note les répliques : sa règle d'audition
est prouvée par test_lk_speech.py. Les doublures NE PROUVENT PAS l'API Java, seulement la logique.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import D, DECIDERS, DUMP, PureBase, FINISH_HOUR  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
import test_carnet as carnet  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402

TRANSLATE = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/Translate'

# Doublure de la parole de proximité (LK11-T04) : chaque réplique est notée, un auditeur fictif l'entend.
SPEECH_DOUBLE = r'''
SAID = {}
LivingKnox.Speech = { say = function(id, what, opts)
    SAID[#SAID + 1] = { id = id, key = type(what) == "table" and what.key or nil,
        text = type(what) == "string" and what or nil, name = opts and opts.name or nil }
    return { id = "sp-test-" .. #SAID, heard = { "listener" }, names = { "listener" } }
end }
'''


class LoyaltyAndRuleTests(PureBase):
    def test_loyalty_follows_morale_and_seniority(self):
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(60, 1, 4)'), ('loyal', 80))
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(60, 4, 4)'), ('loyal', 60))
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(40, 4, 4)'), ('steady', 40))
        # Moral très bas : le dernier arrivé chancelle, le plus ancien tient encore.
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(20, 4, 4)'), ('wavering', 20))
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(20, 1, 4)'), ('steady', 40))
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(5, 1, 1)'), ('wavering', 5))   # seul : aucun bonus
        self.assertEqual(self.run_lua(f'return {D}.loyaltyOf(nil, 1, 1)'), ('steady', 50))  # moral inconnu

    def test_refusal_rules_in_order(self):
        base = 'order = "guard", leader = false, health = 1, loyalty = "steady", score = 40, role = "fighter", ' \
               'allowed = { guard = true, fight = true }'

        def refusal(over=''):
            return self.run_lua(f'return {D}.refusalOf({{ {base}{", " + over if over else ""} }})')
        self.assertIsNone(refusal())
        self.assertEqual(refusal('health = 0.5'), ('wound', 'health 50% < 60%'))
        self.assertEqual(refusal('loyalty = "wavering", score = 12'), ('morale', 'loyalty 12 < 30'))
        self.assertEqual(refusal('health = 0.5, loyalty = "wavering"')[0], 'wound')   # blessure d'abord
        self.assertIsNone(refusal('health = 0.1, loyalty = "wavering", leader = true'))   # le chef ne refuse jamais
        self.assertEqual(refusal('order = "defend", playerLevel = "favorable"'),
                         ('attitude', 'player is favorable'))
        self.assertIsNone(refusal('order = "defend", playerLevel = "hostile"'))
        self.assertIsNone(refusal('order = "guard", playerLevel = "trusting"'))   # attitude : défense seulement
        self.assertEqual(refusal('order = "expedition"'), ('role', 'role fighter not fit'))
        self.assertIsNone(refusal('order = "expedition", allowed = { scavenge = true }'))
        self.assertIsNone(refusal('order = "defend", allowed = { chores = true }'))   # LK06-T07 : tout rôle défend
        self.assertEqual(refusal('order = "guard", allowed = { chores = true }'), ('role', 'role fighter not fit'))

    def test_translations_of_every_template_line(self):
        orders = lua_list(self.ev(f'{D}.ORDERS'))
        reasons = lua_list(self.ev(f'{D}.REFUSAL_REASONS'))
        prefix = self.ev(f'{D}.REFUSAL_KEY')
        for lang in ('EN', 'FR'):
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for order in orders:
                for reason in reasons:
                    key = f'{prefix}{order}_{reason}'
                    self.assertTrue(data.get(key), f'{lang} {key}')
                    self.assertLessEqual(len(data[key].encode('utf-8')), 200)


class EngineOrderRefusalTests(MatBase):
    """Pile complète, serveur dédié + deux clients : refus déterministes des ordres du moteur, sans pont."""

    mode = 'mp'
    # Chef ouvrier (m-1), deux combattants aptes au guet (m-2, m-3), un éclaireur (m-4).
    CREW = [('worker', 'cook', 'false'), ('fighter', 'gunner', 'false'), ('fighter', 'gunner', 'true'),
            ('scout', 'runner', 'nil')]

    def make(self, root=None):
        h = super().make(root)
        h.load(self.srv_name(), DECIDERS)
        h.load(self.srv_name(), DUMP)
        return h

    def srv_name(self):
        return 'solo' if self.mode == 'solo' else 'server'

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        code += 'assert(G.setLeader(g.id, "m-1", 1)) return g.id'
        gid = self.run_lua(code)
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() for k in pairs({D}.stats) do {D}.stats[k] = 0 end')
        self.h.load(self.srv_name(), SPEECH_DOUBLE)
        return gid

    def log(self, gid, kind):
        return lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                                     f'if e.kind == "{kind}" then out[#out + 1] = e.text end end return out'))

    def said(self):
        return [(e.id, e.key) for e in lua_list(self.ev('SAID'))]

    def score(self, gid):
        self.run_lua(f'{D}.scorePass({D}.currentHour(), "{gid}")')

    def test_guard_refused_by_low_morale_another_member_takes_it(self):
        gid = self.mk()
        self.score(gid)
        sentries = [m for m in ('m-2', 'm-3') if self.member(gid, m, 'duty') == 'sentry']
        self.assertEqual(len(sentries), 1)
        self.assertEqual(self.log(gid, 'refusal'), [], 'refusal with a good morale')
        # Moral très bas : le plus ancien combattant (m-2) reste « steady », le dernier arrivé (m-3) chancelle.
        self.run_lua(f'assert(LivingKnox.Groups.setMorale("{gid}", 20))')
        self.assertEqual(self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") return {D}.loyaltyOfMember(g, "m-2")'),
                         ('steady', 33))
        self.assertEqual(self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") return {D}.loyaltyOfMember(g, "m-3")'),
                         ('wavering', 27))
        self.run_lua(f'local g = LivingKnox.Groups.state.data.groups["{gid}"] g.members["m-2"].duty = "keeper" '
                     'g.members["m-3"].duty = "sentry"')
        # Relève de quart en quart : quand la rotation donne le guet à m-3, il refuse et m-2 le prend.
        for _ in range(6):
            self.h.advance(60 * 4)   # quart suivant : autre rotation
            self.score(gid)
            if self.log(gid, 'refusal'):
                break
        refusals = self.log(gid, 'refusal')
        self.assertEqual(len(refusals), 1, refusals)
        self.assertEqual(refusals[0], 'm-3 refused the guard order: morale (loyalty 27 < 30)')
        self.assertEqual(self.member(gid, 'm-2', 'duty'), 'sentry')
        self.assertNotEqual(self.member(gid, 'm-3', 'duty'), 'sentry')
        npc3 = self.ev(f'MEMBER_NPC("{gid}", "m-3")')
        self.assertEqual(self.said(), [(npc3, 'IGUI_LK_Refuse_guard_morale')])
        self.assertEqual(self.ev(f'{D}.refusalFor("{npc3}", "guard").reason'), 'morale')
        # Même instance d'ordre, refus encore valable : rejugé sans nouvelle annonce ; mémoire et appartenance gardées.
        self.score(gid)
        self.run_lua(f'{D}.scoreGroup("{gid}", LivingKnox.Groups.state.data.groups["{gid}"], {D}.currentHour())')
        self.run_lua(f'{D}.flushRefusals()')
        self.assertEqual(len(self.log(gid, 'refusal')), 1)
        self.assertEqual(len(self.said()), 1)
        self.assertEqual(self.ev(f'LivingKnox.Groups.findNpc("{npc3}")'), (gid, 'm-3'))
        self.assertEqual(self.member(gid, 'm-3', 'alive'), True)
        self.assertEqual(self.h.errors('server'), [])

    def test_refusal_judged_at_the_minute_then_at_the_full_hour_is_announced_once(self):
        # Essai en jeu du 2026-10-13 : refus jugé à la minute près (23 h 25), puis le guet rejugé par scoreGroup à
        # l'heure pleine (minute = heure x 60, plus tôt) : même refus, une seule annonce.
        gid = self.mk()
        self.run_lua(f'assert(LivingKnox.Groups.setMorale("{gid}", 20))')
        g = f'LivingKnox.Groups.state.data.groups["{gid}"]'
        hour = self.ev(f'{D}.currentHour()')
        minute = hour * 60 + 25
        self.assertEqual(self.run_lua(f'return ({D}.judgeOrder("{gid}", {g}, "m-3", {g}.members["m-3"], "guard", '
                                      f'"sentry", {minute}))'), 'morale')
        self.assertEqual(self.run_lua(f'return ({D}.judgeOrder("{gid}", {g}, "m-3", {g}.members["m-3"], "guard", '
                                      f'"sentry", {hour * 60}))'), 'morale')
        self.assertEqual(self.run_lua(f'return {D}.flushRefusals()'), 1)
        self.assertEqual(len(self.log(gid, 'refusal')), 1)
        # Au-delà de HOLD_MINUTES : rejugé et annoncé de nouveau.
        hold = self.ev(f'{D}.CFG and {D}.CFG.REFUSE and {D}.CFG.REFUSE.HOLD_MINUTES or 240')
        self.run_lua(f'{D}.judgeOrder("{gid}", {g}, "m-3", {g}.members["m-3"], "guard", "sentry", {minute + hold})')
        self.run_lua(f'{D}.flushRefusals()')
        self.assertEqual(len(self.log(gid, 'refusal')), 2)

    def test_leader_and_wounded_member(self):
        gid = self.mk()
        # Blessé (santé 50 % < 60 %) : refuse le guet quelle que soit sa loyauté ; le chef ne refuse jamais.
        self.run_lua(f'local g = LivingKnox.Groups.state.data.groups["{gid}"] g.members["m-2"].wound = 50 '
                     'g.members["m-3"].wound = 50 g.members["m-1"].wound = 90')
        g = f'LivingKnox.Groups.state.data.groups["{gid}"]'
        minute = self.ev(f'{D}.currentMinute()')
        self.assertEqual(self.run_lua(f'return {D}.judgeOrder("{gid}", {g}, "m-2", {g}.members["m-2"], "guard", '
                                      f'"sentry", {minute})'), ('wound', 'health 50% < 60%'))
        self.assertIsNone(self.run_lua(f'return {D}.judgeOrder("{gid}", {g}, "m-1", {g}.members["m-1"], "guard", '
                                       f'"sentry", {minute})'))
        self.assertEqual(self.run_lua(f'return {D}.flushRefusals()'), 1)
        self.assertEqual(self.log(gid, 'refusal'), ['m-2 refused the guard order: wound (health 50% < 60%)'])

    def test_defense_post_refused_member_leaves_the_post_and_fights_no_player(self):
        gid = self.mk()
        self.run_lua(f'assert(LivingKnox.Groups.setMorale("{gid}", 5))')
        g = f'LivingKnox.Groups.state.data.groups["{gid}"]'
        minute = self.ev(f'{D}.currentMinute()')
        ctx = ('{ defense = { id = "def-1", role = "post", key = "def:post 1,1,0" }, '
               'target = { kind = "player", u = "alice", d = 3 } }')
        out = self.run_lua(f'CTX1 = {ctx} local r = {D}.judgeDefense("{gid}", {g}, "m-3", {g}.members["m-3"], CTX1, '
                           f'{{}}, {minute}) return r, CTX1.defense == nil, CTX1.target == nil, CTX1.refused')
        self.assertEqual(out, ('morale', True, True, 'morale'))
        # Abri (rôle shelter) : pas un ordre de combat, jamais jugé ; zombie à portée : toujours combattu.
        out = self.run_lua(f'CTX2 = {{ defense = {{ id = "def-1", role = "shelter" }} }} '
                           f'return {D}.judgeDefense("{gid}", {g}, "m-3", {g}.members["m-3"], CTX2, {{}}, {minute}), '
                           'CTX2.defense ~= nil')
        self.assertEqual(out, (None, True))
        out = self.run_lua(f'CTX3 = {{ defense = {{ id = "def-1", role = "post" }}, target = {{ kind = "zombie", u = "z1" }} }} '
                           f'{D}.judgeDefense("{gid}", {g}, "m-3", {g}.members["m-3"], CTX3, {{}}, {minute}) '
                           'return CTX3.target ~= nil, CTX3.defense == nil')
        self.assertEqual(out, (True, True))
        self.run_lua(f'{D}.flushRefusals()')
        self.assertEqual(self.log(gid, 'refusal'), ['m-3 refused the defend order: morale (loyalty 12 < 30)'])
        self.assertEqual(self.said()[0][1], 'IGUI_LK_Refuse_defend_morale')

    def test_expedition_team_leaves_without_the_member_who_refuses(self):
        gid = self.mk()
        if self.ev('LivingKnox.Expeditions') is None:
            self.h.load(self.srv_name(), 'server/LivingKnox/LK_Expeditions.lua')
        g = f'LivingKnox.Groups.state.data.groups["{gid}"]'
        # Deux fourrageurs au foyer (m-2 éclaireur fictif apte, m-4 éclaireur) ; corps posés au foyer.
        self.run_lua(f'{g}.members["m-2"].role = "scout" {g}.members["m-2"].duty = "forager" '
                     f'{g}.members["m-4"].duty = "forager" '
                     f'for _, mid in ipairs({{ "m-2", "m-4" }}) do HARNESS.place(MAT_BODY("{gid}", mid), 110.5, 110.5, 0) end')
        self.run_lua('LivingKnox.Expeditions.CFG.MIN_HOME = 0 LivingKnox.Expeditions.CFG.TEAM_MAX = 3')
        team = lua_list(self.run_lua(f'return (LivingKnox.Expeditions.teamOf({g}, "{gid}", {{}}))'))
        self.assertEqual(team, ['m-2', 'm-4'])
        self.assertEqual(self.log(gid, 'refusal'), [])
        # Moral très bas : le dernier arrivé (m-4) chancelle et reste au foyer, m-2 (plus ancien) part.
        self.run_lua(f'assert(LivingKnox.Groups.setMorale("{gid}", 20))')
        team = lua_list(self.run_lua(f'return (LivingKnox.Expeditions.teamOf({g}, "{gid}", {{}}))'))
        self.assertEqual(team, ['m-2'])
        # Sans gid (lecture pure), aucun jugement.
        self.assertEqual(lua_list(self.run_lua(f'return (LivingKnox.Expeditions.teamOf({g}, nil, {{}}))')), ['m-2', 'm-4'])
        self.run_lua(f'{D}.flushRefusals()')
        self.assertEqual(self.log(gid, 'refusal'), ['m-4 refused the expedition order: morale (loyalty 20 < 30)'])
        self.assertEqual(self.said()[0][1], 'IGUI_LK_Refuse_expedition_morale')


class SoloEngineOrderRefusalTests(EngineOrderRefusalTests):
    mode = 'solo'

    def test_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKContest.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.contest", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.contest')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)


class MemberReactionTests(unittest.TestCase):
    """Carnet : décision collective du chef née d'une conversation, réactions des membres incarnés jouées par le
    modèle (pont hors ligne : RS_OFFLINE_INTENT=member:<choix>), quota par décision, journal et réplique."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-contest-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name, intent='', extra_members=0):
        sim = carnet.Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(carnet.LK_WORLD)
        for i in range(extra_members):
            sim.server.rt.execute(f'LK_EXTRA_{i} = lkNpc({20 + i}, LK_GROUP, "worker")')
        sim.server.rt.execute(SPEECH_DOUBLE)
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.G = self.rt.eval('LivingKnox.Groups')
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        self.process = carnet.start_bridge(sim.path, intent)
        return sim

    def journal(self, kind):
        return [e.text for e in carnet.lua_list(self.G.get(self.g.LK_GROUP).log) if e.kind == kind]

    def requests(self, kind):
        return [r for r in self.server.pending.values() if r.kind == kind]

    def offer_by_the_leader(self):
        sim = self.sim
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        sim.acquaint('alice')
        sim.command('alice', 'talk', channel='say', text="Vous avez besoin d'aide ?", language='FR')
        [req] = carnet.talk_requests(self.g)
        rid = req.id
        self.assertTrue(carnet.pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [sim.tick]),
                        'no leader reply')
        return sim.mission()

    def wait_members(self):
        self.assertTrue(carnet.pump(lambda: not self.requests('npc_member'), [self.sim.tick]), 'no member reply')

    def test_member_refuses_the_leader_decision_heard_and_logged(self):
        sim = self.world('refuse', 'member:refuse')
        m = self.offer_by_the_leader()
        self.assertEqual((m.state, m.supply.need), ('offer', 'food'))
        alice = sim.state().characters[sim.character('alice')].name
        fact = f'The leader asked {alice} to bring food for the group.'
        self.assertEqual(self.journal('decision'), [fact])
        # Une seule demande de réaction : le seul autre membre incarné (le compagnon), avec la décision et sa loyauté.
        [req] = self.requests('npc_member')
        mate = self.server.find(self.g.LK_MATE)
        out = carnet.convert(req)
        self.assertEqual((out['npc'], out['character']), (mate.id, 'group'))
        self.assertEqual(out['context']['decision']['text'], fact)
        self.assertIn(out['personality']['loyalty'], ('loyal', 'steady', 'wavering'))
        self.assertEqual(mate.personality.loyalty, 'current_group', 'derived loyalty stored on the fiche')
        self.assertEqual(out['offers'], {})
        system = protocol.prompt(out, [])[0]['content']
        self.assertIn('Never leave the group', system)
        self.assertIn('intent refuse', system)
        self.wait_members()
        self.assertEqual(self.journal('refusal'), [f'{mate.name} refused a group decision: {fact}'])
        said = [(e.id, e.text) for e in carnet.lua_list(self.g.SAID)]
        self.assertEqual(said, [(self.g.LK_MATE, 'Sans moi, je ne m\'en mêle pas.')])
        # Conséquence bornée : appartenance, offre et décision inchangées ; aucun changement de groupe.
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], self.g.LK_GROUP)
        self.assertEqual(m.state, 'offer')
        self.assertEqual(len(self.journal('decision')), 1)

    def test_accept_is_silent_and_contest_is_heard(self):
        self.world('accept', 'member:accept')
        self.offer_by_the_leader()
        self.wait_members()
        self.assertEqual((self.journal('refusal'), self.journal('contest')), ([], []))
        self.assertEqual(carnet.count(self.g.SAID), 0)
        self.process.terminate()
        self.process.communicate(timeout=10)
        self.process = None
        sim = self.world('contest', 'member:contest')
        self.offer_by_the_leader()
        self.wait_members()
        mate = self.server.find(self.g.LK_MATE)
        alice = sim.state().characters[sim.character('alice')].name
        self.assertEqual(self.journal('contest'),
                         [f'{mate.name} contested a group decision: The leader asked {alice} to bring food for the group.'])
        self.assertEqual(carnet.count(self.g.SAID), 1)

    def test_quota_per_decision_and_member_gone_before_the_reply(self):
        self.world('quota', 'member:refuse', extra_members=3)
        self.offer_by_the_leader()
        reqs = self.requests('npc_member')
        self.assertEqual(len(reqs), self.server.MEMBER_REACTIONS, 'quota of member reactions per decision')
        # Un membre quitte le groupe avant la réponse (départ) : sa réaction est refusée, rien n'est écrit pour lui.
        first = carnet.convert(reqs[0])
        gone = self.g.RS_CarnetServer.store.data.npcs[first['npc']].incarnation
        gid, mid = self.G.findNpc(gone)
        self.rt.execute(f'assert(LivingKnox.Groups.removeMember("{gid}", "{mid}"))')
        self.wait_members()
        self.assertEqual(len(self.journal('refusal')), self.server.MEMBER_REACTIONS - 1)

    def test_bridge_contract_for_member_replies(self):
        req = {'kind': 'npc_member', 'id': 'r-1-npc-2', 'world': 'w', 'run': 'r', 'npc': 'npc-2', 'order': 1,
               'revision': 1, 'language': 'EN', 'character': 'group', 'personality': {'loyalty': 'wavering'},
               'offers': {}, 'text': 'Your leader decided: x', 'context': {'decision': {'text': 'x'}}}
        for intent in ('accept', 'contest', 'refuse', 'none'):
            self.assertEqual(protocol.bounded_reply(req, {'text': 'No.', 'intent': intent})['intent'], intent)
        with self.assertRaises(ValueError):
            protocol.bounded_reply(req, {'text': 'No.', 'intent': 'offer', 'offer': 'x'})
        with self.assertRaises(ValueError):
            protocol.bounded_reply(dict(req, kind='npc_talk'), {'text': 'No.', 'intent': 'refuse'})
        long = protocol.bounded_reply(req, {'text': 'word ' * 100, 'intent': 'contest'})['text']
        self.assertLessEqual(len(long.encode('utf-8')), 200)
        reply, why = protocol.model_reply(req, '{"text": "Hm.", "intent": "leave"}')
        self.assertEqual((reply['intent'], why), ('none', 'intent'))
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('your loyalty is wavering', system)
        self.assertIn('Speak in English', system)


if __name__ == '__main__':
    unittest.main(verbosity=2)
