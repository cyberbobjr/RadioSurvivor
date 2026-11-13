"""Balayage des phases de l'horloge de jeu (E19-T05, ADR banc mimétique D04).

Rejoue un scénario de banc plusieurs fois, chaque fois sur un harnais neuf dont l'horloge de départ est décalée, pour
qu'un changement d'heure (EveryHours), un changement de jour (EveryDays), l'entrée dans la nuit et l'aube tombent à
des instants différents de la scène. Un défaut qui dépend du moment où l'heure change (suite lk.meals du
2026-11-13 : pas horaire des besoins entre la faim posée et la première décision) échoue alors sur au moins une
phase, sans crochet écrit pour lui.

Utilisation, dans un unittest.TestCase dont setUp construit self.h (Harness) et le décor :

    from phase_sweep import sweep
    def test_suite_under_the_phase_sweep(self):
        sweep(self, lambda phase: self.check(self.run_suite(start=None)))

- Chaque phase part d'un harnais neuf : la première utilise celui du setUp, les suivantes appellent tearDown puis
  setUp ; le tearDown de unittest ferme le dernier.
- L'horloge est placée (Harness.jump_to, en avant, sans événement : partie chargée à cette heure) avant l'appel du
  scénario ; le scénario ne doit pas la replacer.
- Chaque phase tourne dans un subTest(phase=<nom>) : un échec nomme la phase qui l'a produit, les autres phases
  sont jouées quand même.
- phases : liste de Phase, DEFAULT_PHASES par défaut (9 rejeux) ; PHASES_SHORT pour les scènes coûteuses.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Phase:
    """Heure de jeu de départ de la scène (heure du jour, minute) et son nom dans les rapports d'échec."""
    name: str
    hour: int
    minute: int


# Départ à 10 h moins k minutes (changement d'heure k minutes après le départ, k dense au début : les fenêtres
# fragiles d'une scène sont courtes), puis juste avant la nuit des PNJ (22 h, Config.SIMULATION.NIGHT_START), avant
# minuit (EveryDays, GameTime.java:532-534, 593) et avant 7 h (getNightsSurvived + 1, GameTime.java:515-516).
DEFAULT_PHASES = (
    Phase('hour-1', 9, 59),
    Phase('hour-2', 9, 58),
    Phase('hour-3', 9, 57),
    Phase('hour-5', 9, 55),
    Phase('hour-10', 9, 50),
    Phase('hour-30', 9, 30),
    Phase('night-5', 21, 55),
    Phase('midnight-5', 23, 55),
    Phase('dawn-5', 6, 55),
)

PHASES_SHORT = (DEFAULT_PHASES[0], DEFAULT_PHASES[3], DEFAULT_PHASES[7])


def sweep(case, scenario, phases=DEFAULT_PHASES):
    """Joue scenario(phase) pour chaque phase, sur un harnais neuf placé à l'heure de la phase. Rend la liste des
    noms joués."""
    played = []
    for i, phase in enumerate(phases):
        if i:
            case.tearDown()
            case.setUp()
        with case.subTest(phase=phase.name):
            case.h.jump_to(phase.hour, phase.minute)
            scenario(phase)
        played.append(phase.name)
    return played
