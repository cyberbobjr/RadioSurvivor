"""Suivi du plan d'implémentation RadioSurvivor.

    python RadioSurvivor/tools/plan.py check    # contrôle les fichiers d'étape (CI locale)
    python RadioSurvivor/tools/plan.py suivi    # régénère docs/plan/SUIVI.md
    python RadioSurvivor/tools/plan.py next     # prochaine tâche à traiter
    python RadioSurvivor/tools/plan.py show E01-T02

Les fichiers d'étape (docs/plan/<préfixe><NN>-*.md : préfixe E pour la radio et le carnet, LK pour le moteur de PNJ Living Knox) sont la seule source des états ; SUIVI.md en est une vue générée.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'docs' / 'plan'
SUIVI = PLAN / 'SUIVI.md'

# Rang de progression. "à décider" bloque tant que l'utilisateur n'a pas tranché.
RANK = {'à décider': 0, 'à faire': 0, 'en cours': 1, 'codé': 2, 'testé hors jeu': 3, 'testé solo': 4, 'testé MP': 5}
SPECIAL = {'bloqué', 'abandonné'}
TARGET = {'hors jeu': 3, 'solo': 4, 'MP': 5}

TASK = re.compile(r'^- \[( |x)\] \*\*([A-Z]{1,3}\d{2}-T\d{2})\*\* — (.+?)\s*$')
FIELD = re.compile(r'^  - ([^:]+?) : (.*)$')
STEP = re.compile(r'^# ([A-Z]{1,3}\d{2}) — (.+?)\s*$')
COMMIT = re.compile(r'`([0-9a-f]{7,40})`')


class Task:
    def __init__(self, step, tid, title, checked, line, path):
        self.step, self.id, self.title, self.checked, self.line, self.path = step, tid, title, checked, line, path
        self.fields: dict[str, str] = {}

    @property
    def state(self):
        return self.fields.get('État', '').strip('` ')

    @property
    def target(self):
        return self.fields.get('Cible', '').strip('` ')

    @property
    def deps(self):
        raw = self.fields.get('Dépend de', '—')
        return [] if raw.strip() in ('—', '-', '') else [d.strip() for d in raw.split(',')]

    @property
    def proof(self):
        return self.fields.get('Preuve', '—').strip()

    def done(self):
        return self.state in RANK and self.target in TARGET and RANK[self.state] >= TARGET[self.target]

    def usable(self):
        """Une dépendance est utilisable dès qu'elle est testée hors jeu (les tests en jeu se regroupent)."""
        return self.state == 'abandonné' or RANK.get(self.state, -1) >= RANK['testé hors jeu']


def load():
    steps, tasks = [], []
    for path in sorted(p for p in PLAN.glob('*.md') if re.match(r'[A-Z]{1,3}\d{2}-', p.name)):
        lines = path.read_text(encoding='utf-8').splitlines()
        m = STEP.match(lines[0]) if lines else None
        if not m:
            raise SystemExit(f'{path.name}: première ligne attendue « # E00 — Titre » (préfixe d\'une à trois majuscules)')
        step = m.group(1)
        steps.append((step, m.group(2), path))
        current = None
        for n, line in enumerate(lines, 1):
            t = TASK.match(line)
            if t:
                current = Task(step, t.group(2), t.group(3), t.group(1) == 'x', n, path)
                tasks.append(current)
                continue
            f = FIELD.match(line)
            if current and f:
                current.fields[f.group(1).strip()] = f.group(2).strip()
            elif not line.startswith('  '):
                current = None
    return steps, tasks


def check(steps, tasks):
    errors = []
    seen = {}
    ids = {t.id for t in tasks}
    for t in tasks:
        where = f'{t.path.name}:{t.line} {t.id}'
        if t.id in seen:
            errors.append(f'{where}: identifiant déjà utilisé ({seen[t.id]})')
        seen[t.id] = where
        if not t.id.startswith(t.step + '-'):
            errors.append(f'{where}: préfixe différent de son étape {t.step}')
        if t.state not in RANK and t.state not in SPECIAL:
            errors.append(f'{where}: état inconnu « {t.state} »')
        if t.target not in TARGET:
            errors.append(f'{where}: cible inconnue « {t.target} » (hors jeu, solo, MP)')
        if t.checked != t.done():
            errors.append(f'{where}: case {"cochée" if t.checked else "vide"} incohérente avec état « {t.state} » / cible « {t.target} »')
        for d in t.deps:
            # « Projet:E01-T04 » désigne une tâche d'un autre projet : non vérifiée ici.
            if ':' not in d and d not in ids:
                errors.append(f'{where}: dépendance inconnue {d}')
        if RANK.get(t.state, 0) >= RANK['testé hors jeu'] and t.proof in ('—', ''):
            errors.append(f'{where}: état « {t.state} » sans preuve')
        if t.state in SPECIAL and t.fields.get('Reste', '—') in ('—', ''):
            errors.append(f'{where}: état « {t.state} » sans raison dans « Reste »')
        for commit in COMMIT.findall(t.proof):
            ok = subprocess.run(['git', '-C', str(ROOT), 'cat-file', '-e', commit + '^{commit}'],
                                capture_output=True).returncode == 0
            if not ok:
                errors.append(f'{where}: commit {commit} introuvable')
    if sum(1 for t in tasks if t.state == 'en cours') > 1:
        errors.append('plus d\'une tâche « en cours » : terminer ou remettre « à faire » avant d\'en commencer une autre')
    return errors


def step_state(step_tasks):
    live = [t for t in step_tasks if t.state != 'abandonné']
    if not live:
        return 'vide'
    if all(t.done() for t in live):
        return 'terminée'
    if any(RANK.get(t.state, 0) > 0 for t in live):
        return 'en cours'
    if any(t.state == 'à décider' for t in live):
        return 'décisions à prendre'
    return 'à faire'


def suivi(steps, tasks):
    out = ['# Suivi du plan RadioSurvivor', '',
           '> Fichier **généré** par `python RadioSurvivor/tools/plan.py suivi` à partir des fichiers d\'étape.',
           '> Ne pas le modifier à la main : changer l\'état dans le fichier de l\'étape puis régénérer.', '',
           '## Étapes', '', '| Étape | Titre | État | Tâches terminées |', '|---|---|---|---|']
    for step, title, path in steps:
        st = [t for t in tasks if t.step == step]
        done = sum(1 for t in st if t.done())
        out.append(f'| [{step}]({path.name}) | {title} | {step_state(st)} | {done} / {len(st)} |')
    out += ['', '## Tâches', '', '| | Tâche | Titre | État | Cible | Preuve |', '|---|---|---|---|---|---|']
    for t in tasks:
        box = '☑' if t.done() else '☐'
        out.append(f'| {box} | [{t.id}]({t.path.name}#L{t.line}) | {t.title} | `{t.state}` | {t.target} | {t.proof} |')
    SUIVI.write_text('\n'.join(out) + '\n', encoding='utf-8')
    return SUIVI


def next_task(tasks):
    by_id = {t.id: t for t in tasks}
    for t in tasks:
        if t.state == 'en cours':
            return t, 'reprendre la tâche en cours'
    for t in tasks:
        if t.done() or t.state in SPECIAL or RANK.get(t.state, 0) >= RANK['testé hors jeu']:
            continue
        if all(by_id[d].usable() for d in t.deps if d in by_id):  # dépendances externes : à vérifier à la main
            if t.state == 'à décider':
                return t, 'DÉCISION REQUISE : poser les questions de la tâche à l\'utilisateur, ne rien coder'
            return t, 'à traiter'
    pending = [t for t in tasks if not t.done() and t.state not in SPECIAL]
    if pending:
        return pending[0], 'reste seulement des validations en jeu (protocole à faire exécuter par l\'utilisateur)'
    return None, 'plan terminé'


def show(task):
    lines = task.path.read_text(encoding='utf-8').splitlines()
    end = task.line
    while end < len(lines) and (lines[end].startswith('  ') or lines[end].strip() == '' and end + 1 < len(lines)
                                and lines[end + 1].startswith('  ')):
        end += 1
    return '\n'.join(lines[task.line - 1:end])


def main(argv):
    command = argv[1] if len(argv) > 1 else 'check'
    steps, tasks = load()
    if command == 'check':
        errors = check(steps, tasks)
        for e in errors:
            print('ERREUR', e)
        print(f'{len(steps)} étapes, {len(tasks)} tâches, {len(errors)} erreur(s)')
        return 1 if errors else 0
    if command == 'suivi':
        errors = check(steps, tasks)
        if errors:
            for e in errors:
                print('ERREUR', e)
            return 1
        print('écrit', suivi(steps, tasks))
        return 0
    if command == 'next':
        task, why = next_task(tasks)
        if not task:
            print(why)
            return 0
        print(f'{task.id} [{task.state}] — {why}\n')
        print(show(task))
        return 0
    if command == 'show' and len(argv) > 2:
        found = [t for t in tasks if t.id == argv[2]]
        if not found:
            print('tâche inconnue')
            return 1
        print(show(found[0]))
        return 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main(sys.argv))
