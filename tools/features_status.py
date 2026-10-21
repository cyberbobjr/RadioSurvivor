"""Recalcule les colonnes « Solo » et « MP » des tableaux de docs/annexes/maquettes/fonctionnalites.html depuis le plan (docs/annexes/plans).

Chaque ligne de tableau porte ses étapes dans <span class="step">E00, E03</span>. Pour l'ensemble de ces étapes
(tâches abandonnées exclues) :
    Solo : tâches de cible `solo` ou `MP` jouées en solo (état `testé solo` ou `testé MP`) ; les tâches de cible
           `hors jeu` comptent comme faites quand leur case est cochée.
        - « Fait » : toutes faites ;
        - « Validé en jeu » : au moins une jouée, pas toutes ;
        - « Testé hors jeu » : aucune jouée, plus rien à faire ou à décider ;
        - « En cours » : sinon.
        Sous la puce : « k/n jouées » (tâches de cible solo ou MP).
    MP : tâches de cible `MP` à l'état `testé MP`, c'est-à-dire passées par la campagne MP automatique (serveur
         dédié + 2 clients pilotés ; règle « les tests font foi » du 2026-10-14).
        - « Fait » : toutes en `testé MP` ; « En cours » : une partie ; « À tester » : aucune ; « — » : aucune
          tâche MP.
        Sous la puce : « j/m ».
Une ligne peut aussi viser une tâche (« LK13-T04 ») ou exclure des tâches d'une étape (« LK13 sauf T04 T05 »).
La ligne sans étape de plan (prototype) reçoit seulement une cellule MP « — » si elle n'en a pas.

Usage : python tools/features_status.py [--check]   (--check : n'écrit rien, code 1 si la page n'est pas à jour)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "docs" / "annexes" / "maquettes" / "fonctionnalites.html"
PLAN = ROOT / "docs" / "annexes" / "plans"

TASK = re.compile(r"^- \[([ x])\] \*\*(([A-Z]+[0-9]+)-T[0-9]+)\*\*(.*?)(?=^- \[[ x]\] \*\*|^#|\Z)", re.S | re.M)
ROW = re.compile(r'(<tr><td>[^<]*<br><span class="step">)([^<]+)(</span></td><td>(?:(?!</td>).)*</td>)(.*?)(</tr>)',
                 re.S)
HEAD_OLD = "<th>Ce qu'elle apporte au joueur</th><th>État</th></tr>"
HEAD_NEW = "<th>Ce qu'elle apporte au joueur</th><th>Solo</th><th>MP</th></tr>"
PLAYED = ("testé solo", "testé MP")
OPEN = ("à faire", "à décider", "en cours", "bloqué", "codé")


def stages():
    out = {}
    # Step files only (E00-…, LK00-…), as plan.py: drafts such as proposition-*.md hold copies of tasks.
    for p in PLAN.glob("*.md"):
        if not re.match(r"[A-Z]+[0-9]+-", p.name):
            continue
        for m in TASK.finditer(p.read_text(encoding="utf-8")):
            body = m.group(4)
            state = re.search(r"État : `([^`]*)`", body).group(1)
            if state == "abandonné":
                continue
            target = re.search(r"Cible : `([^`]*)`", body).group(1)
            out.setdefault(m.group(3), []).append((m.group(1) == "x", state, target, m.group(2)))
    return out


def select(st, spec):
    """Tasks of a row. spec: comma-separated items, each a step (« LK13 »), a step with exclusions
    (« LK13 sauf T04 T05 ») or one task (« LK13-T04 »). None when an item is not in the plan (row out of the plan)."""
    tasks = []
    for item in (s.strip() for s in spec.split(",")):
        one = re.fullmatch(r"([A-Z]+[0-9]+)-(T[0-9]+)", item)
        if one:
            found = [t for t in st.get(one.group(1), []) if t[3] == item]
            if not found:
                return None
            tasks += found
            continue
        step, _, rest = item.partition(" sauf ")
        if step not in st:
            return None
        skip = {step + "-" + x for x in rest.split()}
        tasks += [t for t in st[step] if t[3] not in skip]
    return tasks


def chip(kind, label, sub):
    return f'<span class="chip {kind}">{label}</span><br><span class="step">{sub}</span>'


def solo_cell(tasks):
    ingame = [t for t in tasks if t[2] in ("solo", "MP")]
    played = sum(1 for t in ingame if t[1] in PLAYED)
    offline_done = all(t[0] for t in tasks if t[2] == "hors jeu")
    sub = f"{played}/{len(ingame)} jouées" if ingame else "hors jeu seulement"
    if offline_done and played == len(ingame):
        return chip("ok", "Fait", sub)
    if played:
        return chip("open", "Validé en jeu", sub)
    if not any(t[1] in OPEN for t in tasks):
        return chip("open", "Testé hors jeu", sub)
    return chip("later", "En cours", sub)


def mp_cell(tasks):
    mp = [t for t in tasks if t[2] == "MP"]
    if not mp:
        return "—"
    done = sum(1 for t in mp if t[1] == "testé MP")
    sub = f"{done}/{len(mp)}"
    if done == len(mp):
        return chip("ok", "Fait", sub)
    if done:
        return chip("open", "En cours", sub)
    return chip("later", "À tester", sub)


def main():
    st = stages()
    page = PAGE.read_text(encoding="utf-8")
    new = page.replace(HEAD_OLD, HEAD_NEW)

    def sub(m):
        tasks = select(st, m.group(2))
        if tasks is None:
            cells = m.group(4)
            if cells.count("<td>") == 1:   # ligne hors plan (prototype) : cellule MP ajoutée
                cells += "<td>—</td>"
            return m.group(1) + m.group(2) + m.group(3) + cells + m.group(5)
        return (m.group(1) + m.group(2) + m.group(3) + "<td>" + solo_cell(tasks) + "</td><td>" + mp_cell(tasks)
                + "</td>" + m.group(5))

    new = ROW.sub(sub, new)
    if "--check" in sys.argv:
        sys.exit(0 if new == page else 1)
    if new != page:
        PAGE.write_text(new, encoding="utf-8", newline="\n")
    print("features status: " + ("updated" if new != page else "already up to date"))


if __name__ == "__main__":
    main()
