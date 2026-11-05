"""Banc hors jeu de tools/plan.py : tableau de bord en tête de chaque plan, rangement des plans terminés dans
docs/annexes/plans-termines/ avec correction des liens, ordre de travail du README du plan (demande de l'utilisateur
du 2026-11-05)."""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('plan_under_test', ROOT / 'tools' / 'plan.py')


def task(tid, title, state, target='hors jeu', deps='—', proof='—', reste='—'):
    done = {'hors jeu': 3, 'solo': 4, 'MP': 5}
    rank = {'à faire': 0, 'en cours': 1, 'codé': 2, 'testé hors jeu': 3, 'testé solo': 4, 'testé MP': 5}
    box = 'x' if rank.get(state, -1) >= done[target] else ' '
    return (f'- [{box}] **{tid}** — {title}\n  - État : `{state}`\n  - Cible : `{target}`\n  - Dépend de : {deps}\n'
            f'  - Preuve : {proof}\n  - Reste : {reste}\n')


class PlanToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.plan = root / 'docs' / 'annexes' / 'plans'
        self.done = root / 'docs' / 'annexes' / 'plans-termines'
        self.plan.mkdir(parents=True)
        self.m = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.m)
        self.m.ROOT, self.m.PLAN, self.m.DONE = root, self.plan, self.done
        self.m.SUIVI, self.m.README = self.plan / 'SUIVI.md', self.plan / 'README.md'
        (self.plan / 'README.md').write_text('# Méthode\n\n- **Ordre de travail** : `E02-T02 E LK E02`\n',
                                             encoding='utf-8')
        (self.plan / 'E01-fini.md').write_text(
            '# E01 — Étape finie\n\nVoir [E02](E02-ouverte.md) et [doc](../../README.md).\n\n## Tâches\n\n'
            + task('E01-T01', 'Fait', 'testé hors jeu', proof='banc') + '\n'
            + task('E01-T02', 'Retirée', 'abandonné', reste='doublon'), encoding='utf-8')
        (self.plan / 'E02-ouverte.md').write_text(
            '# E02 — Étape ouverte\n\nSuite de [E01](E01-fini.md).\n\n## Tâches\n\n'
            + task('E02-T01', 'Premier', 'à faire') + '\n' + task('E02-T02', 'Deuxième', 'à faire'),
            encoding='utf-8')
        (self.plan / 'E03-radio.md').write_text('# E03 — Radio\n\n## Tâches\n\n' + task('E03-T01', 'Radio', 'à faire'),
                                                encoding='utf-8')
        (self.plan / 'LK01-pnj.md').write_text('# LK01 — PNJ\n\n## Tâches\n\n' + task('LK01-T01', 'PNJ', 'à faire'),
                                               encoding='utf-8')
        (root / 'README.md').write_text('[E01](docs/annexes/plans/E01-fini.md)\n', encoding='utf-8')
        code = root / 'Contents' / 'x.lua'
        code.parent.mkdir()
        code.write_text('-- decision (docs/annexes/plans/E01-fini.md)\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def run_suivi(self):
        steps, tasks = self.m.load()
        self.assertEqual(self.m.check(steps, tasks), [])
        return self.m.suivi(steps, tasks)

    def test_board_written_under_the_title_and_stable(self):
        self.run_suivi()
        text = (self.plan / 'E02-ouverte.md').read_text(encoding='utf-8')
        lines = text.splitlines()
        self.assertEqual(lines[0], '# E02 — Étape ouverte')
        self.assertEqual(lines[2], self.m.BOARD_START)
        self.assertIn('**Avancement.** à faire — 0 / 2 tâche(s) terminée(s).', text)
        self.assertIn('| ☐ | E02-T01 | Premier | `à faire` | hors jeu | — |', text)
        self.run_suivi()
        self.assertEqual((self.plan / 'E02-ouverte.md').read_text(encoding='utf-8'), text, 'board not stable')
        steps, tasks = self.m.load()
        self.assertEqual(len(tasks), 6, 'board rows read as tasks')

    def test_finished_plan_moved_with_its_links_fixed(self):
        _, moves = self.run_suivi()
        self.assertEqual([p.name for p in moves.values()], ['E01-fini.md'])
        moved = self.done / 'E01-fini.md'
        self.assertTrue(moved.is_file())
        self.assertFalse((self.plan / 'E01-fini.md').exists())
        text = moved.read_text(encoding='utf-8')
        self.assertIn('[E02](../plans/E02-ouverte.md)', text)
        self.assertIn('[doc](../../README.md)', text)
        self.assertIn('✕ | E01-T02', text)
        self.assertIn('[E01](../plans-termines/E01-fini.md)', (self.plan / 'E02-ouverte.md').read_text(encoding='utf-8'))
        root = self.m.ROOT
        self.assertIn('docs/annexes/plans-termines/E01-fini.md', (root / 'README.md').read_text(encoding='utf-8'))
        self.assertIn('docs/annexes/plans-termines/E01-fini.md', (root / 'Contents' / 'x.lua').read_text(encoding='utf-8'))
        suivi = (self.plan / 'SUIVI.md').read_text(encoding='utf-8')
        self.assertIn('[E01](../plans-termines/E01-fini.md)', suivi)
        # Reopened: back to plans/, links fixed again.
        moved.write_text(moved.read_text(encoding='utf-8').replace(
            '- [x] **E01-T01** — Fait\n  - État : `testé hors jeu`', '- [ ] **E01-T01** — Fait\n  - État : `codé`'),
            encoding='utf-8')
        self.run_suivi()
        self.assertTrue((self.plan / 'E01-fini.md').is_file())
        self.assertIn('[E01](E01-fini.md)', (self.plan / 'E02-ouverte.md').read_text(encoding='utf-8'))
        self.assertIn('docs/annexes/plans/E01-fini.md', (root / 'Contents' / 'x.lua').read_text(encoding='utf-8'))

    def test_work_order_tokens(self):
        steps, tasks = self.m.load()
        ids = [t.id for t in self.m.ordered(tasks)]
        self.assertEqual(ids, ['E02-T02', 'E01-T01', 'E01-T02', 'E03-T01', 'LK01-T01', 'E02-T01'])
        nxt, _ = self.m.next_task(tasks)
        self.assertEqual(nxt.id, 'E02-T02')

    def test_unknown_order_token_is_an_error(self):
        (self.plan / 'README.md').write_text("- **Ordre de travail** : `E02-T02 n'importe`\n", encoding='utf-8')
        steps, tasks = self.m.load()
        self.assertTrue(any('jeton' in e for e in self.m.check(steps, tasks)))


if __name__ == '__main__':
    unittest.main(verbosity=1)
