"""Panneau de relation du carnet (E09-T07).

    python tests/test_relation_panel.py

Banc lupa (Lua 5.1, `next` retiré comme dans Kahlua) : vrai serveur du carnet (`RS_Carnet_Server.lua`), vrais
`RS_Relations.lua` et `RS_Factions.lua` (doublure fidèle de la faction vanilla de `tests/test_factions.py`), moteur
Living Knox réel (registres, `LK_Hostility`, API, fournisseur `RS_LivingKnox.lua`), vrai client du carnet
(`RS_Notebook.lua` avec les doublures ISUI de `NOTEBOOK_UI`) et table anglaise réelle du mod pour le rendu. Les changements
personnels passent par l'API d'E09-T04 (`Relations.offer` puis `Relations.apply`, faits réels enregistrés par
`LK_Hostility.record`). Doublures seulement : ne prouve ni l'API Java ni le réseau ni l'affichage en jeu.
"""
from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, LK_WORLD, NOTEBOOK_UI, ROOT, convert
from test_factions import FACTION_DOUBLE

LEVELS = ['hostile', 'wary', 'cautious', 'favorable', 'trusting']
EN = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/Translate/EN/IG_UI.json'
FR = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/Translate/FR/IG_UI.json'

# Translator double faithful to Translator.getText / getTextOrNull (42.21, base load-warnings.md): the English table of
# the mod, nil for an unknown key (getTextOrNull only), the raw key for getText; a %N read with fewer arguments logged.
TRANSLATOR = r"""
MISSING_ARGS = {}
local function format(key, text, n, ...)
    local args = { ... }
    for i in string.gmatch(text, '%%(%d)') do
        if tonumber(i) > n then MISSING_ARGS[#MISSING_ARGS + 1] = key; return text end
    end
    return (string.gsub(text, '%%(%d)', function(i) return tostring(args[tonumber(i)]) end))
end
getTextOrNull = function(key, ...)
    local text = EN_TEXTS[key]
    if text == nil then return nil end
    return format(key, text, select('#', ...), ...)
end
getText = function(key, ...) return format(key, EN_TEXTS[key] or key, select('#', ...), ...) end
"""


def shifted(level, gap):
    return LEVELS[max(0, min(4, LEVELS.index(level) + gap))]


class RelationPanelTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-relation-panel-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name, clients=('alice', 'bob', 'carol'), faction=True):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(FACTION_DOUBLE)
        sim.server.rt.execute(LK_WORLD)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        for c in clients:
            sim.add_client(c)
        self.server = self.g.RS_CarnetServer
        self.R = self.rt.eval("require('RadioSurvivor/RS_Relations')")
        self.F = self.rt.eval("require('RadioSurvivor/RS_Factions')")
        self.H = self.rt.eval('LivingKnox.Hostility')
        for npc in (self.g.LK_LEADER, self.g.LK_MATE, self.g.LK_LONER):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        if faction:
            # Faction "North": alice owner, bob member; carol has no faction (personal team).
            self.rt.execute('NORTH = FACTION_CREATE("North", "alice", {"bob"})')
        self.poll()
        return sim

    def poll(self):
        self.sim.clock.offset += 2100
        self.sim.tick()

    def cid(self, name):
        return self.sim.character(name)

    def fiche(self, npc):
        return self.server.ensure(npc)

    def fact(self, name, fact):
        res = self.H.record(self.g.LK_GROUP, self.cid(name), fact, self.rt.table_from({'witnessed': True}))
        self.assertIsNotNone(res, fact)

    def change(self, name, npc, fact, direction):
        """Personal change of this NPC toward name, citing the real fact `fact` (E09-T04 API)."""
        context, binding = self.R.offer(self.fiche(npc), self.cid(name))
        ids = [f['id'] for f in convert(context)['facts'].values() if f['fact'] == fact]
        self.assertTrue(ids, f'{fact} not offered to {npc}')
        view, key = self.R.apply(self.fiche(npc), self.cid(name), binding, direction, ids[-1])
        self.assertIsNotNone(view, key)

    def contacts(self, name):
        self.sim.command(name, 'snapshot')
        snap = self.sim.clients[name].g.RS_CarnetClient.snapshot
        return {c.id: convert(c) for c in snap.contacts.values()}

    def relation(self, name, npc):
        return self.contacts(name)[self.fiche(npc).id]['relation']

    def group_level(self, name):
        return self.rt.eval('LivingKnox.API').attitude(self.g.LK_GROUP, self.cid(name)).level

    def select_all(self, name):
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.sim.command(name, 'select', incarnation=npc)

    @staticmethod
    def facts(rel):
        return [(f['fact'], f['nature'], f['source']) for f in (rel.get('facts') or {}).values()]

    def lines(self, name, rel):
        """Lines of the panel drawn by the real notebook client with the English table of the mod, for the contact
        whose fiche id is rel in the last snapshot of name (None: no relation at all)."""
        c = self.sim.clients[name]
        if not getattr(c, 'rel_ui', False):
            c.rt.execute(NOTEBOOK_UI)
            c.g.EN_TEXTS = c.rt.table_from(json.loads(EN.read_text(encoding='utf-8-sig')))
            c.rt.execute(TRANSLATOR)
            c.load('client/RS_Carnet_Client.lua')
            c.rel_ui = True
        if rel is None:
            out = c.g.RS_UI_Notebook.relationLines(None)
        else:
            [row] = [r for r in c.g.RS_CarnetClient.snapshot.contacts.values() if r.id == rel]
            out = c.g.RS_UI_Notebook.relationLines(row.relation)
        self.assertEqual(list(c.g.MISSING_ARGS.values()), [], 'a text read without its arguments')
        return [out[i] for i in range(1, len(out) + 1)]

    def assert_clean(self, lines):
        text = ' | '.join(lines)
        self.assertNotIn('IGUI_', text, 'raw translation key shown')
        self.assertNotIn('%', text)
        self.assertIsNone(re.search(r'\d', text), 'number shown in the relation panel: ' + text)

    def test_two_members_of_a_group_different_relations_per_character(self):
        """« Deux membres d'une faction, relations différentes » : le chef et un membre d'un même groupe ne voient pas
        alice pareil ; bob, de la même faction de joueurs qu'alice, a sa propre projection ; aucun fait de l'un n'apparaît
        chez l'autre ; l'accord du groupe avec la faction est montré aux deux avec sa portée."""
        self.world('two-members')
        leader, mate, gid = self.g.LK_LEADER, self.g.LK_MATE, self.g.LK_GROUP
        for name in ('alice', 'bob'):
            self.select_all(name)
        self.fact('alice', 'gift')
        self.fact('bob', 'hit')
        self.change('alice', leader, 'gift', 'up')   # the leader thinks better of alice
        self.change('bob', mate, 'hit', 'down')      # the mate thinks worse of bob
        team = self.F.idOf(self.g.PLAYERS['alice'])
        self.assertEqual(team, self.F.idOf(self.g.PLAYERS['bob']), 'alice and bob in the same faction')
        ok, why, _ = self.F.conclude(self.g.PLAYERS['alice'], gid, 'truce',
                                     self.rt.table_from({'team': team, 'revision': 0}), self.rt.table_from({}))
        self.assertTrue(ok, why)

        ga, gb = self.group_level('alice'), self.group_level('bob')
        a_leader, a_mate = self.relation('alice', leader), self.relation('alice', mate)
        b_leader, b_mate = self.relation('bob', leader), self.relation('bob', mate)
        # Two members of the same group, different relations toward the same character.
        self.assertEqual((a_leader['level'], a_leader['group'], a_leader['trend']), (shifted(ga, 1), ga, 'up'))
        self.assertEqual((a_mate['level'], a_mate['group']), (ga, ga))
        self.assertEqual((b_mate['level'], b_mate['group'], b_mate['trend']), (shifted(gb, -1), gb, 'down'))
        self.assertEqual(b_leader['level'], gb)
        self.assertNotEqual(a_leader['level'], a_mate['level'])
        self.assertNotEqual(b_leader['level'], b_mate['level'])
        # Explaining facts: identifiers + game day, own facts only (no fact of the other player leaks).
        self.assertEqual(self.facts(a_leader), [('gift', 'good', 'group'), ('gift', 'good', 'personal')])
        self.assertEqual(self.facts(a_mate), [('gift', 'good', 'group')])
        self.assertEqual(self.facts(b_mate), [('hit', 'bad', 'group'), ('hit', 'bad', 'personal')])
        self.assertEqual(self.facts(b_leader), [('hit', 'bad', 'group')])
        for rel in (a_leader, a_mate, b_leader, b_mate):
            self.assertEqual(sorted(rel), ['agreements', 'facts', 'group', 'level', 'today', 'trend'])
            for f in rel['facts'].values():
                self.assertEqual(sorted(f), ['day', 'fact', 'nature', 'source'])
                self.assertIsInstance(f['day'], (int, float))
            # One agreement: the truce of the group with the faction, its explicit scope.
            [a] = list(rel['agreements'].values())
            self.assertEqual((a['kind'], a['state'], a['scope']), ('truce', 'pending',
                             {'group': 'all_members', 'team': 'current_members'}))
        for name, rels in (('alice', (a_leader, a_mate)), ('bob', (b_leader, b_mate))):
            text = json.dumps(rels)
            for secret in ('att:', 'obs:', 'mis:', 'gap', 'value', 'revision', 'agr-', 'grp-', 'fac-'):
                self.assertNotIn(secret, text, f'{secret} sent to {name}')
        self.assertNotIn('hit', json.dumps([a_leader, a_mate]), 'fact of bob shown to alice')
        self.assertNotIn('gift', json.dumps([b_leader, b_mate]), 'fact of alice shown to bob')
        # Every contact of the snapshot of alice: nothing about bob (name or character id).
        everything = json.dumps(self.contacts('alice'))
        self.assertNotIn(self.cid('bob'), everything)
        # Drawn by the real notebook client, English table: translated, no raw key, no number.
        lines = self.lines('alice', self.fiche(leader).id)
        self.assert_clean(lines)
        self.assertEqual(lines[0], f'Attitude toward you: {shifted(ga, 1)} (improving).')
        self.assertIn(f'Their group as a whole: {ga}.', lines)
        self.assertIn('Truce (concluded, not applied yet): covers every member of their group and the current '
                      'members of your faction.', lines)
        self.assertIn('- Today, you gave them something (changed their own opinion of you).', lines)
        mate_lines = self.lines('alice', self.fiche(mate).id)
        self.assert_clean(mate_lines)
        self.assertFalse(any('Their group as a whole' in s for s in mate_lines), 'group line although equal')
        bob_lines = self.lines('bob', self.fiche(mate).id)
        self.assert_clean(bob_lines)
        self.assertIn('- Today, you struck one of them (changed their own opinion of you).', bob_lines)

    def test_notebook_page_shows_the_panel(self):
        """La fiche du contact (onglet Contacts) contient le panneau, à l'encre, sans les anciennes clés de confiance."""
        self.world('page', clients=('alice',), faction=False)
        self.sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.lines('alice', None)  # loads the notebook client with the English table
        c = self.sim.clients['alice']
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.selectedId = self.fiche(self.g.LK_LEADER).id
        window.showDetail(window)
        text = window.detail.text
        self.assertTrue(text.startswith('<RGB:'))
        self.assertIn('What they think of you:', text)
        self.assertIn(f'Attitude toward you: {self.group_level("alice")} (steady).', text)
        self.assertIn('No agreement with your side.', text)
        self.assertIn('No remembered fact explains it yet.', text)
        self.assertNotIn('IGUI_', text)
        self.assertNotIn('Personal trust', text)

    def test_personal_team_and_suspension(self):
        """Joueur sans faction (équipe personnelle) : portée « vous » ; incident ouvert : protection suspendue."""
        self.world('personal', clients=('carol',), faction=False)
        leader, gid = self.g.LK_LEADER, self.g.LK_GROUP
        self.sim.command('carol', 'select', incarnation=leader)
        team = self.F.idOf(self.g.PLAYERS['carol'])
        ok, why, _ = self.F.conclude(self.g.PLAYERS['carol'], gid, 'alliance',
                                     self.rt.table_from({'team': team, 'revision': 0}), self.rt.table_from({}))
        self.assertTrue(ok, why)
        rel = self.relation('carol', leader)
        [a] = list(rel['agreements'].values())
        self.assertEqual((a['kind'], a['scope']['team']), ('alliance', 'you'))
        self.assertNotIn('suspended', rel)
        # Incident: carol hit a member while covered (E09-T06 source memberHit): protection suspended for her.
        inc, how = self.F.incidentFact(gid, self.cid('carol'), 'hit', self.rt.table_from({'npc': self.g.LK_MATE}))
        self.assertEqual(how, 'opened')
        self.assertTrue(self.F.isIncidentAuthor(gid, self.cid('carol')))
        rel = self.relation('carol', leader)
        self.assertTrue(rel['suspended'])
        lines = self.lines('carol', self.fiche(leader).id)
        self.assert_clean(lines)
        self.assertIn('Alliance (concluded, not applied yet): covers every member of their group and you.', lines)
        self.assertTrue(any(s.startswith('You attacked one of them') for s in lines), lines)

    def test_unknown_without_group_basis(self):
        """PNJ sans groupe ni changement personnel : libellé « inconnu » propre, aucun fait, aucun accord."""
        self.world('loner', clients=('alice',), faction=False)
        loner = self.g.LK_LONER
        self.sim.command('alice', 'select', incarnation=loner)
        rel = self.relation('alice', loner)
        self.assertNotIn('level', rel)
        self.assertNotIn('group', rel)
        lines = self.lines('alice', self.fiche(loner).id)
        self.assert_clean(lines)
        self.assertEqual(lines[0], 'Attitude toward you: unknown (nothing known yet).')
        self.assertEqual(self.lines('alice', None), ['Attitude toward you: unknown (nothing known yet).'])

    def test_unknown_identifiers_fall_back_to_generic_words(self):
        """Identifiants inconnus (serveur plus récent) : mots génériques, jamais une clé brute."""
        self.world('fallback', clients=('alice',), faction=False)
        self.lines('alice', None)
        c = self.sim.clients['alice']
        rel = c.rt.table_from({
            'level': 'cautious', 'trend': 'sideways', 'group': 'cautious', 'today': 9,
            'facts': c.rt.table_from([c.rt.table_from({'fact': 'sang_a_song', 'nature': 'good', 'source': 'group',
                                                       'day': 1})]),
            'agreements': c.rt.table_from([c.rt.table_from({'kind': 'pact', 'state': 'odd',
                                                            'scope': c.rt.table_from({'group': 'x', 'team': 'y'})})]),
        })
        out = c.g.RS_UI_Notebook.relationLines(rel)
        lines = [out[i] for i in range(1, len(out) + 1)]
        self.assert_clean(lines)
        self.assertEqual(lines[0], 'Attitude toward you: cautious (steady).')
        self.assertIn('Agreement (status unknown): covers their side and your side.', lines)
        self.assertIn('- Some time ago, something you did for them.', lines)

    def test_french_table_has_every_key(self):
        en = json.loads(EN.read_text(encoding='utf-8-sig'))
        fr = json.loads(FR.read_text(encoding='utf-8-sig'))
        keys = [k for k in en if k.startswith('IGUI_RS_Rel')]
        self.assertGreater(len(keys), 40)
        self.assertEqual(sorted(keys), sorted(k for k in fr if k.startswith('IGUI_RS_Rel')))
        for k in keys:
            self.assertEqual(re.findall(r'%\d', en[k]), re.findall(r'%\d', fr[k]), k)
        for obsolete in ('IGUI_RS_TrustScope', 'IGUI_RS_TrustUnassessed', 'IGUI_RS_NoAgreements'):
            self.assertNotIn(obsolete, en)


if __name__ == '__main__':
    unittest.main()
