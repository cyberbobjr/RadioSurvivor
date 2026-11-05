"""Suivi du plan d'implémentation RadioSurvivor.

    python RadioSurvivor/tools/plan.py check    # contrôle les fichiers d'étape (CI locale)
    python RadioSurvivor/tools/plan.py suivi    # tableau de bord en tête de chaque plan, plans terminés rangés,
                                                # docs/annexes/plans/SUIVI.md régénéré
    python RadioSurvivor/tools/plan.py next     # prochaine tâche à traiter (ordre de travail du README du plan)
    python RadioSurvivor/tools/plan.py show E01-T02

Les fichiers d'étape (<préfixe><NN>-*.md : préfixe E pour la radio et le carnet, LK pour le moteur de PNJ Living Knox)
sont la seule source des états. Une étape en cours vit dans docs/annexes/plans/ ; une étape terminée (toutes ses tâches
à leur cible, ou abandonnées) est rangée par `suivi` dans docs/annexes/plans-termines/, et y revient si une tâche se
rouvre ; les liens qui la visent sont corrigés dans tout le dépôt. Le tableau de bord en tête de chaque plan et
SUIVI.md sont des vues générées.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'docs' / 'annexes' / 'plans'
DONE = ROOT / 'docs' / 'annexes' / 'plans-termines'
SUIVI = PLAN / 'SUIVI.md'
README = PLAN / 'README.md'

# Rang de progression. "à décider" bloque tant que l'utilisateur n'a pas tranché.
RANK = {'à décider': 0, 'à faire': 0, 'en cours': 1, 'codé': 2, 'testé hors jeu': 3, 'testé solo': 4, 'testé MP': 5}
SPECIAL = {'bloqué', 'abandonné'}
TARGET = {'hors jeu': 3, 'solo': 4, 'MP': 5}
CLOSED_STEPS = {'terminée', 'vide'}   # rangées dans plans-termines/

TASK = re.compile(r'^- \[( |x)\] \*\*([A-Z]{1,3}\d{2}-T\d{2})\*\* — (.+?)\s*$')
FIELD = re.compile(r'^  - ([^:]+?) : (.*)$')
STEP = re.compile(r'^# ([A-Z]{1,3}\d{2}) — (.+?)\s*$')
STEP_FILE = re.compile(r'[A-Z]{1,3}\d{2}-.*\.md$')
COMMIT = re.compile(r'`([0-9a-f]{7,40})`')
ORDER_LINE = re.compile(r'\*\*Ordre de travail\*\*[^`]*`([^`]+)`')

BOARD_START = '<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->'
BOARD_END = '<!-- fin du tableau de bord -->'

# Fichiers texte dont les liens et chemins vers un plan déplacé sont corrigés.
TEXT_SUFFIXES = {'.md', '.lua', '.py', '.ps1', '.txt'}
SKIP_DIRS = {'.git', 'runs', 'node_modules', '__pycache__', '.venv'}
LINK = re.compile(r'\]\(([^)\s]+)\)')


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


def step_files():
    out = []
    for folder in (PLAN, DONE):
        if folder.is_dir():
            out += [p for p in folder.glob('*.md') if STEP_FILE.match(p.name)]
    return sorted(out, key=lambda p: p.name)


def load():
    steps, tasks = [], []
    for path in step_files():
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
    names = {}
    for _, _, path in steps:
        if path.name in names:
            errors.append(f'{path.name}: présent dans plans/ et dans plans-termines/')
        names[path.name] = path
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
    try:
        order_tokens()
    except ValueError as e:
        errors.append(str(e))
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


# ---------------------------------------------------------------- ordre de travail

def order_tokens():
    """Jetons de l'« Ordre de travail » du README du plan : identifiant de tâche, d'étape, ou famille (E, LK)."""
    if not README.is_file():
        return []
    m = ORDER_LINE.search(README.read_text(encoding='utf-8'))
    if not m:
        return []
    tokens = m.group(1).split()
    for tok in tokens:
        if not re.fullmatch(r'[A-Z]{1,3}(\d{2}(-T\d{2})?)?', tok):
            raise ValueError(f'README.md : jeton « {tok} » inconnu dans l\'ordre de travail (tâche, étape ou famille)')
    return tokens


def family(step):
    return re.match(r'[A-Z]+', step).group(0)


def ordered(tasks, tokens=None):
    """Tâches dans l'ordre de travail : chaque jeton prend, dans l'ordre du plan, les tâches non encore prises qu'il
    désigne ; une famille ne prend pas les étapes nommées ailleurs dans l'ordre ; le reste suit dans l'ordre du plan."""
    tokens = order_tokens() if tokens is None else tokens
    named_steps = {tok for tok in tokens if re.fullmatch(r'[A-Z]{1,3}\d{2}', tok)}
    taken, out = set(), []
    for tok in tokens:
        for t in tasks:
            if t.id in taken:
                continue
            if tok == t.id or tok == t.step or (tok == family(t.step) and t.step not in named_steps
                                                   and re.fullmatch(r'[A-Z]{1,3}', tok)):
                taken.add(t.id)
                out.append(t)
    out += [t for t in tasks if t.id not in taken]
    return out


# ---------------------------------------------------------------- tableau de bord dans chaque plan

def board(step_tasks):
    live = [t for t in step_tasks if t.state != 'abandonné']
    done = sum(1 for t in live if t.done())
    dropped = len(step_tasks) - len(live)
    head = f'**Avancement.** {step_state(step_tasks)} — {done} / {len(live)} tâche(s) terminée(s)'
    if dropped:
        head += f', {dropped} abandonnée(s)'
    lines = [BOARD_START, '', head + '.', '', '| | Tâche | Titre | État | Cible | Dépend de |', '|---|---|---|---|---|---|']
    for t in step_tasks:
        box = '☑' if t.done() else ('✕' if t.state == 'abandonné' else '☐')
        deps = ', '.join(t.deps) if t.deps else '—'
        lines.append(f'| {box} | {t.id} | {t.title} | `{t.state}` | {t.target} | {deps} |')
    lines += ['', BOARD_END]
    return lines


def write_board(path, step_tasks):
    """Écrit (ou remplace) le tableau de bord juste sous le titre du plan ; rend vrai si le fichier a changé."""
    with open(path, encoding='utf-8', newline='') as f:
        before = f.read()
    nl = '\r\n' if '\r\n' in before else '\n'
    lines = before.replace('\r\n', '\n').split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    if BOARD_START in lines:
        a = lines.index(BOARD_START)
        b = lines.index(BOARD_END, a)
        del lines[a:b + 1]
        if a < len(lines) and lines[a].strip() == '':
            del lines[a]
    block = board(step_tasks)
    if len(lines) > 1 and lines[1].strip() == '':
        lines[2:2] = block + ['']
    else:
        lines[1:1] = [''] + block + ['']
    text = nl.join(lines) + nl
    if text != before:
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return True
    return False


# ---------------------------------------------------------------- rangement des plans terminés

def text_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            p = Path(dirpath) / name
            if p.suffix in TEXT_SUFFIXES:
                yield p


def rel(target, start):
    return Path(os.path.relpath(target, start)).as_posix()


def fix_links(moves):
    """moves : {ancien chemin résolu: nouveau}. Corrige les liens Markdown (recalculés depuis l'emplacement actuel du
    fichier qui les porte) et les chemins écrits en clair « plans/<nom> » / « plans-termines/<nom> »."""
    if not moves:
        return []
    back = {new: old for old, new in moves.items()}
    changed = []
    for path in text_files():
        try:
            with open(path, encoding='utf-8', newline='') as f:
                text = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        here = path.resolve()
        old_dir, new_dir = back.get(here, here).parent, here.parent
        out = text
        if path.suffix == '.md':
            def repl(m):
                target = m.group(1)
                if re.match(r'[a-z]+:', target) or target.startswith(('#', '/')):
                    return m.group(0)
                base, sep, anchor = target.partition('#')
                if not base:
                    return m.group(0)
                was = (old_dir / base).resolve()
                now = moves.get(was, was)
                if now == was and old_dir == new_dir:
                    return m.group(0)
                return '](' + rel(now, new_dir) + sep + anchor + ')'
            out = LINK.sub(repl, out)
        for new in moves.values():
            folder = new.parent.name
            other = 'plans' if folder == DONE.name else DONE.name
            out = re.sub(r'(?<![\w-])' + re.escape(other + '/' + new.name), folder + '/' + new.name, out)
        if out != text:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(out)
            changed.append(path)
    return changed


def move(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    tracked = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '--error-unmatch', str(src)],
                             capture_output=True).returncode == 0
    if tracked:
        subprocess.run(['git', '-C', str(ROOT), 'mv', str(src), str(dst)], check=True, capture_output=True)
    else:
        src.rename(dst)


def archive(steps, tasks):
    moves = {}
    for step, _, path in steps:
        state = step_state([t for t in tasks if t.step == step])
        want = DONE if state in CLOSED_STEPS else PLAN
        if path.parent.resolve() != want.resolve():
            dst = want / path.name
            moves[path.resolve()] = dst.resolve()
            move(path, dst)
    return moves


# ---------------------------------------------------------------- SUIVI.md

def suivi_text(steps, tasks):
    out = ['# Suivi du plan RadioSurvivor', '',
           '> Fichier **généré** par `python RadioSurvivor/tools/plan.py suivi` à partir des fichiers d\'étape.',
           '> Ne pas le modifier à la main : changer l\'état dans le fichier de l\'étape puis régénérer.',
           '> Étapes en cours : `docs/annexes/plans/` ; étapes terminées : `docs/annexes/plans-termines/`.', '']
    first = [t for t in ordered(tasks) if not t.done() and t.state not in SPECIAL][:12]
    if first:
        out += ['## Ordre de travail', '', '| # | Tâche | Titre | État |', '|---|---|---|---|']
        for i, t in enumerate(first, 1):
            out.append(f'| {i} | [{t.id}]({rel(t.path, PLAN)}#L{t.line}) | {t.title} | `{t.state}` |')
        out.append('')
    out += ['## Étapes', '', '| Étape | Titre | État | Tâches terminées |', '|---|---|---|---|']
    for step, title, path in steps:
        st = [t for t in tasks if t.step == step]
        done = sum(1 for t in st if t.done())
        out.append(f'| [{step}]({rel(path, PLAN)}) | {title} | {step_state(st)} | {done} / {len(st)} |')
    out += ['', '## Tâches', '', '| | Tâche | Titre | État | Cible | Preuve |', '|---|---|---|---|---|---|']
    for t in tasks:
        box = '☑' if t.done() else '☐'
        out.append(f'| {box} | [{t.id}]({rel(t.path, PLAN)}#L{t.line}) | {t.title} | `{t.state}` | {t.target} | {t.proof} |')
    return '\n'.join(out) + '\n'


def suivi(steps, tasks):
    moves = archive(steps, tasks)
    fix_links(moves)
    steps, tasks = load()
    for step, _, path in steps:
        write_board(path, [t for t in tasks if t.step == step])
    steps, tasks = load()   # numéros de ligne après les tableaux de bord
    SUIVI.write_text(suivi_text(steps, tasks), encoding='utf-8', newline='\n')
    return SUIVI, moves


def next_task(tasks):
    by_id = {t.id: t for t in tasks}
    for t in tasks:
        if t.state == 'en cours':
            return t, 'reprendre la tâche en cours'
    for t in ordered(tasks):
        if t.done() or t.state in SPECIAL or RANK.get(t.state, 0) >= RANK['testé hors jeu']:
            continue
        if all(by_id[d].usable() for d in t.deps if d in by_id):  # dépendances externes : à vérifier à la main
            if t.state == 'à décider':
                return t, 'DÉCISION REQUISE : poser les questions de la tâche à l\'utilisateur, ne rien coder'
            return t, 'à traiter'
    pending = [t for t in ordered(tasks) if not t.done() and t.state not in SPECIAL]
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
        path, moves = suivi(steps, tasks)
        for old, new in moves.items():
            print('rangé', Path(old).name, '->', rel(new, ROOT))
        print('écrit', path)
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
