"""Tests hors jeu du registre des sortes de chantier de la fortification (LK16-T02, chantier C1) :
server/LivingKnox/LK_Fortify.lua (Fortify.registerKind) et un fichier par sorte sous server/LivingKnox/Fortify/.

    python RadioSurvivor/tests/test_lk_fortify_kinds.py

Banc : pile du rattrapage hors écran (test_lk_fortify_offscreen.py : maison HOUSE 105..115, foyer 110,110, deux
fenêtres, porte d'entrée sud, caisse avec un marteau, 8 planches et une boîte de clous ; ouvrier m-2 « builder »).
Une sorte factice « spike » est inscrite par CE banc seul (aucune ligne de LK_Fortify.lua ne la nomme) : elle doit
être planifiée, gardée au registre en forme compacte, relue, avancée hors écran et posée à l'arrivée d'un joueur.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_barricade import F  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_fortify_offscreen import OffscreenStack  # noqa: E402

# Sorte factice : un chantier de deux étapes (une pierre chacune, sans outil) à une case à l'est du foyer, tier
# « outer », planifié après le pourtour ; pose hors écran notée dans SPIKE_APPLIED.
SPIKE = r'''
SPIKE_APPLIED = {}
local F = LivingKnox.Fortify
F.registerKind({ id = "spike", code = "s", order = 90, unit = "spike(s)",
    work = function(site, c) return c.GESTURE, c.PLANK_MINUTES, function() return nil, "not in this test" end end,
    plan = function(survey)
        local x, y = survey.home.x + 1, survey.home.y
        return { { id = F.siteId("spike", x, y, 0, true), kind = "spike", tier = "outer", x = x, y = y, z = 0,
            north = true, opp = false, inside = { x = x, y = y }, outside = { x = x, y = y - 1 }, have = 0,
            steps = 2, done = false, tools = {}, materials = { F.req({ "Base.Stone" }, 2) }, time = 400 } }
    end,
    offscreen = {
        types = { "Base.Stone" },
        nextStage = function(e, c) return { F.req({ "Base.Stone" }, 1) }, nil, c.PLANK_MINUTES end,
        remaining = function(e) return { F.req({ "Base.Stone" }, e.s - e.h) } end,
        apply = function(gid, op, mark)
            SPIKE_APPLIED[#SPIKE_APPLIED + 1] = op.id .. " " .. op.a .. ">" .. op.b
            return "placed", nil, op.b - op.a
        end,
    },
})
'''


class KindRegistryTests(OffscreenStack):
    mode = 'solo'

    def test_a_kind_added_by_one_file_is_planned_saved_read_and_applied_offscreen(self):
        self.run_lua(SPIKE)
        gid = self.prepare(extra={'Base.Stone': 2})
        sid = 'spike:111,110,0N'
        # Planifiée : après les barricades et le pourtour (aucune autre sorte ne change de place).
        plan = self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        ids = [s.id for s in plan.sites.values()]
        self.assertEqual(ids[-1], sid)
        self.assertEqual(ids[:2], ['barricade:112,105,0N', 'barricade:105,110,0W'])
        # Sauvegardée en forme compacte (code « s », tier « o », dx 1, dy 0, z 0, face N, côté 0, 2 visées, 0 faite).
        raw = self.ev(f'LivingKnox.Groups.get("{gid}").fort')
        self.assertIn('so1,0,0N020', raw.sites.split(';'))
        # Relue : la vue de travail rend la sorte et l'identifiant recalculé.
        fort = self.ev(f'FORT("{gid}")')
        spike = [s for s in lua_list(fort.sites) if s.k == 'spike']
        self.assertEqual([(s.id, s.t, s.s, s.h) for s in spike], [(sid, 'outer', 2, 0)])
        # Avancée hors écran : deux étapes, deux pierres prises dans la référence du stock.
        self.off(gid)
        ops = [o for o in lua_list(self.ev(f'FORT("{gid}").pend.ops')) if o.k == 'spike']
        self.assertEqual([(o.id, o.a, o.b) for o in ops], [(sid, 0, 2)])
        self.assertIn(';' + str(ops[0].u) + ':s1,0,0N002', ';' + self.ev(f'LivingKnox.Groups.get("{gid}").fort').ops)
        # Appliquée à l'arrivée : la pose de la sorte reçoit son écart, une seule fois.
        self.assertEqual(self.arrive(), 1)
        self.assertEqual(lua_list(self.ev('SPIKE_APPLIED')), [f'{sid} 0>2'])
        for _ in range(2):
            self.ev(f'{F}.scan("minute")')
        self.assertEqual(len(lua_list(self.ev('SPIKE_APPLIED'))), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_a_duplicate_code_is_refused_with_a_clear_error(self):
        ok, err = self.run_lua('return pcall(LivingKnox.Fortify.registerKind, { id = "trench", code = "b", order = 5, '
                               'unit = "x", work = function() end, offscreen = { nextStage = function() end, '
                               'remaining = function() end, apply = function() end } })')
        self.assertFalse(ok)
        self.assertIn('code "b" already used by barricade', err)
        self.assertIsNone(self.ev(f'{F}.KINDS.trench'))

    def test_the_four_kinds_come_from_their_files(self):
        ids = lua_list(self.run_lua(f'local out = {{}} for i, k in ipairs({F}.kindList()) do out[i] = k.id end '
                                    'return out'))
        self.assertEqual(ids, ['barricade', 'wall', 'palisade', 'repair'])
        self.assertEqual(sorted(k for k, v in self.ev(f'{F}.OFF_KINDS').items() if v), ['barricade', 'palisade',
                                                                                         'wall'])


if __name__ == '__main__':
    unittest.main(verbosity=1)
