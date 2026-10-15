"""Tests hors jeu du journal de récit des groupes (LK10-T02) : LK_Journal.lua, API.journal, détail admin.

    python RadioSurvivor/tests/test_lk_journal.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Doublures : getWorld, horloge du banc
(getWorldAgeHours, 0 à 7 h le premier jour), fichiers getFileWriter / getFileReader du banc, getText / getTextOrNull
lus dans les traductions EN du mod (ou absents : serveur dédié). EveryHours est déclenché par le test. Vérité de
terrain indépendante du journal : enveloppes de Simulation.tryDepart / resolveExpedition (départs et retours tirés),
membres morts du registre, faits publiés. Simulation, PAS validation en jeu.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
TRANSLATE = LUA / 'shared' / 'Translate'
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/LK_Appearance.lua', 'shared/LivingKnox/LK_Identity.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = ('server/LivingKnox/LK_Server.lua', 'server/LivingKnox/LK_Stories.lua', 'server/LivingKnox/LK_API.lua',
          'server/LivingKnox/LK_Admin.lua')

WORLD = r'''
getWorld = function()
    return { getWorld = function() return 'rstest_journal' end, getGameMode = function() return 'Multiplayer' end }
end
'''

J, G, SIM = 'LivingKnox.Journal', 'LivingKnox.Groups', 'LivingKnox.Simulation'
CANON = ('require("RadioSurvivor/RS_Codec").hexBytes(require("RadioSurvivor/RS_Codec").encodeBytes('
         'LivingKnox.Groups.state.data))')

# Vérité de terrain : départs et retours d'expédition abstraite tirés par la simulation (enveloppes posées après le
# chargement, appelées par Simulation.simulateHour par la table).
RECORD = r'''
TRUTH = { departures = {}, returns = {} }
local Sim = LivingKnox.Simulation
local depart, resolve = Sim.tryDepart, Sim.resolveExpedition
Sim.tryDepart = function(g, hour, ...)
    local text = depart(g, hour, ...)
    if text ~= nil then
        TRUTH.departures[#TRUTH.departures + 1] = { group = g.id, hour = hour, team = #g.expedition.team,
            place = g.expedition.place }
    end
    return text
end
Sim.resolveExpedition = function(g, gid, hour, ...)
    local res = resolve(g, gid, hour, ...)
    TRUTH.returns[#TRUTH.returns + 1] = { group = gid, back = res.back, lost = #res.lost }
    return res
end
'''


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def translations(lang):
    return json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))


def en_text_double():
    """getText / getTextOrNull du banc : traductions EN du mod, %N remplacés (règle de Translator)."""
    table = translations('EN')
    rows = ',\n'.join(f'[{json.dumps(k)}] = {json.dumps(v)}' for k, v in table.items() if k.startswith('IGUI_LK_'))
    return ('local T = {\n' + rows + '\n}\n' + r'''
local function fmt(text, ...)
    local args = { ... }
    return (string.gsub(text, '%%(%d)', function(d) return tostring(args[tonumber(d)] or '') end))
end
getTextOrNull = function(key, ...) local t = T[key] if t == nil then return nil end return fmt(t, ...) end
getText = function(key, ...) local t = T[key] if t == nil then return key end return fmt(t, ...) end
''')


# LK13-T09 : les passes horaires partent une par image (LK_Simulation.defer) ; ce banc les vide aussitôt.
FINISH_HOUR = 'if LivingKnox.Simulation and LivingKnox.Simulation.finishHour then LivingKnox.Simulation.finishHour() end'

class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = self.make()

    def tearDown(self):
        self.h.close()

    def make(self, root=None):
        h = Harness(mode=self.mode, root=root)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            h.load(m, WORLD)
            for path in SHARED + SERVER:
                h.load(m, path)
        return h

    def ev(self, code):
        return self.h.eval(self.srv, code)

    def run_lua(self, code):
        return self.h.load(self.srv, code)

    def entries(self, gid):
        j = self.ev(f'{G}.state.data.groups["{gid}"].journal')
        return lua_list(j.e) if j is not None else []

    def kinds(self, gid):
        return [e.kind for e in self.entries(gid)]

    def args(self, e):
        return lua_list(e.args)

    def restart(self):
        self.h.load(self.srv, 'if LivingKnox.Groups and LivingKnox.Groups.flush then LivingKnox.Groups.flush() end')  # arrêt propre : écriture différée faite (LK13-T06)
        root, age = self.h.root, self.h.age_minutes
        self.h._tmp = None
        self.h.close()
        self.h = self.make(root=root)
        self.h.age_minutes = age
        self.h._push_clock()
        self.addCleanup(shutil.rmtree, root, True)

    def world(self, record=True):
        """Registre neuf : deux colonies avec foyer, un groupe de pillards, simulation démarrée."""
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        if record:
            self.run_lua(RECORD)
        return self.run_lua(f'''
            local G = {G}
            local a = G.create({{ type = "settlers", name = "Mill Folk", day = 1,
                home = {{ x = 10637, y = 9412, z = 0 }} }}).id
            local b = G.create({{ type = "settlers", name = "Riverside", day = 1,
                home = {{ x = 11200, y = 9100, z = 0 }} }}).id
            local c = G.create({{ type = "raiders", name = "Crows", day = 1 }}).id
            for _, role in ipairs({{ "worker", "fighter", "medic", "scout", "worker", "deputy", "scout" }}) do
                G.addMember(a, {{ role = role }})
            end
            for _, role in ipairs({{ "worker", "scout", "fighter", "worker", "medic" }}) do
                G.addMember(b, {{ role = role }})
            end
            for _, role in ipairs({{ "fighter", "fighter", "breaker", "scout" }}) do G.addMember(c, {{ role = role }}) end
            G.setLeader(a, "m-1", 1)
            G.setLeader(b, "m-1", 1)
            G.setLeader(c, "m-1", 1)
            return a, b, c
        ''')

    def every_hour(self, hours):
        for _ in range(hours):
            self.h.advance(60)
            self.h.fire(self.srv, 'EveryHours')
            self.h.load(self.srv, FINISH_HOUR)   # LK13-T09 : pas horaire étalé, file vidée tout de suite


class StructureTests(Base):
    def test_founding_settling_and_leader(self):
        a, b, c = self.world(record=False)
        self.assertEqual(self.kinds(a), ['settled', 'leader'])
        self.assertEqual(self.kinds(c), ['founded', 'leader'])
        lead = self.entries(a)[1]
        self.assertEqual((lead.member, self.args(lead)), ('m-1', ['worker']))
        e = self.entries(a)[0]
        self.assertEqual((e.n, e.day, e.hour), (1, 1, 9))    # 9 h le premier jour (horloge du banc)
        self.assertEqual(self.ev(f'{G}.state.data.groups["{a}"].journal.n'), 3)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_death_departure_and_no_duplicate_from_joined(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'''
            local G = {G}
            assert(G.markDead("{a}", "m-3", 2))
            assert(G.removeMember("{a}", "m-5", 3))
            assert(G.setLeader("{a}", nil, 3))
        ''')
        ks = self.kinds(a)
        self.assertEqual(ks, ['settled', 'leader', 'died', 'left', 'leaderless'])
        died, left = self.entries(a)[2], self.entries(a)[3]
        self.assertEqual((died.member, self.args(died), died.day), ('m-3', ['medic'], 2))
        self.assertEqual((left.member, self.args(left), left.day), ('m-5', ['worker'], 3))   # rôle par memberLeft
        self.assertNotIn('joined', ks)

    def test_killed_by_a_player_without_keeping_the_account(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'''
            LivingKnox.publish("memberDied", {{ group = "{a}", member = "m-2", npc = "lk-9", day = 2,
                offscreen = false, killer = "bob", cause = "firearm" }})
            assert(LivingKnox.Groups.markDead("{a}", "m-2", 2))
            assert(LivingKnox.Groups.markDead("{a}", "m-4", 2))
        ''')
        es = self.entries(a)
        self.assertEqual([(e.kind, e.member) for e in es[-2:]], [('killed', 'm-2'), ('died', 'm-4')])
        self.assertNotIn('bob', self.ev(CANON.replace('LivingKnox.Groups.state.data',
                                                      f'LivingKnox.Groups.state.data.groups["{a}"].journal')))

    def test_offscreen_events_departure_recruit_clash_dispersal_relief(self):
        a, b, c = self.world(record=False)
        self.run_lua(f'''
            local G = {G}
            G.update(function(data)
                local g, t = data.groups["{a}"], data.groups["{c}"]
                -- Départ hors écran (même ordre que LK_Simulation.eventDeparture) : departure puis left.
                G.appendLog(g, "departure", "m-7 scout: low morale", 4)
                G.applyLeave(g, "m-7", 4)
                -- Recrue (forme de logRecruit) et combat (forme d'eventClash).
                local mid = G.applyMember(g, {{ role = "medic" }}, 4)
                G.appendLog(g, "recruit", "wanderer: " .. mid .. " medic", 4)
                G.appendLog(t, "clash", "attack {a} lost: 1 lost, 0 wounded, food +0", 5)
                G.appendLog(g, "clash", "defend {c} won: 0 lost, 1 wounded, food +0", 5)
                return true
            end)
        ''')
        self.assertEqual(self.kinds(a)[2:], ['deserted', 'recruit', 'defenseWon'])
        dep = self.entries(a)[2]
        self.assertEqual((dep.member, self.args(dep)), ('m-7', ['scout']))
        self.assertEqual(self.args(self.entries(a)[3]), ['medic'])
        self.assertEqual(self.args(self.entries(a)[4]), ['Crows'])
        self.assertEqual(self.kinds(c)[-1], 'attackLost')
        self.assertEqual(self.args(self.entries(c)[-1]), ['Mill Folk'])
        # Dispersion (LK_Population.markGone : départs « dispersed » puis gone) : aucune entrée « left ».
        self.run_lua(f'''
            local G = {G}
            G.update(function(data)
                local g = data.groups["{b}"]
                for _, mid in ipairs({{ "m-1", "m-2", "m-3", "m-4", "m-5" }}) do G.applyLeave(g, mid, 6, "dispersed") end
                G.applyGone(g, "dispersed", 6, 130, 160)
                return true
            end)
        ''')
        self.assertEqual(self.kinds(b)[-1], 'dispersed')
        self.assertNotIn('left', self.kinds(b))
        # Relève (forme de LK_Population.reliefStep) : noms des deux groupes.
        self.run_lua(f'''
            local G = {G}
            G.update(function(data)
                local o = data.groups["{b}"]
                local g = G.applyCreate(data, {{ type = "settlers", name = "New Dawn", day = 8,
                    home = {{ x = 11200, y = 9100, z = 0 }} }})
                o.gone.relief = g.id
                G.appendLog(o, "relieved", g.id, 8)
                G.appendLog(g, "relief", "{b}", 8)
                NEWID = g.id
                return true
            end)
        ''')
        new = self.ev('NEWID')
        self.assertEqual(self.kinds(new), ['settled', 'relief'])
        self.assertEqual(self.args(self.entries(new)[1]), ['Riverside'])
        self.assertEqual(self.args(self.entries(b)[-1]), ['New Dawn'])
        self.assertEqual(self.h.errors(self.srv), [])

    def test_physical_expedition_and_admin_move(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'''
            local G = {G}
            G.update(function(data)
                local g = data.groups["{a}"]
                g.trips = {{ v = 1, n = 3, seen = {{}}, cur = {{ n = 3, phase = "out", team = {{ "m-4", "m-7" }} }} }}
                G.appendLog(g, "expedition", "trip 3 to house (40 squares): m-4 m-7 for food 2", 3)
                G.appendLog(g, "trip", "trip 3 offscreen (search): m-4 m-7, back in 2 h", 3)
                G.appendLog(g, "trip", "trip 3 back offscreen: 2 back, 1 item(s) found", 3)
                G.appendLog(g, "return", "trip 3 back from house: 2 back, food +1", 3)
                G.appendLog(g, "expedition", "trip 4 to shop (20 squares): m-4 for food 1", 4)
                G.appendLog(g, "return", "trip 4: no one came back from shop", 4)
                G.appendLog(g, "return", "trip 5: record lost, 1 back", 4)
                G.appendLog(g, "admin", "home 10637,9412,0 -> 10700,9400,0 by boss", 5)
                G.appendLog(g, "admin", "relief forced by boss", 5)
                return true
            end)
        ''')
        es = self.entries(a)[2:]
        self.assertEqual([(e.kind, self.args(e)) for e in es],
                         [('trip', [2]), ('returned', [2]), ('trip', [2]), ('noneBack', []), ('returned', [1]),
                          ('moved', [])])
        # Formes lues dans le texte technique : présentes dans le code qui les écrit (couplage vérifié).
        ex = (LUA / 'server/LivingKnox/LK_Expeditions.lua').read_text(encoding='utf-8')
        sim = (LUA / 'server/LivingKnox/LK_Simulation.lua').read_text(encoding='utf-8')
        adm = (LUA / 'server/LivingKnox/LK_Admin.lua').read_text(encoding='utf-8')
        self.assertIn('"trip %d to %s (%d squares)', ex)
        self.assertIn('%d back, %s%s%s', ex)
        self.assertIn('no one came back from %s', ex)
        self.assertIn('record lost, " .. back .. " back', ex)
        self.assertIn('": " .. survivors .. " back, "', sim)
        self.assertIn('": unknown place, " .. #present .. " back"', sim)
        self.assertIn('"attack " .. tid .. " " .. outcomeA .. ": "', sim)
        self.assertIn('"defend " .. gid .. " " .. outcomeD .. ": "', sim)
        self.assertIn('cut(mid .. " " .. g.members[mid].role .. ": low morale")', sim)
        self.assertIn('cut(origin .. ": " .. mid .. " " .. role)', sim)
        self.assertIn('"home " .. oldText', adm)


class SimulatedDaysTests(Base):
    def tune(self):
        """Réglages du banc : expéditions fréquentes et risquées, recrues, journal non borné ici."""
        self.run_lua(f'''
            local S = LivingKnox.Config.SIMULATION
            S.EXPEDITIONS.NEED_TRIGGER, S.EXPEDITIONS.DEPART_CHANCE, S.EXPEDITIONS.DEATH_SHARE = 90, 0.5, 0.6
            for _, p in ipairs(S.EXPEDITIONS.PLACES) do p.risk = 0.5 p.recruit = 0.3 end
            S.EVENTS.RECRUIT.CHANCE, S.EVENTS.RECRUIT.FOOD_MIN, S.EVENTS.RECRUIT.MORALE_MIN = 0.3, 0, 0
            {J}.SIZE = 1000
        ''')

    def setup_sim(self):
        ids = self.world()
        self.tune()
        self.run_lua(f'local G = {G} for _, gid in ipairs(G.list()) do G.setNeed(gid, "food", 20) end')
        self.assertEqual(self.ev(f'{SIM}.step()'), 0)
        return ids

    def test_journal_matches_simulated_facts_over_several_days(self):
        ids = self.setup_sim()
        self.every_hour(24 * 6)
        deps = [d for d in lua_list(self.ev('TRUTH.departures'))]
        rets = [r for r in lua_list(self.ev('TRUTH.returns'))]
        self.assertGreater(len(deps), 2, 'bench too quiet: no expedition')
        self.assertGreater(sum(r.lost for r in rets), 0, 'bench too quiet: no loss')
        for gid in ids:
            es = self.entries(gid)
            # Départs : un par départ tiré, même équipe, même lieu, heure du jour du départ ((k + 6) % 24).
            mine = [d for d in deps if d.group == gid]
            exp = [e for e in es if e.kind == 'expedition']
            self.assertEqual([(self.args(e)[0], self.args(e)[1], e.hour) for e in exp],
                             [(d.team, d.place, (d.hour + 6) % 24) for d in mine])
            # Retours : un par retour tiré, survivants comptés ; personne = noneBack.
            back = [r for r in rets if r.group == gid]
            got = [(e.kind, self.args(e)[0] if e.kind == 'returned' else 0) for e in es
                   if e.kind in ('returned', 'noneBack')]
            self.assertEqual(got, [('returned', r.back) if r.back > 0 else ('noneBack', 0) for r in back])
            # Morts : une entrée par membre mort du registre, avec son rôle.
            members = self.ev(f'{G}.state.data.groups["{gid}"].members')
            dead = sorted(k for k, m in members.items() if not m.alive)
            died = sorted(e.member for e in es if e.kind in ('died', 'killed'))
            self.assertEqual(died, dead)
            for e in es:
                if e.kind == 'died':
                    self.assertEqual(self.args(e), [members[e.member].role])
            # Recrues : une entrée par membre recruté (membres au-delà de la population de départ, encore là).
            recruits = [e.member for e in es if e.kind == 'recruit']
            self.assertEqual(len(recruits), len(set(recruits)))
            # Ordre et dates : numéros croissants, jours croissants, heures dans 0..23.
            ns = [e.n for e in es]
            self.assertEqual(ns, sorted(ns))
            self.assertEqual(len(ns), len(set(ns)))
            days = [e.day for e in es]
            self.assertEqual(days, sorted(days))
            self.assertTrue(all(0 <= e.hour <= 23 for e in es))
        self.assertEqual(self.h.errors(self.srv), [])

    def test_catch_up_writes_the_same_journal_as_hour_by_hour(self):
        self.setup_sim()
        self.every_hour(30)
        journals = {gid: [(e.n, e.day, e.hour, e.kind) for e in self.entries(gid)] for gid in self.ev(f'{G}.list()').values()}
        other = self.make()
        try:
            self.h, first = other, self.h
            self.setup_sim()
            self.h.advance(30 * 60)
            self.restart()
            self.tune()
            self.h.fire(self.srv, 'OnInitGlobalModData', False)
            self.h.fire(self.srv, 'OnServerStarted')
            for gid, want in journals.items():
                self.assertEqual([(e.n, e.day, e.hour, e.kind) for e in self.entries(gid)], want)
        finally:
            first.close()

    def test_journal_survives_a_restart(self):
        a, _, _ = self.setup_sim()
        self.every_hour(12)
        before = [(e.n, e.kind) for e in self.entries(a)]
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual([(e.n, e.kind) for e in self.entries(a)], before)


class BoundsTests(Base):
    def test_size_numbering_and_argument_bounds(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'''
            local G, J = {G}, {J}
            G.update(function(data)
                local g = data.groups["{a}"]
                for i = 1, 100 do J.add(g, "returned", {{ i }}, 2) end
                J.add(g, "relief", {{ string.rep("x", 300), 2, 3, 4, 5, 6 }}, 3)
                OK_UNKNOWN = J.add(g, "secret_plan", {{}}, 3)
                return true
            end)
        ''')
        es = self.entries(a)
        self.assertEqual(len(es), self.ev(f'{J}.SIZE'))
        self.assertEqual(self.ev(f'{J}.SIZE'), 40)
        self.assertEqual(es[-1].n, 103)
        self.assertEqual(es[0].n, 64)
        self.assertEqual([len(self.args(es[-1])), len(self.args(es[-1])[0])], [4, 64])
        self.assertIsNone(self.ev('OK_UNKNOWN'))
        self.assertTrue(self.ev(f'{J}.valid({G}.state.data.groups["{a}"].journal)'))

    def test_malformed_journal_is_reset_once_and_numbering_kept(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'''
            local G = {G}
            local j = G.state.data.groups["{a}"].journal
            j.e[1].kind = "nonsense"
            G.save()
            assert(G.markDead("{a}", "m-2", 2))
            G.state.data.groups["{a}"].journal = "garbage"
            assert(G.markDead("{a}", "m-3", 2))
        ''')
        es = self.entries(a)
        self.assertEqual([(e.n, e.kind, e.member) for e in es], [(1, 'died', 'm-3')])
        warns = [line for line in self.h.logs(self.srv) if 'journal: malformed story journal' in line]
        self.assertEqual(len(warns), 1)
        j = self.ev(f'{G}.state.data.groups["{a}"].journal')
        self.assertEqual(j.n, 2)
        # Le premier remis à neuf a gardé sa numérotation (n = 3, entrée 3) : contrôlé ici sur un journal lisible.
        self.run_lua(f'''
            local g = {G}.state.data.groups["{a}"]
            g.journal = {{ v = 1, n = 9, e = {{ {{ n = 12, day = 1, kind = "died", args = {{}} }} }} }}
            assert({G}.markDead("{a}", "m-4", 2))
        ''')
        self.assertEqual([(e.n, e.member) for e in self.entries(a)], [(9, 'm-4')])

    def test_broken_listener_does_not_break_the_group_write(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'{J}.onLog = function() error("boom") end')
        self.assertTrue(self.ev(f'{G}.markDead("{a}", "m-2", 2)'))
        self.assertFalse(self.ev(f'{G}.get("{a}").members["m-2"].alive'))
        self.assertTrue(any('journal: died entry of' in line and 'boom' in line for line in self.h.logs(self.srv)))
        self.h.errors(self.srv)   # erreur journalisée, pas levée


class EncounterTests(Base):
    def test_one_entry_per_group_and_day_written_after_the_transaction(self):
        a, b, _ = self.world(record=False)
        for player in ('bob', 'alice', 'bob'):
            self.run_lua(f'LivingKnox.publish("encounterStarted", {{ group = "{a}", npc = "lk-1", player = "{player}", '
                         'level = "wary", n = 1 })')
        self.run_lua(f'LivingKnox.publish("encounterStarted", {{ group = "{b}", player = "carl", level = "hostile" }})')
        self.assertNotIn('encounter', self.kinds(a))      # pas encore : file
        self.h.tick(1)                                    # OnTickEvenPaused
        e = self.entries(a)[-1]
        self.assertEqual((e.kind, self.args(e), e.day), ('encounter', [3], 1))
        self.assertEqual(self.kinds(b)[-1], 'encounter')
        self.h.advance(24 * 60)
        self.run_lua(f'LivingKnox.publish("encounterStarted", {{ group = "{a}", player = "bob", level = "wary" }})')
        self.h.tick(1)
        self.assertEqual([self.args(x)[0] for x in self.entries(a) if x.kind == 'encounter'], [3, 1])
        dump = self.ev(CANON)
        for secret in ('bob', 'alice', 'carl'):
            self.assertNotIn(secret.encode().hex(), dump)
        # Écrit sur disque : relu après redémarrage.
        self.restart()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual([self.args(x)[0] for x in self.entries(a) if x.kind == 'encounter'], [3, 1])


class ReadingTests(Base):
    def test_api_journal_public_view_since_and_text(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'assert({G}.markDead("{a}", "m-3", 2))')
        out = self.ev(f'LivingKnox.API.journal("{a}")')
        es = lua_list(out.entries)
        self.assertEqual(out.next, 4)
        self.assertEqual([e.kind for e in es], ['settled', 'leader', 'died'])
        died = es[2]
        self.assertEqual(died.key, 'IGUI_LK_Journal_died')
        arg = lua_list(died.args)[0]
        self.assertEqual((arg.text, arg.key), ('medic', 'IGUI_LK_Journal_Role_medic'))
        self.assertIsNone(died.text)                      # serveur dédié : pas de traductions du mod
        self.assertEqual([e.n for e in lua_list(self.ev(f'LivingKnox.API.journal("{a}", 2).entries'))], [3])
        self.assertEqual(self.ev('LivingKnox.API.journal("grp-99")'), (None, 'unknown group grp-99'))
        # Machine qui résout les traductions (solo, hôte) : texte composé, rôle traduit.
        self.run_lua(en_text_double())
        es = lua_list(self.ev(f'LivingKnox.API.journal("{a}").entries'))
        self.assertEqual(es[2].text, 'Death of a member (medic).')
        self.assertEqual(es[0].text, 'The group came together and settled in its home.')
        # Aucune coordonnée du foyer dans la vue.
        self.run_lua(f'''
            local function d(v) if type(v) ~= "table" then return tostring(v) end local s = ""
                for k, x in pairs(v) do s = s .. tostring(k) .. "=" .. d(x) .. ";" end return s end
            FLAT = d(LivingKnox.API.journal("{a}"))
        ''')
        flat = self.ev('FLAT')
        for coord in ('10637', '9412'):
            self.assertNotIn(coord, flat)

    def test_admin_detail_carries_the_journal_and_the_window_composes_it(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'assert({G}.markDead("{a}", "m-3", 2))')
        self.run_lua(f'''
            LivingKnox.Admin.isAllowed = function() return true end
            REPLY = LivingKnox.Admin.request(nil, {{ op = "group", gid = "{a}", n = 1 }})
        ''')
        reply = self.ev('REPLY')
        self.assertTrue(reply.ok)
        journal = lua_list(reply.group.journal)
        self.assertEqual([e.kind for e in journal], ['settled', 'leader', 'died'])
        self.h.load('A', en_text_double())
        self.h.load('A', 'client/LivingKnox/LK_AdminView.lua')
        e = journal[2]
        args = ', '.join(f'{{ text = {json.dumps(a.text)}, key = {json.dumps(a.key) if a.key else "nil"} }}'
                         for a in lua_list(e.args))
        self.h.load('A', f'E = {{ day = {e.day}, hour = {e.hour}, key = {json.dumps(e.key)}, args = {{ {args} }} }}')
        text = self.h.eval('A', 'LivingKnox.AdminView.journalWhen(E) .. "  " .. LivingKnox.AdminView.journalText(E)')
        self.assertEqual(text, 'Day 2, 09:00  Death of a member (medic).')

    def test_every_kind_role_and_place_is_translated_in_en_and_fr(self):
        kinds = self.ev(f'{J}.KINDS')
        roles = lua_list(self.ev('LivingKnox.Config.GROUP_ROLES')) + [self.ev(f'{J}.UNKNOWN_ROLE')]
        places = [p.id for p in lua_list(self.ev('LivingKnox.Config.SIMULATION.EXPEDITIONS.PLACES'))]
        for lang in ('EN', 'FR'):
            table = translations(lang)
            for kind, spec in kinds.items():
                key = 'IGUI_LK_Journal_' + kind
                self.assertIn(key, table, f'{lang} {key}')
                wanted = {f'%{i}' for i in range(1, len(lua_list(spec)) + 1)}
                self.assertEqual(set(re.findall(r'%\d', table[key])), wanted, f'{lang} {key}')
            for role in roles:
                self.assertIn('IGUI_LK_Journal_Role_' + role, table, lang)
            for place in places:
                self.assertIn('IGUI_LK_Journal_Place_' + place, table, lang)
            for key in ('IGUI_LK_Admin_Journal', 'IGUI_LK_Admin_JournalWhen'):
                self.assertIn(key, table, lang)

    def test_lua_code_is_ascii(self):
        code = (LUA / 'server/LivingKnox/LK_Journal.lua').read_text(encoding='utf-8')
        for line in code.splitlines():
            stripped = line.split('--', 1)[0]
            self.assertTrue(all(ord(ch) < 128 for ch in stripped), line)


class SoloTests(Base):
    mode = 'solo'

    def test_solo_journal_is_written_and_read(self):
        a, _, _ = self.world(record=False)
        self.run_lua(f'assert({G}.markDead("{a}", "m-3", 2))')
        self.assertEqual(self.kinds(a), ['settled', 'leader', 'died'])
        self.assertEqual(len(lua_list(self.ev(f'LivingKnox.API.journal("{a}").entries'))), 3)


class ClientTests(Base):
    def test_mp_client_has_no_journal_module(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Journal'))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Groups'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
