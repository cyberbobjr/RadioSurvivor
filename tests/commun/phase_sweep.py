"""Balayage des phases de l'horloge de jeu (E19-T05, ADR banc mimétique D04).

Rejoue un scénario de banc plusieurs fois, chaque fois sur un harnais neuf dont l'horloge de départ est décalée, pour
qu'un changement d'heure (EveryHours), un changement de jour (EveryDays), l'entrée dans la nuit et l'aube tombent à
des instants différents de la scène. Axe facultatif : le monde autour de la scène (vide, ou déjà peuplé d'un groupe
Living Knox incarné). Un défaut qui dépend du moment où l'heure change échoue alors sur au moins une phase, sans
crochet écrit pour lui (suite lk.meals du 2026-11-13 : pas horaire des besoins entre la faim posée et la première
décision, attrapé par POPULATED).

Utilisation, dans un unittest.TestCase dont setUp construit self.h (Harness) et le décor :

    from phase_sweep import POPULATED, WORLDS, sweep
    def test_suite_under_the_phase_sweep(self):
        sweep(self, lambda phase: self.check(self.run_suite(start=None)), worlds=WORLDS)

- Chaque rejeu part d'un harnais neuf : le premier utilise celui du setUp, les suivants appellent tearDown puis
  setUp ; le tearDown de unittest ferme le dernier.
- L'horloge est placée (Harness.jump_to, en avant, sans événement : partie chargée à cette heure), puis le monde est
  préparé (temps réel seulement, l'heure de jeu ne bouge pas), puis le scénario est appelé ; il ne doit pas replacer
  l'horloge. case.sweep_world est le monde du rejeu en cours (other_groups(case) : groupes laissés par le monde).
- Chaque rejeu tourne dans un subTest(phase=<nom>) : « hour-3 » dans le monde vide, « populated/hour-3 » sinon ; un
  échec nomme la phase et le monde qui l'ont produit, les autres rejeux sont joués quand même.
- phases : DEFAULT_PHASES (10) par défaut, PHASES_SHORT pour les scènes coûteuses ; worlds : (EMPTY,) par défaut,
  WORLDS = (EMPTY, POPULATED) pour une scène Living Knox.
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
    Phase('hour-4', 9, 56),
    Phase('hour-5', 9, 55),
    Phase('hour-10', 9, 50),
    Phase('hour-30', 9, 30),
    Phase('night-5', 21, 55),
    Phase('midnight-5', 23, 55),
    Phase('dawn-5', 6, 55),
)

PHASES_SHORT = tuple(p for p in DEFAULT_PHASES if p.name in ('hour-1', 'hour-5', 'midnight-5'))


@dataclass(frozen=True)
class EmptyWorld:
    """Monde vide : la scène seule (bancs RS et toute scène sans Living Knox)."""
    name: str = 'empty'
    groups: int = 0

    def prepare(self, case):
        return None


# Groupe voisin créé par les vrais modules (LK_Groups), incarné par LK_Bodies près du joueur, puis évalué par la
# cascade de LK_Decisions : rien n'est écrit à la main dans l'état des décisions.
_POPULATE = '''
local G = LivingKnox.Groups
local g = assert(G.create({{ type = "{type}", name = "Sweep neighbours", day = G.today(),
    home = {{ x = {x}, y = {y}, z = {z} }} }}))
for _ = 1, {members} do assert(G.addMember(g.id, {{ role = "worker", day = G.today() }})) end
assert(G.setLeader(g.id, "m-1", G.today()))
return g.id
'''

_READY = '''
local g = LivingKnox.Groups.get("{gid}")
local bodies, decided = 0, 0
for _, m in pairs(g and g.members or {{}}) do
    if m.npc ~= nil and LivingKnox.Bodies.find(m.npc) ~= nil then bodies = bodies + 1 end
    if m.npc ~= nil and LivingKnox.Decisions.get(m.npc) ~= nil then decided = decided + 1 end
end
return bodies == {members} and decided == {members}
'''


@dataclass(frozen=True)
class PopulatedWorld:
    """Monde déjà peuplé, comme une campagne : un groupe Living Knox voisin incarné et déjà évalué par la cascade.

    Liste des membres incarnés de LK_Decisions alors non vide : elle n'est refaite que toutes les ROSTER_MS (5 s) et
    les membres sont pris tour à tour, MEMBERS_PER_PASS par passage, un par image (LK_Decisions.lua:137-140,
    2019-2048) ; un membre incarné ensuite attend sa première décision jusqu'à ROSTER_MS, comme en jeu. Monde vide :
    liste refaite à chaque passage, première décision presque immédiate.

    Foyer à 40 cases de la scène (110, 110) : hors de la maison de la scène, dans le rayon d'incarnation
    (Config.MATERIALIZE.RADIUS 80) et en deçà du retrait (BODIES.RELEASE_RADIUS 120). Le joueur passe près du foyer
    pour l'incarner ; la scène le replace."""
    name: str = 'populated'
    groups: int = 1
    home: tuple = (150, 110, 0)
    members: int = 3
    type: str = 'settlers'
    max_ticks: int = 1200

    def prepare(self, case):
        h = case.h
        srv = h.server.name
        x, y, z = self.home
        gid = h.load(srv, _POPULATE.format(type=self.type, x=x, y=y, z=z, members=self.members))
        for player in h.clients:
            h.move_player(player, x, y, z)
        ready = _READY.format(gid=gid, members=self.members)
        for _ in range(self.max_ticks):
            h.tick()
            if len(h.machines) > 1:
                h.pump()
            h.advance_ms(100)
            if h.load(srv, ready):
                return gid
        raise AssertionError(f'populated world: group {gid} not embodied and decided after {self.max_ticks} frames')


EMPTY = EmptyWorld()
POPULATED = PopulatedWorld()
WORLDS = (EMPTY, POPULATED)


def other_groups(case):
    """Groupes Living Knox laissés par le monde du rejeu en cours (0 hors balayage)."""
    world = getattr(case, 'sweep_world', None)
    return world.groups if world is not None else 0


def sweep(case, scenario, phases=DEFAULT_PHASES, worlds=(EMPTY,)):
    """Joue scenario(phase) pour chaque monde et chaque phase, sur un harnais neuf placé à l'heure de la phase puis
    peuplé. Rend la liste des noms joués."""
    played = []
    for w, world in enumerate(worlds):
        for i, phase in enumerate(phases):
            if w or i:
                case.tearDown()
                case.setUp()
            name = phase.name if world.name == EMPTY.name else f'{world.name}/{phase.name}'
            with case.subTest(phase=name):
                case.sweep_world = world
                case.h.jump_to(phase.hour, phase.minute)
                world.prepare(case)
                scenario(phase)
            played.append(name)
    case.sweep_world = None
    return played
